@echo off
rem EX Odyssey launcher: the exported build if present, else run the project with Godot 4.6.1.
rem Godot is taken from %GODOT_BIN%, else the usual Downloads path, else godot.exe on PATH.
cd /d "%~dp0"
if exist "build\EX_Odyssey.exe" (
  start "" "build\EX_Odyssey.exe"
  goto :eof
)
set "G=%GODOT_BIN%"
if not defined G set "G=%USERPROFILE%\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe"
if not exist "%G%" (
  for /f "delims=" %%F in ('where godot 2^>nul') do set "G=%%F"
)
if not exist "%G%" (
  echo Godot 4.6.1 not found. Set GODOT_BIN to Godot_v4.6.1-stable_win64.exe and run again.
  pause
  goto :eof
)
start "" "%G%" --path "%~dp0."
