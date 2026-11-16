class_name MobileGestureHelper
extends Control
## iOS 移动端触控交互、刘海屏安全区适配与仿 PC 布局 HUD（左上角日期手机入口 + 左下/右下快捷栏）

signal advance_requested()
signal toggle_skip_requested()
signal toggle_auto_requested()
signal open_backlog_requested()
signal open_phone_requested()
signal open_tips_requested()
signal open_save_requested()
signal open_load_requested()
signal open_config_requested()
signal toggle_hide_ui_requested()
signal open_title_requested()
signal quick_save_requested()
signal quick_load_requested()

var is_auto_active: bool = false
var is_skip_active: bool = false
var is_dialogue_mode: bool = false
var is_modal_blocked: bool = false
var is_movie_playing_block: bool = false
var is_ui_hidden: bool = false
var is_phone_open: bool = false

var _hud_container: HBoxContainer = null
var _bottom_left_hud: HBoxContainer = null
var _bottom_right_hud: HBoxContainer = null
var _date_phone_btn: Button = null
var _btn_skip: Button = null
var _btn_auto: Button = null
var _btn_phone: Button = null
var _btn_hide: Button = null

var _theme_loader: UiThemeLoader = null
var _meswin_assets: Dictionary = {}

var _swipe_start: Vector2 = Vector2.ZERO
var _tracking_swipe: bool = false
var _last_hud_btn_msec: int = -1000
var _last_date_text: String = "11/23 (TUE)"


func _ready() -> void:
	name = "MobileGestureHelper"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_hud()
	_apply_safe_area()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_apply_safe_area):
		vp.size_changed.connect(_apply_safe_area)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED or what == NOTIFICATION_RESIZED:
		_apply_safe_area()


func _apply_safe_area() -> void:
	## 依据刘海屏 / Home 指示条安全区微调 HUD 四周边距（桌面及无刘海环境保持原 PC 偏移）
	var left_inset: float = 0.0
	var top_inset: float = 0.0
	var right_inset: float = 0.0
	var bottom_inset: float = 0.0
	var win_size: Vector2i = DisplayServer.window_get_size()
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if win_size.x > 0 and win_size.y > 0 and safe.size.x > 0 and safe.size.y > 0:
		var sx: float = 1920.0 / float(win_size.x)
		var sy: float = 1080.0 / float(win_size.y)
		left_inset = clampf(float(safe.position.x) * sx, 0.0, 120.0)
		top_inset = clampf(float(safe.position.y) * sy, 0.0, 80.0)
		right_inset = clampf(float(win_size.x - safe.end.x) * sx, 0.0, 120.0)
		bottom_inset = clampf(float(win_size.y - safe.end.y) * sy, 0.0, 36.0)

	if _date_phone_btn != null:
		var l: float = 24.0 + left_inset
		var t: float = 18.0 + top_inset
		_date_phone_btn.offset_left = l
		_date_phone_btn.offset_top = t
		_date_phone_btn.offset_right = l + 234.0
		_date_phone_btn.offset_bottom = t + 68.0
	if _bottom_left_hud != null:
		var bt: float = 1018.0 - minf(bottom_inset, 18.0)
		_bottom_left_hud.offset_left = 28.0 + left_inset
		_bottom_left_hud.offset_top = bt
		_bottom_left_hud.offset_right = 660.0 + left_inset
		_bottom_left_hud.offset_bottom = bt + 48.0
	if _bottom_right_hud != null:
		var bt2: float = 1018.0 - minf(bottom_inset, 18.0)
		_bottom_right_hud.offset_left = 1220.0 - right_inset
		_bottom_right_hud.offset_top = bt2
		_bottom_right_hud.offset_right = 1892.0 - right_inset
		_bottom_right_hud.offset_bottom = bt2 + 48.0


func bind_theme(loader: UiThemeLoader) -> void:
	## 绑定主题加载器并应用 PC 同款日期胶囊与按钮贴图
	_theme_loader = loader
	if _theme_loader == null:
		return
	_meswin_assets = _theme_loader.get_meswin_assets()
	var date_tex: Texture2D = _meswin_assets.get("date_pill_bg", null)
	if date_tex != null and _date_phone_btn != null:
		var sb := StyleBoxTexture.new()
		sb.texture = date_tex
		sb.content_margin_left = 18
		sb.content_margin_right = 22
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		_date_phone_btn.add_theme_stylebox_override("normal", sb)
		var sb_hover := sb.duplicate() as StyleBoxTexture
		sb_hover.modulate_color = Color(1.12, 1.12, 1.12, 1.0)
		_date_phone_btn.add_theme_stylebox_override("hover", sb_hover)
		var sb_pressed := sb.duplicate() as StyleBoxTexture
		sb_pressed.modulate_color = Color(0.85, 0.9, 1.0, 1.0)
		_date_phone_btn.add_theme_stylebox_override("pressed", sb_pressed)
	_refresh_mode_btn_styles()


func update_date_display(vm: Sc3Vm) -> void:
	## 同步 VM 中的日期变量 ScrWork[11/12/13] 到左上角日期手机按钮
	if vm == null or _date_phone_btn == null:
		return
	var year: int = vm.get_scr_work(11)
	var month: int = vm.get_scr_work(12)
	var day: int = vm.get_scr_work(13)
	if month >= 1 and month <= 12 and day >= 1 and day <= 31:
		var weekday: String = _calc_weekday_abbr(year if year > 1900 else 2010, month, day)
		_last_date_text = "%02d/%02d (%s)" % [month, day, weekday]
	else:
		# 序章尚在世界线计算之前，显示 RINE 手机标识提示可随时点开
		_last_date_text = "RINE  手机"
	_date_phone_btn.text = _last_date_text


func _calc_weekday_abbr(y: int, m: int, d: int) -> String:
	## Sakamoto 算法计算英文星期缩写，匹配 PC 版左上角日期显示
	var t := [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
	var yy: int = y
	if m < 3:
		yy -= 1
	var w: int = (yy + yy / 4 - yy / 100 + yy / 400 + t[m - 1] + d) % 7
	var names := ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
	return names[clampi(w, 0, 6)]


func _build_hud() -> void:
	# 1. 左上角 PC 同款日期胶囊按钮（点击即弹出右侧手机 / RINE 界面）
	_date_phone_btn = Button.new()
	_date_phone_btn.name = "DatePhoneButton"
	_date_phone_btn.text = _last_date_text
	_date_phone_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_date_phone_btn.offset_left = 24
	_date_phone_btn.offset_top = 18
	_date_phone_btn.offset_right = 258
	_date_phone_btn.offset_bottom = 86
	_date_phone_btn.focus_mode = Control.FOCUS_NONE
	_date_phone_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_date_phone_btn.add_theme_font_size_override("font_size", 22)
	_date_phone_btn.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
	_date_phone_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.55, 1.0))
	_date_phone_btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.78, 0.3, 1.0))
	_apply_date_fallback_style(_date_phone_btn)
	_date_phone_btn.pressed.connect(func():
		_mark_hud_pressed()
		open_phone_requested.emit()
	)
	_date_phone_btn.visible = false
	add_child(_date_phone_btn)
	_btn_phone = _date_phone_btn

	# 2. 左下角快捷功能栏（AUTO / SKIP / LOG / TIPS），与正下方说话人名错开
	_bottom_left_hud = HBoxContainer.new()
	_bottom_left_hud.name = "BottomLeftHudBar"
	_bottom_left_hud.alignment = BoxContainer.ALIGNMENT_BEGIN
	_bottom_left_hud.grow_horizontal = Control.GROW_DIRECTION_END
	_bottom_left_hud.add_theme_constant_override("separation", 10)
	_bottom_left_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_bottom_left_hud.offset_left = 28
	_bottom_left_hud.offset_top = 1018
	_bottom_left_hud.offset_right = 660
	_bottom_left_hud.offset_bottom = 1066
	_bottom_left_hud.mouse_filter = Control.MOUSE_FILTER_PASS
	_bottom_left_hud.visible = false
	add_child(_bottom_left_hud)
	_hud_container = _bottom_left_hud

	_btn_auto = _make_hud_btn("自动 AUTO", func(): toggle_auto_requested.emit())
	_btn_skip = _make_hud_btn("快进 SKIP", func(): toggle_skip_requested.emit())
	var btn_log := _make_hud_btn("回顾 LOG", func(): open_backlog_requested.emit())
	var btn_tips := _make_hud_btn("TIPS", func(): open_tips_requested.emit())
	for b in [_btn_auto, _btn_skip, btn_log, btn_tips]:
		_bottom_left_hud.add_child(b)

	# 3. 右下角系统功能栏（SAVE / LOAD / CONFIG / HIDE / TITLE），与正下方说话人名错开
	_bottom_right_hud = HBoxContainer.new()
	_bottom_right_hud.name = "BottomRightHudBar"
	_bottom_right_hud.alignment = BoxContainer.ALIGNMENT_END
	_bottom_right_hud.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_bottom_right_hud.add_theme_constant_override("separation", 10)
	_bottom_right_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_bottom_right_hud.offset_left = 1220
	_bottom_right_hud.offset_top = 1018
	_bottom_right_hud.offset_right = 1892
	_bottom_right_hud.offset_bottom = 1066
	_bottom_right_hud.mouse_filter = Control.MOUSE_FILTER_PASS
	_bottom_right_hud.visible = false
	add_child(_bottom_right_hud)

	var btn_save := _make_hud_btn("存档 SAVE", func(): open_save_requested.emit())
	var btn_load := _make_hud_btn("读档 LOAD", func(): open_load_requested.emit())
	var btn_cfg := _make_hud_btn("设置", func(): open_config_requested.emit())
	_btn_hide = _make_hud_btn("隐藏", func(): toggle_hide_ui_requested.emit())
	var btn_title := _make_hud_btn("标题", func(): open_title_requested.emit())
	for b in [btn_save, btn_load, btn_cfg, _btn_hide, btn_title]:
		_bottom_right_hud.add_child(b)


func _apply_date_fallback_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.11, 0.19, 0.86)
	normal.border_color = Color(0.86, 0.52, 0.14, 0.92)
	normal.border_width_left = 3
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 2
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.10, 0.19, 0.30, 0.94)
	hover.border_color = Color(1.0, 0.72, 0.28, 1.0)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.18, 0.30, 0.45, 0.96)
	btn.add_theme_stylebox_override("pressed", pressed)


func _make_hud_btn(title: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = title
	btn.custom_minimum_size = Vector2(96, 46)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_color_override("font_color", Color(0.86, 0.91, 0.96, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.78, 0.32, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.56, 0.12, 1.0))
	_apply_hud_btn_style(btn, false)
	btn.pressed.connect(func():
		_mark_hud_pressed()
		cb.call()
	)
	return btn


func _apply_hud_btn_style(btn: Button, active: bool) -> void:
	var normal := StyleBoxFlat.new()
	if active:
		normal.bg_color = Color(0.82, 0.42, 0.08, 0.92)
		normal.border_color = Color(1.0, 0.78, 0.36, 0.98)
	else:
		normal.bg_color = Color(0.05, 0.08, 0.14, 0.78)
		normal.border_color = Color(0.28, 0.42, 0.58, 0.65)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.14, 0.24, 0.38, 0.9) if not active else Color(0.92, 0.5, 0.12, 0.98)
	btn.add_theme_stylebox_override("hover", hover)


func _mark_hud_pressed() -> void:
	_last_hud_btn_msec = Time.get_ticks_msec()


func set_dialogue_mode(active: bool) -> void:
	is_dialogue_mode = active
	_sync_hud_visibility()


func set_modal_blocked(blocked: bool) -> void:
	is_modal_blocked = blocked
	_sync_hud_visibility()


func set_movie_playing_block(blocked: bool) -> void:
	is_movie_playing_block = blocked
	_sync_hud_visibility()


func set_movie_playing(playing: bool) -> void:
	set_movie_playing_block(playing)


func set_ui_hidden(hidden: bool) -> void:
	is_ui_hidden = hidden
	_sync_hud_visibility()


func set_phone_open(opened: bool) -> void:
	is_phone_open = opened


func _sync_hud_visibility() -> void:
	var show_hud: bool = is_dialogue_mode and not is_modal_blocked and not is_movie_playing_block and not is_ui_hidden
	if _bottom_left_hud != null:
		_bottom_left_hud.visible = show_hud
	if _bottom_right_hud != null:
		_bottom_right_hud.visible = show_hud
	if _date_phone_btn != null:
		_date_phone_btn.visible = show_hud


func set_mode_states(auto_on: bool, skip_on: bool) -> void:
	is_auto_active = auto_on
	is_skip_active = skip_on
	_refresh_mode_btn_styles()


func _refresh_mode_btn_styles() -> void:
	if _btn_auto != null:
		var tex_auto: Texture2D = _meswin_assets.get("auto_btn_on" if is_auto_active else "auto_btn_off", null)
		if tex_auto != null:
			_apply_texture_mode_btn(_btn_auto, tex_auto, is_auto_active)
		else:
			_btn_auto.custom_minimum_size = Vector2(96, 46)
			_btn_auto.text = "[自动中]" if is_auto_active else "自动 AUTO"
			_apply_hud_btn_style(_btn_auto, is_auto_active)
	if _btn_skip != null:
		var tex_skip: Texture2D = _meswin_assets.get("skip_btn_on" if is_skip_active else "skip_btn_off", null)
		if tex_skip != null:
			_apply_texture_mode_btn(_btn_skip, tex_skip, is_skip_active)
		else:
			_btn_skip.custom_minimum_size = Vector2(96, 46)
			_btn_skip.text = "[快进中]" if is_skip_active else "快进 SKIP"
			_apply_hud_btn_style(_btn_skip, is_skip_active)


func _apply_texture_mode_btn(btn: Button, tex: Texture2D, _active: bool) -> void:
	btn.text = ""
	var th := maxf(1.0, float(tex.get_height()))
	var target_h := 42.0
	var target_w := roundf(float(tex.get_width()) * (target_h / th))
	btn.custom_minimum_size = Vector2(target_w, target_h)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	btn.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate() as StyleBoxTexture
	sb_hover.modulate_color = Color(1.12, 1.12, 1.12, 1.0)
	btn.add_theme_stylebox_override("hover", sb_hover)
	var sb_pressed := sb.duplicate() as StyleBoxTexture
	sb_pressed.modulate_color = Color(0.86, 0.90, 1.0, 1.0)
	btn.add_theme_stylebox_override("pressed", sb_pressed)
	btn.add_theme_stylebox_override("focus", sb)


func _input(event: InputEvent) -> void:
	if not is_dialogue_mode or is_modal_blocked or is_movie_playing_block or not visible or is_ui_hidden:
		return

	# 滑动手势探测（上下/左右划）
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var canvas_pos := _to_canvas_pos(st.position)
		if st.pressed:
			_swipe_start = canvas_pos
			_tracking_swipe = true
		elif _tracking_swipe:
			_tracking_swipe = false
			var delta := canvas_pos - _swipe_start
			if delta.length() > 140.0 and not _is_over_hud(canvas_pos):
				if absf(delta.x) > absf(delta.y):
					if delta.x < 0:
						open_phone_requested.emit()
					else:
						open_backlog_requested.emit()
				else:
					if delta.y < 0:
						open_backlog_requested.emit()
					else:
						toggle_hide_ui_requested.emit()
				get_viewport().set_input_as_handled()
		return

	# 注意：项目开启了 emulate_mouse_from_touch=true，触屏点击也会转为左键 MouseButton，
	# 因此仅在非按钮按下时刻（且距最近按钮按下 > 120ms）才由点击空白处退出 Auto/Skip，避免按钮点按自己取消自己
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var canvas_pos := _to_canvas_pos(mb.position)
			if (Time.get_ticks_msec() - _last_hud_btn_msec) <= 120:
				return
			if (is_auto_active or is_skip_active) and not _is_over_hud(canvas_pos):
				if is_auto_active:
					toggle_auto_requested.emit()
				if is_skip_active:
					toggle_skip_requested.emit()
				get_viewport().set_input_as_handled()


func _to_canvas_pos(viewport_pt: Vector2) -> Vector2:
	if is_inside_tree():
		return get_viewport_transform().affine_inverse() * viewport_pt
	var vp := get_viewport()
	if vp == null:
		return viewport_pt
	return vp.get_canvas_transform().affine_inverse() * viewport_pt


func _is_over_hud(canvas_pt: Vector2) -> bool:
	if _date_phone_btn != null and _date_phone_btn.visible and _date_phone_btn.get_global_rect().has_point(canvas_pt):
		return true
	if _bottom_left_hud != null and _bottom_left_hud.visible and _bottom_left_hud.get_global_rect().has_point(canvas_pt):
		return true
	if _bottom_right_hud != null and _bottom_right_hud.visible and _bottom_right_hud.get_global_rect().has_point(canvas_pt):
		return true
	if is_phone_open and canvas_pt.x >= 1280.0:
		return true
	return false
