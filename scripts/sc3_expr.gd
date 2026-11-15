class_name Sc3Expr
extends RefCounted
## SC3 后缀/优先级树表达式求值器（严格对齐 Game.exe 0x41a740 & 0x41acc0）

const INT32_DIV_ZERO := 0x7FFFFFFF


static func _rd_u32(buf: PackedByteArray, pos: int) -> int:
	return int(buf[pos]) | (int(buf[pos + 1]) << 8) | (int(buf[pos + 2]) << 16) | (int(buf[pos + 3]) << 24)


static func _to_i32(v: int) -> int:
	var u := v & 0xFFFFFFFF
	if u & 0x80000000:
		return u - 0x100000000
	return u


## 跳过表达式字节流并返回下一个字节位置
static func skip(buf: PackedByteArray, pos: int) -> int:
	var n := buf.size()
	while pos < n:
		var b0 := int(buf[pos])
		if b0 == 0x00:
			return pos + 1
		if (b0 & 0x80) != 0:
			var cls := b0 & 0x60
			if cls == 0x00:
				pos += 2
			elif cls == 0x20:
				pos += 3
			elif cls == 0x40:
				pos += 4
			else:
				pos += 6
		else:
			pos += 2
	return n


## 求值表达式，返回 Dictionary { "value": int, "end_pos": int }
static func eval(buf: PackedByteArray, pos: int, ctx: Object, thread: Object = null) -> Dictionary:
	var n := buf.size()
	if pos >= n or buf[pos] == 0x00:
		return {"value": 0, "end_pos": mini(pos + 1, n)}

	# Pass 1: 词法切分为 [ { kind, val, prec }, ... ]
	# kind == 0xFF 表示值；其余 0x01..0x3F 表示操作符 ID
	var tokens: Array[Dictionary] = []
	var cur := pos
	while cur < n:
		var b0 := int(buf[cur])
		if b0 == 0x00:
			cur += 1
			break
		if (b0 & 0x80) != 0:
			var cls := b0 & 0x60
			var val := 0
			if cls == 0x00:
				val = b0 & 0x1F
				if (b0 & 0x10) != 0:
					val -= 32
				cur += 2
			elif cls == 0x20:
				val = ((b0 & 0x1F) << 8) | int(buf[cur + 1])
				if (b0 & 0x10) != 0:
					val -= 0x2000
				cur += 3
			elif cls == 0x40:
				val = ((b0 & 0x1F) << 16) | (int(buf[cur + 2]) << 8) | int(buf[cur + 1])
				if (b0 & 0x10) != 0:
					val -= 0x200000
				cur += 4
			else:
				val = _to_i32(int(buf[cur + 1]) | (int(buf[cur + 2]) << 8) | (int(buf[cur + 3]) << 16) | (int(buf[cur + 4]) << 24))
				cur += 6
			tokens.append({"kind": 0xFF, "val": val, "prec": 0})
		else:
			var op := b0 & 0x7F
			var prec := int(buf[cur + 1]) if cur + 1 < n else 0
			if op >= 0x2F and op <= 0x32:
				var sv := 0
				if ctx != null and ctx.has_method("get_sys_var"):
					sv = int(ctx.get_sys_var(op))
				tokens.append({"kind": 0xFF, "val": sv, "prec": 0})
			else:
				tokens.append({"kind": op, "val": 0, "prec": prec})
			cur += 2

	if tokens.is_empty():
		return {"value": 0, "end_pos": cur}

	# 查找最左侧赋值运算符 (0x14 .. 0x21)
	var assign_idx := -1
	for i in range(tokens.size()):
		var k: int = tokens[i]["kind"]
		if k >= 0x14 and k <= 0x21:
			assign_idx = i
			break

	if assign_idx >= 0:
		var assign_op: int = tokens[assign_idx]["kind"]
		# 先从高优先级到低优先级折叠右侧 RHS [assign_idx + 1 .. end)
		_collapse_range(tokens, assign_idx + 1, ctx, thread)
		# 再折叠左侧前缀链（但保留 tokens[0] 作为赋值目标类型，不把 tokens[0] 直接取值消掉）
		if assign_idx > 2:
			var removed := _collapse_lhs_subrange(tokens, 1, assign_idx, ctx, thread)
			assign_idx -= removed

		var lhs_kind: int = tokens[0]["kind"] if tokens.size() >= 1 else 0xFF
		var lhs_arg: int = tokens[1]["val"] if tokens.size() >= 2 else 0
		var lhs_arg2: int = tokens[2]["val"] if assign_idx >= 3 and tokens.size() >= 3 else 0
		var rhs_val: int = tokens[assign_idx + 1]["val"] if assign_idx + 1 < tokens.size() else 0

		var cur_lhs := _read_lvalue(lhs_kind, lhs_arg, lhs_arg2, ctx, thread)
		var new_val := cur_lhs
		match assign_op:
			0x14: new_val = rhs_val
			0x15: new_val = _to_i32(cur_lhs * rhs_val)
			0x16: new_val = INT32_DIV_ZERO if rhs_val == 0 else _to_i32(int(cur_lhs / rhs_val))
			0x17: new_val = _to_i32(cur_lhs + rhs_val)
			0x18: new_val = _to_i32(cur_lhs - rhs_val)
			0x19: new_val = INT32_DIV_ZERO if rhs_val == 0 else _to_i32(cur_lhs % rhs_val)
			0x1A: new_val = _to_i32(cur_lhs << (rhs_val & 31))
			0x1B: new_val = _to_i32(cur_lhs >> (rhs_val & 31))
			0x1C: new_val = _to_i32(cur_lhs & rhs_val)
			0x1D: new_val = _to_i32(cur_lhs | rhs_val)
			0x1E: new_val = _to_i32(cur_lhs ^ rhs_val)
			0x20: new_val = _to_i32(cur_lhs + 1)
			0x21: new_val = _to_i32(cur_lhs - 1)
			_: new_val = rhs_val

		_write_lvalue(lhs_kind, lhs_arg, lhs_arg2, new_val, ctx, thread)
		return {"value": new_val, "end_pos": cur}

	# 无赋值表达式：全局按最高优先级折叠到单一结果
	_collapse_range(tokens, 0, ctx, thread)
	var final_val: int = tokens[0]["val"] if not tokens.is_empty() else 0
	return {"value": final_val, "end_pos": cur}


static func _collapse_range(tokens: Array[Dictionary], start_idx: int, ctx: Object, thread: Object) -> void:
	while tokens.size() - start_idx > 1:
		var max_prec := 0
		for i in range(start_idx, tokens.size()):
			var t := tokens[i]
			if t["kind"] != 0xFF and int(t["prec"]) > max_prec:
				max_prec = int(t["prec"])
		if max_prec <= 0:
			# 容错：若存在 prec==0 的未折叠操作符，取第一个操作符执行
			var found := false
			for i in range(start_idx, tokens.size()):
				if tokens[i]["kind"] != 0xFF:
					_apply_op(tokens, i, ctx, thread)
					found = true
					break
			if not found:
				break
			continue

		var did_work := false
		var i := start_idx
		while i < tokens.size():
			var t := tokens[i]
			if t["kind"] != 0xFF and int(t["prec"]) == max_prec:
				_apply_op(tokens, i, ctx, thread)
				did_work = true
			else:
				i += 1
		if not did_work:
			break


static func _collapse_lhs_subrange(tokens: Array[Dictionary], start_idx: int, end_limit: int, ctx: Object, thread: Object) -> int:
	# 仅折叠 [start_idx .. end_limit - 1]，用于 ScrWork[expr] 下标求值
	var sub: Array[Dictionary] = []
	for i in range(start_idx, end_limit):
		sub.append(tokens[i])
	_collapse_range(sub, 0, ctx, thread)
	var removed := (end_limit - start_idx) - sub.size()
	if removed > 0:
		for k in range(sub.size()):
			tokens[start_idx + k] = sub[k]
		for _r in range(removed):
			tokens.remove_at(start_idx + sub.size())
	return maxi(0, removed)


static func _apply_op(tokens: Array[Dictionary], idx: int, ctx: Object, thread: Object) -> void:
	var op: int = tokens[idx]["kind"]
	# 一元右参数操作符: 0x0B(~), 0x28(ScrWork), 0x29(GetFlag), 0x2B(LabelAddr), 0x2D(ThreadVar), 0x33(Random)
	if op == 0x0B or op == 0x28 or op == 0x29 or op == 0x2B or op == 0x2D or op == 0x33:
		var arg := int(tokens[idx + 1]["val"]) if idx + 1 < tokens.size() else 0
		var res := 0
		match op:
			0x0B: res = _to_i32(~arg)
			0x28: res = int(ctx.get_scr_work(arg)) if ctx != null else 0
			0x29: res = int(ctx.get_flag(arg)) if ctx != null else 0
			0x2B:
				if ctx != null and thread != null:
					res = int(ctx.resolve_label_addr(thread, arg))
				else:
					res = arg
			0x2D:
				if thread != null and ctx != null:
					res = int(ctx.get_thread_var(thread, arg))
				elif thread != null:
					res = int(thread.get_var(arg))
			0x33:
				res = 0 if arg <= 0 else randi() % arg
		tokens[idx] = {"kind": 0xFF, "val": res, "prec": 0}
		if idx + 1 < tokens.size():
			tokens.remove_at(idx + 1)
		return

	# 三元组表索引操作符: 0x2A(DataU32), 0x2C(ScriptTbl), 0x2E(ScriptVal) -> (op, addr_or_sid, elem_idx)
	if op == 0x2A or op == 0x2C or op == 0x2E:
		var addr_or_sid := int(tokens[idx + 1]["val"]) if idx + 1 < tokens.size() else 0
		var elem_idx := int(tokens[idx + 2]["val"]) if idx + 2 < tokens.size() else 0
		var res := 0
		if ctx != null:
			res = int(ctx.read_expr_table(thread, op, addr_or_sid, elem_idx))
		tokens[idx] = {"kind": 0xFF, "val": res, "prec": 0}
		if idx + 2 < tokens.size():
			tokens.remove_at(idx + 2)
		if idx + 1 < tokens.size():
			tokens.remove_at(idx + 1)
		return

	# 后缀自增/自减（如果出现在非赋值区）
	if op == 0x20 or op == 0x21:
		var arg := int(tokens[idx - 1]["val"]) if idx >= 1 else 0
		tokens[idx - 1 if idx >= 1 else 0] = {"kind": 0xFF, "val": arg + (1 if op == 0x20 else -1), "prec": 0}
		if idx >= 1:
			tokens.remove_at(idx)
		return

	# 二元运算符 (lhs = tokens[idx - 1], rhs = tokens[idx + 1])
	var lhs := int(tokens[idx - 1]["val"]) if idx >= 1 else 0
	var rhs := int(tokens[idx + 1]["val"]) if idx + 1 < tokens.size() else 0
	var out := 0
	match op:
		0x01: out = _to_i32(lhs * rhs)
		0x02: out = INT32_DIV_ZERO if rhs == 0 else _to_i32(int(lhs / rhs))
		0x03: out = _to_i32(lhs + rhs)
		0x04: out = _to_i32(lhs - rhs)
		0x05: out = INT32_DIV_ZERO if rhs == 0 else _to_i32(lhs % rhs)
		0x06: out = _to_i32(lhs << (rhs & 31))
		0x07: out = _to_i32(lhs >> (rhs & 31))
		0x08: out = _to_i32(lhs & rhs)
		0x09: out = _to_i32(lhs ^ rhs)
		0x0A: out = _to_i32(lhs | rhs)
		0x0C: out = 1 if lhs == rhs else 0
		0x0D: out = 1 if lhs != rhs else 0
		0x0E: out = 1 if lhs <= rhs else 0
		0x0F: out = 1 if lhs >= rhs else 0
		0x10: out = 1 if lhs < rhs else 0
		0x11: out = 1 if lhs > rhs else 0
		_: out = rhs

	if idx >= 1 and idx + 1 < tokens.size():
		tokens[idx - 1] = {"kind": 0xFF, "val": out, "prec": 0}
		tokens.remove_at(idx + 1)
		tokens.remove_at(idx)
	elif idx + 1 < tokens.size():
		tokens[idx] = {"kind": 0xFF, "val": out, "prec": 0}
		tokens.remove_at(idx + 1)
	else:
		tokens[idx] = {"kind": 0xFF, "val": out, "prec": 0}


static func _read_lvalue(kind: int, arg1: int, _arg2: int, ctx: Object, thread: Object) -> int:
	if ctx == null:
		return 0
	match kind:
		0x28: return int(ctx.get_scr_work(arg1))
		0x29: return int(ctx.get_flag(arg1))
		0x2D:
			if thread != null:
				return int(ctx.get_thread_var(thread, arg1))
	return 0


static func _write_lvalue(kind: int, arg1: int, _arg2: int, val: int, ctx: Object, thread: Object) -> void:
	if ctx == null:
		return
	var v := _to_i32(val)
	match kind:
		0x28: ctx.set_scr_work(arg1, v)
		0x29: ctx.set_flag(arg1, v)
		0x2D:
			if thread != null:
				ctx.set_thread_var(thread, arg1, v)
