@echo off
rem Thin ASCII wrapper for the uninstaller installed into the game folder.
rem "%~dp0." (with the dot) avoids the trailing-backslash-escapes-quote bug.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" -InstallDir "%~dp0."
exit /b %errorlevel%
