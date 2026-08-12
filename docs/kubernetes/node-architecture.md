\# Kubernetes Node Architecture



\## Overview



A Kubernetes cluster consists of control-plane and worker-node components.



Conceptually:



```text

&#x20;                Kubernetes Cluster

&#x20;                        │

&#x20;             ┌──────────┴──────────┐

&#x20;             │                     │

&#x20;       Control Plane            Workers

&#x20;             │                     │

&#x20;     ┌───────┼───────┐       ┌─────┼─────┐

&#x20;     │       │       │       │     │     │

&#x20;  API     Scheduler Controllers kubelet ...

&#x20;  Server

&#x20;     │

&#x20;    etcd

```



\## Control Plane Components



Major components:



\- kube-apiserver

\- etcd

\- kube-scheduler

\- kube-controller-manager



\## kube-apiserver



The API server is the primary API entry point for Kubernetes.



Example:



```text

kubectl

&#x20;  │

&#x20;  ▼

kube-apiserver

&#x20;  │

&#x20;  ▼

Kubernetes API

```



`kubectl` communicates with Kubernetes through the API server.



\## etcd



`etcd` is the persistent distributed key-value store used by Kubernetes.



It stores cluster state and Kubernetes objects.



Conceptually:



```text

API Server

&#x20;   │

&#x20;   ▼

&#x20; etcd

&#x20;   │

&#x20;   ├── objects

&#x20;   ├── configuration

&#x20;   ├── desired state

&#x20;   └── metadata

```



\## kube-scheduler



The scheduler selects an appropriate node for Pods that need to be scheduled.



It considers constraints such as:



\- resource requests

\- node availability

\- taints and tolerations

\- affinity

\- topology

\- scheduling policies



\## kube-controller-manager



Controllers continuously reconcile desired state and actual state.



Example:



```text

Desired replicas = 3

Actual replicas  = 2

&#x20;      │

&#x20;      ▼

Controller

&#x20;      │

&#x20;      ▼

Create another Pod

```



\## Worker Node



A worker node normally contains:



\- kubelet

\- container runtime

\- CNI

\- often kube-proxy



Conceptually:



```text

Worker

&#x20; │

&#x20; ├── kubelet

&#x20; │      │

&#x20; │      ▼

&#x20; │   container runtime

&#x20; │      │

&#x20; │      ▼

&#x20; │     runc

&#x20; │      │

&#x20; │      ▼

&#x20; │     Pods

&#x20; │

&#x20; └── CNI

&#x20;        │

&#x20;        ▼

&#x20;     networking

```



\## kubelet



The kubelet is the primary node agent.



It makes sure workloads assigned to the node are running according to their specifications.



Simplified:



```text

API Server

&#x20;   │

&#x20;   ▼

&#x20;kubelet

&#x20;   │

&#x20;  CRI

&#x20;   │

&#x20;   ▼

container runtime

&#x20;   │

&#x20;   ▼

&#x20;containers

```



The kubelet does not directly implement the container runtime.



\## Container Runtime



The node needs a container runtime such as:



```text

containerd

CRI-O

```



The runtime handles container lifecycle and invokes an OCI runtime such as:



```text

runc

```



\## CNI



CNI provides workload networking.



Conceptually:



```text

Pod sandbox

&#x20;   │

&#x20;   ▼

network namespace

&#x20;   │

&#x20;   ▼

CNI

&#x20;   │

&#x20;   ├── interface

&#x20;   ├── IP

&#x20;   ├── routes

&#x20;   └── connectivity

```



\## kube-proxy



kube-proxy has traditionally implemented Kubernetes Service networking using mechanisms such as:



\- iptables

\- IPVS



Modern CNI implementations can provide Service handling using eBPF and may not require kube-proxy.



Therefore Service networking is implementation-dependent.



\## Single-Node Cluster



For learning, control-plane and workload components can run on the same VM.



```text

&#x20;               Single VM

&#x20;                  │

&#x20;       ┌──────────┴──────────┐

&#x20;       │                     │

&#x20; Control Plane            Worker

&#x20; components              components

&#x20;       │                     │

&#x20;       └──────────┬──────────┘

&#x20;                  │

&#x20;                 Pods

```



\## Production Cluster



Production clusters commonly separate control-plane and worker nodes.



Example:



```text

Control Plane

&#x20;├── CP1

&#x20;├── CP2

&#x20;└── CP3



Workers

&#x20;├── W1

&#x20;├── W2

&#x20;└── W3

```



This provides higher availability and workload capacity.



\## Current Learning VM



The current `ubuntu-template` is still a normal Ubuntu VM.



It currently does not have:



```text

containerd

runc

kubelet

kubeadm

kubectl

CNI

```



installed.



The Linux foundation is already prepared.



\## Transformation to Kubernetes Node



The planned process is:



```text

Ubuntu VM

&#x20;   │

&#x20;   ▼

Install container runtime

&#x20;   │

&#x20;   ▼

containerd

&#x20;   │

&#x20;   ▼

Install Kubernetes components

&#x20;   │

&#x20;   ├── kubeadm

&#x20;   ├── kubelet

&#x20;   └── kubectl

&#x20;   │

&#x20;   ▼

Initialize / join cluster

&#x20;   │

&#x20;   ▼

Install CNI

&#x20;   │

&#x20;   ▼

Working Kubernetes node

```

