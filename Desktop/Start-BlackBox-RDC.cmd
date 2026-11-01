@echo off
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js is unavailable. Install a supported Windows x64 Node.js runtime first.
  pause
  exit /b 1
)
node --version
echo Starting the existing RDC remote agent. Keep this window open.
echo First use may ask to download the provider package and pair this PC.
call npx @wonderwhy-er/desktop-commander@latest remote
pause
