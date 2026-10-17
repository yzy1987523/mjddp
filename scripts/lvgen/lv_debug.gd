extends Node2D

## 关卡生成器调试场景：跑一次生成，把占位与牌型画出来。
## 灰框 = 空盒子；米色框 = 放牌（上行为牌型，下行为放置序号 #0 起）。
## 按 R / 空格 / 鼠标左键 = 换个随机种子重新生成。

const SKELETON_PATH := "res://data/MapData/mahjong-layout.json"

const CELL := 13.0
const GAP := 1.0
const LAYER_DY := 22.0

var _skel: LvSkeleton
var _level: Dictionary = {}


func _ready() -> void:
	_skel = LvSkeleton.from_mahjong_layout(SKELETON_PATH)
	if _skel == null:
		return
	_regenerate(20261017)


func _input(event: InputEvent) -> void:
	var go: bool = false
	if event is InputEventKey and event.pressed and not event.echo:
		go = event.keycode == KEY_R or event.keycode == KEY_SPACE
	elif event is InputEventMouseButton and event.pressed:
		go = true
	if go:
		_regenerate(-1)


func _regenerate(p_seed: int) -> void:
	var gen := LvGenerator.new()
	gen.fill_all = true
	_level = gen.generate(_skel, p_seed)
	if not _level.get("ok", false):
		push_error("LvGenDebug: 生成失败 -> %s" % _level.get("error", ""))
		queue_redraw()
		return

	print("[LvGen] 盒子 %d / 放牌 %d / 重试 %d 次" % [_skel.boxes.size(), _level["count"], _level["attempts"]])
	print("[LvGen] 放置顺序(部分) %s" % str(_level["placement"].slice(0, 12)))
	print("[LvGen] 消除顺序(部分) %s" % str(_level["solution"].slice(0, 12)))
	queue_redraw()


func _draw() -> void:
	if _skel == null or not _level.get("ok", false):
		return

	var tiles: Dictionary = _level["tiles"]
	var order_by_id := {}
	for i in _level["placement"].size():
		order_by_id[_level["placement"][i]] = i

	var font := ThemeDB.fallback_font

	for b in _skel.boxes:
		var px: float
		var py: float
		if b.src_layer >= 0:
			px = 30.0 + b.src_x * (CELL + GAP)
			py = 30.0 + b.src_y * (CELL + GAP) + b.src_layer * LAYER_DY
		else:
			px = 60.0 + b.gx * (CELL + GAP)
			py = 560.0 - b.row * 12.0

		var rect := Rect2(px, py, CELL, CELL)
		if tiles.has(b.id):
			draw_rect(rect, Color(0.94, 0.91, 0.81))
			draw_rect(rect, Color(0.27, 0.24, 0.19), false, 1.0)
			draw_string(font, rect.position + Vector2(1, CELL - 3), str(tiles[b.id]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.16, 0.13, 0.10))
		else:
			draw_rect(rect, Color(0.30, 0.33, 0.38, 0.30))
