class_name MgsCache
extends RefCounted
## iOS 内存与纹理 LRU 缓存管理（上限 140 MB，响应内存告警自动释放非活跃贴图）

const DEFAULT_MAX_BYTES := 140 * 1024 * 1024 # 140 MB

var max_bytes: int = DEFAULT_MAX_BYTES
var _used_bytes: int = 0
var _entries: Dictionary = {} # key(String) -> { texture: Texture2D, bytes: int, origin: Vector2i }
var _lru_order: Array[String] = []


func _init(limit_bytes: int = DEFAULT_MAX_BYTES) -> void:
	max_bytes = maxi(16 * 1024 * 1024, limit_bytes)


func get_used_bytes() -> int:
	return _used_bytes


func get_entry_count() -> int:
	return _entries.size()


func has_texture(key: String) -> bool:
	return _entries.has(key)


func get_entry(key: String) -> Dictionary:
	if not _entries.has(key):
		return {}
	# 移至 LRU 尾部（最近使用）
	_lru_order.erase(key)
	_lru_order.append(key)
	return _entries[key]


func put_texture(key: String, texture: Texture2D, origin: Vector2i = Vector2i.ZERO) -> void:
	if texture == null:
		return
	var w := texture.get_width()
	var h := texture.get_height()
	var byte_est := maxi(4, w * h * 4)

	if _entries.has(key):
		var old: Dictionary = _entries[key]
		_used_bytes -= int(old["bytes"])
		_lru_order.erase(key)

	_entries[key] = {
		"texture": texture,
		"bytes": byte_est,
		"origin": origin,
	}
	_lru_order.append(key)
	_used_bytes += byte_est
	trim_to_limit(max_bytes)


func trim_to_limit(limit: int) -> int:
	var evicted := 0
	while _used_bytes > limit and not _lru_order.is_empty():
		var oldest_key: String = _lru_order.pop_front()
		if _entries.has(oldest_key):
			var info: Dictionary = _entries[oldest_key]
			_used_bytes -= int(info["bytes"])
			_entries.erase(oldest_key)
			evicted += 1
	_used_bytes = maxi(0, _used_bytes)
	return evicted


func on_low_memory() -> int:
	# 收到系统内存警告时直接收缩到 40% 配额
	return trim_to_limit(int(max_bytes * 0.4))


func clear() -> void:
	_entries.clear()
	_lru_order.clear()
	_used_bytes = 0
