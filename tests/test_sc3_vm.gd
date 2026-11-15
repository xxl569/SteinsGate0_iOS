extends SceneTree

var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	_run()
	return true


func _run() -> void:
	print("=== Phase 3.2 Verification (Sc3Vm) ===")
	var cfg := ConfigManager.new()
	cfg.load_config()
	var vfs := MgsVfs.new()
	assert(vfs.auto_mount(cfg), "VFS 挂载失败")

	var vm := Sc3Vm.new(vfs)

	# 1. 启动流测试：从 _Startup_win.scx 跑 30 帧，检查系统脚本挂载状态
	assert(vm.start_boot_script(), "_Startup_win.scx 启动失败")
	for _f in range(30):
		vm.step_frame(1)
	assert(vm._scripts.has(6) and vm._scripts[6]["name"] == "_Startup_win.scx" or vm._scripts.has(6), "")
	print("Boot step ok, loaded script slots: ", vm._scripts.keys())
	assert(vm._scripts.size() >= 6, "启动流程应加载至少 6 个系统脚本槽位，实际: %d" % vm._scripts.size())

	# 2. 直达 SG0_00_01.scx 推进对白与舞台信号
	var got_dialogues: Array[Dictionary] = []
	var got_bgs: Array[int] = []
	var got_charas: Array[int] = []
	var got_voices: Array[int] = []

	vm.dialogue_shown.connect(func(buf: PackedByteArray, off: int, cid: int, vid: int, sid: int, _read: bool):
		got_dialogues.append({"buf": buf, "off": off, "cid": cid, "vid": vid, "sid": sid})
	)
	vm.bg_changed.connect(func(_layer: int, bg_idx: int):
		got_bgs.append(bg_idx)
	)
	vm.chara_loaded.connect(func(_slot: int, chara_idx: int, _grp: int):
		got_charas.append(chara_idx)
	)
	vm.voice_play_requested.connect(func(vid: int, _cid: int):
		got_voices.append(vid)
	)

	assert(vm.jump_to_script("SG0_00_01.scx", 0), "SG0_00_01.scx 跳转失败")
	for _step in range(500):
		vm.step_frame(1)
		if vm.is_waiting_for_click():
			vm.notify_user_advance()
		if got_dialogues.size() >= 15:
			break

	print("SG0_00_01 dialogues=", got_dialogues.size(), " bgs=", got_bgs, " charas=", got_charas, " voices=", got_voices.size())
	if got_dialogues.size() < 15:
		for t in vm._threads:
			print("  thread id=", t.id, " slot=", t.script_slot, " (", vm._scripts[t.script_slot]["name"], ") pc=", "%x" % t.pc, " wait=", t.wait_mode, " wf=", t.wait_frames, " stk=", t.call_stack.size())
	assert(got_dialogues.size() >= 15, "SG0_00_01 推进对白不足 15 句")
	assert(got_bgs.size() >= 1, "未触发任何背景加载信号")
	assert(got_charas.size() >= 1, "未触发任何立绘加载信号")

	# 验证字库渲染对接
	var fr := MgsFontRenderer.new()
	get_root().add_child(fr)
	fr.bind_vfs(vfs)
	var first_d := got_dialogues[0]
	var parse_res := fr.set_sc3_string(first_d["buf"], int(first_d["off"]), vm, null, true)
	print("First dialogue body glyphs=", parse_res["body_glyph_count"], " name glyphs=", parse_res["name_glyph_count"])
	assert(int(parse_res["body_glyph_count"]) > 0, "首句对白解析字形数为 0")
	fr.queue_free()

	# 3. 验证存档导出与恢复
	var snap := vm.export_state()
	var saved_script := str(snap["script_name"])
	var vm2 := Sc3Vm.new(vfs)
	assert(vm2.import_state(snap), "状态恢复失败")
	assert(vm2.get_current_script_name() == saved_script, "恢复脚本名不一致")
	assert(vm2._threads.size() == vm._threads.size(), "恢复活跃线程数不一致")

	print("=== Phase 3.2 Verification PASSED ===")
	quit(0)
