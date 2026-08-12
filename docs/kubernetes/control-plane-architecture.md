\# Kubernetes Control Plane Architecture



\## Overview



A Kubernetes cluster consists of a Control Plane and one or more Worker Nodes.



The Control Plane manages the cluster, while Worker Nodes execute workloads.



\---



\## Control Plane Components



\- kube-apiserver

\- etcd

\- kube-scheduler

\- kube-controller-manager

\- cloud-controller-manager (optional)



\---



\## Worker Node Components



\- kubelet

\- Container Runtime (containerd)

\- CNI Plugin

\- Pods



\---



\## Responsibilities



\### API Server



Cluster entry point and API endpoint.



\### etcd



Stores all cluster state.



\### Scheduler



Assigns Pods to nodes.



\### Controller Manager



Maintains desired state.



\### kubelet



Runs workloads on worker nodes.



\---



\## Key Concepts



\- Declarative configuration

\- Desired state

\- Reconciliation loop

\- API-driven architecture

