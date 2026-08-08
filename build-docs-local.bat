@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-docs-local.ps1"
if errorlevel 1 (
  echo.
  echo Documentation build failed.
  pause
  exit /b 1
)
echo.
echo Documentation build complete.
pause
