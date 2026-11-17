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

	var mw_a := loader.get_meswin_assets()
	_check(mw_a.get("accent_left", null) != null and (mw_a["accent_left"] as Texture2D).get_width() <= 165,
		"说话人名左翼切片应裁除尾部 '0' 字形")
	_check(mw_a.get("date_pill_bg", null) != null and (mw_a["date_pill_bg"] as Texture2D).get_height() <= 140,
		"日期胶囊切片不应包含上方 wait_ring 边缘")
	_check(mw_a.get("auto_btn_off", null) != null and mw_a.get("skip_btn_off", null) != null,
		"MESWIN AUTO/SKIP 按钮切片缺失")
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

	var date_btn := main_node.gesture_helper._date_phone_btn
	var hud_left := main_node.gesture_helper._bottom_left_hud
	var hud_right := main_node.gesture_helper._bottom_right_hud
	_check(date_btn != null and date_btn.visible, "进入剧情后左上角日期/手机按钮应可见")
	_check(date_btn.offset_left <= 40.0 and date_btn.offset_top <= 40.0 and date_btn.offset_right < 350.0,
		"左上角日期按钮应位于左上角 (left=%s, right=%s)" % [date_btn.offset_left, date_btn.offset_right])
	_check(hud_left != null and hud_left.visible and hud_left.offset_top >= 1000.0 and hud_left.offset_right < 720.0,
		"左下角快捷栏应位于左下区域且留出正下方名字空档")
	_check(hud_right != null and hud_right.visible and hud_right.offset_top >= 1000.0 and hud_right.offset_left >= 1180.0,
		"右下角系统栏应位于右下区域且留出正下方名字空档")

	var accent := main_node.panels._meswin_accent
	_check(accent != null, "正下方说话人名装饰框应存在")
	var accent_center_x := accent.position.x + accent.size.x * 0.5
	_check(absf(accent_center_x - 960.0) <= 20.0 and accent.position.y >= 1000.0,
		"说话人名装饰框应位于正下方居中 (cx=%s, y=%s)" % [accent_center_x, accent.position.y])

	# 验证点击左上角日期胶囊可弹出手机 / RINE 抽屉，并测试桌面->通讯录->RINE->设置->12壁纸->7铃声全页面
	date_btn.pressed.emit()
	_check(main_node.phone_drawer.is_phone_open(), "点击左上角日期按钮应打开手机抽屉")
	var pd := main_node.phone_drawer
	_check(pd._screen_root != null and pd._frame_tex != null and pd._screen_root.get_index() > pd._frame_tex.get_index(),
		"手机屏幕图层必须位于外框 _frame_tex 之上，防止被不透明黑色开孔区域遮挡")
	_check(pd._screen_root.position == Vector2(118, 124) and pd._screen_root.size == Vector2(454, 794),
		"手机屏幕开孔区域尺寸异常: %s / %s" % [pd._screen_root.position, pd._screen_root.size])
	_check(main_node.gesture_helper._btn_auto.get_theme_stylebox("normal") is StyleBoxTexture and main_node.gesture_helper._btn_skip.get_theme_stylebox("normal") is StyleBoxTexture,
		"左下角 AUTO/SKIP 按钮应绑定 PC StyleBoxTexture")
	_check(pd._wallpapers.size() == 12, "手机应加载 12 张 PWCG 壁纸，实际: %d" % pd._wallpapers.size())
	_check(pd._ringtone_btns.size() == 7, "手机应提供 7 首 PC 原版铃声，实际: %d" % pd._ringtone_btns.size())
	pd.switch_screen(UiPhoneRine.PhoneScreen.WALLPAPER)
	pd.select_wallpaper(5)
	_check(main_node.config.phone_wallpaper_idx == 5, "壁纸选择应同步并持久化到 ConfigManager")
	pd.switch_screen(UiPhoneRine.PhoneScreen.RINGTONE)
	pd.select_ringtone(6, false)
	_check(main_node.config.phone_ringtone_idx == 6, "铃声选择应同步并持久化到 ConfigManager")
	pd.switch_screen(UiPhoneRine.PhoneScreen.HOME)
	pd.close_phone()
	_check(not main_node.phone_drawer.is_phone_open(), "收起手机抽屉失败")

	# 验证点击快进 SKIP 在未读状态下不会立刻自我取消
	main_node.config.skip_unread = true
	main_node.gesture_helper._btn_skip.pressed.emit()
	_check(main_node._skip_mode, "点击快进按钮后 _skip_mode 应激活")
	main_node._process(0.05)
	_check(main_node._skip_mode, "未读文本下开启快进时不应在首帧自动熄灭")
	main_node._toggle_skip_mode()

	var hud := main_node.gesture_helper._hud_container
	print("[3/7] PC-layout Date Pill + Bottom-Left/Right HUD + Center Speaker + Phone/RINE & Skip ok")

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

	# 8. 补充防回归：DDS 精切尺寸、RINE 指令解码、Config v1->v2 迁移
	var ma := loader.get_meswin_assets()
	_check((ma["auto_btn_on"] as Texture2D).get_size() == Vector2(137, 40), "auto_btn_on 应为 137x40")
	_check((ma["auto_btn_off"] as Texture2D).get_size() == Vector2(119, 39), "auto_btn_off 应为 119x39")
	_check((ma["skip_btn_on"] as Texture2D).get_size() == Vector2(119, 39), "skip_btn_on 应为 119x39")
	_check((ma["skip_btn_off"] as Texture2D).get_size() == Vector2(119, 39), "skip_btn_off 应为 119x39")
	var pa := loader.get_phone_assets()
	_check((pa["rine_bg"] as Texture2D).get_size() == Vector2(456, 696), "rine_bg 应剔除底部紫条至 456x696")
	_check((pa["settings_bg"] as Texture2D).get_size() == Vector2(446, 744), "settings_bg 应为纯净斜光底 446x744")
	_check(pa.get("rine_emoji", null) != null and pa.get("rine_send_arrow", null) != null, "RINE 表情与发送箭头纹理应存在")

	var pd_chk := main_node.phone_drawer
	_check(pd_chk._messages.is_empty(), "开局未触发 RINE 事件前不应注入假聊天消息")
	pd_chk._on_rine_event(0, [2, 3, 4, 5, 6, 7, 8])
	_check(pd_chk._messages.is_empty(), "RINE subop=0 初始化指令不应作为消息气泡输出")
	pd_chk._on_rine_event(15, [1, 0, 5])
	_check(pd_chk._messages.size() == 1 and int(pd_chk._messages[0].get("str_id", -1)) == 5 and not bool(pd_chk._messages[0].get("self", true)),
		"RINE subop=15 文本应解码 args[2]=5 且标记对方消息")
	pd_chk._on_rine_event(15, [0, 1, 2])
	_check(pd_chk._messages.size() == 2 and pd_chk._messages[1].get("type", "") == "sticker" and int(pd_chk._messages[1].get("idx", -1)) == 2 and bool(pd_chk._messages[1].get("self", false)),
		"RINE subop=15 贴纸应解码 args[2]=2 且标记己方发送")

	var cfg_test := ConfigManager.new()
	var old_f := FileAccess.open(ConfigManager.CONFIG_PATH, FileAccess.WRITE)
	if old_f != null:
		old_f.store_string("{\"skip_unread\": false}")
		old_f.close()
	cfg_test.load_config()
	_check(cfg_test.skip_unread == true, "旧版 v1 config.json 的 skip_unread=false 应自动迁移为 true")
	if FileAccess.file_exists(ConfigManager.CONFIG_PATH):
		DirAccess.remove_absolute(ConfigManager.CONFIG_PATH)
	print("[8/8] Exact DDS slices, RINE event decoder & Config v2 migration ok")

	# 9. 防回归：RINE 头像/贴纸精确切片 + 候选回复列表 + 标题读档现场完整恢复
	var avs := loader.get_rine_avatars()
	_check(avs.size() == 12 and (avs[0] as Texture2D).get_size() == Vector2(90, 90),
		"RINE 头像应为 12 枚 90x90 精确切片")
	var stks := loader.get_rine_stickers()
	_check(stks.size() == 21, "RINE 贴纸应为 21 枚 (3x7)")
	_check(pd_chk._get_contact_avatar_idx(10) == 9 and pd_chk._get_contact_avatar_idx(9) == 10,
		"阿万音由季(10)->avatar 9, 椎名篝(9)->avatar 10 索引必须正确")
	_check(pd_chk._amadeus_btn != null and not pd_chk._amadeus_btn.visible,
		"序章初始桌面不应显示未解锁的 Amadeus 图标")
	pd_chk._on_rine_event(13, [10, 1])
	pd_chk._on_rine_event(13, [11, 2])
	_check(pd_chk._reply_options.size() == 2, "RINE subop=13 应注册 2 个候选回复")
	pd_chk._on_rine_event(43, [7])
	pd_chk._on_rine_event(46, [7, 0, 0])
	pd_chk._on_rine_event(46, [7, 1, 10])
	_check(pd_chk._active_contact_idx == 7 and pd_chk._messages_by_contact.get(7, []).size() == 2,
		"RINE subop=43/46 应将铃羽(7)的消息与贴纸记录到铃羽线程")
	pd_chk._toggle_reply_tray()
	_check(pd_chk._reply_panel.visible and pd_chk._reply_list.get_child_count() == 2,
		"点击输入栏应弹出 2 个真实候选回复选项")

	# 舞台背景+立绘+台词 存档 -> 返回标题清空舞台 -> 读档完整恢复
	main_node.stage.load_bg_by_index(0, 1)
	main_node.stage.flush_transitions()
	_check(main_node.stage.get_bg_texture(0) != null, "测试前舞台 BG 0 应已加载")
	var reg_slot := 46
	UiPanels.set_slot_locked(reg_slot, false)
	main_node._on_save_slot(reg_slot)
	main_node.return_to_title()
	_check(main_node.stage.get_bg_texture(0) == null, "返回标题后舞台 BG 0 应已清空")
	main_node._on_load_slot(reg_slot)
	_check(main_node.stage.get_bg_texture(0) != null, "从标题读档后舞台 BG 0 必须完整恢复，不可灰屏缺失")
	_check(main_node.stage.visible and main_node._running_story, "读档后舞台与剧情状态应激活")
	if FileAccess.file_exists(UiPanels.get_slot_path(reg_slot)):
		DirAccess.remove_absolute(UiPanels.get_slot_path(reg_slot))
	if FileAccess.file_exists(UiPanels.get_slot_thumb_path(reg_slot)):
		DirAccess.remove_absolute(UiPanels.get_slot_thumb_path(reg_slot))
	print("[9/9] RINE avatars/stickers/reply-tray & title-load stage recovery ok")

	# [10/10] _rndrine.scx 子解释器、回复/贴纸写回、Amadeus 来电写回、未读角标与铃声停止
	main_node.start_new_game()
	main_node.vm.jump_to_script("SG0_00_01.scx", 0)
	pd_chk.reset_phone_state()
	pd_chk.close_phone()
	pd_chk._active_contact_idx = 2 # 故意设为非目标联系人(桶子)，验证 PC 真实流程 sub=43(1)/sub=46(1) 后不会在旧联系人上残留幽灵未读
	main_node.vm._handle_rine_ctrl(50, [9])
	_check(main_node.vm.get_scr_work(6655) == 162, "SG0_RineCtrl.sub=50(9) 应写入 ScrWork[6655]=162")
	main_node.vm._handle_rine_ctrl(43, [1]) # PC L01: 加入目标联系人真由理(1)
	main_node.vm._handle_rine_ctrl(46, [1, 0, 162]) # PC L12: 发送真由理(1)开场第一条消息
	main_node.vm.set_scr_work(1501, 0) # PC 中 ScrWork[1501] 常为 0，验证 sub=12(0,0) 不会把聊天对象错改成伦太郎(0)
	main_node.vm._handle_rine_ctrl(10, [24]) # 启动 _rndrine.scx L024
	var rs0 := main_node.vm.get_rine_state()
	_check(main_node.vm.get_flag(2614) == 1 and main_node.vm.get_flag(2615) == 0 and main_node.vm.get_flag(2616) == 1,
		"RINE sub=10 启动后 Flag(2614)=1, Flag(2615)=0, Flag(2616)=1")
	_check(bool(rs0.get("waiting_reply", false)) and (rs0.get("reply_options", []) as Array).size() == 3,
		"L024 应停在 sub=14 并注册 3 个回复分支")
	_check(pd_chk._active_contact_idx == 1, "sub=43/46 后活跃联系人应为真由理(1)，且 sub=12(0,0) 不可覆盖为 0")
	_check(int(pd_chk._unread_by_contact.get(2, 0)) == 0 and int(pd_chk._unread_by_contact.get(1, 0)) >= 1,
		"未读角标必须只挂在目标联系人(1)上，不能残留在旧联系人(2)上")
	_check((pd_chk._contact_badges[1] as Label).visible and not (pd_chk._contact_badges[2] as Label).visible,
		"联系人列表仅目标联系人(1)角标亮起")
	_check(pd_chk._reply_options.size() == 3 and pd_chk.get_unread_count() > 0,
		"UiPhoneRine 应同步收到 3 个可回复项与未读角标")
	_check(main_node.gesture_helper.is_phone_unread(), "左上角日期手机按钮应显示未读提示")

	# 存档/读档往返验证 RINE 子解释器状态与手机未读状态
	var rine_snap := main_node._build_save_state()
	main_node.vm.reset_vm()
	pd_chk.reset_phone_state()
	_check(main_node.vm.import_state(rine_snap), "RINE 存档快照恢复应成功")
	pd_chk.import_state(rine_snap.get("phone_state", {}) as Dictionary)
	var rs_restored := main_node.vm.get_rine_state()
	_check(bool(rs_restored.get("waiting_reply", false)) and (rs_restored.get("reply_options", []) as Array).size() == 3,
		"读档后 _rndrine.scx 子解释器等待回复状态与选项必须完整保留")
	_check(main_node.vm.get_scr_work(6655) == 162 and main_node.vm.get_flag(2614) == 1,
		"读档后 ScrWork[6655] 与 Flag(2614) 必须保留")
	_check(pd_chk.get_unread_count() >= 1 and main_node.gesture_helper.is_phone_unread(),
		"读档后手机未读角标与左上角未读提示必须保留")

	# 选择第 1 个回复选项 (163 -> L025)，验证子解释器推进后续对话与标志清零
	var pre_msg_cnt: int = (pd_chk._messages_by_contact.get(1, []) as Array).size()
	pd_chk.rine_reply_selected.emit(163)
	var post_msg_cnt: int = (pd_chk._messages_by_contact.get(1, []) as Array).size()
	_check(post_msg_cnt > pre_msg_cnt + 2, "选择回复 163 应驱动 L025 推进多条后续对方消息与贴纸")
	_check(main_node.vm.get_flag(2614) == 0 and main_node.vm.get_flag(2760) == 1,
		"回复分支执行完毕后 Flag(2614)=0 且 Flag(2760)=1")
	pd_chk.rine_sticker_selected.emit(2)
	_check(main_node.vm.get_flag(2615) == 1, "发送贴纸后应保持已读状态")

	# 验证来电铃声播放与真实点击接听/挂断按钮写回 + 铃声精确停止
	var amadeus_btns := pd_chk._amadeus_overlay.find_children("*", "Button", true, false)
	_check(amadeus_btns.size() >= 2, "Amadeus 来电遮罩应包含接听与挂断两个按钮")
	var btn_amadeus_conn := amadeus_btns[0] as Button
	var btn_amadeus_cancel := amadeus_btns[1] as Button
	main_node.vm.set_flag(0x4B6, 1)
	pd_chk._on_phone_event(10, [185])
	pd_chk._on_phone_event(1, [185])
	_check(pd_chk._amadeus_overlay.visible, "Amadeus 来电遮罩应显示")
	_check(main_node.audio.is_se_playing("SGSE700.ogg"), "Amadeus 来电应播放循环铃声 SGSE700.ogg")
	btn_amadeus_conn.pressed.emit()
	_check(not pd_chk._amadeus_overlay.visible and not main_node.audio.is_se_playing("SGSE700.ogg"),
		"点击接听按钮后遮罩应关闭且必须彻底停止铃声")
	_check(main_node.vm.get_flag(0x4B6) == 0 and main_node.vm.get_flag(0x505) == 1,
		"接听 Amadeus 来电应清除 Flag(0x4B6) 并置位 Flag(0x505)=1")
	pd_chk._on_phone_event(10, [185])
	pd_chk._on_phone_event(1, [185])
	_check(main_node.audio.is_se_playing("SGSE700.ogg"), "再次来电应重新播放铃声")
	btn_amadeus_cancel.pressed.emit()
	_check(not pd_chk._amadeus_overlay.visible and not main_node.audio.is_se_playing("SGSE700.ogg"),
		"点击挂断按钮后遮罩应关闭且必须彻底停止铃声")
	_check(main_node.vm.get_flag(0x4B6) == 0 and main_node.vm.get_flag(0x505) == 0,
		"挂断 Amadeus 来电应清除 Flag(0x4B6) 与 Flag(0x505)=0")

	# 先打开真由理(1)聊天查看，清除本轮回复产生的未读计数
	pd_chk._active_contact_idx = 1
	pd_chk.open_phone()
	pd_chk.switch_screen(UiPhoneRine.PhoneScreen.CHAT, false)
	_check(pd_chk.get_unread_count() == 0, "查看真由理(1)聊天后未读应清零")

	# 验证未读角标在关闭手机收信时亮起，并在打开对应联系人聊天后清零
	pd_chk.close_phone()
	pd_chk.switch_screen(UiPhoneRine.PhoneScreen.HOME, false)
	pd_chk._on_rine_event(46, [7, 0, 10])
	_check(pd_chk.get_unread_count() > 0 and pd_chk._home_rine_badge.visible,
		"手机关闭收到铃羽新消息时 RINE 桌面图标未读徽章应亮起")
	_check((pd_chk._contact_badges[7] as Label).visible and main_node.gesture_helper.is_phone_unread(),
		"联系人列表铃羽角标与左上角手机按钮未读提示均应亮起")
	pd_chk.open_phone()
	pd_chk.switch_screen(UiPhoneRine.PhoneScreen.CHAT, false)
	_check(pd_chk.get_unread_count() == 0 and not pd_chk._home_rine_badge.visible,
		"打开对应联系人 RINE 聊天后未读角标应全部清零隐藏")
	_check(not (pd_chk._contact_badges[7] as Label).visible and not main_node.gesture_helper.is_phone_unread(),
		"联系人角标与左上角手机未读提示应同步清零")
	_check(main_node.vm.get_flag(2615) == 1 and main_node.vm.get_flag(2616) == 0,
		"查看已读后 VM Flag(2615)=1 且 Flag(2616)=0")
	print("[10/10] _rndrine.scx sub-interpreter, reply/sticker/Amadeus writeback, unread badges & ringtone stop ok")

	# 11. 回归测试：SKIP/AUTO/WAIT 3D金环帧动画无2D旋转、sub=12不污染伦太郎头像、点进RINE即显初始消息、PhoneCtrl(10,5)+PhoneCtrl(1)不误弹来电、L62贴纸分支
	var m_assets := main_node.theme_loader.get_meswin_assets()
	var auto_fr: Array = m_assets.get("auto_ring_frames", [])
	var skip_fr: Array = m_assets.get("skip_ring_frames", [])
	var wait_fr: Array = m_assets.get("wait_ring_frames", [])
	_check(auto_fr.size() == 20 and skip_fr.size() == 20 and wait_fr.size() == 20,
		"MESWIN.DDS 应切出完整 20 帧 AUTO/SKIP/WAIT 3D 环动画序列")
	main_node.panels.show_dialogue_mode()
	main_node.panels.set_mode_badge(false, true)
	main_node.panels._process(0.12)
	_check(main_node.panels._mode_ring.visible and is_zero_approx(main_node.panels._mode_ring.rotation),
		"快进模式 SKIP 环应使用原版 3D 序列帧且 rotation=0 禁止 2D 倒转畸变")
	main_node.panels.set_mode_badge(false, false)

	# 回归测试2 & 3：sub=12(0,0) 不得把聊天对象篡改为 0(伦太郎)，且未回复前点进 RINE 立即显示初始消息
	pd_chk.reset_phone_state()
	pd_chk.close_phone()
	pd_chk._on_rine_event(46, [1, 0, 162])
	pd_chk._on_rine_event(12, [0, 0])
	pd_chk._on_rine_event(13, [163, 25])
	pd_chk._on_rine_event(14, [])
	_check(pd_chk._active_contact_idx == 1, "sub=12(0,0) 后活跃联系人仍应保持 1(真由理)，绝不可变成 0(伦太郎)")
	pd_chk.open_phone()
	pd_chk._open_rine_app()
	_check(pd_chk._chat_title_label.text == "RINE · 真由理",
		"点进 RINE 顶部标题应显示 RINE · 真由理，实际=%s" % pd_chk._chat_title_label.text)
	_check(pd_chk._msg_list.get_child_count() >= 1,
		"刚点进 RINE 短信功能（未点击回复前）应立即显示初始开场消息，实际子项=%d" % pd_chk._msg_list.get_child_count())

	# 回归测试4a：RINE 收信后的 PhoneCtrl(10, 5) + PhoneCtrl(1) 及主线 PhoneCtrl(10, 230) + PhoneCtrl(5) 绝不得误弹 Amadeus 来电或误停快进
	pd_chk._on_phone_event(10, [5])
	pd_chk._on_phone_event(1, [5])
	_check(not pd_chk._amadeus_overlay.visible,
		"RINE 收信通知 PhoneCtrl(10,5)+PhoneCtrl(1) 绝不可误触发 Amadeus 来电界面")
	main_node._skip_mode = true
	main_node._on_vm_trigger_event(10, [230])
	pd_chk._on_phone_event(10, [230])
	pd_chk._on_phone_event(5, [230])
	_check(not pd_chk._amadeus_overlay.visible and main_node._skip_mode,
		"主线 PhoneCtrl(10, 230) + PhoneCtrl(5) 绝不可误弹 Amadeus 来电或打断快进")
	main_node._skip_mode = false

	# 回归测试4b：从通讯录选定联系人或打开 Amadeus App 切入 CHAT 时，即使真由理(1)有未读消息也不得覆盖用户选择
	pd_chk._unread_by_contact[1] = 1
	pd_chk._open_amadeus_app()
	_check(pd_chk._active_contact_idx == 3 and pd_chk._chat_title_label.text == "RINE · 红莉栖 (Amadeus)",
		"打开 Amadeus App 后应保持联系人 3(红莉栖)，不可被真由理未读覆盖")
	pd_chk._on_contact_pressed(7, "铃羽")
	pd_chk.switch_screen(UiPhoneRine.PhoneScreen.CHAT, false)
	_check(pd_chk._active_contact_idx == 7 and pd_chk._chat_title_label.text == "RINE · 铃羽",
		"在通讯录选中铃羽(7)再切换到 CHAT 时应保持铃羽，不可被真由理未读覆盖")

	# 回归测试4b：sub=12(0,1) 贴纸回复模式 + _rndrine.scx L64->L65 完整推进
	pd_chk.reset_phone_state()
	main_node.vm.reset_vm()
	main_node.vm.load_script_into_slot(11, "_rndrine.scx")
	main_node.vm._handle_rine_ctrl(50, [13]) # 铃羽首次 RINE (_phone L13 = 248)
	main_node.vm._handle_rine_ctrl(46, [7, 0, main_node.vm.get_scr_work(6655)]) # 开场白
	main_node.vm._handle_rine_ctrl(10, [64]) # 启动 L64 贴纸回复
	_check(pd_chk._active_contact_idx == 7 or pd_chk.get_unread_count() > 0,
		"铃羽 RINE 触发后应锁定/提示联系人 7(铃羽)")
	_check(pd_chk._reply_mode == 1 and pd_chk._reply_options.size() == 3,
		"L64 应进入贴纸回复模式 (reply_mode=1, 选项数=3)")
	var ok_st: bool = main_node.vm.submit_rine_sticker(1)
	_check(ok_st and main_node.vm.get_flag(2614) == 0,
		"贴纸回复模式下发送贴纸 1 应推进 L65 分支并清除 Flag(2614)")
	print("[11/11] SKIP/AUTO/WAIT 3D-ring, sub=12/15 sender/avatar, initial RINE display, non-call PhoneCtrl & sticker-reply ok")

	main_node.queue_free()
	if _failed:
		quit(1)
		return
	print("=== PC 1:1 UI & Top-Left HUD Verification PASSED ===")
	quit(0)
