"""
LAB513 — FAQ Assistant web interface.

A minimal, self-contained chat UI that runs the RAG agent end-to-end:
    user question -> SearchFAQ (Azure SQL) -> grounded prompt -> o4-mini -> answer

Reuses the SAME logic as Module 3 of the runbook. No Copilot, no Foundry,
no extra pip packages — only pyodbc (already installed), the Azure CLI login,
and the Python standard library.

Run:
    cd workshop
    python faq_agent_app.py
Then open http://localhost:8000 in your browser.

Requires: `az login` already done (as your workshop SQL user).
"""
import json
import struct
import subprocess
import urllib.request
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

# ---------------------------------------------------------------- config
CFG_PATH = Path(__file__).with_name("student.config.local.json")
if not CFG_PATH.exists():
    raise SystemExit(f"Config not found: {CFG_PATH}. Run the runbook Configuration cell first.")

_cfg = json.loads(CFG_PATH.read_text(encoding="utf-8"))
SQL_SERVER = _cfg["sql_server"]
SQL_DATABASE = _cfg["sql_database"]
OPENAI_ENDPOINT = _cfg["openai_endpoint"].rstrip("/")
CHAT_DEPLOYMENT = _cfg["chat_deployment"]
CHAT_API_VERSION = _cfg["chat_api_version"]

SQL_COPT_SS_ACCESS_TOKEN = 1256
PORT = 8000
TOP_K = 3

SYSTEM_PROMPT = (
    "You are a FAQ assistant. Answer ONLY using the FAQ context below. "
    "If the answer is not in the context, say 'I don't have that information.' "
    "Do NOT make up information."
)


# ---------------------------------------------------------------- helpers (same as the runbook)
def get_access_token(resource: str) -> str:
    result = subprocess.run(
        f'az account get-access-token --resource "{resource}" --query accessToken -o tsv',
        shell=True, text=True, capture_output=True, encoding="utf-8", errors="replace",
    )
    if result.returncode != 0:
        raise RuntimeError(f"Could not get token for {resource}. Run 'az login' first.\n{result.stderr}")
    return result.stdout.strip()


def _pick_sql_driver() -> str:
    import pyodbc
    installed = [d for d in pyodbc.drivers() if "for SQL Server" in d]
    for preferred in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server"):
        if preferred in installed:
            return preferred
    if installed:
        return installed[-1]
    raise RuntimeError("No 'ODBC Driver for SQL Server' found. Install ODBC Driver 18.")


def _sql_connect():
    import pyodbc
    token = get_access_token("https://database.windows.net/")
    token_bytes = token.encode("utf-16-le")
    token_struct = struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)
    conn_str = (
        f"Driver={{{_pick_sql_driver()}}};"
        f"Server=tcp:{SQL_SERVER},1433;Database={SQL_DATABASE};"
        "Encrypt=yes;TrustServerCertificate=no;"
    )
    return pyodbc.connect(conn_str, attrs_before={SQL_COPT_SS_ACCESS_TOKEN: token_struct})


def search_faq(question: str, top_k: int = TOP_K):
    conn = _sql_connect()
    try:
        cur = conn.cursor()
        cur.execute("EXEC dbo.SearchFAQ @Question = ?, @TopK = ?;", (question, top_k))
        cols = [c[0] for c in cur.description]
        return [dict(zip(cols, r)) for r in cur.fetchall()]
    finally:
        conn.close()


def build_context(rows) -> str:
    return "\n\n".join(f"Q: {r['question']}\nA: {r['answer']}" for r in rows)


def ask_grounded(question: str):
    rows = search_faq(question)
    context = build_context(rows)
    token = get_access_token("https://cognitiveservices.azure.com")
    # o4-mini is a reasoning model — only the default temperature is allowed (no temperature param).
    body = json.dumps({
        "messages": [
            {"role": "system", "content": f"{SYSTEM_PROMPT}\n\nFAQ CONTEXT:\n{context}"},
            {"role": "user", "content": question},
        ],
    }).encode()
    req = urllib.request.Request(
        f"{OPENAI_ENDPOINT}/openai/deployments/{CHAT_DEPLOYMENT}/chat/completions?api-version={CHAT_API_VERSION}",
        data=body, method="POST",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as resp:
        answer = json.loads(resp.read())["choices"][0]["message"]["content"]
    return answer, rows


# ---------------------------------------------------------------- web UI
PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>LAB513 FAQ Assistant</title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body { font-family: system-ui, Segoe UI, sans-serif; margin: 0; background: #0f172a; color: #e2e8f0;
         display: flex; flex-direction: column; height: 100vh; }
  header { padding: 16px 20px; background: #1e293b; border-bottom: 1px solid #334155; }
  header h1 { margin: 0; font-size: 18px; } header p { margin: 4px 0 0; font-size: 13px; color: #94a3b8; }
  #chat { flex: 1; overflow-y: auto; padding: 20px; display: flex; flex-direction: column; gap: 14px; }
  .msg { max-width: 720px; padding: 12px 16px; border-radius: 12px; line-height: 1.5; white-space: pre-wrap; }
  .user { align-self: flex-end; background: #2563eb; color: #fff; border-bottom-right-radius: 3px; }
  .bot  { align-self: flex-start; background: #1e293b; border: 1px solid #334155; border-bottom-left-radius: 3px; }
  .sources { font-size: 12px; color: #94a3b8; margin-top: 8px; border-top: 1px dashed #334155; padding-top: 6px; }
  form { display: flex; gap: 10px; padding: 16px 20px; background: #1e293b; border-top: 1px solid #334155; }
  input { flex: 1; padding: 12px 14px; border-radius: 10px; border: 1px solid #334155; background: #0f172a;
          color: #e2e8f0; font-size: 15px; }
  button { padding: 12px 20px; border: none; border-radius: 10px; background: #2563eb; color: #fff;
           font-size: 15px; cursor: pointer; } button:disabled { opacity: .5; cursor: default; }
</style></head>
<body>
  <header>
    <h1>&#129302; LAB513 FAQ Assistant</h1>
    <p>RAG agent &middot; Azure SQL retrieval &rarr; o4-mini grounded answers. Ask a support question.</p>
  </header>
  <div id="chat">
    <div class="msg bot">Hi! Ask me a support question, e.g. <em>"How do I reset my password?"</em>
I only answer from the FAQ knowledge base &mdash; if it's not there, I'll tell you.</div>
  </div>
  <form id="f">
    <input id="q" autocomplete="off" placeholder="Type your question..." autofocus>
    <button id="send" type="submit">Send</button>
  </form>
<script>
const chat = document.getElementById('chat'), form = document.getElementById('f'),
      input = document.getElementById('q'), send = document.getElementById('send');
function add(text, cls, sources) {
  const d = document.createElement('div'); d.className = 'msg ' + cls; d.textContent = text;
  if (sources && sources.length) {
    const s = document.createElement('div'); s.className = 'sources';
    s.textContent = 'Sources: ' + sources.map(r => r.question + ' (' + r.similarity_score + ')').join('  |  ');
    d.appendChild(s);
  }
  chat.appendChild(d); chat.scrollTop = chat.scrollHeight; return d;
}
form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const q = input.value.trim(); if (!q) return;
  add(q, 'user'); input.value = ''; send.disabled = true;
  const thinking = add('Thinking...', 'bot');
  try {
    const res = await fetch('/ask', { method: 'POST', headers: {'Content-Type':'application/json'},
                                      body: JSON.stringify({ question: q }) });
    const data = await res.json();
    thinking.remove();
    if (data.error) add('Error: ' + data.error, 'bot');
    else add(data.answer, 'bot', data.sources);
  } catch (err) { thinking.remove(); add('Request failed: ' + err, 'bot'); }
  send.disabled = false; input.focus();
});
</script>
</body></html>"""


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            self._send(200, PAGE, "text/html; charset=utf-8")
        else:
            self._send(404, "not found", "text/plain")

    def do_POST(self):
        if self.path != "/ask":
            self._send(404, json.dumps({"error": "not found"}))
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            payload = json.loads(self.rfile.read(length) or b"{}")
            question = (payload.get("question") or "").strip()
            if not question:
                self._send(400, json.dumps({"error": "empty question"}))
                return
            answer, rows = ask_grounded(question)
            sources = [{"question": r["question"], "similarity_score": r["similarity_score"]} for r in rows]
            self._send(200, json.dumps({"answer": answer, "sources": sources}))
        except Exception as exc:  # noqa: BLE001 — surface any error to the UI
            self._send(200, json.dumps({"error": str(exc)}))

    def log_message(self, *args):  # quieter console
        return


if __name__ == "__main__":
    print(f"FAQ Assistant running at  http://localhost:{PORT}")
    print("Make sure 'az login' is your workshop SQL user. Press Ctrl+C to stop.")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
