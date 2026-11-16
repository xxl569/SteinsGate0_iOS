class_name UiConfigPanel
extends Control
## MAGES. PC 1:1 系统设置界面（BASIC 基本设置 / TEXT 文字设置 / SOUND 声音设置 / VOICE 各个角色语音设定）

signal applied()
signal closed()

const VOICE_DISPLAY_ORDER := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0]

var _cfg: ConfigManager = null
var _theme_loader: UiThemeLoader = null
var _assets: Dictionary = {}

var _bg_tex: TextureRect = null
var _ring_tex: TextureRect = null
var _tools_tex: TextureRect = null
var _header_tex: TextureRect = null
var _footer_tex: TextureRect = null
var _tab_active_texs: Array[Texture2D] = []
var _tab_overlays: Array[TextureRect] = []
var _page_containers: Array[Control] = []

var _btn_footer_default: Button = null
var _btn_footer_voice_toggle: Button = null
var _btn_footer_back: Button = null

var _built: bool = false
var _active_tab: int = 0
var _selected_voice_order_idx: int = 0
var _ring_angle: float = 0.0

# 动态刷新回调
var _basic_refreshers: Array[Callable] = []
var _text_refreshers: Array[Callable] = []
var _sound_refreshers: Array[Callable] = []
var _voice_refreshers: Array[Callable] = []
var _voice_scroll: ScrollContainer = null
var _voice_up_arrow: Label = null
var _voice_more_arrow: Label = null
var _voice_row_highlights: Array[ColorRect] = []
var _voice_drag_active: bool = false
var _voice_drag_start_y: float = 0.0
var _voice_drag_start_scroll: int = 0
var _voice_drag_moved: bool = false


func _ready() -> void:
	name = "UiConfigPanel"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(cfg: ConfigManager, loader: UiThemeLoader) -> void:
	_cfg = cfg
	_theme_loader = loader
	_ensure_ui()
	_bind_assets()
	_refresh_all()


func open_panel(initial_tab: int = 0) -> void:
	_ensure_ui()
	if _assets.is_empty():
		_bind_assets()
	_switch_tab(clampi(initial_tab, 0, 3))
	_refresh_all()
	visible = true


func close_panel() -> void:
	_save_and_emit()
	visible = false
	closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	_ring_angle = fmod(_ring_angle + delta * 0.18, TAU)
	if _ring_tex != null:
		_ring_tex.rotation = _ring_angle
	if _active_tab == 3 and _voice_scroll != null:
		var vbar := _voice_scroll.get_v_scroll_bar()
		if _voice_more_arrow != null:
			var can_more := vbar != null and (_voice_scroll.scroll_vertical + _voice_scroll.size.y < vbar.max_value - 8.0)
			_voice_more_arrow.visible = can_more
		if _voice_up_arrow != null:
			_voice_up_arrow.visible = _voice_scroll.scroll_vertical > 8


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode == KEY_ESCAPE or ke.keycode == KEY_BACKSPACE:
			close_panel()
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_Q:
			_switch_tab((_active_tab + 3) % 4)
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_E:
			_switch_tab((_active_tab + 1) % 4)
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_DELETE:
			_on_reset_defaults()
			get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not visible or _active_tab != 3 or _voice_scroll == null:
		_voice_drag_active = false
		_voice_drag_moved = false
		return
	var rect := _voice_scroll.get_global_rect()
	# 仅在左侧头像/角色名与空白区域（避开右侧滑块区 x>=1340）拦截垂直触控拖拽滚动
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		pos = st.position
		if st.pressed:
			if rect.has_point(pos) and pos.x < rect.position.x + 632.0:
				_voice_drag_active = true
				_voice_drag_moved = false
				_voice_drag_start_y = pos.y
				_voice_drag_start_scroll = _voice_scroll.scroll_vertical
		else:
			if _voice_drag_active and _voice_drag_moved:
				get_viewport().set_input_as_handled()
			_voice_drag_active = false
	elif event is InputEventScreenDrag and _voice_drag_active:
		var sd := event as InputEventScreenDrag
		var dy := sd.position.y - _voice_drag_start_y
		if absf(dy) > 12.0:
			_voice_drag_moved = true
		if _voice_drag_moved:
			_voice_scroll.scroll_vertical = maxi(0, _voice_drag_start_scroll - int(dy))
			get_viewport().set_input_as_handled()


func _ensure_ui() -> void:
	if _built:
		return
	_built = true

	# 1. 背景图（含未选中 4 枚左侧标签 + 电路网格 + SETUP MENU 底框）
	_bg_tex = TextureRect.new()
	_bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_tex.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_bg_tex)

	# 2. 左下角旋转圆环与锤子扳手图标（与 PC 截图 1:1 一致）
	_ring_tex = TextureRect.new()
	_ring_tex.position = Vector2(-36, 730)
	_ring_tex.size = Vector2(440, 394)
	_ring_tex.pivot_offset = Vector2(220, 197)
	_ring_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ring_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ring_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ring_tex)

	_tools_tex = TextureRect.new()
	_tools_tex.position = Vector2(96, 845)
	_tools_tex.size = Vector2(176, 158)
	_tools_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tools_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tools_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tools_tex)

	# 3. 左侧 4 个主分类页签（精确对齐 CONFIG.DDS 背景位置 (172, 59 + i*180)）
	for i in range(4):
		var tab_y := 59 + i * 180
		var ov := TextureRect.new()
		ov.position = Vector2(172, tab_y)
		ov.size = Vector2(472, 146)
		ov.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ov.stretch_mode = TextureRect.STRETCH_SCALE
		ov.visible = (i == 0)
		ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(ov)
		_tab_overlays.append(ov)

		var hit := _make_invisible_btn(Vector2(172, tab_y), Vector2(472, 146))
		var tab_idx := i
		hit.pressed.connect(func(): _switch_tab(tab_idx))
		add_child(hit)

	# 4. 右上角分页标题（基本设置 / 文字设置 / 声音设置 / 各个角色语音设定）
	_header_tex = TextureRect.new()
	_header_tex.position = Vector2(724, 102)
	_header_tex.size = Vector2(620, 88)
	_header_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_header_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_header_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_header_tex)

	# 5. 四个分页内容容器
	for i in range(4):
		var page := Control.new()
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.visible = (i == 0)
		add_child(page)
		_page_containers.append(page)

	# 6. SETUP MENU 按钮点击热区（位于左下角 SETUP MENU 铭牌处）
	var btn_setup_menu := _make_invisible_btn(Vector2(284, 982), Vector2(262, 64))
	btn_setup_menu.tooltip_text = "保存并返回"
	btn_setup_menu.pressed.connect(close_panel)
	add_child(btn_setup_menu)

	# 7. 右下角底部操作栏（支持触控直接点击“回到默认设定”/“该角色语音ON/OFF”/“返回”）
	_footer_tex = TextureRect.new()
	_footer_tex.position = Vector2(912, 984)
	_footer_tex.size = Vector2(972, 60)
	_footer_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_footer_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_footer_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_footer_tex)

	_btn_footer_default = _make_invisible_btn(Vector2(1418, 984), Vector2(210, 60))
	_btn_footer_default.tooltip_text = "回到默认设定"
	_btn_footer_default.pressed.connect(_on_reset_defaults)
	add_child(_btn_footer_default)

	_btn_footer_voice_toggle = _make_invisible_btn(Vector2(1380, 984), Vector2(300, 60))
	_btn_footer_voice_toggle.tooltip_text = "切换当前角色语音 ON/OFF"
	_btn_footer_voice_toggle.visible = false
	_btn_footer_voice_toggle.pressed.connect(_toggle_selected_voice_mute)
	add_child(_btn_footer_voice_toggle)

	_btn_footer_back = _make_invisible_btn(Vector2(1720, 984), Vector2(165, 60))
	_btn_footer_back.tooltip_text = "返回"
	_btn_footer_back.pressed.connect(close_panel)
	add_child(_btn_footer_back)


func _bind_assets() -> void:
	if _theme_loader == null:
		return
	_assets = _theme_loader.get_config_assets()
	if _assets.is_empty():
		return

	if _assets.get("bg", null) != null:
		_bg_tex.texture = _assets["bg"] as Texture2D
	if _assets.get("ring_config", null) != null:
		_ring_tex.texture = _assets["ring_config"] as Texture2D
	if _assets.get("icon_tools", null) != null:
		_tools_tex.texture = _assets["icon_tools"] as Texture2D

	_tab_active_texs.clear()
	for t in _assets.get("tabs_active", []):
		_tab_active_texs.append(t as Texture2D)
	for i in range(mini(4, _tab_overlays.size())):
		if i < _tab_active_texs.size():
			_tab_overlays[i].texture = _tab_active_texs[i]

	_build_basic_page()
	_build_text_page()
	_build_sound_page()
	_build_voice_page()
	_switch_tab(_active_tab)


func _switch_tab(tab_idx: int) -> void:
	_active_tab = clampi(tab_idx, 0, 3)
	for i in range(_tab_overlays.size()):
		_tab_overlays[i].visible = (i == _active_tab)
	for i in range(_page_containers.size()):
		_page_containers[i].visible = (i == _active_tab)

	var headers: Array = _assets.get("headers", [])
	if _active_tab < headers.size() and headers[_active_tab] != null:
		_header_tex.texture = headers[_active_tab] as Texture2D

	if _active_tab == 3:
		if _assets.get("footer_voice", null) != null:
			_footer_tex.texture = _assets["footer_voice"] as Texture2D
			_footer_tex.position = Vector2(582, 984)
			_footer_tex.size = Vector2(1300, 60)
		_btn_footer_default.position = Vector2(1110, 984)
		_btn_footer_default.size = Vector2(215, 60)
		_btn_footer_voice_toggle.visible = true
		_btn_footer_voice_toggle.position = Vector2(1375, 984)
		_btn_footer_voice_toggle.size = Vector2(315, 60)
	else:
		if _assets.get("footer_config", null) != null:
			_footer_tex.texture = _assets["footer_config"] as Texture2D
			_footer_tex.position = Vector2(912, 984)
			_footer_tex.size = Vector2(972, 60)
		_btn_footer_default.position = Vector2(1418, 984)
		_btn_footer_default.size = Vector2(210, 60)
		_btn_footer_voice_toggle.visible = false


# ==================== BASIC 基本设置 ====================

func _clear_container(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _build_basic_page() -> void:
	var page := _page_containers[0]
	_clear_container(page)
	_basic_refreshers.clear()

	# 1. 触发操作时跳过模式解除 (是 / 否)
	var g1 := func() -> int: return 0 if (_cfg == null or _cfg.skip_stop_on_trigger) else 1
	var s1 := func(idx: int):
		if _cfg != null:
			_cfg.skip_stop_on_trigger = (idx == 0)
			_save_and_emit()
	_add_choice_row(page, 272, _assets.get("lbl_trigger_skip"), [
		{"tex": _assets.get("opt_trigger_yes"), "x": 1545, "w": 84},
		{"tex": _assets.get("opt_trigger_no"), "x": 1692, "w": 84},
	], g1, s1, _basic_refreshers)

	# 2. 登陆Tips消息显示 (是 / 否)
	var g2 := func() -> int: return 0 if (_cfg == null or _cfg.show_tips_popup) else 1
	var s2 := func(idx: int):
		if _cfg != null:
			_cfg.show_tips_popup = (idx == 0)
			_save_and_emit()
	_add_choice_row(page, 395, _assets.get("lbl_tips_popup"), [
		{"tex": _assets.get("opt_tips_yes"), "x": 1545, "w": 84},
		{"tex": _assets.get("opt_tips_no"), "x": 1692, "w": 84},
	], g2, s2, _basic_refreshers)

	# 3. 自动快速储存 (场景 / 触发器 / 双方 / 都不)
	var g3 := func() -> int: return _cfg.auto_quicksave_mode if _cfg != null else 2
	var s3 := func(idx: int):
		if _cfg != null:
			_cfg.auto_quicksave_mode = idx
			_save_and_emit()
	_add_choice_row(page, 518, _assets.get("lbl_auto_qsave"), [
		{"tex": _assets.get("opt_qsave_scene"), "x": 1198, "w": 110},
		{"tex": _assets.get("opt_qsave_trig"), "x": 1358, "w": 154},
		{"tex": _assets.get("opt_qsave_both"), "x": 1548, "w": 110},
		{"tex": _assets.get("opt_qsave_none"), "x": 1694, "w": 110},
	], g3, s3, _basic_refreshers)

	# 4. 全屏切换 (全屏 / 窗口)
	var g4 := func() -> int: return 0 if (_cfg != null and _cfg.fullscreen) else 1
	var s4 := func(idx: int):
		if _cfg != null:
			_cfg.fullscreen = (idx == 0)
			_save_and_emit()
	_add_choice_row(page, 641, _assets.get("lbl_fullscreen"), [
		{"tex": _assets.get("opt_full_on"), "x": 1300, "w": 112},
		{"tex": _assets.get("opt_full_off"), "x": 1635, "w": 112},
	], g4, s4, _basic_refreshers)

	# 5. 屏幕分辨率 (1024×576 / 1280×720 / 1920×1080)
	var g5 := func() -> int: return _cfg.resolution_index if _cfg != null else 1
	var s5 := func(idx: int):
		if _cfg != null:
			_cfg.resolution_index = idx
			_save_and_emit()
	_add_choice_row(page, 764, _assets.get("lbl_resolution"), [
		{"tex": _assets.get("opt_res_0"), "x": 1245, "w": 184},
		{"tex": _assets.get("opt_res_1"), "x": 1445, "w": 196},
		{"tex": _assets.get("opt_res_2"), "x": 1652, "w": 196},
	], g5, s5, _basic_refreshers)


# ==================== TEXT 文字设置 ====================

func _build_text_page() -> void:
	var page := _page_containers[1]
	_clear_container(page)
	_text_refreshers.clear()

	# 1. 信息速度 (15..120 cps)
	var tg1 := func() -> float:
		return clampf(((_cfg.text_speed if _cfg != null else 48.0) - 15.0) / 105.0, 0.0, 1.0)
	var ts1 := func(norm: float):
		if _cfg != null:
			_cfg.text_speed = 15.0 + norm * 105.0
			_save_and_emit()
	_add_slider_row(page, 276, _assets.get("lbl_msg_speed"), tg1, ts1, _text_refreshers)

	# 2. 自动模式等待时间 (0.3..4.0 sec；越靠右等待越长)
	var tg2 := func() -> float:
		return clampf(((_cfg.auto_delay if _cfg != null else 1.6) - 0.3) / 3.7, 0.0, 1.0)
	var ts2 := func(norm: float):
		if _cfg != null:
			_cfg.auto_delay = 0.3 + norm * 3.7
			_save_and_emit()
	_add_slider_row(page, 412, _assets.get("lbl_auto_wait"), tg2, ts2, _text_refreshers)

	# 3. 跳过模式 (仅已读 / 全部)
	var tg3 := func() -> int: return 1 if (_cfg != null and _cfg.skip_unread) else 0
	var ts3 := func(idx: int):
		if _cfg != null:
			_cfg.skip_unread = (idx == 1)
			_save_and_emit()
	_add_choice_row(page, 548, _assets.get("lbl_skip_mode"), [
		{"tex": _assets.get("opt_skip_read"), "x": 1472, "w": 156},
		{"tex": _assets.get("opt_skip_all"), "x": 1715, "w": 106},
	], tg3, ts3, _text_refreshers)


# ==================== SOUND 声音设置 ====================

func _build_sound_page() -> void:
	var page := _page_containers[2]
	_clear_container(page)
	_sound_refreshers.clear()

	var sg1 := func() -> float: return _cfg.voice_volume if _cfg != null else 1.0
	var ss1 := func(norm: float):
		if _cfg != null:
			_cfg.voice_volume = norm
			_save_and_emit()
	_add_slider_row(page, 260, _assets.get("lbl_vol_voice"), sg1, ss1, _sound_refreshers)

	var sg2 := func() -> float: return _cfg.bgm_volume if _cfg != null else 0.8
	var ss2 := func(norm: float):
		if _cfg != null:
			_cfg.bgm_volume = norm
			_save_and_emit()
	_add_slider_row(page, 372, _assets.get("lbl_vol_bgm"), sg2, ss2, _sound_refreshers)

	var sg3 := func() -> float: return _cfg.se_volume if _cfg != null else 0.85
	var ss3 := func(norm: float):
		if _cfg != null:
			_cfg.se_volume = norm
			_save_and_emit()
	_add_slider_row(page, 484, _assets.get("lbl_vol_se"), sg3, ss3, _sound_refreshers)

	var sg4 := func() -> float: return _cfg.movie_volume if _cfg != null else 0.85
	var ss4 := func(norm: float):
		if _cfg != null:
			_cfg.movie_volume = norm
			_save_and_emit()
	_add_slider_row(page, 596, _assets.get("lbl_vol_movie"), sg4, ss4, _sound_refreshers)

	var sg5 := func() -> int: return 0 if (_cfg == null or _cfg.audio_sync) else 1
	var ss5 := func(idx: int):
		if _cfg != null:
			_cfg.audio_sync = (idx == 0)
			_save_and_emit()
	_add_choice_row(page, 708, _assets.get("lbl_audio_sync"), [
		{"tex": _assets.get("opt_sync_yes"), "x": 1545, "w": 84},
		{"tex": _assets.get("opt_sync_no"), "x": 1692, "w": 84},
	], sg5, ss5, _sound_refreshers)

	var sg6 := func() -> int: return 0 if (_cfg != null and _cfg.skip_voice) else 1
	var ss6 := func(idx: int):
		if _cfg != null:
			_cfg.skip_voice = (idx == 0)
			_cfg.voice_stop_on_next = _cfg.skip_voice
			_save_and_emit()
	_add_choice_row(page, 820, _assets.get("lbl_skip_voice"), [
		{"tex": _assets.get("opt_svoice_yes"), "x": 1545, "w": 84},
		{"tex": _assets.get("opt_svoice_no"), "x": 1692, "w": 84},
	], sg6, ss6, _sound_refreshers)


# ==================== VOICE 各个角色语音设定 ====================

func _build_voice_page() -> void:
	var page := _page_containers[3]
	_clear_container(page)
	_voice_refreshers.clear()
	_voice_row_highlights.clear()

	_voice_scroll = ScrollContainer.new()
	_voice_scroll.position = Vector2(704, 240)
	_voice_scroll.size = Vector2(1152, 666)
	_voice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_voice_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	page.add_child(_voice_scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	_voice_scroll.add_child(vbox)

	var voice_slots: Array = _assets.get("voice_slots", [])
	var voice_off_tex: Texture2D = _assets.get("voice_off_bar") as Texture2D

	for order_idx in range(VOICE_DISPLAY_ORDER.size()):
		var char_slot: int = VOICE_DISPLAY_ORDER[order_idx]
		var row := Control.new()
		row.custom_minimum_size = Vector2(1130, 98)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		vbox.add_child(row)

		# 当前选中行微弱暖白底条（清晰指示底部“该角色语音ON/OFF”作用对象）
		var row_hl := ColorRect.new()
		row_hl.position = Vector2(0, 6)
		row_hl.size = Vector2(1124, 86)
		row_hl.color = Color(0.95, 0.72, 0.36, 0.14)
		row_hl.visible = (order_idx == _selected_voice_order_idx)
		row_hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(row_hl)
		_voice_row_highlights.append(row_hl)

		# 左侧头像 + 角色名 + 点线
		var name_btn := Button.new()
		name_btn.position = Vector2(8, 10)
		name_btn.size = Vector2(620, 76)
		name_btn.flat = true
		name_btn.mouse_filter = Control.MOUSE_FILTER_PASS
		name_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var empty_sb := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus"]:
			name_btn.add_theme_stylebox_override(st, empty_sb)
		row.add_child(name_btn)

		var char_tex := TextureRect.new()
		char_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		if char_slot < voice_slots.size():
			char_tex.texture = voice_slots[char_slot] as Texture2D
		char_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		char_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		char_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_btn.add_child(char_tex)

		# 右侧火焰音量滑块
		var vg := func() -> float: return _cfg.get_char_voice_volume(char_slot) if _cfg != null else 1.0
		var vs := func(norm: float):
			_selected_voice_order_idx = order_idx
			_update_voice_row_selection()
			if _cfg != null:
				_cfg.set_char_voice_muted(char_slot, false)
				_cfg.set_char_voice_volume(char_slot, norm)
				_save_and_emit()
		var slider_ctrl := _create_flame_slider(Vector2(638, 22), Vector2(478, 52), vg, vs)
		row.add_child(slider_ctrl["node"] as Control)

		# Voice OFF 遮罩条（点击头像/名字或 Voice OFF 均可切换 ON/OFF）
		var off_btn := Button.new()
		off_btn.position = Vector2(638, 27)
		off_btn.size = Vector2(478, 42)
		off_btn.flat = true
		off_btn.visible = false
		for st in ["normal", "hover", "pressed", "focus"]:
			off_btn.add_theme_stylebox_override(st, empty_sb)
		row.add_child(off_btn)

		var off_tex := TextureRect.new()
		off_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		off_tex.texture = voice_off_tex
		off_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		off_tex.stretch_mode = TextureRect.STRETCH_SCALE
		off_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		off_btn.add_child(off_tex)

		var toggle_fn := func():
			if _voice_drag_moved:
				_voice_drag_moved = false
				return
			_selected_voice_order_idx = order_idx
			_update_voice_row_selection()
			if _cfg != null:
				_cfg.set_char_voice_muted(char_slot, not _cfg.is_char_voice_muted(char_slot))
				_save_and_emit()
			_refresh_all()
		name_btn.pressed.connect(toggle_fn)
		off_btn.pressed.connect(func():
			_selected_voice_order_idx = order_idx
			_update_voice_row_selection()
			if _cfg != null:
				_cfg.set_char_voice_muted(char_slot, false)
				_save_and_emit()
			_refresh_all()
		)

		var refresh_slider: Callable = slider_ctrl["refresh"]
		var refresh_row := func():
			var muted := _cfg != null and _cfg.is_char_voice_muted(char_slot)
			off_btn.visible = muted
			(slider_ctrl["node"] as Control).visible = not muted
			row_hl.visible = (order_idx == _selected_voice_order_idx)
			refresh_slider.call()
		_voice_refreshers.append(refresh_row)

	# 列表上/下方白色三角滚动提示（对齐 PC 截图）
	_voice_up_arrow = Label.new()
	_voice_up_arrow.text = "▲"
	_voice_up_arrow.position = Vector2(1240, 200)
	_voice_up_arrow.size = Vector2(60, 40)
	_voice_up_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_voice_up_arrow.add_theme_font_size_override("font_size", 28)
	_voice_up_arrow.modulate = Color(0.95, 0.96, 0.98, 0.92)
	_voice_up_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_voice_up_arrow.visible = false
	page.add_child(_voice_up_arrow)

	_voice_more_arrow = Label.new()
	_voice_more_arrow.text = "▼"
	_voice_more_arrow.position = Vector2(1240, 912)
	_voice_more_arrow.size = Vector2(60, 44)
	_voice_more_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_voice_more_arrow.add_theme_font_size_override("font_size", 32)
	_voice_more_arrow.modulate = Color(0.95, 0.96, 0.98, 0.92)
	_voice_more_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_voice_more_arrow)


func _update_voice_row_selection() -> void:
	for i in range(_voice_row_highlights.size()):
		_voice_row_highlights[i].visible = (i == _selected_voice_order_idx)


# ==================== 通用 PC 控件构建器 ====================

func _add_choice_row(
	page: Control,
	row_y: float,
	lbl_tex: Variant,
	choices: Array,
	getter: Callable,
	setter: Callable,
	refresh_list: Array[Callable]
) -> void:
	var row := Control.new()
	row.position = Vector2(0, row_y)
	row.size = Vector2(1920, 60)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(row)

	# 左侧标签 + 点线
	var lbl_tr := TextureRect.new()
	lbl_tr.position = Vector2(726, 6)
	lbl_tr.size = Vector2(lbl_tex.get_width() if lbl_tex is Texture2D else 460, 48)
	if lbl_tex is Texture2D:
		lbl_tr.texture = lbl_tex as Texture2D
	lbl_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lbl_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	lbl_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl_tr)

	var ovals: Array[TextureRect] = []
	var oval_tex := _assets.get("select_oval_red") as Texture2D

	for i in range(choices.size()):
		var ch: Dictionary = choices[i]
		var cx := float(ch["x"])
		var cw := float(ch["w"])

		# 橙红手绘椭圆选中圈（垫在文字之下）
		var oval := TextureRect.new()
		oval.position = Vector2(cx - 24.0, -24.0)
		oval.size = Vector2(cw + 48.0, 108.0)
		oval.texture = oval_tex
		oval.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		oval.stretch_mode = TextureRect.STRETCH_SCALE
		oval.mouse_filter = Control.MOUSE_FILTER_IGNORE
		oval.visible = false
		row.add_child(oval)
		ovals.append(oval)

		var btn := _make_invisible_btn(Vector2(cx - 10.0, -4.0), Vector2(cw + 20.0, 68.0))
		row.add_child(btn)

		var opt_tr := TextureRect.new()
		opt_tr.position = Vector2(10.0, 10.0)
		opt_tr.size = Vector2(cw, 48.0)
		if ch.get("tex", null) is Texture2D:
			opt_tr.texture = ch["tex"] as Texture2D
		opt_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		opt_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		opt_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(opt_tr)

		var opt_idx := i
		btn.pressed.connect(func():
			setter.call(opt_idx)
			for k in range(ovals.size()):
				ovals[k].visible = (k == opt_idx)
		)

	refresh_list.append(func():
		var active_idx := int(getter.call())
		for k in range(ovals.size()):
			ovals[k].visible = (k == active_idx)
	)


func _add_slider_row(
	page: Control,
	row_y: float,
	lbl_tex: Variant,
	getter: Callable,
	setter: Callable,
	refresh_list: Array[Callable]
) -> void:
	var row := Control.new()
	row.position = Vector2(0, row_y)
	row.size = Vector2(1920, 64)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(row)

	var lbl_tr := TextureRect.new()
	lbl_tr.position = Vector2(726, 8)
	lbl_tr.size = Vector2(lbl_tex.get_width() if lbl_tex is Texture2D else 560, 46)
	if lbl_tex is Texture2D:
		lbl_tr.texture = lbl_tex as Texture2D
	lbl_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lbl_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	lbl_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl_tr)

	var slider_ctrl := _create_flame_slider(Vector2(1346, 4), Vector2(490, 52), getter, setter)
	row.add_child(slider_ctrl["node"] as Control)
	refresh_list.append(slider_ctrl["refresh"])


func _create_flame_slider(pos: Vector2, sz: Vector2, getter: Callable, setter: Callable) -> Dictionary:
	var root := Control.new()
	root.position = pos
	root.size = sz
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# 暗底轨（未填充区保持纯黑半透明）
	var bg_panel := Panel.new()
	bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0.02, 0.02, 0.03, 0.88)
	bg_sb.border_color = Color(0.92, 0.94, 0.96, 0.95)
	bg_sb.set_border_width_all(2)
	bg_panel.add_theme_stylebox_override("panel", bg_sb)
	root.add_child(bg_panel)

	# 亮橙色火焰进度条（不被黑底压暗，100% 还原 PC 截图亮度）
	var fill_clip := Control.new()
	fill_clip.position = Vector2(3, 3)
	fill_clip.size = Vector2(sz.x - 6, sz.y - 6)
	fill_clip.clip_contents = true
	fill_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill_clip)

	var fill_tex := TextureRect.new()
	fill_tex.position = Vector2.ZERO
	fill_tex.size = Vector2(sz.x - 6, sz.y - 6)
	fill_tex.texture = _assets.get("slider_fill") as Texture2D
	fill_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fill_tex.stretch_mode = TextureRect.STRETCH_SCALE
	fill_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill_clip.add_child(fill_tex)

	# 清晰白色边框 + MIN / MAX 浮层（叠加在火焰条之上）
	var border_overlay := Panel.new()
	border_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	border_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border_sb := StyleBoxFlat.new()
	border_sb.bg_color = Color(0, 0, 0, 0)
	border_sb.border_color = Color(0.95, 0.96, 0.98, 0.95)
	border_sb.set_border_width_all(2)
	border_overlay.add_theme_stylebox_override("panel", border_sb)
	root.add_child(border_overlay)

	var lbl_min := Label.new()
	lbl_min.text = "MIN"
	lbl_min.position = Vector2(10, 0)
	lbl_min.size = Vector2(80, sz.y)
	lbl_min.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_min.add_theme_font_size_override("font_size", 24)
	lbl_min.add_theme_color_override("font_color", Color.WHITE)
	lbl_min.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	lbl_min.add_theme_constant_override("shadow_offset_x", 1)
	lbl_min.add_theme_constant_override("shadow_offset_y", 1)
	lbl_min.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lbl_min)

	var lbl_max := Label.new()
	lbl_max.text = "MAX"
	lbl_max.position = Vector2(sz.x - 94, 0)
	lbl_max.size = Vector2(82, sz.y)
	lbl_max.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_max.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_max.add_theme_font_size_override("font_size", 24)
	lbl_max.add_theme_color_override("font_color", Color.WHITE)
	lbl_max.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	lbl_max.add_theme_constant_override("shadow_offset_x", 1)
	lbl_max.add_theme_constant_override("shadow_offset_y", 1)
	lbl_max.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lbl_max)

	var refresh_fn := func():
		var norm := clampf(float(getter.call()), 0.0, 1.0)
		fill_clip.size.x = (sz.x - 6.0) * norm

	var dragging := [false]
	root.gui_input.connect(func(ev: InputEvent):
		var update := false
		var local_x := 0.0
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				dragging[0] = mb.pressed
				if mb.pressed:
					update = true
					local_x = mb.position.x
		elif ev is InputEventMouseMotion and dragging[0]:
			update = true
			local_x = (ev as InputEventMouseMotion).position.x
		elif ev is InputEventScreenTouch:
			var st := ev as InputEventScreenTouch
			dragging[0] = st.pressed
			if st.pressed:
				update = true
				local_x = st.position.x
		elif ev is InputEventScreenDrag and dragging[0]:
			update = true
			local_x = (ev as InputEventScreenDrag).position.x

		if update:
			var norm := clampf(local_x / maxf(1.0, sz.x), 0.0, 1.0)
			fill_clip.size.x = (sz.x - 6.0) * norm
			setter.call(norm)
			root.accept_event()
	)

	return {"node": root, "refresh": refresh_fn}


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


func _toggle_selected_voice_mute() -> void:
	if _cfg == null:
		return
	var char_slot: int = int(VOICE_DISPLAY_ORDER[clampi(_selected_voice_order_idx, 0, VOICE_DISPLAY_ORDER.size() - 1)])
	_cfg.set_char_voice_muted(char_slot, not _cfg.is_char_voice_muted(char_slot))
	_save_and_emit()
	_refresh_all()


func _on_reset_defaults() -> void:
	if _cfg != null:
		_cfg.reset_to_defaults()
		_save_and_emit()
	_refresh_all()


func _refresh_all() -> void:
	for fn in _basic_refreshers:
		fn.call()
	for fn in _text_refreshers:
		fn.call()
	for fn in _sound_refreshers:
		fn.call()
	for fn in _voice_refreshers:
		fn.call()


func _save_and_emit() -> void:
	if _cfg != null:
		_cfg.save_config()
	applied.emit()
