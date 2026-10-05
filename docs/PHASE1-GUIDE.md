# CN Project Phase 1: Complete Build Guide

**Private Network Service Platform** · DNS → TCP → TLS → HTTP → load balancer, on 4 MacBooks, no cloud

This guide is written from a team that finished Phase 1 end to end. It covers the setup, every command in the order we ran it, the mistakes that cost us time, the evidence evaluators want, and the project structure. Replace the placeholders with your own values and follow it top to bottom.

---

## Contents
1. [What you are building](#1-what-you-are-building)
2. [Before you start](#2-before-you-start)
3. [Your values (fill this in first)](#3-your-values-fill-this-in-first)
4. [Step-by-step build](#4-step-by-step-build)
5. [Packet capture (Task G)](#5-packet-capture-task-g)
6. [The five failure demonstrations](#6-the-five-failure-demonstrations)
7. [Evidence checklist](#7-evidence-checklist)
8. [Project and repo structure](#8-project-and-repo-structure)
9. [Every session: restart and IP check](#9-every-session-restart-and-ip-check)
10. [Troubleshooting, layer by layer](#10-troubleshooting-layer-by-layer)
11. [Gotchas that cost us time](#11-gotchas-that-cost-us-time)
12. [Viva points](#12-viva-points)

---

## 1. What you are building

A client types `https://app.teamX.test`. The name is resolved by **your own DNS server**, the request goes over **HTTPS to an nginx edge**, and nginx **load-balances** it to one of **two backends**. You prove every step with `dig`, `curl` and Wireshark.

```
Client (Mac 1 or Mac 4)
  ├─ 1. DNS query  UDP :53  ───────────►  Mac 1  dnsmasq            (Private DNS)
  │      answer: app.teamX.test = Mac 2's IP
  └─ 2. HTTPS      TCP :443 ───────────►  Mac 2  nginx              (Edge: TLS + load balancer)
                                            ├─ plain HTTP :3001 ► Mac 3  Node/Express  (Backend A)
                                            └─ plain HTTP :3002 ► Mac 4  Node/Express  (Backend B)
```

| Machine | Role | Runs | Cloud equivalent |
|---|---|---|---|
| Mac 1 | Private DNS + test client | dnsmasq | Route 53 private hosted zone |
| Mac 2 | Edge: reverse proxy, TLS, load balancer | nginx | AWS ALB / CDN edge |
| Mac 3 | Backend A | Node.js + Express, port 3001 | EC2 instance in a target group |
| Mac 4 | Backend B + capture client | Node.js + Express, port 3002, Wireshark | EC2 instance in a target group |

**Give the most config work to the Mac 2 owner** (nginx + certificates). Mac 1 also needs admin rights.

**RAM does not matter.** dnsmasq, nginx and a small Express app each use a few MB; 8 GB Macs are plenty.

---

## 2. Before you start

### Network
- **All 4 Macs on the same Wi-Fi.** College Wi-Fi *may* block device-to-device traffic (client isolation). Test with `ping` before anything else (Step 2). If pings time out, use a personal router or phone hotspot instead.
- Turn off **VPNs** and **iCloud Private Relay** on client Macs; they bypass your DNS.
- On each Mac: System Settings → Wi-Fi → Details → set **Private Wi-Fi Address** to **Fixed**, so the MAC you record stays the same.

### Per Mac
- Admin password (needed on at least Mac 1 and Mac 2).
- [Homebrew](https://brew.sh) on Mac 1 and Mac 2 (`brew --version`).
- Node.js on Mac 3 and Mac 4 (`node -v`; else `brew install node`).
- Wireshark (Apple Silicon build) on Mac 4.

### Team habits that save hours
- **Never share commands through WhatsApp or similar chat apps.** They replace backticks and quotes with look-alike characters, which breaks code and makes the shell hang at a `quote>` prompt. Share through GitHub, AirDrop a `.txt`, or copy from this file directly.
- **Run `caffeinate -dims`** on the DNS and edge Macs and leave that tab open. When our DNS Mac went to sleep, every client lost name resolution.
- Make one person (the Mac 2 owner) the **evidence collector**; everyone AirDrops screenshots to them.

---

## 3. Your values (fill this in first)

Pick a team number and get each Mac's IP in Step 2. Every command below uses these placeholders:

| Placeholder | Meaning | Example (our team) |
|---|---|---|
| `teamX` | your team name | `team1` |
| `__DNS_IP__` | Mac 1 IP | `10.7.16.0` |
| `__EDGE_IP__` | Mac 2 IP | `10.7.21.121` |
| `__A_IP__` | Mac 3 IP | `10.7.18.211` |
| `__B_IP__` | Mac 4 IP | `10.7.16.48` |

Use the reserved **`.test`** domain. Never `.local`: macOS uses it for mDNS (Bonjour) and it will conflict.

---

## 4. Step-by-step build

Do one step at a time and check its expected output before moving on. Order: **LAN → DNS → backends → nginx (HTTP) → TLS → caching → captures.** Adding TLS last means you test each layer on its own first.

### Step 1: Check built-in tools (all Macs)
```bash
which curl dig nslookup ping openssl
```
Expected: 5 paths such as `/usr/bin/curl`. All ship with macOS.

### Step 2: Find IPs and test reachability (all Macs) · Task A
```bash
ipconfig getifaddr en0
```
Then ping every other Mac:
```bash
ping -c 3 <teammate IP>
```
- `64 bytes from ...` = reachable. ✅
- `Request timeout` = blocked. If **every** ping fails, the Wi-Fi has client isolation: switch networks.
- Look at `ttl=64` in the replies: macOS starts at 64 and each router hop subtracts 1. Still 64 means no router between your Macs, i.e. the same LAN segment.

### Step 3: Record network details (all Macs) · Task A
```bash
ipconfig getoption en0 subnet_mask
route -n get default | grep gateway
ifconfig en0 | grep ether
```
Put IP, subnet mask, prefix (e.g. 255.255.224.0 = /19), gateway, interface (`en0`) and MAC into one table. This is your **IP inventory** for the architecture document and demo step 1.

> Our example: a /19 network covers 10.7.0.0 to 10.7.31.255, so an IP ending in `.0` (10.7.16.0) was a valid ordinary host, not the network address.

### Step 4: Install software
**Mac 1:**
```bash
brew install dnsmasq
```
**Mac 2:**
```bash
brew install nginx
```

### Step 5: Configure the DNS server (Mac 1) · Task B
Check outside DNS is reachable (for forwarding normal names):
```bash
dig @8.8.8.8 google.com +short
```
Back up the default config, then write yours:
```bash
cp $(brew --prefix)/etc/dnsmasq.conf $(brew --prefix)/etc/dnsmasq.conf.original

cat > $(brew --prefix)/etc/dnsmasq.conf <<'EOF'
# ---- Team DNS (Mac 1) ----
# Don't read /etc/resolv.conf; use these upstream servers for everything else
no-resolv
server=8.8.8.8
server=1.1.1.1

# Our zone: answer it ourselves, never forward it upstream
local=/teamX.test/

# A records -> both names point to the edge (Mac 2)
host-record=app.teamX.test,__EDGE_IP__
host-record=api.teamX.test,__EDGE_IP__

# TTL for our records (seconds)
local-ttl=60

# Log every query
log-queries
EOF
```
Fill in your values (edit the two lines below, then run):
```bash
TEAM=teamX; EDGE_IP=__EDGE_IP__
sed -i '' "s/teamX/$TEAM/g; s/__EDGE_IP__/$EDGE_IP/g" $(brew --prefix)/etc/dnsmasq.conf
```
Syntax check. **dnsmasq lives in `sbin`, which is not on your PATH**, so use the full path:
```bash
$(brew --prefix)/sbin/dnsmasq --test --conf-file=$(brew --prefix)/etc/dnsmasq.conf
```
Expected: `dnsmasq: syntax check OK.`

Start it. `sudo` is required because port 53 is privileged:
```bash
sudo brew services start dnsmasq
```
Test on Mac 1, then from another Mac:
```bash
dig @127.0.0.1 app.teamX.test +short          # on Mac 1
dig @__DNS_IP__ app.teamX.test +short          # on Mac 4
```
Both should print Mac 2's IP.

### Step 6: Point client Macs at your DNS (Mac 4 + one more) · Task B
The spec needs **at least two** client Macs using your DNS.
```bash
sudo networksetup -setdnsservers Wi-Fi __DNS_IP__
dig app.teamX.test +short       # Mac 2's IP, with no @ = uses the configured resolver
dig google.com +short           # still works = forwarding upstream works
```
Undo later with `sudo networksetup -setdnsservers Wi-Fi empty`.

⚠️ These Macs now depend on Mac 1 for **all** DNS. If Mac 1 sleeps, their internet stops too.

### Step 7: Backends (Mac 3 and Mac 4) · Task C
```bash
mkdir -p ~/cn-backend && cd ~/cn-backend
npm init -y
npm install express
```
Create `server.js`. This version deliberately uses **no backticks**, so it survives being copied:
```bash
cat > ~/cn-backend/server.js <<'EOF'
const express = require("express");
const os = require("os");

const BACKEND = process.env.BACKEND || "A";
const PORT = Number(process.env.PORT) || 3001;
const app = express();

// Every response carries X-Backend so we can see who served it
app.use((req, res, next) => {
  res.set("X-Backend", BACKEND);
  console.log(new Date().toISOString() + "  from=" + req.socket.remoteAddress + "  " + req.method + " " + req.url);
  next();
});

app.get("/", (req, res) => {
  res.json({ service: "team backend", backend: BACKEND, host: os.hostname(), message: "running" });
});

// Never cached, so load balancing stays visible on every request
app.get("/api/status", (req, res) => {
  res.set("Cache-Control", "no-store");
  res.json({ backend: BACKEND, status: "ok", time: new Date().toISOString() });
});

// Cacheable (Task F). Same body on A and B => same ETag => 304 works behind the load balancer
app.get("/api/cached", (req, res) => {
  res.set("Cache-Control", "public, max-age=60");
  res.json({ data: "this response is cacheable", version: 1 });
});

// 0.0.0.0 = listen on all interfaces, so other Macs can reach it (not just localhost)
app.listen(PORT, "0.0.0.0", () => {
  console.log("Backend " + BACKEND + " listening on 0.0.0.0:" + PORT);
});
EOF
```
Start (leave the terminal open). Click **Allow** if macOS asks about incoming connections:
```bash
BACKEND=A PORT=3001 node server.js     # Mac 3
BACKEND=B PORT=3002 node server.js     # Mac 4
```
Test locally in a new tab, then from Mac 2 across the LAN:
```bash
curl -i http://localhost:3001/api/status        # Mac 3
curl -i http://__A_IP__:3001/api/status         # Mac 2 -> expect X-Backend: A
curl -i http://__B_IP__:3002/api/status         # Mac 2 -> expect X-Backend: B
```
If Mac 2's curl hangs: System Settings → Privacy & Security → **Local Network** → allow Terminal on Mac 2; and check the firewall on the backend Mac allows `node`.

Design notes worth knowing for the viva:
- `/api/status` includes the backend name and time, so A and B return **different ETags**. That is why it is `no-store`.
- `/api/cached` returns an **identical body** on A and B, so the ETag matches on both. That is what makes `304` work through the load balancer.

### Step 8: nginx reverse proxy + load balancer, HTTP first (Mac 2) · Task D
```bash
mkdir -p $(brew --prefix)/etc/nginx/servers
cat > $(brew --prefix)/etc/nginx/servers/teamX.conf <<'EOF'
# ---- Edge (Mac 2) ----
upstream team_backends {                                     # default strategy = round-robin
    server __A_IP__:3001 max_fails=1 fail_timeout=10s;       # Backend A
    server __B_IP__:3002 max_fails=1 fail_timeout=10s;       # Backend B
}

server {
    listen 80;
    server_name app.teamX.test api.teamX.test;

    location / {
        proxy_pass http://team_backends;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # If a backend is down, fail fast and retry on the other one
        proxy_connect_timeout 2s;
        proxy_next_upstream error timeout http_502 http_503;
    }
}
EOF

TEAM=teamX; A_IP=__A_IP__; B_IP=__B_IP__
sed -i '' "s/teamX/$TEAM/g; s/__A_IP__/$A_IP/g; s/__B_IP__/$B_IP/g" $(brew --prefix)/etc/nginx/servers/teamX.conf
mv $(brew --prefix)/etc/nginx/servers/teamX.conf $(brew --prefix)/etc/nginx/servers/$TEAM.conf

sudo nginx -t
sudo brew services start nginx
```
Test from Mac 4:
```bash
for i in 1 2 3 4; do curl -si http://app.teamX.test/api/status | grep X-Backend; done
```
Expected: `A B A B`. The client only ever used the name; it never learned the backend IPs.

### Step 9: Create TLS certificates (Mac 2) · Task E
You create your **own root CA**, then a **server certificate** signed by it. Clients trust only the CA.

Two rules:
- The certificate **must have a SAN** (Subject Alternative Name). Browsers ignore the Common Name.
- Use **Homebrew's OpenSSL 3**. macOS's `openssl` is actually LibreSSL.

Run all of these in the same terminal tab:
```bash
mkdir -p ~/cn-certs && cd ~/cn-certs
OPENSSL="$(brew --prefix openssl@3)/bin/openssl"
$OPENSSL version          # should print OpenSSL 3.x
TEAM=teamX                # <- your team

cat > ca.cnf <<EOF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = $TEAM Local Root CA
[v3_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
EOF

cat > leaf.cnf <<EOF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = app.$TEAM.test
[v3_leaf]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:app.$TEAM.test, DNS:api.$TEAM.test
EOF

# Root CA
$OPENSSL req -x509 -new -nodes -newkey rsa:2048 \
  -keyout rootCA.key -out rootCA.pem -days 825 \
  -config ca.cnf -extensions v3_ca

# Server key + CSR, signed by the CA
$OPENSSL req -new -nodes -newkey rsa:2048 \
  -keyout server.key -out server.csr -config leaf.cnf
$OPENSSL x509 -req -in server.csr -CA rootCA.pem -CAkey rootCA.key \
  -CAcreateserial -out server.crt -days 397 -sha256 \
  -extfile leaf.cnf -extensions v3_leaf

# Verify
$OPENSSL verify -CAfile rootCA.pem server.crt
$OPENSSL x509 -in server.crt -noout -ext subjectAltName
```
Expected: `server.crt: OK` and both `DNS:app...` and `DNS:api...`.

🔒 **Never share or commit `rootCA.key` or `server.key`.** Anyone with `rootCA.key` can mint certificates your Macs will trust. Only `rootCA.pem` leaves Mac 2.

### Step 10: Enable HTTPS in nginx (Mac 2) · Task E
```bash
mkdir -p $(brew --prefix)/etc/nginx/certs
cp ~/cn-certs/server.crt ~/cn-certs/server.key $(brew --prefix)/etc/nginx/certs/
chmod 600 $(brew --prefix)/etc/nginx/certs/server.key
```
Open your config (`nano $(brew --prefix)/etc/nginx/servers/teamX.conf`, with your team name), replace its whole content with the HTTPS version below, and fill in the placeholders. Quickest way, after saving:
```bash
TEAM=teamX; A_IP=__A_IP__; B_IP=__B_IP__
sed -i '' "s/teamX/$TEAM/g; s/__A_IP__/$A_IP/g; s/__B_IP__/$B_IP/g" $(brew --prefix)/etc/nginx/servers/$TEAM.conf
```
```nginx
upstream team_backends {
    server __A_IP__:3001 max_fails=1 fail_timeout=10s;   # Backend A
    server __B_IP__:3002 max_fails=1 fail_timeout=10s;   # Backend B
}

# Port 80: redirect everything to HTTPS
server {
    listen 80;
    server_name app.teamX.test api.teamX.test;
    return 301 https://$host$request_uri;
}

# Port 443: TLS terminates here, then plain HTTP to the backends
server {
    listen 443 ssl;
    http2 on;
    server_name app.teamX.test api.teamX.test;

    ssl_certificate     /opt/homebrew/etc/nginx/certs/server.crt;
    ssl_certificate_key /opt/homebrew/etc/nginx/certs/server.key;
    ssl_protocols       TLSv1.2 TLSv1.3;   # keep 1.2: its handshake is visible in Wireshark

    location / {
        proxy_pass http://team_backends;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 2s;
        proxy_next_upstream error timeout http_502 http_503;
    }
}
```
```bash
sudo nginx -t
sudo brew services restart nginx
curl -i --resolve app.teamX.test:443:127.0.0.1 --cacert ~/cn-certs/rootCA.pem https://app.teamX.test/api/status
```
Expected: `HTTP/2 200` and an `x-backend` header (lowercase in HTTP/2). If 443 is not allowed on your Mac, use 8443; the spec allows it.

### Step 11: Trust the CA on client Macs · Task E
AirDrop **only `rootCA.pem`** to each client. On each:
```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ~/Downloads/rootCA.pem
curl -i https://app.teamX.test/api/status
```
Expected: `HTTP/2 200` with **no `-k`** and no certificate error. The demo must not bypass validation.

Browser: Safari works. Chrome also worked for us; if Chrome ignores your DNS, turn off Settings → Privacy → **Use secure DNS**. Firefox has its own certificate store, so avoid it.

### Step 12: HTTP caching (Mac 4) · Task F
```bash
curl -I https://app.teamX.test/api/cached
```
Look for `cache-control: public, max-age=60` and `etag: W/"..."`.

Conditional request. Run as **separate lines**, copied from this file:
```bash
ETAG=$(curl -sI https://app.teamX.test/api/cached | grep -i '^etag' | cut -d' ' -f2 | tr -d '\r')
echo $ETAG
curl -I -H "If-None-Match: $ETAG" https://app.teamX.test/api/cached
```
Expected: **`HTTP/2 304`** with no body. Run it a few times: you will see a 304 from **both** A and B, because both produce the same ETag.

| Case | What happens |
|---|---|
| Fresh hit | Within `max-age`, the client reuses its copy and sends nothing |
| Conditional request | After expiry, the client sends `If-None-Match`; the server replies `304`, no body |
| Full request | No cached copy; server replies `200` with the full body |

### Step 13: HTTP/1.1 vs HTTP/2 (Mac 4)
```bash
curl -sI --http1.1 https://app.teamX.test/api/status | head -1     # HTTP/1.1 200 OK
curl -sI --http2   https://app.teamX.test/api/status | head -1     # HTTP/2 200
```
The version is agreed inside the TLS handshake through **ALPN**. HTTP/3 (QUIC over UDP 443) is explanation-only.

---

## 5. Packet capture (Task G)

Capture from **Mac 4, not Mac 1.** If Mac 1 queries its own dnsmasq, the DNS packet uses loopback and never appears on Wi-Fi.

1. Clear the DNS cache so a fresh query goes on the wire:
   ```bash
   sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
   ```
2. Open Wireshark. If no interfaces appear, install **ChmodBPF** (Wireshark offers it on first launch), then reopen. In the capture-filter box enter `host __DNS_IP__ or host __EDGE_IP__`, then double-click **Wi-Fi: en0**.
3. Make exactly one request:
   ```bash
   curl -v --tls-max 1.2 https://app.teamX.test/api/status 2>&1 | tee ~/curl-verbose.txt
   ```
   `--tls-max 1.2` matters: in TLS 1.3 the **Certificate** message is encrypted and you cannot point to it.
4. Stop (red square) → File → Save As → `phase1-full-flow.pcapng`.
5. Display filters to check (type in the top bar, press Enter):
   - `dns`
   - `tcp.flags.syn == 1`
   - `tls.handshake`
6. Find your client's port (the SYN to 443 shows e.g. `50353 → 443`), then show the clean single flow:
   ```
   dns.qry.name == "app.teamX.test" or tcp.port == <client port>
   ```
   File → Export Specified Packets → Displayed → `phase1-app-flow.pcapng`.

What to point at, in order:

| Layer | Packets | Show |
|---|---|---|
| DNS (UDP) | query + response | client ephemeral port → **53**; answer = edge IP |
| TCP | SYN, SYN-ACK, ACK | client ephemeral port → **443**; Seq/Ack numbers, Window |
| TLS 1.2 | Client Hello | SNI = `app.teamX.test`; ALPN offers h2, http/1.1 |
| | Server Hello, **Certificate**, Server Key Exchange, Server Hello Done | the certificate your CA signed |
| | Client Key Exchange, Change Cipher Spec, Finished | key agreement done |
| | Change Cipher Spec, Finished (server) | everything after is encrypted |
| Data | Application Data | HTTP is encrypted; show headers from `curl -v` instead |

Screenshots worth taking: each filter; the clean flow from the top; DNS packet with UDP expanded (ports); SYN with TCP expanded (ports, Seq 0); one Application Data packet expanded (encrypted bytes).

Bonus: on Wi-Fi you may catch real **Dup ACKs, SACK and retransmissions**. Keep them; they demonstrate TCP reliability perfectly.

---

## 6. The five failure demonstrations

Run on a client Mac (Mac 4). Restore after each one.

### 1. Wrong DNS server
```bash
sudo networksetup -setdnsservers Wi-Fi 8.8.8.8
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
dig app.teamX.test                                       # status: NXDOMAIN
curl https://app.teamX.test/api/status                  # Could not resolve host
ping -c 2 __EDGE_IP__                                    # still replies
curl --resolve app.teamX.test:443:__EDGE_IP__ https://app.teamX.test/api/status   # works
# restore
sudo networksetup -setdnsservers Wi-Fi __DNS_IP__
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```
**Proves:** DNS and IP connectivity are independent. The NXDOMAIN's AUTHORITY section is the **root zone**: `.test` does not exist publicly.

### 2. DNS record points to the wrong IP
On Mac 1, point `app` at a real Mac that has no nginx (e.g. Mac 3):
```bash
sed -i '' 's/host-record=app.teamX.test,__EDGE_IP__/host-record=app.teamX.test,__A_IP__/' $(brew --prefix)/etc/dnsmasq.conf
sudo brew services restart dnsmasq
```
On Mac 4:
```bash
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
dig app.teamX.test +short                     # wrong IP, resolution "succeeds"
curl https://app.teamX.test/api/status        # Failed to connect ... port 443
curl https://api.teamX.test/api/status        # still works (its record is correct)
```
Restore with the reverse `sed`, restart dnsmasq, flush the client cache.
**Proves:** DNS is a directory, not a connection. The failure surfaces at TCP.

### 3. One backend stopped
`Ctrl + C` on Mac 3, then on Mac 4:
```bash
for i in 1 2 3 4 5 6; do curl -si https://app.teamX.test/api/status | grep -i x-backend; done   # all B
```
On Mac 2:
```bash
tail -n 5 $(brew --prefix)/var/log/nginx/error.log      # connect() failed (61: Connection refused) ... :3001
```
Restart A, wait ~10 s (`fail_timeout`), rerun the loop: A and B alternate again.
**Proves:** passive health checks + retry keep the service up.

### 4. Both backends stopped
```bash
dig app.teamX.test +short
curl -vi https://app.teamX.test/api/status 2>&1 | grep -iE "SSL connection|HTTP/2|x-backend|server:"
```
Expected: DNS works, `SSL connection using TLS...`, `HTTP/2 502`, `server: nginx`, **no `x-backend`**.
**Proves:** everything up to the edge works; the failure is behind nginx.

### 5. Wrong destination port
```bash
nc -vz __EDGE_IP__ 443          # succeeded
nc -vz __EDGE_IP__ 8443         # Connection refused
curl https://app.teamX.test:8443/api/status
```
**Proves:** the IP picks the machine, the port picks the service. In Wireshark, a refused port is a SYN answered by RST, with no SYN-ACK.

---

## 7. Evidence checklist

The evaluator should find any piece of evidence within 30 seconds. Use one folder per task and name files by task letter. Terminal output saved as text counts ("screenshots or exports").

| Folder | Evidence |
|---|---|
| `A-lan/` | IP inventory table (IP, mask/prefix, gateway, en0, MAC); ping outputs between all pairs |
| `B-dns/` | `dig @<DNS_IP>`, `dig` with no `@` from **two** clients, `dig google.com`; screenshot of System Settings → Wi-Fi → Details → **DNS** showing your DNS IP on both clients |
| `C-backends/` | `curl -i` from Mac 2 to each backend (X-Backend A/B); backend log showing `from=<EDGE_IP>` |
| `D-loadbalancer/` | `nginx -t`; the A/B/A/B loop through the domain name |
| `E-tls/` | `openssl verify` + SAN output; `curl -i https://...` with **no `-k`**; browser padlock → certificate issued by your CA; Keychain Access → CA → **Always Trust**; HTTP/1.1 vs HTTP/2 lines |
| `F-caching/` | `curl -I` showing `cache-control` + `etag`; the **304** output |
| `G-wireshark/` | `phase1-full-flow.pcapng`, `phase1-app-flow.pcapng`, `curl-verbose.txt`; filter screenshots; port and encrypted-data detail screenshots |
| `H-failures/` | all five demonstrations above, plus the nginx error log line |

Also required: **architecture document** (topology diagram, IP/service table, request-flow diagram with each protocol layer, OSI/TCP-IP mapping, cloud equivalents), **configuration bundle**, **backend source code**.

Screenshot one window on macOS: `Cmd + Shift + 4`, then `Space`, then click the window.

---

## 8. Project and repo structure

```
cn-project/
├── README.md                 # overview, diagram, layout, endpoints
├── .gitignore                # *.key, *.csr, *.srl, node_modules/, .DS_Store
├── backend/
│   ├── server.js
│   └── package.json          # copy the real one from a backend Mac
├── dns/
│   └── dnsmasq.conf
├── nginx/
│   └── teamX.conf
├── certs/
│   ├── ca.cnf
│   ├── leaf.cnf
│   └── make-certs.sh         # the Step 9 commands as a script (keys stay git-ignored)
├── docs/
│   ├── SETUP.md              # per-machine setup and launch instructions
│   └── RUNBOOK.md            # session start, IP-change fixes, diagnosis
└── evidence/
    ├── A-lan/  B-dns/  C-backends/  D-loadbalancer/
    ├── E-tls/  F-caching/  G-wireshark/  H-failures/
```

`.gitignore`:
```
*.key
*.csr
*.srl
node_modules/
.DS_Store
```

---

## 9. Every session: restart and IP check

College DHCP can hand out new IPs. Start every session with this.

**1. Check IPs on all 4 Macs:** `ipconfig getifaddr en0`

**2. If one changed:**

| Changed | Fix |
|---|---|
| Edge (Mac 2) | Mac 1: update both `host-record` lines → `sudo brew services restart dnsmasq`; clients flush cache |
| A backend | Mac 2: update the `upstream` block → `sudo nginx -t && sudo brew services restart nginx` |
| DNS (Mac 1) | Each client: `sudo networksetup -setdnsservers Wi-Fi <new IP>` |

**3. Restart what doesn't survive sleep:**

| Survives a restart | Must restart |
|---|---|
| dnsmasq, nginx (brew services), client DNS settings, trusted CA, configs | both `node server.js` backends; `caffeinate -dims` on Mac 1 and Mac 2 |

**4. One test checks everything (Mac 4):**
```bash
for i in 1 2 3 4; do curl -si https://app.teamX.test/api/status | grep -i x-backend; done
```
A and B alternating = DNS, TCP, TLS, nginx and both backends are up.

---

## 10. Troubleshooting, layer by layer

Always go bottom-up in this order. This is also exactly how to handle the faculty-injected fault.

| # | Check | Command | If it fails |
|---|---|---|---|
| 1 | Name resolution | `dig app.teamX.test +short` | DNS: is Mac 1 awake? dnsmasq running? client resolver set? |
| 2 | IP reachability | `ping -c 2 <EDGE_IP>` | Network: same Wi-Fi? IP changed? |
| 3 | TCP port | `nc -vz <EDGE_IP> 443` | nginx not running, or wrong port |
| 4 | TLS | `curl -v https://app.teamX.test` | certificate / CA trust / SAN problem |
| 5 | Application | look for `502` | backends down or upstream IP wrong |

curl error codes: `(6) Could not resolve host` = DNS · `(7) Failed to connect` = TCP · `SSL certificate problem` = TLS · `502` = backend.

⚠️ `curl -s` hides error messages. When something "prints nothing", rerun without `-s` and add `; echo "exit=$?"`.

---

## 11. Gotchas that cost us time

| Symptom | Cause | Fix |
|---|---|---|
| `SyntaxError: Invalid or unexpected token` in server.js | WhatsApp replaced backticks with invisible characters | Use the backtick-free server.js above; never share code via chat apps |
| Shell "stuck", or `quote>` / `dquote>` prompt | A quote was altered while copying | `Ctrl + C`; copy from the source file directly |
| `dnsmasq: command not found` | Homebrew installs it in `/opt/homebrew/sbin` | Use `$(brew --prefix)/sbin/dnsmasq`, or add `/opt/homebrew/sbin` to PATH |
| Suddenly nothing resolves on any Mac | DNS Mac went to sleep / shut down | `caffeinate -dims` on Mac 1 (and Mac 2) |
| Conditional request returns `200`, not `304` | `If-None-Match` header got mangled | Use the `ETAG=$(...)` method or paste the exact ETag in single quotes |
| curl prints nothing | `-s` hid a real error | Remove `-s` |
| Certificate rejected by browser | No SAN in certificate | Use the `leaf.cnf` above |
| Can't see the Certificate packet in Wireshark | TLS 1.3 encrypts it | `curl --tls-max 1.2` for the capture |
| DNS packets missing from capture | Captured on the DNS server itself (loopback) | Capture on another client Mac |
| `No route to host` to a LAN IP | macOS Local Network permission | Privacy & Security → Local Network → allow Terminal |
| Ping between Macs times out | Wi-Fi client isolation or firewall Stealth Mode | Change network / turn off Stealth Mode |

---

## 12. Viva points

Every member must be able to explain every part, not only what they configured.

- **DNS vs connection:** DNS only finds the IP (UDP 53). The TCP/TLS connection to that IP is a separate, later step. Failure demos 1 and 2 prove it.
- **TTL 64 and MAC addresses:** pings arrive with TTL 64 and frames are addressed to the target Mac's own MAC, not the gateway's, so the Macs talk directly on one LAN segment.
- **Why `.test`:** reserved for private use; public DNS answers NXDOMAIN from the root zone. `.local` belongs to mDNS.
- **TLS termination:** TLS ends at nginx. nginx → backend is plain HTTP on the LAN. The backend sees the edge's IP, not the client's (`from=<EDGE_IP>` in its log); the real client is in `X-Forwarded-For`.
- **Why the client never knows backend IPs:** it only knows the name; DNS points at the edge; the edge chooses the backend.
- **TLS 1.2 handshake:** Client Hello (SNI, ALPN) → Server Hello → Certificate → Server Key Exchange → Server Hello Done → Client Key Exchange → Change Cipher Spec → Finished, in both directions.
- **Why your CA works:** it is marked `CA:TRUE` with Key Cert Sign, and the client keychain trusts it, so any certificate it signs (with a matching SAN) validates.
- **ALPN:** HTTP/1.1 vs HTTP/2 is negotiated inside the TLS Client Hello, which is why Wireshark labels encrypted data as HTTP/2 without being able to read it.
- **Load balancing:** round-robin by default; `max_fails` + `fail_timeout` mark a backend down; `proxy_next_upstream` retries the request on the other backend. Cloud equivalent: ALB health checks.
- **Caching:** identical content → identical ETag → `304` works whichever backend answers. Fresh hit vs conditional request vs full request.
- **Ports:** client uses a random ephemeral port (e.g. 50353, 58942); servers use well-known ports (53, 443) or fixed ones (3001, 3002). A socket = IP + port at each end.
- **TCP reliability:** sequence/acknowledgement numbers, Dup ACKs, SACK and retransmission; the `Win=` field is flow control.
- **502 Bad Gateway:** the edge is fine but its upstream isn't.
- **Single points of failure:** Mac 1 (DNS) and Mac 2 (edge). Phase 2 adds a backup resolver and a standby edge with a DNS cutover.
