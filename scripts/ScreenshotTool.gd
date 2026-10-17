extends Node

## 截图工具（autoload）：监听请求标志文件，由外部（AI 的 PowerShell 脚本）触发截图。
## 请求标志： <项目>/screenshots/.request  （内容可写自定义保存路径，留空用默认时间戳路径）
## 完成标志： <项目>/screenshots/.done    （内容为实际保存的 png 路径）
## 也可手动按 F12 立即截图（默认路径）。

const BASE_DIR := "c:/Custom/MyGames/mjddp/screenshots/"
const REQ := BASE_DIR + ".request"
const DONE := BASE_DIR + ".done"

var _busy := false


func _ready() -> void:
	_ensure_dir(BASE_DIR)


func _ensure_dir(path: String) -> void:
	var base := path.trim_suffix("/")
	var parent := base.get_base_dir()
	var name := base.get_file()
	var da := DirAccess.open(parent)
	if da != null:
		da.make_dir_recursive(name)


func _process(_delta: float) -> void:
	if _busy:
		return
	if FileAccess.file_exists(REQ):
		_busy = true
		_take()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			_busy = true
			_take()


func _take():
	await get_tree().process_frame
	_capture()


func _capture():
	var path := _read_request_path()
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(path)
		print("ScreenshotTool: saved -> " + path)
	else:
		print("ScreenshotTool: failed to get viewport image")
		path = ""
	_write_done(path)
	DirAccess.remove_absolute(REQ)
	_busy = false


func _read_request_path() -> String:
	var p := ""
	if FileAccess.file_exists(REQ):
		var f := FileAccess.open(REQ, FileAccess.READ)
		if f:
			p = f.get_as_text().strip_edges()
			f.close()
	if p == "":
		var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
		p = BASE_DIR + "shot_" + stamp + ".png"
	return p


func _write_done(p: String) -> void:
	var f := FileAccess.open(DONE, FileAccess.WRITE)
	if f:
		f.store_string(p)
		f.close()
