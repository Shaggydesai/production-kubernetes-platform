# 06 --- Flannel CNI

## Purpose

kubeadm creates the control plane but does not install a Pod network. A
CNI is required for Pod-to-Pod networking.

Flannel was selected for this lab.

## Pod network

The cluster was initialized with:

``` text
10.244.0.0/16
```

Flannel allocated:

``` text
k8s-cp01       10.244.0.0/24
k8s-worker01   10.244.1.0/24
k8s-worker02   10.244.2.0/24
```

## Install Flannel

Apply the Flannel manifest appropriate for the selected
release/environment.

After installation:

``` bash
kubectl get pods -n kube-flannel -o wide
```

Expected:

``` text
kube-flannel-ds-...   1/1   Running   ...   k8s-cp01
kube-flannel-ds-...   1/1   Running   ...   k8s-worker01
kube-flannel-ds-...   1/1   Running   ...   k8s-worker02
```

## Verify Pod CIDRs

``` bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,POD-CIDR:.spec.podCIDR
```

Expected:

``` text
NAME           POD-CIDR
k8s-cp01       10.244.0.0/24
k8s-worker01   10.244.1.0/24
k8s-worker02   10.244.2.0/24
```

## Why CoreDNS was initially Pending

Immediately after kubeadm initialization, CoreDNS was Pending because
the Pod network had not yet been installed.

After Flannel was deployed:

``` text
CoreDNS → Running
Node → Ready
```

This is normal kubeadm bootstrap behavior.

## CNI verification

On a node:

``` bash
ip -br addr
```

Expected interfaces include:

``` text
flannel.1
cni0
```

For example on the control plane:

``` text
ens33       192.168.75.136/24
flannel.1   10.244.0.0/32
cni0        10.244.0.1/24
```

## Important rule

Only one Pod network should be installed in this cluster. Do not install
another CNI over Flannel unless deliberately rebuilding/reconfiguring
the cluster.
