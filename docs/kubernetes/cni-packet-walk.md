\# CNI Packet Walk



\## Purpose



This document follows Kubernetes packets through the networking stack.



The goal is to understand the difference between:



```text

Pod IP → Pod IP

```



and:



```text

Pod → Service ClusterIP → Pod

```



\---



\## Example Cluster



```text

Cluster Pod CIDR:



10.244.0.0/16

```



Example nodes:



```text

worker-1

Node IP: 192.168.10.101

Pod CIDR: 10.244.1.0/24



worker-2

Node IP: 192.168.10.102

Pod CIDR: 10.244.2.0/24

```



Example Pods:



```text

Pod A

10.244.1.10

worker-1



Pod B

10.244.2.10

worker-2

```



\---



\## Flow 1: Pod IP to Pod IP



Pod A executes:



```bash

curl http://10.244.2.10:8080

```



The packet is:



```text

Source:

10.244.1.10



Destination:

10.244.2.10



Port:

8080

```



\### Step 1 — Pod Network Namespace



The application sends the packet through the Pod's Linux networking stack.



Conceptually:



```text

Application

&#x20;   ↓

TCP

&#x20;   ↓

IP

&#x20;   ↓

eth0

```



\### Step 2 — veth Pair



The Pod's `eth0` connects to the node through a veth pair.



```text

Pod namespace



eth0

&#x20;│

&#x20;║ veth pair

&#x20;│

Node namespace



vethXXXX

```



\### Step 3 — Node Networking



The packet reaches the node.



The CNI/networking implementation determines how to reach the destination Pod network.



Example:



```text

10.244.2.0/24 → worker-2

```



\### Step 4 — Node Network



The packet travels from worker-1 toward worker-2.



This may use:



\- routing

\- encapsulation

\- eBPF-based networking



depending on the CNI and configuration.



\### Step 5 — Destination Node



worker-2 receives the packet and forwards it toward the destination Pod.



```text

worker-2

&#x20;  ↓

CNI dataplane

&#x20;  ↓

veth

&#x20;  ↓

Pod B

```



\### Step 6 — Destination Pod



The packet enters:



```text

Pod B eth0

```



and is delivered to the application listening on port 8080.



\### Complete Path



```text

Pod A

10.244.1.10

&#x20;  ↓

eth0

&#x20;  ↓

veth

&#x20;  ↓

worker-1

&#x20;  ↓

CNI dataplane

&#x20;  ↓

node network

&#x20;  ↓

worker-2

&#x20;  ↓

CNI dataplane

&#x20;  ↓

veth

&#x20;  ↓

Pod B

10.244.2.10

```



\---



\# Flow 2: Pod to Service ClusterIP



Suppose:



```text

Service:

backend



ClusterIP:

10.96.20.50



Service port:

80



targetPort:

8080

```



Backend endpoint:



```text

10.244.2.10:8080

```



The client executes:



```bash

curl http://10.96.20.50:80

```



The packet destination is:



```text

10.96.20.50:80

```



not:



```text

10.244.2.10:8080

```



\---



\## ClusterIP Is Virtual



The ClusterIP is a virtual Service address.



It is generally not a normal physical interface address.



The Service dataplane recognizes traffic destined for the Service IP.



Historically this can involve:



\- kube-proxy

\- iptables

\- IPVS



Modern eBPF-based implementations can provide Service handling directly.



\---



\## Service Translation



Conceptually:



```text

10.96.20.50:80

&#x20;       ↓

10.244.2.10:8080

```



This can involve destination NAT (DNAT) and connection tracking.



\---



\## EndpointSlice



A Service gets backend information through EndpointSlices.



Conceptually:



```text

Service

&#x20; ↓

EndpointSlice

&#x20; ↓

10.244.2.10:8080

10.244.2.11:8080

10.244.3.10:8080

```



Traffic can be distributed across eligible endpoints.



\---



\## Service Packet Path



```text

Client Pod

&#x20;   ↓

Service ClusterIP

&#x20;   ↓

Service dataplane

&#x20;   ↓

Endpoint Pod IP

&#x20;   ↓

CNI networking

&#x20;   ↓

Backend Pod

```



\---



\# Service Troubleshooting



If a Service is unreachable, don't immediately assume the CNI is broken.



Check the layers.



\## DNS



```text

Application

&#x20;   ↓

DNS

&#x20;   X

```



The Service may never have been contacted.



\## Service



```bash

kubectl get svc <service>

```



\## EndpointSlice



```bash

kubectl get endpointslice

```



Check whether backend endpoints exist.



\## Pod



```bash

kubectl get pods -o wide

```



Check Pod IP and node placement.



\## Direct Pod Test



Test the Pod directly.



If:



```text

Pod IP works

Service IP fails

```



investigate:



\- Service configuration

\- EndpointSlices

\- Service dataplane

\- kube-proxy/eBPF



If:



```text

Pod IP fails

```



investigate:



\- CNI

\- routes

\- NetworkPolicy

\- application



\---



\# NodePort



Example:



```text

NodePort:

30080

```



External traffic:



```text

External Client

&#x20;     ↓

NodeIP:30080

&#x20;     ↓

Service dataplane

&#x20;     ↓

Endpoint Pod

```



NodePort is a Service exposure mechanism and is not the same as the Pod application port.



\---



\# LoadBalancer



Conceptually:



```text

External Client

&#x20;     ↓

LoadBalancer IP

&#x20;     ↓

Service

&#x20;     ↓

Pod

```



On bare-metal clusters, an implementation such as MetalLB can provide LoadBalancer functionality.



\---



\# Ingress



A common external path is:



```text

Client

&#x20; ↓

DNS

&#x20; ↓

LoadBalancer

&#x20; ↓

Ingress / Gateway

&#x20; ↓

Service

&#x20; ↓

Pod

```



For a Contour/Envoy architecture:



```text

Client

&#x20; ↓

DNS

&#x20; ↓

LoadBalancer IP

&#x20; ↓

Envoy

&#x20; ↓

HTTPProxy

&#x20; ↓

Service

&#x20; ↓

Pod

```



\---



\# Overlay and Underlay



The node network can be considered the underlay:



```text

192.168.10.0/24

```



The Pod network can be considered the overlay:



```text

10.244.0.0/16

```



With encapsulation:



```text

Overlay packet

&#x20;     ↓

encapsulation

&#x20;     ↓

Underlay packet

&#x20;     ↓

network

&#x20;     ↓

decapsulation

&#x20;     ↓

Overlay packet

```



\---



\# Packet Debugging Model



When troubleshooting networking, identify each layer:



```text

Application

&#x20;   ↓

Socket

&#x20;   ↓

TCP/UDP

&#x20;   ↓

IP

&#x20;   ↓

Pod eth0

&#x20;   ↓

veth

&#x20;   ↓

CNI

&#x20;   ↓

Node routing

&#x20;   ↓

Node network

&#x20;   ↓

Destination node

&#x20;   ↓

CNI

&#x20;   ↓

veth

&#x20;   ↓

Destination Pod

```



For Service traffic:



```text

Application

&#x20;   ↓

Service IP

&#x20;   ↓

Service dataplane

&#x20;   ↓

Endpoint Pod IP

&#x20;   ↓

CNI

&#x20;   ↓

Destination Pod

```



\---



\# Production Troubleshooting Order



When traffic fails:



1\. Check DNS.

2\. Check Service.

3\. Check EndpointSlice.

4\. Check Pod IP.

5\. Check Pod networking.

6\. Check CNI.

7\. Check routing.

8\. Check NetworkPolicy.

9\. Check application port.

10\. Check the application itself.



The goal is to identify the exact failing layer rather than saying:



```text

"Kubernetes networking is broken."

```

