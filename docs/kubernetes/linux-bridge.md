\# Linux Bridge Internals



\## What Is a Linux Bridge?



A Linux bridge is a software Layer-2 switch.



It forwards Ethernet frames using destination MAC addresses.



Conceptually:



```text

&#x20;            br-lab

&#x20;       ┌──────┼──────┐

&#x20;       │      │      │

&#x20;     veth1  veth2  veth3

```



\## Bridge Ports



Inspect bridge interfaces:



```bash

bridge link

```



This shows which interfaces are attached to a bridge.



\## Forwarding Database



Inspect learned MAC addresses:



```bash

bridge fdb show

```



For a specific bridge:



```bash

bridge fdb show br br-lab

```



The FDB conceptually maps:



```text

MAC address → bridge port

```



\## MAC Learning



When a frame enters the bridge:



```text

Source MAC = MAC-A

Ingress port = veth-a-host

```



the bridge can learn:



```text

MAC-A → veth-a-host

```



The bridge then uses the destination MAC to determine the outgoing port.



\## Unknown Unicast



If the destination MAC is unknown, the bridge floods the frame to the appropriate other ports.



\## Broadcast



Broadcast frames such as ARP requests are forwarded to the relevant bridge ports.



\## ARP



Inspect neighbour information:



```bash

sudo ip netns exec ns-a ip neigh

```



Capture ARP:



```bash

sudo tcpdump -i br-lab -nn -e arp

```



\## Ethernet Inspection



Use `-e` with tcpdump:



```bash

sudo tcpdump -i br-lab -nn -e icmp

```



This shows Ethernet MAC addresses in addition to IP information.



Conceptually:



```text

Ethernet:

MAC-A → MAC-B



IP:

10.20.0.2 → 10.20.0.3

```



\## Layer 2 vs Layer 3



Bridge:



```text

destination MAC

&#x20;       ↓

bridge FDB

&#x20;       ↓

outgoing port

```



Router:



```text

destination IP

&#x20;       ↓

routing table

&#x20;       ↓

next hop/interface

```



\## Kubernetes Connection



A bridge-based container network can look conceptually like:



```text

&#x20;            cni0

&#x20;       ┌─────┼─────┐

&#x20;       │     │     │

&#x20;    veth1  veth2  veth3

&#x20;       │     │     │

&#x20;     Pod1  Pod2  Pod3

```



The exact Kubernetes networking architecture depends on the selected CNI.



Not every Kubernetes CNI uses a Linux bridge.



\## Docker Connection



A Docker bridge network can use:



```text

Container

&#x20;   ↓

veth

&#x20;   ↓

docker0

&#x20;   ↓

Host

```



The same Linux networking concepts apply.



\## Useful Commands



```bash

bridge link

bridge fdb show

bridge fdb show br br-lab

ip link

ip neigh

tcpdump -nn -e

```



\## Key Principle



```text

Bridge → Layer 2 → MAC

Router → Layer 3 → IP

```



A bridge forwards Ethernet frames.



A router forwards IP packets between networks.

