\# DevOps Engineering Journal



This journal documents my journey of building a Production Kubernetes Platform from scratch. The goal is not only to build the platform but to understand the engineering decisions behind every component.



\---



\# Session 01 – Ubuntu Golden Template



\*\*Date:\*\* 06-Aug-2026



\## Objective



Build a reusable Ubuntu Server template that will become the foundation of the Kubernetes platform.



\---



\## Completed Tasks



\- Installed Ubuntu Server 24.04.4 LTS

\- Configured UEFI boot

\- Configured LVM storage

\- Installed OpenSSH Server

\- Updated operating system

\- Installed essential Linux administration tools

\- Verified SSH connectivity from Windows

\- Verified NTP synchronization

\- Created project documentation structure

\- Created first Git commit



\---



\## Commands Learned



\- `hostnamectl`

\- `timedatectl`

\- `lsblk`

\- `df -h`

\- `ip addr`

\- `systemctl`

\- `apt update`

\- `apt upgrade`

\- `ssh`

\- `ss`



\---



\## Concepts Learned



\- Difference between BIOS and UEFI

\- DHCP vs Static IP

\- LVM basics

\- Ubuntu package management

\- SSH architecture

\- NTP and time synchronization

\- UTC vs local time

\- Golden image philosophy

\- Why production servers should be standardized



\---



\## Problems Encountered



\### Problem



`chmod` was not recognized on Windows PowerShell.



\### Cause



`chmod` is a Linux command and cannot be executed directly in Windows PowerShell.



\### Resolution



Linux shell commands should be executed inside Ubuntu. Windows PowerShell should be used for Windows-specific tasks such as Git and VMware management.



\---



\## Key Takeaways



I learned that DevOps is not about installing software quickly. It is about understanding why each decision is made and creating systems that are repeatable, maintainable, and well documented.



\---



\## Next Goals



\- Prepare Ubuntu for Kubernetes

\- Configure kernel modules

\- Configure sysctl

\- Understand cgroups and namespaces

\- Install containerd

