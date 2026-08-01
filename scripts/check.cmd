@echo off
rem check.cmd - one-command Windows entry to the canonical gauntlet.
rem Bypasses the machine execution policy for this invocation only, then
rem check.ps1 locates Git Bash and forwards to scripts/check.sh.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0check.ps1" %*
exit /b %ERRORLEVEL%
