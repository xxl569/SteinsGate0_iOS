class_name UiPhoneRine
extends Control
## PC 1:1 复刻智能手机终端（桌面 / 電話通讯录 / RINE 聊天与21枚贴纸 / 设置 / 12张壁纸设置 / 7首来电铃声试听）

signal panel_toggled(opened: bool)
signal amadeus_action(accepted: bool)
signal rine_reply_selected(str_id: int)
signal rine_sticker_selected(sticker_idx: int)
signal rine_read_ack()
signal unread_state_changed(has_unread: bool, unread_count: int)

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

# 头像索引严格对应 PHONE_RINE.DDS 左侧 12 行 (0..11)：
# 0=冈部 1=真由理 2=桶子 3=红莉栖 4=萌郁 5=琉华 6=菲莉丝 7=铃羽 8=真帆 9=由季 10=篝 11=默认剪影
const CONTACT_DEFS: Array[Dictionary] = [
	{"id": 0, "name": "冈部 伦太郎", "short": "伦太郎", "status": "鳳凰院凶真 / LabMem001", "avatar": 0, "in_phonebook": false, "default_unlocked": true},
	{"id": 1, "name": "真由理", "short": "真由理", "status": "嘟嘟噜♪ LabMem002", "avatar": 1, "in_phonebook": true, "default_unlocked": true},
	{"id": 2, "name": "桶子", "short": "桶子", "status": "超级黑客 LabMem003", "avatar": 2, "in_phonebook": true, "default_unlocked": true},
	{"id": 5, "name": "琉华子", "short": "琉华子", "status": "柳林神社", "avatar": 5, "in_phonebook": true, "default_unlocked": true},
	{"id": 7, "name": "铃羽", "short": "铃羽", "status": "打工战士 LabMem008", "avatar": 7, "in_phonebook": true, "default_unlocked": true},
	{"id": 6, "name": "菲莉丝", "short": "菲莉丝", "status": "MayQueen+Nyan2", "avatar": 6, "in_phonebook": true, "default_unlocked": true},
	{"id": 10, "name": "阿万音由季", "short": "阿万音由季", "status": "Coser / 铃羽之母", "avatar": 9, "in_phonebook": true, "default_unlocked": true},
	{"id": 3, "name": "牧濑 红莉栖 (Amadeus)", "short": "红莉栖 (Amadeus)", "status": "维克多·孔多利亚大学 AI", "avatar": 3, "in_phonebook": true, "default_unlocked": false},
	{"id": 8, "name": "比屋定 真帆", "short": "比屋定真帆", "status": "维克多·孔多利亚研究员", "avatar": 8, "in_phonebook": true, "default_unlocked": false},
	{"id": 4, "name": "桐生 萌郁", "short": "桐生萌郁", "status": "闪光的指压师", "avatar": 4, "in_phonebook": true, "default_unlocked": false},
	{"id": 9, "name": "椎名 篝", "short": "椎名篝", "status": "未来之子", "avatar": 10, "in_phonebook": true, "default_unlocked": false},
	{"id": 11, "name": "亚历克西斯·莱斯基宁", "short": "莱斯基宁", "status": "教授 / Shaman Girls", "avatar": 11, "in_phonebook": true, "default_unlocked": false},
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
var _amadeus_overlay: ColorRect = null
var _amadeus_logo: TextureRect = null
var _call_avatar_rect: TextureRect = null
var _call_title_lbl: Label = null
var _msg_list: VBoxContainer = null
var _msg_scroll: ScrollContainer = null
var _sticker_panel: PanelContainer = null
var _sticker_grid: GridContainer = null
var _reply_panel: PanelContainer = null
var _reply_list: VBoxContainer = null
var _quick_reply_btn: Button = null
var _btn_toggle_st: Button = null
var _btn_send: Button = null
var _btn_reply_prev: TextureButton = null
var _btn_reply_next: TextureButton = null
var _input_preview_clip: Control = null
var _input_preview_fr: MgsFontRenderer = null
var _contact_toast_lbl: Label = null
var _amadeus_btn: TextureButton = null
var _contact_btns: Dictionary = {} # cid -> Button
var _status_label: Label = null
var _top_status_date: Label = null
var _chat_title_label: Label = null
var _connect_bar: HBoxContainer = null
var _rine_header_bg: TextureRect = null
var _rine_input_bg: Panel = null
var _rine_emoji_tex: TextureRect = null
var _rine_send_tex: TextureRect = null

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
var _modal_blocked: bool = false
var _sticker_tray_visible: bool = false
var _tween: Tween = null

var _stickers: Array[Texture2D] = []
var _avatars: Array[Texture2D] = []
var _wallpapers: Array[Texture2D] = []
var _phone_assets: Dictionary = {}
var _phone_bytes: PackedByteArray = PackedByteArray()
var _phone_offsets: PackedInt32Array = PackedInt32Array()
var _messages: Array[Dictionary] = []
var _messages_by_contact: Dictionary = {} # cid -> Array[Dictionary]
var _unlocked_contacts: Dictionary = {0: true, 1: true, 2: true, 5: true, 6: true, 7: true, 10: true}
var _amadeus_unlocked: bool = false
var _reply_options: Array[int] = []
var _reply_mode: int = 0 # 0=文本回复选项, 1=贴纸回复选项 (sub=12 args[1])
var _reply_selected_idx: int = 0 # 文本回复模式下当前 < > 选中的候选索引
var _self_contact_id: int = 0 # sub=42 设置的己方视角ID (默认0=冈部伦太郎)
var _reply_tray_visible: bool = false
var _unread_by_contact: Dictionary = {} # cid -> int
var _has_unread_call: bool = false
var _home_rine_badge: PanelContainer = null
var _home_rine_badge_lbl: Label = null
var _contact_badges: Dictionary = {} # cid -> Label
var _badge_blink_tween: Tween = null


func _ready() -> void:
	name = "UiPhoneRine"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = true
	_ensure_ui()


func set_modal_blocked(blocked: bool) -> void:
	_modal_blocked = blocked


func _input(event: InputEvent) -> void:
	if not visible or not _is_open or _modal_blocked or _current_screen != PhoneScreen.CHAT:
		return
	if _amadeus_overlay != null and _amadeus_overlay.visible:
		return
	if _reply_mode == 0 and not _reply_options.is_empty() and event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			if ke.keycode == KEY_LEFT and _reply_options.size() > 1:
				_cycle_reply_option(-1)
				get_viewport().set_input_as_handled()
			elif ke.keycode == KEY_RIGHT and _reply_options.size() > 1:
				_cycle_reply_option(1)
				get_viewport().set_input_as_handled()
			elif ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER:
				_send_selected_text_reply()
				get_viewport().set_input_as_handled()


func _ensure_ui() -> void:
	if _drawer != null:
		return
	_drawer = Control.new()
	_drawer.name = "PhoneDrawer"
	# 缩放至 0.84 并在 y=940 处裁剪红框下缘，使屏幕与硬件按键完整落在对话金线 (y=762) 上方而不遮挡字幕
	_drawer.size = Vector2(620, 940)
	_drawer.scale = Vector2(0.84, 0.84)
	_drawer.position = Vector2(1920, -28) # 默认隐藏于右侧画面外
	_drawer.clip_contents = true
	_drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_drawer)

	# 1. 手机红色外壳底图置于底层（注意：PHONE.DDS 屏幕区域是不透明黑色，绝不可盖在 _screen_root 上层）
	_frame_tex = TextureRect.new()
	_frame_tex.name = "PhoneCaseFrame"
	_frame_tex.position = Vector2.ZERO
	_frame_tex.size = Vector2(620, 1080)
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
	_top_status_date.position = Vector2(96, 9)
	_top_status_date.size = Vector2(84, 26)
	_top_status_date.add_theme_font_size_override("font_size", 14)
	_top_status_date.add_theme_color_override("font_color", Color(0.86, 0.92, 0.98, 0.95))
	top_bar.add_child(_top_status_date)

	_status_label = Label.new()
	_status_label.position = Vector2(182, 9)
	_status_label.size = Vector2(126, 26)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.text = "HOME"
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.98, 0.78, 0.34, 1.0))
	top_bar.add_child(_status_label)

	var btn_close := Button.new()
	btn_close.text = "✕"
	btn_close.position = Vector2(314, 7)
	btn_close.size = Vector2(34, 28)
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

	# 6. Amadeus 来电浮层（带半透明遮罩防止底层电话簿/桌面文字透出与误触）
	_amadeus_overlay = ColorRect.new()
	_amadeus_overlay.name = "AmadeusCallOverlay"
	_amadeus_overlay.position = Vector2(SCREEN_X, SCREEN_Y + TOP_BAR_H)
	_amadeus_overlay.size = Vector2(SCREEN_W, BODY_H)
	_amadeus_overlay.color = Color(0.03, 0.05, 0.10, 0.94)
	_amadeus_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_amadeus_overlay.visible = false
	_drawer.add_child(_amadeus_overlay)

	_amadeus_logo = TextureRect.new()
	_amadeus_logo.position = Vector2((SCREEN_W - 360.0) * 0.5, 90.0)
	_amadeus_logo.size = Vector2(360, 180)
	_amadeus_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_amadeus_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_amadeus_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_amadeus_overlay.add_child(_amadeus_logo)

	_call_avatar_rect = TextureRect.new()
	_call_avatar_rect.name = "IncomingCallerAvatar"
	_call_avatar_rect.position = Vector2((SCREEN_W - 140.0) * 0.5, 110.0)
	_call_avatar_rect.size = Vector2(140, 140)
	_call_avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_call_avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_call_avatar_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_call_avatar_rect.visible = false
	_amadeus_overlay.add_child(_call_avatar_rect)

	_call_title_lbl = Label.new()
	_call_title_lbl.text = "Amadeus · 牧濑 红莉栖\n来电中..."
	_call_title_lbl.position = Vector2(20.0, 275.0)
	_call_title_lbl.size = Vector2(SCREEN_W - 40.0, 56.0)
	_call_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_call_title_lbl.add_theme_font_size_override("font_size", 19)
	_call_title_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55, 1.0))
	_amadeus_overlay.add_child(_call_title_lbl)

	_connect_bar = HBoxContainer.new()
	_connect_bar.position = Vector2((SCREEN_W - 400.0) * 0.5, 355.0)
	_connect_bar.size = Vector2(400, 48)
	_connect_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_connect_bar.add_theme_constant_override("separation", 18)
	_amadeus_overlay.add_child(_connect_bar)

	var btn_conn := Button.new()
	btn_conn.text = "接听 CONNECT"
	btn_conn.add_theme_stylebox_override("normal", UiThemeLoader.make_button_style(false))
	btn_conn.pressed.connect(func():
		_amadeus_overlay.visible = false
		_has_unread_call = false
		_stop_ringtone()
		_refresh_unread_badges()
		close_phone()
		amadeus_action.emit(true)
	)
	var btn_cancel := Button.new()
	btn_cancel.text = "挂断 CANCEL"
	btn_cancel.add_theme_stylebox_override("normal", UiThemeLoader.make_button_style(true))
	btn_cancel.pressed.connect(func():
		_amadeus_overlay.visible = false
		var keep_pending := (_vm != null and _vm.is_incoming_call_active())
		_has_unread_call = keep_pending
		_stop_ringtone()
		_refresh_unread_badges()
		close_phone()
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
		var btn := TextureButton.new()
		btn.name = "AppBtn_%s" % item["title"]
		btn.custom_minimum_size = Vector2(92, 114)
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(item["cb"])
		if str(item["title"]) == "Amadeus":
			_amadeus_btn = btn
			btn.visible = _amadeus_unlocked
		elif str(item["title"]) == "RINE":
			_home_rine_badge = PanelContainer.new()
			_home_rine_badge.name = "RineUnreadBadge"
			_home_rine_badge.position = Vector2(62, 2)
			_home_rine_badge.custom_minimum_size = Vector2(26, 26)
			_home_rine_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_home_rine_badge.visible = false
			_home_rine_badge.add_theme_stylebox_override("panel", _make_flat_box(Color(0.92, 0.16, 0.16, 0.98), Color(1.0, 0.85, 0.85, 0.95), 13))
			_home_rine_badge_lbl = Label.new()
			_home_rine_badge_lbl.text = "1"
			_home_rine_badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_home_rine_badge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_home_rine_badge_lbl.add_theme_font_size_override("font_size", 14)
			_home_rine_badge_lbl.add_theme_color_override("font_color", Color.WHITE)
			_home_rine_badge.add_child(_home_rine_badge_lbl)
			btn.add_child(_home_rine_badge)
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

	_contact_btns.clear()
	_contact_badges.clear()
	for c in CONTACT_DEFS:
		if not bool(c.get("in_phonebook", true)):
			continue
		var cid: int = int(c["id"])
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(SCREEN_W - 8, 66)
		btn.focus_mode = Control.FOCUS_NONE
		btn.visible = bool(_unlocked_contacts.get(cid, bool(c.get("default_unlocked", false))))
		btn.add_theme_stylebox_override("normal", _make_flat_box(Color(0.11, 0.13, 0.18, 0.95), Color(0.24, 0.30, 0.40, 0.5), 0))
		btn.add_theme_stylebox_override("hover", _make_flat_box(Color(0.16, 0.56, 0.92, 0.95), Color(0.35, 0.78, 1.0, 1.0), 0))
		btn.pressed.connect(func(): _on_contact_pressed(cid, str(c.get("short", c["name"]))))

		var row := HBoxContainer.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.add_theme_constant_override("separation", 14)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(row)

		var av := TextureRect.new()
		av.name = "ContactAvatar_%d" % cid
		av.custom_minimum_size = Vector2(54, 54)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(av)

		var name_lbl := Label.new()
		name_lbl.text = str(c.get("short", c["name"]))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 22)
		name_lbl.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_lbl)

		var badge_lbl := Label.new()
		badge_lbl.name = "ContactUnread_%d" % cid
		badge_lbl.custom_minimum_size = Vector2(28, 24)
		badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge_lbl.add_theme_font_size_override("font_size", 14)
		badge_lbl.add_theme_color_override("font_color", Color.WHITE)
		badge_lbl.add_theme_stylebox_override("normal", _make_flat_box(Color(0.92, 0.16, 0.16, 0.98), Color(1.0, 0.85, 0.85, 0.9), 12))
		badge_lbl.visible = false
		badge_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(badge_lbl)
		_contact_badges[cid] = badge_lbl

		list.add_child(btn)
		_contact_btns[cid] = btn

	_contact_toast_lbl = Label.new()
	_contact_toast_lbl.position = Vector2(20, BODY_H - 52)
	_contact_toast_lbl.size = Vector2(SCREEN_W - 40, 36)
	_contact_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_contact_toast_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_contact_toast_lbl.visible = false
	_contact_toast_lbl.add_theme_font_size_override("font_size", 16)
	_contact_toast_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65, 1.0))
	_contact_toast_lbl.add_theme_stylebox_override("normal", _make_flat_box(Color(0.05, 0.08, 0.14, 0.92), Color(0.45, 0.65, 0.90, 0.8), 6))
	_screen_contacts.add_child(_contact_toast_lbl)


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

	_rine_header_bg = TextureRect.new()
	_rine_header_bg.position = Vector2(0, 0)
	_rine_header_bg.size = Vector2(SCREEN_W, 46)
	_rine_header_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rine_header_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_rine_header_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_chat.add_child(_rine_header_bg)

	_chat_title_label = _add_subpage_header(_screen_chat, "RINE · 椎名 真由理", func(): _go_back(), Color(0.94, 0.96, 0.98, 0.72), Color(0.15, 0.22, 0.30, 1.0))

	_msg_scroll = ScrollContainer.new()
	_msg_scroll.position = Vector2(8, 52)
	_msg_scroll.size = Vector2(SCREEN_W - 16, BODY_H - 122)
	_screen_chat.add_child(_msg_scroll)

	_msg_list = VBoxContainer.new()
	_msg_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg_list.add_theme_constant_override("separation", 8)
	_msg_scroll.add_child(_msg_list)

	# 底部 PC 原版 RINE 输入栏（左：桶子贴纸按钮，中：白底胶囊输入条，右：发送箭头）
	var input_bar := Control.new()
	input_bar.position = Vector2(0, BODY_H - 68)
	input_bar.size = Vector2(SCREEN_W, 68)
	_screen_chat.add_child(input_bar)

	var bar_plate := ColorRect.new()
	bar_plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_plate.color = Color(0.84, 0.87, 0.92, 0.98)
	bar_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input_bar.add_child(bar_plate)

	_rine_emoji_tex = TextureRect.new()
	_rine_emoji_tex.position = Vector2(10, 13)
	_rine_emoji_tex.size = Vector2(40, 40)
	_rine_emoji_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rine_emoji_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rine_emoji_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input_bar.add_child(_rine_emoji_tex)

	_rine_input_bg = Panel.new()
	_rine_input_bg.name = "RineInputBg"
	_rine_input_bg.position = Vector2(56, 8)
	_rine_input_bg.size = Vector2(342, 52)
	_rine_input_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rine_input_bg.add_theme_stylebox_override("panel", _make_flat_box(Color(0.92, 0.94, 0.96, 1.0), Color(0.73, 0.77, 0.83, 1.0), 8))
	input_bar.add_child(_rine_input_bg)

	_rine_send_tex = TextureRect.new()
	_rine_send_tex.position = Vector2(410, 18)
	_rine_send_tex.size = Vector2(30, 32)
	_rine_send_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rine_send_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rine_send_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input_bar.add_child(_rine_send_tex)

	_btn_toggle_st = Button.new()
	_btn_toggle_st.name = "BtnStickerToggle"
	_btn_toggle_st.text = ""
	_btn_toggle_st.position = Vector2(4, 10)
	_btn_toggle_st.size = Vector2(50, 48)
	_btn_toggle_st.flat = true
	_btn_toggle_st.focus_mode = Control.FOCUS_NONE
	_btn_toggle_st.pressed.connect(func():
		# PC 原版仅在“贴纸回复分支”(reply_mode==1 且有候选贴纸) 时打开候选贴纸栏，避免无回复时段误导为“只能发表情”
		if _reply_mode == 1 and not _reply_options.is_empty():
			_toggle_sticker_tray()
	)
	input_bar.add_child(_btn_toggle_st)

	_btn_reply_prev = TextureButton.new()
	_btn_reply_prev.name = "BtnReplyPrev"
	_btn_reply_prev.position = Vector2(54, 13)
	_btn_reply_prev.size = Vector2(28, 42)
	_btn_reply_prev.ignore_texture_size = true
	_btn_reply_prev.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_btn_reply_prev.focus_mode = Control.FOCUS_NONE
	_btn_reply_prev.visible = false
	_btn_reply_prev.pressed.connect(func(): _cycle_reply_option(-1))
	input_bar.add_child(_btn_reply_prev)

	_input_preview_clip = Control.new()
	_input_preview_clip.name = "InputPreviewClip"
	_input_preview_clip.position = Vector2(96, 10)
	_input_preview_clip.size = Vector2(260, 48)
	_input_preview_clip.clip_contents = true
	_input_preview_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_input_preview_clip.visible = false
	input_bar.add_child(_input_preview_clip)

	_input_preview_fr = MgsFontRenderer.new()
	_input_preview_fr.position = Vector2(2, 12)
	_input_preview_fr.base_scale = 0.46
	_input_preview_fr.line_height = 22.0
	_input_preview_fr.max_line_width = 256.0
	_input_preview_fr.default_color = Color(0.08, 0.14, 0.22, 1.0)
	_input_preview_fr.shadow_offset = Vector2.ZERO
	_input_preview_fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_input_preview_clip.add_child(_input_preview_fr)

	_quick_reply_btn = Button.new()
	_quick_reply_btn.name = "BtnQuickReply"
	_quick_reply_btn.text = "当前无需回复"
	_quick_reply_btn.position = Vector2(76, 14)
	_quick_reply_btn.size = Vector2(304, 40)
	_quick_reply_btn.flat = true
	_quick_reply_btn.focus_mode = Control.FOCUS_NONE
	_quick_reply_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_quick_reply_btn.add_theme_font_size_override("font_size", 15)
	_quick_reply_btn.add_theme_color_override("font_color", Color(0.16, 0.24, 0.36, 0.95))
	_quick_reply_btn.add_theme_color_override("font_hover_color", Color(0.10, 0.38, 0.76, 1.0))
	_quick_reply_btn.add_theme_color_override("font_disabled_color", Color(0.42, 0.48, 0.56, 0.85))
	_quick_reply_btn.pressed.connect(func():
		if _reply_mode == 1 and not _reply_options.is_empty():
			_toggle_sticker_tray()
		else:
			_toggle_reply_tray()
	)
	input_bar.add_child(_quick_reply_btn)

	_btn_reply_next = TextureButton.new()
	_btn_reply_next.name = "BtnReplyNext"
	_btn_reply_next.position = Vector2(370, 13)
	_btn_reply_next.size = Vector2(28, 42)
	_btn_reply_next.ignore_texture_size = true
	_btn_reply_next.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_btn_reply_next.focus_mode = Control.FOCUS_NONE
	_btn_reply_next.visible = false
	_btn_reply_next.pressed.connect(func(): _cycle_reply_option(1))
	input_bar.add_child(_btn_reply_next)

	_btn_send = Button.new()
	_btn_send.name = "BtnRineSend"
	_btn_send.text = ""
	_btn_send.position = Vector2(400, 10)
	_btn_send.size = Vector2(50, 48)
	_btn_send.flat = true
	_btn_send.focus_mode = Control.FOCUS_NONE
	_btn_send.pressed.connect(func():
		if _reply_options.is_empty():
			return
		if _reply_mode == 1:
			_toggle_sticker_tray()
		else:
			_send_selected_text_reply()
	)
	input_bar.add_child(_btn_send)

	# 底部 RINE 表情贴纸栏（21 枚，默认收起、点左下笑脸弹出）
	_sticker_panel = PanelContainer.new()
	_sticker_panel.position = Vector2(6, BODY_H - 246)
	_sticker_panel.size = Vector2(SCREEN_W - 12, 176)
	_sticker_panel.visible = false
	_sticker_panel.add_theme_stylebox_override("panel", UiThemeLoader.make_dark_panel_style(Color(0.08, 0.11, 0.18, 0.95), Color(0.35, 0.58, 0.85, 0.85)))
	_screen_chat.add_child(_sticker_panel)

	var st_scroll := ScrollContainer.new()
	st_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	st_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sticker_panel.add_child(st_scroll)

	var st_center := CenterContainer.new()
	st_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	st_scroll.add_child(st_center)

	_sticker_grid = GridContainer.new()
	_sticker_grid.columns = 5
	_sticker_grid.add_theme_constant_override("h_separation", 6)
	_sticker_grid.add_theme_constant_override("v_separation", 6)
	st_center.add_child(_sticker_grid)

	# 底部 RINE 候选回复选择面板（仅当 _reply_options 非空时弹出真实 SC3 回复选项）
	_reply_panel = PanelContainer.new()
	_reply_panel.position = Vector2(6, BODY_H - 246)
	_reply_panel.size = Vector2(SCREEN_W - 12, 176)
	_reply_panel.visible = false
	_reply_panel.add_theme_stylebox_override("panel", UiThemeLoader.make_dark_panel_style(Color(0.94, 0.96, 0.99, 0.98), Color(0.25, 0.55, 0.88, 0.9)))
	_screen_chat.add_child(_reply_panel)

	var rp_scroll := ScrollContainer.new()
	rp_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	rp_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_reply_panel.add_child(rp_scroll)

	_reply_list = VBoxContainer.new()
	_reply_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reply_list.add_theme_constant_override("separation", 6)
	rp_scroll.add_child(_reply_list)


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

	# 对齐 PC 视频 f_044.jpg：壁纸全屏铺满内屏，顶部半透极简返回与编号，底部清爽横向缩略图条
	_wp_preview_tex = TextureRect.new()
	_wp_preview_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wp_preview_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wp_preview_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_wp_preview_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_wallpaper.add_child(_wp_preview_tex)

	_wp_title_label = _add_subpage_header(_screen_wallpaper, "壁纸 01 / 12", func(): _go_back(), Color(0.03, 0.05, 0.10, 0.36))

	var tray := ColorRect.new()
	tray.position = Vector2(0, BODY_H - 128)
	tray.size = Vector2(SCREEN_W, 128)
	tray.color = Color(0.02, 0.04, 0.08, 0.35)
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_wallpaper.add_child(tray)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, BODY_H - 120)
	scroll.size = Vector2(SCREEN_W - 16, 114)
	_screen_wallpaper.add_child(scroll)

	var hbox := HBoxContainer.new()
	hbox.name = "WallpaperThumbRow"
	hbox.add_theme_constant_override("separation", 6)
	scroll.add_child(hbox)

	_wp_thumb_buttons.clear()
	for i in range(12):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(72, 108)
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
		{"name": "NavRine", "x": third_w, "cb": func(): _open_rine_app()},
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
		var rine_hdr: Texture2D = _phone_assets.get("rine_header_bar", null)
		if rine_hdr != null and _rine_header_bg != null:
			_rine_header_bg.texture = rine_hdr
		var rine_em: Texture2D = _phone_assets.get("rine_emoji", null)
		if rine_em != null and _rine_emoji_tex != null:
			_rine_emoji_tex.texture = rine_em
		var rine_sa: Texture2D = _phone_assets.get("rine_send_arrow", null)
		if rine_sa != null and _rine_send_tex != null:
			_rine_send_tex.texture = rine_sa
		var al_norm: Texture2D = _phone_assets.get("rine_arrow_left", null)
		var al_act: Texture2D = _phone_assets.get("rine_arrow_left_active", null)
		if _btn_reply_prev != null and al_norm != null:
			_btn_reply_prev.texture_normal = al_norm
			if al_act != null:
				_btn_reply_prev.texture_hover = al_act
				_btn_reply_prev.texture_pressed = al_act
		var ar_norm: Texture2D = _phone_assets.get("rine_arrow_right", null)
		var ar_act: Texture2D = _phone_assets.get("rine_arrow_right_active", null)
		if _btn_reply_next != null and ar_norm != null:
			_btn_reply_next.texture_normal = ar_norm
			if ar_act != null:
				_btn_reply_next.texture_hover = ar_act
				_btn_reply_next.texture_pressed = ar_act
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
	if _input_preview_fr != null and _vfs != null:
		_input_preview_fr.bind_vfs(_vfs)
	_refresh_reply_prompt()

	if _vm != null:
		if not _vm.phone_event.is_connected(_on_phone_event):
			_vm.phone_event.connect(_on_phone_event)
		if not _vm.rine_event.is_connected(_on_rine_event):
			_vm.rine_event.connect(_on_rine_event)

	var saved_wp: int = _config.phone_wallpaper_idx if _config != null else 0
	var saved_rt: int = _config.phone_ringtone_idx if _config != null else 0
	select_wallpaper(saved_wp)
	select_ringtone(saved_rt, false)


func _open_contacts_app() -> void:
	if _is_incoming_call_active():
		_show_incoming_call_overlay(true)
		return
	switch_screen(PhoneScreen.CONTACTS)


func _open_rine_app() -> void:
	# 对齐 Game.exe 0x44e9d8：当 Flag(2748)!=0 且未处于 RINE 聊天时，点击 RINE 触发推进分支
	if _vm != null and _vm.get_flag(2748) != 0 and _vm.get_scr_work(6656) == 0 and _vm.get_flag(2620) == 0:
		close_phone()
		amadeus_action.emit(true)
		return
	_ensure_best_rine_contact()
	_refresh_chat_header()
	switch_screen(PhoneScreen.CHAT)


func _ensure_best_rine_contact() -> void:
	# 优先切换到当前有未读消息的对方联系人，避免停留在 0(伦太郎自己) 或空频道
	if _active_contact_idx > 0 and int(_unread_by_contact.get(_active_contact_idx, 0)) > 0:
		return
	for cid_var in _unread_by_contact.keys():
		var cid := int(cid_var)
		if cid > 0 and int(_unread_by_contact[cid]) > 0:
			_active_contact_idx = cid
			return
	# 若当前联系人无消息或为 0，切换到最近有消息记录的非己方联系人
	var cur_msgs: Array = _messages_by_contact.get(_active_contact_idx, [])
	if _active_contact_idx <= 0 or cur_msgs.is_empty():
		for cid_var in _messages_by_contact.keys():
			var cid := int(cid_var)
			var arr: Array = _messages_by_contact[cid]
			if cid > 0 and not arr.is_empty():
				_active_contact_idx = cid
				return
		if _active_contact_idx <= 0:
			_active_contact_idx = 1


func _is_incoming_call_active() -> bool:
	if _vm != null:
		if _vm.get_flag(2620) != 0:
			return false
		if _vm.is_incoming_call_active():
			return true
		if _vm.get_flag(2750) != 0 or _vm.get_flag(2748) != 0:
			return false
	return _has_unread_call or (_amadeus_overlay != null and _amadeus_overlay.visible)


func _update_incoming_call_display() -> bool:
	var is_amadeus := (_vm == null) or (_vm.get_flag(2743) != 0) or (_vm.get_flag(2740) == 0)
	if is_amadeus:
		if _amadeus_logo != null:
			_amadeus_logo.visible = true
		if _call_avatar_rect != null:
			_call_avatar_rect.visible = false
		if _call_title_lbl != null:
			_call_title_lbl.text = "Amadeus · 牧濑 红莉栖\n来电中..."
		if _status_label != null:
			_status_label.text = "Amadeus"
	else:
		var caller_cid := _vm.get_scr_work(6613)
		var cdef := _get_contact_def(caller_cid if caller_cid > 0 else 1)
		var cname := str(cdef.get("name", "来电"))
		var av_idx := int(cdef.get("avatar", 11))
		if _amadeus_logo != null:
			_amadeus_logo.visible = false
		if _call_avatar_rect != null:
			var av_tex := _avatars[av_idx] if (av_idx >= 0 and av_idx < _avatars.size()) else null
			_call_avatar_rect.texture = av_tex
			_call_avatar_rect.visible = (av_tex != null)
		if _call_title_lbl != null:
			_call_title_lbl.text = "%s\n来电中..." % cname
		if _status_label != null:
			_status_label.text = "電話"
	return is_amadeus


func _show_incoming_call_overlay(ensure_ringtone: bool = true) -> void:
	_ensure_ui()
	var is_amadeus := _update_incoming_call_display()
	if is_amadeus:
		unlock_amadeus()
	if _amadeus_overlay != null:
		_amadeus_overlay.visible = true
	if ensure_ringtone:
		_play_ringtone()


func _open_amadeus_app() -> void:
	# 若当前正处于未接/响铃中的来电阶段，点击 Amadeus 图标直接弹出接听/挂断来电界面
	if _is_incoming_call_active():
		_show_incoming_call_overlay(true)
		return
	# 对齐 Game.exe 0x44ea33：当 Flag(2750)!=0 且 Flag(2613)==0 时，点击 Amadeus 主动发起呼叫并推进剧情
	if _vm != null and _vm.get_flag(2750) != 0 and _vm.get_flag(2613) == 0 and _vm.get_flag(2620) == 0:
		close_phone()
		amadeus_action.emit(true)
		return
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
	if _sticker_grid == null:
		return
	for c in _sticker_grid.get_children():
		_sticker_grid.remove_child(c)
		c.queue_free()
	var indices: Array[int] = []
	var is_mode1_pick := (_reply_mode == 1 and not _reply_options.is_empty())
	if is_mode1_pick:
		for rid in _reply_options:
			var sidx := int(rid)
			if sidx >= 0 and sidx < _stickers.size() and not indices.has(sidx):
				indices.append(sidx)
		_sticker_grid.columns = clampi(indices.size(), 1, 3)
		_sticker_grid.add_theme_constant_override("h_separation", 10)
	else:
		for i in range(_stickers.size()):
			indices.append(i)
		_sticker_grid.columns = 5
		_sticker_grid.add_theme_constant_override("h_separation", 6)

	for sidx in indices:
		var tex := _stickers[sidx]
		if tex == null:
			continue
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(132, 120) if is_mode1_pick else Vector2(76, 66)
		btn.text = ""
		btn.focus_mode = Control.FOCUS_NONE
		if is_mode1_pick:
			btn.add_theme_stylebox_override("normal", _make_flat_box(Color(0.16, 0.24, 0.36, 0.92), Color(0.45, 0.72, 0.98, 0.9), 8))
			btn.add_theme_stylebox_override("hover", _make_flat_box(Color(0.24, 0.42, 0.68, 0.96), Color(0.75, 0.90, 1.0, 1.0), 8))
		# 使用内置 TextureRect 按 202:174 原图比例居中显示，避免 Button.icon 在方形槽位中被横向挤压
		var icon_tr := TextureRect.new()
		icon_tr.texture = tex
		icon_tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon_tr.offset_left = 6
		icon_tr.offset_top = 6
		icon_tr.offset_right = -6
		icon_tr.offset_bottom = -6
		icon_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(icon_tr)
		var chosen_idx := sidx
		btn.pressed.connect(func():
			var self_av := _get_contact_avatar_idx(_self_contact_id)
			_append_sticker_msg(chosen_idx, true, true, self_av)
			if _reply_mode == 1 and not _reply_options.is_empty():
				_reply_options.clear()
				_reply_mode = 0
				_reply_selected_idx = 0
				_sticker_tray_visible = false
				if _sticker_panel != null:
					_sticker_panel.visible = false
				_populate_sticker_tray()
				_refresh_reply_prompt()
			rine_sticker_selected.emit(chosen_idx)
		)
		_sticker_grid.add_child(btn)


func _has_contact(cid: int) -> bool:
	for c in CONTACT_DEFS:
		if int(c["id"]) == cid:
			return true
	return false


func _get_contact_def(cid: int) -> Dictionary:
	for c in CONTACT_DEFS:
		if int(c["id"]) == cid:
			return c
	return CONTACT_DEFS[1]


func _get_contact_avatar_idx(cid: int) -> int:
	var c := _get_contact_def(cid)
	return int(c.get("avatar", 11))


func _on_contact_pressed(cid: int, short_name: String) -> void:
	if _contact_toast_lbl == null:
		return
	_contact_toast_lbl.text = "%s：当前非通话时段" % short_name
	_contact_toast_lbl.visible = true
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_callback(func():
		if is_instance_valid(_contact_toast_lbl):
			_contact_toast_lbl.visible = false
	)
	# 同步记录目标联系人以便进入 RINE 时可查看对应频道
	_active_contact_idx = cid


func _refresh_contacts_visibility() -> void:
	for cid in _contact_btns.keys():
		var btn := _contact_btns[cid] as Button
		if is_instance_valid(btn):
			btn.visible = bool(_unlocked_contacts.get(int(cid), false))
	if _amadeus_btn != null:
		_amadeus_btn.visible = _amadeus_unlocked


func unlock_contact(cid: int) -> void:
	_unlocked_contacts[cid] = true
	_refresh_contacts_visibility()


func unlock_amadeus() -> void:
	_amadeus_unlocked = true
	unlock_contact(3)
	_refresh_contacts_visibility()


func _play_ringtone() -> void:
	if _audio == null:
		return
	var rt_idx: int = _config.phone_ringtone_idx if _config != null else 0
	var se_name := "SGSE%d.ogg" % (700 + clampi(rt_idx, 0, RINGTONE_NAMES.size() - 1))
	if not _audio.is_se_playing(se_name):
		_audio.play_se_by_name(se_name, true)


func _stop_ringtone() -> void:
	if _audio == null:
		return
	if _audio.has_method("stop_se_by_prefix"):
		_audio.stop_se_by_prefix("SGSE7")
	elif _audio.has_method("stop_all_se"):
		_audio.stop_all_se()
	elif _audio.has_method("stop_se"):
		_audio.stop_se(-1)


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
	if _amadeus_overlay != null and _amadeus_overlay.visible:
		_update_incoming_call_display()
	else:
		_status_label.text = names[clampi(target, 0, names.size() - 1)]
	if target == PhoneScreen.CHAT:
		if _active_contact_idx <= 0:
			_active_contact_idx = 1
		_refresh_chat_header()
		_clear_contact_unread(_active_contact_idx)
		if _reply_mode == 1 and not _reply_options.is_empty():
			_populate_sticker_tray()
			_sticker_tray_visible = true
		_refresh_reply_prompt()
		_scroll_chat_to_bottom()


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
	var c := _get_contact_def(_active_contact_idx)
	_chat_title_label.text = "RINE · %s" % str(c.get("short", c["name"]))
	_rebuild_chat_for_active_contact()


func _update_msg_scroll_height() -> void:
	if _msg_scroll == null:
		return
	var tray_open := _reply_tray_visible or _sticker_tray_visible
	_msg_scroll.size.y = (BODY_H - 302.0) if tray_open else (BODY_H - 122.0)


func _refresh_reply_prompt() -> void:
	if _quick_reply_btn == null:
		return
	if _reply_options.is_empty():
		_reply_selected_idx = 0
		_reply_tray_visible = false
		_sticker_tray_visible = false
		if _reply_panel != null:
			_reply_panel.visible = false
		if _sticker_panel != null:
			_sticker_panel.visible = false
		if _btn_reply_prev != null:
			_btn_reply_prev.visible = false
		if _btn_reply_next != null:
			_btn_reply_next.visible = false
		if _input_preview_clip != null:
			_input_preview_clip.visible = false
		if _rine_input_bg != null:
			_rine_input_bg.position = Vector2(56, 8)
			_rine_input_bg.size = Vector2(342, 52)
		_quick_reply_btn.position = Vector2(68, 14)
		_quick_reply_btn.size = Vector2(318, 40)
		_quick_reply_btn.text = "当前无需回复"
		_quick_reply_btn.disabled = true
		if _btn_toggle_st != null:
			_btn_toggle_st.disabled = true
		if _rine_emoji_tex != null:
			_rine_emoji_tex.modulate = Color(1.0, 1.0, 1.0, 0.42)
		if _btn_send != null:
			_btn_send.disabled = true
		if _rine_send_tex != null:
			_rine_send_tex.modulate = Color(1.0, 1.0, 1.0, 0.42)
	elif _reply_mode == 1:
		_reply_selected_idx = 0
		_reply_tray_visible = false
		if _reply_panel != null:
			_reply_panel.visible = false
		if _sticker_panel != null:
			_sticker_panel.visible = _sticker_tray_visible
		if _btn_reply_prev != null:
			_btn_reply_prev.visible = false
		if _btn_reply_next != null:
			_btn_reply_next.visible = false
		if _input_preview_clip != null:
			_input_preview_clip.visible = false
		if _rine_input_bg != null:
			_rine_input_bg.position = Vector2(56, 8)
			_rine_input_bg.size = Vector2(342, 52)
		_quick_reply_btn.position = Vector2(68, 14)
		_quick_reply_btn.size = Vector2(318, 40)
		_quick_reply_btn.text = "请选择上方表情贴纸回复 (%d)..." % _reply_options.size()
		_quick_reply_btn.disabled = false
		if _btn_toggle_st != null:
			_btn_toggle_st.disabled = false
		if _rine_emoji_tex != null:
			_rine_emoji_tex.modulate = Color(1.0, 1.0, 1.0, 1.0)
		if _btn_send != null:
			_btn_send.disabled = false
		if _rine_send_tex != null:
			_rine_send_tex.modulate = Color(1.0, 1.0, 1.0, 0.55)
	else:
		# PC 原版文本回复模式：白底输入框内直接预览当前候选文本，左右 < > 箭头置于输入框两侧切换，右侧发送箭头直接发送
		_reply_selected_idx = clampi(_reply_selected_idx, 0, _reply_options.size() - 1)
		_sticker_tray_visible = false
		if _sticker_panel != null:
			_sticker_panel.visible = false
		var show_arrows := _reply_options.size() > 1
		if _btn_reply_prev != null:
			_btn_reply_prev.visible = show_arrows
		if _btn_reply_next != null:
			_btn_reply_next.visible = show_arrows
		if _rine_input_bg != null:
			_rine_input_bg.position = Vector2(84, 8) if show_arrows else Vector2(56, 8)
			_rine_input_bg.size = Vector2(284, 52) if show_arrows else Vector2(342, 52)
		var preview_x := 96.0 if show_arrows else 68.0
		var preview_w := 260.0 if show_arrows else 318.0
		if _input_preview_clip != null:
			_input_preview_clip.position = Vector2(preview_x, 10.0)
			_input_preview_clip.size = Vector2(preview_w, 48.0)
			_input_preview_clip.visible = true
		_quick_reply_btn.position = Vector2(preview_x, 10.0)
		_quick_reply_btn.size = Vector2(preview_w, 48.0)
		_quick_reply_btn.text = ""
		_quick_reply_btn.disabled = false
		if _input_preview_fr != null:
			_input_preview_fr.max_line_width = preview_w - 4.0
			if _vfs != null:
				_input_preview_fr.bind_vfs(_vfs)
			var cur_opt_id := int(_reply_options[_reply_selected_idx])
			if not _phone_bytes.is_empty() and cur_opt_id >= 0 and cur_opt_id < _phone_offsets.size():
				_input_preview_fr.set_sc3_string(_phone_bytes, int(_phone_offsets[cur_opt_id]), _vm, null, true)
				var ch := _input_preview_fr.get_content_size().y
				_input_preview_fr.position = Vector2(2.0, 12.0 if ch <= 24.0 else 2.0)
			else:
				_quick_reply_btn.text = "点击选择回复 (%d/%d)" % [_reply_selected_idx + 1, _reply_options.size()]
				if _input_preview_clip != null:
					_input_preview_clip.visible = false
		if _btn_toggle_st != null:
			_btn_toggle_st.disabled = true
		if _rine_emoji_tex != null:
			_rine_emoji_tex.modulate = Color(1.0, 1.0, 1.0, 0.42)
		if _btn_send != null:
			_btn_send.disabled = false
		if _rine_send_tex != null:
			_rine_send_tex.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_update_msg_scroll_height()


func _cycle_reply_option(delta: int) -> void:
	if _reply_mode != 0 or _reply_options.is_empty():
		return
	_reply_selected_idx = posmod(_reply_selected_idx + delta, _reply_options.size())
	_refresh_reply_prompt()
	if _reply_tray_visible:
		_rebuild_reply_list()


func _send_selected_text_reply() -> void:
	if _reply_mode != 0 or _reply_options.is_empty():
		return
	var idx := clampi(_reply_selected_idx, 0, _reply_options.size() - 1)
	var opt_id := int(_reply_options[idx])
	_send_text_reply_option(opt_id)


func _send_text_reply_option(opt_id: int) -> void:
	_reply_options.clear()
	_reply_selected_idx = 0
	_reply_tray_visible = false
	_sticker_tray_visible = false
	if _reply_panel != null:
		_reply_panel.visible = false
	if _sticker_panel != null:
		_sticker_panel.visible = false
	var self_av := _get_contact_avatar_idx(_self_contact_id)
	_append_sc3_msg(self_av, opt_id, true)
	_refresh_reply_prompt()
	rine_reply_selected.emit(opt_id)


func _toggle_sticker_tray() -> void:
	if _reply_mode != 1 or _reply_options.is_empty():
		return
	_sticker_tray_visible = not _sticker_tray_visible
	if _sticker_tray_visible:
		_reply_tray_visible = false
		if _reply_panel != null:
			_reply_panel.visible = false
		_populate_sticker_tray()
	if _sticker_panel != null:
		_sticker_panel.visible = _sticker_tray_visible
	_update_msg_scroll_height()
	if _sticker_tray_visible:
		_scroll_chat_to_bottom()


func _toggle_reply_tray() -> void:
	if _reply_options.is_empty():
		return
	if _reply_mode == 1:
		_toggle_sticker_tray()
		return
	_reply_tray_visible = not _reply_tray_visible
	if _reply_tray_visible:
		_sticker_tray_visible = false
		if _sticker_panel != null:
			_sticker_panel.visible = false
		_rebuild_reply_list()
	if _reply_panel != null:
		_reply_panel.visible = _reply_tray_visible
	_update_msg_scroll_height()
	if _reply_tray_visible:
		_scroll_chat_to_bottom()


func _rebuild_reply_list() -> void:
	if _reply_list == null:
		return
	for c in _reply_list.get_children():
		_reply_list.remove_child(c)
		c.queue_free()
	for idx in range(_reply_options.size()):
		var opt_id := int(_reply_options[idx])
		if _phone_bytes.is_empty() or opt_id < 0 or opt_id >= _phone_offsets.size():
			continue
		var is_cur := (idx == _reply_selected_idx)
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 48)
		btn.focus_mode = Control.FOCUS_NONE
		var norm_bg := Color(0.76, 0.90, 1.0, 1.0) if is_cur else Color(0.88, 0.94, 0.99, 1.0)
		var norm_bd := Color(0.14, 0.48, 0.88, 1.0) if is_cur else Color(0.32, 0.62, 0.92, 0.9)
		btn.add_theme_stylebox_override("normal", _make_flat_box(norm_bg, norm_bd, 6))
		btn.add_theme_stylebox_override("hover", _make_flat_box(Color(0.24, 0.62, 0.96, 1.0), Color(0.10, 0.45, 0.85, 1.0), 6))
		var holder := Control.new()
		holder.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(holder)
		var fr := MgsFontRenderer.new()
		fr.bind_vfs(_vfs)
		fr.position = Vector2(10, 6)
		fr.base_scale = 0.50
		fr.line_height = 26.0
		fr.max_line_width = SCREEN_W - 64.0
		fr.default_color = Color(0.08, 0.14, 0.22, 1.0)
		fr.shadow_offset = Vector2.ZERO
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(fr)
		fr.set_sc3_string(_phone_bytes, int(_phone_offsets[opt_id]), _vm, null, true)
		var h_est := maxf(46.0, fr.get_content_size().y + 14.0)
		btn.custom_minimum_size = Vector2(0, h_est)
		var chosen_opt := opt_id
		btn.pressed.connect(func():
			_send_text_reply_option(chosen_opt)
		)
		_reply_list.add_child(btn)


func toggle_phone() -> void:
	if _is_open:
		close_phone()
	else:
		open_phone()


func open_phone() -> void:
	_ensure_ui()
	_sync_status_date()
	_is_open = true
	if _vm != null:
		_vm.set_flag(2603, 0)
		_vm.set_flag(2604, 0)
		_vm.set_flag(2617, 0)
		if _vm.get_flag(2750) != 0 and _vm.get_flag(2613) == 0:
			unlock_amadeus()
	if _is_incoming_call_active():
		_has_unread_call = true
		_show_incoming_call_overlay(true)
		_refresh_unread_badges()
	else:
		if _amadeus_overlay != null:
			_amadeus_overlay.visible = false
		if _current_screen == PhoneScreen.CHAT:
			_clear_contact_unread(_active_contact_idx)
	_animate_x(1340.0)
	panel_toggled.emit(true)


func close_phone() -> void:
	_ensure_ui()
	_is_open = false
	_stop_ringtone()
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
	# 真正来电由 VM 在 Flag(2699) & (Flag(2743) | Flag(2740)) 激活时发出 subop=20；
	# subop=23 为主动呼叫 Amadeus (2750) 或 RINE 分支触发 (2748)，仅解锁桌面图标而绝不弹来电遮罩；
	# subop=1 仅保留给无 arg0 过滤的旧测试/外部直呼（VM 正常运行时 PhoneCtrl(1) args 为空）
	var arg0: int = int(args[0]) if args.size() >= 1 else -1
	if subop == 23:
		if arg0 == 2750:
			unlock_amadeus()
		return
	var is_real_call: bool = (
		subop == 20
		or subop == 21
		or (subop == 1 and (arg0 == 1 or arg0 >= 180))
	)
	if is_real_call:
		_has_unread_call = true
		_show_incoming_call_overlay(true)
		_refresh_unread_badges()
	elif subop == 255 or subop == 5 or subop == 3:
		if _amadeus_overlay != null:
			_amadeus_overlay.visible = false
		_has_unread_call = (_vm != null and _vm.is_incoming_call_active())
		_stop_ringtone()
		_refresh_unread_badges()
		switch_screen(_current_screen, false)


func _on_rine_event(subop: int, args: Array) -> void:
	# 依据 Game.exe (0x4619b0 / 0x4543c0) 与 _rndrine.scx 实测字节码:
	# 0x00 = RINE 会话初始化
	# 0x0a (10) = 启动 _rndrine.scx 子解释器标签
	# 0x0b (11) = 结束本轮 RINE 回复
	# 0x0c (12) = 设置本轮回复关联参数与回复模式 (args[0]=ScrWork[1501], args[1]=0文本/1贴纸；非联系人ID！)
	# 0x0d (13) = 注册单条可回复项 (args[0]=_phone.scx 字符串ID 或 贴纸ID, args[1]=分支标签序号)
	# 0x0e (14) = 挂起等待玩家回复
	# 0x0f (15) / 0x2e (46) = 追加聊天消息 (args[0]=0己方/>0对方角色ID, args[1]=0文本/1贴纸, args[2]=payload_id)
	# 0x2a (42) = 设置己方视角角色ID (默认0=冈部伦太郎)
	# 0x2b (43) / 0x2c (44) = 将联系人加入当前聊天成员列表并激活对话窗口
	if subop == 0:
		return
	elif subop == 10:
		if not (_is_open and _current_screen == PhoneScreen.CHAT):
			_ensure_best_rine_contact()
			if _active_contact_idx > 0:
				_unread_by_contact[_active_contact_idx] = maxi(1, int(_unread_by_contact.get(_active_contact_idx, 0)))
				_refresh_unread_badges()
	elif subop == 11 or subop == 40 or subop == 47:
		_reply_options.clear()
		_reply_mode = 0
		_reply_selected_idx = 0
		_populate_sticker_tray()
		_refresh_reply_prompt()
		_refresh_unread_badges()
	elif subop == 12:
		_reply_mode = int(args[1]) if args.size() >= 2 else 0
		_reply_options.clear()
		_reply_selected_idx = 0
		_reply_tray_visible = false
		_sticker_tray_visible = false
		_refresh_reply_prompt()
	elif subop == 42:
		if args.size() >= 1:
			_self_contact_id = int(args[0])
	elif subop == 43 or subop == 44:
		if args.size() > 0:
			var raw_cid := int(args[0])
			if raw_cid != _self_contact_id and raw_cid > 0 and _has_contact(raw_cid):
				_active_contact_idx = raw_cid
				unlock_contact(_active_contact_idx)
				_refresh_chat_header()
	elif subop == 13:
		if args.size() >= 1:
			var opt_id := int(args[0])
			if _reply_mode == 1:
				if opt_id >= 0 and opt_id < _stickers.size() and not _reply_options.has(opt_id):
					_reply_options.append(opt_id)
			else:
				if opt_id > 0 and opt_id < _phone_offsets.size() and not _reply_options.has(opt_id):
					_reply_options.append(opt_id)
		if _reply_mode == 1 and not _reply_options.is_empty():
			_populate_sticker_tray()
		_refresh_reply_prompt()
	elif subop == 14:
		if _reply_mode == 1 and not _reply_options.is_empty():
			_populate_sticker_tray()
			_sticker_tray_visible = true
		_refresh_reply_prompt()
		if _sticker_tray_visible:
			_scroll_chat_to_bottom()
	elif subop == 15 or subop == 46:
		var side_or_cid := int(args[0]) if args.size() > 0 else 1
		var msg_type := int(args[1]) if args.size() > 1 else 0
		var payload_id := int(args[2]) if args.size() > 2 else -1
		var is_self := (side_or_cid == _self_contact_id)
		if not is_self and side_or_cid > 0 and _has_contact(side_or_cid):
			if _active_contact_idx != side_or_cid:
				_active_contact_idx = side_or_cid
				_refresh_chat_header()
		if _active_contact_idx <= 0:
			_active_contact_idx = 1
			_refresh_chat_header()
		unlock_contact(_active_contact_idx)
		var sender_cid := side_or_cid if (not is_self and side_or_cid >= 0 and _has_contact(side_or_cid)) else _active_contact_idx
		var av_idx := _get_contact_avatar_idx(_self_contact_id) if is_self else _get_contact_avatar_idx(sender_cid)
		var appended := false
		if msg_type == 1:
			if payload_id >= 0 and payload_id < _stickers.size():
				_append_sticker_msg(payload_id, is_self, true, av_idx)
				appended = true
		else:
			if payload_id >= 0 and payload_id < _phone_offsets.size():
				_append_sc3_msg(av_idx, payload_id, is_self)
				appended = true
		if appended and not is_self:
			# 播放 PC 原版 RINE 新消息通知音 SE10_07.ogg (se.mpk 索引 252)
			if _audio != null:
				_audio.play_se(252, false)
			if _is_open and _current_screen == PhoneScreen.CHAT:
				_clear_contact_unread(_active_contact_idx)
			else:
				_unread_by_contact[_active_contact_idx] = int(_unread_by_contact.get(_active_contact_idx, 0)) + 1
				_refresh_unread_badges()


func _append_sc3_msg(avatar_idx: int, str_id: int, is_self: bool = false, record: bool = true) -> void:
	if _phone_bytes.is_empty() or str_id < 0 or str_id >= _phone_offsets.size():
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END if is_self else BoxContainer.ALIGNMENT_BEGIN
	if not is_self and avatar_idx >= 0 and avatar_idx < _avatars.size() and _avatars[avatar_idx] != null:
		var av := TextureRect.new()
		av.texture = _avatars[avatar_idx]
		av.custom_minimum_size = Vector2(44, 44)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(av)

	var bubble := PanelContainer.new()
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_END if is_self else Control.SIZE_EXPAND_FILL
	bubble.custom_minimum_size = Vector2(280, 56) if is_self else Vector2(340, 56)
	var bg_col := Color(0.46, 0.82, 0.34, 0.96) if is_self else Color(0.95, 0.97, 0.99, 0.96)
	var bd_col := Color(0.32, 0.68, 0.22, 0.85) if is_self else Color(0.60, 0.74, 0.88, 0.85)
	bubble.add_theme_stylebox_override("panel", _make_flat_box(bg_col, bd_col, 10))

	var holder := Control.new()
	var max_w := 260.0 if is_self else 320.0
	holder.custom_minimum_size = Vector2(max_w, 44)
	bubble.add_child(holder)

	var fr := MgsFontRenderer.new()
	fr.bind_vfs(_vfs)
	fr.base_scale = 0.56
	fr.line_height = 30.0
	fr.max_line_width = max_w - 10.0
	fr.default_color = Color(0.08, 0.12, 0.18, 1.0)
	fr.shadow_offset = Vector2.ZERO
	holder.add_child(fr)
	fr.set_sc3_string(_phone_bytes, int(_phone_offsets[str_id]), _vm, null, true)
	var line_h_est := maxf(42.0, fr.get_content_size().y + 10.0)
	holder.custom_minimum_size = Vector2(max_w, line_h_est)
	bubble.custom_minimum_size = Vector2(max_w + 20.0, line_h_est + 12.0)

	row.add_child(bubble)
	_msg_list.add_child(row)
	if record:
		_record_msg({"type": "sc3", "str_id": str_id, "self": is_self, "avatar_idx": avatar_idx})
	_scroll_chat_to_bottom()


func _append_text_msg(avatar_idx: int, txt: String, is_self: bool, record: bool = true) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END if is_self else BoxContainer.ALIGNMENT_BEGIN
	if not is_self and avatar_idx >= 0 and avatar_idx < _avatars.size() and _avatars[avatar_idx] != null:
		var av := TextureRect.new()
		av.texture = _avatars[avatar_idx]
		av.custom_minimum_size = Vector2(44, 44)
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
	if record:
		_record_msg({"type": "text", "text": txt, "self": is_self, "avatar_idx": avatar_idx})
	_scroll_chat_to_bottom()


func _append_sticker_msg(sticker_idx: int, is_self: bool = true, record: bool = true, custom_avatar_idx: int = -1) -> void:
	if sticker_idx < 0 or sticker_idx >= _stickers.size():
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END if is_self else BoxContainer.ALIGNMENT_BEGIN
	var av_idx := custom_avatar_idx if custom_avatar_idx >= 0 else _get_contact_avatar_idx(_active_contact_idx)
	if not is_self:
		if av_idx >= 0 and av_idx < _avatars.size() and _avatars[av_idx] != null:
			var av := TextureRect.new()
			av.texture = _avatars[av_idx]
			av.custom_minimum_size = Vector2(44, 44)
			av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(av)
	var tr := TextureRect.new()
	tr.texture = _stickers[sticker_idx]
	tr.custom_minimum_size = Vector2(116, 100)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(tr)
	_msg_list.add_child(row)
	if record:
		_record_msg({"type": "sticker", "idx": sticker_idx, "self": is_self, "avatar_idx": av_idx})
	_scroll_chat_to_bottom()


func _record_msg(entry: Dictionary) -> void:
	_messages.append(entry)
	var cid := _active_contact_idx
	if not _messages_by_contact.has(cid):
		_messages_by_contact[cid] = []
	(_messages_by_contact[cid] as Array).append(entry)


func _rebuild_chat_for_active_contact() -> void:
	if _msg_list == null:
		return
	for c in _msg_list.get_children():
		_msg_list.remove_child(c)
		c.queue_free()
	var list: Array = _messages_by_contact.get(_active_contact_idx, [])
	for item in list:
		if not (item is Dictionary):
			continue
		var d := item as Dictionary
		var t := str(d.get("type", ""))
		var is_self := bool(d.get("self", false))
		var av := int(d.get("avatar_idx", _get_contact_avatar_idx(_active_contact_idx)))
		if t == "sc3":
			_append_sc3_msg(av, int(d.get("str_id", -1)), is_self, false)
		elif t == "text":
			_append_text_msg(av, str(d.get("text", "")), is_self, false)
		elif t == "sticker":
			_append_sticker_msg(int(d.get("idx", -1)), is_self, false, av)


func reset_phone_state() -> void:
	_active_contact_idx = 1
	_amadeus_unlocked = false
	if _amadeus_overlay != null:
		_amadeus_overlay.visible = false
	_stop_ringtone()
	_unlocked_contacts = {0: true, 1: true, 2: true, 5: true, 6: true, 7: true, 10: true}
	_messages.clear()
	_messages_by_contact.clear()
	_reply_options.clear()
	_reply_mode = 0
	_reply_selected_idx = 0
	_reply_tray_visible = false
	_sticker_tray_visible = false
	_self_contact_id = 0
	_unread_by_contact.clear()
	_has_unread_call = false
	_screen_history.clear()
	_populate_sticker_tray()
	_refresh_contacts_visibility()
	_refresh_reply_prompt()
	_refresh_chat_header()
	_refresh_unread_badges()
	switch_screen(PhoneScreen.HOME, false)


func export_state() -> Dictionary:
	var uc := []
	for k in _unlocked_contacts.keys():
		if bool(_unlocked_contacts[k]):
			uc.append(int(k))
	var mbc := {}
	for cid in _messages_by_contact.keys():
		mbc[str(cid)] = (_messages_by_contact[cid] as Array).duplicate(true)
	var ubc := {}
	for cid in _unread_by_contact.keys():
		var cnt := int(_unread_by_contact[cid])
		if cnt > 0:
			ubc[str(cid)] = cnt
	return {
		"active_contact_idx": _active_contact_idx,
		"amadeus_unlocked": _amadeus_unlocked,
		"unlocked_contacts": uc,
		"messages_by_contact": mbc,
		"reply_options": _reply_options.duplicate(),
		"reply_mode": _reply_mode,
		"reply_selected_idx": _reply_selected_idx,
		"self_contact_id": _self_contact_id,
		"unread_by_contact": ubc,
		"has_unread_call": _has_unread_call,
		"amadeus_overlay_visible": _amadeus_overlay != null and _amadeus_overlay.visible,
	}


func serialize_state() -> Dictionary:
	return export_state()


func deserialize_state(st: Dictionary) -> void:
	import_state(st)


func import_state(st: Dictionary) -> void:
	if st.is_empty():
		reset_phone_state()
		return
	_ensure_ui()
	_active_contact_idx = int(st.get("active_contact_idx", 1))
	_amadeus_unlocked = bool(st.get("amadeus_unlocked", false))
	_unlocked_contacts.clear()
	for k in st.get("unlocked_contacts", [0, 1, 2, 5, 6, 7, 10]):
		_unlocked_contacts[int(k)] = true
	_messages.clear()
	_messages_by_contact.clear()
	var mbc: Variant = st.get("messages_by_contact", {})
	if mbc is Dictionary:
		for cid_str in (mbc as Dictionary).keys():
			var cid := int(cid_str)
			var arr: Array = []
			for m in (mbc as Dictionary)[cid_str]:
				if m is Dictionary:
					arr.append((m as Dictionary).duplicate(true))
					_messages.append(m as Dictionary)
			_messages_by_contact[cid] = arr
	var raw_opts := (st.get("reply_options", []) as Array).duplicate()
	_reply_options.clear()
	for r in raw_opts:
		_reply_options.append(int(r))
	_reply_mode = int(st.get("reply_mode", 0))
	_reply_selected_idx = int(st.get("reply_selected_idx", 0))
	_reply_tray_visible = false
	_sticker_tray_visible = (_reply_mode == 1 and not _reply_options.is_empty() and _current_screen == PhoneScreen.CHAT)
	_self_contact_id = int(st.get("self_contact_id", 0))
	if _active_contact_idx <= 0:
		_ensure_best_rine_contact()
	_unread_by_contact.clear()
	var ubc: Variant = st.get("unread_by_contact", {})
	if ubc is Dictionary:
		for cid_str in (ubc as Dictionary).keys():
			var cnt := int((ubc as Dictionary)[cid_str])
			if cnt > 0:
				_unread_by_contact[int(cid_str)] = cnt
	_has_unread_call = bool(st.get("has_unread_call", false))
	var vm_call_active: bool = (_vm != null and _vm.is_incoming_call_active())
	var show_call: bool = bool(st.get("amadeus_overlay_visible", false)) or _has_unread_call or vm_call_active
	if _amadeus_overlay != null:
		_amadeus_overlay.visible = show_call
	if show_call:
		_has_unread_call = true
		_update_incoming_call_display()
		_play_ringtone()
	else:
		_stop_ringtone()
	_populate_sticker_tray()
	_refresh_contacts_visibility()
	_refresh_reply_prompt()
	_refresh_chat_header()
	_refresh_unread_badges()


func get_unread_count() -> int:
	var total := 0
	for cid in _unread_by_contact.keys():
		total += maxi(0, int(_unread_by_contact[cid]))
	if _has_unread_call:
		total += 1
	return total


func _clear_contact_unread(cid: int) -> void:
	var had := _unread_by_contact.has(cid)
	_unread_by_contact.erase(cid)
	_refresh_unread_badges()
	if had and get_unread_count() == 0:
		rine_read_ack.emit()


func _refresh_unread_badges() -> void:
	var rine_total := 0
	for cid in _unread_by_contact.keys():
		rine_total += maxi(0, int(_unread_by_contact[cid]))
	if _home_rine_badge != null:
		_home_rine_badge.visible = rine_total > 0
		if _home_rine_badge_lbl != null:
			_home_rine_badge_lbl.text = str(mini(99, rine_total))
	if _badge_blink_tween != null and _badge_blink_tween.is_valid():
		_badge_blink_tween.kill()
		_badge_blink_tween = null
	if _home_rine_badge != null and rine_total > 0:
		_home_rine_badge.modulate.a = 1.0
		_badge_blink_tween = create_tween().set_loops()
		_badge_blink_tween.tween_property(_home_rine_badge, "modulate:a", 0.35, 0.55)
		_badge_blink_tween.tween_property(_home_rine_badge, "modulate:a", 1.0, 0.55)
	for cid in _contact_badges.keys():
		var lbl := _contact_badges[cid] as Label
		if is_instance_valid(lbl):
			var cnt := int(_unread_by_contact.get(int(cid), 0))
			lbl.visible = cnt > 0
			if cnt > 0:
				lbl.text = str(mini(99, cnt))
	var total := get_unread_count()
	unread_state_changed.emit(total > 0, total)


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
