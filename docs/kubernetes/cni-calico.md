\# CNI and Calico



\## CNI



CNI stands for Container Network Interface.



CNI configures networking for containers and Kubernetes Pods.



Responsibilities can include:



\- Pod IP allocation

\- Interface creation

\- veth configuration

\- Routes

\- Cross-node connectivity

\- Network policy



\---



\## Pod Network



Example:



```text

10.244.0.0/16

```



Pods receive addresses from the Pod network.



\---



\## Node Pod CIDRs



Example:



```text

Node 1 → 10.244.1.0/24

Node 2 → 10.244.2.0/24

Node 3 → 10.244.3.0/24

```



\---



\## veth Pair



A veth pair connects the Pod network namespace to the node network namespace.



```text

Pod namespace

&#x20;   │

&#x20;  eth0

&#x20;   │

&#x20; veth pair

&#x20;   │

&#x20;  veth

&#x20;   │

Node namespace

```



\---



\## Cross-Node Networking



```text

Pod A

10.244.1.10

&#x20;   ↓

Node 1

&#x20;   ↓

Node network

&#x20;   ↓

Node 2

&#x20;   ↓

Pod B

10.244.2.20

```



Cross-node connectivity can be implemented through routing, encapsulation, or other dataplane mechanisms.



\---



\## Calico



Calico provides Kubernetes networking and network policy.



Important components can include:



\- calico-node

\- Felix

\- Calico controllers

\- Typha

\- BGP components



The exact deployment depends on configuration.



\---



\## Routing



Calico can distribute Pod network routes using routing technologies such as BGP.



Example:



```text

10.244.1.0/24 → Node 1

10.244.2.0/24 → Node 2

```



\---



\## Encapsulation



Calico can also use encapsulation modes such as:



\- IP-in-IP

\- VXLAN



depending on configuration.



\---



\## eBPF



Calico supports an eBPF-based dataplane.



eBPF allows packet processing programs to execute within the Linux kernel.



\---



\## NetworkPolicy



Calico can enforce Kubernetes NetworkPolicy.



Example:



```text

frontend → backend     ALLOW

backend  → database   ALLOW

frontend → database   DENY

```



\---



\## Network Separation



Example lab design:



```text

Node network:

192.168.75.0/24



Pod network:

10.244.0.0/16



Service network:

10.96.0.0/12

```



These networks should not overlap.



\---



\## Troubleshooting



Useful commands:



```bash

ip addr

ip link

ip route

ip neigh

lsns -t net

```



Kubernetes:



```bash

kubectl get nodes -o wide

kubectl get pods -n calico-system

```



\---



\## Key Takeaways



\- CNI configures Pod networking.

\- Pods use network namespaces.

\- veth pairs connect Pod and node networking.

\- Pod CIDRs provide Pod address space.

\- Nodes need routes to other Pod CIDRs.

\- Calico can provide routing and network policy.

\- Calico supports routing, encapsulation and eBPF dataplanes.

\- Pod, Node and Service networks must be designed carefully.

