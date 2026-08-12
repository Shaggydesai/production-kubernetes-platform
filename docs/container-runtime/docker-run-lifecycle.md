\# docker run Lifecycle



\## Overview



Executing `docker run` triggers a sequence of operations involving Docker, containerd, runc, and the Linux kernel.



\---



\## Lifecycle



```

docker CLI

&#x20;   ↓

dockerd

&#x20;   ↓

containerd

&#x20;   ↓

Check Image

&#x20;   ↓

Pull OCI Image (if necessary)

&#x20;   ↓

Verify SHA256

&#x20;   ↓

Store Layers

&#x20;   ↓

Create Snapshot

&#x20;   ↓

Generate OCI Bundle

&#x20;   ↓

runc

&#x20;   ↓

clone()

&#x20;   ↓

Namespaces

&#x20;   ↓

cgroups

&#x20;   ↓

OverlayFS

&#x20;   ↓

Mount Special Filesystems

&#x20;   ↓

pivot\_root()

&#x20;   ↓

execve()

&#x20;   ↓

Application Starts

&#x20;   ↓

containerd-shim

```



\---



\## Linux Technologies Used



\- Processes

\- clone()

\- execve()

\- Namespaces

\- cgroups

\- OverlayFS

\- Mount namespaces

\- OCI Bundle



\---



\## Key Takeaways



A container is a Linux process created with isolation, resource limits, and a layered filesystem.



Docker orchestrates the workflow, containerd manages the lifecycle, runc creates the container, and the Linux kernel enforces isolation and resource controls.

