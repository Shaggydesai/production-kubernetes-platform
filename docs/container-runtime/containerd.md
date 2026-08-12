\# containerd



\## Overview



containerd is an OCI-compliant container runtime daemon responsible for managing container lifecycle, images, snapshots, and tasks.



It delegates low-level container creation to an OCI runtime such as `runc`.



\---



\## Responsibilities



\- Pull images

\- Store images

\- Manage snapshots

\- Create containers

\- Manage running tasks

\- Invoke OCI runtimes

\- Expose the Container Runtime Interface (CRI)



\---



\## Architecture



```

Kubernetes

&#x20;   ↓

kubelet

&#x20;   ↓

CRI Plugin

&#x20;   ↓

containerd

&#x20;   ↓

Snapshotter

&#x20;   ↓

containerd-shim

&#x20;   ↓

runc

&#x20;   ↓

Linux Kernel

```



\---



\## Key Components



\### Content Store



Stores downloaded OCI image layers.



\### Snapshotter



Creates writable container filesystems.



Common snapshotters:



\- overlayfs

\- native

\- btrfs

\- zfs



\### Runtime



Invokes OCI runtimes such as `runc`.



\### Shim



Keeps containers alive independently of the containerd daemon.



\---



\## Kubernetes Connection



Modern Kubernetes communicates with containerd using the Container Runtime Interface (CRI).



Docker is no longer required.



\---



\## Storage Location



```

/var/lib/containerd

```



\---



\## Key Takeaways



\- containerd manages container lifecycle.

\- runc creates containers.

\- Snapshotters manage writable filesystems.

\- Shims keep containers alive.

\- Kubernetes communicates with containerd through CRI.

