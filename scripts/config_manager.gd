class_name ConfigManager
extends RefCounted
## Steins;Gate 0 iOS 全局配置与命令行调试参数管理（user://config.json）
## 完整对齐 PC 版 4 大设置分页：BASIC / TEXT / SOUND / VOICE

const CONFIG_PATH := "user://config.json"
const CONFIG_SCHEMA_VERSION := 2

# 16 名角色语音槽位定义（严格对应 CONFIG.DDS 4x4 角色网格顺序）
const VOICE_CHAR_COUNT := 16
const VOICE_CHAR_NAMES := [
	"????",
	"冈部伦太郎",
	"椎名真由理",
	"桥田至",
	"牧濑红莉栖",
	"桐生萌郁",
	"漆原琉华",
	"菲莉丝·喵喵",
	"阿万音铃羽",
	"天王寺绹",
	"天王寺裕吾",
	"比屋定真帆",
	"阿万音由季",
	"椎名篝",
	"其他（男）",
	"其他（女）",
]

# 1. BASIC 基本设置
var skip_stop_on_trigger: bool = true # 触发操作时跳过模式解除 (true=是, false=否)
var show_tips_popup: bool = true # 登陆Tips消息显示 (true=是, false=否)
var auto_quicksave_mode: int = 2 # 自动快速储存 (0=场景, 1=触发器, 2=双方, 3=都不)
var fullscreen: bool = false # 全屏切换 (true=全屏, false=窗口)
var resolution_index: int = 1 # 屏幕分辨率 (0=1024x576, 1=1280x720, 2=1920x1080)

# 保留兼容字段
var dialogue_opacity: float = 0.88
var wait_indicator_anim: bool = true
var show_floating_hud: bool = true

# 2. TEXT 文字设置
var text_speed: float = 48.0 # 信息速度 (每秒字数；>= 110 表示瞬间全显)
var auto_delay: float = 1.6 # 自动模式等待时间 (秒)
var skip_unread: bool = true # 跳过模式 (false=仅已读, true=全部；iOS 触控默认开启全部快进以免首次游玩点快进无反应)
var skip_continue_at_choice: bool = false
var voice_stop_on_next: bool = false

# 手机 RINE 个性化设置
var phone_wallpaper_idx: int = 0 # 0..11 (PWCG.DDS 12 张壁纸)
var phone_ringtone_idx: int = 0 # 0..6 (SGSE700..SGSE706 7 首来电铃声)

# 3. SOUND 声音设置 (0.0 ~ 1.0)
var voice_volume: float = 1.00 # 声音音量
var bgm_volume: float = 0.80 # BGM音量
var se_volume: float = 0.85 # 效果音量
var movie_volume: float = 0.85 # 视频音量
var audio_sync: bool = true # 音频同步 (true=是, false=否)
var skip_voice: bool = false # 跳过声音 (true=是, false=否)

# 4. VOICE 各个角色语音设定（索引 0..15）
var char_voice_volumes: Dictionary = {} # String(idx) -> float(0.0..1.0)
var char_voice_muted: Dictionary = {} # String(idx) -> bool

# 5. 调试与外置资产覆盖路径（同时支持 --cmdline 与 user://config.json）
var custom_game_dir: String = ""
var custom_movie_dir: String = ""
var debug_script: String = ""
var debug_label: int = -1


func _init() -> void:
	_init_voice_defaults()


func _init_voice_defaults() -> void:
	for i in range(VOICE_CHAR_COUNT):
		var k := str(i)
		if not char_voice_volumes.has(k):
			char_voice_volumes[k] = 1.0
		if not char_voice_muted.has(k):
			char_voice_muted[k] = false


func reset_to_defaults() -> void:
	skip_stop_on_trigger = true
	show_tips_popup = true
	auto_quicksave_mode = 2
	fullscreen = false
	resolution_index = 1

	dialogue_opacity = 0.88
	wait_indicator_anim = true
	show_floating_hud = true

	text_speed = 48.0
	auto_delay = 1.6
	skip_unread = true
	skip_continue_at_choice = false
	voice_stop_on_next = false
	phone_wallpaper_idx = 0
	phone_ringtone_idx = 0

	voice_volume = 1.00
	bgm_volume = 0.80
	se_volume = 0.85
	movie_volume = 0.85
	audio_sync = true
	skip_voice = false

	char_voice_volumes.clear()
	char_voice_muted.clear()
	_init_voice_defaults()


func get_char_voice_volume(char_slot: int) -> float:
	var k := str(clampi(char_slot, 0, VOICE_CHAR_COUNT - 1))
	return clampf(float(char_voice_volumes.get(k, 1.0)), 0.0, 1.0)


func set_char_voice_volume(char_slot: int, vol: float) -> void:
	var k := str(clampi(char_slot, 0, VOICE_CHAR_COUNT - 1))
	char_voice_volumes[k] = clampf(vol, 0.0, 1.0)


func is_char_voice_muted(char_slot: int) -> bool:
	var k := str(clampi(char_slot, 0, VOICE_CHAR_COUNT - 1))
	return bool(char_voice_muted.get(k, false))


func set_char_voice_muted(char_slot: int, muted: bool) -> void:
	var k := str(clampi(char_slot, 0, VOICE_CHAR_COUNT - 1))
	char_voice_muted[k] = muted


func get_char_voice_gain(char_slot: int) -> float:
	if is_char_voice_muted(char_slot):
		return 0.0
	return get_char_voice_volume(char_slot)


func load_config() -> void:
	_init_voice_defaults()
	if FileAccess.file_exists(CONFIG_PATH):
		var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				var d := parsed as Dictionary
				skip_stop_on_trigger = bool(d.get("skip_stop_on_trigger", skip_stop_on_trigger))
				show_tips_popup = bool(d.get("show_tips_popup", show_tips_popup))
				auto_quicksave_mode = clampi(int(d.get("auto_quicksave_mode", auto_quicksave_mode)), 0, 3)
				fullscreen = bool(d.get("fullscreen", fullscreen))
				resolution_index = clampi(int(d.get("resolution_index", resolution_index)), 0, 2)

				dialogue_opacity = clampf(float(d.get("dialogue_opacity", dialogue_opacity)), 0.25, 1.0)
				wait_indicator_anim = bool(d.get("wait_indicator_anim", wait_indicator_anim))
				show_floating_hud = bool(d.get("show_floating_hud", show_floating_hud))

				text_speed = clampf(float(d.get("text_speed", text_speed)), 10.0, 120.0)
				auto_delay = clampf(float(d.get("auto_delay", auto_delay)), 0.3, 5.0)
				var loaded_schema := int(d.get("config_schema_version", 1))
				if loaded_schema < CONFIG_SCHEMA_VERSION:
					# 从 v1 旧存档迁移：默认开启未读快进，避免 iOS 首次游玩快进无效
					skip_unread = true
				else:
					skip_unread = bool(d.get("skip_unread", skip_unread))
				skip_continue_at_choice = bool(d.get("skip_continue_at_choice", skip_continue_at_choice))
				voice_stop_on_next = bool(d.get("voice_stop_on_next", voice_stop_on_next))
				phone_wallpaper_idx = clampi(int(d.get("phone_wallpaper_idx", phone_wallpaper_idx)), 0, 11)
				phone_ringtone_idx = clampi(int(d.get("phone_ringtone_idx", phone_ringtone_idx)), 0, 6)

				voice_volume = clampf(float(d.get("voice_volume", voice_volume)), 0.0, 1.0)
				bgm_volume = clampf(float(d.get("bgm_volume", bgm_volume)), 0.0, 1.0)
				se_volume = clampf(float(d.get("se_volume", se_volume)), 0.0, 1.0)
				movie_volume = clampf(float(d.get("movie_volume", movie_volume)), 0.0, 1.0)
				audio_sync = bool(d.get("audio_sync", audio_sync))
				skip_voice = bool(d.get("skip_voice", skip_voice))

				var cv: Variant = d.get("char_voice_volumes", null)
				if cv is Dictionary:
					for k in (cv as Dictionary).keys():
						char_voice_volumes[str(k)] = clampf(float((cv as Dictionary)[k]), 0.0, 1.0)
				var cm: Variant = d.get("char_voice_muted", null)
				if cm is Dictionary:
					for k in (cm as Dictionary).keys():
						char_voice_muted[str(k)] = bool((cm as Dictionary)[k])

				custom_game_dir = str(d.get("custom_game_dir", "")).strip_edges()
				custom_movie_dir = str(d.get("custom_movie_dir", "")).strip_edges()
	_init_voice_defaults()
	_apply_cmdline_args()


func save_config() -> void:
	var data := {
		"config_schema_version": CONFIG_SCHEMA_VERSION,
		"skip_stop_on_trigger": skip_stop_on_trigger,
		"show_tips_popup": show_tips_popup,
		"auto_quicksave_mode": auto_quicksave_mode,
		"fullscreen": fullscreen,
		"resolution_index": resolution_index,
		"dialogue_opacity": dialogue_opacity,
		"wait_indicator_anim": wait_indicator_anim,
		"show_floating_hud": show_floating_hud,
		"text_speed": text_speed,
		"auto_delay": auto_delay,
		"skip_unread": skip_unread,
		"skip_continue_at_choice": skip_continue_at_choice,
		"voice_stop_on_next": voice_stop_on_next,
		"phone_wallpaper_idx": phone_wallpaper_idx,
		"phone_ringtone_idx": phone_ringtone_idx,
		"voice_volume": voice_volume,
		"bgm_volume": bgm_volume,
		"se_volume": se_volume,
		"movie_volume": movie_volume,
		"audio_sync": audio_sync,
		"skip_voice": skip_voice,
		"char_voice_volumes": char_voice_volumes,
		"char_voice_muted": char_voice_muted,
		"custom_game_dir": custom_game_dir,
		"custom_movie_dir": custom_movie_dir,
	}
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))


func _apply_cmdline_args() -> void:
	var all_args: PackedStringArray = OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--game-dir=") or arg.begins_with("--movie-dir=") or arg.begins_with("--script=") or arg.begins_with("--label="):
			all_args.append(arg)

	for arg in all_args:
		if arg.begins_with("--game-dir="):
			custom_game_dir = arg.substr(11).strip_edges()
		elif arg.begins_with("--movie-dir="):
			custom_movie_dir = arg.substr(12).strip_edges()
		elif arg.begins_with("--script="):
			debug_script = arg.substr(9).strip_edges()
		elif arg.begins_with("--label="):
			var val := arg.substr(8).strip_edges()
			if val.is_valid_int():
				debug_label = int(val)
