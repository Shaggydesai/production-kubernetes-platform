# Incident: host sleep corrupts Longhorn volumes, control plane flaps

**Date:** 2026-09-25
**Duration:** 04:07 UTC (host resume) to 06:00 UTC (all applications healthy) — ~2h
**Data loss:** none
**Author:** Sagar
**Status:** resolved; contributing cause (HDD) accepted pending hardware migration

Times are UTC. The host clock is IST (UTC+5:30); host event times are given in both.

## 1. Summary

The laptop hosting all three cluster VMs entered S3 sleep overnight with the VMs
running. On resume, VMware's pending virtual-SCSI I/O had long since timed out.
The guests received hard I/O errors, ext4 aborted its journals and remounted the
affected filesystems read-only, and the emulated NIC on the control plane wedged.

No data was lost. Recovery required a full power cycle of all three VMs and a
Vault unseal. The underlying HDD, which has no I/O headroom, turned a recoverable
event into a two-hour one.

## 2. Timeline

| Time (UTC) | Event |
|---|---|
| 24-09 18:11 (23:41 IST) | Host enters S3 sleep. All three VMs running. Kernel-Power event 42. |
| 24-09 18:11 – 25-09 04:07 | ~10 hours suspended. |
| 25-09 04:07 (09:37 IST) | Host resumes. Kernel-Power event 131, ResumeCount 2. |
| 25-09 ~04:20 | Guests report `critical medium error` on Longhorn iSCSI devices. ext4 aborts journals on the MinIO and Prometheus PVCs; filesystems remount read-only. |
| 25-09 04:37–04:46 | metallb frr-k8s on worker01 logs `no route to host` to the API server. |
| 25-09 ~04:32 (10:02 IST) | Detected. SSH to cp01 times out; VMware consoles show the errors. |
| 25-09 ~04:45 | Windows sleep and hibernate disabled (`powercfg`), lid action set to none. |
| 25-09 ~05:00 | Workers powered off (hard — read-only roots cannot shut down gracefully). cp01 shut down via ACPI. |
| 25-09 ~05:10 | Staged start: cp01, then worker01, then worker02. All Ready. |
| 25-09 05:29 | Longhorn rebuilding two degraded volumes. kube-controller-manager crashlooping. |
| 25-09 05:47 | Last volume (Prometheus, 10Gi) reaches healthy. Controller-manager restarts stop at 47. |
| 25-09 05:51 | Vault unsealed. |
| 25-09 ~06:00 | All 7 ExternalSecrets force-synced; 17/17 applications Synced and Healthy. |

## 3. Root cause

**Host S3 sleep with running VMs.** When the host suspends, VMware cannot
complete guest I/O. On resume, requests that have been outstanding for hours are
failed back to the guest, which reports them as `critical medium error` — a SCSI
media fault — even though the physical media is healthy. ext4 responds correctly
by aborting the journal and remounting read-only to prevent corruption.

The same stalled-I/O mechanism wedged the emulated e1000 adapter on cp01
(`Detected Tx Unit Hang`), which is why SSH was unreachable.

Confirmed by Windows Kernel-Power events 42 (sleep) and 131 (resume) bracketing
the failure window, and by two separate guest error batches matching the two
consecutive nights on which the host slept.

**Ruled out:** physical disk failure. Both drives report Healthy/OK, and the
Windows System log contains no disk errors (IDs 7/11/51/52/98/129/153 were all
virtual-switch, NTFS-healthy or boot events).

## 4. Contributing cause: the HDD has no headroom

The VMs run on a 1TB 5400rpm SSHD (ST1000LX015). During recovery:

- Host disk **active time 100%**, **average response time 16,451 ms**
- etcd WAL fsync p99 **1,341 ms** during Longhorn rebuild (etcd's target: <10 ms)
- etcd WAL fsync p99 **15 ms** at idle
- `kube-controller-manager` restarted **47 times**, each on
  `Failed to update lease ... context deadline exceeded` — the lease renewal is
  an etcd write, and it could not complete within the 5-second deadline

The disk is adequate when idle and collapses under any concurrent load. Every
node restart triggers a Longhorn rebuild, which reproduces this reliably.

## 5. What went well

- Guests remounted read-only rather than corrupting data — the failure was safe.
- Longhorn auto-recovered all eight volumes; none reached `faulted`.
- Root cause was identified from three commands (Kernel-Power log, drive health,
  guest dmesg) rather than by trial and error.
- etcd survived intact: 28 MB, no alarms, raft term advanced cleanly.
- The off-site encrypted backups on the SSD were untouched and had been verified
  restorable the previous day.

## 6. What did not go well

**The alert written for this did not fire.** `EtcdDiskCriticallySlow`
(`lab:etcd_wal_fsync_p99 > 1` for 10m) was added on 2026-09-24 and stayed silent
through a 1,341 ms fsync and 47 control-plane restarts. Prometheus stores its
TSDB on a Longhorn volume on the same disk; its pod was Pending for most of the
incident, so there was no data to evaluate and never ten continuous minutes of
it afterwards.

**Monitoring cannot observe the storage layer it depends on.** This is
structural, not a threshold to tune.

**Two pre-existing failures were found by accident**, not by alerting: the
controller-manager crashloop and elevated metallb restart counts were visible
only because `kubectl get pods -A | grep -v Running` was run by hand during
recovery. Argo CD reported every application Healthy throughout.

## 7. Action items

| # | Item | Status |
|---|---|---|
| 1 | Disable host sleep/hibernate; lid action none | Done 25-09 |
| 2 | Record the rule: never sleep the host with VMs running; use the staged shutdown | Open |
| 3 | Power settings as code in `infrastructure/laptop/` | Open |
| 4 | Windows Update active hours (event 578: update-initiated reboot from sleep on 23-09) | Open |
| 5 | Move cp01 to the SSD | Open — see PROJECT_STATE accepted risk 14 |
| 6 | Raise leader-election lease/renew deadlines on controller-manager and scheduler; free on a single-node control plane | Open |
| 7 | Move Prometheus TSDB off Longhorn so monitoring survives storage incidents | Open |
| 8 | Shorten `EtcdDiskCriticallySlow` from `for: 10m` to `for: 5m` | Open |
| 9 | Alert on pod restart rate — `KubePodCrashLooping` should have caught the controller-manager | Open |
| 10 | Switch e1000 → vmxnet3 (lower priority: the Tx hang followed suspend/resume both times) | Open |

## 8. Notes

`taskflow-api` has no database schema — the `taskflow` database is an empty 7.5 MB
template. The `daily-data` Velero schedule is therefore backing up a volume with
no application data, and the restore procedure has never had data to restore.
Giving the app real persistence would make both meaningful.
