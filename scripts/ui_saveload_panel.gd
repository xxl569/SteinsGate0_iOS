class_name UiSaveloadPanel
extends Control
## MAGES. PC 1:1 存档 / 读档界面（6 页 × 8 槽位 = 48 存档位，支持缩略图、锁定保护与页码胶囊切换）

signal save_slot_requested(slot_id: int)
signal load_slot_requested(slot_id: int)
signal closed()

const SLOTS_PER_PAGE := 8
const TOTAL_PAGES := 6
const TOTAL_SLOTS := SLOTS_PER_PAGE * TOTAL_PAGES

var _theme_loader: UiThemeLoader = null
var _assets: Dictionary = {}

var _bg_tex: TextureRect = null
var _frame_tex: TextureRect = null
var _ring_tex: TextureRect = null
var _clock_tex: TextureRect = null
var _footer_tex: TextureRect = null
var _page_digit_tex: TextureRect = null
var _page_slash_tex: TextureRect = null
var _status_hint: Label = null

var _slots_layer: Control = null
var _slot_cards: Array[Dictionary] = []
var _pill_glows: Array[TextureRect] = []
var _pill_actives: Array[TextureRect] = []

var _built: bool = false
var _is_save: bool = true
var _current_page: int = 0
var _selected_local_idx: int = 0
var _ring_angle: float = 0.0
var _thumb_cache: Dictionary = {} # slot_id -> Texture2D


func _ready() -> void:
	name = "UiSaveloadPanel"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(loader: UiThemeLoader) -> void:
	_theme_loader = loader
	_ensure_ui()
	_bind_assets()


func open_panel(is_save: bool, page: int = -1) -> void:
	_ensure_ui()
	if _assets.is_empty():
		_bind_assets()
	_is_save = is_save
	if page >= 0:
		_current_page = clampi(page, 0, TOTAL_PAGES - 1)
	_thumb_cache.clear()
	_update_mode_emblem()
	_refresh_page()
	visible = true


func close_panel() -> void:
	visible = false
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	_ring_angle = fmod(_ring_angle + delta * 0.16, TAU)
	if _ring_tex != null:
		_ring_tex.rotation = _ring_angle


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode == KEY_ESCAPE or ke.keycode == KEY_BACKSPACE:
			close_panel()
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_Q or ke.keycode == KEY_LEFT:
			_switch_page((_current_page + TOTAL_PAGES - 1) % TOTAL_PAGES)
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_E or ke.keycode == KEY_RIGHT:
			_switch_page((_current_page + 1) % TOTAL_PAGES)
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_INSERT:
			_toggle_lock_selected()
			get_viewport().set_input_as_handled()


func _ensure_ui() -> void:
	if _built:
		return
	_built = true

	# 1. 底层齿轮蓝图背景
	_bg_tex = TextureRect.new()
	_bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_bg_tex)

	# 2. 右侧旋转圆环与时钟徽章
	_ring_tex = TextureRect.new()
	_ring_tex.position = Vector2(1485, 24)
	_ring_tex.size = Vector2(610, 573)
	_ring_tex.pivot_offset = Vector2(305, 286)
	_ring_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ring_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ring_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring_tex)

	_clock_tex = TextureRect.new()
	_clock_tex.position = Vector2(1703, 224)
	_clock_tex.size = Vector2(174, 174)
	_clock_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_clock_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_clock_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clock_tex)

	# 3. 主暗灰半透明边框框架（SAVEMENU.DDS）
	_frame_tex = TextureRect.new()
	_frame_tex.position = Vector2(108, 0)
	_frame_tex.size = Vector2(1670, 1015)
	_frame_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_frame_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame_tex)

	# 4. 8 个存档槽位卡片（2 列 × 4 行）
	_slots_layer = Control.new()
	_slots_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slots_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slots_layer)

	for idx in range(SLOTS_PER_PAGE):
		@warning_ignore("integer_division")
		var col := idx / 4
		var row := idx % 4
		var sx := 184 + col * 762
		var sy := 120 + row * 190

		var card := Control.new()
		card.position = Vector2(sx, sy)
		card.size = Vector2(746, 176)
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		_slots_layer.add_child(card)

		var hl := TextureRect.new()
		hl.position = Vector2(-14, 0)
		hl.size = Vector2(774, 176)
		hl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hl.stretch_mode = TextureRect.STRETCH_SCALE
		hl.visible = (idx == 0)
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(hl)

		var thumb := TextureRect.new()
		thumb.position = Vector2(20, 12)
		thumb.size = Vector2(268, 152)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_SCALE
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(thumb)

		var lbl_no := Label.new()
		lbl_no.position = Vector2(304, 10)
		lbl_no.size = Vector2(220, 32)
		lbl_no.add_theme_font_size_override("font_size", 24)
		lbl_no.modulate = Color(0.95, 0.56, 0.16)
		card.add_child(lbl_no)

		var lock_btn := Button.new()
		lock_btn.position = Vector2(548, 4)
		lock_btn.size = Vector2(188, 46)
		lock_btn.flat = true
		lock_btn.visible = false
		lock_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var empty_sb := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus"]:
			lock_btn.add_theme_stylebox_override(st, empty_sb)
		card.add_child(lock_btn)

		var lock_tex := TextureRect.new()
		lock_tex.position = Vector2(12, 4)
		lock_tex.size = Vector2(168, 38)
		lock_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lock_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lock_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_btn.add_child(lock_tex)

		var lbl_title := Label.new()
		lbl_title.position = Vector2(304, 44)
		lbl_title.size = Vector2(424, 42)
		lbl_title.add_theme_font_size_override("font_size", 28)
		lbl_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lbl_title.modulate = Color(0.95, 0.96, 0.98)
		card.add_child(lbl_title)

		var lbl_ptime := Label.new()
		lbl_ptime.position = Vector2(304, 96)
		lbl_ptime.size = Vector2(424, 28)
		lbl_ptime.add_theme_font_size_override("font_size", 20)
		card.add_child(lbl_ptime)

		var lbl_date := Label.new()
		lbl_date.position = Vector2(304, 128)
		lbl_date.size = Vector2(424, 28)
		lbl_date.add_theme_font_size_override("font_size", 20)
		card.add_child(lbl_date)

		var hit := Button.new()
		hit.position = Vector2.ZERO
		hit.size = Vector2(546, 176)
		hit.flat = true
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "focus"]:
			hit.add_theme_stylebox_override(st, empty_sb)
		card.add_child(hit)

		# 卡片右侧下方点击区也触发主操作（避开右上角 lock_btn）
		var hit_r := Button.new()
		hit_r.position = Vector2(546, 52)
		hit_r.size = Vector2(200, 124)
		hit_r.flat = true
		hit_r.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "focus"]:
			hit_r.add_theme_stylebox_override(st, empty_sb)
		card.add_child(hit_r)

		var local_i := idx
		var click_fn := func(): _on_slot_clicked(local_i)
		hit.pressed.connect(click_fn)
		hit_r.pressed.connect(click_fn)
		lock_btn.pressed.connect(func():
			_selected_local_idx = local_i
			_toggle_lock_selected()
		)

		_slot_cards.append({
			"hl": hl,
			"thumb": thumb,
			"lbl_no": lbl_no,
			"lock_btn": lock_btn,
			"lock_tex": lock_tex,
			"lbl_title": lbl_title,
			"lbl_ptime": lbl_ptime,
			"lbl_date": lbl_date,
		})

	# 5. 底部 6 个分页胶囊按钮 + "1/6" 页码指示
	for p in range(TOTAL_PAGES):
		var px := 304 + p * 90
		var py := 954
		var glow := TextureRect.new()
		glow.position = Vector2(px - 8, py - 9)
		glow.size = Vector2(90, 36)
		glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glow.stretch_mode = TextureRect.STRETCH_SCALE
		glow.visible = (p == 0)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(glow)
		_pill_glows.append(glow)

		var act := TextureRect.new()
		act.position = Vector2(px, py)
		act.size = Vector2(74, 18)
		act.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		act.stretch_mode = TextureRect.STRETCH_SCALE
		act.visible = (p == 0)
		act.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(act)
		_pill_actives.append(act)

		var pbtn := _make_invisible_btn(Vector2(px - 6, py - 16), Vector2(86, 52))
		var page_i := p
		pbtn.pressed.connect(func(): _switch_page(page_i))
		add_child(pbtn)

	_page_digit_tex = TextureRect.new()
	_page_digit_tex.position = Vector2(860, 946)
	_page_digit_tex.size = Vector2(22, 32)
	_page_digit_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_page_digit_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_page_digit_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_page_digit_tex)

	_page_slash_tex = TextureRect.new()
	_page_slash_tex.position = Vector2(884, 946)
	_page_slash_tex.size = Vector2(38, 32)
	_page_slash_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_page_slash_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_page_slash_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_page_slash_tex)

	_status_hint = Label.new()
	_status_hint.position = Vector2(945, 946)
	_status_hint.size = Vector2(460, 32)
	_status_hint.add_theme_font_size_override("font_size", 20)
	_status_hint.modulate = Color(1.0, 0.72, 0.30)
	add_child(_status_hint)

	# 6. 右下角底部提示条（可触控点击 锁定资料 / 返回）
	_footer_tex = TextureRect.new()
	_footer_tex.position = Vector2(1152, 984)
	_footer_tex.size = Vector2(730, 60)
	_footer_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_footer_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_footer_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_footer_tex)

	var btn_lock_footer := _make_invisible_btn(Vector2(1470, 984), Vector2(205, 60))
	btn_lock_footer.tooltip_text = "锁定/解锁选中存档"
	btn_lock_footer.pressed.connect(_toggle_lock_selected)
	add_child(btn_lock_footer)

	var btn_back_footer := _make_invisible_btn(Vector2(1735, 984), Vector2(150, 60))
	btn_back_footer.tooltip_text = "返回"
	btn_back_footer.pressed.connect(close_panel)
	add_child(btn_back_footer)


func _bind_assets() -> void:
	if _theme_loader == null:
		return
	_assets = _theme_loader.get_saveload_assets()
	if _assets.is_empty():
		return
	if _assets.get("bg", null) != null:
		_bg_tex.texture = _assets["bg"] as Texture2D
	if _assets.get("frame", null) != null:
		_frame_tex.texture = _assets["frame"] as Texture2D
	if _assets.get("footer", null) != null:
		_footer_tex.texture = _assets["footer"] as Texture2D
	if _assets.get("slash_6", null) != null:
		_page_slash_tex.texture = _assets["slash_6"] as Texture2D

	var hl_tex := _assets.get("slot_highlight") as Texture2D
	for c in _slot_cards:
		(c["hl"] as TextureRect).texture = hl_tex
	var g_tex := _assets.get("pill_glow") as Texture2D
	var a_tex := _assets.get("pill_active") as Texture2D
	for p in range(TOTAL_PAGES):
		_pill_glows[p].texture = g_tex
		_pill_actives[p].texture = a_tex
	_update_mode_emblem()


func _update_mode_emblem() -> void:
	if _assets.is_empty():
		return
	if _is_save:
		_ring_tex.texture = _assets.get("ring_save") as Texture2D
		_clock_tex.texture = _assets.get("icon_clock_square") as Texture2D
	else:
		_ring_tex.texture = _assets.get("ring_load") as Texture2D
		_clock_tex.texture = _assets.get("icon_clock_round") as Texture2D


func _switch_page(page_idx: int) -> void:
	_current_page = clampi(page_idx, 0, TOTAL_PAGES - 1)
	_selected_local_idx = 0
	_status_hint.text = ""
	_refresh_page()


func _refresh_page() -> void:
	for p in range(TOTAL_PAGES):
		var act := (p == _current_page)
		_pill_glows[p].visible = act
		_pill_actives[p].visible = act
	var digits: Array = _assets.get("page_digits", [])
	if _current_page < digits.size() and digits[_current_page] != null:
		_page_digit_tex.texture = digits[_current_page] as Texture2D

	var nodata_tex := _assets.get("nodata") as Texture2D
	var locked_tex := _assets.get("locked_badge") as Texture2D
	var unlocked_tex := _assets.get("unlocked_badge") as Texture2D

	for i in range(SLOTS_PER_PAGE):
		var slot_id := _current_page * SLOTS_PER_PAGE + i + 1
		var meta := UiPanels.read_slot_meta(slot_id)
		var card: Dictionary = _slot_cards[i]
		(card["hl"] as TextureRect).visible = (i == _selected_local_idx)
		(card["lbl_no"] as Label).text = "No. %02d" % slot_id

		var thumb_tr := card["thumb"] as TextureRect
		var lock_btn := card["lock_btn"] as Button
		var lock_tr := card["lock_tex"] as TextureRect
		var lbl_title := card["lbl_title"] as Label
		var lbl_ptime := card["lbl_ptime"] as Label
		var lbl_date := card["lbl_date"] as Label

		if meta.is_empty():
			thumb_tr.texture = nodata_tex
			lock_btn.visible = false
			lbl_title.text = "No data"
			lbl_ptime.text = "PLAY TIME"
			lbl_date.text = "SAVE DATE"
			lbl_ptime.modulate = Color(0.55, 0.58, 0.64)
			lbl_date.modulate = Color(0.55, 0.58, 0.64)
		else:
			thumb_tr.texture = _get_slot_thumb(slot_id, nodata_tex)
			var is_locked := bool(meta.get("locked", false))
			lock_btn.visible = true
			lock_tr.texture = locked_tex if is_locked else unlocked_tex

			var summary := str(meta.get("summary", "")).strip_edges()
			var sname := str(meta.get("script_name", "")).get_basename()
			lbl_title.text = summary if summary != "" else sname
			var psec := int(meta.get("play_time_sec", 0))
			lbl_ptime.text = "PLAY TIME  %02d:%02d:%02d" % [psec / 3600, (psec % 3600) / 60, psec % 60]
			lbl_date.text = "SAVE DATE  %s" % str(meta.get("timestamp", ""))
			lbl_ptime.modulate = Color(0.88, 0.90, 0.94)
			lbl_date.modulate = Color(0.88, 0.90, 0.94)


func _get_slot_thumb(slot_id: int, fallback: Texture2D) -> Texture2D:
	if _thumb_cache.has(slot_id):
		return _thumb_cache[slot_id] as Texture2D
	var p := UiPanels.get_slot_thumb_path(slot_id)
	if FileAccess.file_exists(p):
		var img := Image.load_from_file(p)
		if img != null and not img.is_empty():
			var tex := ImageTexture.create_from_image(img)
			_thumb_cache[slot_id] = tex
			return tex
	return fallback


func _on_slot_clicked(local_idx: int) -> void:
	_selected_local_idx = local_idx
	for i in range(_slot_cards.size()):
		(_slot_cards[i]["hl"] as TextureRect).visible = (i == local_idx)

	var slot_id := _current_page * SLOTS_PER_PAGE + local_idx + 1
	var meta := UiPanels.read_slot_meta(slot_id)

	if _is_save:
		if not meta.is_empty() and bool(meta.get("locked", false)):
			_status_hint.text = "No. %02d 已锁定，请先解锁再覆盖" % slot_id
			return
		visible = false
		save_slot_requested.emit(slot_id)
	else:
		if meta.is_empty():
			_status_hint.text = "No. %02d 暂无存档数据" % slot_id
			return
		visible = false
		load_slot_requested.emit(slot_id)


func _toggle_lock_selected() -> void:
	var slot_id := _current_page * SLOTS_PER_PAGE + _selected_local_idx + 1
	var meta := UiPanels.read_slot_meta(slot_id)
	if meta.is_empty():
		return
	var new_locked := not bool(meta.get("locked", false))
	UiPanels.set_slot_locked(slot_id, new_locked)
	_status_hint.text = "No. %02d %s" % [slot_id, "已锁定" if new_locked else "已解锁"]
	_refresh_page()


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
