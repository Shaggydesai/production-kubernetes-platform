\# Linux OverlayFS



\## Overview



OverlayFS is a union filesystem that combines multiple directories into a single logical filesystem.



It is one of the key technologies behind Docker and Kubernetes container images.



\---



\## Key Concepts



\- Lower Layer (Read-only)

\- Upper Layer (Writable)

\- Merged Layer (Visible filesystem)

\- Copy-on-Write (CoW)



\---



\## Layer Structure



```

Application



↓



Merged Layer



↓



Upper Layer (Writable)



↓



Lower Layers (Read-only)

```



\---



\## Copy-on-Write



When a container modifies a file from a read-only image layer:



1\. The file is copied to the writable upper layer.

2\. The modification is applied to the copied file.

3\. Other containers continue using the original read-only file.



\---



\## Docker Connection



Docker stores image layers using OverlayFS.



Common location:



```

/var/lib/docker/overlay2

```



\---



\## containerd Connection



containerd stores snapshot layers under:



```

/var/lib/containerd

```



\---



\## Kubernetes Connection



Each container receives:



\- Shared read-only image layers

\- A private writable layer



This allows multiple containers to efficiently share the same image.



\---



\## Useful Commands



```bash

cat /proc/filesystems | grep overlay

lsmod | grep overlay

modinfo overlay

sudo modprobe overlay

find /sys/module/overlay

```



\---



\## Key Takeaways



\- OverlayFS is a union filesystem.

\- Docker images consist of multiple layers.

\- Containers receive a writable upper layer.

\- Copy-on-Write avoids duplicating files.

\- OverlayFS enables fast container startup and efficient disk usage.

