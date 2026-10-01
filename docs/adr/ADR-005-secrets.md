# ADR-005: Secrets with Vault and External Secrets Operator

- **Status:** Accepted
- **Date:** 2026-09-30
- **Supersedes:** none

## Context

GitOps has one hole in it. If the cluster's desired state is a Git repository,
and some of that state is a database password, then either the password is in Git
or something has to fetch it at reconcile time.

This platform has eight secrets: the PostgreSQL credentials, the taskflow
application's DB password and JWT secret, Grafana's admin login, MinIO's root
credentials, Velero's copy of those, the GHCR pull token, and the Alertmanager
Discord webhook. None of them are in Git. Plus two pieces of key material that
are not in Vault either, because they are what protects Vault and the backups.

The decisions below were mostly made during recovery from the 2026-09-18
incident, whose action items 8 and 9 were "remove the Vault root token from the
cluster" and "rotate credentials exposed during the incident".

## Decision 1 — Vault is the source of truth; External Secrets renders Kubernetes Secrets

```
Vault (secret/<path>)
  └─ ClusterSecretStore "vault-backend"  (Kubernetes auth)
      └─ ExternalSecret  → Kubernetes Secret → pod env var
```

The rejected alternatives, and why:

**SOPS or sealed-secrets** put an encrypted value in Git. That is a real and
simpler design, and its weakness is that rotation means a commit, the ciphertext
history is permanent, and the decryption key has to be in the cluster for the
controller to use it. It also has no audit trail of reads.

**Vault Agent Injector** mounts secrets as files via a sidecar. It gives lease
renewal and dynamic credentials, and it means every workload carries a sidecar
and the secret never becomes a Kubernetes `Secret` — which most charts, including
every one used here, expect.

ESO was chosen because it produces an ordinary `Secret` that any chart can
consume by name, keeps the value out of Git, and keeps the workload unaware that
Vault exists.

**Consequence:** the Secret is a real Kubernetes object, so anyone with `get
secrets` in the namespace can read it. ESO moves the boundary; it does not remove
it.

## Decision 2 — Vault runs in the cluster, on Raft, sealed by Shamir shares that never enter it

Vault is a StatefulSet with the Raft integrated storage backend on a Longhorn
volume. It is initialised once, by hand, and prints five unseal shares exactly
once. Three are needed to unseal.

**Nothing in the cluster holds them.** They are in a password manager. `make up`
stops at this point deliberately, and the Makefile says why:

> a pipeline that generates unseal shares and then stores them somewhere it can
> read them again has produced encryption with the key taped to the box.

**Consequence, and it is a large one:** Vault comes back **sealed** after every
restart, and nothing that needs a rendered Secret starts until a human unseals
it. This is the single most important fact about recovering this platform, and it
is why the recovery order is fixed:

1. **Vault** — unseal, 3 of 5
2. **External Secrets Operator** — so it can render
3. **Postgres** — and everything else

That ordering was proved by the 2026-09-26 restore drill and was correct on both
2026-09-27 restores. Without it you get `CreateContainerConfigError` and
`Error: secret "postgresql-credentials" not found`, which gives no hint that the
answer is to go and unseal Vault.

## Decision 3 — no root token; Kubernetes auth for machines, userpass for the human

The root token was revoked as action item 8 of the 2026-09-18 postmortem.

**The `vault-configure` Job** authenticates with Kubernetes auth as
`vault/vault-configurator` and holds a deliberately narrow policy:

```hcl
# may configure the auth mount and the ESO role, but NOT its own policy or role
path "auth/kubernetes/config"                         { capabilities = ["create","read","update"] }
path "auth/kubernetes/role/external-secrets-role"     { capabilities = ["create","read","update"] }
path "sys/policies/acl/external-secrets-policy"       { capabilities = ["create","read","update"] }

# seeding: existence checks via metadata only - no values
path "secret/metadata/*"  { capabilities = ["read"] }
path "secret/data/*"      { capabilities = ["create"] }
path "secret/data/minio"  { capabilities = ["create","read"] }
path "sys/tools/random/*" { capabilities = ["update"] }
```

Two properties are doing real work. It cannot edit its own policy or role, so it
cannot escalate. And it has **`create` but not `update`** on `secret/data/*` — in
KV v2, `create` cannot overwrite existing data, so a re-run of the Job can seed a
missing secret and can never clobber a live one. Existence is checked through
`secret/metadata/*`, which returns versions and timestamps but no values.

**Consequence:** the Job cannot rotate anything. That is intentional and is why
step 3 of `docs/runbooks/secret-rotation.md` is done by a human as the admin
identity.

**The human** logs in with `vault login -method=userpass username=sagar` against
a broad policy. Broad on purpose — but unlike a root token it is tied to an
identity in the audit trail, it expires, and it can be revoked. If the admin
login is lost, `vault operator generate-root` with three unseal shares is the way
back in.

## Decision 4 — secrets are generated inside Vault and never appear on a terminal

```bash
kubectl exec -it vault-0 -n vault -- sh -c '
vault login -method=userpass username=sagar >/dev/null
NEW=$(vault write -f -field=random_bytes sys/tools/random/20 format=base64)
vault kv put secret/<path> <key>="$NEW" >/dev/null && echo written
rm -f ~/.vault-token'
```

The value is generated by Vault, assigned to a shell variable inside the pod, and
written back without being printed. The cached token is removed at the end.

The same discipline applies everywhere a credential is handled in this repo:
passwords go in on **stdin** and never as command-line arguments, because
arguments are visible in `ps` to every user on the box; Ansible tasks that handle
bootstrap tokens carry `no_log: true`, with the failure message explaining how to
debug without it; and verification is done by **comparing hashes**, never by
printing values.

**Consequence:** a generated password contains characters that break a
hand-built URL — `/`, `+`, `@`, `:` all appear in base64 output. The application
handles this in two places for two reasons: `internal/db` sets discrete
connection fields and never assembles a string, and `internal/migrate` builds its
DSN with `net/url` because `golang-migrate` accepts only a string. This is a
platform decision landing on application code.

## Decision 5 — KV v2 version history is capped, and old versions are destroyed on rotation

KV v2 keeps history. A "rotated" secret whose previous versions are still
readable has not been rotated — anyone with read access can fetch version 3.

Two mechanisms:

- `vault kv destroy -versions=<n,...>` on rotation. **`kv delete` is not
  enough:** a soft delete is reversible with `kv undelete` and the value remains
  recoverable. Only `destroy` removes the data.
- `max-versions` set on every path, so history cannot accumulate silently again.

**Evidence this matters.** A rotation completed in September left **17 readable
historical versions** across several paths, including four distinct Discord
webhook URLs of which one was live. It was found by surveying every path's
metadata rather than by trusting that the rotation had finished. Notably,
`max_versions` was confirmed by experiment to apply only to *future* writes — it
does not retroactively prune existing versions — so capping and destroying are
both required.

**Consequence:** `docs/runbooks/secret-rotation.md` gained a tenth step,
"confirm no readable history remains", because the rotation is not finished until
that has been checked. Verifying the effect, not the action.

## Decision 6 — one secret is a whole config file, assembled by an ExternalSecret template

Alertmanager's Discord webhook cannot be in Git, and Alertmanager's
configuration is one YAML file. So the entire routing tree lives in the
`template` block of `vault-config/externalsecret-alertmanager-config.yaml`, with
`{{ .webhookUrl }}` as the single substitution, and
`useExistingSecret: true` makes the operator use that Secret verbatim.

See ADR-004 decision 7 for the trap this creates. Two consequences belong here:

**ESO's own templating collides with Helm's.** An ExternalSecret placed inside a
Helm chart's `templates/` has its `{{ .username }}` consumed by Helm before ESO
ever sees it. The result renders green and produces a Secret that authenticates
as nobody. The fix is to wrap the literal in a raw string, and CI asserts that
`{{ .username }}` survives into the rendered output of the MinIO chart —
verifying the effect rather than the source.

**Changes arrive on the refresh interval.** `refreshInterval: 1h`, so Argo CD
syncs the ExternalSecret immediately and ESO decides when to re-render.
`kubectl annotate externalsecret <name> force-sync=$(date +%s) --overwrite`
forces it.

## Decision 7 — sync waves order the secret pipeline, and pods read env vars once

```
-2  ClusterSecretStore
-1  ExternalSecret
 0  migration Job
 1  Deployment
```

Without the ordering, a first install races: the ExternalSecret reconciles before
the store exists, fails, and retries — noisy but self-correcting, which is the
best kind of ordering bug. The Job/Deployment ordering matters more, and ADR-002
covers why it is a wave rather than a PreSync hook.

**Consequence:** environment variables are read **once, at startup**. Updating a
Secret changes nothing in a running pod, which is why step 7 of the rotation
runbook restarts every consumer, and why it says to `delete pod -l <selector>`
rather than `rollout restart`, which Argo CD may revert.

## Decision 8 — two secrets live outside Vault, on purpose

**The age backup key.** Every etcd bundle and every off-site Velero snapshot is
encrypted to one age public key. The private half is not in Vault — Vault's own
data is inside those backups, so a key stored there could not decrypt the backup
you need in order to get Vault back. It lives in three places in three failure
domains: a file on the laptop, a password manager entry, and a paper copy. The
cluster holds only the public half, committed as
`roles/etcd_backup/files/recipient.txt`, which is why a compromised control-plane
node cannot read its own backup history.

The audit that established this did not check by looking for the files. It
derived the public half from each copy with `age-keygen -y` (which only ever
emits the public key and is safe to run), compared hashes against the committed
recipient, confirmed the deployed recipient matched, **decrypted a real archive
and listed its contents** — because deriving the same public key proves the key
pair is right and only a decrypt proves the archive is readable — then found a
leftover working copy of the private key in a home directory and `shred -u`'d it.

The outcome was recorded as **accepted risk 15**, not as "resolved", because two
verified copies plus paper is a decision about a tradeoff rather than the
elimination of a problem.

**The Vault unseal shares**, per decision 2. Three of five are needed and none
are in the cluster. Losing them loses Vault's data regardless of how many volume
backups exist.

**Consequence:** a restore requires copying the age private key onto the node
temporarily, and the runbook ends that step with `shred -u`. The key's absence is
a security property, so restoring it is a deliberate, reversed, cleaned-up
action.

## Decision 9 — rotation is a procedure, because a secret has more than one copy

```
Vault (source of truth)
└─ ExternalSecret → Kubernetes Secret ──> pod env vars (read ONCE at startup)
└─ a second ExternalSecret may read the SAME Vault key
└─ the system itself (Postgres role, MinIO user, Grafana user, Discord webhook)
```

Rotating means changing every copy plus the system that validates it, **in the
right order**. Miss one and something crashes — which is how `taskflow-api` went
into CrashLoopBackOff on 2026-09-23.

So the runbook begins by enumerating consumers with two `jq` queries rather than
assuming they are known, has an explicit **stop** condition in the middle (step
5: if the Kubernetes Secret has not changed, do not touch the system), and ends
by verifying the *goal* rather than confirming the steps ran.

## Consequences

- No secret is in Git, and the repository can be public.
- Nothing that needs a rendered Secret starts until a human unseals Vault. This
  is a deliberate availability cost bought for a real security property, and it
  is the first line of every recovery procedure.
- Vault is a single point of failure for the whole platform's ability to start.
  Its data is in a Longhorn volume, included in `velero-daily-data`, and worth
  its own `vault operator raft snapshot save` before risky work.
- There is no dynamic-secret usage at all — no database credentials with leases,
  no short-lived tokens. Every secret is static and rotated by hand. For a lab
  that is the right amount of machinery; it is the obvious next step if this were
  real.
- The audit trail exists but nothing reads it. Vault's audit device is not
  enabled, which is an honest gap.

## Related

- `docs/adr/ADR-002-gitops.md` — sync waves and hook semantics
- `docs/adr/ADR-004-monitoring.md` — decision 7, the Alertmanager config trap
- `docs/adr/ADR-006-bootstrap.md` — decision 7, the human gate; decision 8, the age identity
- `docs/runbooks/secret-rotation.md` — the ten-step procedure
- `docs/runbooks/database-restore-drill.md` — why recovery order is Vault → ESO → Postgres
- `docs/incidents/2026-09-18-etcd-corruption.md` — action items 8 and 9
