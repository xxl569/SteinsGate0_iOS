class_name UiTips
extends Control
## MAGES. PC 1:1 TIPS 用语词典（SYSM_TIPS.DDS 蝴蝶蓝图 + TIPSCHIPS.DDS 鎏金框 + 全部/已取得/未读/新规 四分类过滤）

signal closed()

enum FilterMode {
	ALL = 0,
	UNLOCKED = 1,
	UNREAD = 2,
	NEW = 3,
}

const TIPS_STATE_PATH := "user://tips_state.json"

var _vfs: MgsVfs = null
var _vm: Sc3Vm = null
var _theme_loader: UiThemeLoader = null
var _assets: Dictionary = {}

var _bg_tex: TextureRect = null
var _grid_tex: TextureRect = null
var _ring_tex: TextureRect = null
var _globe_tex: TextureRect = null
var _footer_tex: TextureRect = null
var _scroll_thumb: TextureRect = null
var _body_scroll_thumb: TextureRect = null

var _tab_imgs: Array[TextureRect] = []
var _list_scroll: ScrollContainer = null
var _list_box: VBoxContainer = null

var _detail_no_label: Label = null
var _detail_title_renderer: MgsFontRenderer = null
var _detail_cat_renderer: MgsFontRenderer = null
var _body_scroll: ScrollContainer = null
var _body_holder: Control = null
var _body_renderer: MgsFontRenderer = null

var _tips_bytes: PackedByteArray = PackedByteArray()
var _tips_offsets: PackedInt32Array = PackedInt32Array()
var _total_tips: int = 0
var _read_tips: Dictionary = {} # tip_id -> true（已点击阅读过的词条）
var _seen_tips: Dictionary = {} # tip_id -> true（已在 TIPS 界面浏览过的新规词条）

var _built: bool = false
var _filter_mode: int = FilterMode.ALL
var _selected_tip_id: int = 0
var _ring_angle: float = 0.0
var _row_highlights: Dictionary = {} # tip_id -> TextureRect
var _row_new_badges: Dictionary = {} # tip_id -> TextureRect

var _active_drag_scroll: ScrollContainer = null
var _drag_start_y: float = 0.0
var _drag_start_scroll: int = 0
var _drag_moved: bool = false


func _ready() -> void:
	name = "UiTips"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(vfs: MgsVfs, vm: Sc3Vm, loader: UiThemeLoader) -> void:
	_vfs = vfs
	_vm = vm
	_theme_loader = loader
	_load_tips_state()
	_ensure_ui()
	_bind_assets()
	_load_tips_scx()


func open_panel() -> void:
	_ensure_ui()
	if _assets.is_empty():
		_bind_assets()
	if _tips_bytes.is_empty():
		_load_tips_scx()
	_switch_filter(_filter_mode)
	visible = true


func close_panel() -> void:
	if _vm != null:
		for k in _vm.unlocked_tips.keys():
			_seen_tips[int(k)] = true
		_save_tips_state()
	visible = false
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	_ring_angle = fmod(_ring_angle + delta * 0.14, TAU)
	if _ring_tex != null:
		_ring_tex.rotation = _ring_angle
	_update_scroll_thumb()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode == KEY_ESCAPE or ke.keycode == KEY_BACKSPACE:
			close_panel()
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_Q:
			_switch_filter((_filter_mode + 3) % 4)
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_E:
			_switch_filter((_filter_mode + 1) % 4)
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not visible:
		_active_drag_scroll = null
		_drag_moved = false
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_drag_moved = false
			if _list_scroll != null and _list_scroll.get_global_rect().has_point(st.position):
				_active_drag_scroll = _list_scroll
			elif _body_scroll != null and _body_scroll.get_global_rect().has_point(st.position):
				_active_drag_scroll = _body_scroll
			else:
				_active_drag_scroll = null
			if _active_drag_scroll != null:
				_drag_start_y = st.position.y
				_drag_start_scroll = _active_drag_scroll.scroll_vertical
		else:
			if _active_drag_scroll != null and _drag_moved:
				get_viewport().set_input_as_handled()
			_active_drag_scroll = null
	elif event is InputEventScreenDrag and _active_drag_scroll != null:
		var sd := event as InputEventScreenDrag
		var dy := sd.position.y - _drag_start_y
		if absf(dy) > 12.0:
			_drag_moved = true
		if _drag_moved:
			_active_drag_scroll.scroll_vertical = maxi(0, _drag_start_scroll - int(dy))
			get_viewport().set_input_as_handled()


func _ensure_ui() -> void:
	if _built:
		return
	_built = true

	# 1. 蝴蝶与相对论公式底层背景
	_bg_tex = TextureRect.new()
	_bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_bg_tex)

	# 2. 半透明黑底压暗 + TIPSCHIPS.DDS 鎏金框线（已内含 Tips / No. / Category / Note 标签）
	var inner_dim := ColorRect.new()
	inner_dim.position = Vector2(112, 58)
	inner_dim.size = Vector2(1702, 952)
	inner_dim.color = Color(0.02, 0.03, 0.04, 0.48)
	inner_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(inner_dim)

	_grid_tex = TextureRect.new()
	_grid_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grid_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_grid_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_grid_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grid_tex)

	# 3. 左上角 TIPS 旋转圆环与拼图地球徽章
	_ring_tex = TextureRect.new()
	_ring_tex.position = Vector2(-46, -28)
	_ring_tex.size = Vector2(465, 430)
	_ring_tex.pivot_offset = Vector2(232, 215)
	_ring_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ring_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ring_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring_tex)

	_globe_tex = TextureRect.new()
	_globe_tex.position = Vector2(14, 152)
	_globe_tex.size = Vector2(148, 144)
	_globe_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_globe_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_globe_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_globe_tex)

	# 4. 4 个分类过滤页签：全部 / 已取得 / 未读 / 新规（精确嵌入金框槽位 x=114 + i*156, y=114）
	for i in range(4):
		var tx := 114 + i * 156
		var tab_img := TextureRect.new()
		tab_img.position = Vector2(tx, 114)
		tab_img.size = Vector2(150, 42)
		tab_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tab_img.stretch_mode = TextureRect.STRETCH_SCALE
		tab_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tab_img)
		_tab_imgs.append(tab_img)

		var tab_btn := _make_invisible_btn(Vector2(tx, 110), Vector2(150, 48))
		var idx := i
		tab_btn.pressed.connect(func(): _switch_filter(idx))
		add_child(tab_btn)

	# 5. 左侧 TIPS 词条滚动列表
	_list_scroll = ScrollContainer.new()
	_list_scroll.position = Vector2(116, 166)
	_list_scroll.size = Vector2(590, 838)
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_list_scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 0)
	_list_scroll.add_child(_list_box)

	# 列表右侧原版白色发光滚动滑块
	_scroll_thumb = TextureRect.new()
	_scroll_thumb.position = Vector2(710, 166)
	_scroll_thumb.size = Vector2(24, 71)
	_scroll_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scroll_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_scroll_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scroll_thumb)

	# 6. 右上角 No. / Category / 词条标题区 (x=780..1812, y=60..264)
	_detail_no_label = Label.new()
	_detail_no_label.position = Vector2(868, 74)
	_detail_no_label.size = Vector2(160, 44)
	_detail_no_label.add_theme_font_size_override("font_size", 32)
	_detail_no_label.modulate = Color(1.0, 0.72, 0.25)
	add_child(_detail_no_label)

	_detail_cat_renderer = MgsFontRenderer.new()
	_detail_cat_renderer.position = Vector2(1425, 76)
	_detail_cat_renderer.base_scale = 0.74
	_detail_cat_renderer.max_line_width = 360.0
	_detail_cat_renderer.default_color = Color(0.95, 0.96, 0.98)
	add_child(_detail_cat_renderer)

	_detail_title_renderer = MgsFontRenderer.new()
	_detail_title_renderer.position = Vector2(812, 154)
	_detail_title_renderer.base_scale = 0.92
	_detail_title_renderer.max_line_width = 960.0
	_detail_title_renderer.default_color = Color(1.0, 0.76, 0.30)
	add_child(_detail_title_renderer)

	# 7. 右下角 Note 词条正文区 (x=780..1788, y=368..962，留出底部操作栏空间)
	_body_scroll = ScrollContainer.new()
	_body_scroll.position = Vector2(800, 368)
	_body_scroll.size = Vector2(972, 594)
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_body_scroll)

	_body_holder = Control.new()
	_body_holder.custom_minimum_size = Vector2(960, 580)
	_body_scroll.add_child(_body_holder)

	_body_renderer = MgsFontRenderer.new()
	_body_renderer.position = Vector2(8, 4)
	_body_renderer.base_scale = 0.74
	_body_renderer.line_height = 50.0
	_body_renderer.max_line_width = 930.0
	_body_holder.add_child(_body_renderer)

	_body_scroll_thumb = TextureRect.new()
	_body_scroll_thumb.position = Vector2(1782, 368)
	_body_scroll_thumb.size = Vector2(20, 71)
	_body_scroll_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_body_scroll_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_body_scroll_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body_scroll_thumb.visible = false
	add_child(_body_scroll_thumb)

	# 8. 右下角底部操作提示条（可点击“切换列表”与“返回”）
	_footer_tex = TextureRect.new()
	_footer_tex.position = Vector2(856, 984)
	_footer_tex.size = Vector2(1028, 60)
	_footer_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_footer_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_footer_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_footer_tex)

	var btn_cycle := _make_invisible_btn(Vector2(1375, 984), Vector2(215, 60))
	btn_cycle.tooltip_text = "切换列表 (全部/已取得/未读/新规)"
	btn_cycle.pressed.connect(func(): _switch_filter((_filter_mode + 1) % 4))
	add_child(btn_cycle)

	var btn_back := _make_invisible_btn(Vector2(1725, 984), Vector2(158, 60))
	btn_back.tooltip_text = "返回"
	btn_back.pressed.connect(close_panel)
	add_child(btn_back)


func _bind_assets() -> void:
	if _theme_loader == null:
		return
	_assets = _theme_loader.get_tips_assets()
	if _assets.is_empty():
		return
	if _assets.get("bg", null) != null:
		_bg_tex.texture = _assets["bg"] as Texture2D
	if _assets.get("grid_frame", null) != null:
		_grid_tex.texture = _assets["grid_frame"] as Texture2D
	if _assets.get("ring_tips", null) != null:
		_ring_tex.texture = _assets["ring_tips"] as Texture2D
	if _assets.get("icon_globe", null) != null:
		_globe_tex.texture = _assets["icon_globe"] as Texture2D
	if _assets.get("footer", null) != null:
		_footer_tex.texture = _assets["footer"] as Texture2D
	if _assets.get("scroll_thumb", null) != null:
		_scroll_thumb.texture = _assets["scroll_thumb"] as Texture2D
		if _body_scroll_thumb != null:
			_body_scroll_thumb.texture = _assets["scroll_thumb"] as Texture2D


func _load_tips_scx() -> void:
	if _vfs == null or not _vfs.is_mounted:
		return
	_detail_title_renderer.bind_vfs(_vfs)
	_detail_cat_renderer.bind_vfs(_vfs)
	_body_renderer.bind_vfs(_vfs)

	if not _vfs.has_entry("script.mpk", "_tips.scx"):
		return
	_tips_bytes = _vfs.read_entry("script.mpk", "_tips.scx")
	if _tips_bytes.size() < 16:
		return
	var str_tbl := int(_tips_bytes.decode_u32(4))
	var ret_tbl := int(_tips_bytes.decode_u32(8))
	@warning_ignore("integer_division")
	var count := maxi(0, (ret_tbl - str_tbl) / 4)
	_tips_offsets.resize(count)
	for i in range(count):
		_tips_offsets[i] = int(_tips_bytes.decode_u32(str_tbl + i * 4))

	# 从 str[11] 起每 5 条字符串对应一个 TIP (Category, Title, Reading, AltTitle, Body)
	@warning_ignore("integer_division")
	_total_tips = maxi(0, (count - 11) / 5)


func _switch_filter(mode: int) -> void:
	_filter_mode = clampi(mode, 0, 3)
	var tabs_act: Array = _assets.get("tabs_active", [])
	var tabs_inact: Array = _assets.get("tabs_inactive", [])
	for i in range(4):
		if i == _filter_mode and i < tabs_act.size():
			_tab_imgs[i].texture = tabs_act[i] as Texture2D
		elif i < tabs_inact.size():
			_tab_imgs[i].texture = tabs_inact[i] as Texture2D
	_rebuild_list()


func _is_tip_unlocked(tip_id: int) -> bool:
	return _vm != null and _vm.unlocked_tips.has(tip_id)


func _rebuild_list() -> void:
	for c in _list_box.get_children():
		_list_box.remove_child(c)
		c.queue_free()
	_row_highlights.clear()
	_row_new_badges.clear()

	var hl_tex := _assets.get("row_highlight") as Texture2D
	var new_tex := _assets.get("new_badge") as Texture2D
	var shown_ids: Array[int] = []

	for i in range(_total_tips):
		var unlocked := _is_tip_unlocked(i)
		var is_unread := unlocked and not _read_tips.has(i)
		var is_new := unlocked and not _seen_tips.has(i)
		match _filter_mode:
			FilterMode.UNLOCKED:
				if not unlocked:
					continue
			FilterMode.UNREAD:
				if not is_unread:
					continue
			FilterMode.NEW:
				if not is_new:
					continue
		shown_ids.append(i)

	if shown_ids.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "当前分类暂无词条"
		empty_lbl.custom_minimum_size = Vector2(580, 120)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 24)
		empty_lbl.modulate = Color(0.75, 0.78, 0.84, 0.75)
		_list_box.add_child(empty_lbl)
		_clear_detail()
		return

	for tip_id in shown_ids:
		var unlocked := _is_tip_unlocked(tip_id)
		var is_new := unlocked and not _read_tips.has(tip_id)

		var row := Control.new()
		row.custom_minimum_size = Vector2(586, 42)
		row.mouse_filter = Control.MOUSE_FILTER_PASS

		var hl := TextureRect.new()
		hl.set_anchors_preset(Control.PRESET_FULL_RECT)
		hl.texture = hl_tex
		hl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hl.stretch_mode = TextureRect.STRETCH_SCALE
		hl.visible = false
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hl)
		_row_highlights[tip_id] = hl

		# 序号列（右对齐 1..206）
		var num_lbl := Label.new()
		num_lbl.position = Vector2(18, 2)
		num_lbl.size = Vector2(116, 38)
		num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		num_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		num_lbl.text = "%d." % (tip_id + 1)
		num_lbl.add_theme_font_size_override("font_size", 26)
		num_lbl.modulate = Color(0.92, 0.94, 0.98) if unlocked else Color(0.70, 0.72, 0.76)
		row.add_child(num_lbl)

		if unlocked:
			var str_idx := 11 + tip_id * 5 + 1
			if str_idx < _tips_offsets.size() and not _tips_bytes.is_empty():
				var tfr := MgsFontRenderer.new()
				tfr.bind_vfs(_vfs)
				tfr.position = Vector2(142, 4)
				tfr.base_scale = 0.64
				tfr.max_line_width = 365.0
				tfr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(tfr)
				tfr.set_sc3_string(_tips_bytes, int(_tips_offsets[str_idx]), _vm, null, true)
		else:
			var q_lbl := Label.new()
			q_lbl.position = Vector2(142, 2)
			q_lbl.size = Vector2(360, 38)
			q_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			q_lbl.text = "???"
			q_lbl.add_theme_font_size_override("font_size", 26)
			q_lbl.modulate = Color(0.70, 0.72, 0.76)
			row.add_child(q_lbl)

		if is_new and new_tex != null:
			var badge := TextureRect.new()
			badge.position = Vector2(510, 5)
			badge.size = Vector2(56, 32)
			badge.texture = new_tex
			badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(badge)
			_row_new_badges[tip_id] = badge

		var hit := _make_invisible_btn(Vector2.ZERO, Vector2(586, 42))
		hit.mouse_filter = Control.MOUSE_FILTER_PASS
		var tid := tip_id
		hit.pressed.connect(func():
			if _drag_moved:
				_drag_moved = false
				return
			_select_tip(tid)
		)
		row.add_child(hit)

		_list_box.add_child(row)

	var first_sel := _selected_tip_id if shown_ids.has(_selected_tip_id) else shown_ids[0]
	_select_tip(first_sel)


func _select_tip(tip_id: int) -> void:
	_selected_tip_id = tip_id
	for k in _row_highlights.keys():
		var tr: TextureRect = _row_highlights[k]
		tr.visible = (int(k) == tip_id)

	if not _is_tip_unlocked(tip_id):
		_clear_detail()
		return

	_read_tips[tip_id] = true
	_seen_tips[tip_id] = true
	_save_tips_state()
	if _row_new_badges.has(tip_id):
		(_row_new_badges[tip_id] as TextureRect).visible = false

	var base := 11 + tip_id * 5
	if _tips_bytes.is_empty() or base + 4 >= _tips_offsets.size():
		_clear_detail()
		return

	_detail_no_label.text = "%03d" % (tip_id + 1)
	_detail_cat_renderer.set_sc3_string(_tips_bytes, int(_tips_offsets[base + 0]), _vm, null, true)
	_detail_title_renderer.set_sc3_string(_tips_bytes, int(_tips_offsets[base + 1]), _vm, null, true)
	_body_renderer.set_sc3_string(_tips_bytes, int(_tips_offsets[base + 4]), _vm, null, true)
	var content_h := maxf(580.0, _body_renderer.get_content_size().y + 40.0)
	_body_holder.custom_minimum_size = Vector2(960, content_h)
	_body_scroll.scroll_vertical = 0


func _clear_detail() -> void:
	_detail_no_label.text = ""
	if _detail_cat_renderer != null:
		_detail_cat_renderer.clear_text()
	if _detail_title_renderer != null:
		_detail_title_renderer.clear_text()
	if _body_renderer != null:
		_body_renderer.clear_text()


func _update_scroll_thumb() -> void:
	if _list_scroll != null and _scroll_thumb != null:
		var vbar := _list_scroll.get_v_scroll_bar()
		if vbar == null or vbar.max_value <= _list_scroll.size.y:
			_scroll_thumb.visible = false
		else:
			_scroll_thumb.visible = true
			var max_s := maxf(1.0, vbar.max_value - _list_scroll.size.y)
			var ratio := clampf(float(_list_scroll.scroll_vertical) / max_s, 0.0, 1.0)
			_scroll_thumb.position.y = 166.0 + ratio * (838.0 - 71.0)

	if _body_scroll != null and _body_scroll_thumb != null:
		var bvbar := _body_scroll.get_v_scroll_bar()
		if bvbar == null or bvbar.max_value <= _body_scroll.size.y:
			_body_scroll_thumb.visible = false
		else:
			_body_scroll_thumb.visible = true
			var bmax := maxf(1.0, bvbar.max_value - _body_scroll.size.y)
			var bratio := clampf(float(_body_scroll.scroll_vertical) / bmax, 0.0, 1.0)
			_body_scroll_thumb.position.y = 368.0 + bratio * (594.0 - 71.0)


func _load_tips_state() -> void:
	_read_tips.clear()
	_seen_tips.clear()
	if not FileAccess.file_exists(TIPS_STATE_PATH):
		return
	var txt := FileAccess.get_file_as_string(TIPS_STATE_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		var d := parsed as Dictionary
		for id in d.get("read", []):
			_read_tips[int(id)] = true
		for id in d.get("seen", []):
			_seen_tips[int(id)] = true


func _save_tips_state() -> void:
	var read_arr: Array[int] = []
	for k in _read_tips.keys():
		read_arr.append(int(k))
	var seen_arr: Array[int] = []
	for k in _seen_tips.keys():
		seen_arr.append(int(k))
	var f := FileAccess.open(TIPS_STATE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"read": read_arr, "seen": seen_arr}))
		f.close()


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
