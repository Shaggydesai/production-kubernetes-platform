\# Container Networking From Scratch



\## Overview



A common Linux container networking model looks like:



```text

Container namespace

&#x20;      │

&#x20;     eth0

&#x20;      │

&#x20;      ║ veth pair

&#x20;      ║

&#x20;      │

&#x20; Host veth

&#x20;      │

&#x20;      ▼

&#x20;  Linux bridge

&#x20;      │

&#x20;      ▼

&#x20;  Host routing

&#x20;      │

&#x20;      ▼

&#x20;     NAT

&#x20;      │

&#x20;      ▼

&#x20;External network

```



\## Network Namespace



A container has its own network namespace.



It can contain:



\- `eth0`

\- `lo`

\- IP addresses

\- routes

\- neighbour table

\- sockets



\## veth Pair



A veth pair acts like a virtual Ethernet cable.



```text

Container namespace

&#x20;     │

&#x20;    eth0

&#x20;     │

&#x20;     ║

&#x20;     ║ veth

&#x20;     ║

&#x20;     │

Host namespace

&#x20;     │

&#x20; vethXXXX

```



\## Linux Bridge



A Linux bridge acts as a software Layer-2 switch.



Multiple container veth interfaces can connect to the bridge:



```text

&#x20;            br-cont

&#x20;         ┌─────┼─────┐

&#x20;         │     │     │

&#x20;       veth1 veth2 veth3

&#x20;         │     │     │

&#x20;        C1    C2    C3

```



\## Container IP



Example:



```text

Container:

10.50.0.2/24



Bridge:

10.50.0.1/24

```



The container can use:



```text

default via 10.50.0.1

```



for traffic outside its local subnet.



\## IP Forwarding



The host must have IPv4 forwarding enabled to route packets between interfaces.



Check:



```bash

sysctl net.ipv4.ip\_forward

```



Enable temporarily:



```bash

sudo sysctl -w net.ipv4.ip\_forward=1

```



\## NAT



Private container addresses may not be routable on the external network.



Example:



```text

Inside:



10.50.0.2 → 8.8.8.8

```



After MASQUERADE:



```text

Host:



192.168.75.10 → 8.8.8.8

```



Example:



```bash

sudo iptables -t nat -A POSTROUTING \\

&#x20; -s 10.50.0.0/24 \\

&#x20; -o <external-interface> \\

&#x20; -j MASQUERADE

```



\## Forwarding



Forward traffic from the container network:



```bash

sudo iptables -A FORWARD \\

&#x20; -s 10.50.0.0/24 \\

&#x20; -o <external-interface> \\

&#x20; -j ACCEPT

```



Allow return traffic:



```bash

sudo iptables -A FORWARD \\

&#x20; -d 10.50.0.0/24 \\

&#x20; -i <external-interface> \\

&#x20; -m conntrack \\

&#x20; --ctstate ESTABLISHED,RELATED \\

&#x20; -j ACCEPT

```



\## Packet Path



Outbound packet:



```text

Container application

&#x20;       ↓

Container network namespace

&#x20;       ↓

eth0

&#x20;       ↓

veth pair

&#x20;       ↓

Linux bridge

&#x20;       ↓

Host routing

&#x20;       ↓

FORWARD

&#x20;       ↓

POSTROUTING

&#x20;       ↓

MASQUERADE

&#x20;       ↓

External interface

&#x20;       ↓

External network

```



Return traffic:



```text

External network

&#x20;       ↓

External interface

&#x20;       ↓

Reverse NAT / conntrack

&#x20;       ↓

Host routing

&#x20;       ↓

Linux bridge

&#x20;       ↓

veth pair

&#x20;       ↓

Container eth0

&#x20;       ↓

Application

```



\## Debugging Commands



Inspect container interfaces:



```bash

sudo ip netns exec container1 ip addr

```



Inspect routes:



```bash

sudo ip netns exec container1 ip route

```



Inspect neighbours:



```bash

sudo ip netns exec container1 ip neigh

```



Inspect bridge:



```bash

bridge link

bridge fdb show

```



Inspect forwarding:



```bash

sudo iptables -L FORWARD -n -v

```



Inspect NAT:



```bash

sudo iptables -t nat -L POSTROUTING -n -v

```



Inspect conntrack:



```bash

sudo conntrack -L

```



Capture bridge traffic:



```bash

sudo tcpdump -i br-cont -nn -e

```



Capture external traffic:



```bash

sudo tcpdump -i <external-interface> -nn -e

```



\## Docker Connection



Docker bridge networking can conceptually look like:



```text

Container

&#x20;   ↓

eth0

&#x20;   ↓

veth

&#x20;   ↓

docker0

&#x20;   ↓

host

&#x20;   ↓

NAT

&#x20;   ↓

external network

```



\## Kubernetes Connection



A Pod can conceptually use:



```text

Pod namespace

&#x20;     ↓

&#x20;    eth0

&#x20;     ↓

&#x20;    veth

&#x20;     ↓

Node CNI

&#x20;     ↓

routing / bridge / overlay / eBPF

&#x20;     ↓

Node network

```



The exact implementation depends on the CNI.



\## CNI



CNI stands for Container Network Interface.



A CNI plugin is responsible for configuring workload networking.



Typical responsibilities can include:



\- creating/configuring interfaces

\- assigning IP addresses

\- configuring routes

\- connecting workloads to node networking

\- implementing network connectivity

\- implementing network policy depending on the CNI



\## Important Principle



Do not assume every Kubernetes cluster uses:



```text

bridge + iptables + NAT

```



Different CNIs use different architectures.



Learn the Linux primitives first, then understand how the selected CNI uses them.

