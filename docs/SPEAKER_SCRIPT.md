# Speaker Teleprompter & Voiceover Guide
**Use this file to read from your phone, secondary monitor, or side window while recording.**  
*(The audience will only see `SCREEN_DISPLAY.md` on your main screen).*

---

## ⏱️ Target Timing Breakdown
- **0:00 – 1:30** ➔ Part 1: Team Intro, Topology, & LAN Reachability
- **1:30 – 3:30** ➔ Part 2: DNS, Wireshark Evidence, TLS, Load Balancing, & Caching
- **3:30 – 4:30** ➔ Part 3: Failure Demonstration D3 (Stop Backend A & Failover)
- **4:30 – 4:45** ➔ Part 4: Conclusion & Layer Summary

---

# PART 1: Team Intro & Setup Flow (0:00 – 1:30)

### 🎬 Action on Screen:
*Open `SCREEN_DISPLAY.md`. Keep Section 1 (Network Topology & Table) visible.*

### 🎙️ Read Aloud (Speak clearly at a steady pace):
> "Hello everyone. We are Team **LANdo**, and this is our Phase 1 demonstration for the Computer Networks course project.
> 
> We have designed and deployed a complete private network service platform running entirely on four physical macOS laptops connected via a local Wi-Fi network, completely without cloud dependencies or virtual machines.
> 
> When a client types `https://app.lando.test`, the request undergoes private DNS resolution, Transport Layer TCP handshakes, TLS termination, and round-robin load balancing across two independent Node.js Express backend servers."

---

### 🎬 Action on Screen:
*Highlight or point your cursor at the Infrastructure Inventory Table.*

### 🎙️ Read Aloud:
> "Our architecture consists of four distinct roles:
> - **Mac 1** (`10.7.5.248`) runs `dnsmasq` as our Private DNS Server — the AWS Route 53 equivalent.
> - **Mac 2** (`10.7.21.122`) operates Nginx at the edge for TLS termination and load balancing — the Application Load Balancer equivalent.
> - **Mac 3** (`10.7.6.183`) hosts Backend A on port 3001.
> - And **Mac 4** (`10.7.7.247`) — my machine — hosts Backend B on port 3002 and serves as the primary test client."

---

### 🎬 Action on Screen:
*Scroll down to Section 2: Layer-2 Direct LAN Connectivity Evidence.*

### 🎙️ Read Aloud:
> "Our network operates on private subnet `10.7.0.0/19` with gateway `10.7.0.1`.
> 
> To prove layer-2 direct connectivity before running application services, we executed reciprocal ICMP ping tests from Mac 4 to Mac 1, Mac 2, and Mac 3.
> 
> As you can see from our live ping results on screen, every single packet returned with **TTL 64** and **0.0% packet loss**. Because macOS initializes ICMP packets with a Time-To-Live of 64 and every router hop subtracts 1, receiving 64 confirms zero router hops — all four machines talk directly across the local Wi-Fi broadcast segment."

---

# PART 2: How Configuration Works (1:30 – 3:30)

### 🎬 Action on Screen:
*Scroll to Section 3A: Private DNS Resolution & Wireshark DNS Capture.*

### 🎙️ Read Aloud:
> "Now let us trace how a live request traverses each layer of the network.
> 
> First: **Private DNS Resolution**.
> Mac 1 runs `dnsmasq`. The directive `local=/lando.test/` defines our private authoritative namespace so queries are never leaked to public root servers. Host records map `app.lando.test` and `api.lando.test` directly to Mac 2's Edge IP `10.7.21.122`. External queries like `google.com` forward upstream to `8.8.8.8`.
> 
> Below the commands, our Wireshark capture confirms this: Frame 85 shows the DNS query from client port to UDP port 53, and Frame 86 shows the response returning `10.7.21.122` with a 60-second TTL."

---

### 🎬 Action on Screen:
*Scroll down to Section 3B: TCP Three-Way Handshake.*

### 🎙️ Read Aloud:
> "Immediately following DNS resolution, the client initiates the Transport Layer connection.
> 
> In our Wireshark capture under filter `tcp.flags.syn==1`:
> Frame 87 shows the `SYN` packet from client ephemeral port `55063` to port `443` on the edge.
> Frame 88 shows the server's `[SYN, ACK]` acknowledgment, followed by the client's `ACK`. This establishes a reliable, bidirectional, ordered byte stream before any TLS data is exchanged."

---

### 🎬 Action on Screen:
*Scroll down to Section 3C: TLS Termination & HTTP/2.*

### 🎙️ Read Aloud:
> "Next: **Edge TLS Termination**.
> Mac 2 terminates TLS using an X.509 certificate issued by our custom LANdo Root Certificate Authority. Because our client machines have installed and trusted `rootCA.pem`, our curl request connects with zero certificate warnings — notice there is no `-k` flag used!
> 
> The connection negotiated **HTTP/2** via ALPN, and returned `HTTP/2 200 OK` with the custom header `x-backend: B` identifying which backend handled the request."

---

### 🎬 Action on Screen:
*Scroll down to Section 3D & 3E: Round-Robin Load Balancing and HTTP Caching.*

### 🎙️ Read Aloud:
> "In Section 3D, our four-request loop demonstrates **Round-Robin Load Balancing**:
> Responses alternate cleanly: `x-backend: A`, `B`, `A`, `B`. The client only ever interfaces with the domain name; Nginx chooses the backend.
> 
> In Section 3E, we demonstrate **HTTP Caching**:
> The endpoint `/api/cached` serves identical content from both backends with an ETag and `Cache-Control: max-age=60`. Sending a conditional request with `If-None-Match` returns **HTTP/2 304 Not Modified** with zero payload bytes, confirming bandwidth optimization behind the load balancer."

---

# PART 3: Failure Demonstration D3 (3:30 – 4:30)

### 🎬 Action on Screen:
*Scroll to Section 4: Controlled Failure Demonstration.*

### 🎙️ Read Aloud:
> "Now we demonstrate controlled failure **Scenario D3: One Backend Stopped (Option A)**.
> This scenario demonstrates how Nginx's passive health checks and automatic retries maintain continuous system availability when an application backend crashes.
> 
> In the baseline state, traffic alternates evenly between Backend A and Backend B."

---

### 🎬 Action on Screen:
*Point to Subsection 2 (Failure State).*

### 🎙️ Read Aloud:
> "During the failure step, the Mac 3 operator terminates Backend A using `Ctrl + C`, closing port 3001.
> 
> When the client issues repeated requests, observe that 100% of responses are now seamlessly served by Backend B (`x-backend: B`).
> 
> In Nginx's configuration, `max_fails=1 fail_timeout=10s` and `proxy_next_upstream error timeout http_502` instructed Nginx that when port 3001 refused the connection, it must immediately retry Backend B without returning any 502 error to the client.
> 
> The Nginx error log on Mac 2 confirms: `connect() failed: Connection refused while connecting to upstream`."

---

### 🎬 Action on Screen:
*Point to Subsection 3 (Restored State).*

### 🎙️ Read Aloud:
> "To restore the system, Backend A is restarted on Mac 3. Once the 10-second `fail_timeout` expires, Nginx automatically detects that Backend A is healthy again, and responses immediately resume alternating `A B A B`.
> 
> **Layer Affected:** This was strictly an upstream Layer 7 and Layer 4 port 3001 event. The client-facing DNS on port 53 and edge TLS on port 443 remained completely functional throughout the incident."

---

# PART 4: Conclusion & Course Topic Mapping (4:30 – 4:45)

### 🎬 Action on Screen:
*Scroll to Section 5: Course Topic & Protocol Mapping Summary.*

### 🎙️ Read Aloud:
> "To conclude, our Phase 1 deployment successfully validates core networking concepts across all five layers:
> - **Link Layer:** Direct LAN segment reachability verified by ICMP `ttl=64`.
> - **Network Layer:** IPv4 private subnet routing across `10.7.0.0/19`.
> - **Transport Layer:** TCP 3-way handshake and ephemeral-to-well-known port mapping (`55063` to `443`).
> - **Presentation Layer:** TLS 1.2 cryptographic termination and custom PKI trust.
> - **Application Layer:** Private DNS resolution via `dnsmasq`, HTTP/2 binary framing, ETag caching with 304 revalidation, and automated load balancer failover.
> 
> Thank you! This concludes Team LANdo's Phase 1 demonstration."
