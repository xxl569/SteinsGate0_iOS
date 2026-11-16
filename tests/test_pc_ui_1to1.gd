extends SceneTree
## PC 1:1 界面与移动端左上角 HUD 深度功能及边界验证

var _done := false
var _failed := false


func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	_run()
	return false


func _fail(msg: String) -> void:
	_failed = true
	printerr("FAIL: ", msg)
	quit(1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _run() -> void:
	print("=== PC 1:1 UI & Top-Left HUD Verification ===")

	# 1. ConfigManager 全字段持久化、边界裁剪与恢复默认测试
	var cfg := ConfigManager.new()
	cfg.reset_to_defaults()
	_check(cfg.skip_stop_on_trigger == true, "skip_stop_on_trigger 默认应为 true")
	_check(cfg.show_tips_popup == true, "show_tips_popup 默认应为 true")
	_check(cfg.auto_quicksave_mode == 2, "auto_quicksave_mode 默认应为 2 (双方)")
	_check(cfg.resolution_index == 1, "resolution_index 默认应为 1 (1280x720)")
	_check(cfg.audio_sync == true and cfg.skip_voice == false, "SOUND 默认值异常")

	cfg.skip_stop_on_trigger = false
	cfg.show_tips_popup = false
	cfg.auto_quicksave_mode = 3
	cfg.fullscreen = true
	cfg.resolution_index = 2
	cfg.text_speed = 95.0
	cfg.auto_delay = 2.8
	cfg.skip_unread = true
	cfg.voice_volume = 0.65
	cfg.bgm_volume = 0.45
	cfg.se_volume = 0.55
	cfg.movie_volume = 0.35
	cfg.audio_sync = false
	cfg.skip_voice = true
	cfg.set_char_voice_volume(1, 0.42)
	cfg.set_char_voice_muted(2, true)
	cfg.set_char_voice_volume(-5, 9.0) # 越界裁剪测试
	_check(absf(cfg.get_char_voice_volume(0) - 1.0) < 0.01, "越界槽位裁剪异常")
	_check(cfg.get_char_voice_gain(2) == 0.0, "静音角色增益应为 0.0")
	cfg.save_config()

	var cfg2 := ConfigManager.new()
	cfg2.load_config()
	_check(cfg2.skip_stop_on_trigger == false and cfg2.auto_quicksave_mode == 3, "BASIC 配置持久化失败")
	_check(cfg2.fullscreen == true and cfg2.resolution_index == 2, "画面配置持久化失败")
	_check(absf(cfg2.text_speed - 95.0) < 0.1 and absf(cfg2.auto_delay - 2.8) < 0.1 and cfg2.skip_unread, "TEXT 配置持久化失败")
	_check(absf(cfg2.movie_volume - 0.35) < 0.01 and not cfg2.audio_sync and cfg2.skip_voice, "SOUND 配置持久化失败")
	_check(absf(cfg2.get_char_voice_volume(1) - 0.42) < 0.01 and cfg2.is_char_voice_muted(2), "VOICE 角色音量/静音持久化失败")

	cfg2.reset_to_defaults()
	cfg2.save_config()
	_check(cfg2.auto_quicksave_mode == 2 and not cfg2.is_char_voice_muted(2), "reset_to_defaults 未恢复全部默认值")
	print("[1/7] ConfigManager ok")

	# 2. 挂载真实资产并校验 UiThemeLoader 全套 PC 切片
	var vfs := MgsVfs.new()
	_check(vfs.auto_mount(cfg2), "VFS 挂载失败")
	var loader := UiThemeLoader.new()
	loader.bind_vfs(vfs)

	var cfg_a := loader.get_config_assets()
	_check(cfg_a["bg"] != null and (cfg_a["tabs_active"] as Array).size() == 4, "Config 图集切片异常")
	_check((cfg_a["voice_slots"] as Array).size() == 16 and cfg_a["voice_off_bar"] != null, "Config 16 角色切片异常")
	for vs in cfg_a["voice_slots"]:
		_check(vs != null, "存在空的语音角色切片")

	var sl_a := loader.get_saveload_assets()
	_check(sl_a["frame"] != null and sl_a["nodata"] != null and (sl_a["page_digits"] as Array).size() == 6, "SaveLoad 图集切片异常")
	_check(sl_a["ring_save"] != null and sl_a["ring_load"] != null and sl_a["locked_badge"] != null, "SaveLoad 徽章切片异常")

	var bl_a := loader.get_backlog_assets()
	_check(bl_a["panel"] != null and bl_a["speaker_icon"] != null and bl_a["scroll_thumb"] != null, "Backlog 图集切片异常")

	var tp_a := loader.get_tips_assets()
	_check(tp_a["bg"] != null and tp_a["grid_frame"] != null and (tp_a["tabs_active"] as Array).size() == 4, "Tips 图集切片异常")
	print("[2/7] UiThemeLoader 1:1 PC assets ok")

	# 3. 加载主场景验证 HUD 位置、弹窗拦截与全部 PC 面板功能
	var scene := load("res://scenes/main.tscn") as PackedScene
	_check(scene != null, "scenes/main.tscn 加载失败")
	var main_node := scene.instantiate() as MainController
	_check(main_node != null, "MainController 实例化失败")
	get_root().add_child(main_node)

	# 验证左上角 HUD 位置与不重叠特性
	main_node.start_new_game()
	for _i in range(240):
		main_node.vm.step_frame(1)
		if main_node.vm.is_waiting_for_click():
			break

	var hud := main_node.gesture_helper._hud_container
	_check(hud != null and hud.visible, "进入剧情后悬浮 HUD 应可见")
	_check(hud.anchor_left == 0.0 and hud.anchor_right == 0.0, "悬浮 HUD 必须锚定在左上角而非右上角")
	_check(hud.offset_left >= 14.0 and hud.offset_right <= 1100.0, "悬浮 HUD 应位于屏幕左上区域 (offset_left=%s, right=%s)" % [hud.offset_left, hud.offset_right])

	# 打开 RINE 手机抽屉（位于右侧 x>=1290），确认不重叠
	main_node.phone_drawer.open_phone()
	_check(hud.offset_right < 1290.0, "左上角 HUD 不得与右侧手机抽屉重叠")
	main_node.phone_drawer.close_phone()
	print("[3/7] MobileGestureHelper top-left HUD & non-overlap ok")

	# 4. Config 面板 4 分页切换、角色静音联动与重置默认
	main_node.panels.open_config(0)
	_check(main_node.panels.has_modal_open(), "Config 打开后应处于 modal 拦截态")
	_check(not hud.visible, "全屏模态打开时左上角 HUD 应自动隐藏以免重叠")
	for tab in range(4):
		main_node.panels._config_view._switch_tab(tab)
		_check(main_node.panels._config_view._page_containers[tab].visible, "Config 分页 %d 未正确切换" % tab)
	main_node.panels._config_view._toggle_selected_voice_mute()
	_check(main_node.config.is_char_voice_muted(1), "角色 1 (冈部) 应已静音")
	# 验证 VOICE 列表触控拖拽滚动（不应阻塞或误触静音）
	main_node.panels._config_view._switch_tab(3)
	await process_frame
	await process_frame
	var vs := main_node.panels._config_view._voice_scroll
	var v_pos := vs.get_global_rect().position + Vector2(120, 300)
	var st_down := InputEventScreenTouch.new()
	st_down.index = 0; st_down.pressed = true; st_down.position = v_pos
	get_root().push_input(st_down, true)
	var st_drag := InputEventScreenDrag.new()
	st_drag.index = 0; st_drag.position = v_pos + Vector2(0, -180); st_drag.relative = Vector2(0, -180)
	get_root().push_input(st_drag, true)
	var st_up := InputEventScreenTouch.new()
	st_up.index = 0; st_up.pressed = false; st_up.position = v_pos + Vector2(0, -180)
	get_root().push_input(st_up, true)
	await process_frame
	_check(vs.scroll_vertical >= 100, "VOICE 列表触控上滑应能滚动 (actual=%d)" % vs.scroll_vertical)

	main_node.panels._config_view._on_reset_defaults()
	_check(not main_node.config.is_char_voice_muted(1), "恢复默认后角色 1 应取消静音")
	main_node.panels._config_view.close_panel()
	_check(not main_node.panels.has_modal_open() and hud.visible, "关闭 Config 后应恢复左上角 HUD")
	print("[4/7] UiConfigPanel 4 tabs, voice mute & touch scroll ok")

	# 5. Save/Load 面板 6 页 48 槽位、写入/锁定防覆盖/翻页与读取验证
	var test_slot := 47 # 第 6 页最后一格
	UiPanels.set_slot_locked(test_slot, false)
	main_node._play_time_sec = 3665.0
	main_node._on_save_slot(test_slot)
	var meta47 := UiPanels.read_slot_meta(test_slot)
	_check(not meta47.is_empty() and int(meta47.get("play_time_sec", 0)) == 3665, "槽位 47 存档或时长记录失败")

	main_node.panels.open_saveload(true)
	var sl_panel := main_node.panels._saveload_view
	sl_panel._switch_page(5)
	_check(sl_panel._current_page == 5, "翻页至第 6 页失败")
	sl_panel._selected_local_idx = 7 # 5*8 + 7 = 47
	sl_panel._toggle_lock_selected()
	_check(bool(UiPanels.read_slot_meta(test_slot).get("locked", false)), "槽位 47 锁定失败")

	var save_emitted := [false]
	var conn := func(_sid: int): save_emitted[0] = true
	sl_panel.save_slot_requested.connect(conn)
	sl_panel._on_slot_clicked(7)
	_check(not save_emitted[0], "已锁定槽位在存档模式下不应允许直接覆盖")
	sl_panel.save_slot_requested.disconnect(conn)

	sl_panel._toggle_lock_selected()
	_check(not bool(UiPanels.read_slot_meta(test_slot).get("locked", true)), "槽位 47 解锁失败")
	sl_panel.close_panel()
	# 清理测试槽位 47 文件
	DirAccess.remove_absolute(UiPanels.get_slot_path(test_slot))
	if FileAccess.file_exists(UiPanels.get_slot_thumb_path(test_slot)):
		DirAccess.remove_absolute(UiPanels.get_slot_thumb_path(test_slot))
	print("[5/7] UiSaveloadPanel 48 slots, 6 pages, lock protection ok")

	# 6. Backlog 面板验证（含语音标记与重播信号）
	main_node.vm.backlog.append({
		"script": "SG0_00_01.scx",
		"str_id": 0,
		"str_offset": int(main_node.vm._scripts[0]["str_offsets"][0]),
		"char_id": 1,
		"voice_id": 1,
	})
	main_node.panels.open_backlog()
	var bl_panel := main_node.panels._backlog_view
	_check(bl_panel.visible and bl_panel._row_highlights.size() >= 1, "Backlog 未渲染出历史条目")
	var replayed_vid := [-1]
	var replayed_cid := [-1]
	bl_panel.voice_replay_with_char_requested.connect(func(vid: int, cid: int):
		replayed_vid[0] = vid
		replayed_cid[0] = cid
	)
	bl_panel._on_row_clicked(bl_panel._row_highlights.size() - 1)
	_check(replayed_vid[0] == 1 and replayed_cid[0] == 1, "点击带语音条目未触发 voice_replay_with_char_requested(1, 1)")
	bl_panel.close_panel()

	# 验证 *_K.ogg 电话滤音角色码映射
	_check(main_node.audio._resolve_voice_char_slot("SG0_00_04_MAH0025_K.ogg", 0) == 11, "*_K.ogg 角色码映射异常")
	_check(main_node.audio._resolve_voice_char_slot("SG0_A02_08_CRS0001_K.ogg", 0) == 4, "CRS *_K.ogg 角色码映射异常")
	print("[6/7] UiBacklogPanel & _K voice mapping ok")

	# 7. TIPS 面板验证（206 词条、锁/解锁态、4 分类过滤、已读持久化、弹窗与正文展示）
	var tips := main_node.tips_panel
	tips._read_tips.clear()
	tips._seen_tips.clear()
	tips._save_tips_state()
	tips.setup(vfs, main_node.vm, loader)
	_check(tips._total_tips == 206, "TIPS 总词条数应为 206，实际: %d" % tips._total_tips)
	main_node.vm.unlocked_tips.clear()
	tips._read_tips.clear()
	tips._seen_tips.clear()
	tips.open_panel()
	_check(tips._detail_no_label.text == "", "未解锁 TIPS 详情区应为空白")

	main_node.vm.unlocked_tips[0] = true
	main_node.vm.unlocked_tips[5] = true
	tips._switch_filter(UiTips.FilterMode.UNLOCKED)
	_check(tips._list_box.get_child_count() == 2, "已取得过滤应显示 2 条，实际: %d" % tips._list_box.get_child_count())
	_check(tips._detail_no_label.text == "001", "选中 TIPS #001 后 No. 应为 001")
	_check(tips._body_renderer.get_glyphs_count() > 0, "选中已解锁 TIPS 后正文不应为空")
	tips._switch_filter(UiTips.FilterMode.UNREAD)
	# 选中 tip 0 后已自动标为已读，仅剩 tip 5 未读 (1 条)
	_check(tips._list_box.get_child_count() == 1, "未读过滤计数应为 1，实际: %d" % tips._list_box.get_child_count())
	# 验证 TIPS 列表触控拖拽滚动
	tips._switch_filter(UiTips.FilterMode.ALL)
	await process_frame
	await process_frame
	var tls := tips._list_scroll
	var t_pos := tls.get_global_rect().position + Vector2(200, 400)
	var td := InputEventScreenTouch.new(); td.index = 0; td.pressed = true; td.position = t_pos
	get_root().push_input(td, true)
	var tdr := InputEventScreenDrag.new(); tdr.index = 0; tdr.position = t_pos + Vector2(0, -240)
	get_root().push_input(tdr, true)
	var tu := InputEventScreenTouch.new(); tu.index = 0; tu.pressed = false; tu.position = t_pos + Vector2(0, -240)
	get_root().push_input(tu, true)
	await process_frame
	_check(tls.scroll_vertical >= 150, "TIPS 列表触控上滑应能滚动 (actual=%d)" % tls.scroll_vertical)

	tips.close_panel()
	# 关闭后 tip 0/5 均已标为 seen，再次打开新规应为 0，而未读仍为 1 (tip 5)
	tips._switch_filter(UiTips.FilterMode.NEW)
	_check(tips._list_box.get_child_count() == 1 and not tips._seen_tips.has(99), "空新规提示节点校验")
	# 验证新规解锁 tip 10
	main_node.vm.unlocked_tips[10] = true
	tips._switch_filter(UiTips.FilterMode.NEW)
	_check(tips._list_box.get_child_count() == 1, "新规解锁 tip 10 后应显示 1 条，实际: %d" % tips._list_box.get_child_count())
	# 验证 show_tips_popup 提示条
	main_node.config.show_tips_popup = true
	main_node.panels.show_tips_toast(10)
	_check(main_node.panels._tips_toast != null and main_node.panels._tips_toast.visible, "TIPS 登录提示条应显示")
	tips.close_panel()
	if FileAccess.file_exists(UiTips.TIPS_STATE_PATH):
		DirAccess.remove_absolute(UiTips.TIPS_STATE_PATH)
	print("[7/7] UiTips 206 entries, filters, persistence & detail ok")

	main_node.queue_free()
	if _failed:
		quit(1)
		return
	print("=== PC 1:1 UI & Top-Left HUD Verification PASSED ===")
	quit(0)
