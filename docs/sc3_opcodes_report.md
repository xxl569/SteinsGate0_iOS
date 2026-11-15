# STEINS;GATE 0 SC3 脚本逆向与全量扫描报告

## 1. 扫描总览

- **脚本文件总数**：`178` 个（来自 `USRDIR/script.mpk`）
- **累计解析指令数**：`269049` 条
- **实际使用操作码种类**：`117` 种（解析错误：`0`；剧情文件 `SG0_*` 异常未覆盖：`0`）
- **内联字符串总数**：`30580` 条
- **字形 ID 范围**：`0 .. 7440`（与 `assets/tables/font_widths.bin` 的 8000 槽位匹配情况需在文本渲染器做越界保护）

## 2. SC3 字符串控制标签分布（依据 Game.exe `0x445790`）

| 标签 | 名称 | 参数格式 | 出现次数 |
| --- | --- | --- | ---: |
| `0x00` | `LineBreak` | `none` | 40 |
| `0x01` | `NameStart` | `none` | 15168 |
| `0x02` | `NameEnd` | `none` | 15168 |
| `0x03` | `WaitClick` | `none` | 25904 |
| `0x04` | `SetColor` | `expr` | 522 |
| `0x08` | `AutoWait` | `none` | 1769 |
| `0x09` | `RubyBaseStart` | `none` | 412 |
| `0x0a` | `RubyTextStart` | `none` | 412 |
| `0x0b` | `RubyTextEnd` | `none` | 412 |
| `0x0e` | `Center` | `none` | 30 |
| `0x11` | `SetPosX` | `u16be` | 1179 |
| `0x13` | `PrintScrWork` | `u16be` | 12 |
| `0x15` | `EvalExpr` | `expr` | 42 |
| `0x18` | `Tag18` | `none` | 9 |
| `0x19` | `SetSpacing` | `u16be` | 24 |
| `0x1e` | `RubyDot` | `none` | 3 |

## 3. 表达式操作符统计（依据 Game.exe `0x41a740` / `0x41acc0`）

| 操作符 ID | 语义 | 出现次数 |
| --- | --- | ---: |
| `0x01` | `*` | 443 |
| `0x02` | `/` | 60 |
| `0x03` | `+` | 1797 |
| `0x04` | `-` | 127 |
| `0x05` | `%` | 9 |
| `0x06` | `<<` | 80 |
| `0x07` | `>>` | 56 |
| `0x08` | `&` | 230 |
| `0x09` | `^` | 42 |
| `0x0a` | `|` | 75 |
| `0x0c` | `==` | 964 |
| `0x0d` | `!=` | 68 |
| `0x0e` | `<=` | 50 |
| `0x0f` | `>=` | 24 |
| `0x10` | `<` | 333 |
| `0x11` | `>` | 47 |
| `0x14` | `=` | 23180 |
| `0x15` | `*=` | 5 |
| `0x17` | `+=` | 157 |
| `0x18` | `-=` | 74 |
| `0x1a` | `<<=` | 4 |
| `0x1b` | `>>=` | 28 |
| `0x1c` | `&=` | 87 |
| `0x1d` | `|=` | 34 |
| `0x1e` | `^=` | 21 |
| `0x20` | `++` | 263 |
| `0x21` | `--` | 102 |
| `0x28` | `ScrWork` | 38502 |
| `0x29` | `GetFlag` | 73 |
| `0x2a` | `DataU32` | 78 |
| `0x2b` | `LabelAddr` | 78 |
| `0x2d` | `ThreadVar` | 4564 |
| `0x33` | `Random` | 48 |

## 4. 核心系统脚本审计（手机 / RINE / TIPS / 启动控制）

### `_phone.scx`
- 体积：`39886` B，标签：`91`，字符串：`978`，解析指令：`105`
- 高频指令：`FE`(ExprStmt): 15, `000a`(If): 15, `0010`(JumpIfFlag): 14, `0025`(Audio3DControl): 14, `0007`(Jump): 13, `0005`(Wait): 11, `000f`(Loop): 6, `0012`(ResetFlag): 4, `0013`(CopyFlag): 4, `000e`(Return): 3, `0011`(SetFlag): 2, `1037`(SG0_RineCtrl): 1

### `_rndrine.scx`
- 体积：`14976` B，标签：`197`，字符串：`0`，解析指令：`921`
- 高频指令：`1037`(SG0_RineCtrl): 739, `FE`(ExprStmt): 36, `000b`(Call): 36, `0007`(Jump): 26, `0000`(End): 26, `000e`(Return): 23, `0012`(ResetFlag): 9, `1022`(SG0_PhoneCtrl): 6, `0010`(JumpIfFlag): 5, `000a`(If): 4, `0013`(CopyFlag): 4, `002a`(ReturnIfWait): 4

### `_Startup_win.scx`
- 体积：`24003` B，标签：`346`，字符串：`103`，解析指令：`2317`
- 高频指令：`FE`(ExprStmt): 480, `0043`(TitleOrSystem43): 261, `000a`(If): 175, `0013`(CopyFlag): 167, `0005`(Wait): 150, `0007`(Jump): 144, `0012`(ResetFlag): 113, `0010`(JumpIfFlag): 95, `000b`(Call): 93, `000d`(CallFar): 58, `0019`(StopSE): 56, `0015`(PlayBGMEx): 42

### `_tips.scx`
- 体积：`73681` B，标签：`3`，字符串：`1041`，解析指令：`3`
- 高频指令：`0121`(LoadMask): 1, `1033`(SG0_HelpCtrl): 1, `000e`(Return): 1

### `macrosys.scx`
- 体积：`88636` B，标签：`1514`，字符串：`0`，解析指令：`6639`
- 高频指令：`FE`(ExprStmt): 4052, `0007`(Jump): 609, `000a`(If): 379, `000e`(Return): 347, `000b`(Call): 344, `0012`(ResetFlag): 230, `0013`(CopyFlag): 163, `0005`(Wait): 88, `0010`(JumpIfFlag): 82, `0105`(DispCtrl): 62, `0046`(Sub46): 40, `0033`(SetWorkOrWait): 34

### `macrosys2.scx`
- 体积：`43820` B，标签：`667`，字符串：`36`，解析指令：`3086`
- 高频指令：`FE`(ExprStmt): 1285, `0013`(CopyFlag): 242, `000a`(If): 218, `000d`(CallFar): 205, `0007`(Jump): 197, `000e`(Return): 138, `0012`(ResetFlag): 112, `000b`(Call): 62, `1037`(SG0_RineCtrl): 58, `0005`(Wait): 57, `0011`(SetFlag): 56, `0001`(CreateThread): 56

## 5. 关键系统子操作码分布（Sub-opcodes）

| 操作码:子号 | 出现次数 | 说明 |
| --- | ---: | --- |
| `0035:00` | 4 | `Sub35` (sub=0x00) |
| `0043:00` | 136 | `TitleOrSystem43` (sub=0x00) |
| `0043:01` | 34 | `TitleOrSystem43` (sub=0x01) |
| `0043:02` | 180 | `TitleOrSystem43` (sub=0x02) |
| `0043:03` | 446 | `TitleOrSystem43` (sub=0x03) |
| `0043:04` | 130 | `TitleOrSystem43` (sub=0x04) |
| `0043:05` | 120 | `TitleOrSystem43` (sub=0x05) |
| `0043:06` | 180 | `TitleOrSystem43` (sub=0x06) |
| `0043:07` | 176 | `TitleOrSystem43` (sub=0x07) |
| `0050:00` | 5 | `CondJump50` (sub=0x00) |
| `0050:03` | 4 | `CondJump50` (sub=0x03) |
| `0050:05` | 5 | `CondJump50` (sub=0x05) |
| `0105:03` | 28 | `DispCtrl` (sub=0x03) |
| `0105:05` | 53 | `DispCtrl` (sub=0x05) |
| `0108:00` | 3 | `BGSwapOrFade` (sub=0x00) |
| `0108:01` | 3 | `BGSwapOrFade` (sub=0x01) |
| `0108:02` | 3 | `BGSwapOrFade` (sub=0x02) |
| `0108:03` | 3 | `BGSwapOrFade` (sub=0x03) |
| `0108:04` | 3 | `BGSwapOrFade` (sub=0x04) |
| `0109:00` | 27241 | `MesWindow` (sub=0x00) |
| `0109:01` | 456 | `MesWindow` (sub=0x01) |
| `0109:02` | 9 | `MesWindow` (sub=0x02) |
| `0110:00` | 10 | `SetChoiceCtrl` (sub=0x00) |
| `0110:01` | 5 | `SetChoiceCtrl` (sub=0x01) |
| `0110:02` | 15 | `SetChoiceCtrl` (sub=0x02) |
| `0110:03` | 5 | `SetChoiceCtrl` (sub=0x03) |
| `0110:04` | 5 | `SetChoiceCtrl` (sub=0x04) |
| `0110:05` | 10 | `SetChoiceCtrl` (sub=0x05) |
| `0111:01` | 27697 | `MesSync` (sub=0x01) |
| `0111:02` | 27706 | `MesSync` (sub=0x02) |
| `0111:03` | 5003 | `MesSync` (sub=0x03) |
| `0111:05` | 5005 | `MesSync` (sub=0x05) |
| `0111:06` | 10 | `MesSync` (sub=0x06) |
| `0111:07` | 27 | `MesSync` (sub=0x07) |
| `0112:00` | 2 | `Select` (sub=0x00) |
| `0112:01` | 19 | `Select` (sub=0x01) |
| `0113:00` | 2 | `SelectWait` (sub=0x00) |
| `0113:01` | 2 | `SelectWait` (sub=0x01) |
| `0113:02` | 2 | `SelectWait` (sub=0x02) |
| `0122:01` | 25 | `MoviePlay` (sub=0x01) |
| `0122:04` | 3 | `MoviePlay` (sub=0x04) |
| `0122:0a` | 1 | `MoviePlay` (sub=0x0a) |
| `0122:0d` | 2 | `MoviePlay` (sub=0x0d) |
| `0122:63` | 9 | `MoviePlay` (sub=0x63) |
| `0123:00` | 17 | `MovieCtrl` (sub=0x00) |
| `0123:02` | 53 | `MovieCtrl` (sub=0x02) |
| `0123:03` | 14 | `MovieCtrl` (sub=0x03) |
| `0125:00` | 36 | `Effect125` (sub=0x00) |
| `1004:00` | 4 | `SG0_SpriteAnim` (sub=0x00) |
| `1004:01` | 6 | `SG0_SpriteAnim` (sub=0x01) |
| `1005:00` | 5877 | `SG0_ChaLoad` (sub=0x00) |
| `1005:01` | 40 | `SG0_ChaLoad` (sub=0x01) |
| `1022:00` | 70 | `SG0_PhoneCtrl` (sub=0x00) |
| `1022:01` | 2 | `SG0_PhoneCtrl` (sub=0x01) |
| `1022:02` | 10 | `SG0_PhoneCtrl` (sub=0x02) |
| `1022:03` | 10 | `SG0_PhoneCtrl` (sub=0x03) |
| `1022:05` | 479 | `SG0_PhoneCtrl` (sub=0x05) |
| `1022:0a` | 551 | `SG0_PhoneCtrl` (sub=0x0a) |
| `1022:ff` | 551 | `SG0_PhoneCtrl` (sub=0xff) |
| `1023:00` | 33 | `SG0_TipsCtrl` (sub=0x00) |
| `1023:01` | 10 | `SG0_TipsCtrl` (sub=0x01) |
| `1023:14` | 15 | `SG0_TipsCtrl` (sub=0x14) |
| `1030:0a` | 3 | `SG0_GalleryOrMusic` (sub=0x0a) |
| `1030:0b` | 12 | `SG0_GalleryOrMusic` (sub=0x0b) |
| `1033:00` | 1 | `SG0_HelpCtrl` (sub=0x00) |
| `1033:01` | 10 | `SG0_HelpCtrl` (sub=0x01) |
| `1033:02` | 5 | `SG0_HelpCtrl` (sub=0x02) |
| `1033:03` | 15 | `SG0_HelpCtrl` (sub=0x03) |
| `1033:04` | 10 | `SG0_HelpCtrl` (sub=0x04) |
| `1037:00` | 1 | `SG0_RineCtrl` (sub=0x00) |
| `1037:01` | 8 | `SG0_RineCtrl` (sub=0x01) |
| `1037:02` | 1 | `SG0_RineCtrl` (sub=0x02) |
| `1037:03` | 1 | `SG0_RineCtrl` (sub=0x03) |
| `1037:04` | 1 | `SG0_RineCtrl` (sub=0x04) |
| `1037:0a` | 19 | `SG0_RineCtrl` (sub=0x0a) |
| `1037:0b` | 60 | `SG0_RineCtrl` (sub=0x0b) |
| `1037:0c` | 19 | `SG0_RineCtrl` (sub=0x0c) |
| `1037:0d` | 57 | `SG0_RineCtrl` (sub=0x0d) |
| `1037:0e` | 19 | `SG0_RineCtrl` (sub=0x0e) |
| `1037:0f` | 552 | `SG0_RineCtrl` (sub=0x0f) |
| `1037:28` | 6 | `SG0_RineCtrl` (sub=0x28) |
| `1037:29` | 15 | `SG0_RineCtrl` (sub=0x29) |
| `1037:2a` | 6 | `SG0_RineCtrl` (sub=0x2a) |
| `1037:2b` | 8 | `SG0_RineCtrl` (sub=0x2b) |
| `1037:2c` | 3 | `SG0_RineCtrl` (sub=0x2c) |
| `1037:2e` | 64 | `SG0_RineCtrl` (sub=0x2e) |
| `1037:2f` | 14 | `SG0_RineCtrl` (sub=0x2f) |
| `1037:30` | 2 | `SG0_RineCtrl` (sub=0x30) |
| `1037:32` | 48 | `SG0_RineCtrl` (sub=0x32) |

## 6. 全部 117 种操作码频次表

| Opcode | 助记符 | 出现次数 |
| --- | --- | ---: |
| `0x0000` | `End` | 246 |
| `0x0001` | `CreateThread` | 884 |
| `0x0004` | `ScriptLoad` | 165 |
| `0x0005` | `Wait` | 876 |
| `0x0006` | `Halt` | 29 |
| `0x0007` | `Jump` | 1673 |
| `0x0008` | `JumpTable` | 8 |
| `0x000a` | `If` | 1569 |
| `0x000b` | `Call` | 977 |
| `0x000c` | `JumpFarCond` | 6 |
| `0x000d` | `CallFar` | 21653 |
| `0x000e` | `Return` | 944 |
| `0x000f` | `Loop` | 36 |
| `0x0010` | `JumpIfFlag` | 897 |
| `0x0011` | `SetFlag` | 888 |
| `0x0012` | `ResetFlag` | 2559 |
| `0x0013` | `CopyFlag` | 10208 |
| `0x0015` | `PlayBGMEx` | 235 |
| `0x0018` | `PlaySE` | 140 |
| `0x0019` | `StopSE` | 277 |
| `0x001a` | `WaitBGM` | 10 |
| `0x001b` | `SwitchScript` | 1 |
| `0x001f` | `SetThreadGroup` | 13 |
| `0x0020` | `WaitThreadGroup` | 40 |
| `0x0021` | `BGMFadeOrSync` | 486 |
| `0x0022` | `SetFlagU8` | 567 |
| `0x0023` | `BGExControl` | 922 |
| `0x0024` | `TimerControl` | 707 |
| `0x0025` | `Audio3DControl` | 112 |
| `0x0026` | `WaitTimer` | 75 |
| `0x0028` | `ViewportOrCam` | 2 |
| `0x0029` | `SystemSub29` | 20 |
| `0x002a` | `ReturnIfWait` | 498 |
| `0x002c` | `KeyConfigOrPad` | 1 |
| `0x002e` | `SoundFadeCtrl` | 135 |
| `0x002f` | `ScreenFadeCtrl` | 48 |
| `0x0030` | `GlobalCtrl30` | 20 |
| `0x0031` | `WaitSE` | 7 |
| `0x0032` | `SyncWait32` | 15 |
| `0x0033` | `SetWorkOrWait` | 732 |
| `0x0035` | `Sub35` | 4 |
| `0x0037` | `ScreenEffect37` | 2 |
| `0x0038` | `VoiceChannel` | 122 |
| `0x003a` | `Sub3A` | 5 |
| `0x003b` | `Sub3B` | 25 |
| `0x003d` | `Sub3D` | 2 |
| `0x003e` | `Sub3E` | 31 |
| `0x003f` | `Sub3F` | 30 |
| `0x0042` | `Sub42` | 5 |
| `0x0043` | `TitleOrSystem43` | 1402 |
| `0x0044` | `Sub44` | 10 |
| `0x0046` | `Sub46` | 44 |
| `0x004b` | `Sub4B` | 1 |
| `0x004c` | `Sub4C` | 6 |
| `0x0050` | `CondJump50` | 14 |
| `0x0051` | `Sub51` | 60 |
| `0x0053` | `Sub53Data` | 19 |
| `0x0054` | `CallIf54` | 525 |
| `0x0056` | `CallFarIf56` | 2 |
| `0x0058` | `DataLoad58` | 21 |
| `0x0059` | `JumpIf59` | 10 |
| `0x005f` | `Sub5F` | 5 |
| `0x0101` | `ReleaseSurf` | 24 |
| `0x0102` | `LoadPic` | 46 |
| `0x0105` | `DispCtrl` | 81 |
| `0x0108` | `BGSwapOrFade` | 15 |
| `0x0109` | `MesWindow` | 27706 |
| `0x010a` | `MesMode` | 3 |
| `0x010b` | `MesClear` | 27706 |
| `0x010c` | `Mes` | 27706 |
| `0x010d` | `MesMain` | 27697 |
| `0x010e` | `SetMesMacro` | 7 |
| `0x010f` | `MesFontLoad` | 1 |
| `0x0110` | `SetChoiceCtrl` | 50 |
| `0x0111` | `MesSync` | 65448 |
| `0x0112` | `Select` | 21 |
| `0x0113` | `SelectWait` | 6 |
| `0x0114` | `MesVoiceWait` | 10 |
| `0x0121` | `LoadMask` | 7 |
| `0x0122` | `MoviePlay` | 40 |
| `0x0123` | `MovieCtrl` | 84 |
| `0x0124` | `MovieWait` | 5 |
| `0x0125` | `Effect125` | 36 |
| `0x0126` | `MovieEx126` | 5 |
| `0x012b` | `Effect12B` | 10 |
| `0x1000` | `SG0_InitOrMode` | 71 |
| `0x1001` | `SG0_BgChaCtrl` | 2022 |
| `0x1002` | `SG0_VoiceOrLip` | 16 |
| `0x1004` | `SG0_SpriteAnim` | 10 |
| `0x1005` | `SG0_ChaLoad` | 5917 |
| `0x1006` | `SG0_ChaRelease` | 3 |
| `0x100b` | `SG0_ChaSync` | 5877 |
| `0x1010` | `SG0_System1010` | 41 |
| `0x1011` | `SG0_System1011` | 44 |
| `0x1013` | `SG0_SaveLoadMenu` | 21 |
| `0x1014` | `SG0_SysMenu` | 20 |
| `0x101a` | `SG0_Sub101A` | 12 |
| `0x101b` | `SG0_Sub101B` | 10 |
| `0x101d` | `SG0_Sub101D` | 5 |
| `0x101f` | `SG0_Sub101F` | 15 |
| `0x1020` | `SG0_Sub1020` | 5 |
| `0x1021` | `SG0_Sub1021` | 10 |
| `0x1022` | `SG0_PhoneCtrl` | 1673 |
| `0x1023` | `SG0_TipsCtrl` | 58 |
| `0x1024` | `SG0_Achievement` | 15 |
| `0x1027` | `SG0_Sub1027` | 2 |
| `0x1028` | `SG0_Sub1028` | 4 |
| `0x1029` | `SG0_SysCall1029` | 507 |
| `0x102a` | `SG0_Sub102A` | 4 |
| `0x102d` | `SG0_Sub102D` | 5 |
| `0x1030` | `SG0_GalleryOrMusic` | 15 |
| `0x1033` | `SG0_HelpCtrl` | 41 |
| `0x1034` | `SG0_AmadeusOrExtra` | 24 |
| `0x1037` | `SG0_RineCtrl` | 904 |
| `0x1040` | `SG0_Sub1040` | 1 |
| `0x1041` | `SG0_Sub1041` | 2 |
| `0xFE` | `ExprStmt` | 23955 |

## 7. 高频 ScrWork 与 FlagWork 引用（前 30 项）

- **ScrWork 高频索引**：`1400`(3372), `4363`(2855), `1410`(2524), `1022`(1730), `5260`(1425), `1407`(1287), `38`(1260), `1402`(1180), `1401`(1052), `1403`(890), `4551`(806), `1415`(777), `51`(721), `4541`(658), `4540`(651), `4549`(643), `4544`(638), `2191`(617), `1420`(561), `6655`(552), `2190`(467), `1411`(443), `5300`(440), `39`(410), `61`(380), `2147`(361), `1406`(311), `1405`(300), `1421`(281), `1404`(213)
- **FlagWork 高频索引**：`2492`(10), `109`(6), `2484`(5), `2740`(4), `2743`(4), `2493`(4), `113`(3), `114`(3), `801`(2), `806`(2), `108`(2), `100`(2), `102`(2), `2610`(2), `802`(1), `803`(1), `804`(1), `805`(1), `98`(1), `800`(1), `90`(1), `860`(1), `91`(1), `864`(1), `92`(1), `863`(1), `99`(1), `115`(1), `103`(1), `101`(1)
