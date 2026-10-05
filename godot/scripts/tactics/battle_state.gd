extends RefCounted

const Map = preload("res://scripts/tactics/battle_map.gd")
const TARGET_SCORE := 6
const VICTORY_CREDITS := 60
const VICTORY_POINTS := 10
const VICTORY_EXPERIENCE := 20
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
# 仅战棋使用的初版参数，不修改养成配置。依次为生命、移动、视野、射程、伤害。
const PROFILES := {
	"dragon": [32, 5, 6, 1, 8], "goose": [26, 6, 6, 1, 9],
	"cat": [24, 7, 7, 1, 8], "whale": [36, 4, 6, 2, 8],
	"hoshino": [30, 5, 6, 3, 7], "gpt": [24, 5, 7, 4, 7],
	"claude": [26, 5, 6, 3, 8], "gemini": [24, 6, 6, 4, 7]
}

var tiles: Dictionary = {}
var units: Array[Dictionary] = []
var objectives: Array[Dictionary] = []
var visible_cells: Dictionary = {}
var explored_cells: Dictionary = {}
var enemy_visible_cells: Dictionary = {}
var enemy_explored_cells: Dictionary = {}
var enemy_memory: Dictionary = {}
var last_seen_enemies: Dictionary = {}
var enemy_objective_memory: Dictionary = {}
var phase := "player"
var round_number := 1
var score_ally := 0
var score_enemy := 0
var _enemy_order: Array[int] = []
var _enemy_cursor := 0

func setup(pets: Array, _catalog: Dictionary) -> void:
	tiles = Map.create_tiles()
	units.clear(); objectives.clear()
	visible_cells.clear(); explored_cells.clear()
	enemy_visible_cells.clear(); enemy_explored_cells.clear()
	enemy_memory.clear(); last_seen_enemies.clear(); enemy_objective_memory.clear()
	phase = "player"; round_number = 1; score_ally = 0; score_enemy = 0
	_enemy_order.clear(); _enemy_cursor = 0
	var level_sum := 0
	for index in mini(pets.size(), 4):
		var pet: Dictionary = pets[index]
		level_sum += int(pet.get("level", 1))
		var unit := _make_unit(index, "ally", str(pet.get("species", "dragon")), str(pet.get("name", "宠物")), int(pet.get("level", 1)), Map.ALLY_SPAWNS[index])
		unit.pet_index = int(pet.get("pet_index", index))
		units.append(unit)
	if units.is_empty(): phase = "lost"; return
	var average_level := maxi(1, roundi(float(level_sum) / units.size()))
	for index in mini(6, maxi(2, units.size() + 1)):
		var species: String = ["goose", "cat", "dragon", "gpt", "whale", "gemini"][index]
		var unit := _make_unit(100 + index, "enemy", species, "对手%d" % (index + 1), average_level, Map.ENEMY_SPAWNS[index])
		unit.hp = maxi(12, unit.hp - 8); unit.max_hp = unit.hp
		unit.damage = maxi(3, unit.damage - 2)
		units.append(unit)
	for cell in Map.OBJECTIVE_CELLS: objectives.append({"cell": cell, "owner": "neutral"})
	refresh_visibility()

func _make_unit(id: int, side: String, species: String, unit_name: String, level: int, cell: Vector2i) -> Dictionary:
	var profile: Array = PROFILES.get(species, PROFILES.dragon)
	var growth := clampi(level - 1, 0, 10)
	var health: int = int(profile[0]) + growth * 2
	return {"id": id, "side": side, "cell": cell, "name": unit_name, "species": species, "level": level, "hp": health, "max_hp": health, "ap": 2, "move": int(profile[1]), "sight": int(profile[2]), "range": int(profile[3]), "damage": int(profile[4]) + growth / 3, "guard": false, "pet_index": -1, "stride": 0}

func get_unit(id: int) -> Dictionary:
	for unit in units:
		if unit.id == id: return unit
	return {}

func unit_at(cell: Vector2i) -> Dictionary:
	for unit in units:
		if unit.hp > 0 and unit.cell == cell: return unit
	return {}

static func distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

func _inside(cell: Vector2i) -> bool:
	return tiles.has(cell)

func _walkable(cell: Vector2i) -> bool:
	return _inside(cell) and tiles[cell] not in ["wall", "water"]

func _sight_for(side: String) -> Dictionary:
	return visible_cells if side == "ally" else enemy_visible_cells

func _known_for(side: String) -> Dictionary:
	return explored_cells if side == "ally" else enemy_explored_cells

func _known_occupied(cell: Vector2i, side: String) -> bool:
	var occupant := unit_at(cell)
	return not occupant.is_empty() and (occupant.side == side or _sight_for(side).has(cell))

func _movement_search(unit: Dictionary, goal := Vector2i(-1, -1), unlimited := false) -> Dictionary:
	var origin: Vector2i = unit.cell
	var budget: int = 10000 if unlimited else (int(unit.get("stride", 0)) if int(unit.get("stride", 0)) > 0 else int(unit.move))
	var costs := {origin: 0}
	var parents: Dictionary = {}
	var pending: Array[Vector2i] = [origin]
	var known := _known_for(unit.side)
	while not pending.is_empty():
		pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return costs[a] < costs[b])
		var current: Vector2i = pending.pop_front()
		if current == goal: break
		for direction in DIRECTIONS:
			var next := current + direction
			if not _inside(next): continue
			# 未探索区按普通地面规划；不能通过移动高亮泄露墙体或隐藏敌人。
			if known.has(next) and not _walkable(next): continue
			if next != origin and _known_occupied(next, unit.side): continue
			var cost: int = costs[current] + (2 if known.has(next) and tiles[next] == "brush" else 1)
			if cost > budget or (costs.has(next) and costs[next] <= cost): continue
			costs[next] = cost; parents[next] = current; pending.append(next)
	return {"costs": costs, "parents": parents}

func reachable_cells(id: int) -> Dictionary:
	var unit := get_unit(id)
	if unit.is_empty() or unit.hp <= 0 or (unit.ap <= 0 and int(unit.get("stride", 0)) <= 0) or phase != ("player" if unit.side == "ally" else "enemy"): return {}
	return _movement_search(unit).costs

func path_to(id: int, destination: Vector2i) -> Array[Vector2i]:
	var unit := get_unit(id)
	var path: Array[Vector2i] = []
	if unit.is_empty(): return path
	var search := _movement_search(unit)
	if not search.costs.has(destination): return path
	var current := destination
	while current != unit.cell:
		path.push_front(current)
		if not search.parents.has(current): return []
		current = search.parents[current]
	return path

func _can_act(unit: Dictionary) -> bool:
	return not unit.is_empty() and unit.hp > 0 and phase == ("player" if unit.side == "ally" else "enemy")

func move_unit(id: int, destination: Vector2i) -> Dictionary:
	var unit := get_unit(id)
	if not _can_act(unit) or (unit.ap <= 0 and int(unit.get("stride", 0)) <= 0): return {"ok": false, "error": "当前无法移动", "path": []}
	var path := path_to(id, destination)
	if path.is_empty(): return {"ok": false, "error": "请选移动范围内的空格", "path": []}
	var continuation: bool = int(unit.get("stride", 0)) > 0
	var remaining: int = int(unit.stride) if continuation else int(unit.move)
	var walked: Array[Vector2i] = []
	var interrupted := false
	for next in path:
		var cost := 2 if tiles[next] == "brush" else 1
		if not _walkable(next) or not unit_at(next).is_empty() or cost > remaining:
			interrupted = true; break
		unit.cell = next; remaining -= cost; walked.append(next)
		refresh_visibility()
	if walked.is_empty():
		refresh_visibility()
		return {"ok": false, "error": "前方受阻，请重新规划", "path": []}
	if not continuation: unit.ap -= 1
	unit.stride = remaining if interrupted else 0
	_capture_objectives()
	return {"ok": true, "error": "遭遇障碍，剩余移动距离已保留" if interrupted else "", "path": walked}

func attack_preview(id: int, target_cell: Vector2i) -> Dictionary:
	var unit := get_unit(id)
	var target := unit_at(target_cell)
	if not _can_act(unit) or unit.ap <= 0: return {"ok": false, "error": "当前无法攻击"}
	if target.is_empty() or target.side == unit.side or not _sight_for(unit.side).has(target_cell): return {"ok": false, "error": "请选择可见敌人"}
	if distance(unit.cell, target_cell) > unit.range: return {"ok": false, "error": "敌人在射程之外"}
	if not has_line_of_sight(unit.cell, target_cell): return {"ok": false, "error": "攻击路线被墙体遮挡"}
	return {"ok": true, "damage": maxi(1, int(unit.damage) - (3 if target.guard else 0))}

func attack_unit(id: int, target_cell: Vector2i) -> Dictionary:
	var result := attack_preview(id, target_cell)
	if not result.ok: return result
	var unit := get_unit(id)
	var target := unit_at(target_cell)
	unit.ap -= 1; unit.stride = 0
	target.hp = maxi(0, int(target.hp) - int(result.damage))
	refresh_visibility(); _check_elimination()
	result["target"] = target.name; result["defeated"] = target.hp == 0
	return result

func defend_unit(id: int) -> Dictionary:
	var unit := get_unit(id)
	if not _can_act(unit) or unit.ap <= 0 or unit.guard: return {"ok": false, "error": "当前无法防御"}
	unit.ap -= 1; unit.guard = true; unit.stride = 0
	return {"ok": true, "error": ""}

func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	# 格子中心连线的保守遮挡：穿过墙角也算遮挡，避免隔角透视。
	var delta := to - from
	var steps := maxi(absi(delta.x), absi(delta.y)) * 4
	if steps == 0: return true
	var previous := from
	for index in range(1, steps + 1):
		var at := Vector2(from) + Vector2(0.5, 0.5) + Vector2(delta) * (float(index) / steps)
		var cell := Vector2i(floori(at.x), floori(at.y))
		if cell != previous and cell.x != previous.x and cell.y != previous.y:
			if tiles.get(Vector2i(cell.x, previous.y), "wall") == "wall" or tiles.get(Vector2i(previous.x, cell.y), "wall") == "wall": return false
		if cell != to and tiles.get(cell, "wall") == "wall": return false
		previous = cell
	return true

func refresh_visibility() -> void:
	visible_cells.clear(); enemy_visible_cells.clear()
	for unit in units:
		if unit.hp <= 0: continue
		var vision := _sight_for(unit.side)
		var known := _known_for(unit.side)
		var origin: Vector2i = unit.cell
		for y in range(maxi(0, origin.y - unit.sight), mini(Map.SIZE.y, origin.y + unit.sight + 1)):
			for x in range(maxi(0, origin.x - unit.sight), mini(Map.SIZE.x, origin.x + unit.sight + 1)):
				var cell := Vector2i(x, y)
				if distance(origin, cell) <= unit.sight and has_line_of_sight(origin, cell): vision[cell] = true; known[cell] = true
	# 记忆仅记录实际看到的位置；重新看见空格时清除过时记忆。
	_update_memory("enemy", visible_cells, last_seen_enemies)
	_update_memory("ally", enemy_visible_cells, enemy_memory)
	_update_objective_memory()

func _update_objective_memory() -> void:
	for objective in objectives:
		if enemy_visible_cells.has(objective.cell): enemy_objective_memory[objective.cell] = objective.owner

func _update_memory(target_side: String, sight: Dictionary, memory: Dictionary) -> void:
	for id in memory.keys():
		var record: Dictionary = memory[id]
		if sight.has(record.cell):
			var occupant := unit_at(record.cell)
			if occupant.is_empty() or occupant.id != id: memory.erase(id)
	for unit in units:
		if unit.side == target_side and unit.hp > 0 and sight.has(unit.cell): memory[unit.id] = {"cell": unit.cell, "round": round_number, "name": unit.name}

func _capture_objectives() -> void:
	for objective in objectives:
		var occupant := unit_at(objective.cell)
		if not occupant.is_empty(): objective.owner = occupant.side
	_update_objective_memory()

func _check_elimination() -> void:
	var allies := 0; var enemies := 0
	for unit in units:
		if unit.hp <= 0: continue
		if unit.side == "ally": allies += 1
		else: enemies += 1
	if allies == 0: phase = "lost"
	elif enemies == 0: phase = "won"

func end_player_turn() -> bool:
	if phase != "player": return false
	phase = "enemy"; _enemy_cursor = 0; _enemy_order.clear()
	for unit in units:
		if unit.side == "enemy" and unit.hp > 0:
			unit.ap = 2; unit.guard = false; unit.stride = 0; _enemy_order.append(unit.id)
	return true

func step_enemy() -> Dictionary:
	if phase != "enemy": return {"ok": false, "error": "敌方回合尚未开始"}
	if _enemy_cursor >= _enemy_order.size():
		_finish_round()
		return {"ok": true, "message": "新的回合开始", "visible": true}
	var unit := get_unit(_enemy_order[_enemy_cursor])
	if unit.hp <= 0 or unit.ap <= 0:
		_enemy_cursor += 1
		return {"ok": true, "message": "", "visible": false}
	var seen_before := visible_cells.has(unit.cell)
	var targets: Array[Dictionary] = []
	for target in units:
		if target.side == "ally" and target.hp > 0 and enemy_visible_cells.has(target.cell): targets.append(target)
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return distance(unit.cell, a.cell) < distance(unit.cell, b.cell))
	for target in targets:
		if attack_preview(unit.id, target.cell).ok:
			var result := attack_unit(unit.id, target.cell)
			return {"ok": true, "message": "%s 攻击 %s，造成 %d 伤害" % [unit.name, target.name, result.damage], "visible": true}
	var goal: Vector2i = unit.cell
	if not targets.is_empty(): goal = targets[0].cell
	elif not enemy_memory.is_empty():
		var closest := 10000
		for record: Dictionary in enemy_memory.values():
			var d := distance(unit.cell, record.cell)
			if d < closest: closest = d; goal = record.cell
	else:
		var closest := 10000
		for objective in objectives:
			if enemy_objective_memory.get(objective.cell, "neutral") == "enemy": continue
			var d := distance(unit.cell, objective.cell)
			if d < closest: closest = d; goal = objective.cell
	if goal == unit.cell:
		defend_unit(unit.id); unit.ap = 0
		return {"ok": true, "message": "敌人守住阵地" if seen_before else "", "visible": seen_before}
	# 选择朝目标推进的可达格；寻路只用敌方已探索地形和已看见的单位。
	var search := _movement_search(unit, Vector2i(-1, -1), true)
	var destination: Vector2i = unit.cell
	var best := 10000
	for cell: Vector2i in search.costs:
		var metric := distance(cell, goal)
		if metric < best: best = metric; destination = cell
	var route: Array[Vector2i] = []
	var current := destination
	while current != unit.cell and search.parents.has(current): route.push_front(current); current = search.parents[current]
	var cost := 0
	destination = unit.cell
	for cell in route:
		cost += 2 if enemy_explored_cells.has(cell) and tiles[cell] == "brush" else 1
		if cost > unit.move: break
		destination = cell
	var result := move_unit(unit.id, destination)
	if not result.ok: defend_unit(unit.id); unit.ap = 0
	return {"ok": true, "message": "敌人调整位置" if seen_before or visible_cells.has(unit.cell) else "", "visible": seen_before or visible_cells.has(unit.cell)}

func _finish_round() -> void:
	_capture_objectives(); _check_elimination()
	if phase in ["won", "lost"]: return
	for objective in objectives:
		if objective.owner == "ally": score_ally += 1
		elif objective.owner == "enemy": score_enemy += 1
	# 同轮都达到目标时，分数较高者获胜；平分继续争夺。
	if score_ally >= TARGET_SCORE and score_ally > score_enemy: phase = "won"
	elif score_enemy >= TARGET_SCORE and score_enemy > score_ally: phase = "lost"
	else:
		phase = "player"; round_number += 1
		for unit in units:
			if unit.side == "ally" and unit.hp > 0: unit.ap = 2; unit.guard = false; unit.stride = 0
	refresh_visibility()
