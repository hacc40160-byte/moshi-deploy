#!/bin/bash
set -euo pipefail

# Stop all MoshiRAG services

echo "========================================="
echo "  Stopping All Services"
echo "========================================="

echo "[1/5] Stopping Cloudflare tunnel..."
pkill -f "cloudflared tunnel" 2>/dev/null && echo "  [✓] stopped" || echo "  [–] not running"

echo "[2/5] Stopping Nginx..."
nginx -s stop 2>/dev/null && echo "  [✓] stopped" || echo "  [–] not running"

echo "[3/5] Stopping Knowledge Base..."
pkill -f "knowledge-base/venv.*server.py" 2>/dev/null && echo "  [✓] stopped" || echo "  [–] not running"

echo "[4/5] Stopping MoshiRAG..."
pkill -f "moshi.server --hf-repo" 2>/dev/null && echo "  [✓] stopped" || echo "  [–] not running"

echo "[5/5] Stopping Conditioner..."
pkill -f "moshi.server_conditioner" 2>/dev/null && echo "  [✓] stopped" || echo "  [–] not running"

# Ollama stays running (shared resource, lightweight)
echo ""
echo "  Ollama left running (shared, lightweight)"
echo "  To stop: pkill ollama"
echo ""
echo "  All services stopped."
