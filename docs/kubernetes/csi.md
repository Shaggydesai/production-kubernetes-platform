\# Kubernetes CSI Architecture



\## Overview



CSI stands for Container Storage Interface.



CSI provides a standard interface between Kubernetes and storage systems.



```text

Kubernetes

&#x20;   ↓

CSI Driver

&#x20;   ↓

Storage Backend

```



\## Dynamic Provisioning



```text

PVC

&#x20;↓

StorageClass

&#x20;↓

External Provisioner

&#x20;↓

CSI Controller

&#x20;↓

CreateVolume

&#x20;↓

Storage Backend

&#x20;↓

PV

&#x20;↓

PVC Bound

```



\## Pod Volume Lifecycle



After the PVC is bound:



```text

Pod

&#x20;↓

Scheduler

&#x20;↓

Node

&#x20;↓

CSI Node Plugin

&#x20;↓

Stage

&#x20;↓

Publish

&#x20;↓

Container

```



\## CSI Components



Common components include:



\- CSI Controller

\- CSI Node Plugin

\- external-provisioner

\- external-attacher

\- external-resizer

\- external-snapshotter

\- node-driver-registrar



Exact components depend on the driver and enabled features.



\## Controller Responsibilities



Common controller-side operations:



\- CreateVolume

\- DeleteVolume

\- ControllerPublishVolume

\- ControllerUnpublishVolume



The exact operations depend on driver capabilities.



\## Node Responsibilities



Common node-side operations:



\- NodeStageVolume

\- NodeUnstageVolume

\- NodePublishVolume

\- NodeUnpublishVolume



\## VolumeAttachment



For attachable storage:



```text

Volume

&#x20;↓

VolumeAttachment

&#x20;↓

Node

```



Inspect with:



```bash

kubectl get volumeattachment

```



\## Troubleshooting



\### PVC Pending



Investigate:



```text

StorageClass

CSI provisioner

CSI controller

Storage backend

```



Commands:



```bash

kubectl get pvc -A

kubectl describe pvc <name>

kubectl get storageclass

kubectl get csidrivers

```



\### PVC Bound but Pod Pending



Investigate:



```text

Scheduling

Attach

Mount

Topology

CSI node plugin

Kubelet

```



Commands:



```bash

kubectl describe pod <name>

kubectl get volumeattachment

journalctl -u kubelet

```



\### Pod Running but Application Cannot Use Volume



Investigate:



```text

Filesystem

Permissions

UID/GID

Mount options

Application configuration

```



\## Important Distinction



```text

Provisioning

=

creating storage



Attach

=

making storage available to a node



Mount/Stage

=

preparing storage on the node



Publish

=

making storage available to the Pod



Application access

=

using the mounted filesystem

```



These are separate stages.



\## Complete Architecture



```text

PVC

&#x20;↓

StorageClass

&#x20;↓

External Provisioner

&#x20;↓

CSI Controller

&#x20;↓

Storage Backend

&#x20;↓

PV

&#x20;↓

PVC Bound

&#x20;↓

Pod

&#x20;↓

Scheduler

&#x20;↓

Node

&#x20;↓

CSI Node Plugin

&#x20;↓

Stage

&#x20;↓

Publish

&#x20;↓

Container

```



\## Key Takeaways



\- CSI separates Kubernetes from vendor-specific storage implementations.

\- Dynamic provisioning uses a StorageClass and CSI provisioner.

\- Provisioning and mounting are separate operations.

\- CSI controller components handle control-plane storage operations.

\- CSI node plugins perform node-side operations.

\- Kubelet coordinates Pod volume mounting.

\- `PVC Pending` and `PVC Bound + Pod Pending` indicate different troubleshooting layers.

\- `VolumeAttachment` is useful when debugging attachable storage.

