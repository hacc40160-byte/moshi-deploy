#!/bin/bash
set -euo pipefail

# MoshiRAG + Knowledge Base — Start All Services
# Order: Ollama → Conditioner → MoshiRAG → Knowledge Base → Nginx → Tunnel

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
KB_VENV="$SCRIPT_DIR/knowledge-base/venv"
LOGS_DIR="/root/moshi-logs"
mkdir -p "$LOGS_DIR"

PIDFILE="/tmp/moshi-deploy.pids"
> "$PIDFILE"

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
echo "  Starting All Services"
echo "========================================="

# 1. Ollama (CPU, zero-cost LLM backend)
echo "[1/6] Starting Ollama..."
if ! pgrep -x ollama >/dev/null 2>&1; then
    CUDA_VISIBLE_DEVICES='' \
    OLLAMA_NUM_PARALLEL=1 \
    ollama serve > "$LOGS_DIR/ollama.log" 2>&1 &
    save_pid "ollama" $!
    sleep 5
else
    echo "  [✓] Ollama already running"
fi
echo "[✓] Ollama ready"

# 2. Conditioner (CPU-only)
echo "[2/6] Starting Conditioner (CPU, port $CONDITIONER_PORT)..."
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

# 3. MoshiRAG Main (GPU)
echo "[3/6] Starting MoshiRAG Main (GPU, port $MOSHI_PORT)..."
cd "$SCRIPT_DIR"
REFERENCE_ENCODER_URL="$REFERENCE_ENCODER_URL" \
HF_TOKEN="$HF_TOKEN" \
LLM_BASE_URL="$LLM_BASE_URL" \
OPENAI_API_KEY="${OPENAI_API_KEY:-sk-dummy}" \
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

# 4. Knowledge Base (CPU, port 8500)
echo "[4/6] Starting Knowledge Base (port 8500)..."
cd "$SCRIPT_DIR/knowledge-base"
OLLAMA_URL="http://localhost:${OLLAMA_PORT:-11434}" \
EMBED_MODEL="nomic-embed-text" \
DB_PATH="$SCRIPT_DIR/knowledge-base/chromadb" \
DATA_DIR="$SCRIPT_DIR/knowledge-base/data" \
"$KB_VENV/bin/python3" server.py > "$LOGS_DIR/knowledge-base.log" 2>&1 &
save_pid "knowledge-base" $!
echo "  PID: $!"
wait_for_port 8500 "Knowledge Base"

# 5. Nginx (reverse proxy on port 80)
echo "[5/6] Starting Nginx (port 80)..."
pkill nginx 2>/dev/null || true
sleep 1
nginx
sleep 1
if curl -s http://localhost:80/kb/stats >/dev/null 2>&1; then
    echo "[✓] Nginx ready — / → MoshiRAG, /kb/ → Knowledge Base"
else
    echo "[!] Nginx started but /kb/ not responding"
fi
save_pid "nginx" "$(pgrep -x nginx | head -1)"

# 6. Cloudflare Tunnel (public URL)
echo "[6/6] Starting Cloudflare Tunnel..."
if ! command -v cloudflared &>/dev/null; then
    curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
fi
nohup cloudflared tunnel --url http://localhost:80 > "$LOGS_DIR/tunnel.log" 2>&1 &
save_pid "tunnel" $!
sleep 5
TUNNEL_URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOGS_DIR/tunnel.log" | head -1 || echo "check $LOGS_DIR/tunnel.log")

echo ""
echo "========================================="
echo "  All Services Running"
echo "========================================="
echo ""
echo "  MoshiRAG:       http://localhost:$MOSHI_PORT"
echo "  Knowledge Base: http://localhost:8500"
echo "  Nginx (local):  http://localhost:80"
echo "  Public URL:     $TUNNEL_URL"
echo ""
echo "  $TUNNEL_URL/         → MoshiRAG"
echo "  $TUNNEL_URL/kb/      → Knowledge Base UI"
echo ""
echo "  Logs: $LOGS_DIR/"
echo "  PIDs: $PIDFILE"
echo ""
