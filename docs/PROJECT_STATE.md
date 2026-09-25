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

## Manual steps — nothing enforces these

| Step | When |
|---|---|
| `kubectl apply -f kubernetes/gitops/bootstrap/platform-root.yaml` | After any change to the root Application |
| Vault unseal, 3 of 5 shares | After any restart of `vault-0` |
| `infrastructure/laptop/set-power-policy.ps1` | On a fresh host install |

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
- **Postmortem item 13** — full rebuild drill. Runbook section 4 has never been
  executed. Intended to be done for real during the SSD migration.
- **Monitoring blind spot** — Prometheus stores its TSDB on a Longhorn volume,
  so it cannot observe storage incidents. `EtcdDiskCriticallySlow` did not fire
  on 2026-09-25 because Prometheus was Pending throughout.
- **taskflow-api has no database schema.** The `daily-data` Velero schedule
  therefore backs up an empty database, and the restore procedure has never had
  data to restore.
- Empty placeholder docs: ADR-003 to ADR-005, `platform-architecture.md`,
  `roadmap.md`, `implementation-plan.md`, `interview-notes.md`. Fill or delete.
