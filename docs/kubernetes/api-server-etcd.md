\# kube-apiserver and etcd



\## API Server



The kube-apiserver is the central entry point to the Kubernetes API.



Typical responsibilities include:



\- authentication

\- authorization

\- admission

\- validation

\- API request handling

\- persistence through etcd

\- watch mechanisms



The Kubernetes API server normally listens on port `6443` using HTTPS.



\## kubectl



`kubectl` is a Kubernetes API client.



Conceptually:



```text

kubectl

&#x20;↓

kube-apiserver

```



kubectl obtains cluster endpoint and credentials from kubeconfig.



\## Authentication



Authentication answers:



```text

Who are you?

```



Examples include:



\- client certificates

\- bearer tokens

\- OIDC

\- ServiceAccount tokens



\## Authorization



Authorization answers:



```text

What are you allowed to do?

```



RBAC evaluates permissions based on identity, verb, resource and scope.



\## Admission



Admission provides an additional control layer after authorization.



A request can be:



```text

authenticated

\+

authorized

\+

rejected by admission

```



\## Kubernetes API Objects



Typical Kubernetes objects contain:



```text

apiVersion

kind

metadata

spec

status

```



`spec` represents desired state.



`status` represents observed/current state.



\## ResourceVersion



`metadata.resourceVersion` identifies the object's version in the Kubernetes API's resource state.



It is important for concurrency and watch processing.



\## Watch



Controllers can watch API resources for changes.



Typical events include:



```text

ADDED

MODIFIED

DELETED

```



This enables event-driven reconciliation.



\## etcd



etcd is the distributed key-value datastore used by Kubernetes for persistent cluster state.



It stores Kubernetes API state such as:



\- Pods

\- Deployments

\- Services

\- Secrets

\- ConfigMaps

\- Nodes

\- Namespaces

\- RBAC resources

\- Custom Resources



\## API Server and etcd



The normal architecture is:



```text

kubectl

&#x20;  ↓

API Server

&#x20;  ↓

etcd

```



Clients and controllers should normally interact with the API server rather than directly modifying etcd.



\## etcd Quorum



Production etcd clusters commonly use an odd number of members.



Examples:



```text

3 members → quorum 2

5 members → quorum 3

7 members → quorum 4

```



Quorum:



```text

floor(N / 2) + 1

```



A three-member cluster can tolerate one member failure while maintaining quorum.



A five-member cluster can tolerate two member failures.



\## Raft



etcd uses the Raft consensus algorithm.



Conceptually:



```text

Leader

&#x20;├── Follower

&#x20;└── Follower

```



State changes are replicated and require the appropriate majority before being committed.



\## etcd Failure



Losing etcd quorum can prevent normal control-plane state changes from being committed.



Existing workloads on worker nodes do not necessarily disappear immediately, but control-plane functionality can be severely affected.



\## etcd Backup



etcd is critical cluster state and requires reliable backups.



Conceptually:



```text

etcd

&#x20;↓

snapshot

&#x20;↓

secure backup

&#x20;↓

restore testing

```



\## API Server High Availability



Multiple API servers can operate against the same etcd cluster.



Example:



```text

Load Balancer

&#x20;     │

&#x20;┌────┼────┐

&#x20;▼    ▼    ▼

API1 API2 API3

&#x20;│    │    │

&#x20;└────┼────┘

&#x20;     ▼

&#x20;    etcd

```



\## Kubernetes Control Flow



A simplified request:



```text

kubectl

&#x20;↓

TLS

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

Watch Event

&#x20;↓

Controller

&#x20;↓

Reconciliation

```



\## Example Deployment Update



```text

kubectl

&#x20;↓

API Server

&#x20;↓

etcd

&#x20;↓

Deployment MODIFIED

&#x20;↓

Deployment Controller

&#x20;↓

ReplicaSet

&#x20;↓

Pods

&#x20;↓

Scheduler

&#x20;↓

kubelet

&#x20;↓

container runtime

```



\## Core Mental Model



Kubernetes continuously reconciles:



```text

Desired State

&#x20;     vs

Current State

```



The API server provides the central API.



etcd stores persistent cluster state.



Controllers observe API state and perform reconciliation.

