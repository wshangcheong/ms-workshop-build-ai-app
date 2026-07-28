<#
.SYNOPSIS
    One-command bootstrap for LAB513 workshop attendees.
    Installs all prerequisites and configures the environment.
 
.DESCRIPTION
    Run this on your machine BEFORE the workshop starts.
    It will:
    1. Check installed tools; auto-install anything missing, and
       auto-upgrade anything below the required minimum version
       (incl. ODBC Driver 18 for SQL Server and the Dev Tunnel CLI)
    2. Clone the workshop repo (or reuse the clone you're running from)
       and verify the lab files are present
    3. Install Python dependencies into your current Python environment
       for the runbook notebook and the MCP server (pyodbc, mcp, ipykernel),
       then register a Jupyter kernel for that environment
    4. Install required VS Code extensions (incl. Jupyter)
    5. Pre-install Data API Builder (Module 6)
    6. Verify Azure login
 
    Not comfortable with a terminal? Just DOUBLE-CLICK bootstrap.cmd in the
    repo root - it launches this script for you using the PowerShell already
    built into Windows (no Python or PowerShell 7 needed beforehand).

.EXAMPLE
    # Easiest: double-click bootstrap.cmd in the repo root.

.EXAMPLE
    # Or from a terminal, if already cloned:
    .\workshop\bootstrap.ps1
#>
 
param(
    [string]$InstallDir = (Join-Path $env:USERPROFILE "Lab513-Workshop"),
    [switch]$SkipInstall
)
 
$ErrorActionPreference = "Stop"

# If the script is being run from inside an existing clone (e.g. .\workshop\bootstrap.ps1
# from the repo root, as STUDENT-GUIDE.md instructs), use that clone instead of cloning
# a second copy under $env:USERPROFILE. An explicit -InstallDir still wins.
if (-not $PSBoundParameters.ContainsKey('InstallDir') -and $PSScriptRoot) {
    $repoRootFromScript = Split-Path -Parent $PSScriptRoot
    if (Test-Path (Join-Path $repoRootFromScript "sql\searchfaq.sql")) {
        $InstallDir = $repoRootFromScript
    }
}

Write-Host @"
 
  ==================================================================
        LAB513 WORKSHOP - Environment Bootstrap
        AI-Powered FAQ Assistant with Azure SQL + OpenAI
  ==================================================================
 
"@ -ForegroundColor Cyan
 
# ============================================================================
# Helper: pull the first x.y.z-style version number out of arbitrary text
# ============================================================================
 
function Get-VersionFromText {
    param([string]$Text)
    if (-not $Text) { return $null }
    $match = [regex]::Match($Text, '\d+(\.\d+){1,3}')
    if ($match.Success) {
        try { return [version]$match.Value } catch { return $null }
    }
    return $null
}

# ============================================================================
# Native-command helpers
# ----------------------------------------------------------------------------
# With $ErrorActionPreference = "Stop", Windows PowerShell 5.1 (the version
# built into Windows, which the bootstrap.cmd launcher uses) turns a native
# program's stderr into a TERMINATING NativeCommandError whenever that stderr
# is redirected or captured (2>&1, 2>$null, or `$x = tool 2>$null`) - even when
# it's only a harmless warning. Real examples that would otherwise abort the
# bootstrap: VS Code's `code` CLI prints a DEP0169 url.parse deprecation
# warning; `git`, `az` and `dotnet` print normal progress to stderr; and
# `az account show` writes to stderr when you're simply not logged in yet.
# These helpers run the command with that behavior relaxed. Genuine failures
# still surface via $LASTEXITCODE, which callers check.
# ============================================================================

# Run a native command and discard everything it prints. Keeps $LASTEXITCODE.
function Invoke-NativeQuiet {
    param([Parameter(Mandatory)][scriptblock]$Command)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Command 2>&1 | Out-Null } finally { $ErrorActionPreference = $prev }
}

# Run a native command and return its stdout (stderr discarded). Keeps $LASTEXITCODE.
function Get-NativeOutput {
    param([Parameter(Mandatory)][scriptblock]$Command)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Command 2>$null } finally { $ErrorActionPreference = $prev }
}
 
# ============================================================================
# STEP 1: Check Prerequisites (existence AND minimum version)
# ============================================================================
 
Write-Host "Step 1: Checking prerequisites...`n" -ForegroundColor Yellow
 
# Each tool can define:
#   check       - script block returning truthy output if the tool is present
#   version     - script block returning the raw version string/output
#   minVersion  - (optional) minimum acceptable [version]; omit to skip the check
#   packageId   - winget package id used for both install and upgrade
#
# check/version blocks are wrapped in try/catch when invoked below, so a
# missing command just resolves to $null instead of throwing a terminating
# error (which $ErrorActionPreference = "Stop" would otherwise turn into a
# hard stop, even with 2>$null on the command itself).
# Only the tools the workshop actually uses are listed here. Node.js, GitHub CLI,
# PowerShell 7 and azd were intentionally removed - nothing in the guide, notebook
# or module code references them, so a non-developer machine doesn't need them.
$tools = @(
    @{ name = "Azure CLI";          check = { az version 2>$null };                    version = { (az version --query '"azure-cli"' -o tsv 2>$null) }; minVersion = [version]"2.60.0"; packageId = "Microsoft.AzureCLI";        required = $true }
    @{ name = "Git";                check = { git --version 2>$null };                 version = { (git --version 2>$null) };                            minVersion = $null;              packageId = "Git.Git";                    required = $true }
    @{ name = "Visual Studio Code"; check = { code --version 2>$null };                version = { (code --version 2>$null | Select-Object -First 1) }; minVersion = $null;              packageId = "Microsoft.VisualStudioCode"; required = $true }
    @{ name = "Python 3";           check = { python --version 2>$null };              version = { (python --version 2>$null) };                         minVersion = [version]"3.10.0"; packageId = "Python.Python.3.12";        required = $true }
    @{ name = ".NET SDK";           check = { dotnet --version 2>$null };              version = { (dotnet --version 2>$null) };                         minVersion = [version]"8.0.0";  packageId = "Microsoft.DotNet.SDK.8";    required = $true }
    # ODBC Driver for SQL Server: needed by pyodbc (runbook notebook + MCP server). 17 or 18 both work.
    @{ name = "ODBC Driver for SQL Server"; check = { Get-OdbcDriver -Name "ODBC Driver 1? for SQL Server" -ErrorAction SilentlyContinue }; version = { (Get-OdbcDriver -Name "ODBC Driver 1? for SQL Server" -ErrorAction SilentlyContinue | Select-Object -Last 1).Name }; minVersion = $null; packageId = "Microsoft.msodbcsql.18"; required = $true }
    # Dev Tunnel CLI: required for Module 4 (Foundry Agent needs the MCP server exposed via dev tunnel)
    @{ name = "Dev Tunnel CLI";     check = { devtunnel --version 2>$null };           version = { (devtunnel --version 2>$null | Select-Object -First 1) }; minVersion = $null;         packageId = "Microsoft.devtunnel";        required = $true }
)
 
# Anything that needs winget action ends up here, tagged as install or upgrade,
# and carries the tool's required/optional flag through to the install step
$actionQueue = @()
 
# Safely invoke a tool's check/version script block: returns $null instead of
# throwing when the underlying command isn't found on PATH at all.
function Invoke-ToolProbe {
    param([scriptblock]$Block)
    try {
        & $Block
    } catch {
        $null
    }
}
 
foreach ($tool in $tools) {
    $result = Invoke-ToolProbe $tool.check
    $tag = if ($tool.required) { "" } else { " (optional)" }
 
    if (-not $result) {
        Write-Host "  [--] $($tool.name)$tag - NOT FOUND" -ForegroundColor Red
        $actionQueue += [pscustomobject]@{ Tool = $tool; Action = "install" }
        continue
    }
 
    $rawVersion = Invoke-ToolProbe $tool.version
    $parsedVersion = Get-VersionFromText $rawVersion
 
    if ($tool.minVersion -and $parsedVersion -and ($parsedVersion -lt $tool.minVersion)) {
        Write-Host "  [!!] $($tool.name)$tag - found $rawVersion, need >= $($tool.minVersion)" -ForegroundColor Red
        $actionQueue += [pscustomobject]@{ Tool = $tool; Action = "upgrade" }
    } else {
        Write-Host "  [ok] $($tool.name)$tag - $rawVersion" -ForegroundColor Green
    }
}
 
# Auto-install/upgrade anything that's missing or below the minimum version.
# No confirmation prompt - this runs automatically unless -SkipInstall is passed.
if ($actionQueue.Count -gt 0 -and -not $SkipInstall) {
    # Everything below is installed via winget (App Installer). On a non-developer
    # machine that ships without it, fail early with a clear, actionable message
    # instead of a confusing "winget is not recognized" error mid-loop.
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw ("winget (the 'App Installer') is needed to install the missing tools, but it wasn't found. " +
               "Install 'App Installer' from the Microsoft Store (or update Windows), then run this again.")
    }

    Write-Host "`n  $($actionQueue.Count) tool(s) need installing or upgrading. Handling automatically...`n" -ForegroundColor Yellow
 
    foreach ($item in $actionQueue) {
        $tool = $item.Tool
        $label = if ($tool.required) { $tool.name } else { "$($tool.name) (optional)" }
 
        try {
            if ($item.Action -eq "install") {
                Write-Host "  Installing $label..." -ForegroundColor White
                winget install --id $tool.packageId -e --accept-source-agreements --accept-package-agreements
                if ($LASTEXITCODE -ne 0) { throw "winget install exited with code $LASTEXITCODE" }
            } else {
                Write-Host "  Upgrading $label..." -ForegroundColor White
                # Try an upgrade first; if winget has no record of it as "upgradeable"
                # (e.g. it wasn't installed via winget originally), fall back to install --force
                winget upgrade --id $tool.packageId -e --accept-source-agreements --accept-package-agreements
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "  Upgrade path failed for $label, forcing reinstall..." -ForegroundColor DarkYellow
                    winget install --id $tool.packageId -e --force --accept-source-agreements --accept-package-agreements
                    if ($LASTEXITCODE -ne 0) { throw "winget install --force exited with code $LASTEXITCODE" }
                }
            }
        } catch {
            if ($tool.required) {
                # Required tool failed to install/upgrade - this blocks the workshop, so stop here
                throw "Failed to install/upgrade required tool '$($tool.name)': $_"
            } else {
                # Optional tool - warn and keep going, don't fail the whole bootstrap
                Write-Host "  [!!] Optional tool '$($tool.name)' failed to install/upgrade - skipping. ($_)" -ForegroundColor DarkYellow
            }
        }
    }
 
    Write-Host "`n  Done installing tools.`n" -ForegroundColor Green
} elseif ($actionQueue.Count -gt 0 -and $SkipInstall) {
    Write-Host "`n  -SkipInstall passed. The following need attention before the workshop:" -ForegroundColor Yellow
    foreach ($item in $actionQueue) {
        $verb = if ($item.Action -eq "install") { "install" } else { "upgrade" }
        $tag = if ($item.Tool.required) { "" } else { " (optional)" }
        Write-Host "     winget $verb --id $($item.Tool.packageId) -e$tag" -ForegroundColor DarkGray
    }
}
 
# Reload PATH into THIS session from the registry. winget writes new tools
# (Python, Git, Azure CLI, .NET, ...) into the persisted PATH, but the running
# PowerShell process still has the old copy - so on a fresh machine the steps
# below (git clone, python, code, az) would otherwise fail with "not found".
# This makes the just-installed tools usable immediately, no new window needed.
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
$userPath    = [System.Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = (@($machinePath, $userPath) | Where-Object { $_ }) -join ";"

# ============================================================================
# STEP 2: Clone Workshop Repo
# ============================================================================
 
Write-Host "`nStep 2: Getting workshop files...`n" -ForegroundColor Yellow
 
if (Test-Path $InstallDir) {
    Write-Host "  [ok] Already present at: $InstallDir" -ForegroundColor Green
    Set-Location $InstallDir
    Invoke-NativeQuiet { git pull --quiet }
} else {
    Write-Host "  Cloning to: $InstallDir"
    Invoke-NativeQuiet { git clone https://github.com/MSLab513/MS-LAB513-Student.git $InstallDir }
    Set-Location $InstallDir
    Write-Host "  [ok] Cloned successfully" -ForegroundColor Green
}

# Verify the lab files the guide/notebook depend on are present (Module 0, step 4)
$labFiles = @(
    "sql\searchfaq.sql"
    "tools\sql_mcp_server\server.py"
    "workshop\LAB513-Student-Runbook.ipynb"
)
foreach ($f in $labFiles) {
    if (Test-Path (Join-Path $InstallDir $f)) {
        Write-Host "  [ok] $f" -ForegroundColor Green
    } else {
        Write-Host "  [!!] MISSING: $f - re-clone the repo or ask your instructor" -ForegroundColor Red
    }
}

# ============================================================================
# STEP 3: Python environment (current/local interpreter)
# ============================================================================

Write-Host "`nStep 3: Python environment (local/current interpreter)...`n" -ForegroundColor Yellow

$pythonExe = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $pythonExe) {
    # A freshly winget-installed Python is sometimes reachable only through the
    # 'py' launcher (or the Store alias temporarily shadows 'python'). Try py.
    $pyLauncher = (Get-Command py -ErrorAction SilentlyContinue).Source
    if ($pyLauncher) {
        $pythonExe = Get-NativeOutput { & $pyLauncher -c "import sys; print(sys.executable)" }
    }
}
if (-not $pythonExe) {
    throw ("Python was not found even after setup. This can happen the very first " +
           "time Python is installed. Close this window, open a NEW one, and double-click " +
           "bootstrap.cmd again - the fresh window will see the newly installed Python.")
}

$requirementsPath = Join-Path $InstallDir "tools\sql_mcp_server\requirements.txt"
$kernelName = "lab513-local"
$kernelDisplayName = "Python (LAB513 Local)"

# pyodbc + mcp for the Module 4 MCP server, ipykernel so VS Code can run the
# runbook notebook (workshop\LAB513-Student-Runbook.ipynb) on the current interpreter.
Write-Host "  Installing Python packages (pyodbc, mcp, ipykernel) to local Python..."
& $pythonExe -m pip install --quiet --upgrade pip
& $pythonExe -m pip install --quiet -r $requirementsPath ipykernel

if ($LASTEXITCODE -ne 0) {
    Write-Host "  Standard pip install failed; retrying with --user..." -ForegroundColor DarkYellow
    & $pythonExe -m pip install --user --quiet -r $requirementsPath ipykernel
}

if ($LASTEXITCODE -ne 0) {
    throw "pip install failed in the local environment - check permissions/network and re-run the script"
}

Write-Host "  [ok] Python packages installed to local/current Python environment" -ForegroundColor Green

Write-Host "  Registering Jupyter kernel: $kernelDisplayName ..."
& $pythonExe -m ipykernel install --user --name $kernelName --display-name $kernelDisplayName
if ($LASTEXITCODE -ne 0) {
    throw "Failed to register Jupyter kernel '$kernelDisplayName'."
}
Write-Host "  [ok] Jupyter kernel registered: $kernelDisplayName" -ForegroundColor Green

# ============================================================================
# STEP 4: VS Code Extensions
# ============================================================================

Write-Host "`nStep 4: VS Code extensions...`n" -ForegroundColor Yellow

$extensions = @(
    "ms-mssql.mssql"
    "github.copilot"
    "github.copilot-chat"
    "ms-python.python"
    "ms-toolsai.jupyter"    # needed to run workshop\LAB513-Student-Runbook.ipynb
)
 
$installedExtensions = @(Get-NativeOutput { code --list-extensions })
foreach ($ext in $extensions) {
    if ($installedExtensions -contains $ext) {
        Write-Host "  [ok] $ext" -ForegroundColor Green
    } else {
        Write-Host "  Installing $ext..."
        Invoke-NativeQuiet { code --install-extension $ext --force }
        Write-Host "  [ok] $ext installed" -ForegroundColor Green
    }
}
 
# ============================================================================
# STEP 5: Data API Builder (Module 6) - best effort, Module 6 also installs it
# ============================================================================

Write-Host "`nStep 5: Data API Builder (dab)...`n" -ForegroundColor Yellow

$dabVersion = Invoke-ToolProbe { dab --version 2>$null }
if ($dabVersion) {
    Write-Host "  [ok] Data API Builder - $($dabVersion | Select-Object -First 1)" -ForegroundColor Green
} else {
    # Some lab machines only have the Visual Studio offline feed configured,
    # which prevents dotnet tool install from finding microsoft.dataapibuilder.
    # Ensure nuget.org exists before installing.
    $nugetSources = Get-NativeOutput { dotnet nuget list source }
    if (-not ($nugetSources -match "https://api\.nuget\.org/v3/index\.json")) {
        Write-Host "  NuGet source 'nuget.org' is missing. Adding it..."
        Invoke-NativeQuiet { dotnet nuget add source https://api.nuget.org/v3/index.json -n nuget.org }
    }

    Write-Host "  Installing Data API Builder (dotnet global tool)..."
    Invoke-NativeQuiet { dotnet tool install --global microsoft.dataapibuilder }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Primary install failed, retrying with explicit NuGet source..." -ForegroundColor DarkYellow
        Invoke-NativeQuiet { dotnet tool install --global microsoft.dataapibuilder --add-source https://api.nuget.org/v3/index.json }
    }
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [ok] Data API Builder installed" -ForegroundColor Green
    } else {
        # Not fatal: Module 6 of the guide installs it as an explicit step
        Write-Host "  [!!] Could not pre-install Data API Builder - you can install it in Module 6 with:" -ForegroundColor DarkYellow
        Write-Host "       dotnet tool install --global microsoft.dataapibuilder" -ForegroundColor DarkGray
    }
}

# ============================================================================
# STEP 6: Azure Login
# ============================================================================

Write-Host "`nStep 6: Azure authentication...`n" -ForegroundColor Yellow
 
$account = Get-NativeOutput { az account show --query "user.name" -o tsv }
if ($account) {
    Write-Host "  [ok] Logged in as: $account" -ForegroundColor Green
} else {
    Write-Host "  Not logged in. Opening browser for Azure login..."
    Invoke-NativeQuiet { az login }
    $account = Get-NativeOutput { az account show --query "user.name" -o tsv }
    Write-Host "  [ok] Logged in as: $account" -ForegroundColor Green
}
 
# ============================================================================
# DONE
# ============================================================================
 
Write-Host @"
 
  ==================================================================
    BOOTSTRAP COMPLETE - You're ready for the workshop!
  ==================================================================
 
  Workshop folder: $InstallDir
  Azure account:   $account
 
  ------------------------------------------------------------------
  WHAT HAPPENS NEXT (workshop day):
  ------------------------------------------------------------------
  1. Instructor will share your credentials (SQL server + OpenAI
     endpoint, tenant ID, subscription ID)
  2. Open VS Code in this folder
  3. Follow the modules in STUDENT-GUIDE.md, starting with Module 0,
    or run the notebook: workshop\LAB513-Student-Runbook.ipynb
    (select kernel: Python (LAB513 Local))

  Open: STUDENT-GUIDE.md
  ------------------------------------------------------------------
 
"@ -ForegroundColor Cyan
 