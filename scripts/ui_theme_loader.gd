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


## 获取对话框底板与指示图标贴图
func get_meswin_assets() -> Dictionary:
	return {
		"box": get_region("MESWIN.DDS", Rect2i(0, 888, 1920, 318)),
		"accent": get_region("MESWIN.DDS", Rect2i(0, 818, 340, 36)),
		"auto_badge": get_region("MESWIN.DDS", Rect2i(2192, 1040, 210, 48)),
		"skip_badge": get_region("MESWIN.DDS", Rect2i(2192, 1090, 210, 48)),
		"auto_ring": get_region("MESWIN.DDS", Rect2i(2480, 0, 140, 140)),
	}


func get_panel_backdrops() -> Dictionary:
	return {
		"savemenu": get_region("SAVEMENU.DDS", Rect2i(5, 0, 1664, 1009)),
		"savemenu_nodata": get_region("SAVEMENU.DDS", Rect2i(1686, 40, 290, 170)),
		"config": get_region("CONFIG.DDS", Rect2i(0, 0, 1920, 1080)),
		"backlog": get_region("BACKLOG.DDS", Rect2i(150, 0, 1640, 1080)),
		"tips": get_region("SYSM_TIPS.DDS", Rect2i(0, 0, 1920, 1080)),
		"phone_frame": get_region("PHONE.DDS", Rect2i(0, 0, 620, 1080)),
		"amadeus_logo": get_region("PHONE.DDS", Rect2i(940, 760, 400, 240)),
	}


## 切片 PHONE_RINE.DDS 的 12 个头像与 18 枚中文化表情贴纸
func get_rine_stickers() -> Array[Texture2D]:
	var stickers: Array[Texture2D] = []
	var sheet := get_sheet("PHONE_RINE.DDS")
	if sheet == null:
		return stickers
	# 右侧 3 列 x 6 行贴纸区 (x: 96..704, y: 0..1216)
	var start_x := 96
	var cell_w := 202
	var cell_h := 202
	for row in range(6):
		for col in range(3):
			stickers.append(get_region("PHONE_RINE.DDS", Rect2i(start_x + col * cell_w, row * cell_h, cell_w, cell_h)))
	return stickers


func get_rine_avatars() -> Array[Texture2D]:
	var avatars: Array[Texture2D] = []
	var sheet := get_sheet("PHONE_RINE.DDS")
	if sheet == null:
		return avatars
	var cell_h := 101
	for row in range(12):
		avatars.append(get_region("PHONE_RINE.DDS", Rect2i(0, row * cell_h, 90, cell_h)))
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
