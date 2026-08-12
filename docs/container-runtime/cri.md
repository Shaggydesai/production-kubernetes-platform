\# Container Runtime Interface (CRI)



\## Overview



The Container Runtime Interface (CRI) is a gRPC API that allows Kubernetes to communicate with container runtimes.



It provides a standard interface between the kubelet and OCI-compatible runtimes.



\---



\## Why CRI Exists



Before CRI, Kubernetes depended on Docker-specific APIs.



CRI removed this dependency and allowed Kubernetes to work with multiple runtimes.



\---



\## Runtime Examples



\- containerd

\- CRI-O

\- Mirantis Container Runtime



\---



\## Common CRI Operations



\- PullImage

\- RunPodSandbox

\- CreateContainer

\- StartContainer

\- StopContainer

\- RemoveContainer

\- ContainerStatus



\---



\## Pod Creation Flow



```

kubectl



↓



API Server



↓



Scheduler



↓



kubelet



↓



CRI



↓



containerd



↓



Pause Container



↓



Application Container

```



\---



\## Pause Container



Every Pod begins with a pause container.



The pause container owns:



\- Network namespace

\- IPC namespace

\- UTS namespace



Other containers join these namespaces.



\---



\## Key Takeaways



\- CRI is an API.

\- kubelet communicates using gRPC.

\- containerd implements CRI.

\- Kubernetes no longer depends on Docker.

