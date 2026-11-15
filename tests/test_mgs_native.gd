extends SceneTree

var _started := false

func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run_tests()
	return true

func _run_tests() -> void:
	print("=== Test MgsNative & Godot 4.3 Integration ===")
	var mgs = ClassDB.instantiate("MgsNative")
	assert(mgs != null, "ClassDB.instantiate('MgsNative') 失败")

	var game_dir := "U:/anti/projects/STEINS GATE 0"
	var count: int = mgs.mount_game_dir(game_dir)
	print("Mounted entries: ", count, " archives: ", mgs.get_archive_count())
	assert(count >= 17000, "挂载条目数量异常: %d" % count)
	assert(mgs.get_archive_count() == 9, "应挂载 9 个活跃 MPK，实际: %d" % mgs.get_archive_count())

	# 1. 测试 FONT_A.DDS L8 解码
	var font_info: Dictionary = mgs.decode_archive_image("system.mpk", "FONT_A.DDS", true)
	assert(font_info.get("ok", false), "FONT_A.DDS 解码失败")
	assert(font_info["format"] == "l8", "FONT_A.DDS 格式应为 l8")
	assert(font_info["width"] == 3072 and font_info["height"] == 4096, "FONT_A.DDS 尺寸异常: %dx%d" % [font_info["width"], font_info["height"]])
	var font_img := Image.create_from_data(font_info["width"], font_info["height"], false, Image.FORMAT_L8, font_info["data"])
	assert(not font_img.is_empty(), "FONT_A Image 创建失败")
	print("FONT_A.DDS ok: ", font_img.get_width(), "x", font_img.get_height())

	# 2. 测试 MESWIN.DDS RGBA8 解码
	var mes_info: Dictionary = mgs.decode_archive_image("system.mpk", "MESWIN.DDS", false)
	assert(mes_info.get("ok", false), "MESWIN.DDS 解码失败")
	assert(mes_info["format"] == "rgba8", "MESWIN.DDS 应为 rgba8")
	var mes_img := Image.create_from_data(mes_info["width"], mes_info["height"], false, Image.FORMAT_RGBA8, mes_info["data"])
	assert(not mes_img.is_empty(), "MESWIN Image 创建失败")
	print("MESWIN.DDS ok: ", mes_img.get_width(), "x", mes_img.get_height())

	# 3. 测试 bg.mpk 中超大 PNG 识别与原生 libpng 解码
	var bg_info: Dictionary = mgs.decode_archive_image("bg.mpk", "BG01A.png", false)
	assert(bg_info.get("ok", false), "BG01A.png 读取失败")
	assert(bg_info["format"] == "png", "BG01A.png 应返回 png 格式标记")
	var bg_img := Image.new()
	var perr := bg_img.load_png_from_buffer(bg_info["data"])
	assert(perr == OK and bg_img.get_width() == 1920 and bg_img.get_height() == 1080, "BG01A.png PNG 解码失败")
	print("BG01A.png ok: ", bg_img.get_width(), "x", bg_img.get_height())

	# 4. 测试 chara.mpk .lay + PNG atlas 合成
	var chara_entries: PackedStringArray = mgs.list_entries("chara.mpk", "")
	var first_lay := ""
	for e in chara_entries:
		if e.to_lower().ends_with(".lay"):
			first_lay = e
			break
	assert(first_lay != "", "未在 chara.mpk 中找到 .lay 文件")
	var stem := first_lay.substr(0, first_lay.length() - 4)
	var atlas_stem := stem.substr(0, stem.length() - 1) if stem.ends_with("_") else stem
	var atlas_name := atlas_stem + ".png"
	if not mgs.has_entry("chara.mpk", atlas_name):
		atlas_name = atlas_stem + ".dds"
	if not mgs.has_entry("chara.mpk", atlas_name):
		atlas_name = stem + ".png"
	assert(mgs.has_entry("chara.mpk", atlas_name), "未找到配套立绘图集: " + atlas_name)

	var lay_bytes: PackedByteArray = mgs.read_entry("chara.mpk", first_lay)
	var atlas_dict: Dictionary = mgs.decode_archive_image("chara.mpk", atlas_name, false)
	assert(atlas_dict.get("ok", false), "图集读取失败: " + atlas_name)
	var atlas_img := Image.new()
	if atlas_dict["format"] == "png":
		atlas_img.load_png_from_buffer(atlas_dict["data"])
	else:
		atlas_img = Image.create_from_data(atlas_dict["width"], atlas_dict["height"], false, Image.FORMAT_RGBA8, atlas_dict["data"])
	if atlas_img.get_format() != Image.FORMAT_RGBA8:
		atlas_img.convert(Image.FORMAT_RGBA8)

	var gids := PackedInt32Array([1])
	var lay_res: Dictionary = mgs.compose_lay_rgba(lay_bytes, atlas_img.get_data(), atlas_img.get_width(), atlas_img.get_height(), gids)
	assert(lay_res.get("ok", false), ".lay 合成失败: " + first_lay)
	assert(lay_res["width"] > 100 and lay_res["height"] > 100, ".lay 合成尺寸过小")
	print("LAY compose ok (", first_lay, "): ", lay_res["width"], "x", lay_res["height"], " origin=(", lay_res["origin_x"], ",", lay_res["origin_y"], ")")

	# 5. 测试已转码的 .ogv 是否能被 Godot VideoStreamTheora 正常加载
	var test_ogv := "U:/anti/temp/SteinsGate0_iOS/SteinsGate0_iOS_Documents/movie/IMV001.ogv"
	if FileAccess.file_exists(test_ogv):
		var vstream: VideoStreamTheora = ResourceLoader.load(test_ogv, "VideoStreamTheora") if ResourceLoader.exists(test_ogv) else VideoStreamTheora.new()
		vstream.file = test_ogv
		var vsp := VideoStreamPlayer.new()
		vsp.stream = vstream
		get_root().add_child(vsp)
		vsp.play()
		assert(vsp.is_playing(), "VideoStreamPlayer 播放 IMV001.ogv 失败")
		print("VideoStreamTheora IMV001.ogv ok, is_playing=", vsp.is_playing(), " name=", vsp.get_stream_name())
		vsp.stop()
		vsp.queue_free()

	print("=== ALL MgsNative TESTS PASSED ===")
	quit(0)
