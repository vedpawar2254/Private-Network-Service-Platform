const express = require("express");
const os = require("os");

const BACKEND = process.env.BACKEND || "A";
const PORT = Number(process.env.PORT) || 3001;
const app = express();

// Every response carries X-Backend so we can see who served it
app.use((req, res, next) => {
  res.set("X-Backend", BACKEND);
  console.log(new Date().toISOString() + "  from=" + req.socket.remoteAddress + "  " + req.method + " " + req.url);
  next();
});

app.get("/", (req, res) => {
  res.json({ service: "team backend", backend: BACKEND, host: os.hostname(), message: "running" });
});

// Never cached, so load balancing stays visible on every request
app.get("/api/status", (req, res) => {
  res.set("Cache-Control", "no-store");
  res.json({ backend: BACKEND, status: "ok", time: new Date().toISOString() });
});

// Cacheable (Task F). Same body on A and B => same ETag => 304 works behind the load balancer
app.get("/api/cached", (req, res) => {
  res.set("Cache-Control", "public, max-age=60");
  res.json({ data: "this response is cacheable", version: 1 });
});

// 0.0.0.0 = listen on all interfaces, so other Macs can reach it (not just localhost)
app.listen(PORT, "0.0.0.0", () => {
  console.log("Backend " + BACKEND + " listening on 0.0.0.0:" + PORT);
});
