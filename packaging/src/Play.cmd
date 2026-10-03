@echo off
rem ============================================================
rem  PetGame launcher - opens the game in a standalone window.
rem  ASCII only on purpose: cmd.exe reads .cmd files with the
rem  system ANSI codepage, so non-ASCII text here would break.
rem ============================================================
setlocal

rem Locate the game html. Prefer PetGame.html, otherwise accept any
rem single .html next to this launcher (file may have been renamed).
rem NOTE: no parenthesised block here - cmd.exe would expand %GAME%
rem at parse time and wipe the result.
set "GAME=%~dp0PetGame.html"
if not exist "%GAME%" set "GAME="
for %%F in ("%~dp0*.html") do if not defined GAME set "GAME=%%~fF"

if not exist "%GAME%" (
  echo [ERROR] No .html game file found next to this launcher.
  echo         Please keep all files in the same folder.
  pause
  exit /b 1
)

set "URL=file:///%GAME:\=/%"
set "PROFILE=%~dp0profile"
set "EDGE=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
if not exist "%EDGE%" set "EDGE=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
if not exist "%EDGE%" set "EDGE=%LocalAppData%\Microsoft\Edge\Application\msedge.exe"

if exist "%EDGE%" (
  start "" "%EDGE%" --app="%URL%" --window-size=1120,960 --user-data-dir="%PROFILE%"
  exit /b 0
)

rem No Edge found: fall back to the default browser.
start "" "%GAME%"
exit /b 0
