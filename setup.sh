#!/bin/bash
set -euo pipefail

# MoshiRAG One-Time Setup
# Exact replica of working RTX 5090 deployment
# Run once on a fresh GPU machine

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Load .env
if [ -f .env ]; then
    source .env
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
echo "  MoshiRAG Setup - Fresh GPU Machine"
echo "========================================="

# Check GPU
echo "[1/8] Checking GPU..."
if ! nvidia-smi &>/dev/null; then
    echo "[!] No NVIDIA GPU detected."
    exit 1
fi
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
echo "[✓] GPU detected"

# System deps
echo "[2/8] Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq python3.11 python3.11-venv python3-pip curl wget git portaudio19-dev

# Python 3.11 venv
echo "[3/8] Creating Python 3.11 venv..."
VENV_DIR="/root/moshi-venv"
if [ ! -d "$VENV_DIR" ]; then
    python3.11 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"
pip install --upgrade pip setuptools wheel

# PyTorch with CUDA 12.8
echo "[4/8] Installing PyTorch (takes a while)..."
pip install torch==2.9.1+cu128 torchaudio==2.11.0+cu128 --index-url https://download.pytorch.org/whl/cu128

# MoshiRAG from source (exact commit that works)
echo "[5/8] Installing MoshiRAG from source..."
pip install -e "git+https://github.com/kyutai-labs/moshi-rag.git@8c6dfc101b7871baa428424bcdc583b74fb561d9#egg=moshi&subdirectory=moshi"

# Remaining deps from frozen requirements
echo "[6/8] Installing remaining dependencies..."
pip install -r requirements.txt --no-deps 2>/dev/null || true

# Ollama
echo "[7/8] Installing Ollama + pulling qwen3:4b..."
if ! command -v ollama &>/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
fi
ollama pull qwen3:4b

# Download MoshiRAG model (~15GB)
echo "[8/8] Downloading MoshiRAG model (~15GB)..."
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

echo ""
echo "========================================="
echo "  Setup Complete!"
echo "========================================="
echo ""
echo "  Next: ./start.sh"
