class_name LvPairAssigner
extends RefCounted

## 阶段二：成对卡牌分配 —— 往阶段一给出的 hasCard 盒子里放对子。
##
## 【注意：这里不能用「洗牌后随机发牌」，虽然文档 5-阶段二 是这么写的】
## 实测 500 局：随机洗牌配对后只有 7% 的关卡能通关。原因：
##   逆向构造保证的是【单张】的解锁序 r0,r1,...,rn-1（ri 在 r0..ri-1 都移除后才自由），
##   但真实消除必须【两张同时自由】才能消一对。
##   若 ri 正好压着 ri+1，这两张永远无法同时自由 —— 随机配对必然撞上这种组合。
## 正确做法：按 WFC 的逆序（= 消除序）模拟消除，
##   每一轮取「解锁序中最早的两张自由牌」配成同一牌型，成对发牌。
## 实测同一批布局：通关率 100%（bias=1.0） / 99%（bias=0.9，残余 1% 由外层重跑兜底）。
##
## 副作用：牌型分配不再随机，而是由消除序决定 —— 这正是可解性的来源。


static func assign(skel: LvSkeleton, placement: Array, tile_types: Array, rng: RandomNumberGenerator) -> Dictionary:
	if placement.size() % 2 != 0:
		push_error("LvPairAssigner: 放牌盒子数为奇数（%d），无法成对" % placement.size())
		return {}
	if tile_types.is_empty():
		push_error("LvPairAssigner: 牌型列表为空")
		return {}

	# rank: 消除序号，越小越早解锁（placement 的完全反转）
	var rank := {}
	for i in placement.size():
		rank[placement[i]] = placement.size() - 1 - i

	var remaining := {}
	for id in placement:
		remaining[id] = true

	var pool := tile_types.duplicate()
	_shuffle(pool, rng)

	var tiles := {}
	var type_index := 0
	while not remaining.is_empty():
		var free := []
		for id in remaining:
			var b = skel.box_by_id[id]
			if _is_free(b, remaining):
				free.append(b)

		if free.size() < 2:
			# 自由牌不足两张 = 死局，交给外层重跑
			return {}

		free.sort_custom(func(x, y): return rank[x.id] < rank[y.id])

		var t = pool[type_index % pool.size()]
		type_index += 1
		tiles[free[0].id] = t
		tiles[free[1].id] = t
		remaining.erase(free[0].id)
		remaining.erase(free[1].id)

	return tiles


## 自由 = 上面没被压住，且左右不同时有牌
static func _is_free(b, remaining: Dictionary) -> bool:
	for a in b.above:
		if remaining.has(a.id):
			return false
	var lh: bool = b.left != null and remaining.has(b.left.id)
	var rh: bool = b.right != null and remaining.has(b.right.id)
	return not (lh and rh)


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
