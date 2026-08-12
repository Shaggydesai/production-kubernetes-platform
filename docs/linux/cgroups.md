\# Linux cgroups (Control Groups)



\## Overview



Control Groups (cgroups) are a Linux kernel feature that limits and monitors resource usage for groups of processes.



Namespaces provide isolation.



cgroups provide resource control.



\---



\## Resources Controlled



\- CPU

\- Memory

\- Block IO

\- PIDs

\- Huge Pages

\- Devices



\---



\## cgroup v2



Ubuntu 24.04 uses cgroup v2 with the unified hierarchy.



The cgroup filesystem is mounted at:



```

/sys/fs/cgroup

```



\---



\## Important Files



| File | Purpose |

|------|----------|

| cpu.max | CPU limit |

| cpu.stat | CPU usage statistics |

| memory.max | Maximum memory |

| memory.current | Current memory usage |

| memory.stat | Memory statistics |

| pids.max | Maximum number of processes |

| io.stat | Block device I/O statistics |



\---



\## Docker Connection



Docker creates cgroups to enforce CPU and memory limits for containers.



Example:



```bash

docker run --memory=512m --cpus=1 nginx

```



\---



\## Kubernetes Connection



The Kubernetes resource specification:



```yaml

resources:

&#x20; requests:

&#x20;   cpu: "250m"

&#x20;   memory: "128Mi"



&#x20; limits:

&#x20;   cpu: "1"

&#x20;   memory: "512Mi"

```



is ultimately enforced by Linux cgroups through the container runtime.



\---



\## Useful Commands



```bash

mount | grep cgroup

stat -fc %T /sys/fs/cgroup

ls /sys/fs/cgroup

cat /sys/fs/cgroup/cpu.max

cat /sys/fs/cgroup/memory.max

cat /sys/fs/cgroup/memory.current

cat /sys/fs/cgroup/pids.max

cat /sys/fs/cgroup/io.stat

```



\---



\## Key Takeaways



\- Namespaces isolate processes.

\- cgroups control resources.

\- Docker uses both namespaces and cgroups.

\- Kubernetes relies on cgroups to enforce Pod resource requests and limits.

