@echo off
setlocal
REM scout installer bootstrap for Windows
REM
REM Fetches and runs install.ps1 over HTTPS via PowerShell.
REM Double-click this file, or run `install.cmd` from a terminal.
REM It runs the same one-liner shown in the README "Quick start (Windows)".

echo ================================================================
echo  scout installer - prerequisites
echo ================================================================
echo.
echo  Before installing scout, ONE tool must already be installed
echo  on this machine:
echo.
echo    1. Claude Code CLI   (provides the 'claude' command)
echo.
echo  scout installs over a plain HTTPS download - no version-control
echo  client, no SSH key, nothing else to set up.
echo.
echo ----------------------------------------------------------------
echo  How to install on Windows:
echo ----------------------------------------------------------------
echo.
echo  Claude Code CLI:
echo    Follow the Windows install steps in the docs:
echo    https://docs.claude.com/en/docs/claude-code
echo.
echo ================================================================
echo.

choice /c YN /n /m "Is the Claude Code CLI already installed?  [Y = continue / N = cancel] "
if errorlevel 2 goto :cancel

echo.
echo Continuing with scout installation...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/tenzoki/scout/main/install.ps1 | iex"
set "rc=%errorlevel%"
echo.
pause
exit /b %rc%

:cancel
echo.
echo Installation cancelled.
echo Please install the prerequisite above, then run install.cmd again.
echo.
pause
exit /b 1
