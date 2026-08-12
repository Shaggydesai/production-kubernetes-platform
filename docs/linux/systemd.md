\# systemd



\## What is systemd?



systemd is the system and service manager used by modern Linux distributions.



It is the first userspace process started by the Linux kernel and always runs as PID 1.



\---



\## Responsibilities



\- Boot process

\- Service management

\- Logging

\- Device management

\- Timers

\- Mounts

\- Sockets



\---



\## Common Services



\- ssh

\- systemd-timesyncd

\- cron

\- rsyslog

\- open-vm-tools

\- kubelet



\---



\## Common Commands



```bash

systemctl status

systemctl status ssh

systemctl start ssh

systemctl stop ssh

systemctl restart ssh

systemctl enable ssh

systemctl disable ssh

systemctl list-units --type=service --state=running

```



\---



\## Kubernetes Connection



The kubelet runs as a systemd service on Kubernetes nodes.



systemd automatically starts kubelet during system boot.



\---



\## Key Takeaways



\- systemd is PID 1.

\- It manages background services.

\- It starts services during boot.

\- Kubernetes depends on systemd to manage kubelet on most Linux distributions.







\---



\# Practical Observations



\## systemd Version



```bash

systemctl --version

```



Ubuntu Server 24.04 uses systemd 255 with the unified cgroup hierarchy (cgroup v2).



\---



\## Service Health



Useful commands:



```bash

systemctl status

systemctl --failed

systemctl is-active ssh

systemctl is-enabled ssh

```



These commands help verify that services are running correctly and will start automatically after a reboot.



\---



\## Important Services Observed



\- ssh

\- open-vm-tools

\- systemd-timesyncd

\- systemd-networkd

\- systemd-resolved

\- rsyslog

\- cron



\---



\## What I Learned



\- systemd is the first userspace process (PID 1).

\- It starts and manages background services.

\- It tracks service state and startup behavior.

\- It provides access to service logs through `journalctl`.

\- Kubernetes relies on systemd to manage services like kubelet and containerd on most Linux distributions.

