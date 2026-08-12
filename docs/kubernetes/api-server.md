\# Kubernetes API Server



\## Overview



The Kubernetes API Server is the central communication hub of the cluster.



Every component communicates through it.



\---



\## Responsibilities



\- Authentication

\- Authorization

\- Admission

\- Validation

\- Serialization

\- Storage

\- Watch API

\- API Aggregation



\---



\## API Groups



\- core/v1

\- apps/v1

\- batch/v1

\- networking.k8s.io/v1

\- storage.k8s.io/v1

\- rbac.authorization.k8s.io/v1



\---



\## Features



\- REST API

\- Watches

\- Informers

\- ResourceVersion

\- Optimistic concurrency

\- CRDs

\- API Aggregation



\---



\## Key Takeaways



\- Everything communicates through the API Server.

\- The API Server persists state in etcd.

\- Controllers use watches and informers for efficient updates.

\- Admission controllers validate and mutate requests before storage.

