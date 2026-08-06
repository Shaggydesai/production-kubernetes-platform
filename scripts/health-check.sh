#!/usr/bin/env bash

echo "=================================="
echo " Ubuntu Server Health Check"
echo "=================================="

echo
echo "Hostname"
hostnamectl --static

echo
echo "Operating System"
grep PRETTY_NAME /etc/os-release

echo
echo "Kernel"
uname -r

echo
echo "Uptime"
uptime

echo
echo "Memory"
free -h

echo
echo "Disk Usage"
df -h /

echo
echo "IP Address"
hostname -I

echo
echo "SSH Service"
systemctl is-active ssh

echo
echo "Time Synchronization"
timedatectl | grep "System clock synchronized"

echo
echo "VMware Tools"
systemctl is-active open-vm-tools

echo
echo "=================================="
echo "Health Check Complete"
echo "=================================="