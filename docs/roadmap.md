# Roadmap

What is left, ordered by how much it reduces the chance of an undetected failure
rather than by how interesting it is.

Every item below is traceable to a postmortem action item, an accepted risk in
`docs/PROJECT_STATE.md`, or an ADR that records its own decision as one to
reverse. Nothing here is aspirational feature work — this platform's history is
components failing quietly, and the list is ordered accordingly.

**Last reviewed:** 2026-09-30

---

## Now — closes a hole through which a failure has already passed undetected

### 1. A dead-man's switch

The cheapest remaining improvement, and it addresses the worst class of failure
this platform has had.

`kube-prometheus-stack` makes a `Watchdog` alert fire permanently by design, so
that an external service can notice the *absence* of notifications and conclude
your monitoring is dead. This platform routes it to `null`, because there is no
external service to receive it.

On 2026-09-27 the right alerts existed, the metrics were correct, the `.prom`
files on disk were correct — and **both ends of the pipeline were broken at once**:
an orphaned container held `hostNetwork` port 9100 so nothing was scraped, and
Alertmanager's Discord webhook came from the wrong Vault path and served a revoked
URL. Nothing arrived, and nothing could have told anyone that nothing was
arriving.

A free Healthchecks.io or Better Stack heartbeat URL, an Alertmanager receiver
pointed at it for `alertname=Watchdog`, and a 15-minute grace period closes it.

- **Source:** `docs/incidents/2026-09-27-unclean-shutdown-corruption.md` §7.1;
  ADR-004 decision 9
- **Effort:** an hour
- **Blocked on:** nothing

### 2. Move item #50 off GitHub's scheduler

The daily image-availability check is the one thing that asks "is this platform
still rebuildable", and it has **never run on `event=schedule`**. One recorded run
returns zero bytes with exit code 0, so the only evidence it ever passed is a chat
transcript.

Scheduled GitHub Actions workflows are best-effort, are disabled automatically on
repositories without recent activity, and their logs expire. The check whose whole
purpose is to notice silent decay is decaying silently.

Move it to the pattern this repo already uses three times: a systemd timer on
cp01, a last-run status and timestamp written to the node-exporter textfile
collector, and a staleness alert plus an `absent()` companion.

- **Source:** open finding #50
- **Effort:** half a day
- **Blocked on:** nothing

### 3. Prometheus's TSDB off Longhorn

`EtcdDiskCriticallySlow` was written the day before the incident it was aimed at
and stayed silent through a 1,341 ms WAL fsync and 47 control-plane restarts,
because Prometheus's pod was `Pending` waiting for its own Longhorn volume.

Monitoring stored on the storage layer it monitors cannot report on that layer.
This is structural, not a threshold to tune — shortening `for: 10m` to `5m` helps
marginally and does not address the pod being Pending.

Use a `local-path` volume pinned to one node. Losing that node loses metrics
history; metrics history is the least valuable data in the cluster and the
ability to observe an incident while it happens is the most.

- **Source:** `docs/incidents/2026-09-25-host-sleep.md` action item 7; ADR-003
  decision 7
- **Effort:** half a day
- **Blocked on:** nothing

### 4. Alert on stale `VolumeAttachment` objects

Loki's `VolumeAttachment` wedged on its `external-attacher` finalizer on
2026-09-26 and was not noticed for **two days** — during precisely the window its
logs would have explained what was happening.

- **Source:** `docs/incidents/2026-09-27-unclean-shutdown-corruption.md` action item 9
- **Effort:** an hour
- **Blocked on:** nothing

### 5. Grafana dashboards as ConfigMaps

Dashboards created in the UI live in Grafana's Longhorn volume. They are not in
Git, not in any backup, and do not survive a rebuild. The chart's sidecar loads
ConfigMaps carrying the `grafana_dashboard` label.

- **Source:** ADR-003 decision 8
- **Effort:** an afternoon, plus however long the dashboards took to build
- **Blocked on:** nothing

---

## Next — needs the hardware migration

These resolve together and are the reason four accepted risks exist. Every
corruption event in this platform's history traces to the host, not to the
software.

### 6. Complete the KVM migration

Four corruption events, all following an unclean host reset, on media with clean
SMART. bbolt is engineered to survive power loss; two independent programs using
it were damaged by one event, which indicts the layer beneath both of them —
**the host does not honour guest fsync across an abrupt reset.**

The migration carries five changes at once, and the Terraform in
`infrastructure/terraform/` already describes all of them:

| From | To | Fixes |
|---|---|---|
| VMware Workstation | KVM / libvirt | the fsync chain |
| 5400 rpm SSHD | NVMe | 1,341 ms fsync p99 under load |
| emulated e1000 | virtio | three Tx unit hangs in five days |
| DHCP leases | static addresses from Git | a PKI pinned to a lease |
| hand-built + Ansible | `make up` | a rebuild that is a routine |

- **Source:** `docs/incidents/2026-09-27-unclean-shutdown-corruption.md` action
  item 6; ADR-006; accepted risks 12, 14
- **Blocked on:** the replacement NVMe

### 7. Execute the rebuild drill, and time it

`docs/runbooks/rebuild.md` exists and has never been run end to end. Until it
has, it is a draft — the same standard this platform applies to backups.

The Terraform is in the same position and it is worth being explicit about it:
`terraform init` has run (the provider is pinned at 0.8.3 in a committed lock
file) and `terraform apply` never has. `fmt`, `validate` and a templatefile render
assertion now run in CI on every change, which is the most that can be checked
without a host. It is not the same as having built something.

- **Source:** `docs/incidents/2026-09-25-host-sleep.md` action item 13
- **Blocked on:** #6

### 8. Revisit the leader-election tuning

```yaml
leader_elect_lease_duration: "60s"   # defaults: 15s
leader_elect_renew_deadline: "40s"   #           10s
leader_elect_retry_period:  "5s"     #            2s
```

These exist because etcd on the HDD showed 1,341 ms fsync p99 and the control
plane was losing its lease. On an NVMe they should be **revisited, not
inherited**: measure `etcd_disk_wal_fsync_duration_seconds` first, then lower them
back toward the defaults if the disk allows.

A workaround without an expiry condition becomes permanent by default. This one
has its condition written next to it in `group_vars/all.example.yml`.

- **Source:** ADR-006 decision 4
- **Blocked on:** #6

### 9. Power and update policy as code

Windows Update rebooted the host with all three guests running on 2026-09-28,
causing the second of two corruptions that week. `NoAutoRebootWithLoggedOnUsers=1`
is set; active hours and the power policy are not in
`infrastructure/laptop/set-power-policy.ps1`. Power policy and update policy
belong in the same script.

Moot if the host becomes Linux, which is why it sits here rather than above.

- **Source:** 2026-09-27 action item 5; 2026-09-25 action items 3 and 4
- **Blocked on:** whether the new host runs Windows at all

---

## Later — real improvements, no failure waiting behind them

### 10. Structured logging in the application

`chimiddleware.Logger` and `log.Printf` produce human-readable lines with no
machine-readable structure. You can `|= "error"` them; you cannot ask for
`status>=500 and duration>1s`, because those are not fields.

`log/slog` with a JSON handler is three lines and makes every field queryable
without touching Loki's configuration.

- **Effort:** an hour

### 11. Argo CD Image Updater with `write-back-method: argocd`

CI currently opens a pull request to bump the image tag, which requires a GitHub
App private key so that the PR triggers the required status check. Image Updater
with `write-back-method: argocd` needs no Git write at all, which eliminates the
credential rather than protecting it.

- **Source:** the comment in `.github/workflows/taskflow-api-ci.yml`
- **Effort:** a day

### 12. Switch `job-create-bucket.yaml` to `mc`

The Job uses `amazon/aws-cli` because `quay.io/minio/mc` returns 401. The `mc`
binary does ship inside the MinIO server image already mirrored to GHCR. Not
urgent: the aws-cli path is proven working.

- **Source:** open finding #46
- **Effort:** an hour

### 13. A digest of what is currently firing

Postmortem action item 14 asked for two things. Routing criticals distinctly is
done. A periodic summary — "3 firing: 1 critical, 2 warning" — is the stronger
half, because its absence is also informative and it answers the question a
responder actually has, which is not "what fired today" but "what is broken now".

- **Source:** 2026-09-27 action item 14
- **Effort:** half a day

### 14. Vault audit device

The audit trail exists as a capability and nothing is recording it. An
`admin.hcl` policy with `sudo` on `path "*"` deserves a log of what it did.

- **Source:** ADR-005 consequences
- **Effort:** an hour

### 15. Pin the application's base images by digest

`golang:1-alpine` and `alpine:3.20` are tags, not digests, so two builds months
apart can use different bytes. The build stage matters less — the output is a
static binary the tests verify — but the runtime base is in the shipped image.

- **Source:** the pattern established for Helm charts and the Ubuntu cloud image
- **Effort:** an hour, and a decision about how often to bump

---

## Accepted, not scheduled

Recorded so that the distinction between a risk that has been decided and a risk
nobody has noticed stays visible.

| Risk | Why it is accepted |
|---|---|
| Single control-plane node, no etcd quorum | A second control plane needs a load balancer this design does not provide, and a second physical host to be worth anything. Compensated with tested backups. |
| The age private key in three places, one on paper | Accepted risk 15. Two verified copies plus paper is a tradeoff, not a solved problem. |
| Static secrets only, no leases or dynamic credentials | Correct amount of machinery for a lab. The obvious first change if this were real. |
| No RWX volumes | Nothing needs shared write access. |
| Stateful components take downtime on upgrade | A consequence of RWO, not worth engineering around at this size. |
| Monitoring data not backed up | Seven days of lab metrics is not worth the cost. Dashboards are the exception and are item #5. |

---

## How to use this file

An item moves out of "Now" only when there is evidence it works — a delivered
notification counted, a metric appearing in Prometheus, a restore that produced
rows. Not when the configuration exists.

That standard is the whole of `docs/adr/` and every postmortem in
`docs/incidents/`, and it is the reason this list is short.
