# 《命运石之门 0》(STEINS;GATE 0) iOS TrollStore 安装与使用指南

## 1. 获取签名空壳与 Windows 本地 3 秒热打包

1. **云端编译 iOS 原生空壳（仅首次或修改 `MgsNative` C 代码时需要）**：
   - 将仓库推送至 GitHub 后，触发 Actions 工作流 `.github/workflows/ios-ipa.yml`（`macos-latest`）；
   - 从产物 `SteinsGate0_iOS_TrollStore` 下载 `SteinsGate0_iOS_Shell.zip`，将其中的 `SteinsGate0_iOS.app` 解压到：
     `U:\anti\projects\SteinsGate0_iOS\build\ios\SteinsGate0_iOS.app`（`build\.gdignore` 会阻止 Godot 扫描空壳目录）。
2. **Windows 本地 3 秒热打包**：
   - 双击 `1_一键环境检查与导出PCK.bat` 导出纯净 `.pck` 资源包（零版权资产泄露）；
   - 双击 `2_一键合成TrollStore_IPA.bat`，或在终端执行：
     ```powershell
     python tools/package_trollstore_ipa.py export-pck --output build/ios/SteinsGate0_iOS.pck
     python tools/package_trollstore_ipa.py package --app-shell build/ios/SteinsGate0_iOS.app --pck build/ios/SteinsGate0_iOS.pck --output build/ios/SteinsGate0_iOS_TrollStore.ipa
     python tools/package_trollstore_ipa.py verify-ipa --ipa build/ios/SteinsGate0_iOS_TrollStore.ipa
     ```
3. **通过 TrollStore 安装**：
   - 将 `SteinsGate0_iOS_TrollStore.ipa` 发送至 iPhone / iPad，使用 TrollStore 安装。

---

## 2. BYOA 外置游戏资产放置说明（首次启动必读）

本应用采用外置资产挂载（BYOA）机制，`.ipa` 安装包内**不包含**任何 PC 原版封包、音频或视频。请在 iPhone / iPad「文件」App 中打开 **我的 iPhone -> SteinsGate0_iOS**（应用沙盒 `Documents` 目录），拷贝以下文件：

- **必需 `*.mpk` 封包**（直接放入 `Documents/` 或 `Documents/USRDIR/`）：
  - `script.mpk`（简体中文剧本 / 词典 / RINE 库）
  - `system.mpk`（原版字库 `FONT_A/B`、`MESWIN.DDS`、`PHONE.DDS` 等界面图集）
  - `bg.mpk`、`chara.mpk`、`mask.mpk`
  - `bgm.mpk`、`se.mpk`、`voice.mpk`（可选仅缺少音频时降级静音）
- **转码后的 `.ogv` 过场视频**（共 33 部）：
  - 请使用 `tools/transcode_movies.py`（或从 `U:\anti\temp\SteinsGate0_iOS\SteinsGate0_iOS_Documents\movie\` 拷贝）放入 `Documents/movie/*.ogv`。

> **提示**：拷贝完成后无需重启 App，切回游戏或点击「重新扫描资产目录」即可自动挂载并进入主菜单。

---

## 3. 移动端触控手势与特色功能

- **单指轻触**：推进对白（`Auto` / `Skip` 开启时，首次轻触优先暂停自动/快进，避免误跳过对白）。
- **单指左滑**：弹出/收起右侧 **RINE / Amadeus 手机终端**。
- **单指右滑**：打开对话历史回顾（Backlog），支持点击任意条目重听对应原声语音。
- **双指轻触**：隐藏 / 显示对话框与顶部 HUD，方便纯享 CG。
- **三指轻触**：打开用语词典（TIPS）。
- **iOS 低内存保护**：内置 `MgsCache` 140 MB LRU 纹理缓存池，响应 `NOTIFICATION_OS_MEMORY_WARNING` 自动将缓存释放至 40% 以内，确保 3GB~4GB 内存设备长期稳定运行。
