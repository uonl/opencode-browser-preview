@echo off
rem ============================================================
rem  Local web service launcher (ASCII only, CRLF)
rem  - watchdog: restarts 5s after a crash
rem  - port guard: exits if the port is already serving
rem
rem  Replace the placeholders before use:
rem    __SERVICE__  display name, e.g. drama editor
rem    __ROOT__     project root, relative to this file (e.g. ..\..)
rem    __NODE__     full path to node.exe
rem    __SERVER__   server entry file, relative to this file
rem    __PORT__     listening port
rem ============================================================
setlocal
set "HERE=%~dp0"
set "ROOT=%HERE%__ROOT__"
set "NODE=__NODE__"
set "SRV=%HERE%__SERVER__"
set "PORT=__PORT__"
set "HOST=127.0.0.1"

cd /d "%ROOT%"
set "LOG=%HERE%monitor.log"

rem already running? then do nothing
powershell -NoProfile -Command "if (Get-NetTCPConnection -State Listen -LocalPort %PORT% -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }" >nul 2>&1
if not errorlevel 1 (
  echo [%date% %time%] port %PORT% already in use - nothing to do.
  exit /b 0
)

:loop
echo [%date% %time%] starting __SERVICE__ on http://%HOST%:%PORT%/ >> "%LOG%"
echo [%date% %time%] starting __SERVICE__ on http://%HOST%:%PORT%/
"%NODE%" "%SRV%" --port %PORT% --host %HOST%
echo [%date% %time%] __SERVICE__ exited (code %errorlevel%), restarting in 5s... >> "%LOG%"
echo [%date% %time%] __SERVICE__ exited (code %errorlevel%), restarting in 5s...
timeout /t 5 /nobreak >nul
goto loop
