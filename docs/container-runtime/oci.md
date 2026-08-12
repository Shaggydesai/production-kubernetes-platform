\# Open Container Initiative (OCI)



\## Overview



The Open Container Initiative (OCI) is an open standard that defines how container images are built, distributed, and executed.



OCI is a specification, not a container runtime.



It ensures interoperability between Docker, containerd, CRI-O, Podman, and Kubernetes.



\---



\## OCI Specifications



\### Runtime Specification



Defines how containers execute.



Examples:



\- Namespaces

\- cgroups

\- Mounts

\- Process lifecycle



\---



\### Image Specification



Defines the structure of container images.



Includes:



\- Manifest

\- Configuration

\- Layers



\---



\### Distribution Specification



Defines how container registries communicate.



Supports:



\- Image push

\- Image pull

\- Authentication

\- Layer downloads



\---



\## Why OCI Exists



Before OCI, container runtimes risked becoming incompatible.



OCI provides a common standard that allows images to run across multiple runtimes.



\---



\## Runtime Examples



\- runc

\- crun

\- kata-runtime



\---



\## OCI Compatible Engines



\- Docker

\- containerd

\- CRI-O

\- Podman

\- nerdctl



\---



\## Kubernetes Connection



Kubernetes does not run Docker directly.



It communicates with OCI-compatible runtimes such as containerd or CRI-O through the Container Runtime Interface (CRI).



\---



\## Key Takeaways



\- OCI is an open standard.

\- Docker follows OCI.

\- containerd follows OCI.

\- Kubernetes relies on OCI-compatible runtimes.

\- OCI enables container portability across platforms.

