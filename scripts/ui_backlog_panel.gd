class_name UiBacklogPanel
extends Control
## MAGES. PC 1:1 历史对话回放界面（BACKLOG：左上旋转圆环书本徽章、橙色喇叭语音标记、自定义右侧滚动滑块）

signal voice_replay_requested(voice_id: int)
signal voice_replay_with_char_requested(voice_id: int, char_id: int)
signal closed()

var _vfs: MgsVfs = null
var _vm: Sc3Vm = null
var _theme_loader: UiThemeLoader = null
var _assets: Dictionary = {}

var _sheet_tex: TextureRect = null
var _ring_tex: TextureRect = null
var _book_tex: TextureRect = null
var _scroll_thumb: TextureRect = null
var _footer_tex: TextureRect = null
var _scroll: ScrollContainer = null
var _list_box: VBoxContainer = null

var _row_highlights: Array[ColorRect] = []
var _row_voices: Array[int] = []
var _row_char_ids: Array[int] = []
var _selected_idx: int = -1
var _built: bool = false
var _ring_angle: float = 0.0
var _scroll_to_bottom_frames: int = 0
var _drag_active: bool = false
var _drag_start_y: float = 0.0
var _drag_start_scroll: int = 0
var _drag_moved: bool = false


func _ready() -> void:
	name = "UiBacklogPanel"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(vfs: MgsVfs, vm: Sc3Vm, loader: UiThemeLoader) -> void:
	_vfs = vfs
	_vm = vm
	_theme_loader = loader
	_ensure_ui()
	_bind_assets()


func open_panel() -> void:
	_ensure_ui()
	if _assets.is_empty():
		_bind_assets()
	_rebuild_entries()
	visible = true
	_scroll_to_bottom_frames = 2


func close_panel() -> void:
	visible = false
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	_ring_angle = fmod(_ring_angle + delta * 0.16, TAU)
	if _ring_tex != null:
		_ring_tex.rotation = _ring_angle

	if _scroll_to_bottom_frames > 0:
		_scroll_to_bottom_frames -= 1
		if _scroll_to_bottom_frames == 0 and _scroll != null:
			var vbar := _scroll.get_v_scroll_bar()
			if vbar != null:
				_scroll.scroll_vertical = int(vbar.max_value)

	_update_scroll_thumb()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode == KEY_ESCAPE or ke.keycode == KEY_BACKSPACE:
			close_panel()
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not visible or _scroll == null:
		_drag_active = false
		_drag_moved = false
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			if _scroll.get_global_rect().has_point(st.position):
				_drag_active = true
				_drag_moved = false
				_drag_start_y = st.position.y
				_drag_start_scroll = _scroll.scroll_vertical
		else:
			if _drag_active and _drag_moved:
				get_viewport().set_input_as_handled()
			_drag_active = false
	elif event is InputEventScreenDrag and _drag_active:
		var sd := event as InputEventScreenDrag
		var dy := sd.position.y - _drag_start_y
		if absf(dy) > 12.0:
			_drag_moved = true
		if _drag_moved:
			_scroll.scroll_vertical = maxi(0, _drag_start_scroll - int(dy))
			get_viewport().set_input_as_handled()


func _ensure_ui() -> void:
	if _built:
		return
	_built = true

	# 1. 半透明舞台暗幕（两侧露出少许游戏画面，对齐 PC 截图）
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.04, 0.78)
	add_child(dim)

	# 2. BACKLOG.DDS 暗金边框主卷轴底板
	_sheet_tex = TextureRect.new()
	_sheet_tex.position = Vector2(154, 0)
	_sheet_tex.size = Vector2(1665, 1080)
	_sheet_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sheet_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_sheet_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sheet_tex)

	# 3. 历史文本滚动区（隐藏原生滚动条，改用原版发光胶囊滑块）
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(278, 32)
	_scroll.size = Vector2(1472, 942)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list_box)

	# 4. 右侧原版白色发光滚动滑块
	_scroll_thumb = TextureRect.new()
	_scroll_thumb.position = Vector2(1774, 48)
	_scroll_thumb.size = Vector2(28, 91)
	_scroll_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scroll_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_scroll_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scroll_thumb)

	# 5. 左上角 BACKLOG 旋转圆环与翻开书本徽章（叠加于边框之上）
	_ring_tex = TextureRect.new()
	_ring_tex.position = Vector2(-42, -30)
	_ring_tex.size = Vector2(430, 416)
	_ring_tex.pivot_offset = Vector2(215, 208)
	_ring_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ring_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ring_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring_tex)

	_book_tex = TextureRect.new()
	_book_tex.position = Vector2(96, 100)
	_book_tex.size = Vector2(154, 124)
	_book_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_book_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_book_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_book_tex)

	# 6. 右下角底部功能提示条（可点击“播放语音”与“返回”）
	_footer_tex = TextureRect.new()
	_footer_tex.position = Vector2(1312, 984)
	_footer_tex.size = Vector2(560, 60)
	_footer_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_footer_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_footer_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_footer_tex)

	var btn_voice := _make_invisible_btn(Vector2(1515, 984), Vector2(180, 60))
	btn_voice.tooltip_text = "播放选中条目语音"
	btn_voice.pressed.connect(_replay_selected)
	add_child(btn_voice)

	var btn_back := _make_invisible_btn(Vector2(1735, 984), Vector2(145, 60))
	btn_back.tooltip_text = "返回"
	btn_back.pressed.connect(close_panel)
	add_child(btn_back)


func _bind_assets() -> void:
	if _theme_loader == null:
		return
	_assets = _theme_loader.get_backlog_assets()
	if _assets.is_empty():
		return
	if _assets.get("panel", null) != null:
		_sheet_tex.texture = _assets["panel"] as Texture2D
	if _assets.get("scroll_thumb", null) != null:
		_scroll_thumb.texture = _assets["scroll_thumb"] as Texture2D
	if _assets.get("ring_backlog", null) != null:
		_ring_tex.texture = _assets["ring_backlog"] as Texture2D
	if _assets.get("icon_book", null) != null:
		_book_tex.texture = _assets["icon_book"] as Texture2D
	if _assets.get("footer", null) != null:
		_footer_tex.texture = _assets["footer"] as Texture2D


func _rebuild_entries() -> void:
	for c in _list_box.get_children():
		_list_box.remove_child(c)
		c.queue_free()
	_row_highlights.clear()
	_row_voices.clear()
	_row_char_ids.clear()
	_selected_idx = -1

	if _vm == null or _vm.backlog.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "暂无历史对话记录"
		empty_lbl.custom_minimum_size = Vector2(1420, 120)
		empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 26)
		empty_lbl.modulate = Color(0.75, 0.78, 0.84, 0.85)
		_list_box.add_child(empty_lbl)
		return

	var entries := _vm.backlog
	var start := maxi(0, entries.size() - 100)
	var speaker_tex := _assets.get("speaker_icon") as Texture2D

	for i in range(start, entries.size()):
		var item: Dictionary = entries[i]
		var sname := str(item.get("script", ""))
		var off := int(item.get("str_offset", -1))
		var vid := int(item.get("voice_id", -1))
		if _vfs == null or not _vfs.is_mounted or sname == "" or off < 0:
			continue
		var sdata := _vfs.read_entry("script.mpk", sname)
		if sdata.is_empty():
			continue

		var row := Control.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.mouse_filter = Control.MOUSE_FILTER_PASS

		var hl := ColorRect.new()
		hl.set_anchors_preset(Control.PRESET_FULL_RECT)
		hl.color = Color(0.84, 0.78, 0.66, 0.24)
		hl.visible = false
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hl)

		var body_fr := MgsFontRenderer.new()
		body_fr.bind_vfs(_vfs)
		body_fr.base_scale = 0.74
		body_fr.line_height = 48.0
		body_fr.max_line_width = 1360.0
		body_fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body_fr.set_sc3_string(sdata, off, _vm, null, true)

		var name_arr := body_fr.get_name_glyphs()
		var has_name := not name_arr.is_empty()
		var body_y := 8.0

		if has_name:
			if vid > 0 and speaker_tex != null:
				var spk := TextureRect.new()
				spk.position = Vector2(20, 10)
				spk.size = Vector2(44, 34)
				spk.texture = speaker_tex
				spk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				spk.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				spk.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(spk)

			var name_fr := MgsFontRenderer.new()
			name_fr.bind_vfs(_vfs)
			name_fr.position = Vector2(72, 6)
			name_fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var gids := PackedInt32Array()
			for ng in name_arr:
				gids.append(int(ng["gid"]))
			name_fr.set_glyph_list(gids, 0.74, Color(1.0, 0.54, 0.16))
			row.add_child(name_fr)
			body_y = 50.0

		body_fr.position = Vector2(72, body_y)
		row.add_child(body_fr)

		var body_h := maxf(48.0, body_fr.get_content_size().y)
		var total_h := body_y + body_h + 10.0
		row.custom_minimum_size = Vector2(1460, total_h)

		var hit := _make_invisible_btn(Vector2.ZERO, Vector2(1460, total_h))
		hit.mouse_filter = Control.MOUSE_FILTER_PASS
		var row_idx := _row_highlights.size()
		hit.pressed.connect(func():
			if _drag_moved:
				_drag_moved = false
				return
			_on_row_clicked(row_idx)
		)
		row.add_child(hit)

		_row_highlights.append(hl)
		_row_voices.append(vid)
		_row_char_ids.append(int(item.get("char_id", 0)))
		_list_box.add_child(row)

	if not _row_highlights.is_empty():
		_select_row(_row_highlights.size() - 1)


func _select_row(idx: int) -> void:
	_selected_idx = clampi(idx, 0, _row_highlights.size() - 1)
	for i in range(_row_highlights.size()):
		_row_highlights[i].visible = (i == _selected_idx)


func _on_row_clicked(idx: int) -> void:
	_select_row(idx)
	if idx >= 0 and idx < _row_voices.size():
		var vid := _row_voices[idx]
		if vid > 0:
			var cid := _row_char_ids[idx] if idx < _row_char_ids.size() else 0
			voice_replay_requested.emit(vid)
			voice_replay_with_char_requested.emit(vid, cid)


func _replay_selected() -> void:
	if _selected_idx >= 0 and _selected_idx < _row_voices.size():
		var vid := _row_voices[_selected_idx]
		if vid > 0:
			var cid := _row_char_ids[_selected_idx] if _selected_idx < _row_char_ids.size() else 0
			voice_replay_requested.emit(vid)
			voice_replay_with_char_requested.emit(vid, cid)


func _update_scroll_thumb() -> void:
	if _scroll == null or _scroll_thumb == null:
		return
	var vbar := _scroll.get_v_scroll_bar()
	if vbar == null or vbar.max_value <= _scroll.size.y:
		_scroll_thumb.visible = false
		return
	_scroll_thumb.visible = true
	var max_scroll := maxf(1.0, vbar.max_value - _scroll.size.y)
	var ratio := clampf(float(_scroll.scroll_vertical) / max_scroll, 0.0, 1.0)
	_scroll_thumb.position.y = 48.0 + ratio * (920.0 - 91.0)


func _make_invisible_btn(pos: Vector2, sz: Vector2) -> Button:
	var b := Button.new()
	b.position = pos
	b.size = sz
	b.flat = true
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, empty)
	return b
