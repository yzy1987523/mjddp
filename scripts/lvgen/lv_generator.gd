class_name LvGenerator
extends RefCounted

## 关卡生成门面：骨架 -> [阶段一 WFC 占位] -> [阶段二 对子分配] -> 关卡数据。
## 冲突或牌数不合法时整局重跑，最多 max_retry 次。

## WFC 重试上限（骨架越紧越需要调高）
var max_retry: int = 50
## 塌缩时选择「放牌」的倾向 0~1
var card_bias: float = 0.9
## 目标牌数，0 = 尽量填满
var target_cards: int = 0
## 全填充模式：每个盒子都放牌（满盘布局用）。关掉则走 WFC 随机占位。
var fill_all: bool = false
## 少于该牌数视为失败，重跑
var min_cards: int = 2
## 可用牌型
var tile_types: Array = []


func _init() -> void:
	tile_types = default_tile_types()


## 默认牌型：万/条/筒各 9 种 + 字牌 7 种 = 34 种
static func default_tile_types() -> Array:
	var t := []
	for i in range(1, 10):
		t.append("m%d" % i)
	for i in range(1, 10):
		t.append("s%d" % i)
	for i in range(1, 10):
		t.append("p%d" % i)
	for i in range(1, 8):
		t.append("z%d" % i)
	return t


## p_seed >= 0 时用固定种子复现
func generate(skel: LvSkeleton, p_seed: int = -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if p_seed >= 0:
		rng.seed = p_seed
	else:
		rng.randomize()

	if tile_types.is_empty():
		tile_types = default_tile_types()

	if fill_all:
		# 满盘：直接取合法放置序（保证合法的三规则），跳过 WFC 随机塌缩
		var wfc := LvWfc.new(skel, rng)
		var r: Dictionary = wfc.run_fill_all()
		if not r.is_empty():
			var tiles := LvPairAssigner.assign(skel, r["placement"], tile_types, rng)
			if not tiles.is_empty():
				return _pack(skel, r["placement"], tiles, 1)

	for attempt in range(1, max_retry + 1):
		var wfc: LvWfc = LvWfc.new(skel, rng)
		wfc.card_bias = card_bias
		wfc.target_cards = target_cards

		var r: Dictionary = wfc.run_once()
		if r.is_empty():
			continue

		var placement: Array = r["placement"]
		if placement.size() < min_cards:
			continue

		var tiles: Dictionary = LvPairAssigner.assign(skel, placement, tile_types, rng)
		if tiles.is_empty():
			continue

		return _pack(skel, placement, tiles, attempt)

	return {
		"ok": false,
		"error": "WFC 重试 %d 次仍未生成合法关卡（骨架可能偏紧，可放宽约束或调高 max_retry）" % max_retry,
		"attempts": max_retry,
	}


## placement = 逆向放置顺序；solution = 其完全反转，即正向消除顺序
func _pack(skel: LvSkeleton, placement: Array, tiles: Dictionary, attempt: int) -> Dictionary:
	var cards := []
	for i in placement.size():
		var b = skel.box_by_id[placement[i]]
		cards.append({
			"id": b.id,
			"row": b.row,
			"gx": b.gx,
			"tile": tiles[b.id],
			"order": i,
		})

	var solution := placement.duplicate()
	solution.reverse()

	return {
		"ok": true,
		"attempts": attempt,
		"count": placement.size(),
		"placement": placement.duplicate(),
		"solution": solution,
		"tiles": tiles,
		"cards": cards,
	}
