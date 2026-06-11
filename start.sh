#!/bin/bash
set -euo pipefail

# MoshiRAG Start All Services
# Exact commands from working RTX 5090 deployment
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

PIDFILE="/tmp/moshi-deploy.pids"
touch "$PIDFILE"

save_pid() {
    echo "${1}=${2}" >> "$PIDFILE"
}

wait_for_port() {
    local port=$1
    local name=$2
    local max=120
    local i=0
    while ! curl -s "http://localhost:${port}" >/dev/null 2>&1; do
        sleep 1
        i=$((i + 1))
        if [ $i -ge $max ]; then
            echo "[!] $name failed to start on port $port after ${max}s"
            echo "    Check logs: $LOGS_DIR/"
            return 1
        fi
    done
    echo "[✓] $name ready on port $port"
}

echo "========================================="
echo "  Starting MoshiRAG Services"
echo "========================================="

# 1. Conditioner (CPU-only)
echo "[1/3] Starting Conditioner (CPU, port $CONDITIONER_PORT)..."
cd "$SCRIPT_DIR"
CUDA_VISIBLE_DEVICES='' \
HF_TOKEN="$HF_TOKEN" \
"$VENV_DIR/bin/python3" \
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
echo "[2/3] Starting Ollama (port $OLLAMA_PORT)..."
if ! pgrep -x ollama >/dev/null 2>&1; then
    CUDA_VISIBLE_DEVICES='' \
    OLLAMA_NUM_PARALLEL=1 \
    ollama serve > "$LOGS_DIR/ollama.log" 2>&1 &
    save_pid "ollama" $!
    echo "  PID: $!"
    sleep 5
else
    echo "  [✓] Ollama already running"
fi
echo "[✓] Ollama ready"

# 3. MoshiRAG Main (GPU, batch-size 1)
echo "[3/3] Starting MoshiRAG Main (GPU, batch-size $BATCH_SIZE, port $MOSHI_PORT)..."
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
echo "  MoshiRAG:    http://localhost:$MOSHI_PORT"
echo "  Conditioner: http://localhost:$CONDITIONER_PORT"
echo "  Ollama:      http://localhost:$OLLAMA_PORT"
echo ""
echo "  Logs: $LOGS_DIR/"
echo "  PIDs: $PIDFILE"
echo "  Public URL: ./tunnel.sh"
