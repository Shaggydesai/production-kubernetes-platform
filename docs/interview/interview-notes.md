# DevOps interview notes

Two parts.

**Part 1** is a general question bank, pitched at junior-to-mid (0–3 years). It
covers what gets asked in screening calls and first technical rounds. Answers are
written to be **said out loud in 30–60 seconds** — not essays.

**Part 2** is the same subject matter answered from *this* cluster, with real
numbers. That is what turns a correct answer into a memorable one. An interviewer
hears "etcd needs fast disks" fifty times; they hear "our WAL fsync p99 was 15 ms
idle and 1,341 ms under load, and the controller-manager restarted 47 times
because lease renewal is an etcd write" once.

Questions marked **[stretch]** are above the target level. Know they exist; do not
panic if you cannot answer them.

A note on how to answer: if you do not know, say so and then say how you would
find out. "I haven't hit that, but I'd start by checking X because Y" scores far
better than a guess. Every interviewer has seen candidates bluff.

---
---

# Part 1 — General question bank

## 1. Linux fundamentals

**What happens when you run a command in a shell?**
The shell `fork()`s a copy of itself, then the child calls `exec()` to replace its
memory image with the new program. The parent `wait()`s for the child's exit
status. `fork` makes the process, `exec` changes what it is running.

**What is a process versus a thread?**
A process has its own memory space; threads share the memory of their process.
Linux implements both with the same `clone()` call, differing in what gets shared.

**Explain file permissions `rwxr-xr--`.**
Three triads: owner can read/write/execute, group can read/execute, others can
read only. Numerically 754. Directories need `x` to be traversed, not just read.

**What is the difference between a hard link and a symlink?**
A hard link is another name for the same inode — delete the original and the data
survives. A symlink is a file containing a path; delete the target and the symlink
dangles. Hard links cannot cross filesystems.

**How do you find what is using disk space?**
`df -h` for filesystem level, `du -sh *` to descend. The classic gotcha: `df` shows
full and `du` shows less, because a deleted file is still held open by a running
process — find it with `lsof | grep deleted` and restart the process.

**A process is using 100% CPU. Walk me through it.**
`top` or `htop` to identify it, `ps -p <pid> -o args=` for the full command line,
`journalctl -u <unit>` if it is a service. Then `strace -p <pid>` to see syscalls
or `py-spy`/`jstack` for a language-level stack. Check whether it is user or system
time — high system time points at I/O or syscall thrash.

**What is a zombie process?**
A process that has exited but whose parent has not `wait()`ed to reap its exit
status. It holds no resources except a PID entry. Fix the parent, or if the parent
died the init process adopts and reaps it.

**Signals: what is the difference between SIGTERM and SIGKILL?**
`SIGTERM` (15) asks a process to shut down and can be caught, so the process can
flush and close cleanly. `SIGKILL` (9) is handled by the kernel and cannot be
caught. Always try TERM first. This is exactly what Kubernetes does: TERM, wait
`terminationGracePeriodSeconds`, then KILL.

**What is systemd and what is a unit?**
The init system — PID 1 — which starts and supervises services. A unit is a
declarative file describing something systemd manages: `.service`, `.timer`,
`.mount`, `.socket`.

**`Wants=` versus `Requires=` versus `After=`?**
`Wants` is a weak dependency (start it too, but carry on if it fails). `Requires`
is strong (if it fails, fail me). `After` is *ordering only* and says nothing about
whether the other unit is even wanted. The common mistake is assuming `After`
implies a dependency — it does not.

**What is a systemd timer and why prefer it over cron?**
A `.timer` unit triggering a `.service`. Advantages: the job's output goes to the
journal, you get dependency ordering, `RandomizedDelaySec` to spread load, and
`Persistent=true` to run a job missed while the machine was off.

**[stretch] What is the catch with `Persistent=true`?**
A missed job runs *immediately* at boot, before the things it depends on are ready.
A backup job with `OnCalendar=03:15` on a host that boots at 03:15 runs against an
API server that is not yet serving. Any timer job must either wait for its
dependencies or be safe to fail.

**What are cgroups and namespaces?**
Namespaces control **what a process can see** — PID, network, mount, UTS, IPC,
user, cgroup. cgroups control **how much it can use** — CPU, memory, I/O. Together
they are what a container is.

**[stretch] Which namespace does a pod share?**
All containers in a pod share the network and IPC namespaces (so they reach each
other on `localhost`) and usually the UTS namespace, but have their own mount and
PID namespaces by default.

**Commands you should be able to produce without thinking.**
```bash
grep -rn "pattern" .          journalctl -u nginx -n 50 --no-pager
find . -name "*.log" -mtime +7    systemctl status / is-enabled / list-timers
tail -f /var/log/syslog       ss -tulpn          # sockets, replaces netstat
sed -i 's/old/new/g' file     lsof -i :8080
awk '{print $1}' file         dmesg -T | tail
sort | uniq -c | sort -rn     chmod 640 / chown user:group
```

---

## 2. Networking fundamentals

**Walk me through what happens when you type a URL into a browser.**
DNS resolution (cache → `/etc/hosts` → resolver → recursive lookup) → TCP
three-way handshake to the IP on port 443 → TLS handshake (certificate presented,
chain validated, keys agreed) → HTTP request → response → render. Interviewers use
this to see how many layers you can name.

**What is the TCP three-way handshake?**
SYN → SYN-ACK → ACK. Client proposes, server acknowledges and proposes, client
acknowledges. Then data flows.

**TCP versus UDP?**
TCP is connection-oriented, ordered, retransmits lost segments, has flow control.
UDP is fire-and-forget with lower overhead. DNS, VXLAN and most metrics protocols
use UDP; anything needing reliability uses TCP.

**What is a subnet mask? What is `192.168.75.0/24`?**
The `/24` means the first 24 bits are the network, leaving 8 bits for hosts — 256
addresses, 254 usable, from `192.168.75.1` to `.254`. Routing works by
longest-prefix match: the most specific matching route wins.

**Difference between a public and a private IP?**
Private ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) are not routable
on the internet and need NAT to get out.

**What is NAT?**
Rewriting addresses in packet headers so many private addresses can share one
public one. Outbound is usually source NAT / masquerading; the kernel tracks each
flow in the conntrack table so replies come back to the right host.

**Connection refused versus a timeout — what does each tell you?**
**Refused** means the packet arrived and nothing was listening on that port —
routing is fine, the service is down. A **timeout** means the packet went nowhere
— firewall, wrong route, or the host is unreachable. This distinction saves hours;
it is one `curl` each.

**How do you debug "I can't reach this service"?**
Work up the stack. `ping` the host (ICMP may be blocked, so a failure is not
conclusive) → `ss -tulpn` on the server to confirm it is listening and on which
interface → `curl -v` from the client → `dig` to check the name resolves to what
you expect → check firewall rules. Bisect: does the IP work when the name does
not? That is DNS. Does the pod IP work when the Service IP does not? That is
kube-proxy.

**What is DNS, briefly — A, CNAME, TXT?**
`A` maps a name to an IPv4 address, `AAAA` to IPv6. `CNAME` is an alias to another
name. `TXT` holds arbitrary text, used for domain verification and SPF/DKIM.

**What are ports 22, 53, 80, 443, 6443?**
SSH, DNS, HTTP, HTTPS, and the Kubernetes API server.

**[stretch] What is MTU and why would you lower it?**
Maximum transmission unit — the largest frame an interface will send, normally
1500 bytes on Ethernet. An overlay network adds headers, so the inner packet must
be smaller or it fragments. VXLAN's 50-byte header is why Flannel uses 1450.
Symptom of getting it wrong: small requests work, large ones hang.

---

## 3. Containers and Docker

**What is a container?**
A process, isolated by kernel namespaces and limited by cgroups, running against a
filesystem assembled from image layers. It is **not** a virtual machine — there is
no guest kernel; it shares the host's.

**Container versus VM?**
A VM virtualises hardware and runs a full guest OS with its own kernel — heavier,
stronger isolation. A container isolates a process on the host kernel — much
lighter, weaker isolation boundary.

**What is an image? What is a layer?**
An image is an ordered stack of read-only filesystem layers plus metadata. Each
Dockerfile instruction creates a layer. A container adds one writable layer on top
via a union filesystem (overlayfs); modifying an existing file copies it up into
the writable layer first.

**Why does layer order matter in a Dockerfile?**
A layer's cache is invalidated when its inputs change, and everything after it
rebuilds. So copy dependency manifests and install dependencies *before* copying
source:
```dockerfile
COPY go.mod go.sum ./
RUN go mod download        # cached unless dependencies change
COPY . .                   # changes on every edit
```
Reverse those and every one-line edit re-downloads every dependency.

**What is a multi-stage build and why use one?**
Build in one stage with the full toolchain, then `COPY --from=builder` only the
artefact into a minimal runtime image. The published image contains no compiler,
no source, no build cache — smaller to pull and a much smaller attack surface.

**Difference between a tag and a digest?**
A tag is a **mutable pointer**; `:latest` can point at different bytes tomorrow. A
digest (`@sha256:...`) is content-addressed and immutable. Deploy by digest or by
an immutable tag like a commit SHA — never `:latest`, or you cannot tell what is
running and cannot roll back.

**`CMD` versus `ENTRYPOINT`?**
`ENTRYPOINT` is the executable; `CMD` provides default arguments that a `docker
run` argument overrides. Use `ENTRYPOINT ["/app/binary"]` plus `CMD` for defaults.

**`COPY` versus `ADD`?**
`COPY` copies files. `ADD` also auto-extracts tarballs and can fetch URLs, which
is surprising behaviour. Prefer `COPY` unless you specifically want extraction.

**How do you make a container image smaller?**
Multi-stage build, a minimal base (`alpine`, `distroless`, `scratch`), combine
`RUN` steps that create and clean up in the same layer (a file deleted in a later
layer is still in the image), `.dockerignore`, and no build tools in the final
stage.

**Why not run as root in a container?**
Container root is namespaced root, which is less dangerous than host root but not
nothing — a kernel or runtime escape lands you as root on the host. Add a user and
`USER appuser`. It is also required by restrictive Pod Security Standards.

**Two things people always forget in a minimal image.**
`ca-certificates` — without it every outbound TLS call fails with a certificate
error that looks like a server problem — and timezone data.

**[stretch] What is the OCI, and what is containerd's role?**
The Open Container Initiative publishes three specs: image, runtime and
distribution. containerd is a runtime that manages images and containers and
delegates the actual process creation to `runc`; it sits behind Kubernetes' CRI.
Docker is a developer-facing toolchain on top of containerd.

---

## 4. Kubernetes core

**What problem does Kubernetes solve?**
It takes a declaration of what should be running and continuously makes reality
match it — scheduling, restarting, scaling, service discovery and rollout across a
set of machines.

**Explain the control plane components.**
- **kube-apiserver** — the only thing that talks to etcd; validates and serves all
  API requests.
- **etcd** — the datastore; all cluster state.
- **kube-scheduler** — assigns pending pods to nodes.
- **kube-controller-manager** — runs the built-in controllers that drive actual
  state toward desired.
- **kubelet** (per node) — makes the pods assigned to its node exist.
- **kube-proxy** (per node) — programs the rules that make Service IPs work.

**What is level-triggered reconciliation?**
Controllers compare desired state against actual state and act on the difference,
rather than reacting to a stream of events. That is why Kubernetes recovers from a
missed message: the next reconcile sees the same gap. Edge-triggered systems break
when an event is lost.

**Walk me through `kubectl apply -f deployment.yaml`.**
kubectl resolves the server's schema and sends the object → authentication →
authorization (RBAC) → admission (mutating webhooks, then validating) → persisted
in etcd → the Deployment controller creates a ReplicaSet → the ReplicaSet
controller creates Pods → the scheduler binds each Pod to a node → that node's
kubelet pulls the image and asks the runtime to start containers → kubelet reports
status back.

**Pod, ReplicaSet, Deployment — what does each add?**
A Pod is one or more co-located containers sharing a network namespace, and is
mortal. A ReplicaSet keeps N copies of a pod template running. A Deployment
manages ReplicaSets to give you rollouts and rollbacks. You write Deployments.

**When would you use a StatefulSet instead?**
When pods need stable identity: predictable names (`db-0`, `db-1`), a PVC per
replica, ordered start-up and shutdown, and a stable DNS name each. Databases and
anything doing leader election.

**DaemonSet? Job? CronJob?**
DaemonSet runs one pod per node — log collectors, CNI, node-exporter. A Job runs
to completion. A CronJob creates Jobs on a schedule.

**Service types?**
- **ClusterIP** — internal virtual IP (default).
- **NodePort** — a port on every node forwards in.
- **LoadBalancer** — asks the infrastructure for an external IP.
- **ExternalName** — a CNAME to an outside address, no proxying.

**Liveness versus readiness versus startup probe? This gets asked constantly.**
- **Liveness** — "is this process wedged?" Failure **restarts the container**.
- **Readiness** — "can this serve traffic?" Failure **removes it from Service
  endpoints** but does not restart it.
- **Startup** — disables the other two until the app has finished booting, for
  slow starters.

**The critical rule: never check an external dependency in a liveness probe.** If a
database outage fails liveness, every replica gets killed and restarted repeatedly
while the database is down — you have turned a recoverable dependency outage into
a crash-loop that cannot recover even after the database returns. Dependencies
belong in readiness.

**Requests versus limits?**
A **request** is what the scheduler reserves and what it uses to decide if a pod
fits. A **limit** is the ceiling at runtime. Exceeding a memory limit is
OOMKilled, immediately, no signal. Exceeding a CPU limit is throttling, not
killing.

**What are QoS classes?**
**Guaranteed** (requests == limits), **Burstable** (requests < limits),
**BestEffort** (neither set). Under node memory pressure the kubelet evicts
BestEffort first, then Burstable, then Guaranteed.

**ConfigMap versus Secret?**
Both are key-value objects mounted as files or environment variables. Secrets are
base64-encoded, not encrypted, unless you turn on encryption at rest. Treat the
difference as intent and RBAC, not as protection.

**A pod is `Pending`. How do you debug it?**
`kubectl describe pod` and read the **events** — that is where the answer almost
always is. Common causes: insufficient CPU/memory on any node, a PVC that cannot
bind, a node selector or affinity that matches nothing, an unsatisfied taint, or
no nodes Ready.

**`CrashLoopBackOff`?**
The container starts and exits repeatedly. `kubectl logs <pod> --previous` to see
the *crashed* container's output, not the new one's. Then check the command, the
config, whether a required env var or Secret is missing, and whether a liveness
probe is killing it before it is ready.

**`ImagePullBackOff`?**
Wrong image name or tag, a private registry with no `imagePullSecret`, or the
registry is unreachable. `kubectl describe` gives the registry's actual error.

**What is a namespace for?**
Scoping names, RBAC and resource quotas. It is not a security boundary by itself —
network isolation needs NetworkPolicies.

**Explain RBAC.**
A **Role** (namespaced) or **ClusterRole** (cluster-wide) lists verbs on
resources. A **RoleBinding** or **ClusterRoleBinding** grants it to a user, group
or ServiceAccount. Check what an identity can do with
`kubectl auth can-i --list --as=system:serviceaccount:ns:name`.

**[stretch] What is a taint and a toleration?**
A taint on a node repels pods; a matching toleration on a pod lets it be scheduled
there anyway. Used to reserve nodes — control-plane nodes are tainted so ordinary
workloads stay off them.

**[stretch] What is an admission webhook and how can it break a cluster?**
An HTTP service the API server calls to validate or mutate objects before they are
persisted. If its certificate expires or its pods are down and its
`failurePolicy` is `Fail`, every affected write is rejected — the cluster becomes
read-only for those resource types, and fixing it may itself require a write.

---

## 5. Kubernetes networking

**What are the rules of the Kubernetes network model?**
Every pod gets its own IP; pods can reach each other directly without NAT; and
what a pod sees as its own IP is what others see. Implementing that is the CNI
plugin's job.

**How does a Service actually work?**
A Service gets a virtual IP that nothing listens on. It selects pods by label, and
the endpoints controller keeps an EndpointSlice of the matching pod IPs.
kube-proxy on each node programs iptables (or IPVS) rules that DNAT traffic for
the Service IP to one of those pod IPs. The load balancing is packet-level, in the
kernel — there is no proxy process in the path.

**What breaks if a pod's labels do not match the Service selector?**
The Service has no endpoints and connections are refused or time out. The reverse
also bites: a pod that accidentally *does* carry the selector's labels joins the
Service and receives traffic it cannot serve — which is why a migration Job must
not be labelled like the Deployment it migrates for.

**How does DNS work in a cluster?**
CoreDNS runs as a Deployment behind a Service, usually `10.96.0.10`. Every pod's
`/etc/resolv.conf` points at it. `my-svc.my-ns.svc.cluster.local` resolves to the
Service's ClusterIP.

**[stretch] What is `ndots:5` and why does it matter?**
`resolv.conf` has `options ndots:5`, so any name with fewer than five dots is
first tried with each search domain appended. `google.com` becomes four failed
lookups before the correct one. It is a common source of DNS latency; a trailing
dot (`google.com.`) makes it absolute and skips the search list.

**Ingress versus Gateway API?**
Ingress is the older single-resource HTTP routing API, extended in practice by
vendor-specific annotations. Gateway API replaces it with role-separated
resources: **GatewayClass** (the implementation), **Gateway** (listeners and TLS,
owned by the platform team) and **HTTPRoute** (routing rules, owned by app teams).
The point is that an app team can add a route without touching shared
infrastructure.

**What is a NetworkPolicy?**
A namespaced firewall for pods, selected by label. Default is allow-all; as soon as
a pod is selected by any policy it becomes default-deny for that direction, and you
must list what is allowed.

**The trap everyone hits:** a default-deny **egress** policy with no rule for port
53 breaks DNS, and the symptom is every dependency appearing to be down. Always
add a DNS egress rule.

**How do you get external traffic into a bare-metal cluster?**
There is no cloud load balancer to ask, so a `LoadBalancer` Service stays
`Pending` forever. MetalLB fills the gap: in L2 mode it assigns an IP from a pool
and has one node answer ARP for it.

---

## 6. Kubernetes storage

**PV, PVC and StorageClass?**
A **PersistentVolume** is a piece of storage. A **PersistentVolumeClaim** is a
request for one. A **StorageClass** names a provisioner so that a PVC gets a PV
created on demand instead of an admin pre-creating it.

**Access modes?**
- **ReadWriteOnce (RWO)** — mounted read-write by **one node**. Not one pod — one
  node. Most block storage.
- **ReadOnlyMany** — many nodes, read-only.
- **ReadWriteMany (RWX)** — many nodes read-write. Needs a shared filesystem like
  NFS or CephFS.

**[stretch] Why does RWO plus RollingUpdate deadlock?**
A single-replica Deployment with `RollingUpdate` starts the new pod before
terminating the old one. If the new pod lands on a different node it waits for the
volume, and the volume waits for the old pod to release it. Deadlock. Use
`strategy: Recreate`, or a StatefulSet.

**What is CSI?**
The Container Storage Interface — a standard so storage vendors ship a driver
instead of code inside Kubernetes. The flow is Attach → NodeStage (mount once per
node) → NodePublish (bind-mount into the pod), and the reverse on teardown.

**What happens to a PVC's data when a pod is deleted?**
Nothing — that is the point. The PVC and PV survive. Whether the data survives
deleting the **PVC** depends on the StorageClass `reclaimPolicy`: `Delete` removes
the volume, `Retain` keeps it.

**`emptyDir` versus a PVC?**
`emptyDir` lives for the pod's lifetime on the node and vanishes with the pod —
fine for cache and scratch. A PVC outlives the pod.

---

## 7. Helm

**What is Helm and what is a chart?**
A package manager for Kubernetes. A chart is templates plus a `values.yaml`,
rendered into manifests. `Chart.yaml` has metadata and dependencies;
`templates/` holds Go-templated YAML.

**What is a wrapper chart (umbrella chart) and why use one?**
A chart whose only job is to declare an upstream chart as a dependency and supply
your values, plus any extra manifests of your own. It gives you one place for your
configuration, versioned in Git, without forking upstream.

**How do you debug a chart that produces the wrong thing?**
`helm template <name> <chart>` renders locally with no cluster, so you can read
exactly what would be applied. `helm lint` for structure, `helm diff upgrade`
(plugin) to see what an upgrade would change.

**Two Helm gotchas worth knowing.**
- **Helm does not validate values.** A typo'd key is silently ignored and you get
  chart defaults. There is no error; the manifest just does the wrong thing.
- **Lists are replaced, not merged.** Adding one entry to an `extraArgs` array
  means repeating every default the chart had, or you lose them.

**What does `helm upgrade --install` do?**
Installs if the release does not exist, upgrades if it does. Idempotent, which is
what you want in automation.

**[stretch] What is a Helm hook and how does it interact with GitOps?**
An annotation making a resource run at a lifecycle point (`pre-install`,
`post-install`). Under Argo CD, Helm hooks are translated to Argo hooks and are
**excluded from the diff**, so changing only a hook produces no visible drift and
no sync. You have to trigger a sync explicitly.

---

## 8. Git, GitOps and CI/CD

**`git merge` versus `git rebase`?**
Merge creates a commit joining two histories and preserves what actually happened.
Rebase replays your commits on top of another branch, giving linear history but
rewriting commit IDs. Never rebase a branch other people have pulled.

**How do you undo things?**
`git revert <sha>` makes a new commit undoing an old one — safe on shared
branches. `git reset --soft` moves the branch pointer and keeps changes staged;
`--hard` discards them. `git reflog` recovers from almost any mistake.

**What is a pull request for?**
Review, and a place to run automated checks before code reaches the main branch.
With a protected branch plus required status checks, it is the enforcement point.

**What is CI? What is CD?**
CI is automatically building and testing every change. CD is automatically
delivering it — "continuous delivery" means it is always *ready* to ship (a human
approves), "continuous deployment" means it ships without one.

**What is GitOps?**
Git is the single source of truth for the desired state of a system, and a
controller in the cluster continuously reconciles reality toward it. Deployment is
a `git merge`, not a pipeline pushing to a cluster.

**Why is pull-based better than a pipeline that runs `kubectl apply`?**
Three things. The cluster needs no inbound credentials handed to CI — the
controller pulls. Drift is corrected continuously rather than only when the
pipeline runs. And the audit trail is the Git history.

**What is Argo CD's sync status versus health status?**
**Synced** means the live objects match Git. **Healthy** means their controllers
report ready. They are independent — a perfectly Synced app can be completely
broken, and that is the single most misread signal in GitOps.

**[stretch] What are sync waves?**
An annotation ordering resources within one sync. Wave N must be created and
Healthy before N+1 starts. A Job is Healthy only once it has completed
successfully, which makes waves the right way to run a database migration before
the Deployment that needs the new schema.

**Describe a deployment pipeline you would build.**
On a pull request: lint, unit tests, build the image but do not push. On merge to
main: build and push tagged with the commit SHA, then update the manifest
repository with that tag. A controller picks up the manifest change and rolls it
out. Rollback is reverting the manifest commit.

**How would you do a zero-downtime deploy?**
A rolling update with readiness probes that are honest, `maxUnavailable: 0`, a
PodDisruptionBudget, and `terminationGracePeriodSeconds` long enough to drain
in-flight requests. The application must handle SIGTERM by stopping new work and
finishing what it has.

**What is blue-green? Canary?**
Blue-green runs two full environments and flips traffic at once — instant
rollback, double the resources. Canary sends a small percentage to the new version
and increases it while watching error rates.

---

## 9. Infrastructure as code

**What is IaC and why?**
Infrastructure defined in version-controlled files instead of by hand. You get
review, history, reproducibility, and the ability to rebuild rather than repair.

**Terraform versus Ansible — when do you use which?**
Terraform is **stateful and declarative**: it records what it created, so removing
a resource from the configuration **destroys** it. Right for provisioning things
whose existence you control. Ansible is **convergent and forgetful**: each run
moves the host toward the declared state and it has no memory — removing a task
leaves the thing it created behind, unmanaged. Right for configuring machines that
already exist.

Match the tool to the lifetime of the thing.

**What is Terraform state and why does it matter?**
A file mapping your resources to real-world IDs and their last-known attributes.
It is the source of truth for what Terraform believes exists. Lose it and
Terraform thinks nothing exists and tries to create everything. It contains
secrets in plaintext, so it needs protecting; in a team it needs a remote backend
with **locking**, because two concurrent applies corrupt it.

**`terraform plan` versus `apply`?**
`plan` shows what would change without changing it. `apply` does it. Always read
the plan — especially the destroy count and anything marked for replacement.

**What is idempotence and why does Ansible care?**
Running the same thing twice produces the same result. Ansible modules declare
desired state and check first, so a second run reports `ok` and changes nothing.
That is what makes it safe to run a playbook against a working system to verify it
still matches.

**What is an Ansible handler?**
A task that runs only if notified, and only once, at the end of the play — restart
a service once after any of six config changes. The catch: "at the end of the
play" is wrong if a later task depends on its effect, and then you need
`meta: flush_handlers`. The classic case is `daemon-reload` before `systemctl
enable`, which otherwise fails on the first run and works on the second.

**How do you handle secrets in IaC?**
Never in the repository. Ansible Vault, a secret manager (HashiCorp Vault, AWS
Secrets Manager) fetched at runtime, or CI-injected environment variables. In
Ansible, `no_log: true` on tasks handling them, because output ends up in CI logs
and screenshots.

**Why pin versions?**
An unpinned dependency means an upstream release can break your build at 3am with
an empty diff. And **a floor is not a pin**: `>=2.16` permits anything newer,
including a version that removed the API your other pinned tool imports.

---

## 10. Monitoring and observability

**What are the three pillars?**
Metrics (cheap, aggregated numbers over time), logs (high-cardinality detail about
individual events), traces (one request's path across services). Metrics tell you
*that* something is wrong; logs and traces tell you *why*.

**How does Prometheus work?**
It **pulls** — scrapes an HTTP `/metrics` endpoint on each target on a schedule and
stores the samples in a local time-series database. Targets are found by service
discovery.

**Consequences of pull instead of push?**
The target must be reachable from Prometheus, which is awkward for things behind
NAT or for batch jobs. In exchange, reachability is itself a free signal —
`up{job="x"} == 0` gives you liveness monitoring with no cooperation from the
application.

**The four metric types?**
**Counter** — only increases; use `rate()`. **Gauge** — goes up and down; read
directly. **Histogram** — bucketed observations, aggregatable, gives percentiles
server-side. **Summary** — client-computed quantiles, cheaper but not aggregatable
across instances, because the average of two p99s is not a p99.

**What is the most important PromQL gotcha?**
A target that does not exist produces **no data at all**, not zero. So
`up{job="x"} == 0` fires when the scrape fails but **cannot** fire when the scrape
config was deleted — there is no series to be zero, and an expression returning
nothing is not firing. You need `absent(up{job="x"})` as a companion alert.

**`rate()` versus `increase()`?**
The same calculation, different scaling: `rate` is per-second, `increase` is the
total over the window. Both handle counter resets correctly.

**What is cardinality and why is it dangerous?**
Every distinct combination of label values is a separate time series. A label
drawn from an unbounded set — user ID, request path with an ID in it, trace ID —
creates series without limit and kills Prometheus. Label by **route pattern**
(`/users/{id}`), never by path (`/users/8a3f...`). High-cardinality detail belongs
in logs.

**What makes a good alert?**
It is actionable, it fires before the user notices, and it says what to do. A good
rule of thumb: **alert on the mechanism failing, not on the eventual
consequence** — alert that the backup job failed, not that a restore found nothing;
that certificate renewal is failing, not that expiry is near. The mechanism fires
earlier and names the fix.

**What makes a bad alert?**
One nobody acts on. An alert firing for a known unfixable reason trains people to
ignore *all* alerts, and volume is itself a failure mode — a real critical can be
invisible inside a day's worth of warnings.

**What is Alertmanager for?**
Grouping, deduplication, silencing, inhibition and routing to receivers.
Prometheus decides *what is wrong*; Alertmanager decides *who hears about it*.

**What are SLI, SLO and error budget?**
An **SLI** is the measurement (99.2% of requests succeeded). An **SLO** is the
target (99.9%). The **error budget** is the allowed shortfall — 0.1% — and it is
what makes "should we ship or stabilise" a data question rather than an argument.

**How does Loki differ from Elasticsearch?**
Loki indexes only **labels**, not log content, and stores lines as compressed
chunks. The index is tiny and cheap; searching content means brute-forcing the
chunks your label selector matched. So you narrow first and grep second, which is
the opposite habit from Elasticsearch.

**Why structured logging?**
`{"level":"error","status":500,"duration_ms":1240}` is queryable by field. A
human-readable sentence is only greppable. Log lines are for a human reading one
line; log fields are for a machine reading a million.

---

## 11. Security and secrets

**What is the principle of least privilege?**
Every identity gets the minimum permissions needed. In Kubernetes: a
ServiceAccount per workload with a narrow Role, not `cluster-admin`.

**How should secrets be handled?**
Never in Git. A secret manager as the source of truth, fetched at deploy or
runtime. Rotatable, audited, and scoped. Kubernetes Secrets are base64, not
encrypted — enable encryption at rest and restrict `get secrets` by RBAC.

**Why is base64 not encryption?**
It is an encoding, reversible by anyone with `base64 -d`. It prevents accidental
reading, not deliberate reading.

**What is TLS and what does a certificate prove?**
TLS gives encryption in transit plus identity. A certificate binds a public key to
a set of names and is signed by a CA the client trusts. What matters is the
**Subject Alternative Name** — Common Name has been deprecated for host
identification for years, and a certificate valid for the wrong SAN is rejected.

**Certificate chain: what goes wrong most often?**
"Valid certificate, rejected by client" is almost always a **trust distribution**
problem, not a certificate problem — the client does not have the CA in its trust
store. Browsers, language runtimes and containers all keep their own.

**How do you secure a container image?**
Minimal base, non-root user, no secrets baked in, pinned base image, scan for
known vulnerabilities (Trivy, Grype) in CI, and a read-only root filesystem where
possible.

**[stretch] What would you check in a Kubernetes security review?**
RBAC for over-broad bindings, ServiceAccount token automounting where it is not
needed, privileged containers and `hostPath` mounts, NetworkPolicies (is anything
default-deny?), Pod Security Standards enforcement, secrets encryption at rest,
admission control, and whether the API server is reachable from where it should
not be.

**How would you rotate a leaked credential?**
Find **every** copy first — a secret usually lives in more than one place: the
manager, a derived Kubernetes Secret, pod environment variables, and the system
that validates it. Then change them in order, restart consumers (env vars are read
once at startup), verify, and finally **destroy the old versions** — a soft delete
in most secret managers is reversible, which means the leaked value is still
readable. The rotation is not finished until you have confirmed no readable
history remains.

---

## 12. Databases and SQL, lightly

**What is an index and what does it cost?**
A structure making lookups on a column fast, at the cost of extra writes and
storage. Postgres indexes primary keys and unique constraints automatically and
**nothing else** — a foreign key you query on needs its own index, or you get a
sequential scan.

**What is a transaction? What does ACID mean?**
A unit of work that either fully happens or does not. Atomicity, Consistency,
Isolation, Durability.

**`TIMESTAMP` versus `TIMESTAMPTZ`?**
`TIMESTAMPTZ` stores an absolute instant; plain `TIMESTAMP` stores a wall-clock
reading with no zone, so two rows written in different timezones cannot be ordered.
Always use the `tz` variant.

**What is a database migration and how do you run one safely?**
A versioned schema change, applied in order and recorded in a table. Safely:
migrate before deploying the code that needs it, keep changes
backward-compatible so old and new code can both run during a rollout, use a lock
so two runners cannot apply the same migration, and write the down migration even
if you never run it.

**[stretch] What is crash-consistent versus transactionally consistent backup?**
Copying a running data directory gives you crash consistency — the database
recovers on start exactly as it would after a power cut, which is safe but logs
alarming things. Transactional consistency needs a `pg_dump` or a pre-backup
checkpoint hook.

---

## 13. Troubleshooting and scenarios

These are the highest-signal questions. They want your *method*, not the answer.

**"The website is down. Go."**
Narrow the layer before touching anything. Is it down for everyone or just me
(DNS, or my network)? Does the load balancer have healthy backends? Are the pods
Running and Ready? Does a pod IP answer directly — if yes but the Service does not,
it is Service/kube-proxy; if no, it is the application. Check recent changes
first, because most incidents follow one. Then logs, then metrics for when it
started.

**"Deploys are fine but the app is slow."**
Establish where: client, network, ingress, app, or database. Check p99 latency, not
average. Look for the obvious multipliers — an N+1 query, a missing index, a
connection pool exhausted, a noisy neighbour, CPU throttling from a limit that is
too low.

**"A node is NotReady."**
`kubectl describe node` for conditions — `MemoryPressure`, `DiskPressure`,
`NetworkUnavailable`. Then on the node: is the kubelet running, can it reach the
API server, is the disk full, is the container runtime healthy. `systemctl status
kubelet` and `journalctl -u kubelet`.

**"You're paged at 3am for high memory. What do you do?"**
Stabilise first, diagnose second. Is it affecting users? If so, mitigate — roll
back the recent change, scale out, restart the offending pod — then investigate
with the pressure off. Write down what you did as you go, because the postmortem
needs a timeline.

**"How do you know your backups work?"**
By restoring from one. Everything else is a hope. A backup job reporting success
proves it ran, not that the output is usable — check that the archive verifies and
that a restore produces the *rows you expected*, compared against something you
recorded beforehand. An empty database is a *working* database, and a restore into
one reports success.

---

## 14. Behavioural, with the shape of a good answer

Use **STAR**: Situation, Task, Action, Result. Keep it to 90 seconds and make the
result a number wherever you can.

**"Tell me about a time you broke production."**
They are testing honesty and whether you learned. Pick something real, own it
without grovelling, and spend most of the answer on the control you added so it
cannot recur. Never blame a person.

**"Tell me about a difficult debugging problem."**
The best answers show a method: what you observed, what hypotheses you formed, how
you ruled each out, and what the evidence was. Mentioning a hypothesis you were
*wrong* about makes it credible.

**"How do you handle disagreement with a colleague?"**
Look for the shared goal, make the disagreement about evidence rather than
preference, propose a cheap experiment to settle it, and be willing to be wrong in
public.

**"Why do you want this role?" / "Where do you see yourself?"**
Be specific about *their* stack and problems. Generic ambition reads as no
research.

**"What are your weaknesses?"**
One real one, with what you are actively doing about it. Not a humblebrag.

---
---

# Part 2 — Answered from this project

This is the part that differentiates you. The facts below are all measured or
recorded in this repository, so you can say them with confidence and point at the
file.

## 15. The elevator description

> I built a production-shaped Kubernetes platform from scratch on three VMs on one
> laptop — kubeadm cluster, Flannel, Longhorn storage, Vault and External Secrets,
> Argo CD for GitOps, Prometheus and Alertmanager, Velero backups, and a Go API
> behind Gateway API. What I actually learned came from it breaking four times: I
> have three written postmortems, and most of the platform's controls exist because
> something failed silently and nothing told me.

Then stop and let them pick a thread. Every thread below has a real answer.

## 16. Architecture questions

**Describe your architecture.**
Four declarative layers, each with a narrow handoff. Terraform creates the libvirt
network and three guests and stops at "a machine that boots with an address and an
SSH key". Ansible takes it to "three Ready nodes" — kernel modules, sysctls,
containerd, kubeadm, Flannel, joining workers. Argo CD owns everything inside the
cluster, 17 Applications from Git. CI builds the image and opens a PR to bump the
manifest, so the merge is the deploy.

**Why did you split it that way?**
Because the reconciliation models differ. Terraform is stateful — deleting a
resource from the config destroys it, which is right for machines and wrong for OS
config. Ansible is convergent and forgetful. Argo CD is a controller that
continuously self-heals, which is right for cluster objects that drift. Using
Terraform for in-cluster resources would mean drift is only fixed when I run it.

**Why Gateway API and not Ingress?**
Role separation. The Gateway with its listeners and TLS is platform-owned; an
HTTPRoute is app-owned. An app team adds a route without touching shared config.
Ingress pushes everything through vendor-specific annotations on one object.

**How does traffic get in with no cloud load balancer?**
A `LoadBalancer` Service on bare metal stays Pending forever, because there is
nothing to fulfil it. MetalLB in L2 mode assigns an IP from a pool and has one
node answer ARP for it. Then Envoy Gateway, then HTTPRoute, then the Service.

## 17. The incidents — your strongest material

### Incident 1: etcd corruption, 14 hours of no API server

**What happened?**
The single etcd member corrupted and the API server crash-looped. My first
recovery attempts made it worse — I ran `snapshot restore` against a raw
`member/snap/db` file, then `--force-new-cluster`, and got a cluster with only the
default namespaces. So I **stopped, preserved raw copies of the data directory,
and moved to offline analysis.** I wrote Go tools to read the bbolt pages, the WAL
and the Kubernetes protobuf payloads, and rebuilt a working database. Fourteen
hours total.

**What was the real root cause?**
Not conclusively established, but the strongest candidate was found six days later:
the emulated e1000 NIC hanging under load, which produces exactly the
symptom I recorded at the start — every namespace failing simultaneously with
"network is unreachable" and no single application at fault.

**What actually turned a fault into a disaster?**
Not the fault. There were **no etcd backups at all**, Velero existed but its volume
restore had never worked, and nothing told me either of those things. The blast
radius was invisible.

**The best detail — and lead with this one.**
Three days after I declared it recovered, a routine check found the rebuilt
database was **structurally damaged but functional**. Four stray records sat
outside any bucket in the bbolt file, so every snapshot taken from it failed
integrity checks. And the first time that check failed, on the day I declared
success, **I explained it away as an etcdctl version mismatch** — which was
plausible, because in etcd 3.6 those subcommands moved to `etcdutl`. It was real.
So for three days the cluster ran correctly while every backup it produced was
unverifiable.

Two lessons I now apply everywhere: **when verification fails, believe it**, and
**software that runs is not software that is correct.**

**What did you change?**
Thirteen action items, eleven done: encrypted etcd snapshots every six hours,
integrity-checked *inside the job before the bundle is written* so a corrupt
snapshot never becomes a backup; automatic off-node copies; a tested restore;
staleness and absence alerts; Alertmanager to Discord; control-plane metrics
actually reachable; host config moved into Ansible roles; the Vault root token
revoked.

### Incident 2: host sleep, and the alert that could not fire

**What happened?**
The laptop went to S3 sleep overnight with the VMs running. On resume, I/O that
had been outstanding for ten hours was failed back to the guests as
`critical medium error` — a SCSI media fault, on perfectly healthy disks. ext4 did
exactly the right thing and remounted read-only. Two hours to recover.

**The number to quote.**
etcd WAL fsync p99 was **15 ms at idle and 1,341 ms under Longhorn rebuild**, against
etcd's target of under 10 ms. The host disk showed 100% active time and a 16,451 ms
average response time. `kube-controller-manager` restarted **47 times**, every one
on `Failed to update lease: context deadline exceeded` — because lease renewal is
an etcd write, and it could not finish inside the 5-second deadline.

**And the finding that taught me the most.**
I had written the alert for exactly this failure **the day before**, and it stayed
silent. Prometheus stores its TSDB on a Longhorn volume on the same disk, so its
pod was Pending for most of the incident — there was no data to evaluate, and never
ten continuous minutes of it afterwards.

That is not a threshold to tune. **Monitoring that shares a failure domain with
what it monitors cannot report on that domain.** The fix is to move it out of the
domain or put the signal outside it, and it is still open.

**Anything else?**
Two pre-existing failures were found by accident, by running `kubectl get pods -A
| grep -v Running` by hand during recovery. Argo CD reported every application
Healthy throughout — because Healthy means the objects match Git and their
controllers report ready, which a component restarting 47 times satisfies.
`KubePodCrashLooping` also never fired, because it needs rapid consecutive
failures and this one ran fine for minutes between exits, so the backoff kept
resetting. I now alert on restart **rate**, not crash **state**.

### Incident 3: two databases corrupted by one event

**What happened?**
The host was reset abruptly twice in three days — once unplanned, once by Windows
Update rebooting itself with all three guests running. Each reset corrupted a
bbolt database on the control plane: etcd's both times, and containerd's own
metadata store the second time.

**How did you diagnose it?**
This is my favourite piece of reasoning in the project. bbolt is specifically
engineered to survive power loss. **One** corrupted database suggests an
application bug. **Two independent programs, damaged by one event, on media with
clean SMART, does not** — the fault has to be beneath both of them. So writes were
being lost or reordered somewhere between the guest's `fsync` and the platter.

I also ruled things out with evidence rather than assumption. Failing media:
excluded by storage reliability counters showing zero read and write errors on
both drives. A bad backup as the cause of the second corruption: excluded by
arithmetic — the crashing compaction covered revisions after the revision the
restore had left the database at, so the corrupt page was in data written *after*
the restore.

**Why did recovery take six hours if the restore took twenty minutes?**
A nine-layer dependency chain, and each layer was only diagnosable once the one
beneath it was fixed. containerd's metadata was discarded, so the node re-pulled
about forty images; CoreDNS was down meanwhile, so there was no cluster DNS; so
`longhorn-manager` could not resolve its own webhook and crash-looped; so it never
bound its port; so the CSI plugin could not reach the backend; so no CSI driver
registered; so no volume could attach; so Vault, Postgres and the whole monitoring
stack were stuck. **Nine layers, one cause, and not a single bug** — every one was
a correct failure of a component waiting on a dependency.

**The best debugging trick from it.**
It stalled again one layer up, with kube-proxy on both workers holding stale
iptables rules. I diagnosed it by finding that a worker could reach a backend
**pod IP** directly — connection refused in 0 ms, so routing was fine — but not the
**ClusterIP**, which timed out. Pod IP works and ClusterIP does not means
kube-proxy. Two `curl`s.

**And the worst finding?**
The alerting was broken at **both ends** and it predated the incident. The right
alerts existed and named this exact failure. But an orphaned container was holding
`hostNetwork` port 9100, so the node-exporter pod could not bind and nothing was
ever scraped — 230 restarts over six days. And Alertmanager's webhook came from
the wrong Vault path and served a revoked URL. External Secrets reported
`SecretSynced` the entire time, and it was telling the truth: it had successfully
read a value and written it. That the value was revoked is not something it can
know.

The metric file was sitting on disk, accurate and current, and invisible. **The
monitoring for backups was itself unmonitored.**

**How do you verify alerting now?**
End to end, by counting. The action item says "alerting verified end to end, 33
Discord notifications, 1 failure" — not "the rules are valid".

## 18. The questions they will ask about your judgement

**Three components came back Ready and not working. Tell me about that.**
containerd reported healthy with `NRestarts=0` while ten orphaned containers were
still running, invisible to `crictl`, `kubectl` and the kubelet — one of them a
**second kube-proxy programming iptables**, which is what caused the stale-rules
cascade. The etcd defrag timer reported a fresh success timestamp on runs that
never reached etcd. And Velero's node-agent showed `1/1 Running` while failing
every volume backup instantly, for **three days**, because its pod cache was stale.

None would have been caught by a readiness probe. Each needed its own check: shim
count against sandbox count, the metric file read for name-with-no-value lines,
and the newest PodVolumeBackup checked for non-zero `bytesDone`. `Ready` is a
liveness claim, not a correctness one, and those three checks are now numbered
steps in the startup runbook.

**Your restore drill failed the first time. What happened?**
I passed `--include-resources` to keep the sandbox tidy, listing PVCs, Secrets,
ConfigMaps, Services, StatefulSets and ServiceAccounts. Two things broke. The PVC
could not bind, because with PVs excluded it kept `spec.volumeName` pointing at the
PV the *live* database was using. And no data was restored at all, because Velero
does a filesystem restore by injecting an init container into the restored **Pod**,
and I had excluded Pods.

The second one is the dangerous one: **had the PVC bound, Postgres would have
started cleanly on an empty disk and the restore would have reported success.** An
empty database is a working database. The only check that catches it is comparing
rows against something recorded beforehand — I diff a dump and compare sha256.

Lesson: never narrow a filesystem restore by resource type. Select by label.

**What surprised you most about recovery ordering?**
That Postgres cannot be restored from Velero alone. Its password comes from a
Secret that External Secrets renders from Vault, and that Secret carries ESO's
labels, not PostgreSQL's — so a label-selected restore does not include it, and the
pod fails with `secret "postgresql-credentials" not found` and
`CreateContainerConfigError`. Nothing in that message suggests the answer is *go
and unseal Vault*.

So the recovery order is fixed: **Vault, then External Secrets, then Postgres.** It
was correct on both real restores. Generally: work out the order in advance by
asking what each component reads at startup and who produces it.

**Why does nothing start until you unseal Vault by hand?**
Because the alternative is worse. Vault prints five Shamir unseal shares once and
three are needed; they are in a password manager and nothing in the cluster holds
them. `make up` deliberately stops at that point. A pipeline that generates unseal
shares and then stores them somewhere it can read them again has produced
encryption with the key taped to the box. It is an availability cost bought for a
real security property.

**Why is a backup key not in Vault?**
Because Vault's own data is inside those backups. A key stored there could not
decrypt the backup you need in order to get Vault back. It lives in three failure
domains — a file on the laptop, a password manager, and paper — and the cluster
holds only the public half, so a fully compromised control-plane node cannot read
its own backup history.

**How did you verify that?**
Not by looking for the files. I derived the public half from each copy with
`age-keygen -y`, which only ever emits the public key, compared hashes against the
recipient committed in Git, confirmed the deployed recipient matched, and then
**decrypted a real archive and listed its contents** — because deriving the same
public key proves the key pair is right and only a decrypt proves the archive is
readable. Then I found a leftover working copy of the private key in a home
directory and shredded it. I recorded the outcome as an *accepted risk*, not as
resolved, because two copies plus paper is a tradeoff and not the elimination of a
problem.

**Your backups are pulled, not pushed. Why?**
So that a fully compromised cluster cannot delete its own off-site backups. The
laptop pulls hourly over SFTP with a key restricted three ways — `restrict` to
disable forwarding and PTY, `from=` to limit the source address, and `command=`
forcing the SFTP server with `-R` for read-only, so the key cannot get a shell.

That last link had **no monitoring of its own** and failed ten times overnight
without anyone noticing, because Prometheus cannot scrape the laptop and the
laptop must not be able to write into the cluster. The fix I am proudest of: cp01
watches **its own sshd log** for successful pull logins and exposes the timestamp
as a metric. When you cannot instrument a component, instrument the evidence it
leaves behind.

**Tell me about a monitoring bug you found.**
MinIO — which holds every Velero backup — had no metrics at all from installation
until I checked. The ServiceMonitor existed, was valid, and Argo CD reported the
app Synced and Healthy. It was missing one label:
`release: kube-prometheus-stack`, which every selector on the Prometheus CR
requires. A resource without it is silently ignored — not rejected.

I found it by asking Prometheus what it actually held: **1,879 metric names, zero
matching `minio_*`**. Not by checking that the ServiceMonitor existed, because it
did. That is now a habit — verify monitoring by querying the metric names, not by
confirming the config object exists.

**Tell me about a time too much monitoring was the problem.**
`VeleroBackupTooOld` fired at critical for **23 hours** while application data had
no backup for three days. Every rule fired, routing worked, and Alertmanager
delivered **72 of 72** notifications with zero failures. Nobody acted, because
that critical arrived in the same stream as 38 warnings that day.

It is the exact opposite of the missing-instrumentation problem and needs the
opposite fix. Adding a fourth Velero rule would have made it worse. The fix was
cadence: warnings re-notify every 24 hours, criticals every hour. Volume is a
failure mode.

## 19. The sharpest thing you can say about verification

If they ask how you know something works, this is the answer — and it is unusual
enough to be memorable.

> Most of my controls exist because a check that couldn't fail told me everything
> was fine. So now I run every check against known-bad input before I trust it.

With examples you can produce on demand:

- A grep for a secret **matched its own search commands** in shell history — the
  count grew from 4 to 8 as I kept searching.
- A CI check for a banned registry **matched the comment explaining why it was
  banned**, because Helm passes template comments through to rendered output.
- A check read an exit code from `tail` at the end of a pipeline and labelled it
  "grep exit". `tail` almost always succeeds.
- A check ran `gh run view --log` with `2>/dev/null` and got **zero bytes with exit
  code 0**, and passed on an empty string, every time.
- A cleanup grep reported the repository clean while **four more copies survived**,
  because each author had worded the claim differently and one wrapped across two
  lines, defeating line-based matching.

So the rules are: parse and assert on the parsed value rather than grepping a
document; put a vacuity guard in every check so it fails if it examined nothing;
and validate a check against a state you know is bad before you believe it. My CI
has `assert configmaps > 0`, `assert n > 0` and `assert scanned > 0` for exactly
that reason.

## 20. Honest answers to "what would you do differently"

Have these ready. Being able to criticise your own work is what separates mid from
junior.

- **A dead-man's switch, first.** The absence of notifications should itself be an
  alert. I route `Watchdog` to null because there is no external service to
  receive it, and that is the single cheapest improvement left.
- **Prometheus's storage off the disk it monitors.** I knew the volume was
  convenient; I did not foresee that it makes the monitoring blind during exactly
  the incidents that matter.
- **Static addresses from the start.** The API server certificate is pinned to what
  is actually a DHCP lease, so any change that alters the guest MAC is a latent
  hazard. It also blocks the NIC change I want to make.
- **Structured logging from day one.** `log.Printf` is greppable, not queryable,
  and retrofitting fields is more work than starting with them.
- **Instrumentation is not optional.** The application returned 500 from every
  data endpoint for eight hours and nothing could have alerted, because it exposed
  no request metrics at all. The best monitoring stack cannot monitor an
  application that emits nothing.

## 21. Questions to ask them

Asking good questions is scored. These get real answers.

- How do you find out something is broken — who gets paged, and how often is it a
  false alarm?
- What does your deploy look like, and how long from merge to production?
- When did you last restore from a backup, deliberately?
- Do you write postmortems, and are they blameless? Can I read one?
- What is the oldest thing in the stack nobody wants to touch?
- What would I own in the first three months?
- How much of the infrastructure is in code, honestly?

That third one is a very good question to ask, and the answer tells you a great
deal about the team.

---

## 22. Two-week revision plan

| Day | Focus |
|---|---|
| 1–2 | Linux and networking fundamentals (§1, §2). Say the answers out loud. |
| 3–4 | Containers and Docker (§3). Write a multi-stage Dockerfile from memory. |
| 5–7 | Kubernetes core (§4). Probes, requests/limits and debugging are the most-asked. |
| 8 | Kubernetes networking and storage (§5, §6). |
| 9 | Helm, Git, GitOps, CI/CD (§7, §8). |
| 10 | IaC (§9). Be crisp on Terraform-versus-Ansible. |
| 11 | Monitoring and security (§10, §11). |
| 12 | Scenarios (§13) — practise the *method*, not answers. |
| 13 | Part 2. Rehearse the three incidents as 90-second STAR stories. |
| 14 | Behavioural (§14) and your questions for them (§21). |

Two things to practise out loud, because they are what you will actually be asked
first: the elevator description in §15, and one incident in 90 seconds. If you can
do those two well, the rest of the interview is you being asked to go deeper on
things you actually did.

---

## Related

- `docs/architecture/platform-architecture.md` — the diagram to sketch on a whiteboard
- `docs/adr/` — why each decision was made, if they ask "why not X instead"
- `docs/incidents/` — the three postmortems, in full
- `docs/roadmap.md` — what you would do next, and why in that order
