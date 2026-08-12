\# Linux Routing Between Network Namespaces



\## Objective



Build a Linux router connecting two separate network namespaces.



Topology:



```text

&#x20;            Linux Router

&#x20;         ┌─────────────────┐

&#x20;         │                 │

&#x20;  10.10.1.1           10.10.2.1

&#x20;         │                 │

&#x20;      veth-a             veth-b

&#x20;         │                 │

&#x20;       ns-a              ns-b

&#x20;    10.10.1.2         10.10.2.2

```



\## Networks



Namespace A:



```text

10.10.1.0/24

```



Namespace B:



```text

10.10.2.0/24

```



Because the networks are different, routing is required.



\## Create Namespaces



```bash

sudo ip netns add ns-a

sudo ip netns add ns-b

```



\## Create veth Pairs



```bash

sudo ip link add veth-a-host type veth peer name veth-a

sudo ip link set veth-a netns ns-a



sudo ip link add veth-b-host type veth peer name veth-b

sudo ip link set veth-b netns ns-b

```



\## Bring Interfaces Up



```bash

sudo ip link set veth-a-host up

sudo ip link set veth-b-host up



sudo ip netns exec ns-a ip link set lo up

sudo ip netns exec ns-a ip link set veth-a up



sudo ip netns exec ns-b ip link set lo up

sudo ip netns exec ns-b ip link set veth-b up

```



\## Configure Router Addresses



```bash

sudo ip addr add 10.10.1.1/24 dev veth-a-host

sudo ip addr add 10.10.2.1/24 dev veth-b-host

```



The Linux host now has interfaces in two networks.



\## Configure Namespace Addresses



```bash

sudo ip netns exec ns-a ip addr add 10.10.1.2/24 dev veth-a

sudo ip netns exec ns-b ip addr add 10.10.2.2/24 dev veth-b

```



\## Configure Routes



Namespace A:



```bash

sudo ip netns exec ns-a ip route add 10.10.2.0/24 via 10.10.1.1

```



Namespace B:



```bash

sudo ip netns exec ns-b ip route add 10.10.1.0/24 via 10.10.2.1

```



\## Enable IPv4 Forwarding



Inspect:



```bash

sysctl net.ipv4.ip\_forward

```



For the temporary lab:



```bash

sudo sysctl -w net.ipv4.ip\_forward=1

```



Do not make this persistent as part of this temporary lab.



\## Test



Test namespace-to-router connectivity:



```bash

sudo ip netns exec ns-a ping -c 3 10.10.1.1

sudo ip netns exec ns-b ping -c 3 10.10.2.1

```



Test routed connectivity:



```bash

sudo ip netns exec ns-a ping -c 3 10.10.2.2

```



\## Inspect Routing



```bash

sudo ip netns exec ns-a ip route

sudo ip netns exec ns-b ip route

```



Use:



```bash

sudo ip netns exec ns-a ip route get 10.10.2.2

```



to determine the exact route Linux will use.



\## Packet Capture



Capture on the source side:



```bash

sudo tcpdump -i veth-a-host -nn icmp

```



Capture on the destination side:



```bash

sudo tcpdump -i veth-b-host -nn icmp

```



Generate traffic:



```bash

sudo ip netns exec ns-a ping -c 3 10.10.2.2

```



\## Packet Path



```text

ns-a

&#x20;↓

veth-a

&#x20;↓

veth-a-host

&#x20;↓

Linux routing

&#x20;↓

veth-b-host

&#x20;↓

veth-b

&#x20;↓

ns-b

```



\## Routing vs Forwarding



Routing determines:



```text

Where should the packet go?

```



Forwarding determines:



```text

Should Linux pass the packet between interfaces?

```



A correct route does not guarantee forwarding.



\## Layer 2 vs Layer 3



Within a subnet:



```text

ARP

&#x20;↓

MAC

&#x20;↓

Ethernet

```



Between different subnets:



```text

IP

&#x20;↓

routing

&#x20;↓

next hop

```



When a packet crosses a router, Ethernet source/destination addresses change while the IP source/destination generally remain unchanged.



\## Kubernetes Connection



A Kubernetes CNI may need to provide connectivity between Pod networks.



A simplified model is:



```text

Pod A

&#x20;↓

Pod network namespace

&#x20;↓

veth

&#x20;↓

node networking

&#x20;↓

routing / overlay / other CNI mechanism

&#x20;↓

destination node

&#x20;↓

destination Pod

```



The exact implementation depends on the CNI.



\## Cleanup



```bash

sudo ip netns del ns-a

sudo ip netns del ns-b

```



Remove host interfaces if required:



```bash

sudo ip link del veth-a-host

sudo ip link del veth-b-host

```



Verify:



```bash

sudo ip netns list

ip link show | grep -E 'veth-a|veth-b'

```

