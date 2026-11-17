class_name UiPanels
extends Control
## MAGES. 主 UI 面板集合（标题画面 / 对话框与分支选项 / 1:1 PC 历史回放 / 存档读档 / 系统设置 / BYOA 引导）

signal new_game_requested()
signal continue_game_requested()
signal extra_requested(tab: int)
signal tips_requested()
signal advance_dialogue_requested()
signal choice_selected(index: int)
signal voice_replay_requested(voice_idx: int)
signal voice_replay_with_char_requested(voice_idx: int, char_id: int)
signal save_slot_requested(slot_id: int)
signal load_slot_requested(slot_id: int)
signal retry_byoa_requested()
signal config_applied()
signal modal_visibility_changed(any_open: bool)
signal ui_hidden_changed(hidden: bool)

const SAVE_DIR := "user://saves"
const NUM_SAVE_SLOTS := 48

var _vfs: MgsVfs = null
var _vm: Sc3Vm = null
var _cfg: ConfigManager = null
var _theme_loader: UiThemeLoader = null

# 主视图容器
var _title_view: Control = null
var _title_bg: TextureRect = null
var _title_status: Label = null
var _btn_continue: Button = null

var _dialogue_view: Control = null
var _meswin_plate: TextureRect = null
var _meswin_accent: Control = null
var _accent_left: TextureRect = null
var _accent_right: TextureRect = null
var _name_renderer: MgsFontRenderer = null
var _body_renderer: MgsFontRenderer = null
var _mode_badge: Label = null
var _mode_ring: TextureRect = null
var _auto_ring_tex: Texture2D = null
var _skip_ring_tex: Texture2D = null
var _auto_ring_frames: Array[Texture2D] = []
var _skip_ring_frames: Array[Texture2D] = []
var _wait_ring_frames: Array[Texture2D] = []
var _mode_ring_is_skip: bool = false
var _wait_cursor: Label = null
var _wait_ring: TextureRect = null
var _choices_panel: PanelContainer = null
var _choices_box: VBoxContainer = null
var _quicksave_toast: TextureRect = null
var _quicksave_timer: float = 0.0

var _modal_layer: Control = null
var _backlog_view: UiBacklogPanel = null
var _saveload_view: UiSaveloadPanel = null
var _config_view: UiConfigPanel = null

var _byoa_view: Control = null
var _byoa_detail: Label = null
var _tips_banner_tex: Texture2D = null
var _tips_banner_rect: TextureRect = null
var _tips_toast: PanelContainer = null
var _tips_toast_label: Label = null
var _tips_toast_timer: float = 0.0
const TIPS_TOAST_DURATION := 3.2

var _built: bool = false
var _ui_hidden: bool = false
var _blink_t: float = 0.0


func _ready() -> void:
	name = "UiPanels"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_ui()


func setup(vfs: MgsVfs, vm: Sc3Vm, cfg: ConfigManager, loader: UiThemeLoader) -> void:
	_vfs = vfs
	_vm = vm
	_cfg = cfg
	_theme_loader = loader
	_ensure_ui()
	_bind_textures_and_renderers()
	if _config_view != null:
		_config_view.setup(_cfg, _theme_loader)
	if _saveload_view != null:
		_saveload_view.setup(_theme_loader)
	if _backlog_view != null:
		_backlog_view.setup(_vfs, _vm, _theme_loader)
	refresh_title_status()


func _ensure_ui() -> void:
	if _built:
		return
	_built = true
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_build_title_view()
	_build_dialogue_view()
	_build_modal_layer()
	_build_byoa_view()


func _build_title_view() -> void:
	_title_view = Control.new()
	_title_view.name = "TitleView"
	_title_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_title_view)

	_title_bg = TextureRect.new()
	_title_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_title_view.add_child(_title_bg)

	var bg_fallback := ColorRect.new()
	bg_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_fallback.color = Color(0.05, 0.03, 0.03, 0.25)
	bg_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_view.add_child(bg_fallback)

	var logo_card := PanelContainer.new()
	logo_card.position = Vector2(96, 84)
	logo_card.size = Vector2(560, 128)
	logo_card.add_theme_stylebox_override("panel", UiThemeLoader.make_dark_panel_style(Color(0.08, 0.04, 0.03, 0.85), Color(0.95, 0.45, 0.12, 0.95)))
	_title_view.add_child(logo_card)

	var logo_vbox := VBoxContainer.new()
	logo_card.add_child(logo_vbox)
	var lbl_main := Label.new()
	lbl_main.text = "STEINS;GATE 0"
	lbl_main.add_theme_font_size_override("font_size", 46)
	lbl_main.modulate = Color(1.0, 0.78, 0.35)
	var lbl_sub := Label.new()
	lbl_sub.text = "命运石之门 0 · iOS BYOA 移植版 (Godot 4.3 + MgsNative)"
	lbl_sub.add_theme_font_size_override("font_size", 18)
	lbl_sub.modulate = Color(0.88, 0.88, 0.90)
	logo_vbox.add_child(lbl_main)
	logo_vbox.add_child(lbl_sub)

	var menu_col := VBoxContainer.new()
	menu_col.name = "TitleMenu"
	menu_col.position = Vector2(96, 280)
	menu_col.size = Vector2(360, 480)
	menu_col.add_theme_constant_override("separation", 14)
	_title_view.add_child(menu_col)

	var btn_new := _make_menu_btn("开始游戏  NEW GAME", func(): new_game_requested.emit())
	_btn_continue = _make_menu_btn("继续游戏  CONTINUE", func():
		if _has_any_save():
			continue_game_requested.emit()
		else:
			open_saveload(false)
	)
	var btn_load := _make_menu_btn("读取存档  LOAD", func(): open_saveload(false))
	var btn_extra := _make_menu_btn("鉴赏模式  EXTRA", func(): extra_requested.emit(0))
	var btn_tips := _make_menu_btn("用语词典  TIPS", func(): tips_requested.emit())
	var btn_cfg := _make_menu_btn("系统设置  CONFIG", func(): open_config())

	for b in [btn_new, _btn_continue, btn_load, btn_extra, btn_tips, btn_cfg]:
		menu_col.add_child(b)

	_title_status = Label.new()
	_title_status.position = Vector2(96, 836)
	_title_status.size = Vector2(1400, 40)
	_title_status.add_theme_font_size_override("font_size", 18)
	_title_status.modulate = Color(0.90, 0.78, 0.55)
	_title_view.add_child(_title_status)


func _make_menu_btn(txt: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(340, 58)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_stylebox_override("normal", UiThemeLoader.make_button_style(true))
	btn.add_theme_stylebox_override("hover", UiThemeLoader.make_button_style(false))
	btn.add_theme_stylebox_override("pressed", UiThemeLoader.make_button_style(false))
	btn.pressed.connect(cb)
	return btn


func _build_dialogue_view() -> void:
	_dialogue_view = Control.new()
	_dialogue_view.name = "DialogueView"
	_dialogue_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dialogue_view.visible = false
	_dialogue_view.mouse_filter = Control.MOUSE_FILTER_PASS
	_dialogue_view.gui_input.connect(_on_dialogue_tap)
	add_child(_dialogue_view)

	_meswin_plate = TextureRect.new()
	_meswin_plate.name = "MesWinPlate"
	_meswin_plate.position = Vector2(0, 762)
	_meswin_plate.size = Vector2(1920, 318)
	_meswin_plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_meswin_plate.stretch_mode = TextureRect.STRETCH_SCALE
	_meswin_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_view.add_child(_meswin_plate)

	# PC 原版样式：说话人名称与两侧橙色光翼居中置于对话框正下方（无名旁白时自动隐藏）
	_meswin_accent = Control.new()
	_meswin_accent.name = "SpeakerNameBracket"
	_meswin_accent.position = Vector2(760, 1028)
	_meswin_accent.size = Vector2(400, 32)
	_meswin_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meswin_accent.visible = false
	_dialogue_view.add_child(_meswin_accent)

	_accent_left = TextureRect.new()
	_accent_left.position = Vector2(0, 2)
	_accent_left.size = Vector2(158, 28)
	_accent_left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_accent_left.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_accent_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meswin_accent.add_child(_accent_left)

	_accent_right = TextureRect.new()
	_accent_right.position = Vector2(242, 2)
	_accent_right.size = Vector2(158, 28)
	_accent_right.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_accent_right.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_accent_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meswin_accent.add_child(_accent_right)

	_name_renderer = MgsFontRenderer.new()
	_name_renderer.name = "SpeakerNameRenderer"
	_name_renderer.position = Vector2(960, 1024)
	_name_renderer.base_scale = 0.72
	_name_renderer.default_color = Color(1.0, 0.80, 0.36)
	_name_renderer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_view.add_child(_name_renderer)

	_body_renderer = MgsFontRenderer.new()
	_body_renderer.name = "BodyTextRenderer"
	_body_renderer.position = Vector2(240, 796)
	_body_renderer.base_scale = 0.70
	_body_renderer.line_height = 50.0
	_body_renderer.max_line_width = 1420.0
	_body_renderer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_view.add_child(_body_renderer)

	_mode_ring = TextureRect.new()
	_mode_ring.name = "ModeRingBadge"
	_mode_ring.position = Vector2(1690, 845)
	_mode_ring.size = Vector2(124, 124)
	_mode_ring.pivot_offset = Vector2(62, 62)
	_mode_ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mode_ring.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mode_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_ring.visible = false
	_dialogue_view.add_child(_mode_ring)

	_mode_badge = Label.new()
	_mode_badge.position = Vector2(1650, 774)
	_mode_badge.size = Vector2(240, 32)
	_mode_badge.add_theme_font_size_override("font_size", 20)
	_mode_badge.modulate = Color(1.0, 0.68, 0.22)
	_mode_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_view.add_child(_mode_badge)

	_wait_ring = TextureRect.new()
	_wait_ring.name = "WaitRingCursor"
	_wait_ring.position = Vector2(1672, 928)
	_wait_ring.size = Vector2(48, 48)
	_wait_ring.pivot_offset = Vector2(24, 24)
	_wait_ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wait_ring.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_wait_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wait_ring.visible = false
	_dialogue_view.add_child(_wait_ring)

	_wait_cursor = Label.new()
	_wait_cursor.text = "▼"
	_wait_cursor.position = Vector2(1680, 936)
	_wait_cursor.add_theme_font_size_override("font_size", 26)
	_wait_cursor.modulate = Color(1.0, 0.68, 0.22)
	_wait_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wait_cursor.visible = false
	_dialogue_view.add_child(_wait_cursor)

	_quicksave_toast = TextureRect.new()
	_quicksave_toast.name = "QuickSavedGear"
	_quicksave_toast.position = Vector2(28, 868)
	_quicksave_toast.size = Vector2(168, 134)
	_quicksave_toast.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_quicksave_toast.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_quicksave_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quicksave_toast.visible = false
	_dialogue_view.add_child(_quicksave_toast)

	# 分支选项居中面板
	_choices_panel = PanelContainer.new()
	_choices_panel.name = "ChoicesModal"
	_choices_panel.position = Vector2(460, 260)
	_choices_panel.size = Vector2(1000, 360)
	_choices_panel.visible = false
	_choices_panel.add_theme_stylebox_override("panel", UiThemeLoader.make_dark_panel_style(Color(0.05, 0.06, 0.08, 0.92), Color(0.95, 0.55, 0.18, 0.95)))
	add_child(_choices_panel)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 14)
	_choices_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_choices_panel.add_child(_choices_box)


func _build_modal_layer() -> void:
	_modal_layer = Control.new()
	_modal_layer.name = "ModalLayer"
	_modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modal_layer)

	# 1. PC 1:1 Backlog 面板
	_backlog_view = UiBacklogPanel.new()
	_backlog_view.voice_replay_requested.connect(func(vid: int): voice_replay_requested.emit(vid))
	_backlog_view.voice_replay_with_char_requested.connect(func(vid: int, cid: int): voice_replay_with_char_requested.emit(vid, cid))
	_backlog_view.closed.connect(_notify_modal_state)
	_modal_layer.add_child(_backlog_view)

	# 2. PC 1:1 Save / Load 面板
	_saveload_view = UiSaveloadPanel.new()
	_saveload_view.save_slot_requested.connect(func(sid: int):
		_notify_modal_state()
		save_slot_requested.emit(sid)
	)
	_saveload_view.load_slot_requested.connect(func(sid: int):
		_notify_modal_state()
		load_slot_requested.emit(sid)
	)
	_saveload_view.closed.connect(_notify_modal_state)
	_modal_layer.add_child(_saveload_view)

	# 3. PC 1:1 Config 面板
	_config_view = UiConfigPanel.new()
	_config_view.applied.connect(func(): config_applied.emit())
	_config_view.closed.connect(_notify_modal_state)
	_modal_layer.add_child(_config_view)


func _build_byoa_view() -> void:
	_byoa_view = Control.new()
	_byoa_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_byoa_view.visible = false
	add_child(_byoa_view)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.05, 0.08, 0.96)
	_byoa_view.add_child(bg)

	var card := PanelContainer.new()
	card.position = Vector2(360, 180)
	card.size = Vector2(1200, 680)
	card.add_theme_stylebox_override("panel", UiThemeLoader.make_dark_panel_style())
	_byoa_view.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	card.add_child(box)

	var h := Label.new()
	h.text = "未检测到《命运石之门 0》游戏资产 (BYOA 模式)"
	h.add_theme_font_size_override("font_size", 32)
	h.modulate = Color(1.0, 0.65, 0.25)
	box.add_child(h)

	_byoa_detail = Label.new()
	_byoa_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_byoa_detail.add_theme_font_size_override("font_size", 22)
	_byoa_detail.text = "请通过 iOS“文件”App 或爱思/Finder 文件共享，将 PC 版游戏目录下的：\n1. USRDIR/ 文件夹（含 script.mpk、bg.mpk、chara.mpk、system.mpk、bgm.mpk、se.mpk、voice.mpk、mask.mpk）\n2. 转码后的 movie/ 文件夹（含 33 个 .ogv 过场动画）\n复制到本应用的「我的 iPhone -> SteinsGate0_iOS」根目录后点击下方重试。"
	box.add_child(_byoa_detail)

	var btn_retry := _make_menu_btn("重新扫描并挂载资产 RETRY", func(): retry_byoa_requested.emit())
	box.add_child(btn_retry)


func _bind_textures_and_renderers() -> void:
	if _vfs != null:
		_name_renderer.bind_vfs(_vfs)
		_body_renderer.bind_vfs(_vfs)
	if _theme_loader != null and _vfs != null and _vfs.is_mounted:
		var t_assets := _theme_loader.get_title_assets()
		if t_assets.get("bg", null) != null:
			_title_bg.texture = t_assets["bg"] as Texture2D
		var m_assets := _theme_loader.get_meswin_assets()
		if m_assets.get("box", null) != null:
			_meswin_plate.texture = m_assets["box"] as Texture2D
		if m_assets.get("accent_left", null) != null and _accent_left != null:
			_accent_left.texture = m_assets["accent_left"] as Texture2D
		if m_assets.get("accent_right", null) != null and _accent_right != null:
			_accent_right.texture = m_assets["accent_right"] as Texture2D
		_auto_ring_tex = m_assets.get("auto_ring", null) as Texture2D
		_skip_ring_tex = m_assets.get("skip_ring", null) as Texture2D
		_auto_ring_frames.clear()
		for fr in m_assets.get("auto_ring_frames", []):
			if fr != null:
				_auto_ring_frames.append(fr as Texture2D)
		_skip_ring_frames.clear()
		for fr in m_assets.get("skip_ring_frames", []):
			if fr != null:
				_skip_ring_frames.append(fr as Texture2D)
		_wait_ring_frames.clear()
		for fr in m_assets.get("wait_ring_frames", []):
			if fr != null:
				_wait_ring_frames.append(fr as Texture2D)
		if m_assets.get("wait_ring", null) != null and _wait_ring != null:
			_wait_ring.texture = m_assets["wait_ring"] as Texture2D
		if m_assets.get("quicksave_gear", null) != null and _quicksave_toast != null:
			_quicksave_toast.texture = m_assets["quicksave_gear"] as Texture2D
		_tips_banner_tex = m_assets.get("tips_banner", null) as Texture2D
		if _tips_banner_rect != null and _tips_banner_tex != null:
			_tips_banner_rect.texture = _tips_banner_tex


func _process(delta: float) -> void:
	_blink_t += delta
	if _tips_toast_timer > 0.0:
		_tips_toast_timer -= delta
		var elapsed := TIPS_TOAST_DURATION - _tips_toast_timer
		var alpha := 1.0
		var y_off := 18.0
		if elapsed < 0.22:
			var t := clampf(elapsed / 0.22, 0.0, 1.0)
			alpha = t
			y_off = lerpf(-60.0, 18.0, t * (2.0 - t))
		elif _tips_toast_timer < 0.45:
			alpha = clampf(_tips_toast_timer / 0.45, 0.0, 1.0)
		if _tips_toast_timer <= 0.0:
			if _tips_banner_rect != null:
				_tips_banner_rect.visible = false
			if _tips_toast != null:
				_tips_toast.visible = false
		else:
			if _tips_banner_rect != null and _tips_banner_rect.visible:
				_tips_banner_rect.position.y = y_off
				_tips_banner_rect.modulate.a = alpha
			if _tips_toast != null and _tips_toast.visible:
				_tips_toast.position.y = y_off
				_tips_toast.modulate.a = alpha
	if _quicksave_toast != null and _quicksave_toast.visible:
		_quicksave_timer -= delta
		if _quicksave_timer <= 0.0:
			_quicksave_toast.visible = false
		else:
			_quicksave_toast.modulate.a = clampf(_quicksave_timer * 1.8, 0.0, 1.0)
	if _dialogue_view != null and _dialogue_view.visible:
		var completed := _body_renderer.is_fully_revealed()
		if not completed:
			_body_renderer.step_reveal(delta)
		var show_wait := completed and not _choices_panel.visible and (_mode_ring == null or not _mode_ring.visible)
		if _wait_ring != null and (_wait_ring.texture != null or not _wait_ring_frames.is_empty()):
			_wait_ring.visible = show_wait
			_wait_cursor.visible = false
			if show_wait:
				_wait_ring.rotation = 0.0
				if not _wait_ring_frames.is_empty():
					var widx := int(floor(_blink_t * 18.0)) % _wait_ring_frames.size()
					_wait_ring.texture = _wait_ring_frames[widx]
				_wait_ring.modulate.a = 0.78 + 0.22 * sin(_blink_t * 5.0)
		else:
			_wait_cursor.visible = show_wait
			if _wait_cursor.visible:
				_wait_cursor.modulate.a = 0.55 + 0.45 * sin(_blink_t * 6.0)
		if _mode_ring != null and _mode_ring.visible:
			_mode_ring.rotation = 0.0
			var mframes := _skip_ring_frames if _mode_ring_is_skip else _auto_ring_frames
			if not mframes.is_empty():
				var midx := int(floor(_blink_t * 16.0)) % mframes.size()
				_mode_ring.texture = mframes[midx]


func show_quicksaved_toast() -> void:
	_ensure_ui()
	if _quicksave_toast != null and _quicksave_toast.texture != null:
		_quicksave_toast.visible = true
		_quicksave_toast.modulate.a = 1.0
		_quicksave_timer = 1.8


func show_tips_toast(tip_id: int) -> void:
	if _cfg != null and not _cfg.show_tips_popup:
		return
	_ensure_ui()
	if _tips_banner_tex == null and _theme_loader != null and _vfs != null and _vfs.is_mounted:
		_tips_banner_tex = _theme_loader.get_meswin_assets().get("tips_banner", null) as Texture2D

	if _tips_banner_tex != null:
		if _tips_banner_rect == null:
			_tips_banner_rect = TextureRect.new()
			_tips_banner_rect.name = "TipsUnlockedBanner"
			_tips_banner_rect.size = Vector2(762, 102)
			_tips_banner_rect.position = Vector2((1920.0 - 762.0) * 0.5, 18.0)
			_tips_banner_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_tips_banner_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_tips_banner_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_tips_banner_rect.z_index = 20
			add_child(_tips_banner_rect)
		_tips_banner_rect.texture = _tips_banner_tex
		_tips_banner_rect.position = Vector2((1920.0 - 762.0) * 0.5, 18.0)
		_tips_banner_rect.modulate.a = 1.0
		_tips_banner_rect.visible = true
		if _tips_toast != null:
			_tips_toast.visible = false
	else:
		if _tips_toast == null:
			_tips_toast = PanelContainer.new()
			_tips_toast.name = "TipsUnlockedFallback"
			_tips_toast.position = Vector2((1920.0 - 420.0) * 0.5, 22.0)
			_tips_toast.size = Vector2(420, 54)
			_tips_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_tips_toast.z_index = 20
			_tips_toast.add_theme_stylebox_override("panel", UiThemeLoader.make_dark_panel_style(Color(0.06, 0.09, 0.14, 0.92), Color(0.95, 0.58, 0.16, 0.95)))
			add_child(_tips_toast)
			_tips_toast_label = Label.new()
			_tips_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_tips_toast_label.add_theme_font_size_override("font_size", 20)
			_tips_toast_label.modulate = Color(1.0, 0.84, 0.42)
			_tips_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_tips_toast.add_child(_tips_toast_label)
		_tips_toast_label.text = "取得了新的TIPS  No.%03d" % (tip_id + 1)
		_tips_toast.position = Vector2((1920.0 - 420.0) * 0.5, 22.0)
		_tips_toast.modulate.a = 1.0
		_tips_toast.visible = true
	_tips_toast_timer = TIPS_TOAST_DURATION


func show_byoa_wizard(missing_paths: PackedStringArray) -> void:
	_ensure_ui()
	_byoa_view.visible = true
	_title_view.visible = false
	_dialogue_view.visible = false
	if not missing_paths.is_empty():
		_byoa_detail.text += "\n\n已探测候选路径:\n" + "\n".join(missing_paths.slice(0, 5))


func hide_byoa_wizard() -> void:
	if _byoa_view != null:
		_byoa_view.visible = false


func show_title_screen() -> void:
	_ensure_ui()
	_title_view.visible = true
	_dialogue_view.visible = false
	_choices_panel.visible = false
	refresh_title_status()


func show_dialogue_mode() -> void:
	_ensure_ui()
	_title_view.visible = false
	_byoa_view.visible = false
	_dialogue_view.visible = not _ui_hidden


func toggle_hide_ui() -> void:
	_ui_hidden = not _ui_hidden
	if not _title_view.visible:
		_dialogue_view.visible = not _ui_hidden
	ui_hidden_changed.emit(_ui_hidden)


func set_mode_badge(auto_on: bool, skip_on: bool) -> void:
	if _mode_ring != null:
		_mode_ring.rotation = 0.0
		_mode_ring_is_skip = skip_on
		if skip_on and (_skip_ring_tex != null or not _skip_ring_frames.is_empty()):
			_mode_ring.texture = _skip_ring_frames[3] if _skip_ring_frames.size() > 3 else _skip_ring_tex
			_mode_ring.visible = true
		elif auto_on and (_auto_ring_tex != null or not _auto_ring_frames.is_empty()):
			_mode_ring.texture = _auto_ring_frames[3] if _auto_ring_frames.size() > 3 else _auto_ring_tex
			_mode_ring.visible = true
		else:
			_mode_ring.visible = false
	if _mode_badge == null:
		return
	if skip_on:
		_mode_badge.text = ">> SKIPPING" if (_mode_ring == null or not _mode_ring.visible) else ""
	elif auto_on:
		_mode_badge.text = "● AUTO" if (_mode_ring == null or not _mode_ring.visible) else ""
	else:
		_mode_badge.text = ""


func refresh_title_status() -> void:
	if _title_status == null:
		return
	var sc_cnt := _vfs.get_archive_entry_count("script.mpk") if _vfs != null and _vfs.is_mounted else 0
	var mov_cnt := _vfs.get_movie_names().size() if _vfs != null else 0
	_title_status.text = "BYOA 已挂载: script.mpk=%d 条目 | movie=.ogv %d 部 | 路径: %s" % [sc_cnt, mov_cnt, _vfs.active_game_dir if _vfs != null else "-"]
	if _btn_continue != null:
		_btn_continue.disabled = not _has_any_save()


func show_dialogue_line(buf: PackedByteArray, str_offset: int, instant: bool = false) -> void:
	show_dialogue_mode()
	var cps := _cfg.text_speed if _cfg != null else 60.0
	_body_renderer.set_text_speed(cps)
	_body_renderer.set_sc3_string(buf, str_offset, _vm, null, instant)
	var name_arr := _body_renderer.get_name_glyphs()
	var gids := PackedInt32Array()
	for ng in name_arr:
		gids.append(int(ng["gid"]))
	_name_renderer.set_glyph_list(gids, 0.72, Color(1.0, 0.80, 0.36))
	var has_name := not gids.is_empty()
	if _meswin_accent != null:
		_meswin_accent.visible = has_name
	if has_name:
		var nw := _name_renderer.get_content_size().x
		_name_renderer.position = Vector2(960.0 - nw * 0.5, 1022.0)
		if _meswin_accent != null:
			var wing_w := 158.0
			var gap := maxf(76.0, nw + 36.0)
			var total_w := wing_w * 2.0 + gap
			_meswin_accent.position = Vector2(960.0 - total_w * 0.5, 1024.0)
			_meswin_accent.size = Vector2(total_w, 32.0)
			if _accent_left != null:
				_accent_left.position = Vector2(0.0, 2.0)
			if _accent_right != null:
				_accent_right.position = Vector2(total_w - wing_w, 2.0)


func clear_dialogue_line() -> void:
	if _name_renderer != null:
		_name_renderer.clear_text()
	if _meswin_accent != null:
		_meswin_accent.visible = false
	if _body_renderer != null:
		_body_renderer.clear_text()


func is_dialogue_reveal_done() -> bool:
	return _body_renderer == null or _body_renderer.is_fully_revealed()


func reveal_dialogue_instant() -> void:
	if _body_renderer != null:
		_body_renderer.reveal_all()


func show_choices(choices: Array) -> void:
	for c in _choices_box.get_children():
		_choices_box.remove_child(c)
		c.queue_free()
	if choices.is_empty():
		_choices_panel.visible = false
		return

	for i in range(choices.size()):
		var ch: Dictionary = choices[i]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(920, 64)
		btn.add_theme_stylebox_override("normal", UiThemeLoader.make_button_style(true))
		btn.add_theme_stylebox_override("hover", UiThemeLoader.make_button_style(false))
		btn.text = "分支选项 %d" % (i + 1)

		var sc_name := str(ch.get("script", ""))
		var off := int(ch.get("str_offset", -1))
		if _vfs != null and _vfs.is_mounted and sc_name != "" and off >= 0:
			var sdata := _vfs.read_entry("script.mpk", sc_name)
			if not sdata.is_empty():
				btn.text = ""
				var fr := MgsFontRenderer.new()
				fr.bind_vfs(_vfs)
				fr.position = Vector2(28, 10)
				fr.base_scale = 0.65
				fr.max_line_width = 860.0
				fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				btn.add_child(fr)
				fr.set_sc3_string(sdata, off, _vm, null, true)

		var idx := int(ch.get("index", i))
		btn.pressed.connect(func():
			_choices_panel.visible = false
			choice_selected.emit(idx)
		)
		_choices_box.add_child(btn)
	_choices_panel.visible = true


func has_modal_open() -> bool:
	return (
		(_backlog_view != null and _backlog_view.visible)
		or (_saveload_view != null and _saveload_view.visible)
		or (_config_view != null and _config_view.visible)
	)


func close_all_modals() -> void:
	if _backlog_view != null:
		_backlog_view.visible = false
	if _saveload_view != null:
		_saveload_view.visible = false
	if _config_view != null:
		_config_view.visible = false
	_notify_modal_state()


func _notify_modal_state() -> void:
	modal_visibility_changed.emit(has_modal_open())


func open_backlog() -> void:
	if _backlog_view == null:
		return
	if _saveload_view != null:
		_saveload_view.visible = false
	if _config_view != null:
		_config_view.visible = false
	_backlog_view.open_panel()
	_notify_modal_state()


func open_saveload(is_save: bool) -> void:
	if _saveload_view == null:
		return
	if _backlog_view != null:
		_backlog_view.visible = false
	if _config_view != null:
		_config_view.visible = false
	_saveload_view.open_panel(is_save)
	_notify_modal_state()


func open_config(initial_tab: int = 0) -> void:
	if _config_view == null:
		return
	if _backlog_view != null:
		_backlog_view.visible = false
	if _saveload_view != null:
		_saveload_view.visible = false
	_config_view.open_panel(initial_tab)
	_notify_modal_state()


func _on_dialogue_tap(event: InputEvent) -> void:
	if has_modal_open():
		return
	var emulate_mouse := bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", false))
	if _ui_hidden:
		if (event is InputEventMouseButton and event.pressed) or (not emulate_mouse and event is InputEventScreenTouch and event.pressed):
			toggle_hide_ui()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			advance_dialogue_requested.emit()
	elif not emulate_mouse and event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			advance_dialogue_requested.emit()


# ==================== 存档文件读写辅助 ====================

static func get_slot_path(slot_id: int) -> String:
	return "%s/slot_%02d.json" % [SAVE_DIR, slot_id]


static func get_slot_thumb_path(slot_id: int) -> String:
	return "%s/slot_%02d.png" % [SAVE_DIR, slot_id]


func _has_any_save() -> bool:
	for s in range(NUM_SAVE_SLOTS):
		if FileAccess.file_exists(get_slot_path(s)):
			return true
	return FileAccess.file_exists(get_slot_path(99))


static func write_slot_data(
	slot_id: int,
	state: Dictionary,
	summary_text: String = "",
	play_time_sec: int = 0,
	thumb_img: Image = null
) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var existing := read_slot_meta(slot_id)
	var keep_locked := bool(existing.get("locked", false))
	var dt := Time.get_datetime_dict_from_system()
	var ts := "%04d/%02d/%02d %02d:%02d:%02d" % [
		int(dt["year"]), int(dt["month"]), int(dt["day"]),
		int(dt["hour"]), int(dt["minute"]), int(dt["second"]),
	]
	var payload := {
		"slot_id": slot_id,
		"timestamp": ts,
		"play_time_sec": maxi(0, play_time_sec),
		"locked": keep_locked,
		"script_name": str(state.get("script_name", "")),
		"summary": summary_text,
		"vm_state": state,
	}
	var f := FileAccess.open(get_slot_path(slot_id), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(payload))
	f.close()

	if thumb_img != null and not thumb_img.is_empty():
		var scaled := thumb_img.duplicate() as Image
		scaled.resize(320, 180, Image.INTERPOLATE_BILINEAR)
		scaled.save_png(get_slot_thumb_path(slot_id))
	return true


static func set_slot_locked(slot_id: int, locked: bool) -> bool:
	var meta := read_slot_meta(slot_id)
	if meta.is_empty():
		return false
	meta["locked"] = locked
	var f := FileAccess.open(get_slot_path(slot_id), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(meta))
	f.close()
	return true


static func read_slot_meta(slot_id: int) -> Dictionary:
	var p := get_slot_path(slot_id)
	if not FileAccess.file_exists(p):
		return {}
	var txt := FileAccess.get_file_as_string(p)
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}
