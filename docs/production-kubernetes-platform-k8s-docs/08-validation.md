# 08 --- Cluster and Network Validation

## Node health

``` bash
kubectl get nodes -o wide
```

Final verified state:

``` text
k8s-cp01       Ready   control-plane   v1.36.3   192.168.75.136
k8s-worker01   Ready   <none>          v1.36.3   192.168.75.137
k8s-worker02   Ready   <none>          v1.36.3   192.168.75.138
```

## System Pods

``` bash
kubectl get pods -A -o wide
```

Verified components:

-   etcd --- Running
-   kube-apiserver --- Running
-   kube-controller-manager --- Running
-   kube-scheduler --- Running
-   kube-proxy on all nodes --- Running
-   Flannel on all nodes --- Running
-   CoreDNS --- Running

## Pod scheduling test

A BusyBox Pod was scheduled onto worker02:

``` bash
kubectl run test-pod --image=busybox:1.36 --restart=Never -- sleep 3600
```

Observed:

``` text
Node: k8s-worker02
Pod IP: 10.244.2.2
```

## Cross-node Pod to CoreDNS test

From the worker02 Pod:

``` bash
kubectl exec test-pod -- ping -c 3 10.244.0.2
```

Result:

``` text
3 packets transmitted
3 packets received
0% packet loss
```

This verified cross-node Pod networking.

## DNS test

``` bash
kubectl exec test-pod -- nslookup kubernetes.default.svc.cluster.local
```

Observed:

``` text
Server: 10.96.0.10
Name: kubernetes.default.svc.cluster.local
Address: 10.96.0.1
```

This verified Kubernetes DNS.

## Actual Pod-to-Pod cross-node test

A test Pod was forced onto worker01:

``` bash
kubectl run worker01-test   --image=busybox:1.36   --restart=Never   --overrides='{"spec":{"nodeName":"k8s-worker01"}}'   -- sleep 3600
```

Observed:

``` text
worker01-test → 10.244.1.2
```

A second test Pod was forced onto worker02:

``` bash
kubectl run worker02-test   --image=busybox:1.36   --restart=Never   --overrides='{"spec":{"nodeName":"k8s-worker02"}}'   -- sleep 3600
```

Observed:

``` text
worker02-test → 10.244.2.3
```

Then:

``` bash
kubectl exec worker02-test -- ping -c 3 10.244.1.2
```

Result:

``` text
3 packets transmitted
3 packets received
0% packet loss
```

This is the strongest network validation performed in this build: a Pod
on worker02 successfully communicated with a Pod on worker01 through the
Flannel Pod network.

## Cleanup

``` bash
kubectl delete pod test-pod worker01-test worker02-test
```

## Note about CNI gateway ping

A test from worker02 to:

``` text
10.244.1.1
```

returned 100% packet loss.

This was not treated as a CNI failure because `10.244.1.1` is the
worker01 CNI bridge/gateway address rather than an application Pod
address.

The subsequent direct Pod-to-Pod test:

``` text
10.244.2.3 → 10.244.1.2
```

succeeded with 0% packet loss, proving the relevant cross-node Pod
networking path works.
