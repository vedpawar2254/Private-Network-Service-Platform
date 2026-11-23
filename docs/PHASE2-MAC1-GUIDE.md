# Phase 2 — Mac 1 (Private DNS Server) Complete Guide
**Harden · Recover · Troubleshoot**

> Mac 1 role: **Primary DNS Server + Test Client**
> Domain: `lando.test` | Mac 1 IP: `10.7.5.248` | Edge (Mac 2): `10.7.21.122`
> Backend A (Mac 3): `10.7.6.183` | Backend B (Mac 4): `10.7.7.247`

---

## Mac 1 ka Phase 2 mein kya kaam hai?

| Extension | Mac 1 kya karta hai |
|-----------|---------------------|
| **A — Backup DNS** | Primary dnsmasq configure karta hai; backup DNS verify karta hai |
| **B — TTL + Record Change** | dnsmasq config mein TTL set karta hai; record change demonstrate karta hai |
| **C — Service Isolation** | Client ban ke firewall test karta hai (Mac 3/4 par direct connect try karta hai) |
| **D — HA Failover** | Client ban ke backend fail hone par test karta hai |
| **E — DNS Cutover** | Edge IP record mein change karta hai (standby edge ke liye) |
| **F — Troubleshooting** | Layer-by-layer diagnosis methodology follow karta hai |

---

## Session Start — Har baar yeh pehle karo

```bash
# Step 1: Apna current IP check karo
ipconfig getifaddr en0

# Step 2: Baaki Macs tak ping karo
ping -c 3 10.7.21.122   # Mac 2 (Edge)
ping -c 3 10.7.6.183    # Mac 3 (Backend A)
ping -c 3 10.7.7.247    # Mac 4 (Backend B)

# Step 3: dnsmasq running hai ya nahi check karo
sudo brew services list | grep dnsmasq

# Step 4: Agar band hai toh start karo
sudo brew services start dnsmasq

# Step 5: Caffeinate — Mac 1 ko sleep mat karne do (tab khuli rakhni hai)
caffeinate -dims
```

> **⚠️ Important:** Agar Mac 1 IP change hua hai toh Mac 4 pe ja ke:
> `sudo networksetup -setdnsservers Wi-Fi <naya Mac 1 IP>`

---

## Extension A — Backup DNS Resolver

**Goal:** Dusre Mac pe second dnsmasq chalana jisme wahi records hon. Mac 1 band karo → clients ka DNS tab bhi kaam kare.

### A.1 — Primary DNS config ko TTL 30s ke saath update karo (Extension B ke liye bhi)

```bash
# Current config backup
cp $(brew --prefix)/etc/dnsmasq.conf $(brew --prefix)/etc/dnsmasq.conf.backup-phase1

# Naya config likhna — TTL ab 30 seconds (visible aur fast expiry ke liye)
cat > $(brew --prefix)/etc/dnsmasq.conf << 'EOF'
# ---- Team DNS (Mac 1) — Phase 2 ----
no-resolv
server=8.8.8.8
server=1.1.1.1

# Our zone
local=/lando.test/

# A records → edge (Mac 2)
host-record=app.lando.test,10.7.21.122
host-record=api.lando.test,10.7.21.122

# Phase 2: Short TTL so we can demonstrate TTL expiry easily
local-ttl=30

# Log every query
log-queries
log-facility=/tmp/dnsmasq.log
EOF

# Syntax check
$(brew --prefix)/sbin/dnsmasq --test --conf-file=$(brew --prefix)/etc/dnsmasq.conf

# Restart
sudo brew services restart dnsmasq

# Verify
dig @127.0.0.1 app.lando.test +short    # should return 10.7.21.122
dig @127.0.0.1 app.lando.test           # TTL column mein 30 dikhna chahiye
```

### A.2 — Backup DNS verify karna (Mac 4 pe backup dnsmasq chalega)

> **Mac 4 pe yeh kaam hoga** (doosre laptop pe):
> ```bash
> # Mac 4 pe: same dnsmasq config copy karke install karna
> brew install dnsmasq
> # config copy aur start (Mac 4 wala apni machine pe karega)
> ```

### A.3 — Mac 1 se Backup DNS test karo

```bash
# Mac 4 IP par backup resolver test karo (Mac 4 ne dnsmasq start kar liya hai toh)
dig @10.7.7.247 app.lando.test +short    # should return 10.7.21.122

# Ab Mac 1 ka dnsmasq band karo (failover demo ke liye)
sudo brew services stop dnsmasq

# Mac 4 (ya kisi client) se check karo — backup se resolve ho raha hai?
# (Mac 4 pe ja ke verify karo ya Mac 1 se agar dual DNS set hai)

# WAPAS start karo — demo ke baad
sudo brew services start dnsmasq
```

### A.4 — Evidence collect karo

```bash
mkdir -p /Users/vedpawar2254/Developer/NewtonP/CN_project/evidence/I-backup-dns

# Primary DNS se resolution
dig @127.0.0.1 app.lando.test > /Users/vedpawar2254/Developer/NewtonP/CN_project/evidence/I-backup-dns/primary-resolution.txt

# Backup DNS se resolution (Mac 4 IP)
dig @10.7.7.247 app.lando.test > /Users/vedpawar2254/Developer/NewtonP/CN_project/evidence/I-backup-dns/backup-resolution.txt

# dnsmasq service status
sudo brew services list | grep dnsmasq >> /Users/vedpawar2254/Developer/NewtonP/CN_project/evidence/I-backup-dns/service-status.txt
```

---

## Extension B — DNS TTL and Controlled Record Change

**Goal:** Short TTL set karo. Record change karo. Client pehle purana answer deta hai (cached), TTL expire hone ke baad naya answer milta hai.

### B.1 — TTL check karo (30s set hai Extension A se)

```bash
# TTL column mein 30 dikhna chahiye
dig @127.0.0.1 app.lando.test
# ;; ANSWER SECTION:
# app.lando.test.  30  IN  A  10.7.21.122
#                  ^^
#                  yeh TTL hai
```

### B.2 — Record change demo (Mac 1 IP par temporarily point karo)

```bash
# Step 1: Note karo current time
date

# Step 2: Config mein app record change karo (Mac 1 IP pe temporarily)
sudo sed -i '' 's/host-record=app.lando.test,10.7.21.122/host-record=app.lando.test,10.7.5.248/' $(brew --prefix)/etc/dnsmasq.conf

# Step 3: dnsmasq restart
sudo brew services restart dnsmasq

# Step 4: Immediately query karo — agar client ne cache kiya hai toh purana IP milega
dig app.lando.test +short               # client cache hai toh purana (10.7.21.122) milega
dig @127.0.0.1 app.lando.test +short    # DNS server pe new record (10.7.5.248) milega

# Step 5: 30 seconds wait karo (TTL expire)
echo "30 seconds wait karo TTL expire ke liye..."; sleep 30

# Step 6: Ab naya answer milega
dig app.lando.test +short          # ab 10.7.5.248 milega (naya record)

# Step 7: Cache manually flush karo
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
dig app.lando.test +short          # turant naya answer milega

# Step 8: Original record wapas karo
sudo sed -i '' 's/host-record=app.lando.test,10.7.5.248/host-record=app.lando.test,10.7.21.122/' $(brew --prefix)/etc/dnsmasq.conf
sudo brew services restart dnsmasq

# Verify restoration
dig @127.0.0.1 app.lando.test +short    # wapas 10.7.21.122
```

### B.3 — Evidence collect karo

```bash
mkdir -p /Users/vedpawar2254/Developer/NewtonP/CN_project/evidence/J-ttl-demo

# TTL visible dig output save karo
dig @127.0.0.1 app.lando.test > /Users/vedpawar2254/Developer/NewtonP/CN_project/evidence/J-ttl-demo/ttl-30s-record.txt
cat /Users/vedpawar2254/Developer/NewtonP/CN_project/evidence/J-ttl-demo/ttl-30s-record.txt
```

---

## Extension C — Service Isolation (Firewall) — Client Test

**Goal:** Mac 3 aur Mac 4 ke ports 3001/3002 par sirf Mac 2 (nginx) pahunch sakta hai. Mac 1 direct connect nahi kar sakta.

> **Firewall rules Mac 3 aur Mac 4 pe lagenge** (unke laptops pe). Mac 1 ka kaam sirf **test client** banna hai.

### C.1 — Before firewall: direct access check karo

```bash
mkdir -p /Users/vedpawar2254/Developer/NewtonP/CN_project/evidence/K-isolation

# Mac 1 se Mac 3 ke backend directly try karo
curl -i http://10.7.6.183:3001/api/status      # should WORK (before firewall)
curl -i http://10.7.7.247:3002/api/status      # should WORK (before firewall)

# Save as "before" evidence
curl -i http://10.7.6.183:3001/api/status > /Users/vedpawar2254/Developer/NewtonP/CN_project/evidence/K-isolation/before-firewall-mac3.txt 2>&1
curl -i http://10.7.7.247:3002/api/status > /Users/vedpawar2254/Developer/NewtonP/CN_project/evidence/K-isolation/before-firewall-mac4.txt 2>&1
```

### C.2 — After firewall (Mac 3/4 ne rules laga diye): same test

```bash
# Mac 3/4 ne firewall rules laga diye — ab yahi commands fail karni chahiye
curl -i --connect-timeout 5 http://10.7.6.183:3001/api/status     # should FAIL
curl -i --connect-timeout 5 http://10.7.7.247:3002/api/status     # should FAIL

# But domain name se through nginx — still works
curl -i https://app.lando.test/api/status      # should still WORK (via Mac 2)

# Save as "after" evidence
curl -i --connect-timeout 5 http://10.7.6.183:3001/api/status > /Users/vedpawar2254/Developer/NewtonP/CN_project/evidence/K-isolation/after-firewall-mac3-BLOCKED.txt 2>&1
curl -i https://app.lando.test/api/status > /Users/vedpawar2254/Developer/NewtonP/CN_project/evidence/K-isolation/after-firewall-via-nginx-WORKS.txt 2>&1
```

---

## Extension D — High Availability Failover

**Goal:** Backend A band karo → sirf Backend B serve kare. Restart karo → phir A aur B alternate kare.

### D.1 — Normal operation verify karo

```bash
# A aur B alternate kar rahe hain
for i in 1 2 3 4 5 6; do curl -si https://app.lando.test/api/status | grep -i x-backend; done
# Expected: A B A B A B
```

### D.2 — Backend A fail karo (Mac 3 wala Ctrl+C karega)

```bash
# Mac 3 wale apna server band karenge — phir test karo
for i in 1 2 3 4 5 6; do curl -si https://app.lando.test/api/status | grep -i x-backend; done
# Expected: B B B B B B  (sirf B serve karega)

# Service abhi bhi up hai
curl -si https://app.lando.test/api/status | head -5    # should return 200
```

### D.3 — Backend A restart karo (Mac 3 wala server chalayega)

```bash
# 15 seconds baad (fail_timeout = 10s nginx mein)
sleep 15
for i in 1 2 3 4 5 6; do curl -si https://app.lando.test/api/status | grep -i x-backend; done
# Expected: A B A B A B  (wapas alternating)

# Evidence save karo
mkdir -p /Users/vedpawar2254/Developer/NewtonP/CN_project/evidence/L-ha-failover
for i in 1 2 3 4 5 6; do curl -si https://app.lando.test/api/status | grep -i x-backend; done > /Users/vedpawar2254/Developer/NewtonP/CN_project/evidence/L-ha-failover/after-restart-both-backends.txt
```

---

## Extension E — DNS-Based Edge Cutover (Standby Edge)

**Goal:** `app.lando.test` ka DNS record change karo — primary edge (Mac 2) se standby edge pe point karo. TTL effects observe karo.

> **Pehle Mac 3 ya Mac 4 pe nginx install aur configure hona chahiye** (unka kaam). Mac 1 ka kaam sirf DNS record change karna hai.

### E.1 — Standby edge IP confirm karo

```bash
# Suppose standby edge Mac 4 pe hai at 10.7.7.247
# (ya Mac 3 pe — jo bhi team ne configure kiya)
# Verify standby nginx accessible hai
curl --connect-timeout 5 https://10.7.7.247/api/status -k 2>&1 | head -5
```

### E.2 — DNS record change (cutover to standby)

```bash
mkdir -p /Users/vedpawar2254/Developer/NewtonP/CN_project/evidence/M-cutover

# Step 1: Current state save karo
dig @127.0.0.1 app.lando.test > /Users/vedpawar2254/Developer/NewtonP/CN_project/evidence/M-cutover/before-cutover.txt

# Step 2: Config change — app.lando.test ab standby edge pe point karo (eg Mac 4)
sudo sed -i '' 's/host-record=app.lando.test,10.7.21.122/host-record=app.lando.test,10.7.7.247/' $(brew --prefix)/etc/dnsmasq.conf
sudo brew services restart dnsmasq

# Step 3: Verify — DNS server pe naya record
dig @127.0.0.1 app.lando.test +short    # 10.7.7.247

# Step 4: Client cache abhi purana IP de raha hoga (TTL 30s)
dig app.lando.test +short               # purana (10.7.21.122) — cached

# Step 5: 30 sec baad ya cache flush karke
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
dig app.lando.test +short               # naya (10.7.7.247)

# Step 6: Save cutover evidence
dig @127.0.0.1 app.lando.test > /Users/vedpawar2254/Developer/NewtonP/CN_project/evidence/M-cutover/after-cutover-dns.txt

# Step 7: Rollback — original edge wapas (Mac 2)
sudo sed -i '' 's/host-record=app.lando.test,10.7.7.247/host-record=app.lando.test,10.7.21.122/' $(brew --prefix)/etc/dnsmasq.conf
sudo brew services restart dnsmasq
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
dig @127.0.0.1 app.lando.test +short    # wapas 10.7.21.122
```

---

## Extension F — Troubleshooting Challenge (Layer-by-Layer Diagnosis)

Jab faculty koi fault inject kare, **is sequence mein diagnose karo** — bottom-up:

```bash
# LAYER 1: DNS — name resolve ho raha hai?
dig app.lando.test +short
# - Kuch nahi mila / NXDOMAIN → DNS problem
# - IP mila → DNS theek hai, aage badho

# LAYER 2: IP Reachability — machine tak pahunch sakte hain?
ping -c 3 10.7.21.122
# - Timeout → Network/firewall problem
# - 64 bytes → IP OK, aage badho

# LAYER 3: TCP Port — nginx sun raha hai?
nc -vz 10.7.21.122 443
# - Connection refused → nginx band hai ya wrong port
# - Succeeded → TCP OK, aage badho

# LAYER 4: TLS — certificate theek hai?
curl -v https://app.lando.test/api/status 2>&1 | grep -iE "SSL|certificate|TLS|error"
# - SSL certificate problem → CA trust ya cert issue
# - Connected → TLS OK, aage badho

# LAYER 5: Application — backend se response aa raha hai?
curl -si https://app.lando.test/api/status | head -5
# - 502 Bad Gateway → backends down
# - 200 OK → sab theek hai
```

### Common Faults aur Diagnosis

| Fault | dig result | ping result | nc result | curl result |
|-------|-----------|-------------|-----------|-------------|
| dnsmasq band | NXDOMAIN | ✅ works | ✅ works | (6) Cannot resolve |
| Wrong DNS record | Wrong IP | ✅ works | ❌ refused | (7) Connection refused |
| nginx band | ✅ correct IP | ✅ works | ❌ refused | (7) Connection refused |
| Backend down | ✅ correct IP | ✅ works | ✅ works | 502 Bad Gateway |
| Wrong CA cert | ✅ correct IP | ✅ works | ✅ works | SSL certificate problem |
| Wrong port | ✅ correct IP | ✅ works | ❌ refused | (7) Failed to connect |

---

## Dnsmasq Config — Quick Reference

```bash
# Config file location
$(brew --prefix)/etc/dnsmasq.conf
# Usually: /opt/homebrew/etc/dnsmasq.conf

# Syntax check
$(brew --prefix)/sbin/dnsmasq --test --conf-file=$(brew --prefix)/etc/dnsmasq.conf

# Start / Stop / Restart
sudo brew services start dnsmasq
sudo brew services stop dnsmasq
sudo brew services restart dnsmasq

# Status
sudo brew services list | grep dnsmasq

# Live logs dekho
tail -f /tmp/dnsmasq.log

# Client DNS settings
sudo networksetup -getdnsservers Wi-Fi
sudo networksetup -setdnsservers Wi-Fi 10.7.5.248 10.7.7.247   # primary + backup
sudo networksetup -setdnsservers Wi-Fi empty                    # restore default

# Cache flush
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

---

## Evidence Folders — Phase 2 (Mac 1)

```
evidence/
├── I-backup-dns/        ← Extension A
│   ├── primary-resolution.txt
│   ├── backup-resolution.txt
│   └── service-status.txt
├── J-ttl-demo/          ← Extension B
│   └── ttl-30s-record.txt
├── K-isolation/         ← Extension C (client test from Mac 1)
│   ├── before-firewall-mac3.txt
│   ├── after-firewall-mac3-BLOCKED.txt
│   └── after-firewall-via-nginx-WORKS.txt
├── L-ha-failover/       ← Extension D
│   └── after-restart-both-backends.txt
└── M-cutover/           ← Extension E
    ├── before-cutover.txt
    └── after-cutover-dns.txt
```

---

## Phase 2 Final Report ke liye Notes (Mac 1 perspective)

**What changed from Phase 1:**
- `local-ttl` changed from 60s to 30s for visible TTL demonstration
- Logging added to `/tmp/dnsmasq.log` for real-time query monitoring
- Backup DNS resolver configured on Mac 4 (same records, secondary resolver)
- Client Macs now have dual DNS: primary Mac 1, secondary Mac 4

**Resilience tests results:**
- Primary DNS (Mac 1) stopped → clients continued resolving via Mac 4 backup ✅
- TTL expiry: clients cached old record for 30s, then picked up changed record ✅
- DNS cutover to standby edge: TTL-based traffic migration demonstrated ✅

**Single Point of Failure identified:**
- Mac 2 (nginx edge) is still a SPOF — both DNS servers point to same edge IP
- To eliminate: would need a second nginx + a VIP/floating IP or DNS round-robin to both edges

---

## Viva Points — Phase 2 (Mac 1 ke liye)

1. **Backup DNS:** "Humne Mac 4 pe bhi dnsmasq chalaya — same records. Client Macs ko do DNS server bataye. Jab Mac 1 band hua, Mac 4 ke through resolution continue hua. DNS fail hone aur application fail hone mein fark hai — DNS fail mein NXDOMAIN milta hai, application fail mein TCP/HTTP error milta hai."

2. **TTL:** "TTL batata hai kitne seconds tak client apna cached answer use karega. 30 second ke baad record change dikhne laga. Production mein migration se pehle TTL kam karte hain taaki cutover fast ho."

3. **DNS vs Service failure:** "DNS fail = name resolve nahi hota (NXDOMAIN/timeout). Service fail = DNS resolve ho jata hai lekin connection fail hota hai (TCP refused ya 502 Bad Gateway)."

4. **DNS Cutover:** "Sirf DNS record change kiya — no downtime, no nginx restart needed. TTL expire hone ke baad traffic automatically new edge pe gaya. Yeh production mein blue-green deployment ya canary release ke liye use hota hai."

5. **SPOF:** "Mac 1 (DNS) ka SPOF Extension A ne solve kiya — backup resolver hai. Mac 2 (edge nginx) abhi bhi SPOF hai — isko solve karne ke liye VRRP ya keepalived se floating IP chahiye hoga, ya do edge Macs pe DNS round-robin."

6. **Service Isolation:** "Backend ports (3001, 3002) sirf Mac 2 ke liye accessible hain. Direct client access blocked. Yeh real production mein security groups ya VPC settings se karte hain — koi bhi client backend bypass karke directly nahi pahunch sakta."
