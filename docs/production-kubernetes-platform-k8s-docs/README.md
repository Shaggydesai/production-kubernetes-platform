# Kubernetes Platform Documentation

This directory documents the Kubernetes lab/platform built with
`kubeadm` on VMware-hosted Ubuntu VMs.

## Environment

  Component            Configuration
  -------------------- -----------------------------
  Hypervisor           VMware Workstation Pro
  Network              VMware VMnet8 / NAT
  Host network         `192.168.75.0/24`
  Kubernetes version   `v1.36.3`
  OS                   Ubuntu 24.04.4 LTS
  Container runtime    containerd `2.2.1`
  CNI                  Flannel
  Pod CIDR             `10.244.0.0/16`
  Service CIDR         `10.96.0.0/12`
  Nodes                1 control-plane + 2 workers

## Node inventory

  Node             Role            Node IP            Pod CIDR
  ---------------- --------------- ------------------ -----------------
  `k8s-cp01`       control-plane   `192.168.75.136`   `10.244.0.0/24`
  `k8s-worker01`   worker          `192.168.75.137`   `10.244.1.0/24`
  `k8s-worker02`   worker          `192.168.75.138`   `10.244.2.0/24`

## Documentation order

1.  VMware lab networking and DHCP reservations
2.  Ubuntu node preparation
3.  containerd installation and CRI validation
4.  Kubernetes package installation
5.  Control-plane bootstrap with kubeadm
6.  Flannel CNI
7.  Worker node joining
8.  Cluster and network validation

## Design decisions

-   VMware DHCP reservations are used instead of static Netplan
    addresses. This keeps the VMs as DHCP clients while ensuring stable
    addresses.
-   containerd is used as the CRI-compatible runtime.
-   `systemd` is used as the cgroup driver.
-   Flannel is used for the Pod network.
-   The Pod CIDR `10.244.0.0/16` does not overlap the VMware host
    network `192.168.75.0/24`.
-   Kubernetes components are pinned/held at the installed patch version
    to avoid unintended package upgrades.

## Official references

-   Kubernetes kubeadm cluster creation:
    https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
-   Kubernetes kubeadm installation:
    https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
-   Kubernetes container runtimes:
    https://kubernetes.io/docs/setup/production-environment/container-runtimes/
-   kubeadm reference:
    https://kubernetes.io/docs/reference/setup-tools/kubeadm/
