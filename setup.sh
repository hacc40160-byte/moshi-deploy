#!/bin/bash
set -euo pipefail

# MoshiRAG + Knowledge Base — One-Time Setup
# Run once on a fresh GPU machine. Zero errors.
# After this: ./start.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Load .env
if [ -f .env ]; then
    set -a; source .env; set +a
else
    echo "[!] No .env found. Copying from template..."
    cp .env.template .env
    echo "[!] Edit .env with your HF_TOKEN, then re-run."
    exit 1
fi

# Validate HF token
if [ -z "${HF_TOKEN:-}" ] || [ "$HF_TOKEN" = "hf_YOUR_TOKEN_HERE" ]; then
    echo "[!] Set HF_TOKEN in .env first!"
    echo "    Get one at: https://huggingface.co/settings/tokens"
    exit 1
fi

echo "========================================="
echo "  MoshiRAG + Knowledge Base Setup"
echo "========================================="

# Check GPU
echo "[1/9] Checking GPU..."
if ! nvidia-smi &>/dev/null; then
    echo "[!] No NVIDIA GPU detected."
    exit 1
fi
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
echo "[✓] GPU detected"

# System deps
echo "[2/9] Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq python3.11 python3.11-venv python3-pip curl wget git portaudio19-dev nginx > /dev/null 2>&1
echo "[✓] System deps installed"

# Python 3.11 venv
echo "[3/9] Creating Python 3.11 venv..."
VENV_DIR="/root/moshi-venv"
if [ ! -d "$VENV_DIR" ]; then
    python3.11 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"
pip install --upgrade pip setuptools wheel -q

# PyTorch with CUDA 12.8
echo "[4/9] Installing PyTorch (takes a while)..."
pip install torch==2.9.1+cu128 torchaudio==2.11.0+cu128 --index-url https://download.pytorch.org/whl/cu128 -q

# MoshiRAG from source (exact commit that works)
echo "[5/9] Installing MoshiRAG from source..."
pip install -e "git+https://github.com/kyutai-labs/moshi-rag.git@8c6dfc101b7871baa428424bcdc583b74fb561d9#egg=moshi&subdirectory=moshi" -q

# Remaining deps from frozen requirements
echo "[6/9] Installing remaining dependencies..."
pip install -r requirements.txt --no-deps -q 2>/dev/null || true

# Knowledge Base deps (separate venv to avoid conflicts)
echo "[7/9] Setting up Knowledge Base..."
KB_DIR="$SCRIPT_DIR/knowledge-base"
KB_VENV="$KB_DIR/venv"
mkdir -p "$KB_DIR/data" "$KB_DIR/chromadb"
if [ ! -d "$KB_VENV" ]; then
    python3.11 -m venv "$KB_VENV"
fi
"$KB_VENV/bin/pip" install --upgrade pip -q
"$KB_VENV/bin/pip" install chromadb fastapi uvicorn python-multipart requests beautifulsoup4 PyPDF2 -q
echo "[✓] Knowledge Base deps installed"

# Ollama + embedding model
echo "[8/9] Installing Ollama + pulling models..."
if ! command -v ollama &>/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
fi
ollama pull qwen3:4b
ollama pull nomic-embed-text
echo "[✓] Ollama models ready"

# Download MoshiRAG model (~15GB)
echo "[9/9] Downloading MoshiRAG model (~15GB)..."
export HF_TOKEN="$HF_TOKEN"
mkdir -p "$MODEL_DIR"
python3 -c "
from huggingface_hub import snapshot_download
snapshot_download(
    '${MOSHI_REPO}',
    local_dir='${MODEL_DIR}',
    token='${HF_TOKEN}'
)
print('Model downloaded to ${MODEL_DIR}')
"

# Setup nginx config
echo "[+] Configuring nginx..."
cp nginx.conf /etc/nginx/sites-available/moshi-deploy
ln -sf /etc/nginx/sites-available/moshi-deploy /etc/nginx/sites-enabled/moshi-deploy
rm -f /etc/nginx/sites-enabled/default
nginx -t 2>/dev/null && echo "[✓] nginx configured" || echo "[!] nginx config error — check nginx.conf"

echo ""
echo "========================================="
echo "  Setup Complete!"
echo "========================================="
echo ""
echo "  Next: ./start.sh"
echo ""
