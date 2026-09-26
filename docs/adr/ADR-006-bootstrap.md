# ADR-006: One-command platform bootstrap

**Status:** Accepted — 2026-09-26
**Supersedes:** the manual build in `docs/production-kubernetes-platform-k8s-docs/01`–`08`

## Context

The cluster was built by hand. The documentation makes the build *repeatable*,
but repeating it takes an afternoon and the result depends on who is typing.

- Automated today: Argo CD, node tuning, etcd backup/defrag, control-plane
  metrics (seven Ansible roles).
- Not automated at all: containerd, `kubeadm init`, the worker `join`, the CNI,
  and the VMs themselves.
- Postmortem item 13 (a full rebuild drill) has never been executed, because
  executing it means repeating the whole manual build.

The host is also changing: a 1 TB SSD running Ubuntu replaces Windows + VMware
Workstation. That forces the virtualisation layer to be rebuilt regardless,
which makes this the right moment to make the stack declarative rather than to
port a manual process onto a new hypervisor.

Goal: someone who has never seen this repo clones it, fills in one variables
file, runs two commands, and gets this platform.

## Decision 1 — KVM + libvirt replaces VMware Workstation

Native Linux virtualisation, no licence, fully scriptable.

The deciding factor is not convenience. On 2026-09-24 the host slept with all
three guests running; on resume the emulated **e1000** NIC on the control plane
wedged (`e1000 Tx Unit Hang`) and the guests took hard SCSI errors. Recovery took
two hours. KVM's **virtio** network and block devices are paravirtualised — there
is no emulated NIC to hang. The specific failure mode that cost those two hours
does not exist in the same form.

Secondary: `vmrun` plus hand-edited `.vmx` files is not an automation story.
libvirt has a real API, a Terraform provider, and first-class cloud-init support.

## Decision 2 — Terraform + cloud-init provisions the VMs

`terraform apply` creates three guests from an Ubuntu cloud image; cloud-init
sets hostname, static IP and the operator's SSH key.

Terraform is chosen over Ansible's libvirt modules specifically for the **state
file**. `terraform destroy && terraform apply` is a genuine, repeatable rebuild.
That turns postmortem item 13 from an afternoon into a routine — and a drill that
is cheap gets run, while one that is expensive does not.

Cost accepted: Terraform is a new tool in the repo, and its state file is
gitignored (machine-specific, and can contain host detail).

## Decision 3 — the network stays 192.168.75.0/24

VMware's NAT network is replaced by a libvirt network on the **same subnet**, so
every address already committed to Git stays valid:

| Thing | Value |
|---|---|
| Control plane | 192.168.75.136 |
| worker01 | 192.168.75.137 |
| worker02 | 192.168.75.138 |
| MetalLB L2 pool | 192.168.75.240–250 |
| Gateway LoadBalancer | 192.168.75.240 |

Renumbering would mean touching the Ansible inventory, the MetalLB pool, the
Gateway, `taskflow.platform.internal` resolution, and every runbook quoting an
address — with no benefit. A rebuild that also renumbers is two experiments at
once.

Addresses come from **cloud-init, not DHCP reservations**: a static address in
Git is reproducible, a DHCP lease is state living in the hypervisor.

## Decision 4 — ALL control-plane tuning lives in the kubeadm config file

The control plane is initialised from a templated `ClusterConfiguration` +
`KubeletConfiguration`, and **every** flag goes in it. Nothing is added to
`/etc/kubernetes/manifests/*.yaml` after the fact.

This is not a style preference. Verified on the live cluster, 2026-09-26:

```
running manifests:  --leader-elect-lease-duration=60s      (controller-manager, scheduler)
                    --leader-elect-renew-deadline=40s
                    --leader-elect-retry-period=5s
kubeadm-config:     absent
```

`kubeadm upgrade apply` regenerates the static pod manifests from
`ClusterConfiguration`. `bind-address` is in there and would survive; the
leader-election values are not, so an upgrade would **silently discard** them —
the settings that exist precisely because etcd on an HDD showed 1,341 ms fsync
p99 under load. The upgrade would report success while making the cluster less
tolerant of a slow disk.

The cause is the `control_plane_metrics` role editing manifests with
`lineinfile`. The new build must not inherit that: the role becomes a producer of
kubeadm config, not an editor of generated files.

On SSD these timings should be **revisited, not inherited**. They are a
workaround for a disk that no longer exists, and the config file is what makes
that a visible decision rather than an accident.

## Decision 5 — set `controlPlaneEndpoint` at init time

The live cluster has `apiServer: {}` — no `certSANs`, no `controlPlaneEndpoint` —
so the API server certificate covers only kubeadm's defaults and every kubeconfig
points straight at `192.168.75.136`. The control plane's address is baked into the
PKI.

The rebuild sets a `controlPlaneEndpoint` (a name, e.g.
`k8s-api.platform.internal`, resolved by hosts file or the libvirt DNS) plus
explicit `certSANs` covering that name and the node IP. Free at init; expensive
to retrofit, because retrofitting means regenerating certificates.

This does not make the cluster HA — see *out of scope* — it removes one obstacle
to ever changing that.

## Decision 6 — the CNI is installed by Ansible, not Argo CD

Everything else here is GitOps-managed. The CNI cannot be, for ordering reasons:
Argo CD is a set of pods, pods need pod networking, and pod networking *is* the
CNI. Argo CD cannot install what it needs in order to exist.

So Flannel is applied by the `control_plane` role immediately after
`kubeadm init`, with its manifest **vendored into the repo** like the Helm charts.
(`dl.min.io` began returning HTTP 410 mid-project; upstream URLs are not a
dependency this platform accepts.)

The same reasoning, in the other direction, covers two node-level prerequisites
that Argo-managed components need:

- **Longhorn** requires `open-iscsi` and `nfs-common` on every node.
- **Velero's node-agent** needs the kubelet root directory host-mounted.

Both are Ansible's job. A Helm chart cannot install a package on its host.

## Decision 7 — two commands, with a deliberate human gate

```
make up            host prep → VMs → cluster → Argo CD → platform-root
                   stops with: "Vault is uninitialised. Run make vault-init."

make vault-init    prints 5 unseal shares + root token to the operator ONCE.
                   Writes them nowhere. The operator stores them.

make secrets       unseal, enable Kubernetes auth for ESO, write the platform's
                   secrets. Argo converges the rest unattended.
```

The gate is the design, not a shortcut. A pipeline that generates unseal shares
and then stores them where it can read them again has produced encryption with
the key taped to the box. Automating it would make the repo *look* more
impressive and *be* less secure, and a README claiming "fully automated including
secrets" is a claim an interviewer would take apart.

**Recovery ordering is a hard constraint, proven by the 2026-09-26 restore
drill:** the database cannot start from a Velero restore alone. Its password comes
from Vault via External Secrets Operator, so the credentials Secret does not exist
until Vault is unsealed. The restored pod fails with `CreateContainerConfigError`,
which gives no hint that the answer is "go unseal Vault". Order:

1. Vault (unseal)
2. External Secrets Operator
3. Postgres, and anything else consuming a rendered Secret

## Decision 8 — the age identity is generated and handed over once

`make secrets` generates an age keypair, commits the **public recipient** to
`infrastructure/ansible/roles/etcd_backup/files/recipient.txt`, and prints the
private identity to the operator exactly once. The tooling never writes the
private half to disk and never echoes it a second time.

A direct consequence of the 2026-09-25 exposure: a verification step that
displayed stored key material led to it being pasted into a chat log, and the
remedy was rotating every backup. The rule from
`docs/runbooks/secret-rotation.md` applies here — **verify by comparing hashes,
never by printing values.**

## Decision 9 — nothing personal in Git; one variables contract

A single example file lists everything an operator must supply, with no working
default for anything identifying:

| Variable | Why it cannot be defaulted |
|---|---|
| `ssh_public_key` | theirs, not mine |
| `container_registry` / `registry_user` | their GHCR namespace, not `shaggydesai` |
| `git_repo_url` | Argo must follow *their* fork, or it silently syncs mine |
| `gateway_hostname` | `taskflow.platform.internal` is arbitrary |
| `discord_webhook_url` | optional; Alertmanager degrades to no notifier |
| `network_cidr`, node IPs | must not collide with their LAN |

`git_repo_url` is the one that bites: leaving it defaulted produces a cluster
quietly tracking someone else's `main`.

## Decision 10 — the libvirt provider is pinned below 0.9

`version = "~> 0.8.0"`, with `.terraform.lock.hcl` committed.

The original constraint was `~> 0.8`, which is **not a pin**: it permits
anything below 1.0. It resolved to v0.9.9 — a Terraform Plugin Framework
rewrite that maps libvirt's raw XML almost 1:1. Nested blocks became nested
attributes, and disks, interfaces, consoles and graphics all moved inside a
single `devices` attribute. Every block in the configuration was rejected:

    Blocks of type "dns" are not expected here.
    Did you mean to define argument "dns"? If so, use the equals sign.

0.8.x is kept because this layer's job is to be **readable**. It expresses
"three guests on a NAT network" in roughly sixty lines that match every
published example. The 0.9 equivalent is several hundred lines of XML-shaped
HCL saying the same thing, and a reader who cannot follow the file cannot
check it. Choosing the newer provider would make the repo look more
sophisticated and be harder to verify — the same trade refused in decision 7.

To move to 0.9 later: dump the schema with `terraform providers schema -json`
(the installed binary is authoritative; published docs lag), expand the nested
`devices`, `os` and `ips` attributes, and rewrite `main.tf` against them.

**The general lesson:** `~> X.Y` on a 0.x provider is not a pin, because 0.x
releases may break compatibility at the minor level. `~> X.Y.Z` is. This is the
same reasoning that led to vendoring the Helm charts, applied to a different
tool — and it was caught only because `terraform validate` was run before
anything was applied.

## Confirmed facts — all read from the live cluster, 2026-09-26

| Fact | Value |
|---|---|
| Kubernetes / kubeadm | v1.36.3 |
| kubeadm API version | `kubeadm.k8s.io/v1beta4` |
| containerd | 2.2.1, `SystemdCgroup = true` |
| etcd | 3.6.8, dataDir `/var/lib/etcd` |
| Guest OS | Ubuntu 24.04.4 |
| CNI | **Flannel** (`kube-flannel` namespace, DaemonSet) |
| Pod subnet | `10.244.0.0/16` |
| Service subnet | `10.96.0.0/12` |
| DNS domain | `cluster.local` |
| Image repository | `registry.k8s.io` |
| Encryption algorithm | RSA-2048 |
| CA validity | 87600h (10 years) |
| **Leaf cert validity** | **8760h (1 year)** — see below |
| Node subnet | 192.168.75.0/24, nodes .136 / .137 / .138 |
| MetalLB pool | 192.168.75.240–250 |
| Storage class | `longhorn` |
| Gateway | `platform-gateway` in `envoy-gateway-system`, `https` listener |
| Argo Applications | 16, under `platform-root` |
| Vendored Helm charts | 14 |
| etcd metrics arg | `listen-metrics-urls=http://127.0.0.1:2381,http://<node-ip>:2381` — must be templated per node |

**Certificate expiry is a scheduled outage waiting to happen.** Leaf certificates
last one year. The cluster is roughly a week old, so they expire around September
2027. `kubeadm certs check-expiration` belongs in a runbook, and
kube-prometheus-stack's `KubeClientCertificateExpiration` rule should be confirmed
as firing-capable rather than assumed.

## VM sizing — revised for the new host

Host: **12 logical CPUs, 31.9 GB RAM.** Current allocation uses 8 vCPU and
15.3 GiB — under half of it, and distributed backwards: cp01 runs etcd and the
entire control plane on 2 vCPU while worker01 has 4.

| Node | Now | Rebuild |
|---|---|---|
| cp01 | 2 vCPU / 5.7 GiB | **4 vCPU / 8 GiB** |
| worker01 | 4 vCPU / 4.8 GiB | **3 vCPU / 8 GiB** |
| worker02 | 2 vCPU / 4.8 GiB | **3 vCPU / 8 GiB** |
| Host retains | — | 2 vCPU / ~8 GB |

Twice the CPU for etcd, on an SSD instead of an HDD. That combination is what
should allow the leader-election timings to move back toward defaults instead of
carrying the HDD workaround forever — measure `etcd_disk_wal_fsync_duration`
after the rebuild before changing them.

## Consequences

**Good.** The rebuild drill becomes cheap enough to actually run. Host
configuration stops being a PowerShell script nobody can verify and becomes
Ansible. Version drift becomes visible, because every version is a variable. The
repo's central claim — rebuildable from Git alone — becomes testable rather than
aspirational.

**Accepted costs.** Terraform is a new tool to learn and explain. The VMware VMs
are replaced rather than converted, so anything not in Git is lost — which is
exactly why the restore drill came first. And two commands is not one; the README
says so plainly rather than claiming a single switch.

**Out of scope: high availability.** One laptop, one control-plane node.
Pretending otherwise would be dishonest. The single control plane remains accepted
risk 12, mitigated by backups that have now been verified by restore.

## Related

- `docs/adr/ADR-002-gitops.md` — why Argo CD has exactly one install path
- `docs/incidents/2026-09-25-host-sleep.md` — why virtio matters
- `docs/runbooks/database-restore-drill.md` — the Vault → ESO → Postgres ordering
- `docs/runbooks/secret-rotation.md` — verify by hash, never by printing
