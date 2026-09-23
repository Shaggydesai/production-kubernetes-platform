# Runbook: rotating a secret

**Principle:** a secret usually lives in more than one place. Rotating it means
changing **every** copy plus the system that validates it, in the right order.
Miss one and something crashes (this is how `taskflow-api` went into
CrashLoopBackOff on 23 Sep 2026).

Where copies live in this platform:
Vault (source of truth)
└─ ExternalSecret → Kubernetes Secret ──> pod env vars (read ONCE at startup)
└─ a second ExternalSecret may read the SAME Vault key
└─ the system itself (Postgres role, MinIO user, Grafana user, Discord webhook) 


---

## 1. Find every consumer first

```bash
# which pods mount which secret keys
kubectl get pods -A -o json | jq -r '.items[] | .metadata.namespace + "/" + .metadata.name as $p
  | .spec.containers[].env[]? | select(.valueFrom.secretKeyRef)
  | $p + "  " + .valueFrom.secretKeyRef.name + "/" + .valueFrom.secretKeyRef.key' | sort -u

# which ExternalSecrets read a given Vault key (e.g. "postgresql")
kubectl get externalsecret -A -o json | jq -r '.items[] | .metadata.namespace + "/" + .metadata.name as $e
  | .spec.data[]? | select(.remoteRef.key=="postgresql")
  | $e + "  <- secret/" + .remoteRef.key + "#" + .remoteRef.property'
```

## 2. The procedure

1. **List the consumers** (step 1). Write them down.
2. **Capture the old value** into a shell variable if you need it to authenticate
   for the change: `OLD=$(kubectl -n <ns> get secret <name> -o jsonpath='{.data.<key>}' | base64 -d)`
3. **Generate and write the new value in Vault**, so it never appears on screen:
```bash
   kubectl exec -it vault-0 -n vault -- sh -c '
   vault login -method=userpass username=sagar >/dev/null
   NEW=$(vault write -f -field=random_bytes sys/tools/random/20 format=base64)
   vault kv put secret/<path> <key>="$NEW" >/dev/null && echo written
   rm -f ~/.vault-token'
```
   The `vault-configure` Job **cannot** do this: its policy is create-only, by design.
4. **Force-sync every ExternalSecret** that reads that key (they refresh hourly otherwise):
   `kubectl -n <ns> annotate externalsecret <name> force-sync=$(date +%s) --overwrite`
5. **Confirm the Kubernetes Secrets changed** before touching the system:
   compare the new value against the old one; if it hasn't propagated, stop.
6. **Change the system itself** (see the table below).
7. **Restart every consumer.** Environment variables are read once at startup:
   `kubectl -n <ns> delete pod -l <selector>` (prefer this over `rollout restart`,
   which Argo CD may revert).
8. **Verify** each consumer: logs, a real login, the app's health endpoint.
9. **Destroy the old Vault versions** so the leaked value can't be read back:
   `vault kv destroy -versions=<n,...> secret/<path>`

---

## 3. Per-secret notes

| Secret | Vault path | Derived Kubernetes Secrets | Changing the system | Restart |
|---|---|---|---|---|
| Postgres admin + app | `secret/postgresql` | `default/postgresql-credentials` (ES `postgresql-secret`), `default/taskflow-api-credentials#db-password` (ES `taskflow-api-secret`) | `ALTER USER postgres/taskflow WITH PASSWORD ...` via `psql`, using the **old** admin password | `postgresql-0`, then all `taskflow-api` pods |
| Grafana admin | `secret/grafana` | `monitoring/grafana-admin-credentials` | Grafana only applies the password on **first** start. For an existing install: `kubectl -n monitoring exec deploy/kube-prometheus-stack-grafana -c grafana -- grafana cli admin reset-admin-password <new>` | Grafana pod |
| MinIO root | `secret/minio` | `minio/minio-credentials` | MinIO reads root credentials from its env | MinIO pod. **Then rotate `secret/velero` too**, it embeds these credentials |
| Velero → MinIO | `secret/velero` (field `cloud`) | `velero/velero-credentials` | derived from `secret/minio`; rewrite the `[default]` credentials block | Velero deployment + node-agent DaemonSet |
| taskflow JWT signing key | `secret/taskflow-api#jwt-secret` | `default/taskflow-api-credentials` | none — but **every issued token becomes invalid**, so users must log in again | taskflow-api pods |
| Discord webhook | `secret/alertmanager#discord-webhook-url` | `monitoring/alertmanager-config` (whole config built by the ES template) | Delete the webhook in Discord, create a new one | Alertmanager reloads automatically; check `Reconciled=True` |
| Argo CD Redis | not in Vault | chart-managed | n/a | n/a |

---

## 4. Traps

- **ExternalSecrets refresh hourly.** Without `force-sync`, the Kubernetes Secret
  keeps the old value for up to an hour.
- **Two ExternalSecrets can read the same Vault key.** Sync both. This is the one
  that bit us.
- **Env vars are read once.** A pod keeps the old value until it restarts; secrets
  mounted as files update on their own, but the application may still cache them.
- **Never echo a secret.** Use `read -rsp` for input, and pipe values through
  stdin instead of putting them in command arguments (they show up in the process
  list and in shell history).
- **Vault keeps old versions.** Destroy the versions holding a leaked value.
- **If a value leaked publicly** (a chat log, a screenshot, a commit), treat it as
  compromised: rotate it, don't just hide it.

## 5. Worked example: PostgreSQL, 23 Sep 2026

Vault write → sync `postgresql-secret` → `ALTER USER` for both roles → restart
`postgresql-0` and `taskflow-api`. The app then crash-looped with
`password authentication failed for user "taskflow"` because
`taskflow-api-credentials` comes from a **separate** ExternalSecret that was
never synced. Fix: sync `taskflow-api-secret`, confirm both Secrets match,
restart the app. Total disruption: about 6 minutes for the app, none for Postgres.
