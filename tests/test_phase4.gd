extends SceneTree

var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	_run()
	return true


func _run() -> void:
	print("=== Phase 4 Verification (ThemeLoader + UI Panels + Phone + Gallery + TIPS + MainController) ===")
	var cfg := ConfigManager.new()
	cfg.load_config()
	var vfs := MgsVfs.new()
	assert(vfs.auto_mount(cfg), "VFS 挂载失败")

	var loader := UiThemeLoader.new()
	loader.bind_vfs(vfs)
	var title_a := loader.get_title_assets()
	assert(title_a["bg"] != null, "TITLE_CHIP 背景切片为空")
	var mes_a := loader.get_meswin_assets()
	assert(mes_a["box"] != null and (mes_a["box"] as Texture2D).get_height() == 318, "MESWIN 底板切片尺寸异常")
	var stickers := loader.get_rine_stickers()
	assert(stickers.size() == 18, "RINE 表情贴纸数量应为 18")
	print("UiThemeLoader ok: title_bg=", (title_a["bg"] as Texture2D).get_size(), " stickers=", stickers.size())

	# 挂载主场景测试完整链路
	var scene := load("res://scenes/main.tscn") as PackedScene
	assert(scene != null, "scenes/main.tscn 加载失败")
	var main_node := scene.instantiate() as MainController
	assert(main_node != null, "MainController 实例化失败")
	get_root().add_child(main_node)

	# 验证 Start New Game -> SG0_00_01 推进与 UI 面板开关
	main_node.start_new_game()
	for _i in range(1800):
		main_node.vm.step_frame(1)
		if main_node.video.is_movie_playing():
			main_node.video.stop_movie(true)
		elif main_node.vm.is_waiting_for_movie():
			main_node.vm.notify_movie_finished()
		if main_node.vm.is_waiting_for_click():
			break
	assert(main_node.panels._body_renderer.get_glyphs_count() > 0 or not main_node.vm.backlog.is_empty(), "对白未渲染")

	# 存档 / 读档闭环
	main_node._on_save_slot(0)
	var meta := UiPanels.read_slot_meta(0)
	assert(not meta.is_empty() and str(meta.get("script_name", "")) == "SG0_00_01.scx", "存档元数据写入异常")

	# RINE / TIPS / Gallery 面板打开关闭
	main_node.phone_drawer.open_phone()
	assert(main_node.phone_drawer.is_phone_open(), "RINE 抽屉打开失败")
	main_node.phone_drawer.close_phone()

	main_node.tips_panel.open_panel()
	assert(main_node.tips_panel.visible, "TIPS 面板未显示")
	main_node.tips_panel.close_panel()

	main_node.gallery.open_panel(1)
	assert(main_node.gallery.visible, "Gallery 面板未显示")
	main_node.gallery.close_panel()

	main_node.panels.open_backlog()
	main_node.panels.open_config()
	main_node.panels.open_saveload(false)

	# 测试 MgsFontRenderer 修复后的 ASCII 字形编码
	var g_colon := MgsFontRenderer.encode_ascii_glyphs("2026/11/16 02:30-OK")
	assert(g_colon.size() == 19 and g_colon[4] == 64 and g_colon[13] == 65 and g_colon[16] == 66, "ASCII /:- 槽位映射异常")

	main_node.queue_free()
	print("=== Phase 4 Verification PASSED ===")
	quit(0)
