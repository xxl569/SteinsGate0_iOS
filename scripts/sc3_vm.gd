class_name Sc3Vm
extends RefCounted
## STEINS;GATE 0 MAGES. SC3 多线程协程虚拟机
## 覆盖 TBL_00 / TBL_01 / TBL_10 / 0xFE 全部已逆向操作码与精确参数对齐

signal dialogue_shown(script_bytes: PackedByteArray, str_offset: int, char_id: int, voice_id: int, str_id: int, is_read: bool)
signal dialogue_clear()
signal mes_window_changed(visible: bool)
signal bg_changed(layer: int, bg_idx: int)
signal bg_color_changed(layer: int, color: Color)
signal bg_cleared(layer: int)
signal bg_committed(dst_mask: int, src_mask: int)
signal pic_loaded(surf_id: int, archive_type: int, file_id: int)
signal disp_changed(surf_id: int, visible: bool)
signal chara_loaded(slot: int, chara_idx: int, group_hint: int)
signal chara_released(slot: int)
signal chara_swapped(dst_mask: int, src_mask: int)
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
	var switch_val: int = 0 # 0x001F / 0x0020 Switch-Case 缓存值

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
var _in_chara_swap: bool = false
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
var skip_active: bool = false # 快进开关（供 0x0046 与协程等待加速读取）

# RINE (_rndrine.scx) 子解释器状态（对齐 Game.exe 0x454160 / 0x4543c0 / 0x454690 / 0x453d30）
var _rine_active: bool = false
var _rine_pc: int = 0
var _rine_waiting_reply: bool = false
var _rine_contact_id: int = -1
var _rine_reply_mode: int = 0 # 0=文本选项, 1=贴纸选项 (sub=12 args[1])
var _rine_self_id: int = 0 # sub=42 设置的己方角色ID (默认0=伦太郎)
var _rine_members: Array[int] = [] # sub=43/44/45 维护的当前群聊成员
var _rine_reply_options: Array[Dictionary] = [] # [{ "str_id": int, "label_id": int }]
var _rine_history_count: int = 0
var _rine_trigger_label: int = -1
var _last_phone_ctrl_arg: int = -1 # 记录最近一次 PhoneCtrl(10, arg) 参数以区分 RINE 通知与真正来电
var _incoming_call_notified: bool = false # 防止同一来电窗口内重复触发来电弹窗与铃声

const READ_LINES_PATH := "user://read_lines.json"
const UNLOCKED_TIPS_PATH := "user://unlocked_tips.json"


func _init(vfs: MgsVfs = null) -> void:
	_vfs = vfs
	load_read_lines()
	load_unlocked_tips()


func load_unlocked_tips() -> void:
	if not FileAccess.file_exists(UNLOCKED_TIPS_PATH):
		return
	var txt := FileAccess.get_file_as_string(UNLOCKED_TIPS_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Array:
		for tk in parsed:
			unlocked_tips[int(tk)] = true


func save_unlocked_tips() -> void:
	var f := FileAccess.open(UNLOCKED_TIPS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(unlocked_tips.keys()))
		f.close()


func unlock_tip(tip_id: int) -> bool:
	if tip_id < 0:
		return false
	if unlocked_tips.has(tip_id):
		return false
	unlocked_tips[tip_id] = true
	save_unlocked_tips()
	tips_unlocked.emit(tip_id)
	return true


func load_read_lines() -> void:
	if not FileAccess.file_exists(READ_LINES_PATH):
		return
	var txt := FileAccess.get_file_as_string(READ_LINES_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		read_lines = (parsed as Dictionary).duplicate()


func save_read_lines() -> void:
	var f := FileAccess.open(READ_LINES_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(read_lines))
		f.close()


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
	_reset_rine_subinterp()
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
		if entry_name != "":
			entry_idx = _vfs.get_archive_entry_index("script.mpk", entry_name)
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
	# 同步当前主线脚本 MPK 索引至 ScrWork[4343]，驱动 macrosys2 自动更新章节日期与 RINE 状态
	if entry_idx >= 16 and entry_idx <= 119:
		if slot_id == 3 or (slot_id == 0 and entry_name.to_upper().begins_with("SG0_")):
			set_scr_work(4343, entry_idx)
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


func is_incoming_call_active() -> bool:
	return get_flag(2620) == 0 and get_flag(2699) != 0 and (get_flag(2743) != 0 or get_flag(2740) != 0)


func set_flag(idx: int, val: int) -> void:
	var was_set := get_flag(idx) != 0
	if val == 0:
		flags.erase(idx)
	else:
		flags[idx] = true
	if idx >= 2410 and idx <= 2417 and was_set and val == 0 and not _in_chara_swap:
		# 立绘槽位注销（macrosys L36/L42 宏全角色清理或指令释放）：按槽位位掩码发射释放信号
		var slot_mask := 1 << (idx - 2410)
		chara_released.emit(slot_mask)
	elif idx == 2699 or idx == 2743 or idx == 2740:
		var call_active := is_incoming_call_active()
		if call_active and not _incoming_call_notified:
			_incoming_call_notified = true
			phone_event.emit(20, [1 if get_flag(2743) != 0 else 0, get_scr_work(6613)])
		elif not call_active and _incoming_call_notified:
			_incoming_call_notified = false
			if idx == 2699 and was_set and val == 0:
				set_flag(0x4B6, 0)
				if get_flag(2620) == 0:
					set_flag(0x505, 0)
			phone_event.emit(3, [])
	elif idx == 2750 and not was_set and val != 0 and get_flag(2613) == 0:
		# 主动呼叫 Amadeus 触发窗口 (macrosys2 L[320])：通知手机解锁 Amadeus 图标（绝不弹来电遮罩）
		phone_event.emit(23, [2750])
	elif idx == 2748 and not was_set and val != 0:
		# 主动触发 RINE 分支窗口：仅通知主控停止快进等（绝不弹来电遮罩）
		phone_event.emit(23, [2748])


static func _mask_to_index(mask: int) -> int:
	## 对应 Game.exe 0x4238c0：将图层/槽位位掩码 (1,2,4,8,16...) 转换为 0..7 索引
	if mask <= 0:
		return 0
	for b in range(8):
		if (mask & (1 << b)) != 0:
			return b
	return clampi(mask, 0, 7)


func _swap_scr_work_range(base_a: int, base_b: int, count: int) -> void:
	## 双向交换两段连续 ScrWork 区间（用于 10:02 BGCommit 与 10:06 ChaSwap）
	for i in range(count):
		var va := get_scr_work(base_a + i)
		var vb := get_scr_work(base_b + i)
		set_scr_work(base_a + i, vb)
		set_scr_work(base_b + i, va)


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
	# 仅唤醒当前处于 MES_SYNC 等待的对白线程，绝不再额外置位 _mes_click_pending 导致连跳下一句对白
	for th in _threads:
		if th.alive and th.wait_mode == WaitMode.MES_SYNC:
			th.wait_mode = WaitMode.NONE
	_mes_click_pending = false


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
	# 0. 对齐 Game.exe 0x44def0：每帧驱动手机展开/收起计数 ScrWork[6601] (0..29)
	# 防止 macrosys2.scx L[345..346] / L[355] 等待 ScrWork[6601] 时死循环卡死
	var phone_step := 29 if skip_active else maxi(1, frames)
	var cur_6601 := get_scr_work(6601)
	if get_flag(2600) != 0:
		if cur_6601 < 29:
			set_scr_work(6601, mini(29, cur_6601 + phone_step))
	else:
		if cur_6601 > 0:
			set_scr_work(6601, maxi(0, cur_6601 - phone_step))

	# 1. 新一帧解除 YIELD_FRAME 并将 FRAMES 倒计时递减（快进态加速过渡帧等待）
	var step_mult := 4 if skip_active else 1
	for th in _threads:
		if not th.alive:
			continue
		if th.wait_mode == WaitMode.YIELD_FRAME:
			th.wait_mode = WaitMode.NONE
		elif th.wait_mode == WaitMode.FRAMES:
			th.wait_frames -= maxi(1, frames) * step_mult
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
			# 对齐 Game.exe 0x45dc90 -> 0x45aa80：新线程创建后立即同步执行至首次让出或结束，
			# 确保子线程忙标志在父线程紧随其后的 WaitFlag 检查前已就位
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			var e2 := Sc3Expr.eval(data, p, self, th); p = int(e2["end_pos"])
			var lid := _rd_u16(data, p); p += 2
			th.pc = p
			var target_slot := int(e2["value"])
			if not _scripts.has(target_slot):
				target_slot = th.script_slot
			var new_th := _spawn_thread(int(e1["value"]), target_slot, lid)
			if new_th != null:
				var init_ran := 0
				while new_th.alive and new_th.wait_mode == WaitMode.NONE and init_ran < 1000:
					_exec_one(new_th)
					init_ran += 1
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
			if skip_active:
				wf = 1
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
		0x11: # WaitFlag(cond_u8, flag_expr) (Game.exe 0x45e490: 若 Flag[fid] == cond 则挂起本帧并在原 PC 重试)
			var cond := _rd_u8(data, p); p += 1
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			var fid := int(e1["value"])
			var target_bit := 1 if cond != 0 else 0
			if get_flag(fid) == target_bit:
				if (fid == 0x73B or fid == 0x73C) and not _movie_playing:
					set_flag(fid, 0)
					th.pc = p
				else:
					th.wait_mode = WaitMode.YIELD_FRAME
			else:
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
		0x1F: # Switch(expr) (Game.exe 0x45b220)
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			th.switch_val = int(e1["value"])
			th.pc = p
		0x26, 0x2C, 0x31, 0x42, 0x46: # 1-expr 指令
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			th.pc = p
			if b1 == 0x26:
				th.wait_mode = WaitMode.FRAMES
				th.wait_frames = 1 if skip_active else maxi(1, int(e1["value"]))
			elif b1 == 0x46:
				# 动画/过渡循环内检测快进按键状态 -> 写入 ThreadVar[7]
				th.set_var(7, 1 if skip_active else 0)
		0x20: # Case(expr, label) (Game.exe 0x45b240)
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			var lid := _rd_u16(data, p); p += 2
			if int(e1["value"]) == th.switch_val:
				_jump_label(th, lid)
			else:
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
		0x33: # WaitFramesCounted (Game.exe 0x45c520: 开场动画与转场真实 60fps 帧等待；快进模式下立即跳过)
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			var _e2 := Sc3Expr.eval(data, p, self, th); p = int(_e2["end_pos"])
			th.pc = p
			var cnt := int(e1["value"]) & 0x3FF
			if cnt > 0 and not skip_active:
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
		0x05: # DispCtrl / 数学插值运算 (sub=3 正弦缓动, sub=5 线性插值)
			var sub := _rd_u8(data, p); p += 1
			var argc: int = int({0: 2, 1: 2, 2: 3, 3: 4, 4: 4, 5: 4, 6: 4}.get(sub, 0))
			var args: Array[int] = []
			for _k in range(argc):
				var ek := Sc3Expr.eval(data, p, self, th); p = int(ek["end_pos"])
				args.append(int(ek["value"]))
			th.pc = p
			if sub == 3 and args.size() >= 3:
				var s_val := sin(clampf(float(args[2]) / 16384.0, 0.0, 1.0) * PI * 0.5)
				set_scr_work(args[0], int(round(s_val * float(args[1]) * 65536.0)))
			elif sub == 5 and args.size() >= 4:
				var denom := maxi(1, args[3])
				set_scr_work(args[0], int(round(float(args[1]) * float(args[2]) / float(denom))))
			elif sub <= 2 and args.size() >= 2:
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
				if get_flag(2606) != 0:
					# 对齐 Game.exe 0x457d83：接听来电置位 Flag(2606) 时自动推进当前对白等待
					set_flag(2606, 0)
				elif not _mes_click_pending:
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
		0x00, 0x17, 0x28, 0x29, 0x2E:
			p = Sc3Expr.skip(data, p)
			th.pc = p
		0x10: # SG0_BgReleaseMask(mask_expr) -> 按位释放背景图层 (Game.exe 0x460b90)
			var em := Sc3Expr.eval(data, p, self, th); p = int(em["end_pos"])
			th.pc = p
			var mask := int(em["value"])
			for bit_i in range(8):
				if (mask & (1 << bit_i)) != 0:
					set_flag(2400 + bit_i, 0)
					set_scr_work(4500 + 40 * bit_i + 7, 0xFFFF)
					bg_cleared.emit(bit_i)
		0x11: # SG0_ChaReleaseMask(mask_expr) -> 按位淡出释放立绘槽位 (Game.exe 0x460c00)
			var em := Sc3Expr.eval(data, p, self, th); p = int(em["end_pos"])
			th.pc = p
			var mask := int(em["value"])
			for bit_i in range(8):
				if (mask & (1 << bit_i)) != 0:
					set_flag(2410 + bit_i, 0)
					set_scr_work(5100 + 40 * bit_i + 9, 0xFFFF)
					chara_released.emit(1 << bit_i)
		0x01: # SG0_BgChaCtrl(layer_mask_expr, bg_idx_expr) (Game.exe 0x45f930)
			var el := Sc3Expr.eval(data, p, self, th); p = int(el["end_pos"])
			var eb := Sc3Expr.eval(data, p, self, th); p = int(eb["end_pos"])
			th.pc = p
			var layer := _mask_to_index(int(el["value"]))
			var bg_val := int(eb["value"])
			set_flag(2400 + layer, 1)
			set_scr_work(4500 + 40 * layer + 7, bg_val)
			if bg_val >= 0 and bg_val < 0x00FF0000:
				bg_changed.emit(layer, bg_val)
			else:
				# 0xFFRRGGBB (-1=白, -16777216=黑, -65536=红) 为纯色全屏层而非清屏透明
				var u32 := bg_val & 0xFFFFFFFF
				var ca := float((u32 >> 24) & 0xFF) / 255.0
				var cr := float((u32 >> 16) & 0xFF) / 255.0
				var cg := float((u32 >> 8) & 0xFF) / 255.0
				var cb := float(u32 & 0xFF) / 255.0
				if ca <= 0.0:
					ca = 1.0
				bg_color_changed.emit(layer, Color(cr, cg, cb, ca))
		0x02: # SG0_BgCommit(dst_mask, src_mask) (Game.exe 0x460220: 双向交换图层与 ScrWork[4500+40*i])
			var ed := Sc3Expr.eval(data, p, self, th); p = int(ed["end_pos"])
			var es := Sc3Expr.eval(data, p, self, th); p = int(es["end_pos"])
			th.pc = p
			var dst_m := int(ed["value"])
			var src_m := int(es["value"])
			var d_idx := _mask_to_index(dst_m)
			var s_idx := _mask_to_index(src_m)
			if d_idx >= 0 and s_idx >= 0 and d_idx != s_idx:
				var fd := get_flag(2400 + d_idx)
				var fs := get_flag(2400 + s_idx)
				set_flag(2400 + d_idx, fs)
				set_flag(2400 + s_idx, fd)
				_swap_scr_work_range(4500 + 40 * d_idx, 4500 + 40 * s_idx, 40)
				_swap_scr_work_range(3400 + d_idx, 3400 + s_idx, 1)
			bg_committed.emit(dst_m, src_m)
		0x06: # SG0_ChaSwap(dst_mask, src_mask) (Game.exe 0x460760: 双向交换槽位与 ScrWork[5100+40*i])
			var ed := Sc3Expr.eval(data, p, self, th); p = int(ed["end_pos"])
			var es := Sc3Expr.eval(data, p, self, th); p = int(es["end_pos"])
			th.pc = p
			var dst_m := int(ed["value"])
			var src_m := int(es["value"])
			var d_idx := _mask_to_index(dst_m)
			var s_idx := _mask_to_index(src_m)
			if d_idx >= 0 and s_idx >= 0 and d_idx != s_idx:
				var fd := get_flag(2410 + d_idx)
				var fs := get_flag(2410 + s_idx)
				_in_chara_swap = true
				set_flag(2410 + d_idx, fs)
				set_flag(2410 + s_idx, fd)
				_in_chara_swap = false
				_swap_scr_work_range(5100 + 40 * d_idx, 5100 + 40 * s_idx, 40)
				_swap_scr_work_range(3450 + d_idx, 3450 + s_idx, 1)
			chara_swapped.emit(dst_m, src_m)
		0x03: # SG0_BgColorFill(layer_mask, rgb) (Game.exe 0x460320)
			var el := Sc3Expr.eval(data, p, self, th); p = int(el["end_pos"])
			var ec := Sc3Expr.eval(data, p, self, th); p = int(ec["end_pos"])
			th.pc = p
			var layer := _mask_to_index(int(el["value"]))
			var rgb := int(ec["value"]) & 0xFFFFFF
			set_flag(2400 + layer, 1)
			set_scr_work(4500 + 40 * layer + 7, int(0xFF000000 | rgb))
			var cr := float((rgb >> 16) & 0xFF) / 255.0
			var cg := float((rgb >> 8) & 0xFF) / 255.0
			var cb := float(rgb & 0xFF) / 255.0
			bg_color_changed.emit(layer, Color(cr, cg, cb, 1.0))
		0x07, 0x08, 0x09, 0x0E, 0x16:
			p = Sc3Expr.skip(data, p)
			p = Sc3Expr.skip(data, p)
			th.pc = p
		0x04: # SG0_SpriteAnim (Game.exe 0x4603c0)
			var sub := _rd_u8(data, p); p += 1
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			var e2 := Sc3Expr.eval(data, p, self, th); p = int(e2["end_pos"])
			var v3 := 0
			if sub >= 4:
				var e3 := Sc3Expr.eval(data, p, self, th); p = int(e3["end_pos"])
				v3 = int(e3["value"])
				sub -= 4
			var e4 := Sc3Expr.eval(data, p, self, th); p = int(e4["end_pos"])
			th.pc = p
			var packed := ((((v3 & 0xFF) << 8) | (int(e4["value"]) & 0xFF)) << 8) | (int(e1["value"]) & 0xFF)
			packed = (packed << 8) | (int(e2["value"]) & 0xFF)
			set_scr_work(4490 + sub, packed)
		0x05: # SG0_ChaLoad(subop, slot_mask_expr, encoded_idx_expr) (Game.exe 0x460450)
			var _sub := _rd_u8(data, p); p += 1
			var e_slot := Sc3Expr.eval(data, p, self, th); p = int(e_slot["end_pos"])
			var e_val := Sc3Expr.eval(data, p, self, th); p = int(e_val["end_pos"])
			th.pc = p
			var slot_mask := int(e_slot["value"])
			var slot_idx := _mask_to_index(slot_mask)
			var raw_v := int(e_val["value"])
			var chara_idx := raw_v & 0xFFFF
			var grp_hint := (raw_v >> 16) & 0xFFFF
			set_flag(2410 + slot_idx, 1)
			set_scr_work(5100 + 40 * slot_idx + 9, chara_idx)
			if grp_hint != 0:
				set_scr_work(5100 + 40 * slot_idx + 12, grp_hint)
			chara_loaded.emit(slot_mask, chara_idx, grp_hint)
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
		0x22: # SG0_PhoneCtrl (Game.exe 0x460f60)
			var sub := _rd_u8(data, p); p += 1
			var args: Array = []
			if sub == 10:
				var arg0 := _rd_u16(data, p); p += 2
				_last_phone_ctrl_arg = arg0
				args.append(arg0)
				set_flag(0x4B6, 1)
			elif sub == 255:
				set_flag(0x4B6, 1)
			elif sub == 0 or sub == 1 or sub == 5:
				set_flag(0x505, 1)
				# PhoneCtrl(1) 在 macrosys2 L[323] 中仅为手机触发点存档准备，实际来电/去电分支由 Flag(2699/2743/2740/2750/2748) 决定
				if sub != 1:
					args.append(_last_phone_ctrl_arg)
			elif sub == 3:
				set_flag(0x505, 0)
			th.pc = p
			phone_event.emit(sub, args)
		0x23: # SG0_TipsCtrl
			var sub := _rd_u8(data, p); p += 1
			var tip_id := -1
			if sub == 0 or sub == 10:
				tip_id = _rd_u8(data, p); p += 1
			th.pc = p
			if tip_id >= 0:
				unlock_tip(tip_id)
		0x27: # SG0_TipsSet / TipsStatus (macrosys.scx label 0x92/0x9a 调用 0x10 0x27 sub=1)
			var sub := _rd_u8(data, p); p += 1
			var e1 := Sc3Expr.eval(data, p, self, th); p = int(e1["end_pos"])
			var tip_id := int(e1["value"])
			var out_flag_id := -1
			if sub == 1:
				var e2 := Sc3Expr.eval(data, p, self, th); p = int(e2["end_pos"])
				out_flag_id = int(e2["value"])
			th.pc = p
			if sub == 1 and tip_id >= 0:
				var cur_sname := str(_scripts.get(th.script_slot, {}).get("name", "")).to_upper()
				if cur_sname == "CLRFLG.SCX":
					if out_flag_id >= 0:
						set_flag(out_flag_id, 1 if unlocked_tips.has(tip_id) else 0)
				else:
					var newly_unlocked := unlock_tip(tip_id)
					if out_flag_id >= 0:
						# 对齐 Game.exe 0x461427 (1 - GetTipStatus)：仅首次新解锁时输出 1，已解锁返回 0
						set_flag(out_flag_id, 1 if newly_unlocked else 0)
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
		0x37: # SG0_RineCtrl (Game.exe 0x4619b0)
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
			_handle_rine_ctrl(sub, args)
		0x0A, 0x0B, 0x12, 0x1E, 0x2D, 0x2F, 0x40, 0x41: # 0-操作数指令 (含 10:0B SG0_ChaSync)
			th.pc = p
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
		"rine_state": {
			"active": _rine_active,
			"pc": _rine_pc,
			"waiting_reply": _rine_waiting_reply,
			"contact_id": _rine_contact_id,
			"reply_mode": _rine_reply_mode,
			"self_id": _rine_self_id,
			"members": Array(_rine_members),
			"reply_options": _rine_reply_options.duplicate(true),
			"history_count": _rine_history_count,
			"trigger_label": _rine_trigger_label,
		},
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
		flags[int(fk)] = true
	_incoming_call_notified = is_incoming_call_active()
	for tk in state.get("unlocked_tips", []):
		unlocked_tips[int(tk)] = true
	if not unlocked_tips.is_empty():
		save_unlocked_tips()

	var rs: Variant = state.get("rine_state", {})
	if rs is Dictionary and not (rs as Dictionary).is_empty():
		var rd: Dictionary = rs as Dictionary
		_rine_active = bool(rd.get("active", false))
		_rine_pc = int(rd.get("pc", 0))
		_rine_waiting_reply = bool(rd.get("waiting_reply", false))
		_rine_contact_id = int(rd.get("contact_id", -1))
		_rine_reply_mode = int(rd.get("reply_mode", 0))
		_rine_self_id = int(rd.get("self_id", 0))
		_rine_members.clear()
		for m in rd.get("members", []):
			_rine_members.append(int(m))
		_rine_history_count = int(rd.get("history_count", 0))
		_rine_trigger_label = int(rd.get("trigger_label", -1))
		_rine_reply_options.clear()
		for opt in rd.get("reply_options", []):
			if opt is Dictionary:
				_rine_reply_options.append({
					"str_id": int(opt.get("str_id", -1)),
					"label_id": int(opt.get("label_id", -1)),
				})

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


# ==================== RINE (_rndrine.scx) 子解释器 & Amadeus 写回 ====================

func _reset_rine_subinterp() -> void:
	_rine_active = false
	_rine_pc = 0
	_rine_waiting_reply = false
	_rine_contact_id = -1
	_rine_reply_mode = 0
	_rine_self_id = 0
	_rine_members.clear()
	_rine_reply_options.clear()
	_rine_history_count = 0
	_rine_trigger_label = -1
	_last_phone_ctrl_arg = -1
	_incoming_call_notified = false


func get_rine_state() -> Dictionary:
	return {
		"active": _rine_active,
		"pc": _rine_pc,
		"waiting_reply": _rine_waiting_reply,
		"contact_id": _rine_contact_id,
		"reply_mode": _rine_reply_mode,
		"self_id": _rine_self_id,
		"members": Array(_rine_members),
		"reply_options": _rine_reply_options.duplicate(true),
		"history_count": _rine_history_count,
		"trigger_label": _rine_trigger_label,
	}


func _handle_rine_ctrl(sub: int, args: Array) -> void:
	match sub:
		0x32: # sub=50: 从 _phone.scx(slot 9) 读取索引标签首字 u16 写入 ScrWork[6655] (Game.exe 0x44d620)
			if not _scripts.has(9):
				load_script_into_slot(9, "_phone.scx")
			if _scripts.has(9) and args.size() >= 1:
				var idx := int(args[0])
				var ph: Dictionary = _scripts[9]
				var ph_labels: PackedInt32Array = ph["labels"]
				var ph_data: PackedByteArray = ph["data"]
				if idx >= 0 and idx < ph_labels.size():
					var off := int(ph_labels[idx])
					if off + 1 < ph_data.size():
						var base_str_id := _rd_u16(ph_data, off)
						set_scr_work(6655, base_str_id)
			rine_event.emit(sub, args)
		0x0A: # sub=10: 启动 _rndrine.scx 子解释器标签 (Game.exe 0x454690)
			var lid := int(args[0]) if args.size() >= 1 else -1
			set_flag(2614, 1) # 0xA36: RINE 待回复
			set_flag(2615, 0) # 0xA37: RINE 未读
			set_flag(2616, 1) # 0xA38: RINE 全局未读通知
			set_scr_work(6656, 0)
			if lid >= 0:
				_start_rine_subinterp(lid)
			rine_event.emit(sub, args)
		0x0B: # sub=11: 结束本轮 RINE 回复并更新标志 (Game.exe 0x453d30)
			_finish_rine_round()
			rine_event.emit(sub, args)
		0x0C: # sub=12: 设置本轮回复关联参数与回复模式 (args[0]=ScrWork[1501], args[1]=0文本/1贴纸；绝非联系人ID！)
			if args.size() >= 2:
				_rine_reply_mode = int(args[1])
			_rine_reply_options.clear()
			rine_event.emit(sub, args)
		0x0D: # sub=13: 注册可回复选项 (str_id/sticker_id, branch_label_id)
			if args.size() >= 2 and _rine_reply_options.size() < 3:
				var opt_str := int(args[0])
				var opt_lbl := int(args[1])
				var exists := false
				for o in _rine_reply_options:
					if int(o["str_id"]) == opt_str and int(o["label_id"]) == opt_lbl:
						exists = true
						break
				if not exists:
					_rine_reply_options.append({"str_id": opt_str, "label_id": opt_lbl})
			rine_event.emit(sub, args)
		0x0E: # sub=14: 等待玩家选择回复
			_rine_waiting_reply = true
			rine_event.emit(sub, args)
		0x0F, 0x2E: # sub=15 / sub=46: 追加聊天消息 (args[0]=发送者ID: 0=伦太郎自己, >0=对方角色ID)
			_rine_history_count += 1
			if args.size() >= 1:
				var sender_id := int(args[0])
				if sender_id != _rine_self_id and sender_id > 0:
					_rine_contact_id = sender_id
					set_flag(2616, 1)
					set_flag(2615, 0)
			rine_event.emit(sub, args)
		0x2A: # sub=42: 设置己方视角角色ID (Game.exe 0x452660, 默认0=伦太郎)
			if args.size() >= 1:
				_rine_self_id = int(args[0])
			rine_event.emit(sub, args)
		0x2B, 0x2C: # sub=43/44: 将成员加入当前聊天室列表 (Game.exe 0x452580 / 0x452530)
			if args.size() >= 1:
				var m_id := int(args[0])
				if not _rine_members.has(m_id):
					_rine_members.append(m_id)
				if m_id != _rine_self_id and m_id > 0:
					_rine_contact_id = m_id
			rine_event.emit(sub, args)
		0x2D: # sub=45: 将成员从当前聊天室移除 (Game.exe 0x452610)
			if args.size() >= 1:
				_rine_members.erase(int(args[0]))
			rine_event.emit(sub, args)
		0x2F: # sub=47: 清空当前 RINE UI 临时缓冲 (Game.exe 0x452470)
			rine_event.emit(sub, args)
		0x28: # sub=40: 初始化/重置 RINE 全局记录 (Game.exe 0x452c30)
			set_flag(2760, 0) # 0xAC8
			set_flag(2741, 0) # 0xAB5
			set_scr_work(6652, 0)
			set_scr_work(6653, 0)
			_rine_history_count = 0
			_rine_reply_options.clear()
			_rine_waiting_reply = false
			_rine_active = false
			rine_event.emit(sub, args)
		0x29: # sub=41: 同步历史消息存在标志 (Game.exe 0x452ca0)
			if _rine_history_count > 0:
				set_flag(2760, 1)
			rine_event.emit(sub, args)
		_:
			rine_event.emit(sub, args)


func _finish_rine_round() -> void:
	set_flag(2616, 0) # 清除全局未读通知
	set_flag(1205, 0) # 0x4B5: 清除 RINE 活跃阻塞标志
	if _rine_history_count > 0:
		set_flag(2760, 1) # 0xAC8: 存在历史记录
	set_scr_work(6650, 0)
	set_scr_work(6651, 0)
	set_scr_work(6656, 0)
	_rine_reply_options.clear()
	_rine_waiting_reply = false


func _start_rine_subinterp(label_id: int) -> void:
	if not _scripts.has(11):
		load_script_into_slot(11, "_rndrine.scx")
	if not _scripts.has(11):
		return
	var rsc: Dictionary = _scripts[11]
	var rlabels: PackedInt32Array = rsc["labels"]
	if label_id < 0 or label_id >= rlabels.size():
		return
	_rine_active = true
	_rine_waiting_reply = false
	_rine_trigger_label = label_id
	_rine_reply_options.clear()
	_rine_pc = int(rlabels[label_id])
	_run_rine_subinterp()


func _run_rine_subinterp() -> void:
	if not _scripts.has(11):
		_rine_active = false
		return
	var rsc: Dictionary = _scripts[11]
	var data: PackedByteArray = rsc["data"]
	var code_end: int = int(rsc["code_end"])
	var dummy_th := ThreadCtx.new()
	dummy_th.script_slot = 11

	var guard := 0
	while _rine_active and not _rine_waiting_reply and _rine_pc < code_end and guard < 256:
		guard += 1
		var p := _rine_pc
		if p + 1 >= data.size():
			_rine_active = false
			set_scr_work(6656, 99)
			break
		var b0 := int(data[p])
		var b1 := int(data[p + 1])

		# 仅执行 RINE 子解释器白名单指令: 00:12 SetFlag, 00:13 ResetFlag, 10:37 SG0_RineCtrl
		if b0 == 0x00 and (b1 == 0x12 or b1 == 0x13):
			var ev := Sc3Expr.eval(data, p + 2, self, dummy_th)
			_rine_pc = int(ev["end_pos"])
			set_flag(int(ev["value"]), 1 if b1 == 0x12 else 0)
			continue

		if (b0 & 0x7F) == 0x10 and b1 == 0x37:
			var sp := p + 2
			var sub := _rd_u8(data, sp); sp += 1
			var args: Array = []
			if sub == 0x0C: # 设置回复关联参数与模式 (args[1]=0文本/1贴纸，不修改 _rine_contact_id)
				var e1 := Sc3Expr.eval(data, sp, self, dummy_th); sp = int(e1["end_pos"]); args.append(e1["value"])
				var e2 := Sc3Expr.eval(data, sp, self, dummy_th); sp = int(e2["end_pos"]); args.append(e2["value"])
				_rine_pc = sp
				_rine_reply_mode = int(args[1])
				_rine_reply_options.clear()
				rine_event.emit(12, args)
			elif sub == 0x0D: # 注册可回复选项
				var e1 := Sc3Expr.eval(data, sp, self, dummy_th); sp = int(e1["end_pos"]); args.append(e1["value"])
				args.append(_rd_u16(data, sp)); sp += 2
				_rine_pc = sp
				if _rine_reply_options.size() < 3:
					var opt_str := int(args[0])
					var opt_lbl := int(args[1])
					var exists := false
					for o in _rine_reply_options:
						if int(o["str_id"]) == opt_str and int(o["label_id"]) == opt_lbl:
							exists = true
							break
					if not exists:
						_rine_reply_options.append({"str_id": opt_str, "label_id": opt_lbl})
				rine_event.emit(13, args)
			elif sub == 0x0E: # 挂起等待玩家回复
				_rine_pc = sp
				_rine_waiting_reply = true
				rine_event.emit(14, [])
				break
			elif sub == 0x0F: # 追加消息
				for _k in range(3):
					var ek := Sc3Expr.eval(data, sp, self, dummy_th); sp = int(ek["end_pos"]); args.append(ek["value"])
				_rine_pc = sp
				_rine_history_count += 1
				if args.size() >= 1:
					var sender_id := int(args[0])
					if sender_id != _rine_self_id and sender_id > 0:
						_rine_contact_id = sender_id
						set_flag(2616, 1)
						set_flag(2615, 0)
				rine_event.emit(15, args)
			elif sub == 0x0B: # 本轮回复结束
				_rine_pc = sp
				_finish_rine_round()
				rine_event.emit(11, [])
				# 若紧随指令不是继续的 RINE 动作（例如 End/Return），结束子解释器
				if _rine_pc + 2 >= data.size():
					_rine_active = false
					set_scr_work(6656, 99)
					break
				var nb0 := int(data[_rine_pc])
				var nb1 := int(data[_rine_pc + 1])
				var is_next_rine := ((nb0 & 0x7F) == 0x10 and nb1 == 0x37) or (nb0 == 0x00 and (nb1 == 0x12 or nb1 == 0x13))
				if not is_next_rine:
					_rine_active = false
					set_scr_work(6656, 99)
					break
			else:
				_rine_active = false
				set_scr_work(6656, 99)
				break
		else:
			# 遇到 End (00:00) / Return (00:0E) 等非 RINE 子指令，标记本段完成
			_rine_active = false
			set_scr_work(6656, 99)
			break


## 玩家打开/阅读 RINE 聊天后清除未读标志
func mark_rine_read() -> void:
	set_flag(2615, 1) # 已读
	set_flag(2616, 0) # 清除全局未读提示


## 玩家在 UI 选择一条 RINE 回复选项，写回状态机并推进 _rndrine.scx 分支
func submit_rine_reply(str_id: int) -> bool:
	var target_label := -1
	for opt in _rine_reply_options:
		if int(opt["str_id"]) == str_id:
			target_label = int(opt["label_id"])
			break
	set_flag(2615, 1) # 已读
	set_flag(2614, 0) # 已回复，清除待回复标志
	set_flag(2616, 0) # 清除全局未读提示
	_rine_reply_options.clear()
	_rine_waiting_reply = false
	_rine_history_count += 1
	if _rine_history_count > 0:
		set_flag(2760, 1)

	if target_label >= 0 and _scripts.has(11):
		var rlabels: PackedInt32Array = _scripts[11]["labels"]
		if target_label < rlabels.size():
			_rine_active = true
			_rine_pc = int(rlabels[target_label])
			_run_rine_subinterp()
			return true
	return false


## 玩家在贴纸托盘发送贴纸，写回已读与历史计数；若当前处于贴纸回复分支 (sub=12 args[1]==1)，则推进对应 _rndrine.scx 分支
func submit_rine_sticker(sticker_idx: int) -> bool:
	set_flag(2615, 1)
	set_flag(2616, 0)
	_rine_history_count += 1
	if _rine_history_count > 0:
		set_flag(2760, 1)
	if _rine_waiting_reply and _rine_reply_mode == 1 and not _rine_reply_options.is_empty():
		var target_label := -1
		for opt in _rine_reply_options:
			if int(opt["str_id"]) == sticker_idx:
				target_label = int(opt["label_id"])
				break
		if target_label < 0:
			target_label = int(_rine_reply_options[0]["label_id"])
		set_flag(2614, 0)
		_rine_reply_options.clear()
		_rine_waiting_reply = false
		if target_label >= 0 and _scripts.has(11):
			var rlabels: PackedInt32Array = _scripts[11]["labels"]
			if target_label < rlabels.size():
				_rine_active = true
				_rine_pc = int(rlabels[target_label])
				_run_rine_subinterp()
				return true
	return false


## 玩家在 Amadeus/来电/触发界面点击接听(true)或挂断(false)，写回 SG0_PhoneCtrl 状态标志
func submit_amadeus_action(accepted: bool) -> void:
	set_flag(0x4B6, 0) # 清除来电等待标志
	if accepted:
		_incoming_call_notified = false
		set_flag(0x505, 1) # 通话连接标志置位
		set_flag(2620, 1) # 0xA3C: 对齐 Game.exe 0x44e280，置位已接听标志以命中 JumpIfFlag(1, 2620, ...)
		set_flag(2604, 1) # 0xA2C
		set_flag(2606, 1) # 0xA2E: 对齐 Game.exe 0x457d83，触发 MesMain 自动推进
		phone_event.emit(0, [])
		if is_waiting_for_click():
			notify_user_advance()
			set_flag(2606, 0)
	else:
		set_flag(0x505, 0) # 挂断/拒接清除通话标志
		set_flag(2617, 1) # 0xA39
		set_flag(2603, 1) # 0xA2B
		set_flag(2604, 1) # 0xA2C
		set_scr_work(6656, 0)
		phone_event.emit(3, [])
