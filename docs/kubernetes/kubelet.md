\# kubelet Deep Dive



\## Overview



kubelet is the primary Kubernetes node agent.



It ensures that Pods assigned to the node are running according to their specifications.



\---



\## Architecture



```text

API Server

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

```



\---



\## Responsibilities



\- Pod lifecycle management

\- Container lifecycle coordination

\- Runtime interaction

\- Node status reporting

\- Health probes

\- Volume handling

\- Secret and ConfigMap handling

\- Static Pods

\- Resource management

\- Node pressure handling



\---



\## Pod Lifecycle



```text

Scheduler assigns Pod

&#x20;       ↓

kubelet observes Pod

&#x20;       ↓

Prepare Pod

&#x20;       ↓

Configure volumes/network

&#x20;       ↓

Pull image if required

&#x20;       ↓

Create container

&#x20;       ↓

Start container

&#x20;       ↓

Run probes

&#x20;       ↓

Report status

```



\---



\## CRI



kubelet communicates with the container runtime through the Container Runtime Interface.



\---



\## Static Pods



kubelet can manage static Pods from local manifests, commonly:



```text

/etc/kubernetes/manifests/

```



\---



\## Health Probes



\- Startup probe

\- Readiness probe

\- Liveness probe



\---



\## Node Health



kubelet reports node health and maintains node heartbeats.



Important conditions include:



\- Ready

\- MemoryPressure

\- DiskPressure

\- PIDPressure



\---



\## Resource Management



kubelet participates in enforcing Pod resource constraints and managing node resource pressure.



\---



\## Troubleshooting



\### Pending



Investigate the Scheduler.



\### ContainerCreating



Investigate kubelet, runtime, CNI, CSI, image and volumes.



\### ImagePullBackOff



Investigate image name, registry connectivity and credentials.



\### CrashLoopBackOff



Investigate the application and its configuration.



\### Node NotReady



Investigate kubelet, runtime, network, disk, memory and API Server connectivity.



\---



\## Key Takeaways



\- kubelet is the node agent.

\- kubelet does not directly run containers.

\- kubelet communicates with the runtime through CRI.

\- containerd manages containers.

\- runc provides the low-level OCI runtime.

\- kubelet manages Pod lifecycle and reports node status.

\- Static Pods are managed directly by kubelet.

