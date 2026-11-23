# Task G: Protocol Flow & Packet Capture Analysis (Wireshark)

## 1. Overview & Topology
- **Client Machine (Mac 4):** `10.7.7.247`
- **Private DNS Server (Mac 1):** `10.7.5.248` (UDP Port 53)
- **Edge Load Balancer (Mac 2):** `10.7.21.122` (TCP Port 443)
- **Domain Name:** `app.lando.test`
- **End-to-End Flow:** DNS Query (UDP) ➔ TCP Handshake ➔ TLS 1.2 Handshake ➔ Encrypted HTTP/2 Application Data

---

## 2. Evidence Deliverables Checklist
All required files reside in `evidence/G-wireshark/`:
1. `phase1-full-flow.pcapng` — Complete Wireshark packet capture file containing the uninterrupted client journey.
2. `phase1-app-flow.pcapng` — Filtered packet capture file targeting specifically: `dns.qry.name == "app.lando.test" or tcp.port == <client_port>`.
3. `curl-verbose.txt` — Plaintext terminal trace verifying DNS resolution, TLS certificate negotiation, HTTP/2 stream, and headers.
4. Screenshots of standard Wireshark display filters:
   - Filter `dns`: UDP query and response.
   - Filter `tcp.flags.syn == 1`: TCP 3-way handshake.
   - Filter `tls.handshake`: Complete TLS negotiation exchange.
   - Filter `tls`: Binary encrypted Application Data record showing unreadable HTTP payload.

---

## 3. Layer-by-Layer Packet Analysis

| Layer | Protocol | Wireshark Filter | Source ➔ Destination | Technical Details & Observations |
|---|---|---|---|---|
| **DNS** | UDP | `dns` | `10.7.7.247:<ephemeral>` ➔ `10.7.5.248:53` | Standard DNS query for `app.lando.test` (Type A). Response resolves to `10.7.21.122` with `TTL=60s`. |
| **Transport** | TCP | `tcp.flags.syn == 1` | `10.7.7.247:<ephemeral>` ➔ `10.7.21.122:443` | TCP Three-Way Handshake: `SYN` ➔ `SYN-ACK` ➔ `ACK`. Establishes bidirectional reliability, initial sequence numbers, and sliding window flow control. |
| **Presentation / Security** | TLS 1.2 | `tls.handshake` | `10.7.7.247` ⇄ `10.7.21.122` | **ClientHello:** SNI=`app.lando.test`, ALPN=`h2, http/1.1`, Cipher Suites offered.<br>**ServerHello:** Cipher chosen.<br>**Certificate:** X.509 certificate chain (`CN=app.lando.test`, SAN: `DNS:app.lando.test`, issuer: `CN=lando Local Root CA`).<br>**ServerKeyExchange & ClientKeyExchange:** ECDH key agreement.<br>**ChangeCipherSpec & Finished:** Symmetric encryption verified. |
| **Application** | HTTP/2 | `tls` | `10.7.7.247` ⇄ `10.7.21.122` | **Application Data:** Binary encrypted records. HTTP payload is completely encrypted. |

---

## 4. Socket & Port Identification
- **DNS Layer:** Client generates a random ephemeral source port (e.g. `52341/UDP`) connecting to well-known destination port **`53/UDP`**.
- **HTTPS Layer:** Client generates a random ephemeral source port (e.g. `58942/TCP`) connecting to well-known destination port **`443/TCP`**.

---

## 5. Security Analysis: Why HTTP Headers are Inaccessible in Packet Captures
TLS operates at the Presentation Layer (OSI Layer 6) beneath the Application Layer (Layer 7). Upon completion of the cryptographic key exchange (`ChangeCipherSpec`), all data framing, HTTP/2 pseudo-headers (`:method`, `:path`, `:authority`), response headers (`X-Backend`, `Cache-Control`), and response bodies are encrypted using the negotiated symmetric session cipher (e.g. `CHACHA20-POLY1305` / `AES-GCM`). 

Because Wireshark does not possess the client or server ephemeral private session keys, it can only interpret the frames as opaque binary `Application Data`. Proof of plaintext HTTP/2 headers and status codes is verified via client-side verbose logging (`curl-verbose.txt`).
