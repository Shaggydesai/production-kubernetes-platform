# Argo CD GitOps Platform Component

## 1. Overview

Argo CD is the GitOps continuous delivery component of the production Kubernetes platform.

It provides declarative, Kubernetes-native application delivery by continuously comparing the desired state stored in Git with the live state of Kubernetes resources.

Argo CD is deployed through a Helm wrapper chart maintained in the `production-kubernetes-platform` repository.

The platform exposes the Argo CD UI/API through the shared Envoy Gateway using HTTPS and a certificate issued by the internal platform CA.

---

## 2. Repository Structure

The Argo CD Helm wrapper is stored under:

```text
helm/
└── platform/
    └── argocd/
        ├── Chart.yaml
        ├── Chart.lock
        └── values.yaml

GitOps-specific Kubernetes resources are stored under:

kubernetes/
└── gitops/
    └── applications/
        └── argocd-route.yaml

The Argo CD TLS certificate is managed by cert-manager:

kubernetes/
└── platform/
    └── cert-manager/
        └── certificate-argocd.yaml

The shared platform Gateway is managed separately:

kubernetes/
└── platform/
    └── envoy-gateway/
        └── gateway.yaml
3. Helm Wrapper Chart

The platform does not directly vendor the upstream Argo CD chart as the primary chart.

Instead, the platform uses a Helm wrapper chart.

Chart.yaml:

apiVersion: v2
name: argocd
description: Argo CD configuration for the production Kubernetes platform
type: application
version: 0.1.0
appVersion: "v3.5.1"

dependencies:
  - name: argo-cd
    version: 10.4.0
    repository: "https://argoproj.github.io/argo-helm"

The wrapper provides a controlled platform-specific configuration layer while keeping the upstream Argo CD chart as a dependency.

The dependency is pinned through Chart.lock.

Current versions:

Wrapper chart version: 0.1.0
Argo CD application version: v3.5.1
Argo CD Helm chart version: 10.4.0
4. Helm Configuration

The platform configuration is scoped under the argo-cd dependency:

argo-cd:
  crds:
    install: true
    keep: true

  createClusterRoles: true

  global:
    domain: argocd.platform.internal

    logging:
      format: json
      level: info

    networkPolicy:
      create: true
      defaultDenyIngress: false

    nodeSelector:
      kubernetes.io/os: linux

    affinity:
      podAntiAffinity: soft

  configs:
    cm:
      create: true
      admin.enabled: true
      exec.enabled: false
      timeout.reconciliation: 120s
      timeout.reconciliation.jitter: 60s

    rbac:
      create: true
      policy.default: ""

  controller:
    replicas: 1

  server:
    replicas: 1

  repoServer:
    replicas: 1

  applicationSet:
    replicas: 1

  dex:
    enabled: false

  notifications:
    enabled: false

  redis:
    enabled: true

  redis-ha:
    enabled: false
5. Configuration Decisions
5.1 CRDs

Argo CD CRDs are installed by the chart:

crds:
  install: true
  keep: true

The following Argo CD CRDs were verified in the cluster:

applications.argoproj.io
applicationsets.argoproj.io
appprojects.argoproj.io

These CRDs provide the Kubernetes API objects used by Argo CD.

5.2 Cluster Roles

Cluster-level RBAC is enabled:

createClusterRoles: true

This allows the Argo CD controllers to manage Kubernetes resources across the required cluster scope.

5.3 Argo CD Domain

The configured Argo CD domain is:

argocd.platform.internal

This domain is used by the Argo CD server configuration and the external Gateway route.

5.4 Logging

Argo CD logging is configured as JSON:

logging:
  format: json
  level: info

JSON logging makes the component easier to integrate with centralized Kubernetes logging and observability systems.

5.5 Network Policy

Network policies are enabled:

networkPolicy:
  create: true
  defaultDenyIngress: false

The platform therefore enables Argo CD network policy resources without applying a default-deny ingress policy.

5.6 Linux Node Selection

Argo CD workloads are restricted to Linux nodes:

nodeSelector:
  kubernetes.io/os: linux
5.7 Pod Anti-Affinity

Soft pod anti-affinity is configured:

affinity:
  podAntiAffinity: soft

This encourages Argo CD workloads to spread across nodes where possible without making scheduling impossible.

6. Argo CD Components

The platform deployment currently runs the following Argo CD components:

argocd-application-controller
argocd-applicationset-controller
argocd-repo-server
argocd-server
argocd-redis

The application controller runs as a StatefulSet.

The following components run as Deployments:

argocd-applicationset-controller
argocd-repo-server
argocd-server
argocd-redis

Current replica configuration:

Application Controller:       1
ApplicationSet Controller:    1
Repo Server:                  1
Server:                       1
Redis:                        1
7. Authentication and Optional Components

The Argo CD administrator account is enabled:

admin.enabled: true

Argo CD command execution is disabled:

exec.enabled: false

Dex is disabled:

dex:
  enabled: false

Notifications are disabled:

notifications:
  enabled: false

Redis HA is disabled:

redis-ha:
  enabled: false

A standalone Redis instance is enabled:

redis:
  enabled: true

These choices keep the initial platform deployment intentionally simple while providing a clear path for later integration with external authentication, notifications, and highly available Redis.

8. Argo CD Kubernetes Services

Argo CD exposes the following services:

argocd-applicationset-controller
argocd-redis
argocd-repo-server
argocd-server

The Argo CD server service is:

Service: argocd-server
Type: ClusterIP
Ports:
  80/TCP
  443/TCP

Argo CD internally serves HTTPS through the server endpoint.

9. Internal Connectivity Validation

Argo CD server connectivity was validated from inside the cluster.

HTTP:

curl -I http://argocd-server

Expected behavior:

HTTP/1.1 307 Temporary Redirect
Location: https://argocd-server/

HTTPS:

curl -k -I https://argocd-server

Expected result:

HTTP/1.1 200 OK

Hostname-based HTTPS was also validated from inside the cluster:

curl -k -I \
  --resolve argocd.platform.internal:443:10.102.138.180 \
  https://argocd.platform.internal

Expected result:

HTTP/1.1 200 OK

This confirmed that the Argo CD server itself was functioning before external Gateway exposure was configured.

10. Redis Connectivity

Argo CD uses Redis internally.

The Redis service is:

argocd-redis:6379

The Redis EndpointSlice was verified to point to the running Redis pod.

Connectivity from the Argo CD server was tested with:

kubectl exec -n argocd deploy/argocd-server -- \
  bash -c 'echo > /dev/tcp/argocd-redis/6379 && echo REDIS_OK || echo REDIS_FAILED'

Result:

REDIS_OK

This confirmed that Redis was reachable through the Kubernetes Service.

11. TLS Architecture

The platform uses cert-manager to issue the Argo CD TLS certificate.

The certificate resource is:

kubernetes/platform/cert-manager/certificate-argocd.yaml

Configuration:

apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: argocd-tls
  namespace: envoy-gateway-system
spec:
  secretName: argocd-tls
  duration: 2160h
  renewBefore: 360h
  commonName: argocd.platform.internal
  dnsNames:
    - argocd.platform.internal
  issuerRef:
    name: platform-ca
    kind: ClusterIssuer
    group: cert-manager.io
  privateKey:
    algorithm: RSA
    size: 2048

The certificate is issued by:

ClusterIssuer: platform-ca

The resulting Secret is:

Namespace: envoy-gateway-system
Secret: argocd-tls
Type: kubernetes.io/tls
12. Certificate Validation

The certificate was verified as ready:

kubectl get certificate argocd-tls \
  -n envoy-gateway-system

Expected:

NAME         READY   SECRET
argocd-tls   True    argocd-tls

The certificate served by Envoy Gateway was also inspected:

openssl s_client \
  -connect 192.168.75.240:443 \
  -servername argocd.platform.internal \
  </dev/null 2>/dev/null |
  openssl x509 -noout -subject -issuer -dates -ext subjectAltName

Verified certificate properties:

Subject: CN = argocd.platform.internal
Issuer:  CN = platform-ca

Subject Alternative Name:
DNS:argocd.platform.internal
13. Shared Platform Gateway

Argo CD does not receive a dedicated external LoadBalancer.

Instead, it uses the shared platform Gateway:

platform-gateway

Namespace:

envoy-gateway-system

The Gateway is assigned the MetalLB address:

192.168.75.240

The HTTPS listener uses multiple certificates:

tls:
  mode: Terminate
  certificateRefs:
    - name: platform-gateway-tls
    - name: argocd-tls

This allows Envoy Gateway to select the appropriate certificate using TLS SNI.

14. Argo CD HTTPRoute

The Argo CD route is stored at:

kubernetes/gitops/applications/argocd-route.yaml

Configuration:

apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd
  namespace: argocd
spec:
  parentRefs:
    - name: platform-gateway
      namespace: envoy-gateway-system
      sectionName: https

  hostnames:
    - argocd.platform.internal

  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: argocd-server
          port: 443

Important design decisions:

Explicit HTTPS listener
sectionName: https

This ensures the route attaches specifically to the Gateway's HTTPS listener.

Host-based routing
hostnames:
  - argocd.platform.internal

Only requests addressed to the Argo CD hostname match this route.

Backend
backendRefs:
  - name: argocd-server
    port: 443

Traffic is forwarded to the Argo CD server's HTTPS service.

15. HTTPRoute Validation

The route was validated with:

kubectl describe httproute argocd -n argocd

The route reported:

Accepted=True
ResolvedRefs=True

This confirms that:

Envoy Gateway accepted the route.
The Gateway reference is valid.
The backend Service reference is valid.
The HTTPS listener accepted the route.
16. External Traffic Flow

The complete request path is:

Client
  |
  | HTTPS
  | SNI: argocd.platform.internal
  |
  v
MetalLB
192.168.75.240
  |
  v
Envoy Gateway
:443
  |
  | TLS termination
  | Certificate: argocd-tls
  |
  v
HTTPRoute
argocd.platform.internal
  |
  v
argocd-server
:443
  |
  v
Argo CD

MetalLB provides the external LoadBalancer IP.

Envoy Gateway provides Gateway API-based traffic management.

cert-manager provides the TLS certificate.

Argo CD provides the GitOps control plane.

17. External HTTPS Validation

The external Argo CD endpoint was tested using:

curl -vk \
  --resolve argocd.platform.internal:443:192.168.75.240 \
  https://argocd.platform.internal/

The request successfully reached Argo CD.

The response was:

HTTP/2 307
location: https://argocd.platform.internal/

The 307 response is generated by Argo CD and confirms that the request reached the Argo CD server.

18. Certificate Verification Without -k

After installing the internal platform-ca certificate into the trusted CA store on the Kubernetes node, the endpoint was successfully verified without disabling TLS verification.

Test:

curl \
  --resolve argocd.platform.internal:443:192.168.75.240 \
  https://argocd.platform.internal/

The request succeeded and returned the Argo CD redirect response.

This confirms the complete TLS trust chain:

argocd.platform.internal
        |
        v
argocd-tls
        |
        v
platform-ca
19. Gateway Validation

The Gateway listener status was verified with:

kubectl get gateway platform-gateway \
  -n envoy-gateway-system \
  -o jsonpath='{range .status.listeners[*]}{.name}{" => "}{range .conditions[?(@.type=="Accepted")]}Accepted={.status}{" "}{end}{range .conditions[?(@.type=="Programmed")]}Programmed={.status}{end}{"\n"}{end}'

Verified result:

http => Accepted=True Programmed=True
https => Accepted=True Programmed=True

Therefore both Gateway listeners are operational.

20. Deployment Validation

Verify the Argo CD workloads:

kubectl get pods -n argocd -o wide

All expected Argo CD pods should report:

STATUS: Running
READY:  1/1

Verify deployments:

kubectl get deploy -n argocd

Verify the application controller:

kubectl get statefulset -n argocd

Verify services:

kubectl get svc -n argocd

Verify CRDs:

kubectl get crd | grep argoproj.io
21. Helm Validation

Validate the dependency:

helm dependency list .

Expected:

NAME      VERSION   REPOSITORY
argo-cd   10.4.0    https://argoproj.github.io/argo-helm

Render the chart:

helm template argocd . \
  --namespace argocd \
  -f values.yaml \
  > /tmp/argocd-rendered.yaml

The rendered output should contain:

Deployments
StatefulSet
Services
ConfigMaps
NetworkPolicies
CRDs
ServiceAccounts

The rendered deployment should include:

argocd-applicationset-controller
argocd-repo-server
argocd-server
argocd-redis

The application controller should be rendered as:

argocd-application-controller
22. Argo CD Health Checks

Basic health checks:

kubectl get pods -n argocd
kubectl get svc -n argocd
kubectl get crd | grep argoproj.io
kubectl get httproute argocd -n argocd
kubectl get certificate argocd-tls -n envoy-gateway-system
kubectl get gateway platform-gateway -n envoy-gateway-system

Check Argo CD server logs:

kubectl logs -n argocd deploy/argocd-server --tail=50

The server should report that it is serving HTTPS on port 8080 internally.

23. Troubleshooting
Argo CD pods are not Running

Check:

kubectl get pods -n argocd -o wide
kubectl describe pod -n argocd <pod-name>
kubectl logs -n argocd <pod-name>
Argo CD server cannot communicate with Redis

Check:

kubectl get svc argocd-redis -n argocd
kubectl get endpointslice -n argocd \
  -l kubernetes.io/service-name=argocd-redis

Test connectivity:

kubectl exec -n argocd deploy/argocd-server -- \
  bash -c 'echo > /dev/tcp/argocd-redis/6379 && echo REDIS_OK || echo REDIS_FAILED'

Expected:

REDIS_OK
HTTPRoute is not accepted

Check:

kubectl describe httproute argocd -n argocd

Look for:

Accepted=True
ResolvedRefs=True

Verify the Gateway:

kubectl describe gateway platform-gateway \
  -n envoy-gateway-system
TLS certificate is not Ready

Check:

kubectl get certificate argocd-tls \
  -n envoy-gateway-system

Then:

kubectl describe certificate argocd-tls \
  -n envoy-gateway-system

Verify the issuer:

kubectl get clusterissuer platform-ca
Wrong certificate is returned

Use SNI explicitly:

openssl s_client \
  -connect 192.168.75.240:443 \
  -servername argocd.platform.internal \
  </dev/null 2>/dev/null |
  openssl x509 -noout -subject -issuer -ext subjectAltName

The certificate should contain:

CN = argocd.platform.internal

and:

DNS:argocd.platform.internal
External endpoint does not resolve

For local validation, bypass DNS:

curl \
  --resolve argocd.platform.internal:443:192.168.75.240 \
  https://argocd.platform.internal/

This maps:

argocd.platform.internal
        ->
192.168.75.240

without requiring external DNS.

24. Security Considerations

The platform currently uses an internal CA:

platform-ca

The Argo CD certificate is therefore trusted only by systems that trust this CA.

The Argo CD administrator account is enabled:

admin.enabled: true

The initial platform configuration should therefore be treated as a controlled internal deployment.

Future production hardening should consider:

External identity provider integration
SSO
More restrictive Argo CD RBAC
High availability
Redis HA
Multiple Argo CD replicas
Repository credential management
Secret management integration
Network policy hardening
Audit logging
Backup and disaster recovery

These are future hardening areas and are not part of the current baseline implementation.

25. Current Platform State

The current platform contains:

cert-manager
    |
    └── platform-ca
          |
          ├── platform-gateway-tls
          └── argocd-tls

MetalLB
    |
    └── 192.168.75.240
          |
          v
Envoy Gateway
    |
    ├── HTTP :80
    └── HTTPS :443
          |
          └── argocd.platform.internal
                    |
                    v
                 HTTPRoute
                    |
                    v
                argocd-server
                    |
                    v
                  Argo CD
26. GitOps Role

Argo CD is the GitOps control-plane component of the platform.

The intended model is:

Git Repository
      |
      | Desired state
      v
    Argo CD
      |
      | Reconciliation
      v
Kubernetes API
      |
      v
Cluster Resources

The Git repository becomes the source of truth for declarative Kubernetes configuration.

Argo CD continuously observes the desired state and the live cluster state and reconciles differences according to the configured application definitions.

Application resources will be added under:

kubernetes/gitops/applications/

as the platform grows.

27. Current GitOps Structure

The current GitOps structure is:

kubernetes/
└── gitops/
    ├── argocd/
    └── applications/
        └── argocd-route.yaml

The argocd directory is reserved for Argo CD-specific bootstrap or platform resources.

The applications directory is intended for declarative Argo CD application definitions and GitOps-related resources.

28. Design Principles

The Argo CD implementation follows these platform principles:

Use Helm wrapper charts for third-party platform components.
Pin upstream chart versions using Chart.lock.
Keep platform configuration in Git.
Separate Helm deployment configuration from Kubernetes application resources.
Use cert-manager for certificate lifecycle management.
Use the shared Envoy Gateway instead of creating individual LoadBalancer services.
Use MetalLB to provide the cluster's external LoadBalancer address.
Use Gateway API resources for external application routing.
Keep Git as the declarative source of truth.
Validate every platform integration before committing it.
29. Validation Summary

The following components have been successfully validated:

[✓] Argo CD Helm dependency
[✓] Argo CD Helm rendering
[✓] Argo CD CRDs
[✓] Argo CD application controller
[✓] Argo CD ApplicationSet controller
[✓] Argo CD repo server
[✓] Argo CD server
[✓] Argo CD Redis
[✓] Internal Argo CD HTTPS
[✓] Redis connectivity
[✓] cert-manager Argo CD certificate
[✓] TLS certificate SAN
[✓] Envoy Gateway HTTPS listener
[✓] Argo CD HTTPRoute
[✓] HTTPRoute Accepted
[✓] HTTPRoute ResolvedRefs
[✓] MetalLB external IP
[✓] External HTTPS connectivity
[✓] SNI certificate selection
[✓] TLS verification using platform CA

The Argo CD endpoint is:

https://argocd.platform.internal

The external Gateway address is:

192.168.75.240
30. Summary

Argo CD is deployed as a platform-level GitOps component using an upstream Helm dependency wrapped by the platform repository.

The deployment provides the Argo CD controllers, repository server, server, ApplicationSet controller, and Redis.

External access is implemented through the shared platform networking stack:

MetalLB
   ↓
Envoy Gateway
   ↓
Gateway API HTTPRoute
   ↓
Argo CD

TLS is managed by:

cert-manager
   ↓
platform-ca
   ↓
argocd-tls

The resulting platform endpoint is:

https://argocd.platform.internal

The implementation has been validated from the Kubernetes cluster through the external MetalLB address, including TLS certificate selection and certificate verification.
