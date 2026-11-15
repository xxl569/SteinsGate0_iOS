class_name UiTips
extends Control
## MAGES. TIPS 词条浏览器（使用 SYSM_TIPS.DDS 原版背景并通过 MgsFontRenderer 渲染 _tips.scx 词条正文）

signal closed()

var _vfs: MgsVfs = null
var _vm: Sc3Vm = null
var _theme_loader: UiThemeLoader = null

var _bg_tex: TextureRect = null
var _list_box: VBoxContainer = null
var _title_renderer: MgsFontRenderer = null
var _body_renderer: MgsFontRenderer = null
var _status_label: Label = null

var _tips_bytes: PackedByteArray = PackedByteArray()
var _tips_offsets: PackedInt32Array = PackedInt32Array()
var _built: bool = false
var _selected_tip: int = 0


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func setup(vfs: MgsVfs, vm: Sc3Vm, loader: UiThemeLoader) -> void:
	_vfs = vfs
	_vm = vm
	_theme_loader = loader
	_ensure_ui()
	_load_tips_scx()


func _ensure_ui() -> void:
	if _built:
		return
	_built = true

	_bg_tex = TextureRect.new()
	_bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_bg_tex)

	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.03, 0.04, 0.06, 0.72)
	add_child(dimmer)

	var header := Label.new()
	header.text = "TIPS 用语词典"
	header.position = Vector2(64, 38)
	header.add_theme_font_size_override("font_size", 34)
	header.modulate = Color(1.0, 0.65, 0.25)
	add_child(header)

	_status_label = Label.new()
	_status_label.position = Vector2(360, 48)
	_status_label.add_theme_font_size_override("font_size", 20)
	add_child(_status_label)

	var btn_close := Button.new()
	btn_close.text = "返回"
	btn_close.position = Vector2(1740, 38)
	btn_close.custom_minimum_size = Vector2(120, 46)
	btn_close.add_theme_stylebox_override("normal", UiThemeLoader.make_button_style(true))
	btn_close.add_theme_stylebox_override("hover", UiThemeLoader.make_button_style(false))
	btn_close.pressed.connect(close_panel)
	add_child(btn_close)

	var left_panel := PanelContainer.new()
	left_panel.position = Vector2(64, 110)
	left_panel.size = Vector2(540, 900)
	left_panel.add_theme_stylebox_override("panel", UiThemeLoader.make_dark_panel_style())
	add_child(left_panel)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	left_panel.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_list_box)

	var right_panel := PanelContainer.new()
	right_panel.position = Vector2(634, 110)
	right_panel.size = Vector2(1220, 900)
	right_panel.add_theme_stylebox_override("panel", UiThemeLoader.make_dark_panel_style())
	add_child(right_panel)

	var detail_root := Control.new()
	detail_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	right_panel.add_child(detail_root)

	_title_renderer = MgsFontRenderer.new()
	_title_renderer.position = Vector2(24, 20)
	_title_renderer.base_scale = 0.85
	_title_renderer.max_line_width = 1140.0
	_title_renderer.default_color = Color(1.0, 0.72, 0.25)
	detail_root.add_child(_title_renderer)

	_body_renderer = MgsFontRenderer.new()
	_body_renderer.position = Vector2(24, 100)
	_body_renderer.base_scale = 0.68
	_body_renderer.line_height = 46.0
	_body_renderer.max_line_width = 1140.0
	detail_root.add_child(_body_renderer)


func _load_tips_scx() -> void:
	if _vfs == null or not _vfs.is_mounted:
		return
	if _theme_loader != null:
		var bgs := _theme_loader.get_panel_backdrops()
		if bgs.get("tips", null) != null:
			_bg_tex.texture = bgs["tips"] as Texture2D
	_title_renderer.bind_vfs(_vfs)
	_body_renderer.bind_vfs(_vfs)

	if not _vfs.has_entry("script.mpk", "_tips.scx"):
		return
	_tips_bytes = _vfs.read_entry("script.mpk", "_tips.scx")
	if _tips_bytes.size() < 16:
		return
	var str_tbl := int(_tips_bytes.decode_u32(4))
	var ret_tbl := int(_tips_bytes.decode_u32(8))
	var count := maxi(0, (ret_tbl - str_tbl) / 4)
	_tips_offsets.resize(count)
	for i in range(count):
		_tips_offsets[i] = int(_tips_bytes.decode_u32(str_tbl + i * 4))


func open_panel() -> void:
	_ensure_ui()
	if _tips_bytes.is_empty():
		_load_tips_scx()
	_rebuild_list()
	visible = true


func close_panel() -> void:
	visible = false
	closed.emit()


func _rebuild_list() -> void:
	for c in _list_box.get_children():
		c.queue_free()

	var total_pairs := mini(120, _tips_offsets.size() / 4)
	var unlocked_count := _vm.unlocked_tips.size() if _vm != null else 0
	_status_label.text = "已解锁词条: %d / 总目录展示: %d (来自 _tips.scx 共 %d 串)" % [unlocked_count, total_pairs, _tips_offsets.size()]

	for i in range(total_pairs):
		var str_idx := 6 + i * 4
		if str_idx + 2 >= _tips_offsets.size():
			break
		var unlocked := (_vm != null and _vm.unlocked_tips.has(i)) or i < 8
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(490, 52)
		btn.add_theme_stylebox_override("normal", UiThemeLoader.make_button_style(true))
		btn.add_theme_stylebox_override("hover", UiThemeLoader.make_button_style(false))
		var prefix := "[NEW] " if (_vm != null and _vm.unlocked_tips.has(i)) else ("○ " if unlocked else "🔒 ")
		btn.text = "%sTIPS #%03d" % [prefix, i + 1]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_select_tip.bind(i, str_idx))
		_list_box.add_child(btn)

	if total_pairs > 0:
		_select_tip(_selected_tip, 6 + _selected_tip * 4)


func _select_tip(tip_id: int, str_idx: int) -> void:
	_selected_tip = tip_id
	if _tips_bytes.is_empty() or str_idx < 0 or str_idx >= _tips_offsets.size():
		return
	var title_off := int(_tips_offsets[str_idx])
	var body_off := int(_tips_offsets[mini(str_idx + 2, _tips_offsets.size() - 1)])
	_title_renderer.set_sc3_string(_tips_bytes, title_off, _vm, null, true)
	_body_renderer.set_sc3_string(_tips_bytes, body_off, _vm, null, true)
