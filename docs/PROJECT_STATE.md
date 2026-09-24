# Project state

Living summary of what exists, why, and what is deliberately deferred.
Detailed procedures live in `docs/runbooks/`; incidents in `docs/incidents/`.

## Conventions

### Helm chart dependencies

Upstream chart dependencies are **vendored** into each wrapper chart's
`charts/` directory and committed — all 13 platform charts follow this.
The platform is therefore rebuildable from Git alone, with the exact chart
bytes that were tested, independent of upstream repo availability.

To bump a chart: edit `Chart.yaml`, run `helm dependency update` in that
directory, then commit the new `.tgz` and `Chart.lock` together and remove
the old `.tgz`. `.gitattributes` marks `*.tgz` binary so diffs stay readable.

### Alertmanager configuration

`alertmanagerSpec.useExistingSecret: true` means the operator ignores any
`config:` key in the chart values. The live `alertmanager.yaml` is rendered
by the ExternalSecret at
`kubernetes/platform/vault-config/externalsecret-alertmanager-config.yaml`.

## Accepted risks

| # | Risk | Mitigation | Revisit |
|---|------|-----------|---------|
| 12 | Single-member control plane | Verified 6-hourly encrypted etcd backups, off-site copy | Not fixable on one laptop |
| 14 | etcd on HDD; WAL fsync degrades badly under load | `lab:etcd_wal_fsync_p99` trending, `EtcdDiskCriticallySlow` alert | SSD migration |

## Open

- Postmortem item 13: full rebuild drill (runbook section 4 untested)
- `main` is stale; all Argo apps track `feature/ubuntu-template`
- `taskflow-api` + Postgres still in the `default` namespace
