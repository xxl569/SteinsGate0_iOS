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
		for _step in range(1800):
			vm.step_frame(1)
			if vm.is_waiting_for_movie() or vm._movie_playing:
				vm.notify_movie_finished()
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

	# 5. AV 与立绘防回归专项校验（真实 BGM 25 / 无 0018 重复 SE 爆音 / 0033 开场计时等待 / 视频表 IMV008 / 立绘静止不跳动）
	var audio_chk := MgsAudioMgr.new()
	get_root().add_child(audio_chk)
	audio_chk.bind_vfs(vfs)
	audio_chk.apply_config(cfg)
	assert(vfs.get_movie_path_by_index(11).get_file().to_lower() == "imv008.ogv", "视频表索引 11 应固定映射 IMV008.ogv")
	var vm_av := Sc3Vm.new(vfs)
	var av_bgms: Array[int] = []
	var av_ses: Array[int] = []
	var av_movies: Array[int] = []
	vm_av.bgm_play_requested.connect(func(idx: int, _lp: bool, _fd: int): av_bgms.append(idx))
	vm_av.se_play_requested.connect(func(idx: int, _lp: bool): av_ses.append(idx))
	vm_av.movie_play_requested.connect(func(idx: int): av_movies.append(idx))
	vm_av.start_boot_script()
	for _f in range(15):
		vm_av.step_frame(1)
	assert(av_ses.is_empty(), "启动阶段不应再因 0x0018 误触重复 SE 爆音，实际: %s" % [str(av_ses)])
	assert(vm_av.jump_to_script("SG0_00_01.scx", 0), "AV 校验跳转 SG0_00_01 失败")
	var dlg_tick := -1
	for tk in range(2200):
		vm_av.step_frame(1)
		if vm_av.is_waiting_for_movie() or vm_av._movie_playing:
			vm_av.notify_movie_finished()
		if vm_av.is_waiting_for_click():
			dlg_tick = tk
			break
	assert(dlg_tick >= 200, "开场 0x0033 过场等待应正常生效（>=200帧），实际仅: %d" % dlg_tick)
	assert(av_bgms.has(25), "SG0_00_01 开场应通过 0x0021 触发 BGM 25 (bgm213.ogg)，实际: %s" % [str(av_bgms)])
	assert(av_ses.size() <= 5, "SG0_00_01 开场 SE 触发次数异常过多: %s" % [str(av_ses)])
	assert(av_movies.has(11), "SG0_00_01 开场应触发 IMV008 (idx=11)")
	# 检查 MgsStage 立绘绝对静止（无垂直 sin 呼吸抖动与口型 Y 轴拉伸）
	assert(stage.load_chara(16, 674, 3), "加载测试立绘失败")
	var sp_chk: Sprite2D = stage._chara_slots[16]["sprite"]
	var y_before := sp_chk.position.y
	var s_before := sp_chk.scale
	stage._process(0.45)
	stage.update_lip_sync(2)
	assert(absf(sp_chk.position.y - y_before) < 0.001, "立绘不应出现垂直跳动")
	assert(sp_chk.scale == s_before and sp_chk.scale == MgsStage.CHARA_DISPLAY_SCALE, "立绘不应在说话时发生拉伸变形")
	print("AV & static portrait parity ok: dlg_tick=%d bgms=%s ses=%s movies=%s" % [dlg_tick, str(av_bgms), str(av_ses), str(av_movies)])

	# 6. 序章全流程连贯跳转 (MAIN00 -> SG0_00_01 -> SG0_00_02) 与 MgsVideoPlayer EOF 看门狗/触控防卡死校验
	assert(vm_av.jump_to_script("MAIN00.scx", 2), "MAIN00 label 2 起步失败")
	var m0_switched: Array[String] = []
	vm_av.script_switched.connect(func(sn: String): m0_switched.append(sn))
	for _t in range(4500):
		vm_av.step_frame(1)
		if vm_av.is_waiting_for_movie() or vm_av._movie_playing:
			vm_av.notify_movie_finished()
		if vm_av.is_waiting_for_click():
			vm_av.notify_user_advance()
			if m0_switched.has("SG0_00_02.scx") and vm_av.backlog.size() >= 97:
				break
	assert(m0_switched.has("SG0_00_01.scx") and m0_switched.has("SG0_00_02.scx"),
		"MAIN00 未能从 SG0_00_01 自动过渡到 SG0_00_02，实际切换: %s" % [str(m0_switched)])

	# 7. 立绘释放 / 纯色背景 / 日期变量 11/23 防回归校验
	var st_reg := MgsStage.new()
	get_root().add_child(st_reg)
	st_reg.bind_vfs(vfs)
	var vm_reg := Sc3Vm.new(vfs)
	st_reg.bind_vm(vm_reg)
	vm_reg.start_boot_script()
	for _f in range(15):
		vm_reg.step_frame(1)
	assert(vm_reg.jump_to_script("MAIN00.scx", 2), "回归验证跳转 MAIN00 失败")
	var checked_str23 := false
	var checked_multi := false
	var checked_bg376_zoom := false
	var entered_02 := false
	for _t in range(4500):
		vm_reg.step_frame(1)
		if vm_reg.is_waiting_for_movie() or vm_reg._movie_playing:
			vm_reg.notify_movie_finished()
		var cur_sc := ""
		if vm_reg._threads.size() > 0:
			var sc_slot: int = vm_reg._threads[0].script_slot
			if vm_reg._scripts.has(sc_slot):
				cur_sc = str(vm_reg._scripts[sc_slot]["name"])
		if cur_sc == "SG0_00_01.scx" and not checked_bg376_zoom and vm_reg.get_scr_work(4507) == 376 and vm_reg.get_scr_work(4509) == 2:
			checked_bg376_zoom = true
			var z376 := vm_reg.get_scr_work(4504)
			assert(z376 >= 1000 and z376 <= 2000, "CreateThread+WaitFlag 同步后 BG 376 缩放应 <=2000，实际: %d" % z376)
		if cur_sc == "SG0_00_01.scx" and not checked_multi and vm_reg.backlog.size() >= 10:
			var vis_xs: Array[float] = []
			for sid in st_reg._chara_slots.keys():
				var sp_k := st_reg._chara_slots[sid].get("sprite", null) as Sprite2D
				if is_instance_valid(sp_k) and sp_k.visible:
					assert(int(sid) < 16, "暂存立绘槽 %d 不应直接在前台显示" % int(sid))
					vis_xs.append(sp_k.position.x)
			if vis_xs.size() >= 2:
				checked_multi = true
				var all_same := true
				for vx in vis_xs:
					if absf(vx - vis_xs[0]) > 5.0:
						all_same = false
				assert(not all_same, "同屏多名角色不应叠在同一 X 坐标: %s" % str(vis_xs))
		if cur_sc == "SG0_00_01.scx" and not checked_str23 and vm_reg.backlog.size() >= 24:
			checked_str23 = true
			assert(st_reg.get_chara_count() <= 2, "SG0_00_01 str=23 后桶子应已释放，剩余立绘数: %d" % st_reg.get_chara_count())
		if cur_sc == "SG0_00_02.scx" and vm_reg.is_waiting_for_click():
			entered_02 = true
			break
		if vm_reg.is_waiting_for_click():
			vm_reg.notify_user_advance()
	assert(entered_02, "回归验证未能进入 SG0_00_02.scx 首句")
	assert(checked_bg376_zoom, "未能校验 SG0_00_01 开篇天空 BG 376 缩放同步状态")
	# 校验 MgsStage 脚本驱动 BG 渐入 (mode=1, prog=128 -> alpha≈0.5) 与 draw_mode=2 缩放
	st_reg.load_bg_by_index(1, 392)
	vm_reg.set_scr_work(4540 + 11, 1)
	vm_reg.set_scr_work(4540 + 10, 128)
	vm_reg.set_scr_work(4540 + 9, 2)
	vm_reg.set_scr_work(4540 + 4, 2000)
	st_reg._process(0.016)
	var sp1 := st_reg._bg_layers[1]["sprite"] as Sprite2D
	assert(sp1.visible and absf(sp1.modulate.a - 0.5) < 0.02 and sp1.scale == Vector2(2.0, 2.0),
		"MgsStage 未按 ScrWork[4550/4551/4544/4549] 同步 BG1 淡入与缩放: vis=%s a=%.2f sc=%s" % [str(sp1.visible), sp1.modulate.a, str(sp1.scale)])
	assert(st_reg._bg_layers.has(0) and is_instance_valid(st_reg._bg_layers[0].get("sprite", null)) and (st_reg._bg_layers[0]["sprite"] as Sprite2D).visible,
		"进入 SG0_00_02 UPX 场景后 0 号背景层必须可见，防止 10:02+10:10 导致黑屏")
	assert(st_reg.get_chara_count() == 0, "进入 SG0_00_02 UPX 场景后上一幕立绘必须已全部释放，实际: %d" % st_reg.get_chara_count())
	assert(vm_reg.get_scr_work(11) == 2010 and vm_reg.get_scr_work(12) == 11 and vm_reg.get_scr_work(13) == 23,
		"SG0_00_02 应计算出日期 2010/11/23，实际: %d/%d/%d" % [vm_reg.get_scr_work(11), vm_reg.get_scr_work(12), vm_reg.get_scr_work(13)])
	st_reg.load_bg_color(0, Color(0, 0, 0, 1))
	assert(st_reg.get_bg_count() >= 1, "纯色黑屏 SG0_BgChaCtrl 应在舞台生成背景色块层")
	st_reg.reset_stage()
	st_reg.queue_free()
	print("Portrait release, solid color BG & 2010/11/23 date parity ok")

	var vp_chk := MgsVideoPlayer.new()
	get_root().add_child(vp_chk)
	vp_chk.bind_vfs(vfs)
	vp_chk.bind_vm(vm_av)
	assert(vp_chk.play_movie(11), "MgsVideoPlayer 播放 IMV008 失败")
	# 模拟播放器在末尾漏发 finished 信号（_player.stop() 后 _is_playing 仍为 true），验证 EOF 看门狗自动解除卡死
	vp_chk._player.stop()
	vp_chk._play_elapsed = 0.5
	vp_chk._process(0.016)
	assert(not vp_chk.is_movie_playing() and not vp_chk.visible, "EOF 看门狗未在停播后自动收尾释放遮罩")
	vp_chk.queue_free()
	print("MAIN00 chapter chain & VideoPlayer EOF watchdog ok: switched=%s" % [str(m0_switched)])

	audio_chk.stop_bgm(0)
	audio_chk.stop_se(-1)
	audio_chk.queue_free()
	stage.reset_stage()
	stage.queue_free()
	print("=== Phase 5.1 Verification PASSED ===")
	quit(0)
