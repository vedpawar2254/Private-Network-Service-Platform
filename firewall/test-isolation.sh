#!/usr/bin/env bash
# ==============================================================================
# Test Service Isolation Connectivity
# Can be run locally on Laptop 3 or from any other Mac
# ==============================================================================
TARGET_IP="${1:-127.0.0.1}"
TARGET_PORT="${2:-3001}"

echo "=========================================================="
echo " Testing connectivity to http://${TARGET_IP}:${TARGET_PORT}/api/status"
echo "=========================================================="

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "http://${TARGET_IP}:${TARGET_PORT}/api/status" || echo "FAILED")

if [[ "$HTTP_CODE" == "200" ]]; then
    echo "RESULT: [ALLOWED] HTTP status 200 OK"
    curl -s -i --connect-timeout 3 "http://${TARGET_IP}:${TARGET_PORT}/api/status" | head -n 12
elif [[ "$HTTP_CODE" == "FAILED" ]]; then
    echo "RESULT: [BLOCKED / REJECTED] Connection failed or timed out (Firewall active)."
else
    echo "RESULT: HTTP Response code: ${HTTP_CODE}"
fi
echo "=========================================================="

