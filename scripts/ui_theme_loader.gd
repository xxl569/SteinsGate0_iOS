class_name UiThemeLoader
extends RefCounted
## MAGES. 原版 system.mpk UI 贴图图集加载与精确切片器

var _vfs: MgsVfs = null
var _sheets: Dictionary = {} # sheet_name -> Texture2D
var _atlases: Dictionary = {} # cache_key -> AtlasTexture


func bind_vfs(vfs: MgsVfs) -> void:
	_vfs = vfs
	_sheets.clear()
	_atlases.clear()


func get_sheet(sheet_name: String) -> Texture2D:
	if _sheets.has(sheet_name):
		return _sheets[sheet_name] as Texture2D
	if _vfs == null or not _vfs.is_mounted:
		return null
	if not _vfs.has_entry("system.mpk", sheet_name):
		return null
	var tex := _vfs.decode_texture("system.mpk", sheet_name, false)
	if tex != null:
		_sheets[sheet_name] = tex
	return tex


func get_region(sheet_name: String, rect: Rect2i) -> Texture2D:
	var key := "%s:%d,%d,%d,%d" % [sheet_name, rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	if _atlases.has(key):
		return _atlases[key] as Texture2D
	var sheet := get_sheet(sheet_name)
	if sheet == null:
		return null
	var max_w := sheet.get_width()
	var max_h := sheet.get_height()
	var rx := clampi(rect.position.x, 0, max_w - 1)
	var ry := clampi(rect.position.y, 0, max_h - 1)
	var rw := clampi(rect.size.x, 1, max_w - rx)
	var rh := clampi(rect.size.y, 1, max_h - ry)
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(rx, ry, rw, rh)
	atlas.filter_clip = true
	_atlases[key] = atlas
	return atlas


## 获取标题界面背景与主菜单按键贴图
func get_title_assets() -> Dictionary:
	var res := {
		"bg": get_region("TITLE_CHIP.DDS", Rect2i(0, 0, 1920, 1080)),
		"normal": [],
		"hover": [],
		"press_hint": get_region("TITLE_CHIP.DDS", Rect2i(10, 1428, 460, 39)),
	}
	for i in range(5):
		var row_y := 1090 + i * 64
		(res["normal"] as Array).append(get_region("TITLE_CHIP.DDS", Rect2i(651, row_y, 264, 62)))
		(res["hover"] as Array).append(get_region("TITLE_CHIP.DDS", Rect2i(936, row_y, 249, 62)))
	return res


## 获取对话框底板与指示图标贴图（含 AUTO / SKIP / WAIT 20 帧原版 3D 金环动画序列）
func get_meswin_assets() -> Dictionary:
	var auto_frames: Array[Texture2D] = []
	var skip_frames: Array[Texture2D] = []
	var wait_frames: Array[Texture2D] = []
	for r in range(5):
		for c in range(4):
			auto_frames.append(get_region("MESWIN.DDS", Rect2i(2472 + c * 150, r * 150, 150, 150)))
			skip_frames.append(get_region("MESWIN.DDS", Rect2i(2472 + c * 150, 750 + r * 150, 150, 150)))
	for r in range(2):
		for c in range(10):
			wait_frames.append(get_region("MESWIN.DDS", Rect2i(1924 + c * 54, 910 + r * 54, 52, 52)))

	return {
		"box": get_region("MESWIN.DDS", Rect2i(0, 888, 1920, 318)),
		"accent": get_region("MESWIN.DDS", Rect2i(5, 820, 326, 28)),
		"accent_left": get_region("MESWIN.DDS", Rect2i(5, 820, 158, 28)),
		"accent_right": get_region("MESWIN.DDS", Rect2i(173, 820, 158, 28)),
		"date_pill_bg": get_region("MESWIN.DDS", Rect2i(1933, 1023, 260, 133)),
		"auto_btn_off": get_region("MESWIN.DDS", Rect2i(2207, 1078, 119, 39)),
		"auto_btn_on": get_region("MESWIN.DDS", Rect2i(2198, 1024, 137, 40)),
		"skip_btn_off": get_region("MESWIN.DDS", Rect2i(2207, 1186, 119, 39)),
		"skip_btn_on": get_region("MESWIN.DDS", Rect2i(2207, 1132, 119, 39)),
		"auto_badge": get_region("MESWIN.DDS", Rect2i(2192, 1040, 210, 48)),
		"skip_badge": get_region("MESWIN.DDS", Rect2i(2192, 1090, 210, 48)),
		"auto_ring": auto_frames[3] if auto_frames.size() > 3 else null,
		"skip_ring": skip_frames[3] if skip_frames.size() > 3 else null,
		"wait_ring": wait_frames[2] if wait_frames.size() > 2 else null,
		"auto_ring_frames": auto_frames,
		"skip_ring_frames": skip_frames,
		"wait_ring_frames": wait_frames,
		"quicksave_gear": get_region("MESWIN.DDS", Rect2i(1930, 686, 260, 140)),
		"tips_banner": get_region("DATA01.DDS", Rect2i(195, 3, 762, 102)),
	}


## 获取 PC 1:1 手机终端 / RINE / 壁纸 / 图标全套切片
func get_phone_assets() -> Dictionary:
	var wallpapers: Array[Texture2D] = []
	var pw_sheet := get_sheet("PWCG.DDS")
	if pw_sheet != null:
		for row in range(2):
			for col in range(6):
				wallpapers.append(get_region("PWCG.DDS", Rect2i(col * 456, row * 726, 456, 726)))
	var app_icons: Array[Texture2D] = [
		get_region("PHONE_B.DDS", Rect2i(2220, 1410, 92, 118)), # 電話
		get_region("PHONE_B.DDS", Rect2i(2328, 1410, 92, 118)), # RINE
		get_region("PHONE_B.DDS", Rect2i(2436, 1410, 92, 118)), # Amadeus
		get_region("PHONE_B.DDS", Rect2i(2544, 1410, 92, 118)), # 設定
	]
	var app_icons_active: Array[Texture2D] = [
		get_region("PHONE_B.DDS", Rect2i(2650, 1410, 95, 118)),
		get_region("PHONE_B.DDS", Rect2i(2755, 1410, 95, 118)),
		get_region("PHONE_B.DDS", Rect2i(2860, 1410, 95, 118)),
		get_region("PHONE_B.DDS", Rect2i(2965, 1410, 95, 118)),
	]
	return {
		"phone_frame": get_region("PHONE.DDS", Rect2i(0, 0, 620, 1080)),
		"amadeus_logo": get_region("PHONE.DDS", Rect2i(940, 760, 400, 240)),
		"rine_bg": get_region("PHONE_B.DDS", Rect2i(1473, 0, 456, 696)),
		"settings_bg": get_region("PHONE_B.DDS", Rect2i(1024, 0, 446, 744)),
		"ringtone_bg": get_region("PHONE_B.DDS", Rect2i(1024, 0, 446, 744)),
		"xp_status_bar": get_region("PHONE_B.DDS", Rect2i(0, 1442, 453, 44)),
		"hw_nav_bar": get_region("PHONE_B.DDS", Rect2i(0, 1389, 453, 48)),
		"rine_header_bar": get_region("PHONE_B.DDS", Rect2i(1929, 640, 456, 65)),
		"rine_input_bar": get_region("PHONE_B.DDS", Rect2i(2628, 1236, 342, 54)),
		"rine_emoji": get_region("PHONE_B.DDS", Rect2i(3012, 1218, 42, 42)),
		"rine_send_arrow": get_region("PHONE_B.DDS", Rect2i(3012, 1278, 26, 28)),
		"rine_arrow_left": get_region("PHONE_B.DDS", Rect2i(2416, 1238, 30, 50)),
		"rine_arrow_right": get_region("PHONE_B.DDS", Rect2i(2480, 1238, 30, 50)),
		"rine_arrow_left_active": get_region("PHONE_B.DDS", Rect2i(2416, 1334, 30, 50)),
		"rine_arrow_right_active": get_region("PHONE_B.DDS", Rect2i(2480, 1334, 30, 50)),
		"nav_bar": get_region("PHONE_B.DDS", Rect2i(0, 1389, 453, 147)),
		"app_icons": app_icons,
		"app_icons_active": app_icons_active,
		"wallpapers": wallpapers,
	}


func get_panel_backdrops() -> Dictionary:
	return {
		"savemenu": get_region("SAVEMENU.DDS", Rect2i(5, 0, 1664, 1009)),
		"savemenu_nodata": get_region("SAVEMENU.DDS", Rect2i(1686, 84, 288, 162)),
		"config": get_region("CONFIG.DDS", Rect2i(0, 0, 1920, 1080)),
		"backlog": get_region("BACKLOG.DDS", Rect2i(160, 0, 1665, 1080)),
		"tips": get_region("SYSM_TIPS.DDS", Rect2i(0, 0, 1920, 1080)),
		"phone_frame": get_region("PHONE.DDS", Rect2i(0, 0, 620, 1080)),
		"amadeus_logo": get_region("PHONE.DDS", Rect2i(940, 760, 400, 240)),
	}


## 获取 PC 1:1 CONFIG 系统设置界面全套原版切片
func get_config_assets() -> Dictionary:
	var voice_slots: Array[Texture2D] = []
	for r in range(4):
		for c in range(4):
			voice_slots.append(get_region("CONFIG.DDS", Rect2i(1 + c * 624, 2173 + r * 78, 620, 76)))

	return {
		"bg": get_region("CONFIG.DDS", Rect2i(0, 0, 1920, 1080)),
		"tabs_active": [
			get_region("CONFIG.DDS", Rect2i(1936, 17, 472, 146)),
			get_region("CONFIG.DDS", Rect2i(1936, 197, 472, 146)),
			get_region("CONFIG.DDS", Rect2i(1936, 377, 472, 145)),
			get_region("CONFIG.DDS", Rect2i(2427, 377, 472, 145)),
		],
		"headers": [
			get_region("CONFIG.DDS", Rect2i(1936, 728, 308, 88)),
			get_region("CONFIG.DDS", Rect2i(1939, 816, 305, 88)),
			get_region("CONFIG.DDS", Rect2i(1934, 904, 310, 88)),
			get_region("CONFIG.DDS", Rect2i(1932, 992, 620, 88)),
		],
		"row_highlight": get_region("CONFIG.DDS", Rect2i(2439, 8, 501, 33)),
		"slider_frame": get_region("CONFIG.DDS", Rect2i(2433, 63, 532, 50)),
		"slider_fill": get_region("CONFIG.DDS", Rect2i(2436, 132, 474, 42)),
		"select_oval_red": get_region("CONFIG.DDS", Rect2i(2430, 198, 152, 92)),
		"select_oval_white": get_region("CONFIG.DDS", Rect2i(2580, 199, 152, 92)),
		"voice_off_bar": get_region("CONFIG.DDS", Rect2i(2436, 312, 474, 42)),
		"voice_up_arrow": get_region("CONFIG.DDS", Rect2i(2920, 40, 107, 50)),
		"voice_down_arrow": get_region("CONFIG.DDS", Rect2i(2931, 90, 100, 45)),
		"voice_highlight": get_region("CONFIG.DDS", Rect2i(2523, 2195, 546, 219)),
		"voice_slots": voice_slots,
		"ring_config": get_region("SYSM_TIPS.DDS", Rect2i(610, 1080, 640, 573)),
		"icon_tools": get_region("SYSM_TIPS.DDS", Rect2i(2135, 412, 199, 179)),
		"footer_config": get_region("SYSM_TIPS.DDS", Rect2i(929, 1778, 959, 60)),
		"footer_voice": get_region("SYSM_TIPS.DDS", Rect2i(596, 1856, 1292, 60)),
		# BASIC 行标签与选项
		"lbl_trigger_skip": get_region("CONFIG.DDS", Rect2i(1940, 1097, 815, 50)),
		"opt_trigger_yes": get_region("CONFIG.DDS", Rect2i(2778, 1097, 52, 50)),
		"opt_trigger_no": get_region("CONFIG.DDS", Rect2i(2925, 1097, 46, 50)),
		"lbl_tips_popup": get_region("CONFIG.DDS", Rect2i(1940, 1167, 815, 48)),
		"opt_tips_yes": get_region("CONFIG.DDS", Rect2i(2778, 1167, 52, 48)),
		"opt_tips_no": get_region("CONFIG.DDS", Rect2i(2925, 1167, 46, 48)),
		"lbl_auto_qsave": get_region("CONFIG.DDS", Rect2i(1950, 1240, 468, 50)),
		"opt_qsave_scene": get_region("CONFIG.DDS", Rect2i(2432, 1240, 96, 50)),
		"opt_qsave_trig": get_region("CONFIG.DDS", Rect2i(2598, 1240, 146, 50)),
		"opt_qsave_both": get_region("CONFIG.DDS", Rect2i(2788, 1240, 100, 50)),
		"opt_qsave_none": get_region("CONFIG.DDS", Rect2i(2934, 1240, 98, 50)),
		"lbl_fullscreen": get_region("CONFIG.DDS", Rect2i(1950, 552, 570, 46)),
		"opt_full_on": get_region("CONFIG.DDS", Rect2i(2528, 552, 94, 46)),
		"opt_full_off": get_region("CONFIG.DDS", Rect2i(2864, 552, 92, 46)),
		"lbl_resolution": get_region("CONFIG.DDS", Rect2i(1942, 622, 535, 50)),
		"opt_res_0": get_region("CONFIG.DDS", Rect2i(2482, 622, 178, 50)),
		"opt_res_1": get_region("CONFIG.DDS", Rect2i(2664, 622, 191, 50)),
		"opt_res_2": get_region("CONFIG.DDS", Rect2i(2862, 622, 191, 50)),
		# TEXT 行标签与选项
		"lbl_msg_speed": get_region("CONFIG.DDS", Rect2i(1942, 1457, 610, 44)),
		"lbl_auto_wait": get_region("CONFIG.DDS", Rect2i(1952, 1531, 600, 46)),
		"lbl_skip_mode": get_region("CONFIG.DDS", Rect2i(1940, 1600, 735, 50)),
		"opt_skip_read": get_region("CONFIG.DDS", Rect2i(2704, 1600, 146, 50)),
		"opt_skip_all": get_region("CONFIG.DDS", Rect2i(2948, 1600, 92, 50)),
		# SOUND 行标签与选项
		"lbl_vol_voice": get_region("CONFIG.DDS", Rect2i(1940, 1750, 610, 45)),
		"lbl_vol_bgm": get_region("CONFIG.DDS", Rect2i(1940, 1823, 610, 41)),
		"lbl_vol_se": get_region("CONFIG.DDS", Rect2i(1940, 1895, 610, 41)),
		"lbl_vol_movie": get_region("CONFIG.DDS", Rect2i(1939, 1967, 610, 41)),
		"lbl_audio_sync": get_region("CONFIG.DDS", Rect2i(1940, 2033, 815, 49)),
		"opt_sync_yes": get_region("CONFIG.DDS", Rect2i(2775, 2033, 52, 49)),
		"opt_sync_no": get_region("CONFIG.DDS", Rect2i(2922, 2033, 46, 49)),
		"lbl_skip_voice": get_region("CONFIG.DDS", Rect2i(1940, 2105, 815, 51)),
		"opt_svoice_yes": get_region("CONFIG.DDS", Rect2i(2775, 2105, 52, 51)),
		"opt_svoice_no": get_region("CONFIG.DDS", Rect2i(2922, 2105, 46, 51)),
	}


## 获取 PC 1:1 SAVE/LOAD 界面全套原版切片
func get_saveload_assets() -> Dictionary:
	var page_digits: Array[Texture2D] = [
		get_region("SAVEMENU.DDS", Rect2i(2338, 87, 13, 31)),
		get_region("SAVEMENU.DDS", Rect2i(2371, 87, 20, 31)),
		get_region("SAVEMENU.DDS", Rect2i(2407, 87, 19, 31)),
		get_region("SAVEMENU.DDS", Rect2i(2442, 87, 22, 31)),
		get_region("SAVEMENU.DDS", Rect2i(2479, 87, 20, 31)),
		get_region("SAVEMENU.DDS", Rect2i(2515, 87, 21, 31)),
	]
	return {
		"bg": get_region("SYSM_SAVEMENU.DDS", Rect2i(0, 0, 1920, 1080)),
		"frame": get_region("SAVEMENU.DDS", Rect2i(0, 0, 1670, 1015)),
		"nodata": get_region("SAVEMENU.DDS", Rect2i(1686, 84, 288, 162)),
		"slot_highlight": get_region("SAVEMENU.DDS", Rect2i(1692, 336, 780, 174)),
		"pill_active": get_region("SAVEMENU.DDS", Rect2i(2135, 138, 76, 18)),
		"pill_glow": get_region("SAVEMENU.DDS", Rect2i(2236, 141, 90, 36)),
		"slash_6": get_region("SAVEMENU.DDS", Rect2i(2281, 87, 37, 31)),
		"page_digits": page_digits,
		"unlocked_badge": get_region("SAVEMENU.DDS", Rect2i(2198, 201, 188, 41)),
		"locked_badge": get_region("SAVEMENU.DDS", Rect2i(2234, 267, 139, 41)),
		"ring_save": get_region("SYSM_SAVEMENU.DDS", Rect2i(0, 1080, 610, 573)),
		"ring_load": get_region("SYSM_SAVEMENU.DDS", Rect2i(600, 1080, 610, 573)),
		"icon_clock_round": get_region("SYSM_SAVEMENU.DDS", Rect2i(1932, 6, 179, 184)),
		"icon_clock_square": get_region("SYSM_SAVEMENU.DDS", Rect2i(1936, 217, 173, 174)),
		"footer": get_region("SYSM_SAVEMENU.DDS", Rect2i(1178, 1700, 709, 60)),
	}


## 获取 PC 1:1 BACKLOG 界面全套原版切片
func get_backlog_assets() -> Dictionary:
	return {
		"panel": get_region("BACKLOG.DDS", Rect2i(160, 0, 1665, 1080)),
		"scroll_thumb": get_region("BACKLOG.DDS", Rect2i(1932, 8, 28, 91)),
		"speaker_icon": get_region("BACKLOG.DDS", Rect2i(1929, 117, 58, 44)),
		"ring_backlog": get_region("SYSM_SAVEMENU.DDS", Rect2i(1800, 1080, 591, 573)),
		"icon_book": get_region("SYSM_SAVEMENU.DDS", Rect2i(2132, 5, 214, 171)),
		"footer": get_region("SYSM_SAVEMENU.DDS", Rect2i(1331, 1778, 555, 60)),
	}


## 获取 PC 1:1 TIPS 界面全套原版切片
func get_tips_assets() -> Dictionary:
	return {
		"bg": get_region("SYSM_TIPS.DDS", Rect2i(0, 0, 1920, 1080)),
		"grid_frame": get_region("TIPSCHIPS.DDS", Rect2i(0, 0, 1920, 1080)),
		"ring_tips": get_region("SYSM_TIPS.DDS", Rect2i(0, 1080, 620, 573)),
		"icon_globe": get_region("SYSM_TIPS.DDS", Rect2i(2130, 201, 180, 174)),
		"footer": get_region("SYSM_TIPS.DDS", Rect2i(857, 1700, 1030, 60)),
		"tabs_active": [
			get_region("TIPSCHIPS.DDS", Rect2i(1926, 96, 150, 42)),
			get_region("TIPSCHIPS.DDS", Rect2i(2081, 96, 150, 42)),
			get_region("TIPSCHIPS.DDS", Rect2i(2236, 96, 150, 42)),
			get_region("TIPSCHIPS.DDS", Rect2i(2391, 96, 150, 42)),
		],
		"tabs_inactive": [
			get_region("TIPSCHIPS.DDS", Rect2i(1926, 48, 150, 42)),
			get_region("TIPSCHIPS.DDS", Rect2i(2081, 48, 150, 42)),
			get_region("TIPSCHIPS.DDS", Rect2i(2236, 48, 150, 42)),
			get_region("TIPSCHIPS.DDS", Rect2i(2391, 48, 150, 42)),
		],
		"row_highlight": get_region("TIPSCHIPS.DDS", Rect2i(1926, 144, 618, 46)),
		"new_badge": get_region("TIPSCHIPS.DDS", Rect2i(2540, 81, 72, 44)),
		"scroll_thumb": get_region("TIPSCHIPS.DDS", Rect2i(2846, 11, 26, 71)),
	}


## 切片 PHONE_RINE.DDS 的 12 个头像 (90x90, 步进 96) 与 21 枚表情贴纸 (202x174, 3列x7行)
func get_rine_stickers() -> Array[Texture2D]:
	var stickers: Array[Texture2D] = []
	var sheet := get_sheet("PHONE_RINE.DDS")
	if sheet == null:
		return stickers
	# 右侧 3 列 x 7 行贴纸区 (x: 96..702, y: 0..1216)
	var start_x := 96
	var cell_w := 202
	var stride_y := 174
	for row in range(7):
		for col in range(3):
			var sy := row * stride_y
			var sh := mini(stride_y, 1216 - sy)
			stickers.append(get_region("PHONE_RINE.DDS", Rect2i(start_x + col * cell_w, sy, cell_w, sh)))
	return stickers


func get_rine_avatars() -> Array[Texture2D]:
	var avatars: Array[Texture2D] = []
	var sheet := get_sheet("PHONE_RINE.DDS")
	if sheet == null:
		return avatars
	# 左侧 12 行头像区：每枚实际 90x90，行步进 96px（含 6px 透明间隔）
	var stride_y := 96
	for row in range(12):
		avatars.append(get_region("PHONE_RINE.DDS", Rect2i(0, row * stride_y, 90, 90)))
	return avatars


## 创建统一样式的科幻暗金半透明面板风格
static func make_dark_panel_style(bg_col: Color = Color(0.06, 0.07, 0.09, 0.90), border_col: Color = Color(0.78, 0.42, 0.14, 0.85)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_col
	sb.border_color = border_col
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	return sb


static func make_button_style(normal: bool = true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.13, 0.17, 0.88) if normal else Color(0.76, 0.34, 0.08, 0.92)
	sb.border_color = Color(0.55, 0.36, 0.20, 0.85) if normal else Color(1.0, 0.65, 0.25, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb
