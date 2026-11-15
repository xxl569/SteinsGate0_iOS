class_name MgsStage
extends Node2D
## 1920x1080 舞台渲染器：多图层背景（支持超大分辨率 CG 平移）、灰度遮罩转场、.lay 差分立绘与 LRU 缓存

signal stage_updated()

const STAGE_WIDTH := 1920.0
const STAGE_HEIGHT := 1080.0
const MASK_WIPE_SHADER := preload("res://assets/shaders/mask_wipe.gdshader")

var _vfs: MgsVfs = null
var _cache: MgsCache = MgsCache.new()

var _bg_root: Node2D = null
var _pic_root: Node2D = null
var _chara_root: Node2D = null
var _wipe_overlay: TextureRect = null

var _bg_layers: Dictionary = {} # layer_id(int) -> { sprite: Sprite2D, bg_idx: int, pan: Vector2, scale: float }
var _pic_layers: Dictionary = {} # surf_id(int) -> { sprite: Sprite2D, archive_type: int, file_id: int }
var _chara_slots: Dictionary = {} # slot_id(int) -> Dictionary

var _wipe_tween: Tween = null
var _blink_elapsed: float = 0.0


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


func bind_vfs(vfs: MgsVfs) -> void:
	_vfs = vfs
	_ensure_layers()


func bind_vm(vm: Sc3Vm) -> void:
	if vm == null:
		return
	if not vm.bg_changed.is_connected(load_bg_by_index):
		vm.bg_changed.connect(load_bg_by_index)
	if not vm.bg_cleared.is_connected(clear_bg_layer):
		vm.bg_cleared.connect(clear_bg_layer)
	if not vm.pic_loaded.is_connected(load_pic):
		vm.pic_loaded.connect(load_pic)
	if not vm.disp_changed.is_connected(set_pic_visible):
		vm.disp_changed.connect(set_pic_visible)
	if not vm.chara_loaded.is_connected(load_chara):
		vm.chara_loaded.connect(load_chara)
	if not vm.chara_released.is_connected(release_chara):
		vm.chara_released.connect(release_chara)
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
		var sp := info["sprite"] as Sprite2D
		if is_instance_valid(sp):
			sp.queue_free()
	_chara_slots.clear()

	if _wipe_overlay != null:
		_wipe_overlay.visible = false
		_wipe_overlay.texture = null


func _process(delta: float) -> void:
	_blink_elapsed += delta
	# 轻量级待机呼吸/眨眼节律更新，不依赖额外纹理切换
	if not _chara_slots.is_empty():
		var phase := fmod(_blink_elapsed, 4.5)
		for slot_id in _chara_slots.keys():
			var info: Dictionary = _chara_slots[slot_id]
			var sp := info["sprite"] as Sprite2D
			if is_instance_valid(sp) and sp.visible:
				var offset_phase := fmod(phase + float(int(slot_id)) * 0.7, 4.5)
				var breath := sin(_blink_elapsed * 1.4 + float(int(slot_id))) * 1.5
				var base_y := float(info.get("base_y", STAGE_HEIGHT * 0.5))
				sp.position.y = base_y + breath
				if offset_phase > 4.35:
					sp.modulate.a = 0.96
				else:
					sp.modulate.a = float(info.get("alpha", 1.0))


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

	# 记录旧图以备潜在转场叠加
	var old_tex: Texture2D = get_bg_texture(layer)
	if old_tex != null and layer == 0 and _wipe_overlay != null and not _wipe_overlay.visible:
		_wipe_overlay.texture = old_tex

	var entry_name := _vfs.get_entry_name_by_index("bg.mpk", bg_idx)
	if entry_name == "":
		return false
	var tex := _load_cached_texture("bg:%d:%s" % [bg_idx, entry_name], "bg.mpk", entry_name)
	if tex == null:
		return false

	var sp: Sprite2D = null
	if _bg_layers.has(layer):
		sp = _bg_layers[layer]["sprite"] as Sprite2D
	else:
		sp = Sprite2D.new()
		sp.name = "BgLayer_%d" % layer
		sp.centered = true
		sp.z_index = layer
		_bg_root.add_child(sp)

	sp.texture = tex
	sp.visible = true
	sp.scale = Vector2.ONE
	sp.position = Vector2(STAGE_WIDTH * 0.5, STAGE_HEIGHT * 0.5)

	# 对超大分辨率 CG（例如 1920x3227 或 3840x4050），允许后续通过平移控制观察区间，默认水平居中顶对齐偏中
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	if tw > STAGE_WIDTH or th > STAGE_HEIGHT:
		if tw > STAGE_WIDTH:
			var fit_s := maxf(STAGE_WIDTH / tw, 1.0)
			sp.scale = Vector2(fit_s, fit_s)
		if th > STAGE_HEIGHT:
			sp.position.y = STAGE_HEIGHT * 0.5

	_bg_layers[layer] = {
		"sprite": sp,
		"bg_idx": bg_idx,
		"entry": entry_name,
		"size": Vector2i(tex.get_width(), tex.get_height()),
	}
	stage_updated.emit()
	return true


func set_bg_pan(layer: int, offset: Vector2, zoom: float = 1.0) -> void:
	if not _bg_layers.has(layer):
		return
	var sp := _bg_layers[layer]["sprite"] as Sprite2D
	if not is_instance_valid(sp):
		return
	sp.scale = Vector2(zoom, zoom)
	sp.position = Vector2(STAGE_WIDTH * 0.5, STAGE_HEIGHT * 0.5) + offset


func clear_bg_layer(layer: int) -> void:
	if layer == 2 and not _chara_slots.is_empty():
		for cslot in _chara_slots.keys():
			var csp := _chara_slots[cslot]["sprite"] as Sprite2D
			if is_instance_valid(csp):
				csp.queue_free()
		_chara_slots.clear()
	if not _bg_layers.has(layer):
		return
	var sp := _bg_layers[layer]["sprite"] as Sprite2D
	if is_instance_valid(sp):
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
	# archive_type != 0（system.mpk）为系统字库/菜单图集纹理，由 UiThemeLoader 与 MgsFontRenderer 专属切片管理，不可整张铺上舞台
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


func load_chara(slot: int, chara_idx: int, group_hint: int = 0) -> bool:
	_ensure_layers()
	if _vfs == null or not _vfs.is_mounted or chara_idx < 0:
		return false

	var entry_name := _vfs.get_entry_name_by_index("chara.mpk", chara_idx)
	if entry_name == "":
		return false

	# SG0_ChaLoad 的 group_hint 实测为 1-based 表情编号 (如 3/4/5) 或位掩码；
	# .lay 组 ID 约定：0x1=身体底图, 0x20000000|face=表情脸盘, 0x40000000|(face<<8)=睁眼差分
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
			# 若指定表情编号不存在则回退到表情 1
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

	var sp: Sprite2D = null
	if _chara_slots.has(slot):
		sp = _chara_slots[slot]["sprite"] as Sprite2D
	else:
		sp = Sprite2D.new()
		sp.name = "CharaSlot_%d" % slot
		sp.centered = true
		sp.z_index = slot
		_chara_root.add_child(sp)

	sp.texture = tex
	sp.visible = true
	sp.scale = Vector2(0.84, 0.84)
	var base_y := STAGE_HEIGHT * 0.60
	sp.position = Vector2(STAGE_WIDTH * 0.5, base_y)

	_chara_slots[slot] = {
		"sprite": sp,
		"chara_idx": chara_idx,
		"entry": entry_name,
		"group_hint": face_id,
		"origin": origin,
		"base_y": base_y,
		"alpha": 1.0,
	}
	_relayout_chara_slots()
	stage_updated.emit()
	return true


func release_chara(slot: int) -> void:
	if not _chara_slots.has(slot):
		return
	var sp := _chara_slots[slot]["sprite"] as Sprite2D
	if is_instance_valid(sp):
		sp.queue_free()
	_chara_slots.erase(slot)
	_relayout_chara_slots()
	stage_updated.emit()


func _relayout_chara_slots() -> void:
	var keys := _chara_slots.keys()
	keys.sort()
	var n := keys.size()
	if n == 0:
		return
	for i in range(n):
		var sp := _chara_slots[keys[i]]["sprite"] as Sprite2D
		if not is_instance_valid(sp):
			continue
		if n == 1:
			sp.position.x = STAGE_WIDTH * 0.5
		elif n == 2:
			sp.position.x = STAGE_WIDTH * (0.32 if i == 0 else 0.68)
		else:
			var t := float(i) / float(n - 1)
			sp.position.x = STAGE_WIDTH * lerpf(0.22, 0.78, t)


func get_chara_count() -> int:
	return _chara_slots.size()


func update_lip_sync(amplitude_level: int) -> void:
	# 语音振幅映射到活跃立绘轻微口型震动反馈（0=闭, 1=半开, 2=全开）
	var scale_bump := 1.0 + float(clampi(amplitude_level, 0, 2)) * 0.0025
	for slot_id in _chara_slots.keys():
		var sp := _chara_slots[slot_id]["sprite"] as Sprite2D
		if is_instance_valid(sp) and sp.visible:
			sp.scale = Vector2(1.0, scale_bump)


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
