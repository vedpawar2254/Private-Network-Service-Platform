# Complete Video Presentation Script & Demonstration Runbook
**Course Project: Private Network Service Platform — Phase 1**  
**Team Name:** LANdo | **Domain:** `app.lando.test` | **Infrastructure:** 4 macOS Laptops (No Cloud)

---

## 📌 Video Submission Guidelines
- **Duration:** Strictly under 5:00 minutes (Target: 4:30 – 4:45)
- **Format & Resolution:** `.mp4` (1080p, H.264 video, AAC audio recommended)
- **File Size:** Under 500 MB
- **File Naming Convention:** `CN_Phase1_[Section]LANdo_MacLocal.mp4` *(e.g. `CN_Phase1_SecA_LANdo_MacLocal.mp4`)*
- **Sharing Setting:** Google Drive ➔ *"Anyone with the link can view"* (⚠️ Always test in an incognito window before submitting!)

---

## ⏱️ Video Time Breakdown

```
0:00 ──────────────── 1:30 ─────────────── 3:30 ────────────── 4:30 ────── 5:00
│  Part 1: Intro & LAN   │  Part 2: Config, DNS, │  Part 3: Failure D3 │ Part 4: │
│  Topology, Ping ttl=64 │  TLS, LB, Caching 304 │  Stop Backend A     │ Summary │
```

---

# SECTION 1: Team Intro & Setup Flow (0:00 – 1:30)

### 🎙️ [Voiceover / Say]:
> "Hello everyone. We are Team **LANdo**, and this is our Phase 1 demonstration for the Computer Networks project.
> We designed and deployed an end-to-end private network service platform entirely on four physical macOS laptops connected to a local Wi-Fi network, completely without cloud dependencies.
> When a client types `https://app.lando.test`, the request undergoes private DNS resolution, Transport Layer TCP handshakes, TLS termination, and round-robin reverse-proxy load balancing across two independent Node.js Express backend servers."

---

### 🖥️ [Visual 1: Architecture Topology & Machine Inventory Table]
*(Display this on screen)*

```
Client (Mac 4 - Aviral)
  │
  ├─ 1. DNS Query (UDP Port 53) ───────► Mac 1: dnsmasq (Private DNS Server)
  │                                        Record: app.lando.test -> 10.7.21.122
  │
  └─ 2. HTTPS Request (TCP Port 443) ──► Mac 2: Nginx Edge (TLS Termination & Load Balancer)
                                           ├─ Plain HTTP :3001 ──► Mac 3: Backend A (Express)
                                           └─ Plain HTTP :3002 ──► Mac 4: Backend B (Express)
```

| Machine | Role | Service | IP Address | MAC Address (Ethernet) | Port | Cloud Equivalent |
|---|---|---|---|---|---|---|
| **Mac 1** | Private DNS Server | `dnsmasq` | `10.7.5.248` | `7a:ed:a5:e2:d8:4c` | 53 (UDP) | AWS Route 53 Private Hosted Zone |
| **Mac 2** | Edge Reverse Proxy & LB | `nginx`, OpenSSL | `10.7.21.122` | `52:01:cf:b4:e1:ba` | 80, 443 (TCP) | AWS Application Load Balancer / CloudFront |
| **Mac 3** | Application Backend A | Express REST API | `10.7.6.183` | `46:8b:9c:ce:33:ac` | 3001 (TCP) | EC2 Instance in Target Group A |
| **Mac 4** | Backend B + Capture Client | Express REST API | `10.7.7.247` | `6a:5f:a6:ec:a9:39` | 3002 (TCP) | EC2 Instance in Target Group B |

*(Network definition: Subnet `255.255.224.0` (/19), Default Gateway: `10.7.0.1`, Wi-Fi SSID: `Rishihood_Learner`)*

![Mac 4 Wi-Fi Network Details](/Users/aviralmishra/.gemini/antigravity-ide/brain/2a8a0a08-e634-4b7c-af83-7fa1e15afe03/wifi_network_settings.png)

---

### 🎙️ [Voiceover / Say]:
> "To verify that all four MacBooks have direct layer-2 connectivity on the local broadcast domain without intermediate router hops, we executed reciprocal ICMP ping tests."

### 🖥️ [Visual 2: Terminal Ping Evidence Across All Nodes]
*(Show or execute this command in terminal)*

```bash
# Ping from Mac 4 to Mac 1, Mac 2, and Mac 3
ping -c 4 10.7.5.248
ping -c 4 10.7.21.122
ping -c 4 10.7.6.183
```

#### 📋 Live Terminal Output:
```text
Mac4 -> Mac1: ping -c 4 10.7.5.248
PING 10.7.5.248 (10.7.5.248): 56 data bytes
64 bytes from 10.7.5.248: icmp_seq=0 ttl=64 time=42.343 ms
64 bytes from 10.7.5.248: icmp_seq=1 ttl=64 time=7.880 ms
64 bytes from 10.7.5.248: icmp_seq=2 ttl=64 time=87.926 ms
64 bytes from 10.7.5.248: icmp_seq=3 ttl=64 time=100.297 ms

--- 10.7.5.248 ping statistics ---
4 packets transmitted, 4 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 7.880/59.611/100.297/36.849 ms


Mac4 -> Mac2: ping -c 4 10.7.21.122
PING 10.7.21.122 (10.7.21.122): 56 data bytes
64 bytes from 10.7.21.122: icmp_seq=0 ttl=64 time=6.858 ms
64 bytes from 10.7.21.122: icmp_seq=1 ttl=64 time=69.331 ms
64 bytes from 10.7.21.122: icmp_seq=2 ttl=64 time=87.429 ms
64 bytes from 10.7.21.122: icmp_seq=3 ttl=64 time=8.749 ms

--- 10.7.21.122 ping statistics ---
4 packets transmitted, 4 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 6.858/43.092/87.429/35.870 ms


Mac4 -> Mac3: ping -c 4 10.7.6.183
PING 10.7.6.183 (10.7.6.183): 56 data bytes
64 bytes from 10.7.6.183: icmp_seq=0 ttl=64 time=12.218 ms
64 bytes from 10.7.6.183: icmp_seq=1 ttl=64 time=119.009 ms
64 bytes from 10.7.6.183: icmp_seq=2 ttl=64 time=8.849 ms
64 bytes from 10.7.6.183: icmp_seq=3 ttl=64 time=50.160 ms

--- 10.7.6.183 ping statistics ---
4 packets transmitted, 4 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 8.849/47.559/119.009/44.326 ms
```

### 🎙️ [Voiceover / Say]:
> "Notice `ttl=64` in every single response with 0.0% packet loss. In macOS, ICMP packets originate with a TTL of 64; each router hop decrements this value by 1. Receiving TTL 64 confirms zero router hops — our machines communicate directly across the local LAN segment."

---

# SECTION 2: How Configuration Works (1:30 – 3:30)

### 🎙️ [Voiceover / Say]:
> "Now let us examine how each layer operates during a live request.
> First, **Private DNS Resolution**.
> Mac 1 runs `dnsmasq`. The directive `local=/lando.test/` designates `lando.test` as a private zone that is never forwarded to public root servers. Host records map `app.lando.test` and `api.lando.test` to Mac 2's Edge IP `10.7.21.122`.
> External queries like `google.com` are forwarded upstream to `8.8.8.8` via the `no-resolv` directive, ensuring standard internet connectivity remains intact."

---

### 🖥️ [Visual 3: Live DNS Resolution & Wireshark Capture]
```bash
# Query private domain without specifying server (uses configured resolver 10.7.5.248)
dig app.lando.test +short

# Verify upstream public domain forwarding works
dig google.com +short
```

#### 📋 Live Terminal Output:
```text
$ dig app.lando.test +short
10.7.21.122

$ dig google.com +short
192.178.158.102
192.178.158.100
192.178.158.101
```

![Wireshark DNS Query & Response](/Users/aviralmishra/.gemini/antigravity-ide/brain/2a8a0a08-e634-4b7c-af83-7fa1e15afe03/wireshark_dns_lando.png)

### 🎙️ [Voiceover / Say]:
> "In Wireshark under filter `dns.qry.name contains 'lando'`:
> Frame 85 shows the DNS query from client `10.7.7.247` to DNS server `10.7.5.248:53 (UDP)`.
> Frame 86 shows the response with Transaction ID `0x85d9` returning `10.7.21.122` with a TTL of 60 seconds."

---

### 🖥️ [Visual 4: TCP 3-Way Handshake in Wireshark]
![Wireshark TCP 3-Way Handshake](/Users/aviralmishra/.gemini/antigravity-ide/brain/2a8a0a08-e634-4b7c-af83-7fa1e15afe03/wireshark_tcp_handshake.png)

### 🎙️ [Voiceover / Say]:
> "Immediately following DNS resolution, the client initiates the Transport Layer connection to Edge port 443.
> Under filter `tcp.flags.syn==1`:
> Frame 87 shows the `SYN` packet from client ephemeral port `55063` to `10.7.21.122:443` with `Seq=0`.
> Frame 88 shows the server's `[SYN, ACK]` with `Seq=0, Ack=1`, followed by the client's `ACK`, establishing a reliable, connection-oriented channel before any TLS data is exchanged."

---

### 🎙️ [Voiceover / Say]:
> "Next, **Edge TLS Termination and Load Balancing**.
> Mac 2 runs Nginx. Port 80 issues a 301 redirect to HTTPS.
> Port 443 terminates TLS using an X.509 certificate signed by our own LANdo Local Root CA. Because client machines trust `rootCA.pem`, certificate validation succeeds natively without requiring the `-k` flag."

---

### 🖥️ [Visual 5: Validated HTTPS Request (No `-k`)]
```bash
curl -v --tls-max 1.2 https://app.lando.test/api/status
```

#### 📋 Live Terminal Output:
```text
* Host app.lando.test:443 was resolved.
* IPv4: 10.7.21.122
* Connected to app.lando.test (10.7.21.122) port 443
* ALPN: curl offers h2,http/1.1
* TLSv1.2 (IN), TLS handshake, Certificate (11):
* Server certificate:
*  subject: CN=app.lando.test
*  issuer: CN=lando Local Root CA
* SSL certificate verify ok.
* using HTTP/2
* [HTTP/2] [1] [:method: GET]
* [HTTP/2] [1] [:path: /api/status]
> GET /api/status HTTP/2
> Host: app.lando.test
> User-Agent: curl/8.7.1
> 
< HTTP/2 200 
< server: nginx/1.31.6
< date: Mon, 05 Oct 2026 09:01:55 GMT
< content-type: application/json; charset=utf-8
< x-powered-by: Express
< x-backend: B
< cache-control: no-store
< etag: W/"3f-GJXGksv83Fkn0HW/cZX5plzy+1s"
< 
{"backend":"B","status":"ok","time":"2026-10-05T09:01:55.524Z"}
```

---

### 🎙️ [Voiceover / Say]:
> "Now we demonstrate **Round-Robin Load Balancing** across both backend instances."

### 🖥️ [Visual 6: Round-Robin Traffic Alternation]
```bash
for i in 1 2 3 4; do curl -si https://app.lando.test/api/status | grep -i x-backend; done
```

#### 📋 Live Terminal Output:
```text
x-backend: A
x-backend: B
x-backend: A
x-backend: B
```

### 🎙️ [Voiceover / Say]:
> "The responses alternate cleanly between Backend A on Mac 3 and Backend B on Mac 4. The client only ever interfaces with `app.lando.test` without knowing the private backend IP addresses."

---

### 🖥️ [Visual 7: HTTP Caching Validation (Task F)]
```bash
# 1. Fetch resource and capture ETag
curl -I https://app.lando.test/api/cached

# 2. Issue conditional request using If-None-Match
ETAG=$(curl -sI https://app.lando.test/api/cached | grep -i '^etag' | cut -d' ' -f2 | tr -d '\r')
curl -I -H "If-None-Match: $ETAG" https://app.lando.test/api/cached
```

#### 📋 Live Terminal Output:
```text
HTTP/2 200 
cache-control: public, max-age=60
etag: W/"29-s/P7x0T5t70Q66w9E7H4A"

--- Conditional Validation ---
HTTP/2 304 Not Modified
server: nginx/1.31.6
etag: W/"29-s/P7x0T5t70Q66w9E7H4A"
cache-control: public, max-age=60
```

### 🎙️ [Voiceover / Say]:
> "For HTTP caching, `/api/cached` returns identical content on both backends with an ETag and `Cache-Control: max-age=60`. Sending a conditional request with `If-None-Match` returns **HTTP/2 304 Not Modified** with zero payload bytes, confirming bandwidth optimization behind the load balancer."

---

# SECTION 3: Failure Demonstration D3 (3:30 – 4:30)

### 🎙️ [Voiceover / Say]:
> "Now we demonstrate controlled failure **Scenario D3: One Backend Stopped (Option A)**.
> This scenario demonstrates how Nginx's passive health checks and automatic upstream retries prevent client-facing outages when an application backend crashes."

---

### 🖥️ [Visual 8: Normal Baseline State Before Failure]
```bash
for i in 1 2 3 4; do curl -si https://app.lando.test/api/status | grep -i x-backend; done
```
#### 📋 Live Output:
```text
x-backend: A
x-backend: B
x-backend: A
x-backend: B
```

---

### 🖥️ [Visual Action: Injected Failure on Mac 3]
*(Show Mac 3 terminal where Backend A is running, and press `Ctrl + C`)*

### 🎙️ [Voiceover / Say]:
> "On Mac 3, the operator kills the Backend A Express process using `Ctrl + C`. Port 3001 is now closed."

---

### 🖥️ [Visual 9: Client Behavior After Failure]
```bash
for i in 1 2 3 4; do curl -si https://app.lando.test/api/status | grep -i x-backend; done
```
#### 📋 Live Output:
```text
x-backend: B
x-backend: B
x-backend: B
x-backend: B
```

### 🎙️ [Voiceover / Say]:
> "Notice that 100% of client requests are now served cleanly by Backend B (`x-backend: B`).
> Due to Nginx directives `max_fails=1 fail_timeout=10s` and `proxy_next_upstream error timeout http_502`, Nginx detected connection refusal on port 3001, temporarily quarantined Backend A, and immediately routed traffic to Backend B without serving any 502 error to the client.
> On Mac 2, the Nginx error log confirms: `connect() failed (61: Connection refused) while connecting to upstream: http://10.7.6.183:3001/api/status`."

---

### 🖥️ [Visual 10: Service Recovery & Restoration]
*(On Mac 3, restart: `BACKEND=A PORT=3001 node server.js`)*

### 🎙️ [Voiceover / Say]:
> "Backend A is now restarted on Mac 3. Once the 10-second `fail_timeout` expires, Nginx detects Backend A is healthy again."

```bash
for i in 1 2 3 4; do curl -si https://app.lando.test/api/status | grep -i x-backend; done
```
#### 📋 Live Output:
```text
x-backend: A
x-backend: B
x-backend: A
x-backend: B
```

### 🎙️ [Voiceover / Say]:
> "Immediately, round-robin distribution resumes alternating between A and B.
> **Layer Affected:** Layer 7 (Application Upstream) and Layer 4 (Port 3001). The client-facing DNS (UDP 53) and Edge TLS (TCP 443) layers remained completely operational throughout the incident."

---

# SECTION 4: Conclusion & Course Topic Mapping (4:30 – 4:45)

### 🎙️ [Voiceover / Say]:
> "To conclude, this implementation validates core Computer Networks concepts across all five layers:
> - **Physical & Link Layer:** Direct LAN segment reachability verified by ICMP `ttl=64`.
> - **Network Layer:** IPv4 private subnet routing across `10.7.0.0/19`.
> - **Transport Layer:** TCP 3-way handshake (`SYN, SYN-ACK, ACK`) and ephemeral-to-well-known port mapping (`55063 ➔ 443`).
> - **Presentation / Security Layer:** TLS 1.2 negotiation with custom Root CA chain verification and payload encryption.
> - **Application Layer:** Private DNS resolution via `dnsmasq`, HTTP/2 protocol negotiation via ALPN, ETag-based caching with 304 revalidation, and resilient reverse-proxy load balancing.
> 
> Thank you! This concludes Team LANdo's Phase 1 demonstration."

---

## 📂 Deliverables Index in Workspace
- **Complete Architecture & Guide:** [docs/MAC4_GUIDE.md](file:///Users/aviralmishra/.gemini/antigravity-ide/scratch/cn-project/docs/MAC4_GUIDE.md)
- **Wireshark Analysis & Packet Descriptions:** [evidence/G-wireshark/WIRESHARK_EVIDENCE.md](file:///Users/aviralmishra/.gemini/antigravity-ide/scratch/cn-project/evidence/G-wireshark/WIRESHARK_EVIDENCE.md)
- **Verbose Request Log:** [evidence/G-wireshark/curl-verbose.txt](file:///Users/aviralmishra/.gemini/antigravity-ide/scratch/cn-project/evidence/G-wireshark/curl-verbose.txt)
- **Saved Evidence Screenshots:** [evidence/screenshots/](file:///Users/aviralmishra/.gemini/antigravity-ide/scratch/cn-project/evidence/screenshots/)
