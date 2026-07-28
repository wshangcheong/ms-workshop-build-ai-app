@echo off
REM ============================================================
REM  LAB513 Workshop - one-click environment setup
REM
REM  Just DOUBLE-CLICK this file. No terminal, no Python and no
REM  PowerShell 7 needed first - this uses the PowerShell that
REM  is already built into every Windows machine, and installs
REM  everything else for you.
REM ============================================================
echo.
echo   ==================================================
echo     LAB513 Workshop - setting up your environment
echo   ==================================================
echo.
echo   A setup window will now run and install the tools.
echo   This can take several minutes - please wait for it
echo   to say BOOTSTRAP COMPLETE.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0workshop\bootstrap.ps1"

echo.
if errorlevel 1 (
  echo   [!] Setup did not finish cleanly. Scroll up to read the error,
  echo       fix it, then double-click this file again.
) else (
  echo   [ok] Setup finished. You can close this window.
)
echo.
pause
