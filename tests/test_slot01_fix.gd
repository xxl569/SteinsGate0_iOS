extends SceneTree

var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	_run()
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		printerr("FATAL REGRESSION ASSERTION FAILED: ", message)
		quit(1)
		assert(false, message)


func _run() -> void:
	print("=== Test Slot 01 Fix: Save and Load No. 01 (slot_01.json) in SG0_01_03 ===")

	var cfg := ConfigManager.new()
	cfg.load_config()
	var vfs := MgsVfs.new()
	_check(vfs.auto_mount(cfg), "VFS mount failed")

	var scene := load("res://scenes/main.tscn") as PackedScene
	_check(scene != null, "main.tscn load failed")
	var main_node := scene.instantiate() as MainController
	_check(main_node != null, "MainController instantiate failed")
	get_root().add_child(main_node)

	# 备份已有的 slot_01.json（若存在）以便测试后恢复
	var backup_slot1_meta: Dictionary = UiPanels.read_slot_meta(1)
	var backup_slot1_path := UiPanels.get_slot_path(1)
	var backup_slot1_str := ""
	if FileAccess.file_exists(backup_slot1_path):
		backup_slot1_str = FileAccess.get_file_as_string(backup_slot1_path)

	# 1. 确保 slot_00 不存在
	if FileAccess.file_exists(UiPanels.get_slot_path(0)):
		DirAccess.remove_absolute(UiPanels.get_slot_path(0))

	# 2. 启动游戏并推进到 SG0_01_03.scx
	print("Starting new game and advancing to SG0_01_03.scx...")
	main_node.start_new_game()
	for _s in range(60000):
		main_node.vm.step_frame(1)
		if main_node.video.is_movie_playing():
			main_node.video.stop_movie(true)
		elif main_node.vm.is_waiting_for_movie():
			main_node.vm.notify_movie_finished()
		if main_node.vm.is_waiting_for_click():
			if main_node.vm.get_current_script_name() == "SG0_01_03.scx":
				break
			main_node.panels.reveal_dialogue_instant()
			main_node.vm.notify_user_advance()

	_check(main_node.vm.get_current_script_name() == "SG0_01_03.scx", "未能到达 SG0_01_03.scx")

	# 在 SG0_01_03 中推进 8 句对话，使立绘与场景完全展开
	print("Advancing 8 lines in SG0_01_03...")
	for _k in range(8):
		main_node.panels.reveal_dialogue_instant()
		main_node.vm.notify_user_advance()
		for _f in range(3000):
			main_node.vm.step_frame(1)
			if main_node.vm.is_waiting_for_click():
				break

	# 记录保存时的原始精确状态
	var saved_script := main_node.vm.get_current_script_name()
	var saved_dlg := main_node._last_dialogue_entry.duplicate(true)
	var saved_pc := int(main_node.vm._threads[0].pc)
	var saved_backlog_size := main_node.vm.backlog.size()
	var saved_stage_st := main_node.stage.export_state()
	print("Target save point: script=", saved_script, " pc=", saved_pc, " dlg=", saved_dlg)

	# 3. 打开 SAVE 面板，验证卡片 0 标号为 No. 01
	main_node.panels.open_saveload(true)
	var sl_panel := main_node.panels._saveload_view
	_check(sl_panel.visible, "SaveLoad panel should be visible")
	var card0: Dictionary = sl_panel._slot_cards[0]
	var card0_lbl: String = (card0["lbl_no"] as Label).text
	_check(card0_lbl == "No. 01", "卡片 0 标号应为 No. 01，当前为: " + card0_lbl)

	# 4. 点击卡片 0 执行存盘
	print("Clicking Card 0 (No. 01) to save...")
	var saved_emitted_slot := [-1]
	var conn_save := func(slot: int): saved_emitted_slot[0] = slot
	sl_panel.save_slot_requested.connect(conn_save)
	sl_panel._on_slot_clicked(0)
	sl_panel.save_slot_requested.disconnect(conn_save)

	_check(saved_emitted_slot[0] == 1, "卡片 0 点击应触发 1 号物理槽存档，实际为: %d" % saved_emitted_slot[0])
	main_node._on_save_slot(saved_emitted_slot[0])

	# 验证写入物理文件
	_check(FileAccess.file_exists(UiPanels.get_slot_path(1)), "slot_01.json 必须存在")
	_check(not FileAccess.file_exists(UiPanels.get_slot_path(0)), "slot_00.json 不应被写入或存在")

	var meta1 := UiPanels.read_slot_meta(1)
	_check(meta1.get("slot_id") == 1, "元数据 slot_id 应为 1")
	_check(str(meta1.get("script_name")) == "SG0_01_03.scx", "元数据 script_name 应为 SG0_01_03.scx")
	var summary_text := str(meta1.get("summary"))
	print("Saved slot 1 summary: ", summary_text)
	_check(summary_text.begins_with("SG0_01_03 对白回顾"), "存档摘要应以 'SG0_01_03 对白回顾' 开头，实际为: " + summary_text)

	# 5. 继续向前推进 10 句对话改变现场状态
	print("Advancing 10 more lines to change game state...")
	for _k in range(10):
		main_node.panels.reveal_dialogue_instant()
		main_node.vm.notify_user_advance()
		for _f in range(3000):
			main_node.vm.step_frame(1)
			if main_node.vm.is_waiting_for_click():
				break

	print("Current altered position: pc=", main_node.vm._threads[0].pc, " dlg=", main_node._last_dialogue_entry)
	_check(main_node.vm._threads[0].pc != saved_pc, "推进后 PC 应改变")

	# 6. 返回标题界面
	print("Returning to Title...")
	main_node.return_to_title()
	_check(not main_node._running_story, "应处于标题非剧情状态")

	# 7. 从标题界面打开 LOAD 面板，验证卡片 0 显示 No. 01 与真实摘要
	main_node.panels.open_saveload(false)
	_check(sl_panel.visible, "Load panel should be visible")
	var card0_load: Dictionary = sl_panel._slot_cards[0]
	var title_lbl: String = (card0_load["lbl_title"] as Label).text
	print("Card 0 title on LOAD panel: ", title_lbl)
	_check(title_lbl.begins_with("SG0_01_03 对白回顾"), "卡片 0 标题应以 'SG0_01_03 对白回顾' 开头，实际为: " + title_lbl)

	# 8. 点击卡片 0 读档
	print("Clicking Card 0 to load...")
	var loaded_emitted_slot := [-1]
	var conn_load := func(slot: int): loaded_emitted_slot[0] = slot
	sl_panel.load_slot_requested.connect(conn_load)
	sl_panel._on_slot_clicked(0)
	sl_panel.load_slot_requested.disconnect(conn_load)

	_check(loaded_emitted_slot[0] == 1, "卡片 0 点击应触发 1 号物理槽读档，实际为: %d" % loaded_emitted_slot[0])
	main_node._on_load_slot(loaded_emitted_slot[0])

	# 9. 断言 100% 精确还原
	print("Verifying restored state after loading No. 01...")
	_check(main_node._running_story, "剧情状态应恢复为 running")
	_check(main_node.vm.get_current_script_name() == saved_script, "脚本应恢复为: " + saved_script)
	_check(int(main_node.vm._threads[0].pc) == saved_pc, "PC 应完全恢复为: %d，实际为: %d" % [saved_pc, main_node.vm._threads[0].pc])
	_check(main_node._last_dialogue_entry.get("str_offset") == saved_dlg.get("str_offset"), "对白偏移量应一致")
	_check(main_node._last_dialogue_entry.get("str_id") == saved_dlg.get("str_id"), "对白 str_id 应一致")
	_check(main_node.vm.backlog.size() == saved_backlog_size, "Backlog 数量应完全一致")
	_check(main_node.vm.is_waiting_for_click(), "读档后主线程必须处于对白等待点击状态 (wait_mode==MES_SYNC)")

	# 10. 测试推进一步，验证恢复后游戏可正常平稳前进
	print("Advancing 1 line from restored state...")
	main_node._on_user_advance()
	for _f in range(50):
		main_node.vm.step_frame(1)
		if main_node.vm.is_waiting_for_click():
			break
	_check(main_node.vm._threads[0].pc != saved_pc, "用户点击后剧情应正常前进")
	print("Next line reached: pc=", main_node.vm._threads[0].pc, " dlg=", main_node._last_dialogue_entry)

	# 11. 测试旧存档 slot_00.json 自动无缝迁移至 slot_01.json
	print("Testing legacy slot_00.json migration to slot_01.json...")
	if FileAccess.file_exists(UiPanels.get_slot_path(0)):
		DirAccess.remove_absolute(UiPanels.get_slot_path(0))
	if FileAccess.file_exists(UiPanels.get_slot_path(1)):
		DirAccess.remove_absolute(UiPanels.get_slot_path(1))
	if FileAccess.file_exists(UiPanels.get_slot_thumb_path(0)):
		DirAccess.remove_absolute(UiPanels.get_slot_thumb_path(0))
	if FileAccess.file_exists(UiPanels.get_slot_thumb_path(1)):
		DirAccess.remove_absolute(UiPanels.get_slot_thumb_path(1))

	var legacy_payload := {
		"slot_id": 0,
		"timestamp": "2026/01/01 00:00:00",
		"play_time_sec": 123,
		"locked": false,
		"script_name": "SG0_00_01.scx",
		"summary": "旧版槽位0迁移测试",
		"vm_state": {}
	}
	var f_legacy := FileAccess.open(UiPanels.get_slot_path(0), FileAccess.WRITE)
	_check(f_legacy != null, "旧存档创建失败")
	f_legacy.store_string(JSON.stringify(legacy_payload))
	f_legacy.close()

	var f_legacy_thumb := FileAccess.open(UiPanels.get_slot_thumb_path(0), FileAccess.WRITE)
	_check(f_legacy_thumb != null, "旧缩略图创建失败")
	f_legacy_thumb.store_string("fake_png")
	f_legacy_thumb.close()

	UiPanels._legacy_slot0_checked = false
	UiPanels._migrate_legacy_slot0()

	_check(FileAccess.file_exists(UiPanels.get_slot_path(1)), "迁移后 slot_01.json 必须存在")
	_check(not FileAccess.file_exists(UiPanels.get_slot_path(0)), "迁移后 slot_00.json 必须已被移除")
	_check(FileAccess.file_exists(UiPanels.get_slot_thumb_path(1)), "迁移后 slot_01.png 必须存在")
	_check(not FileAccess.file_exists(UiPanels.get_slot_thumb_path(0)), "迁移后 slot_00.png 必须已被转移")

	var migrated_meta := UiPanels.read_slot_meta(1)
	_check(migrated_meta.get("slot_id") == 1, "迁移后 slot_id 应更新为 1")
	_check(str(migrated_meta.get("summary")) == "旧版槽位0迁移测试", "迁移后 summary 内容应保留")
	print("Legacy migration test PASSED.")

	DirAccess.remove_absolute(UiPanels.get_slot_path(1))
	DirAccess.remove_absolute(UiPanels.get_slot_thumb_path(1))

	# 12. 测试 Continue 全局时间戳裁决（1..48 号手动槽位与 99 号自动槽位）
	print("Testing continue requested global timestamp arbitration...")
	var dummy_state := main_node._build_save_state()

	for sid in [1, 2, 99]:
		var sp := UiPanels.get_slot_path(sid)
		if FileAccess.file_exists(sp):
			DirAccess.remove_absolute(sp)

	# 场景 A: 1 号手动存档更旧 (10:00:00)，99 号自动存档更新 (12:00:00) -> 裁决加载 99 号槽
	UiPanels.write_slot_data(1, dummy_state, "手动1号", 101)
	var m_s1 := UiPanels.read_slot_meta(1)
	m_s1["timestamp"] = "2099/01/01 10:00:00"
	var f_s1 := FileAccess.open(UiPanels.get_slot_path(1), FileAccess.WRITE)
	f_s1.store_string(JSON.stringify(m_s1))
	f_s1.close()

	UiPanels.write_slot_data(99, dummy_state, "自动99号", 999)
	var m_s99 := UiPanels.read_slot_meta(99)
	m_s99["timestamp"] = "2099/01/01 12:00:00"
	var f_s99 := FileAccess.open(UiPanels.get_slot_path(99), FileAccess.WRITE)
	f_s99.store_string(JSON.stringify(m_s99))
	f_s99.close()

	main_node._on_continue_requested()
	_check(is_equal_approx(main_node._play_time_sec, 999.0), "裁决 A 失败：99号自动存档时间戳更新，Continue 应加载99号槽，当前 play_time=%f" % main_node._play_time_sec)
	print("Timestamp arbitration Case A (auto 99 is newer) PASSED.")

	# 场景 B: 2 号手动存档更新 (14:00:00) -> 裁决加载 2 号槽
	UiPanels.write_slot_data(2, dummy_state, "手动2号", 202)
	var m_s2 := UiPanels.read_slot_meta(2)
	m_s2["timestamp"] = "2099/01/01 14:00:00"
	var f_s2 := FileAccess.open(UiPanels.get_slot_path(2), FileAccess.WRITE)
	f_s2.store_string(JSON.stringify(m_s2))
	f_s2.close()

	main_node._on_continue_requested()
	_check(is_equal_approx(main_node._play_time_sec, 202.0), "裁决 B 失败：2号手动存档时间戳更新，Continue 应加载2号槽，当前 play_time=%f" % main_node._play_time_sec)
	print("Timestamp arbitration Case B (manual 2 is newer) PASSED.")

	# 清理时间戳测试槽位
	for sid in [1, 2, 99]:
		var sp := UiPanels.get_slot_path(sid)
		if FileAccess.file_exists(sp):
			DirAccess.remove_absolute(sp)

	# 13. 恢复备份或清理
	if backup_slot1_str != "":
		var f := FileAccess.open(backup_slot1_path, FileAccess.WRITE)
		if f != null:
			f.store_string(backup_slot1_str)
			f.close()
	else:
		DirAccess.remove_absolute(backup_slot1_path)

	main_node.queue_free()
	print("=== Test Slot 01 Fix PASSED SUCCESSFULLY ===")
	quit(0)
