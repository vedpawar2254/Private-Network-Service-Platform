#!/usr/bin/env bash
# ==============================================================================
# Status Check for Service Isolation on Laptop 3
# ==============================================================================
ANCHOR_NAME="com.apple/backend_isolation"

echo "=========================================================="
echo " [Laptop 3] Service Isolation Status Check"
echo "=========================================================="

echo "1. PF Global Status:"
sudo pfctl -s info 2>/dev/null | grep -E "Status|State Table|Source Tracking" || echo "PF status check failed"

echo ""
echo "2. Active Rules in Anchor '${ANCHOR_NAME}':"
sudo pfctl -a "$ANCHOR_NAME" -s rules 2>/dev/null || echo "No rules found in anchor."

echo ""
echo "3. Active Tables in Anchor '${ANCHOR_NAME}':"
sudo pfctl -a "$ANCHOR_NAME" -s Tables 2>/dev/null || true

echo ""
echo "4. Local Port 3001 Listening Check:"
lsof -nP -iTCP:3001 -sTCP:LISTEN || echo "Note: No process currently listening on port 3001."
echo "=========================================================="

