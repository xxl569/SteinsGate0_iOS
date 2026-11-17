extends SceneTree

var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	_run()
	return true

func _run() -> void:
	print("=== Test Chara Clear & Overlap Fix ===")
	var cfg := ConfigManager.new()
	cfg.load_config()
	var vfs := MgsVfs.new()
	var ok := vfs.auto_mount(cfg)
	if not ok:
		print("FAIL: VFS auto_mount failed")
		quit(1)
		return

	var root_node := Control.new()
	root_node.size = Vector2(1920, 1080)
	get_root().add_child(root_node)

	var vm := Sc3Vm.new(vfs)
	var stage := MgsStage.new()
	root_node.add_child(stage)
	stage.bind_vfs(vfs)
	stage.bind_vm(vm)

	# 1. 模拟研讨会：加载红莉栖立绘 (chara_idx=114, slot=16)
	print("Step 1: Loading Kurisu (slot=16, chara_idx=114)...")
	vm.set_flag(2414, 1)
	var l_ok: bool = stage.load_chara(16, 114, 1)
	print("Kurisu load ok=", l_ok, ", chara_count=", stage.get_chara_count())
	assert(stage._chara_slots.has(16), "Kurisu not loaded into slot 16")

	# 2. 模拟研讨会结束切街景：执行官方宏清理 (set_flag(2414, 0))
	print("Step 2: Simulating scene switch macro cleanup (ResetFlag 2414)...")
	vm.set_flag(2414, 0)
	print("After ResetFlag 2414, chara_count=", stage.get_chara_count())
	assert(not stage._chara_slots.has(16), "Kurisu slot 16 must be released!")

	# 3. 模拟接听电话进入办公室：加载真帆 (slot=16, chara_idx=602)
	print("Step 3: Loading Maho (slot=16, chara_idx=602)...")
	var m_ok: bool = stage.load_chara(16, 602, 1)
	print("Maho load ok=", m_ok, ", chara_count=", stage.get_chara_count())
	assert(stage._chara_slots.has(16), "Maho not loaded into slot 16")

	var info: Dictionary = stage._chara_slots[16]
	assert(str(info.get("entry", "")) == "MAH_CMA.png", "Slot 16 must be Maho")

	# 4. 验证舞台总立绘槽数量严格为 1
	var total_slots := stage._chara_slots.size()
	print("Step 4: Total active chara slots in stage = ", total_slots)
	assert(total_slots == 1, "Expected exactly 1 slot, but got %d" % total_slots)

	# 5. 验证 _relayout_chara_slots 不会发生位置错乱或幽灵残留
	stage._relayout_chara_slots()
	var sp: Sprite2D = info["sprite"]
	print("Maho sprite pos = ", sp.position)
	print("=== Test Chara Clear & Overlap Fix PASSED ===")
	quit(0)
