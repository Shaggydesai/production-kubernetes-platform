\# Kubernetes DNS and CoreDNS



\## Overview



Kubernetes DNS provides service discovery inside the cluster.



```text

Application

&#x20;   ↓

DNS Resolver

&#x20;   ↓

CoreDNS

&#x20;   ↓

Service

&#x20;   ↓

ClusterIP

```



DNS performs name resolution. It does not itself send application traffic to the backend.



\---



\## `/etc/resolv.conf`



Typical Pod configuration:



```text

nameserver 10.96.0.10

search <namespace>.svc.cluster.local svc.cluster.local cluster.local

options ndots:5

```



The exact values depend on cluster configuration.



\---



\## CoreDNS Service



Kubernetes commonly exposes cluster DNS through a Service named:



```text

kube-dns

```



Example:



```text

kube-dns

ClusterIP:

10.96.0.10

```



The Service name remains `kube-dns` even when CoreDNS is the actual DNS implementation.



\---



\## Service DNS



Example:



```text

Service:

backend



Namespace:

production

```



Full DNS name:



```text

backend.production.svc.cluster.local

```



Structure:



```text

backend

&#x20; ↓

Service name



production

&#x20; ↓

Namespace



svc

&#x20; ↓

Service DNS zone



cluster.local

&#x20; ↓

Cluster DNS domain

```



\---



\## Short Names



Inside the same namespace:



```text

backend

```



can resolve using the DNS search path.



Cross-namespace access can use:



```text

backend.production

```



or:



```text

backend.production.svc.cluster.local

```



\---



\## CoreDNS



CoreDNS is the DNS server commonly deployed in Kubernetes.



CoreDNS can use Kubernetes cluster state to answer Service and Pod DNS queries.



The CoreDNS configuration is commonly stored in a ConfigMap containing a `Corefile`.



\---



\## CoreDNS Plugins



Common plugins include:



\- kubernetes

\- forward

\- cache

\- loop

\- reload

\- loadbalance



The `kubernetes` plugin provides Kubernetes-aware DNS responses.



The `forward` plugin can forward external DNS queries to upstream resolvers.



\---



\## Internal DNS



Example:



```text

backend.production.svc.cluster.local

```



Conceptually:



```text

Application

&#x20;   ↓

CoreDNS

&#x20;   ↓

Kubernetes Service

&#x20;   ↓

10.96.20.30

```



\---



\## External DNS



Example:



```text

example.com

```



Conceptually:



```text

Application

&#x20;   ↓

CoreDNS

&#x20;   ↓

Upstream DNS

&#x20;   ↓

Internet DNS

```



\---



\## Headless Service



A headless Service uses:



```yaml

clusterIP: None

```



Instead of returning a single virtual ClusterIP, DNS can return individual Pod addresses.



Example:



```text

backend

&#x20;↓

10.244.1.10

10.244.1.11

10.244.2.10

```



Headless Services are useful for StatefulSets and distributed systems.



\---



\## DNS Policy



Common DNS policies include:



\- ClusterFirst

\- ClusterFirstWithHostNet

\- Default

\- None



Ordinary Pods commonly use:



```text

ClusterFirst

```



\---



\## Troubleshooting



\### Check CoreDNS Pods



```bash

kubectl get pods -n kube-system -l k8s-app=kube-dns

```



\### Check DNS Service



```bash

kubectl get svc -n kube-system kube-dns

```



\### Check EndpointSlices



```bash

kubectl get endpointslice -n kube-system

```



\### Check CoreDNS Logs



```bash

kubectl logs -n kube-system -l k8s-app=kube-dns

```



\### Test DNS



```bash

nslookup kubernetes.default

```



\### Test Fully Qualified Service Name



```bash

nslookup backend.production.svc.cluster.local

```



\---



\## DNS Failure Troubleshooting



If DNS fails:



```text

DNS failure

&#x20;   ↓

Can Pod reach DNS Service?

&#x20;   ↓

Can CoreDNS respond?

&#x20;   ↓

Does requested Service exist?

&#x20;   ↓

Is namespace correct?

&#x20;   ↓

Is DNS name correct?

&#x20;   ↓

Does CoreDNS have healthy endpoints?

```



\---



\## Important Distinction



```text

CoreDNS

= name resolution



Service

= stable virtual endpoint



CNI

= Pod networking



kube-proxy / dataplane

= Service traffic implementation

```



\---



\## Example Error



```text

lookup payment.production.svc.cluster.local

on 10.96.0.10:53:

no such host

```



Interpretation:



```text

payment

&#x20;   ↓

Service name



production

&#x20;   ↓

Namespace



10.96.0.10:53

&#x20;   ↓

DNS server



no such host

&#x20;   ↓

Requested DNS record was not found

```



Possible causes:



\- Service does not exist

\- Wrong namespace

\- Typo in DNS name

\- Wrong cluster DNS domain

\- CoreDNS problem

\- DNS Service has no healthy endpoints

\- Underlying Pod networking problem



\---



\## DNS vs Connectivity



Successful:



```bash

nslookup backend

```



only proves DNS resolution.



Successful:



```bash

curl http://backend:8080

```



requires:



```text

DNS

\+

network connectivity

\+

Service routing

\+

endpoint

\+

application

```



\---



\## Key Takeaways



\- CoreDNS provides Kubernetes cluster DNS.

\- `kube-dns` is commonly the Service name for cluster DNS.

\- Pods normally use the cluster DNS Service through `/etc/resolv.conf`.

\- Service DNS names follow Kubernetes DNS conventions.

\- Services are namespace-scoped.

\- Headless Services can return Pod IPs directly.

\- DNS and Service networking are separate layers.

\- `no such host` means name resolution failed; it does not automatically mean the application is down.

