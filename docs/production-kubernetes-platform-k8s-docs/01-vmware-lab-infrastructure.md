# 01 --- VMware Lab Infrastructure

## Purpose

Provide stable networking for the three Kubernetes VMs before
bootstrapping Kubernetes.

## VMware network

The cluster uses VMware VMnet8:

``` text
VMnet8 / NAT
192.168.75.0/24
Gateway: 192.168.75.2
DHCP pool: 192.168.75.150 - 192.168.75.254
```

The lower addresses are reserved for Kubernetes nodes.

## Node MAC/IP reservations

  Node             MAC address           Reserved IP
  ---------------- --------------------- ------------------
  `k8s-cp01`       `00:0c:29:52:36:43`   `192.168.75.136`
  `k8s-worker01`   `00:0c:29:75:77:e4`   `192.168.75.137`
  `k8s-worker02`   `00:0c:29:e5:06:fa`   `192.168.75.138`

## Why DHCP reservations instead of static Linux IPs?

The VMs remain configured as DHCP clients, but VMware DHCP always
assigns the same address to each MAC address.

Advantages:

-   Stable Kubernetes node addresses
-   No manual Netplan configuration per clone
-   Easier VM cloning and rebuilds
-   Centralized IP management in VMware
-   Kubernetes sees a predictable node network

## VMware DHCP configuration

The relevant VMnet8 configuration contains:

``` text
subnet 192.168.75.0 netmask 255.255.255.0 {
range 192.168.75.150 192.168.75.254;
option routers 192.168.75.2;
}
```

And host reservations for the Kubernetes VMs.

**Important:** VMware may regenerate `vmnetdhcp.conf` when VMnet
networks are changed. Keep a backup of any custom reservation
configuration.

## Validation

On each VM:

``` bash
hostnamectl --static
ip -br addr
ip route
ip link show ens33
```

Expected node IPs:

``` text
k8s-cp01       192.168.75.136
k8s-worker01   192.168.75.137
k8s-worker02   192.168.75.138
```

Test node-to-node reachability:

``` bash
ping -c 3 192.168.75.136
ping -c 3 192.168.75.137
ping -c 3 192.168.75.138
```

All nodes should communicate without packet loss.

## Clone identity

After cloning a VM, verify and regenerate its identity as required:

``` bash
hostnamectl --static
cat /etc/machine-id
```

For a newly cloned node, set the intended hostname and ensure it has a
unique machine ID.

Example:

``` bash
sudo hostnamectl set-hostname k8s-worker01
sudo rm -f /etc/machine-id
sudo systemd-machine-id-setup
```

Do this before joining a cloned VM to Kubernetes.
