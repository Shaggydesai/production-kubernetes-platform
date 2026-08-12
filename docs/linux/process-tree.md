\# Linux Process Tree



\## What is a Process Tree?



Linux organizes processes in a hierarchical tree.



Every process has a parent process except PID 1.



\---



\## Example



```

systemd (PID 1)

│

├── sshd

│   └── sshd: sagar

│       └── bash

│           └── ps

```



\---



\## Process ID (PID)



Every running process receives a unique Process ID from the Linux kernel.



\---



\## Parent Process ID (PPID)



Every process records the Process ID of the process that created it.



\---



\## Kernel Threads



Kernel threads perform internal operating system tasks.



Examples:



\- kthreadd

\- kworker

\- kswapd

\- ksoftirqd

\- jbd2



These appear inside square brackets when viewed using `ps`.



\---



\## Useful Commands



```bash

ps -ef

ps aux

echo $$

ps -p 1

pstree

```



\---



\## Key Takeaways



\- Everything running in Linux is a process.

\- Every process has a unique PID.

\- Every process (except PID 1) has a parent.

\- The Linux kernel creates kernel threads for internal work.

\- Containers are ultimately Linux processes.

