#!/bin/bash
set -euo pipefail

# MoshiRAG Cloudflare Tunnel
# Creates a free public URL for the MoshiRAG web UI

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load env for port
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a; source "$SCRIPT_DIR/.env"; set +a
fi

MOSHI_PORT="${MOSHI_PORT:-8998}"

# Install cloudflared if missing
if ! command -v cloudflared &>/dev/null; then
    echo "[*] Installing cloudflared..."
    curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
fi

echo "========================================="
echo "  Starting Cloudflare Tunnel"
echo "========================================="
echo ""
echo "  Exposing localhost:$MOSHI_PORT"
echo "  Press Ctrl+C to stop"
echo ""

cloudflared tunnel --url "http://localhost:${MOSHI_PORT}"
