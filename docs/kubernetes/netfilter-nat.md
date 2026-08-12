\# Linux Netfilter and NAT



\## Netfilter



Netfilter is a Linux kernel framework that provides packet-processing hooks.



It is used for:



\- packet filtering

\- NAT

\- packet modification

\- connection tracking

\- packet marking



Tools such as `iptables` and `nftables` configure rules interacting with this infrastructure.



\## Important Packet Paths



Simplified incoming packet path:



```text

Incoming packet

&#x20;     ↓

PREROUTING

&#x20;     ↓

Routing decision

&#x20;  /       \\

&#x20; /         \\

INPUT      FORWARD

&#x20;            ↓

&#x20;       POSTROUTING

&#x20;            ↓

&#x20;         Network

```



Locally generated traffic:



```text

Local process

&#x20;     ↓

OUTPUT

&#x20;     ↓

Routing

&#x20;     ↓

POSTROUTING

&#x20;     ↓

Network

```



\## iptables Tables



Important tables include:



```text

filter

nat

mangle

```



\### filter



Primarily used for filtering.



Important chains:



```text

INPUT

FORWARD

OUTPUT

```



\### nat



Used for address/port translation.



Important chains:



```text

PREROUTING

POSTROUTING

OUTPUT

```



\## SNAT



Source Network Address Translation changes the source address.



Example:



```text

Before:



10.30.1.2 → 10.30.2.2



After:



10.30.2.1 → 10.30.2.2

```



Example rule:



```bash

sudo iptables -t nat -A POSTROUTING \\

&#x20; -s 10.30.1.0/24 \\

&#x20; -d 10.30.2.0/24 \\

&#x20; -j SNAT --to-source 10.30.2.1

```



\## MASQUERADE



MASQUERADE is a source-NAT mechanism commonly used when the outgoing interface address can change.



Example:



```bash

sudo iptables -t nat -A POSTROUTING \\

&#x20; -o eth0 \\

&#x20; -j MASQUERADE

```



\## DNAT



Destination Network Address Translation changes the destination.



Conceptually:



```text

Client

&#x20; ↓

192.168.1.10:8080

&#x20; ↓

DNAT

&#x20; ↓

10.30.2.2:80

```



DNAT is commonly associated with:



\- port forwarding

\- load balancing

\- Service exposure



\## Connection Tracking



Linux uses connection tracking to maintain state for network flows.



NAT relies heavily on connection tracking so return traffic can be translated correctly.



If installed:



```bash

sudo conntrack -L

```



\## Kubernetes Connection



Kubernetes Services may implement traffic redirection/load balancing using mechanisms such as:



```text

DNAT

iptables

IPVS

nftables

eBPF

```



depending on the networking implementation.



A simplified Service flow:



```text

Client

&#x20; ↓

Service virtual IP

&#x20; ↓

DNAT/load-balancing decision

&#x20; ↓

Pod IP

```



NodePort can similarly redirect traffic from:



```text

NodeIP:NodePort

```



toward a backend.



\## Important Distinction



```text

DNAT → destination address

SNAT → source address

```



A useful simplified ordering is:



```text

PREROUTING

&#x20;   ↓

DNAT

&#x20;   ↓

routing

&#x20;   ↓

FORWARD

&#x20;   ↓

POSTROUTING

&#x20;   ↓

SNAT

```



\## Inspection Commands



Inspect filter rules:



```bash

sudo iptables -L -n -v

```



Inspect NAT rules:



```bash

sudo iptables -t nat -L -n -v

```



Inspect nftables:



```bash

sudo nft list ruleset

```



Inspect forwarding:



```bash

sudo iptables -L FORWARD -n -v

```



\## Safety



Do not casually execute:



```bash

sudo iptables -F

sudo iptables -t nat -F

sudo nft flush ruleset

```



on a production or important machine.



These commands can destroy existing firewall/NAT configuration.

