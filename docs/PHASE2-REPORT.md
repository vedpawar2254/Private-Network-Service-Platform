# Phase 2 Final Report — Harden, Recover, Troubleshoot

**Project:** Private Network Service Platform · **Team zone:** `lando.test` · **Date of tests:** 23 Nov 2026
**Evidence index:** [`evidence/README.md`](../evidence/README.md)

## 1. Final topology

| Mac | Phase 1 role | Added in Phase 2 | IP |
|-----|--------------|------------------|----|
| Mac 1 | Primary DNS (dnsmasq) + client | TTL 30 s, query logging | `10.7.30.221` |
| Mac 2 | nginx edge: TLS termination + round-robin LB | Failover tuning, `X-Edge` / `X-Upstream` headers | `10.7.26.218` |
| Mac 3 | Backend A `:3001` | pf isolation rule | `10.7.21.122` |
| Mac 4 | Backend B `:3002` + client | Backup DNS, standby edge, pf isolation rule | `10.7.15.167` |

Request path: client → DNS (Mac 1, backup Mac 4) → HTTPS `:443` to the edge (Mac 2, standby Mac 4) → plain HTTP to Backend A or B.

## 2. What changed from Phase 1

**DNS (Mac 1).** `local-ttl` lowered to 30 s so cache expiry is visible in a demo. `log-queries` added for live query logs.

**Backup DNS (Mac 4).** Second dnsmasq with the same records. Every client now lists Mac 1 first and Mac 4 second.

**Edge (Mac 2): [`nginx/lando-phase2.conf`](../nginx/lando-phase2.conf)**
- `X-Edge: mac2-primary` response header, so a client can see which edge served it.
- `X-Upstream: $upstream_addr` response header, so a client can see which backend was tried.
- A separate `lando-error.log` at `warn` level records upstream failures.
- `proxy_next_upstream_tries 2` bounds retries.
- Kept from Phase 1: `max_fails=1 fail_timeout=10s`, `proxy_connect_timeout 2s`, `proxy_next_upstream error timeout http_502 http_503`.

**Standby edge (Mac 4): [`nginx/lando-standby.conf`](../nginx/lando-standby.conf)**
- Same config and the same certificate as Mac 2, with `X-Edge: mac4-standby`.
- The certificate SAN is name-based (`DNS:app.lando.test, DNS:api.lando.test`), so it stays valid on any IP.

**Backends (Mac 3, Mac 4).** pf anchor `com.apple/cn-isolation` allows TCP to `3001`/`3002` only from `10.7.26.218` (the edge) and drops everything else.

**Operational change.** College DHCP reassigned three of the four IPs during the session. Mac 2's old IP went to Mac 3. We updated only the DNS records and the nginx `upstream` block. No certificate was reissued, because the SAN carries no IP.

## 3. Resilience tests and results

| # | Test | Expected | Observed | Result | Evidence |
|---|------|----------|----------|--------|----------|
| A | Stop primary DNS (Mac 1) | Clients resolve via backup | `dig @Mac1` timed out. The client resolver returned `10.7.26.218` from Mac 4, and the app returned `HTTP/2 200` | ✅ | `I-backup-dns/primary-down-backup-works.txt` |
| B | Change record with TTL 30 | Old answer until TTL expiry; flush applies it at once | Authoritative answer changed immediately. Clients kept the cached answer: about 18 s on a live client (see E) | ✅ | `J-ttl-demo/`, `M-cutover/2-ttl-countdown.txt` |
| C | Restrict backend ports to the edge | Edge allowed, clients blocked | Mac 2 got `200` from both backends directly. Mac 1 and Mac 4 got `curl (28)` timeouts. Service via `https://app.lando.test` unaffected. Rules flushed afterwards and direct access restored | ✅ | `K-isolation/` |
| D1 | Stop Backend A | All requests served by B, no client errors | 6/6 `200` from B. The first request shows `x-upstream: A, B` and the access log shows `(502, 200)`: nginx tried A, got connection refused, and retried the same request on B | ✅ | `L-ha-failover/2-*` |
| D2 | Restart Backend A | Round-robin resumes without an nginx restart | `B B A B A B`: A was still skipped for the rest of `fail_timeout`, then rejoined | ✅ | `L-ha-failover/3-backendA-restored.txt` |
| E1 | Cut DNS over to the standby edge | Cached clients stay on the old edge, then move | 12:13:24 DNS → Mac 4, still `mac2-primary`. 12:13:42 → `mac4-standby` | ✅ | `M-cutover/2-ttl-countdown.txt` |
| E2 | Stop primary edge after cutover | Service continues | Mac 2 `:443` refused, client got `200` via `mac4-standby` | ✅ | `M-cutover/3-mac2-down-still-works.txt` |
| E3 | Roll back | Traffic returns to Mac 2 after TTL | Same cache lag in reverse, then `mac2-primary` | ✅ | `M-cutover/4-rollback.txt` |

## 4. Troubleshooting findings (real faults met during the session)

All faults below were found with the same order of checks: DNS → IP reachability → TCP port → TLS → HTTP status.

| Symptom | Layer check that isolated it | Root cause | Fix |
|---------|------------------------------|------------|-----|
| `502`, nginx log `no live upstreams` | `nc` to backend: *Connection refused* on Mac 3, *timeout* on Mac 4 | DHCP changed IPs. `10.7.6.183` now belonged to another device, and Mac 4 had moved | Found the new IPs, updated `upstream`, ran `nginx -s reload` |
| Name resolved to the wrong host | `dig @Mac1` returned Mac 1's own IP | Record left changed after the TTL demo | Restored `host-record` |
| Backend timeouts and ping failures, then recovery | Repeated `nc` sampling every 2 s: drops on two Macs, the DNS Mac stable | Laptops sleeping / Wi-Fi idle | `caffeinate -dims` on every Mac |
| pf rules "not working" | `pfctl -a … -s rules` → `DIOCGETRULES: Invalid argument` | Anchor never loaded | Reloaded the anchor, confirmed both rules listed |
| Standby edge `curl (7)` although `brew services` said *started* | `lsof -iTCP:443` empty on Mac 4 | A stale nginx process blocked the root service | Stopped all nginx instances, started only the root service |
| Site down during the cutover rehearsal | `dig` → standby IP, `nc` standby `:443` closed | DNS switched before the standby nginx was up | Rolled back the record, then started the standby first |

Two failure modes are also captured as Phase 1 evidence (`H-failures/`):
- **Wrong DNS server:** `8.8.8.8` returns NXDOMAIN while the edge still answers ping, so naming and IP connectivity are independent.
- **Wrong port:** `8443` is refused while `443` returns `200`, so a port identifies a service separately from the host.

Lesson: **timeout and refused mean different things.** *Refused* means the host is up but nothing listens on that port. *Timeout* means the packet was dropped, by a firewall or because the host is gone.

## 5. Learning summary

**Extension A — Backup DNS.** A resolver list makes DNS redundant at the client, without any change on the servers. When Mac 1 stopped, the macOS resolver moved to Mac 4 and the application kept working. A DNS failure shows up before any connection is attempted (`curl (6)`). An application failure shows up after resolution, as a TCP or HTTP error (`curl (7)`, `502`). Telling the two apart is the first step in diagnosis.

**Extension B — TTL.** TTL is a promise about how long an answer may be reused. It controls how fast a change propagates, not whether it propagates. Changing the record updated the server at once, but clients followed only after their cache expired. A manual flush skipped the wait. In production, teams lower the TTL well before a migration, so that the cutover itself is fast.

**Extension C — Service isolation.** With a pf rule that allows only the edge's IP, the backends are reachable only through nginx. Knowing a backend's IP no longer helps a client. Blocked clients see a timeout, not a refusal, because pf drops packets silently. This is the same pattern as a cloud security group that accepts traffic only from the load balancer's group. Keeping the rules in their own anchor let us flush them cleanly without touching the system ruleset.

**Extension D — HA failover.** Open-source nginx uses passive health checks. A real request that fails marks the server down for `fail_timeout`, and `proxy_next_upstream` retries that same request on the other server, so the client never sees the failure, only a slower response (1.1 s vs ~0.02 s). Recovery is automatic: after `fail_timeout` nginx probes the server with the next real request. Active probing would need NGINX Plus or HAProxy. **Mac 2 is still a single point of failure:** removing it needs two edges sharing a floating IP (VRRP/keepalived), or health-checked DNS across both edges.

**Extension E — DNS-based edge cutover.** Moving traffic to the standby edge needed only a DNS change, with no nginx restart. The capture shows the cost of DNS-based cutover: about 18 s during which clients still used the old edge, because of cached answers. That is why the old edge must stay up until its access log goes quiet, and only then be stopped. Reusing one name-based certificate on both edges made the cutover invisible to TLS.

**Extension F — Troubleshooting method.** Most of our time went to faults we did not plan: IPs reassigned by DHCP, sleeping laptops, a pf anchor that never loaded, and a service reported as started that was not listening. Each was found quickly by checking the layers in order and reading the exact error (`(6)`, `(7)`, `(28)`, `502`, `DIOCGETRULES`) instead of guessing.

## 6. Open items

- **Wireshark (Task G):** the current `G-wireshark/full-flow-mac4.pcap` and its screenshots contain unrelated Internet traffic and no `app.lando.test` flow. It must be re-captured with the project filter before the final demo.
- **Phase 1 failure captures not yet recorded:** both backends down (`502`), and edge stopped (`curl (7)`). Both are quick to demonstrate live.
