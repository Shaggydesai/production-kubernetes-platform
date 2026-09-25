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

## Rotating the age backup identity

This identity decrypts every etcd and Velero off-site archive. Only the **public**
recipient belongs in Git (`roles/etcd_backup/files/recipient.txt`). The private key
lives in a password manager and on paper — never on the node, never in terminal
output.

Rotate when the key is exposed, or annually.

1. **Generate.** `age-keygen -o ~/age-new.txt` writes the identity and prints only
   the public key to stderr. `age-keygen -y <file>` re-derives the public half later.
2. **Store the private key before anything else.** Open it in an editor and copy it
   into the password manager; write the `AGE-SECRET-KEY-1` line on paper. Do not
   `cat` it — terminal echo is exactly how the 2026-09-25 exposure happened.
3. **Replace the recipient.** Both `etcd-backup.sh` and `velero-offsite.sh` read
   `/etc/etcd-backup/recipient.txt`, so one file change rotates both. Merge by PR,
   then run `ansible-playbook playbooks/hosts.yml --limit control_plane -K`.
   Expect exactly one changed task.
4. **Prove it.** Trigger `etcd-backup.service` and `velero-offsite.service`, pull to
   the laptop, and decrypt the newest archive with the new key. Check the filename —
   testing an older archive proves nothing.
5. **Clear the old ciphertext.** Re-encrypt the retained archives, or delete them:
   the 6-hourly timer rebuilds four generations within a day. Do it on the node, the
   laptop and the off-site copy — the exposed key matters only while files it opens
   still exist.
6. **Destroy the retired identity** everywhere.

## Inspecting secrets without leaking them

Never pipe a secret to the terminal. Redact in the pipeline:

```bash
kubectl -n <ns> get secret <name> -o jsonpath='{.data.<key>}' | base64 -d \
  | sed -E 's#(https://discord(app)?\.com/api/webhooks/[0-9]+/)[A-Za-z0-9_.-]+#\1REDACTED#g'
```

Terminal output ends up in transcripts, tickets and screenshots. Redact at the
source, because you cannot un-share a credential — you can only rotate it.

## Discord webhook (Alertmanager)

Rotated 2026-09-25 after the URL was echoed to a terminal. Any webhook URL that
has appeared on a screen, in a chat, or in shell history is burned.

### Find the real Vault path first

The ExternalSecret is the authority on where the value lives. Read it before
writing anything to Vault:

    kubectl -n monitoring get externalsecret alertmanager-config -o yaml \
      | sed -n '/^spec:/,/^status:/p'

As of 2026-09-25 it reads:

    remoteRef:
      key: alertmanager            # -> secret/alertmanager
      property: discord-webhook-url
    secretKey: webhookUrl          # -> {{ .webhookUrl }} in the target template

On 2026-09-25 this step was skipped and the new URL went to `secret/discord`
with key `webhookUrl`. ESO kept reporting `Ready=True SecretSynced` the whole
time, because it was still reading the old path correctly. The only signal that
anything was wrong was the target secret's hash not changing. A `version 1` in
the `vault kv` output is the same tell: it means you just created a new path.

### Rotate

1. Discord: Server Settings -> Integrations -> Webhooks -> **delete** the old
   webhook, then create a new one on the same channel and copy its URL.
   Deleting first is what actually revokes the old URL; creating a second
   webhook alongside it leaves the burned one live.

2. Record the before-state hash:

       kubectl -n monitoring get secret alertmanager-config \
         -o jsonpath='{.data}' | sha256sum

3. Write it to Vault with `kv patch`, **never** `kv put`. KV v2 stores one JSON
   document per path, so `put` silently deletes every other property at
   `secret/alertmanager`. `-method=rw` is the fallback for policies that grant
   `update` but not `patch`.

   Write the block to a file and run it; pasting a multi-line quoted block
   straight into the prompt gets mangled.

       cat > /tmp/rot-am.sh <<'SH'
       set -eu
       read -rsp 'Vault username: ' VU; echo
       read -rsp 'Vault password: ' VP; echo
       read -rsp 'New webhook URL: ' WH; echo

       printf '%s\n%s\n%s\n' "$VU" "$VP" "$WH" \
         | kubectl -n vault exec -i vault-0 -- sh -c '
         read -r VU; read -r VP; read -r WH
         export VAULT_ADDR=http://127.0.0.1:8200
         VAULT_TOKEN=$(vault login -token-only -method=userpass \
           username="$VU" password="$VP") || exit 1
         export VAULT_TOKEN
         if ! printf "%s" "$WH" \
           | vault kv patch secret/alertmanager discord-webhook-url=-; then
           printf "%s" "$WH" \
             | vault kv patch -method=rw secret/alertmanager \
                 discord-webhook-url=- || exit 1
         fi
         vault token revoke -self >/dev/null 2>&1
       '
       unset VU VP WH
       SH
       bash /tmp/rot-am.sh; rm -f /tmp/rot-am.sh

   `read -rsp` keeps all three values off the screen and out of history. The
   `=-` makes Vault read the value from stdin, so it never appears in the pod's
   argv. The self-revoke kills the login token when the command ends.

4. Force the resync and confirm the hash *changed*:

       kubectl -n monitoring annotate externalsecret alertmanager-config \
         force-sync="$(date +%s)" --overwrite
       sleep 20
       kubectl -n monitoring get secret alertmanager-config \
         -o jsonpath='{.data}' | sha256sum

   Allow up to ~60s. If the hash is unchanged, stop and re-read the
   ExternalSecret; do not assume it will catch up.

### Verify

    AM=alertmanager-kube-prometheus-stack-alertmanager-0

    # config-reloader must log "Reload triggered" after the secret changed
    kubectl -n monitoring logs $AM -c config-reloader --tail=20

    # before/after the probe: total must increment, failed must stay 0
    kubectl -n monitoring exec $AM -c alertmanager -- sh -c \
      'wget -qO- http://localhost:9093/metrics | grep notifications | grep discord'

    kubectl -n monitoring exec $AM -c alertmanager -- amtool alert add \
      alertname=RotationProbe severity=warning \
      --annotation='summary="rotation probe"' \
      --alertmanager.url=http://localhost:9093

Use `severity=warning` or higher. The route sends `severity = "info"` to the
`null` receiver, so an info-severity probe is dropped by design and looks
exactly like a broken webhook.

Use a fresh `alertname` for each probe. Reusing one folds it into the existing
group, where `group_interval: 5m` suppresses the notification.

Alertmanager logs notification *failures* only, so an empty log is the expected
result on success. `notifications_failed_total{integration="discord",
reason="clientError"}` is what a dead or wrong webhook produces (Discord
answers 401/404).

Finish by looking at the Discord channel. The metrics prove Discord's API
returned 2xx; only your eyes prove it landed in the right channel.

**Never print the webhook value to verify it.** Compare hashes.
