@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ==============================================================
echo   STEINS;GATE 0 iOS - 环境检查与 Godot .pck 导出
echo ==============================================================
echo.

if not exist "tools\godot\Godot_v4.3-stable_win64_console.exe" (
    echo [错误] 缺少 tools\godot\Godot_v4.3-stable_win64_console.exe
    pause
    exit /b 1
)
if not exist "tools\ldid\ldid.exe" (
    echo [错误] 缺少 tools\ldid\ldid.exe
    pause
    exit /b 1
)

echo [1/2] 语法自检全部 GDScript...
for %%f in (scripts\*.gd) do (
    tools\godot\Godot_v4.3-stable_win64_console.exe --headless --path . --script "%%f" --check-only
    if errorlevel 1 goto :err
)

echo [2/2] 导出纯净 SteinsGate0_iOS.pck 并校验零泄露...
python tools\package_trollstore_ipa.py export-pck --output build\ios\SteinsGate0_iOS.pck
if errorlevel 1 goto :err

echo [完成] 已成功导出 build\ios\SteinsGate0_iOS.pck !
pause
exit /b 0

:err
echo [失败] 环境检查或 PCK 导出失败，请查看上方日志。
pause
exit /b 1
