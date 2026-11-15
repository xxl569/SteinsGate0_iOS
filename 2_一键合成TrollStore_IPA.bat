@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ==============================================================
echo   STEINS;GATE 0 iOS - Windows 3 秒热打包 TrollStore .ipa
echo ==============================================================
echo.

echo [1/3] 导出最新 Godot .pck 资源包...
python tools\package_trollstore_ipa.py export-pck --output build\ios\SteinsGate0_iOS.pck
if errorlevel 1 goto :err

set "SHELL_PATH="
if exist "build\ios\SteinsGate0_iOS.app" set "SHELL_PATH=build\ios\SteinsGate0_iOS.app"
if "%SHELL_PATH%"=="" if exist "build\ios\SteinsGate0_iOS_Shell.zip" set "SHELL_PATH=build\ios\SteinsGate0_iOS_Shell.zip"
if "%SHELL_PATH%"=="" (
    echo [提示] 未找到 build\ios\SteinsGate0_iOS.app 或 SteinsGate0_iOS_Shell.zip，仅完成了 .pck 导出。
    echo 请先从 GitHub Actions 下载 SteinsGate0_iOS_TrollStore 产物并放置到 build\ios\ 后重试。
    pause
    exit /b 0
)

echo [2/3] 注入 .pck 并使用 ldid 重签 TrollStore .ipa...
python tools\package_trollstore_ipa.py package --app-shell "%SHELL_PATH%" --pck build\ios\SteinsGate0_iOS.pck --output build\ios\SteinsGate0_iOS_TrollStore.ipa
if errorlevel 1 goto :err

echo [3/3] 全项校验最终 .ipa 结构与权限...
python tools\package_trollstore_ipa.py verify-ipa --ipa build\ios\SteinsGate0_iOS_TrollStore.ipa
if errorlevel 1 goto :err

echo [完成] 已成功生成 build\ios\SteinsGate0_iOS_TrollStore.ipa !
pause
exit /b 0

:err
echo [失败] 打包过程出现错误，请检查上方输出日志。
pause
exit /b 1
