# LANdo Private Network Service

## Machine inventory

| Laptop | Role | IP address | Service |
|---|---|---|---|
| 1 | Private DNS | `10.7.30.221` | dnsmasq, UDP/TCP 53 |
| 2 | Edge / load balancer | `10.7.26.218` | nginx, HTTP 80 and HTTPS 443 |
| 3 | Backend A | `10.7.21.122` | Node/Express, TCP 3001 |
| 4 | Backend B | `10.7.7.247` | Node/Express, TCP 3002 |

Laptop 1 network details: subnet mask `255.255.224.0` (`/19`), gateway `10.7.0.1`, interface `en0`, MAC `7a:ed:a5:e2:d8:4c`.

The IPs are DHCP addresses and may change. Recheck each laptop with `ipconfig getifaddr en0` at the start of a session; update the DNS or nginx config if an address changed. DNS is configured for `app.lando.test` and `api.lando.test` and sends both names to Laptop 2.

## Config files

- `dns/LANdo.conf`: install on Laptop 1 as the dnsmasq configuration.
- `nginx/LANdo.conf`: install on Laptop 2 after creating and installing the TLS certificate for `app.lando.test` and `api.lando.test` using Step 9 of `CN-Project-Phase1-Guide.md`. Set `TEAM=lando` (lowercase) in that step so the certificate SANs match these hostnames.
- `backend/`: install dependencies and run on Laptops 3 and 4.

On Laptop 1, copy `dns/LANdo.conf` to `$(brew --prefix)/etc/dnsmasq.conf`, run the dnsmasq syntax check from the guide, then start/restart dnsmasq.

On Laptop 2, copy `nginx/LANdo.conf` to `$(brew --prefix)/etc/nginx/servers/LANdo.conf`, make sure its certificate and key are installed at `/opt/homebrew/etc/nginx/certs/server.crt` and `/opt/homebrew/etc/nginx/certs/server.key`, then run `sudo nginx -t` and restart nginx. On an Intel Mac whose Homebrew prefix is `/usr/local`, change the two certificate paths in the nginx config to match.

On both backend laptops, run `npm install` in `backend/`. Start Laptop 3 with `npm start`; start Laptop 4 with `npm run start:backend-b`. Keep each server terminal open.

## Phase 2: Harden, Recover & Troubleshoot (Laptop 3 Setup)

For Phase 2, Laptop 3 (Backend Server A) is configured for:
1. **Extension C: Service Isolation (macOS PF Firewall)**
   - Only allow Edge (Laptop 2: `10.7.26.218`) and localhost to port 3001.
   - Block all other incoming client connections.
   - Enable: `./firewall/enable-isolation-laptop3.sh`
   - Check status: `./firewall/status-isolation-laptop3.sh`
   - Disable / Rollback: `./firewall/disable-isolation-laptop3.sh`
2. **Extension D: High-Availability Failover**
   - Start backend: `./backend/start-backend-a.sh`
   - Stop backend: `./backend/stop-backend-a.sh` (demonstrates automatic failover to Backend B on Laptop 4).
3. **Extension E & A (Standby Edge / Backup DNS)**
   - Standby edge config: `nginx/standby-edge-laptop3.conf`
   - Backup DNS config: `dns/LANdo-backup-laptop3.conf`

See [CN-Project-Phase2-Laptop3-Guide.md](file:///Users/adityarajpal/Desktop/cnproject/CN-Project-Phase2-Laptop3-Guide.md) for full commands, testing steps, Wireshark instructions, and viva questions.

## Checks

From Laptop 1:

```bash
dig @127.0.0.1 app.lando.test +short
```

From Laptop 2, check each backend directly:

```bash
curl -i http://10.7.21.122:3001/api/status
curl -i http://10.7.7.247:3002/api/status
```

From a client with Laptop 1 configured as its DNS resolver:

```bash
curl -i https://app.lando.test/api/status
```

Expected: DNS returns `10.7.26.218`; backend checks return `X-Backend: A` and `X-Backend: B`; the HTTPS response returns either backend header.