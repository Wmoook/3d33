@echo off
rem EX Odyssey launcher: the exported build if present, else run the project with the Godot editor binary.
cd /d "%~dp0"
if exist "buildX_Odyssey.exe" (
  start "" "buildX_Odyssey.exe"
) else (
  start "" "C:\Users\super\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe" --path "%~dp0."
)
