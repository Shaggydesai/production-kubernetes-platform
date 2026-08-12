\# Kubernetes Scheduler



\## Overview



The Kubernetes Scheduler selects a suitable Worker Node for Pods that do not yet have a node assignment.



The Scheduler does not create containers or configure networking.



\---



\## Scheduling Flow



```text

Pod

&#x20;↓

Scheduling Queue

&#x20;↓

Filtering

&#x20;↓

Scoring

&#x20;↓

Node Selection

&#x20;↓

Binding

&#x20;↓

kubelet

```



\---



\## Filtering



Filtering determines whether a node is feasible.



Examples:



\- Resource availability

\- Taints and tolerations

\- Node affinity

\- Pod affinity

\- Pod anti-affinity

\- Volume constraints

\- Topology constraints



\---



\## Scoring



Scoring ranks feasible nodes according to scheduling preferences.



\---



\## Important Concepts



\### Resource Requests



The Scheduler uses resource requests when determining whether a Pod can fit on a node.



\### Taints



Nodes can reject Pods unless those Pods have matching tolerations.



\### Node Affinity



Allows Pods to require or prefer nodes with particular labels.



\### Pod Affinity



Allows Pods to prefer or require placement near other Pods.



\### Pod Anti-Affinity



Allows Pods to avoid placement near other Pods.



\### Topology Spread



Distributes replicas across topology domains such as zones or nodes.



\### Preemption



Allows higher-priority Pods to displace lower-priority Pods when necessary.



\---



\## Key Takeaways



\- Scheduler selects nodes.

\- kubelet actually creates Pods.

\- Filtering determines feasibility.

\- Scoring ranks feasible nodes.

\- Resource requests influence scheduling.

\- Taints and affinity can prevent scheduling.

\- `kubectl describe pod` is essential when debugging Pending Pods.






# Kubernetes Scheduler

## Purpose

The Kubernetes scheduler selects a suitable node for an unscheduled Pod.

The scheduler does not start containers.

Conceptually:

```text
Pod
 ↓
Scheduler
 ↓
Node Selection
 ↓
Binding
 ↓
kubelet
 ↓
Container Runtime
```

## Unscheduled Pod

A newly created Pod may initially have no node assignment.

Conceptually:

```text
Pod
 └── nodeName: empty
```

The scheduler watches the Kubernetes API for such Pods.

## Scheduling Process

Simplified scheduling flow:

```text
Pod
 ↓
Filtering
 ↓
Scoring
 ↓
Node Selection
 ↓
Binding
```

## Filtering

Filtering asks:

```text
Can this Pod run on this node?
```

A node can be filtered because of:

- insufficient CPU
- insufficient memory
- taints
- node selector mismatch
- node affinity
- volume constraints
- topology constraints
- other scheduling requirements

## Resource Requests

Example:

```yaml
resources:
  requests:
    cpu: "500m"
    memory: "512Mi"
```

Requests are important for scheduling decisions.

CPU:

```text
1000m = 1 CPU
500m = 0.5 CPU
250m = 0.25 CPU
```

Memory commonly uses:

```text
Mi
Gi
```

## Requests vs Limits

Example:

```yaml
resources:
  requests:
    cpu: "500m"
    memory: "512Mi"
  limits:
    cpu: "1"
    memory: "1Gi"
```

Requests primarily influence scheduling.

Limits define workload resource boundaries.

## Node Capacity and Allocatable

Nodes expose:

```text
Capacity
Allocatable
```

The scheduler primarily considers resources available to workloads through allocatable capacity and resource requests.

## Taints

A taint can prevent ordinary Pods from being scheduled on a node.

Example:

```text
dedicated=gpu:NoSchedule
```

Command:

```bash
kubectl taint nodes worker-1 dedicated=gpu:NoSchedule
```

## Tolerations

A Pod can tolerate a node taint:

```yaml
tolerations:
  - key: dedicated
    operator: Equal
    value: gpu
    effect: NoSchedule
```

A toleration makes a Pod eligible for a tainted node.

A toleration does not force placement on that node.

## Taint Effects

Common effects:

```text
NoSchedule
PreferNoSchedule
NoExecute
```

`NoSchedule` prevents scheduling of non-tolerating new Pods.

`PreferNoSchedule` expresses a softer avoidance preference.

`NoExecute` can also affect existing Pods that do not tolerate the taint.

## Node Labels

Nodes can be labelled:

```bash
kubectl label node worker-1 disk=ssd
```

View labels:

```bash
kubectl get nodes --show-labels
```

## nodeSelector

Example:

```yaml
nodeSelector:
  disk: ssd
```

The Pod can only be scheduled on nodes matching the label.

## Node Affinity

Node affinity provides more expressive node-selection rules.

Required example:

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: disk
              operator: In
              values:
                - ssd
```

## Required vs Preferred

Required:

```text
requiredDuringSchedulingIgnoredDuringExecution
```

Hard requirement.

Preferred:

```text
preferredDuringSchedulingIgnoredDuringExecution
```

Soft preference.

## Pod Affinity

Pod affinity allows workloads to prefer or require placement near other Pods based on labels and topology.

## Pod Anti-Affinity

Pod anti-affinity can help separate replicas.

Example:

```text
worker-1 → replica-1
worker-2 → replica-2
worker-3 → replica-3
```

instead of placing all replicas on one node.

## Topology

Kubernetes can reason about topology domains such as:

```text
hostname
zone
region
```

## Topology Spread

Topology spread constraints can distribute Pods across topology domains.

This improves workload resilience by avoiding excessive concentration.

## Filtering vs Scoring

Filtering:

```text
Can the Pod run here?
```

Scoring:

```text
How desirable is this node?
```

Conceptually:

```text
All Nodes
 ↓
Filtering
 ↓
Valid Nodes
 ↓
Scoring
 ↓
Best Node
```

## Binding

After selecting a node, the scheduler records the Pod's node assignment through the Kubernetes API.

The kubelet on that node then manages the Pod.

## Scheduler vs Controller

Controller:

```text
How many Pods should exist?
```

Scheduler:

```text
Which node should each Pod run on?
```

## Scheduler vs kubelet

Scheduler:

```text
Placement
```

kubelet:

```text
Node-level execution
```

## Pending Pods

A Pod can remain `Pending` because no node satisfies its scheduling requirements.

Useful troubleshooting command:

```bash
kubectl describe pod <pod-name>
```

Check the `Events` section for scheduling failures.

Common causes include:

```text
Insufficient CPU
Insufficient memory
Taints
Affinity
Node selector
Topology constraints
Volume constraints
```

## Mental Model

```text
Controller
 ↓
Pod
 ↓
Scheduler
 ↓
Filtering
 ↓
Scoring
 ↓
Node
 ↓
kubelet
 ↓
Container Runtime
```

## Key Principle

The scheduler makes placement decisions based on declared requirements and cluster constraints.

Do not confuse:

```text
Scheduling
```

with:

```text
Container execution
```
