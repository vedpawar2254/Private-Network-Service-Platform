#!/usr/bin/env bash
# ==============================================================================
# Start Backend A on Laptop 3 (Port 3001)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if node is installed
if ! command -v node >/dev/null 2>&1; then
    echo "ERROR: node is not installed. Please install Node.js (e.g. brew install node)."
    exit 1
fi

# Check if port 3001 is already in use
if lsof -nP -iTCP:3001 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Warning: Port 3001 is already in use by process:"
    lsof -nP -iTCP:3001 -sTCP:LISTEN
    echo "Kill it first using ./stop-backend-a.sh if you want to restart."
    exit 1
fi

echo "Starting Backend A on port 3001..."
export BACKEND="A"
export PORT="3001"

# Run node server
exec node server.js

