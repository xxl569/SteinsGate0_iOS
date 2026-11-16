class_name UiPhoneRine
extends Control
## PC 1:1 复刻智能手机终端（桌面 / 電話通讯录 / RINE 聊天与18枚贴纸 / 设置 / 12张壁纸设置 / 7首来电铃声试听）

signal panel_toggled(opened: bool)
signal amadeus_action(accepted: bool)

enum PhoneScreen {
	HOME = 0,
	CONTACTS = 1,
	CHAT = 2,
	SETTINGS = 3,
	WALLPAPER = 4,
	RINGTONE = 5,
}

const RINGTONE_NAMES: Array[String] = [
	"Beginning of fight",
	"Village",
	"Easygoingness",
	"Precaution",
	"Over the sky",
	"Reunion",
	"GATE OF STEINER",
]

const CONTACT_DEFS: Array[Dictionary] = [
	{"id": 0, "name": "冈部 伦太郎", "status": "鳳凰院凶真 / LabMem001", "avatar": 0},
	{"id": 1, "name": "椎名 真由理", "status": "嘟嘟噜♪ LabMem002", "avatar": 1},
	{"id": 2, "name": "桥田 至 (桶子)", "status": "超级黑客 LabMem003", "avatar": 2},
	{"id": 3, "name": "牧濑 红莉栖 (Amadeus)", "status": "维克多·孔多利亚大学 AI", "avatar": 3},
	{"id": 4, "name": "桐生 萌郁", "status": "闪光的指压师", "avatar": 4},
	{"id": 5, "name": "漆原 琉华", "status": "柳林神社", "avatar": 5},
	{"id": 6, "name": "菲利斯·喵喵", "status": "MayQueen+Nyan2", "avatar": 6},
	{"id": 7, "name": "阿万音 铃羽", "status": "打工战士 LabMem008", "avatar": 7},
	{"id": 8, "name": "比屋定 真帆", "status": "维克多·孔多利亚研究员", "avatar": 8},
	{"id": 9, "name": "椎名 篝", "status": "未来之子", "avatar": 9},
	{"id": 10, "name": "阿万音 由季", "status": "Coser / 铃羽之母", "avatar": 10},
	{"id": 11, "name": "亚历克西斯·莱斯基宁", "status": "教授 / Shaman Girls", "avatar": 11},
]

# PHONE.DDS 内屏幕开孔区域 (x:118..572, y:124..918 -> 454x794)
const SCREEN_X := 118.0
const SCREEN_Y := 124.0
const SCREEN_W := 454.0
const SCREEN_H := 794.0
const TOP_BAR_H := 44.0
const NAV_BAR_H := 48.0
const BODY_H := 702.0 # 794 - 44 - 48

var _vfs: MgsVfs = null
var _vm: Sc3Vm = null
var _theme_loader: UiThemeLoader = null
var _audio: MgsAudioMgr = null
var _config: ConfigManager = null

var _drawer: Control = null
var _frame_tex: TextureRect = null
var _screen_root: Control = null
var _xp_bar_tex: TextureRect = null
var _hw_nav_tex: TextureRect = null
var _home_wallpaper: TextureRect = null
var _amadeus_logo: TextureRect = null
var _msg_list: VBoxContainer = null
var _msg_scroll: ScrollContainer = null
var _sticker_panel: PanelContainer = null
var _sticker_grid: GridContainer = null
var _status_label: Label = null
var _top_status_date: Label = null
var _chat_title_label: Label = null
var _connect_bar: HBoxContainer = null
var _rine_input_bg: TextureRect = null

var _screen_home: Control = null
var _screen_contacts: Control = null
var _screen_chat: Control = null
var _screen_settings: Control = null
var _screen_wallpaper: Control = null
var _screen_ringtone: Control = null

var _wp_preview_tex: TextureRect = null
var _wp_title_label: Label = null
var _wp_thumb_buttons: Array[Button] = []
var _ringtone_btns: Array[Button] = []
var _settings_wp_sub: Label = null
var _settings_rt_sub: Label = null

var _current_screen: int = PhoneScreen.HOME
var _screen_history: Array[int] = []
var _active_contact_idx: int = 1
var _is_open: bool = false
var _sticker_tray_visible: bool = false
var _tween: Tween = null

var _stickers: Array[Texture2D] = []
var _avatars: Array[Texture2D] = []
var _wallpapers: Array[Texture2D] = []
var _phone_assets: Dictionary = {}
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

	# 1. 手机红色外壳底图置于底层（注意：PHONE.DDS 屏幕区域是不透明黑色，绝不可盖在 _screen_root 上层）
	_frame_tex = TextureRect.new()
	_frame_tex.name = "PhoneCaseFrame"
	_frame_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_frame_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer.add_child(_frame_tex)

	# 2. 手机内屏裁剪容器严格对齐 PHONE.DDS 屏幕区域 (118, 124, 454, 794)
	_screen_root = Control.new()
	_screen_root.name = "PhoneScreenRoot"
	_screen_root.position = Vector2(SCREEN_X, SCREEN_Y)
	_screen_root.size = Vector2(SCREEN_W, SCREEN_H)
	_screen_root.clip_contents = true
	_screen_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_drawer.add_child(_screen_root)

	var base_bg := ColorRect.new()
	base_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	base_bg.color = Color(0.05, 0.07, 0.11, 1.0)
	_screen_root.add_child(base_bg)

	# 3. 顶部 PC 原版 XP 状态栏 (0..44)
	var top_bar := Control.new()
	top_bar.name = "XpStatusBar"
	top_bar.position = Vector2(0, 0)
	top_bar.size = Vector2(SCREEN_W, TOP_BAR_H)
	_screen_root.add_child(top_bar)

	_xp_bar_tex = TextureRect.new()
	_xp_bar_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_xp_bar_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_xp_bar_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_xp_bar_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(_xp_bar_tex)

	_top_status_date = Label.new()
	_top_status_date.position = Vector2(54, 10)
	_top_status_date.size = Vector2(180, 24)
	_top_status_date.add_theme_font_size_override("font_size", 14)
	_top_status_date.add_theme_color_override("font_color", Color(0.86, 0.92, 0.98, 0.95))
	top_bar.add_child(_top_status_date)

	_status_label = Label.new()
	_status_label.position = Vector2(210, 10)
	_status_label.size = Vector2(110, 24)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.text = "HOME"
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.98, 0.78, 0.34, 1.0))
	top_bar.add_child(_status_label)

	var btn_close := Button.new()
	btn_close.text = "收起"
	btn_close.position = Vector2(326, 6)
	btn_close.size = Vector2(54, 30)
	btn_close.focus_mode = Control.FOCUS_NONE
	btn_close.add_theme_font_size_override("font_size", 13)
	btn_close.add_theme_stylebox_override("normal", _make_flat_box(Color(0.18, 0.22, 0.30, 0.85), Color(0.75, 0.45, 0.20, 0.85), 6))
	btn_close.pressed.connect(close_phone)
	top_bar.add_child(btn_close)

	# 4. 6 个功能子页面 (y: 44..746 -> 454x702)
	_build_home_screen()
	_build_contacts_screen()
	_build_chat_screen()
	_build_settings_screen()
	_build_wallpaper_screen()
	_build_ringtone_screen()

	# 5. 底部 PC 原版硬件按键导航栏 (y: 746..794 -> 454x48)
	_build_bottom_nav_bar()

	# 确保顶栏在子页面之上
	_screen_root.move_child(top_bar, _screen_root.get_child_count() - 1)

	# 6. Amadeus 来电浮层（仅实际触发时显示）
	_amadeus_logo = TextureRect.new()
	_amadeus_logo.position = Vector2(165, 220)
	_amadeus_logo.size = Vector2(360, 180)
	_amadeus_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_amadeus_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_amadeus_logo.visible = false
	_drawer.add_child(_amadeus_logo)

	_connect_bar = HBoxContainer.new()
	_connect_bar.position = Vector2(145, 420)
	_connect_bar.size = Vector2(400, 48)
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

	switch_screen(PhoneScreen.HOME, false)


func _build_home_screen() -> void:
	_screen_home = Control.new()
	_screen_home.name = "ScreenHome"
	_screen_home.position = Vector2(0, TOP_BAR_H)
	_screen_home.size = Vector2(SCREEN_W, BODY_H)
	_screen_root.add_child(_screen_home)

	_home_wallpaper = TextureRect.new()
	_home_wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	_home_wallpaper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_home_wallpaper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_home_wallpaper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_home.add_child(_home_wallpaper)

	# 严格对齐 PC 视频 f_040.jpg：桌面左侧纵向排列 電話 / RINE / Amadeus / 設定 原版图标
	var col := VBoxContainer.new()
	col.name = "HomeAppColumn"
	col.position = Vector2(20, 22)
	col.size = Vector2(104, 520)
	col.add_theme_constant_override("separation", 18)
	_screen_home.add_child(col)

	var apps := [
		{"idx": 0, "title": "電話", "cb": Callable(self, "_open_contacts_app")},
		{"idx": 1, "title": "RINE", "cb": Callable(self, "_open_rine_app")},
		{"idx": 2, "title": "Amadeus", "cb": Callable(self, "_open_amadeus_app")},
		{"idx": 3, "title": "設定", "cb": Callable(self, "_open_settings_app")},
	]
	for item in apps:
		var idx: int = int(item["idx"])
		var btn := TextureButton.new()
		btn.name = "AppBtn_%s" % item["title"]
		btn.custom_minimum_size = Vector2(92, 114)
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(item["cb"])
		col.add_child(btn)


func _build_contacts_screen() -> void:
	_screen_contacts = Control.new()
	_screen_contacts.name = "ScreenContacts"
	_screen_contacts.position = Vector2(0, TOP_BAR_H)
	_screen_contacts.size = Vector2(SCREEN_W, BODY_H)
	_screen_contacts.visible = false
	_screen_root.add_child(_screen_contacts)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.10, 0.14, 1.0)
	_screen_contacts.add_child(bg)

	_add_subpage_header(_screen_contacts, "▶ 电话簿", func(): _go_back(), Color(0.14, 0.16, 0.21, 0.96))

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 48)
	scroll.size = Vector2(SCREEN_W, BODY_H - 48)
	_screen_contacts.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)

	for c in CONTACT_DEFS:
		var cid: int = int(c["id"])
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(SCREEN_W - 8, 66)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_stylebox_override("normal", _make_flat_box(Color(0.11, 0.13, 0.18, 0.95), Color(0.24, 0.30, 0.40, 0.5), 0))
		btn.add_theme_stylebox_override("hover", _make_flat_box(Color(0.16, 0.56, 0.92, 0.95), Color(0.35, 0.78, 1.0, 1.0), 0))
		btn.pressed.connect(func():
			_active_contact_idx = cid
			_refresh_chat_header()
			_append_text_msg(cid, "已切换至与 %s 的通讯频道。" % c["name"], false)
			switch_screen(PhoneScreen.CHAT)
		)

		var row := HBoxContainer.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.add_theme_constant_override("separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(row)

		var av := TextureRect.new()
		av.name = "ContactAvatar_%d" % cid
		av.custom_minimum_size = Vector2(54, 58)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(av)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(info)

		var name_lbl := Label.new()
		name_lbl.text = str(c["name"])
		name_lbl.add_theme_font_size_override("font_size", 20)
		name_lbl.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(name_lbl)

		var sub_lbl := Label.new()
		sub_lbl.text = str(c["status"])
		sub_lbl.add_theme_font_size_override("font_size", 13)
		sub_lbl.add_theme_color_override("font_color", Color(0.72, 0.80, 0.90, 1.0))
		sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(sub_lbl)

		list.add_child(btn)


func _build_chat_screen() -> void:
	_screen_chat = Control.new()
	_screen_chat.name = "ScreenChat"
	_screen_chat.position = Vector2(0, TOP_BAR_H)
	_screen_chat.size = Vector2(SCREEN_W, BODY_H)
	_screen_chat.visible = false
	_screen_root.add_child(_screen_chat)

	var bg_tex := TextureRect.new()
	bg_tex.name = "RineWallpaperTex"
	bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_chat.add_child(bg_tex)

	_chat_title_label = _add_subpage_header(_screen_chat, "RINE · 椎名 真由理", func(): _go_back(), Color(0.94, 0.96, 0.98, 0.92), Color(0.15, 0.22, 0.30, 1.0))

	_msg_scroll = ScrollContainer.new()
	_msg_scroll.position = Vector2(8, 52)
	_msg_scroll.size = Vector2(SCREEN_W - 16, BODY_H - 122)
	_screen_chat.add_child(_msg_scroll)

	_msg_list = VBoxContainer.new()
	_msg_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg_list.add_theme_constant_override("separation", 8)
	_msg_scroll.add_child(_msg_list)

	# 底部 PC 原版 RINE 栏（贴纸表情开关 + 快捷发送条）
	var input_bar := Control.new()
	input_bar.position = Vector2(0, BODY_H - 68)
	input_bar.size = Vector2(SCREEN_W, 68)
	_screen_chat.add_child(input_bar)

	_rine_input_bg = TextureRect.new()
	_rine_input_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rine_input_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rine_input_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_rine_input_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input_bar.add_child(_rine_input_bg)

	var btn_toggle_st := Button.new()
	btn_toggle_st.text = "贴纸"
	btn_toggle_st.position = Vector2(6, 12)
	btn_toggle_st.size = Vector2(56, 44)
	btn_toggle_st.flat = true
	btn_toggle_st.focus_mode = Control.FOCUS_NONE
	btn_toggle_st.add_theme_color_override("font_color", Color(0.25, 0.35, 0.45, 0.01))
	btn_toggle_st.pressed.connect(func():
		_sticker_tray_visible = not _sticker_tray_visible
		_sticker_panel.visible = _sticker_tray_visible
		_msg_scroll.size.y = (BODY_H - 302.0) if _sticker_tray_visible else (BODY_H - 122.0)
	)
	input_bar.add_child(btn_toggle_st)

	var btn_quick := Button.new()
	btn_quick.text = "发送回复：了解，我现在过去"
	btn_quick.position = Vector2(72, 14)
	btn_quick.size = Vector2(320, 40)
	btn_quick.flat = true
	btn_quick.focus_mode = Control.FOCUS_NONE
	btn_quick.add_theme_font_size_override("font_size", 16)
	btn_quick.add_theme_color_override("font_color", Color(0.22, 0.28, 0.36, 0.92))
	btn_quick.pressed.connect(func():
		_append_text_msg(0, "了解，我现在就去确认。", true)
	)
	input_bar.add_child(btn_quick)

	var btn_send := Button.new()
	btn_send.text = ""
	btn_send.position = Vector2(398, 12)
	btn_send.size = Vector2(50, 44)
	btn_send.flat = true
	btn_send.focus_mode = Control.FOCUS_NONE
	btn_send.pressed.connect(func():
		_append_text_msg(0, "没问题！稍后联络。", true)
	)
	input_bar.add_child(btn_send)

	# 底部 RINE 表情贴纸栏（18 枚，默认收起、点左下笑脸弹出）
	_sticker_panel = PanelContainer.new()
	_sticker_panel.position = Vector2(6, BODY_H - 246)
	_sticker_panel.size = Vector2(SCREEN_W - 12, 176)
	_sticker_panel.visible = false
	_sticker_panel.add_theme_stylebox_override("panel", UiThemeLoader.make_dark_panel_style(Color(0.08, 0.11, 0.18, 0.95), Color(0.35, 0.58, 0.85, 0.85)))
	_screen_chat.add_child(_sticker_panel)

	var st_scroll := ScrollContainer.new()
	st_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sticker_panel.add_child(st_scroll)

	_sticker_grid = GridContainer.new()
	_sticker_grid.columns = 5
	_sticker_grid.add_theme_constant_override("h_separation", 6)
	_sticker_grid.add_theme_constant_override("v_separation", 6)
	st_scroll.add_child(_sticker_grid)


func _build_settings_screen() -> void:
	_screen_settings = Control.new()
	_screen_settings.name = "ScreenSettings"
	_screen_settings.position = Vector2(0, TOP_BAR_H)
	_screen_settings.size = Vector2(SCREEN_W, BODY_H)
	_screen_settings.visible = false
	_screen_root.add_child(_screen_settings)

	var bg_tex := TextureRect.new()
	bg_tex.name = "SettingsBgTex"
	bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_tex.modulate = Color(0.28, 0.34, 0.45, 0.35)
	bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_settings.add_child(bg_tex)

	var dark_mask := ColorRect.new()
	dark_mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark_mask.color = Color(0.05, 0.07, 0.12, 0.82)
	dark_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_settings.add_child(dark_mask)

	_add_subpage_header(_screen_settings, "▶ 设定", func(): _go_back(), Color(0.14, 0.16, 0.21, 0.94))

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(10, 60)
	vbox.size = Vector2(SCREEN_W - 20, 420)
	vbox.add_theme_constant_override("separation", 10)
	_screen_settings.add_child(vbox)

	# 选项 1：壁纸设置
	var wp_btn := Button.new()
	wp_btn.name = "BtnWallpaperSetting"
	wp_btn.custom_minimum_size = Vector2(SCREEN_W - 20, 78)
	wp_btn.focus_mode = Control.FOCUS_NONE
	wp_btn.add_theme_stylebox_override("normal", _make_flat_box(Color(0.08, 0.10, 0.14, 0.84), Color(0.32, 0.44, 0.62, 0.7), 4))
	wp_btn.add_theme_stylebox_override("hover", _make_flat_box(Color(0.16, 0.56, 0.94, 0.92), Color(0.45, 0.85, 1.0, 0.95), 4))
	wp_btn.pressed.connect(func(): switch_screen(PhoneScreen.WALLPAPER))
	vbox.add_child(wp_btn)

	var wp_box := VBoxContainer.new()
	wp_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	wp_box.alignment = BoxContainer.ALIGNMENT_CENTER
	wp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wp_btn.add_child(wp_box)
	var wp_title := Label.new()
	wp_title.text = "  壁纸设置"
	wp_title.add_theme_font_size_override("font_size", 21)
	wp_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wp_box.add_child(wp_title)
	_settings_wp_sub = Label.new()
	_settings_wp_sub.text = "  壁纸 #01"
	_settings_wp_sub.add_theme_font_size_override("font_size", 14)
	_settings_wp_sub.add_theme_color_override("font_color", Color(0.75, 0.86, 0.98, 1.0))
	_settings_wp_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wp_box.add_child(_settings_wp_sub)

	# 选项 2：来电声音设置
	var rt_btn := Button.new()
	rt_btn.name = "BtnRingtoneSetting"
	rt_btn.custom_minimum_size = Vector2(SCREEN_W - 20, 78)
	rt_btn.focus_mode = Control.FOCUS_NONE
	rt_btn.add_theme_stylebox_override("normal", _make_flat_box(Color(0.08, 0.10, 0.14, 0.84), Color(0.32, 0.44, 0.62, 0.7), 4))
	rt_btn.add_theme_stylebox_override("hover", _make_flat_box(Color(0.16, 0.56, 0.94, 0.92), Color(0.45, 0.85, 1.0, 0.95), 4))
	rt_btn.pressed.connect(func(): switch_screen(PhoneScreen.RINGTONE))
	vbox.add_child(rt_btn)

	var rt_box := VBoxContainer.new()
	rt_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	rt_box.alignment = BoxContainer.ALIGNMENT_CENTER
	rt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt_btn.add_child(rt_box)
	var rt_title := Label.new()
	rt_title.text = "  来电声音设置"
	rt_title.add_theme_font_size_override("font_size", 21)
	rt_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt_box.add_child(rt_title)
	_settings_rt_sub = Label.new()
	_settings_rt_sub.text = "  Beginning of fight"
	_settings_rt_sub.add_theme_font_size_override("font_size", 14)
	_settings_rt_sub.add_theme_color_override("font_color", Color(0.75, 0.86, 0.98, 1.0))
	_settings_rt_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt_box.add_child(_settings_rt_sub)


func _build_wallpaper_screen() -> void:
	_screen_wallpaper = Control.new()
	_screen_wallpaper.name = "ScreenWallpaper"
	_screen_wallpaper.position = Vector2(0, TOP_BAR_H)
	_screen_wallpaper.size = Vector2(SCREEN_W, BODY_H)
	_screen_wallpaper.visible = false
	_screen_root.add_child(_screen_wallpaper)

	# 对齐 PC 视频 f_044.jpg：所选壁纸全屏铺满内屏预览，底部横向缩略图条切换
	_wp_preview_tex = TextureRect.new()
	_wp_preview_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wp_preview_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wp_preview_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_wp_preview_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_wallpaper.add_child(_wp_preview_tex)

	_wp_title_label = _add_subpage_header(_screen_wallpaper, "壁纸 01 / 12", func(): _go_back(), Color(0.06, 0.08, 0.14, 0.75))

	var tray := ColorRect.new()
	tray.position = Vector2(0, BODY_H - 166)
	tray.size = Vector2(SCREEN_W, 166)
	tray.color = Color(0.03, 0.05, 0.10, 0.65)
	_screen_wallpaper.add_child(tray)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, BODY_H - 156)
	scroll.size = Vector2(SCREEN_W - 16, 148)
	_screen_wallpaper.add_child(scroll)

	var hbox := HBoxContainer.new()
	hbox.name = "WallpaperThumbRow"
	hbox.add_theme_constant_override("separation", 8)
	scroll.add_child(hbox)

	_wp_thumb_buttons.clear()
	for i in range(12):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(86, 132)
		btn.expand_icon = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func(): select_wallpaper(i))
		hbox.add_child(btn)
		_wp_thumb_buttons.append(btn)


func _build_ringtone_screen() -> void:
	_screen_ringtone = Control.new()
	_screen_ringtone.name = "ScreenRingtone"
	_screen_ringtone.position = Vector2(0, TOP_BAR_H)
	_screen_ringtone.size = Vector2(SCREEN_W, BODY_H)
	_screen_ringtone.visible = false
	_screen_root.add_child(_screen_ringtone)

	var bg_tex := TextureRect.new()
	bg_tex.name = "RingtoneBgTex"
	bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_ringtone.add_child(bg_tex)

	var dark_mask := ColorRect.new()
	dark_mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark_mask.color = Color(0.05, 0.07, 0.12, 0.84)
	dark_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_ringtone.add_child(dark_mask)

	_add_subpage_header(_screen_ringtone, "▶ 来电声音设置", func(): _go_back(), Color(0.14, 0.16, 0.21, 0.94))

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(4, 52)
	scroll.size = Vector2(SCREEN_W - 8, BODY_H - 56)
	_screen_ringtone.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	_ringtone_btns.clear()
	for i in range(RINGTONE_NAMES.size()):
		var btn := Button.new()
		btn.name = "RingtoneBtn_%d" % i
		btn.custom_minimum_size = Vector2(SCREEN_W - 16, 60)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(func(): select_ringtone(i, true))
		vbox.add_child(btn)
		_ringtone_btns.append(btn)


func _build_bottom_nav_bar() -> void:
	var nav := Control.new()
	nav.name = "PhoneHardwareNav"
	nav.position = Vector2(0, SCREEN_H - NAV_BAR_H)
	nav.size = Vector2(SCREEN_W, NAV_BAR_H)
	_screen_root.add_child(nav)

	_hw_nav_tex = TextureRect.new()
	_hw_nav_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hw_nav_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hw_nav_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_hw_nav_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav.add_child(_hw_nav_tex)

	var third_w := SCREEN_W / 3.0
	var defs := [
		{"name": "NavHome", "x": 0.0, "cb": func(): switch_screen(PhoneScreen.HOME)},
		{"name": "NavRine", "x": third_w, "cb": func(): switch_screen(PhoneScreen.CHAT)},
		{"name": "NavBack", "x": third_w * 2.0, "cb": func(): _go_back()},
	]
	for d in defs:
		var btn := Button.new()
		btn.name = d["name"]
		btn.position = Vector2(float(d["x"]), 0.0)
		btn.size = Vector2(third_w, NAV_BAR_H)
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(d["cb"])
		nav.add_child(btn)


func _add_subpage_header(
	parent: Control,
	title: String,
	on_back: Callable,
	bg_col: Color = Color(0.11, 0.15, 0.24, 0.94),
	txt_col: Color = Color(0.96, 0.98, 1.0, 1.0)
) -> Label:
	var header := PanelContainer.new()
	header.position = Vector2(0, 0)
	header.size = Vector2(SCREEN_W, 44)
	header.add_theme_stylebox_override("panel", _make_flat_box(bg_col, Color(0.32, 0.48, 0.72, 0.45), 0))
	parent.add_child(header)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	header.add_child(hbox)

	var back_btn := Button.new()
	back_btn.text = " < 返回 "
	back_btn.custom_minimum_size = Vector2(72, 32)
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.add_theme_stylebox_override("normal", UiThemeLoader.make_button_style(false))
	back_btn.pressed.connect(on_back)
	hbox.add_child(back_btn)

	var lbl := Label.new()
	lbl.text = title
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", txt_col)
	hbox.add_child(lbl)
	return lbl


func setup(vfs: MgsVfs, vm: Sc3Vm, loader: UiThemeLoader, audio: MgsAudioMgr = null, cfg: ConfigManager = null) -> void:
	_vfs = vfs
	_vm = vm
	_theme_loader = loader
	_audio = audio
	_config = cfg
	_ensure_ui()

	if _theme_loader != null:
		_phone_assets = _theme_loader.get_phone_assets()
		if _phone_assets.get("phone_frame", null) != null:
			_frame_tex.texture = _phone_assets["phone_frame"] as Texture2D
		if _phone_assets.get("amadeus_logo", null) != null:
			_amadeus_logo.texture = _phone_assets["amadeus_logo"] as Texture2D
		if _phone_assets.get("xp_status_bar", null) != null and _xp_bar_tex != null:
			_xp_bar_tex.texture = _phone_assets["xp_status_bar"] as Texture2D
		if _phone_assets.get("hw_nav_bar", null) != null and _hw_nav_tex != null:
			_hw_nav_tex.texture = _phone_assets["hw_nav_bar"] as Texture2D

		var rine_bg: Texture2D = _phone_assets.get("rine_bg", null)
		if rine_bg != null and _screen_chat != null:
			var rtex := _screen_chat.get_node_or_null("RineWallpaperTex") as TextureRect
			if rtex != null:
				rtex.texture = rine_bg
		var rine_bar: Texture2D = _phone_assets.get("rine_input_bar", null)
		if rine_bar != null and _rine_input_bg != null:
			_rine_input_bg.texture = rine_bar
		var set_bg: Texture2D = _phone_assets.get("settings_bg", null)
		if set_bg != null and _screen_settings != null:
			var stex := _screen_settings.get_node_or_null("SettingsBgTex") as TextureRect
			if stex != null:
				stex.texture = set_bg
		var rt_bg: Texture2D = _phone_assets.get("ringtone_bg", null)
		if rt_bg != null and _screen_ringtone != null:
			var ttex := _screen_ringtone.get_node_or_null("RingtoneBgTex") as TextureRect
			if ttex != null:
				ttex.texture = rt_bg

		var app_icons: Array = _phone_assets.get("app_icons", [])
		var app_active: Array = _phone_assets.get("app_icons_active", [])
		var app_names := ["電話", "RINE", "Amadeus", "設定"]
		for i in range(4):
			var btn := _screen_home.find_child("AppBtn_%s" % app_names[i], true, false) as TextureButton
			if btn != null and i < app_icons.size() and app_icons[i] != null:
				btn.texture_normal = app_icons[i] as Texture2D
				if i < app_active.size() and app_active[i] != null:
					btn.texture_hover = app_active[i] as Texture2D
					btn.texture_pressed = app_active[i] as Texture2D

		var wp_arr: Array = _phone_assets.get("wallpapers", [])
		_wallpapers.clear()
		for item in wp_arr:
			_wallpapers.append(item as Texture2D)
		for i in range(mini(_wp_thumb_buttons.size(), _wallpapers.size())):
			if _wallpapers[i] != null:
				_wp_thumb_buttons[i].icon = _wallpapers[i]

		_stickers = _theme_loader.get_rine_stickers()
		_avatars = _theme_loader.get_rine_avatars()
		_populate_sticker_tray()
		_populate_contact_avatars()

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

	var saved_wp: int = _config.phone_wallpaper_idx if _config != null else 0
	var saved_rt: int = _config.phone_ringtone_idx if _config != null else 0
	select_wallpaper(saved_wp)
	select_ringtone(saved_rt, false)

	if _messages.is_empty():
		_append_text_msg(1, "嘟嘟噜♪ 真由理发来了一条问候！", false)
		if not _phone_offsets.is_empty():
			_append_sc3_msg(1, 0)


func _open_contacts_app() -> void:
	switch_screen(PhoneScreen.CONTACTS)


func _open_rine_app() -> void:
	switch_screen(PhoneScreen.CHAT)


func _open_amadeus_app() -> void:
	_active_contact_idx = 3
	_refresh_chat_header()
	switch_screen(PhoneScreen.CHAT)


func _open_settings_app() -> void:
	switch_screen(PhoneScreen.SETTINGS)


func _populate_contact_avatars() -> void:
	if _screen_contacts == null:
		return
	for c in CONTACT_DEFS:
		var cid: int = int(c["id"])
		var av_idx: int = int(c["avatar"])
		var av_node := _screen_contacts.find_child("ContactAvatar_%d" % cid, true, false) as TextureRect
		if av_node != null and av_idx >= 0 and av_idx < _avatars.size():
			av_node.texture = _avatars[av_idx]


func _populate_sticker_tray() -> void:
	for c in _sticker_grid.get_children():
		_sticker_grid.remove_child(c)
		c.queue_free()
	for i in range(_stickers.size()):
		var tex := _stickers[i]
		if tex == null:
			continue
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(76, 76)
		btn.icon = tex
		btn.expand_icon = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func(): _append_sticker_msg(i))
		_sticker_grid.add_child(btn)


func switch_screen(target: int, push_history: bool = true) -> void:
	_ensure_ui()
	if push_history and target != _current_screen:
		_screen_history.append(_current_screen)
		if _screen_history.size() > 16:
			_screen_history.pop_front()
	_current_screen = target
	_screen_home.visible = (target == PhoneScreen.HOME)
	_screen_contacts.visible = (target == PhoneScreen.CONTACTS)
	_screen_chat.visible = (target == PhoneScreen.CHAT)
	_screen_settings.visible = (target == PhoneScreen.SETTINGS)
	_screen_wallpaper.visible = (target == PhoneScreen.WALLPAPER)
	_screen_ringtone.visible = (target == PhoneScreen.RINGTONE)

	var names := ["HOME", "電話", "RINE", "設定", "壁纸", "铃声"]
	_status_label.text = names[clampi(target, 0, names.size() - 1)]


func _go_back() -> void:
	if _screen_history.is_empty():
		if _current_screen != PhoneScreen.HOME:
			switch_screen(PhoneScreen.HOME, false)
		else:
			close_phone()
		return
	var prev: int = _screen_history.pop_back()
	switch_screen(prev, false)


func select_wallpaper(idx: int) -> void:
	var clamped: int = clampi(idx, 0, maxi(0, _wallpapers.size() - 1))
	if _config != null and _config.phone_wallpaper_idx != clamped:
		_config.phone_wallpaper_idx = clamped
		_config.save_config()

	var tex: Texture2D = _wallpapers[clamped] if clamped < _wallpapers.size() else null
	if _home_wallpaper != null and tex != null:
		_home_wallpaper.texture = tex
	if _wp_preview_tex != null and tex != null:
		_wp_preview_tex.texture = tex
	if _wp_title_label != null:
		_wp_title_label.text = "壁纸 %02d / %02d" % [clamped + 1, maxi(1, _wallpapers.size())]
	if _settings_wp_sub != null:
		_settings_wp_sub.text = "  壁纸 #%02d" % [clamped + 1]
	for i in range(_wp_thumb_buttons.size()):
		var active := (i == clamped)
		_wp_thumb_buttons[i].add_theme_stylebox_override(
			"normal",
			_make_flat_box(Color(0.10, 0.14, 0.22, 0.9), Color(0.28, 0.76, 1.0, 1.0) if active else Color(0.32, 0.42, 0.56, 0.6), 4)
		)


func select_ringtone(idx: int, preview_audio: bool = true) -> void:
	var clamped: int = clampi(idx, 0, RINGTONE_NAMES.size() - 1)
	if _config != null and _config.phone_ringtone_idx != clamped:
		_config.phone_ringtone_idx = clamped
		_config.save_config()

	for i in range(_ringtone_btns.size()):
		var active := (i == clamped)
		var mark := "☑ " if active else "☐ "
		_ringtone_btns[i].text = "  %s%s" % [mark, RINGTONE_NAMES[i]]
		_ringtone_btns[i].add_theme_stylebox_override(
			"normal",
			_make_flat_box(
				Color(0.16, 0.54, 0.90, 0.92) if active else Color(0.08, 0.11, 0.16, 0.80),
				Color(0.45, 0.85, 1.0, 0.95) if active else Color(0.24, 0.34, 0.48, 0.6),
				2
			)
		)
	if _settings_rt_sub != null:
		_settings_rt_sub.text = "  %s" % RINGTONE_NAMES[clamped]

	if preview_audio and _audio != null:
		var se_name := "SGSE%d.ogg" % (700 + clamped)
		_audio.play_se_by_name(se_name, false)


func _refresh_chat_header() -> void:
	if _chat_title_label == null:
		return
	var idx := clampi(_active_contact_idx, 0, CONTACT_DEFS.size() - 1)
	_chat_title_label.text = "RINE · %s" % CONTACT_DEFS[idx]["name"]


func toggle_phone() -> void:
	if _is_open:
		close_phone()
	else:
		open_phone()


func open_phone() -> void:
	_ensure_ui()
	_sync_status_date()
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


func _sync_status_date() -> void:
	if _vm == null or _top_status_date == null:
		return
	var m: int = _vm.get_scr_work(12)
	var d: int = _vm.get_scr_work(13)
	if m >= 1 and d >= 1:
		_top_status_date.text = "%02d/%02d" % [m, d]
	else:
		_top_status_date.text = "LTE"


func _animate_x(target_x: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_drawer, "position:x", target_x, 0.25)


func _on_phone_event(subop: int, args: Array) -> void:
	# 序章 SG0_PhoneCtrl(5) / SG0_PhoneCtrl(10, 32) 为系统状态准备/隐藏，仅 subop=1 或 (subop=10 && args[0]==1) 为实际来电
	if subop == 1 or (subop == 10 and args.size() >= 1 and int(args[0]) == 1):
		_status_label.text = "Amadeus"
		_amadeus_logo.visible = _amadeus_logo.texture != null
		_connect_bar.visible = true
	elif subop == 255 or subop == 5:
		_amadeus_logo.visible = false
		_connect_bar.visible = false
		switch_screen(_current_screen, false)


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
	bubble.custom_minimum_size = Vector2(340, 56)
	bubble.add_theme_stylebox_override("panel", _make_flat_box(Color(0.95, 0.97, 0.99, 0.96), Color(0.60, 0.74, 0.88, 0.85), 10))

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(320, 44)
	bubble.add_child(holder)

	var fr := MgsFontRenderer.new()
	fr.bind_vfs(_vfs)
	fr.base_scale = 0.50
	fr.line_height = 28.0
	fr.max_line_width = 310.0
	fr.default_color = Color(0.10, 0.14, 0.20, 1.0)
	fr.shadow_offset = Vector2.ZERO
	holder.add_child(fr)
	fr.set_sc3_string(_phone_bytes, int(_phone_offsets[str_id]), _vm, null, true)
	var line_h_est := maxf(42.0, fr.get_content_size().y + 10.0)
	holder.custom_minimum_size = Vector2(320, line_h_est)
	bubble.custom_minimum_size = Vector2(340, line_h_est + 12.0)

	row.add_child(bubble)
	_msg_list.add_child(row)
	_messages.append({"type": "sc3", "str_id": str_id})
	_scroll_chat_to_bottom()


func _append_text_msg(avatar_idx: int, txt: String, is_self: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END if is_self else BoxContainer.ALIGNMENT_BEGIN
	if not is_self and avatar_idx >= 0 and avatar_idx < _avatars.size() and _avatars[avatar_idx] != null:
		var av := TextureRect.new()
		av.texture = _avatars[avatar_idx]
		av.custom_minimum_size = Vector2(44, 48)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(av)

	var bubble := PanelContainer.new()
	bubble.custom_minimum_size = Vector2(210, 42)
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not is_self else Control.SIZE_SHRINK_END
	var bg_col := Color(0.46, 0.82, 0.34, 0.96) if is_self else Color(0.95, 0.97, 0.99, 0.96)
	var bd_col := Color(0.32, 0.68, 0.22, 0.85) if is_self else Color(0.65, 0.78, 0.92, 0.85)
	bubble.add_theme_stylebox_override("panel", _make_flat_box(bg_col, bd_col, 10))

	var lbl := Label.new()
	lbl.text = txt
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(200, 24)
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", Color(0.08, 0.12, 0.18, 1.0))
	bubble.add_child(lbl)

	row.add_child(bubble)
	_msg_list.add_child(row)
	_messages.append({"type": "text", "text": txt, "self": is_self})
	_scroll_chat_to_bottom()


func _append_sticker_msg(sticker_idx: int) -> void:
	if sticker_idx < 0 or sticker_idx >= _stickers.size():
		return
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	var tr := TextureRect.new()
	tr.texture = _stickers[sticker_idx]
	tr.custom_minimum_size = Vector2(116, 116)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(tr)
	_msg_list.add_child(row)
	_messages.append({"type": "sticker", "idx": sticker_idx})
	_scroll_chat_to_bottom()


func _scroll_chat_to_bottom() -> void:
	if _msg_scroll != null and is_inside_tree():
		_msg_scroll.set_deferred("scroll_vertical", 999999)


static func _make_flat_box(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1 if border.a > 0.0 else 0)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb
