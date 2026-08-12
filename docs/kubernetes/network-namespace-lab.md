\# Linux Network Namespace Lab



\## Objective



Build a small Linux network manually to understand the primitives used by containers and Kubernetes networking.



Topology:



```text

namespace-A

10.10.0.2

&#x20;   │

&#x20;  veth

&#x20;   │

&#x20;   ▼

&#x20;Linux bridge

&#x20;   ▲

&#x20;   │

&#x20;  veth

&#x20;   │

namespace-B

10.10.0.3

```



\## Create Namespaces



```bash

sudo ip netns add ns-a

sudo ip netns add ns-b

```



Verify:



```bash

sudo ip netns list

```



\## Create veth Pair



```bash

sudo ip link add veth-a-host type veth peer name veth-a

sudo ip link set veth-a netns ns-a

```



Second pair:



```bash

sudo ip link add veth-b-host type veth peer name veth-b

sudo ip link set veth-b netns ns-b

```



\## Create Bridge



```bash

sudo ip link add br-lab type bridge

```



Connect host-side veth interfaces:



```bash

sudo ip link set veth-a-host master br-lab

sudo ip link set veth-b-host master br-lab

```



Bring interfaces up:



```bash

sudo ip link set veth-a-host up

sudo ip link set veth-b-host up

sudo ip link set br-lab up



sudo ip netns exec ns-a ip link set lo up

sudo ip netns exec ns-a ip link set veth-a up



sudo ip netns exec ns-b ip link set lo up

sudo ip netns exec ns-b ip link set veth-b up

```



\## Assign IP Addresses



```bash

sudo ip netns exec ns-a ip addr add 10.10.0.2/24 dev veth-a

sudo ip netns exec ns-b ip addr add 10.10.0.3/24 dev veth-b

```



\## Verify



```bash

sudo ip netns exec ns-a ip -br addr

sudo ip netns exec ns-b ip -br addr

```



Routes:



```bash

sudo ip netns exec ns-a ip route

sudo ip netns exec ns-b ip route

```



\## Test Connectivity



```bash

sudo ip netns exec ns-a ping -c 3 10.10.0.3

```



\## Inspect Neighbours



```bash

sudo ip netns exec ns-a ip neigh

```



This demonstrates IPv4 neighbour/ARP resolution.



\## Capture Packets



On namespace A:



```bash

sudo ip netns exec ns-a tcpdump -i veth-a -nn icmp

```



On namespace B:



```bash

sudo ip netns exec ns-b tcpdump -i veth-b -nn icmp

```



On the bridge:



```bash

sudo tcpdump -i br-lab -nn icmp

```



Generate traffic:



```bash

sudo ip netns exec ns-a ping -c 3 10.10.0.3

```



\## Packet Path



The packet travels approximately:



```text

ns-a

&#x20;↓

veth-a

&#x20;↓

veth-a-host

&#x20;↓

br-lab

&#x20;↓

veth-b-host

&#x20;↓

veth-b

&#x20;↓

ns-b

```



\## Kubernetes Connection



A simplified Pod networking model is:



```text

Pod network namespace

&#x20;       ↓

&#x20;     veth

&#x20;       ↓

CNI-managed node networking

&#x20;       ↓

&#x20;     network

```



The CNI may use different Linux primitives and technologies including:



\- veth

\- bridge

\- routes

\- iptables/nftables

\- VXLAN

\- Geneve

\- BGP

\- eBPF



\## Key Learning



The important Linux primitives are:



```text

Network namespace

veth pair

bridge

IP address

routing

ARP/neighbours

tcpdump

```



These primitives form part of the foundation on which container and Kubernetes networking is built.



\## Cleanup



Remove namespaces:



```bash

sudo ip netns del ns-a

sudo ip netns del ns-b

```



Remove bridge:



```bash

sudo ip link del br-lab

```



Verify:



```bash

sudo ip netns list

ip link show | grep -E 'br-lab|veth-a|veth-b'

```

