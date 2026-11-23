#!/bin/bash
# Mac 4: Backend B Startup Script
echo "=========================================="
echo " Starting Backend B on Mac 4 (Port 3002) "
echo " Host IP: $(ipconfig getifaddr en0)"
echo "=========================================="
export BACKEND=B
export PORT=3002
cd "$(dirname "$0")"
node server.js
