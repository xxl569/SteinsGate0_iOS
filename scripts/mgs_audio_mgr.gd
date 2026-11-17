class_name MgsAudioMgr
extends Node
## 多通道音频管理器（BGM Ogg LOOPSTART/LOOPLENGTH 无缝循环 + SE 池 + 配音与 WAVTABLE/峰值口型同步）

signal bgm_started(bgm_name: String)
signal voice_started(voice_name: String)
signal voice_finished()

const SE_POOL_SIZE := 8
const BUS_BGM := &"BGM"
const BUS_SE := &"SE"
const BUS_VOICE := &"Voice"

var _vfs: MgsVfs = null
var _cfg: ConfigManager = null
var _bgm_player: AudioStreamPlayer = null
var _voice_player: AudioStreamPlayer = null
var _se_pool: Array[AudioStreamPlayer] = []
var _se_pool_ids: Array[int] = []
var _se_pool_names: Array[String] = []
var _se_last_ms: Dictionary = {}
var _se_cursor: int = 0

var _bgm_loop_enabled: bool = false
var _bgm_loop_start_sec: float = 0.0
var _bgm_loop_end_sec: float = 0.0
var _bgm_fade_tween: Tween = null
var _current_bgm_idx: int = -1

var _wavtable_raw: PackedByteArray = PackedByteArray()
var _wavtable_loaded: bool = false
var _voice_elapsed: float = 0.0


func _ready() -> void:
	ensure_buses()
	_ensure_players()


func ensure_buses() -> void:
	for bname in [BUS_BGM, BUS_SE, BUS_VOICE]:
		if AudioServer.get_bus_index(bname) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bname)


func _ensure_players() -> void:
	if _bgm_player != null:
		return
	ensure_buses()
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BgmPlayer"
	_bgm_player.bus = BUS_BGM
	add_child(_bgm_player)

	_voice_player = AudioStreamPlayer.new()
	_voice_player.name = "VoicePlayer"
	_voice_player.bus = BUS_VOICE
	_voice_player.finished.connect(func(): voice_finished.emit())
	add_child(_voice_player)

	for i in range(SE_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.name = "SePlayer_%d" % i
		p.bus = BUS_SE
		add_child(p)
		_se_pool.append(p)
		_se_pool_ids.append(-1)
		_se_pool_names.append("")


func bind_vfs(vfs: MgsVfs) -> void:
	_vfs = vfs
	_ensure_players()
	if _vfs != null and _vfs.is_mounted and _vfs.has_entry("system.mpk", "WAVTABLE.DAT"):
		_wavtable_raw = _vfs.read_entry("system.mpk", "WAVTABLE.DAT")
		_wavtable_loaded = _wavtable_raw.size() >= 16


func bind_vm(vm: Sc3Vm) -> void:
	if vm == null:
		return
	if not vm.bgm_play_requested.is_connected(play_bgm):
		vm.bgm_play_requested.connect(play_bgm)
	if not vm.bgm_stop_requested.is_connected(stop_bgm):
		vm.bgm_stop_requested.connect(stop_bgm)
	if not vm.se_play_requested.is_connected(play_se):
		vm.se_play_requested.connect(play_se)
	if not vm.se_stop_requested.is_connected(stop_se):
		vm.se_stop_requested.connect(stop_se)
	if not vm.voice_play_requested.is_connected(play_voice):
		vm.voice_play_requested.connect(play_voice)


func has_wavtable() -> bool:
	return _wavtable_loaded


func get_wavtable_size() -> int:
	return _wavtable_raw.size()


func apply_config(cfg: ConfigManager) -> void:
	if cfg == null:
		return
	_cfg = cfg
	ensure_buses()
	_set_bus_linear(BUS_BGM, cfg.bgm_volume)
	_set_bus_linear(BUS_SE, cfg.se_volume)
	_set_bus_linear(BUS_VOICE, cfg.voice_volume)


func _set_bus_linear(bus_name: StringName, linear_vol: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var v := clampf(linear_vol, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.001, v)))


func _process(delta: float) -> void:
	if _bgm_player != null and _bgm_player.playing and _bgm_loop_enabled and _bgm_loop_end_sec > _bgm_loop_start_sec:
		var pos := _bgm_player.get_playback_position()
		if pos >= _bgm_loop_end_sec:
			_bgm_player.seek(_bgm_loop_start_sec)

	if _voice_player != null and _voice_player.playing:
		_voice_elapsed += delta
	else:
		_voice_elapsed = 0.0


## 解析 Ogg Vorbis 头部中的采样率与 LOOPSTART/LOOPLENGTH 标签
static func parse_ogg_loop_tags(ogg_bytes: PackedByteArray) -> Dictionary:
	var sample_rate := 44100
	var loop_start := -1
	var loop_length := -1
	var head := ogg_bytes.slice(0, mini(16384, ogg_bytes.size()))

	# 读取 Vorbis Identification 头采样率 (0x01 + "vorbis" + 4B version + 1B ch + 4B sample_rate)
	for i in range(0, maxi(0, head.size() - 16)):
		if head[i] == 0x01 and head[i + 1] == 0x76 and head[i + 2] == 0x6F and head[i + 3] == 0x72 and head[i + 4] == 0x62 and head[i + 5] == 0x69 and head[i + 6] == 0x73:
			var sr := int(head.decode_u32(i + 12))
			if sr >= 8000 and sr <= 192000:
				sample_rate = sr
			break

	# 仅保留可打印 ASCII 提取 Vorbis 注释中的 LOOPSTART / LOOPLENGTH
	var ascii_buf := PackedByteArray()
	ascii_buf.resize(head.size())
	for i in range(head.size()):
		var b := int(head[i])
		ascii_buf[i] = b if (b >= 0x20 and b <= 0x7E) else 0x20
	var text := ascii_buf.get_string_from_ascii()

	var ls_idx := text.find("LOOPSTART=")
	if ls_idx >= 0:
		loop_start = _parse_int_after(text, ls_idx + 10)
	var ll_idx := text.find("LOOPLENGTH=")
	if ll_idx >= 0:
		loop_length = _parse_int_after(text, ll_idx + 11)

	return {
		"sample_rate": sample_rate,
		"loop_start": loop_start,
		"loop_length": loop_length,
	}


static func _parse_int_after(s: String, start_pos: int) -> int:
	var digits := ""
	var i := start_pos
	while i < s.length():
		var ch := s[i]
		if ch >= "0" and ch <= "9":
			digits += ch
			i += 1
		else:
			break
	return int(digits) if digits != "" else -1


func play_bgm(bgm_idx: int, loop: bool = true, fade_frames: int = 0) -> bool:
	_ensure_players()
	if _vfs == null or not _vfs.is_mounted or bgm_idx < 0:
		return false
	if _current_bgm_idx == bgm_idx and _bgm_player.playing:
		return true
	var entry_name := _vfs.get_entry_name_by_index("bgm.mpk", bgm_idx)
	if entry_name == "":
		return false
	var raw := _vfs.read_entry("bgm.mpk", entry_name)
	if raw.is_empty():
		return false
	var stream := AudioStreamOggVorbis.load_from_buffer(raw)
	if stream == null:
		return false

	var tags := parse_ogg_loop_tags(raw)
	var sr := int(tags["sample_rate"])
	var ls := int(tags["loop_start"])
	var ll := int(tags["loop_length"])

	_bgm_loop_enabled = loop
	_bgm_loop_start_sec = float(ls) / float(sr) if ls >= 0 and sr > 0 else 0.0
	_bgm_loop_end_sec = 0.0
	stream.loop = loop
	if loop and _bgm_loop_start_sec > 0.0:
		stream.loop_offset = _bgm_loop_start_sec
	if loop and ls >= 0 and ll > 0 and sr > 0:
		var end_sec := float(ls + ll) / float(sr)
		if end_sec < stream.get_length() - 0.05:
			_bgm_loop_end_sec = end_sec

	if _bgm_fade_tween != null and _bgm_fade_tween.is_valid():
		_bgm_fade_tween.kill()
	_bgm_player.stop()
	_bgm_player.stream = stream
	_current_bgm_idx = bgm_idx

	if fade_frames > 0:
		_bgm_player.volume_db = -40.0
		_bgm_player.play()
		_bgm_fade_tween = create_tween()
		_bgm_fade_tween.tween_property(_bgm_player, "volume_db", 0.0, float(fade_frames) / 60.0)
	else:
		_bgm_player.volume_db = 0.0
		_bgm_player.play()

	bgm_started.emit(entry_name)
	return true


func stop_bgm(fade_frames: int = 15) -> void:
	_ensure_players()
	if _bgm_fade_tween != null and _bgm_fade_tween.is_valid():
		_bgm_fade_tween.kill()
	_current_bgm_idx = -1
	if not _bgm_player.playing:
		return
	if fade_frames <= 1:
		_bgm_player.stop()
		return
	_bgm_fade_tween = create_tween()
	_bgm_fade_tween.tween_property(_bgm_player, "volume_db", -60.0, float(fade_frames) / 60.0)
	_bgm_fade_tween.tween_callback(func():
		if is_instance_valid(_bgm_player):
			_bgm_player.stop()
	)


func is_bgm_playing() -> bool:
	return _bgm_player != null and _bgm_player.playing


func get_bgm_loop_info() -> Dictionary:
	return {
		"bgm_idx": _current_bgm_idx,
		"loop_enabled": _bgm_loop_enabled,
		"loop_start_sec": _bgm_loop_start_sec,
		"loop_end_sec": _bgm_loop_end_sec,
	}


func play_se(se_idx: int, loop: bool = false) -> bool:
	_ensure_players()
	if _vfs == null or not _vfs.is_mounted or se_idx < 0:
		return false
	# 防止循环音效在同一槽位重复叠加触发引起高频爆音/蜂鸣
	if loop:
		for i in range(_se_pool.size()):
			if _se_pool_ids[i] == se_idx and _se_pool[i].playing:
				return true
	else:
		var now_ms := Time.get_ticks_msec()
		if _se_last_ms.has(se_idx) and now_ms - int(_se_last_ms[se_idx]) < 35:
			return true
		_se_last_ms[se_idx] = now_ms

	var entry_name := _vfs.get_entry_name_by_index("se.mpk", se_idx)
	if entry_name == "":
		return false
	var raw := _vfs.read_entry("se.mpk", entry_name)
	if raw.is_empty():
		return false
	var stream := AudioStreamOggVorbis.load_from_buffer(raw)
	if stream == null:
		return false
	stream.loop = loop

	var slot_idx := _se_cursor % _se_pool.size()
	var player: AudioStreamPlayer = _se_pool[slot_idx]
	_se_cursor += 1
	player.stop()
	player.stream = stream
	_se_pool_ids[slot_idx] = se_idx
	_se_pool_names[slot_idx] = entry_name
	player.play()
	return true


func stop_se(channel: int = -1) -> void:
	if channel < 0:
		for i in range(_se_pool.size()):
			_se_pool[i].stop()
			_se_pool_ids[i] = -1
			if i < _se_pool_names.size():
				_se_pool_names[i] = ""
	elif channel < _se_pool.size():
		if channel < _se_pool_names.size() and _se_pool_names[channel].to_upper().begins_with("SGSE7"):
			return
		_se_pool[channel].stop()
		_se_pool_ids[channel] = -1
		if channel < _se_pool_names.size():
			_se_pool_names[channel] = ""


## 停止全部 SE 通道（供来电结束/挂断等场景统一调用）
func stop_all_se() -> void:
	stop_se(-1)


## 按条目前缀精确停止指定 SE（例如 "SGSE7" 停止循环来电铃声而不误伤其他音效）
func stop_se_by_prefix(prefix: String) -> void:
	if prefix == "":
		return
	var p_upper := prefix.to_upper()
	for i in range(_se_pool.size()):
		if i < _se_pool_names.size() and _se_pool_names[i].to_upper().begins_with(p_upper):
			_se_pool[i].stop()
			_se_pool_ids[i] = -1
			_se_pool_names[i] = ""


## 查询指定名称或任意 SE 是否正在播放
func is_se_playing(entry_name: String = "") -> bool:
	var target := entry_name.to_upper()
	for i in range(_se_pool.size()):
		if _se_pool[i].playing:
			if target == "" or (i < _se_pool_names.size() and _se_pool_names[i].to_upper() == target):
				return true
	return false


## 按 se.mpk 条目名直接播放音效（用于手机来电铃声试听 SGSE700.ogg..SGSE706.ogg）
func play_se_by_name(entry_name: String, loop: bool = false) -> bool:
	_ensure_players()
	if _vfs == null or not _vfs.is_mounted or entry_name == "":
		return false
	var idx := _vfs.get_archive_entry_index("se.mpk", entry_name)
	if idx >= 0:
		return play_se(idx, loop)
	var raw := _vfs.read_entry("se.mpk", entry_name)
	if raw.is_empty():
		return false
	var stream := AudioStreamOggVorbis.load_from_buffer(raw)
	if stream == null:
		return false
	stream.loop = loop
	var slot_idx := _se_cursor % _se_pool.size()
	var player: AudioStreamPlayer = _se_pool[slot_idx]
	_se_cursor += 1
	player.stop()
	player.stream = stream
	_se_pool_ids[slot_idx] = -2
	_se_pool_names[slot_idx] = entry_name
	player.play()
	return true


func _resolve_voice_char_slot(entry_name: String, fallback_char_id: int) -> int:
	var stem := entry_name.get_basename().to_upper()
	var parts := stem.split("_")
	# 从右向左扫描分段，兼容 *_K.ogg（电话滤音版）等尾部后缀
	for idx in range(parts.size() - 1, -1, -1):
		var tag := parts[idx]
		var code := ""
		for i in range(tag.length()):
			var ch := tag[i]
			if ch >= "A" and ch <= "Z":
				code += ch
			else:
				break
		match code:
			"OKA", "OKM": return 1
			"MAY", "SMY": return 2
			"DAR": return 3
			"CRS": return 4
			"MOE": return 5
			"RUK": return 6
			"FEI": return 7
			"SUZ": return 8
			"NAE": return 9
			"TEN": return 10
			"MAH": return 11
			"YUK": return 12
			"KAG": return 13
			"REI", "RDA", "IZK": return 0
			"FUB", "KAE", "EXA", "EXB", "EXC", "EXE", "EXF", "EXH", "EXJ", "EXM", "EXP", "EXR", "EXT", "EXW", "EXY": return 15
			"ETA", "ETB", "EXD", "EXG", "EXI", "EXL", "EXN", "EXO", "EXQ", "EXS", "EXU", "EXV", "EXX", "EXZ", "GOS", "HMN", "KRK", "NAK", "RES", "URP": return 14
	if fallback_char_id >= 0 and fallback_char_id < ConfigManager.VOICE_CHAR_COUNT:
		return fallback_char_id
	return 14


func play_voice(voice_idx: int, char_id: int = 0) -> bool:
	_ensure_players()
	if _vfs == null or not _vfs.is_mounted or voice_idx <= 0:
		return false
	var entry_name := _vfs.get_entry_name_by_index("voice.mpk", voice_idx)
	if entry_name == "" or entry_name.to_lower().begins_with("_novoice"):
		return false
	var char_gain := 1.0
	if _cfg != null:
		var slot := _resolve_voice_char_slot(entry_name, char_id)
		char_gain = _cfg.get_char_voice_gain(slot)
		if char_gain <= 0.001:
			return false
	var raw := _vfs.read_entry("voice.mpk", entry_name)
	if raw.is_empty():
		return false
	var stream := AudioStreamOggVorbis.load_from_buffer(raw)
	if stream == null:
		return false
	_voice_player.stop()
	_voice_player.stream = stream
	_voice_player.volume_db = linear_to_db(maxf(0.001, char_gain))
	_voice_elapsed = 0.0
	_voice_player.play()
	voice_started.emit(entry_name)
	return true


func stop_voice() -> void:
	if _voice_player != null:
		_voice_player.stop()


func is_voice_playing() -> bool:
	return _voice_player != null and _voice_player.playing


## 获取当前口型张合等级（0=闭合，1=半张，2=全张）
func get_voice_mouth_level() -> int:
	if _voice_player == null or not _voice_player.playing:
		return 0
	var bus_idx := AudioServer.get_bus_index(BUS_VOICE)
	if bus_idx >= 0:
		var db := AudioServer.get_bus_peak_volume_left_db(bus_idx, 0)
		if db > -60.0:
			if db > -14.0:
				return 2
			elif db > -32.0:
				return 1
			return 0
	# Dummy 音频后端无实时波形峰值时使用稳定音节节拍
	var tick := int(_voice_elapsed * 12.0) % 4
	return 2 if tick == 1 else (1 if tick == 0 or tick == 2 else 0)


func get_current_bgm_idx() -> int:
	if _bgm_player != null and _bgm_player.playing:
		return _current_bgm_idx
	return -1


func is_current_bgm_loop() -> bool:
	return _bgm_loop_enabled
