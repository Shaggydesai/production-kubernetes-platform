# Envoy Gateway Platform

## Overview

Envoy Gateway is the Gateway API implementation used as the north-south traffic entry point for the production Kubernetes platform.

The platform uses:

- Envoy Gateway
- Kubernetes Gateway API
- MetalLB
- GatewayClass
- Gateway
- HTTPRoute
- Kubernetes Services

The resulting traffic flow is:

Client
  |
  v
MetalLB External IP
  |
  v
Envoy Gateway
  |
  v
Gateway
  |
  v
HTTPRoute
  |
  v
Kubernetes Service
  |
  v
Application Pods

---

## Repository Structure

```text
production-kubernetes-platform/
|
├── helm/
│   └── platform/
│       ├── envoy-gateway/
│       │   ├── Chart.yaml
│       │   ├── Chart.lock
│       │   └── values.yaml
│       │
│       └── metallb/
│           ├── Chart.yaml
│           ├── Chart.lock
│           └── values.yaml
|
├── kubernetes/
│   └── platform/
│       ├── envoy-gateway/
│       │   ├── gatewayclass.yaml
│       │   ├── gateway.yaml
│       │   └── test/
│       │       └── http-test.yaml
│       │
│       └── metallb/
│           ├── ipaddresspool.yaml
│           └── l2advertisement.yaml
|
└── docs/
    └── platform/
        └── envoy-gateway.md

1. Envoy Gateway
Helm Chart

Envoy Gateway is deployed through a platform wrapper Helm chart.

Location:

helm/platform/envoy-gateway/

The wrapper chart uses the upstream Envoy Gateway Helm chart:

dependencies:
  - name: gateway-helm
    version: v1.8.3
    repository: "oci://docker.io/envoyproxy"

Chart version:

0.1.0

Application version:

v1.8.3

The dependency is locked using:

Chart.lock
Envoy Gateway Values

The platform values file is:

helm/platform/envoy-gateway/values.yaml

Current configuration:

gateway-helm:
  crds:
    enabled: true

  podDisruptionBudget:
    minAvailable: 1

  deployment:
    replicas: 2

    pod:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              control-plane: envoy-gateway

  service:
    type: ClusterIP

The values are scoped under:

gateway-helm:

because Envoy Gateway is installed as a Helm subchart.

High Availability

Envoy Gateway runs with two replicas:

deployment:
  replicas: 2

A PodDisruptionBudget is configured:

podDisruptionBudget:
  minAvailable: 1

Topology spreading is configured using:

topologyKey: kubernetes.io/hostname

This allows the two Envoy Gateway replicas to be distributed across different Kubernetes nodes when possible.

Namespace

Envoy Gateway is deployed into:

envoy-gateway-system

Check the deployment:

kubectl get deployment envoy-gateway \
  -n envoy-gateway-system

Expected:

NAME            READY
envoy-gateway   2/2

Check the pods:

kubectl get pods \
  -n envoy-gateway-system \
  -o wide
2. GatewayClass

The platform defines the GatewayClass here:

kubernetes/platform/envoy-gateway/gatewayclass.yaml

Configuration:

apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: envoy-gateway
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller

The important field is:

controllerName: gateway.envoyproxy.io/gatewayclass-controller

This tells Kubernetes that Envoy Gateway is responsible for managing this GatewayClass.

Check:

kubectl get gatewayclass

Expected:

NAME            CONTROLLER
envoy-gateway   gateway.envoyproxy.io/gatewayclass-controller

Check its status:

kubectl describe gatewayclass envoy-gateway

Expected:

Accepted=True
Reason=Accepted
3. Platform Gateway

The platform Gateway is defined here:

kubernetes/platform/envoy-gateway/gateway.yaml

Configuration:

apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: platform-gateway
  namespace: envoy-gateway-system
spec:
  gatewayClassName: envoy-gateway
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All

The Gateway uses:

GatewayClass:
envoy-gateway

The Gateway exposes:

HTTP
Port 80

Routes are currently allowed from all namespaces:

allowedRoutes:
  namespaces:
    from: All

This is useful for platform-level testing and cross-namespace routing.

Gateway Status

Check:

kubectl get gateway platform-gateway \
  -n envoy-gateway-system

Expected:

NAME               CLASS           ADDRESS          PROGRAMMED
platform-gateway   envoy-gateway   192.168.75.240   True

Detailed status:

kubectl describe gateway platform-gateway \
  -n envoy-gateway-system

Important conditions:

Accepted=True
Programmed=True
4. MetalLB

A Kubernetes cluster running on VMs or bare metal does not automatically provide external IP addresses for LoadBalancer Services.

MetalLB is therefore used to provide external IP allocation and Layer 2 advertisement.

MetalLB is deployed through:

helm/platform/metallb/

Version:

v0.16.1

Namespace:

metallb-system
MetalLB Components

MetalLB runs:

metallb-controller
metallb-speaker

The controller runs as a Deployment.

The speaker runs as a DaemonSet.

Check:

kubectl get pods \
  -n metallb-system \
  -o wide

The speakers are running on:

k8s-cp01
k8s-worker01
k8s-worker02
5. MetalLB IPAddressPool

The address pool is defined here:

kubernetes/platform/metallb/ipaddresspool.yaml

Configuration:

apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: platform-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.75.240-192.168.75.250

The available LoadBalancer address range is:

192.168.75.240
-
192.168.75.250

This provides 11 possible addresses.

Check:

kubectl get ipaddresspool \
  -n metallb-system

Expected:

NAME            AUTO ASSIGN   AVOID BUGGY IPS   ADDRESSES
platform-pool   true          false             ["192.168.75.240-192.168.75.250"]
6. MetalLB L2Advertisement

The Layer 2 advertisement is defined here:

kubernetes/platform/metallb/l2advertisement.yaml

Configuration:

apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: platform-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - platform-pool

This tells MetalLB to advertise IP addresses from:

platform-pool

using Layer 2 networking.

Check:

kubectl get l2advertisement \
  -n metallb-system

Expected:

NAME          IPADDRESSPOOLS
platform-l2   ["platform-pool"]
7. Envoy Gateway and MetalLB Integration

When the platform-gateway resource is created, Envoy Gateway creates an Envoy proxy Service.

The generated Service is:

Type: LoadBalancer

Initially, without MetalLB, the Service showed:

EXTERNAL-IP: <pending>

After MetalLB was installed and configured, the Service received:

192.168.75.240

Check:

kubectl get svc \
  -n envoy-gateway-system

Expected:

NAME                                                   TYPE           EXTERNAL-IP
envoy-envoy-gateway-system-platform-gateway-86e22454   LoadBalancer   192.168.75.240
8. Gateway External Address

After MetalLB assigned the IP, the Gateway reported:

Address:
192.168.75.240

The Gateway condition changed to:

Programmed=True

The Gateway reported:

Address assigned to the Gateway, 1/1 envoy replicas available

This confirms:

MetalLB
   |
   v
LoadBalancer Service
   |
   v
Envoy Gateway
   |
   v
Gateway

is functioning correctly.

9. HTTPRoute

The platform test HTTPRoute is located at:

kubernetes/platform/envoy-gateway/test/http-test.yaml

The HTTPRoute is:

apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: http-test
  namespace: envoy-gateway-test
spec:
  parentRefs:
    - name: platform-gateway
      namespace: envoy-gateway-system
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: http-test
          port: 80

The important relationship is:

HTTPRoute
    |
    | parentRefs
    v
platform-gateway
10. Cross-Namespace Routing

The Gateway exists in:

envoy-gateway-system

The test application exists in:

envoy-gateway-test

The Gateway allows routes from all namespaces:

allowedRoutes:
  namespaces:
    from: All

Therefore the HTTPRoute in:

envoy-gateway-test

can attach to:

platform-gateway

in:

envoy-gateway-system

The route was successfully validated with:

Accepted=True
ResolvedRefs=True
11. Test Application

The test application is stored in:

kubernetes/platform/envoy-gateway/test/http-test.yaml

The test namespace is:

envoy-gateway-test

The application is an nginx Deployment with two replicas.

replicas: 2

The container image is:

nginx:1.27

The Service is:

http-test

with:

ClusterIP
port 80

Check:

kubectl get pods \
  -n envoy-gateway-test \
  -o wide

Check the Service:

kubectl get svc \
  -n envoy-gateway-test

Check the EndpointSlice:

kubectl get endpointslice \
  -n envoy-gateway-test

The test endpoints were:

10.244.1.16
10.244.2.18
12. HTTPRoute Validation

Check:

kubectl get httproute http-test \
  -n envoy-gateway-test

Detailed status:

kubectl describe httproute http-test \
  -n envoy-gateway-test

Expected conditions:

Accepted=True
ResolvedRefs=True

A convenient status command is:

kubectl get httproute http-test \
  -n envoy-gateway-test \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'

Expected:

Accepted=True Accepted
ResolvedRefs=True ResolvedRefs
13. End-to-End HTTP Test

The external Gateway address is:

192.168.75.240

Run:

curl -v http://192.168.75.240/

The request successfully connected to:

192.168.75.240:80

The response was:

HTTP/1.1 200 OK

The response came from:

nginx/1.27.5

This confirms that traffic successfully travelled through the complete platform path.

14. Verified Traffic Flow

The complete validated traffic flow is:

Client
   |
   | HTTP :80
   v
192.168.75.240
   |
   | MetalLB L2
   v
LoadBalancer Service
   |
   v
Envoy Proxy
   |
   v
platform-gateway
   |
   v
HTTPRoute: http-test
   |
   v
Service: http-test
   |
   +----------------------+
   |                      |
   v                      v
10.244.1.16          10.244.2.18
   |                      |
   +----------+-----------+
              |
              v
            nginx

The final result was:

HTTP 200 OK
15. Validation Commands
Envoy Gateway
kubectl get deployment envoy-gateway \
  -n envoy-gateway-system

kubectl get pods \
  -n envoy-gateway-system \
  -o wide
GatewayClass
kubectl get gatewayclass

kubectl describe gatewayclass envoy-gateway
Gateway
kubectl get gateway \
  -n envoy-gateway-system

kubectl describe gateway platform-gateway \
  -n envoy-gateway-system
MetalLB
kubectl get pods \
  -n metallb-system \
  -o wide

kubectl get ipaddresspool \
  -n metallb-system

kubectl get l2advertisement \
  -n metallb-system
LoadBalancer
kubectl get svc \
  -n envoy-gateway-system
HTTPRoute
kubectl get httproute \
  -n envoy-gateway-test

kubectl describe httproute http-test \
  -n envoy-gateway-test
Backend
kubectl get svc \
  -n envoy-gateway-test

kubectl get endpointslice \
  -n envoy-gateway-test
External Test
curl -v http://192.168.75.240/
16. Troubleshooting
LoadBalancer IP is Pending

Check:

kubectl get svc \
  -n envoy-gateway-system

If:

EXTERNAL-IP: <pending>

check MetalLB:

kubectl get pods \
  -n metallb-system

kubectl get ipaddresspool \
  -n metallb-system

kubectl get l2advertisement \
  -n metallb-system

Also check:

kubectl describe svc \
  -n envoy-gateway-system \
  <loadbalancer-service-name>
Gateway is not Programmed

Run:

kubectl describe gateway platform-gateway \
  -n envoy-gateway-system

Check:

Accepted
Programmed

If there is no address, investigate the LoadBalancer Service and MetalLB.

HTTPRoute is not Accepted

Run:

kubectl describe httproute http-test \
  -n envoy-gateway-test

Check:

Accepted=True
ResolvedRefs=True

Also verify the Gateway listener:

kubectl describe gateway platform-gateway \
  -n envoy-gateway-system
Backend References Are Not Resolved

Check:

kubectl get svc \
  -n envoy-gateway-test

kubectl get endpointslice \
  -n envoy-gateway-test

The HTTPRoute backend Service must exist and have endpoints.

External IP Works but HTTP Fails

Check:

kubectl get gateway \
  -n envoy-gateway-system

kubectl get httproute \
  -n envoy-gateway-test

kubectl get svc \
  -n envoy-gateway-test

kubectl get endpointslice \
  -n envoy-gateway-test

kubectl get pods \
  -n envoy-gateway-system \
  -o wide

Then inspect the Envoy proxy pod:

kubectl get pods \
  -n envoy-gateway-system \
  -o wide
17. Platform Responsibilities
MetalLB

Responsible for:

LoadBalancer IP allocation
External IP assignment
Layer 2 advertisement
Making LoadBalancer Services reachable on the local network
Envoy Gateway

Responsible for:

Gateway API controller
GatewayClass reconciliation
Gateway reconciliation
HTTPRoute reconciliation
Envoy proxy configuration
Envoy data plane
Gateway API

Responsible for:

GatewayClass
Gateway
HTTPRoute
Listeners
Route attachment
Backend references
Kubernetes Service

Responsible for:

Stable application endpoint
Service discovery
Backend endpoint selection
Application

Responsible for:

Application traffic
Application-level behavior
Application health
18. Why This Architecture

The platform separates external IP management from HTTP routing.

MetalLB handles:

External IP

Gateway API handles:

Gateway
HTTPRoute
Listener
Backend reference

Envoy Gateway handles:

Envoy proxy
Data plane
Gateway API reconciliation

Kubernetes Services handle:

Application backend connectivity

This provides a clean separation of responsibilities.

19. Current Platform Status

The following has been successfully validated:

[OK] Envoy Gateway installed
[OK] Envoy Gateway 2 replicas running
[OK] Gateway API resources available
[OK] GatewayClass accepted
[OK] Platform Gateway accepted
[OK] MetalLB installed
[OK] MetalLB controller running
[OK] MetalLB speakers running
[OK] MetalLB IPAddressPool configured
[OK] MetalLB L2Advertisement configured
[OK] LoadBalancer IP assigned
[OK] Gateway programmed
[OK] HTTPRoute accepted
[OK] HTTPRoute backend references resolved
[OK] Cross-namespace routing validated
[OK] Backend endpoints available
[OK] External HTTP request successful
[OK] nginx returned HTTP 200
20. Current External Address

The current platform Gateway address is:

192.168.75.240

The address comes from the MetalLB pool:

192.168.75.240-192.168.75.250
21. Future Work

The current implementation validates HTTP traffic.

The next platform enhancements can include:

HTTPS listener
TLS certificates
cert-manager integration
Platform CA integration
DNS integration
Production HTTPRoutes
Application onboarding standards
Authentication and authorization
Rate limiting
Access logging
Prometheus metrics
Distributed tracing
Network policies
GitOps deployment of Gateway resources
Namespace-specific route policies

HTTPS should use the platform's existing certificate-management architecture rather than introducing a separate certificate-management mechanism.

22. Final Validation

The complete platform path has been successfully validated:

Client
  |
  v
MetalLB
  |
  v
192.168.75.240
  |
  v
Envoy Gateway
  |
  v
GatewayClass
  |
  v
Gateway
  |
  v
HTTPRoute
  |
  v
Kubernetes Service
  |
  v
nginx Pods

Final test:

curl http://192.168.75.240/

Result:

HTTP/1.1 200 OK

Therefore the Envoy Gateway + Gateway API + MetalLB integration is operational and provides the foundation for the platform's north-south traffic management.
