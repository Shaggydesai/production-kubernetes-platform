\# Kubernetes Controllers



\## Overview



Controllers continuously reconcile the actual cluster state with the desired state declared through Kubernetes API objects.



The fundamental control loop is:



```text

Observe

&#x20; ↓

Compare

&#x20; ↓

Act

&#x20; ↓

Observe Again

```



\---



\## kube-controller-manager



`kube-controller-manager` runs multiple Kubernetes controllers.



Examples include:



\- Deployment controller

\- ReplicaSet controller

\- Node controller

\- Job controller

\- StatefulSet controller

\- Namespace controller

\- ServiceAccount controller

\- EndpointSlice controller

\- PersistentVolume controller



\---



\## Deployment Reconciliation



```text

Deployment

&#x20;   ↓

Deployment Controller

&#x20;   ↓

ReplicaSet

&#x20;   ↓

ReplicaSet Controller

&#x20;   ↓

Pods

&#x20;   ↓

Scheduler

&#x20;   ↓

kubelet

```



\---



\## Informers



Controllers use watches and informers to efficiently observe changes through the API Server.



```text

API Server

&#x20;   ↓

Watch

&#x20;   ↓

Informer

&#x20;   ↓

Local Cache

&#x20;   ↓

Work Queue

&#x20;   ↓

Controller

```



\---



\## Work Queue



Work queues provide:



\- Event buffering

\- Retry

\- Rate limiting

\- Backoff

\- Controlled processing



\---



\## Idempotency



Reconciliation should be idempotent.



If the desired state is already satisfied, another reconciliation should not create unnecessary resources.



\---



\## Key Takeaways



\- Controllers implement reconciliation.

\- Controllers do not directly start containers.

\- Controllers modify Kubernetes API objects.

\- The Scheduler assigns Pods to nodes.

\- kubelet creates workloads on nodes.

\- Informers and work queues make controllers scalable.

\- Kubernetes is fundamentally a continuous reconciliation system.

