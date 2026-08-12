\# Linux Connection Tracking



\## What Is Conntrack?



Conntrack is a Linux kernel subsystem that tracks network flows.



It is used by the Linux networking stack for:



\- connection state tracking

\- NAT

\- return traffic handling

\- flow classification

\- related connections



\## Five-Tuple



A network flow can be identified using:



```text

Source IP

Destination IP

Source port

Destination port

Protocol

```



Example:



```text

10.10.1.2:50000

&#x20;      ↓ TCP

10.10.2.2:80

```



\## Common Conntrack States



Important states include:



```text

NEW

ESTABLISHED

RELATED

```



These are conntrack states and should not be confused with the complete TCP state machine.



\## Inspect Conntrack



Current number of entries:



```bash

sudo conntrack -C

```



List entries:



```bash

sudo conntrack -L

```



TCP entries:



```bash

sudo conntrack -L -p tcp

```



UDP entries:



```bash

sudo conntrack -L -p udp

```



Monitor events:



```bash

sudo conntrack -E

```



Maximum entries:



```bash

sysctl net.netfilter.nf\_conntrack\_max

```



Kernel messages:



```bash

sudo journalctl -k | grep -i conntrack

```



\## Conntrack and NAT



Suppose:



```text

Original:



10.40.0.2:45000

&#x20;       ↓

10.40.0.3:8080

```



SNAT may produce:



```text

Translated:



10.40.0.1:45000

&#x20;       ↓

10.40.0.3:8080

```



Conntrack maintains state associated with the flow and NAT mapping so return traffic can be translated correctly.



\## Kubernetes Connection



Kubernetes networking can involve:



```text

Pod

&#x20;↓

Service

&#x20;↓

DNAT / load balancing

&#x20;↓

Pod

```



or:



```text

Pod

&#x20;↓

SNAT / MASQUERADE

&#x20;↓

Node

&#x20;↓

External network

```



Conntrack can be involved in maintaining the state required for these flows.



\## NodePort



Conceptually:



```text

Client

192.168.1.50:50000

&#x20;      ↓

Node

192.168.1.10:30080

&#x20;      ↓

DNAT / load balancing

&#x20;      ↓

Pod

10.244.1.20:8080

```



Conntrack maintains state for the connection and corresponding reverse traffic.



\## Capacity



Check current entries:



```bash

sudo conntrack -C

```



Check maximum:



```bash

sysctl net.netfilter.nf\_conntrack\_max

```



If the conntrack table becomes exhausted, new network connections can fail.



\## Important Safety Note



Do not casually run:



```bash

sudo conntrack -F

```



because this flushes connection-tracking state and can disrupt active connections.

