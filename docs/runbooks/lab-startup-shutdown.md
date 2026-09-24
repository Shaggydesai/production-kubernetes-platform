# Runbook: starting and stopping the lab

The cluster runs as three VMware Workstation VMs on one laptop. Booting them
together overloads the host and causes a cascade: etcd slows down, the API
server's probes time out, the scheduler loses its lease, nodes go NotReady,
and pods get evicted faster than they can start.

**Observed on 24 Sep 2026:** an unclean host shutdown, then all three VMs
starting at once → load average 78 on `k8s-cp01`, 129 MB free RAM, etcd
"apply request took too long" at 460 ms, `kube-scheduler` in CrashLoopBackOff
with `Leaderelection lost`. Recovery took about 90 minutes.

---

## Shutting down (always do this before closing the laptop)

```bash
ssh k8s-worker01 'sudo shutdown -h now'
ssh k8s-worker02 'sudo shutdown -h now'
# wait until both VMs are powered off in VMware
sudo shutdown -h now      # on k8s-cp01, last
```

Never suspend the host with the VMs running, and never power the VMs off from
VMware while they're running. The etcd corruption of 18 Sep is believed to have
started this way.

## Starting up (staged, about 20 minutes)

1. **`k8s-cp01` only.** Wait until load average is under 4 and
   `kube-apiserver`, `kube-scheduler` and `kube-controller-manager` have gone
   5 minutes with no new restarts:
```bash
   watch -n 30 'uptime; kubectl get pods -n kube-system | head -12'
```
2. **`k8s-worker01`.** Wait for `Ready`, then 5–10 minutes of calm.
3. **`k8s-worker02`.** Same again. Expect a load spike to 20–60 while Longhorn
   reattaches volumes; it settles within ~10 minutes. **Don't run kubectl in a
   loop during the spike — it adds to the queue.**
4. **Unseal Vault** (3 of 5 keys) once `vault-0` is Running and stable:
```bash
   kubectl exec -it vault-0 -n vault -- vault operator unseal   # ×3
```
5. **Check External Secrets.** If the store says
   `Ready=False: unable to create client`, its Vault client got stuck while the
   API server was down:
```bash
   kubectl -n external-secrets rollout restart deployment external-secrets
   # then force-sync each ExternalSecret
```
6. **Restart anything that crash-looped** while its dependencies were down
   (typically `taskflow-api` waiting on Postgres).
7. **Take a backup** once healthy: `velero backup create --from-schedule velero-daily-data --wait`

## When the host is short on memory

Pause the monitoring stack; it's the heaviest part and the least critical:

```bash
kubectl -n argocd patch application platform-kube-prometheus-stack --type=merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
kubectl -n argocd patch application platform-loki-stack --type=merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
kubectl -n monitoring patch prometheus kube-prometheus-stack-prometheus --type=merge -p '{"spec":{"replicas":0}}'
kubectl -n monitoring scale deployment kube-prometheus-stack-grafana --replicas=0
kubectl -n monitoring scale statefulset loki-stack --replicas=0
```

Turning Argo CD's auto-sync off first is essential, otherwise it undoes the
scale-down. Reverse the steps to bring it back, one component at a time, and
re-enable auto-sync at the end.

---

## Known problems and their fixes

### VMware e1000 "Detected Tx Unit Hang"

A node disappears from the network entirely (no ping, no SSH, kubelet gone)
while the VM is still running. The console shows:

e1000 0000:02:01.0 ens33: Detected Tx Unit Hang


The emulated NIC's transmit ring hangs under load. Seen on `k8s-worker01`
twice on 24 Sep 2026, and the likely trigger of the 18 Sep incident.

- **Recover:** power off the VM in VMware and power it on again.
- **Mitigation (applied):** offloads disabled via the `node_tuning` Ansible
  role (`nic-offload-off.service`).
- **Durable fix (not done):** change the adapter to `vmxnet3` in the VM's
  `.vmx` (`ethernet0.virtualDev = "vmxnet3"`). Be at the console: the
  interface name may change from `ens33`, which breaks netplan until fixed.

### Longhorn volumes "faulted" after a hard power-off

Longhorn refuses to attach when it trusts none of the replicas.

- First check the node holding the replicas is actually up:
  `kubectl -n longhorn-system get replicas.longhorn.io -o custom-columns='NAME:.metadata.name,VOL:.spec.volumeName,NODE:.spec.nodeID,FAILEDAT:.spec.failedAt,HEALTHYAT:.spec.healthyAt'`
- Auto-salvage is enabled and recovers the volumes on its own **once that node
  returns**. On 24 Sep all four recovered with no manual salvage.
- `spec.salvageRequested` does **not** exist in this Longhorn version.

### Pods stuck Terminating, replacements stuck ContainerCreating

`Multi-Attach error ... Volume is already used by pod(s) <old pod>`. The old
pod still holds the ReadWriteOnce volume. Force-delete it **only** when its
node was power-cycled, so nothing is still writing:

```bash
kubectl -n <ns> delete pod <name> --grace-period=0 --force
```

### inotify exhaustion

`Failed to allocate directory watch: Too many open files`. Fixed by the
`node_tuning` role (`fs.inotify.max_user_instances = 1024`).
