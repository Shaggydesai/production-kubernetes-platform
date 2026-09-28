# Incident: two bbolt databases corrupted by an unclean host reset

**Date:** 2026-09-27 to 2026-09-28
**Duration:** 26-09 18:18 UTC (host down) to 28-09 07:15 UTC (all applications healthy) — ~37h, of which ~6h active recovery across two days
**Data loss:** none
**Author:** Sagar
**Status:** resolved; root cause is the hypervisor/host combination and is accepted only until the hardware migration

Times are UTC. The host clock is IST (UTC+5:30); host event times are given in both.

## 1. Summary

The laptop hosting all three cluster VMs was reset abruptly twice — once by an
unplanned shutdown on 26-09, once by a Windows Update auto-reboot on 28-09 with
all three guests running. Each reset corrupted a **bbolt** database on cp01:
etcd's on both occasions, and containerd's own metadata store on the second.

bbolt is explicitly engineered to survive power loss. Two independent programs
using it were damaged by the same event, on drives that report perfect SMART
health. The fault is therefore not in either program and not in the media: the
storage stack beneath them acknowledged writes that never reached stable storage.

Recovery required restoring etcd from an off-cluster backup **twice**, discarding
containerd's metadata store, and then unpicking nine layers of dependent failure.
No data was lost — the six application rows survived both events because they
live in Longhorn replicas on the workers, not in etcd.

Two further failures were found during recovery, neither caused by this incident:
an orphaned container had been silently disabling backup metrics for six days,
and the off-site backup copy had stopped two days earlier without alerting.

## 2. Timeline

| Time (UTC) | Event |
|---|---|
| 26-09 11:20 | A `VolumeAttachment` for the Loki PVC enters deletion and wedges on its `external-attacher` finalizer. Unnoticed; later restored from backup and blocks Loki for two days. |
| 26-09 12:03 | Scheduled etcd backup succeeds. Revision 1,403,336; 2,653 keys. **This is the last archive to reach the off-site drive.** |
| 26-09 ~13:00 | Last successful off-site pull to D:. The pull stops here and does not run again. Not detected. |
| 26-09 18:18 | Last etcd WAL write. Host goes down uncleanly. |
| 27-09 11:31 | cp01 booted. `kubectl` fails: `connection refused` on 6443. |
| 27-09 11:34 | etcd found in CrashLoopBackOff, attempt 25; apiserver attempt 45. |
| 27-09 ~11:40 | **Corruption 1 identified.** etcd panics on startup: `consistent-index: 0` against `snapshot-index: 1210129`, then `failed to find [SNAPSHOT-INDEX].snap.db`. |
| 27-09 17:14 | etcd restored from `etcd-k8s-cp01-20260926-120327` into a fresh data directory. Starts first time, attempt 1. |
| 27-09 17:48 | Vault unsealed. Longhorn, CSI and ExternalSecrets recovered in order. |
| 27-09 ~18:00 | Cluster healthy. Six rows confirmed present. |
| 28-09 04:37 | **Third e1000 `Detected Tx Unit Hang`** on cp01, flooding the console; SSH unreachable. `nic-offload-off.service` was enabled and active, all offloads confirmed `off`. Cleared by bouncing the link. |
| 28-09 ~04:46 (10:16 IST) | **Windows restarts itself** with all three guests running. Second unclean reset. |
| 28-09 04:52 | Guests boot. etcd starts cleanly at attempt 1 — the restored database survives a genuine cold boot. |
| 28-09 05:02:41 | **Corruption 2.** etcd exits code 2 during scheduled MVCC compaction of revisions 1,425,299–1,439,321: `assertion failed: Page expected to be: 8688, but self identifies as 3846692236623885411`. |
| 28-09 05:10 | `etcdutl defrag` panics on the same page. The database is unrecoverable by tooling. |
| 28-09 05:15 | etcd restored a second time from the same 26-09 archive. |
| 28-09 05:24:46 | **Corruption 3.** containerd 2.2.1 panics: `page 367 already freed` in its own bbolt metadata store, during `Tx.Commit`. `NRestarts=77`. Also a snapshotter collision: `rename ... snapshots/4668: file exists`. |
| 28-09 ~05:30 | `/var/lib/containerd` moved aside; containerd restarted clean and re-pulled every image. |
| 28-09 ~06:00 | CoreDNS up on cp01 after the re-pull. |
| 28-09 ~06:12 | Worker kubelets found wedged on orphaned pod workers (see §7, recovery errors). Restarted. |
| 28-09 ~06:25 | kube-proxy pods on both workers deleted; stale iptables rules rebuilt; Service routing restored. |
| 28-09 06:29 | Vault unsealed. |
| 28-09 ~06:45 | Loki's two-day-old stuck `VolumeAttachment` cleared by removing its finalizer. |
| 28-09 06:59 | Fresh etcd backup taken and manually copied off-site. Revision 1,423,859. |
| 28-09 ~07:10 | **Finding.** An orphaned `node-exporter` container (PID 3860, parented by orphaned shim 2266) found holding port 9100, blocking the DaemonSet for six days. Killed. |
| 28-09 ~07:14 | Backup metrics reach Prometheus for the first time. `VeleroOffsiteCopyTooOld` fires and is delivered to Discord. |

## 3. Root cause

**The host does not honour guest fsync across an abrupt reset.**

etcd and containerd both use bbolt, and bbolt's crash safety rests on one
assumption: when a write is acknowledged as durable, it is durable. Both
databases were damaged by the same events, in different ways:

| | etcd | containerd |
|---|---|---|
| Symptom | page header contains garbage | freelist double-free |
| Message | `Page expected to be: 8688, but self identifies as 3846692236623885411` | `page 367 already freed` |
| Discovered during | MVCC compaction | transaction commit |
| Recoverable by tooling | no (`etcdutl defrag` panicked on the same page) | n/a — store discarded |

A single corrupted database suggests an application bug. **Two independent ones,
from one event, on media with clean SMART, does not.** Writes were lost or
reordered somewhere between the guest's fsync and the platter — the guest's
virtual disk layer, the host's file cache, or the drive's volatile write cache.

**Ruled out: failing media.** `Get-StorageReliabilityCounter` reports
`ReadErrorsTotal 0`, `WriteErrorsTotal 0`, 43 °C, and `HealthStatus Healthy` on
both the Samsung NVMe and the Seagate SSHD.

**Ruled out for corruption 2: a bad backup.** The crashing compaction covered
revisions 1,425,299–1,439,321. The restore had left the database at revision
1,403,336. The corrupt page was therefore in data written *after* the restore,
not in the archive.

### 3.1 The 27-09 failure was a latent defect from 2026-09-18

The first panic is different in kind. etcd's `consistentIndex` read **0** against
a snapshot at index 1,210,129, so etcd tried to rebuild its backend from a
`.snap.db` file that single-node clusters never write.

A `consistentIndex` of zero is the signature of a bbolt file assembled by hand —
which is exactly what the 2026-09-18 recovery produced. **That defect was
invisible for nine days**, because etcd only performs this check at startup and
holds its state in memory otherwise. The cluster was suspended and resumed
repeatedly in that window; none of it triggered a genuinely cold start. The
26-09 unclean shutdown forced one.

**A control-plane repair is not verified until the node has been cold-booted.**
"It is running again" is not the test.

## 4. Why recovery took so long

etcd was restored in about twenty minutes on each occasion. The rest of the time
went on a dependency chain in which each layer only became diagnosable once the
one beneath it was fixed:

```
Windows auto-restart
 └─ etcd + containerd bbolt corruption
     └─ containerd metadata discarded → cp01 re-pulls ~40 images
         └─ CoreDNS down meanwhile → no cluster DNS
             └─ longhorn-manager cannot resolve its own conversion webhook
                 → fatal after 60s, crashlooping on both workers
                 └─ never binds :9500
                     └─ longhorn-csi-plugin cannot reach longhorn-backend
                         └─ csi.sock never created
                             └─ node-driver-registrar times out after 30s
                                 └─ no CSI driver registered
                                     └─ no volume attach
                                         └─ Vault, Postgres, Prometheus,
                                            Grafana, Alertmanager, Loki all stuck
```

Later, with DNS healthy, the same chain stalled again one layer up: **kube-proxy
on both workers came back with stale iptables rules**, so `longhorn-manager`
still could not reach its webhook *Service*, and the identical cascade repeated.
Diagnosed by observing that worker01 could reach a backend pod IP directly
(connection *refused*, 0 ms — routing fine) but not the ClusterIP (timeout).

Nine layers, one cause. Each was a correct, well-behaved failure of a component
waiting on a dependency; none was a bug.

## 5. Recovery evidence

| | |
|---|---|
| Archive used | `etcd-k8s-cp01-20260926-120327.tar.gz.age`, sha256 `398ee0b1…186e` |
| Contents | `etcd.db`, full PKI incl. CA keys, four static manifests, five kubeconfigs |
| Snapshot status | revision 1,403,336; 2,653 keys; 49 MB; hash `fe772c81` |
| Restore command | `etcdutl snapshot restore --name k8s-cp01 --initial-cluster … --data-dir /var/lib/etcd` |
| Post-restore | etcd attempt 1 Running; cluster-id `306382c50f6165be` |
| Data verified | `select count(*) from tasks` → **6**, after both restores |
| Volumes | 8/8 `attached` / `healthy` after rebuild |
| New backup | `etcd-k8s-cp01-20260928-065932`, revision 1,423,859, 7.4 MB, copied off-site and checksum-verified |

## 6. What went well

- **The backup worked, twice.** A verified archive, a documented procedure and a
  tested restore turned two total control-plane losses into routine operations.
- **Zero data loss**, because application data lives in Longhorn replicas on the
  workers and is unaffected by etcd's state. This distinction was understood in
  advance rather than discovered under pressure.
- **The recovery ordering held.** Vault → External Secrets → Postgres, proven by
  the 26-09 restore drill, was correct both times.
- **The corrupt artefacts were preserved**, not deleted, at every step —
  `/var/lib/etcd.broken-20260927`, `/var/lib/etcd.corrupt-20260928`,
  `/var/lib/containerd.corrupt-20260928` and two tarballs — which is what made
  the diagnosis in §3 possible.
- **Longhorn rebuilt every degraded replica unattended.**

## 7. What did not go well

### 7.1 The alerting was broken in two independent places

This is the most serious finding, and it predates the incident.

The right alerts existed. They were written in advance and they name this exact
failure:

```yaml
- alert: EtcdBackupMetricMissing
  expr: absent(etcd_backup_last_success_timestamp_seconds)
  summary: "No etcd backup metric: backup script or node-exporter textfile collector broken"

- alert: VeleroOffsiteMetricMissing
  expr: absent(velero_offsite_last_success_timestamp_seconds)
  summary: "No off-cluster copy metric: the mirror job or node-exporter may be broken"
```

Neither reached a human, because **both ends of the pipeline were broken**:

1. **Collection.** An orphaned `node-exporter` container held `hostNetwork` port
   9100 on cp01, so the DaemonSet pod could not bind — 230 restarts over 6d15h.
   That pod is what reads `/var/lib/node_exporter/textfile_collector/`. The
   metrics were being written correctly the entire time and never scraped.
2. **Delivery.** Until 27-09, Alertmanager's Discord webhook came from the wrong
   Vault path and served a revoked URL. External Secrets reported `SecretSynced`
   throughout.

`velero_offsite.prom` was sitting on disk with an mtime of 26-09 03:22 —
accurate, current as of the failure, and invisible.

**The monitoring for backups was itself unmonitored.**

### 7.2 The off-site copy stopped silently

Every etcd backup after 26-09 12:03 existed only on the VM it was protecting.
Through the worst two days this cluster has had, the only off-cluster copy was
the one being restored from. Had the VMDK been damaged instead of etcd's pages,
the outcome would have been very different.

### 7.3 The documented e1000 mitigation does not work

`nic-offload-off.service` was **enabled, active, and all offloads confirmed
`off`** when the third Tx unit hang occurred on 28-09. Disabling segmentation
and checksum offload reduces the frequency but does not prevent it. Three hangs
in five days.

### 7.4 Recovery errors

- **Force-deleting live pods stranded two kubelets.** `kubectl delete --force`
  on the `longhorn-manager` pods removed the API objects while the workers'
  kubelets still held them, after which NodeRestriction refused the kubelets'
  own status queries (`no relationship found between node 'k8s-worker01' and
  this object`). Both kubelets then looped on orphans for fourteen minutes,
  blocking every new pod. **Rule: a stuck pod deletion on a live node means the
  kubelet is busy, not broken — restart the kubelet; never force the object
  away.** Force delete is correct only for a ghost object whose node has
  rebooted and which the kubelet has no record of.
- **containerd was twice misread as healthy** from a single clean boot line in
  the journal tail, while it was in fact restarting every few seconds.
  `systemctl show containerd -p NRestarts` answers this in one command and
  should be the first check, not the last.

## 8. Action items

| # | Item | Status |
|---|---|---|
| 1 | `NoAutoRebootWithLoggedOnUsers=1` to stop Windows Update restarting the host | **Done 28-09** |
| 2 | Kill the orphaned node-exporter; backup metrics now scraped and alerting verified end to end (33 Discord notifications, 1 failure) | **Done 28-09** |
| 3 | Fresh etcd backup taken and manually copied off-site with checksum | **Done 28-09** |
| 4 | Find why the off-site pull died on 26-09; it is a Windows-side scheduled task with no monitoring of its own | Open |
| 5 | Add active-hours and the registry policy to `infrastructure/laptop/set-power-policy.ps1` — power policy and update policy belong in the same script | Open |
| 6 | **Complete the KVM migration.** Four corruption events, all following an unclean host reset, on healthy media | Open — blocked on replacement SSD |
| 7 | Mirror `quay.io/minio/minio` to GHCR; upstream now returns 401 and the only copy is one node's containerd store plus a 60 MB tar on D: | Open |
| 8 | CoreDNS anti-affinity — both replicas on cp01 meant one slow image pull removed cluster DNS and blocked storage on two other nodes | Open |
| 9 | Alert on stale `VolumeAttachment` objects; Loki's was wedged for two days and was restored from backup along with everything else | Open |
| 10 | Record in `rebuild.md` that `secret/ghcr` and `secret/alertmanager`'s webhook are neither in Git nor generated by the vault-config Job | Open |
| 11 | Reconsider §7.3 — either accept e1000 hangs until migration, or switch cp01 to vmxnet3 (requires pinning the IP statically first: the address is currently a DHCP lease and the API certificate is pinned to it) | Open |
| 12 | Clean reboot of cp01 to clear ten orphaned `containerd-shim` processes, then delete the three preserved corrupt directories | Open |

## 9. Notes

**The cluster's addresses are DHCP leases, not static.** `ip a` on cp01 shows
`192.168.75.136/24 … dynamic ens33` with a 30-minute lease. The API server
certificate is pinned to that address. ADR-006 decision 3 specifies cloud-init
static addressing for exactly this reason — "a DHCP lease is state living in the
hypervisor" — and the current cluster does not match it. This is a latent hazard
for any change that alters the guest MAC, including switching NIC type.

**Restart counters as a measure of hardware cost.** `kube-apiserver` reached 98
restarts and `cert-manager-cainjector` 129 over the life of this cluster. Very
few represent distinct faults; almost all are a slow disk and a wedging NIC
failing liveness probes.

## 10. Related

- `docs/incidents/2026-09-18-etcd-corruption.md` — the repair whose latent defect surfaced here
- `docs/incidents/2026-09-25-host-sleep.md` — the same fsync mechanism, via S3 sleep
- `docs/runbooks/database-restore-drill.md` — the Vault → ESO → Postgres ordering, correct both times
- `docs/adr/ADR-006-bootstrap.md` — decision 1 (virtio over e1000), decision 3 (static addressing)
