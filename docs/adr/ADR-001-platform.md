\# ADR-001: Adopt Kubernetes and GitOps as the Platform Foundation



\* \*\*Status:\*\* Accepted

\* \*\*Date:\*\* 2026-08-03

\* \*\*Authors:\*\* Sagar Desai

\* \*\*Decision Makers:\*\* Platform Engineering Team (Portfolio Project)



\---



\# Context



Modern software teams require an application platform that is reliable, scalable, secure, and easy to operate.



Traditional deployment approaches often rely on engineers manually logging into servers, copying application files, restarting services, or executing deployment scripts. While this approach may work for small environments, it becomes increasingly difficult to maintain as systems grow.



Some common challenges include:



\* Configuration drift between environments

\* Manual deployment errors

\* Limited deployment traceability

\* Difficult rollback procedures

\* Inconsistent infrastructure

\* Poor scalability

\* Operational overhead



As organizations adopt cloud-native technologies and microservices, a more automated and declarative platform becomes necessary.



The objective of this project is to build a production-style platform that demonstrates modern Platform Engineering and DevOps practices while remaining practical for learning and portfolio purposes.



\---



\# Problem Statement



How should the platform manage containerized applications in a way that is:



\* Highly available

\* Scalable

\* Self-healing

\* Secure

\* Automated

\* Reproducible

\* Easy to maintain



Additionally, how should deployments be performed in a way that minimizes manual intervention while maintaining a clear history of infrastructure and application changes?



\---



\# Decision



The platform will use:



\* \*\*Kubernetes\*\* as the container orchestration platform.

\* \*\*GitOps\*\* as the deployment methodology.

\* \*\*Argo CD\*\* as the GitOps controller.

\* \*\*GitHub\*\* as the single source of truth for infrastructure and application configuration.



All Kubernetes manifests, Helm values, and infrastructure configuration will be stored in Git.



Any desired change to the platform will be introduced through a Git commit rather than by manually modifying resources inside the cluster.



\---



\# Why Kubernetes?



Kubernetes has become the industry standard for container orchestration because it provides capabilities that are difficult to implement consistently with custom scripts or traditional virtual machines.



Key advantages include:



\## Declarative Infrastructure



Engineers describe the desired state of the system instead of writing imperative deployment scripts.



Example:



Instead of saying:



> Start three containers.



We declare:



> There should always be three healthy application replicas.



Kubernetes continuously works to maintain that desired state.



\---



\## Self-Healing



If a container crashes or a node becomes unavailable, Kubernetes automatically recreates workloads without manual intervention.



Benefits include:



\* Improved availability

\* Reduced operational effort

\* Faster recovery



\---



\## Scalability



Applications can scale horizontally by increasing replica counts manually or automatically using the Horizontal Pod Autoscaler (HPA).



This enables applications to respond to increased demand while optimizing resource usage.



\---



\## Service Discovery



Applications communicate using Kubernetes Services instead of hardcoded IP addresses.



Benefits:



\* Stable networking

\* Simplified service communication

\* Easier scaling



\---



\## Rolling Updates



Application updates can be deployed gradually without significant downtime.



If a deployment fails, Kubernetes supports rollback to a previous stable version.



\---



\## Large Ecosystem



Kubernetes has a mature ecosystem including:



\* Helm

\* Prometheus

\* Grafana

\* cert-manager

\* Argo CD

\* External Secrets Operator

\* Velero

\* Longhorn



Choosing Kubernetes allows the platform to integrate with widely adopted cloud-native tooling.



\---



\# Why GitOps?



GitOps extends Infrastructure as Code by treating Git as the single source of truth for infrastructure and application configuration.



Instead of engineers applying manifests manually, the cluster continuously synchronizes itself with the desired configuration stored in Git.



This approach provides consistency, transparency, and repeatability.



\---



\# Benefits of GitOps



\## Version Control



Every infrastructure change is recorded in Git.



Benefits:



\* Complete history

\* Easy code reviews

\* Traceability

\* Collaboration



\---



\## Automated Deployments



After code is merged into the repository, Argo CD synchronizes the Kubernetes cluster automatically.



This reduces manual deployment steps and lowers the risk of human error.



\---



\## Drift Detection



If someone changes a Kubernetes resource manually, Argo CD detects the difference between the cluster and Git.



Depending on the synchronization policy, Argo CD can automatically restore the desired state.



\---



\## Rollback



If an application deployment introduces problems, the previous configuration can be restored simply by reverting the Git commit.



This makes recovery predictable and repeatable.



\---



\## Auditability



Git maintains a complete history of:



\* Who made a change

\* When the change occurred

\* What changed

\* Why it changed (through commit messages and pull requests)



This is valuable for troubleshooting and compliance.



\---



\# Alternatives Considered



\## Option 1 — Manual Deployments



\### Advantages



\* Easy to start

\* No additional tooling



\### Disadvantages



\* High risk of human error

\* Difficult to audit

\* Difficult to reproduce

\* Poor scalability



\*\*Decision:\*\* Rejected.



\---



\## Option 2 — Traditional CI/CD Only



In this model, the CI/CD pipeline deploys resources directly to Kubernetes.



\### Advantages



\* Faster initial implementation

\* Familiar workflow



\### Disadvantages



\* Cluster state is not continuously reconciled

\* Configuration drift may occur

\* Rollback often depends on pipeline logic



\*\*Decision:\*\* Rejected.



\---



\## Option 3 — GitOps with Argo CD



\### Advantages



\* Declarative deployments

\* Continuous reconciliation

\* Drift detection

\* Automatic synchronization

\* Simplified rollback

\* Strong operational visibility



\### Disadvantages



\* Additional component to manage

\* Requires understanding GitOps workflows



\*\*Decision:\*\* Accepted.



\---



\# Consequences



Adopting Kubernetes and GitOps provides a modern platform architecture that is aligned with current industry practices.



The platform gains:



\* Automated deployments

\* Self-healing infrastructure

\* Infrastructure versioning

\* Easier disaster recovery

\* Better scalability

\* Improved operational consistency



The trade-off is increased platform complexity and a steeper learning curve. However, this investment results in a more maintainable, production-oriented environment.



\---



\# Future Improvements



As the platform evolves, the following capabilities will be added:



\* Multi-environment GitOps (Development, Staging, Production)

\* Progressive delivery strategies (Blue/Green and Canary deployments)

\* Policy-as-Code with Kyverno

\* Image security scanning

\* Automated compliance checks

\* Multi-cluster GitOps

\* Disaster recovery automation



\---



\# References



\* Kubernetes Documentation

\* Argo CD Documentation

\* CNCF GitOps Working Group

\* GitOps Principles



