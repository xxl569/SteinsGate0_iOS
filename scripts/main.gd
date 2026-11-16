class_name MainController
extends Node
## 《命运石之门 0》iOS 移植版主控节点：串联 VFS、SC3 虚拟机、舞台、音视频与全部 UI 面板

var config: ConfigManager = null
var vfs: MgsVfs = null
var vm: Sc3Vm = null
var stage: MgsStage = null
var audio: MgsAudioMgr = null
var video: MgsVideoPlayer = null

var theme_loader: UiThemeLoader = null
var ui_layer: CanvasLayer = null
var panels: UiPanels = null
var phone_drawer: UiPhoneRine = null
var gallery: UiGalleryPanel = null
var tips_panel: UiTips = null
var gesture_helper: MobileGestureHelper = null

var _running_story: bool = false
var _auto_mode: bool = false
var _skip_mode: bool = false
var _auto_timer: float = 0.0
var _skip_timer: float = 0.0
var _line_read_flag: bool = false
var _play_time_sec: float = 0.0
var _pending_save_thumb: Image = null

var _cli_game_dir: String = ""
var _cli_movie_dir: String = ""
var _cli_script: String = ""
var _cli_label: int = 0
var _cli_advance_clicks: int = 0
var _cli_skip_movies: bool = false
var _cli_open_phone: bool = false
var _cli_open_panel: String = ""
var _cli_screenshot_path: String = ""
var _screenshot_frames_left: int = -1


func _ready() -> void:
	_parse_cli_args()
	_init_subsystems()
	_mount_and_boot()


func _parse_cli_args() -> void:
	var all_args := PackedStringArray()
	all_args.append_array(OS.get_cmdline_args())
	all_args.append_array(OS.get_cmdline_user_args())
	for arg in all_args:
		if arg.begins_with("--game-dir="):
			_cli_game_dir = arg.substr(11)
		elif arg.begins_with("--movie-dir="):
			_cli_movie_dir = arg.substr(12)
		elif arg.begins_with("--script="):
			_cli_script = arg.substr(9)
		elif arg.begins_with("--label="):
			_cli_label = int(arg.substr(8))
		elif arg.begins_with("--advance-clicks="):
			_cli_advance_clicks = int(arg.substr(17))
		elif arg == "--skip-movies":
			_cli_skip_movies = true
		elif arg == "--open-phone":
			_cli_open_phone = true
		elif arg.begins_with("--open-panel="):
			_cli_open_panel = arg.substr(13)
		elif arg.begins_with("--screenshot="):
			_cli_screenshot_path = arg.substr(13)


func _init_subsystems() -> void:
	config = ConfigManager.new()
	config.load_config()

	vfs = MgsVfs.new()
	vm = Sc3Vm.new(vfs)

	stage = MgsStage.new()
	stage.name = "MgsStage"
	add_child(stage)

	audio = MgsAudioMgr.new()
	audio.name = "MgsAudioMgr"
	add_child(audio)

	video = MgsVideoPlayer.new()
	video.name = "MgsVideoPlayer"
	add_child(video)

	theme_loader = UiThemeLoader.new()

	ui_layer = CanvasLayer.new()
	ui_layer.name = "UiCanvasLayer"
	ui_layer.layer = 50
	add_child(ui_layer)

	panels = UiPanels.new()
	ui_layer.add_child(panels)

	phone_drawer = UiPhoneRine.new()
	ui_layer.add_child(phone_drawer)

	gallery = UiGalleryPanel.new()
	ui_layer.add_child(gallery)

	tips_panel = UiTips.new()
	ui_layer.add_child(tips_panel)

	gesture_helper = MobileGestureHelper.new()
	ui_layer.add_child(gesture_helper)

	_connect_signals()


func _connect_signals() -> void:
	vm.dialogue_shown.connect(_on_vm_dialogue)
	vm.dialogue_clear.connect(_on_vm_dialogue_clear)
	vm.mes_window_changed.connect(_on_vm_mes_window_changed)
	vm.choices_requested.connect(_on_vm_choices_requested)
	vm.script_switched.connect(_on_vm_script_switched)
	vm.phone_event.connect(_on_vm_trigger_event)
	vm.rine_event.connect(_on_vm_trigger_event)
	vm.tips_unlocked.connect(func(tid: int):
		if panels != null:
			panels.show_tips_toast(tid)
	)

	panels.new_game_requested.connect(start_new_game)
	panels.continue_game_requested.connect(_on_continue_requested)
	panels.extra_requested.connect(func(tab: int):
		gallery.open_panel(tab)
		_sync_modal_block()
	)
	panels.tips_requested.connect(func():
		tips_panel.open_panel()
		_sync_modal_block()
	)
	panels.advance_dialogue_requested.connect(_on_user_advance)
	panels.choice_selected.connect(func(idx: int): vm.submit_choice(idx))
	panels.voice_replay_with_char_requested.connect(func(vid: int, cid: int): audio.play_voice(vid, cid))
	panels.save_slot_requested.connect(_on_save_slot)
	panels.load_slot_requested.connect(_on_load_slot)
	panels.retry_byoa_requested.connect(_mount_and_boot)
	panels.config_applied.connect(_on_config_applied)
	panels.modal_visibility_changed.connect(func(_open: bool): _sync_modal_block())

	tips_panel.closed.connect(_sync_modal_block)
	gallery.closed.connect(_sync_modal_block)

	gesture_helper.advance_requested.connect(_on_user_advance)
	gesture_helper.toggle_skip_requested.connect(_toggle_skip_mode)
	gesture_helper.toggle_auto_requested.connect(_toggle_auto_mode)
	gesture_helper.open_backlog_requested.connect(func():
		panels.open_backlog()
		_sync_modal_block()
	)
	gesture_helper.open_save_requested.connect(func():
		_capture_pending_thumb()
		panels.open_saveload(true)
		_sync_modal_block()
	)
	gesture_helper.open_load_requested.connect(func():
		panels.open_saveload(false)
		_sync_modal_block()
	)
	gesture_helper.open_config_requested.connect(func():
		panels.open_config()
		_sync_modal_block()
	)
	gesture_helper.open_phone_requested.connect(func(): phone_drawer.toggle_phone())
	gesture_helper.open_tips_requested.connect(func():
		tips_panel.open_panel()
		_sync_modal_block()
	)
	gesture_helper.open_title_requested.connect(return_to_title)
	gesture_helper.toggle_hide_ui_requested.connect(func(): panels.toggle_hide_ui())


func _mount_and_boot() -> void:
	var ok := false
	if _cli_game_dir != "":
		ok = vfs.mount_explicit(_cli_game_dir, _cli_movie_dir)
	else:
		ok = vfs.auto_mount(config)
		if ok and _cli_movie_dir != "":
			vfs.mount_explicit(vfs.active_game_dir, _cli_movie_dir)

	if not ok:
		panels.setup(vfs, vm, config, theme_loader)
		panels.show_byoa_wizard(vfs.get_candidate_game_dirs(config))
		gesture_helper.set_dialogue_mode(false)
		return

	panels.hide_byoa_wizard()
	theme_loader.bind_vfs(vfs)
	stage.bind_vfs(vfs)
	stage.bind_vm(vm)
	audio.bind_vfs(vfs)
	audio.bind_vm(vm)
	audio.apply_config(config)
	video.bind_vfs(vfs)
	video.bind_vm(vm)
	video.apply_config(config)
	panels.setup(vfs, vm, config, theme_loader)
	phone_drawer.setup(vfs, vm, theme_loader)
	gallery.setup(vfs, audio, video, stage.get_cache(), theme_loader)
	tips_panel.setup(vfs, vm, theme_loader)

	if _cli_script != "":
		vm.start_boot_script()
		for _f in range(15):
			vm.step_frame(1)
		_running_story = vm.jump_to_script(_cli_script, _cli_label)
		if _running_story:
			panels.show_dialogue_mode()
			gesture_helper.set_dialogue_mode(true)
			var clicks_left := _cli_advance_clicks
			for _s in range(600):
				vm.step_frame(1)
				if _cli_skip_movies and video.is_movie_playing():
					video.stop_movie(true)
				if vm.is_waiting_for_click():
					if clicks_left > 0:
						clicks_left -= 1
						panels.reveal_dialogue_instant()
						vm.notify_user_advance()
					else:
						panels.reveal_dialogue_instant()
						break
				elif vm.is_waiting_for_choice():
					break
			if _cli_open_phone:
				phone_drawer.open_phone()
	else:
		return_to_title()

	if _cli_open_panel != "":
		_open_cli_panel(_cli_open_panel)

	if _cli_screenshot_path != "":
		_screenshot_frames_left = 22 if _cli_open_phone else 5


func _open_cli_panel(spec: String) -> void:
	var low := spec.to_lower()
	if low.begins_with("config"):
		var tab := 0
		if low.contains(":"):
			tab = int(low.split(":")[1])
		panels.open_config(tab)
	elif low == "save":
		panels.open_saveload(true)
	elif low == "load":
		panels.open_saveload(false)
	elif low == "backlog":
		panels.open_backlog()
	elif low == "tips":
		tips_panel.open_panel()
	_sync_modal_block()


func _sync_modal_block() -> void:
	if gesture_helper == null:
		return
	var blocked := (
		(panels != null and panels.has_modal_open())
		or (tips_panel != null and tips_panel.visible)
		or (gallery != null and gallery.visible)
	)
	gesture_helper.set_modal_blocked(blocked)


func start_new_game() -> void:
	_auto_mode = false
	_skip_mode = false
	_play_time_sec = 0.0
	_update_mode_indicators()
	stage.reset_stage()
	vm.start_boot_script()
	for _f in range(15):
		vm.step_frame(1)
	_running_story = vm.jump_to_script("SG0_00_01.scx", 0)
	if _running_story:
		panels.show_dialogue_mode()
		gesture_helper.set_dialogue_mode(true)
		_sync_modal_block()


func return_to_title() -> void:
	_running_story = false
	_auto_mode = false
	_skip_mode = false
	_update_mode_indicators()
	audio.stop_bgm(10)
	audio.stop_voice()
	stage.reset_stage()
	phone_drawer.close_phone()
	if panels != null:
		panels.close_all_modals()
	if tips_panel != null:
		tips_panel.visible = false
	if gallery != null:
		gallery.visible = false
	gesture_helper.set_dialogue_mode(false)
	_sync_modal_block()
	panels.show_title_screen()


func _process(delta: float) -> void:
	if _screenshot_frames_left >= 0:
		if _screenshot_frames_left == 0 and _cli_screenshot_path != "":
			_capture_debug_screenshot(_cli_screenshot_path)
			_cli_screenshot_path = ""
			get_tree().quit(0)
			return
		_screenshot_frames_left -= 1

	if not _running_story or not vfs.is_mounted:
		return

	var modal_open := (
		(panels != null and panels.has_modal_open())
		or (tips_panel != null and tips_panel.visible)
		or (gallery != null and gallery.visible)
	)
	if modal_open:
		return

	_play_time_sec += delta

	if video.is_movie_playing():
		if _cli_skip_movies:
			video.stop_movie(true)
		else:
			return

	vm.step_frame(1)

	# 实时口型驱动
	stage.update_lip_sync(audio.get_voice_mouth_level())

	# 快进模式逻辑
	if _skip_mode:
		if not config.skip_unread and not _line_read_flag:
			_skip_mode = false
			_update_mode_indicators()
		elif vm.is_waiting_for_choice():
			_skip_mode = false
			_update_mode_indicators()
		elif vm.is_waiting_for_click():
			_skip_timer += delta
			if _skip_timer >= 0.04:
				_skip_timer = 0.0
				panels.reveal_dialogue_instant()
				vm.notify_user_advance()

	# 自动播放模式逻辑
	elif _auto_mode and vm.is_waiting_for_click() and not vm.is_waiting_for_choice():
		if panels.is_dialogue_reveal_done() and not audio.is_voice_playing():
			_auto_timer += delta
			if _auto_timer >= config.auto_delay:
				_auto_timer = 0.0
				vm.notify_user_advance()
		else:
			_auto_timer = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if _running_story and not video.is_movie_playing() and not (panels != null and panels.has_modal_open()):
		if event.is_action_pressed("ui_accept"):
			_on_user_advance()


func _notification(what: int) -> void:
	if what == NOTIFICATION_OS_MEMORY_WARNING:
		if stage != null:
			stage.on_low_memory()


func _on_user_advance() -> void:
	if not _running_story or vm.is_waiting_for_choice() or video.is_movie_playing():
		return
	if (panels != null and panels.has_modal_open()) or (tips_panel != null and tips_panel.visible) or (gallery != null and gallery.visible):
		return
	if not panels.is_dialogue_reveal_done():
		panels.reveal_dialogue_instant()
	else:
		if config != null and config.skip_voice:
			audio.stop_voice()
		vm.notify_user_advance()


func _toggle_auto_mode() -> void:
	_auto_mode = not _auto_mode
	if _auto_mode:
		_skip_mode = false
	_auto_timer = 0.0
	_update_mode_indicators()


func _toggle_skip_mode() -> void:
	_skip_mode = not _skip_mode
	if _skip_mode:
		_auto_mode = false
	_skip_timer = 0.0
	_update_mode_indicators()


func _update_mode_indicators() -> void:
	if panels != null:
		panels.set_mode_badge(_auto_mode, _skip_mode)
	if gesture_helper != null:
		gesture_helper.set_mode_states(_auto_mode, _skip_mode)


func _on_vm_dialogue(buf: PackedByteArray, soff: int, _cid: int, _vid: int, _sid: int, is_read: bool) -> void:
	_line_read_flag = is_read
	_auto_timer = 0.0
	panels.show_dialogue_line(buf, soff, _skip_mode)


func _on_vm_dialogue_clear() -> void:
	panels.clear_dialogue_line()


func _on_vm_mes_window_changed(vis: bool) -> void:
	if _running_story and panels._dialogue_view != null and not panels._ui_hidden:
		panels._dialogue_view.visible = vis


func _on_vm_choices_requested(choices: Array) -> void:
	_auto_mode = false
	_skip_mode = false
	_update_mode_indicators()
	if config != null and (config.auto_quicksave_mode == 1 or config.auto_quicksave_mode == 2):
		UiPanels.write_slot_data(99, vm.export_state(), "自动分支点存档", int(_play_time_sec))
	panels.show_choices(choices)


func _on_vm_trigger_event(_subop: int, _args: Array) -> void:
	if _skip_mode and config != null and config.skip_stop_on_trigger:
		_skip_mode = false
		_update_mode_indicators()


func _on_vm_script_switched(_sname: String) -> void:
	# 按设置决定是否自动快速存档留存最近切换脚本进度 (0=场景, 2=双方)
	if config == null or config.auto_quicksave_mode == 0 or config.auto_quicksave_mode == 2:
		UiPanels.write_slot_data(99, vm.export_state(), "自动章节切换", int(_play_time_sec))


func _capture_pending_thumb() -> void:
	_pending_save_thumb = null
	if DisplayServer.get_name() == "headless":
		return
	var vp := get_viewport()
	if vp != null and vp.get_texture() != null:
		_pending_save_thumb = vp.get_texture().get_image()


func _on_save_slot(slot_id: int) -> void:
	var summary := "第 %d 条回顾" % vm.backlog.size()
	var thumb := _pending_save_thumb
	if thumb == null and DisplayServer.get_name() != "headless":
		var vp := get_viewport()
		if vp != null and vp.get_texture() != null:
			thumb = vp.get_texture().get_image()
	_pending_save_thumb = null
	UiPanels.write_slot_data(slot_id, vm.export_state(), summary, int(_play_time_sec), thumb)
	panels.refresh_title_status()


func _on_load_slot(slot_id: int) -> void:
	var meta := UiPanels.read_slot_meta(slot_id)
	var st: Variant = meta.get("vm_state", null)
	if st is Dictionary and vm.import_state(st as Dictionary):
		_running_story = true
		_auto_mode = false
		_skip_mode = false
		_play_time_sec = float(meta.get("play_time_sec", 0))
		_update_mode_indicators()
		panels.show_dialogue_mode()
		gesture_helper.set_dialogue_mode(true)
		_sync_modal_block()


func _on_continue_requested() -> void:
	var latest_slot := -1
	var latest_ts := ""
	for s in range(UiPanels.NUM_SAVE_SLOTS):
		var m := UiPanels.read_slot_meta(s)
		if not m.is_empty():
			var ts := str(m.get("timestamp", ""))
			if latest_slot < 0 or ts > latest_ts:
				latest_ts = ts
				latest_slot = s
	if latest_slot < 0 and not UiPanels.read_slot_meta(99).is_empty():
		latest_slot = 99
	if latest_slot >= 0:
		_on_load_slot(latest_slot)


func _on_config_applied() -> void:
	audio.apply_config(config)
	video.apply_config(config)
	if panels._body_renderer != null:
		panels._body_renderer.set_text_speed(config.text_speed)
	if OS.get_name() in ["Windows", "macOS", "Linux"] and DisplayServer.get_name() != "headless":
		if config.fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var res_sizes := [Vector2i(1024, 576), Vector2i(1280, 720), Vector2i(1920, 1080)]
			var sz: Vector2i = res_sizes[clampi(config.resolution_index, 0, 2)]
			DisplayServer.window_set_size(sz)


func _capture_debug_screenshot(out_path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		var dir := out_path.get_base_dir()
		if dir != "":
			DirAccess.make_dir_recursive_absolute(dir)
		img.save_png(out_path)
		print("Screenshot saved: ", out_path)
