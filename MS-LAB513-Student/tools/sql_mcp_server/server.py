import os
import struct
import subprocess
from typing import Any

import pyodbc
from mcp.server.fastmcp import FastMCP


mcp = FastMCP("lab513-sql-faq")


def get_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def pick_sql_driver() -> str:
    """Return the best available 'ODBC Driver NN for SQL Server' (prefers 18, falls back to 17)."""
    installed = [d for d in pyodbc.drivers() if "for SQL Server" in d]
    for preferred in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server"):
        if preferred in installed:
            return preferred
    if installed:
        return installed[-1]
    raise RuntimeError(
        "No 'ODBC Driver for SQL Server' found. Install ODBC Driver 18: https://aka.ms/downloadmsodbcsql"
    )


def get_sql_access_token() -> str:
    # NOTE: use shell=True so this works on Windows, where the Azure CLI is `az.cmd`.
    # A bare subprocess.run(["az", ...]) fails on Windows with
    # "[WinError 2] The system cannot find the file specified".
    result = subprocess.run(
        'az account get-access-token --resource "https://database.windows.net/" --query accessToken -o tsv',
        shell=True,
        capture_output=True,
        text=True,
        check=False,
    )
    token = result.stdout.strip()
    if result.returncode != 0 or not token:
        raise RuntimeError(
            "Unable to acquire Azure SQL access token. Run 'az login' and set the correct tenant/subscription."
        )
    return token


def query_sql(query: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    server = get_env("SQL_SERVER")
    database = os.getenv("SQL_DATABASE", "faq-ai-assistant-db")
    token = get_sql_access_token()

    token_bytes = token.encode("utf-16-le")
    token_struct = struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)
    sql_copt_ss_access_token = 1256

    connection_string = (
        f"Driver={{{pick_sql_driver()}}};"
        f"Server=tcp:{server},1433;"
        f"Database={database};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;"
        "Connection Timeout=30;"
    )

    with pyodbc.connect(
        connection_string,
        attrs_before={sql_copt_ss_access_token: token_struct},
    ) as connection:
        cursor = connection.cursor()
        cursor.execute(query, params)
        columns = [column[0] for column in cursor.description]
        return [dict(zip(columns, row)) for row in cursor.fetchall()]


@mcp.tool()
def search_faq(question: str, top_k: int = 3) -> list[dict[str, Any]]:
    """
    Search FAQ content using the SQL SearchFAQ stored procedure.
    """
    if not question or not question.strip():
        raise ValueError("question must be provided")
    top_k = max(1, min(top_k, 10))
    return query_sql("EXEC dbo.SearchFAQ @Question=?, @TopK=?", (question.strip(), top_k))


@mcp.tool()
def list_faq_categories() -> list[dict[str, Any]]:
    """
    List FAQ categories with record counts.
    """
    return query_sql(
        """
        SELECT category, COUNT(*) AS faq_count
        FROM dbo.FAQ_Content
        GROUP BY category
        ORDER BY category
        """
    )


if __name__ == "__main__":
    port = int(os.getenv("PORT", "5000"))
    # FastMCP reads host/port from its settings (not from run() kwargs).
    mcp.settings.host = "0.0.0.0"
    mcp.settings.port = port
    mcp.run(transport="streamable-http")
