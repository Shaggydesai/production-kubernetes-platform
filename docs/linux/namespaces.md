\# Linux Namespaces



\## Overview



Linux namespaces provide isolation between groups of processes.



Namespaces are one of the core technologies behind containers.



\---



\## Namespace Types



| Namespace | Purpose |

|------------|---------|

| PID | Process isolation |

| NET | Network isolation |

| MNT | Filesystem isolation |

| UTS | Hostname isolation |

| IPC | Inter-process communication |

| USER | User and group isolation |



\---



\## Why Namespaces?



Namespaces allow multiple applications to run on the same Linux kernel while appearing to have independent systems.



\---



\## Docker Connection



Docker creates namespaces for each container, allowing every container to have its own process tree, networking stack, hostname, and filesystem view.



\---



\## Kubernetes Connection



Every Kubernetes Pod receives its own set of Linux namespaces.



Containers within the same Pod usually share the same network namespace, which is why they can communicate using `localhost`.



\---



\## Useful Commands



```bash

lsns

ls -l /proc/self/ns

readlink /proc/self/ns/pid

readlink /proc/self/ns/net

readlink /proc/self/ns/mnt

hostname

```



\---



\## Key Takeaways



\- Namespaces isolate system resources.

\- Containers are isolated using Linux namespaces.

\- Docker and Kubernetes rely heavily on namespaces.

\- PID, NET, MNT, UTS, IPC, and USER namespaces form the foundation of container isolation.







\---



\# Practical Observations



\## Namespaces Present on Ubuntu 24.04



The system contained the following namespace types:



\- PID

\- NET

\- MNT

\- IPC

\- UTS

\- USER

\- CGROUP

\- TIME



Each namespace had a unique namespace ID.



Example:



\- PID: 4026531836

\- NET: 4026531840

\- MNT: 4026531841



\---



\## Observations



At this stage only the host namespaces existed because Docker and Kubernetes had not yet been installed.



All running processes shared the same namespaces.



Later, container runtimes will create additional namespaces for every container or Pod.



\---



\## Important Commands



```bash

lsns

ls -l /proc/self/ns

readlink /proc/self/ns/pid

readlink /proc/self/ns/net

readlink /proc/self/ns/mnt

hostname

```

