extends SceneTree

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	_run()
	return true


func _run() -> void:
	print("=== Phase 5.1 Full Regression & Stress Verification ===")
	var cfg := ConfigManager.new()
	cfg.load_config()

	# 1. BYOA 失效目录回退测试（不得崩溃，并触发引导面板）
	var bad_vfs := MgsVfs.new()
	var bad_ok := bad_vfs.mount_explicit("U:/anti/temp/SteinsGate0_iOS/__nonexistent_dir__", "")
	assert(not bad_ok and not bad_vfs.is_mounted, "无效目录不应挂载成功")
	var loader := UiThemeLoader.new()
	var panels := UiPanels.new()
	get_root().add_child(panels)
	var bad_vm := Sc3Vm.new(bad_vfs)
	panels.setup(bad_vfs, bad_vm, cfg, loader)
	panels.show_byoa_wizard(bad_vfs.get_candidate_game_dirs(cfg))
	assert(panels._byoa_view.visible, "缺失资源时应弹出 BYOA 引导面板")
	print("BYOA fallback wizard ok")
	panels.queue_free()

	# 2. 显式挂载真实 STEINS;GATE 0 资产与电影目录
	var vfs := MgsVfs.new()
	var ok := vfs.mount_explicit(
		"U:/anti/projects/STEINS GATE 0/USRDIR",
		"U:/anti/temp/SteinsGate0_iOS/SteinsGate0_iOS_Documents/movie"
	)
	assert(ok and vfs.is_mounted, "显式挂载真实资产失败")
	assert(vfs.get_movie_names().size() >= 30, ".ogv 电影数量异常: %d" % vfs.get_movie_names().size())
	print("Explicit BYOA mount ok: movies=", vfs.get_movie_names().size())

	# 3. 多章节 SC3 推进回归（SG0_00_01 / SG0_A03_11 / SG0_01_01）
	var vm := Sc3Vm.new(vfs)
	var stage := MgsStage.new()
	get_root().add_child(stage)
	stage.bind_vfs(vfs)
	stage.bind_vm(vm)

	var dlg_total := [0]
	var bg_total := [0]
	var chara_total := [0]
	var voice_total := [0]
	vm.dialogue_shown.connect(func(_b, _o, _c, vid: int, _s, _r):
		dlg_total[0] += 1
		if vid >= 0:
			voice_total[0] += 1
	)
	vm.bg_changed.connect(func(_l, _id): bg_total[0] += 1)
	vm.chara_loaded.connect(func(_sl, _ci, _gh): chara_total[0] += 1)

	for sname in ["SG0_00_01.scx", "SG0_A03_11.scx", "SG0_01_01.scx"]:
		assert(vfs.has_entry("script.mpk", sname), "缺少剧本: " + sname)
		vm.start_boot_script()
		for _f in range(15):
			vm.step_frame(1)
		assert(vm.jump_to_script(sname, 0), "跳转剧本失败: " + sname)
		var local_clicks := 0
		for _step in range(360):
			vm.step_frame(1)
			if vm.is_waiting_for_click():
				local_clicks += 1
				vm.notify_user_advance()
				if local_clicks >= 6:
					break
			elif vm.is_waiting_for_choice():
				vm.submit_choice(0)
				break
		assert(local_clicks >= 2, "%s 推进对话次数过少: %d" % [sname, local_clicks])
		print("Chapter progressed ok: ", sname, " clicks=", local_clicks)

	assert(dlg_total[0] >= 12 and bg_total[0] >= 3 and chara_total[0] >= 2 and voice_total[0] >= 2,
		"多章节信号统计异常 dlg=%d bg=%d chara=%d voice=%d" % [dlg_total[0], bg_total[0], chara_total[0], voice_total[0]])

	# 验证读档状态导出/导入与舞台同步恢复
	var saved_state := vm.export_state()
	assert(not saved_state.is_empty(), "状态导出不应为空")
	assert(vm.import_state(saved_state), "状态导入恢复失败")
	print("Save/Load VM snapshot roundtrip ok")

	# 4. 缓存压测与 iOS 低内存告警释放验证（<= 140MB 上限，告警后缩至 <= 40%）
	var cache := stage.get_cache()
	var bg_names := vfs.list_entries("bg.mpk", "")
	var loaded_bgs := 0
	for bn in bg_names:
		if bn.to_lower().ends_with(".png"):
			var idx := -1
			for bi in range(bg_names.size()):
				if bg_names[bi] == bn:
					idx = bi
					break
			if idx >= 0 and stage.load_bg_by_index(0, idx):
				loaded_bgs += 1
				if loaded_bgs >= 24:
					break
	var peak_bytes := cache.get_used_bytes()
	print("Cache stress after %d BGs: used_bytes=%d (limit=%d)" % [loaded_bgs, peak_bytes, MgsCache.DEFAULT_MAX_BYTES])
	assert(peak_bytes <= MgsCache.DEFAULT_MAX_BYTES, "缓存超出 140MB 上限: %d" % peak_bytes)
	assert(peak_bytes > 40 * 1024 * 1024, "压测未充分填充缓存: %d" % peak_bytes)

	var after_low := stage.on_low_memory()
	var max_after_low := int(float(MgsCache.DEFAULT_MAX_BYTES) * 0.40) + 1024
	print("Cache after on_low_memory(): used_bytes=%d (max_allowed=%d)" % [after_low, max_after_low])
	assert(after_low <= max_after_low, "低内存回收后仍超过 40%% 上限: %d" % after_low)

	stage.reset_stage()
	stage.queue_free()
	print("=== Phase 5.1 Verification PASSED ===")
	quit(0)
