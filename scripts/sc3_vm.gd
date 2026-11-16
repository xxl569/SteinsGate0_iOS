class_name Sc3Vm
extends RefCounted
## STEINS;GATE 0 MAGES. SC3 多线程协程虚拟机
## 覆盖 TBL_00 / TBL_01 / TBL_10 / 0xFE 全部已逆向操作码与精确参数对齐

signal dialogue_shown(script_bytes: PackedByteArray, str_offset: int, char_id: int, voice_id: int, str_id: int, is_read: bool)
signal dialogue_clear()
signal mes_window_changed(visible: bool)
signal bg_changed(layer: int, bg_idx: int)
signal bg_cleared(layer: int)
signal pic_loaded(surf_id: int, archive_type: int, file_id: int)
signal disp_changed(surf_id: int, visible: bool)
signal chara_loaded(slot: int, chara_idx: int, group_hint: int)
signal chara_released(slot: int)
signal bgm_play_requested(bgm_idx: int, loop: bool, fade_frames: int)
signal bgm_stop_requested(fade_frames: int)
signal se_play_requested(se_idx: int, loop: bool)
signal se_stop_requested(channel: int)
signal voice_play_requested(voice_idx: int, char_id: int)
signal movie_play_requested(movie_idx: int)
signal movie_stop_requested()
signal mask_wipe_requested(mask_id: int, duration_frames: int)
signal choices_requested(choices: Array)
signal phone_event(subop: int, args: Array)
signal rine_event(subop: int, args: Array)
signal tips_unlocked(tip_id: int)
signal script_switched(script_name: String)

enum WaitMode {
	NONE = 0,
	FRAMES = 1,
	YIELD_FRAME = 2,
	MES_SYNC = 3,
	SELECT = 4,
	MOVIE = 5,
	HALT = 6,
}

const MAX_INSNS_PER_FRAME := 8000
const THREAD_VAR_COUNT := 256

class ThreadCtx:
	extends RefCounted
	var id: int = 0
	var group_id: int = 0
	var script_slot: int = 0
	var pc: int = 0
	var alive: bool = true
	var wait_mode: int = WaitMode.NONE
	var wait_frames: int = 0
	var wait_param: int = 0
	var call_stack: Array[Dictionary] = [] # {slot, pc}
	var vars: PackedInt32Array = PackedInt32Array()
	var fields: Dictionary = {} # 0x0018 SetThreadField
	var loop_counts: Dictionary = {} # pc -> remaining

	func _init() -> void:
		vars.resize(THREAD_VAR_COUNT)
		vars.fill(0)

	func get_var(idx: int) -> int:
		if idx >= 0 and idx < vars.size():
			return int(vars[idx])
		return 0

	func set_var(idx: int, val: int) -> void:
		if idx >= 0:
			if idx >= vars.size() and idx < 4096:
				var old_size := vars.size()
				vars.resize(idx + 1)
				for k in range(old_size, vars.size()):
					vars[k] = 0
			if idx < vars.size():
				vars[idx] = val


var _vfs: MgsVfs = null
var _scripts: Dictionary = {} # slot_id(int) -> { name, index, data, labels, str_offsets, ret_addrs }
var _threads: Array[ThreadCtx] = []
var _next_thread_id: int = 1
var _active_slot: int = 0

var scr_work: Dictionary = {} # int -> int
var flags: Dictionary = {} # int -> bool
var read_lines: Dictionary = {} # "script:str_id" -> true
var unlocked_tips: Dictionary = {} # tip_id -> true
var backlog: Array[Dictionary] = []

var _pending_choices: Array[Dictionary] = []
var _mes_reveal_done: bool = true
var _mes_click_pending: bool = false
var _movie_playing: bool = false
var _auto_click_all_waits: bool = false # 仅测试模式可选


func _init(vfs: MgsVfs = null) -> void:
	_vfs = vfs


func bind_vfs(vfs: MgsVfs) -> void:
	_vfs = vfs


func reset_vm() -> void:
	_scripts.clear()
	_threads.clear()
	_next_thread_id = 1
	_active_slot = 0
	scr_work.clear()
	flags.clear()
	backlog.clear()
	_pending_choices.clear()
	_mes_reveal_done = true
	_mes_click_pending = false
	_movie_playing = false
	# SC3 Windows/PC 基础平台环境预设标志（避免启动检测卡住）
	set_scr_work(2194, 0)
	set_scr_work(2195, 0)
	set_scr_work(2196, 0)


func load_script_into_slot(slot_id: int, name_or_idx: Variant) -> bool:
	if _vfs == null or not _vfs.is_mounted:
		return false
	var entry_name := ""
	var entry_idx := -1
	if name_or_idx is int:
		entry_idx = int(name_or_idx)
		entry_name = _vfs.get_entry_name_by_index("script.mpk", entry_idx)
	else:
		entry_name = _vfs.find_script_entry_name(str(name_or_idx))
	if entry_name == "":
		return false

	var data := _vfs.read_entry("script.mpk", entry_name)
	if data.size() < 16 or data.slice(0, 4).get_string_from_ascii() != "SC3":
		return false

	var hdr := _parse_scx_header(data)
	_scripts[slot_id] = {
		"name": entry_name,
		"index": entry_idx,
		"data": data,
		"labels": hdr["labels"],
		"str_offsets": hdr["str_offsets"],
		"ret_addrs": hdr["ret_addrs"],
		"code_start": hdr["code_start"],
		"code_end": hdr["code_end"],
	}
	return true


func _parse_scx_header(data: PackedByteArray) -> Dictionary:
	var str_off := int(data.decode_u32(4))
	var ret_off := int(data.decode_u32(8))
	var lbl0 := int(data.decode_u32(12))
	@warning_ignore("integer_division")
	var n_labels: int = maxi(0, (lbl0 - 12) / 4)
	var labels := PackedInt32Array()
	labels.resize(n_labels)
	for i in range(n_labels):
		labels[i] = int(data.decode_u32(12 + i * 4))

	@warning_ignore("integer_division")
	var n_str: int = maxi(0, (ret_off - str_off) / 4)
	var str_offsets := PackedInt32Array()
	str_offsets.resize(n_str)
	for i in range(n_str):
		str_offsets[i] = int(data.decode_u32(str_off + i * 4))

	var first_str := int(str_offsets[0]) if n_str > 0 else data.size()
	@warning_ignore("integer_division")
	var n_ret: int = maxi(0, (first_str - ret_off) / 4) if first_str > ret_off else 0
	var ret_addrs := PackedInt32Array()
	ret_addrs.resize(n_ret)
	for i in range(n_ret):
		ret_addrs[i] = int(data.decode_u32(ret_off + i * 4))

	return {
		"labels": labels,
		"str_offsets": str_offsets,
		"ret_addrs": ret_addrs,
		"code_start": lbl0,
		"code_end": str_off,
	}


func start_boot_script() -> bool:
	return jump_to_script("_Startup_win.scx", 0)


func jump_to_script(name_or_idx: Variant, label_id: int = 0) -> bool:
	reset_vm()
	# 若直接从剧情脚本起跳，先将通用宏脚本 macrosys/macrosys2/_system/_phone/_rndrine/_tips 预加载至标准槽位
	var target_name := ""
	if name_or_idx is int:
		target_name = _vfs.get_entry_name_by_index("script.mpk", int(name_or_idx)) if _vfs != null else ""
	else:
		target_name = _vfs.find_script_entry_name(str(name_or_idx)) if _vfs != null else ""

	if target_name.to_lower() != "_startup_win.scx":
		load_script_into_slot(1, "_system.scx")
		load_script_into_slot(4, "anime.scx")
		load_script_into_slot(6, "macrosys.scx")
		load_script_into_slot(7, "macrosys2.scx")
		load_script_into_slot(9, "_phone.scx")
		load_script_into_slot(10, "_tips.scx")
		load_script_into_slot(11, "_rndrine.scx")

	if not load_script_into_slot(0, name_or_idx):
		return false

	_active_slot = 0
	var th := _spawn_thread(0, 0, label_id)
	script_switched.emit(_scripts[0]["name"])
	return th != null


func _spawn_thread(group_id: int, slot_id: int, label_id: int) -> ThreadCtx:
	if not _scripts.has(slot_id):
		return null
	var sc: Dictionary = _scripts[slot_id]
	var labels: PackedInt32Array = sc["labels"]
	if label_id < 0 or label_id >= labels.size():
		return null
	var th := ThreadCtx.new()
	th.id = _next_thread_id
	_next_thread_id += 1
	th.group_id = group_id
	th.script_slot = slot_id
	th.pc = int(labels[label_id])
	_threads.append(th)
	return th


# ==================== Sc3Expr 上下文接口 ====================

func get_scr_work(idx: int) -> int:
	return int(scr_work.get(idx, 0))


func set_scr_work(idx: int, val: int) -> void:
	if val == 0:
		scr_work.erase(idx)
	else:
		scr_work[idx] = val


func get_flag(idx: int) -> int:
	return 1 if bool(flags.get(idx, false)) else 0


func set_flag(idx: int, val: int) -> void:
	if val == 0:
		flags.erase(idx)
	else:
		flags[idx] = true


func get_thread_var(thread: Object, idx: int) -> int:
	return (thread as ThreadCtx).get_var(idx)


func set_thread_var(thread: Object, idx: int, val: int) -> void:
	(thread as ThreadCtx).set_var(idx, val)


func resolve_label_addr(thread: Object, lid: int) -> int:
	var th := thread as ThreadCtx
	if th == null or not _scripts.has(th.script_slot):
		return lid
	var labels: PackedInt32Array = _scripts[th.script_slot]["labels"]
	if lid >= 0 and lid < labels.size():
		return int(labels[lid])
	return lid


func read_expr_table(thread: Object, _op: int, addr_or_sid: int, elem_idx: int) -> int:
	var th := thread as ThreadCtx
	var data: PackedByteArray = PackedByteArray()
	var byte_off := 0
	if (addr_or_sid & 0x80000000) != 0:
		var sid := addr_or_sid & 0x7FFFFFFF
		if _scripts.has(sid):
			data = _scripts[sid]["data"]
		byte_off = elem_idx * 4
	else:
		if th != null and _scripts.has(th.script_slot):
			data = _scripts[th.script_slot]["data"]
		byte_off = addr_or_sid + elem_idx * 4

	if data.is_empty() or byte_off < 0 or byte_off + 4 > data.size():
		return 0
	return Sc3Expr._to_i32(int(data.decode_u32(byte_off)))


func get_sys_var(op: int) -> int:
	match op:
		0x2F: return 1 # 平台/运行模式正常
		0x30: return 0
		0x31: return 1
		0x32: return 0
	return 0


# ==================== 外部事件驱动接口 ====================

func notify_mes_reveal_done() -> void:
	_mes_reveal_done = true


func notify_user_advance() -> void:
	_mes_click_pending = true
	for th in _threads:
		if th.alive and th.wait_mode == WaitMode.MES_SYNC:
			th.wait_mode = WaitMode.NONE


func notify_movie_finished() -> void:
	_movie_playing = false
	set_flag(0x73B, 0)
	set_flag(0x73C, 0)
	for th in _threads:
		if th.alive and th.wait_mode == WaitMode.MOVIE:
			th.wait_mode = WaitMode.NONE


func submit_choice(choice_index: int) -> void:
	set_scr_work(4, choice_index)
	_pending_choices.clear()
	for th in _threads:
		if th.alive and th.wait_mode == WaitMode.SELECT:
			th.wait_mode = WaitMode.NONE


func is_waiting_for_click() -> bool:
	for th in _threads:
		if th.alive and th.wait_mode == WaitMode.MES_SYNC:
			return true
	return false


func is_waiting_for_choice() -> bool:
	for th in _threads:
		if th.alive and th.wait_mode == WaitMode.SELECT:
			return true
	return false


func is_waiting_for_movie() -> bool:
	for th in _threads:
		if th.alive and th.wait_mode == WaitMode.MOVIE:
			return true
	return false


func get_current_script_name() -> String:
	if _scripts.has(_active_slot):
		return str(_scripts[_active_slot]["name"])
	return ""


# ==================== 帧步进主循环 ====================

func step_frame(frames: int = 1) -> void:
	# 1. 新一帧解除 YIELD_FRAME 并将 FRAMES 倒计时递减
	for th in _threads:
		if not th.alive:
			continue
		if th.wait_mode == WaitMode.YIELD_FRAME:
			th.wait_mode = WaitMode.NONE
		elif th.wait_mode == WaitMode.FRAMES:
			th.wait_frames -= maxi(1, frames)
			if th.wait_frames <= 0:
				th.wait_frames = 0
				th.wait_mode = WaitMode.NONE

	# 2. 按顺序调度所有可运行线程
	var guard := 0
	var idx := 0
	while idx < _threads.size() and guard < MAX_INSNS_PER_FRAME:
		var th := _threads[idx]
		idx += 1
		if not th.alive or th.wait_mode != WaitMode.NONE:
			continue
		var ran := 0
		while th.alive and th.wait_mode == WaitMode.NONE and ran < 500 and guard < MAX_INSNS_PER_FRAME:
			_exec_one(th)
			ran += 1
			guard += 1

	# 3. 清理已退出线程
	for i in range(_threads.size() - 1, -1, -1):
		if not _threads[i].alive:
			_threads.remove_at(i)


func _exec_one(th: ThreadCtx) -> void:
	if not _scripts.has(th.script_slot):
		th.alive = false
		return
	var sc: Dictionary = _scripts[th.script_slot]
	var data: PackedByteArray = sc["data"]
	var code_end: int = sc["code_end"]
	if th.pc < int(sc["code_start"]) or th.pc >= code_end:
		th.alive = false
		return

	var p := th.pc
	var b0 := int(data[p])
	if b0 == 0xFE:
		var ev := Sc3Expr.eval(data, p + 1, self, th)
		th.pc = int(ev["end_pos"])
		return

	if p + 1 >= data.size():
		th.alive = false
		return
	var tbl := b0 & 0x7F
	var b1 := int(data[p + 1])
	p += 2

	if tbl == 0x00:
		_exec_tbl00(th, data, p, b1)
	elif tbl == 0x01:
		_exec_tbl01(th, data, p, b1)
	elif tbl == 0x10:
		_exec_tbl10(th, data, p, b1)
	else:
		push_warning("未知 SC3 表 %02x:%02x @ %x" % [tbl, b1, th.pc])
		th.alive = false


func _rd_u8(data: PackedByteArray, p: int) -> int:
	return int(data[p]) if p < data.size() else 0


func _rd_u16(data: PackedByteArray, p: int) -> int:
	return int(data.decode_u16(p)) if p + 1 < data.size() else 0


func _jump_label(th: ThreadCtx, label_id: int) -> void:
	if not _scripts.has(th.script_slot):
		th.alive = false
		return
	var labels: PackedInt32Array = _scripts[th.script_slot]["labels"]
	if label_id >= 0 and label_id < labels.size():
		th.pc = int(labels[label_id])
	else:
		th.alive = false


func _exec_tbl00(th: ThreadCtx, data: PackedByteArray, p: int, b1: int) -> void:
	var labels: PackedInt32Array = _scripts[th.script_slot]["labels"]
	var ret_addrs: PackedInt32Array = _scripts[th.script_slot]["ret_addrs"]
	match b1:
		0x00: # End
			th.alive = false
		0x01: # CreateThread(group, script_buf_or_expr, label)
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			var e2 := Sc3Expr.eval(data, p, self, th); p = int(e2["end_pos"])
			var lid := _rd_u16(data, p); p += 2
			th.pc = p
			var target_slot := int(e2["value"])
			if not _scripts.has(target_slot):
				target_slot = th.script_slot
			_spawn_thread(int(e1["value"]), target_slot, lid)
		0x02: # KillThread
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			th.pc = p
			var target_gid := int(e1["value"])
			for t in _threads:
				if t != th and t.group_id == target_gid:
					t.alive = false
		0x03: # Reset
			th.pc = p
		0x04: # ScriptLoad(slot_id, script_mpk_idx)
			var e_slot := Sc3Expr.eval(data, p, self, th); p = int(e_slot["end_pos"])
			var e_idx := Sc3Expr.eval(data, p, self, th); p = int(e_idx["end_pos"])
			th.pc = p
			var sid := int(e_slot["value"])
			if load_script_into_slot(sid, int(e_idx["value"])):
				if sid == 3 and _scripts.has(3):
					var sname := str(_scripts[3]["name"])
					if sname.to_upper().begins_with("SG0_"):
						_active_slot = 3
						script_switched.emit(sname)
		0x05: # Wait(frames)
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			th.pc = p
			var wf := maxi(1, int(e1["value"]))
			th.wait_mode = WaitMode.FRAMES
			th.wait_frames = wf
		0x06: # Halt
			th.wait_mode = WaitMode.HALT
			th.pc = p
		0x07: # Jump(label)
			var lid := _rd_u16(data, p)
			_jump_label(th, lid)
		0x08: # JumpTable(expr, table_label_id) -> 查 u16 表得目标 label_id
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			var tbl_lid := _rd_u16(data, p); p += 2
			var idx := maxi(0, int(e1["value"]))
			if tbl_lid >= 0 and tbl_lid < labels.size():
				var tbl_off := int(labels[tbl_lid]) + idx * 2
				if tbl_off + 2 <= data.size():
					var target_lid := _rd_u16(data, tbl_off)
					_jump_label(th, target_lid)
				else:
					th.pc = p
			else:
				th.pc = p
		0x0A: # If(cond_u8, expr, label)
			var cond := _rd_u8(data, p); p += 1
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			var lid := _rd_u16(data, p); p += 2
			var val := int(e1["value"])
			var take := (val != 0) if (cond != 0) else (val == 0)
			if take:
				_jump_label(th, lid)
			else:
				th.pc = p
		0x0B: # Call(label, ret_id)
			var lid := _rd_u16(data, p); p += 2
			var rid := _rd_u16(data, p); p += 2
			var ret_pc := int(ret_addrs[rid]) if rid < ret_addrs.size() else p
			th.call_stack.append({"slot": th.script_slot, "pc": ret_pc})
			_jump_label(th, lid)
		0x0C: # JumpFarCond(slot_expr, label)
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			var lid := _rd_u16(data, p); p += 2
			var target_slot := int(e1["value"])
			if _scripts.has(target_slot):
				th.script_slot = target_slot
				_active_slot = target_slot
				_jump_label(th, lid)
			else:
				th.pc = p
		0x0D: # CallFar(slot_expr, label, ret_id)
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			var lid := _rd_u16(data, p); p += 2
			var rid := _rd_u16(data, p); p += 2
			var target_slot := int(e1["value"])
			var ret_pc := int(ret_addrs[rid]) if rid < ret_addrs.size() else p
			if _scripts.has(target_slot):
				th.call_stack.append({"slot": th.script_slot, "pc": ret_pc})
				th.script_slot = target_slot
				_jump_label(th, lid)
			else:
				th.pc = p
		0x0E: # Return
			if not th.call_stack.is_empty():
				var frame: Dictionary = th.call_stack.pop_back()
				th.script_slot = int(frame["slot"])
				th.pc = int(frame["pc"])
			else:
				th.alive = false
		0x0F: # Loop(label, count_expr)
			var lid := _rd_u16(data, p); p += 2
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			if not th.loop_counts.has(th.pc):
				th.loop_counts[th.pc] = int(e1["value"])
			var rem := int(th.loop_counts[th.pc]) - 1
			if rem > 0:
				th.loop_counts[th.pc] = rem
				_jump_label(th, lid)
			else:
				th.loop_counts.erase(th.pc)
				th.pc = p
		0x10: # JumpIfFlag(cond_u8, flag_expr, label)
			var cond := _rd_u8(data, p); p += 1
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			var lid := _rd_u16(data, p); p += 2
			if get_flag(int(e1["value"])) == (1 if cond != 0 else 0):
				_jump_label(th, lid)
			else:
				th.pc = p
		0x11: # SetFlagVal(val_u8, flag_expr)
			var val := _rd_u8(data, p); p += 1
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			set_flag(int(e1["value"]), val)
			th.pc = p
		0x12: # SetFlag(flag_expr) -> 设为 1
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			set_flag(int(e1["value"]), 1)
			th.pc = p
		0x13: # ResetFlag(flag_expr) -> 设为 0
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			set_flag(int(e1["value"]), 0)
			th.pc = p
		0x14: # CopyFlagBit (Game.exe 0x45e540: GetFlag -> SetFlag，非 BGM)
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			var e2 := Sc3Expr.eval(data, p, self, th); p = int(e2["end_pos"])
			th.pc = p
			set_flag(int(e2["value"]), get_flag(int(e1["value"])))
		0x15: # JumpIfPad (Game.exe 0x45e580: 按键触发条件跳转，非 PlayBGMEx)
			var _sub := _rd_u8(data, p); p += 1
			p = Sc3Expr.skip(data, p)
			p = Sc3Expr.skip(data, p)
			p += 2
			th.pc = p
		0x16: # PadTest (Game.exe 0x45ace0: 按键读取，非 StopBGM)
			var _sub := _rd_u8(data, p); p += 1
			p = Sc3Expr.skip(data, p)
			p = Sc3Expr.skip(data, p)
			th.pc = p
		0x17: # PadWait (Game.exe 0x45adb0: 带计数的按键等待)
			var _sub := _rd_u8(data, p); p += 1
			for _k in range(3):
				p = Sc3Expr.skip(data, p)
			th.pc = p
		0x18: # SetThreadField (Game.exe 0x45aec0: th->field[idx] = val，非 PlaySE)
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			var e2 := Sc3Expr.eval(data, p, self, th); p = int(e2["end_pos"])
			th.pc = p
			th.fields[int(e1["value"])] = int(e2["value"])
		0x19: # SetAchievement / FlagMask (Game.exe 0x45af00 -> 0x466d20，非 StopSE)
			var _e1 := Sc3Expr.eval(data, p, self, th); p = int(_e1["end_pos"])
			var _e2 := Sc3Expr.eval(data, p, self, th); p = int(_e2["end_pos"])
			th.pc = p
		0x1B: # SwitchScript(script_mpk_idx_expr, label)
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			var lid := _rd_u16(data, p)
			var target_idx := int(e1["value"])
			if load_script_into_slot(0, target_idx):
				th.script_slot = 0
				th.call_stack.clear()
				_active_slot = 0
				_jump_label(th, lid)
				script_switched.emit(_scripts[0]["name"])
			else:
				th.alive = false
		0x1F, 0x26, 0x2C, 0x31, 0x42, 0x46: # 1-expr 指令
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			th.pc = p
			if b1 == 0x26:
				th.wait_mode = WaitMode.FRAMES
				th.wait_frames = maxi(1, int(e1["value"]))
		0x20: # WaitThreadGroup
			var _e1 := Sc3Expr.eval(data, p, self, th); p = int(_e1["end_pos"])
			var _u16 := _rd_u16(data, p); p += 2
			th.pc = p
		0x21: # BGMPlay (Game.exe 0x45b2a0: subop_u8, bgm_expr[, loop_expr])
			var sub := _rd_u8(data, p); p += 1
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			var loop := (sub == 0 or sub == 1 or sub == 3)
			if sub == 2:
				var e2 := Sc3Expr.eval(data, p, self, th); p = int(e2["end_pos"])
				loop = (int(e2["value"]) != 0)
			th.pc = p
			var bgm_id := int(e1["value"])
			if bgm_id < 0 or bgm_id >= 0x2710:
				bgm_stop_requested.emit(15)
			else:
				bgm_play_requested.emit(bgm_id, loop, 0)
		0x22: # BGMStop (Game.exe 0x45b5b0)
			var _sub := _rd_u8(data, p); p += 1
			th.pc = p
			bgm_stop_requested.emit(15)
		0x23: # SEPlay (Game.exe 0x45b6c0: ch_u8, mode_u8[, se_expr, loop_expr])
			var ch := _rd_u8(data, p); p += 1
			var mode := _rd_u8(data, p); p += 1
			if mode == 2:
				th.pc = p
				se_stop_requested.emit(ch)
			else:
				var e_se := Sc3Expr.eval(data, p, self, th); p = int(e_se["end_pos"])
				var e_lp := Sc3Expr.eval(data, p, self, th); p = int(e_lp["end_pos"])
				th.pc = p
				var se_id := int(e_se["value"])
				if se_id < 0 or se_id >= 0x2710:
					se_stop_requested.emit(ch)
				else:
					se_play_requested.emit(se_id, int(e_lp["value"]) != 0)
		0x24: # AudioReset (Game.exe 0x45b900)
			var sub := _rd_u8(data, p); p += 1
			th.pc = p
			if sub == 0xFF:
				bgm_stop_requested.emit(0)
				se_stop_requested.emit(-1)
			elif sub <= 2:
				se_stop_requested.emit(sub)
			elif sub >= 10 and sub <= 12:
				se_stop_requested.emit(sub - 10)
		0x25, 0x4E: # 3-expr
			for _k in range(3):
				var ek := Sc3Expr.eval(data, p, self, th); p = int(ek["end_pos"])
			th.pc = p
		0x28: # 4-expr
			for _k in range(4):
				var ek := Sc3Expr.eval(data, p, self, th); p = int(ek["end_pos"])
			th.pc = p
		0x2A: # ReturnIfWait
			var _sub := _rd_u8(data, p); p += 1
			th.pc = p
		0x2E, 0x2F, 0x4D: # subop + 1 expr
			var _sub := _rd_u8(data, p); p += 1
			var _e1 := Sc3Expr.eval(data, p, self, th); p = int(_e1["end_pos"])
			th.pc = p
		0x38: # SEStop (Game.exe 0x45c6b0: ch_u8, fade_expr)
			var ch := _rd_u8(data, p); p += 1
			var _e1 := Sc3Expr.eval(data, p, self, th); p = int(_e1["end_pos"])
			th.pc = p
			se_stop_requested.emit(ch)
		0x33: # WaitFramesCounted (Game.exe 0x45c520: 开场动画与转场真实 60fps 帧等待)
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			var _e2 := Sc3Expr.eval(data, p, self, th); p = int(_e2["end_pos"])
			th.pc = p
			var cnt := int(e1["value"]) & 0x3FF
			if cnt > 0:
				th.wait_mode = WaitMode.FRAMES
				th.wait_frames = cnt
		0x3D: # 2-expr
			var _e1 := Sc3Expr.eval(data, p, self, th); p = int(_e1["end_pos"])
			var _e2 := Sc3Expr.eval(data, p, self, th); p = int(_e2["end_pos"])
			th.pc = p
		0x34, 0x48: # YieldReset / WaitForever
			th.pc = p
			th.wait_mode = WaitMode.YIELD_FRAME if b1 == 0x34 else WaitMode.HALT
		0x35:
			var sub := _rd_u8(data, p); p += 1
			if sub == 0:
				p += 3
			th.pc = p
		0x37: # SEPlayEx (Game.exe 0x45c610: ch_u8, se_expr, loop_expr)
			var ch := _rd_u8(data, p); p += 1
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			var e2 := Sc3Expr.eval(data, p, self, th); p = int(e2["end_pos"])
			th.pc = p
			var se_id := int(e1["value"])
			if se_id < 0 or se_id >= 0x2710:
				se_stop_requested.emit(ch)
			else:
				se_play_requested.emit(se_id, int(e2["value"]) != 0)
		0x3A: # BGMPlay2 (Game.exe 0x45c810)
			var sub := _rd_u8(data, p); p += 1
			if sub == 0:
				var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
				var _e2 := Sc3Expr.eval(data, p, self, th); p = int(_e2["end_pos"])
				th.pc = p
				var bgm_id := int(e1["value"])
				if bgm_id >= 0 and bgm_id < 0x2710:
					bgm_play_requested.emit(bgm_id, true, 0)
			elif sub == 1:
				th.pc = p
				bgm_stop_requested.emit(15)
			elif sub == 2 or sub == 3:
				var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
				th.pc = p
				var bgm_id := int(e1["value"])
				if bgm_id >= 0 and bgm_id < 0x2710:
					bgm_play_requested.emit(bgm_id, true, 0)
			else:
				th.pc = p
		0x43: # TitleOrSystem43
			var sub := _rd_u8(data, p); p += 1
			var s1 := _rd_u8(data, p); p += 1
			if s1 == 0 or s1 == 1:
				if sub == 2:
					p = Sc3Expr.skip(data, p)
				elif sub == 3 or sub == 4:
					p += 2
			th.pc = p
		0x4C, 0x51:
			var sub := _rd_u8(data, p); p += 1
			if sub == 0:
				p = Sc3Expr.skip(data, p)
			th.pc = p
		0x50:
			var sub := _rd_u8(data, p); p += 1
			if sub == 0 or sub == 3:
				var lid := _rd_u16(data, p)
				_jump_label(th, lid)
			else:
				th.pc = p
		0x53:
			var _sub := _rd_u8(data, p); p += 1
			p = Sc3Expr.skip(data, p)
			p += 2
			th.pc = p
		0x54:
			var _sub := _rd_u8(data, p); p += 1
			p = Sc3Expr.skip(data, p)
			p += 4
			th.pc = p
		0x55:
			var _sub := _rd_u8(data, p); p += 1
			p = Sc3Expr.skip(data, p); p = Sc3Expr.skip(data, p)
			p += 2
			th.pc = p
		0x56:
			var _sub := _rd_u8(data, p); p += 1
			p = Sc3Expr.skip(data, p); p = Sc3Expr.skip(data, p)
			p += 4
			th.pc = p
		0x57:
			var _sub := _rd_u8(data, p); p += 1
			p = Sc3Expr.skip(data, p)
			th.pc = p
		0x58:
			var sub := _rd_u8(data, p); p += 1
			var cnt := 4 if (sub == 2 or sub == 3) else 1
			for _k in range(cnt):
				p = Sc3Expr.skip(data, p)
			p += 2
			th.pc = p
		0x59: # JumpIf59 (输入跳过检测等)
			var _sub := _rd_u8(data, p); p += 1
			p = Sc3Expr.skip(data, p)
			p = Sc3Expr.skip(data, p)
			var _lid := _rd_u16(data, p); p += 2
			th.pc = p
		0x1E, 0x29, 0x2D, 0x30, 0x36, 0x39, 0x3B, 0x3C, 0x41, 0x44, 0x49, 0x4A:
			p += 1
			th.pc = p
		_:
			th.pc = p


func _exec_tbl01(th: ThreadCtx, data: PackedByteArray, p: int, b1: int) -> void:
	match b1:
		0x00, 0x07:
			if b1 == 0x00:
				p += 1
			for _k in range(3):
				p = Sc3Expr.skip(data, p)
			th.pc = p
		0x01, 0x03, 0x20:
			var _e1 := Sc3Expr.eval(data, p, self, th); p = int(_e1["end_pos"])
			th.pc = p
		0x24, 0x29: # MovieWait (Game.exe 0x4592c0: 0x24/0x29 共用)
			var _e1 := Sc3Expr.eval(data, p, self, th); p = int(_e1["end_pos"])
			th.pc = p
			if _movie_playing:
				th.wait_mode = WaitMode.MOVIE
		0x02: # LoadPic(surf_id, archive_type, file_id)
			var e_surf := Sc3Expr.eval(data, p, self, th); p = int(e_surf["end_pos"])
			var e_arc := Sc3Expr.eval(data, p, self, th); p = int(e_arc["end_pos"])
			var e_fid := Sc3Expr.eval(data, p, self, th); p = int(e_fid["end_pos"])
			th.pc = p
			pic_loaded.emit(int(e_surf["value"]), int(e_arc["value"]), int(e_fid["value"]))
		0x04:
			for _k in range(5):
				p = Sc3Expr.skip(data, p)
			th.pc = p
		0x05: # DispCtrl
			var sub := _rd_u8(data, p); p += 1
			var argc: int = int({0: 2, 1: 2, 2: 3, 3: 4, 4: 4, 5: 4, 6: 4}.get(sub, 0))
			var args: Array[int] = []
			for _k in range(argc):
				var ek := Sc3Expr.eval(data, p, self, th); p = int(ek["end_pos"])
				args.append(int(ek["value"]))
			th.pc = p
			if args.size() >= 2:
				disp_changed.emit(args[0], args[1] != 0)
		0x06:
			var sub := _rd_u8(data, p); p += 1
			p = Sc3Expr.skip(data, p); p = Sc3Expr.skip(data, p)
			if sub == 0:
				p = Sc3Expr.skip(data, p)
			th.pc = p
		0x08: # BGSwapOrFade
			var sub := _rd_u8(data, p); p += 1
			if sub == 10:
				var ef := Sc3Expr.eval(data, p, self, th); p = int(ef["end_pos"])
				mask_wipe_requested.emit(0, int(ef["value"]))
			th.pc = p
		0x09: # MesWindow
			var sub := _rd_u8(data, p); p += 1
			if sub == 0:
				p += 2
				mes_window_changed.emit(true)
			elif sub == 1:
				p += 2
				var _e1 := Sc3Expr.eval(data, p, self, th); p = int(_e1["end_pos"])
				mes_window_changed.emit(false)
			elif sub == 2:
				p = Sc3Expr.skip(data, p)
			th.pc = p
		0x0A:
			var sub := _rd_u8(data, p); p += 1
			if sub == 4 or sub == 5:
				p = Sc3Expr.skip(data, p)
			th.pc = p
		0x0B: # MesClear
			th.pc = p
			dialogue_clear.emit()
		0x0C: # Mes(subop, ...)
			var sub := _rd_u8(data, p); p += 1
			var voice_id := -1
			var char_id := 0
			if sub & 1:
				var ev := Sc3Expr.eval(data, p, self, th); p = int(ev["end_pos"])
				var e_work := Sc3Expr.eval(data, p, self, th); p = int(e_work["end_pos"])
				voice_id = int(ev["value"])
				char_id = int(e_work["value"])
			var _e_tail := Sc3Expr.eval(data, p, self, th); p = int(_e_tail["end_pos"])
			var str_id := _rd_u16(data, p); p += 2
			th.pc = p
			_dispatch_dialogue(th, str_id, char_id, voice_id)
		0x0D: # MesMain(subop) -> 触发阻塞等待点击/揭示结束
			var sub := _rd_u8(data, p); p += 1
			th.pc = p
			if sub == 0 and not _auto_click_all_waits:
				if not _mes_click_pending:
					th.wait_mode = WaitMode.MES_SYNC
				_mes_click_pending = false
		0x0E: # SetMesMacro
			p = Sc3Expr.skip(data, p)
			p += 2
			th.pc = p
		0x0F: # MesFontLoad
			p += 4
			th.pc = p
		0x11: # MesSync
			var sub := _rd_u8(data, p); p += 1
			if sub == 5 or sub == 6 or sub == 7:
				p = Sc3Expr.skip(data, p)
			th.pc = p
		0x12: # Select
			var sub := _rd_u8(data, p); p += 1
			var str_id := _rd_u16(data, p); p += 2
			var cond_val := 1
			if sub == 0 or sub == 2:
				var ec := Sc3Expr.eval(data, p, self, th); p = int(ec["end_pos"])
				cond_val = int(ec["value"])
			th.pc = p
			if cond_val != 0:
				_append_choice_from_scx(th.script_slot, str_id)
		0x13: # SelectWait
			var sub := _rd_u8(data, p); p += 1
			if sub == 2:
				p = Sc3Expr.skip(data, p)
			th.pc = p
			if not _pending_choices.is_empty() and not _auto_click_all_waits:
				choices_requested.emit(_pending_choices.duplicate())
				th.wait_mode = WaitMode.SELECT
		0x14: # MesVoiceWait
			var sub := _rd_u8(data, p); p += 1
			if sub != 0 and sub != 1:
				p += 2
			th.pc = p
		0x15: # ChaCtrl
			var sub := _rd_u8(data, p); p += 1
			if sub == 0:
				p = Sc3Expr.skip(data, p); p = Sc3Expr.skip(data, p)
			elif sub == 2 or sub == 3:
				p = Sc3Expr.skip(data, p)
			th.pc = p
		0x21: # LoadMask
			var em := Sc3Expr.eval(data, p, self, th); p = int(em["end_pos"])
			p += 2
			th.pc = p
			mask_wipe_requested.emit(int(em["value"]), 20)
		0x22, 0x27: # MoviePlay / MovieEx
			var sub := _rd_u8(data, p); p += 1
			var mov_id := -1
			if sub == 99:
				var em := Sc3Expr.eval(data, p, self, th); p = int(em["end_pos"])
				mov_id = int(em["value"])
				p = Sc3Expr.skip(data, p)
			else:
				var _u := _rd_u8(data, p); p += 1
			var em1 := Sc3Expr.eval(data, p, self, th); p = int(em1["end_pos"])
			var _em2 := Sc3Expr.eval(data, p, self, th); p = int(_em2["end_pos"])
			th.pc = p
			if b1 == 0x22:
				if mov_id < 0:
					mov_id = int(em1["value"])
				_movie_playing = true
				set_flag(0x73B, 1)
				set_flag(0x73C, 1)
				movie_play_requested.emit(mov_id)
		0x25:
			var sub := _rd_u8(data, p); p += 1
			if sub == 0 or sub == 2:
				p += 2
			elif sub == 1:
				p = Sc3Expr.skip(data, p); p = Sc3Expr.skip(data, p); p += 2
			elif sub == 3:
				p += 2; p = Sc3Expr.skip(data, p); p = Sc3Expr.skip(data, p); p = Sc3Expr.skip(data, p)
			th.pc = p
		0x26:
			var sub := _rd_u8(data, p); p += 1
			if sub == 99:
				p = Sc3Expr.skip(data, p); p = Sc3Expr.skip(data, p)
			else:
				p += 1
			p = Sc3Expr.skip(data, p)
			th.pc = p
		0x2A:
			var sub := _rd_u8(data, p); p += 1
			if sub == 99:
				p = Sc3Expr.skip(data, p); p = Sc3Expr.skip(data, p)
			else:
				p += 1
			p = Sc3Expr.skip(data, p)
			th.pc = p
		0x10, 0x2B:
			p += 1
			th.pc = p
		0x23, 0x28: # MovieCtrl (Game.exe 0x458fc0: 按 sub 分支区分阻塞等待/状态查询/强制结束)
			var sub := _rd_u8(data, p); p += 1
			th.pc = p
			match sub:
				0, 0x14:
					if _movie_playing:
						th.wait_mode = WaitMode.MOVIE
				2, 0x16:
					if _movie_playing:
						notify_movie_finished()
						movie_stop_requested.emit()
					else:
						set_flag(0x73B, 0)
						set_flag(0x73C, 0)
				3, 0x17:
					if not _movie_playing:
						set_flag(0x73B, 0)
						set_flag(0x73C, 0)
				_:
					pass
		_:
			th.pc = p


func _exec_tbl10(th: ThreadCtx, data: PackedByteArray, p: int, b1: int) -> void:
	match b1:
		0x00, 0x10, 0x11, 0x17, 0x28, 0x29, 0x2E:
			p = Sc3Expr.skip(data, p)
			th.pc = p
		0x01: # SG0_BgChaCtrl(layer_expr, bg_idx_expr)
			var el := Sc3Expr.eval(data, p, self, th); p = int(el["end_pos"])
			var eb := Sc3Expr.eval(data, p, self, th); p = int(eb["end_pos"])
			th.pc = p
			var layer := int(el["value"])
			var bg_val := int(eb["value"])
			if bg_val < 0 or bg_val >= 0x00FF0000:
				bg_cleared.emit(layer)
			else:
				bg_changed.emit(layer, bg_val)
		0x02, 0x03, 0x06, 0x07, 0x08, 0x09, 0x0E, 0x16:
			p = Sc3Expr.skip(data, p)
			p = Sc3Expr.skip(data, p)
			th.pc = p
		0x04: # SG0_SpriteAnim
			var sub := _rd_u8(data, p); p += 1
			p = Sc3Expr.skip(data, p); p = Sc3Expr.skip(data, p)
			if sub >= 4:
				p = Sc3Expr.skip(data, p)
			p = Sc3Expr.skip(data, p)
			th.pc = p
		0x05: # SG0_ChaLoad(subop, slot_expr, encoded_idx_expr)
			var _sub := _rd_u8(data, p); p += 1
			var e_slot := Sc3Expr.eval(data, p, self, th); p = int(e_slot["end_pos"])
			var e_val := Sc3Expr.eval(data, p, self, th); p = int(e_val["end_pos"])
			th.pc = p
			var raw_v := int(e_val["value"])
			var chara_idx := raw_v & 0xFFFF
			var grp_hint := (raw_v >> 16) & 0xFFFF
			chara_loaded.emit(int(e_slot["value"]), chara_idx, grp_hint)
		0x24:
			var sub := _rd_u8(data, p); p += 1
			if sub == 0:
				var e_slot := Sc3Expr.eval(data, p, self, th); p = int(e_slot["end_pos"])
				var _e2 := Sc3Expr.eval(data, p, self, th); p = int(_e2["end_pos"])
				chara_released.emit(int(e_slot["value"]))
			th.pc = p
		0x0D:
			var sub := _rd_u8(data, p); p += 1
			if sub == 1:
				p = Sc3Expr.skip(data, p); p += 2
			elif sub == 2:
				p = Sc3Expr.skip(data, p)
			elif sub == 4:
				p = Sc3Expr.skip(data, p); p = Sc3Expr.skip(data, p)
			elif sub == 5:
				for _k in range(7):
					p = Sc3Expr.skip(data, p)
			th.pc = p
		0x22: # SG0_PhoneCtrl
			var sub := _rd_u8(data, p); p += 1
			var args: Array = []
			if sub == 10:
				args.append(_rd_u16(data, p)); p += 2
			th.pc = p
			phone_event.emit(sub, args)
		0x23: # SG0_TipsCtrl
			var sub := _rd_u8(data, p); p += 1
			var tip_id := -1
			if sub == 0 or sub == 10:
				tip_id = _rd_u8(data, p); p += 1
			th.pc = p
			if tip_id >= 0:
				unlocked_tips[tip_id] = true
				tips_unlocked.emit(tip_id)
		0x27:
			var sub := _rd_u8(data, p); p += 1
			p = Sc3Expr.skip(data, p)
			if sub == 1:
				p = Sc3Expr.skip(data, p)
			th.pc = p
		0x2A:
			p += 1
			for _k in range(3):
				p = Sc3Expr.skip(data, p)
			th.pc = p
		0x30:
			var sub := _rd_u8(data, p); p += 1
			var cnt: int = int({1: 5, 3: 5, 4: 6, 5: 6, 11: 5, 12: 6}.get(sub, 0))
			for _k in range(cnt):
				p = Sc3Expr.skip(data, p)
			th.pc = p
		0x32, 0x33, 0x38:
			var sub := _rd_u8(data, p); p += 1
			if sub == 0:
				p += 2
			th.pc = p
		0x37: # SG0_RineCtrl
			var sub := _rd_u8(data, p); p += 1
			var args: Array = []
			if sub == 0:
				for _k in range(7):
					args.append(_rd_u16(data, p)); p += 2
			elif sub == 0x0A or sub == 0x32:
				args.append(_rd_u16(data, p)); p += 2
			elif sub == 12:
				var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"]); args.append(e1["value"])
				var e2 := Sc3Expr.eval(data, p, self, th); p = int(e2["end_pos"]); args.append(e2["value"])
			elif sub == 13:
				var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"]); args.append(e1["value"])
				args.append(_rd_u16(data, p)); p += 2
			elif sub == 15 or sub == 46:
				for _k in range(3):
					var ek := Sc3Expr.eval(data, p, self, th); p = int(ek["end_pos"]); args.append(ek["value"])
			elif sub in [42, 43, 44, 45, 48]:
				var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"]); args.append(e1["value"])
			elif sub == 49:
				var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"]); args.append(e1["value"])
				var e2 := Sc3Expr.eval(data, p, self, th); p = int(e2["end_pos"]); args.append(e2["value"])
			th.pc = p
			rine_event.emit(sub, args)
		0x0C, 0x13, 0x14, 0x15, 0x1A, 0x1B, 0x1C, 0x1D, 0x1F, 0x20, 0x21, 0x34, 0x36:
			p += 1
			th.pc = p
		_:
			th.pc = p


func _dispatch_dialogue(th: ThreadCtx, str_id: int, char_id: int, voice_id: int) -> void:
	if not _scripts.has(th.script_slot):
		return
	var sc: Dictionary = _scripts[th.script_slot]
	var offsets: PackedInt32Array = sc["str_offsets"]
	if str_id < 0 or str_id >= offsets.size():
		return
	var soff := int(offsets[str_id])
	var key := "%s:%d" % [sc["name"], str_id]
	var already_read := read_lines.has(key)
	read_lines[key] = true

	_mes_reveal_done = false
	var sc_data: PackedByteArray = sc["data"]
	backlog.append({
		"script": sc["name"],
		"str_id": str_id,
		"str_offset": soff,
		"char_id": char_id,
		"voice_id": voice_id,
	})
	if backlog.size() > 200:
		backlog.remove_at(0)

	if voice_id > 0:
		voice_play_requested.emit(voice_id, char_id)
	dialogue_shown.emit(sc_data, soff, char_id, voice_id, str_id, already_read)


func _append_choice_from_scx(slot_id: int, str_id: int) -> void:
	if not _scripts.has(slot_id):
		return
	var sc: Dictionary = _scripts[slot_id]
	var offsets: PackedInt32Array = sc["str_offsets"]
	if str_id < 0 or str_id >= offsets.size():
		return
	_pending_choices.append({
		"index": _pending_choices.size(),
		"script": sc["name"],
		"str_id": str_id,
		"str_offset": int(offsets[str_id]),
	})


# ==================== 完整存档 / 读档序列化 ====================

func export_state() -> Dictionary:
	var loaded_slots := {}
	for sid in _scripts.keys():
		loaded_slots[str(sid)] = _scripts[sid]["name"]

	var saved_threads: Array = []
	for th in _threads:
		if not th.alive:
			continue
		saved_threads.append({
			"id": th.id,
			"group_id": th.group_id,
			"slot": th.script_slot,
			"pc": th.pc,
			"wait_mode": th.wait_mode,
			"wait_frames": th.wait_frames,
			"vars": Array(th.vars),
			"fields": th.fields.duplicate(true),
			"call_stack": th.call_stack.duplicate(true),
		})

	var sw := {}
	for k in scr_work.keys():
		sw[str(k)] = scr_work[k]
	var fl := []
	for k in flags.keys():
		fl.append(int(k))

	return {
		"version": 1,
		"active_slot": _active_slot,
		"script_name": get_current_script_name(),
		"loaded_slots": loaded_slots,
		"threads": saved_threads,
		"scr_work": sw,
		"flags": fl,
		"unlocked_tips": unlocked_tips.keys(),
	}


func import_state(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	reset_vm()

	var loaded_slots: Dictionary = state.get("loaded_slots", {})
	for k in loaded_slots.keys():
		load_script_into_slot(int(k), str(loaded_slots[k]))
	_active_slot = int(state.get("active_slot", 0))

	var sw: Dictionary = state.get("scr_work", {})
	for k in sw.keys():
		set_scr_work(int(k), int(sw[k]))
	for fk in state.get("flags", []):
		set_flag(int(fk), 1)
	for tk in state.get("unlocked_tips", []):
		unlocked_tips[int(tk)] = true

	var max_tid := 1
	for st in state.get("threads", []):
		var th := ThreadCtx.new()
		th.id = int(st.get("id", max_tid))
		max_tid = maxi(max_tid, th.id + 1)
		th.group_id = int(st.get("group_id", 0))
		th.script_slot = int(st.get("slot", 0))
		th.pc = int(st.get("pc", 0))
		th.wait_mode = int(st.get("wait_mode", WaitMode.NONE))
		th.wait_frames = int(st.get("wait_frames", 0))
		var v_arr: Array = st.get("vars", [])
		for i in range(mini(THREAD_VAR_COUNT, v_arr.size())):
			th.vars[i] = int(v_arr[i])
		var f_dict: Variant = st.get("fields", {})
		if f_dict is Dictionary:
			for fk in (f_dict as Dictionary).keys():
				th.fields[int(fk)] = int((f_dict as Dictionary)[fk])
		for cf in st.get("call_stack", []):
			th.call_stack.append(cf)
		_threads.append(th)
	_next_thread_id = max_tid
	script_switched.emit(get_current_script_name())
	return true
