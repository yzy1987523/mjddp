extends Node

const SAVE_PATH := "user://window_save.cfg"
var _config := ConfigFile.new()


func _ready() -> void:
	var window := get_window()
	_restore(window)
	# 窗口尺寸/位置变化时实时保存，保证下次 F6 恢复
	window.size_changed.connect(_save)
	if window.has_signal("window_moved"):
		window.window_moved.connect(_save)


func _restore(window: Window) -> void:
	if _config.load(SAVE_PATH) != OK:
		return
	var size: Vector2i = _config.get_value("window", "size", Vector2i.ZERO)
	var pos: Vector2i = _config.get_value("window", "position", Vector2i.ZERO)
	if size != Vector2i.ZERO:
		window.size = size
	if pos != Vector2i.ZERO:
		window.position = pos


func _save(_arg = null) -> void:
	var window := get_window()
	_config.set_value("window", "size", window.size)
	_config.set_value("window", "position", window.position)
	_config.save(SAVE_PATH)
