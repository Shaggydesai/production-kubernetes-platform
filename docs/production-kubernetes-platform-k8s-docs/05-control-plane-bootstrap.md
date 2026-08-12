# 05 --- Control Plane Bootstrap

## Control-plane node

``` text
Hostname: k8s-cp01
IP:       192.168.75.136
```

## Preflight validation

Before initialization:

``` bash
sudo kubeadm init phase preflight
```

The preflight checks verified:

-   Kubernetes version
-   Firewall state
-   Required ports
-   Required files/directories
-   Container runtime
-   Runtime compatibility
-   Swap
-   System requirements
-   IP forwarding
-   etcd directory state

The CRI was detected as:

``` text
unix:///var/run/containerd/containerd.sock
```

## kubeadm init

The cluster was initialized with:

``` bash
sudo kubeadm init   --apiserver-advertise-address=192.168.75.136   --pod-network-cidr=10.244.0.0/16   --cri-socket=unix:///run/containerd/containerd.sock
```

### Why these parameters?

`--apiserver-advertise-address`

``` text
192.168.75.136
```

This is the control-plane node's stable VMware-reserved address.

`--pod-network-cidr`

``` text
10.244.0.0/16
```

This is the address space used by the Flannel Pod network.

`--cri-socket`

``` text
unix:///run/containerd/containerd.sock
```

This explicitly selects containerd.

## Configure kubectl

For the normal user:

``` bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Validate:

``` bash
kubectl get nodes
```

Initially the control-plane node was `NotReady` because no CNI had been
installed yet. This is expected.

## Control-plane manifests

After initialization:

``` bash
sudo ls -la /etc/kubernetes/manifests/
```

Expected static Pods:

``` text
etcd.yaml
kube-apiserver.yaml
kube-controller-manager.yaml
kube-scheduler.yaml
```

## Control-plane verification

``` bash
kubectl get pods -n kube-system -o wide
```

The control-plane Pods should be Running.

## Security note

`/etc/kubernetes/admin.conf` contains cluster-admin credentials. Do not
commit it to Git or share it.

Likewise, never commit:

-   bootstrap tokens
-   discovery hashes when treated as sensitive in your environment
-   private keys
-   cluster CA keys
-   kubeconfig files containing admin credentials
