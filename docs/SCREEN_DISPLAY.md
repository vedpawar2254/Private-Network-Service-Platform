# Private Network Service Platform — Phase 1 Demonstration
**Course Project: Computer Networks**  
**Team Name:** LANdo | **Target Domain:** `app.lando.test` | **Environment:** 4 macOS Laptops (Local LAN, No Cloud)

---

## 1. Network Topology & System Architecture

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

### Infrastructure Inventory & Cloud Equivalents

| Host | Functional Role | Service Daemon | IP Address | MAC Address | Service Port | Cloud Equivalent |
|---|---|---|---|---|---|---|
| **Mac 1** | Private DNS Server | `dnsmasq` | `10.7.5.248` | `7a:ed:a5:e2:d8:4c` | `53/UDP` | AWS Route 53 Private Zone |
| **Mac 2** | Edge Reverse Proxy & LB | `nginx`, OpenSSL | `10.7.21.122` | `52:01:cf:b4:e1:ba` | `80/TCP`, `443/TCP` | AWS ALB / CDN Edge |
| **Mac 3** | Application Backend A | Express REST API | `10.7.6.183` | `46:8b:9c:ce:33:ac` | `3001/TCP` | EC2 Instance (Target A) |
| **Mac 4** | Backend B & Capture Client | Express REST API | `10.7.7.247` | `6a:5f:a6:ec:a9:39` | `3002/TCP` | EC2 Instance (Target B) |

- **Subnet Definition:** `10.7.0.0/19` (Netmask: `255.255.224.0`, Default Gateway: `10.7.0.1`)
- **Active Wi-Fi Network:** `Rishihood_Learner`

![Mac 4 Wi-Fi Interface Details](/Users/aviralmishra/.gemini/antigravity-ide/brain/2a8a0a08-e634-4b7c-af83-7fa1e15afe03/wifi_network_settings.png)

---

## 2. Layer-2 Direct LAN Connectivity Evidence

All nodes reside on the same broadcast segment. Direct layer-2 connectivity is verified via `ttl=64` (0 intermediate router hops) with 0.0% packet loss.

```text
Mac4 -> Mac1: ping -c 4 10.7.5.248
PING 10.7.5.248 (10.7.5.248): 56 data bytes
64 bytes from 10.7.5.248: icmp_seq=0 ttl=64 time=42.343 ms
64 bytes from 10.7.5.248: icmp_seq=1 ttl=64 time=7.880 ms
64 bytes from 10.7.5.248: icmp_seq=2 ttl=64 time=87.926 ms
64 bytes from 10.7.5.248: icmp_seq=3 ttl=64 time=100.297 ms
--- 10.7.5.248 ping statistics ---
4 packets transmitted, 4 packets received, 0.0% packet loss

Mac4 -> Mac2: ping -c 4 10.7.21.122
PING 10.7.21.122 (10.7.21.122): 56 data bytes
64 bytes from 10.7.21.122: icmp_seq=0 ttl=64 time=6.858 ms
64 bytes from 10.7.21.122: icmp_seq=1 ttl=64 time=69.331 ms
64 bytes from 10.7.21.122: icmp_seq=2 ttl=64 time=87.429 ms
64 bytes from 10.7.21.122: icmp_seq=3 ttl=64 time=8.749 ms
--- 10.7.21.122 ping statistics ---
4 packets transmitted, 4 packets received, 0.0% packet loss

Mac4 -> Mac3: ping -c 4 10.7.6.183
PING 10.7.6.183 (10.7.6.183): 56 data bytes
64 bytes from 10.7.6.183: icmp_seq=0 ttl=64 time=12.218 ms
64 bytes from 10.7.6.183: icmp_seq=1 ttl=64 time=119.009 ms
64 bytes from 10.7.6.183: icmp_seq=2 ttl=64 time=8.849 ms
64 bytes from 10.7.6.183: icmp_seq=3 ttl=64 time=50.160 ms
--- 10.7.6.183 ping statistics ---
4 packets transmitted, 4 packets received, 0.0% packet loss
```

---

## 3. Protocol Configuration & Request Lifecycle

### A. Private DNS Resolution (`dnsmasq` on Mac 1)
- Authoritative private zone: `local=/lando.test/`
- Host mapping: `app.lando.test` ➔ `10.7.21.122`
- Upstream forwarding: `no-resolv`, `server=8.8.8.8`

```text
$ dig app.lando.test +short
10.7.21.122

$ dig google.com +short
192.178.158.102
192.178.158.100
192.178.158.101
```

#### Wireshark DNS Query & Response Capture
- **Frame 85:** Standard Query A `app.lando.test` (`10.7.7.247:UDP` ➔ `10.7.5.248:53`)
- **Frame 86:** Response `app.lando.test A 10.7.21.122`, `TTL=60s`

![Wireshark DNS Packet Capture](/Users/aviralmishra/.gemini/antigravity-ide/brain/2a8a0a08-e634-4b7c-af83-7fa1e15afe03/wireshark_dns_lando.png)

---

### B. TCP Three-Way Handshake
- **Frame 87 (SYN):** `10.7.7.247:55063` ➔ `10.7.21.122:443` (`Seq=0`, `MSS=1460`)
- **Frame 88 (SYN-ACK):** `10.7.21.122:443` ➔ `10.7.7.247:55063` (`Seq=0`, `Ack=1`)
- **Frame 89 (ACK):** `10.7.7.247:55063` ➔ `10.7.21.122:443` (`Seq=1`, `Ack=1`)

![Wireshark TCP Handshake Capture](/Users/aviralmishra/.gemini/antigravity-ide/brain/2a8a0a08-e634-4b7c-af83-7fa1e15afe03/wireshark_tcp_handshake.png)

---

### C. TLS 1.2 Termination & HTTP/2 (Validated without `-k`)
- **Trust Chain:** Server certificate signed by trusted `LANdo Local Root CA`.
- **ALPN Negotiation:** Agreed protocol `h2` (HTTP/2 binary framing).

```text
$ curl -v --tls-max 1.2 https://app.lando.test/api/status
* Host app.lando.test:443 was resolved.
* Connected to app.lando.test (10.7.21.122) port 443
* ALPN: curl offers h2,http/1.1
* TLSv1.2 (IN), TLS handshake, Certificate (11):
* Server certificate:
*  subject: CN=app.lando.test
*  issuer: CN=lando Local Root CA
* SSL certificate verify ok.
* using HTTP/2
> GET /api/status HTTP/2
> Host: app.lando.test
> User-Agent: curl/8.7.1
> 
< HTTP/2 200 
< server: nginx/1.31.6
< content-type: application/json; charset=utf-8
< x-backend: B
< cache-control: no-store
< etag: W/"3f-GJXGksv83Fkn0HW/cZX5plzy+1s"
< 
{"backend":"B","status":"ok","time":"2026-10-05T09:01:55.524Z"}
```

---

### D. Round-Robin Load Balancing
Traffic distributes across both instances. Clients interface solely with `app.lando.test`.

```text
$ for i in 1 2 3 4; do curl -si https://app.lando.test/api/status | grep -i x-backend; done
x-backend: A
x-backend: B
x-backend: A
x-backend: B
```

---

### E. HTTP Caching & Conditional Revalidation (Task F)
- Content served with `Cache-Control: public, max-age=60` and `ETag`.
- Expired cache revalidation sends `If-None-Match: <etag>`.
- Returns **`HTTP/2 304 Not Modified`** with zero payload body across all nodes.

```text
$ curl -I https://app.lando.test/api/cached
HTTP/2 200 
cache-control: public, max-age=60
etag: W/"29-s/P7x0T5t70Q66w9E7H4A"

$ ETAG=$(curl -sI https://app.lando.test/api/cached | grep -i '^etag' | cut -d' ' -f2 | tr -d '\r')
$ curl -I -H "If-None-Match: $ETAG" https://app.lando.test/api/cached
HTTP/2 304 Not Modified
server: nginx/1.31.6
cache-control: public, max-age=60
etag: W/"29-s/P7x0T5t70Q66w9E7H4A"
```

---

## 4. Controlled Failure Demonstration (Scenario D3: Stop One Backend)

Demonstrating Nginx upstream resilience, passive health checking (`max_fails=1 fail_timeout=10s`), and zero client disruption.

```
                    ┌────────────────────────┐
                    │ Normal State: A B A B  │
                    └───────────┬────────────┘
                                │
               [Action: Terminate Backend A (Port 3001)]
                                │
                    ┌───────────▼────────────┐
                    │ Failure State: B B B B │
                    │ Nginx detects error 61 │
                    │ Transparent retry to B │
                    └───────────┬────────────┘
                                │
               [Action: Restart Backend A on Port 3001]
                                │
                    ┌───────────▼────────────┐
                    │ Restored: A B A B      │
                    │ Self-heals after 10s   │
                    └────────────────────────┘
```

### 1. Normal Baseline State
```text
$ for i in 1 2 3 4; do curl -si https://app.lando.test/api/status | grep -i x-backend; done
x-backend: A
x-backend: B
x-backend: A
x-backend: B
```

### 2. Failure State (Backend A Process Terminated on Mac 3)
```text
$ for i in 1 2 3 4; do curl -si https://app.lando.test/api/status | grep -i x-backend; done
x-backend: B
x-backend: B
x-backend: B
x-backend: B
```
- **Nginx Error Log Evidence on Mac 2:**
  `connect() failed (61: Connection refused) while connecting to upstream: "http://10.7.6.183:3001/api/status"`
- **Upstream Resilience:** Automatically routed via `proxy_next_upstream error timeout http_502` to Backend B.

### 3. Restored State (Backend A Restarted)
```text
$ for i in 1 2 3 4; do curl -si https://app.lando.test/api/status | grep -i x-backend; done
x-backend: A
x-backend: B
x-backend: A
x-backend: B
```
- **Layer Affected:** Layer 7 (Application Upstream) & Layer 4 (Port 3001). Client-side DNS (Port 53) and Edge TLS (Port 443) remained 100% operational throughout.

---

## 5. Course Topic & Protocol Mapping Summary

| OSI / TCP-IP Layer | Protocol / Technology | Function in System Architecture |
|---|---|---|
| **Link & Physical Layer** | 802.11ax Wi-Fi, Ethernet | Local direct communication verified by ICMP `ttl=64`. |
| **Network Layer** | IPv4 (`10.7.0.0/19`) | Private IP addressing across 4 physical macOS nodes. |
| **Transport Layer** | TCP (`443`, `3001`, `3002`), UDP (`53`) | Connection-oriented 3-way handshake (`SYN, SYN-ACK, ACK`). |
| **Presentation / Security** | TLS 1.2, X.509 PKI | Cryptographic termination, custom Root CA trust, encrypted payload. |
| **Application Layer** | DNS, HTTP/2, REST | Private domain routing, binary multiplexing, caching, load balancing. |
