\# Kubernetes Storage Architecture



\## Core Concepts



PV = PersistentVolume



PVC = PersistentVolumeClaim



StorageClass = storage provisioning profile



CSI = Container Storage Interface



\## Basic Model



```text

Pod

&#x20;↓

PVC

&#x20;↓

PV

&#x20;↓

CSI

&#x20;↓

Storage Backend 







Dynamic Provisioning  







PVC

&#x20;↓

StorageClass

&#x20;↓

CSI Driver

&#x20;↓

Storage Backend

&#x20;↓

Volume

&#x20;↓

PV

&#x20;↓

PVC Bound 





Access Modes

ReadWriteOnce

ReadOnlyMany

ReadWriteMany

ReadWriteOncePod



Access modes describe capabilities requested from the storage system. They do not magically provide capabilities unsupported by the backend.



Reclaim Policies

Delete



Deletes dynamically provisioned storage according to driver/backend behavior.



Retain



Retains the storage after the claim is released and requires manual lifecycle management.



Volume Binding



StorageClasses can use:



Immediate

WaitForFirstConsumer



WaitForFirstConsumer delays binding/provisioning so scheduling topology can be considered.



CSI



CSI separates Kubernetes storage APIs from vendor-specific storage implementations.



Conceptually:



Kubernetes

&#x20;↓

CSI Driver

&#x20;↓

Storage Backend

Troubleshooting

kubectl get storageclass

kubectl get pv

kubectl get pvc -A

kubectl describe pvc <name>

kubectl describe pv <name>

kubectl get csidrivers

kubectl get csinodes

Important Distinctions

Persistence != Backup



Snapshot != Backup



PVC != actual storage



RWO != necessarily one Pod



RWX requires backend support

Storage Architecture

Application

&#x20;   ↓

Pod

&#x20;   ↓

PVC

&#x20;   ↓

StorageClass

&#x20;   ↓

CSI Driver

&#x20;   ↓

Storage Backend



\---

