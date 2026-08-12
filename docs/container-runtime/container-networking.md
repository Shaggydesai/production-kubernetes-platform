\# Linux Container Networking



\## Overview



Containers use Linux networking primitives to provide isolated network stacks while sharing the host kernel.



\---



\## Components



\- Network Namespace

\- Virtual Ethernet Pair (veth)

\- Linux Bridge

\- Routing Table

\- ARP

\- iptables / nftables

\- NAT

\- Masquerading



\---



\## Packet Flow



```

Container



↓



eth0



↓



veth



↓



Linux Bridge



↓



Host Interface



↓



Internet

```



\---



\## Docker Bridge



Default bridge:



```

docker0

```



Gateway:



```

172.17.0.1

```



\---



\## NAT



Linux performs source NAT (MASQUERADE) so private container addresses can communicate with external networks.



\---



\## Key Takeaways



\- Every container has its own network namespace.

\- veth pairs connect containers to the host.

\- Linux bridges act like virtual switches.

\- iptables/nftables implement NAT and packet filtering.

\- Docker's bridge network is local to a single host.

