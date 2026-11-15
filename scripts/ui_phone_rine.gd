class_name UiPhoneRine
extends Control
## Amadeus / 手机 RINE 聊天抽屉界面（右侧滑入，加载 PHONE.DDS 红黑机身与 PHONE_RINE.DDS 18 枚表情贴纸）

signal panel_toggled(opened: bool)
signal amadeus_action(accepted: bool)

var _vfs: MgsVfs = null
var _vm: Sc3Vm = null
var _theme_loader: UiThemeLoader = null

var _drawer: Control = null
var _frame_tex: TextureRect = null
var _amadeus_logo: TextureRect = null
var _msg_list: VBoxContainer = null
var _sticker_grid: GridContainer = null
var _status_label: Label = null
var _connect_bar: HBoxContainer = null

var _is_open: bool = false
var _tween: Tween = null
var _stickers: Array[Texture2D] = []
var _avatars: Array[Texture2D] = []
var _phone_bytes: PackedByteArray = PackedByteArray()
var _phone_offsets: PackedInt32Array = PackedInt32Array()
var _messages: Array[Dictionary] = []


func _ready() -> void:
	name = "UiPhoneRine"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = true
	_ensure_ui()


func _ensure_ui() -> void:
	if _drawer != null:
		return
	_drawer = Control.new()
	_drawer.name = "PhoneDrawer"
	_drawer.size = Vector2(620, 1080)
	_drawer.position = Vector2(1920, 0) # 默认隐藏于右侧画面外
	_drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_drawer)

	_frame_tex = TextureRect.new()
	_frame_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_frame_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer.add_child(_frame_tex)

	var screen_bg := ColorRect.new()
	screen_bg.position = Vector2(44, 124)
	screen_bg.size = Vector2(532, 746)
	screen_bg.color = Color(0.05, 0.06, 0.09, 1.0)
	_drawer.add_child(screen_bg)

	var header := PanelContainer.new()
	header.position = Vector2(54, 126)
	header.size = Vector2(512, 54)
	header.add_theme_stylebox_override("panel", UiThemeLoader.make_dark_panel_style(Color(0.16, 0.06, 0.05, 0.92), Color(0.85, 0.35, 0.15, 0.9)))
	_drawer.add_child(header)

	var hbox := HBoxContainer.new()
	header.add_child(hbox)
	_status_label = Label.new()
	_status_label.text = "RINE / Amadeus 终端"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.add_theme_font_size_override("font_size", 20)
	hbox.add_child(_status_label)

	var btn_close := Button.new()
	btn_close.text = "收起"
	btn_close.custom_minimum_size = Vector2(78, 34)
	btn_close.pressed.connect(close_phone)
	hbox.add_child(btn_close)

	_amadeus_logo = TextureRect.new()
	_amadeus_logo.position = Vector2(170, 184)
	_amadeus_logo.size = Vector2(280, 96)
	_amadeus_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_amadeus_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_amadeus_logo.visible = false
	_drawer.add_child(_amadeus_logo)

	_connect_bar = HBoxContainer.new()
	_connect_bar.position = Vector2(110, 286)
	_connect_bar.size = Vector2(400, 46)
	_connect_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_connect_bar.add_theme_constant_override("separation", 18)
	_connect_bar.visible = false
	_drawer.add_child(_connect_bar)

	var btn_conn := Button.new()
	btn_conn.text = "接听 CONNECT"
	btn_conn.add_theme_stylebox_override("normal", UiThemeLoader.make_button_style(false))
	btn_conn.pressed.connect(func():
		_connect_bar.visible = false
		_amadeus_logo.visible = false
		amadeus_action.emit(true)
	)
	var btn_cancel := Button.new()
	btn_cancel.text = "挂断 CANCEL"
	btn_cancel.add_theme_stylebox_override("normal", UiThemeLoader.make_button_style(true))
	btn_cancel.pressed.connect(func():
		_connect_bar.visible = false
		_amadeus_logo.visible = false
		amadeus_action.emit(false)
	)
	_connect_bar.add_child(btn_conn)
	_connect_bar.add_child(btn_cancel)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(56, 188)
	scroll.size = Vector2(508, 490)
	_drawer.add_child(scroll)

	_msg_list = VBoxContainer.new()
	_msg_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_msg_list)

	# 底部 RINE 表情贴纸栏
	var sticker_panel := PanelContainer.new()
	sticker_panel.position = Vector2(56, 686)
	sticker_panel.size = Vector2(508, 178)
	sticker_panel.add_theme_stylebox_override("panel", UiThemeLoader.make_dark_panel_style(Color(0.08, 0.10, 0.14, 0.92), Color(0.35, 0.45, 0.55, 0.8)))
	_drawer.add_child(sticker_panel)

	var st_scroll := ScrollContainer.new()
	st_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	sticker_panel.add_child(st_scroll)

	_sticker_grid = GridContainer.new()
	_sticker_grid.columns = 6
	_sticker_grid.add_theme_constant_override("h_separation", 6)
	_sticker_grid.add_theme_constant_override("v_separation", 6)
	st_scroll.add_child(_sticker_grid)


func setup(vfs: MgsVfs, vm: Sc3Vm, loader: UiThemeLoader) -> void:
	_vfs = vfs
	_vm = vm
	_theme_loader = loader
	_ensure_ui()

	if _theme_loader != null:
		var bgs := _theme_loader.get_panel_backdrops()
		if bgs.get("phone_frame", null) != null:
			_frame_tex.texture = bgs["phone_frame"] as Texture2D
		if bgs.get("amadeus_logo", null) != null:
			_amadeus_logo.texture = bgs["amadeus_logo"] as Texture2D
		_stickers = _theme_loader.get_rine_stickers()
		_avatars = _theme_loader.get_rine_avatars()
		_populate_sticker_tray()

	if _vfs != null and _vfs.is_mounted and _vfs.has_entry("script.mpk", "_phone.scx"):
		_phone_bytes = _vfs.read_entry("script.mpk", "_phone.scx")
		if _phone_bytes.size() >= 16:
			var stbl := int(_phone_bytes.decode_u32(4))
			var rtbl := int(_phone_bytes.decode_u32(8))
			var cnt := maxi(0, (rtbl - stbl) / 4)
			_phone_offsets.resize(cnt)
			for i in range(cnt):
				_phone_offsets[i] = int(_phone_bytes.decode_u32(stbl + i * 4))

	if _vm != null:
		if not _vm.phone_event.is_connected(_on_phone_event):
			_vm.phone_event.connect(_on_phone_event)
		if not _vm.rine_event.is_connected(_on_rine_event):
			_vm.rine_event.connect(_on_rine_event)

	if _messages.is_empty():
		# 预置最近联络预览，确保初次手动打开也有实质消息与原版贴纸展示
		_append_text_msg(0, "LabMem001 冈部伦太郎：Amadeus 系统连接就绪。", false)
		if not _phone_offsets.is_empty():
			_append_sc3_msg(1, 0)


func _populate_sticker_tray() -> void:
	for c in _sticker_grid.get_children():
		c.queue_free()
	for i in range(_stickers.size()):
		var tex := _stickers[i]
		if tex == null:
			continue
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(74, 74)
		btn.icon = tex
		btn.expand_icon = true
		btn.pressed.connect(func(): _append_sticker_msg(i))
		_sticker_grid.add_child(btn)


func toggle_phone() -> void:
	if _is_open:
		close_phone()
	else:
		open_phone()


func open_phone() -> void:
	_ensure_ui()
	_is_open = true
	_animate_x(1290.0)
	panel_toggled.emit(true)


func close_phone() -> void:
	_ensure_ui()
	_is_open = false
	_animate_x(1920.0)
	panel_toggled.emit(false)


func is_phone_open() -> bool:
	return _is_open


func _animate_x(target_x: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_drawer, "position:x", target_x, 0.25)


func _on_phone_event(subop: int, _args: Array) -> void:
	if subop == 5 or subop == 10:
		_status_label.text = "Amadeus 来电"
		_amadeus_logo.visible = _amadeus_logo.texture != null
		_connect_bar.visible = true
	elif subop == 255:
		_amadeus_logo.visible = false
		_connect_bar.visible = false
		_status_label.text = "RINE / Amadeus 终端"


func _on_rine_event(subop: int, args: Array) -> void:
	if subop == 0 or subop == 12 or subop == 15:
		var cid := int(args[0]) if args.size() > 0 else 0
		var msg_idx := int(args[1]) if args.size() > 1 else -1
		if msg_idx >= 0 and msg_idx < _phone_offsets.size():
			_append_sc3_msg(cid % maxi(1, _avatars.size()), msg_idx)
		else:
			_append_text_msg(cid % maxi(1, _avatars.size()), "收到新 RINE 消息 #%d" % msg_idx, false)
	elif subop == 13 or subop == 46:
		var st_idx := int(args[1]) if args.size() > 1 else 0
		if st_idx >= 0 and st_idx < _stickers.size():
			_append_sticker_msg(st_idx)


func _append_sc3_msg(avatar_idx: int, str_id: int) -> void:
	if _phone_bytes.is_empty() or str_id < 0 or str_id >= _phone_offsets.size():
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if avatar_idx >= 0 and avatar_idx < _avatars.size() and _avatars[avatar_idx] != null:
		var av := TextureRect.new()
		av.texture = _avatars[avatar_idx]
		av.custom_minimum_size = Vector2(44, 48)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(av)

	var bubble := PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.custom_minimum_size = Vector2(410, 56)
	bubble.add_theme_stylebox_override("panel", UiThemeLoader.make_dark_panel_style(Color(0.14, 0.16, 0.22, 0.95), Color(0.35, 0.55, 0.75, 0.8)))

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(390, 44)
	bubble.add_child(holder)

	var fr := MgsFontRenderer.new()
	fr.bind_vfs(_vfs)
	fr.base_scale = 0.52
	fr.line_height = 30.0
	fr.max_line_width = 380.0
	holder.add_child(fr)
	var res := fr.set_sc3_string(_phone_bytes, int(_phone_offsets[str_id]), _vm, null, true)
	var line_h_est := maxf(44.0, float(res.get("end_y", 34.0)) + 16.0)
	holder.custom_minimum_size = Vector2(390, line_h_est)
	bubble.custom_minimum_size = Vector2(410, line_h_est + 12.0)

	row.add_child(bubble)
	_msg_list.add_child(row)
	_messages.append({"type": "sc3", "str_id": str_id})


func _append_text_msg(avatar_idx: int, txt: String, is_self: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if not is_self and avatar_idx >= 0 and avatar_idx < _avatars.size() and _avatars[avatar_idx] != null:
		var av := TextureRect.new()
		av.texture = _avatars[avatar_idx]
		av.custom_minimum_size = Vector2(44, 48)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		row.add_child(av)
	var lbl := Label.new()
	lbl.text = txt
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 18)
	row.add_child(lbl)
	_msg_list.add_child(row)
	_messages.append({"type": "text", "text": txt})


func _append_sticker_msg(sticker_idx: int) -> void:
	if sticker_idx < 0 or sticker_idx >= _stickers.size():
		return
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	var tr := TextureRect.new()
	tr.texture = _stickers[sticker_idx]
	tr.custom_minimum_size = Vector2(128, 128)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(tr)
	_msg_list.add_child(row)
	_messages.append({"type": "sticker", "idx": sticker_idx})
