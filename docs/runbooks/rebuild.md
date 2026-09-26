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
