# LAB513 — AI-Powered FAQ Assistant Workshop

> Build an intelligent FAQ assistant using Azure SQL vector search, RAG, Foundry Agents, Microsoft Fabric, and MCP.

---

## 🎯 What You'll Build

By the end of this workshop, you will have:

1. **Semantic search** — Query FAQs by meaning, not just keywords
2. **RAG pipeline** — Ground AI responses in your data (no hallucinations)
3. **AI Agent** — Orchestrate the workflow via Microsoft Foundry
4. **Analytics** — Mirror SQL data into Fabric with Power BI reports
5. **MCP integration** — Expose your database as an AI tool

---

## 📋 Modules

| # | Module | Duration | What You'll Do |
|---|--------|----------|----------------|
| 0 | [Setup & Prerequisites](STUDENT-GUIDE.md#module-0--prerequisites--setup-15-min) | 15 min | Verify tools, login, test connectivity |
| 1 | [AI-Enhanced Querying](STUDENT-GUIDE.md#module-1--ai-enhanced-querying-with-azure-sql-20-min) | 20 min | Embeddings + retrieval scoring |
| 2 | [Copilot SQL Dev](STUDENT-GUIDE.md#module-2--copilot-assisted-sql-development-15-min) | 15 min | Generate & refine SQL with AI |
| 3 | [RAG Implementation](STUDENT-GUIDE.md#module-3--rag-implementation-25-min) | 25 min | Build grounded AI responses |
| 4 | [Foundry Agents](STUDENT-GUIDE.md#module-4--foundry-agent-orchestration-25-min) | 25 min | MCP tools + dev tunnels |
| 5 | [Fabric Analytics](STUDENT-GUIDE.md#module-5--microsoft-fabric-integration-20-min) | 20 min | Mirror, model, report |
| 6 | [Data API Builder](STUDENT-GUIDE.md#module-6--sql-mcp-server-with-data-api-builder-20-min) | 20 min | Database as MCP tool |

**Total: ~2.5 hours**

---

## ⚡ Quick Start

```powershell
# 1. Clone this repo
git clone https://github.com/MSLab513/MS-LAB513-Student.git
cd MS-LAB513-Student

# 2. Login to Azure (credentials from instructor)
az login --tenant <tenant-id>
az account set --subscription <subscription-id>

# 3. Open the Student Guide and start Module 0
```

---

## 🔑 Your Environment

Your instructor will provide:
- **Tenant ID** and **Subscription ID**
- **SQL Server FQDN** (e.g., `faq-ai-assistant-xxxxx.database.windows.net`)
- **OpenAI Endpoint** (e.g., `https://ai-xxxxx.openai.azure.com/`)
- **Environment name** (e.g., `lab513-user01`)

| Setting | Value |
|---------|-------|
| Region | swedencentral |
| SQL Auth | Microsoft Entra ID (no passwords needed) |
| AI Model | o4-mini |
| API Version | `2025-01-01-preview` |
| Embeddings | text-embedding-ada-002 (1536 dims) |

---

## 📖 Full Guide

👉 **[Open the Student Guide →](STUDENT-GUIDE.md)**

---

## 🆘 Need Help?

| Issue | Quick Fix |
|-------|-----------|
| Can't login to Azure | Ask instructor to verify your account |
| SQL "Login failed" | Use Entra ID auth, not SQL auth |
| OpenAI "Not found" | Check API version is `2025-01-01-preview` |
| Fell behind on a module | Ask instructor for checkpoint |
