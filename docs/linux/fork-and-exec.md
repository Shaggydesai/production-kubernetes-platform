\# fork() and execve()



\## Overview



Linux starts new programs using two important system calls:



\- fork()

\- execve()



\---



\## fork()



`fork()` creates a child process.



The child receives:



\- New PID

\- Same program image

\- Same environment

\- Same current directory

\- Open file descriptors



\---



\## execve()



`execve()` replaces the current process image with a new executable.



The PID remains the same.



\---



\## Example



```

bash



↓



fork()



↓



Parent bash



Child bash



↓



execve()



↓



Child becomes ls



↓



ls exits



↓



Parent bash continues

```



\---



\## Kubernetes Connection



Containers ultimately begin as Linux processes.



Container runtimes use `fork()` and `execve()` to start containerized applications.



\---



\## Useful Commands



```bash

ps -ef

pstree -p

watch -n 1 "ps -ef"

sleep 30

```

