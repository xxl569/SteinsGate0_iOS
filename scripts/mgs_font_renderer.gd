class_name MgsFontRenderer
extends Control
## MAGES. SC3 双字库图集渲染器（支持 L8 透明字形、Ruby 振假名、色号、居中、打字机推进）

signal line_completed()

const CELL_SIZE := 48
const COLS := 64
const FONT_A_SLOTS := 5440
const FONT_B_SLOTS := 2560
const FONT_SHADER_PATH := "res://assets/shaders/font_l8.gdshader"

# 字库图集纹理：[0] = FONT_A/B, [1] = FONT2_A/B
static var _shared_atlases: Array = [ [null, null], [null, null] ]
static var _shared_material: ShaderMaterial = null

# 调色板预设（0: 默认正文白, 1: 青绿/Amadeus, 2: 琥珀橙/TIPS, 3: 警示红, 31: 柔和灰银）
const COLOR_PALETTE := {
	0: Color(0.97, 0.98, 1.0, 1.0),
	1: Color(0.45, 0.92, 0.88, 1.0),
	2: Color(1.0, 0.82, 0.38, 1.0),
	3: Color(1.0, 0.36, 0.36, 1.0),
	31: Color(0.75, 0.80, 0.88, 1.0),
}

@export var font_set: int = 0
@export var base_font_size: float = 34.0
@export var base_scale: float = 0.0
@export var line_height: float = 48.0
@export var shadow_offset: Vector2 = Vector2(2.0, 2.0)
@export var shadow_color: Color = Color(0.0, 0.0, 0.0, 0.85)
@export var default_color: Color = Color(0.97, 0.98, 1.0, 1.0)
@export var max_line_width: float = 1280.0
@export var center_mode: bool = false

var _vfs: MgsVfs = null
var _glyphs: Array[Dictionary] = [] # { kind, gid, pos, size, color, font_set }
var _name_glyphs: Array[Dictionary] = [] # 分离出的说话人名区（0x01..0x02）
var _total_revealable: int = 0
var _revealed_count: int = 0
var _reveal_acc: float = 0.0
var _chars_per_sec: float = 48.0
var _has_wait_click: bool = false
var _has_auto_wait: bool = false
var _content_size: Vector2 = Vector2.ZERO


static func ensure_shared_resources(vfs: MgsVfs) -> bool:
	if _shared_material == null and ResourceLoader.exists(FONT_SHADER_PATH):
		var sh: Shader = load(FONT_SHADER_PATH)
		if sh != null:
			_shared_material = ShaderMaterial.new()
			_shared_material.shader = sh
	if _shared_atlases[0][0] != null:
		return true
	if vfs == null or not vfs.is_mounted:
		return false

	_shared_atlases[0][0] = vfs.decode_texture("system.mpk", "FONT_A.DDS", true)
	_shared_atlases[0][1] = vfs.decode_texture("system.mpk", "FONT_B.DDS", true)
	_shared_atlases[1][0] = vfs.decode_texture("system.mpk", "FONT2_A.DDS", true)
	_shared_atlases[1][1] = vfs.decode_texture("system.mpk", "FONT2_B.DDS", true)
	return _shared_atlases[0][0] != null and _shared_atlases[0][1] != null


func _ready() -> void:
	if _shared_material == null and ResourceLoader.exists(FONT_SHADER_PATH):
		var sh: Shader = load(FONT_SHADER_PATH)
		if sh != null:
			_shared_material = ShaderMaterial.new()
			_shared_material.shader = sh
	if _shared_material != null:
		material = _shared_material


func bind_vfs(vfs: MgsVfs) -> void:
	_vfs = vfs
	ensure_shared_resources(vfs)
	if _shared_material != null:
		material = _shared_material


func clear_text() -> void:
	_glyphs.clear()
	_name_glyphs.clear()
	_total_revealable = 0
	_revealed_count = 0
	_reveal_acc = 0.0
	_has_wait_click = false
	_has_auto_wait = false
	_content_size = Vector2.ZERO
	queue_redraw()


func set_text_speed(cps: float) -> void:
	_chars_per_sec = cps


func is_fully_revealed() -> bool:
	return _revealed_count >= _total_revealable


func reveal_all() -> void:
	if _revealed_count < _total_revealable:
		_revealed_count = _total_revealable
		queue_redraw()
		line_completed.emit()


func get_name_glyphs() -> Array[Dictionary]:
	return _name_glyphs


func get_glyphs_count() -> int:
	return _total_revealable


func has_wait_click() -> bool:
	return _has_wait_click


func has_auto_wait() -> bool:
	return _has_auto_wait


func get_content_size() -> Vector2:
	return _content_size


func step_reveal(delta: float) -> void:
	if _revealed_count >= _total_revealable:
		return
	if _chars_per_sec <= 0.0 or _chars_per_sec >= 110.0:
		reveal_all()
		return
	_reveal_acc += delta * _chars_per_sec
	var inc := int(floor(_reveal_acc))
	if inc > 0:
		_reveal_acc -= float(inc)
		_revealed_count = mini(_total_revealable, _revealed_count + inc)
		queue_redraw()
		if _revealed_count >= _total_revealable:
			line_completed.emit()


## 直接从字形 ID 数组设置简洁标签文本（用于测试或简单标签）
func set_glyph_ids(gids: PackedInt32Array, instant: bool = true) -> void:
	var buf := PackedByteArray()
	for gid in gids:
		buf.append(0x80 | ((gid >> 8) & 0x7F))
		buf.append(gid & 0xFF)
	buf.append(0xFF)
	set_sc3_string(buf, 0, null, null, instant)


## 从半角 ASCII 数字/字母快速编码生成 SC3 字形数组（严格对齐 FONT_A.DDS 第 0~1 行实测槽位）
static func encode_ascii_glyphs(text: String) -> PackedInt32Array:
	const PUNCT_MAP := {
		47: 64, 58: 65, 45: 66, 59: 67, 33: 68, 63: 69, 39: 70, 46: 71,
		64: 72, 35: 73, 37: 74, 126: 75, 42: 76, 38: 77, 96: 78, 40: 79,
		41: 80, 94: 82, 62: 83, 43: 84, 60: 85, 61: 88, 34: 89, 36: 90,
		44: 92, 91: 93, 92: 94, 93: 95, 95: 96, 123: 97, 124: 98, 125: 99,
	}
	var out := PackedInt32Array()
	for i in range(text.length()):
		var c := text.unicode_at(i)
		if c == 32:
			out.append(0)
		elif c >= 48 and c <= 57:
			out.append(1 + (c - 48))
		elif c >= 65 and c <= 90:
			out.append(11 + (c - 65))
		elif c >= 97 and c <= 122:
			out.append(37 + (c - 97))
		elif PUNCT_MAP.has(c):
			out.append(int(PUNCT_MAP[c]))
		else:
			out.append(0)
	return out


## 直接用字形 ID 数组铺设固定文本（用于角色名牌、历史回顾条目等）
func set_glyph_list(gids: PackedInt32Array, scale_factor: float = 0.72, col: Color = Color.WHITE) -> void:
	ensure_shared_resources(_vfs)
	if _shared_material != null:
		material = _shared_material
	clear_text()
	var cx := 0.0
	for gid in gids:
		var met := _get_metrics(int(gid))
		var adv := float(met.z) * scale_factor
		var cell_draw := float(CELL_SIZE) * scale_factor
		_glyphs.append({
			"gid": int(gid),
			"pos": Vector2(cx, 0.0),
			"size": Vector2(cell_draw, cell_draw),
			"color": col,
			"font_set": font_set,
			"reveal_idx": _total_revealable,
		})
		_total_revealable += 1
		cx += adv
	_revealed_count = _total_revealable
	_content_size = Vector2(cx, float(CELL_SIZE) * scale_factor)
	queue_redraw()


## 解析一段 SC3 内联字符串流并在控件内排布（含自动换行、Ruby 注音、变量展开与颜色标签）
func set_sc3_string(
	buf: PackedByteArray,
	offset: int,
	expr_ctx: Object = null,
	thread: Object = null,
	instant: bool = false,
	append_mode: bool = false
) -> Dictionary:
	ensure_shared_resources(_vfs)
	if _shared_material != null:
		material = _shared_material

	if not append_mode:
		_glyphs.clear()
		_name_glyphs.clear()
		_total_revealable = 0
		_revealed_count = 0
		_reveal_acc = 0.0
		_has_wait_click = false
		_has_auto_wait = false

	var cur_x := 0.0
	var cur_y := _content_size.y if append_mode and _content_size.y > 0.0 else 0.0
	var cur_color := default_color
	var cur_scale := base_scale if base_scale > 0.0 else (base_font_size / float(CELL_SIZE))
	var extra_spacing := 0.0
	var line_center := center_mode

	var in_name := false
	var in_ruby_base := false
	var in_ruby_text := false
	var ruby_base_x0 := 0.0
	var ruby_base_x1 := 0.0
	var ruby_base_y := 0.0
	var ruby_text_tokens: Array[int] = []
	var line_start_idx := _glyphs.size()

	var p := offset
	var n := buf.size()
	while p < n:
		var b := int(buf[p])
		if b == 0xFF:
			p += 1
			break
		if (b & 0x80) != 0:
			if p + 1 >= n:
				break
			var gid := ((b & 0x7F) << 8) | int(buf[p + 1])
			p += 2
			if in_name:
				_name_glyphs.append({"gid": gid, "color": cur_color, "font_set": font_set})
				continue
			if in_ruby_text:
				ruby_text_tokens.append(gid)
				continue

			var met := _get_metrics(gid)
			var adv := float(met.z) * cur_scale + extra_spacing
			var cell_draw := float(CELL_SIZE) * cur_scale
			if max_line_width > 0.0 and cur_x > 0.0 and cur_x + adv > max_line_width:
				if line_center:
					_apply_line_center(line_start_idx, cur_x)
				cur_x = 0.0
				cur_y += line_height
				line_start_idx = _glyphs.size()

			_glyphs.append({
				"gid": gid,
				"pos": Vector2(cur_x, cur_y),
				"size": Vector2(cell_draw, cell_draw),
				"color": cur_color,
				"font_set": font_set,
				"reveal_idx": _total_revealable,
			})
			_total_revealable += 1
			cur_x += adv
			if in_ruby_base:
				ruby_base_x1 = cur_x
			continue

		# 控制标签 < 0x80
		p += 1
		match b:
			0x00: # LineBreak
				if line_center:
					_apply_line_center(line_start_idx, cur_x)
				cur_x = 0.0
				cur_y += line_height
				line_center = center_mode
				line_start_idx = _glyphs.size()
			0x01: # NameStart
				in_name = true
			0x02: # NameEnd
				in_name = false
			0x03: # WaitClick
				_has_wait_click = true
			0x04: # SetColor(expr)
				var ev := Sc3Expr.eval(buf, p, expr_ctx, thread)
				p = int(ev["end_pos"])
				cur_color = _resolve_color(int(ev["value"]))
			0x07, 0x1B: # 1-byte 参数标签
				if p < n:
					p += 1
			0x08: # AutoWait
				_has_auto_wait = true
			0x09: # RubyBaseStart
				in_ruby_base = true
				ruby_base_x0 = cur_x
				ruby_base_x1 = cur_x
				ruby_base_y = cur_y
			0x0A: # RubyTextStart
				in_ruby_base = false
				in_ruby_text = true
				ruby_text_tokens.clear()
			0x0B: # RubyTextEnd
				in_ruby_text = false
				_emit_ruby_glyphs(ruby_text_tokens, ruby_base_x0, ruby_base_x1, ruby_base_y, cur_color, _total_revealable - 1)
				ruby_text_tokens.clear()
			0x0C: # SetFontSize(u16be)
				if p + 1 < n:
					var sz_val := (int(buf[p]) << 8) | int(buf[p + 1])
					p += 2
					if sz_val > 0:
						cur_scale = (base_font_size * clampf(float(sz_val) / 30.0, 0.5, 2.2)) / float(CELL_SIZE)
			0x0E: # Center
				line_center = true
			0x11: # SetPosX(u16be)
				if p + 1 < n:
					var px := (int(buf[p]) << 8) | int(buf[p + 1])
					p += 2
					cur_x = float(px)
			0x12: # SetPosXY(u16be)
				if p + 1 < n:
					p += 2
			0x13, 0x14: # PrintScrWork / PrintScrWorkAlt (u16be)
				if p + 1 < n:
					var wid := (int(buf[p]) << 8) | int(buf[p + 1])
					p += 2
					var num_val := int(expr_ctx.get_scr_work(wid)) if expr_ctx != null else 0
					for dg in encode_ascii_glyphs(str(num_val)):
						var dmet := _get_metrics(dg)
						var dadv := float(dmet.z) * cur_scale + extra_spacing
						var ddraw := float(CELL_SIZE) * cur_scale
						_glyphs.append({
							"gid": dg,
							"pos": Vector2(cur_x, cur_y),
							"size": Vector2(ddraw, ddraw),
							"color": cur_color,
							"font_set": font_set,
							"reveal_idx": _total_revealable,
						})
						_total_revealable += 1
						cur_x += dadv
			0x15: # EvalExpr(expr)
				var ev15 := Sc3Expr.eval(buf, p, expr_ctx, thread)
				p = int(ev15["end_pos"])
			0x16, 0x1A: # 2-byte big endian 标签
				if p + 1 < n:
					p += 2
			0x19: # SetSpacing(u16be)
				if p + 1 < n:
					var sp := (int(buf[p]) << 8) | int(buf[p + 1])
					p += 2
					extra_spacing = float(sp) * 0.25
			0x1E: # RubyDot (着重号)
				pass
			_:
				pass

	if line_center:
		_apply_line_center(line_start_idx, cur_x)

	_content_size = Vector2(maxf(_content_size.x, cur_x), cur_y + line_height)
	if instant or _chars_per_sec >= 110.0 or _chars_per_sec <= 0.0:
		_revealed_count = _total_revealable
	queue_redraw()
	return {
		"end_pos": p,
		"name_glyph_count": _name_glyphs.size(),
		"body_glyph_count": _total_revealable,
		"has_wait_click": _has_wait_click,
		"has_auto_wait": _has_auto_wait,
	}


func _emit_ruby_glyphs(
	ruby_gids: Array[int],
	bx0: float,
	bx1: float,
	by: float,
	col: Color,
	anchor_reveal: int
) -> void:
	if ruby_gids.is_empty():
		return
	var ruby_scale := (base_font_size * 0.44) / float(CELL_SIZE)
	var total_rw := 0.0
	var advs: Array[float] = []
	for gid in ruby_gids:
		var adv := float(_get_metrics(gid).z) * ruby_scale
		advs.append(adv)
		total_rw += adv
	var mid := (bx0 + bx1) * 0.5
	var rx := mid - total_rw * 0.5
	var ry := by - base_font_size * 0.48
	var rdraw := float(CELL_SIZE) * ruby_scale
	var rev := maxi(0, anchor_reveal)
	for i in range(ruby_gids.size()):
		_glyphs.append({
			"gid": ruby_gids[i],
			"pos": Vector2(rx, ry),
			"size": Vector2(rdraw, rdraw),
			"color": col,
			"font_set": font_set,
			"reveal_idx": rev,
		})
		rx += advs[i]


func _apply_line_center(from_idx: int, line_w: float) -> void:
	if max_line_width <= 0.0 or from_idx >= _glyphs.size():
		return
	var shift := maxf(0.0, (max_line_width - line_w) * 0.5)
	if shift <= 0.5:
		return
	for i in range(from_idx, _glyphs.size()):
		var g: Dictionary = _glyphs[i]
		g["pos"] = (g["pos"] as Vector2) + Vector2(shift, 0.0)


func _get_metrics(gid: int) -> Vector3i:
	if _vfs != null:
		return _vfs.get_glyph_metrics(font_set, gid)
	return Vector3i(0, 47, 24 if gid < 128 else 48)


func _resolve_color(v: int) -> Color:
	if COLOR_PALETTE.has(v):
		return COLOR_PALETTE[v]
	if v > 0xFF:
		var r := float((v >> 16) & 0xFF) / 255.0
		var g := float((v >> 8) & 0xFF) / 255.0
		var b := float(v & 0xFF) / 255.0
		return Color(r, g, b, 1.0)
	return default_color


func _draw() -> void:
	for item in _glyphs:
		if int(item["reveal_idx"]) >= _revealed_count:
			continue
		var gid: int = item["gid"]
		var fs: int = clampi(int(item["font_set"]), 0, 1)
		var tex: Texture2D = null
		var local_id := gid
		if gid < FONT_A_SLOTS:
			tex = _shared_atlases[fs][0]
		elif gid < FONT_A_SLOTS + FONT_B_SLOTS:
			tex = _shared_atlases[fs][1]
			local_id = gid - FONT_A_SLOTS
		if tex == null:
			continue

		@warning_ignore("integer_division")
		var row: int = local_id / COLS
		var col: int = local_id % COLS
		var src_rect := Rect2(col * CELL_SIZE, row * CELL_SIZE, CELL_SIZE, CELL_SIZE)
		var dst_pos: Vector2 = item["pos"]
		var dst_sz: Vector2 = item["size"]
		var fg_col: Color = item["color"]

		if shadow_offset != Vector2.ZERO and shadow_color.a > 0.0:
			var sh_col := Color(shadow_color.r, shadow_color.g, shadow_color.b, shadow_color.a * fg_col.a)
			draw_texture_rect_region(tex, Rect2(dst_pos + shadow_offset, dst_sz), src_rect, sh_col)
		draw_texture_rect_region(tex, Rect2(dst_pos, dst_sz), src_rect, fg_col)
