\# tcpdump



\## Purpose



`tcpdump` is a packet-capture and packet-analysis tool.



It allows us to observe traffic directly from Linux network interfaces.



It is especially useful for troubleshooting:



\- TCP connectivity

\- UDP traffic

\- DNS

\- ICMP

\- routing

\- NAT

\- Kubernetes networking

\- CNI networking



\---



\## Basic Capture



```bash

sudo tcpdump -i <interface>

```



Example:



```bash

sudo tcpdump -i ens33

```



Stop capture with:



```text

Ctrl+C

```



\---



\## Find Interfaces



```bash

ip link

ip addr

ip -br addr

```



Do not assume the interface is called `eth0`.



VMs may use names such as:



```text

ens33

ens160

```



\---



\## Avoid Name Resolution



Use:



```bash

sudo tcpdump -i <interface> -nn

```



`-n` prevents hostname resolution.



`-nn` also prevents port/service-name resolution.



This makes packet output easier to analyze.



\---



\## Filter by Host



```bash

sudo tcpdump -i <interface> host 192.168.75.100

```



\---



\## Filter by Source



```bash

sudo tcpdump -i <interface> src host 192.168.75.100

```



\---



\## Filter by Destination



```bash

sudo tcpdump -i <interface> dst host 192.168.75.100

```



\---



\## Filter by Port



```bash

sudo tcpdump -i <interface> port 22

```



HTTP:



```bash

sudo tcpdump -i <interface> port 80

```



HTTPS:



```bash

sudo tcpdump -i <interface> port 443

```



DNS:



```bash

sudo tcpdump -i <interface> port 53

```



\---



\## Protocol Filters



TCP:



```bash

sudo tcpdump -i <interface> tcp

```



UDP:



```bash

sudo tcpdump -i <interface> udp

```



ICMP:



```bash

sudo tcpdump -i <interface> icmp

```



\---



\## Packet Count



Capture a fixed number of packets:



```bash

sudo tcpdump -i <interface> -nn -c 20

```



\---



\## Capture on All Interfaces



```bash

sudo tcpdump -i any -nn

```



This is useful for initial investigation.



For detailed packet-path analysis, capture on specific interfaces.



\---



\## Save a Capture



```bash

sudo tcpdump -i <interface> -nn -w capture.pcap

```



Read it later:



```bash

tcpdump -nn -r capture.pcap

```



PCAP files can also be analyzed with Wireshark.



\---



\## TCP Handshake



A normal TCP connection begins with:



```text

Client                    Server



&#x20;  SYN  ───────────────────►



&#x20;       ◄────────────────── SYN/ACK



&#x20;  ACK  ───────────────────►

```



Common tcpdump flags:



```text

\[S]     SYN

\[S.]    SYN + ACK

\[.]     ACK

\[R]     RST

```



\---



\## Troubleshooting TCP



\### SYN with no response



```text

SYN

&#x20;↓

nothing

```



Possible causes include:



\- packet filtering

\- routing problem

\- firewall

\- unreachable destination

\- service/network failure



\### SYN followed by RST



```text

SYN

&#x20;↓

RST

```



The destination is reachable but the connection is being actively rejected.



\### Complete handshake



```text

SYN

&#x20;↓

SYN/ACK

&#x20;↓

ACK

```



TCP connectivity is established.



If the application still fails, investigate higher-level protocols or the application itself.



\---



\## Kubernetes Packet Path



A simplified Pod-to-Pod path:



```text

Pod eth0

&#x20;  ↓

veth

&#x20;  ↓

Node

&#x20;  ↓

CNI

&#x20;  ↓

Node network

&#x20;  ↓

Destination node

&#x20;  ↓

veth

&#x20;  ↓

Destination Pod

```



Capture traffic at different points to determine where a packet disappears.



\---



\## Kubernetes Service



Example:



```text

Client Pod:

10.244.1.10



Service:

10.96.20.50:80



Backend:

10.244.2.10:8080

```



Before Service translation:



```text

10.244.1.10 → 10.96.20.50:80

```



After destination translation:



```text

10.244.1.10 → 10.244.2.10:8080

```



A capture location before and after NAT may therefore show different destinations.



\---



\## Packet Trail



When debugging:



```text

Source Pod

&#x20;  ↓

Source veth

&#x20;  ↓

Node interface

&#x20;  ↓

Network

&#x20;  ↓

Destination node

&#x20;  ↓

Destination veth

&#x20;  ↓

Destination Pod

```



Ask:



> Where was the last place the packet was observed?



That identifies the likely failure domain.



\---



\## Security Warning



Packet captures can contain sensitive information including:



\- credentials

\- cookies

\- tokens

\- application data

\- personal information



Do not capture or inspect production traffic unnecessarily.



Use narrow capture filters whenever possible.



\---



\## Engineering Principle



Do not say:



```text

"Kubernetes networking is broken."

```



Instead collect evidence:



```text

Source packet observed

Destination packet not observed

Route is correct

NetworkPolicy denies traffic

```



Then identify the exact failing layer.

