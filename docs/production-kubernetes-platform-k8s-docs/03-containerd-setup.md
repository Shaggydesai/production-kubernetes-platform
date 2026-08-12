# 03 --- containerd Setup

## Why containerd?

Kubernetes 1.36 requires a container runtime that conforms to the
Container Runtime Interface (CRI). containerd provides the runtime used
by this cluster.

Installed runtime:

``` text
containerd 2.2.1
```

## Generate the default configuration

``` bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
```

## Configure systemd cgroups

The runtime configuration was changed from:

``` toml
SystemdCgroup = false
```

to:

``` toml
SystemdCgroup = true
```

Command used:

``` bash
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
```

Verify:

``` bash
sudo grep -n "SystemdCgroup" /etc/containerd/config.toml
```

Expected:

``` text
SystemdCgroup = true
```

## CRI verification

Restart containerd:

``` bash
sudo systemctl restart containerd
```

Verify:

``` bash
systemctl status containerd --no-pager
```

Expected:

``` text
Active: active (running)
```

Verify CRI plugins:

``` bash
sudo ctr plugins ls | grep 'io.containerd.cri.v1'
```

Expected:

``` text
io.containerd.cri.v1    images     ... ok
io.containerd.cri.v1    runtime    linux/amd64    ok
```

Verify the socket:

``` bash
sudo ls -l /run/containerd/containerd.sock
```

## Runtime configuration validation

``` bash
containerd config dump | grep -n "SystemdCgroup"
```

Expected:

``` text
SystemdCgroup = true
```

## Kubernetes compatibility

kubeadm detected:

``` text
unix:///var/run/containerd/containerd.sock
```

The systemd cgroup configuration matches the kubelet's systemd cgroup
configuration.

Kubernetes documentation recommends using the `systemd` cgroup driver
with systemd-based Linux systems and configuring the container runtime
and kubelet consistently.

## Troubleshooting commands

``` bash
sudo journalctl -u containerd -n 100 --no-pager
sudo ctr plugins ls
sudo ls -l /run/containerd/containerd.sock
containerd config dump | grep -n "SystemdCgroup"
```
