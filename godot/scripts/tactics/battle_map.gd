extends RefCounted

## 24×24 固定战场。地形字符串由战斗规则解释：wall/water 不可通行，brush 移动消耗为 2。
const SIZE := Vector2i(24, 24)
const REGION_SIZE := Vector2i(8, 8)
const REGION_GRID := Vector2i(3, 3)
const ALLY_SPAWNS: Array[Vector2i] = [
	Vector2i(2, 10), Vector2i(2, 11), Vector2i(2, 12), Vector2i(2, 13),
]
const ENEMY_SPAWNS: Array[Vector2i] = [
	Vector2i(21, 10), Vector2i(21, 11), Vector2i(21, 12), Vector2i(21, 13),
	Vector2i(22, 10), Vector2i(22, 13),
]


static func create_regions() -> Array[Dictionary]:
	var regions: Array[Dictionary] = []
	for row in range(REGION_GRID.y):
		for col in range(REGION_GRID.x):
			var region_id := row * REGION_GRID.x + col
			regions.append({
				"id": region_id,
				"name": "R%d" % (region_id + 1),
				"rect": Rect2i(col * REGION_SIZE.x, row * REGION_SIZE.y, REGION_SIZE.x, REGION_SIZE.y),
				"owner": "neutral",
				"contested": false,
			})
	return regions


static func create_tiles() -> Dictionary:
	var tiles: Dictionary = {}
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			tiles[Vector2i(x, y)] = "ground"

	# 左右两翼的灌木区，留出道路和出生点周围的空地。
	_paint_rect(tiles, Rect2i(4, 2, 3, 5), "brush")
	_paint_rect(tiles, Rect2i(8, 1, 3, 4), "water")
	_paint_rect(tiles, Rect2i(12, 2, 2, 5), "brush")
	_paint_rect(tiles, Rect2i(3, 16, 4, 5), "brush")
	_paint_rect(tiles, Rect2i(8, 19, 4, 4), "water")
	_paint_rect(tiles, Rect2i(13, 16, 3, 5), "brush")

	# 墙体分隔主路与侧路，墙段之间保留可走的门洞，不形成封闭狭道。
	_paint_rect(tiles, Rect2i(7, 7, 1, 3), "wall")
	_paint_rect(tiles, Rect2i(7, 14, 1, 2), "wall")
	_paint_rect(tiles, Rect2i(14, 8, 1, 2), "wall")
	_paint_rect(tiles, Rect2i(14, 14, 1, 2), "wall")
	_paint_rect(tiles, Rect2i(10, 8, 2, 1), "wall")
	_paint_rect(tiles, Rect2i(10, 15, 2, 1), "wall")

	# 主路贯通全图，纵向支路连接各区域；出生格周围保持通畅。
	_paint_rect(tiles, Rect2i(0, 11, SIZE.x, 2), "road")
	_paint_rect(tiles, Rect2i(11, 5, 2, 14), "road")
	_paint_rect(tiles, Rect2i(2, 9, 2, 6), "road")
	_paint_rect(tiles, Rect2i(20, 4, 3, 5), "road")
	_paint_rect(tiles, Rect2i(20, 15, 3, 5), "road")
	_paint_rect(tiles, Rect2i(20, 9, 3, 6), "road")
	# 侧路接入中央主路，在上下两翼形成可选绕行路线。
	_paint_rect(tiles, Rect2i(5, 6, 8, 1), "road")
	_paint_rect(tiles, Rect2i(5, 17, 8, 1), "road")

	return tiles


static func _paint_rect(tiles: Dictionary, area: Rect2i, terrain: String) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			tiles[Vector2i(x, y)] = terrain
