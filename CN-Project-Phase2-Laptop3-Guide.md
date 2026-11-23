# CN Project Phase 2: Laptop 3 (Backend Server A) Complete Guide

**Machine Role:** Application Server Instance A  
**Default IP:** `10.7.21.122` (Check using `ipconfig getifaddr en0`)  
**Service Port:** `3001` (TCP)  
**Assigned Phase 2 Responsibilities:**
1. **Extension C: Service Isolation (macOS PF Firewall Rules)** — *Primary Mandate*
2. **Extension D: High-Availability (HA) Backend Failover**
3. **Extension E: Standby Edge Proxy** *(If selected as standby node)*
4. **Extension A: Secondary DNS Resolver** *(If selected as backup resolver)*

---

## 1. Quick Checklist for Laptop 3

Before your evaluator approaches your table:
- [ ] Connect to the team Wi-Fi / Hotspot.
- [ ] Verify your IP (`ipconfig getifaddr en0`). If it changed from `10.7.6.183`, notify Laptop 2 so `nginx/LANdo.conf` is updated.
- [ ] Ensure Node.js is installed (`node -v`).
- [ ] Start Backend A: `cd backend && ./start-backend-a.sh`.
- [ ] Verify local health: `curl -i http://localhost:3001/api/status`.

---

## 2. Extension C: Service Isolation (Backend Firewall Rules)

### Goal
In a production cloud environment, backend application servers (EC2 instances) sit in a **private subnet** and must **NEVER** be directly accessible from the public internet or external client machines. Traffic must flow strictly through the Edge Load Balancer (Laptop 2).

### The Architecture on Laptop 3
- **Allow:** Edge Reverse Proxy (Laptop 2: `10.7.26.218`) to TCP port `3001`.
- **Allow:** Localhost (`127.0.0.1` / `::1`) to TCP port `3001`.
- **Block & Reject:** Direct incoming traffic from any other machine (e.g. Laptop 1, Laptop 4, or client laptops) to TCP port `3001`.

### Step-by-Step Execution

#### Step 1: Enable Service Isolation
From the project root on Laptop 3:
```bash
./firewall/enable-isolation-laptop3.sh
```
*(If Laptop 2's IP changed, pass the new IP: `./firewall/enable-isolation-laptop3.sh 10.7.XX.YY`)*

**What this script does:**
1. Generates `firewall/isolation-laptop3.conf` with Laptop 2's IP in the `<edge_server>` table.
2. Loads the rules into the macOS PF anchor `com.apple/backend_isolation` (ensuring system rules are untouched).
3. Enables PF (`pfctl -e`).

#### Step 2: Verify Status on Laptop 3
```bash
./firewall/status-isolation-laptop3.sh
```
Expected output:
```text
table <edge_server> { 10.7.26.218 }
pass in quick proto tcp from <edge_server> to any port = 3001 flags S/SA keep state
pass in quick inet proto tcp from 127.0.0.1 to any port = 3001 flags S/SA keep state
block return in quick proto tcp from any to any port = 3001
```

#### Step 3: Demonstrate to Evaluator
1. **From Laptop 2 (Edge / Reverse Proxy):**
   ```bash
   curl -i http://10.7.21.122:3001/api/status
   ```
   **Result:** `HTTP/1.1 200 OK`, `X-Backend: A`. **ALLOWED!**

2. **From a Client (Laptop 1 or Laptop 4):**
   ```bash
   curl -i --connect-timeout 3 http://10.7.21.122:3001/api/status
   ```
   **Result:** `curl: (7) Failed to connect to 10.7.21.122 port 3001: Connection refused`. **BLOCKED!**

3. **From any Client through the Edge Domain:**
   ```bash
   curl -i https://app.lando.test/api/status
   ```
   **Result:** `HTTP/2 200 OK`. **SUCCESS!** (Traffic reaches Laptop 3 through the edge proxy transparently).

#### Step 4: Rollback / Restore Original Configuration
When demonstration is complete:
```bash
./firewall/disable-isolation-laptop3.sh
```
This flushes only the `backend_isolation` anchor without restarting or disrupting your Mac's network.

---

## 3. Extension D: High-Availability (HA) Failover Behavior

### Goal
Demonstrate that when Backend A (Laptop 3) fails, nginx detects it and automatically routes all client traffic to Backend B (Laptop 4) with zero dropped requests.

### Demonstration Procedure
1. **Normal State (Both backends up):**
   Run multiple requests from a client:
   ```bash
   for i in {1..6}; do curl -sI https://app.lando.test/api/status | grep "x-backend"; done
   ```
   *Output alternates between `x-backend: A` and `x-backend: B`.*

2. **Simulate Laptop 3 Failure:**
   On Laptop 3, stop the backend process:
   ```bash
   cd backend && ./stop-backend-a.sh
   ```
   *(Or press `Ctrl+C` in the running terminal)*

3. **Verify Failover from Client:**
   Run the loop again from the client:
   ```bash
   for i in {1..6}; do curl -sI https://app.lando.test/api/status | grep "x-backend"; done
   ```
   *Output shows 100% `x-backend: B`. No errors, no 502 Bad Gateway!*

4. **Restore Backend A:**
   On Laptop 3:
   ```bash
   cd backend && ./start-backend-a.sh
   ```

5. **Verify Resumption of Load Balancing:**
   Run the loop again:
   *Output immediately resumes alternating between A and B!*

---

## 4. Extension E: Standby Edge (Controlled Edge Migration)

If the evaluator asks Laptop 3 to act as the **Standby Edge**:
1. Copy TLS certificates from Laptop 2 to `/opt/homebrew/etc/nginx/certs/`.
2. Copy `nginx/standby-edge-laptop3.conf` to `/opt/homebrew/etc/nginx/servers/standby.conf`.
3. Start nginx on Laptop 3:
   ```bash
   sudo nginx -t && sudo brew services restart nginx
   ```
4. On Laptop 1 (DNS), update `host-record=app.lando.test,10.7.6.183`.
5. Observe TTL expiry and verify clients now connect to Laptop 3 as the edge!

---

## 5. Wireshark Evidence for Laptop 3

During the live evaluation, you can show packet captures demonstrating the firewall in action:
1. Open Wireshark on Laptop 3 (or Laptop 4 capturing traffic).
2. Filter: `tcp.port == 3001`.
3. When a client tries to connect directly:
   - Notice the client sends `[SYN]`.
   - Laptop 3's PF firewall immediately replies with `[RST, ACK]`.
   - No TCP three-way handshake completes!
4. When Laptop 2 (Edge) connects:
   - Notice `[SYN]` -> `[SYN, ACK]` -> `[ACK]`.
   - Followed by `GET /api/status HTTP/1.1`.

---

## 6. Viva Questions & Model Answers for Laptop 3

### Q1: What layer of the network model does `pf` operate at?
**Answer:** `pf` (Packet Filter) is a stateful packet filter operating at **Layer 3 (Network Layer - IP)** and **Layer 4 (Transport Layer - TCP/UDP)**. It inspects packet headers (source IP, destination IP, source port, destination port, TCP flags) before the packet is delivered to user-space application sockets.

### Q2: Why is service isolation important in modern cloud architectures?
**Answer:** It enforces the **Defense-in-Depth** and **Least Privilege** security principles. Backend instances in private subnets should never be reachable directly from client machines. This prevents attackers from bypassing TLS termination, Web Application Firewalls (WAF), rate-limiting, and authentication checks enforced at the Edge.

### Q3: What is the difference between `block drop` and `block return`?
**Answer:**
- `block drop`: Silently discards the packet. The client's TCP stack retransmits `SYN` packets until timing out (~75 seconds).
- `block return`: Sends an immediate TCP `RST` (reset) packet back to the sender. The client immediately gets "Connection refused", terminating the attempt cleanly without hanging.

### Q4: How does nginx know Backend A is down during HA failover?
**Answer:** In `nginx.conf`, the upstream servers are configured with:
`server 10.7.6.183:3001 max_fails=1 fail_timeout=10s;` and `proxy_next_upstream error timeout http_502 http_503;`.
When Laptop 3 goes down, nginx's TCP connection attempt fails or times out. Instead of returning an error to the client, nginx transparently retries the request against Backend B within milliseconds.

### Q5: What is the Single Point of Failure (SPOF) in this system, and how would you fix it in production?
**Answer:** The Edge reverse proxy (Laptop 2) is a single point of failure. If Laptop 2 crashes, the entire service is unreachable even if both backends are healthy. In production, this is solved by:
1. Running multiple active-standby or active-active reverse proxies with **VRRP / keepalived** (Virtual IP failover).
2. Using **DNS failover / Anycast IP** across multiple edge instances (e.g. AWS Route 53 health checking multiple ALBs).

