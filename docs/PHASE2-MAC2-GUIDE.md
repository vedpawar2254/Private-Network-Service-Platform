# Phase 2 — Mac 2 (Edge / Reverse Proxy / Load Balancer) Complete Guide
**Harden · Recover · Troubleshoot**

> Mac 2 role: **nginx Edge + TLS termination + Load Balancer** (cloud equivalent: AWS ALB / CDN edge)
> Domain: `lando.test` | Mac 1 DNS: `10.7.30.221` | **Mac 2 Edge: `10.7.26.218`** (pehle `10.7.21.122` tha, DHCP ne change kar diya)
> Backend A (Mac 3): `10.7.21.122:3001` | Backend B (Mac 4): `10.7.15.167:3002`
> Live config: `/opt/homebrew/etc/nginx/servers/lando.conf` | Repo copy: `nginx/lando.conf` (Phase 1), `nginx/lando-phase2.conf` (Phase 2)

---

## Mac 2 ka Phase 2 mein kya kaam hai?

| Extension | Mac 2 kya karta hai | Owner level |
|-----------|---------------------|-------------|
| **A — Backup DNS** | Client ban ke dono DNS (Mac 1 + Mac 4) set karta hai, failover test karta hai | Support |
| **B — TTL** | Client ban ke cached vs new answer dekhta hai | Support |
| **C — Service Isolation** | **Allowed IP** hai — prove karta hai ki Mac 2 backends tak pahunch sakta hai jab client blocked hai. pf rule template Mac 3/4 ko deta hai | **Main** |
| **D — HA Failover** | nginx passive health check, failover evidence (access + error logs) | **Main owner** |
| **E — Edge Cutover** | Apna nginx config + cert standby edge (Mac 4) ko deta hai; cutover ke time primary edge | **Main** |
| **F — Troubleshooting** | Edge-side faults (nginx down, bad config, wrong upstream, cert issue) diagnose karta hai | **Main** |

---

## Step 0 — Session Start (har baar pehle yeh)

```bash
cd ~/Desktop/Private-Network-Service-Platform

# 1. Apna IP check karo
ipconfig getifaddr en0          # abhi: 10.7.26.218

# 2. Baaki Macs ping karo
ping -c 2 10.7.30.221            # Mac 1 (DNS)
ping -c 2 10.7.21.122            # Mac 3 (Backend A)
ping -c 2 10.7.15.167            # Mac 4 (Backend B)

# 3. Backends Mac 2 se reachable hain? (yeh hi nginx ka actual path hai)
curl -si http://10.7.21.122:3001/api/status | grep -i x-backend    # A
curl -si http://10.7.15.167:3002/api/status | grep -i x-backend    # B

# 4. nginx chal raha hai?
sudo nginx -t && sudo brew services list | grep nginx

# 5. Sleep mat hone do (alag tab mein chhod do)
caffeinate -dims
```

### ⚠️ Abhi turant karna hai — IP change hua hai

Mac 2 ka IP `10.7.21.122` → `10.7.26.218` ho gaya hai. **Mac 1 wale (Ved) ko bolo:**

```bash
# Mac 1 pe:
# app + api dono records ko Mac 2 ke current IP pe set karo (jo bhi purana IP tha)
sudo sed -i '' -E 's/^(host-record=(app|api)\.lando\.test),.*/\1,10.7.26.218/I' $(brew --prefix)/etc/dnsmasq.conf
grep host-record $(brew --prefix)/etc/dnsmasq.conf
sudo brew services restart dnsmasq
dig @127.0.0.1 app.lando.test +short     # 10.7.26.218 aana chahiye
```
Mac 4 pe backup dnsmasq mein bhi same change. Certificate change **nahi** karna — cert ka SAN `DNS:app.lando.test` hai, IP nahi, isliye IP badalne se TLS nahi tootega (viva point!).

Apne Mac ko bhi team DNS use karwao (abhi `8.8.8.8` pe hai):
```bash
sudo networksetup -setdnsservers Wi-Fi 10.7.30.221 10.7.15.167    # primary + backup
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
dig app.lando.test +short                                       # 10.7.26.218
```

---

## Step 1 — Phase 2 nginx config deploy karo

Phase 2 config mein 3 cheezein add hain (`nginx/lando-phase2.conf`):
- `X-Edge: mac2-primary` header → Extension E mein dikhega kaunsa edge answer kar raha hai
- `X-Upstream: <ip:port>` header → Extension D mein dikhega kaunsa backend IP use hua
- Alag `lando-error.log` at `warn` level → "upstream connect() failed" lines evidence ke liye

```bash
# Phase 1 config ka rollback copy — servers/ ke BAHAR rakho
# (nginx.conf mein `include servers/*;` hai, toh servers/ ki har file load hoti hai → duplicate upstream error)
mkdir -p ~/nginx-backups
cp /opt/homebrew/etc/nginx/servers/lando.conf ~/nginx-backups/lando.conf.phase1

# Phase 2 config lagao
cp nginx/lando-phase2.conf /opt/homebrew/etc/nginx/servers/lando.conf
# (agar kisi backend ka IP change hua hai toh upstream block edit karo)

sudo nginx -t                    # "syntax is ok" + "test is successful"
sudo nginx -s reload             # zero-downtime reload

# Test (kisi bhi client se, ya Mac 2 se)
curl -sI https://app.lando.test/api/status | grep -iE "x-edge|x-upstream|x-backend"
# x-backend: A
# x-edge: mac2-primary
# x-upstream: 10.7.21.122:3001
```

> **Rollback to Phase 1:** `cp ~/nginx-backups/lando.conf.phase1 /opt/homebrew/etc/nginx/servers/lando.conf && sudo nginx -t && sudo nginx -s reload`

---

## Extension C — Service Isolation (Mac 2 = sirf yahi allowed)

**Goal:** Ports 3001/3002 pe sirf Mac 2 pahunch sake. Mac 1 / koi client direct connect kare → blocked.

Firewall **Mac 3 aur Mac 4 pe** lagega, but rule mein **Mac 2 ka IP** hai — isliye yeh template tum unhe doge.

### C.1 — pf rule template (Mac 3 aur Mac 4 ko bhejo)

Mac 3 (port 3001) — file `~/cn-isolation.pf`:
```
# Allow ONLY the edge (Mac 2) to reach Backend A
pass  in quick proto tcp from 10.7.26.218 to any port 3001
block in quick proto tcp from any         to any port 3001
```
Mac 4 (port 3002) — same, bas `3001` → `3002`.

Mac 3/4 pe load karna:
```bash
sudo cp /etc/pf.conf ~/pf.conf.rollback                        # rollback copy (deliverable)
sudo pfctl -a com.apple/cn-isolation -f ~/cn-isolation.pf       # apple anchor already referenced in /etc/pf.conf
sudo pfctl -E                                                   # pf enable
sudo pfctl -a com.apple/cn-isolation -s rules                   # rules dikhao (screenshot)
```
Rollback (demo ke baad):
```bash
sudo pfctl -a com.apple/cn-isolation -F all     # sirf hamare rules hatao
sudo pfctl -d                                   # pf disable (agar pehle disabled tha)
```

### C.2 — Mac 2 se proof (allowed path)

```bash
mkdir -p evidence/K-isolation

# Firewall lagne ke BAAD Mac 2 se direct — WORK karna chahiye
curl -si --connect-timeout 5 http://10.7.21.122:3001/api/status > evidence/K-isolation/mac2-to-backendA-ALLOWED.txt 2>&1
curl -si --connect-timeout 5 http://10.7.15.167:3002/api/status > evidence/K-isolation/mac2-to-backendB-ALLOWED.txt 2>&1
head -3 evidence/K-isolation/mac2-to-backend*-ALLOWED.txt

# Aur full path via nginx bhi
for i in 1 2 3 4; do curl -si https://app.lando.test/api/status | grep -i x-backend; done > evidence/K-isolation/via-edge-still-works.txt
```
Mac 1 same direct curl karega → timeout (`curl: (28)`). Dono ko side-by-side screenshot = Extension C proof.

> ⚠️ **Extension E ke saath conflict:** Agar standby edge Mac 4 pe hai, toh Mac 3 ka firewall Mac 4 ko 3001 pe block karega → standby edge sirf Backend B use karega. Ya toh **C ka rollback karke E karo**, ya Mac 3 ke rule mein Mac 4 ka IP bhi `pass` karo: `pass in quick proto tcp from 10.7.15.167 to any port 3001`.

---

## Extension D — High Availability Failover (Mac 2 ka main kaam)

**Goal:** Backend down ho toh nginx use detect kare aur sirf healthy backend pe bheje. Wapas aaye toh dono pe round-robin phir se.

### D.0 — Kaise kaam karta hai (viva ke liye samjho)

```
upstream team_backends {
    server 10.7.21.122:3001 max_fails=1 fail_timeout=10s;
    server 10.7.15.167:3002 max_fails=1 fail_timeout=10s;
}
proxy_connect_timeout 2s;
proxy_next_upstream error timeout http_502 http_503;
```
- **Passive health check:** open-source nginx khud se ping nahi karta. Jab ek real request A pe fail hoti hai (TCP connection refused), nginx A ko **10s ke liye "down" mark** kar deta hai (`max_fails=1` within `fail_timeout=10s`).
- **`proxy_next_upstream`:** jis request ka A pe connect fail hua, wahi request turant B pe retry hoti hai → **client ko error dikhta hi nahi**.
- 10s baad nginx A ko phir ek real request deta hai. A up hai → wapas rotation mein.
- **Active health check** (`health_check` directive) sirf NGINX Plus mein hota hai — difference batana viva mein.

### D.1 — Live logs khol do (2 alag terminal tabs)

```bash
tail -f /opt/homebrew/var/log/nginx/lando-access.log     # backend=... (status) har request ka
tail -f /opt/homebrew/var/log/nginx/lando-error.log      # failure lines
```

### D.2 — Normal → A down → A back

```bash
mkdir -p evidence/L-ha-failover
t() { for i in 1 2 3 4 5 6; do curl -s -o /dev/null -w "%{http_code} " https://app.lando.test/api/status; curl -sI https://app.lando.test/api/status | grep -i x-backend; done; }

# 1) Normal: A B A B
t | tee evidence/L-ha-failover/1-normal.txt

# 2) Mac 3 wala Ctrl+C karega (Backend A band). Phir:
t | tee evidence/L-ha-failover/2-backendA-down.txt          # sab 200 + B

# Error log mein proof
grep -E "connect\(\) failed|upstream" /opt/homebrew/var/log/nginx/lando-error.log | tail -5 \
  | tee evidence/L-ha-failover/2-nginx-error-log.txt
# ... connect() failed (61: Connection refused) while connecting to upstream ... upstream: "http://10.7.21.122:3001/api/status"

# Access log mein retry dikhega: backend=10.7.21.122:3001, 10.7.15.167:3002 (502, 200)
tail -8 /opt/homebrew/var/log/nginx/lando-access.log | tee evidence/L-ha-failover/2-access-log-retry.txt

# 3) Mac 3 wala server phir start karega. 10-15s wait:
sleep 15
t | tee evidence/L-ha-failover/3-backendA-restored.txt      # phir A B A B
```

### D.3 — Dono backends down (bonus, Phase 1 failure ka Phase 2 version)
```bash
curl -si https://app.lando.test/api/status | head -1     # HTTP/2 502
```
DNS ✅, TCP ✅, TLS ✅ (Mac 2 tak) — sirf application layer fail. **Edge yahin khatam hota hai, backend yahin shuru.**

### D.4 — Single Point of Failure (must explain)

> Backends ab redundant hain (A/B). DNS bhi redundant hai (Mac 1 + Mac 4 backup). **Lekin Mac 2 (nginx edge) abhi bhi SPOF hai** — sirf ek IP, ek machine. Mac 2 band = poori service band, even though DNS aur dono backends up hain.
>
> **Fix:** do edge machines + **floating/virtual IP** with VRRP (`keepalived`) — active edge fail ho toh standby VIP le leta hai seconds mein. Ya DNS mein dono edges (round-robin) + health-checked DNS (Route 53 health checks). Cloud mein ALB khud multi-AZ hota hai. Extension E (DNS cutover) is SPOF ka **manual, TTL-limited** version hai.

---

## Extension E — DNS-Based Edge Cutover (Standby edge = Mac 4)

**Goal:** Mac 4 pe same nginx config. Mac 1 DNS record ko Mac 2 → Mac 4 pe point kare. TTL ke wajah se cached clients thodi der Mac 2 pe hi jaayenge, phir Mac 4 pe.

### E.1 — Standby edge ko config + cert do (Mac 2 ka kaam)

AirDrop / USB se Mac 4 ko bhejo (**git mein `server.key` kabhi commit mat karna**):
- `nginx/lando-standby.conf` (repo mein hai — same config, sirf `X-Edge: mac4-standby`)
- `/opt/homebrew/etc/nginx/certs/server.crt`
- `/opt/homebrew/etc/nginx/certs/server.key`

```bash
# AirDrop ke liye ek folder bana do
mkdir -p ~/Desktop/for-mac4
cp nginx/lando-standby.conf /opt/homebrew/etc/nginx/certs/server.crt ~/Desktop/for-mac4/
sudo cp /opt/homebrew/etc/nginx/certs/server.key ~/Desktop/for-mac4/ && sudo chown $USER ~/Desktop/for-mac4/server.key
# demo ke baad: rm -rf ~/Desktop/for-mac4
```

Mac 4 wala karega:
```bash
brew install nginx
mkdir -p /opt/homebrew/etc/nginx/servers /opt/homebrew/etc/nginx/certs
cp ~/Downloads/lando-standby.conf /opt/homebrew/etc/nginx/servers/lando.conf
cp ~/Downloads/server.crt ~/Downloads/server.key /opt/homebrew/etc/nginx/certs/
chmod 600 /opt/homebrew/etc/nginx/certs/server.key
sudo nginx -t && sudo brew services start nginx
```

Mac 2 se verify (cert same hai isliye `--resolve` se bina `-k` ke chalega):
```bash
curl -sI --resolve app.lando.test:443:10.7.15.167 https://app.lando.test/api/status | grep -iE "x-edge|x-backend"
# x-edge: mac4-standby   ← standby ready
```
> `--resolve` DNS ko bypass karke name→IP fix karta hai, lekin TLS SNI + cert check `app.lando.test` ke liye hi hota hai. Isliye `-k` nahi chahiye.

### E.2 — Cutover (Mac 1 DNS change karega, Mac 2 observe karega)

```bash
mkdir -p evidence/M-cutover
w() { date +%T; dig app.lando.test +noall +answer; curl -sI https://app.lando.test/api/status | grep -i x-edge; }

w | tee evidence/M-cutover/1-before.txt              # 10.7.26.218, x-edge: mac2-primary

# Mac 1: host-record=app.lando.test,10.7.15.167 + restart dnsmasq
# Ab TURANT:
w | tee evidence/M-cutover/2-immediately-after.txt   # abhi bhi mac2-primary (cache, TTL count down)

# Har 10s pe dekho jab tak switch na ho
for i in 1 2 3 4; do w; sleep 10; done | tee evidence/M-cutover/3-ttl-countdown.txt
# TTL 30 → ... → expire → 10.7.15.167, x-edge: mac4-standby

# Mac 2 ke access log mein naye requests aana band ho jaayenge — proof ki traffic chala gaya
tail -5 /opt/homebrew/var/log/nginx/lando-access.log | tee evidence/M-cutover/4-mac2-log-quiet.txt
```

**Strong demo:** cutover ke baad Mac 2 pe `sudo brew services stop nginx` → service ab bhi chal rahi hai via Mac 4. Yeh "planned maintenance" scenario hai.

### E.3 — Rollback
```bash
sudo brew services start nginx                # Mac 2 wapas
# Mac 1: record wapas 10.7.26.218, restart dnsmasq
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
w                                              # mac2-primary
```

**Viva point:** Production mein migration se **pehle** TTL ghatate hain (e.g. 3600 → 30) aur purana TTL expire hone tak wait karte hain, taaki cutover ke time sab clients jaldi switch karein. Purana edge tab tak band nahi karte jab tak uske logs mein traffic zero na ho jaaye.

---

## Extension A & B — Mac 2 as Client (support role)

```bash
mkdir -p evidence/I-backup-dns evidence/J-ttl-demo

# A: dono DNS set hain?
scutil --dns | grep nameserver | head -2 | tee evidence/I-backup-dns/mac2-resolvers.txt

# Mac 1 dnsmasq stop kare, phir:
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
dig app.lando.test +short                      # abhi bhi 10.7.26.218 (Mac 4 backup se)
dig @10.7.30.221 app.lando.test +time=2 +tries=1 # timeout — primary down proof
curl -sI https://app.lando.test/api/status | head -1   # 200 — service chal rahi hai
# sab ek file mein:
{ dig @10.7.30.221 app.lando.test +time=2 +tries=1; dig @10.7.15.167 app.lando.test; curl -sI https://app.lando.test/api/status | head -1; } \
  > evidence/I-backup-dns/mac2-primary-down-backup-works.txt 2>&1

# B: TTL countdown dekhna (record change ke time)
for i in 1 2 3 4; do date +%T; dig app.lando.test +noall +answer; sleep 10; done | tee evidence/J-ttl-demo/mac2-client-view.txt
```

**DNS failure vs app failure:** DNS down → `curl: (6) Could not resolve host` (nginx tak pahunche hi nahi). App down → DNS ✅, TLS ✅, nginx `502`. Mac 2 ka log isse prove karta hai — DNS failure mein **lando-access.log mein koi entry nahi aati**, backend failure mein `502` entry aati hai.

---

## Extension F — Troubleshooting (Edge-side faults)

Faculty zyada chance hai Mac 2 pe fault inject kare (edge = sab kuch yahan se guzarta hai). **Order: client se bahar → andar.**

### F.1 — Client se (kisi bhi Mac se)
```bash
dig app.lando.test +short                                   # 1. DNS
ping -c 2 10.7.26.218                                       # 2. IP
nc -vz 10.7.26.218 443                                      # 3. TCP
curl -v https://app.lando.test/api/status 2>&1 | grep -iE "SSL|certificate|subject|expire|error"   # 4. TLS
curl -si https://app.lando.test/api/status | head -1        # 5. App
```

### F.2 — Mac 2 pe (edge ke andar)
```bash
sudo nginx -t                                               # config syntax / missing cert file
sudo brew services list | grep nginx                        # running?
sudo lsof -nP -iTCP:443 -sTCP:LISTEN                        # 443 pe kaun sun raha hai
tail -20 /opt/homebrew/var/log/nginx/lando-error.log        # upstream / ssl errors
grep -A3 "upstream team_backends" /opt/homebrew/etc/nginx/servers/lando.conf   # backend IP/port sahi?
curl -si --connect-timeout 3 http://10.7.21.122:3001/api/status | head -1      # Mac 2 → A direct
curl -si --connect-timeout 3 http://10.7.15.167:3002/api/status | head -1      # Mac 2 → B direct
openssl s_client -connect 127.0.0.1:443 -servername app.lando.test </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -enddate -ext subjectAltName                  # cert kaunsa serve ho raha hai
```

### F.3 — Likely faults ka cheat sheet

| Fault (Mac 2 pe) | Symptom (client) | Mac 2 pe kaise pakdo | Fix |
|---|---|---|---|
| nginx stopped | `nc` refused, `curl: (7)` | `brew services list` → stopped | `sudo brew services start nginx` |
| Config syntax error | reload fail, purana config chalta rahega / start nahi hoga | `sudo nginx -t` line number batata hai | fix line → `nginx -t` → reload |
| `listen 443` → `listen 8443` | `nc 443` refused | `lsof -iTCP:443` empty | port wapas |
| Upstream wrong IP/port (dono) | `502 Bad Gateway` | error.log: `connect() failed ... upstream: "http://x.x.x.x:yyyy"` | upstream block sahi karo |
| Upstream ek galat | sirf ek backend dikhta (A A A) | access log `backend=...` | same |
| Wrong cert/key (e.g. self-signed localhost) | `SSL certificate problem` / name mismatch | `openssl s_client ... subjectAltName` | sahi `server.crt` |
| cert/key mismatch | nginx start nahi hota | `nginx -t`: `key values mismatch` | matching pair |
| `proxy_pass` galat (e.g. https://) | 502 | error.log: `SSL_do_handshake() failed` / `wrong version number` | `http://team_backends` |
| macOS firewall blocks nginx | client pe timeout | System Settings → Network → Firewall | allow nginx |
| Mac 2 IP change | DNS purana IP de raha, timeout | `ipconfig getifaddr en0` vs `dig` | Mac 1 record update |

**Rule:** Har step bolte jao — "DNS sahi IP de raha hai, isliye DNS layer theek. TCP 443 connect hua, toh nginx sun raha hai. TLS handshake complete, cert valid. 502 aa raha hai, toh problem edge ke peeche — upstream mein." Methodology pe partial marks milte hain.

---

## Evidence Folders — Phase 2 (Mac 2)

```
evidence/
├── I-backup-dns/   mac2-resolvers.txt, mac2-primary-down-backup-works.txt
├── J-ttl-demo/     mac2-client-view.txt
├── K-isolation/    mac2-to-backendA-ALLOWED.txt, mac2-to-backendB-ALLOWED.txt, via-edge-still-works.txt
├── L-ha-failover/  1-normal.txt, 2-backendA-down.txt, 2-nginx-error-log.txt, 2-access-log-retry.txt, 3-backendA-restored.txt
└── M-cutover/      1-before.txt, 2-immediately-after.txt, 3-ttl-countdown.txt, 4-mac2-log-quiet.txt
```
Config bundle: `nginx/lando.conf` (Phase 1), `nginx/lando-phase2.conf`, `nginx/lando-standby.conf`.

---

## Phase 2 Final Report — Mac 2 ke notes

**What changed from Phase 1 (edge):**
- `X-Edge` and `X-Upstream` response headers added (observability for cutover + failover)
- Separate `lando-error.log` at `warn` for upstream failure evidence
- `proxy_next_upstream_tries 2` to bound retries
- Standby edge config (`lando-standby.conf`) on Mac 4 with the same certificate
- Edge IP changed 10.7.21.122 → 10.7.26.218 (DHCP); only DNS record updated, cert unaffected (SAN is name-based)

**Resilience results:** Backend A stopped → 100% requests 200 via B, zero client errors (retry via `proxy_next_upstream`); A restored → round-robin resumed within `fail_timeout` (10s). DNS cutover → clients moved to standby edge after ≤30s TTL; manual flush = instant.

**Remaining SPOF:** Mac 2 edge (single IP). Needs VRRP/keepalived floating IP or health-checked DNS across two edges.

---

## Viva Points — Mac 2

1. **Reverse proxy:** "Client sirf `app.lando.test` → Mac 2 jaanta hai. Backend IPs private hain, nginx ke upstream block mein. Isse hum backends badal sakte hain bina client ko bataye."
2. **TLS termination:** "TLS Mac 2 pe khatam hota hai. Client ↔ Mac 2 encrypted (443), Mac 2 ↔ backends plain HTTP (3001/3002) private LAN pe. Isliye backends ko cert nahi chahiye. Cert ka SAN name-based hai, isliye IP change ya standby edge pe same cert chalta hai."
3. **Passive vs active health check:** "`max_fails=1 fail_timeout=10s` — real request fail hone pe server 10s ke liye skip. `proxy_next_upstream` usi request ko dusre backend pe retry karta hai, client ko error nahi dikhta. Active health check (periodic probe) NGINX Plus / HAProxy mein hota hai."
4. **502 vs 504 vs connection refused:** "502 = nginx tak pahunche, backend ne connection refuse kiya/galat response. 504 = backend ne time pe jawab nahi diya. `curl (7)` = nginx tak hi nahi pahunche."
5. **SPOF:** "Mac 2 abhi bhi SPOF hai. Fix: keepalived + VRRP floating IP, ya do edges DNS mein with health checks. Cloud ALB internally multiple nodes multiple AZ mein chalata hai."
6. **Service isolation:** "pf rule: 3001/3002 pe sirf 10.7.26.218 (Mac 2) allowed. Yeh AWS security group jaisa hai — backend SG sirf ALB SG se traffic allow karta hai."
7. **DNS cutover:** "nginx config change nahi hua, sirf DNS record. TTL decide karta hai kitni der purane edge pe traffic jaayega. Isliye migration se pehle TTL ghatate hain."
