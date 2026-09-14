@echo off
set "LOG=%TEMP%\TakeownTool-startup.log"
echo [%date% %time%] Starting TakeownTool > "%LOG%"
start "TakeownTool" /wait "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0TakeownTool.ps1" >> "%LOG%" 2>&1
set "EXITCODE=%ERRORLEVEL%"
echo [%date% %time%] Exit code: %EXITCODE% >> "%LOG%"
if not "%EXITCODE%"=="0" (
	echo TakeownTool failed. See "%LOG%".
	pause
)