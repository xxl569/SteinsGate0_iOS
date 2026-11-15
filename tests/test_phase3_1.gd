extends SceneTree

var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	_run()
	return true


func _run() -> void:
	print("=== Phase 3.1 Verification (Config, VFS, Sc3Expr, FontRenderer) ===")
	var cfg := ConfigManager.new()
	cfg.load_config()
	assert(cfg.text_speed >= 10.0, "ConfigManager text_speed 异常")

	var vfs := MgsVfs.new()
	var ok := vfs.auto_mount(cfg)
	assert(ok and vfs.is_mounted, "MgsVfs 自动挂载失败")
	print("Mounted dir: ", vfs.active_game_dir, " movie_dir: ", vfs.active_movie_dir)

	var met_space := vfs.get_glyph_metrics(0, 0)
	var met_zero := vfs.get_glyph_metrics(0, 1)
	var met_cjk := vfs.get_glyph_metrics(0, 3676)
	print("Glyph metrics: space=", met_space, " '0'=", met_zero, " gid3676=", met_cjk)
	assert(met_cjk.z == 48, "汉字全角步长应为 48")

	# 验证 Sc3Expr 真实字节码求值（以模拟 ScrWork 上下文测试）
	var mock := _MockCtx.new()
	# fe 28 0a ac f4 14 14 00 81 00 00 -> ScrWork[3316] = 1
	var ex1 := PackedByteArray([0x28, 0x0A, 0xAC, 0xF4, 0x14, 0x14, 0x00, 0x81, 0x00, 0x00])
	var r1 := Sc3Expr.eval(ex1, 0, mock, null)
	assert(mock.get_scr_work(3316) == 1 and int(r1["value"]) == 1, "Sc3Expr 赋值测试失败")

	# ScrWork[10] = 5 * 3 + 2 -> 17 (op=* prec=20, op=+ prec=10)
	var ex2 := PackedByteArray([0x28, 0x30, 0x8A, 0x00, 0x14, 0x00, 0x85, 0x00, 0x01, 0x20, 0x83, 0x00, 0x03, 0x10, 0x82, 0x00, 0x00])
	Sc3Expr.eval(ex2, 0, mock, null)
	assert(mock.get_scr_work(10) == 17, "Sc3Expr 优先级测试失败，期望 17，实际 %d" % mock.get_scr_work(10))

	# 除以 0 保护 -> 0x7FFFFFFF
	var ex3 := PackedByteArray([0x85, 0x00, 0x02, 0x10, 0x80, 0x00, 0x00])
	var r3 := Sc3Expr.eval(ex3, 0, mock, null)
	assert(int(r3["value"]) == Sc3Expr.INT32_DIV_ZERO, "Sc3Expr 除零保护失败")

	# 测试 MgsFontRenderer 解析 SG0_00_01.scx 前 5 条字符串
	var scx := vfs.read_entry("script.mpk", "SG0_00_01.scx")
	assert(scx.size() > 16 and scx.slice(0, 4).get_string_from_ascii() == "SC3", "SG0_00_01.scx 读取失败")
	var str_off := scx.decode_u32(4)
	var ret_off := scx.decode_u32(8)
	var n_str := int((ret_off - str_off) / 4)
	print("SG0_00_01 strings count = ", n_str)
	assert(n_str >= 50, "SG0_00_01 字符串数量过少")

	var fr := MgsFontRenderer.new()
	get_root().add_child(fr)
	fr.bind_vfs(vfs)
	assert(MgsFontRenderer.ensure_shared_resources(vfs), "字库纹理初始化失败")

	var shown_nonempty := 0
	for i in range(mini(10, n_str)):
		var soff := scx.decode_u32(str_off + i * 4)
		var info := fr.set_sc3_string(scx, soff, mock, null, false)
		if int(info["body_glyph_count"]) > 0:
			shown_nonempty += 1
			assert(not fr.is_fully_revealed(), "逐字模式下初始应未全显")
			fr.step_reveal(0.5)
			fr.reveal_all()
			assert(fr.is_fully_revealed(), "reveal_all 后应全显")
	assert(shown_nonempty >= 5, "前 10 条字符串有效正文不足")

	fr.queue_free()
	print("=== Phase 3.1 Verification PASSED ===")
	quit(0)


class _MockCtx:
	extends RefCounted
	var scr: Dictionary = {}
	var flg: Dictionary = {}
	func get_scr_work(idx: int) -> int:
		return int(scr.get(idx, 0))
	func set_scr_work(idx: int, val: int) -> void:
		scr[idx] = val
	func get_flag(idx: int) -> int:
		return int(flg.get(idx, 0))
	func set_flag(idx: int, val: int) -> void:
		flg[idx] = val
	func get_thread_var(_t: Object, _idx: int) -> int:
		return 0
	func set_thread_var(_t: Object, _idx: int, _val: int) -> void:
		pass
	func resolve_label_addr(_t: Object, lid: int) -> int:
		return lid
	func read_expr_table(_t: Object, _op: int, _sid: int, _idx: int) -> int:
		return 0
	func get_sys_var(_op: int) -> int:
		return 0
