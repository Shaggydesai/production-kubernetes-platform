\# cert-manager Platform Component



\## 1. Overview



cert-manager is responsible for certificate lifecycle management in the production Kubernetes platform.



It provides:



\- TLS certificate management

\- Certificate issuance and renewal

\- Kubernetes `Certificate` resources

\- `Issuer` and `ClusterIssuer` resources

\- Internal platform Certificate Authority (CA)

\- TLS certificates for platform and application workloads



cert-manager is deployed using Helm and its configuration is maintained in the `production-kubernetes-platform` Git repository.



\---



\## 2. Repository Structure



The cert-manager Helm configuration is stored under:



```text

helm/

â””â”€â”€ platform/

&#x20;   â””â”€â”€ cert-manager/

&#x20;       â”œâ”€â”€ Chart.yaml

&#x20;       â”œâ”€â”€ Chart.lock

&#x20;       â””â”€â”€ values.yaml

```



The Kubernetes PKI resources are stored under:



```text

kubernetes/

â””â”€â”€ platform/

&#x20;   â””â”€â”€ cert-manager/

&#x20;       â”œâ”€â”€ clusterissuer-selfsigned.yaml

&#x20;       â”œâ”€â”€ certificate-platform-ca.yaml

&#x20;       â””â”€â”€ clusterissuer-platform-ca.yaml

```



The Git repository is the source of truth for the desired platform configuration.



Generated certificates, private keys, and Kubernetes Secrets are not committed to Git.



\---



\## 3. cert-manager Helm Deployment



\### 3.1 Helm Dependency



The platform cert-manager chart uses cert-manager `v1.21.1`.



The dependency is defined in:



```text

helm/platform/cert-manager/Chart.yaml

```



The dependency is locked in:



```text

helm/platform/cert-manager/Chart.lock

```



Build the dependency with:



```bash

helm dependency build .

```



Verify the dependency:



```bash

helm dependency list .

```



Expected:



```text

NAME            VERSION   REPOSITORY                    STATUS

cert-manager    v1.21.1   https://charts.jetstack.io    ok

```



\---



\## 4. cert-manager Configuration



The platform configuration is stored in:



```text

helm/platform/cert-manager/values.yaml

```



cert-manager CRDs are enabled and retained:



```yaml

crds:

&#x20; enabled: true

&#x20; keep: true

```



The `keep: true` setting ensures that cert-manager CRDs are retained when the Helm release is removed.



\---



\## 5. High Availability Configuration



The production platform runs two replicas for each major cert-manager component.



\### Controller



```yaml

replicaCount: 2

```



\### Webhook



```yaml

webhook:

&#x20; replicaCount: 2

```



\### CA Injector



```yaml

cainjector:

&#x20; replicaCount: 2

```



This provides redundancy for the cert-manager control-plane components.



\---



\## 6. PodDisruptionBudgets



PodDisruptionBudgets are enabled for the cert-manager components.



The configuration uses:



```yaml

podDisruptionBudget:

&#x20; enabled: true

&#x20; minAvailable: 1

```



This prevents voluntary disruptions from taking all replicas of a component offline at the same time.



Verify:



```bash

kubectl get pdb -n cert-manager

```



Expected components:



```text

cert-manager

cert-manager-cainjector

cert-manager-webhook

```



Each component should have:



```text

MIN AVAILABLE: 1

```



\---



\## 7. Topology Spreading



cert-manager replicas are distributed using Kubernetes node hostname topology.



The configuration uses:



```yaml

topologySpreadConstraints:

&#x20; - maxSkew: 1

&#x20;   topologyKey: kubernetes.io/hostname

&#x20;   whenUnsatisfiable: ScheduleAnyway

```



Each cert-manager component has a matching label selector.



For example, the controller uses:



```yaml

labelSelector:

&#x20; matchLabels:

&#x20;   app.kubernetes.io/component: controller

&#x20;   app.kubernetes.io/instance: cert-manager

&#x20;   app.kubernetes.io/name: cert-manager

```



The webhook and cainjector use their respective component labels.



This allows Kubernetes to distribute replicas across available worker nodes.



The configuration was verified on the three-node Kubernetes cluster.



The resulting placement was:



```text

cert-manager

â”œâ”€â”€ k8s-worker01

â””â”€â”€ k8s-worker02



cert-manager-webhook

â”œâ”€â”€ k8s-worker01

â””â”€â”€ k8s-worker02



cert-manager-cainjector

â”œâ”€â”€ k8s-worker01

â””â”€â”€ k8s-worker02

```



\---



\## 8. Installed cert-manager Components



The cert-manager namespace contains:



```text

cert-manager

cert-manager-cainjector

cert-manager-webhook

```



Verify:



```bash

kubectl get deployment -n cert-manager

```



Expected:



```text

NAME                      READY

cert-manager              2/2

cert-manager-cainjector   2/2

cert-manager-webhook      2/2

```



Pods can be checked with:



```bash

kubectl get pods -n cert-manager -o wide

```



\---



\## 9. cert-manager CRDs



The cert-manager installation manages the required CustomResourceDefinitions.



Verify:



```bash

kubectl get crd | grep cert-manager.io

```



The installed CRDs include:



```text

certificaterequests.cert-manager.io

certificates.cert-manager.io

challenges.acme.cert-manager.io

clusterissuers.cert-manager.io

issuers.cert-manager.io

orders.acme.cert-manager.io

```



These CRDs provide the Kubernetes API resources used by cert-manager.



\---



\## 10. Internal PKI



The platform implements an internal Certificate Authority using cert-manager.



The PKI consists of:



```text

selfsigned-bootstrap

&#x20;       |

&#x20;       | signs

&#x20;       v

&#x20;  platform-ca

&#x20;  Certificate

&#x20;       |

&#x20;       | creates

&#x20;       v

&#x20;Secret: platform-ca

&#x20;       |

&#x20;       | referenced by

&#x20;       v

&#x20;ClusterIssuer: platform-ca

&#x20;       |

&#x20;       | signs

&#x20;       v

&#x20;Application Certificates

```



The bootstrap issuer is used only to create the initial platform CA.



The `platform-ca` ClusterIssuer is then used for normal internal certificate issuance.



\---



\## 11. Bootstrap ClusterIssuer



The bootstrap issuer is defined in:



```text

kubernetes/platform/cert-manager/clusterissuer-selfsigned.yaml

```



Configuration:



```yaml

apiVersion: cert-manager.io/v1

kind: ClusterIssuer

metadata:

&#x20; name: selfsigned-bootstrap

spec:

&#x20; selfSigned: {}

```



This issuer uses cert-manager's self-signed issuer functionality.



Its purpose is to bootstrap the platform CA.



It is not intended to be used as the normal issuer for application certificates.



Verify:



```bash

kubectl get clusterissuer selfsigned-bootstrap

```



Expected:



```text

NAME                   READY

selfsigned-bootstrap   True

```



\---



\## 12. Platform CA Certificate



The platform CA is defined in:



```text

kubernetes/platform/cert-manager/certificate-platform-ca.yaml

```



Configuration:



```yaml

apiVersion: cert-manager.io/v1

kind: Certificate

metadata:

&#x20; name: platform-ca

&#x20; namespace: cert-manager

spec:

&#x20; isCA: true

&#x20; commonName: platform-ca

&#x20; secretName: platform-ca

&#x20; duration: 87600h

&#x20; renewBefore: 720h

&#x20; privateKey:

&#x20;   algorithm: RSA

&#x20;   size: 4096

&#x20; issuerRef:

&#x20;   name: selfsigned-bootstrap

&#x20;   kind: ClusterIssuer

&#x20;   group: cert-manager.io

```



Important properties:



| Property | Value |

|---|---|

| Certificate | `platform-ca` |

| CA | `true` |

| Common Name | `platform-ca` |

| Private Key Algorithm | RSA |

| Private Key Size | 4096 bits |

| Secret | `platform-ca` |

| Issuer | `selfsigned-bootstrap` |

| Duration | `87600h` |

| Renew Before | `720h` |



The resulting CA material is stored in:



```text

Namespace: cert-manager

Secret: platform-ca

```



Verify:



```bash

kubectl get certificate platform-ca -n cert-manager

```



Expected:



```text

NAME          READY   SECRET

platform-ca   True    platform-ca

```



\---



\## 13. Platform CA Secret



The generated CA material is stored in:



```text

cert-manager/platform-ca

```



Verify:



```bash

kubectl get secret platform-ca -n cert-manager

```



Expected:



```text

NAME          TYPE                DATA

platform-ca   kubernetes.io/tls   3

```



The Secret contains sensitive private-key material.



The Secret must never be committed to Git.



\---



\## 14. CA-backed ClusterIssuer



Once the `platform-ca` Secret exists, the platform CA issuer is created.



The resource is stored in:



```text

kubernetes/platform/cert-manager/clusterissuer-platform-ca.yaml

```



Configuration:



```yaml

apiVersion: cert-manager.io/v1

kind: ClusterIssuer

metadata:

&#x20; name: platform-ca

spec:

&#x20; ca:

&#x20;   secretName: platform-ca

```



This tells cert-manager to use the `platform-ca` Secret as the signing CA.



Verify:



```bash

kubectl get clusterissuer platform-ca

```



Expected:



```text

NAME          READY

platform-ca   True

```



The issuer was successfully verified with:



```text

Reason:  KeyPairVerified

Status:  True

Message: Signing CA verified

```



\---



\## 15. PKI Bootstrap Order



The PKI resources must be created in the following logical order:



```text

1\. selfsigned-bootstrap ClusterIssuer

&#x20;               |

&#x20;               v

2\. platform-ca Certificate

&#x20;               |

&#x20;               v

3\. platform-ca Secret

&#x20;               |

&#x20;               v

4\. platform-ca ClusterIssuer

```



The reason for this order is that the CA-backed `platform-ca` ClusterIssuer depends on the `platform-ca` Secret.



The Secret is created by the `platform-ca` Certificate.



The Certificate is issued by `selfsigned-bootstrap`.



\---



\## 16. Certificate Issuance Test



After creating the internal CA, certificate issuance was tested using a temporary certificate.



The test certificate used:



```text

Certificate: platform-test

DNS name:    platform-test.internal

Issuer:      platform-ca

Secret:      platform-test-tls

```



The certificate successfully reached:



```text

READY=True

```



cert-manager successfully:



1\. Generated a private key

2\. Created a CertificateRequest

3\. Issued the certificate

4\. Stored the certificate in a Kubernetes TLS Secret

5\. Marked the Certificate as Ready



The successful issuance event was:



```text

The certificate has been successfully issued

```



This confirmed that the `platform-ca` ClusterIssuer is capable of issuing certificates.



After verification, the temporary test certificate and its generated Secret were deleted.



\---



\## 17. Current PKI State



The current platform state is:



```text

ClusterIssuers

â”œâ”€â”€ selfsigned-bootstrap   READY=True

â””â”€â”€ platform-ca            READY=True



Certificates

â””â”€â”€ platform-ca            READY=True



Secrets

â””â”€â”€ platform-ca            kubernetes.io/tls

```



Verify ClusterIssuers:



```bash

kubectl get clusterissuer

```



Expected:



```text

NAME                   READY

platform-ca            True

selfsigned-bootstrap   True

```



Verify the CA:



```bash

kubectl get certificate -n cert-manager

```



Expected:



```text

NAME          READY   SECRET

platform-ca   True    platform-ca

```



\---



\## 18. Creating an Internal Certificate



Applications that require an internal TLS certificate should reference the platform CA:



```yaml

issuerRef:

&#x20; name: platform-ca

&#x20; kind: ClusterIssuer

&#x20; group: cert-manager.io

```



Example:



```yaml

apiVersion: cert-manager.io/v1

kind: Certificate

metadata:

&#x20; name: example-tls

&#x20; namespace: example

spec:

&#x20; secretName: example-tls

&#x20; dnsNames:

&#x20;   - example.internal

&#x20; issuerRef:

&#x20;   name: platform-ca

&#x20;   kind: ClusterIssuer

&#x20;   group: cert-manager.io

```



cert-manager will create the TLS Secret specified by:



```yaml

secretName: example-tls

```



The application can then mount or reference that Secret.



\---



\## 19. Security Considerations



The following must never be committed to Git:



\- CA private keys

\- TLS private keys

\- Generated certificates

\- Kubernetes Secret manifests containing private keys

\- Application credentials

\- Temporary certificate test artifacts



The Git repository contains only the declarative configuration required to create the resources.



The actual CA private key is stored inside:



```text

Secret: cert-manager/platform-ca

```



Access to this Secret must be restricted using Kubernetes RBAC and the platform's secret-management and backup policies.



\---



\## 20. Backup and Disaster Recovery



The `platform-ca` Secret is a critical platform security asset.



The Kubernetes Secret contains the private key of the internal Certificate Authority.



The Secret must therefore be included in the approved Kubernetes backup and disaster-recovery process.



The distinction between configuration and secret material is important:



```text

Git Repository

&#x20;     |

&#x20;     â””â”€â”€ PKI configuration

&#x20;         â”œâ”€â”€ ClusterIssuer

&#x20;         â”œâ”€â”€ Certificate

&#x20;         â””â”€â”€ Helm configuration



Kubernetes Secret

&#x20;     |

&#x20;     â””â”€â”€ platform-ca

&#x20;         â”œâ”€â”€ CA certificate

&#x20;         â””â”€â”€ CA private key

```



The CA private key must not be recreated casually.



If a new CA is generated, it will have a different identity and certificates signed by the previous CA will no longer chain to the new CA.



Therefore, restoring the existing `platform-ca` Secret is preferred during disaster recovery when preservation of the existing CA identity is required.



\---



\## 21. Operational Verification



The following commands provide a quick health check.



\### cert-manager pods



```bash

kubectl get pods -n cert-manager -o wide

```



\### Deployments



```bash

kubectl get deployment -n cert-manager

```



\### PodDisruptionBudgets



```bash

kubectl get pdb -n cert-manager

```



\### ClusterIssuers



```bash

kubectl get clusterissuer

```



\### Certificates



```bash

kubectl get certificate -n cert-manager

```



\### CA Secret



```bash

kubectl get secret platform-ca -n cert-manager

```



\### Helm release



```bash

helm list -n cert-manager

```



\---



\## 22. Troubleshooting



\### Check cert-manager controller logs



```bash

kubectl logs -n cert-manager deployment/cert-manager

```



\### Check webhook logs



```bash

kubectl logs -n cert-manager deployment/cert-manager-webhook

```



\### Check CA Injector logs



```bash

kubectl logs -n cert-manager deployment/cert-manager-cainjector

```



\### Check the platform ClusterIssuer



```bash

kubectl describe clusterissuer platform-ca

```



\### Check the platform CA



```bash

kubectl describe certificate platform-ca -n cert-manager

```



\### Check the CA Secret



```bash

kubectl describe secret platform-ca -n cert-manager

```



\---



\## 23. Production Design Summary



The production Kubernetes platform uses cert-manager as the certificate management layer.



The design provides:



\- Helm-managed cert-manager installation

\- Version-pinned cert-manager dependency

\- Two replicas for controller, webhook and cainjector

\- PodDisruptionBudgets

\- Topology-aware replica distribution

\- Managed cert-manager CRDs

\- Internal platform Certificate Authority

\- CA-backed ClusterIssuer

\- Automated certificate issuance and renewal

\- Git-managed PKI configuration

\- Kubernetes Secret-based private-key storage

\- Backup and disaster-recovery requirements for the platform CA



The resulting certificate hierarchy is:



```text

selfsigned-bootstrap

&#x20;       |

&#x20;       v

&#x20;  platform-ca

&#x20;       |

&#x20;       v

&#x20;ClusterIssuer

&#x20;  platform-ca

&#x20;       |

&#x20;       v

Internal TLS Certificates

```



\---



\## 24. Implementation Status



The cert-manager platform component is operational.



Completed:



\- \[x] cert-manager Helm dependency configured

\- \[x] cert-manager version pinned to `v1.21.1`

\- \[x] Helm dependency lock created

\- \[x] cert-manager CRDs enabled

\- \[x] Controller configured with two replicas

\- \[x] Webhook configured with two replicas

\- \[x] CA Injector configured with two replicas

\- \[x] PodDisruptionBudgets configured

\- \[x] Topology spreading configured

\- \[x] Self-signed bootstrap ClusterIssuer created

\- \[x] Platform CA created

\- \[x] Platform CA Secret generated

\- \[x] CA-backed ClusterIssuer created

\- \[x] Platform CA verified

\- \[x] Certificate issuance tested successfully

\- \[x] Temporary test certificate removed

\- \[x] Temporary test Secret removed

\- \[x] PKI configuration stored in Git

\- \[x] Documentation created
