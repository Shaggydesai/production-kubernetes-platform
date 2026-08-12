\# runc - OCI Runtime



\## Overview



`runc` is a lightweight OCI-compliant runtime responsible for creating Linux containers.



It implements the OCI Runtime Specification.



\---



\## Responsibilities



\- Create Linux namespaces

\- Configure cgroups

\- Mount OverlayFS

\- Start container processes

\- Execute the OCI bundle



\---



\## OCI Bundle



A bundle consists of:



```

bundle/

├── config.json

└── rootfs/

```



\- `config.json` defines how the container should run.

\- `rootfs/` contains the container filesystem.



\---



\## Container Creation Flow



```

docker run



↓



dockerd



↓



containerd



↓



runc



↓



Namespaces



↓



cgroups



↓



OverlayFS



↓



fork()



↓



execve()



↓



Application

```



\---



\## Linux Technologies Used



\- Namespaces

\- cgroups

\- OverlayFS

\- fork()

\- execve()



\---



\## Kubernetes Connection



Kubernetes does not create containers directly.



The kubelet communicates with the container runtime (such as containerd), which invokes `runc` to create OCI-compliant containers.



\---



\## Key Takeaways



\- `runc` is the low-level runtime that creates containers.

\- A container is fundamentally a Linux process with isolation and resource controls.

\- `runc` follows the OCI Runtime Specification.

