#!/usr/bin/env bash
# ==============================================================================
# Stop Backend A on Laptop 3 (Port 3001) - For HA Failover Testing (Extension D)
# ==============================================================================
set -euo pipefail

echo "Stopping Backend A on port 3001..."
PID=$(lsof -ti tcp:3001 || true)

if [[ -n "$PID" ]]; then
    echo "Found process $PID listening on port 3001. Terminating..."
    kill "$PID" 2>/dev/null || kill -9 "$PID" 2>/dev/null || true
    sleep 1
    if lsof -ti tcp:3001 >/dev/null 2>&1; then
        echo "Process still running, forcing kill -9..."
        kill -9 $(lsof -ti tcp:3001) 2>/dev/null || true
    fi
    echo "SUCCESS: Backend A stopped. Port 3001 is now free."
else
    echo "No process was found listening on port 3001."
fi

