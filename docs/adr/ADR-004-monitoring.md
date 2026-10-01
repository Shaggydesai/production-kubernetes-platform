# ADR-004: Monitoring, alerting and what counts as evidence

- **Status:** Accepted
- **Date:** 2026-09-30
- **Supersedes:** none

## Context

This platform has had three incidents. In every one of them, the component that
failed reported itself healthy, and the serious finding was not the fault but the
absence of a way to find out. Specifically:

- 2026-09-18: nothing said that no etcd backups existed, that Velero restores had
  never worked, or that etcd was unmonitored.
- 2026-09-25: the alert written for the exact failure stayed silent, and two
  pre-existing failures were found by running `kubectl get pods -A | grep -v
  Running` by hand.
- 2026-09-27: the right alerts existed and reached nobody, because an orphaned
  container held port 9100 and the Discord webhook had been revoked.

So the decisions below are less about tool choice than about what this platform
treats as evidence that something works. The tool choice took an afternoon; the
rest took three postmortems.

## Decision 1 — kube-prometheus-stack, not raw Prometheus

The bundle installs the Prometheus Operator, Prometheus, Alertmanager, Grafana,
node-exporter and kube-state-metrics together, and introduces the CRDs that make
scrape configuration declarative: `ServiceMonitor`, `PodMonitor`,
`PrometheusRule`.

The alternative — a hand-written `prometheus.yml` — means editing a central file
every time a component is added, which is the opposite of what ADR-002 argues
for. With the operator, a `ServiceMonitor` lives in the same wrapper chart as the
thing it scrapes and appears as a target when that chart syncs.

**Consequence:** the operator's selectors become a trap. See decision 2.

## Decision 2 — every ServiceMonitor and PrometheusRule carries `release: kube-prometheus-stack`

The `Prometheus` CR's `serviceMonitorSelector`, `podMonitorSelector` and
`ruleSelector` all require that label. A resource without it is **silently
ignored** — created successfully, visible in `kubectl get servicemonitor`,
reported Synced and Healthy by Argo CD, and never scraped.

```yaml
# every ServiceMonitor we write, and velero/values.yaml
metadata:
  labels:
    release: kube-prometheus-stack
```

**Evidence this matters.** MinIO ran from installation until 2026-09-30 with no
metrics at all. It was found by asking Prometheus what it actually held —
**1,879 metric names, 0 matching `minio_*`** — not by checking that the
ServiceMonitor existed, because it did exist and was correct in every respect
except the label.

**Consequence, recorded as a rule:** verify monitoring by querying the metric
names Prometheus holds, never by confirming the configuration object exists. The
`MinIOMetricsMissing` alert names this trap in its own description so the next
person does not have to rediscover it.

## Decision 3 — alert on the mechanism failing, not on the eventual consequence

When something can fail, you can alert on the mechanism that prevents the failure
or on the failure itself. The mechanism fires earlier and names the fix.

| Alert on | Not on |
|---|---|
| the defrag job not having succeeded in 14 days | etcd reaching its backend quota |
| `certmanager_certificate_ready_status == 0` | a certificate approaching expiry |
| the backup job failing | discovering at restore time that there is nothing to restore |
| `absent(up{job=...})` | the absence of application error metrics |
| the backup pull not happening | a restore failing because nothing left the host |
| Argo CD auto-sync being disabled | an app having silently stopped following Git |

The last row is worth its own note: disabling auto-sync is legitimate during
maintenance and dangerous when forgotten, so `ArgoAppAutoSyncDisabled` fires after
an hour. **Any safety mechanism that gets switched off as part of a normal
procedure needs a timer on it.** `platform-vault` lost its `automated` block
during the September recovery and nothing noticed for three days.

## Decision 4 — every monitored thing gets a paired `absent()` alert

A Prometheus expression over a series that does not exist returns nothing, and an
alert whose expression returns nothing is not firing. So `up{job="x"} == 0`
catches the scrape failing and cannot catch the ServiceMonitor being deleted —
there is then no `up` series for that job to be zero.

```yaml
- alert: TaskflowApiTargetDown
  expr: up{job="taskflow-api"} == 0
- alert: TaskflowApiMetricsMissing
  expr: absent(up{job="taskflow-api"})
```

Nine `...MetricsMissing` / `...MetricMissing` alerts exist for this reason. One
catches the thing being broken; the other catches the monitoring being broken.

Where a fixed number of targets is expected, the count is asserted too, because
`count(...) != 3` catches one target vanishing but returns no series when all
three vanish and therefore cannot fire in the worst case:

```yaml
expr: absent(up{job=~"minio-.*"}) or count(up{job=~"minio-.*"}) != 3
```

Three failure modes, three expressions, all needed to actually monitor one
component.

## Decision 5 — batch jobs report through the node-exporter textfile collector, in two files

Backups, defragmentation and the off-site mirror are systemd timers. They finish
and exit; there is nothing to scrape. node-exporter is configured to read
`*.prom` files from a host directory:

```yaml
prometheus-node-exporter:
  extraArgs:
    - '--collector.textfile.directory=/host/root/var/lib/node_exporter/textfile_collector'
```

Each job writes to a temporary name and `mv`s it, because `mv` within a
filesystem is atomic and node-exporter must never read a half-written file.

**The two-file part is the decision.** A staleness alert detects a job that has
stopped. It does not detect a job that runs, fails, and writes a success
timestamp anyway — which is exactly what `etcd-defrag.sh` did before 2026-09-28,
because a run that could not reach etcd read empty strings for the database
sizes, empty strings evaluate as 0 in shell arithmetic, that took the "nothing to
do" branch, and that branch wrote a fresh timestamp. The job failed weekly and
reported success weekly, and a 14-day staleness alert could never fire.

So:

- `<job>.prom` holds **only the last success**, and a failing run must never
  touch it. If a failure overwrote it, the age would reset and the staleness
  alert would go quiet precisely when it should fire.
- `<job>_run.prom` holds the outcome of the **most recent** run, written from a
  `trap ... EXIT` handler so that failure is the default and success has to be
  earned by reaching the last line of the script.

Each job therefore has three alerts: too old, run failed, metric absent.

## Decision 6 — control-plane metrics are exposed by flags recorded in the kubeadm config

`kube-controller-manager` and `kube-scheduler` bind to `127.0.0.1` by default and
etcd serves metrics only on localhost, so none of them are scrapeable as kubeadm
leaves them. The `control_plane_metrics` Ansible role edits the static pod
manifests to set `--bind-address=0.0.0.0` and `--listen-metrics-urls`.

Editing manifests in `/etc/kubernetes/manifests` is genuinely hazardous and the
role is written accordingly: `check_mode: true` on a detection pass to find which
files will change, backups written to a directory **outside** the watched folder
(a backup file inside it is started by the kubelet as a second etcd or
scheduler), `insertafter` anchored on a flag kubeadm always writes, and a wait on
`/readyz` afterwards because changing a manifest restarts the component.

Per ADR-006 decision 4, the equivalent tuning values also live in the kubeadm
config file, because `kubeadm upgrade apply` regenerates static pod manifests
from its stored configuration and would **silently discard** anything set only in
the manifests.

## Decision 7 — Alertmanager's configuration is rendered by External Secrets, not by chart values

```yaml
alertmanager:
  alertmanagerSpec:
    useExistingSecret: true
    configSecret: alertmanager-config
```

The Discord webhook URL is a credential, so it cannot be in Git. Alertmanager's
configuration is a single YAML file, so it cannot be half in Git and half from
Vault. Something has to assemble them, and that is the `template` block of
`vault-config/externalsecret-alertmanager-config.yaml`, with one substitution.

**This creates a trap that cannot be removed:** `useExistingSecret: true` makes
the operator ignore any `config:` key in the chart's values entirely. Not an
error — you can edit it, commit it, watch Argo CD sync it green, and nothing
changes. The only available defence is an eight-line comment at the top of the
block saying where the live config actually lives, and it is there.

**Consequences:** owning the whole config means reproducing the chart's default
inhibit rules by hand, which is done with a comment saying they are copies. And
routing changes appear on ESO's `refreshInterval` (1h), not on merge.

## Decision 8 — criticals re-notify hourly; warnings daily

```yaml
route:
  repeat_interval: 24h          # warnings
  routes:
    - receiver: discord
      matchers: ['severity = "critical"']
      repeat_interval: 1h
```

On 2026-09-29 `VeleroBackupTooOld` fired at critical for **23 hours** while the
application data had had no backup for three days. Every rule fired, routing
worked, and Alertmanager delivered **72 of 72** notifications with zero failures.
Nobody acted, because that critical arrived in the same stream as 38 warnings
that day.

This is the opposite of the 2026-09-27 finding and needs the opposite fix. That
one was missing instrumentation; this is surplus undifferentiated notification.
**Adding a fourth Velero rule would have made it worse.** The gap was triage, so
the fix is cadence.

**Consequence:** `severity` in this platform means "does this require action
now", not "how bad is it". An alert that fires for a known unfixable reason must
say so in its own description — `EtcdDiskCriticallySlow` states that the cause is
VMs on HDD and an accepted risk pending migration — because an alert with no
action attached trains people to ignore alerts.

**Still open:** postmortem action item 14 asks for two things and only one is
done. A periodic digest of what is *currently* firing is the stronger half,
because its absence is also informative and it answers the question a responder
actually has.

## Decision 9 — accepted: the monitoring stack shares fate with the cluster

Prometheus, Alertmanager, Grafana and Loki all run in this cluster on Longhorn
volumes on the same three nodes as everything else. A failure bad enough to
matter is likely to take them with it, and has:

- 2026-09-25: Prometheus `Pending` for most of the incident, so the alert aimed
  at that incident had no data to evaluate.
- 2026-09-26 to 28: Loki down for **two days** on a wedged `VolumeAttachment`
  finalizer — during the exact window its logs would have been most valuable.

One mitigation is implemented and it is the interesting one. Prometheus cannot
scrape the laptop that pulls backups off cp01, and the laptop must not be able to
write into the cluster. So **cp01 observes its own `sshd` log** for successful
`etcdpull` logins and exposes the timestamp as a textfile metric. The
observation moved to where it could be made and the security boundary stayed
intact. Generalised: *when you cannot instrument a component, instrument the
evidence it leaves behind.*

The two unimplemented mitigations are a dead-man's switch watching for the
absence of the `Watchdog` alert — which is currently routed to `null`, since
there is no external service to receive it — and moving the TSDB off Longhorn per
ADR-003 decision 7. The first is the cheapest remaining improvement to this
platform.

## Decision 10 — alert rules are checked by `promtool` in CI

400 lines of hand-written PromQL live in `additionalPrometheusRulesMap` in a Helm
values file, and were previously validated by nothing but a YAML round-trip,
which cannot catch a bad expression. CI now renders the chart, extracts every
`PrometheusRule`, and runs `promtool check rules` — with a guard asserting that
at least one rule was extracted, because an extraction that silently returns
nothing would report success forever.

Two further CI invariants exist because two facts live in files that cannot be
merged: the bucket list in `MinIOUndeclaredBucket`'s regex must equal
`bucketProvisioning.buckets` in the MinIO chart, **and** every declared bucket
must be covered by an `absent()` alert — so a second bucket cannot be declared
without gaining the same protection as the first.

**Consequence:** `promtool` proves an expression parses. It does not prove it can
ever return a result. The habit that covers that is to invert a rule and confirm
the inverted form fires; if both are quiet, the series does not exist and the
alert is decorative.

## Consequences

- Retention is 7 days for both Prometheus and Loki, matched deliberately so a
  metric spike and the logs from the same minute are both still there.
- Adding a component means adding a ServiceMonitor with the release label, a
  `...TargetDown` alert, a `...MetricsMissing` alert, and — if it is a batch job
  — two `.prom` files and three alerts. This is heavier than it looks and is
  proportional to how much of this platform's history is components failing
  quietly.
- The alerting pipeline is verified end to end by counting delivered
  notifications, not by validating rules. The record of that is "33 Discord
  notifications, 1 failure" in the 2026-09-27 action items.
- Two structural weaknesses remain: no dead-man's switch, and monitoring on the
  storage it monitors.

## Related

- `docs/adr/ADR-003-storage.md` — decision 7, the TSDB on Longhorn
- `docs/adr/ADR-005-secrets.md` — decision 6, why the Alertmanager config is an ExternalSecret
- `docs/adr/ADR-006-bootstrap.md` — decision 4, tuning that survives an upgrade
- `docs/incidents/2026-09-25-host-sleep.md` — the alert that could not fire
- `docs/incidents/2026-09-27-unclean-shutdown-corruption.md` — §7.1, both ends of the pipeline broken
- `docs/runbooks/lab-startup-shutdown.md` — read what is firing before anything else
