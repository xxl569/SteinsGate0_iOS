class_name MgsVideoPlayer
extends CanvasLayer
## 全屏 Theora (.ogv) 过场动画播放器（支持触控点击跳过与防误触防抖）

signal movie_finished(movie_idx: int, skipped: bool)

const SKIP_DEBOUNCE_SEC := 0.35

var _vfs: MgsVfs = null
var _vm: Sc3Vm = null
var _backdrop: ColorRect = null
var _player: VideoStreamPlayer = null
var _hint_label: Label = null

var _is_playing: bool = false
var _current_movie_idx: int = -1
var _play_elapsed: float = 0.0


func _ready() -> void:
	layer = 90
	visible = false
	_ensure_ui()


func _ensure_ui() -> void:
	if _backdrop != null:
		return
	_backdrop = ColorRect.new()
	_backdrop.name = "MovieBackdrop"
	_backdrop.color = Color.BLACK
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_backdrop)

	_player = VideoStreamPlayer.new()
	_player.name = "TheoraPlayer"
	_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player.expand = true
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player.finished.connect(_on_video_finished)
	_backdrop.add_child(_player)

	_hint_label = Label.new()
	_hint_label.name = "SkipHint"
	_hint_label.text = "点击屏幕跳过动画"
	_hint_label.modulate = Color(1, 1, 1, 0.55)
	_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint_label.offset_left = -260
	_hint_label.offset_top = -54
	_hint_label.offset_right = -24
	_hint_label.offset_bottom = -18
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_backdrop.add_child(_hint_label)


func bind_vfs(vfs: MgsVfs) -> void:
	_vfs = vfs
	_ensure_ui()


func bind_vm(vm: Sc3Vm) -> void:
	_vm = vm
	if _vm != null and not _vm.movie_play_requested.is_connected(play_movie):
		_vm.movie_play_requested.connect(play_movie)


func _process(delta: float) -> void:
	if _is_playing:
		_play_elapsed += delta
		if _hint_label != null:
			_hint_label.visible = _play_elapsed >= SKIP_DEBOUNCE_SEC


func play_movie(movie_idx: int) -> bool:
	_ensure_ui()
	var path := ""
	if _vfs != null:
		path = _vfs.get_movie_path_by_index(movie_idx)
	return play_movie_file(path, movie_idx)


func play_movie_by_stem(stem: String) -> bool:
	_ensure_ui()
	var path := ""
	if _vfs != null:
		path = _vfs.find_movie_path(stem)
	return play_movie_file(path, -1)


func play_movie_file(ogv_path: String, movie_idx: int = -1) -> bool:
	_ensure_ui()
	if ogv_path == "" or not FileAccess.file_exists(ogv_path):
		push_warning("过场视频不存在，跳过播放: idx=%d path=%s" % [movie_idx, ogv_path])
		_finish_internal(true)
		return false

	var stream := VideoStreamTheora.new()
	stream.file = ogv_path
	_player.stop()
	_player.stream = stream
	_current_movie_idx = movie_idx
	_play_elapsed = 0.0
	_is_playing = true
	visible = true
	_player.play()
	return true


func stop_movie(skipped: bool = true) -> void:
	if not _is_playing:
		return
	if _player != null:
		_player.stop()
	_finish_internal(skipped)


func is_movie_playing() -> bool:
	return _is_playing


func _on_backdrop_input(event: InputEvent) -> void:
	if not _is_playing or _play_elapsed < SKIP_DEBOUNCE_SEC:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		stop_movie(true)
	elif event is InputEventScreenTouch and event.pressed:
		stop_movie(true)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_playing or _play_elapsed < SKIP_DEBOUNCE_SEC:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
		stop_movie(true)


func _on_video_finished() -> void:
	if _is_playing:
		_finish_internal(false)


func _finish_internal(skipped: bool) -> void:
	var idx := _current_movie_idx
	_is_playing = false
	_current_movie_idx = -1
	visible = false
	if _vm != null:
		_vm.notify_movie_finished()
	movie_finished.emit(idx, skipped)
