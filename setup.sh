#!/bin/bash
set -euo pipefail

# MoshiRAG One-Time Setup
# Run this once on a fresh GPU machine

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Load .env if exists, otherwise use .env.template defaults
if [ -f .env ]; then
    source .env
else
    echo "[!] No .env found. Copying from template..."
    cp .env.template .env
    echo "[!] Edit .env with your HF_TOKEN, then re-run this script."
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

# Check for NVIDIA GPU
echo "[1/7] Checking GPU..."
if ! nvidia-smi &>/dev/null; then
    echo "[!] No NVIDIA GPU detected. Install drivers first."
    exit 1
fi
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
echo "[✓] GPU detected"

# Install system deps
echo "[2/7] Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq python3.11 python3.11-venv python3-pip curl wget git

# Create Python 3.11 venv
echo "[3/7] Creating Python 3.11 venv..."
VENV_DIR="/root/moshi-venv"
if [ ! -d "$VENV_DIR" ]; then
    python3.11 -m venv "$VENV_DIR"
fi
source "$VENV_DIR/bin/activate"
pip install --upgrade pip setuptools wheel

# Install PyTorch with CUDA
echo "[4/7] Installing PyTorch (this takes a while)..."
pip install torch --index-url https://download.pytorch.org/whl/cu128

# Install MoshiRAG
echo "[5/7] Installing MoshiRAG..."
pip install moshi-rag[server]
# Also grab conditioner deps
pip install moshi[conditioner] || true

# Install Ollama
echo "[6/7] Installing Ollama..."
if ! command -v ollama &>/dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
fi
# Pull the LLM model
ollama pull qwen3:4b

# Download MoshiRAG model
echo "[7/7] Downloading MoshiRAG model (~15GB)..."
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
echo "Next: ./start.sh"
