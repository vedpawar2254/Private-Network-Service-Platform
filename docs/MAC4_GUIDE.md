# Mac 4 (Backend B + Capture Client) Complete Action Guide

## 1. Network & IP Inventory (Live Verified)

| Machine | Role | IP Address | MAC Address (Ethernet) | Service Port | Status |
|---|---|---|---|---|---|
| **Mac 1** | Private DNS (dnsmasq) | **`10.7.5.248`** | `7a:ed:a5:e2:d8:4c` | 53 (UDP) | Online (`ttl=64`) |
| **Mac 2** | Edge: Nginx + TLS + Load Balancer | **`10.7.21.122`** | `52:01:cf:b4:e1:ba` | 80, 443 (TCP) | Online (`ttl=64`) |
| **Mac 3** | Backend A (Express) | **`10.7.6.183`** | `46:8b:9c:ce:33:ac` | 3001 (TCP) | Online & Serving (`X-Backend: A`) |
| **Mac 4** | **Backend B + Capture Client (This Machine)** | **`10.7.7.247`** | **`6a:5f:a6:ec:a9:39`** | **3002 (TCP)** | **Online & Serving (`X-Backend: B`)** |

- **Subnet Mask / Prefix:** `255.255.224.0` (/19)
- **Default Gateway:** `10.7.0.1`
- **Wi-Fi SSID:** `Rishihood_Learner`
- **Team Name & Domain:** `LANdo` (`app.lando.test`, `api.lando.test`)

---

## 2. Configuration Directives for Teammates

### A. Mac 2 (Edge Nginx / Load Balancer)
Provide this block for `/opt/homebrew/etc/nginx/servers/lando.conf`:
```nginx
upstream team_backends {
    server 10.7.6.183:3001 max_fails=1 fail_timeout=10s;   # Backend A (Mac 3)
    server 10.7.7.247:3002 max_fails=1 fail_timeout=10s;   # Backend B (Mac 4 - This Host)
}
```
*Note: Request `rootCA.pem` from Mac 2 via AirDrop after certificate generation.*

### B. Mac 1 (Private DNS)
Provide these lines for `/opt/homebrew/etc/dnsmasq.conf`:
```conf
# Team LANdo Private DNS Records
host-record=app.lando.test,10.7.21.122
host-record=api.lando.test,10.7.21.122
```
*Instruction: Reload via `sudo brew services restart dnsmasq`.*

---

## 3. Mac 4 Execution Sequence

### Step 1: Start Backend B (Port 3002)
Execute in a dedicated terminal session:
```bash
cd ~/cn-backend
./start-backend-b.sh
```
Verification:
```bash
curl -i http://localhost:3002/api/status
```
Expected output: `HTTP/1.1 200 OK` with header `X-Backend: B`.

### Step 2: Configure Client DNS Resolver
Point macOS resolver to Mac 1:
```bash
sudo networksetup -setdnsservers Wi-Fi 10.7.5.248
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```
Verify resolution:
```bash
dig app.lando.test +short
# Expected output: 10.7.21.122
```
*(To revert to default DHCP DNS later: `sudo networksetup -setdnsservers Wi-Fi empty`)*

### Step 3: Install & Trust Root CA Certificate
Receive `rootCA.pem` from Mac 2 via AirDrop (saved in `~/Downloads/rootCA.pem`):
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Downloads/rootCA.pem
```
Verify HTTPS (without `-k`):
```bash
curl -i https://app.lando.test/api/status
```
Verify Round-Robin Load Balancing:
```bash
for i in 1 2 3 4; do curl -si https://app.lando.test/api/status | grep -i x-backend; done
```
Expected output: Alternating sequence `A B A B`.

### Step 4: HTTP Caching Verification (Task F)
Validate `Cache-Control` and conditional `304 Not Modified`:
```bash
# Initial request (Inspect Cache-Control and ETag)
curl -I https://app.lando.test/api/cached

# Conditional request
ETAG=$(curl -sI https://app.lando.test/api/cached | grep -i '^etag' | cut -d' ' -f2 | tr -d '\r')
curl -I -H "If-None-Match: $ETAG" https://app.lando.test/api/cached
```
Expected output: `HTTP/2 304` with 0-byte payload.

### Step 5: Protocol Flow Packet Capture (Task G)
1. Flush DNS cache:
   ```bash
   sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
   ```
2. Launch Wireshark:
   ```bash
   open /Applications/Wireshark.app
   ```
3. Set Capture Filter: `host 10.7.5.248 or host 10.7.21.122` on interface `Wi-Fi: en0`.
4. Trigger request:
   ```bash
   curl -v --tls-max 1.2 https://app.lando.test/api/status 2>&1 | tee ~/curl-verbose.txt
   ```
5. Stop capture and export to `evidence/G-wireshark/phase1-full-flow.pcapng`.
