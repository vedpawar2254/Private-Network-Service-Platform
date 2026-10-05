# Backend (Mac 3 and Mac 4)

Node/Express app run on both backend Macs. Same code; identity set by env vars.

- Mac 3 (Backend A): `BACKEND=A PORT=3001 node server.js`
- Mac 4 (Backend B): `BACKEND=B PORT=3002 node server.js`

## To complete this folder

Copy the real files from a backend Mac (`~/cn-backend/`):

```
backend/
├── server.js       # from ~/cn-backend/server.js
└── package.json    # from ~/cn-backend/package.json
```

`node_modules/` is git-ignored — reinstall with `npm install` after cloning.

## Endpoints

| Path | Cache | Purpose |
|------|-------|---------|
| `/` | — | service info + `backend` + hostname |
| `/api/status` | `no-store` | load-balancing proof (changing body → different ETag per backend) |
| `/api/cached` | `public, max-age=60` | caching proof (identical body on A and B → same ETag → 304 works through the LB) |

Every response sets `X-Backend: A|B` so you can see which backend served it.
