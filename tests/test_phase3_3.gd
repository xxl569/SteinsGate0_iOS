extends SceneTree

var _done := false

func _process(_delta: float) -> bool:
	if _done:
		return false
	_done = true
	_run()
	return true


func _run() -> void:
	print("=== Phase 3.3 Verification (Stage + Audio + Video + Cache) ===")
	var cfg := ConfigManager.new()
	cfg.load_config()
	var vfs := MgsVfs.new()
	assert(vfs.auto_mount(cfg), "VFS 挂载失败")

	var stage := MgsStage.new()
	get_root().add_child(stage)
	stage.bind_vfs(vfs)

	# 1. 普通与超大背景加载 + 遮罩转场
	assert(stage.load_bg_by_index(0, 0), "首张背景加载失败")
	var bg0_tex := stage.get_bg_texture(0)
	assert(bg0_tex != null and bg0_tex.get_width() == 1920, "BG[0] 尺寸异常")

	# 查找并加载 BG27A.png（1920x3227 超高背景）
	var bg27 := vfs.list_entries("bg.mpk", "BG27A")
	assert(not bg27.is_empty(), "未找到 BG27A.png")
	var all_bgs := vfs.list_entries("bg.mpk", "")
	var bg27_idx := Array(all_bgs).find(bg27[0])
	assert(bg27_idx >= 0 and stage.load_bg_by_index(1, bg27_idx), "超大背景加载失败")
	var big_tex := stage.get_bg_texture(1)
	assert(big_tex != null and big_tex.get_height() > 2000, "超大背景高度应大于 2000px")
	stage.set_bg_pan(1, Vector2(0, -400), 1.0)
	stage.play_mask_wipe(1, 10)
	print("Stage BGs ok: bg0=", bg0_tex.get_size(), " big_bg=", big_tex.get_size())

	# 2. .lay 立绘合成 + MgsCache 缓存 + 低内存回收
	assert(stage.load_chara(0, 84, 0), "立绘 84 加载失败")
	assert(stage.load_chara(1, 76, 0), "立绘 76 加载失败")
	assert(stage.get_chara_count() == 2, "立绘槽位计数错误")
	var used_before := stage.get_cache().get_used_bytes()
	assert(used_before > 0, "纹理缓存占用应 > 0")
	stage.on_low_memory()
	print("Cache used_bytes after load=", used_before, " entries=", stage.get_cache().get_entry_count())

	# 3. 音频与 Ogg LOOPSTART 解析 + WAVTABLE + 配音口型
	var audio := MgsAudioMgr.new()
	get_root().add_child(audio)
	audio.bind_vfs(vfs)
	audio.apply_config(cfg)
	assert(audio.has_wavtable() and audio.get_wavtable_size() > 100000, "WAVTABLE.DAT 未挂载或异常")

	assert(audio.play_bgm(0, true, 0), "BGM 0 播放失败")
	var bgm_info := audio.get_bgm_loop_info()
	assert(audio.is_bgm_playing(), "BGM 应处于播放状态")
	assert(bool(bgm_info["loop_enabled"]), "BGM 循环应启用")

	assert(audio.play_se(0, false), "SE 0 播放失败")
	assert(audio.play_voice(1, 0), "Voice 1 播放失败")
	assert(audio.is_voice_playing(), "Voice 应处于播放状态")
	var mouth_lvl := audio.get_voice_mouth_level()
	assert(mouth_lvl >= 0 and mouth_lvl <= 2, "口型等级越界")
	stage.update_lip_sync(mouth_lvl)
	print("Audio ok: wavtable=", audio.get_wavtable_size(), " loop_info=", bgm_info, " mouth_lvl=", mouth_lvl)

	# 4. OGV 过场视频播放与跳过信号
	var vp := MgsVideoPlayer.new()
	get_root().add_child(vp)
	vp.bind_vfs(vfs)
	var finished_flag := [false]
	vp.movie_finished.connect(func(_idx: int, _skipped: bool): finished_flag[0] = true)
	assert(vp.play_movie_by_stem("IMV001"), "IMV001.ogv 启动失败")
	assert(vp.is_movie_playing(), "视频应处于播放状态")
	vp.stop_movie(true)
	assert(finished_flag[0] and not vp.is_movie_playing(), "视频跳过收尾异常")
	print("VideoPlayer ok: IMV001 started and skipped cleanly")

	audio.stop_bgm(0)
	audio.stop_se(-1)
	audio.stop_voice()
	vp.queue_free()
	audio.queue_free()
	stage.queue_free()
	print("=== Phase 3.3 Verification PASSED ===")
	quit(0)
