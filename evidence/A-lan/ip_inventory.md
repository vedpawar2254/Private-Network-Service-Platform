# Task A: Network & IP Inventory — Team LANdo

## Team Details
- **Team Name**: `LANdo`
- **Private Domain**: `lando.test` (`app.lando.test`, `api.lando.test`)
- **Network SSID**: `Rishihood_Learner`
- **Subnet Mask**: `255.255.224.0` (/19)
- **Default Gateway**: `10.7.0.1`

## Machine Inventory

| Machine | Role | Hostname / Owner | IP Address | Subnet Mask / CIDR | Gateway | Interface | MAC Address (Ether) | Service Port |
|---|---|---|---|---|---|---|---|---|
| **Mac 1** | Private DNS (dnsmasq) | Teammate 1 | **`10.7.5.248`** | `255.255.224.0` (/19) | `10.7.0.1` | `en0` | `7a:ed:a5:e2:d8:4c` | 53 (UDP) |
| **Mac 2** | Edge: Nginx + TLS + LB | Teammate 2 | **`10.7.21.122`** | `255.255.224.0` (/19) | `10.7.0.1` | `en0` | `52:01:cf:b4:e1:ba` | 80, 443 |
| **Mac 3** | Backend A | Teammate 3 | **`10.7.6.183`** | `255.255.224.0` (/19) | `10.7.0.1` | `en0` | `46:8b:9c:ce:33:ac` | 3001 |
| **Mac 4** | **Backend B + Capture Client** | **Aviral Mishra** | **`10.7.7.247`** | **`255.255.224.0` (/19)** | **`10.7.0.1`** | **`en0`** | **`6a:5f:a6:ec:a9:39`** | **3002** |

## Layer 2 Direct Connectivity
All 4 Macs communicate on the same layer-2 broadcast domain (`/19` covering `10.7.0.0` to `10.7.31.255`).
All ICMP echo replies have `ttl=64`, proving 0 intermediate router hops.
Evidence log: `evidence/A-lan/ping_results.txt`.
