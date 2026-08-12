\# Calico Architecture



\## Overview



Calico is a Kubernetes CNI plugin that provides networking, IP address management, routing, and NetworkPolicy enforcement.



\---



\## Components



\- Calico CNI

\- Felix

\- kube-controllers

\- Typha (optional)

\- BIRD (traditional routing)



\---



\## Dataplanes



\- iptables

\- nftables

\- eBPF



\---



\## Routing Modes



\### BGP



Uses native Layer 3 routing between nodes.



Advantages:



\- High performance

\- No encapsulation overhead



\### VXLAN



Uses an overlay network for environments where native routing is unavailable.



Advantages:



\- Works across most cloud environments

\- Easier deployment



\---



\## IPAM



Calico allocates Pod IP addresses from configured IPPools.



Each node typically receives a CIDR block to reduce coordination.



\---



\## NetworkPolicy



Felix translates Kubernetes NetworkPolicies into kernel-level enforcement using iptables, nftables, or eBPF.



\---



\## Key Takeaways



\- Calico provides networking and security.

\- Felix programs the Linux dataplane.

\- Typha reduces API server load.

\- BGP enables direct routing.

\- VXLAN provides overlay networking.

\- eBPF improves performance by bypassing iptables.

