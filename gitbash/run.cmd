@echo off
setlocal
for /f "delims=" %%i in ('git --exec-path 2^>nul') do set "GITCORE=%%i"
if not defined GITCORE (
  echo Git for Windows not found. Install it first:  winget install Git.Git
  pause & exit /b 1
)
set "BASH=%GITCORE%\..\..\..\usr\bin\bash.exe"
"%BASH%" "%~dp0run.sh" -4 %*
if /i not "%~1"=="--nopause" pause
