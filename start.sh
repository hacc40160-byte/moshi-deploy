#!/bin/bash
set -euo pipefail

# MoshiRAG Start All Services
# Order: Conditioner → Ollama → MoshiRAG Main

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Load env
if [ -f .env ]; then
    set -a; source .env; set +a
else
    echo "[!] No .env found. Run setup.sh first."
    exit 1
fi

VENV_DIR="/root/moshi-venv"
LOGS_DIR="/root/moshi-logs"
mkdir -p "$LOGS_DIR"

# PID file tracking
PIDFILE="/tmp/moshi-deploy.pids"
touch "$PIDFILE"

kill_pid() {
    local name=$1
    if grep -q "^${name}=" "$PIDFILE" 2>/dev/null; then
        local pid=$(grep "^${name}=" "$PIDFILE" | cut -d= -f2)
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            echo "  Stopped $name (PID $pid)"
        fi
        sed -i "/^${name}=/d" "$PIDFILE"
    fi
}

save_pid() {
    local name=$1
    local pid=$2
    echo "${name}=${pid}" >> "$PIDFILE"
}

wait_for_port() {
    local port=$1
    local name=$2
    local max_wait=60
    local count=0
    while ! curl -s "http://localhost:${port}" >/dev/null 2>&1; do
        sleep 1
        count=$((count + 1))
        if [ $count -ge $max_wait ]; then
            echo "[!] $name failed to start on port $port after ${max_wait}s"
            return 1
        fi
    done
    echo "[✓] $name ready on port $port"
}

echo "========================================="
echo "  Starting MoshiRAG Services"
echo "========================================="

# 1. Conditioner (CPU-only, saves VRAM)
echo "[1/3] Starting Conditioner on port $CONDITIONER_PORT..."
kill_pid "conditioner"
cd "$SCRIPT_DIR"
HF_TOKEN="$HF_TOKEN" CUDA_VISIBLE_DEVICES='' "$VENV_DIR/bin/python3" \
    -m moshi.server_conditioner \
    --config "$MODEL_DIR/config.json" \
    --moshi-weight "$MODEL_DIR/model.safetensors" \
    --conditioner reference_with_time \
    --cuda-device cpu \
    --host 0.0.0.0 \
    --port "$CONDITIONER_PORT" \
    > "$LOGS_DIR/conditioner.log" 2>&1 &
save_pid "conditioner" $!
echo "  PID: $!"
wait_for_port "$CONDITIONER_PORT" "Conditioner"

# 2. Ollama (CPU, zero-cost LLM backend)
echo "[2/3] Starting Ollama on port $OLLAMA_PORT..."
if ! pgrep -x ollama >/dev/null 2>&1; then
    CUDA_VISIBLE_DEVICES='' OLLAMA_NUM_PARALLEL=1 OLLAMA_MAX_LOADED_MODELS=1 \
        ollama serve > "$LOGS_DIR/ollama.log" 2>&1 &
    save_pid "ollama" $!
    sleep 3
fi
echo "[✓] Ollama running"

# 3. MoshiRAG Main (GPU, batch-size 1 for 32GB cards)
echo "[3/3] Starting MoshiRAG Main on port $MOSHI_PORT (GPU, batch-size $BATCH_SIZE)..."
kill_pid "moshi"
cd "$SCRIPT_DIR"
REFERENCE_ENCODER_URL="$REFERENCE_ENCODER_URL" \
HF_TOKEN="$HF_TOKEN" \
LLM_BASE_URL="$LLM_BASE_URL" \
LLM_API_KEY="$LLM_API_KEY" \
LLM_MODEL_NAME="$LLM_MODEL_NAME" \
"$VENV_DIR/bin/python3" \
    -m moshi.server \
    --hf-repo "$MOSHI_REPO" \
    --moshi-weight "$MODEL_DIR/model.safetensors" \
    --tokenizer "$MODEL_DIR/tokenizer_spm_32k_3.model" \
    --device "$CUDA_DEVICE" \
    --host 0.0.0.0 \
    --port "$MOSHI_PORT" \
    --batch-size "$BATCH_SIZE" \
    > "$LOGS_DIR/moshi-main.log" 2>&1 &
save_pid "moshi" $!
echo "  PID: $!"
wait_for_port "$MOSHI_PORT" "MoshiRAG Main"

echo ""
echo "========================================="
echo "  All Services Running"
echo "========================================="
echo ""
echo "  MoshiRAG:   http://localhost:$MOSHI_PORT"
echo "  Conditioner: http://localhost:$CONDITIONER_PORT"
echo "  Ollama:     http://localhost:$OLLAMA_PORT"
echo ""
echo "  Logs: $LOGS_DIR/"
echo "  PIDs: $PIDFILE"
echo ""
echo "  For public URL: ./tunnel.sh"
