#!/usr/bin/env bash
# ==============================================================================
# Disable / Rollback Service Isolation on Laptop 3 (Backend A)
# CN Project Phase 2 - Extension C
# ==============================================================================
set -euo pipefail

ANCHOR_NAME="com.apple/backend_isolation"

echo "=========================================================="
echo " [Laptop 3] Disabling Service Isolation (Rollback)"
echo " Flushing anchor: ${ANCHOR_NAME}"
echo "=========================================================="

if [[ $EUID -ne 0 ]]; then
    echo "This script requires administrator privileges."
    echo "Re-running with sudo..."
    exec sudo bash "$0"
fi

# Flush all rules in our specific anchor
pfctl -a "$ANCHOR_NAME" -F all

echo ""
echo "Verification: checking rules in anchor '${ANCHOR_NAME}':"
REMAINING=$(pfctl -a "$ANCHOR_NAME" -s rules 2>/dev/null | wc -l | tr -d ' ')

if [[ "$REMAINING" -eq "0" ]]; then
    echo "-> Anchor '${ANCHOR_NAME}' is completely empty."
    echo "-> Backend A (Port 3001) is now accessible directly again."
    echo "SUCCESS: Rollback complete."
else
    echo "Warning: Some rules remain in anchor:"
    pfctl -a "$ANCHOR_NAME" -s rules
fi
echo "=========================================================="

