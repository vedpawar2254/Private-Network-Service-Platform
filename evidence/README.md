# Evidence Index — Phase 2 (Harden & Recover)

Team zone `lando.test` · captured 2026-11-23 on the college LAN.

| Mac | Role | IP |
|-----|------|----|
| Mac 1 | Primary DNS (dnsmasq) + client | `10.7.30.221` |
| Mac 2 | Edge: nginx, TLS, load balancer | `10.7.26.218` |
| Mac 3 | Backend A `:3001` | `10.7.21.122` |
| Mac 4 | Backend B `:3002` + backup DNS + standby edge + client | `10.7.15.167` |

---

## Extension A — Backup DNS resolver → [`I-backup-dns/`](I-backup-dns/)

| File | Shows |
|------|-------|
| `primary-resolution.txt` | Mac 1 answers `app.lando.test` |
| `mac4-backup-dns-local-resolution.txt`, `backup-resolution-mac4.txt` | Mac 4 backup answers the same record |
| **`primary-down-backup-works.txt`** | Mac 1 dnsmasq **stopped** (timeout) → client still resolves via Mac 4 → app returns `HTTP/2 200` |

DNS failure = name does not resolve (`curl (6)`). Application failure = name resolves, connection or HTTP fails (`curl (7)` / `502`).

## Extension B — TTL and controlled record change → [`J-ttl-demo/`](J-ttl-demo/)

| File | Shows |
|------|-------|
| `ttl-30s-record.txt` | `local-ttl=30` visible in the answer |
| `record-change-demo.txt`, `record-changed-to-mac1.txt` | Record changed; client keeps the old answer until the TTL expires; flush applies it at once |

## Extension C — Service isolation (pf) → [`K-isolation/`](K-isolation/)

Rule on each backend: `pass in quick proto tcp from 10.7.26.218 to any port <3001|3002>` then `block in quick ... port <3001|3002>`.

| File | Shows |
|------|-------|
| `before-firewall-mac3.txt`, `laptop1-to-backendA-before-isolation.txt` | Before: a client reaches Backend A directly |
| `after-firewall-mac2-to-backendA-ALLOWED.txt`, `after-firewall-mac2-to-backendB-ALLOWED.txt` | After: **edge (Mac 2) still allowed** → 200 |
| `after-firewall-mac1-to-mac3-BLOCKED.txt`, `after-firewall-mac1-to-mac4-BLOCKED.txt`, `client-mac4-to-backendA-BLOCKED.txt` | After: **clients blocked** → `curl (28)` timeout (pf drops silently) |
| `after-firewall-via-edge-WORKS.txt` | Clients still served through `https://app.lando.test` |
| `mac4-isolation-rollback.txt`, `after-rollback-mac1-direct-WORKS.txt` | Rules flushed, original access restored |

## Extension D — High-availability failover → [`L-ha-failover/`](L-ha-failover/)

nginx passive health check: `max_fails=1 fail_timeout=10s` + `proxy_next_upstream error timeout http_502 http_503`.

| File | Shows |
|------|-------|
| `1-normal.txt` | A B A B A B |
| `2-backendA-down.txt` | Backend A stopped → 6/6 `200`, all B. First request `x-upstream: 10.7.21.122:3001, 10.7.15.167:3002` = tried A, retried on B |
| `2-nginx-error-log.txt` | `connect() failed (61: Connection refused)` for A |
| `2-access-log-retry.txt` | `backend=10.7.21.122:3001, 10.7.15.167:3002 (502, 200)` |
| `3-backendA-restored.txt` | A restarted → after `fail_timeout` round-robin resumes, no nginx restart |

**Remaining single point of failure:** the edge (Mac 2). Fix: two edges + floating IP (VRRP/keepalived), or health-checked DNS across both edges.

## Extension E — DNS-based edge cutover → [`M-cutover/`](M-cutover/)

Standby nginx on Mac 4 (`nginx/lando-standby.conf`, same certificate, header `X-Edge: mac4-standby`).

| File | Shows |
|------|-------|
| `0-standby-ready.txt` | Standby edge serves A/B with a valid cert (no `-k`) |
| `1-before.txt` | DNS → Mac 2, `x-edge: mac2-primary` |
| **`2-ttl-countdown.txt`** | Every 5 s from a client. 12:13:24 DNS changes to Mac 4 but traffic stays on `mac2-primary` (cached) until 12:13:42 → `mac4-standby`. Same effect again on rollback at 12:17 |
| `3-mac2-down-still-works.txt` | Primary edge nginx stopped → still `200` via standby |
| `4-rollback.txt` | DNS back to Mac 2 → `mac2-primary` |

## Extension F — Troubleshooting (live)

Method and fault table: [`docs/PHASE2-MAC2-GUIDE.md`](../docs/PHASE2-MAC2-GUIDE.md#extension-f--troubleshooting-edge-side-faults) and [`docs/RUNBOOK.md`](../docs/RUNBOOK.md). Order: DNS → IP → TCP port → TLS → HTTP status.

---

## Phase 1 evidence (for the final demo sequence)

| Folder | Task |
|--------|------|
| [`A-lan/`](A-lan/) | LAN inventory, pings |
| [`B-dns/`](B-dns/) | Private DNS resolution, NXDOMAIN on public DNS |
| [`C-backends/`](C-backends/) | Both backends direct: `/`, `/api/status`, `X-Backend` |
| [`D-loadbalancer/`](D-loadbalancer/) | Round-robin A/B |
| [`E-tls/`](E-tls/) | `curl -v` TLS handshake + cert validation |
| [`F-caching/`](F-caching/) | `Cache-Control`, `304 Not Modified` |
| [`G-wireshark/`](G-wireshark/) | Packet capture + screenshots |
| [`H-failures/`](H-failures/) | Wrong DNS server (NXDOMAIN, IP still reachable), wrong port (TCP refused) |

Configs: [`dns/dnsmasq.conf`](../dns/dnsmasq.conf) · [`nginx/lando.conf`](../nginx/lando.conf) (Phase 1) · [`nginx/lando-phase2.conf`](../nginx/lando-phase2.conf) · [`nginx/lando-standby.conf`](../nginx/lando-standby.conf) · [`backend/server.js`](../backend/server.js)
