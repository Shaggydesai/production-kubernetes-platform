\# Lifecycle of `kubectl apply`



\## Overview



The `kubectl apply` command sends the desired Kubernetes object to the API Server.



The API Server validates, stores, and distributes the desired state.



The Scheduler assigns a node.



The kubelet creates the Pod using the container runtime and CNI.



\---



\## Lifecycle



1\. User runs `kubectl apply`

2\. kubectl reads kubeconfig

3\. TLS authentication

4\. Authorization (RBAC)

5\. Admission Controllers

6\. API validation

7\. Store object in etcd

8\. Scheduler selects node

9\. kubelet observes assignment

10\. containerd creates Pod

11\. CNI configures networking

12\. runc creates containers

13\. kubelet reports status

14\. API Server updates Pod status



\---



\## Components Involved



\- kubectl

\- kubeconfig

\- API Server

\- etcd

\- Scheduler

\- kubelet

\- containerd

\- CNI

\- runc

\- Linux kernel



\---



\## Key Takeaways



\- Kubernetes is declarative.

\- The API Server is the central communication point.

\- etcd stores desired and actual cluster state.

\- kubelet creates workloads only after scheduling.

\- CNI configures Pod networking.

