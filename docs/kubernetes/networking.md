\# Kubernetes Networking Fundamentals



\## Kubernetes Networking Model



Kubernetes provides networking between Pods, Services and external clients.



```text

Pod

&#x20;↓

CNI

&#x20;↓

Node networking

&#x20;↓

Service

&#x20;↓

External networking

```



\## Pod Networking



Each Pod normally receives its own IP address.



Example:



```text

Pod A → 10.244.1.10

Pod B → 10.244.1.11

```



Pod IPs are different from node IPs.



\## Network Namespace



Pods use Linux network namespaces to isolate their network stack.



\## veth Pair



A virtual Ethernet pair connects the Pod network namespace to networking outside the namespace.



```text

Pod namespace



eth0

&#x20; │

&#x20; │ veth pair

&#x20; │

vethXXXX



Host namespace

```



\## CNI



CNI stands for Container Network Interface.



CNI plugins configure Pod networking.



Examples:



\- Calico

\- Cilium

\- Flannel



CNI can configure:



\- Pod IPs

\- interfaces

\- routes

\- cross-node connectivity

\- network policies



\## Pod CIDR



A Pod CIDR is the address range allocated for Pod networking.



Example:



```text

10.244.0.0/16

```



\## Service CIDR



A Service CIDR is the address range used for Kubernetes Service virtual IPs.



Example:



```text

10.96.0.0/12

```



Pod and Service CIDRs are different.



\## Service



A Service provides a stable virtual endpoint for Pods.



```text

Client

&#x20; ↓

Service

&#x20; ↓

Pods

```



\## EndpointSlice



EndpointSlices track the backend endpoints associated with Services.



\## kube-proxy



kube-proxy traditionally implements Service traffic routing by programming Linux packet-processing rules.



Common mechanisms include:



\- iptables

\- IPVS



\## DNS



Kubernetes normally provides cluster DNS through CoreDNS.



Example:



```text

backend.production.svc.cluster.local

```



\## Traffic Paths



\### Pod to Pod



```text

Pod

&#x20;↓

CNI

&#x20;↓

Pod

```



\### Pod to Service



```text

Pod

&#x20;↓

Service IP

&#x20;↓

Service routing

&#x20;↓

Pod

```



\### External to NodePort



```text

Client

&#x20;↓

NodeIP:NodePort

&#x20;↓

Service

&#x20;↓

Pod

```



\### External to Ingress



```text

Client

&#x20;↓

LoadBalancer

&#x20;↓

Ingress Controller

&#x20;↓

Service

&#x20;↓

Pod

```



\## NetworkPolicy



NetworkPolicy controls which traffic is allowed between workloads.



Example:



```text

frontend → backend

backend → database

frontend -X-> database

```



\## Important Components



```text

CRI → Container Runtime

CNI → Container Networking

CSI → Container Storage

```



\## Troubleshooting



For Pod networking issues investigate:



1\. Pod IP

2\. Network interface

3\. Routes

4\. CNI

5\. Cross-node connectivity

6\. NetworkPolicy

7\. Service endpoints

8\. CoreDNS



\## Key Takeaways



\- Pods receive their own IP addresses.

\- Pods use Linux network namespaces.

\- veth pairs connect Pod networking to the node.

\- CNI configures Pod networking.

\- Pod CIDR and Service CIDR are different.

\- Services provide stable virtual endpoints.

\- kube-proxy implements Service networking.

\- CoreDNS provides Kubernetes service discovery.

\- NetworkPolicy controls traffic.

