# LAB513 SQL MCP Server

This server exposes Azure SQL FAQ queries as MCP tools over HTTP.

## Required environment variables

- `SQL_SERVER` (for example: `faq-ai-assistant-abc.database.windows.net`)
- `SQL_DATABASE` (optional, default: `faq-ai-assistant-db`)
- `PORT` (optional, default: `5000`)

## Run

```powershell
pip install -r requirements.txt
$env:SQL_SERVER = "<your-sql-server>.database.windows.net"
$env:SQL_DATABASE = "faq-ai-assistant-db"
python server.py
```

The server uses `az account get-access-token` for Entra-based SQL authentication.
