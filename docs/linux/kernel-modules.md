\# Linux Kernel Modules



\## Overview



Linux uses a modular kernel architecture. Instead of compiling every driver and feature into the kernel, functionality is provided through Loadable Kernel Modules (LKMs), which can be loaded or unloaded while the system is running.



\---



\## Why Kernel Modules?



Benefits include:



\- Smaller kernel size

\- Better memory efficiency

\- Hardware flexibility

\- No reboot required for most driver additions



\---



\## Common Commands



```bash

lsmod

modinfo <module>

modprobe <module>

modprobe -r <module>

```



\## Observations from My Ubuntu Server VM



\- The kernel supports both the `overlay` and `bridge` modules (`modinfo` confirmed this).

\- Neither module was loaded (`lsmod` returned no matching entries), because the server had not yet installed Docker or Kubernetes.

\- The minimal Ubuntu Server installation loaded only 75 kernel modules.

\- VMware-specific modules such as `vmw\_balloon` and `vmw\_vsock\_vmci\_transport` were loaded automatically because the VM runs on VMware Workstation.

\- The `nf\_tables` module was loaded by default, providing the modern Linux packet filtering framework.

