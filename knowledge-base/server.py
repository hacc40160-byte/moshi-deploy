import os, json, hashlib, tempfile, re
from pathlib import Path
from typing import Optional
import chromadb
import requests
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse
from PyPDF2 import PdfReader
from bs4 import BeautifulSoup

app = FastAPI(title="Knowledge Base")

# Config
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434")
EMBED_MODEL = os.getenv("EMBED_MODEL", "nomic-embed-text")
DB_PATH = os.getenv("DB_PATH", "/root/knowledge-base/chromadb")
DATA_DIR = os.getenv("DATA_DIR", "/root/knowledge-base/data")

os.makedirs(DB_PATH, exist_ok=True)
os.makedirs(DATA_DIR, exist_ok=True)

# ChromaDB
client = chromadb.PersistentClient(path=DB_PATH)
collection = client.get_or_create_collection(
    name="knowledge",
    metadata={"hnsw:space": "cosine"}
)

def get_embedding(text: str) -> list:
    resp = requests.post(f"{OLLAMA_URL}/api/embeddings", json={
        "model": EMBED_MODEL, "prompt": text
    })
    resp.raise_for_status()
    return resp.json()["embedding"]

def chunk_text(text: str, small_size=200, large_size=500) -> list:
    """Multi-granularity chunking: both small and large chunks."""
    words = text.split()
    chunks = []
    # Small chunks (precise matching)
    for i in range(0, len(words), small_size):
        chunk = " ".join(words[i:i+small_size])
        if len(chunk.strip()) > 50:
            chunks.append({"text": chunk, "size": "small"})
    # Large chunks (broader context)
    for i in range(0, len(words), large_size):
        chunk = " ".join(words[i:i+large_size])
        if len(chunk.strip()) > 50:
            chunks.append({"text": chunk, "size": "large"})
    return chunks

def extract_text_from_file(filepath: str, filename: str) -> str:
    ext = filename.lower().split(".")[-1]
    if ext == "pdf":
        reader = PdfReader(filepath)
        return "\n".join(p.extract_text() or "" for p in reader.pages)
    elif ext in ("txt", "md", "csv", "json"):
        with open(filepath, "r", errors="ignore") as f:
            return f.read()
    return ""

def extract_text_from_url(url: str) -> str:
    resp = requests.get(url, timeout=30, headers={"User-Agent": "Mozilla/5.0"})
    resp.raise_for_status()
    if "text/html" in resp.headers.get("content-type", ""):
        soup = BeautifulSoup(resp.text, "html.parser")
        for tag in soup(["script", "style", "nav", "footer", "header"]):
            tag.decompose()
        return soup.get_text(separator="\n", strip=True)
    return resp.text

def store_chunks(source: str, text: str):
    chunks = chunk_text(text)
    if not chunks:
        return 0
    ids = []
    docs = []
    metas = []
    embeddings = []
    for i, c in enumerate(chunks):
        chunk_id = hashlib.md5(f"{source}_{c['size']}_{i}".encode()).hexdigest()
        ids.append(chunk_id)
        docs.append(c["text"])
        metas.append({"source": source, "chunk_size": c["size"], "index": i})
        embeddings.append(get_embedding(c["text"]))
    collection.upsert(ids=ids, documents=docs, metadatas=metas, embeddings=embeddings)
    return len(chunks)

@app.get("/", response_class=HTMLResponse)
async def ui():
    return UI_HTML

@app.post("/upload")
async def upload(file: UploadFile = File(...)):
    with tempfile.NamedTemporaryFile(delete=False, suffix="_" + file.filename) as tmp:
        content = await file.read()
        tmp.write(content)
        tmp_path = tmp.name
    try:
        text = extract_text_from_file(tmp_path, file.filename)
        if not text.strip():
            raise HTTPException(400, "Could not extract text from file")
        count = store_chunks(file.filename, text)
        # Also save original
        save_path = os.path.join(DATA_DIR, file.filename)
        with open(save_path, "wb") as f:
            f.write(content)
        return {"status": "ok", "chunks": count, "source": file.filename}
    finally:
        os.unlink(tmp_path)

@app.post("/url")
async def add_url(url: str = Form(...)):
    text = extract_text_from_url(url)
    if not text.strip():
        raise HTTPException(400, "Could not extract text from URL")
    count = store_chunks(url, text)
    return {"status": "ok", "chunks": count, "source": url}

@app.post("/text")
async def add_text(text: str = Form(...), name: str = Form("pasted_text")):
    count = store_chunks(name, text)
    return {"status": "ok", "chunks": count, "source": name}

@app.post("/query")
async def query(q: str = Form(...), n_results: int = Form(5)):
    embedding = get_embedding(q)
    results = collection.query(query_embeddings=[embedding], n_results=n_results)
    items = []
    for i in range(len(results["ids"][0])):
        items.append({
            "text": results["documents"][0][i],
            "source": results["metadatas"][0][i].get("source", ""),
            "distance": results["distances"][0][i] if results.get("distances") else None
        })
    return {"query": q, "results": items}

@app.get("/stats")
async def stats():
    return {"total_chunks": collection.count()}

@app.delete("/clear")
async def clear():
    client.delete_collection("knowledge")
    global collection
    collection = client.get_or_create_collection(name="knowledge", metadata={"hnsw:space": "cosine"})
    return {"status": "cleared"}

UI_HTML = """<!DOCTYPE html>
<html><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Knowledge Base</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#0a0a0a;color:#e0e0e0;min-height:100vh;padding:20px}
.container{max-width:900px;margin:0 auto}
h1{color:#00d4ff;margin-bottom:8px;font-size:28px}
.sub{color:#888;margin-bottom:24px;font-size:14px}
.tabs{display:flex;gap:8px;margin-bottom:20px}
.tab{padding:10px 20px;background:#1a1a1a;border:1px solid #333;border-radius:8px;cursor:pointer;color:#aaa;font-size:14px;transition:.2s}
.tab:hover{border-color:#00d4ff;color:#fff}
.tab.active{background:#00d4ff22;border-color:#00d4ff;color:#00d4ff}
.panel{display:none;background:#141414;border:1px solid #333;border-radius:12px;padding:24px;margin-bottom:16px}
.panel.active{display:block}
input[type=text],textarea,input[type=file]{width:100%;padding:12px;background:#1a1a1a;border:1px solid #333;border-radius:8px;color:#e0e0e0;font-size:14px;margin-bottom:12px}
textarea{min-height:120px;resize:vertical}
input[type=file]{padding:8px}
button{padding:12px 24px;background:#00d4ff;color:#000;border:none;border-radius:8px;font-weight:600;cursor:pointer;font-size:14px;transition:.2s}
button:hover{background:#00b8d4}
button:disabled{opacity:.5;cursor:not-allowed}
.results{margin-top:16px}
.result{background:#1a1a1a;border:1px solid #333;border-radius:8px;padding:16px;margin-bottom:12px}
.result .src{color:#00d4ff;font-size:12px;margin-bottom:8px;word-break:break-all}
.result .txt{color:#ccc;font-size:14px;line-height:1.6}
.stats{display:flex;gap:16px;margin-bottom:20px}
.stat{background:#1a1a1a;border:1px solid #333;border-radius:8px;padding:16px;flex:1;text-align:center}
.stat .num{font-size:28px;color:#00d4ff;font-weight:700}
.stat .lbl{color:#888;font-size:12px;margin-top:4px}
.msg{padding:12px;border-radius:8px;margin-bottom:12px;font-size:14px}
.msg.ok{background:#00d4ff22;color:#00d4ff;border:1px solid #00d4ff44}
.msg.err{background:#ff444422;color:#ff6666;border:1px solid #ff444444}
.loader{display:inline-block;width:16px;height:16px;border:2px solid #333;border-top:2px solid #00d4ff;border-radius:50%;animation:spin .6s linear infinite;margin-right:8px}
@keyframes spin{to{transform:rotate(360deg)}}
</style>
</head><body>
<div class="container">
<h1>\U0001f4da Knowledge Base</h1>
<p class="sub">Upload docs, paste URLs, or add text — then ask questions</p>
<div class="stats">
<div class="stat"><div class="num" id="count">-</div><div class="lbl">Chunks Stored</div></div>
</div>
<div class="tabs">
<div class="tab active" onclick="showTab('upload')">\U0001f4c1 Upload File</div>
<div class="tab" onclick="showTab('url')">\U0001f310 Add URL</div>
<div class="tab" onclick="showTab('text')">\U0000270f Paste Text</div>
<div class="tab" onclick="showTab('ask')">\U0001f4ac Ask</div>
</div>
<div id="panel-upload" class="panel active">
<h3 style="color:#fff;margin-bottom:12px">Upload a Document</h3>
<input type="file" id="file" accept=".pdf,.txt,.md,.csv,.json">
<button onclick="uploadFile()">Upload & Learn</button>
<div id="msg-upload"></div>
</div>
<div id="panel-url" class="panel">
<h3 style="color:#fff;margin-bottom:12px">Add from URL</h3>
<input type="text" id="url" placeholder="https://example.com/article">
<button onclick="addUrl()">Fetch & Learn</button>
<div id="msg-url"></div>
</div>
<div id="panel-text" class="panel">
<h3 style="color:#fff;margin-bottom:12px">Paste Text</h3>
<input type="text" id="textname" placeholder="Name (optional)">
<textarea id="textbody" placeholder="Paste your text here..."></textarea>
<button onclick="addText()">Learn Text</button>
<div id="msg-text"></div>
</div>
<div id="panel-ask" class="panel">
<h3 style="color:#fff;margin-bottom:12px">Ask a Question</h3>
<input type="text" id="question" placeholder="What do you want to know?">
<button onclick="askQuestion()">Search</button>
<div id="msg-ask"></div>
<div class="results" id="results"></div>
</div>
</div>
<script>
function showTab(t){document.querySelectorAll('.tab').forEach((e,i)=>{e.classList.toggle('active',['upload','url','text','ask'][i]===t)});document.querySelectorAll('.panel').forEach((e,i)=>{e.classList.toggle('active',['upload','url','text','ask'][i]===t)})}
function msg(id,text,ok){document.getElementById('msg-'+id).innerHTML='<div class="msg '+(ok?'ok':'err')+'">'+text+'</div>'}
async function uploadFile(){const f=document.getElementById('file').files[0];if(!f)return msg('upload','Select a file first',0);const fd=new FormData();fd.append('file',f);msg('upload','<span class="loader"></span> Learning...',1);try{const r=await fetch('/upload',{method:'POST',body:fd});const j=await r.json();if(r.ok){msg('upload','\u2705 Learned '+j.chunks+' chunks from '+j.source,1);loadStats()}else{msg('upload','\u274c '+j.detail,0)}}catch(e){msg('upload','\u274c '+e.message,0)}}
async function addUrl(){const u=document.getElementById('url').value;if(!u)return msg('url','Enter a URL first',0);const fd=new FormData();fd.append('url',u);msg('url','<span class="loader"></span> Fetching & learning...',1);try{const r=await fetch('/url',{method:'POST',body:fd});const j=await r.json();if(r.ok){msg('url','\u2705 Learned '+j.chunks+' chunks from URL',1);loadStats()}else{msg('url','\u274c '+j.detail,0)}}catch(e){msg('url','\u274c '+e.message,0)}}
async function addText(){const t=document.getElementById('textbody').value;if(!t)return msg('text','Paste some text first',0);const n=document.getElementById('textname').value||'pasted_text';const fd=new FormData();fd.append('text',t);fd.append('name',n);msg('text','<span class="loader"></span> Learning...',1);try{const r=await fetch('/text',{method:'POST',body:fd});const j=await r.json();if(r.ok){msg('text','\u2705 Learned '+j.chunks+' chunks',1);loadStats()}else{msg('text','\u274c '+j.detail,0)}}catch(e){msg('text','\u274c '+e.message,0)}}
async function askQuestion(){const q=document.getElementById('question').value;if(!q)return;msg('ask','<span class="loader"></span> Searching...',1);const fd=new FormData();fd.append('q',q);try{const r=await fetch('/query',{method:'POST',body:fd});const j=await r.json();let h='';j.results.forEach(r=>{h+='<div class="result"><div class="src">'+r.source+'</div><div class="txt">'+r.text+'</div></div>'});document.getElementById('results').innerHTML=h;msg('ask','') }catch(e){msg('ask','\u274c '+e.message,0)}}
async function loadStats(){try{const r=await fetch('/stats');const j=await r.json();document.getElementById('count').textContent=j.total_chunks}catch(e){}}
loadStats();
document.getElementById('question').addEventListener('keydown',e=>{if(e.key==='Enter')askQuestion()});
</script>
</body></html>"""

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8500)
