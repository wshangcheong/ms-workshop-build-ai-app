# 🎓 Student Guide — LAB513 AI-Powered FAQ Assistant Workshop

> **Duration:** ~2 hours 45 minutes (7 modules)  
> **Goal:** Build an AI-powered FAQ assistant using Azure SQL vector search, RAG, Foundry Agents, Microsoft Fabric, MCP, and a chat interface.

---

## 🏗️ Architecture Overview

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Azure SQL      │────▶│  Azure OpenAI    │────▶│  Foundry Agent  │
│  Hyperscale     │     │  (o4-mini +      │     │  (MCP tools)    │
│  + Vectors      │     │   embeddings)    │     │                 │
└────────┬────────┘     └──────────────────┘     └─────────────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────────┐
│  Microsoft      │────▶│  Power BI        │
│  Fabric Mirror  │     │  Report          │
└─────────────────┘     └──────────────────┘
```

---

## ⚙️ Your Environment

| Resource | Value |
|----------|-------|
| **Region** | swedencentral |
| **SQL Auth** | Microsoft Entra ID only (no passwords) |
| **AI Model** | o4-mini (API version: `2025-01-01-preview`) |
| **Embeddings** | text-embedding-ada-002 (1536 dimensions) |
| **SQL Tier** | General Purpose Serverless (auto-pauses after 60 min) |

> 📝 Your instructor will provide: SQL Server FQDN, OpenAI endpoint, tenant ID, and subscription ID.

---

## Module 0 — Prerequisites & Setup (15 min)

### 🎯 Objective
Verify all tools, accounts, and services are ready.

### ⚠️ Pre-Requisites
- Azure account with access to the workshop subscription
- VS Code installed on your machine
- Internet access for Azure and GitHub

### 📝 Steps

1. **Install tools** (if not already done):

   **Easiest — no terminal needed:** in the repo folder, **double-click `bootstrap.cmd`**.
   It uses the PowerShell already built into Windows, so you don't need Python or
   PowerShell 7 first — it installs everything for you. Wait for **`BOOTSTRAP COMPLETE`**.

   **Or from a terminal:**
   ```powershell
   # From repo root, run the bootstrap script
   .\workshop\bootstrap.ps1
   ```
   > If script execution is blocked, run:
   > `irm https://raw.githubusercontent.com/MSLab513/MS-LAB513-Student/main/workshop/bootstrap.ps1 | iex`

   The bootstrap installs the CLI tools (Azure CLI, Python, .NET SDK, Dev Tunnel CLI, …),
   the ODBC Driver 18 for SQL Server, the VS Code extensions (incl. Jupyter), and installs
   Python dependencies into your current local Python environment for the runbook notebook and the Module 4 MCP server.

2. **Login to Azure:**
   ```powershell
   az login --tenant <tenant-id-from-instructor>
   az account set --subscription <subscription-id-from-instructor>
   ```

3. **Verify your identity:**
   ```powershell
   az ad signed-in-user show --query "{name:displayName, upn:userPrincipalName}" -o table
   ```

4. **Verify lab files are present:**
   ```powershell
   Test-Path .\sql\searchfaq.sql
   Test-Path .\tools\sql_mcp_server\server.py
   ```
   > Both commands must return `True`.

5. **Connect VS Code to SQL:**
   - Open SQL Server extension → Add Connection
   - Server: `<your-sql-server>.database.windows.net`
   - Database: `faq-ai-assistant-db`
   - Authentication: **Azure Active Directory**

6. **Verify database is seeded:**
   ```sql
   SELECT COUNT(*) AS FAQ_Count FROM dbo.FAQ_Content;
   -- Expected: 15+ records
   ```

7. **Test OpenAI connectivity:**
   ```powershell
   $token = az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv
   $headers = @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" }
   $body = '{"messages":[{"role":"user","content":"Hello"}]}'
   Invoke-RestMethod -Uri "<your-endpoint>/openai/deployments/o4-mini/chat/completions?api-version=2025-01-01-preview" -Headers $headers -Method Post -Body $body
   ```

### ✅ Verification Checklist
- [ ] `az account show` returns the workshop subscription
- [ ] SQL connection works via VS Code
- [ ] `FAQ_Content` has 15+ records
- [ ] OpenAI o4-mini responds to a test message

---

## Module 1 — AI-Enhanced Querying with Azure SQL (20 min)

### 🎯 Objective
Explore FAQ data, generate embeddings, and run FAQ retrieval with relevance scoring.

### ⚠️ Dependencies
- Module 0 completed (SQL connection working)

### 📝 Steps

1. **Explore FAQ content:**
   ```sql
   SELECT TOP 10 id, category, question, LEFT(answer, 100) AS answer_preview
   FROM dbo.FAQ_Content ORDER BY category;
   ```

2. **Create embeddings table and search objects:**
   ```sql
   IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'FAQ_Embeddings')
   BEGIN
       CREATE TABLE dbo.FAQ_Embeddings (
           id INT IDENTITY(1,1) PRIMARY KEY,
           content_id INT NOT NULL,
           embedding VARBINARY(MAX) NOT NULL,
           model_name NVARCHAR(100) NOT NULL DEFAULT 'text-embedding-ada-002',
           dimensions INT NOT NULL DEFAULT 1536,
           created_at DATETIME2 NOT NULL DEFAULT GETUTCDATE()
       );
   END;

   ```

3. **Create search procedure and function:**
   - In VS Code SQL extension, open and run: `.\sql\searchfaq.sql`

4. **Generate embeddings for each FAQ (manual student step):**
   ```powershell
   # Requires: az login already done in Module 0
   $sqlServer = "<your-sql-server>.database.windows.net"
   $db = "faq-ai-assistant-db"
   $endpoint = "<your-openai-endpoint>"   # e.g. https://ai-xxxxx.openai.azure.com/

   $sqlToken = az account get-access-token --resource "https://database.windows.net/" --query accessToken -o tsv
   $aoaiToken = az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv

   $conn = New-Object System.Data.SqlClient.SqlConnection
   $conn.ConnectionString = "Server=tcp:$sqlServer,1433;Database=$db;Encrypt=True;TrustServerCertificate=False;"
   $conn.AccessToken = $sqlToken
   $conn.Open()

   $q = $conn.CreateCommand()
   $q.CommandText = "SELECT id, question, answer FROM dbo.FAQ_Content;"
   $r = $q.ExecuteReader()
   $rows = @()
   while ($r.Read()) { $rows += [pscustomobject]@{ id=$r["id"]; text=("$($r["question"])`n$($r["answer"])") } }
   $r.Close()

   foreach ($row in $rows) {
     $headers = @{ Authorization = "Bearer $aoaiToken"; "Content-Type" = "application/json" }
     $body = @{ input = $row.text } | ConvertTo-Json
     $resp = Invoke-RestMethod -Method Post -Uri "$endpoint/openai/deployments/text-embedding-ada-002/embeddings?api-version=2024-10-21" -Headers $headers -Body $body
     $vec = [System.Text.Encoding]::UTF8.GetBytes(($resp.data[0].embedding | ConvertTo-Json -Compress))

     $ins = $conn.CreateCommand()
     $ins.CommandText = "IF EXISTS (SELECT 1 FROM dbo.FAQ_Embeddings WHERE content_id=@id) UPDATE dbo.FAQ_Embeddings SET embedding=@e, model_name='text-embedding-ada-002', dimensions=1536 WHERE content_id=@id ELSE INSERT INTO dbo.FAQ_Embeddings (content_id, embedding, model_name, dimensions) VALUES (@id,@e,'text-embedding-ada-002',1536);"
     $null = $ins.Parameters.AddWithValue("@id", [int]$row.id)
     $null = $ins.Parameters.AddWithValue("@e", $vec)
     $ins.ExecuteNonQuery() | Out-Null
   }
   $conn.Close()
   Write-Host "Embeddings generated for $($rows.Count) FAQ rows."
   ```

5. **Inspect vector embeddings:**
   ```sql
   SELECT TOP 5 id, content_id, DATALENGTH(embedding) AS embedding_bytes
   FROM dbo.FAQ_Embeddings;
   ```

6. **Verify row counts match:**
   ```sql
   SELECT 'FAQ_Content' AS TableName, COUNT(*) AS Rows FROM dbo.FAQ_Content
   UNION ALL
   SELECT 'FAQ_Embeddings', COUNT(*) FROM dbo.FAQ_Embeddings;
   ```

7. **Run retrieval search:**
   ```sql
   EXEC dbo.SearchFAQ @Question = 'How do I reset my password?';
   EXEC dbo.SearchFAQ @Question = 'What payment methods do you accept?';
   EXEC dbo.SearchFAQ @Question = 'My account is locked';
   ```

8. **Compare keyword vs retrieval search:**
   ```sql
   -- Keyword (exact match only)
   SELECT question, answer FROM dbo.FAQ_Content WHERE question LIKE '%password%';

   -- Retrieval scoring
   EXEC dbo.SearchFAQ @Question = 'I forgot my login credentials';
   ```
   > 💡 Retrieval scoring ranks likely FAQ matches for RAG grounding.

### ✅ Verification Checklist
- [ ] FAQ_Content returns 15+ rows
- [ ] Embeddings are generated for FAQ rows
- [ ] FAQ_Embeddings has matching record count
- [ ] SearchFAQ returns relevant results
- [ ] Retrieval scoring matches intent better than raw keyword search

---

## Module 2 — Copilot-Assisted SQL Development (15 min)

### 🎯 Objective
Use GitHub Copilot Chat to generate, explain, and refine SQL queries.

### ⚠️ Dependencies
- Module 0 completed (Copilot extension active)
- Module 1 completed (understand the FAQ schema)

### 📝 Steps

1. **Open Copilot Chat** (Ctrl+Shift+I)

2. **Generate a semantic search query:**
   > Ask: "Generate a SQL query that performs FAQ retrieval scoring on FAQ_Content using terms from the user question and returns top 3 results."

3. **Ask Copilot to explain the query:**
   > Ask: "Explain this query step by step, especially the cosine similarity calculation."

4. **Refine for production:**
   > Ask: "Add comments, meaningful aliases, a similarity threshold of 0.7, and format for readability."

5. **Generate a stored procedure:**
   > Ask: "Create a stored procedure SearchFAQv2 with @Question and @TopK parameters, including error handling."

6. **Compare** Copilot's output to the validated `SearchFAQ` procedure from Module 1.

### ✅ Verification Checklist
- [ ] Copilot generates syntactically correct SQL
- [ ] Generated query references correct table/column names
- [ ] Explanation is clear and matches your understanding
- [ ] You understand the difference between AI-generated vs validated SQL

> ⚠️ **Remember:** Always verify AI-generated SQL before executing. The lab's tested queries are your ground truth.

---

## Module 3 — RAG Implementation (25 min)

### 🎯 Objective
Build a Retrieval-Augmented Generation pipeline: retrieve FAQ context, augment a prompt, and generate grounded AI responses.

### ⚠️ Dependencies
- Module 1 completed (SearchFAQ working)
- OpenAI endpoint accessible (Module 0 verified)

### ⚠️ Pre-Check
```powershell
# Ensure you can get an OpenAI token
az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv
```

### 📝 Steps

1. **Retrieve relevant FAQ content:**
   ```sql
   EXEC dbo.SearchFAQ @Question = 'How do I get a refund?', @TopK = 3;
   ```

2. **Build grounding context:**
   ```sql
   DECLARE @UserQuestion NVARCHAR(500) = 'How do I get a refund?';
   DECLARE @Context NVARCHAR(MAX);

   SELECT @Context = STRING_AGG(
       CONCAT('Q: ', question, CHAR(10), 'A: ', answer), CHAR(10) + CHAR(10)
   )
   FROM (
       SELECT TOP 3 fc.question, fc.answer
       FROM dbo.SearchFAQ_TVF(@UserQuestion) fe
       JOIN dbo.FAQ_Content fc ON fe.content_id = fc.id
       ORDER BY fe.similarity_score DESC
   ) results;

   SELECT @Context AS GroundingContext;
   ```

3. **Construct grounded prompt:**
   ```
   System: "You are a FAQ assistant. Answer ONLY using the FAQ context below.
   If the answer is not in the context, say 'I don't have that information.'
   Do NOT make up information."

   + FAQ Context from Step 2

   User: "How do I get a refund?"
   ```

4. **Call o4-mini via sp_invoke_external_rest_endpoint** (or via PowerShell):
   ```powershell
   $token = az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv
   $headers = @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" }
   $body = @{
       messages = @(
           @{ role = "system"; content = "<your grounded system prompt>" }
           @{ role = "user"; content = "How do I get a refund?" }
       )
   } | ConvertTo-Json -Depth 3
   # NOTE: o4-mini is a reasoning model — it only supports the DEFAULT temperature.
   # Do NOT send a temperature parameter (sending one returns HTTP 400).

   Invoke-RestMethod -Uri "<endpoint>/openai/deployments/o4-mini/chat/completions?api-version=2025-01-01-preview" -Headers $headers -Method Post -Body $body
   ```

5. **Test with unsupported questions:**
   ```
   "What's the weather today?" → Should respond: "I don't have that information"
   "Tell me about company history" → Should decline
   ```

### ✅ Verification Checklist
- [ ] Search returns relevant FAQ context
- [ ] Grounded prompt constrains AI to FAQ content
- [ ] AI response only references provided context
- [ ] Unsupported questions get "I don't have that information"
- [ ] No hallucinations observed

---

## Module 4 — Foundry Agent Orchestration (25 min)

### 🎯 Objective
Create a Microsoft Foundry Agent that uses MCP tool calls to retrieve FAQ answers.

### ⚠️ Dependencies
- Module 3 completed (understand RAG pattern)
- Python 3.10+ installed
- Dev Tunnels CLI installed

### ⚠️ Pre-Check
```powershell
Test-Path ".\tools\sql_mcp_server\server.py"             # Must be True
python --version                                         # Must be 3.10+
devtunnel --version                                      # Must be installed
```

### 📝 Steps

1. **Start the MCP server:**
   ```powershell
   cd .\tools\sql_mcp_server
   pip install -r requirements.txt
   $env:SQL_SERVER = "<your-sql-server>.database.windows.net"
   $env:SQL_DATABASE = "faq-ai-assistant-db"
   $env:SQL_TOPK = "3"
   python server.py
   ```
   > Keep this terminal open!

2. **Create a dev tunnel** (new terminal):
   ```powershell
   devtunnel user login
   devtunnel create faq-tunnel --allow-anonymous
   devtunnel port create faq-tunnel -p 5000 --protocol http   # --protocol http is REQUIRED
   devtunnel host faq-tunnel
   ```
   > Copy the forwarding URL (e.g., `https://<name>-5000.<region>.devtunnels.ms`). Your MCP endpoint is that URL **+ `/mcp`**.
   > 🔑 The port MUST be created with `--protocol http` — without it, Foundry's **Connect** button stays greyed out.

3. **In Microsoft Foundry** (browser):
   - Open [ai.azure.com](https://ai.azure.com) → open the **`FAQ-Assistant-project`** project your instructor provided
   - **Build → Tools → Connect a tool → Custom → Model Context Protocol (MCP)**
   - Name: `faq-tool`; **Remote MCP Server endpoint:** `<tunnel-url>/mcp`; **Authentication: Unauthenticated**
   - **Connect** → **Use in an agent** → name it `faq-orchestrator-agent`
   - Grounding instructions:
     ```
     You MUST call the FAQ Search tool before answering.
     Only respond based on tool results.
     If no FAQ found, say "I don't have information about that."
     ```
   > 💡 The first time the agent uses the tool, Foundry shows an **Approve** prompt (human-in-the-loop) — click **Approve**. This is expected, not an error.

4. **Test with supported questions:**
   - "How do I reset my password?"
   - "What payment methods do you accept?"
   - Verify: agent calls tool → returns grounded answer

5. **Test with unsupported questions:**
   - "What's the weather?" → Should decline
   - "Write me a poem" → Should decline

### ✅ Verification Checklist
- [ ] MCP server running without errors
- [ ] Dev tunnel accessible from browser
- [ ] Foundry agent calls the MCP tool (visible in trace)
- [ ] Supported questions get FAQ-grounded answers
- [ ] Unsupported questions are properly declined

---

## Module 5 — Microsoft Fabric Integration (20 min)

### 🎯 Objective
Mirror Azure SQL data into Fabric, then analyze it with a Direct Lake semantic model and a Power BI report.

### ⚠️ Dependencies
- Module 1 completed (FAQ data in SQL)
- Microsoft Fabric access (verify in Module 0)
- A **Fabric capacity** — your instructor provisions one (`faqfabric<suffix>`). The self-service Fabric trial is blocked by tenant policy, so use the provided capacity.

### ⚠️ Provided by your instructor (no action needed from you)
- A **Fabric capacity** named `faqfabric<suffix>` — the self-service Fabric trial is disabled for this tenant, so use the capacity your instructor provisioned.
- The SQL server is already configured for mirroring (public network access + managed identity). If mirroring reports a configuration/identity error, **notify your instructor** — it's an infrastructure setting, not something you change.

### ⚠️ Pre-Check
- Navigate to [app.fabric.microsoft.com](https://app.fabric.microsoft.com) — confirm you can log in

### 📝 Steps

1. **Create a workspace and assign the Fabric capacity:**
   - Workspaces → **New workspace** → Name: `LAB513-<your-alias>-FAQ`
   - **Workspace settings → Workspace type → Edit → Fabric capacity → select `faqfabric<suffix>`** (Southeast Asia)
   - **Semantic model storage format:** leave **Small** → **Select**
   - (Ignore the "Start Fabric trial" button — it's policy-blocked and not needed)

2. **Create the mirrored database:**
   - **+ New item → Mirrored Azure SQL Database**
   - Server: `<your-sql-server>.database.windows.net`
   - Database: `faq-ai-assistant-db`
   - **Connection:** *Create new connection*, **Data gateway:** *(none)*
   - **Authentication kind: Organizational account** ← *not* Service principal
   - Confirm you're signed in as your workshop user (`<alias>@...`, the SQL Entra admin)
   - Click **Connect**

   > 🆘 If you see *"turn on the system-assigned managed identity …"*, this is a server setting your **instructor** enables — notify them, wait 1–2 min, then close the dialog and retry.
   > 🆘 If the screen asks for Tenant ID / client ID / key, you selected **Service principal** — switch back to **Organizational account**.

3. **Choose data and replicate:**
   - Select ✅ `dbo.FAQ_Content` (optionally `dbo.FAQ_Embeddings`) → **Connect**
   - **Wait for sync** (1–3 min) — table status goes to **Running / Replicated** (15 rows)

4. **Query via SQL analytics endpoint:**
   - Switch the item to its **SQL analytics endpoint** → **New SQL query**:
   ```sql
   SELECT category, COUNT(*) AS faq_count
   FROM dbo.FAQ_Content
   GROUP BY category ORDER BY faq_count DESC;
   ```

5. **Create a Direct Lake semantic model:**
   - From the SQL analytics endpoint → **New semantic model** → name `FAQ_Model`, select `FAQ_Content` → **Confirm**
   - (Direct Lake reads mirrored data from OneLake — no import/refresh)

6. **Build the Power BI report (category vs count):**
   - From the model → **Create report** → choose **Clustered column/bar chart**
   - Click the **Build visual** icon, then set:
     - **Axis** → `category`
     - **Values** → `id` → dropdown → **Count**
   - ⚠️ Putting `id` on the axis makes one bar per row (15 bars of 1). Use **category** on the axis + **Count of id** as the value.
   - **Save** → `FAQ Category Report` in your workspace

7. **Review data lineage:**
   - Switch to **Lineage view**
   - Observe: SQL → Mirror → Analytics endpoint → Semantic model → Report

### ✅ Verification Checklist
- [ ] Workspace created **and assigned to the Fabric capacity**
- [ ] Mirrored database connected with **Organizational account**, shows "Running/Replicated" (15 rows)
- [ ] SQL analytics endpoint returns FAQ data grouped by category
- [ ] **Direct Lake** semantic model created on `FAQ_Content`
- [ ] Report shows **count of FAQs per category**
- [ ] Lineage shows full data flow chain

### 🆘 Troubleshooting
| Issue | Fix |
|-------|-----|
| "Unable to start trial" | Expected — use the instructor's Fabric capacity (Workspace type = Fabric capacity). |
| No capacity to run mirroring | Assign the workspace to `faqfabric<suffix>`. |
| "turn on the system-assigned managed identity …" | Infrastructure setting — ask your instructor to enable it, then retry. |
| Asks for Tenant ID / client ID / key | Switch Authentication kind to **Organizational account**. |
| Connect fails / can't reach SQL | SQL networking is instructor-managed — notify your instructor if it persists. |
| Report shows one bar per row | Use **category** on axis + **Count of id** as value. |

---

## Module 6 — SQL MCP Server with Data API Builder (20 min)

### 🎯 Objective
Expose Azure SQL as an MCP-compatible tool using Data API Builder, queryable from VS Code Copilot Chat.

### ⚠️ Dependencies
- Module 0 completed (.NET SDK 8.0+)
- Python MCP server from Module 4 stopped

### ⚠️ Pre-Check
```powershell
dotnet --version    # Must be 8.0+
# Stop Python MCP server if still running
Get-Process python -ErrorAction SilentlyContinue | Stop-Process
```

### 📝 Steps

1. **Create working directory:**
   ```powershell
   mkdir .\sql-mcp-lab
   cd .\sql-mcp-lab
   ```

2. **Install Data API Builder:**
   ```powershell
   dotnet tool install --global microsoft.dataapibuilder
   dab --version
   ```

3. **Initialize DAB config:**
   ```powershell
   dab init --database-type "mssql" --connection-string "Server=tcp:<your-server>.database.windows.net,1433;Database=faq-ai-assistant-db;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;" --host-mode "Development"
   ```

4. **Add FAQ entity (read-only):**
   ```powershell
   dab add FAQ_Content --source "dbo.FAQ_Content" --permissions "anonymous:read"
   ```

5. **Start DAB with MCP (stdio):**
   ```powershell
   # DAB 2.0.9 uses --mcp-stdio (NOT --mcp). For VS Code you don't run this yourself —
   # VS Code launches it via .vscode/mcp.json (next step). To test the HTTP engine directly:
   dab start        # REST/GraphQL engine on http://localhost:5000
   ```
   > ⚠️ DAB uses `Active Directory Default` = your `az login` token. Ensure `az account show` is your **workshop user** (the SQL Entra admin), or you'll get *Login failed*.

6. **Configure VS Code MCP** — create `.vscode/mcp.json`:
   ```json
   {
     "servers": {
       "sql-faq": {
         "type": "stdio",
         "command": "dab",
         "args": ["start", "--mcp-stdio"],
         "cwd": "${workspaceFolder}/sql-mcp-lab"
       }
     }
   }
   ```

7. **Test in Copilot Chat:**
   - Open `.vscode/mcp.json` and click the **Start** codelens on the `sql-faq` server (status → *Running*).
   - Open **Copilot Chat** → **Agent** mode → enable the **sql-faq** tools (🔧 picker).
   - Ask: "Using the sql-faq tools, what FAQ categories are available?"
   - Ask: "Show me all Account FAQs"
   - Verify: Copilot uses the DAB MCP tool to query real data

### ✅ Verification Checklist
- [ ] DAB installed and version confirmed (`dab --version`)
- [ ] `az account show` is your workshop user (the SQL Entra admin)
- [ ] `dab-config.json` created in `sql-mcp-lab` with `FAQ_Content` (anonymous:read)
- [ ] `.vscode/mcp.json` uses `dab start --mcp-stdio` and starts without errors
- [ ] VS Code Copilot Chat (Agent mode) detects the **sql-faq** tools
- [ ] Natural language queries return real FAQ data
- [ ] Data is read-only (cannot modify via DAB)

---

## Module 7 — FAQ Assistant Chat Interface (15 min)

### 🎯 Objective
Run a self-contained web chat UI that puts a friendly front-end on the RAG pipeline
from Module 3: type a question → retrieve FAQ context from Azure SQL → get a
grounded o4-mini answer, with the matched sources shown. No Copilot or Foundry required.

### ⚠️ Dependencies
- Module 1 completed (`dbo.SearchFAQ` deployed)
- Module 3 understood (the RAG pattern this UI wraps)
- `az login` done as your workshop SQL user (Module 0)
- `pyodbc` + ODBC Driver 18 installed (from `bootstrap.ps1`)

> 💡 The app uses only `pyodbc`, the Azure CLI login, and the Python standard library —
> no Flask/Gradio or extra `pip install` needed.

### ⚠️ Pre-Check
```powershell
az account show -o table                                  # must be your workshop SQL user
Test-Path .\workshop\faq_agent_app.py                     # must be True
Test-Path .\workshop\student.config.local.json            # must be True (from the runbook Configuration cell)
```

### 📝 Steps

1. **Confirm your identity** (the app queries SQL with *your* `az` token):
   ```powershell
   az account show --query "user.name" -o tsv
   ```

2. **Start the chat interface:**
   ```powershell
   cd .\workshop
   python faq_agent_app.py
   ```
   > Wait for `FAQ Assistant running at  http://localhost:8000`. Keep this terminal open.
   > It binds to `127.0.0.1` (localhost only) — no firewall prompt, nothing exposed externally.

3. **Open the UI:** browse to [http://localhost:8000](http://localhost:8000).

4. **Test a supported question:**
   - Type: `How do I reset my password?`
   - Verify: a grounded answer appears, and the **Sources** line under it lists the matched FAQs + scores.

5. **Test an out-of-scope question:**
   - Type: `What's the weather today?`
   - Verify: it declines with *"I don't have that information."* (no hallucination).

6. **Stop the app** when done: press **Ctrl+C** in the terminal.

### ✅ Verification Checklist
- [ ] App starts and prints the `http://localhost:8000` URL
- [ ] The page loads with the **LAB513 FAQ Assistant** chat UI
- [ ] Supported questions return grounded answers with a **Sources** line
- [ ] Out-of-scope questions get *"I don't have that information."*
- [ ] Answers only reference FAQ content (no hallucinations)

### 🆘 Troubleshooting
| Issue | Fix |
|-------|-----|
| `Could not get token …` in the reply | Run `az login` as your workshop user, then retry. |
| `Login failed` | Your `az` account isn't the SQL Entra user — re-login and restart the app. |
| `Could not find stored procedure 'dbo.SearchFAQ'` | Run Module 1 first (deploys `sql/searchfaq.sql`). |
| `Config not found` on startup | Run the runbook **Configuration** cell to create `student.config.local.json`. |
| Port 8000 already in use | Stop the other process, or change `PORT` near the top of `faq_agent_app.py`. |

---

## 🎉 Workshop Complete!

You have successfully built:

| ✅ | Achievement |
|----|------------|
| 1 | Vector-powered semantic search in Azure SQL |
| 2 | AI-assisted SQL development with Copilot |
| 3 | RAG pipeline with grounded AI responses |
| 4 | Foundry Agent orchestrating FAQ workflow via MCP |
| 5 | Real-time Fabric mirroring with Power BI analytics |
| 6 | Database-as-MCP-tool via Data API Builder |
| 7 | FAQ Assistant chat interface over the RAG pipeline |

### 🧹 Cleanup
```powershell
# Only if instructor confirms
az group delete --name "rg-<your-env-name>" --yes --no-wait
```

---

## 🆘 Quick Troubleshooting

| Issue | Solution |
|-------|----------|
| "Login failed" on SQL | Use Entra ID auth, not SQL auth. Run `az login` to refresh. |
| OpenAI "Resource not found" | Check API version is `2025-01-01-preview` |
| Dev tunnel disconnects | Create a new tunnel, update Foundry agent config |
| Fabric "Cannot connect" | Ensure Entra auth, check firewall allows Fabric |
| DAB "Authentication failed" | Run `az login` to refresh your token |
| Copilot doesn't see MCP tool | Restart VS Code after adding `mcp.json` |
