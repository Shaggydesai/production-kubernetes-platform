\# Kubernetes Service Networking



\## Purpose



A Kubernetes Service provides a stable virtual endpoint for a set of Pods.



```text

Client

&#x20; ↓

Service

&#x20; ↓

Backend Pods

```



\## Example



Backend Pods:



```text

10.244.1.10:8080

10.244.1.11:8080

10.244.2.10:8080

```



Service:



```text

backend

ClusterIP:

10.96.20.30

```



\## DNS



A Pod can access the Service using:



```text

backend.default.svc.cluster.local

```



CoreDNS resolves the Service name to the ClusterIP.



```text

backend

&#x20; ↓

CoreDNS

&#x20; ↓

10.96.20.30

```



\## ClusterIP



ClusterIP is a virtual Service address.



It is not necessarily a physical IP assigned to a network interface.



\## kube-proxy



kube-proxy traditionally watches Services and EndpointSlices and programs the node networking dataplane.



Possible mechanisms include:



\- iptables

\- IPVS



Other networking implementations can use eBPF instead.



\## Service Translation



Conceptually:



```text

Before:



SRC = 10.244.1.20

DST = 10.96.20.30:8080



After:



SRC = 10.244.1.20

DST = 10.244.1.10:8080

```



This commonly involves DNAT.



\## EndpointSlice



EndpointSlices contain the backend endpoints associated with Services.



Example:



```text

Service:

10.96.20.30



Endpoints:



10.244.1.10

10.244.1.11

10.244.2.10

```



\## Service Selector



Example:



```yaml

selector:

&#x20; app: backend

```



Pods with matching labels become Service endpoints when eligible.



\## Service Ports



Example:



```yaml

ports:

&#x20; - port: 80

&#x20;   targetPort: 8080

&#x20;   nodePort: 30080

```



Traffic flow:



```text

NodePort 30080

&#x20;     ↓

Service port 80

&#x20;     ↓

Pod targetPort 8080

```



\## Service Types



Common Service types:



\- ClusterIP

\- NodePort

\- LoadBalancer

\- ExternalName



\## Troubleshooting



If a Service is not working:



1\. Check DNS

2\. Check the Service

3\. Check EndpointSlices

4\. Check Pod labels

5\. Check Pod readiness

6\. Check NetworkPolicy

7\. Check node networking

8\. Check the Service dataplane



Useful commands:



```bash

kubectl get svc

kubectl get endpointslice

kubectl get pods -o wide

kubectl get pods --show-labels

kubectl get networkpolicy

```



Node-level commands:



```bash

ip addr

ip route

```



\## Important Distinction



```text

Service

= Kubernetes abstraction



kube-proxy / eBPF / other dataplane

= implementation

```



A Service does not inherently mean traffic passes through a kube-proxy userspace process.



\## Request Flow



```text

Application

&#x20;   ↓

DNS

&#x20;   ↓

CoreDNS

&#x20;   ↓

ClusterIP

&#x20;   ↓

Service dataplane

&#x20;   ↓

Endpoint

&#x20;   ↓

Pod

```



\## Key Takeaways



\- Services provide stable virtual endpoints.

\- ClusterIP is a virtual Service address.

\- CoreDNS resolves Service names.

\- EndpointSlices identify backend endpoints.

\- kube-proxy traditionally programs Service networking.

\- DNAT can translate Service traffic to Pod traffic.

\- iptables, IPVS and eBPF are possible dataplane mechanisms.

\- Service networking and DNS are separate layers.

\- A running Pod does not automatically mean it is a ready Service endpoint.S

