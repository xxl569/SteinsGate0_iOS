class_name MobileGestureHelper
extends Control
## iOS 移动端触控交互、刘海屏安全区适配与左上角悬浮快捷栏（避免与右上角返回/收起键重叠）

signal advance_requested()
signal toggle_skip_requested()
signal toggle_auto_requested()
signal open_backlog_requested()
signal open_save_requested()
signal open_load_requested()
signal open_config_requested()
signal open_phone_requested()
signal open_tips_requested()
signal open_title_requested()
signal toggle_hide_ui_requested()

var is_auto_active: bool = false
var is_skip_active: bool = false
var is_dialogue_mode: bool = false
var is_modal_blocked: bool = false
var is_movie_playing_block: bool = false

var _hud_container: HBoxContainer = null
var _btn_skip: Button = null
var _btn_auto: Button = null
var _btn_phone: Button = null
var _swipe_start: Vector2 = Vector2.ZERO
var _tracking_swipe: bool = false


func _ready() -> void:
	name = "MobileGestureHelper"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_hud()
	_apply_safe_area()
	if get_viewport() != null and not get_viewport().size_changed.is_connected(_apply_safe_area):
		get_viewport().size_changed.connect(_apply_safe_area)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_apply_safe_area()


func _build_hud() -> void:
	_hud_container = HBoxContainer.new()
	_hud_container.name = "FloatingHudBar"
	_hud_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	_hud_container.grow_horizontal = Control.GROW_DIRECTION_END
	_hud_container.add_theme_constant_override("separation", 6)
	_hud_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_hud_container.offset_left = 20
	_hud_container.offset_top = 14
	_hud_container.offset_right = 980
	_hud_container.offset_bottom = 60
	_hud_container.mouse_filter = Control.MOUSE_FILTER_PASS
	_hud_container.visible = false
	add_child(_hud_container)

	_btn_skip = _make_hud_btn("快进 SKIP", func(): toggle_skip_requested.emit())
	_btn_auto = _make_hud_btn("自动 AUTO", func(): toggle_auto_requested.emit())
	var btn_log := _make_hud_btn("回顾 LOG", func(): open_backlog_requested.emit())
	_btn_phone = _make_hud_btn("手机 RINE", func(): open_phone_requested.emit())
	var btn_tips := _make_hud_btn("TIPS", func(): open_tips_requested.emit())
	var btn_save := _make_hud_btn("存档 SAVE", func(): open_save_requested.emit())
	var btn_load := _make_hud_btn("读档 LOAD", func(): open_load_requested.emit())
	var btn_cfg := _make_hud_btn("设置", func(): open_config_requested.emit())
	var btn_hide := _make_hud_btn("隐藏", func(): toggle_hide_ui_requested.emit())
	var btn_title := _make_hud_btn("标题", func(): open_title_requested.emit())

	for b in [_btn_skip, _btn_auto, btn_log, _btn_phone, btn_tips, btn_save, btn_load, btn_cfg, btn_hide, btn_title]:
		_hud_container.add_child(b)


func _make_hud_btn(label_text: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.custom_minimum_size = Vector2(70, 42)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_stylebox_override("normal", UiThemeLoader.make_button_style(true))
	btn.add_theme_stylebox_override("hover", UiThemeLoader.make_button_style(false))
	btn.add_theme_stylebox_override("pressed", UiThemeLoader.make_button_style(false))
	btn.pressed.connect(cb)
	return btn


func set_dialogue_mode(enabled: bool) -> void:
	is_dialogue_mode = enabled
	_sync_hud_visibility()


func set_modal_blocked(blocked: bool) -> void:
	is_modal_blocked = blocked
	_sync_hud_visibility()


func set_movie_playing(playing: bool) -> void:
	is_movie_playing_block = playing
	_sync_hud_visibility()


func _sync_hud_visibility() -> void:
	if _hud_container != null:
		_hud_container.visible = is_dialogue_mode and not is_modal_blocked and not is_movie_playing_block


func set_mode_states(auto_on: bool, skip_on: bool) -> void:
	is_auto_active = auto_on
	is_skip_active = skip_on
	if _btn_auto != null:
		_btn_auto.modulate = Color(1.0, 0.72, 0.28) if auto_on else Color.WHITE
	if _btn_skip != null:
		_btn_skip.modulate = Color(1.0, 0.55, 0.22) if skip_on else Color.WHITE


func _apply_safe_area() -> void:
	if _hud_container == null:
		return
	var safe := DisplayServer.get_display_safe_area()
	var win_sz := DisplayServer.window_get_size()
	if win_sz.x <= 0 or win_sz.y <= 0:
		return
	var top_pad := maxi(14, int(float(safe.position.y) * (1080.0 / float(win_sz.y))) + 8)
	var left_inset := maxi(20, int(float(safe.position.x) * (1920.0 / float(win_sz.x))) + 14)
	_hud_container.offset_left = left_inset
	_hud_container.offset_top = top_pad
	_hud_container.offset_right = left_inset + 980
	_hud_container.offset_bottom = top_pad + 46


func _input(event: InputEvent) -> void:
	if not is_dialogue_mode or is_modal_blocked or is_movie_playing_block or not visible:
		return
	# 当处于 Auto 或 Skip 状态且点击在非 HUD 按钮区域时，按下瞬间先解除自动/快进（不直接触发误推进）
	var is_press := false
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			is_press = true
			pos = st.position
			_swipe_start = pos
			_tracking_swipe = true
		elif _tracking_swipe:
			_tracking_swipe = false
			var dy := st.position.y - _swipe_start.y
			if dy < -140.0 and not _is_over_hud(st.position):
				open_backlog_requested.emit()
				get_viewport().set_input_as_handled()
				return
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			is_press = true
			pos = mb.position
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			toggle_hide_ui_requested.emit()
			get_viewport().set_input_as_handled()
			return

	if is_press and (is_auto_active or is_skip_active) and not _is_over_hud(pos):
		if is_auto_active:
			toggle_auto_requested.emit()
		if is_skip_active:
			toggle_skip_requested.emit()
		get_viewport().set_input_as_handled()


func _is_over_hud(global_pt: Vector2) -> bool:
	if _hud_container == null or not _hud_container.visible:
		return false
	return _hud_container.get_global_rect().has_point(global_pt)
