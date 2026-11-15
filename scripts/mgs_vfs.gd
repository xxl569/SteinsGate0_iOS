class_name MgsVfs
extends RefCounted
## MAGES. 多封包虚拟文件系统与资产解码统一入口（封装 MgsNative + BYOA 外置路径扫描）

signal mounted(entry_count: int, game_dir: String)
signal mount_failed(searched_paths: PackedStringArray)

const FONT_WIDTHS_PATH := "res://assets/tables/font_widths.bin"
const FONT_A_SLOTS := 5440 # 64 * 85
const FONT_B_SLOTS := 2560 # 64 * 40
const TOTAL_GLYPH_SLOTS := 8000

var native: Object = null # MgsNative 实例
var is_mounted: bool = false
var active_game_dir: String = ""
var active_movie_dir: String = ""

# 字体宽度表：2 套 * 8000 槽位 -> PackedByteArray (每人 3B: x0, x1, advance)
var _font_widths_raw: PackedByteArray = PackedByteArray()
var _font_widths_loaded: bool = false
var _archive_index_cache: Dictionary = {} # archive_lower -> PackedStringArray
var _sorted_movie_files: PackedStringArray = PackedStringArray()


func _init() -> void:
	if ClassDB.class_exists(&"MgsNative"):
		native = ClassDB.instantiate(&"MgsNative")
	_load_font_widths()


func _load_font_widths() -> void:
	if not FileAccess.file_exists(FONT_WIDTHS_PATH):
		push_warning("缺少字形宽度表: %s" % FONT_WIDTHS_PATH)
		return
	var bytes := FileAccess.get_file_as_bytes(FONT_WIDTHS_PATH)
	if bytes.size() < 16 or bytes.slice(0, 4).get_string_from_ascii() != "FWT1":
		push_warning("字形宽度表头无效: %s" % FONT_WIDTHS_PATH)
		return
	_font_widths_raw = bytes
	_font_widths_loaded = true


func get_glyph_metrics(font_set: int, glyph_id: int) -> Vector3i:
	## 返回 Vector3i(x0, x1, advance)。若越界则回退全角 48 步长。
	if not _font_widths_loaded or glyph_id < 0 or glyph_id >= TOTAL_GLYPH_SLOTS:
		return Vector3i(0, 47, 24 if glyph_id < 128 else 48)
	var s := clampi(font_set, 0, 1)
	var off := 16 + (s * TOTAL_GLYPH_SLOTS + glyph_id) * 3
	if off + 3 > _font_widths_raw.size():
		return Vector3i(0, 47, 48)
	return Vector3i(
		int(_font_widths_raw[off]),
		int(_font_widths_raw[off + 1]),
		int(_font_widths_raw[off + 2])
	)


func get_candidate_game_dirs(config: ConfigManager = null) -> PackedStringArray:
	var list := PackedStringArray()
	if config != null and config.custom_game_dir != "":
		list.append(config.custom_game_dir)

	var user_dir := OS.get_user_data_dir()
	var docs_parent := user_dir.get_base_dir()
	# iOS App Documents 根目录与常见子目录
	list.append(user_dir)
	list.append(user_dir.path_join("USRDIR"))
	list.append(user_dir.path_join("game"))
	list.append(user_dir.path_join("game/USRDIR"))
	list.append(docs_parent)
	list.append(docs_parent.path_join("Documents"))
	list.append(docs_parent.path_join("Documents/USRDIR"))
	list.append(docs_parent.path_join("Documents/game"))

	# macOS / Windows 桌面同级目录调试路径
	var exe_dir := OS.get_executable_path().get_base_dir()
	list.append(exe_dir)
	list.append(exe_dir.path_join("USRDIR"))
	list.append("U:/anti/projects/STEINS GATE 0")
	list.append("U:/anti/projects/STEINS GATE 0/USRDIR")
	return _dedup_paths(list)


func get_candidate_movie_dirs(config: ConfigManager = null) -> PackedStringArray:
	var list := PackedStringArray()
	if config != null and config.custom_movie_dir != "":
		list.append(config.custom_movie_dir)
	if active_game_dir != "":
		list.append(active_game_dir.path_join("movie"))
		list.append(active_game_dir.get_base_dir().path_join("movie"))
	var user_dir := OS.get_user_data_dir()
	list.append(user_dir.path_join("movie"))
	list.append(user_dir.get_base_dir().path_join("Documents/movie"))
	list.append("U:/anti/temp/SteinsGate0_iOS/SteinsGate0_iOS_Documents/movie")
	return _dedup_paths(list)


func _dedup_paths(raw: PackedStringArray) -> PackedStringArray:
	var seen := {}
	var out := PackedStringArray()
	for p in raw:
		var norm := p.replace("\\", "/").rstrip("/")
		if norm == "" or seen.has(norm):
			continue
		seen[norm] = true
		out.append(norm)
	return out


func auto_mount(config: ConfigManager = null) -> bool:
	if native == null:
		push_error("MgsNative GDExtension 未加载")
		return false

	var candidates := get_candidate_game_dirs(config)
	for dir_path in candidates:
		if not DirAccess.dir_exists_absolute(dir_path):
			continue
		native.reset()
		var cnt: int = native.mount_game_dir(dir_path)
		if cnt > 0 and native.has_entry("script.mpk", "_Startup_win.scx"):
			_archive_index_cache.clear()
			is_mounted = true
			active_game_dir = dir_path
			_detect_movie_dir(config)
			mounted.emit(cnt, active_game_dir)
			return true

	is_mounted = false
	active_game_dir = ""
	mount_failed.emit(candidates)
	return false


func mount_explicit(dir_path: String, movie_dir: String = "") -> bool:
	if native == null:
		return false
	native.reset()
	var cnt: int = native.mount_game_dir(dir_path)
	if cnt > 0:
		_archive_index_cache.clear()
		is_mounted = true
		active_game_dir = dir_path
		if movie_dir != "":
			_scan_movie_dir(movie_dir)
		else:
			_detect_movie_dir(null)
		mounted.emit(cnt, active_game_dir)
		return true
	return false


func _scan_movie_dir(d: String) -> bool:
	if not DirAccess.dir_exists_absolute(d):
		return false
	var da := DirAccess.open(d)
	if da == null:
		return false
	da.list_dir_begin()
	var fname := da.get_next()
	var ogvs: Array[String] = []
	while fname != "":
		if not da.current_is_dir() and fname.to_lower().ends_with(".ogv"):
			ogvs.append(fname)
		fname = da.get_next()
	da.list_dir_end()
	if ogvs.is_empty():
		return false
	ogvs.sort()
	_sorted_movie_files = PackedStringArray(ogvs)
	active_movie_dir = d
	return true


func _detect_movie_dir(config: ConfigManager) -> void:
	active_movie_dir = ""
	_sorted_movie_files = PackedStringArray()
	for d in get_candidate_movie_dirs(config):
		if _scan_movie_dir(d):
			return


func get_entry_name_by_index(archive: String, idx: int) -> String:
	if not is_mounted or native == null or idx < 0:
		return ""
	var key := archive.to_lower()
	if not key.ends_with(".mpk"):
		key += ".mpk"
	if not _archive_index_cache.has(key):
		_archive_index_cache[key] = native.list_entries(key, "")
	var arr: PackedStringArray = _archive_index_cache[key]
	if idx < arr.size():
		return arr[idx]
	return ""


func get_archive_entry_count(archive: String) -> int:
	if not is_mounted or native == null:
		return 0
	var key := archive.to_lower()
	if not key.ends_with(".mpk"):
		key += ".mpk"
	if not _archive_index_cache.has(key):
		_archive_index_cache[key] = native.list_entries(key, "")
	return (_archive_index_cache[key] as PackedStringArray).size()


func get_movie_path_by_index(idx: int) -> String:
	if active_movie_dir == "" or idx < 0 or idx >= _sorted_movie_files.size():
		return ""
	return active_movie_dir.path_join(_sorted_movie_files[idx])


func get_movie_names() -> PackedStringArray:
	return _sorted_movie_files


## 根据 chara.mpk 条目名或索引加载并合成 .lay + 图集，返回 { ok, image, origin }
func compose_chara_lay(entry_or_idx: Variant, group_ids: PackedInt32Array) -> Dictionary:
	if not is_mounted or native == null:
		return {"ok": false}
	var entry_name := ""
	if entry_or_idx is int:
		entry_name = get_entry_name_by_index("chara.mpk", int(entry_or_idx))
	else:
		entry_name = str(entry_or_idx)
	if entry_name == "":
		return {"ok": false}

	var base := entry_name.get_basename()
	var atlas_stem := base.substr(0, base.length() - 1) if base.ends_with("_") else base
	var lay_name := atlas_stem + "_.lay"
	if not has_entry("chara.mpk", lay_name):
		lay_name = base + ".lay"

	var atlas_name := atlas_stem + ".png"
	if not has_entry("chara.mpk", atlas_name):
		atlas_name = atlas_stem + ".dds"

	# 若不存在 .lay，直接作为静态 PNG/DDS 立绘返回
	if not has_entry("chara.mpk", lay_name):
		var static_img := decode_image("chara.mpk", atlas_name if has_entry("chara.mpk", atlas_name) else entry_name, false)
		if static_img == null:
			return {"ok": false}
		return {"ok": true, "image": static_img, "origin": Vector2i.ZERO}

	var lay_bytes := read_entry("chara.mpk", lay_name)
	var atlas_img := decode_image("chara.mpk", atlas_name, false)
	if lay_bytes.is_empty() or atlas_img == null:
		return {"ok": false}

	var res: Dictionary = native.compose_lay_rgba(
		lay_bytes, atlas_img.get_data(), atlas_img.get_width(), atlas_img.get_height(), group_ids
	)
	if not bool(res.get("ok", false)):
		return {"ok": false}
	var out_img := Image.create_from_data(int(res["width"]), int(res["height"]), false, Image.FORMAT_RGBA8, res["data"])
	return {
		"ok": true,
		"image": out_img,
		"origin": Vector2i(int(res["origin_x"]), int(res["origin_y"])),
	}


func has_entry(archive: String, entry: String) -> bool:
	if not is_mounted or native == null:
		return false
	return bool(native.has_entry(archive, entry))


func read_entry(archive: String, entry: String) -> PackedByteArray:
	if not is_mounted or native == null:
		return PackedByteArray()
	return native.read_entry(archive, entry)


func list_entries(archive: String = "", prefix: String = "") -> PackedStringArray:
	if not is_mounted or native == null:
		return PackedStringArray()
	return native.list_entries(archive, prefix)


func decode_image(archive: String, entry: String, l8_alpha_only: bool = false) -> Image:
	if not is_mounted or native == null:
		return null
	var info: Dictionary = native.decode_archive_image(archive, entry, l8_alpha_only)
	if not bool(info.get("ok", false)):
		return null
	var fmt: String = str(info.get("format", ""))
	var data: PackedByteArray = info["data"]
	var img := Image.new()
	if fmt == "png":
		if img.load_png_from_buffer(data) != OK:
			return null
		if l8_alpha_only:
			img.convert(Image.FORMAT_L8)
		elif img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		return img
	elif fmt == "l8":
		return Image.create_from_data(int(info["width"]), int(info["height"]), false, Image.FORMAT_L8, data)
	elif fmt == "rgba8":
		return Image.create_from_data(int(info["width"]), int(info["height"]), false, Image.FORMAT_RGBA8, data)
	return null


func decode_texture(archive: String, entry: String, l8_alpha_only: bool = false) -> ImageTexture:
	var img := decode_image(archive, entry, l8_alpha_only)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


func find_script_entry_name(name_or_stem: String) -> String:
	var clean := name_or_stem.strip_edges()
	if clean == "":
		return ""
	if not clean.to_lower().ends_with(".scx"):
		clean += ".scx"
	if has_entry("script.mpk", clean):
		return clean
	return ""


func find_movie_path(stem: String) -> String:
	if active_movie_dir == "":
		return ""
	var clean := stem.get_file().get_basename()
	var candidates := PackedStringArray([
		active_movie_dir.path_join(clean + ".ogv"),
		active_movie_dir.path_join(clean.to_upper() + ".ogv"),
		active_movie_dir.path_join(clean.to_lower() + ".ogv"),
	])
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	# 目录忽略大小写遍历兜底
	var da := DirAccess.open(active_movie_dir)
	if da != null:
		var target := (clean + ".ogv").to_lower()
		da.list_dir_begin()
		var f := da.get_next()
		while f != "":
			if f.to_lower() == target:
				da.list_dir_end()
				return active_movie_dir.path_join(f)
			f = da.get_next()
		da.list_dir_end()
	return ""
