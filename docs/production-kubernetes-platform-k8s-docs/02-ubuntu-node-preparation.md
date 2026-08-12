# 02 --- Ubuntu Node Preparation

## Target OS

Ubuntu 24.04.4 LTS

Verify:

``` bash
hostnamectl
```

Expected architecture:

``` text
x86-64
```

## Host identity

Each Kubernetes node must have a unique hostname and machine identity.

Check:

``` bash
hostnamectl --static
cat /etc/machine-id
```

Example node names:

``` text
k8s-cp01
k8s-worker01
k8s-worker02
```

## Network verification

``` bash
ip -br addr
ip route
```

The default route should use VMware's NAT gateway:

``` text
default via 192.168.75.2 dev ens33
```

## Required connectivity

All nodes must have full network connectivity to each other. In this
lab:

``` text
192.168.75.136 <-> 192.168.75.137
192.168.75.136 <-> 192.168.75.138
192.168.75.137 <-> 192.168.75.138
```

## Swap

Kubernetes kubeadm preflight checks swap. Verify:

``` bash
swapon --show
```

If swap is enabled and kubeadm requires it disabled:

``` bash
sudo swapoff -a
```

Persist the decision in `/etc/fstab` according to the node image policy.

## Package prerequisites

Install the packages needed for the Kubernetes repository and runtime:

``` bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

## Node readiness checklist

Before installing Kubernetes components:

``` bash
hostnamectl --static
cat /etc/machine-id
ip -br addr
ip route
swapon --show
```

The node should have:

-   Correct unique hostname
-   Unique machine ID
-   Correct reserved IP
-   Working default route
-   Node-to-node connectivity
-   Swap disabled if required
