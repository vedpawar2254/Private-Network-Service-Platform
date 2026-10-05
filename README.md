# Private Network Service Platform — Phase 1

A private, cloud-free service platform built on 4 MacBooks over one LAN.
A client requests `https://app.lando.test`; the name is resolved by our own
DNS server, the request travels over HTTPS to an nginx edge, and nginx
load-balances it across two backends. Every layer — DNS, TCP, TLS, HTTP,
load balancing — is proven with `dig`, `curl` and Wireshark.

Team domain: **`lando.test`** (reserved `.test` TLD — private, never public).

## Architecture

```
Client (Mac 1 / Mac 4)
  |- 1. DNS query  UDP :53  -------->  Mac 1  dnsmasq        (private DNS)
  |      answer: app.lando.test = Mac 2 IP
  '- 2. HTTPS      TCP :443 -------->  Mac 2  nginx          (edge: TLS + load balancer)
                                         |- HTTP :3001 ->  Mac 3  Express  (Backend A)
                                         '- HTTP :3002 ->  Mac 4  Express  (Backend B)
```

| Mac | Role | Service | IP | Cloud equivalent |
|-----|------|---------|-----|------------------|
| 1 | Private DNS + client | dnsmasq | 10.7.5.248 | Route 53 private zone |
| 2 | Edge: reverse proxy, TLS, load balancer | nginx | 10.7.21.122 | AWS ALB / CDN edge |
| 3 | Backend A | Node/Express :3001 | 10.7.6.183 | EC2 in target group |
| 4 | Backend B + capture | Node/Express :3002 | 10.7.7.247 | EC2 in target group |

> IPs are from college DHCP and may change each session — see `docs/RUNBOOK.md`.

## Request flow

1. **DNS** — client asks Mac 1 for `app.lando.test`; dnsmasq answers Mac 2's IP (UDP 53).
2. **TCP** — client opens a connection to Mac 2 on port 443.
3. **TLS** — nginx terminates TLS with a cert signed by our own root CA; client trusts the CA.
4. **HTTP/2** — nginx proxies the request over plain HTTP to a backend.
5. **Load balancing** — round-robin across Backend A and B; `X-Backend` header shows which served it.

The client only ever knows the **name** — never the backend IPs.

## Repository layout

```
.
├── README.md
├── dns/dnsmasq.conf          # Mac 1 — private DNS config
├── nginx/lando.conf          # Mac 2 — edge: TLS termination + load balancer
├── certs/rootCA.pem          # public CA trust anchor (private keys are git-ignored)
├── docs/
│   ├── PHASE1-GUIDE.md        # full build guide
│   └── RUNBOOK.md             # team values, session restart, troubleshooting
└── evidence/                 # per-task proof (A–H)
    ├── A-lan/                # IP inventory + pings
    ├── B-dns/                # NXDOMAIN proof + private resolution
    ├── D-loadbalancer/       # A/B round-robin
    └── E-tls/                # full HTTPS verbose (TLS1.3, HTTP/2 200, CA-verified)
```

## Quick verify (from any client with the CA trusted)

```bash
dig app.lando.test +short                                    # -> 10.7.21.122
curl -v https://app.lando.test/api/status                    # TLS1.3, HTTP/2 200, X-Backend
for i in 1 2 3 4 5 6; do curl -si https://app.lando.test/api/status | grep -i x-backend; done  # A B A B A B
```

## Security

Private keys (`*.key`) are **never** committed — see `.gitignore`. Only the public
`rootCA.pem` is shared, so clients can trust certificates our CA signs. Anyone with
`rootCA.key` could mint trusted certs, so it stays on Mac 2 only.
