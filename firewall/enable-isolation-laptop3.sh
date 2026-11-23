#!/usr/bin/env bash
# ==============================================================================
# Enable Service Isolation on Laptop 3 (Backend A - Port 3001)
# CN Project Phase 2 - Extension C
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/isolation-laptop3.conf.template"
GENERATED_FILE="${SCRIPT_DIR}/isolation-laptop3.conf"
ANCHOR_NAME="com.apple/backend_isolation"

# Default Edge IP (Laptop 2) from README, or accept as first argument / env var
EDGE_IP="${1:-${EDGE_IP:-10.7.26.218}}"

echo "=========================================================="
echo " [Laptop 3] Enabling Service Isolation (macOS PF)"
echo " Backend Port : 3001"
echo " Allowed Edge : ${EDGE_IP}"
echo "=========================================================="

if [[ $EUID -ne 0 ]]; then
    echo "This script requires administrator privileges to configure PF."
    echo "Re-running with sudo..."
    exec sudo bash "$0" "$EDGE_IP"
fi

# 1. Generate active config from template
sed "s/__EDGE_IP__/${EDGE_IP}/g" "$TEMPLATE_FILE" > "$GENERATED_FILE"

# 2. Test syntax
echo "1. Checking PF rule syntax..."
pfctl -a "$ANCHOR_NAME" -vnf "$GENERATED_FILE" >/dev/null 2>&1 || {
    echo "ERROR: Invalid PF syntax. Aborting."
    exit 1
}
echo "   -> Syntax valid."

# 3. Enable pf if not already enabled
echo "2. Ensuring PF is enabled..."
pfctl -e >/dev/null 2>&1 || true

# 4. Load rules into anchor com.apple/backend_isolation
echo "3. Loading isolation rules into anchor '${ANCHOR_NAME}'..."
pfctl -a "$ANCHOR_NAME" -f "$GENERATED_FILE"

# 5. Show active rules in the anchor
echo ""
echo "4. Active PF rules for Service Isolation:"
pfctl -a "$ANCHOR_NAME" -s rules

echo ""
echo "=========================================================="
echo " SUCCESS: Service isolation is ACTIVE on Laptop 3!"
echo " - Connections from Edge (${EDGE_IP}) -> Port 3001: ALLOWED"
echo " - Connections from localhost (127.0.0.1) -> Port 3001: ALLOWED"
echo " - Direct connections from clients -> Port 3001: BLOCKED (TCP RST)"
echo " To rollback/disable: run ./firewall/disable-isolation-laptop3.sh"
echo "=========================================================="

