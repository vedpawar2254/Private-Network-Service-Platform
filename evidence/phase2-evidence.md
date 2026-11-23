# Phase 2 Evidence Logs

## 1. Extension C — Service Isolation Check (Pre-Firewall / Direct Access Baseline)
**Client:** Laptop 1 (Mac 1)
**Command:**
```bash
curl -i --connect-timeout 3 http://10.7.21.122:3001/api/status
```

**Output:**
```http
HTTP/1.1 200 OK
X-Powered-By: Express
X-Backend: A
Cache-Control: no-store
Content-Type: application/json; charset=utf-8
Content-Length: 63
ETag: W/"3f-09SNlawwVufdPAXnIN8JD0WoBHU"
Date: Mon, 23 Nov 2026 05:52:59 GMT
Connection: keep-alive
Keep-Alive: timeout=5

{"backend":"A","status":"ok","time":"2026-11-23T05:52:59.634Z"}
```

**Observation:** Direct request to Backend A (`10.7.21.122:3001`) succeeded before pf packet filter rules blocked unauthorized clients.
