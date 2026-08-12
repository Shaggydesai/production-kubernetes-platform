\# Kubernetes VolumeSnapshots and Backup Architecture



\## Persistence vs Snapshot vs Backup



```text

Persistence

=

survive Pod replacement



Snapshot

=

point-in-time storage state



Backup

=

recoverable copy designed for broader failure scenarios

```



\## VolumeSnapshot



Kubernetes supports volume snapshots through CSI.



Main resources:



\- VolumeSnapshot

\- VolumeSnapshotClass

\- VolumeSnapshotContent



Conceptual flow:



```text

PVC

&#x20;↓

VolumeSnapshot

&#x20;↓

CSI Snapshotter

&#x20;↓

CSI Driver

&#x20;↓

Storage Backend

&#x20;↓

Snapshot

```



\## VolumeSnapshotClass



Defines the CSI driver responsible for snapshot operations.



Example:



```yaml

apiVersion: snapshot.storage.k8s.io/v1

kind: VolumeSnapshotClass

metadata:

&#x20; name: fast-snapshots

driver: example.com/csi

```



\## VolumeSnapshot



Example:



```yaml

apiVersion: snapshot.storage.k8s.io/v1

kind: VolumeSnapshot

metadata:

&#x20; name: postgres-snapshot

spec:

&#x20; source:

&#x20;   persistentVolumeClaimName: postgres-data

```



\## Snapshot vs Backup



A snapshot may exist on the same storage system as the original volume.



Therefore:



```text

Volume failure

\+

Storage failure

```



may destroy both the original volume and its snapshot.



A backup should be stored independently enough to protect against the relevant failure domain.



\## Backup



Conceptual architecture:



```text

PVC

&#x20;↓

Storage / Backup Mechanism

&#x20;↓

Object Storage

```



Examples of object storage include:



\- S3

\- MinIO

\- Azure Blob

\- GCS



\## Velero



Velero can be used to back up Kubernetes resources and integrate with supported volume-data backup mechanisms.



Important distinction:



```text

PVC object

!=

actual application data

```



Backing up the PVC definition does not automatically mean the bytes stored in the volume are backed up.



\## RPO



Recovery Point Objective:



```text

How much data can be lost?

```



Example:



```text

RPO = 1 hour

```



\## RTO



Recovery Time Objective:



```text

How quickly must recovery complete?

```



Example:



```text

RTO = 2 hours

```



\## Database Consistency



Storage snapshots and database backups are different concerns.



For databases, consider:



\- application consistency

\- database consistency

\- filesystem consistency

\- storage consistency



Database-native backup mechanisms may be appropriate depending on requirements.



\## Backup Requirements



A production backup strategy should define:



\- frequency

\- retention

\- backup location

\- encryption

\- access control

\- monitoring

\- restore testing



\## Restore Testing



A backup is not proven until it has been restored successfully.



Example:



```text

Backup

&#x20;↓

Temporary environment

&#x20;↓

Restore

&#x20;↓

Application validation

```



\## 3-2-1 Principle



A traditional backup principle is:



```text

3 copies

2 different storage types/media

1 off-site copy

```



The exact implementation should follow organizational requirements.



\## GitOps and Backup



GitOps can recreate Kubernetes configuration and resources.



Backups protect persistent application data.



```text

GitOps

=

cluster/application configuration



Backup

=

persistent application data

```



Both are required for complete disaster recovery.



\## Recovery Architecture



```text

Git Repository

&#x20;     ↓

GitOps

&#x20;     ↓

Kubernetes

&#x20;     ↓

Applications

&#x20;     ↓

Persistent Storage

&#x20;     ↓

Snapshots + Backups

&#x20;     ↓

Independent Object Storage

```



\## Key Takeaways



\- Persistence is not backup.

\- Snapshot is not automatically backup.

\- VolumeSnapshot uses CSI snapshot functionality.

\- VolumeSnapshotClass identifies the snapshot driver.

\- VolumeSnapshotContent represents snapshot content in Kubernetes.

\- PVC definitions and application data are different things.

\- Backups should be protected from the same failure domain as production.

\- RPO measures acceptable data loss.

\- RTO measures acceptable recovery time.

\- Restore testing is mandatory for a trustworthy backup strategy.

