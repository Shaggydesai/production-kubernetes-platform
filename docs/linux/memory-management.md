\# Linux Memory Management



\## What is RAM?



RAM is the primary working memory used by the operating system and running applications.



Programs execute from RAM, not directly from disk.



\---



\## Virtual Memory



Linux supports virtual memory by moving inactive memory pages to swap space when needed.



\---



\## Swap



Swap is disk space used as overflow memory.



Ubuntu Server creates a swap file by default.



Kubernetes nodes usually disable swap for predictable memory management.



\---



\## OOM Killer



When physical memory is exhausted, the Linux kernel may terminate processes using the Out Of Memory Killer.



\---



\## Kubernetes Connection



Containers that exceed their configured memory limits are terminated with the reason:



OOMKilled



\---



\## Useful Commands



```bash

free -h

cat /proc/meminfo

vmstat

swapon --show

ps aux --sort=-%mem

```

