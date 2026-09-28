# Runbook: rebuild the platform from nothing

Takes a bare Ubuntu machine to a running platform. This is postmortem item 13
from `docs/incidents/2026-09-25-host-sleep.md` — a full rebuild drill, which had
never been executed because executing it used to mean repeating the manual
build in `docs/production-kubernetes-platform-k8s-docs/01`–`08` by hand.

Design and reasoning: `docs/adr/ADR-006-bootstrap.md`.

## Before you start

| Need | Why |
|---|---|
| Ubuntu 24.04, VT-x/AMD-V enabled in firmware | `make check` fails immediately without it |
| ~24 GiB RAM, 10 spare vCPU, ~250 GB disk | Three guests at 4/3/3 vCPU and 8 GiB each |
| An SSH keypair | Password login is disabled on the guests |
| A GitHub account with a fork of this repo | Argo CD must follow *your* repo, not someone else's |
| Your Velero backups, if restoring | The guests are replaced, not migrated |
| A password manager, open | Vault prints its unseal shares exactly once |
| A GHCR mirror of the MinIO image | Upstream refuses anonymous pulls; `platform-minio` cannot sync without it. See the next section |

```bash
git clone https://github.com/<you>/production-kubernetes-platform.git
cd production-kubernetes-platform

cp infrastructure/terraform/terraform.tfvars.example infrastructure/terraform/terraform.tfvars
cp infrastructure/ansible/group_vars/all.example.yml infrastructure/ansible/group_vars/all.yml
$EDITOR infrastructure/terraform/terraform.tfvars      # ssh key, admin user, pool
$EDITOR infrastructure/ansible/group_vars/all.yml      # admin user, git repo URL

# The Flannel manifest is vendored, not downloaded at apply time
cd infrastructure/ansible/roles/cni_flannel/files
curl -fsSL -o kube-flannel.yml \
  https://github.com/flannel-io/flannel/releases/download/v0.28.9/kube-flannel.yml
cd -

make check
```

`make check` must pass cleanly. It looks for the tools, both config files and
the vendored manifest — five minutes of setup mistakes surface here rather than
twenty minutes into a build.

## Mirror the MinIO image first

`platform-minio` cannot sync on a fresh host until this exists, and Velero has
no backup target without MinIO — so a restore is blocked behind it. Do this
before `make up`.

`quay.io/minio/minio` and `quay.io/minio/mc` both return `401 UNAUTHORIZED` to
anonymous pulls, and `docker.io/minio/*` returns `insufficient_scope`. Verified
2026-09-28 against a control: `busybox` and `amazon/aws-cli` pull from Docker
Hub without credentials on the same host, so this is MinIO's distribution
policy and not a local network problem. It is the third artefact MinIO has
withdrawn that this project depended on — `dl.min.io` began returning HTTP 410
earlier.

The source is an OCI archive exported from a node that still had the image:

| | |
|---|---|
| File | `minio-RELEASE.2024-12-18T13-15-44Z.tar` |
| sha256 | `7f36b5a1d135b034736dea1be4968f9a558e7a605905a6b8e67f3b9e5f669726` |
| Contents | a multi-arch index, but **amd64 blobs only** |

**If that archive is lost, the image cannot be recovered** — neither registry
will serve it again. Treat it like the `age` key, not like a cache.

```bash
sudo apt-get install -y skopeo gh

# GHCR needs a CLASSIC PAT or a gh OAuth token. A fine-grained PAT logs in
# successfully and then fails on the first blob upload with
# "The token provided does not match expected scopes", because fine-grained
# permissions are granted per EXISTING package and the package does not exist
# yet. That failure mode cost half an hour on 2026-09-28.
gh auth login --scopes write:packages --web
gh auth token | skopeo login ghcr.io -u <you> --password-stdin

# NOT --all. The index advertises 6 platforms and the archive contains one, so
# --all dies on the first platform whose blobs are absent.
skopeo copy --override-os linux --override-arch amd64 \
  oci-archive:minio-RELEASE.2024-12-18T13-15-44Z.tar \
  docker://ghcr.io/<you>/minio:RELEASE.2024-12-18T13-15-44Z

skopeo inspect docker://ghcr.io/<you>/minio:RELEASE.2024-12-18T13-15-44Z \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["Digest"])'

skopeo logout ghcr.io
```

That digest must read
`sha256:34c8e2f52a5984492555427fee07254c80036bdb7079bb91679232abd7a4fa20`,
the amd64 entry from quay's original index. If it matches, the mirror is
bit-identical to what upstream served. Then point
`kubernetes/platform/minio/values.yaml` at your own namespace:

```yaml
minio:
  image:
    repository: ghcr.io/<you>/minio
```

The pull side needs no new credential: `secret/ghcr` already holds a
`read:packages` token and `templates/externalsecret-ghcr.yaml` renders it into
the `minio` namespace. Delete the push token afterwards — it is a bootstrap
credential like the Vault unseal shares, and it does not belong in Vault.

**`mc` cannot be mirrored at all.** No copy of it exists on our side, so bucket
creation moved to `templates/job-create-bucket.yaml`, a PostSync Job running
`aws-cli` pinned by manifest digest. The chart's own Job is suppressed by
pinning all five of its gate keys — `buckets`, `users`, `policies`, `svcaccts`,
`customCommands` — to empty. Emptying `buckets` alone does **not** work; the
Job still renders.

## Build

```bash
make up
```

Runs: host preparation → Terraform → cluster → Argo CD → `platform-root`, then
**stops** and tells you Vault is uninitialised.

One interruption is expected in the middle: `make host` adds you to the
`libvirt` group, and group membership only applies to a new login. If `make vms`
fails with a libvirt permission error, log out, log back in, and run `make up`
again — every step is idempotent.

## The gate

```bash
make vault-init
```

Prints five unseal shares and a root token. **Once.** They are not written to
disk and cannot be shown again. Store them before pressing anything else.

This step is deliberately not automated. A pipeline that generates unseal shares
and then stores them where it can read them again has produced encryption with
the key taped to the box. See ADR-006 decision 7.

```bash
make secrets
```

Unseals Vault, enables Kubernetes auth for External Secrets, and writes the
secrets the platform needs. Argo CD converges everything else unattended.

### Two secrets nobody writes for you

The `vault-config` PreSync Job seeds `secret/grafana`, `secret/postgresql`,
`secret/taskflow-api`, `secret/minio`, `secret/velero` and `secret/demo-app`
with random values, idempotently. Two more are neither in Git nor generated,
and nothing tells you they are missing:

```bash
# GHCR pull credentials. taskflow-api, its migration Job, AND platform-minio
# all need these - so forgetting it looks like three unrelated faults.
vault kv put secret/ghcr username=<github-user> token=<ghcr-read-token>

# Discord. The path is secret/alertmanager, NOT secret/discord.
vault kv patch secret/alertmanager discord-webhook-url=<url>
```

`kv patch`, not `kv put`, on `secret/alertmanager` — `put` replaces the whole
document and silently discards the other keys. Writing to `secret/discord`
instead produces an ExternalSecret that reports `SecretSynced` while serving
nothing; that mistake cost an afternoon on 2026-09-27. See
`docs/runbooks/secret-rotation.md`.

**Recovery order is not optional:** Vault → External Secrets Operator →
Postgres. Proven on 2026-09-26: Postgres reads its password from a Secret that
ESO renders from Vault, so before Vault is unsealed the pod fails with
`CreateContainerConfigError` — which gives no hint whatsoever that "go unseal
Vault" is the answer.

```bash
make node-config
```

Backups, metrics and node tuning. Run once the cluster has settled.

## Verify

```bash
make status
```

Then the things `make status` cannot judge:

```bash
kubectl get nodes -o wide                       # three, all Ready
kubectl -n argocd get applications              # every one Synced and Healthy
kubectl get pods -A | grep -vE 'Running|Completed'   # should print nothing

# the control-plane tuning survived, and lives where an upgrade will respect it
kubectl -n kube-system get cm kubeadm-config \
  -o jsonpath='{.data.ClusterConfiguration}' | grep -E 'leader-elect|controlPlaneEndpoint'

# the disk that prompted the whole rebuild
kubectl -n monitoring exec sts/prometheus-kube-prometheus-stack-prometheus -c prometheus -- sh -c \
  'wget -qO- "http://localhost:9090/api/v1/query?query=histogram_quantile(0.99,rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m]))"'
```

That last one is the point of the exercise. On the HDD, etcd's WAL fsync p99 was
**1,341 ms under load**, which is why `leader_elect_lease_duration` is 60s
instead of the 15s default. On an SSD it should be one to two orders of
magnitude better. **Measure it, then lower those values back toward the
defaults** — they are a workaround for a disk that no longer exists, and
carrying them forward unexamined means the rebuild gained you nothing.

## Restoring data

The guests are replaced, not migrated, so anything not in Git or in a Velero
backup is gone. Full procedure: `docs/runbooks/database-restore-drill.md`.

Reference numbers from the 2026-09-26 drill on the old hardware: a 62 MB
database backed up in 18s and came back queryable in about six minutes, with the
row dump byte-identical before and after.

## Record the result

Fill this in after the first real run — a rebuild time nobody measured is not a
capability anybody can plan around.

| Step | Duration |
|---|---|
| `make host` | |
| `make vms` | |
| `make cluster` | |
| `make platform` (to all Applications Synced) | |
| `make vault-init` + `make secrets` | |
| Data restore | |
| **Bare machine to working platform** | |

## Traps, all of them observed

**`virsh` needs sudo.** Group membership has not taken effect. Log out and back
in. The provider's error reads like a Terraform problem and is not one.

**`terraform apply` fails at `libvirt_cloudinit_disk`.** `genisoimage` is
missing — the provider shells out to `mkisofs`. `make host` installs it; you
skipped that step.

**A guest boots with no network.** The netplan config matches `en*` by glob
because the interface is `enp1s0` on some machine types and `ens3` on others.
Get in with `virsh console <node>` and check `ip -br a`.

**Pods stuck in `ContainerCreating`, pause image cannot be pulled.** The
containerd sandbox image does not match what kubeadm expects. `containerd config
dump | grep 'sandbox ='` — the `containerd_runtime` role asserts this, so it
should be impossible from a clean build.

**Pods cannot reach each other.** Flannel's network does not match kubeadm's
`podSubnet`. The `cni_flannel` role asserts this too. If you replaced the
vendored manifest by hand, that is where to look.

**Postgres in `CreateContainerConfigError`.** Vault is sealed. See the gate.

**`kubectl get backups` returns nothing.** Ambiguous CRD: both `longhorn.io` and
`velero.io` register a `Backup` kind. Use `backups.velero.io`.

**An automated bump PR has no checks and cannot be merged.** It was opened with
`GITHUB_TOKEN`, which GitHub suppresses workflow runs for. Since 2026-09-26 CI
uses a GitHub App token; if you forked this repo, create your own App and set
`CI_APP_ID` and `CI_APP_PRIVATE_KEY`.

**`platform-minio` in `ImagePullBackOff` on a fresh build.** You skipped the
mirror — see "Mirror the MinIO image first". If the mirror exists and the pull
still fails with `unauthorized`, check that `secret/ghcr` was written and that
the ExternalSecret in the `minio` namespace actually produced a
`ghcr-pull-secret`.

**The bucket Job fails on a read-only filesystem.** `aws-cli` writes under
`$HOME`; the Job sets `HOME=/tmp` with an `emptyDir` there and
`readOnlyRootFilesystem: true`. If a newer `aws-cli` digest needs to write
elsewhere, that is the flag to relax — and pin the new digest, do not switch to
a tag.
