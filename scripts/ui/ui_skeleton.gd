extends Control

## 点击按钮，按 data/MapData/mahjong-layout.json 生成由空白牌组成的骨架结构。
## 所有尺寸都来自 data/ui_config.json，改配置表即可调整牌大小 / 间距 / 层错位。
##
## 坐标规则：
##   - 底面位置取自 json 里 tile 真实的 (x, y)，每层天然内缩错位（金字塔）已包含其中
##   - 再叠加一个"深度抬升"（layer_dx 向右、layer_dy 向上），让叠放层次可见
##   - 最后按紧致包围盒归一化，并等比缩放到适配屏幕、上下左右精确居中

const TILE_SCENE := preload("res://scenes/tile_blank.tscn")
const LAYOUT_PATH := "res://data/MapData/mahjong-layout.json"
const CONFIG_PATH := "res://data/ui_config.json"

@onready var _btn: Button = $GenButton
@onready var _root: Control = $TilesRoot


func _ready() -> void:
	_btn.pressed.connect(_on_generate)


func _load_cfg() -> Dictionary:
	var cfg := {
		"fit_to_screen": true,
		"padding": 40.0,
		"zoom": 1.0,
		"tile_width": 56, "tile_height": 96,
		"face_width": 40, "face_height": 64,
		"shadow_x": 5, "shadow_y": 7,
		# 额外"深度抬升"：默认 0，让层间偏移完全来自布局数据本身（同心）
		# 想要立体错开的 3D 效果，可设成非 0（如 18 / 26）
		"layer_dx": 0, "layer_dy": 0,
		# 每层牌底颜色（俯视时上层遮下层，可看到 4 层同心台阶）
		"layer_colors": ["#6b8cff", "#57c785", "#f5c542", "#ef6f6c"],
	}
	var text := FileAccess.get_file_as_string(CONFIG_PATH)
	if not text.is_empty():
		var parsed = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			for k in parsed:
				cfg[k] = parsed[k]
	return cfg


func _size_child(inst: Control, node_name: String, px: float, py: float, w: float, h: float) -> void:
	var c := inst.get_node_or_null(node_name)
	if c is Control:
		c.position = Vector2(px, py)
		c.size = Vector2(w, h)


## "#rrggbb" -> Color（带兜底，解析失败返回浅蓝）
func _hex_to_color(s: String) -> Color:
	if s.begins_with("#"):
		s = s.substr(1)
	s = s.strip_edges()
	if s.length() == 6:
		var r := s.substr(0, 2).hex_to_int()
		var g := s.substr(2, 2).hex_to_int()
		var b := s.substr(4, 2).hex_to_int()
		return Color(r / 255.0, g / 255.0, b / 255.0, 1.0)
	return Color(0.42, 0.55, 1.0, 1.0)


func _on_generate() -> void:
	for c in _root.get_children():
		c.queue_free()

	var cfg := _load_cfg()
	# 注意：这里 tw/th 是"基准尺寸"，最终屏幕上会再乘 fit 缩放；zoom 用于在 fit 基础上再调
	var tw: float = float(cfg.get("tile_width", 56))
	var th: float = float(cfg.get("tile_height", 96))
	var ux: float = tw / 2.0          # json 中 1 个网格单元 = 半张牌宽
	var uy: float = th / 2.0
	var dx: float = float(cfg.get("layer_dx", 18))
	var dy: float = float(cfg.get("layer_dy", 26))
	var fsx: float = float(cfg.get("face_width", 40))
	var fsy: float = float(cfg.get("face_height", 64))
	var sox: float = float(cfg.get("shadow_x", 5))
	var soy: float = float(cfg.get("shadow_y", 7))

	# 每层牌底颜色
	var layer_cols: Array[Color] = []
	for c in cfg.get("layer_colors", []):
		if c is String:
			layer_cols.append(_hex_to_color(c))
	if layer_cols.is_empty():
		layer_cols = [Color(0.42, 0.55, 1.0), Color(0.34, 0.78, 0.52), Color(0.96, 0.77, 0.26), Color(0.94, 0.44, 0.42)]

	var text := FileAccess.get_file_as_string(LAYOUT_PATH)
	if text.is_empty():
		push_error("UISkeleton: 无法读取布局 %s" % LAYOUT_PATH)
		return
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("UISkeleton: 布局 JSON 解析失败")
		return

	var tiles: Array = data.get("tiles", [])
	tiles.sort_custom(func(a, b):
		return a["layer"] < b["layer"] or (a["layer"] == b["layer"] and (
			a["y"] < b["y"] or (a["y"] == b["y"] and a["x"] < b["x"]))))

	# 1) 原始位置：真实 x,y 底面 + 深度抬升；记最小角用于归一化
	var placed := []
	var min_x := INF
	var min_y := INF
	for t in tiles:
		var layer: int = int(t.get("layer", 0))
		var x: int = int(t.get("x", 0))
		var y: int = int(t.get("y", 0))
		var px: float = x * ux + layer * dx
		var py: float = y * uy - layer * dy
		min_x = min(min_x, px)
		min_y = min(min_y, py)
		placed.append({"t": t, "px": px, "py": py, "layer": layer})

	# 2) 归一化到 (0,0)，建实例（按 layer 升序加入 → 上层后画压在上面）
	var max_w := 0.0
	var max_h := 0.0
	for p in placed:
		var inst: Control = TILE_SCENE.instantiate()
		inst.custom_minimum_size = Vector2(tw, th)
		inst.size = Vector2(tw, th)
		_size_child(inst, "Shadow", sox, soy, tw, th)
		_size_child(inst, "Body", 0.0, 0.0, tw, th)
		_size_child(inst, "Background", 0.0, 0.0, tw, th)
		_size_child(inst, "Face", (tw - fsx) / 2.0, (th - fsy) / 2.0, fsx, fsy)
		_size_child(inst, "Label", 0.0, 0.0, tw, th)

		var body := inst.get_node_or_null("Body")
		if body is ColorRect:
			body.color = layer_cols[int(p["layer"]) % layer_cols.size()]

		var bx: float = p["px"] - min_x
		var by: float = p["py"] - min_y
		inst.position = Vector2(bx, by)

		var lbl: Label = inst.get_node_or_null("Label")
		if lbl != null:
			lbl.text = str(p["t"].get("id", ""))

		_root.add_child(inst)
		max_w = max(max_w, bx + tw)
		max_h = max(max_h, by + th)

	_root.size = Vector2(max_w, max_h)
	_root.custom_minimum_size = Vector2(max_w, max_h)

	# 3) 等比缩放到适配屏幕 + 精确居中（scale 以 TilesRoot 原点为基准，故直接按缩放后尺寸求位置）
	var vp := get_viewport_rect().size
	var pad: float = float(cfg.get("padding", 40.0))
	var zoom: float = float(cfg.get("zoom", 1.0))
	var s: float = zoom
	if bool(cfg.get("fit_to_screen", true)):
		var fit: float = min((vp.x - pad * 2.0) / max(max_w, 1.0), (vp.y - pad * 2.0) / max(max_h, 1.0))
		s = fit * zoom
	if s <= 0.0:
		s = 0.001

	_root.scale = Vector2(s, s)
	_root.position = Vector2((vp.x - max_w * s) * 0.5, (vp.y - max_h * s) * 0.5)

	print("[UISkeleton] 生成空白牌 %d 张  (包围盒 %.0fx%.0f, 缩放 %.3f, 视口 %.0fx%.0f)" % [
		tiles.size(), max_w, max_h, s, vp.x, vp.y])
