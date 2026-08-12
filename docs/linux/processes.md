\# Linux Processes



\## What is a Process?



A process is a running instance of a program.



Every running application on Linux is represented as one or more processes.



\---



\## Program vs Process



Program:

\- Stored on disk

\- Passive



Process:

\- Loaded into memory

\- Executing



\---



\## Process ID (PID)



Each process receives a unique Process ID assigned by the Linux kernel.



\---



\## Parent Process



Every process has a parent process except PID 1.



Linux organizes processes in a hierarchical tree.



\---



\## PID 1



On Ubuntu, PID 1 is systemd.



It manages system initialization and services.



\---



\## Useful Commands



```bash

echo $$

ps -ef

ps aux

ps -p 1

pstree

htop

