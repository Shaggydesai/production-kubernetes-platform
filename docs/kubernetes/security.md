\# Kubernetes Security Architecture



\## Security Layers



Kubernetes security consists of multiple layers:



```text

Authentication

&#x20;     ↓

Authorization / RBAC

&#x20;     ↓

Admission

&#x20;     ↓

Workload Security

&#x20;     ↓

Network Security

&#x20;     ↓

Node Security

&#x20;     ↓

Linux Kernel

```



\## Authentication



Authentication answers:



```text

Who are you?

```



Possible identities include:



\- users

\- groups

\- ServiceAccounts

\- OIDC identities

\- client certificates



\## Authorization



Authorization answers:



```text

What are you allowed to do?

```



Kubernetes commonly uses RBAC.



Main RBAC resources:



\- Role

\- ClusterRole

\- RoleBinding

\- ClusterRoleBinding



\## Role



A Role grants permissions within a namespace.



Example:



```yaml

apiVersion: rbac.authorization.k8s.io/v1

kind: Role

metadata:

&#x20; name: pod-reader

&#x20; namespace: production

rules:

&#x20; - apiGroups: \[""]

&#x20;   resources:

&#x20;     - pods

&#x20;   verbs:

&#x20;     - get

&#x20;     - list

&#x20;     - watch

```



\## ClusterRole



ClusterRole is cluster-scoped and can describe permissions for cluster-scoped resources or permissions used across namespaces.



\## Principle of Least Privilege



Grant:



```text

minimum permissions

minimum scope

```



Avoid using `cluster-admin` unless genuinely required.



\## ServiceAccounts



Pods can use ServiceAccounts as identities when communicating with the Kubernetes API.



Example:



```yaml

spec:

&#x20; serviceAccountName: application

```



If a workload does not need Kubernetes API access, consider disabling automatic token mounting:



```yaml

automountServiceAccountToken: false

```



\## Kubernetes Secrets



Secrets store sensitive configuration in Kubernetes.



Important:



```text

Base64 encoding != encryption

```



Production environments should consider encryption at rest and/or external secret-management systems.



\## Workload Security



Containers use Linux security mechanisms including:



\- namespaces

\- cgroups

\- capabilities

\- seccomp

\- AppArmor



\## Privileged Containers



Avoid:



```yaml

securityContext:

&#x20; privileged: true

```



unless there is a documented requirement.



Privileged containers significantly reduce isolation from the host.



\## Linux Capabilities



Prefer dropping unnecessary capabilities:



```yaml

securityContext:

&#x20; capabilities:

&#x20;   drop:

&#x20;     - ALL

```



Then add only capabilities actually required by the workload.



\## Seccomp



Seccomp filters Linux system calls.



Recommended baseline:



```yaml

securityContext:

&#x20; seccompProfile:

&#x20;   type: RuntimeDefault

```



\## AppArmor



AppArmor can restrict workload behavior through Linux mandatory access-control profiles.



Seccomp and AppArmor provide different controls and can complement each other.



\## Non-Root Containers



Prefer:



```yaml

securityContext:

&#x20; runAsNonRoot: true

```



Avoid unnecessary UID 0 execution.



\## Privilege Escalation



For hardened workloads:



```yaml

securityContext:

&#x20; allowPrivilegeEscalation: false

```



\## Read-Only Root Filesystem



Where compatible:



```yaml

securityContext:

&#x20; readOnlyRootFilesystem: true

```



Use explicit writable volumes for locations that genuinely require writes.



\## Pod Security Standards



Kubernetes defines security levels:



\- Privileged

\- Baseline

\- Restricted



`Restricted` provides stronger workload security requirements than `Baseline`.



\## NetworkPolicy



NetworkPolicy controls Pod network traffic.



A common architecture is:



```text

Default deny

&#x20;    ↓

Explicitly allow required communication

```



Example:



```text

Frontend → Backend       ALLOW

Backend → Database       ALLOW

Frontend → Database      DENY

Internet → Database      DENY

```



\## Node Security



Nodes must also be hardened.



Important areas:



\- SSH

\- kernel

\- kubelet

\- container runtime

\- filesystem

\- credentials

\- network

\- logs



\## API Server Security



The API server is a central security boundary.



Conceptually:



```text

Request

&#x20;↓

Authentication

&#x20;↓

Authorization

&#x20;↓

Admission

&#x20;↓

API object

```



\## Admission



Admission controls can reject otherwise authorized requests.



Example:



```text

RBAC:

ALLOW



Admission policy:

DENY privileged Pod

```



\## Audit



Kubernetes API audit logging can record:



\- who performed an action

\- what was requested

\- when it happened

\- which resource was accessed

\- result of the request



\## Supply Chain Security



Security should cover the complete software supply chain:



```text

Source

&#x20;↓

Build

&#x20;↓

Image

&#x20;↓

Scan

&#x20;↓

Registry

&#x20;↓

Deploy

&#x20;↓

Runtime

```



Use immutable image references where possible.



Example:



```text

image@sha256:<digest>

```



\## Security Mental Model



For every workload ask:



1\. Who can deploy it?

2\. Is the image trusted?

3\. Can it run as root?

4\. Which Linux capabilities does it have?

5\. Which syscalls can it make?

6\. What filesystem access does it have?

7\. Which Pods can it contact?

8\. Can it access the Kubernetes API?

9\. Where are its secrets stored?

10\. Can security-relevant actions be audited?



\## Defense in Depth



Production Kubernetes security should combine:



```text

RBAC

\+

Pod Security

\+

non-root

\+

capabilities

\+

seccomp

\+

AppArmor

\+

NetworkPolicy

\+

image scanning

\+

image signing

\+

Secrets management

\+

audit logging

```



No single security control is sufficient by itself.

