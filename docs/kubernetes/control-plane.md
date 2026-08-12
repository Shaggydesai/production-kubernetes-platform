\# Kubernetes Control Plane Architecture



\## Major Components



```text

Control Plane



kube-apiserver

etcd

kube-scheduler

kube-controller-manager

cloud-controller-manager (where applicable)

```



\## Worker Node



```text

Worker Node



kubelet

container runtime

CNI

CSI

Pods

```



\## kube-apiserver



The API server is the central entry point to the Kubernetes API.



It handles:



\- authentication

\- authorization

\- admission

\- validation

\- API requests

\- persistence through etcd

\- watch mechanisms



\## etcd



etcd is the distributed key-value datastore used by Kubernetes for cluster state.



It stores Kubernetes objects such as:



\- Pods

\- Deployments

\- Services

\- ConfigMaps

\- Secrets

\- Nodes

\- Namespaces

\- RBAC objects

\- Custom Resources



Normal clients interact with the API server rather than directly with etcd.



\## kube-scheduler



The scheduler selects a suitable node for unscheduled Pods.



The scheduler does not start containers.



It determines node placement.



\## kube-controller-manager



Runs Kubernetes controllers that reconcile desired state and current state.



Conceptual model:



```text

Desired State

&#x20;     ↓

Controller

&#x20;     ↓

Current State

&#x20;     ↓

Reconciliation

```



Examples include controllers for:



\- Nodes

\- ReplicaSets

\- Jobs

\- Namespaces

\- ServiceAccounts

\- PersistentVolume lifecycle



\## Worker Node



Typical worker components:



```text

kubelet

container runtime

CNI

CSI

Pods

```



\## kubelet



kubelet is the node agent responsible for managing Pods assigned to the node.



It coordinates:



\- Pod lifecycle

\- container runtime

\- networking

\- volumes

\- container configuration



\## Container Runtime



Typical architecture:



```text

kubelet

&#x20;↓

CRI

&#x20;↓

containerd

&#x20;↓

OCI runtime

&#x20;↓

Linux kernel

```



\## CNI



CNI provides Pod networking.



Conceptual flow:



```text

Pod

&#x20;↓

CNI

&#x20;↓

Network Namespace

&#x20;↓

Pod Network

```



\## CSI



CSI provides storage integration.



Provisioning:



```text

PVC

&#x20;↓

StorageClass

&#x20;↓

CSI Controller

&#x20;↓

Storage Backend

```



Node-side operation:



```text

kubelet

&#x20;↓

CSI Node Plugin

&#x20;↓

Volume

&#x20;↓

Pod

```



\## kubectl apply Flow



When running:



```bash

kubectl apply -f deployment.yaml

```



the conceptual flow is:



```text

kubectl

&#x20;↓

kube-apiserver

&#x20;↓

Authentication

&#x20;↓

Authorization

&#x20;↓

Admission

&#x20;↓

Validation

&#x20;↓

etcd

&#x20;↓

Controllers

&#x20;↓

Deployment

&#x20;↓

ReplicaSet

&#x20;↓

Pods

&#x20;↓

Scheduler

&#x20;↓

Node Assignment

&#x20;↓

kubelet

&#x20;↓

CNI / CSI / container runtime

&#x20;↓

Linux kernel

&#x20;↓

Container

```



\## Deployment Reconciliation



Example:



```text

Desired replicas = 3

Current replicas = 0

```



The controller creates the required objects.



Eventually:



```text

Desired replicas = 3

Current replicas = 3

```



\## Self-Healing



If a Pod dies:



```text

Desired = 3

Current = 2

&#x20;       ↓

ReplicaSet controller

&#x20;       ↓

Replacement Pod

```



\## Control Plane vs Data Plane



Control Plane:



```text

API Server

etcd

Scheduler

Controllers

```



Data Plane:



```text

Worker Nodes

kubelet

container runtime

CNI

Pods

```



\## Declarative Architecture



Kubernetes is primarily declarative.



The user specifies:



```text

Desired State

```



Controllers continuously reconcile:



```text

Desired State

&#x20;       vs

Current State

```



\## GitOps Relationship



```text

Git

&#x20;↓

Desired State

&#x20;↓

GitOps Controller

&#x20;↓

Kubernetes API

&#x20;↓

Kubernetes Controllers

&#x20;↓

Actual State

```



\## Important Distinction



etcd stores Kubernetes control-plane state.



Application data normally lives in application storage such as:



```text

PVC

&#x20;↓

PV

&#x20;↓

Storage Backend

```



These require different backup strategies.



\## Key Takeaways



\- API Server is the central Kubernetes API endpoint.

\- etcd stores Kubernetes cluster state.

\- Scheduler selects nodes for Pods.

\- Controllers reconcile desired and current state.

\- kubelet manages Pods on worker nodes.

\- The container runtime actually creates/runs containers.

\- CNI provides networking.

\- CSI provides storage integration.

\- Kubernetes is declarative and reconciliation-based.

\- GitOps builds on Kubernetes' desired-state model.

