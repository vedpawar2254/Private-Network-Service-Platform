# Runbook — session start, IP changes, troubleshooting

## Team values

| Placeholder | Meaning | Value |
|-------------|---------|-------|
| domain | team zone | `lando.test` |
| DNS_IP | Mac 1 | `10.7.5.248` |
| EDGE_IP | Mac 2 | `10.7.21.122` |
| A_IP | Mac 3 (Backend A) | `10.7.6.183` |
| B_IP | Mac 4 (Backend B) | `10.7.7.247` |

## Every session: restart + IP check

College DHCP can hand out new IPs. Start every session with this.

**1. Check IPs on all 4 Macs:** `ipconfig getifaddr en0`

**2. If one changed:**

| Changed | Fix |
|---------|-----|
| Edge (Mac 2) | Mac 1: update both `host-record` lines in `dns/dnsmasq.conf` → `sudo brew services restart dnsmasq`; clients flush cache |
| A/B backend | Mac 2: update the `upstream` block → `sudo nginx -t && sudo brew services restart nginx` |
| DNS (Mac 1) | Each client: `sudo networksetup -setdnsservers Wi-Fi <new IP>` |

**3. Restart what does not survive sleep:**

| Survives | Must restart |
|----------|--------------|
| dnsmasq, nginx (brew services), client DNS, trusted CA, configs | both `node server.js` backends; `caffeinate -dims` on Mac 1 and Mac 2 |

**4. One test checks everything (any client):**
```bash
for i in 1 2 3 4; do curl -si https://app.lando.test/api/status | grep -i x-backend; done
```
A and B alternating = DNS, TCP, TLS, nginx and both backends are up.

## Keep DNS alive

Mac 1 is a single point of failure for name resolution. Leave a tab running:
```bash
caffeinate -dims
```
If Mac 1 sleeps, every client loses DNS.

## Troubleshooting (bottom-up)

| # | Check | Command | If it fails |
|---|-------|---------|-------------|
| 1 | Name resolution | `dig app.lando.test +short` | DNS: Mac 1 awake? dnsmasq running? client resolver set? |
| 2 | IP reachability | `ping -c 2 10.7.21.122` | Network: same Wi-Fi? IP changed? firewall stealth mode? |
| 3 | TCP port | `nc -vz 10.7.21.122 443` | nginx not running / wrong port |
| 4 | TLS | `curl -v https://app.lando.test` | cert / CA trust / SAN problem |
| 5 | Application | look for `502` | backends down or upstream IP wrong |

curl error codes: `(6)` = DNS · `(7)` = TCP · `SSL certificate problem` = TLS · `502` = backend.

## Trust the CA on a new client

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain certs/rootCA.pem
```
