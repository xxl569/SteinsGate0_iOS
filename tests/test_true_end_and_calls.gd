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
		printerr("TEST FAILED: ", message)
		quit(1)
		assert(false, message)


func _run() -> void:
	print("=== Running End-to-End Tests: True End, Opcode 0x54/0x56, RINE, Safe Area ===")

	var cfg := ConfigManager.new()
	cfg.load_config()
	var vfs := MgsVfs.new()
	_check(vfs.auto_mount(cfg), "VFS mount failed")

	# =========================================================================
	# TEST 1: P0-1 全局系统标志持久化与二周目真结局 D-Rine 闭环
	# =========================================================================
	print("\n--- Test 1: P0-1 System Flags Persistence & True End D-Rine Loop ---")
	var vm := Sc3Vm.new(vfs)

	# 1.1 系统标志范围判定与写入保存
	_check(Sc3Vm.is_system_flag(800), "Flag 800 should be system flag")
	_check(Sc3Vm.is_system_flag(867), "Flag 867 should be system flag")
	_check(Sc3Vm.is_system_flag(899), "Flag 899 should be system flag")
	_check(not Sc3Vm.is_system_flag(799), "Flag 799 should not be system flag")
	_check(not Sc3Vm.is_system_flag(900), "Flag 900 should not be system flag")

	# 清理旧持久文件确保从头测试
	if FileAccess.file_exists(Sc3Vm.SYSTEM_FLAGS_PATH):
		DirAccess.remove_absolute(Sc3Vm.SYSTEM_FLAGS_PATH)

	# 设置普通标志与系统标志
	vm.set_flag(100, 1) # 普通剧情标志
	vm.set_flag(801, 1) # 结局 1 达成标志
	vm.set_flag(867, 1) # A 线通关标志
	_check(FileAccess.file_exists(Sc3Vm.SYSTEM_FLAGS_PATH), "system_flags.json 应在 set_flag(867, 1) 后自动持久化")

	# 1.2 reset_vm() 不抹除系统标志，只抹除非系统标志
	vm.reset_vm()
	_check(vm.get_flag(100) == 0, "reset_vm() 应清除普通标志 Flag[100]")
	_check(vm.get_flag(801) == 1, "reset_vm() 不得抹除结局标志 Flag[801]")
	_check(vm.get_flag(867) == 1, "reset_vm() 不得抹除 A 线通关标志 Flag[867]")

	# 1.3 import_state() 读档时合入持久化标志，且不被存档内过期的系统标志污染
	var dummy_state := {
		"loaded_slots": {},
		"active_slot": 0,
		"scr_work": {},
		"flags": [200, 300, 805], # 805 为未持久化的过期伪系统标志
		"unlocked_tips": [],
		"threads": []
	}
	_check(vm.import_state(dummy_state), "import_state failed")
	_check(vm.get_flag(200) == 1, "import_state 恢复了 Flag[200]")
	_check(vm.get_flag(867) == 1, "import_state 读入旧档后 Flag[867] 依然应保持为 1")
	_check(vm.get_flag(801) == 1, "import_state 读入旧档后 Flag[801] 依然应保持为 1")
	_check(vm.get_flag(805) == 0, "import_state 不得被旧存档中过期的系统标志 Flag[805] 污染")

	# 1.4 export_state() 校验：系统标志与普通槽位存档解耦，不向存档外泄全局标志
	var exported := vm.export_state()
	var exp_flags: Array = exported.get("flags", [])
	_check(200 in exp_flags, "普通剧情标志 Flag[200] 应保存在槽位存档中")
	_check(not (867 in exp_flags), "系统标志 Flag[867] 不得外泄至普通槽位存档中")
	_check(not (801 in exp_flags), "系统标志 Flag[801] 不得外泄至普通槽位存档中")

	# 1.5 神社场景 (SG0_01_08.scx) 二周目 D-Rine 闭环验证
	# 在 SG0_01_08.scx 中，pc=0x2ca8 处为 00:10 (JumpIfFlag cond=0 flag=867 label=18)
	# 若 Flag[867]=0 (一周目)，跳转到 label 18 跳过 D-Rine，Flag[602] 保持为 0
	# 若 Flag[867]=1 (二周目)，不跳转并顺流执行置位 Flag[602]=1，解锁真结局
	_check(vm.load_script_into_slot(3, "SG0_01_08.scx"), "Failed to load SG0_01_08.scx")
	var s3_labels: PackedInt32Array = vm._scripts[3]["labels"]
	var lbl18_pc := int(s3_labels[18])

	# 模拟一周目 (Flag[867]=0)
	vm.set_flag(867, 0)
	vm.set_flag(602, 0)
	var th_test1 := vm._spawn_thread(0, 3, 0)
	th_test1.pc = 0x2ca8
	vm._exec_one(th_test1)
	_check(th_test1.pc == lbl18_pc, "一周目 Flag[867]=0 时应跳转到 label 18 (pc=%d)" % lbl18_pc)
	_check(vm.get_flag(602) == 0, "一周目不应接收 D-Rine (Flag[602] 应为 0)")

	# 模拟二周目 (Flag[867]=1，通关 A 线后新开局)
	vm.set_flag(867, 1)
	vm.set_flag(602, 0)
	th_test1.pc = 0x2ca8
	vm._exec_one(th_test1)
	_check(th_test1.pc != lbl18_pc, "二周目 Flag[867]=1 时不得跳转 label 18")
	# 顺序执行数条指令至 D-Rine 接收段
	for _step in range(10):
		vm._exec_one(th_test1)
		if vm.get_flag(602) == 1:
			break
	_check(vm.get_flag(602) == 1, "二周目应成功置位 Flag[602]=1 (真结局交叉坐标的星尘前置条件达成!)")
	print("Test 1 (P0-1 True End D-Rine Loop) PASSED!")

	# =========================================================================
	# TEST 2: P0-2 Opcode 0x0054 (CallIf) 与 B 线电话接听分支
	# =========================================================================
	print("\n--- Test 2: P0-2 Opcode 0x0054 CallIf Verification ---")
	_check(vm.load_script_into_slot(3, "SG0_B01_04.scx"), "Failed to load SG0_B01_04.scx")
	var b_labels: PackedInt32Array = vm._scripts[3]["labels"]
	var b_lbl0_pc := int(b_labels[0])
	var th_b := vm._spawn_thread(0, 3, 0)

	# 2.1 未接听 (Flag[2620] == 0) -> CallIf 不触发，pc 直达 0x2aa6，call_stack 为空
	vm.set_flag(2620, 0)
	th_b.pc = 0x2a9b
	th_b.call_stack.clear()
	vm._exec_one(th_b)
	_check(th_b.pc == 0x2aa6, "未接电话时 pc 应推进到 0x2aa6，实际: 0x%x" % th_b.pc)
	_check(th_b.call_stack.is_empty(), "未接电话时 call_stack 应为空")

	# 2.2 接听电话 (Flag[2620] == 1) -> CallIf 触发，压栈 {"slot": 3, "pc": 0x2aa6}，跳转至 label 0
	vm.set_flag(2620, 1)
	th_b.pc = 0x2a9b
	th_b.call_stack.clear()
	vm._exec_one(th_b)
	_check(th_b.pc == b_lbl0_pc, "接听电话时应跳转至 label 0 (pc=%d)，实际: %d" % [b_lbl0_pc, th_b.pc])
	_check(th_b.call_stack.size() == 1, "接听电话时 call_stack 深度应为 1")
	_check(int(th_b.call_stack[0]["slot"]) == 3, "返回栈 slot 应为 3")
	_check(int(th_b.call_stack[0]["pc"]) == 0x2aa6, "返回栈 pc 应为 0x2aa6")

	# 2.3 测试返回指令 (0x0E Return) 能正确弹栈恢复 pc 至 0x2aa6
	var dummy_ret_data := PackedByteArray([0x00, 0x0E]) # 00:0E Return 指令
	vm._exec_tbl00(th_b, dummy_ret_data, 2, 0x0E)
	_check(th_b.pc == 0x2aa6, "Return 后 pc 应准确返回至 0x2aa6")
	_check(th_b.call_stack.is_empty(), "Return 后 call_stack 应已弹出清空")
	print("Test 2 (P0-2 Opcode 0x0054 CallIf) PASSED!")

	# =========================================================================
	# TEST 3: P0-3 RINE 互斥回复串话穿透 Bug 修复验证
	# =========================================================================
	print("\n--- Test 3: P0-3 RINE Mutual Exclusive Replies Isolation ---")
	vm.load_script_into_slot(9, "_phone.scx")
	vm.load_script_into_slot(11, "_rndrine.scx")

	var rine_evs: Array[Dictionary] = []
	var rine_conn = func(subop: int, args: Array):
		rine_evs.append({"subop": subop, "args": args})
	vm.rine_event.connect(rine_conn)

	# 启动 Mayuri 聊天 (label 24)
	vm._start_rine_subinterp(24)
	_check(vm._rine_waiting_reply, "RINE 应处于等待回复状态")
	_check(vm._rine_reply_options.size() == 3, "应注册 3 个互斥回复选项")

	rine_evs.clear()
	var opt0: Dictionary = vm._rine_reply_options[0]
	vm.submit_rine_reply(int(opt0["str_id"]))

	var sub11_count := 0
	var sub15_count := 0
	for ev in rine_evs:
		if ev["subop"] == 11:
			sub11_count += 1
		elif ev["subop"] == 15:
			sub15_count += 1

	_check(sub11_count == 1, "回复一轮结束后 subop 11 (FinishRound) 只能触发 1 次，实际: %d" % sub11_count)
	_check(sub15_count == 7, "选项 0 只有 7 条追加消息，串话穿透修复后不应为 21 条，实际: %d" % sub15_count)
	_check(not vm._rine_active, "轮次结束时 _rine_active 必须标记为 false")
	_check(vm.get_scr_work(6656) == 0, "轮次结束时 ScrWork[6656] 必须复位为 0（确保手机点击 RINE 能响应 Flag(2748) 分支）")
	vm.rine_event.disconnect(rine_conn)
	print("Test 3 (P0-3 RINE Mutual Exclusion & ScrWork[6656] Reset) PASSED!")

	# =========================================================================
	# TEST 4: P1-1 Opcode 0x0056 (CallFarIf) 跨脚本条件调用与非主线程 slot 隔离验证
	# =========================================================================
	print("\n--- Test 4: P1-1 Opcode 0x0056 CallFarIf & Thread Slot Isolation Verification ---")
	_check(vm.load_script_into_slot(3, "SG0_A02_01.scx"), "Failed to load SG0_A02_01.scx")
	_check(vm._scripts.has(11), "Script slot 11 (_rndrine.scx) should be loaded")

	var th_far := vm._spawn_thread(0, 3, 0)
	var a_labels11: PackedInt32Array = vm._scripts[11]["labels"]
	var target_pc := int(a_labels11[112])

	# 4.1 条件不成立 (Flag[600] == 0) -> CallFarIf 不触发，pc 顺移至 0x126e，不切 slot
	vm.set_flag(600, 0)
	th_far.pc = 0x1260
	th_far.script_slot = 3
	vm._active_slot = 3
	th_far.call_stack.clear()
	vm._exec_one(th_far)
	_check(th_far.pc == 0x126e, "Flag[600]=0 时 pc 应为 0x126e，实际: 0x%x" % th_far.pc)
	_check(th_far.script_slot == 3, "Flag[600]=0 时 slot 应保持为 3")
	_check(vm._active_slot == 3, "Flag[600]=0 时 _active_slot 应保持为 3")
	_check(th_far.call_stack.is_empty(), "Flag[600]=0 时 call_stack 应为空")

	# 4.2 条件成立 (Flag[600] == 1) -> CallFarIf 触发，跨 slot 调用至 slot 11 label 112
	vm.set_flag(600, 1)
	th_far.pc = 0x1260
	th_far.script_slot = 3
	vm._active_slot = 3
	th_far.call_stack.clear()
	vm._exec_one(th_far)
	_check(th_far.script_slot == 11, "CallFarIf 应切换 th.script_slot 为 11")
	_check(vm._active_slot == 11, "CallFarIf 应切换 _active_slot 为 11")
	_check(th_far.pc == target_pc, "CallFarIf 应跳转到 slot 11 的 label 112 (pc=%d)" % target_pc)
	_check(th_far.call_stack.size() == 1, "CallFarIf 应压入 1 层返回栈")
	_check(int(th_far.call_stack[0]["slot"]) == 3, "返回栈记录的 caller slot 应为 3")
	_check(int(th_far.call_stack[0]["pc"]) == 0x126e, "返回栈记录的 ret_pc 应为 0x126e")

	# 4.3 模拟目标函数返回 (0x0E Return) -> 验证跨脚本 slot 与 _active_slot 准确回退
	var ret_data := PackedByteArray([0x00, 0x0E])
	vm._exec_tbl00(th_far, ret_data, 2, 0x0E)
	_check(th_far.script_slot == 3, "Return 后 th.script_slot 应恢复为 3")
	_check(vm._active_slot == 3, "Return 后 vm._active_slot 应恢复为 3")
	_check(th_far.pc == 0x126e, "Return 后 pc 应恢复为 0x126e")

	# 4.4 验证辅助/后台线程 (group_id != 0) 跨脚本返回绝不污染全局主线程 _active_slot
	vm._active_slot = 3
	_check(vm.load_script_into_slot(6, "macrosys.scx"), "Failed to load macrosys.scx")
	var th_bg := vm._spawn_thread(1, 6, 0)
	th_bg.call_stack.append({"slot": 6, "pc": 100})
	vm._exec_tbl00(th_bg, ret_data, 2, 0x0E)
	_check(vm._active_slot == 3, "后台辅助线程 (group_id=1) 执行 Return 绝不得篡改主剧情槽位 _active_slot")
	th_bg.alive = false
	print("Test 4 (P1-1 Opcode 0x0056 CallFarIf & Thread Isolation) PASSED!")

	# =========================================================================
	# TEST 5: P1-2 来电读档静音修复 (import_state/deserialize_state 铃声唤醒与 UI 懒加载保活)
	# =========================================================================
	print("\n--- Test 5: P1-2 Incoming Call Audio Recovery & Lazy UI Instantiation ---")
	var audio_mgr := MgsAudioMgr.new()
	audio_mgr.bind_vfs(vfs)
	audio_mgr.bind_vm(vm)
	audio_mgr.apply_config(cfg)
	get_root().add_child(audio_mgr)
	var theme_loader := UiThemeLoader.new()
	theme_loader.bind_vfs(vfs)
	var phone := UiPhoneRine.new()
	phone.setup(vfs, vm, theme_loader, audio_mgr, cfg)
	get_root().add_child(phone)

	# 5.1 通过 deserialize_state 导入含有来电状态的存档
	var call_state := {
		"has_unread_call": true,
		"amadeus_overlay_visible": true,
		"active_contact_idx": 1
	}
	phone.deserialize_state(call_state)
	_check(phone._has_unread_call, "deserialize_state 后 _has_unread_call 应为 true")
	_check(phone._amadeus_overlay != null and phone._amadeus_overlay.visible, "读档后 _amadeus_overlay 必须已实例化并呈现显示")
	_check(audio_mgr.is_se_playing("SGSE700.ogg"), "来电读档后 SGSE700.ogg 铃声应处于播放状态")

	# 5.2 验证 serialize_state 接口导出一致性
	var phone_snap := phone.serialize_state()
	_check(bool(phone_snap.get("has_unread_call", false)), "serialize_state has_unread_call should be true")
	_check(bool(phone_snap.get("amadeus_overlay_visible", false)), "serialize_state amadeus_overlay_visible should be true")

	# 5.3 导入普通无来电存档 -> 铃声停止
	var normal_state := {
		"has_unread_call": false,
		"amadeus_overlay_visible": false,
		"active_contact_idx": 1
	}
	phone.deserialize_state(normal_state)
	_check(not phone._has_unread_call, "无来电读档后 _has_unread_call 应为 false")
	_check(not audio_mgr.is_se_playing("SGSE700.ogg"), "普通读档后铃声应已停止")
	phone.queue_free()
	print("Test 5 (P1-2 Incoming Call Audio Recovery & deserialize_state) PASSED!")

	# =========================================================================
	# TEST 6: P1-3 16:9 长屏安全区优化 (消除黑边吸收范围内的 HUD 多余内缩)
	# =========================================================================
	print("\n--- Test 6: P1-3 16:9 Aspect Ratio Safe Area Inset Optimization ---")
	# 校验数学公式在不同设备分辨率下的推演结果
	var calc_insets = func(win_w: int, win_h: int, safe_pos: Vector2i, safe_end: Vector2i) -> Dictionary:
		var scale_factor: float = minf(float(win_w) / 1920.0, float(win_h) / 1080.0)
		var game_w: float = 1920.0 * scale_factor
		var game_h: float = 1080.0 * scale_factor
		var game_x: float = (float(win_w) - game_w) * 0.5
		var game_y: float = (float(win_h) - game_h) * 0.5

		var raw_left: float = float(safe_pos.x) - game_x
		var raw_top: float = float(safe_pos.y) - game_y
		var raw_right: float = (game_x + game_w) - float(safe_end.x)
		var raw_bottom: float = (game_y + game_h) - float(safe_end.y)

		return {
			"left": clampf(raw_left / scale_factor, 0.0, 120.0) if raw_left > 0.0 else 0.0,
			"top": clampf(raw_top / scale_factor, 0.0, 80.0) if raw_top > 0.0 else 0.0,
			"right": clampf(raw_right / scale_factor, 0.0, 120.0) if raw_right > 0.0 else 0.0,
			"bottom": clampf(raw_bottom / scale_factor, 0.0, 36.0) if raw_bottom > 0.0 else 0.0,
			"game_x": game_x,
			"game_y": game_y,
		}

	# 6.1 标准 16:9 PC / 桌面环境 (1920x1080, 无安全区缩进)
	var res_pc: Dictionary = calc_insets.call(1920, 1080, Vector2i(0, 0), Vector2i(1920, 1080))
	_check(res_pc["left"] == 0.0 and res_pc["right"] == 0.0 and res_pc["top"] == 0.0 and res_pc["bottom"] == 0.0, "PC 1920x1080 safe area insets should be 0")

	# 6.2 iPhone 14/15 宽屏 (2556x1179, 刘海 safe.position.x = 160)
	# 视口 16:9 留黑边: 2556 - 1920*(1179/1080) = 2556 - 2096 = 460px -> 单侧黑边 230px
	# 刘海 160px 完全落在 230px 黑边内，不侵入游戏画面，left_inset 必须为 0.0 (消除了此前 98px 的多余内缩!)
	var res_iphone: Dictionary = calc_insets.call(2556, 1179, Vector2i(160, 0), Vector2i(2396, 1179))
	_check(res_iphone["game_x"] > 225.0, "iPhone 横屏左右黑边应大于 225px")
	_check(res_iphone["left"] == 0.0, "iPhone 160px 刘海被黑边完全吸收，left_inset 应为 0.0，实际: %f" % res_iphone["left"])
	_check(res_iphone["right"] == 0.0, "iPhone 右侧黑边完全吸收，right_inset 应为 0.0")

	# 6.3 极端超大刘海 (例如 safe.position.x = 300，超过黑边 230px)
	# 此时应仅针对超出的 70px 转换为视口坐标进行微幅内缩 (约 64px)
	var res_extreme: Dictionary = calc_insets.call(2556, 1179, Vector2i(300, 0), Vector2i(2256, 1179))
	_check(res_extreme["left"] > 60.0 and res_extreme["left"] < 70.0, "超限刘海应仅内缩超出黑边部分，实际: %f" % res_extreme["left"])

	# 6.4 实例化 MobileGestureHelper 校验 _apply_safe_area() 运行正常
	var helper := MobileGestureHelper.new()
	get_root().add_child(helper)
	helper._apply_safe_area()
	_check(helper._date_phone_btn != null, "MobileGestureHelper _date_phone_btn should exist")
	_check(helper._date_phone_btn.offset_left >= 24.0, "MobileGestureHelper offset_left >= 24")
	helper.queue_free()
	print("Test 6 (P1-3 Safe Area Optimization) PASSED!")

	print("\n=======================================================")
	print("ALL 6 DEFECT FIXES AND END-TO-END TESTS PASSED (100%)!")
	print("=======================================================")
	quit(0)
