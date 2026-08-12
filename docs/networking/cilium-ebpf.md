\# Cilium \& eBPF



\## Overview



Cilium is a Kubernetes CNI plugin built around eBPF to provide networking, security, and observability.



\---



\## eBPF



eBPF allows verified programs to execute safely inside the Linux kernel.



Advantages:



\- Performance

\- Observability

\- Security

\- Dynamic behavior



\---



\## Components



\- eBPF Programs

\- eBPF Maps

\- Verifier

\- Hook Points



\---



\## Cilium



Responsibilities:



\- Pod networking

\- Service load balancing

\- NetworkPolicy enforcement

\- Observability

\- kube-proxy replacement



\---



\## Hubble



Provides:



\- Flow visibility

\- Service visibility

\- DNS visibility

\- HTTP visibility



\---



\## Key Takeaways



\- eBPF executes verified programs inside the Linux kernel.

\- Cilium uses eBPF for networking and security.

\- eBPF can replace many iptables-based workflows.

\- Hubble provides detailed network observability.

