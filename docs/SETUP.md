# System Setup Guide — Team LANdo

## 1. Network Topology & Roles

| Host | Assigned Role | Platform Services | IP Address | Port(s) |
|---|---|---|---|---|
| **Mac 1** | Private DNS Server | `dnsmasq` | `10.7.5.248` | `53/UDP` |
| **Mac 2** | Edge Reverse Proxy & Load Balancer | `nginx`, OpenSSL (TLS termination) | `10.7.21.122` | `80/TCP`, `443/TCP` |
| **Mac 3** | Application Backend A | Node.js + Express | `10.7.6.183` | `3001/TCP` |
| **Mac 4** | Application Backend B & Capture Client | Node.js + Express, Wireshark | `10.7.7.247` | `3002/TCP` |

---

## 2. Machine Configuration Procedures

### Mac 1: Private DNS (`dnsmasq`)
1. Install `dnsmasq`:
   ```bash
   brew install dnsmasq
   ```
2. Write `/opt/homebrew/etc/dnsmasq.conf`:
   ```conf
   no-resolv
   server=8.8.8.8
   server=1.1.1.1
   local=/lando.test/
   host-record=app.lando.test,10.7.21.122
   host-record=api.lando.test,10.7.21.122
   local-ttl=60
   log-queries
   ```
3. Test syntax and start daemon:
   ```bash
   $(brew --prefix)/sbin/dnsmasq --test --conf-file=$(brew --prefix)/etc/dnsmasq.conf
   sudo brew services restart dnsmasq
   ```

---

### Mac 2: Edge Reverse Proxy & TLS (`nginx`)
1. Generate certificates using OpenSSL 3:
   - Root CA (`rootCA.key`, `rootCA.pem`) with `basicConstraints = critical, CA:TRUE`.
   - Leaf Certificate (`server.key`, `server.crt`) with SAN: `DNS:app.lando.test, DNS:api.lando.test`.
   - Distribute `rootCA.pem` to client machines via AirDrop.
2. Configure `/opt/homebrew/etc/nginx/servers/lando.conf`:
   ```nginx
   upstream team_backends {
       server 10.7.6.183:3001 max_fails=1 fail_timeout=10s;
       server 10.7.7.247:3002 max_fails=1 fail_timeout=10s;
   }

   server {
       listen 80;
       server_name app.lando.test api.lando.test;
       return 301 https://$host$request_uri;
   }

   server {
       listen 443 ssl;
       http2 on;
       server_name app.lando.test api.lando.test;

       ssl_certificate     /opt/homebrew/etc/nginx/certs/server.crt;
       ssl_certificate_key /opt/homebrew/etc/nginx/certs/server.key;
       ssl_protocols       TLSv1.2 TLSv1.3;

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
3. Test syntax and start daemon:
   ```bash
   sudo nginx -t
   sudo brew services restart nginx
   ```

---

### Mac 3: Backend A
1. Navigate to backend directory and start process:
   ```bash
   cd ~/cn-backend
   export BACKEND=A PORT=3001
   node server.js
   ```

---

### Mac 4: Backend B & Client Verification
1. Launch Backend B:
   ```bash
   cd ~/cn-backend
   ./start-backend-b.sh
   ```
2. Configure DNS resolver:
   ```bash
   sudo networksetup -setdnsservers Wi-Fi 10.7.5.248
   sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
   ```
3. Trust Root CA:
   ```bash
   sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/Downloads/rootCA.pem
   ```
4. Perform end-to-end verification:
   ```bash
   for i in 1 2 3 4; do curl -si https://app.lando.test/api/status | grep -i x-backend; done
   ```
