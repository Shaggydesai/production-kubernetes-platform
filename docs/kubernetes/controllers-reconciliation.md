\# Kubernetes Controllers and Reconciliation



\## Controller



A controller watches Kubernetes resources and works to make actual state match desired state.



\## Reconciliation



The fundamental control loop is:



Desired State

&#x20;   ↓

Observe

&#x20;   ↓

Compare

&#x20;   ↓

Act

&#x20;   ↓

Observe again



\## Deployment



Typical relationship:



Deployment

&#x20;   ↓

ReplicaSet

&#x20;   ↓

Pods



The Deployment controller manages the Deployment/ReplicaSet relationship.



The ReplicaSet controller maintains the desired number of Pods.



\## Example



Desired:



3 replicas



Actual:



2 Pods



Controller action:



Create another Pod.



Eventually:



Desired = 3

Actual = 3



\## Scaling



3 → 5:



Deployment

&#x20;   ↓

ReplicaSet

&#x20;   ↓

additional Pods

&#x20;   ↓

Scheduler

&#x20;   ↓

Nodes



5 → 2:



The controller reduces the number of running replicas toward the desired count.



\## Pod Deletion



If a Deployment owns a Pod and the Pod is manually deleted:



Desired = 3

Actual = 2



The ReplicaSet controller reconciles the difference and creates a replacement Pod.



\## Rolling Updates



A Deployment image change creates a new Pod template and normally results in a new ReplicaSet.



Conceptually:



Deployment

&#x20;├── Old ReplicaSet

&#x20;└── New ReplicaSet



The rollout gradually moves from the old ReplicaSet to the new ReplicaSet.



\## Rollback



A Deployment can be rolled back using:



kubectl rollout undo deployment <deployment-name>



The controller then reconciles toward the previous revision.



\## Other Controllers



Examples:



\- Deployment Controller

\- ReplicaSet Controller

\- StatefulSet Controller

\- DaemonSet Controller

\- Job Controller

\- CronJob Controller

\- Node Controller

\- EndpointSlice Controller



\## Operators



Operators combine:



```text

Custom Resource

\+

Controller

