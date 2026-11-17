class_name MgsStage
extends Node2D
## 1920x1080 舞台渲染器：多图层背景（支持超大分辨率 CG 平移与纯色遮罩）、平滑交叉淡入淡出、全屏淡变、灰度遮罩转场、.lay 差分立绘与 LRU 缓存

signal stage_updated()

const STAGE_WIDTH := 1920.0
const STAGE_HEIGHT := 1080.0
const CHARA_DISPLAY_SCALE := Vector2.ONE
const MASK_WIPE_SHADER := preload("res://assets/shaders/mask_wipe.gdshader")

var _vfs: MgsVfs = null
var _vm: Sc3Vm = null
var _cache: MgsCache = MgsCache.new()

var _bg_root: Node2D = null
var _pic_root: Node2D = null
var _chara_root: Node2D = null
var _wipe_overlay: TextureRect = null
var _screen_fade_rect: ColorRect = null

var _bg_layers: Dictionary = {} # layer_id(int) -> { sprite: Sprite2D, bg_idx: int, is_color: bool, pan_manual: bool, fade_tween: Tween }
var _pic_layers: Dictionary = {} # surf_id(int) -> { sprite: Sprite2D, archive_type: int, file_id: int }
var _chara_slots: Dictionary = {} # slot_id(int) -> Dictionary
var _fading_nodes: Array[Node] = []

var _wipe_tween: Tween = null
var _white_tex: ImageTexture = null


func _ready() -> void:
	_ensure_layers()


func _ensure_layers() -> void:
	if _bg_root != null:
		return
	_bg_root = Node2D.new()
	_bg_root.name = "BgRoot"
	_bg_root.z_index = 0
	add_child(_bg_root)

	_pic_root = Node2D.new()
	_pic_root.name = "PicRoot"
	_pic_root.z_index = 10
	add_child(_pic_root)

	_chara_root = Node2D.new()
	_chara_root.name = "CharaRoot"
	_chara_root.z_index = 20
	add_child(_chara_root)

	_wipe_overlay = TextureRect.new()
	_wipe_overlay.name = "MaskWipeOverlay"
	_wipe_overlay.visible = false
	_wipe_overlay.z_index = 40
	_wipe_overlay.position = Vector2.ZERO
	_wipe_overlay.size = Vector2(STAGE_WIDTH, STAGE_HEIGHT)
	_wipe_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wipe_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_wipe_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wipe_overlay)

	_screen_fade_rect = ColorRect.new()
	_screen_fade_rect.name = "ScreenFadeOverlay"
	_screen_fade_rect.visible = false
	_screen_fade_rect.z_index = 45
	_screen_fade_rect.position = Vector2.ZERO
	_screen_fade_rect.size = Vector2(STAGE_WIDTH, STAGE_HEIGHT)
	_screen_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_screen_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen_fade_rect)


func _get_white_tex() -> ImageTexture:
	if _white_tex == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex


func bind_vfs(vfs: MgsVfs) -> void:
	_vfs = vfs
	_ensure_layers()


func bind_vm(vm: Sc3Vm) -> void:
	_vm = vm
	if vm == null:
		return
	if not vm.bg_changed.is_connected(load_bg_by_index):
		vm.bg_changed.connect(load_bg_by_index)
	if not vm.bg_color_changed.is_connected(load_bg_color):
		vm.bg_color_changed.connect(load_bg_color)
	if not vm.bg_cleared.is_connected(clear_bg_layer):
		vm.bg_cleared.connect(clear_bg_layer)
	if not vm.bg_committed.is_connected(commit_bg_layer):
		vm.bg_committed.connect(commit_bg_layer)
	if not vm.pic_loaded.is_connected(load_pic):
		vm.pic_loaded.connect(load_pic)
	if not vm.disp_changed.is_connected(set_pic_visible):
		vm.disp_changed.connect(set_pic_visible)
	if not vm.chara_loaded.is_connected(load_chara):
		vm.chara_loaded.connect(load_chara)
	if not vm.chara_released.is_connected(release_chara):
		vm.chara_released.connect(release_chara)
	if not vm.chara_swapped.is_connected(swap_chara_slots):
		vm.chara_swapped.connect(swap_chara_slots)
	if not vm.mask_wipe_requested.is_connected(play_mask_wipe):
		vm.mask_wipe_requested.connect(play_mask_wipe)


func get_cache() -> MgsCache:
	return _cache


func on_low_memory() -> int:
	return _cache.on_low_memory()


func reset_stage() -> void:
	_ensure_layers()
	for lid in _bg_layers.keys():
		var info: Dictionary = _bg_layers[lid]
		var tw: Variant = info.get("fade_tween", null)
		if tw is Tween and (tw as Tween).is_valid():
			(tw as Tween).kill()
		var sp := info["sprite"] as Sprite2D
		if is_instance_valid(sp):
			sp.queue_free()
	_bg_layers.clear()

	for sid in _pic_layers.keys():
		var info: Dictionary = _pic_layers[sid]
		var sp := info["sprite"] as Sprite2D
		if is_instance_valid(sp):
			sp.queue_free()
	_pic_layers.clear()

	for cslot in _chara_slots.keys():
		var info: Dictionary = _chara_slots[cslot]
		var tw: Variant = info.get("fade_tween", null)
		if tw is Tween and (tw as Tween).is_valid():
			(tw as Tween).kill()
		var sp := info["sprite"] as Sprite2D
		if is_instance_valid(sp):
			sp.queue_free()
	_chara_slots.clear()

	for fn in _fading_nodes:
		if is_instance_valid(fn):
			fn.queue_free()
	_fading_nodes.clear()

	if _wipe_tween != null and _wipe_tween.is_valid():
		_wipe_tween.kill()
	if _wipe_overlay != null:
		_wipe_overlay.visible = false
		_wipe_overlay.texture = null
	if _screen_fade_rect != null:
		_screen_fade_rect.visible = false
		_screen_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)


func _process(delta: float) -> void:
	# 1. 同步 SC3 全屏淡入淡出遮罩 (ScrWork[4400]=颜色类型, ScrWork[4401]=0..256 透明度)
	if _vm != null and _screen_fade_rect != null:
		var fade_amt := _vm.get_scr_work(4401)
		if fade_amt > 0:
			var fade_type := _vm.get_scr_work(4400)
			var base_col := Color(1.0, 1.0, 1.0) if fade_type == 1 else Color(0.0, 0.0, 0.0)
			var target_a := clampf(float(fade_amt) / 256.0, 0.0, 1.0)
			base_col.a = lerpf(_screen_fade_rect.color.a, target_a, clampf(delta * 24.0, 0.0, 1.0)) if _screen_fade_rect.visible else target_a
			_screen_fade_rect.color = base_col
			_screen_fade_rect.visible = base_col.a > 0.002
		elif _screen_fade_rect.visible:
			_screen_fade_rect.color.a = lerpf(_screen_fade_rect.color.a, 0.0, clampf(delta * 24.0, 0.0, 1.0))
			if _screen_fade_rect.color.a <= 0.01:
				_screen_fade_rect.visible = false
				_screen_fade_rect.color.a = 0.0

	# 2. 同步 BG 平移/缩放/脚本淡入与遮罩进度 (ScrWork[4500+40*i + 0..15])
	if _vm != null:
		for lid in _bg_layers.keys():
			var info: Dictionary = _bg_layers[lid]
			_apply_bg_sync(clampi(int(lid), 0, 7), info, false, delta)

		# 3. 实时同步立绘目标位置、缩放与环境色调 (ScrWork[5100+40*i] + ScrWork[2500+10*i])
		for slot_id in _chara_slots.keys():
			var cinfo: Dictionary = _chara_slots[slot_id]
			var csp := cinfo.get("sprite", null) as Sprite2D
			if not is_instance_valid(csp):
				continue
			var sid := int(slot_id)
			var sidx := _slot_to_scr_idx(sid)
			var tint_raw := _vm.get_scr_work(5100 + 40 * sidx + 8)
			csp.modulate = _decode_scr_color(tint_raw, csp.modulate.a)
			if sid >= 16 or not csp.visible:
				continue
			var ch_idx := _vm.get_scr_work(5100 + 40 * sidx + 9)
			if ch_idx < 0 or ch_idx == 65535:
				continue
			var sx := _vm.get_scr_work(5100 + 40 * sidx + 0) + _vm.get_scr_work(2500 + 10 * sidx + 0)
			var sy := _vm.get_scr_work(5100 + 40 * sidx + 1) + _vm.get_scr_work(2500 + 10 * sidx + 1)
			var target_pos := _calc_chara_anchor(sidx)
			# 防止 macrosys 在释放槽位前 1~2 帧先把 ScrWork[5100] 重置为 (640,360) 导致立绘淡出前向中间瞬移
			if sx == 640 and sy == 360 and csp.position.distance_to(target_pos) > 4.0:
				var rf := int(cinfo.get("center_reset_frames", 0)) + 1
				cinfo["center_reset_frames"] = rf
				if rf < 3:
					continue
			else:
				cinfo["center_reset_frames"] = 0
			cinfo["base_y"] = target_pos.y
			if csp.position.distance_to(target_pos) > 0.25:
				csp.position = csp.position.lerp(target_pos, clampf(delta * 16.0, 0.0, 1.0))
			var sx_scale := _vm.get_scr_work(5100 + 40 * sidx + 5)
			var sy_scale := _vm.get_scr_work(5100 + 40 * sidx + 6)
			if sx_scale > 0 and sy_scale > 0:
				var target_sc := Vector2(float(sx_scale) / 1000.0, float(sy_scale) / 1000.0)
				if csp.scale.distance_to(target_sc) > 0.002:
					csp.scale = csp.scale.lerp(target_sc, clampf(delta * 16.0, 0.0, 1.0))


func flush_transitions() -> void:
	## 立即结算所有过渡动画与渐隐残影（供命令行快进/截图直达稳态使用）
	for fn in _fading_nodes:
		if is_instance_valid(fn):
			var ftw: Variant = fn.get_meta("_fade_tween", null)
			if ftw is Tween and (ftw as Tween).is_valid():
				(ftw as Tween).kill()
			fn.queue_free()
	_fading_nodes.clear()
	for lid in _bg_layers.keys():
		var info: Dictionary = _bg_layers[lid]
		var tw: Variant = info.get("fade_tween", null)
		if tw is Tween and (tw as Tween).is_valid():
			(tw as Tween).kill()
		var sp := info.get("sprite", null) as Sprite2D
		if is_instance_valid(sp):
			sp.modulate.a = 1.0
		if _vm != null:
			_apply_bg_sync(clampi(int(lid), 0, 7), info, true, 1.0)
	for sid in _chara_slots.keys():
		var cinfo: Dictionary = _chara_slots[sid]
		var tw: Variant = cinfo.get("fade_tween", null)
		if tw is Tween and (tw as Tween).is_valid():
			(tw as Tween).kill()
		var csp := cinfo.get("sprite", null) as Sprite2D
		if is_instance_valid(csp):
			var sidx := _slot_to_scr_idx(int(sid))
			var tint_raw := _vm.get_scr_work(5100 + 40 * sidx + 8) if _vm != null else 16777215
			csp.modulate = _decode_scr_color(tint_raw, 1.0)
			if _vm == null or (_vm.get_scr_work(5100 + 40 * sidx + 9) != 65535 and _vm.get_scr_work(5100 + 40 * sidx + 9) >= 0):
				var target_pos := _calc_chara_anchor(sidx)
				csp.position = target_pos
				cinfo["base_y"] = target_pos.y


func _decode_scr_color(raw: int, alpha: float) -> Color:
	if raw <= 0 or raw == 16777215:
		return Color(1.0, 1.0, 1.0, alpha)
	var r := float((raw >> 16) & 0xFF) / 255.0
	var g := float((raw >> 8) & 0xFF) / 255.0
	var b := float(raw & 0xFF) / 255.0
	return Color(r, g, b, alpha)


func _apply_bg_sync(layer_i: int, info: Dictionary, instant: bool, delta: float) -> void:
	var sp := info.get("sprite", null) as Sprite2D
	if not is_instance_valid(sp):
		return
	var w8 := _vm.get_scr_work(4500 + 40 * layer_i + 8)
	var prog := _vm.get_scr_work(4500 + 40 * layer_i + 10)
	var mode := _vm.get_scr_work(4500 + 40 * layer_i + 11)
	var mask_id := _vm.get_scr_work(4500 + 40 * layer_i + 15)

	var should_vis := false
	if mode == 1 or mode == 16:
		info["script_fading"] = true
		if prog >= 256:
			info["script_fade_done"] = true
		should_vis = (layer_i == 0) or (prog > 0)
		var t := clampf(float(prog) / 256.0, 0.0, 1.0)
		if mode == 16 and _vfs != null and _vfs.is_mounted:
			var mcount := _vfs.get_archive_entry_count("mask.mpk")
			if mcount > 0:
				var cur_mid := int(info.get("mask_id", -1))
				if not (sp.material is ShaderMaterial) or cur_mid != mask_id:
					var mname := _vfs.get_entry_name_by_index("mask.mpk", absi(mask_id) % mcount)
					var mtex := _load_cached_texture("mask:%s" % mname, "mask.mpk", mname) if mname != "" else null
					if mtex != null:
						var mat := ShaderMaterial.new()
						mat.shader = MASK_WIPE_SHADER
						mat.set_shader_parameter("mask_tex", mtex)
						mat.set_shader_parameter("softness", 0.08)
						sp.material = mat
						info["mask_id"] = mask_id
			if sp.material is ShaderMaterial:
				(sp.material as ShaderMaterial).set_shader_parameter("progress", 1.0 - t)
				sp.modulate.a = 1.0
			else:
				sp.modulate.a = t
		else:
			if sp.material != null:
				sp.material = null
			sp.modulate.a = t
	else:
		if sp.material != null:
			sp.material = null
		if layer_i == 0:
			should_vis = true
		elif bool(info.get("script_fade_done", false)):
			should_vis = true
		else:
			should_vis = (w8 != 14 and _vm.get_flag(2400 + layer_i) != 0)
		if bool(info.get("script_fading", false)):
			info["script_fading"] = false
			sp.modulate.a = 1.0
		else:
			var tw: Variant = info.get("fade_tween", null)
			if not (tw is Tween and (tw as Tween).is_valid()):
				sp.modulate.a = 1.0

	if sp.visible != should_vis:
		sp.visible = should_vis
	if not sp.visible or bool(info.get("is_color", false)) or bool(info.get("pan_manual", false)):
		return

	var pan_x := float(_vm.get_scr_work(4500 + 40 * layer_i + 0) + _vm.get_scr_work(2400 + 10 * layer_i + 0))
	var pan_y := float(_vm.get_scr_work(4500 + 40 * layer_i + 1) + _vm.get_scr_work(2400 + 10 * layer_i + 1))
	var draw_mode := _vm.get_scr_work(4500 + 40 * layer_i + 9)
	var zoom_raw := _vm.get_scr_work(4500 + 40 * layer_i + 4)
	var tex_size := Vector2(sp.texture.get_size()) if sp.texture != null else Vector2(STAGE_WIDTH, STAGE_HEIGHT)

	var target_scale := Vector2.ONE
	var target_pos := Vector2(STAGE_WIDTH * 0.5, STAGE_HEIGHT * 0.5) - Vector2(pan_x * 1.5, pan_y * 1.5)
	if draw_mode == 2 and zoom_raw > 0:
		var z := clampf(float(zoom_raw) / 1000.0, 0.1, 8.0)
		target_scale = Vector2(z, z)
		target_pos = Vector2(STAGE_WIDTH * 0.5, STAGE_HEIGHT * 0.5) - (Vector2(pan_x * 1.5, pan_y * 1.5) - tex_size * 0.5) * z
	elif tex_size.x > STAGE_WIDTH:
		var fit_s := maxf(STAGE_WIDTH / tex_size.x, 1.0)
		target_scale = Vector2(fit_s, fit_s)

	if instant or (draw_mode == 2 and zoom_raw > 0):
		sp.scale = target_scale
		sp.position = target_pos
	else:
		if sp.scale.distance_to(target_scale) > 0.002:
			sp.scale = sp.scale.lerp(target_scale, clampf(delta * 18.0, 0.0, 1.0))
		if sp.position.distance_to(target_pos) > 0.25:
			sp.position = sp.position.lerp(target_pos, clampf(delta * 18.0, 0.0, 1.0))


func _get_fade_duration_sec(default_sec: float = 0.28) -> float:
	if DisplayServer.get_name() == "headless":
		return 0.0
	if _vm != null:
		if _vm.skip_active:
			return 0.06
		var f := _vm.get_scr_work(1022)
		if f > 0:
			return clampf(float(f) / 60.0, 0.14, 1.6)
	return default_sec


func _spawn_fade_ghost(root: Node2D, src_sp: Sprite2D, dur_sec: float) -> void:
	if not is_instance_valid(src_sp) or not src_sp.visible or src_sp.texture == null or dur_sec <= 0.01:
		return
	var ghost := Sprite2D.new()
	ghost.texture = src_sp.texture
	ghost.centered = src_sp.centered
	ghost.offset = src_sp.offset
	ghost.position = src_sp.position
	ghost.scale = src_sp.scale
	ghost.modulate = src_sp.modulate
	ghost.z_index = src_sp.z_index
	root.add_child(ghost)
	_fading_nodes.append(ghost)
	var tw := create_tween()
	tw.bind_node(ghost)
	ghost.set_meta("_fade_tween", tw)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(ghost, "modulate:a", 0.0, dur_sec)
	tw.tween_callback(func():
		if is_instance_valid(self):
			_fading_nodes.erase(ghost)
		if is_instance_valid(ghost):
			ghost.queue_free()
	)


func _load_cached_texture(cache_key: String, archive: String, entry_name: String) -> Texture2D:
	if _cache.has_texture(cache_key):
		var cached := _cache.get_entry(cache_key)
		return cached.get("texture", null) as Texture2D
	if _vfs == null or not _vfs.is_mounted or entry_name == "":
		return null
	var tex := _vfs.decode_texture(archive, entry_name, false)
	if tex != null:
		_cache.put_texture(cache_key, tex)
	return tex


func load_bg_by_index(layer: int, bg_idx: int) -> bool:
	_ensure_layers()
	if _vfs == null or not _vfs.is_mounted or bg_idx < 0:
		return false

	# 记录旧图以备潜在遮罩转场或交叉淡变
	var old_tex: Texture2D = get_bg_texture(layer)
	if old_tex != null and layer == 0 and _wipe_overlay != null and not _wipe_overlay.visible:
		_wipe_overlay.texture = old_tex

	var entry_name := _vfs.get_entry_name_by_index("bg.mpk", bg_idx)
	if entry_name == "":
		return false
	var tex := _load_cached_texture("bg:%d:%s" % [bg_idx, entry_name], "bg.mpk", entry_name)
	if tex == null:
		return false

	var had_prev := _bg_layers.has(layer) and is_instance_valid(_bg_layers[layer].get("sprite", null)) and (_bg_layers[layer]["sprite"] as Sprite2D).visible
	var sp: Sprite2D = null
	if _bg_layers.has(layer):
		var prev_info: Dictionary = _bg_layers[layer]
		var old_tw: Variant = prev_info.get("fade_tween", null)
		if old_tw is Tween and (old_tw as Tween).is_valid():
			(old_tw as Tween).kill()
		sp = prev_info["sprite"] as Sprite2D
		if had_prev and sp.texture != tex:
			_spawn_fade_ghost(_bg_root, sp, _get_fade_duration_sec(0.32))
	else:
		sp = Sprite2D.new()
		sp.name = "BgLayer_%d" % layer
		sp.centered = true
		sp.z_index = layer
		_bg_root.add_child(sp)

	sp.texture = tex
	sp.material = null
	sp.modulate = Color.WHITE
	var is_staging_bg := (_vm != null and layer >= 1 and _vm.get_scr_work(4500 + 40 * layer + 8) == 14)
	sp.visible = not is_staging_bg
	sp.scale = Vector2.ONE
	sp.position = Vector2(STAGE_WIDTH * 0.5, STAGE_HEIGHT * 0.5)

	# 对超大分辨率 CG（例如 1920x3227 或 3840x4050），允许后续通过平移控制观察区间
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	if tw > STAGE_WIDTH:
		var fit_s := maxf(STAGE_WIDTH / tw, 1.0)
		sp.scale = Vector2(fit_s, fit_s)

	var fade_tw: Tween = null
	var script_mode := _vm.get_scr_work(4500 + 40 * layer + 11) if _vm != null else 0
	var dur := _get_fade_duration_sec(0.32)
	if layer == 0 and script_mode == 0 and sp.visible and dur > 0.01 and (had_prev or _bg_layers.size() > 0):
		sp.modulate.a = 0.0
		fade_tw = create_tween()
		fade_tw.set_ease(Tween.EASE_OUT)
		fade_tw.set_trans(Tween.TRANS_SINE)
		fade_tw.tween_property(sp, "modulate:a", 1.0, dur)

	_bg_layers[layer] = {
		"sprite": sp,
		"bg_idx": bg_idx,
		"entry": entry_name,
		"size": Vector2i(tex.get_width(), tex.get_height()),
		"is_color": false,
		"pan_manual": false,
		"fade_tween": fade_tw,
		"script_fading": false,
		"script_fade_done": false,
		"mask_id": -1,
	}
	if _vm != null:
		_apply_bg_sync(layer, _bg_layers[layer], true, 1.0)
	stage_updated.emit()
	return true


func load_bg_color(layer: int, color: Color) -> void:
	_ensure_layers()
	var had_prev := _bg_layers.has(layer) and is_instance_valid(_bg_layers[layer].get("sprite", null)) and (_bg_layers[layer]["sprite"] as Sprite2D).visible
	var sp: Sprite2D = null
	if _bg_layers.has(layer):
		var prev_info: Dictionary = _bg_layers[layer]
		var old_tw: Variant = prev_info.get("fade_tween", null)
		if old_tw is Tween and (old_tw as Tween).is_valid():
			(old_tw as Tween).kill()
		sp = prev_info["sprite"] as Sprite2D
		if had_prev:
			_spawn_fade_ghost(_bg_root, sp, _get_fade_duration_sec(0.28))
	else:
		sp = Sprite2D.new()
		sp.name = "BgLayer_%d" % layer
		sp.centered = true
		sp.z_index = layer
		_bg_root.add_child(sp)

	sp.texture = _get_white_tex()
	sp.position = Vector2(STAGE_WIDTH * 0.5, STAGE_HEIGHT * 0.5)
	sp.scale = Vector2(STAGE_WIDTH / 4.0, STAGE_HEIGHT / 4.0)
	sp.modulate = Color(color.r, color.g, color.b, color.a)
	var is_staging_bg := (_vm != null and layer >= 1 and _vm.get_scr_work(4500 + 40 * layer + 8) == 14)
	sp.visible = not is_staging_bg

	var fade_tw: Tween = null
	var dur := _get_fade_duration_sec(0.28)
	if sp.visible and dur > 0.01:
		sp.modulate.a = 0.0
		fade_tw = create_tween()
		fade_tw.set_ease(Tween.EASE_OUT)
		fade_tw.set_trans(Tween.TRANS_SINE)
		fade_tw.tween_property(sp, "modulate:a", color.a, dur)

	_bg_layers[layer] = {
		"sprite": sp,
		"bg_idx": -1,
		"entry": "",
		"size": Vector2i(int(STAGE_WIDTH), int(STAGE_HEIGHT)),
		"is_color": true,
		"pan_manual": false,
		"fade_tween": fade_tw,
	}
	stage_updated.emit()


func commit_bg_layer(dst_mask: int, src_mask: int) -> void:
	# 依据 Game.exe 0x460220: 1002(dst_mask, src_mask) 双向交换 dst 与 src 图层（如 0 <-> 1）
	var src_layer := -1
	var dst_layer := -1
	for b in range(8):
		if (src_mask & (1 << b)) != 0 and src_layer < 0:
			src_layer = b
		if (dst_mask & (1 << b)) != 0 and dst_layer < 0:
			dst_layer = b
	if src_layer < 0 or dst_layer < 0 or src_layer == dst_layer:
		return

	var has_dst := _bg_layers.has(dst_layer)
	var has_src := _bg_layers.has(src_layer)
	if not has_dst and not has_src:
		return

	var dst_info: Dictionary = _bg_layers.get(dst_layer, {})
	var src_info: Dictionary = _bg_layers.get(src_layer, {})
	_bg_layers.erase(dst_layer)
	_bg_layers.erase(src_layer)

	if has_src:
		var src_sp := src_info.get("sprite", null) as Sprite2D
		src_info["script_fade_done"] = false
		src_info["script_fading"] = false
		src_info["mask_id"] = -1
		if is_instance_valid(src_sp):
			src_sp.z_index = dst_layer
			src_sp.name = "BgLayer_%d" % dst_layer
			src_sp.material = null
			src_sp.visible = (dst_layer == 0) or (_vm == null) or (_vm.get_scr_work(4500 + 40 * dst_layer + 8) != 14)
			src_sp.modulate.a = 1.0
		_bg_layers[dst_layer] = src_info
		if _vm != null:
			_apply_bg_sync(dst_layer, src_info, true, 1.0)

	if has_dst:
		var dst_sp := dst_info.get("sprite", null) as Sprite2D
		dst_info["script_fade_done"] = false
		dst_info["script_fading"] = false
		dst_info["mask_id"] = -1
		if is_instance_valid(dst_sp):
			dst_sp.z_index = src_layer
			dst_sp.name = "BgLayer_%d" % src_layer
			dst_sp.material = null
			dst_sp.visible = false if src_layer >= 1 else true
		_bg_layers[src_layer] = dst_info

	stage_updated.emit()


func set_bg_pan(layer: int, offset: Vector2, zoom: float = 1.0) -> void:
	if not _bg_layers.has(layer):
		return
	_bg_layers[layer]["pan_manual"] = true
	var sp := _bg_layers[layer]["sprite"] as Sprite2D
	if not is_instance_valid(sp):
		return
	sp.scale = Vector2(zoom, zoom)
	sp.position = Vector2(STAGE_WIDTH * 0.5, STAGE_HEIGHT * 0.5) + offset


func clear_bg_layer(layer: int) -> void:
	if not _bg_layers.has(layer):
		return
	var info: Dictionary = _bg_layers[layer]
	var old_tw: Variant = info.get("fade_tween", null)
	if old_tw is Tween and (old_tw as Tween).is_valid():
		(old_tw as Tween).kill()
	var sp := info["sprite"] as Sprite2D
	if is_instance_valid(sp):
		_spawn_fade_ghost(_bg_root, sp, _get_fade_duration_sec(0.24))
		sp.visible = false
		sp.texture = null
	_bg_layers.erase(layer)
	stage_updated.emit()


func get_bg_texture(layer: int) -> Texture2D:
	if _bg_layers.has(layer):
		var sp := _bg_layers[layer]["sprite"] as Sprite2D
		if is_instance_valid(sp):
			return sp.texture
	return null


func load_pic(surf_id: int, archive_type: int, file_id: int) -> bool:
	_ensure_layers()
	if _vfs == null or not _vfs.is_mounted or file_id < 0:
		return false
	if archive_type != 0:
		return false
	var arc := "bg.mpk"
	var entry_name := _vfs.get_entry_name_by_index(arc, file_id)
	if entry_name == "":
		return false
	var tex := _load_cached_texture("pic:%s:%d:%s" % [arc, file_id, entry_name], arc, entry_name)
	if tex == null:
		return false

	var sp: Sprite2D = null
	if _pic_layers.has(surf_id):
		sp = _pic_layers[surf_id]["sprite"] as Sprite2D
	else:
		sp = Sprite2D.new()
		sp.name = "Pic_%d" % surf_id
		sp.centered = true
		sp.z_index = surf_id % 10
		_pic_root.add_child(sp)
	sp.texture = tex
	sp.position = Vector2(STAGE_WIDTH * 0.5, STAGE_HEIGHT * 0.5)
	_pic_layers[surf_id] = {"sprite": sp, "archive": arc, "file_id": file_id}
	stage_updated.emit()
	return true


func set_pic_visible(surf_id: int, is_visible: bool) -> void:
	if _pic_layers.has(surf_id):
		var sp := _pic_layers[surf_id]["sprite"] as Sprite2D
		if is_instance_valid(sp):
			sp.visible = is_visible


func _slot_to_scr_idx(slot: int) -> int:
	if slot <= 0:
		return 0
	for b in range(8):
		if slot == (1 << b):
			return b
	return clampi(slot, 0, 7)


func load_chara(slot: int, chara_idx: int, group_hint: int = 0) -> bool:
	_ensure_layers()
	if _vfs == null or not _vfs.is_mounted or chara_idx < 0:
		return false

	var entry_name := _vfs.get_entry_name_by_index("chara.mpk", chara_idx)
	if entry_name == "":
		return false

	var face_id := maxi(1, group_hint & 0xFF)
	var grp_ids := PackedInt32Array([
		1,
		0x20000000 | face_id,
		0x40000000 | (face_id << 8),
	])
	if group_hint > 255:
		var extra_gid := (group_hint >> 8) & 0xFFFF
		if extra_gid > 0:
			grp_ids.append(extra_gid)

	var key := "chara:%d:%s:%d" % [chara_idx, entry_name, face_id]
	var tex: Texture2D = null
	var origin := Vector2i.ZERO
	if _cache.has_texture(key):
		var cached := _cache.get_entry(key)
		tex = cached.get("texture", null) as Texture2D
		origin = cached.get("origin", Vector2i.ZERO)
	else:
		var res := _vfs.compose_chara_lay(entry_name, grp_ids)
		if (not bool(res.get("ok", false)) or (res.get("image") as Image).get_width() <= 2) and face_id != 1:
			res = _vfs.compose_chara_lay(entry_name, PackedInt32Array([1, 0x20000001, 0x40000100]))
		if not bool(res.get("ok", false)):
			return false
		var img := res.get("image", null) as Image
		if img == null or img.is_empty() or img.get_width() <= 2:
			return false
		tex = ImageTexture.create_from_image(img)
		origin = res.get("origin", Vector2i.ZERO)
		_cache.put_texture(key, tex, origin)

	if tex == null:
		return false

	var is_new_slot := not _chara_slots.has(slot)
	var sp: Sprite2D = null
	if not is_new_slot:
		var prev: Dictionary = _chara_slots[slot]
		var old_tw: Variant = prev.get("fade_tween", null)
		if old_tw is Tween and (old_tw as Tween).is_valid():
			(old_tw as Tween).kill()
		sp = prev["sprite"] as Sprite2D
		# 表情/服装替换时保留平滑过渡影子
		if is_instance_valid(sp) and sp.texture != tex and sp.visible:
			_spawn_fade_ghost(_chara_root, sp, _get_fade_duration_sec(0.18))
	else:
		sp = Sprite2D.new()
		sp.name = "CharaSlot_%d" % slot
		sp.centered = false
		sp.z_index = slot
		_chara_root.add_child(sp)

	var sidx := _slot_to_scr_idx(slot)
	var anchor := _calc_chara_anchor(sidx)
	sp.texture = tex
	sp.centered = false
	sp.offset = Vector2(origin)
	# 暂存槽 (slot >= 16) 在脚本运行时保持隐藏，待 1006 交换至前台槽 (1..8) 后再显现
	var is_staging := (_vm != null and slot >= 16)
	sp.visible = not is_staging
	sp.scale = CHARA_DISPLAY_SCALE
	sp.position = anchor
	var tint_raw := _vm.get_scr_work(5100 + 40 * sidx + 8) if _vm != null else 16777215
	sp.modulate = _decode_scr_color(tint_raw, 1.0)

	var fade_tw: Tween = null
	var dur := _get_fade_duration_sec(0.28)
	var front_slot := slot >> 4 if slot >= 16 else slot
	var front_exists := (front_slot != slot) and _chara_slots.has(front_slot)
	if sp.visible and is_new_slot and not front_exists and dur > 0.01:
		sp.modulate.a = 0.0
		fade_tw = create_tween()
		fade_tw.set_ease(Tween.EASE_OUT)
		fade_tw.set_trans(Tween.TRANS_SINE)
		fade_tw.tween_property(sp, "modulate:a", 1.0, dur)

	_chara_slots[slot] = {
		"sprite": sp,
		"chara_idx": chara_idx,
		"entry": entry_name,
		"group_hint": face_id,
		"origin": origin,
		"base_y": anchor.y,
		"alpha": 1.0,
		"fade_tween": fade_tw,
		"center_reset_frames": 0,
	}
	_relayout_chara_slots()
	stage_updated.emit()
	return true


func swap_chara_slots(dst_mask: int, src_mask: int) -> void:
	# 1006(dst_mask, src_mask): 将暂存立绘槽 (16..128) 转入前台槽 (1..8)，若暂存槽为空则淡出释放前台槽
	var dst_slot := -1
	var src_slot := -1
	for b in range(8):
		var m := 1 << b
		if (dst_mask & m) != 0 and dst_slot < 0:
			dst_slot = m
		if (src_mask & m) != 0 and src_slot < 0:
			src_slot = m
	if dst_slot < 0 or src_slot < 0 or dst_slot == src_slot:
		return

	if _chara_slots.has(src_slot):
		var src_info: Dictionary = _chara_slots[src_slot]
		var src_sp := src_info["sprite"] as Sprite2D
		var had_dst := _chara_slots.has(dst_slot)
		if had_dst:
			var dst_info: Dictionary = _chara_slots[dst_slot]
			var old_tw: Variant = dst_info.get("fade_tween", null)
			if old_tw is Tween and (old_tw as Tween).is_valid():
				(old_tw as Tween).kill()
			var dst_sp := dst_info["sprite"] as Sprite2D
			if is_instance_valid(dst_sp):
				if is_instance_valid(src_sp) and dst_sp.texture != src_sp.texture:
					_spawn_fade_ghost(_chara_root, dst_sp, _get_fade_duration_sec(0.22))
				dst_sp.queue_free()
		_chara_slots[dst_slot] = src_info
		_chara_slots.erase(src_slot)
		if is_instance_valid(src_sp):
			src_sp.name = "CharaSlot_%d" % dst_slot
			src_sp.z_index = dst_slot
			src_sp.visible = (dst_slot < 16) or (_vm == null)
			var d_sidx := _slot_to_scr_idx(dst_slot)
			var anchor := _calc_chara_anchor(d_sidx)
			src_sp.position = anchor
			src_info["base_y"] = anchor.y
			src_info["center_reset_frames"] = 0
			var tint_raw := _vm.get_scr_work(5100 + 40 * d_sidx + 8) if _vm != null else 16777215
			src_sp.modulate = _decode_scr_color(tint_raw, 1.0)
			var dur := _get_fade_duration_sec(0.28)
			if src_sp.visible and not had_dst and dur > 0.01:
				var old_stw: Variant = src_info.get("fade_tween", null)
				if old_stw is Tween and (old_stw as Tween).is_valid():
					(old_stw as Tween).kill()
				src_sp.modulate.a = 0.0
				var ftw := create_tween()
				ftw.set_ease(Tween.EASE_OUT)
				ftw.set_trans(Tween.TRANS_SINE)
				ftw.tween_property(src_sp, "modulate:a", 1.0, dur)
				src_info["fade_tween"] = ftw
			else:
				src_sp.modulate.a = 1.0
		_relayout_chara_slots()
		stage_updated.emit()
	elif _chara_slots.has(dst_slot):
		# 暂存槽为空表示脚本清除了该角色，执行平滑淡出释放
		release_chara(dst_slot)


func release_chara(slot: int) -> void:
	if not _chara_slots.has(slot):
		return
	var info: Dictionary = _chara_slots[slot]
	var old_tw: Variant = info.get("fade_tween", null)
	if old_tw is Tween and (old_tw as Tween).is_valid():
		(old_tw as Tween).kill()
	var sp := info["sprite"] as Sprite2D
	_chara_slots.erase(slot)

	if is_instance_valid(sp):
		var dur := _get_fade_duration_sec(0.30)
		if dur > 0.01 and sp.visible and sp.modulate.a > 0.01:
			_fading_nodes.append(sp)
			var tw := create_tween()
			tw.bind_node(sp)
			sp.set_meta("_fade_tween", tw)
			tw.set_ease(Tween.EASE_OUT)
			tw.set_trans(Tween.TRANS_SINE)
			tw.tween_property(sp, "modulate:a", 0.0, dur)
			tw.tween_callback(func():
				if is_instance_valid(self):
					_fading_nodes.erase(sp)
				if is_instance_valid(sp):
					sp.queue_free()
			)
		else:
			sp.queue_free()

	_relayout_chara_slots()
	stage_updated.emit()


func _calc_chara_anchor(sidx: int) -> Vector2:
	if _vm == null:
		return Vector2(STAGE_WIDTH * 0.5, STAGE_HEIGHT * 0.5)
	var sx := _vm.get_scr_work(5100 + 40 * sidx + 0) + _vm.get_scr_work(2500 + 10 * sidx + 0)
	var sy := _vm.get_scr_work(5100 + 40 * sidx + 1) + _vm.get_scr_work(2500 + 10 * sidx + 1)
	if sx == 0 and sy == 0:
		return Vector2(STAGE_WIDTH * 0.5, STAGE_HEIGHT * 0.5)
	return Vector2(float(sx) * 1.5, float(sy) * 1.5)


func _relayout_chara_slots() -> void:
	var visible_keys: Array = []
	for k in _chara_slots.keys():
		var sp_k := _chara_slots[k].get("sprite", null) as Sprite2D
		if is_instance_valid(sp_k) and sp_k.visible:
			visible_keys.append(k)
	visible_keys.sort()
	var n := visible_keys.size()
	if n == 0:
		return
	for i in range(n):
		var slot_id := int(visible_keys[i])
		var sp := _chara_slots[slot_id]["sprite"] as Sprite2D
		var target_pos := Vector2(STAGE_WIDTH * 0.5, STAGE_HEIGHT * 0.5)
		var used_scr := false
		if _vm != null:
			var sidx := _slot_to_scr_idx(slot_id)
			var ch_idx := _vm.get_scr_work(5100 + 40 * sidx + 9)
			var flag_active := _vm.get_flag(2410 + sidx) != 0
			if ch_idx < 0 or ch_idx == 65535 or not flag_active:
				# 变量驱动的槽位失效：原版引擎中对应槽位已注销，平滑淡出释放节点防止穿模残留
				release_chara(slot_id)
				continue
			var sx := _vm.get_scr_work(5100 + 40 * sidx + 0) + _vm.get_scr_work(2500 + 10 * sidx + 0)
			var sy := _vm.get_scr_work(5100 + 40 * sidx + 1) + _vm.get_scr_work(2500 + 10 * sidx + 1)
			if sx != 0 or sy != 0:
				target_pos = Vector2(float(sx) * 1.5, float(sy) * 1.5)
				used_scr = true
				if sx == 640 and sy == 360 and sp.position.distance_to(target_pos) > 4.0:
					continue
		if not used_scr:
			if n == 1:
				target_pos.x = STAGE_WIDTH * 0.5
			elif n == 2:
				target_pos.x = STAGE_WIDTH * (0.32 if i == 0 else 0.68)
			else:
				var t := float(i) / float(n - 1)
				target_pos.x = STAGE_WIDTH * lerpf(0.22, 0.78, t)
		sp.position = target_pos
		_chara_slots[slot_id]["base_y"] = target_pos.y


func get_bg_count() -> int:
	return _bg_layers.size()


func get_chara_count() -> int:
	return _chara_slots.size()


func update_lip_sync(_amplitude_level: int) -> void:
	# 保持立绘缩放恒定（CHARA_DISPLAY_SCALE），避免角色说话时整张立绘上下跳动或拉伸
	for slot_id in _chara_slots.keys():
		var sp := _chara_slots[slot_id]["sprite"] as Sprite2D
		if is_instance_valid(sp):
			if sp.scale != CHARA_DISPLAY_SCALE:
				sp.scale = CHARA_DISPLAY_SCALE
			var base_y := float(_chara_slots[slot_id].get("base_y", STAGE_HEIGHT * 0.5))
			if absf(sp.position.y - base_y) > 0.01:
				sp.position.y = base_y


func play_mask_wipe(mask_id: int, duration_frames: int = 30) -> void:
	_ensure_layers()
	if _wipe_overlay == null or _wipe_overlay.texture == null:
		return

	var mask_tex: Texture2D = null
	if _vfs != null and _vfs.is_mounted:
		var mcount := _vfs.get_archive_entry_count("mask.mpk")
		if mcount > 0:
			var mname := _vfs.get_entry_name_by_index("mask.mpk", mask_id % mcount)
			if mname != "":
				mask_tex = _load_cached_texture("mask:%s" % mname, "mask.mpk", mname)

	if mask_tex != null:
		var mat := ShaderMaterial.new()
		mat.shader = MASK_WIPE_SHADER
		mat.set_shader_parameter("mask_tex", mask_tex)
		mat.set_shader_parameter("progress", 0.0)
		mat.set_shader_parameter("softness", 0.08)
		_wipe_overlay.material = mat
	else:
		_wipe_overlay.material = null

	_wipe_overlay.visible = true
	_wipe_overlay.modulate.a = 1.0
	if _wipe_tween != null and _wipe_tween.is_valid():
		_wipe_tween.kill()

	var dur_sec := clampf(float(maxi(1, duration_frames)) / 60.0, 0.05, 3.0)
	_wipe_tween = create_tween()
	if _wipe_overlay.material is ShaderMaterial:
		var smat := _wipe_overlay.material as ShaderMaterial
		_wipe_tween.tween_method(func(v: float): smat.set_shader_parameter("progress", v), 0.0, 1.0, dur_sec)
	else:
		_wipe_tween.tween_property(_wipe_overlay, "modulate:a", 0.0, dur_sec)
	_wipe_tween.tween_callback(func():
		if is_instance_valid(_wipe_overlay):
			_wipe_overlay.visible = false
	)


## 导出当前舞台背景/图片/立绘图层状态（供存档使用）
func export_state() -> Dictionary:
	var bg_list: Array = []
	for lid in _bg_layers.keys():
		var info: Dictionary = _bg_layers[lid]
		var sp := info.get("sprite", null) as Sprite2D
		var vis := is_instance_valid(sp) and sp.visible
		if bool(info.get("is_color", false)):
			var col := sp.modulate if is_instance_valid(sp) else Color.BLACK
			bg_list.append({
				"layer": int(lid),
				"is_color": true,
				"color": [col.r, col.g, col.b, col.a],
				"visible": vis,
			})
		else:
			var bg_idx := int(info.get("bg_idx", -1))
			if bg_idx >= 0:
				bg_list.append({
					"layer": int(lid),
					"is_color": false,
					"bg_idx": bg_idx,
					"visible": vis,
				})

	var pic_list: Array = []
	for sid in _pic_layers.keys():
		var pinfo: Dictionary = _pic_layers[sid]
		var psp := pinfo.get("sprite", null) as Sprite2D
		pic_list.append({
			"surf_id": int(sid),
			"file_id": int(pinfo.get("file_id", -1)),
			"visible": is_instance_valid(psp) and psp.visible,
		})

	var chara_list: Array = []
	for cslot in _chara_slots.keys():
		var cinfo: Dictionary = _chara_slots[cslot]
		var csp := cinfo.get("sprite", null) as Sprite2D
		chara_list.append({
			"slot": int(cslot),
			"chara_idx": int(cinfo.get("chara_idx", -1)),
			"group_hint": int(cinfo.get("group_hint", 1)),
			"visible": is_instance_valid(csp) and csp.visible,
		})

	return {
		"bg_layers": bg_list,
		"pic_layers": pic_list,
		"chara_slots": chara_list,
	}


## 从存档状态完整还原舞台背景、图片与立绘
func import_state(st: Dictionary) -> void:
	reset_stage()
	if st.is_empty():
		return

	for b in st.get("bg_layers", []):
		if not (b is Dictionary):
			continue
		var bd := b as Dictionary
		var lid := int(bd.get("layer", 0))
		var vis := bool(bd.get("visible", true))
		if bool(bd.get("is_color", false)):
			var carr: Array = bd.get("color", [0.0, 0.0, 0.0, 1.0])
			var col := Color(
				float(carr[0]) if carr.size() > 0 else 0.0,
				float(carr[1]) if carr.size() > 1 else 0.0,
				float(carr[2]) if carr.size() > 2 else 0.0,
				float(carr[3]) if carr.size() > 3 else 1.0
			)
			load_bg_color(lid, col)
		else:
			var bg_idx := int(bd.get("bg_idx", -1))
			if bg_idx >= 0:
				load_bg_by_index(lid, bg_idx)
		if _bg_layers.has(lid):
			var sp := _bg_layers[lid].get("sprite", null) as Sprite2D
			if is_instance_valid(sp):
				sp.visible = vis

	for p in st.get("pic_layers", []):
		if not (p is Dictionary):
			continue
		var pd := p as Dictionary
		var sid := int(pd.get("surf_id", -1))
		var fid := int(pd.get("file_id", -1))
		if sid >= 0 and fid >= 0 and load_pic(sid, 0, fid):
			set_pic_visible(sid, bool(pd.get("visible", true)))

	for c in st.get("chara_slots", []):
		if not (c is Dictionary):
			continue
		var cd := c as Dictionary
		var cslot := int(cd.get("slot", -1))
		var cidx := int(cd.get("chara_idx", -1))
		var gh := int(cd.get("group_hint", 1))
		if cslot >= 0 and cidx >= 0 and load_chara(cslot, cidx, gh):
			if _chara_slots.has(cslot):
				var csp := _chara_slots[cslot].get("sprite", null) as Sprite2D
				if is_instance_valid(csp):
					csp.visible = bool(cd.get("visible", true))

	flush_transitions()
	_relayout_chara_slots()
	stage_updated.emit()
