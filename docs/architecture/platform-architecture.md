# Platform architecture

What this platform is, how its pieces fit, and where to look for each one. Read
this first; the ADRs explain *why* each decision was made, the incidents explain
what happened when they were wrong.

---

## The shape of it

Three Ubuntu 24.04 virtual machines on one laptop, running a Go HTTP API behind a
Gateway API implementation, with everything inside the cluster reconciled from
Git.

```
                          one physical host
  ┌───────────────────────────────────────────────────────────────────┐
  │  hypervisor (VMware Workstation -> KVM/libvirt, see ADR-006)      │
  │                                                                   │
  │   k8s-cp01              k8s-worker01         k8s-worker02         │
  │   192.168.75.136        .137                 .138                 │
  │   4 vCPU / 8 GiB        3 vCPU / 8 GiB       3 vCPU / 8 GiB       │
  │   60 GB                 80 GB                80 GB                │
  │                                                                   │
  │   etcd                  ─── Longhorn replicas, 2 per volume ───   │
  │   kube-apiserver        kubelet              kubelet              │
  │   kube-scheduler        kube-proxy           kube-proxy           │
  │   kube-controller-mgr   flannel              flannel              │
  │   kubelet, kube-proxy                                             │
  │   flannel                                                         │
  └───────────────────────────────────────────────────────────────────┘
          │
          │  hourly, read-only SFTP, laptop PULLS (never pushed)
          ▼
    C:\Backups\etcd     age-encrypted etcd bundles, 30d
    C:\Backups\velero   age-encrypted Velero mirror, 14d
```

| | |
|---|---|
| Kubernetes | 1.36.3, kubeadm, single control plane |
| Runtime | containerd 2.2.1 |
| CNI | Flannel v0.28.9, VXLAN, pods `10.244.0.0/16`, MTU 1450 |
| Services | `10.96.0.0/12`, cluster DNS `10.96.0.10` |
| Ingress | MetalLB L2 (`192.168.75.240-250`) → Envoy Gateway → HTTPRoute |
| Storage | Longhorn 1.7.2, 2 replicas, RWO |
| GitOps | Argo CD, 17 Applications, app-of-apps |

---

## The four layers

Each layer is declarative, owns a different scope, and hands off through a narrow
explicit interface. The boundaries matter more than any individual tool: each
layer can be re-run without the others, and each stops at a defined point.

```
  ┌──────────────────────────────────────────────────────────────────┐
  │ 1. Terraform          infrastructure/terraform/                  │
  │    libvirt network, 3 qcow2 overlays, cloud-init ISOs, 3 guests   │
  │    STOPS AT: a machine that boots, has an address and an SSH key  │
  │    HANDS OFF: a generated Ansible inventory                       │
  ├──────────────────────────────────────────────────────────────────┤
  │ 2. Ansible            infrastructure/ansible/  (16 roles)         │
  │    kernel modules, sysctls, containerd, kubeadm, Flannel, join,   │
  │    backup timers, metrics flags, node tuning                      │
  │    STOPS AT: `kubectl get nodes` shows three Ready nodes          │
  │    HANDS OFF: `kubectl apply -f platform-root.yaml`               │
  ├──────────────────────────────────────────────────────────────────┤
  │ 3. Argo CD            kubernetes/gitops/ + kubernetes/platform/   │
  │    13 platform components as wrapper charts, continuously         │
  │    reconciled, drift corrected automatically                      │
  │    STOPS AT: everything inside the cluster                        │
  ├──────────────────────────────────────────────────────────────────┤
  │ 4. CI                 .github/workflows/                          │
  │    tests, builds and publishes the image; opens a PR to bump      │
  │    the manifest. THE MERGE IS THE DEPLOY.                         │
  └──────────────────────────────────────────────────────────────────┘
```

The split between 1 and 2 is the one worth internalising. **Terraform is stateful:**
remove a resource from the configuration and the next `apply` destroys it. That is
right for machines. **Ansible is convergent and forgetful:** each run moves the
host toward the declared state and it has no memory of what it did last time. That
is right for OS configuration, which changes constantly and must not cause a host
to be destroyed because a sysctl changed. Layer 3 is a controller, because cluster
objects change constantly and must self-heal.

Use the tool whose reconciliation model matches the lifetime of the thing.

### Where each layer refuses to help

- A Helm chart runs *inside* the cluster and cannot install a package on a node.
  `open-iscsi` and `nfs-common` are in Ansible for that reason, and a Longhorn
  that installs perfectly and cannot attach a volume is what happens if you
  forget (ADR-003 decision 4, ADR-006 decision 6).
- The CNI is installed by Ansible, not Argo CD: Argo CD needs a network to run,
  so the network cannot be one of its Applications.
- Argo CD itself is installed by Ansible, so a broken Argo CD can be fixed
  without a working Argo CD (ADR-002 decision 3).
- `platform-root.yaml` is applied by hand and managed by nothing, because
  something has to apply the thing that applies everything else (ADR-002
  decision 1).

---

## The build

```bash
make check        # preflight: tools, credentials, config files
make up           # host -> VMs -> cluster -> Argo CD, STOPS at the Vault gate
make vault-init   # prints 5 unseal shares ONCE. You store them.
make secrets      # unseal, wire up External Secrets, let Argo converge
```

Two commands, not one, and the gap is deliberate. A pipeline that generates unseal
shares and then stores them somewhere it can read them again has produced
encryption with the key taped to the box (ADR-006 decision 7).

---

## Request path

```
client
  │  https://taskflow.platform.internal
  ▼
MetalLB  192.168.75.240        L2 mode: one node answers ARP for the VIP
  ▼
Envoy Gateway                  Gateway (listener, TLS cert from cert-manager)
  ▼
HTTPRoute                      path match -> backendRef
  ▼
Service  taskflow-api:8080     ClusterIP, EndpointSlice
  ▼
kube-proxy iptables            DNAT to a pod IP, probability-weighted
  ▼
pod                            2 replicas, 8080 app / 9090 metrics
  ▼
Service postgresql:5432        in-namespace
```

Seven NetworkPolicies wrap that path, default-deny plus explicit allows:
gateway→app on 8080, monitoring→app on 9090, app→db, migrate→db, and DNS egress —
which is the one everybody forgets, because a default-deny egress policy that
omits port 53 breaks name resolution and presents as every dependency being down.

`/metrics` is on **port 9090, not 8080**, because the HTTPRoute matches
`PathPrefix: /` and previously exposed it to anything that could reach the
LoadBalancer address. Moving the port made the boundary structural — enforced by
NetworkPolicy rather than by a path prefix nobody had widened yet.

---

## Secret path

```
Vault (Raft, sealed until a human unseals it, 3 of 5 Shamir shares)
  ▼  Kubernetes auth, role external-secrets-role
ClusterSecretStore  vault-backend                    sync wave -2
  ▼
ExternalSecret                                       sync wave -1
  ▼
Kubernetes Secret
  ▼
pod env var  (read ONCE at startup)
```

Nothing that needs a rendered Secret starts until Vault is unsealed. That single
fact fixes the recovery order for the whole platform:

**Vault → External Secrets Operator → Postgres → everything else.**

Get it wrong and you get `CreateContainerConfigError` and `secret
"postgresql-credentials" not found`, which gives no hint that the answer is to go
and unseal Vault. See ADR-005 decision 2.

---

## Observability path

```
scraped:   apiserver, controller-manager, scheduler, etcd, kubelet/cAdvisor,
           node-exporter, kube-state-metrics, CoreDNS, Flannel, Argo CD,
           Longhorn, MinIO, Velero, taskflow-api
   ▼
Prometheus  7d, 10Gi                 ──────►  Grafana  (+ Loki as a 2nd source)
   ▼
Alertmanager                                  Promtail ──► Loki  168h, 10Gi
   ▼  warnings repeat 24h / criticals 1h
Discord
```

Batch jobs — etcd backup, etcd defrag, the Velero off-site mirror, the backup-pull
observer — cannot be scraped, so each writes two files to node-exporter's textfile
collector: one holding only the last **success** (what the staleness alert reads),
one holding the outcome of the most recent **run**, written from a `trap ... EXIT`
so failure is the default and success must be reached.

Every scraped thing has a `...TargetDown` alert *and* an `absent()` companion,
because a deleted ServiceMonitor produces no series at all rather than a zero, and
an expression that returns nothing is not firing. See ADR-004 decision 4.

---

## Backup path

Four kinds of state, four mechanisms. Knowing which is which is what made both
2026-09-27 restores zero-data-loss.

| State | Where it lives | Recovered by | Retention |
|---|---|---|---|
| Kubernetes objects | etcd | etcd snapshot, age-encrypted, every 6h | 7d node / 30d laptop |
| Cluster identity (3 CAs, `sa.key`, kubeconfigs, manifests) | `/etc/kubernetes` | the same bundle | same |
| Declared config | Git | Git | forever |
| Application volumes | Longhorn on the workers | Velero + Kopia → MinIO, daily 01:00 | 7d |
| All object metadata | — | Velero, no volumes, daily 02:00 | 14d |
| MinIO's contents | Longhorn | `rclone` mirror, age-encrypted, daily 03:15 | 7d node / 14d laptop |
| Unseal shares, age private key | password manager, paper | not in the cluster, by design | — |

Two properties are load-bearing. **Application data is not in etcd** — it is in
Longhorn replicas on the workers — which is why two total control-plane losses
cost zero rows. And **the laptop pulls; the cluster never pushes**, so a fully
compromised cluster cannot delete its own off-site backups.

The encryption is one age key pair whose private half is not on any cluster node.
Without it every backup is noise, which is why it has three copies in three
failure domains and its own audit (ADR-005 decision 8).

---

## Repository map

```
apps/taskflow-api/           Go source, Dockerfile, embedded SQL migrations
infrastructure/
  terraform/                 layer 1 — network, disks, cloud-init, guests
  ansible/                   layer 2 — 16 roles, 4 playbooks
  vault/                     bootstrap script and two ACL policies
  laptop/                    PowerShell: the backup pull, power policy
kubernetes/
  gitops/bootstrap/          platform-root.yaml, applied by hand
  gitops/argocd/             one Application per component
  platform/                  13 wrapper charts, dependencies vendored as .tgz
  applications/              taskflow-api and two demos
.github/workflows/           app CI, manifest CI, daily image availability
docs/
  adr/                       why each decision was made
  incidents/                 three postmortems, in full
  runbooks/                  six procedures, each one used in anger
  roadmap.md                 what is left, ordered by risk
Makefile                     the build, and the human gate in the middle
```

Every platform component is a **wrapper chart**: a `Chart.yaml` naming one
upstream dependency, that dependency vendored as a `.tgz` under `charts/`, a
`Chart.lock`, a `values.yaml`, and any extra manifests in `templates/`. Vendoring
means CI renders with no network and the cluster and CI cannot get different
versions — which matters because three upstream artefacts this platform depended
on have been withdrawn (`dl.min.io` → HTTP 410, `quay.io/minio/minio` → 401, then
`quay.io/minio/mc` → 401).

---

## What this platform is not

Being explicit, since several of these look like oversights and are decisions.

- **Not highly available.** One control plane, one etcd member, one physical host.
  A second control plane needs a load balancer this design does not provide.
  Compensated with backups that have been restored twice under pressure.
- **Not multi-tenant.** No quotas, no per-team RBAC, one namespace per component.
- **No dynamic secrets.** Every secret is static and rotated by a documented
  procedure. No leases, no short-lived database credentials.
- **No autoscaling.** `metrics-server` is installed and nothing uses it for an
  HPA. Fixed replica counts throughout.
- **Not a cloud platform.** libvirt and MetalLB stand in for a cloud's network and
  load balancer, deliberately, because doing it by hand is where the learning is.

---

## Where to read next

| If you want | Read |
|---|---|
| To build it | `Makefile`, then `docs/runbooks/rebuild.md` |
| Why KVM, Terraform, the subnet, the human gate | `docs/adr/ADR-006-bootstrap.md` |
| Why Argo CD is shaped this way | `docs/adr/ADR-002-gitops.md` |
| Why Longhorn, and two decisions to reverse | `docs/adr/ADR-003-storage.md` |
| What counts as evidence that monitoring works | `docs/adr/ADR-004-monitoring.md` |
| Why nothing starts until Vault is unsealed | `docs/adr/ADR-005-secrets.md` |
| What actually happens when it breaks | `docs/incidents/` — all three, in order |
| To run it day to day | `docs/runbooks/lab-startup-shutdown.md` |
| What is left | `docs/roadmap.md` |
