@echo off
chcp 65001 >nul
cd /d "%~dp0"
title STEINS;GATE 0 - Windows Trial Launcher

echo ======================================================================
echo   STEINS;GATE 0 iOS BYOA - Windows Trial (Godot 4.3 + MgsNative)
echo   Mode   : GL Compatibility (1280x720 Windowed)
echo   Assets : U:\anti\projects\STEINS GATE 0\USRDIR
echo   Movie  : U:\anti\temp\SteinsGate0_iOS\SteinsGate0_iOS_Documents\movie
echo ======================================================================
echo.

set "GODOT_BIN="
if exist "%~dp0tools\godot\Godot_v4.3-stable_win64_console.exe" set "GODOT_BIN=%~dp0tools\godot\Godot_v4.3-stable_win64_console.exe"
if "%GODOT_BIN%"=="" if exist "%~dp0tools\godot\Godot_v4.3-stable_win64.exe" set "GODOT_BIN=%~dp0tools\godot\Godot_v4.3-stable_win64.exe"
if "%GODOT_BIN%"=="" (
    echo [ERROR] Godot 4.3 Windows executable not found.
    pause
    exit /b 1
)

"%GODOT_BIN%" --path "." scenes/main.tscn %*
if errorlevel 1 (
    echo [ERROR] Godot exited with code %errorlevel%
    pause
    exit /b %errorlevel%
)
