\# Docker Image Internals



\## Overview



A Docker image is an OCI-compliant package consisting of metadata and filesystem layers.



Images are immutable and content-addressable.



\---



\## Components



\- Manifest

\- Config

\- Layers



\---



\## Manifest



Defines:



\- Layer order

\- Layer digests

\- Config reference



\---



\## Config



Contains:



\- CMD

\- ENTRYPOINT

\- ENV

\- USER

\- WORKDIR

\- EXPOSE



\---



\## Layers



Each Dockerfile instruction typically creates a new immutable layer.



Layers are shared across images when possible.



\---



\## Digests



Every layer is identified by a SHA256 digest.



This guarantees integrity and enables deduplication.



\---



\## Multi-Architecture Images



A single image tag can reference different manifests for:



\- amd64

\- arm64

\- ppc64le

\- s390x



The runtime selects the correct manifest based on the host architecture.



\---



\## Key Takeaways



\- Docker images are layered.

\- Layers are immutable.

\- Images consist of manifests, configs, and layers.

\- Registries store blobs addressed by SHA256 digests.

\- OCI images are portable across compatible runtimes.

