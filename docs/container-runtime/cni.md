\# Container Network Interface (CNI)



\## Overview



The Container Network Interface (CNI) is a specification that defines how container runtimes configure networking for containers.



Kubernetes relies on CNI-compatible plugins to provide Pod networking.



\---



\## Responsibilities



\- Create network interfaces

\- Assign IP addresses

\- Configure routes

\- Connect containers to networks

\- Clean up networking resources



\---



\## Standard Operations



\- ADD

\- DEL

\- CHECK

\- VERSION



\---



\## Components



\- CNI Plugin

\- IPAM

\- Linux Networking



\---



\## Plugin Locations



```

/opt/cni/bin

```



Configuration:



```

/etc/cni/net.d

```



\---



\## Pod Networking Flow



```

kubelet

&#x20;   ↓

containerd

&#x20;   ↓

CNI ADD

&#x20;   ↓

IPAM

&#x20;   ↓

Assign IP

&#x20;   ↓

Configure Network

&#x20;   ↓

Pod Ready

```



\---



\## Popular Plugins



\- Calico

\- Flannel

\- Cilium

\- Weave Net

\- Antrea



\---



\## Key Takeaways



\- CNI is a specification, not a product.

\- CNI plugins implement Pod networking.

\- IPAM assigns Pod IP addresses.

\- kubelet and containerd rely on CNI for network setup.

