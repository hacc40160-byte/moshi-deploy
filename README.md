# MoshiRAG + Knowledge Base — One-Command Deploy

Zero-error deploy for fresh GPU machines. Pull, configure, run.

## What's Included

- **MoshiRAG** — voice AI agent (GPU, port 8999)
- **Knowledge Base** — document upload + semantic search (CPU, port 8500)
- **Nginx** — reverse proxy (port 80): `/` → MoshiRAG, `/kb/` → Knowledge Base
- **Cloudflare Tunnel** — free public URL (auto-generated)
- **Ollama** — local LLM backend (qwen3:4b + nomic-embed-text)

## Quick Start (Fresh GPU)

```bash
# 1. Clone
git clone https://github.com/hacc40160-byte/moshi-deploy.git
cd moshi-deploy

# 2. Configure
cp .env.template .env
nano .env  # Add your HF_TOKEN

# 3. Setup (one-time, ~15 min)
chmod +x setup.sh start.sh stop.sh
./setup.sh

# 4. Start
./start.sh
```

## After Start

```
  MoshiRAG:       http://localhost:8999
  Knowledge Base: http://localhost:8500
  Nginx (local):  http://localhost:80
  Public URL:     https://xxx.trycloudflare.com

  https://xxx.trycloudflare.com/       → MoshiRAG
  https://xxx.trycloudflare.com/kb/    → Knowledge Base UI
```

## Knowledge Base Features

- 📁 Upload files (PDF, txt, md, csv, json)
- 🌐 Paste any URL → auto-scrapes and learns
- ✏️ Paste raw text directly
- 🔍 Semantic search with multi-granularity chunks
- 🗑️ Clear all data
- OpenAI-compatible endpoint at `/v1/chat/completions`

## Commands

| Command | What it does |
|---------|-------------|
| `./start.sh` | Start all services + tunnel |
| `./stop.sh` | Stop all services |
| `./status.sh` | Check what's running |
| `./restart.sh` | Stop + Start |

## Architecture

```
User Browser
    │
    ▼
Cloudflare Tunnel (free public URL)
    │
    ▼
Nginx (:80)
    ├── /      → MoshiRAG (:8999, GPU)
    └── /kb/   → Knowledge Base (:8500, CPU)
                      │
                      ▼
                 Ollama (:11434)
                 ├── qwen3:4b (LLM)
                 └── nomic-embed-text (embeddings)
```

## Requirements

- NVIDIA GPU (24GB+ VRAM recommended)
- Python 3.11
- ~30GB disk (model + deps)
- HuggingFace token

## Files

```
moshi-deploy/
├── .env.template        # Config template
├── setup.sh             # One-time install
├── start.sh             # Start all services
├── stop.sh              # Stop all services
├── status.sh            # Check status
├── restart.sh           # Restart all
├── nginx.conf           # Reverse proxy config
├── requirements.txt     # Python deps (MoshiRAG)
├── knowledge-base/
│   ├── server.py        # Knowledge Base FastAPI server
│   ├── venv/            # (created by setup.sh)
│   ├── chromadb/        # Vector store
│   └── data/            # Uploaded files
└── README.md
```
