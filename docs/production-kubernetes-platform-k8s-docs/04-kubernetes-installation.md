# 04 --- Kubernetes Component Installation

## Kubernetes version

The cluster uses:

``` text
v1.36.3
```

Installed components:

``` text
kubeadm  v1.36.3
kubelet  v1.36.3
kubectl  v1.36.3
```

## Kubernetes package repository

The Kubernetes repository was configured for the v1.36 stable series.

Keyring:

``` text
/etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

Repository:

``` text
/etc/apt/sources.list.d/kubernetes.list
```

The repository was verified with:

``` bash
apt-cache policy kubeadm
apt-cache policy kubelet
apt-cache policy kubectl
```

The installed candidate was:

``` text
1.36.3-1.1
```

## Install components

On every Kubernetes node:

``` bash
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
```

Verify:

``` bash
kubeadm version
kubelet --version
kubectl version --client
```

Expected:

``` text
kubeadm v1.36.3
Kubernetes v1.36.3
Client Version: v1.36.3
```

## Hold versions

The installed versions were held:

``` bash
sudo apt-mark hold kubelet kubeadm kubectl
```

Verify:

``` bash
apt-mark showhold
```

Expected:

``` text
kubeadm
kubectl
kubelet
```

Holding versions prevents an unattended package update from changing
Kubernetes component versions unexpectedly.

## kubelet service

Before kubeadm initialization, kubelet may be inactive because kubeadm
has not yet generated its runtime configuration. The service should be
enabled:

``` bash
systemctl is-enabled kubelet
```

After `kubeadm init` or `kubeadm join`, kubelet receives its
configuration and runs normally.

## Image list

Verify the images kubeadm expects:

``` bash
sudo kubeadm config images list
```

For this cluster:

``` text
registry.k8s.io/kube-apiserver:v1.36.3
registry.k8s.io/kube-controller-manager:v1.36.3
registry.k8s.io/kube-scheduler:v1.36.3
registry.k8s.io/kube-proxy:v1.36.3
registry.k8s.io/coredns/coredns:v1.14.2
registry.k8s.io/pause:3.10.2
registry.k8s.io/etcd:3.6.8-0
```
