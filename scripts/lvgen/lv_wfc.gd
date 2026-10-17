class_name LvWfc
extends RefCounted

## 阶段一：WFC 生成合法占位（哪些盒子放牌）。
## 只决定盒子的状态 empty / hasCard，具体牌型交给阶段二。
## 三条放牌规则见文档第三节，同时生效，少一条都会导致关卡不可解。

const EMPTY := 0
const CARD := 1
const UNKNOWN := -1

var _skel: LvSkeleton
var _rng: RandomNumberGenerator

## 塌缩时选择「放牌」的倾向 0~1（1.0 = 尽量填满）
var card_bias: float = 0.9
## 目标牌数，0 = 不限
var target_cards: int = 0


func _init(skel: LvSkeleton, rng: RandomNumberGenerator) -> void:
	_skel = skel
	_rng = rng


## 全填充模式：固定满盘，不需要 WFC 随机塌缩。
## 直接按 (row, gx) 升序作为放置序——该序天然满足三规则（层升序保证支撑、
## 行内 gx 升序保证左右最多一侧、分段内紧贴），其反转即一条保证通关的消除序。
## 用于"每个物理格都必须放牌"的满盘布局（如麻将立体棋盘）。
func run_fill_all() -> Dictionary:
	var order := _skel.boxes.duplicate()
	order.sort_custom(func(a, b): return a.row < b.row or (a.row == b.row and a.gx < b.gx))
	var state := {}
	for b in _skel.boxes:
		state[b.id] = CARD
	var placement := []
	for b in order:
		placement.append(b.id)
	return {"state": state, "placement": placement}


## 跑完一整局。返回 {} 表示本轮作废（出现矛盾），由外层重试。
## 返回 { "state": {id: EMPTY/CARD}, "placement": [id...] }，placement 即逆向放置顺序。
func run_once() -> Dictionary:
	var state := {}
	var possible := {}
	for b in _skel.boxes:
		state[b.id] = UNKNOWN
		possible[b.id] = [EMPTY, CARD]

	var placement := []

	while true:
		if not _propagate(state, possible):
			return {}
		var target = _pick_cell(state, possible)
		if target == null:
			break
		var want_card: bool = _rng.randf() < card_bias
		if want_card and (target_cards <= 0 or placement.size() < target_cards):
			state[target.id] = CARD
			placement.append(target.id)
		else:
			state[target.id] = EMPTY

	for b in _skel.boxes:
		if state[b.id] == UNKNOWN:
			state[b.id] = EMPTY

	if placement.size() % 2 == 1:
		# 奇数张：丢弃「最后放上的」那张，其余仍是合法前缀
		var last = placement.pop_back()
		state[last] = EMPTY

	return {"state": state, "placement": placement}


## 约束传播：剔除在当前部分赋值下【绝对不可能】放牌的盒子。
## 注意这里只做「确定违规」的修剪（下方盒子已被判空 / 左右都已放牌），
## 规则3 依赖放置顺序，无法静态判定，只能在塌缩时用 _strict_can_place 把关。
func _propagate(state: Dictionary, possible: Dictionary) -> bool:
	var changed := true
	while changed:
		changed = false
		for b in _skel.boxes:
			if state[b.id] != UNKNOWN:
				continue
			var opts: Array = possible[b.id]
			if opts.has(CARD) and not _maybe_card(b, state):
				opts.erase(CARD)
				changed = true
			if opts.is_empty():
				return false
			if opts.size() == 1:
				# 只剩 empty：本盒永不可能放牌，直接塌缩
				state[b.id] = opts[0]
				changed = true
	return true


## 规则1（确定版）：任一被压住的下层盒子已确定为空 -> 永远不能放牌
## 规则2（确定版）：左右都已确定放牌 -> 永远不能放牌
func _maybe_card(b, state: Dictionary) -> bool:
	for u in b.under:
		if state[u.id] == EMPTY:
			return false
	if b.left != null and state[b.left.id] == CARD and b.right != null and state[b.right.id] == CARD:
		return false
	return true


## 三条规则合体（严格版）：未塌缩的盒子一律视为「还没放牌」
func _strict_can_place(b, state: Dictionary) -> bool:
	# 规则1 底部支撑：下方是地面，或所有被压住的下层盒子都已放牌
	for u in b.under:
		if state[u.id] != CARD:
			return false

	# 规则2 左右约束：左右最多只能有一侧有牌
	var lh: bool = b.left != null and state[b.left.id] == CARD
	var rh: bool = b.right != null and state[b.right.id] == CARD
	if lh and rh:
		return false

	# 规则3 分段生长：分段内已有牌时，新牌必须紧贴段内已有牌（同分段左右相邻）
	var seg_has := false
	for sb in b.segment.boxes:
		if state[sb.id] == CARD:
			seg_has = true
			break
	if seg_has and not (lh or rh):
		return false

	return true


## 选下一个塌缩的盒子：
## 1) 熵最低（可选状态最少）优先 —— WFC 核心，提前啃硬骨头
## 2) 同熵下优先「一侧已有牌」的盒子 —— 文档规则2 的候选优先级
## 3) 仍并列则随机
## 只从「当前时刻严格可放牌」的盒子里挑，保证塌缩顺序 == 合法放置顺序。
func _pick_cell(state: Dictionary, possible: Dictionary):
	var best := []
	var best_score := 1 << 30
	for b in _skel.boxes:
		if state[b.id] != UNKNOWN:
			continue
		if not possible[b.id].has(CARD):
			continue
		if not _strict_can_place(b, state):
			continue

		var lh: bool = b.left != null and state[b.left.id] == CARD
		var rh: bool = b.right != null and state[b.right.id] == CARD
		var side_score: int = 0 if (lh or rh) else 1
		var score: int = (possible[b.id].size() - 1) * 10 + side_score

		if score < best_score:
			best_score = score
			best = [b]
		elif score == best_score:
			best.append(b)

	if best.is_empty():
		return null
	return best[_rng.randi() % best.size()]
