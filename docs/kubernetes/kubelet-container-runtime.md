\# kubelet, CRI, containerd and runc



\## kubelet



The kubelet is the Kubernetes node agent.



Its responsibility is to ensure that Pods assigned to its node are running according to their specifications.



Conceptually:



```text

API Server

&#x20;   ↓

kubelet

&#x20;   ↓

container runtime

```



The kubelet does not directly execute containers.



\## Container Runtime Interface



CRI stands for:



```text

Container Runtime Interface

```



It provides the interface between kubelet and a compatible container runtime.



Conceptually:



```text

kubelet

&#x20;  ↓

CRI

&#x20;  ↓

container runtime

```



Common runtime implementations include:



\- containerd

\- CRI-O



\## containerd



containerd manages container lifecycle and related functionality.



Conceptually:



```text

kubelet

&#x20;  ↓

CRI

&#x20;  ↓

containerd

```



containerd handles functionality such as:



\- image management

\- container lifecycle

\- snapshotters

\- runtime integration



\## runc



runc is a low-level OCI container runtime.



Conceptually:



```text

containerd

&#x20;  ↓

runc

&#x20;  ↓

Linux kernel

```



It participates in creating and starting the actual container process.



\## OCI



OCI stands for:



```text

Open Container Initiative

```



OCI defines standards related to container images and runtimes.



\## Container vs VM



A container does not normally contain its own Linux kernel.



Containers use the host Linux kernel with isolation mechanisms such as:



\- namespaces

\- cgroups

\- filesystem isolation

\- Linux networking



\## Linux Namespaces



Important namespaces include:



```text

PID

NET

MNT

IPC

UTS

USER

CGROUP

TIME

```



Namespaces provide isolation.



\## PID Namespace



A process can have a different PID inside a container than on the host.



Conceptually:



```text

Host PID

&#x20;  ↓

Container PID namespace

&#x20;  ↓

PID 1

```



\## Network Namespace



Containers can have isolated network namespaces.



Kubernetes networking builds on Linux networking primitives.



\## Mount Namespace



Mount namespaces provide a separate filesystem mount view for processes.



\## cgroups



cgroups provide resource accounting and control.



Examples:



```text

CPU

Memory

PIDs

I/O

```



The Ubuntu template uses cgroup v2.



Check with:



```bash

mount | grep cgroup

```



\## Kubernetes Resources and cgroups



Kubernetes resource configuration eventually interacts with Linux cgroups.



Example:



```yaml

resources:

&#x20; requests:

&#x20;   cpu: "500m"

&#x20;   memory: "512Mi"

&#x20; limits:

&#x20;   cpu: "1"

&#x20;   memory: "1Gi"

```



Requests influence scheduling.



Limits establish workload resource boundaries implemented through underlying runtime/kernel mechanisms.



\## OOMKilled



A container exceeding its effective memory boundary can be affected by Linux memory management and OOM handling.



Kubernetes may report:



```text

OOMKilled

```



\## Images and Containers



Image:



```text

immutable template

```



Container:



```text

running instance created from an image

```



Conceptually:



```text

Image

&#x20;├── Container A

&#x20;├── Container B

&#x20;└── Container C

```



\## Image Pull



Simplified flow:



```text

kubelet

&#x20;  ↓

CRI

&#x20;  ↓

containerd

&#x20;  ↓

registry

&#x20;  ↓

image

```



\## ImagePullBackOff



Possible causes include:



\- incorrect image name

\- incorrect tag

\- registry unavailable

\- authentication failure

\- DNS failure

\- network failure

\- registry rate limiting

\- private registry configuration



\## Pod Network and CNI



Container runtime and networking are separate concerns.



Conceptually:



```text

kubelet

&#x20;├── CRI → container runtime

&#x20;│

&#x20;└── networking → CNI

```



\## Pod Storage and CSI



Storage is another separate interface:



```text

kubelet

&#x20;├── CRI → container runtime

&#x20;├── CNI → networking

&#x20;└── CSI → storage

```



\## Pod Startup Flow



After scheduling:



```text

API Server

&#x20;   ↓

Pod assigned to node

&#x20;   ↓

kubelet

&#x20;   ↓

CRI

&#x20;   ↓

container runtime

&#x20;   ↓

network setup

&#x20;   ↓

image pull

&#x20;   ↓

container creation

&#x20;   ↓

container start

&#x20;   ↓

kubelet monitoring

&#x20;   ↓

status reported to API Server

```



\## kubelet Status Reporting



The kubelet reports observed node and Pod state back to the Kubernetes API.



Conceptually:



```text

spec

&#x20;↓

desired state



kubelet

&#x20;↓

observed state

&#x20;↓

status

```



\## Health Probes



Kubernetes supports:



```text

startupProbe

readinessProbe

livenessProbe

```



Simplified:



```text

startupProbe

&#x20;   ↓

application initialization



livenessProbe

&#x20;   ↓

should container be restarted?



readinessProbe

&#x20;   ↓

should Pod receive traffic?

```



\## Pod Sandbox



A Pod provides a shared environment for its containers.



Conceptually:



```text

Pod

&#x20;├── sandbox/network

&#x20;├── container A

&#x20;└── container B

```



Containers in the same Pod share the Pod network namespace.



\## Runtime Troubleshooting



Useful commands include:



```bash

systemctl status kubelet

systemctl status containerd

crictl info

crictl pods

crictl ps

crictl images

```



\## Runtime Failure



If containerd fails:



```text

kubelet

&#x20;  ↓

CRI

&#x20;  ↓

containerd ❌

```



Container management on that node is affected.



\## kubelet Failure



If kubelet fails:



```text

kubelet ❌

```



The node's Kubernetes agent cannot perform its normal responsibilities.



\## Troubleshooting Model



```text

Pod Pending

&#x20;   ↓

scheduler / constraints



ContainerCreating

&#x20;   ↓

kubelet / CRI / runtime / image / CNI / CSI



Container exits

&#x20;   ↓

application / runtime



OOMKilled

&#x20;   ↓

memory / cgroup / Linux kernel

```



\## Complete Execution Path



```text

API Server

&#x20;   ↓

Scheduler

&#x20;   ↓

Pod assigned to node

&#x20;   ↓

kubelet

&#x20;   ↓

CRI

&#x20;   ↓

containerd

&#x20;   ↓

runc

&#x20;   ↓

Linux kernel

&#x20;   ↓

namespaces + cgroups

&#x20;   ↓

Linux process

```

