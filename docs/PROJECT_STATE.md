# Project state

Living summary of what exists, why, and what is deliberately deferred.
Procedures live in `docs/runbooks/`, decisions in `docs/adr/`, incidents in
`docs/incidents/`.

Last reviewed: 2026-09-25

## Conventions

### Helm chart dependencies

Upstream dependencies are **vendored** into each wrapper chart's `charts/`
directory and committed — all 14 platform charts. The platform is rebuildable
from Git alone with the exact bytes that were tested, independent of upstream
availability. `dl.min.io` began returning HTTP 410 mid-project; this is not
theoretical.

Bumping a chart: edit `Chart.yaml`, run `helm dependency update`, commit the
new `.tgz` and `Chart.lock` together. `.gitattributes` marks `*.tgz` binary.

### Argo CD has one install path

`infrastructure/ansible/roles/argocd` installs the in-repo wrapper chart at
`kubernetes/platform/argocd`. There is deliberately no values template in the
role — the chart's own `values.yaml` is the single source. See ADR-002.

### Alertmanager configuration

`alertmanagerSpec.useExistingSecret: true` means the operator ignores any
`config:` key in the chart values. The live `alertmanager.yaml` is rendered by
`kubernetes/platform/vault-config/externalsecret-alertmanager-config.yaml`.

The Discord webhook value lives in Vault at `secret/alertmanager`, property
`discord-webhook-url` — **not** `secret/discord`. Rotation procedure and the
verification chain: `docs/runbooks/secret-rotation.md`.

### Building the platform from nothing

Four layers, all declarative:

| Layer | Where | What |
|---|---|---|
| Host | `infrastructure/ansible/playbooks/kvm-host.yml` | KVM, libvirt, storage pool, sleep disabled |
| VMs | `infrastructure/terraform` | three guests, cloud-init, static IPs |
| Cluster | `infrastructure/ansible/playbooks/cluster.yml` | containerd, kubeadm, Flannel, join |
| Platform | `platform-root` | Argo CD converges the rest |

`make up` runs all four and stops at the Vault gate. Decisions and their
reasoning: `docs/adr/ADR-006-bootstrap.md`. Procedure: `docs/runbooks/rebuild.md`.

Two things deliberately are **not** GitOps-managed, and both have ordering
reasons rather than stylistic ones. The CNI is applied by Ansible, because Argo
CD is pods and pods need pod networking. Node packages — `open-iscsi`,
`nfs-common` — are Ansible's, because a Helm chart cannot install a package on
its host.

## Manual steps — nothing enforces these

| Step | When |
|---|---|
| `kubectl apply -f kubernetes/gitops/bootstrap/platform-root.yaml` | After any change to the root Application |
| Vault unseal, 3 of 5 shares | After any restart of `vault-0` |
| `infrastructure/laptop/set-power-policy.ps1` | Windows host only; replaced by the `host_no_sleep` Ansible role after the Ubuntu rebuild |
| `make vault-init` then `make secrets` | After a rebuild. Deliberately not automated — ADR-006 decision 7 |

## Accepted risks

| # | Risk | Mitigation | Revisit |
|---|------|-----------|---------|
| 12 | Single control-plane node | Verified 6-hourly encrypted etcd backups, off-site copy, proven restorable | Not fixable on one laptop |
| 14 | etcd on HDD: 15 ms fsync p99 idle, 1,341 ms under load | `lab:etcd_wal_fsync_p99` trending, `EtcdDiskCriticallySlow`, raised leader-election deadlines | SSD migration |

## Open

- **Age private key not confirmed replicated.** The identity rotated on
  2026-09-25 12:18 exists in exactly one location on the operator's workstation
  and has not been confirmed replicated anywhere else. Every etcd and Velero
  archive written since 12:18 is encrypted to its public half, so losing that
  one file makes every current backup permanently unreadable. Fix: store the identity in the password
  manager, verify a decrypt from that copy, then remove the working file. This
  outranks risk 12 (single control-plane node), because the backups are the
  mitigation for risk 12.
- **Postmortem item 13 — the rebuild drill has still never been run.** It is now
  *executable* rather than theoretical: `make up` plus two manual steps, see
  `docs/runbooks/rebuild.md`. Every layer passes syntax and lint checks, and none
  of it has ever been applied to real hardware. Do it on the SSD host, record
  the timings in the runbook's table, and then measure
  `etcd_disk_wal_fsync_duration_seconds` before deciding whether the raised
  leader-election values are still needed.
- **Monitoring blind spot** — Prometheus stores its TSDB on a Longhorn volume,
  so it cannot observe storage incidents. `EtcdDiskCriticallySlow` did not fire
  on 2026-09-25 because Prometheus was Pending throughout.
- **Velero data backups fail when the host sleeps.** 3 of the 8 backups
  recorded on 2026-09-26 had failed: 09-24 and 09-25 `velero-daily-data` and
  09-24 `velero-daily-metadata`. All three started ~3h after their 01:00
  schedule, i.e. cron firing late on host resume while MinIO and Longhorn were
  still unavailable. `velero backup logs` returns "file not found" for them:
  they failed before uploading anything. `VeleroBackupTooOld` should have fired
  on the resulting 39h gap and did not, because Prometheus was Pending — see
  the monitoring blind spot above.
- **Stale Velero BackupRepository `velero-drill-default-kopia-mptz8`** for a
  namespace that no longer exists, running maintenance jobs every 30 minutes
  against the HDD.
- Empty placeholder docs: ADR-003 to ADR-005, `platform-architecture.md`,
  `roadmap.md`, `implementation-plan.md`, `interview-notes.md`. Fill or delete.
