class_name UiPanels
extends Control
## MAGES. 主 UI 面板集合（标题画面 / 对话框与分支选项 / 历史回顾 / 存档读档 / 系统设置 / BYOA 引导）

signal new_game_requested()
signal continue_game_requested()
signal extra_requested(tab: int)
signal tips_requested()
signal advance_dialogue_requested()
signal choice_selected(index: int)
signal voice_replay_requested(voice_idx: int)
signal save_slot_requested(slot_id: int)
signal load_slot_requested(slot_id: int)
signal retry_byoa_requested()
signal config_applied()

const SAVE_DIR := "user://saves"
const NUM_SAVE_SLOTS := 12

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
var _meswin_accent: TextureRect = null
var _name_renderer: MgsFontRenderer = null
var _body_renderer: MgsFontRenderer = null
var _mode_badge: Label = null
var _wait_cursor: Label = null
var _choices_panel: PanelContainer = null
var _choices_box: VBoxContainer = null

var _modal_layer: Control = null
var _backlog_view: Control = null
var _backlog_bg: TextureRect = null
var _backlog_list: VBoxContainer = null

var _saveload_view: Control = null
var _saveload_bg: TextureRect = null
var _saveload_title: Label = null
var _saveload_grid: GridContainer = null
var _saveload_is_save: bool = true

var _config_view: Control = null
var _config_bg: TextureRect = null
var _slider_bgm: HSlider = null
var _slider_se: HSlider = null
var _slider_voice: HSlider = null
var _slider_speed: HSlider = null
var _chk_unread: CheckButton = null

var _byoa_view: Control = null
var _byoa_detail: Label = null

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

	_meswin_accent = TextureRect.new()
	_meswin_accent.position = Vector2(140, 756)
	_meswin_accent.size = Vector2(340, 36)
	_meswin_accent.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_meswin_accent.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_meswin_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_view.add_child(_meswin_accent)

	_name_renderer = MgsFontRenderer.new()
	_name_renderer.name = "SpeakerNameRenderer"
	_name_renderer.position = Vector2(180, 774)
	_name_renderer.base_scale = 0.76
	_name_renderer.default_color = Color(1.0, 0.78, 0.35)
	_dialogue_view.add_child(_name_renderer)

	_body_renderer = MgsFontRenderer.new()
	_body_renderer.name = "BodyTextRenderer"
	_body_renderer.position = Vector2(210, 826)
	_body_renderer.base_scale = 0.70
	_body_renderer.line_height = 50.0
	_body_renderer.max_line_width = 1480.0
	_dialogue_view.add_child(_body_renderer)

	_mode_badge = Label.new()
	_mode_badge.position = Vector2(1660, 780)
	_mode_badge.size = Vector2(210, 34)
	_mode_badge.add_theme_font_size_override("font_size", 20)
	_mode_badge.modulate = Color(1.0, 0.65, 0.18)
	_mode_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dialogue_view.add_child(_mode_badge)

	_wait_cursor = Label.new()
	_wait_cursor.text = "▼"
	_wait_cursor.position = Vector2(1720, 995)
	_wait_cursor.add_theme_font_size_override("font_size", 26)
	_wait_cursor.modulate = Color(1.0, 0.68, 0.22)
	_wait_cursor.visible = false
	_dialogue_view.add_child(_wait_cursor)

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

	# 1. Backlog 面板
	_backlog_view = Control.new()
	_backlog_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backlog_view.visible = false
	_modal_layer.add_child(_backlog_view)

	_backlog_bg = TextureRect.new()
	_backlog_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backlog_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_backlog_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_backlog_view.add_child(_backlog_bg)

	var bl_dim := ColorRect.new()
	bl_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	bl_dim.color = Color(0.03, 0.03, 0.05, 0.80)
	_backlog_view.add_child(bl_dim)

	var bl_hdr := _make_modal_header("历史对话记录 BACKLOG", func(): _backlog_view.visible = false)
	_backlog_view.add_child(bl_hdr)

	var bl_scroll := ScrollContainer.new()
	bl_scroll.position = Vector2(160, 110)
	bl_scroll.size = Vector2(1600, 910)
	_backlog_view.add_child(bl_scroll)

	_backlog_list = VBoxContainer.new()
	_backlog_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_backlog_list.add_theme_constant_override("separation", 10)
	bl_scroll.add_child(_backlog_list)

	# 2. Save / Load 面板
	_saveload_view = Control.new()
	_saveload_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_saveload_view.visible = false
	_modal_layer.add_child(_saveload_view)

	_saveload_bg = TextureRect.new()
	_saveload_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_saveload_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_saveload_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_saveload_view.add_child(_saveload_bg)

	var sl_dim := ColorRect.new()
	sl_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	sl_dim.color = Color(0.04, 0.04, 0.06, 0.78)
	_saveload_view.add_child(sl_dim)

	var sl_top := HBoxContainer.new()
	sl_top.position = Vector2(80, 34)
	sl_top.size = Vector2(1760, 56)
	_saveload_view.add_child(sl_top)
	_saveload_title = Label.new()
	_saveload_title.text = "存档 SAVE"
	_saveload_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_saveload_title.add_theme_font_size_override("font_size", 32)
	_saveload_title.modulate = Color(1.0, 0.65, 0.25)
	sl_top.add_child(_saveload_title)
	var sl_close := _make_small_btn("返回", func(): _saveload_view.visible = false)
	sl_top.add_child(sl_close)

	_saveload_grid = GridContainer.new()
	_saveload_grid.position = Vector2(80, 120)
	_saveload_grid.size = Vector2(1760, 880)
	_saveload_grid.columns = 3
	_saveload_grid.add_theme_constant_override("h_separation", 20)
	_saveload_grid.add_theme_constant_override("v_separation", 20)
	_saveload_view.add_child(_saveload_grid)

	# 3. Config 面板
	_config_view = Control.new()
	_config_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_config_view.visible = false
	_modal_layer.add_child(_config_view)

	_config_bg = TextureRect.new()
	_config_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_config_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_config_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_config_view.add_child(_config_bg)

	var cf_dim := ColorRect.new()
	cf_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	cf_dim.color = Color(0.03, 0.04, 0.06, 0.72)
	_config_view.add_child(cf_dim)

	_config_view.add_child(_make_modal_header("系统设置 CONFIG", func(): _config_view.visible = false))

	var cf_card := PanelContainer.new()
	cf_card.position = Vector2(420, 140)
	cf_card.size = Vector2(1080, 760)
	cf_card.add_theme_stylebox_override("panel", UiThemeLoader.make_dark_panel_style())
	_config_view.add_child(cf_card)

	var cf_box := VBoxContainer.new()
	cf_box.add_theme_constant_override("separation", 24)
	cf_card.add_child(cf_box)

	_slider_bgm = _add_slider_row(cf_box, "BGM 音乐音量", 0.0, 1.0, 0.05)
	_slider_se = _add_slider_row(cf_box, "SE 音效音量", 0.0, 1.0, 0.05)
	_slider_voice = _add_slider_row(cf_box, "角色语音音量", 0.0, 1.0, 0.05)
	_slider_speed = _add_slider_row(cf_box, "文字显示速度 (字/秒)", 20.0, 240.0, 10.0)

	_chk_unread = CheckButton.new()
	_chk_unread.text = "允许快进未读文本（调试/快速推进推荐）"
	_chk_unread.add_theme_font_size_override("font_size", 22)
	cf_box.add_child(_chk_unread)

	var btn_save_cfg := _make_menu_btn("保存并应用设置", func():
		if _cfg != null:
			_cfg.bgm_volume = _slider_bgm.value
			_cfg.se_volume = _slider_se.value
			_cfg.voice_volume = _slider_voice.value
			_cfg.text_speed = _slider_speed.value
			_cfg.skip_unread = _chk_unread.button_pressed
			_cfg.save_config()
			config_applied.emit()
		_config_view.visible = false
	)
	cf_box.add_child(btn_save_cfg)


func _build_byoa_view() -> void:
	_byoa_view = Control.new()
	_byoa_view.set_anchors_preset(Control.PRESET_FULL_RECT)
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


func _make_modal_header(title_txt: String, on_close: Callable) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.position = Vector2(80, 34)
	hb.size = Vector2(1760, 56)
	var lbl := Label.new()
	lbl.text = title_txt
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.modulate = Color(1.0, 0.65, 0.25)
	hb.add_child(lbl)
	hb.add_child(_make_small_btn("返回", on_close))
	return hb


func _make_small_btn(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(120, 46)
	b.add_theme_stylebox_override("normal", UiThemeLoader.make_button_style(true))
	b.add_theme_stylebox_override("hover", UiThemeLoader.make_button_style(false))
	b.pressed.connect(cb)
	return b


func _add_slider_row(parent: VBoxContainer, label_txt: String, min_v: float, max_v: float, step_v: float) -> HSlider:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	var lbl := Label.new()
	lbl.text = label_txt
	lbl.custom_minimum_size = Vector2(360, 42)
	lbl.add_theme_font_size_override("font_size", 22)
	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step_v
	sl.custom_minimum_size = Vector2(560, 42)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lbl)
	hb.add_child(sl)
	parent.add_child(hb)
	return sl


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
		if m_assets.get("accent", null) != null:
			_meswin_accent.texture = m_assets["accent"] as Texture2D
		var p_bgs := _theme_loader.get_panel_backdrops()
		if p_bgs.get("backlog", null) != null:
			_backlog_bg.texture = p_bgs["backlog"] as Texture2D
		if p_bgs.get("savemenu", null) != null:
			_saveload_bg.texture = p_bgs["savemenu"] as Texture2D
		if p_bgs.get("config", null) != null:
			_config_bg.texture = p_bgs["config"] as Texture2D


func _process(delta: float) -> void:
	_blink_t += delta
	if _dialogue_view != null and _dialogue_view.visible:
		var completed := _body_renderer.is_fully_revealed()
		if not completed:
			_body_renderer.step_reveal(delta)
		_wait_cursor.visible = completed and not _choices_panel.visible
		if _wait_cursor.visible:
			_wait_cursor.modulate.a = 0.55 + 0.45 * sin(_blink_t * 6.0)


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


func set_mode_badge(auto_on: bool, skip_on: bool) -> void:
	if _mode_badge == null:
		return
	if skip_on:
		_mode_badge.text = ">> SKIPPING"
	elif auto_on:
		_mode_badge.text = "● AUTO"
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
	var name_Arr := _body_renderer.get_name_glyphs()
	var gids := PackedInt32Array()
	for ng in name_Arr:
		gids.append(int(ng["gid"]))
	_name_renderer.set_glyph_list(gids, 0.76, Color(1.0, 0.78, 0.35))


func clear_dialogue_line() -> void:
	if _name_renderer != null:
		_name_renderer.clear_text()
	if _body_renderer != null:
		_body_renderer.clear_text()


func is_dialogue_reveal_done() -> bool:
	return _body_renderer == null or _body_renderer.is_fully_revealed()


func reveal_dialogue_instant() -> void:
	if _body_renderer != null:
		_body_renderer.reveal_all()


func show_choices(choices: Array) -> void:
	for c in _choices_box.get_children():
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


func open_backlog() -> void:
	for c in _backlog_list.get_children():
		c.queue_free()
	if _vm != null:
		var entries := _vm.backlog
		var start := maxi(0, entries.size() - 60)
		for i in range(start, entries.size()):
			var item: Dictionary = entries[i]
			var card := PanelContainer.new()
			card.custom_minimum_size = Vector2(1540, 84)
			card.add_theme_stylebox_override("panel", UiThemeLoader.make_dark_panel_style(Color(0.08, 0.09, 0.12, 0.88), Color(0.45, 0.32, 0.18, 0.7)))
			var hbox := HBoxContainer.new()
			hbox.add_theme_constant_override("separation", 12)
			card.add_child(hbox)

			var holder := Control.new()
			holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			holder.custom_minimum_size = Vector2(1340, 68)
			hbox.add_child(holder)

			var sname := str(item.get("script", ""))
			var off := int(item.get("str_offset", -1))
			if _vfs != null and _vfs.is_mounted and sname != "" and off >= 0:
				var sdata := _vfs.read_entry("script.mpk", sname)
				if not sdata.is_empty():
					var fr := MgsFontRenderer.new()
					fr.bind_vfs(_vfs)
					fr.base_scale = 0.56
					fr.line_height = 34.0
					fr.max_line_width = 1320.0
					holder.add_child(fr)
					fr.set_sc3_string(sdata, off, _vm, null, true)

			var vid := int(item.get("voice_id", -1))
			if vid > 0:
				var vbtn := _make_small_btn("▶ 语音", func(): voice_replay_requested.emit(vid))
				hbox.add_child(vbtn)

			_backlog_list.add_child(card)
	_backlog_view.visible = true


func open_saveload(is_save: bool) -> void:
	_saveload_is_save = is_save
	_saveload_title.text = "存档保存 SAVE DATA" if is_save else "读取存档 LOAD DATA"
	for c in _saveload_grid.get_children():
		c.queue_free()

	for slot_id in range(NUM_SAVE_SLOTS):
		var meta := read_slot_meta(slot_id)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(560, 190)
		btn.add_theme_stylebox_override("normal", UiThemeLoader.make_button_style(true))
		btn.add_theme_stylebox_override("hover", UiThemeLoader.make_button_style(false))
		if meta.is_empty():
			btn.text = "SLOT %02d\n\n— NO DATA —" % (slot_id + 1)
			if not is_save:
				btn.disabled = true
		else:
			btn.text = "SLOT %02d  [%s]\n%s\n%s" % [
				slot_id + 1,
				str(meta.get("script_name", "")),
				str(meta.get("timestamp", "")),
				str(meta.get("summary", "点击操作")),
			]
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(func():
			_saveload_view.visible = false
			if is_save:
				save_slot_requested.emit(slot_id)
			else:
				load_slot_requested.emit(slot_id)
		)
		_saveload_grid.add_child(btn)
	_saveload_view.visible = true


func open_config() -> void:
	if _cfg != null:
		_slider_bgm.value = _cfg.bgm_volume
		_slider_se.value = _cfg.se_volume
		_slider_voice.value = _cfg.voice_volume
		_slider_speed.value = _cfg.text_speed
		_chk_unread.button_pressed = _cfg.skip_unread
	_config_view.visible = true


func _on_dialogue_tap(event: InputEvent) -> void:
	if _ui_hidden:
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			toggle_hide_ui()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			advance_dialogue_requested.emit()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			advance_dialogue_requested.emit()


# ==================== 存档文件读写辅助 ====================

static func get_slot_path(slot_id: int) -> String:
	return "%s/slot_%02d.json" % [SAVE_DIR, slot_id]


func _has_any_save() -> bool:
	for s in range(NUM_SAVE_SLOTS):
		if FileAccess.file_exists(get_slot_path(s)):
			return true
	return FileAccess.file_exists(get_slot_path(99))


static func write_slot_data(slot_id: int, state: Dictionary, summary_text: String = "") -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var dt := Time.get_datetime_dict_from_system()
	var ts := "%04d/%02d/%02d %02d:%02d:%02d" % [
		int(dt["year"]), int(dt["month"]), int(dt["day"]),
		int(dt["hour"]), int(dt["minute"]), int(dt["second"]),
	]
	var payload := {
		"slot_id": slot_id,
		"timestamp": ts,
		"script_name": str(state.get("script_name", "")),
		"summary": summary_text,
		"vm_state": state,
	}
	var f := FileAccess.open(get_slot_path(slot_id), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(payload))
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
