#!/bin/bash
set -euo pipefail

# MoshiRAG Stop All Services

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIDFILE="/tmp/moshi-deploy.pids"

echo "========================================="
echo "  Stopping MoshiRAG Services"
echo "========================================="

# Kill tracked PIDs
if [ -f "$PIDFILE" ]; then
    while IFS='=' read -r name pid; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            echo "[✓] Stopped $name (PID $pid)"
        else
            echo "[–] $name (PID $pid) already stopped"
        fi
    done < "$PIDFILE"
    rm -f "$PIDFILE"
fi

# Also kill any orphaned processes
pkill -f "moshi.server_conditioner" 2>/dev/null && echo "[✓] Killed orphan conditioner" || true
pkill -f "moshi.server " 2>/dev/null && echo "[✓] Killed orphan moshi server" || true
# Don't kill ollama — user might be using it for other things
# pkill -f "ollama serve" 2>/dev/null

# Kill cloudflared tunnel
pkill -f "cloudflared tunnel" 2>/dev/null && echo "[✓] Killed tunnel" || true

echo ""
echo "All MoshiRAG services stopped."
