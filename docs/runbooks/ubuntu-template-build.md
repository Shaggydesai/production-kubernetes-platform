\# Ubuntu Template Build Runbook



\## Purpose



This runbook documents the process of building the reusable Ubuntu Server template for the Production Kubernetes Platform.



\---



\## Base Operating System



\- Ubuntu Server 24.04.4 LTS

\- UEFI Firmware

\- VMware Workstation Pro

\- NVMe Virtual Disk

\- LVM Storage

\- OpenSSH Installed



\---



\## Completed Tasks



\- Ubuntu installed

\- System updated

\- Essential administration tools installed

\- SSH verified

\- Time synchronization verified



\---



\## Verification Commands



```bash

hostnamectl

timedatectl

systemctl status ssh

systemctl status systemd-timesyncd

ip addr

lsblk

df -h

```



\---



\## Status



Golden Template Preparation - In Progress

