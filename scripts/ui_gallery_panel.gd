class_name UiGalleryPanel
extends Control
## EXTRA 鉴赏模式面板（CG 鉴赏图库 + 全曲目 BGM 播放器 + 过场视频回放）

signal closed()

var _vfs: MgsVfs = null
var _audio: MgsAudioMgr = null
var _video: MgsVideoPlayer = null
var _cache: MgsCache = null
var _theme_loader: UiThemeLoader = null

var _bg_tex: TextureRect = null
var _tab_content: Control = null
var _cg_grid: GridContainer = null
var _list_box: VBoxContainer = null
var _cg_scroll: ScrollContainer = null
var _list_scroll: ScrollContainer = null
var _lightbox: ColorRect = null
var _lightbox_tex: TextureRect = null
var _info_label: Label = null

var _built: bool = false
var _active_tab: int = 0 # 0=CG, 1=BGM, 2=Movie


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func setup(vfs: MgsVfs, audio: MgsAudioMgr, video: MgsVideoPlayer, cache: MgsCache, loader: UiThemeLoader) -> void:
	_vfs = vfs
	_audio = audio
	_video = video
	_cache = cache
	_theme_loader = loader
	_ensure_ui()


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
	dimmer.color = Color(0.03, 0.04, 0.06, 0.78)
	add_child(dimmer)

	var top_bar := HBoxContainer.new()
	top_bar.position = Vector2(60, 32)
	top_bar.size = Vector2(1800, 56)
	top_bar.add_theme_constant_override("separation", 16)
	add_child(top_bar)

	var title := Label.new()
	title.text = "EXTRA 鉴赏模式"
	title.add_theme_font_size_override("font_size", 32)
	title.modulate = Color(1.0, 0.65, 0.25)
	top_bar.add_child(title)

	var btn_cg := _make_tab_btn("CG 图库", func(): _switch_tab(0))
	var btn_bgm := _make_tab_btn("音乐鉴赏 (BGM)", func(): _switch_tab(1))
	var btn_mov := _make_tab_btn("动画回放 (Movie)", func(): _switch_tab(2))
	top_bar.add_child(btn_cg)
	top_bar.add_child(btn_bgm)
	top_bar.add_child(btn_mov)

	_info_label = Label.new()
	_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_label.add_theme_font_size_override("font_size", 20)
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_bar.add_child(_info_label)

	var btn_close := _make_tab_btn("返回", close_panel)
	top_bar.add_child(btn_close)

	var panel := PanelContainer.new()
	panel.position = Vector2(60, 108)
	panel.size = Vector2(1800, 910)
	panel.add_theme_stylebox_override("panel", UiThemeLoader.make_dark_panel_style())
	add_child(panel)

	_tab_content = Control.new()
	_tab_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(_tab_content)

	_cg_scroll = ScrollContainer.new()
	_cg_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tab_content.add_child(_cg_scroll)

	_cg_grid = GridContainer.new()
	_cg_grid.columns = 5
	_cg_grid.add_theme_constant_override("h_separation", 14)
	_cg_grid.add_theme_constant_override("v_separation", 14)
	_cg_scroll.add_child(_cg_grid)

	_list_scroll = ScrollContainer.new()
	_list_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_list_scroll.visible = false
	_tab_content.add_child(_list_scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 8)
	_list_scroll.add_child(_list_box)

	# 全屏大图查看遮罩
	_lightbox = ColorRect.new()
	_lightbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lightbox.color = Color(0, 0, 0, 0.94)
	_lightbox.visible = false
	_lightbox.mouse_filter = Control.MOUSE_FILTER_STOP
	_lightbox.gui_input.connect(func(ev: InputEvent):
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			_lightbox.visible = false
	)
	add_child(_lightbox)

	_lightbox_tex = TextureRect.new()
	_lightbox_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lightbox_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lightbox_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lightbox_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lightbox.add_child(_lightbox_tex)


func _make_tab_btn(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(150, 46)
	b.add_theme_stylebox_override("normal", UiThemeLoader.make_button_style(true))
	b.add_theme_stylebox_override("hover", UiThemeLoader.make_button_style(false))
	b.pressed.connect(cb)
	return b


func open_panel(initial_tab: int = 0) -> void:
	_ensure_ui()
	if _theme_loader != null and _bg_tex.texture == null:
		var bgs := _theme_loader.get_panel_backdrops()
		if bgs.get("tips", null) != null:
			_bg_tex.texture = bgs["tips"] as Texture2D
	visible = true
	_switch_tab(initial_tab)


func close_panel() -> void:
	visible = false
	closed.emit()


func _switch_tab(tab_idx: int) -> void:
	_active_tab = tab_idx
	_cg_scroll.visible = (tab_idx == 0)
	_list_scroll.visible = (tab_idx != 0)
	if tab_idx == 0:
		_populate_cgs()
	elif tab_idx == 1:
		_populate_bgms()
	else:
		_populate_movies()


func _populate_cgs() -> void:
	for c in _cg_grid.get_children():
		c.queue_free()
	if _vfs == null or not _vfs.is_mounted:
		return
	var ev_names := _vfs.list_entries("bg.mpk", "EV")
	if ev_names.is_empty():
		ev_names = _vfs.list_entries("bg.mpk", "")
	var limit := mini(60, ev_names.size())
	_info_label.text = "CG 图库展示: %d / %d" % [limit, ev_names.size()]

	for i in range(limit):
		var entry_name: String = ev_names[i]
		var card := Button.new()
		card.custom_minimum_size = Vector2(336, 210)
		card.add_theme_stylebox_override("normal", UiThemeLoader.make_button_style(true))
		card.add_theme_stylebox_override("hover", UiThemeLoader.make_button_style(false))
		card.text = entry_name.get_basename()
		card.pressed.connect(func():
			var tex := _load_cg_tex(entry_name)
			if tex != null:
				_lightbox_tex.texture = tex
				_lightbox.visible = true
		)
		_cg_grid.add_child(card)


func _load_cg_tex(entry_name: String) -> Texture2D:
	var key := "gallery:" + entry_name
	if _cache != null and _cache.has_texture(key):
		return _cache.get_entry(key).get("texture", null) as Texture2D
	var tex := _vfs.decode_texture("bg.mpk", entry_name, false)
	if tex != null and _cache != null:
		_cache.put_texture(key, tex)
	return tex


func _populate_bgms() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	if _vfs == null or not _vfs.is_mounted:
		return
	var bgms := _vfs.list_entries("bgm.mpk", "")
	_info_label.text = "BGM 曲目共 %d 首" % bgms.size()
	for i in range(bgms.size()):
		var bname: String = bgms[i]
		var row := Button.new()
		row.custom_minimum_size = Vector2(1700, 48)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_stylebox_override("normal", UiThemeLoader.make_button_style(true))
		row.add_theme_stylebox_override("hover", UiThemeLoader.make_button_style(false))
		row.text = "  ♪ %02d. %s" % [i + 1, bname.get_basename()]
		row.pressed.connect(func():
			if _audio != null:
				_audio.play_bgm(i, true, 0)
				_info_label.text = "正在播放: " + bname
		)
		_list_box.add_child(row)


func _populate_movies() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	if _vfs == null:
		return
	var movies := _vfs.get_movie_names()
	_info_label.text = "过场动画 (.ogv) 共 %d 部" % movies.size()
	for i in range(movies.size()):
		var mname: String = movies[i]
		var row := Button.new()
		row.custom_minimum_size = Vector2(1700, 50)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_stylebox_override("normal", UiThemeLoader.make_button_style(true))
		row.add_theme_stylebox_override("hover", UiThemeLoader.make_button_style(false))
		row.text = "  ▶ %02d. %s" % [i + 1, mname]
		row.pressed.connect(func():
			if _video != null:
				_video.play_movie(i)
		)
		_list_box.add_child(row)
