\# Kubernetes Container Runtime and CRI



\## Overview



The kubelet does not directly create containers.



The typical execution path is:



```text

kubelet

&#x20; ↓

CRI

&#x20; ↓

containerd

&#x20; ↓

containerd-shim

&#x20; ↓

runc

&#x20; ↓

Linux kernel

```



\---



\## CRI



CRI stands for Container Runtime Interface.



It provides the interface between kubelet and a container runtime.



\---



\## containerd



containerd manages:



\- Container lifecycle

\- Image management

\- Filesystem snapshots

\- Runtime integration



\---



\## runc



runc is an OCI runtime responsible for creating and configuring the low-level Linux container process.



\---



\## Linux Isolation



Containers use Linux primitives including:



\- PID namespaces

\- Network namespaces

\- Mount namespaces

\- UTS namespaces

\- IPC namespaces

\- User namespaces

\- cgroups

\- Capabilities

\- seccomp



\---



\## Filesystem



Container images consist of layers.



Linux container filesystems commonly use overlayfs.



```text

Writable layer

&#x20;     ↓

Image layers

&#x20;     ↓

overlayfs

&#x20;     ↓

Linux kernel

```



\---



\## Pod Sandbox



A Pod has a shared sandbox/network namespace.



Application containers within the Pod can share the Pod network namespace.



\---



\## CNI



CNI configures Pod networking.



```text

Runtime

&#x20; ↓

CNI

&#x20; ↓

Pod network namespace

```



\---



\## CSI



CSI handles storage integration.



```text

CSI → Container Storage

```



\---



\## Runtime Debugging



```bash

systemctl status containerd

crictl info

crictl pods

crictl ps

crictl ps -a

crictl images

journalctl -u containerd

journalctl -u kubelet

```



\---



\## Tool Differences



\### crictl



Communicates with a CRI runtime.



\### ctr



Communicates directly with containerd.



\### nerdctl



Provides a Docker-compatible style CLI for containerd.



\---



\## Troubleshooting Layers



```text

API

&#x20;↓

Scheduler

&#x20;↓

kubelet

&#x20;↓

CRI

&#x20;↓

containerd

&#x20;↓

CNI / CSI

&#x20;↓

runc

&#x20;↓

Linux kernel

```



\---



\## Key Takeaways



\- Containers are Linux processes with isolation and resource controls.

\- kubelet communicates with runtimes through CRI.

\- containerd manages container lifecycle.

\- runc creates the low-level container process.

\- CNI handles networking.

\- CSI handles storage.

\- Linux namespaces provide isolation.

\- cgroups provide resource control. 




# Container Runtime Architecture

## Overview

Modern Linux container infrastructure is layered.

A simplified architecture is:

```text
User
 │
 ▼
CLI
 │
 ▼
Container runtime / engine
 │
 ▼
containerd
 │
 ▼
OCI runtime
 │
 ▼
runc
 │
 ▼
Linux kernel
```

Networking is handled through a separate layer:

```text
Container runtime
       │
       ▼
      CNI
       │
       ├── network namespace
       ├── interfaces
       ├── IP address
       └── routes
```

## runc

`runc` is an OCI runtime.

It is responsible for creating and running containers using Linux kernel primitives.

These can include:

- namespaces
- cgroups
- mounts
- capabilities
- root filesystem
- container process

Conceptually:

```text
runc
 │
 ├── PID namespace
 ├── NET namespace
 ├── MNT namespace
 ├── UTS namespace
 ├── cgroups
 ├── capabilities
 └── process
```

## containerd

`containerd` is a container runtime daemon that manages container lifecycle and images and can invoke an OCI runtime such as `runc`.

Conceptually:

```text
containerd
    │
    ├── images
    ├── containers
    ├── snapshots
    └── lifecycle
          │
          ▼
        runc
```

## Docker

A simplified Docker architecture is:

```text
docker CLI
    │
    ▼
Docker Engine
    │
    ▼
containerd
    │
    ▼
runc
    │
    ▼
Linux kernel
```

Docker also manages networking through its networking components.

## Kubernetes Runtime

Kubernetes nodes use the Container Runtime Interface (CRI).

Conceptually:

```text
kubelet
   │
   ▼
  CRI
   │
   ▼
containerd / CRI-O
   │
   ▼
runc / OCI runtime
   │
   ▼
Linux kernel
```

## CRI

CRI stands for:

```text
Container Runtime Interface
```

It provides the interface between kubelet and the container runtime.

## CNI

CNI stands for:

```text
Container Network Interface
```

CNI is responsible for configuring workload networking.

Typical responsibilities can include:

- configuring network interfaces
- assigning IP addresses
- configuring routes
- connecting workloads to node networking
- implementing network connectivity
- implementing network policy depending on the CNI

## CNI Configuration

Common configuration directory:

```bash
/etc/cni/net.d/
```

Inspect:

```bash
sudo ls -la /etc/cni/net.d/
```

## CNI Binaries

Common plugin directory:

```bash
/opt/cni/bin/
```

Inspect:

```bash
sudo ls -la /opt/cni/bin/
```

## IPAM

IPAM means:

```text
IP Address Management
```

It is responsible for allocating IP addresses to workloads.

Example:

```text
Pod A → 10.244.1.10
Pod B → 10.244.1.11
Pod C → 10.244.1.12
```

IPAM implementations can include:

- host-local
- DHCP
- CNI-specific mechanisms

## Pod Startup

A simplified Pod startup sequence is:

```text
kubelet
   │
   ▼
CRI
   │
   ▼
container runtime
   │
   ▼
Pod sandbox
   │
   ▼
network namespace
   │
   ▼
CNI
   │
   ├── interface
   ├── veth
   ├── IP
   └── routes
   │
   ▼
application container
```

## Pod Networking

Containers in the same Pod normally share the Pod network namespace.

```text
Pod
 │
 ├── container A
 ├── container B
 │
 └── shared network namespace
          │
         eth0
          │
        Pod IP
```

Therefore containers in the same Pod can communicate through:

```text
localhost
```

## containerd vs Linux Namespace

These are different concepts.

Linux namespace:

```text
kernel isolation mechanism
```

Example:

```text
net:[4026531840]
```

containerd namespace:

```text
containerd resource grouping
```

Example:

```text
k8s.io
```

They must not be confused.

## Useful Commands

Check containerd:

```bash
containerd --version
systemctl status containerd
```

Check runc:

```bash
runc --version
```

Check CRI:

```bash
crictl --version
crictl info
```

Check containerd:

```bash
sudo ctr version
sudo ctr namespaces list
```

Check CNI:

```bash
sudo ls -la /etc/cni/net.d/
sudo ls -la /opt/cni/bin/
```

Check containerd socket:

```bash
sudo ls -l /run/containerd/containerd.sock
```

## Important Mental Model

```text
                 kubelet
                    │
                   CRI
                    │
               containerd
                    │
                   runc
                    │
              Linux kernel
                    │
          ┌─────────┴─────────┐
          │                   │
      namespaces            cgroups
          │
          ▼
       Pod sandbox
          │
          ▼
         CNI
          │
          ▼
    Pod networking
```

Runtime and networking are separate layers.

Runtime creates/runs the container environment.

CNI configures networking.

The Linux kernel provides the underlying primitives.

