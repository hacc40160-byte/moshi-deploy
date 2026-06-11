# MoshiRAG One-Command Deploy

Battle-tested deployment for MoshiRAG on any fresh GPU machine.

**Tested on:** RTX 5090 32GB / 60GB disk / 93GB RAM

## What Gets Deployed

| Service | Port | Device | Purpose |
|---------|------|--------|---------|
| MoshiRAG Main | 8998 | GPU | Audio RAG server |
| Conditioner | 8001 | CPU | Reference encoder |
| Ollama | 11434 | CPU | LLM backend (qwen3:4b) |

## Quick Start

```bash
# 1. SSH into your fresh GPU machine
ssh -p PORT USER@HOST

# 2. Clone or upload this repo
git clone <this-repo> ~/moshi-deploy && cd ~/moshi-deploy

# 3. Set your HF token (for gated Llama 3.2 conditioner model)
export HF_TOKEN="hf_YOUR_TOKEN_HERE"

# 4. Run setup (installs everything, downloads models)
./setup.sh

# 5. Start all services
./start.sh

# 6. (Optional) Public URL via Cloudflare tunnel
./tunnel.sh
```

## Files

```
setup.sh       - One-time install: deps, models, venv, Ollama
start.sh       - Start all 3 services (conditioner → ollama → moshi)
stop.sh        - Graceful stop all services
restart.sh     - Stop + Start
tunnel.sh      - Cloudflare quick tunnel for public access
status.sh      - Health check all services
.env.template  - Environment variables (copy to .env)
```

## Key Discoveries (Battle-Tested)

- **batch-size 1** is required on 32GB cards — default causes CUDA OOM
- **Conditioner on CPU** — frees ~2GB VRAM for the main model
- **torch 2.9.1+cu128** works with RTX 5090
- **Python 3.11** required — 3.10 lacks asyncio.TaskGroup
- **HF classic token** required — Llama 3.2 is a gated model
- **Cloudflare quick tunnel** for free public URL (no account needed)
