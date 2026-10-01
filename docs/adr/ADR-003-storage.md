# ADR-003: Persistent storage with Longhorn

- **Status:** Accepted, with two decisions flagged for reversal
- **Date:** 2026-09-30
- **Supersedes:** none

## Context

Six components in this platform need persistent volumes: PostgreSQL, Vault,
MinIO, Prometheus, Grafana, Alertmanager and Loki. The cluster is three VMs on a
single physical host, which means "replication across nodes" buys resilience
against a guest dying but nothing at all against the host dying.

Most of these decisions were made while building and only became visible as
decisions when something broke. Two of them are now known to be wrong and are
recorded here as such rather than quietly corrected, because the reasoning that
produced them was sound at the time and is worth keeping.

## Decision 1 — Longhorn as the CSI driver, not hostPath or local-path

Longhorn runs as a DaemonSet, presents a CSI driver, and replicates each volume
synchronously to *N* nodes. `local-path-provisioner` is simpler and faster and
gives a volume that exists on exactly one node, which means a node reboot
strands every workload bound to it.

**Evidence this was the right call.** During the 2026-09-18 etcd corruption,
Vault's data was recovered by reading a Longhorn replica directory directly off
`k8s-worker02` — the API server was down, the CSI driver was not running, and the
data was still there as files on a worker's disk. Nothing else in the cluster
survived that event. A `hostPath` volume on cp01 would have been inside the
blast radius.

**Consequence:** every write is a synchronous network write to a second node, so
volume latency is bounded by the slowest replica. On a 5400 rpm SSHD this is the
dominant cost of every storage operation, and it is what makes a node restart —
which triggers a rebuild — reproduce the etcd fsync collapse in ADR-006 and
`docs/incidents/2026-09-25-host-sleep.md`.

## Decision 2 — two replicas, not three, with soft anti-affinity

```yaml
longhorn:
  defaultSettings:
    replicaSoftAntiAffinity: true
  persistence:
    defaultClassReplicaCount: 2
```

Three replicas on a three-node cluster means every write goes to every node, and
a single node being down degrades every volume simultaneously. Two gives one
spare copy at two-thirds of the write cost.

`replicaSoftAntiAffinity: true` lets Longhorn place both replicas on the same
node **rather than refusing to schedule**. With hard anti-affinity, a volume
needing two replicas on a cluster with one healthy storage node stays
`Degraded` and unattachable — the volume is unavailable because it cannot be
made perfectly safe. Soft anti-affinity prefers spreading and degrades to
co-location.

**Consequence:** a volume can silently end up with both replicas on one node,
which is exactly the redundancy you thought you had and do not. Longhorn
rebalances when a node returns, but nothing alerts on the co-located state.

## Decision 3 — MinIO gets a single-replica StorageClass of its own

```yaml
# kubernetes/platform/minio/templates/storageclass.yaml
name: longhorn-single-replica
parameters:
  numberOfReplicas: "1"
  staleReplicaTimeout: "2880"
```

MinIO holds Velero backups. Replicating it inside the cluster protects against a
node failure, which is the failure mode least likely to matter for a backup
target: the backups that count are the ones already mirrored off the host by
`velero-offsite.sh`. Paying double write cost to keep a second in-cluster copy of
data whose whole purpose is to exist off-cluster is the wrong trade.

**Consequence:** losing the node holding MinIO's replica loses every backup not
yet mirrored — up to 24 hours of them, since the mirror runs at 03:15. This is
accepted, and it is the reason `MinIODriveOffline` is a **critical** alert with
the description "this deployment is single-drive with EC:0, so there is no
redundancy to lose".

## Decision 4 — node prerequisites are Ansible's, not Helm's

```yaml
# roles/kube_prereqs/defaults/main.yml
kube_prereqs_storage_packages:
  - open-iscsi
  - nfs-common
```

Longhorn attaches volumes over iSCSI and mounts some over NFS. Neither is
something a chart running *inside* the cluster can install on a node.

This is the general layer boundary from ADR-006 decision 6, in its most
load-bearing form: a Longhorn that installs perfectly and cannot attach a single
volume is a very confusing failure, and the error surfaces in the CSI plugin
rather than anywhere near the missing package.

**Consequence:** adding a node means running `playbooks/cluster.yml` against it
before Longhorn will work there. `make node-config` does not cover it; the
prerequisites are in the cluster build.

## Decision 5 — ReadWriteOnce everywhere, and stateful workloads do not roll

Every volume in this platform is RWO. Longhorn supports RWX via an NFS
provisioner, and nothing here needs shared write access.

RWO means **one node**, not one pod. The consequence is specific and catches
people: a single-replica Deployment with a `RollingUpdate` strategy deadlocks
when the new pod is scheduled to a different node, because the new pod waits for
the volume and the volume waits for the old pod to terminate. The fix is
`strategy: Recreate` for single-replica stateful Deployments, or a StatefulSet,
which uses `OnDelete`/ordered replacement semantics and one PVC per replica.

**Consequence:** Prometheus, Grafana, Alertmanager and Loki all take a gap in
service across an upgrade rather than rolling. Expect a hole in your metrics
across a Prometheus bump, and expect it to coincide with the change you were
trying to observe.

## Decision 6 — volumes are sized small and deliberately

| Component | Size | Retention it implies |
|---|---|---|
| Prometheus | 10 Gi | 7d |
| Loki | 10 Gi | 168h, matched to Prometheus on purpose |
| MinIO | 5 Gi | 7d of Velero data, 14d of metadata |
| PostgreSQL | 5 Gi | the application's actual data |
| Grafana | 5 Gi | dashboards and its own DB |
| Alertmanager | 2 Gi | silences and notification state |

Total is under 40 Gi before replication, which fits a lab host with other things
to do. Prometheus and Loki retention are matched so that a metric spike and the
logs from the same minute are both still there — mismatched windows produce the
specific frustration of having half the evidence.

**Consequence:** MinIO at 5 Gi with accumulating backups is the tightest of
these, which is why it has capacity alerts at 20% and 10% free and why the
critical one says outright that "backups will start failing".

## Decision 7 — REVERSE THIS: Prometheus's TSDB is on Longhorn

This was wrong and is recorded as a decision because the reasoning was
consistent and the consequence was not foreseen.

Putting Prometheus on Longhorn is what every other stateful component does, it
survives a node failure, and it needs no special case. The problem is that
**monitoring stored on the storage layer it monitors cannot report on that
layer.**

`EtcdDiskCriticallySlow` was written on 2026-09-24, aimed precisely at the
failure that occurred the next day, and stayed silent through a 1,341 ms WAL
fsync and 47 control-plane restarts — because Prometheus's pod was `Pending` for
most of the incident waiting for its own Longhorn volume, so there was no data to
evaluate and never ten continuous minutes of it afterwards.

This is structural, not a threshold to tune. Action item 7 of
`docs/incidents/2026-09-25-host-sleep.md` is to move the TSDB off Longhorn — to a
`local-path` volume pinned to one node, accepting that a lost node loses metrics
history, because metrics history is the least valuable thing in the cluster and
the ability to observe an incident while it is happening is the most.

**Status:** open. See `docs/roadmap.md`.

## Decision 8 — REVERSE THIS: monitoring data is not backed up

`velero-daily-data` includes `taskflow` and `vault` only. The `monitoring`
namespace is excluded, so after the September incident Prometheus, Grafana,
Alertmanager and Loki were rebuilt empty.

For time series this is correct — seven days of lab metrics is not worth a
backup. It is wrong for one thing that happens to live in the same volume:
**Grafana dashboards created in the UI**, which are not in Git, not in a backup,
and do not survive a rebuild.

The fix is not to back up the namespace. It is to provision dashboards as
ConfigMaps carrying the `grafana_dashboard` label, which the chart's sidecar
loads — moving them into the declared state where everything else lives.

**Status:** open. See `docs/roadmap.md`.

## Consequences

- Application data survives the loss of a guest, and has twice survived the loss
  of the control plane, because it lives in Longhorn replicas on the workers and
  not in etcd. This distinction was understood in advance rather than discovered
  under pressure, and it is why both 2026-09-27 restores were zero-data-loss.
- Nothing survives the loss of the host except what has been mirrored off it.
  That is `velero-offsite.sh` and the hourly etcd backup pull, and it is the only
  real protection this platform has.
- Volume latency is the platform's dominant performance characteristic, and it is
  a property of the disk rather than of Longhorn.
- Stateful components take downtime on upgrade. This is a consequence of RWO and
  is not worth engineering around at this size.
- Two of the eight decisions above are known-wrong and unfixed. Both are in the
  roadmap with the reasoning intact.

## Related

- `docs/adr/ADR-006-bootstrap.md` — decision 6, the Ansible/Helm layer boundary
- `docs/adr/ADR-004-monitoring.md` — decision 9, monitoring's shared fate
- `docs/incidents/2026-09-18-etcd-corruption.md` — Vault recovered from a replica
- `docs/incidents/2026-09-25-host-sleep.md` — action item 7, the TSDB
- `docs/runbooks/database-restore-drill.md` — what a volume restore actually needs
- `docs/runbooks/lab-startup-shutdown.md` — Longhorn's staged start and salvage
