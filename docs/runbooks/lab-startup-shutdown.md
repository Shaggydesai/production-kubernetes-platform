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

## After an unclean shutdown or a control-plane outage

Do this in addition to the staged startup above, not instead of it. Three
separate components have come back from an outage `Ready` and not working, and
each stayed broken until someone looked for it by hand — once for three days.
`Ready` is a liveness claim, not a correctness one.

**1. Read what is firing, before anything else.**

```bash
kubectl -n monitoring exec sts/prometheus-kube-prometheus-stack-prometheus -c prometheus -- \
  sh -c 'wget -qO- "http://localhost:9090/api/v1/query?query=ALERTS{alertstate=\"firing\"}"' | head -c 800
```

`Watchdog` is expected. Anything else is a real answer to "what did the outage
break", and it is cheaper to read than to rediscover. On 2026-09-29 a critical
alert had been firing for 23 hours and was found by accident.

**2. Restart the components that hold caches.**

```bash
kubectl -n velero rollout restart daemonset/node-agent
```

Velero's node agent caches pods per node. If that cache is broken it still
reports `1/1 Running` and fails every volume backup instantly with
`Pod "<name>" not found`. It cost three days of application-data backups on
2026-09-27 to 29. Restarting the Velero *server* does not fix it; the agent does.

**3. Check for containers that outlived containerd's records.**

```bash
sudo crictl pods -q | sort > /tmp/sandboxes.txt
ps -C containerd-shim-runc-v2 -o args= \
  | sed -n 's/.*-id \([0-9a-f]\{64\}\).*/\1/p' | sort > /tmp/shims.txt
wc -l /tmp/sandboxes.txt /tmp/shims.txt
comm -13 /tmp/sandboxes.txt /tmp/shims.txt | wc -l
```

Must be 0. Discarding `/var/lib/containerd` does **not** stop the containers it
was running, and the survivors are invisible to `crictl`, `kubectl` and the
kubelet. On 2026-09-28 ten survived, one of them a second `kube-proxy`
programming iptables. Kill the shim, not the container — the shim owns the
lifecycle.

**4. Run the metric-writing timers once, so their files are known-good.**

```bash
sudo systemctl start etcd-defrag.service etcd-pull-observe.service
cat /var/lib/node_exporter/textfile_collector/*.prom | grep -vE '^#' | grep -E '[a-z_]+ *$' \
  && echo "!! a metric above has no value - node-exporter will refuse the whole file" \
  || echo "all textfile metrics have values"
```

A metric line with a name and no value is invalid and breaks the collector. It
happened when the defrag script queried a dead etcd and wrote the empty result
out anyway.

**5. Confirm the last volume backup actually moved bytes.**

```bash
kubectl -n velero get podvolumebackups \
  -o custom-columns=POD:.spec.pod.name,VOL:.spec.volume,PHASE:.status.phase,BYTES:.status.progress.bytesDone \
  --sort-by=.metadata.creationTimestamp | tail -8
```

A `Completed` Backup object is not evidence that volume data was captured — a
backup whose every PodVolumeBackup failed reports `PartiallyFailed`, which reads
like a minor problem and is not.

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
