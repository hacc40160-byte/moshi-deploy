#!/bin/bash

# MoshiRAG Health Check

check_port() {
    local name=$1
    local port=$2
    if curl -s --connect-timeout 3 "http://localhost:${port}" >/dev/null 2>&1; then
        echo "  ✅ $name (port $port) — UP"
    else
        echo "  ❌ $name (port $port) — DOWN"
    fi
}

echo "========================================="
echo "  MoshiRAG Service Status"
echo "========================================="
echo ""

check_port "MoshiRAG Main" 8998
check_port "Conditioner" 8001
check_port "Ollama" 11434

# GPU status
echo ""
echo "GPU Status:"
if nvidia-smi --query-gpu=name,memory.used,memory.total,temperature.gpu,utilization.gpu --format=csv,noheader 2>/dev/null; then
    :
else
    echo "  (no GPU info available)"
fi

# Ollama models
echo ""
echo "Ollama Models:"
ollama list 2>/dev/null || echo "  (ollama not running)"

# PID file
PIDFILE="/tmp/moshi-deploy.pids"
if [ -f "$PIDFILE" ]; then
    echo ""
    echo "Tracked PIDs:"
    cat "$PIDFILE"
fi
