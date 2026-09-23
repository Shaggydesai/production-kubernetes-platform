# Incident: etcd corruption and full control-plane loss

**Date:** 18–20 September 2026 (recovery), 21 September (follow-up repair)
**Severity:** SEV-1 — complete control-plane outage, permanent loss of some application data
**Cluster:** `k8s-cp01` / `k8s-worker01` / `k8s-worker02`, kubeadm v1.36.3, etcd 3.6.8, single control-plane node
**Status:** Resolved. Follow-up actions tracked below.

> This is a blameless postmortem. The goal is to understand what the system let
> happen, not who typed what. Every "we" below is the system plus its operator.

---

## 1. Summary

The single etcd member backing the cluster became corrupted. The API server
entered a crash loop and the cluster was unusable. The initial recovery
attempts (`etcdctl snapshot restore` on a raw `member/snap/db`, then
`--force-new-cluster`) did not restore the data and made the on-disk state
harder to reason about.

Recovery was eventually achieved by rebuilding an etcd database from the
preserved copies of the data directory, using purpose-written Go tools to read
the bbolt pages, the write-ahead log and the Kubernetes protobuf payloads.
The cluster returned to service on 19 September at about 08:42.

Kubernetes objects and HashiCorp Vault's data were recovered. PostgreSQL,
MinIO, Prometheus, Grafana, Alertmanager and Loki data were **not** recovered
and were rebuilt empty.

Three days later a routine verification revealed that the rebuilt database was
**structurally damaged but functional**: four stray records sat at the top level
of the bbolt file, so every snapshot taken from it failed integrity checks. That
was repaired on 21 September with 47 seconds of API downtime.

---

## 2. Impact

| Area | Impact |
|---|---|
| Kubernetes API | Unavailable for roughly 14 hours (18 Sep evening → 19 Sep 08:42) |
| Running workloads | Kept running on the workers; no scheduling, no reconciliation, no `kubectl` |
| Kubernetes objects | Recovered |
| Vault data | Recovered from a Longhorn replica |
| PostgreSQL / MinIO / Prometheus / Grafana / Alertmanager / Loki | **Data lost**, rebuilt empty |
| Backups | None usable: no etcd snapshot schedule existed; Velero could back up but its volume restore had never worked |

---

## 3. Timeline (all times local)

| When | What |
|---|---|
| 13 Sep | Last known-good state. Platform complete: MetalLB, cert-manager, Envoy Gateway, Longhorn, Vault + ESO, kube-prometheus-stack, MinIO, Velero, taskflow-api |
| 17–18 Sep | Cluster-wide pod failures with `network is unreachable` across unrelated namespaces at the same moment. Nodes use DHCP with ~26-minute leases on VMware Workstation |
| 18 Sep | Networking checks came back clean; the blip had passed. Deeper problems remained: `vault-configure` Jobs failed, `ClusterSecretStore` missing, pods Pending for 22 hours |
| 18 Sep | etcd began crashing; the API server followed. `/var/lib/etcd` was moved aside twice, producing `etcd.bak.1789755333` and `etcd.old/member.corrupted.1789755960` |
| 18 Sep | First recovery attempts: `etcdctl snapshot restore` on a raw `member/snap/db`, then `etcd --force-new-cluster`. The API server started but contained only the default namespaces; repeated attempts panicked |
| 18 Sep | **Recovery stopped. Raw copies were preserved** under `/root/etcd-backup-BEFORE-RECOVERY` and `/root/etcd-old-BEFORE-RECOVERY` before any further experiments |
| 18–19 Sep | Offline analysis: `strings` confirmed the backup contained `/registry/...` objects. Custom Go tools were written to read bbolt pages, the WAL and `mvccpb.KeyValue` / Kubernetes protobuf payloads, and to rebuild a usable database |
| 19 Sep 08:42 | `/var/lib/etcd.RECOVERED` moved into place; etcd, the API server and the nodes came back |
| 19 Sep | Vault's data volume recovered from a Longhorn replica on `k8s-worker02`. PostgreSQL, MinIO and the monitoring stack were rebuilt with empty volumes |
| 19–20 Sep | Platform repairs: Longhorn orphan cleanup, an Argo CD sync-wave ordering bug, cert-manager ClusterIssuers, an Argo CD HTTPRoute pointing at a non-existent Service |
| 20 Sep 11:34 | All Argo CD applications Healthy. Final snapshot taken: `etcd-recovery-final-20260920-113414.db`, sha256 `4caf669f…fec34`. **`snapshot status` on it failed and the failure was attributed to an etcdctl version mismatch** |
| 21 Sep | With matching etcdutl 3.6.8, `snapshot status` still failed: `nil bucket`. Four stray MVCC records (revisions 2267850–2267853, all Lease heartbeats from the pre-incident database) sat at the top level of the bbolt file, outside any bucket |
| 21 Sep | Cleaned offline on a copy, verified with `etcdutl snapshot status`, test-restored into a throwaway etcd, then swapped live via a scripted procedure with automatic rollback. **API downtime: 47 seconds** |
| 21–23 Sep | Follow-up work: automated encrypted backups, off-node copies, alerting, control-plane metrics, host config in Ansible, Vault least privilege, credential rotation |

---

## 4. Root cause

**Direct cause: not conclusively established.** The evidence points to the etcd
data files being damaged by an abrupt interruption of the underlying VM or its
storage: the cluster runs on a single VMware Workstation host, the nodes use
short DHCP leases, and the failure began with a simultaneous, cluster-wide
`network is unreachable` event consistent with a host sleep/resume or a virtual
network reset. A single-member etcd has no peer to reconcile against, so
whatever reached the disk became the only truth.

**What turned a fault into a disaster** was the absence of recovery options, not
the fault itself:

1. **No etcd backups.** No snapshot schedule existed. Recovery depended entirely
   on data directories that happened to still be on disk.
2. **Backups that existed were never restore-tested.** Velero could create
   backups, but restoring volume data had never worked (a known, documented
   open item at the time: node-agent → API server connectivity). An untested
   backup is a hope, not a backup.
3. **A single control-plane node.** One etcd member means one copy of cluster state.
4. **Destructive recovery steps came before preservation.** `--force-new-cluster`
   and repeated restores were attempted before full copies were secured.
5. **The hand-rebuilt database was trusted without verification.** It ran
   correctly for three days while every snapshot taken from it was unverifiable.

---

## 5. What went well

- **Copies were preserved** (`etcd.bak.*`, `etcd.old/*`) before the most
  destructive steps, which is what ultimately made recovery possible.
- **GitOps paid off.** Every piece of platform configuration lived in Git, so
  rebuilding the platform on top of a recovered etcd was mechanical.
- **Longhorn replicas survived** and allowed Vault's data to be recovered from a
  worker node's local replica directory.
- **Recovery stopped when it was making things worse**, and switched to offline
  analysis of read-only copies.

## 6. What went badly

- A verification failure (`snapshot status`) was explained away as a tooling
  issue rather than investigated. It was real, and it meant three days of
  unverifiable backups.
- Recovery ran for hours on a system with no rollback plan, because no known-good
  copy of the cluster state existed.
- The blast radius was invisible: nothing told anyone that backups were missing,
  that Velero restores didn't work, or that etcd was unmonitored.

---

## 7. Action items

| # | Action | Status |
|---|---|---|
| 1 | Encrypted etcd snapshots every 6 hours, integrity-checked on creation, 7-day retention | **Done** (systemd timer, `age` encryption, `etcdutl snapshot status` in the script) |
| 2 | Snapshots copied off the node automatically | **Done** (hourly pull to a laptop over read-only, IP-restricted SFTP; 30-day retention) |
| 3 | Restore actually tested from a backup | **Done** (decrypt → unpack → `snapshot status`; full restore rehearsed on a throwaway etcd) |
| 4 | Alert when backups stop | **Done** (`EtcdBackupTooOld`, `EtcdBackupMetricMissing`; tested by breaking it on purpose) |
| 5 | Alerts delivered somewhere a human sees them | **Done** (Alertmanager → Discord; webhook in Vault, never in Git) |
| 6 | Control-plane components actually monitored | **Done** (etcd, scheduler, controller-manager and kube-proxy metrics were unreachable on 127.0.0.1; now bound correctly, and recorded in `kubeadm-config` so upgrades keep it) |
| 7 | Host-level configuration in code | **Done** (`etcd_backup`, `node_metrics`, `control_plane_metrics` Ansible roles; dry run reports no drift) |
| 8 | Vault root token removed from the cluster | **Done** (Job uses Kubernetes auth with a least-privilege policy; root token revoked; admin access via `userpass`) |
| 9 | Rotate credentials exposed during the incident | **Done** (PostgreSQL admin and app passwords; old Vault versions destroyed) |
| 10 | Velero volume restore fixed and proven | **Done** — drill 23 Sep 2026: backup → namespace deleted → restore → canary file byte-identical |
| 11 | Velero backups copied off-cluster | **Done** — nightly rclone mirror, age-encrypted, pulled to the laptop, alerted on |
| 12 | Multi-node control plane (etcd quorum) | **Open** — accepted risk for a lab on one physical host |
| 13 | Periodic restore drill: rebuild the cluster from Git + backups and time it | **Open** |

---

## 8. Lessons

1. **A backup is not a backup until you have restored from it.** Both failures
   here (no etcd snapshots, Velero volume restore never working) were invisible
   until the day they mattered.
2. **Preserve before you repair.** Copy the failed state somewhere safe before
   trying anything that writes.
3. **When verification fails, believe it.** `snapshot status` failing was a real
   defect, not a tooling quirk.
4. **Software that runs is not software that is correct.** The rebuilt etcd
   served traffic for three days with a malformed database.
5. **Monitor the things that save you**: backup age, and the components whose
   failure ends the cluster.
6. **A single-node control plane is a single point of failure**, and if you accept
   that risk you must compensate with backups you have tested.

---

## 9. Evidence

- Stray records: revisions 2267850–2267853 (`/registry/leases/...`), sitting at
  the bbolt top level; rebuilt database's own maximum revision was 289689.
- Failure signature before repair: `Error: nil bucket: "\x00\x00\x00\x00\x00\"\x9a\xca_..."`
- After repair: `snapshot status` → hash `89bc6b94`, revision 289689, 1480 keys.
- Swap procedure: `/root/etcd-swap.sh` (stop API server → snapshot → clean →
  verify → stop etcd → restore → start → verify), with automatic rollback.
- Live swap window: 13:47:48 → 13:48:35 on 21 Sep 2026.
