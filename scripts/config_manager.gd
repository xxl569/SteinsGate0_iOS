class_name ConfigManager
extends RefCounted
## Steins;Gate 0 iOS 全局配置与命令行调试参数管理（user://config.json）

const CONFIG_PATH := "user://config.json"

# 1. 画面设置
var fullscreen: bool = false
var dialogue_opacity: float = 0.88
var wait_indicator_anim: bool = true
var show_floating_hud: bool = true

# 2. 文本与阅读设置
var text_speed: float = 48.0 # 每秒字数；>= 110 表示瞬间全显
var auto_delay: float = 1.6  # 自动模式每句停顿秒数
var skip_unread: bool = false # false: 仅跳过已读, true: 全部跳过
var skip_continue_at_choice: bool = false # 遇到分支是否停止快进
var voice_stop_on_next: bool = false # false: 下句话触发语音中断; true: 点击即停止当前语音

# 3. 音量设置 (0.0 ~ 1.0)
var bgm_volume: float = 0.80
var se_volume: float = 0.85
var voice_volume: float = 1.00
var movie_volume: float = 0.85

# 4. 调试与外置资产覆盖路径（同时支持 --cmdline 与 user://config.json）
var custom_game_dir: String = ""
var custom_movie_dir: String = ""
var debug_script: String = ""
var debug_label: int = -1


func reset_to_defaults() -> void:
	fullscreen = false
	dialogue_opacity = 0.88
	wait_indicator_anim = true
	show_floating_hud = true
	text_speed = 48.0
	auto_delay = 1.6
	skip_unread = false
	skip_continue_at_choice = false
	voice_stop_on_next = false
	bgm_volume = 0.80
	se_volume = 0.85
	voice_volume = 1.00
	movie_volume = 0.85


func load_config() -> void:
	if FileAccess.file_exists(CONFIG_PATH):
		var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				var d := parsed as Dictionary
				fullscreen = bool(d.get("fullscreen", fullscreen))
				dialogue_opacity = clampf(float(d.get("dialogue_opacity", dialogue_opacity)), 0.25, 1.0)
				wait_indicator_anim = bool(d.get("wait_indicator_anim", wait_indicator_anim))
				show_floating_hud = bool(d.get("show_floating_hud", show_floating_hud))

				text_speed = clampf(float(d.get("text_speed", text_speed)), 10.0, 120.0)
				auto_delay = clampf(float(d.get("auto_delay", auto_delay)), 0.3, 5.0)
				skip_unread = bool(d.get("skip_unread", skip_unread))
				skip_continue_at_choice = bool(d.get("skip_continue_at_choice", skip_continue_at_choice))
				voice_stop_on_next = bool(d.get("voice_stop_on_next", voice_stop_on_next))

				bgm_volume = clampf(float(d.get("bgm_volume", bgm_volume)), 0.0, 1.0)
				se_volume = clampf(float(d.get("se_volume", se_volume)), 0.0, 1.0)
				voice_volume = clampf(float(d.get("voice_volume", voice_volume)), 0.0, 1.0)
				movie_volume = clampf(float(d.get("movie_volume", movie_volume)), 0.0, 1.0)

				custom_game_dir = str(d.get("custom_game_dir", "")).strip_edges()
				custom_movie_dir = str(d.get("custom_movie_dir", "")).strip_edges()
	_apply_cmdline_args()


func save_config() -> void:
	var data := {
		"fullscreen": fullscreen,
		"dialogue_opacity": dialogue_opacity,
		"wait_indicator_anim": wait_indicator_anim,
		"show_floating_hud": show_floating_hud,
		"text_speed": text_speed,
		"auto_delay": auto_delay,
		"skip_unread": skip_unread,
		"skip_continue_at_choice": skip_continue_at_choice,
		"voice_stop_on_next": voice_stop_on_next,
		"bgm_volume": bgm_volume,
		"se_volume": se_volume,
		"voice_volume": voice_volume,
		"movie_volume": movie_volume,
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
