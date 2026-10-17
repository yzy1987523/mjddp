class_name LvSkeleton
extends RefCounted

## 盒子骨架：位置与上下左右邻接关系固定，生成过程中不变。
## 对应文档 2.1 盒子 / 2.2 行分段 / 6.3 骨架与分段预处理。

class Box:
	## 唯一ID
	var id: String
	## 行号（层，0 = 最底层）
	var row: int
	## 行内网格横坐标
	var gx: int
	## 所有被它压住的下层盒子（空 = 落在地面）
	var under: Array = []
	## 压在它上面的盒子（由 under 反推，供阶段二判断「是否被压住」）
	var above: Array = []
	## 左侧盒子（同行 gx-1，不存在为 null）
	var left = null
	## 右侧盒子（同行 gx+1，不存在为 null）
	var right = null
	## 归属的行分段
	var segment = null
	## 源布局坐标（仅调试绘制用，普通骨架为 -1）
	var src_x: int = -1
	var src_y: int = -1
	var src_layer: int = -1

	func _init(p_id: String, p_row: int, p_gx: int) -> void:
		id = p_id
		row = p_row
		gx = p_gx


class Segment:
	## 全局分段序号
	var index: int
	## 所在行
	var row: int
	## 段内盒子（按 gx 升序）
	var boxes: Array = []

	func _init(p_index: int, p_row: int) -> void:
		index = p_index
		row = p_row


## 全部盒子
var boxes: Array = []
## 全部分段
var segments: Array = []
## id -> Box
var box_by_id: Dictionary = {}


## 从字典数据构建骨架。
## 数据格式：
## {
##   "boxes": [
##     {"id": "r0_0", "row": 0, "gx": 0},
##     {"id": "r1_0", "row": 1, "gx": 0, "under": ["r0_0", "r0_1"]}
##   ],
##   "under": { "r1_1": ["r0_1", "r0_2"] }   # 可选，与内联 under 合并
## }
static func from_data(data: Dictionary) -> LvSkeleton:
	var skel := LvSkeleton.new()
	skel._build(data)
	return skel


## 从 JSON 文件构建骨架
static func from_json_file(path: String) -> LvSkeleton:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("LvSkeleton: 无法打开骨架文件 %s" % path)
		return null
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("LvSkeleton: 骨架 JSON 解析失败 %s" % path)
		return null
	return from_data(parsed)


## 从麻将布局文件（data/MapData/mahjong-layout.json 格式）构建骨架。
## 约定：每个 tile 占 tileWidth×tileHeight 格；上层 tile 压在下层有重叠的 tile 上。
## 转换规则：
##   row  = layer * 100000 + y        （同一 (层,行) 视为同一条分段行）
##   gx   = x / tileWidth
##   under = 上一层与本 tile 在 x、y 两个方向重叠量均 >= 1 的 tile
static func from_mahjong_layout(path: String) -> LvSkeleton:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("LvSkeleton: 无法打开布局文件 %s" % path)
		return null
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("LvSkeleton: 布局 JSON 解析失败 %s" % path)
		return null

	var grid: Dictionary = data.get("grid", {})
	var tw: int = int(grid.get("tileWidth", 2))
	var th: int = int(grid.get("tileHeight", 2))
	var tiles: Array = data.get("tiles", [])

	var raw := []
	var by_layer := {}
	for t in tiles:
		var layer: int = int(t.get("layer", 0))
		var x: int = int(t.get("x", 0))
		var y: int = int(t.get("y", 0))
		var w: int = int(t.get("width", tw))
		var hh: int = int(t.get("height", th))
		var row: int = layer * 100000 + y
		var gx: int = x / tw
		raw.append({
			"id": str(t.get("id", "")),
			"row": row, "gx": gx,
			"src_x": x, "src_y": y, "src_layer": layer,
			"x": x, "y": y, "w": w, "h": hh, "layer": layer,
			"under": [],
		})
		by_layer[layer] = by_layer.get(layer, [])
		by_layer[layer].append(raw[-1])

	for b in raw:
		for u in by_layer.get(b["layer"] - 1, []):
			var ox := mini(b["x"] + b["w"], u["x"] + u["w"]) - maxi(b["x"], u["x"])
			var oy := mini(b["y"] + b["h"], u["y"] + u["h"]) - maxi(b["y"], u["y"])
			if ox >= 1 and oy >= 1:
				b["under"].append(u["id"])

	var out := {"boxes": []}
	for b in raw:
		out["boxes"].append({
			"id": b["id"], "row": b["row"], "gx": b["gx"],
			"src_x": b["src_x"], "src_y": b["src_y"], "src_layer": b["src_layer"],
			"under": b["under"],
		})
	return from_data(out)


func _build(data: Dictionary) -> void:
	var raw_boxes = data.get("boxes", [])
	var under_map := {}
	for rb in raw_boxes:
		var b := Box.new(str(rb.get("id", "")), int(rb.get("row", 0)), int(rb.get("gx", 0)))
		b.src_x = int(rb.get("src_x", -1))
		b.src_y = int(rb.get("src_y", -1))
		b.src_layer = int(rb.get("src_layer", -1))
		boxes.append(b)
		box_by_id[b.id] = b
		under_map[b.id] = rb.get("under", [])

	var top_under = data.get("under", {})
	for k in top_under:
		if under_map.has(k):
			under_map[k] = under_map[k] + top_under[k]

	for b in boxes:
		for uid in under_map[b.id]:
			var ub = box_by_id.get(str(uid))
			if ub == null:
				push_error("LvSkeleton: 盒子 %s 的 under 引用了不存在的盒子 %s" % [b.id, str(uid)])
				continue
			b.under.append(ub)

	for b in boxes:
		for u in b.under:
			u.above.append(b)

	_build_neighbors()
	_build_segments()


## 同行内 gx 相差 1 即互为左右邻居
func _build_neighbors() -> void:
	var by_row := {}
	for b in boxes:
		if not by_row.has(b.row):
			by_row[b.row] = {}
		by_row[b.row][b.gx] = b
	for b in boxes:
		var row_map: Dictionary = by_row[b.row]
		b.left = row_map.get(b.gx - 1)
		b.right = row_map.get(b.gx + 1)


## 按行分组、行内按 gx 排序；gx 连续则同段，遇空位切断
func _build_segments() -> void:
	var sorted := boxes.duplicate()
	sorted.sort_custom(func(a, b): return a.row < b.row or (a.row == b.row and a.gx < b.gx))

	var cur: Segment = null
	var prev = null
	for b in sorted:
		var continuous: bool = prev != null and prev.row == b.row and b.gx == prev.gx + 1
		if not continuous:
			cur = Segment.new(segments.size(), b.row)
			segments.append(cur)
		cur.boxes.append(b)
		b.segment = cur
		prev = b
