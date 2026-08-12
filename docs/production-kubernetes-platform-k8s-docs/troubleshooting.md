# Kubernetes Foundation Troubleshooting

## Node is NotReady immediately after kubeadm init

### Symptom

``` text
k8s-cp01   NotReady
```

CoreDNS may be:

``` text
Pending
```

### Cause

The Pod network CNI has not been installed yet.

### Check

``` bash
kubectl get pods -A -o wide
kubectl get pods -n kube-flannel
```

### Fix

Install the selected CNI and wait for the CNI DaemonSet to become
Running.

------------------------------------------------------------------------

## kubelet is inactive before kubeadm initialization

### Symptom

``` text
systemctl status kubelet
Active: inactive (dead)
```

### Explanation

Before kubeadm initializes or joins a node, kubelet may be waiting for
kubeadm-generated configuration.

Check:

``` bash
systemctl is-enabled kubelet
```

After `kubeadm init` or `kubeadm join`, kubelet receives its
configuration and starts normally.

------------------------------------------------------------------------

## CRI not detected

Check:

``` bash
sudo ctr plugins ls | grep 'io.containerd.cri.v1'
```

Expected:

``` text
images    ... ok
runtime   ... ok
```

Check:

``` bash
systemctl is-active containerd
```

Check:

``` bash
sudo ls -l /run/containerd/containerd.sock
```

Then:

``` bash
containerd config dump | grep -n "SystemdCgroup"
```

Expected:

``` text
SystemdCgroup = true
```

------------------------------------------------------------------------

## Kubernetes package not found

Check:

``` bash
cat /etc/apt/sources.list.d/kubernetes.list
sudo ls -lh /etc/apt/keyrings/kubernetes-apt-keyring.gpg
apt-cache policy kubeadm
```

Then:

``` bash
sudo apt-get update
```

------------------------------------------------------------------------

## Worker cannot join

Check from worker:

``` bash
ping -c 3 192.168.75.136
```

Check control-plane API port:

``` bash
nc -vz 192.168.75.136 6443
```

Check worker versions:

``` bash
kubeadm version
kubelet --version
```

For this cluster, the worker kubeadm version is:

``` text
v1.36.x
```

Generate a fresh join command on the control plane:

``` bash
kubeadm token create --print-join-command
```

------------------------------------------------------------------------

## Flannel Pod is not Running

Check:

``` bash
kubectl get pods -n kube-flannel -o wide
kubectl describe pod -n kube-flannel <pod>
kubectl logs -n kube-flannel <pod>
```

Check node networking:

``` bash
ip -br addr
ip route
```

Look for:

``` text
flannel.1
cni0
```

------------------------------------------------------------------------

## Cross-node Pod networking failure

First determine whether the problem is:

1.  Node-to-node connectivity
2.  CNI configuration
3.  Pod routing
4.  DNS
5.  Service networking

Start with:

``` bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get pods -n kube-flannel -o wide
```

Then test actual Pod-to-Pod communication using Pods placed on different
nodes.

Do not use a CNI bridge gateway ping alone as proof that Pod networking
is broken.

------------------------------------------------------------------------

## Security reminders

Never commit these to Git:

``` text
/etc/kubernetes/admin.conf
/etc/kubernetes/super-admin.conf
/etc/kubernetes/pki/*.key
bootstrap tokens
private certificates
cloud credentials
VMware credentials
```

Use placeholders in documentation.
