@echo off
rem Thin ASCII wrapper: IExpress runs this from the extraction folder.
rem "%~dp0." (with the dot) avoids the classic trailing-backslash-escapes-quote bug.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -SourceDir "%~dp0."
exit /b %errorlevel%
