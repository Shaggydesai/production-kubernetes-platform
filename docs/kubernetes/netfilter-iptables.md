\# Netfilter, iptables and Kubernetes Services



\## Overview



Linux networking provides the kernel-level packet-processing capabilities used by Kubernetes networking.



The simplified model is:



```text

Packet

&#x20; ↓

Linux networking stack

&#x20; ↓

Netfilter

&#x20; ↓

routing / filtering / NAT

&#x20; ↓

destination

```



\---



\## Netfilter



Netfilter is the Linux kernel networking framework that provides hooks for packet processing.



It supports functionality including:



\- packet filtering

\- NAT

\- connection tracking



User-space tools such as `iptables` and `nftables` configure packet-processing behavior.



\---



\## iptables



iptables is a user-space interface for configuring packet-processing rules.



Important concepts include:



```text

Tables

&#x20; ↓

Chains

&#x20; ↓

Rules

```



Common tables include:



```text

filter

nat

mangle

raw

security

```



The most important tables for Kubernetes networking are generally:



```text

filter

nat

```



\---



\## Important Chains



Common chains include:



```text

PREROUTING

INPUT

FORWARD

OUTPUT

POSTROUTING

```



Simplified packet path:



```text

Packet arrives

&#x20;     ↓

PREROUTING

&#x20;     ↓

Routing decision

&#x20;  /       \\

&#x20; /         \\

INPUT      FORWARD

&#x20; │           │

&#x20; ▼           ▼

Local       POSTROUTING

process         │

&#x20;               ▼

&#x20;            Interface

```



Locally generated traffic follows:



```text

Local process

&#x20;    ↓

OUTPUT

&#x20;    ↓

Routing

&#x20;    ↓

POSTROUTING

&#x20;    ↓

Interface

```



\---



\## Kubernetes Services



A Kubernetes ClusterIP is a virtual Service address.



Example:



```text

Service:

backend



ClusterIP:

10.96.20.50



Port:

80

```



Backend endpoint:



```text

10.244.2.10:8080

```



A process does not necessarily listen directly on:



```text

10.96.20.50:80

```



Instead, the Service dataplane redirects traffic toward an endpoint.



Conceptually:



```text

10.96.20.50:80

&#x20;      ↓

10.244.2.10:8080

```



\---



\## kube-proxy



Historically kube-proxy has programmed node-level Service networking using implementations such as:



```text

iptables

IPVS

```



Modern networking implementations can also use eBPF.



Important distinction:



```text

kube-proxy

```



does not necessarily proxy every packet as an application-level proxy.



In iptables mode, kube-proxy primarily programs the kernel dataplane.



The actual packet is handled by:



```text

Linux kernel

&#x20;↓

iptables / Netfilter

&#x20;↓

backend

```



\---



\## DNAT



Destination NAT changes the destination address.



Simplified Service example:



```text

Before:



10.244.1.10

&#x20;     ↓

10.96.20.50:80



After:



10.244.1.10

&#x20;     ↓

10.244.2.10:8080

```



The actual implementation also involves connection tracking and endpoint selection.



\---



\## Connection Tracking



Connection tracking maintains state about network flows.



It is important for:



\- NAT

\- Service traffic

\- firewall state

\- return traffic



Conceptually:



```text

Client → Service → Backend

Backend → Client

```



can be associated with the same tracked connection.



\---



\## SNAT



Source NAT changes the source address.



Example:



```text

Before:



10.244.1.10 → external destination



After:



Node IP → external destination

```



SNAT can be used when Pod traffic leaves the cluster.



\---



\## DNAT



Destination NAT changes the destination.



Service traffic can conceptually use:



```text

Service ClusterIP

&#x20;      ↓

DNAT

&#x20;      ↓

Pod IP

```



\---



\## Service Dataplane



A Kubernetes Service can be implemented using different dataplane mechanisms:



```text

Service

&#x20;  ↓

Service dataplane

&#x20;  ├── iptables

&#x20;  ├── IPVS

&#x20;  └── eBPF

&#x20;  ↓

Endpoint

```



The implementation depends on the cluster networking architecture.



\---



\## Control Plane vs Data Plane



Control-plane programming:



```text

Kubernetes API

&#x20;     ↓

kube-proxy / networking agent

&#x20;     ↓

program dataplane

```



Actual packet path:



```text

Packet

&#x20;  ↓

Linux kernel

&#x20;  ↓

Service dataplane

&#x20;  ↓

Endpoint

```



\---



\## Troubleshooting



When a Service doesn't work, start with Kubernetes resources:



```bash

kubectl get svc <service>

kubectl get endpointslice

kubectl get pods -o wide

```



Test the backend Pod directly.



If:



```text

Pod IP works

Service IP fails

```



investigate:



\- Service configuration

\- EndpointSlice

\- Service dataplane

\- kube-proxy

\- iptables/IPVS/eBPF



Only then inspect the raw kernel dataplane.



Useful commands include:



```bash

sudo iptables-save

sudo nft list ruleset

```



\---



\## Core Mental Model



```text

Pod

&#x20;↓

Service ClusterIP

&#x20;↓

Service dataplane

&#x20;↓

Netfilter / iptables / IPVS / eBPF

&#x20;↓

Endpoint selection

&#x20;↓

DNAT

&#x20;↓

Routing

&#x20;↓

Backend Pod

```



The ClusterIP is a virtual address. A normal application process does not need to listen directly on the ClusterIP.

