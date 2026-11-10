@echo off
rem codex-hook.cmd - Windows launcher for the Codex hooks in .codex/hooks.json.
rem Usage: codex-hook.cmd NAME, where NAME is session-context, feedback-log, destructive-guard or stop-gate.
rem Input: the hook payload on stdin, passed on to the matching script in scripts/ under Git Bash.
rem Output: that script's stdout, stderr and exit code.
rem Why: Codex on Windows runs a hook through cmd.exe, which cannot run a .sh file.
rem Assumptions: cwd is inside the repository (Codex runs a hook in the session's
rem folder); git is on PATH (the hooks.json prefix checks that before this runs).
rem Fail-closed: destructive-guard exits 2 when it cannot run; the others exit 0.
setlocal
set "NAME=%~1"
if /i not "%NAME%"=="session-context" if /i not "%NAME%"=="feedback-log" if /i not "%NAME%"=="destructive-guard" if /i not "%NAME%"=="stop-gate" (echo codex-hook: unknown hook name %NAME% 1>&2 & exit /b 0)
set "FAILRC=0"
if /i "%NAME%"=="destructive-guard" set "FAILRC=2"
set "ROOT="
for /f "usebackq delims=" %%r in (`git rev-parse --show-toplevel 2^>nul`) do set "ROOT=%%r"
if not defined ROOT (echo codex-hook: not inside a git repository; run bash scripts/doctor.sh 1>&2 & exit /b %FAILRC%)
set "GX="
for /f "usebackq delims=" %%e in (`git --exec-path 2^>nul`) do set "GX=%%e"
set "BASH_EXE="
if defined GX if exist "%GX%\..\..\..\bin\bash.exe" set "BASH_EXE=%GX%\..\..\..\bin\bash.exe"
if not defined BASH_EXE if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH_EXE (echo codex-hook: Git Bash not found; run bash scripts/doctor.sh 1>&2 & exit /b %FAILRC%)
"%BASH_EXE%" "%ROOT%/scripts/%NAME%.sh"
exit /b %ERRORLEVEL%
