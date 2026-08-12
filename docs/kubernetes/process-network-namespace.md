\# Processes and Network Namespaces



\## Core Concept



A Linux process is associated with a network namespace.



The network namespace provides an isolated networking environment containing things such as:



\- network interfaces

\- IP addresses

\- routing tables

\- neighbour tables

\- sockets

\- network-related kernel state



Conceptually:



```text

Process

&#x20;  ↓

Network namespace

&#x20;  ↓

Interfaces

&#x20;  ↓

IP / routes / sockets

```



\## Inspect Current Namespace



```bash

readlink /proc/self/ns/net

```



Example:



```text

net:\[4026531840]

```



The number identifies the namespace object.



\## Inspect PID 1



```bash

sudo readlink /proc/1/ns/net

```



Compare it with:



```bash

readlink /proc/self/ns/net

```



If the IDs match, both processes are in the same network namespace.



\## List Network Namespaces



```bash

lsns -t net

```



\## Create a Network Namespace



```bash

sudo ip netns add ns-demo

```



List:



```bash

sudo ip netns list

```



Inspect its network namespace:



```bash

sudo ip netns exec ns-demo readlink /proc/self/ns/net

```



\## Inspect Interfaces



Host:



```bash

ip addr

```



Namespace:



```bash

sudo ip netns exec ns-demo ip addr

```



The namespace has its own network interfaces.



A newly created namespace normally contains only loopback.



Bring loopback up:



```bash

sudo ip netns exec ns-demo ip link set lo up

```



\## Enter a Process Network Namespace



Given a process PID:



```bash

sudo readlink /proc/<PID>/ns/net

```



Enter its network namespace:



```bash

sudo nsenter -t <PID> -n ip addr

```



Or open a shell:



```bash

sudo nsenter -t <PID> -n bash

```



Exit with:



```bash

exit

```



\## veth and Network Namespaces



A veth pair connects two network namespaces.



Conceptually:



```text

Host namespace

&#x20;     │

&#x20;  veth-host

&#x20;     │

&#x20;     ║

&#x20;     ║ veth pair

&#x20;     ║

&#x20;  veth-container

&#x20;     │

Container namespace

```



The container-side interface is commonly named:



```text

eth0

```



while the host side may have a generated name such as:



```text

vethabc123

```



\## Containers



Containers use Linux namespaces for isolation.



A simplified container contains:



```text

PID namespace

Network namespace

Mount namespace

UTS namespace

IPC namespace

User namespace

cgroups

root filesystem

```



\## Pod Networking



Kubernetes Pods are the basic networking unit.



Containers in the same Pod normally share the same network namespace.



Conceptually:



```text

Pod network namespace

&#x20;       │

&#x20;       ├── eth0

&#x20;       ├── IP address

&#x20;       ├── routes

&#x20;       └── sockets

&#x20;            │

&#x20;      ┌─────┴─────┐

&#x20;      │           │

&#x20; container A  container B

```



Therefore containers in the same Pod can communicate using:



```text

localhost

```



\## Pod Sandbox



A Pod sandbox/pause container is commonly used to establish and hold the Pod's network namespace.



Other containers join that namespace.



Conceptually:



```text

Pod

&#x20;│

&#x20;├── sandbox/pause

&#x20;│       │

&#x20;│       └── network namespace

&#x20;│

&#x20;├── application container

&#x20;│

&#x20;└── sidecar

```



\## Network Namespace vs cgroup



Network namespace answers:



```text

What networking environment can the process see?

```



Cgroup answers:



```text

What resources can the process/group consume?

```



They solve different problems.



\## Network Namespace vs Mount Namespace



Network namespace:



```text

network isolation

```



Mount namespace:



```text

filesystem/mount isolation

```



Container isolation is built from multiple Linux primitives rather than one mechanism.



\## Useful Troubleshooting Commands



```bash

lsns -t net

readlink /proc/<PID>/ns/net

sudo nsenter -t <PID> -n ip addr

sudo nsenter -t <PID> -n ip route

sudo nsenter -t <PID> -n ip neigh

sudo nsenter -t <PID> -n ss -lntup

sudo ip netns exec <namespace> ip addr

```



\## Key Mental Model



```text

Container

&#x20;  │

&#x20;  ├── Process

&#x20;  │

&#x20;  ├── Network namespace

&#x20;  │      ├── eth0

&#x20;  │      ├── routes

&#x20;  │      └── sockets

&#x20;  │

&#x20;  ├── Mount namespace

&#x20;  ├── PID namespace

&#x20;  ├── User namespace

&#x20;  └── cgroups

```



Linux containers are built from kernel primitives such as namespaces, cgroups, virtual filesystems, capabilities, and networking primitives.

