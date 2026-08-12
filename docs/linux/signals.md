\# Linux Signals



\## What is a Signal?



A signal is a notification sent by the Linux kernel to a process to inform it that an event has occurred.



Signals allow the operating system to control process behavior.



\---



\## Common Signals



| Signal | Number | Purpose |

|---------|--------|---------|

| SIGINT | 2 | Interrupt (Ctrl+C) |

| SIGTERM | 15 | Graceful shutdown |

| SIGKILL | 9 | Immediate termination |

| SIGSTOP | 19 | Pause process |

| SIGCONT | 18 | Resume process |

| SIGHUP | 1 | Hangup / Reload |



\---



\## SIGTERM



SIGTERM requests that a process terminate gracefully.



Applications can catch this signal and perform cleanup before exiting.



\---



\## SIGKILL



SIGKILL immediately terminates a process.



It cannot be caught, blocked, or ignored.



\---



\## Kubernetes Connection



When a Pod is deleted, Kubernetes first sends SIGTERM to allow the application to shut down gracefully.



If the application does not exit within the configured grace period, Kubernetes sends SIGKILL.



\---



\## Useful Commands



```bash

kill PID

kill -9 PID

kill -STOP PID

kill -CONT PID

kill -l

```

