\# Kubernetes Networking Foundation



\## Kubernetes Networking Model



Every Pod receives a Pod IP and Pods are designed to communicate according to the cluster networking implementation.



Kubernetes networking is built on Linux networking primitives and CNI implementations.



\## Network Namespace



A network namespace provides an isolated networking environment containing its own:



\- interfaces

\- routes

\- sockets

\- neighbour information

\- networking state



A Pod normally has its own network namespace.



\## CNI



CNI stands for:



```text

Container Network Interface

```



CNI plugins configure Pod networking.



Examples include:



\- Calico

\- Cilium

\- Flannel



Conceptually:



```text

Pod created

&#x20;   ↓

network namespace

&#x20;   ↓

CNI

&#x20;   ↓

IP + interface + routes

```



\## veth Pair



A veth pair provides a virtual Ethernet connection between two network namespaces.



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



The exact interface names depend on the networking implementation.



\## Linux Bridge



A Linux bridge can act as a virtual Ethernet switch.



Conceptually:



```text

&#x20;             bridge

&#x20;            /  |  \\

&#x20;         veth veth veth

&#x20;          |    |    |

&#x20;        PodA PodB PodC

```



Not every CNI uses a bridge in this way.



\## Pod CIDR



A cluster can allocate an address range for Pods.



Example:



```text

Pod CIDR:

10.244.0.0/16

```



Nodes can receive portions of the Pod CIDR.



Example:



```text

worker-1:

10.244.1.0/24



worker-2:

10.244.2.0/24

```



\## Node IP vs Pod IP



Example:



```text

Node IP:

192.168.10.101



Pod IP:

10.244.1.10

```



These are different network identities.



\## Pod-to-Pod Communication



Same-node and cross-node communication depend on the CNI implementation.



Conceptually:



```text

Pod

&#x20;↓

network namespace

&#x20;↓

veth

&#x20;↓

CNI/node networking

&#x20;↓

destination node

&#x20;↓

destination Pod

```



CNI implementations can use approaches such as:



\- routing

\- encapsulation

\- eBPF-based networking



\## Pod-to-Internet



A simplified path is:



```text

Pod

&#x20;↓

Pod network

&#x20;↓

Node

&#x20;↓

NAT/routing

&#x20;↓

LAN

&#x20;↓

Internet

```



Private Pod addresses generally require appropriate routing/NAT for Internet access.



\## Service



A Service provides a stable virtual endpoint for a set of Pods.



Example:



```text

Pods:

10.244.1.10

10.244.1.11

10.244.2.10



Service:

my-api



ClusterIP:

10.96.20.50

```



\## Service Selector



Example:



```yaml

selector:

&#x20; app: api

```



The selector determines which Pods become Service backends.



\## EndpointSlice



Modern Kubernetes represents Service endpoints using EndpointSlices.



Conceptually:



```text

Service

&#x20;  ↓

EndpointSlice

&#x20;  ↓

Pod endpoints

```



\## ClusterIP



ClusterIP is the default Service type.



It provides an internal virtual IP for the Service.



It is generally reachable from within the cluster.



\## Service Port and targetPort



Example:



```yaml

ports:

&#x20; - port: 80

&#x20;   targetPort: 8080

```



Traffic conceptually flows:



```text

client

&#x20;↓

Service:80

&#x20;↓

Pod:8080

```



\## kube-proxy



kube-proxy has traditionally implemented much of Kubernetes Service traffic handling.



Depending on the cluster configuration, Service traffic may use mechanisms such as:



\- iptables

\- IPVS



Modern networking implementations can also provide Service dataplane functionality through other mechanisms such as eBPF.



\## NodePort



NodePort exposes a Service through a port on cluster nodes.



Example:



```text

NodeIP:30080

```



Conceptually:



```text

External client

&#x20;    ↓

NodeIP:30080

&#x20;    ↓

Service

&#x20;    ↓

Pod

```



NodePort is not necessarily the same as the Pod's application port.



\## LoadBalancer



A LoadBalancer Service requires an implementation that provides external load-balancer functionality.



Conceptually:



```text

External IP

&#x20;   ↓

LoadBalancer

&#x20;   ↓

Service

&#x20;   ↓

Pods

```



Cloud environments commonly provide this functionality.



Bare-metal environments can use implementations such as MetalLB.



\## MetalLB



MetalLB can provide LoadBalancer functionality for environments without a cloud load balancer.



Conceptually:



```text

LoadBalancer Service

&#x20;      ↓

MetalLB

&#x20;      ↓

External IP

&#x20;      ↓

Service

&#x20;      ↓

Pods

```



\## Ingress / Gateway



A common external traffic path is:



```text

Internet

&#x20;  ↓

LoadBalancer

&#x20;  ↓

Ingress / Gateway

&#x20;  ↓

Service

&#x20;  ↓

Pods

```



\## DNS



Kubernetes DNS allows applications to use Service names rather than hard-coded Service IP addresses.



Example:



```text

my-api.namespace.svc.cluster.local

```



Conceptually:



```text

Application

&#x20;   ↓

DNS query

&#x20;   ↓

CoreDNS

&#x20;   ↓

Service

```



\## Networking Layers



```text

Pod networking

&#x20;     ↓

CNI

&#x20;     ↓

Node networking

&#x20;     ↓

Service networking

&#x20;     ↓

DNS

&#x20;     ↓

Ingress / Gateway

&#x20;     ↓

External networking

```



\## Troubleshooting Model



When a Pod has networking problems, check:



1\. Does the Pod have an IP?

2\. Does the Pod have an interface?

3\. Does the Pod have routes?

4\. Can the Pod reach another Pod?

5\. Does DNS resolve?

6\. Does the Service have endpoints?

7\. Does the Service selector match the Pods?

8\. Is the Service dataplane working?

9\. Is NetworkPolicy blocking traffic?

10\. Is the application listening on the expected port?



\## Important Principle



Kubernetes networking is not a single component.



It is a combination of:



```text

Linux networking

\+

CNI

\+

Service dataplane

\+

DNS

\+

Ingress / Gateway

\+

external networking

```



Troubleshooting should identify the failing layer rather than treating "Kubernetes networking" as one component.

