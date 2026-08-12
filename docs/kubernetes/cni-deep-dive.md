\# CNI Deep Dive



\## What Is CNI?



CNI stands for:



```text

Container Network Interface

```



CNI provides the mechanism used to configure networking for containers/Pods.



CNI is an interface/specification, not a single networking implementation.



Examples of CNI/networking implementations include:



\- Calico

\- Cilium

\- Flannel



\## Pod Network Creation



Simplified flow:



```text

Pod scheduled

&#x20;   ↓

kubelet

&#x20;   ↓

container runtime

&#x20;   ↓

network namespace

&#x20;   ↓

CNI

&#x20;   ↓

interface + IP + routes

&#x20;   ↓

Pod networking ready

```



\## Network Namespace



The Pod normally receives its own network namespace.



It contains networking state such as:



\- interfaces

\- routes

\- sockets

\- neighbour information



\## veth Pair



A veth pair connects two Linux network namespaces.



Conceptually:



```text

Pod namespace



eth0

&#x20;│

&#x20;║ veth pair

&#x20;│

Host namespace



vethXXXX

```



The veth pair acts like a virtual Ethernet cable.



\## IPAM



IPAM means:



```text

IP Address Management

```



It allocates Pod IP addresses from configured address ranges.



Example:



```text

Pod A → 10.244.1.10

Pod B → 10.244.1.11

Pod C → 10.244.1.12

```



\## Pod CIDR



A cluster can allocate a Pod network range.



Example:



```text

10.244.0.0/16

```



Nodes can receive portions of the range.



Example:



```text

worker-1 → 10.244.1.0/24

worker-2 → 10.244.2.0/24

```



The exact ranges depend on cluster configuration.



\## Routing



Nodes need to know how to reach Pod networks.



Conceptually:



```text

worker-1

10.244.1.0/24 → local



10.244.2.0/24 → worker-2

```



Linux routing tables provide the underlying routing mechanism.



\## CNI Configuration



CNI configuration is commonly found under:



```text

/etc/cni/net.d/

```



CNI binaries are commonly found under:



```text

/opt/cni/bin/

```



The exact contents depend on the installed CNI.



\## Loopback



A Pod network namespace normally contains:



```text

lo

eth0

```



The loopback interface is used for local communication.



\## Same-Node Pod Networking



A simplified bridge-based design may look like:



```text

Pod A

&#x20; │

veth

&#x20; │

bridge

&#x20; │

veth

&#x20; │

Pod B

```



Not every CNI uses a Linux bridge.



\## Cross-Node Networking



Example:



```text

worker-1

Pod A → 10.244.1.10



worker-2

Pod B → 10.244.2.10

```



The CNI must provide connectivity between the nodes.



Possible approaches include:



\- routing

\- encapsulation

\- eBPF-based networking



\## Calico



Calico provides Kubernetes networking and NetworkPolicy functionality.



Depending on configuration, Calico can use routing-based networking and other dataplane mechanisms.



Important components and concepts include:



\- IPAM

\- routing

\- NetworkPolicy

\- Felix

\- BIRD in relevant routing configurations



\## Cilium



Cilium is heavily based on eBPF.



Conceptually:



```text

Pod

&#x20;↓

Linux networking

&#x20;↓

eBPF dataplane

&#x20;↓

forwarding / policy / observability

```



Cilium can also provide Service dataplane functionality and other features depending on configuration.



\## Flannel



Flannel is primarily focused on Pod networking.



Depending on configuration it can use mechanisms such as:



\- VXLAN

\- host-gw



\## High-Level Comparison



| CNI | Primary characteristic |

|---|---|

| Calico | Networking, routing and NetworkPolicy |

| Cilium | eBPF-based networking, policy and observability |

| Flannel | Simpler Pod networking |



The actual behavior depends on configuration.



\## NetworkPolicy



NetworkPolicy defines traffic rules.



Example:



```text

frontend

&#x20;  ↓

backend

```



A policy can allow or deny this traffic.



Actual enforcement requires a networking implementation that supports NetworkPolicy.



\## Service Networking



Pod networking and Service networking are separate concepts.



Pod-to-Pod:



```text

Pod A

&#x20;↓

CNI

&#x20;↓

Pod B

```



Pod-to-Service:



```text

Pod A

&#x20;↓

Service IP

&#x20;↓

Service dataplane

&#x20;↓

Pod B

```



\## CNI Failure



If CNI networking fails:



```text

Pod scheduled

&#x20;   ↓

kubelet

&#x20;   ↓

runtime

&#x20;   ↓

CNI ❌

```



The Pod may remain in a state such as:



```text

ContainerCreating

```



with networking-related Events.



\## IPAM Exhaustion



If available Pod IP addresses are exhausted, new Pods may fail during network setup.



The root cause can therefore be CNI/IPAM rather than the application or scheduler.



\## CNI DaemonSet



Networking agents commonly run as a DaemonSet.



Conceptually:



```text

worker-1 → CNI agent

worker-2 → CNI agent

worker-3 → CNI agent

```



A CNI failure on one node can affect Pods on that node.



\## Diagnostics



Useful Linux commands:



```bash

ip addr

ip link

ip route

ip neigh

ss -lntup

```



Useful Kubernetes commands:



```bash

kubectl get pods -A -o wide

kubectl describe pod <pod>

kubectl get nodes

```



Network namespaces can be inspected with:



```bash

readlink /proc/<PID>/ns/net

sudo nsenter -t <PID> -n ip addr

```



Packet-level debugging can use:



```bash

tcpdump

```



\## Troubleshooting Model



When Pod networking fails:



1\. Does the Pod have an IP?

2\. Does the network namespace have `eth0`?

3\. Does the Pod have a route?

4\. Is the CNI agent healthy?

5\. Is IPAM working?

6\. Can the Pod reach another Pod?

7\. Does the Service have endpoints?

8\. Is NetworkPolicy blocking traffic?

9\. Is the application listening?



\## Core Principle



Do not think:



```text

Kubernetes networking

```



as one component.



Think:



```text

Network namespace

&#x20;   ↓

veth

&#x20;   ↓

CNI

&#x20;   ↓

IPAM

&#x20;   ↓

routes

&#x20;   ↓

node networking

&#x20;   ↓

cross-node networking

&#x20;   ↓

Service dataplane

&#x20;   ↓

DNS

&#x20;   ↓

Ingress / Gateway

```

