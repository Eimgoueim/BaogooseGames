extends RefCounted

const Map = preload("res://scripts/tactics/battle_map.gd")
const Skills = preload("res://scripts/tactics/skill_catalog.gd")
const TARGET_SCORE := 30
const TURN_AP := 24
const DEFEND_COST := 2
const SOLDIER_HEALTH := 12
const SOLDIER_DAMAGE := 3
const SOLDIER_MOVE := 2
const SOLDIER_SIGHT := 4
const VICTORY_CREDITS := 60
const VICTORY_POINTS := 10
const VICTORY_EXPERIENCE := 20
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
# 仅战棋使用的参数，不修改养成配置。依次为生命、AI单次推进、视野、射程、伤害。
const PROFILES := {
	"dragon": [32, 5, 6, 1, 8], "goose": [26, 6, 6, 1, 9],
	"cat": [24, 7, 7, 1, 8], "whale": [36, 4, 6, 2, 8],
	"hoshino": [30, 5, 6, 3, 7], "gpt": [24, 5, 7, 4, 7],
	"claude": [26, 5, 6, 3, 8], "gemini": [24, 6, 6, 4, 7]
}

var tiles: Dictionary = {}
var units: Array[Dictionary] = []
var regions: Array[Dictionary] = []
var region_memory: Dictionary = {}
var enemy_region_memory: Dictionary = {}
var visible_cells: Dictionary = {}
var explored_cells: Dictionary = {}
var enemy_visible_cells: Dictionary = {}
var enemy_explored_cells: Dictionary = {}
var enemy_memory: Dictionary = {}
var last_seen_enemies: Dictionary = {}
var action_points := {"ally": TURN_AP, "enemy": TURN_AP}
var deploy_budget := {"ally": 1, "enemy": 1}
var phase := "player"
var round_number := 1
var score_ally := 0
var score_enemy := 0
var _enemy_order: Array[int] = []
var _enemy_finished: Dictionary = {}
var _enemy_cursor := 0
var _enemy_deployment_pending := false
var _reaction_order: Array[int] = []
var _next_soldier_id := 1000

func setup(pets: Array, _catalog: Dictionary) -> void:
	tiles = Map.create_tiles(); regions = Map.create_regions()
	units.clear(); region_memory.clear(); enemy_region_memory.clear()
	visible_cells.clear(); explored_cells.clear()
	enemy_visible_cells.clear(); enemy_explored_cells.clear()
	enemy_memory.clear(); last_seen_enemies.clear()
	phase = "player"; round_number = 1; score_ally = 0; score_enemy = 0
	action_points = {"ally": TURN_AP, "enemy": TURN_AP}
	deploy_budget = {"ally": 1, "enemy": 1}; _next_soldier_id = 1000
	_enemy_order.clear(); _enemy_finished.clear(); _enemy_cursor = 0
	_enemy_deployment_pending = false; _reaction_order.clear()
	var level_sum := 0
	for index in mini(pets.size(), 4):
		var pet: Dictionary = pets[index]
		level_sum += int(pet.get("level", 1))
		var unit := _make_unit(index, "ally", str(pet.get("species", "dragon")), str(pet.get("name", "宠物")), int(pet.get("level", 1)), Map.ALLY_SPAWNS[index])
		unit.pet_index = int(pet.get("pet_index", index)); units.append(unit)
	if units.is_empty(): phase = "lost"; return
	var average_level := maxi(1, roundi(float(level_sum) / units.size()))
	for index in mini(6, maxi(2, units.size() + 1)):
		var species: String = ["goose", "cat", "dragon", "gpt", "whale", "gemini"][index]
		var unit := _make_unit(100 + index, "enemy", species, "对手%d" % (index + 1), average_level, Map.ENEMY_SPAWNS[index])
		unit.hp = maxi(12, unit.hp - 8); unit.max_hp = unit.hp
		unit.damage = maxi(3, unit.damage - 2); units.append(unit)
	region_at(Map.ALLY_SPAWNS[0]).owner = "ally"
	region_at(Map.ENEMY_SPAWNS[0]).owner = "enemy"
	refresh_visibility()

func _make_unit(id: int, side: String, species: String, unit_name: String, level: int, cell: Vector2i) -> Dictionary:
	var profile: Array = PROFILES.get(species, PROFILES.dragon)
	var growth := clampi(level - 1, 0, 10)
	var health: int = int(profile[0]) + growth * 2
	return {"id": id, "kind": "pet", "side": side, "cell": cell, "name": unit_name, "species": species, "level": level, "hp": health, "max_hp": health, "move": int(profile[1]), "sight": int(profile[2]), "range": int(profile[3]), "damage": int(profile[4]) + growth / 3, "guard": false, "pet_index": -1, "skills": Skills.loadout_for(species), "charge": 0, "charge_max": Skills.CHARGE_MAX}

func get_unit(id: int) -> Dictionary:
	for unit in units:
		if unit.id == id: return unit
	return {}

func unit_at(cell: Vector2i) -> Dictionary:
	for unit in units:
		if unit.hp > 0 and unit.cell == cell: return unit
	return {}

func region_at(cell: Vector2i) -> Dictionary:
	for region in regions:
		if region.rect.has_point(cell): return region
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

func _regions_for(side: String) -> Dictionary:
	return region_memory if side == "ally" else enemy_region_memory

func _known_occupied(cell: Vector2i, side: String) -> bool:
	var occupant := unit_at(cell)
	return not occupant.is_empty() and (occupant.side == side or _sight_for(side).has(cell))

func _movement_search(unit: Dictionary, goal := Vector2i(-1, -1), unlimited := false) -> Dictionary:
	var origin: Vector2i = unit.cell
	var budget: int = 10000 if unlimited else (int(unit.move) if unit.get("kind", "pet") == "soldier" else int(action_points[unit.side]))
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
			# 未探索区按普通地面规划，避免高亮泄露隐藏地形和敌人。
			if known.has(next) and not _walkable(next): continue
			if next != origin and _known_occupied(next, unit.side): continue
			var cost: int = costs[current] + (2 if known.has(next) and tiles[next] == "brush" else 1)
			if cost > budget or (costs.has(next) and costs[next] <= cost): continue
			costs[next] = cost; parents[next] = current; pending.append(next)
	return {"costs": costs, "parents": parents}

func _can_act(unit: Dictionary) -> bool:
	return not unit.is_empty() and unit.hp > 0 and unit.get("kind", "pet") == "pet" and not has_pending_reactions() and phase == ("player" if unit.side == "ally" else "enemy")

func reachable_cells(id: int) -> Dictionary:
	var unit := get_unit(id)
	if not _can_act(unit) or int(action_points[unit.side]) <= 0: return {}
	return _movement_search(unit).costs

func movement_cost(id: int, destination: Vector2i) -> int:
	return int(reachable_cells(id).get(destination, -1))

func _route_to(unit: Dictionary, destination: Vector2i, search: Dictionary) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not search.costs.has(destination): return path
	var current := destination
	while current != unit.cell:
		path.push_front(current)
		if not search.parents.has(current): return []
		current = search.parents[current]
	return path

func path_to(id: int, destination: Vector2i) -> Array[Vector2i]:
	var unit := get_unit(id)
	if not _can_act(unit) or int(action_points[unit.side]) <= 0: return []
	return _route_to(unit, destination, _movement_search(unit))

func _walk_path(unit: Dictionary, path: Array[Vector2i], budget: int) -> Dictionary:
	var walked: Array[Vector2i] = []
	var spent := 0
	for next in path:
		var cost := 2 if tiles.get(next) == "brush" else 1
		if not _walkable(next) or not unit_at(next).is_empty() or spent + cost > budget: break
		unit.cell = next; spent += cost; walked.append(next)
		refresh_visibility()
	refresh_visibility()
	return {"ok": not walked.is_empty(), "path": walked, "cost": spent, "interrupted": walked.size() < path.size()}

func move_unit(id: int, destination: Vector2i) -> Dictionary:
	var unit := get_unit(id)
	if not _can_act(unit) or int(action_points[unit.side]) <= 0: return {"ok": false, "error": "当前无法移动", "path": []}
	var path := path_to(id, destination)
	if path.is_empty(): return {"ok": false, "error": "请选行动点足够的空格", "path": []}
	var result := _walk_path(unit, path, int(action_points[unit.side]))
	result["error"] = "前方受阻，请重新规划" if not result.ok else ("遭遇障碍，仅扣实际走过的点数" if result.interrupted else "")
	if result.ok:
		action_points[unit.side] -= int(result.cost); _queue_reactions(unit.side)
	return result

func _attack_check(unit: Dictionary, target_cell: Vector2i) -> Dictionary:
	var target := unit_at(target_cell)
	if target.is_empty() or target.side == unit.side or not _sight_for(unit.side).has(target_cell): return {"ok": false, "error": "请选择可见敌人"}
	if distance(unit.cell, target_cell) > unit.range: return {"ok": false, "error": "敌人在射程之外"}
	if not has_line_of_sight(unit.cell, target_cell): return {"ok": false, "error": "攻击路线被墙体遮挡"}
	return {"ok": true, "damage": maxi(1, int(unit.damage) - (3 if target.guard else 0))}

func skill_loadout(id: int) -> Array[Dictionary]:
	var unit := get_unit(id)
	var loadout: Array[Dictionary] = []
	if unit.is_empty() or unit.get("kind", "pet") != "pet": return loadout
	for skill_id: String in unit.get("skills", []):
		var skill := Skills.definition(skill_id)
		if not skill.is_empty(): loadout.append(skill)
	return loadout

func _learned_skill(unit: Dictionary, skill_id: String) -> Dictionary:
	if unit.is_empty() or skill_id not in unit.get("skills", []): return {}
	return Skills.definition(skill_id)

func skill_ready(id: int, skill_id: String) -> Dictionary:
	var unit := get_unit(id)
	if not _can_act(unit): return {"ok": false, "error": "当前无法释放技能"}
	var skill := _learned_skill(unit, skill_id)
	if skill.is_empty(): return {"ok": false, "error": "这只宠物没有该技能"}
	if int(action_points[unit.side]) < int(skill.cost): return {"ok": false, "error": "%s 需要 %d 行动点" % [skill.name, skill.cost]}
	if skill.kind == "ultimate" and int(unit.get("charge", 0)) < Skills.CHARGE_MAX: return {"ok": false, "error": "大招需要满 %d 格充能" % Skills.CHARGE_MAX}
	return {"ok": true, "skill": skill}

func skill_area(skill_id: String, center: Vector2i) -> Array[Vector2i]:
	var area: Array[Vector2i] = []
	var skill := Skills.definition(skill_id)
	if skill.is_empty() or not _inside(center): return area
	# 仅公开技能几何范围，不用未知墙体裁剪高亮，以免泄露迷雾地形。
	for y in range(center.y - int(skill.radius), center.y + int(skill.radius) + 1):
		for x in range(center.x - int(skill.radius), center.x + int(skill.radius) + 1):
			var cell := Vector2i(x, y)
			if _inside(cell) and distance(cell, center) <= int(skill.radius): area.append(cell)
	return area

func _skill_hits(unit: Dictionary, skill: Dictionary, center: Vector2i, visible_only: bool) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	for target in units:
		if target.hp <= 0 or target.side == unit.side or distance(target.cell, center) > int(skill.radius): continue
		if visible_only and not _sight_for(unit.side).has(target.cell): continue
		if not has_line_of_sight(center, target.cell) or not has_line_of_sight(unit.cell, target.cell): continue
		var damage := _skill_damage(unit, skill, target)
		hits.append({"id": target.id, "cell": target.cell, "name": target.name, "damage": damage, "defeated": int(target.hp) <= damage})
	return hits

func _skill_damage(unit: Dictionary, skill: Dictionary, target: Dictionary) -> int:
	return maxi(1, roundi(float(unit.damage) * float(skill.damage_scale)) - (3 if target.guard else 0))

func skill_preview(id: int, skill_id: String, target_cell: Vector2i) -> Dictionary:
	var ready := skill_ready(id, skill_id)
	if not ready.ok: return ready
	var unit := get_unit(id)
	var skill: Dictionary = ready.skill
	var target := unit_at(target_cell)
	if target.is_empty() or target.side == unit.side or not _sight_for(unit.side).has(target_cell): return {"ok": false, "error": "请选择可见敌人作为技能目标"}
	if distance(unit.cell, target_cell) > int(unit.range) + int(skill.range_bonus): return {"ok": false, "error": "目标在技能射程之外"}
	if not has_line_of_sight(unit.cell, target_cell): return {"ok": false, "error": "技能路线被墙体遮挡"}
	var hits := _skill_hits(unit, skill, target_cell, true)
	return {
		"ok": true, "skill_id": skill_id, "skill_name": skill.name, "cost": skill.cost,
		"hits": hits, "area": skill_area(skill_id, target_cell), "damage": _skill_damage(unit, skill, target), "target": target.name,
		"charge_gain": mini(Skills.NORMAL_CHARGE_GAIN, maxi(0, Skills.CHARGE_MAX - int(unit.get("charge", 0)))) if skill.kind == "normal" else 0,
		"charge_spent": Skills.ULTIMATE_CHARGE_COST if skill.kind == "ultimate" else 0
	}

func skill_targets(id: int, skill_id: String) -> Dictionary:
	var cells: Dictionary = {}
	if not skill_ready(id, skill_id).ok: return cells
	var unit := get_unit(id)
	for target in units:
		if target.hp > 0 and target.side != unit.side and _sight_for(unit.side).has(target.cell) and skill_preview(id, skill_id, target.cell).ok: cells[target.cell] = true
	return cells

func cast_skill(id: int, skill_id: String, target_cell: Vector2i) -> Dictionary:
	var result := skill_preview(id, skill_id, target_cell)
	if not result.ok: return result
	var unit := get_unit(id)
	var skill := _learned_skill(unit, skill_id)
	var sight_before := _sight_for(unit.side).duplicate()
	var actual_hits := _skill_hits(unit, skill, target_cell, false)
	var reported_hits: Array[Dictionary] = []
	action_points[unit.side] -= int(skill.cost)
	for hit in actual_hits:
		var target := get_unit(int(hit.id))
		target.hp = maxi(0, int(target.hp) - int(hit.damage))
		hit.defeated = target.hp == 0
		if sight_before.has(hit.cell): reported_hits.append(hit)
	unit.charge = 0 if skill.kind == "ultimate" else mini(Skills.CHARGE_MAX, int(unit.get("charge", 0)) + Skills.NORMAL_CHARGE_GAIN)
	result.hits = reported_hits
	result["defeated"] = unit_at(target_cell).is_empty()
	result["charge"] = unit.charge
	# 范围技能可伤及隐藏敌军，预览和战报仅返回施法前已见敌军，不能泄露数量或属性。
	refresh_visibility(); _check_elimination(); _queue_reactions(unit.side)
	return result

func _apply_attack(unit: Dictionary, target_cell: Vector2i, result: Dictionary) -> void:
	var target := unit_at(target_cell)
	target.hp = maxi(0, int(target.hp) - int(result.damage))
	result["target"] = target.name; result["defeated"] = target.hp == 0
	refresh_visibility(); _check_elimination()

func defend_unit(id: int) -> Dictionary:
	var unit := get_unit(id)
	if not _can_act(unit) or int(action_points[unit.side]) < DEFEND_COST or unit.guard: return {"ok": false, "error": "防御需要 %d 行动点，且不能重复防御" % DEFEND_COST}
	action_points[unit.side] -= DEFEND_COST; unit.guard = true; _queue_reactions(unit.side)
	return {"ok": true, "error": "", "cost": DEFEND_COST}

func deployment_cells(side: String) -> Dictionary:
	var cells: Dictionary = {}
	if side not in ["ally", "enemy"] or phase != ("player" if side == "ally" else "enemy") or has_pending_reactions() or int(deploy_budget[side]) <= 0: return cells
	for region in regions:
		if region.owner != side: continue
		for cell: Vector2i in _sight_for(side):
			if region.rect.has_point(cell) and _walkable(cell) and unit_at(cell).is_empty(): cells[cell] = true
	return cells

func deploy_soldier(side: String, cell: Vector2i) -> Dictionary:
	if not deployment_cells(side).has(cell): return {"ok": false, "error": "请在己方控制区域内的可见空地部署小兵"}
	var soldier := {"id": _next_soldier_id, "kind": "soldier", "side": side, "cell": cell, "name": "我方小兵" if side == "ally" else "敌方小兵", "species": "goose", "level": 1, "hp": SOLDIER_HEALTH, "max_hp": SOLDIER_HEALTH, "move": SOLDIER_MOVE, "sight": SOLDIER_SIGHT, "range": 1, "damage": SOLDIER_DAMAGE, "guard": false, "pet_index": -1}
	_next_soldier_id += 1; units.append(soldier); deploy_budget[side] -= 1
	refresh_visibility()
	return {"ok": true, "id": soldier.id, "error": ""}

func has_pending_reactions() -> bool:
	return not _reaction_order.is_empty()

func _queue_reactions(acting_side: String) -> void:
	if phase in ["won", "lost"]: return
	# 只响应宠物的成功指令；快照保证每只对方小兵恰好行动一次，不递归触发。
	for unit in units:
		if unit.get("kind", "pet") == "soldier" and unit.side != acting_side and unit.hp > 0: _reaction_order.append(unit.id)

func step_reaction() -> Dictionary:
	if not has_pending_reactions() or phase in ["won", "lost"]: return {"ok": false, "visible": false, "message": ""}
	var unit := get_unit(_reaction_order.pop_front())
	if unit.is_empty() or unit.hp <= 0: return {"ok": true, "visible": false, "message": "", "skipped": true}
	var result := _soldier_action(unit)
	result["reaction"] = true; result["actor_id"] = unit.id
	return result

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
	_update_memory("enemy", visible_cells, last_seen_enemies)
	_update_memory("ally", enemy_visible_cells, enemy_memory)
	_update_region_presence()
	_update_region_memory("ally"); _update_region_memory("enemy")

func _update_memory(target_side: String, sight: Dictionary, memory: Dictionary) -> void:
	for id in memory.keys():
		var record: Dictionary = memory[id]
		if sight.has(record.cell):
			var occupant := unit_at(record.cell)
			if occupant.is_empty() or occupant.id != id: memory.erase(id)
	for unit in units:
		if unit.side == target_side and unit.hp > 0 and sight.has(unit.cell): memory[unit.id] = {"cell": unit.cell, "round": round_number, "name": unit.name}

func _region_presence(region: Dictionary, sight: Dictionary = {}, observer := "") -> Dictionary:
	var presence := {"ally": false, "enemy": false}
	for unit in units:
		if unit.hp <= 0 or not region.rect.has_point(unit.cell): continue
		if not observer.is_empty() and unit.side != observer and not sight.has(unit.cell): continue
		presence[unit.side] = true
	return presence

func _update_region_presence() -> void:
	for region in regions:
		var presence := _region_presence(region)
		region.contested = presence.ally and presence.enemy

func _update_region_memory(side: String) -> void:
	var sight := _sight_for(side)
	var memory := _regions_for(side)
	for region in regions:
		var presence := _region_presence(region, sight, side)
		var center: Vector2i = region.rect.position + region.rect.size / 2
		# 区域中心或己方驻军提供归属信息；争夺提示只使用看见的敌人。
		if presence[side] or sight.has(center):
			memory[region.id] = {"owner": region.owner, "contested": presence.ally and presence.enemy}

func _resolve_regions() -> void:
	for region in regions:
		var presence := _region_presence(region)
		region.contested = presence.ally and presence.enemy
		if not region.contested:
			if presence.ally: region.owner = "ally"
			elif presence.enemy: region.owner = "enemy"

func _check_elimination() -> void:
	var allies := 0; var enemies := 0
	for unit in units:
		if unit.hp <= 0 or unit.get("kind", "pet") != "pet": continue
		if unit.side == "ally": allies += 1
		else: enemies += 1
	if allies == 0: phase = "lost"
	elif enemies == 0: phase = "won"
	if phase in ["won", "lost"]: _reaction_order.clear()

func end_player_turn() -> bool:
	if phase != "player" or has_pending_reactions(): return false
	phase = "enemy"; _enemy_cursor = 0; _enemy_order.clear(); _enemy_finished.clear()
	_enemy_deployment_pending = true; action_points.enemy = TURN_AP
	for unit in units:
		if unit.side == "enemy" and unit.hp > 0 and unit.get("kind", "pet") == "pet":
			unit.guard = false; _enemy_order.append(unit.id)
	return true

func _visible_targets(unit: Dictionary) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	for target in units:
		if target.side != unit.side and target.hp > 0 and _sight_for(unit.side).has(target.cell): targets.append(target)
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return distance(unit.cell, a.cell) < distance(unit.cell, b.cell))
	return targets

func _goal_for(unit: Dictionary, targets: Array[Dictionary]) -> Vector2i:
	if not targets.is_empty(): return targets[0].cell
	var memory := last_seen_enemies if unit.side == "ally" else enemy_memory
	var goal: Vector2i = unit.cell
	var closest := 10000
	for record: Dictionary in memory.values():
		var d := distance(unit.cell, record.cell)
		if d < closest: closest = d; goal = record.cell
	if closest < 10000: return goal
	var known_regions := _regions_for(unit.side)
	var here := region_at(unit.cell)
	if not here.is_empty() and known_regions.get(here.id, {}).get("owner", "neutral") != unit.side: return unit.cell
	for region in regions:
		if known_regions.get(region.id, {}).get("owner", "neutral") == unit.side: continue
		# 队友已进入的区域留给队友夺取，其他单位继续展开。
		if _region_presence(region, _sight_for(unit.side), unit.side)[unit.side]: continue
		var center: Vector2i = region.rect.position + region.rect.size / 2
		var d := distance(unit.cell, center)
		if d < closest: closest = d; goal = center
	return goal

func _advance_path(unit: Dictionary, goal: Vector2i, budget: int) -> Array[Vector2i]:
	if budget <= 0 or goal == unit.cell: return []
	var search := _movement_search(unit, Vector2i(-1, -1), true)
	var destination: Vector2i = unit.cell
	var best := distance(unit.cell, goal)
	for cell: Vector2i in search.costs:
		var metric := distance(cell, goal)
		if metric < best: best = metric; destination = cell
	var route := _route_to(unit, destination, search)
	var cost := 0
	var path: Array[Vector2i] = []
	for cell in route:
		cost += 2 if _known_for(unit.side).has(cell) and tiles[cell] == "brush" else 1
		if cost > budget: break
		path.append(cell)
	return path

func _soldier_action(unit: Dictionary) -> Dictionary:
	var seen_before: bool = unit.side == "ally" or visible_cells.has(unit.cell)
	var targets := _visible_targets(unit)
	for target in targets:
		var attack := _attack_check(unit, target.cell)
		if attack.ok:
			_apply_attack(unit, target.cell, attack)
			var observed: bool = seen_before or target.side == "ally"
			return {"ok": true, "action": "attack", "visible": observed, "message": "%s 响应攻击 %s，造成 %d 伤害" % [unit.name, target.name, attack.damage] if observed else ""}
	var path := _advance_path(unit, _goal_for(unit, targets), int(unit.move))
	if not path.is_empty():
		var result := _walk_path(unit, path, int(unit.move))
		var observed: bool = seen_before or visible_cells.has(unit.cell)
		return {"ok": true, "action": "move" if result.ok else "hold", "visible": observed, "message": "%s 自动推进" % unit.name if result.ok and observed else ("%s 守住区域" % unit.name if observed else "")}
	return {"ok": true, "action": "hold", "visible": seen_before, "message": "%s 守住区域" % unit.name if seen_before else ""}

func _deploy_enemy_soldier() -> Dictionary:
	var cells := deployment_cells("enemy")
	var chosen := Vector2i(-1, -1)
	var best := 10000
	for cell: Vector2i in cells:
		var d := distance(cell, Map.SIZE / 2)
		if d < best: best = d; chosen = cell
	return deploy_soldier("enemy", chosen) if chosen.x >= 0 else {"ok": false}

func step_enemy() -> Dictionary:
	if phase != "enemy": return {"ok": false, "error": "敌方回合尚未开始"}
	if has_pending_reactions(): return step_reaction()
	if _enemy_deployment_pending:
		var deployed := _deploy_enemy_soldier()
		if deployed.ok:
			var soldier := get_unit(deployed.id)
			var observed := visible_cells.has(soldier.cell)
			return {"ok": true, "action": "deploy", "visible": observed, "message": "敌方部署了小兵" if observed else ""}
		_enemy_deployment_pending = false
	if int(action_points.enemy) <= 0:
		_finish_round()
		return {"ok": true, "action": "round", "message": "区域已结算，新的回合开始", "visible": true}
	# 轮流给敌方宠物下指令，避免共享行动点被第一只宠物全部占用。
	var unit: Dictionary = {}
	for index in _enemy_order.size():
		var candidate := get_unit(_enemy_order[_enemy_cursor])
		_enemy_cursor = (_enemy_cursor + 1) % _enemy_order.size()
		if candidate.hp > 0 and not _enemy_finished.has(candidate.id): unit = candidate; break
	if unit.is_empty():
		_finish_round()
		return {"ok": true, "action": "round", "message": "区域已结算，新的回合开始", "visible": true}
	var seen_before := visible_cells.has(unit.cell)
	var targets := _visible_targets(unit)
	var chosen := _choose_enemy_skill(unit, targets)
	if not chosen.is_empty():
		var result := cast_skill(unit.id, chosen.skill_id, chosen.cell)
		return {"ok": true, "action": "skill", "skill_id": chosen.skill_id, "actor_id": unit.id, "message": "%s 释放 %s，命中 %d 个已见目标" % [unit.name, result.skill_name, result.hits.size()], "visible": true}
	var budget := mini(int(action_points.enemy), int(unit.move))
	var reserve := _cheapest_ready_skill(unit)
	if not targets.is_empty() and int(action_points.enemy) > reserve: budget = mini(budget, int(action_points.enemy) - reserve)
	var path := _advance_path(unit, _goal_for(unit, targets), budget)
	if not path.is_empty():
		var moved := move_unit(unit.id, path.back())
		if moved.ok:
			var observed := seen_before or visible_cells.has(unit.cell)
			return {"ok": true, "action": "move", "actor_id": unit.id, "message": "敌人移动，消耗 %d 点" % moved.cost if observed else "", "visible": observed}
	var defended := defend_unit(unit.id)
	_enemy_finished[unit.id] = true
	return {"ok": true, "action": "defend" if defended.ok else "wait", "actor_id": unit.id, "message": "敌人守住区域" if seen_before else "", "visible": seen_before}

func _cheapest_ready_skill(unit: Dictionary) -> int:
	var cost := TURN_AP
	for skill in skill_loadout(unit.id):
		if skill.kind != "ultimate" or int(unit.get("charge", 0)) >= Skills.CHARGE_MAX: cost = mini(cost, int(skill.cost))
	return cost

func _choose_enemy_skill(unit: Dictionary, targets: Array[Dictionary]) -> Dictionary:
	var chosen: Dictionary = {}
	var best := -1
	for skill in skill_loadout(unit.id):
		for target in targets:
			var preview := skill_preview(unit.id, skill.id, target.cell)
			if not preview.ok: continue
			# 只按预览中本方已见目标估值，隐藏敌军不能影响技能或目标选择。
			var value := 0
			for hit: Dictionary in preview.hits: value += int(hit.damage) + (20 if hit.defeated else 0)
			value = value * 10 / int(skill.cost) + (100 if skill.kind == "ultimate" else 0)
			if value > best: best = value; chosen = {"skill_id": skill.id, "cell": target.cell}
	return chosen

func _finish_round() -> void:
	_resolve_regions(); _check_elimination()
	if phase in ["won", "lost"]: return
	for region in regions:
		if region.contested: continue
		if region.owner == "ally": score_ally += 1
		elif region.owner == "enemy": score_enemy += 1
	# 同轮都达到目标时，分数较高者获胜；平分继续争夺。
	if score_ally >= TARGET_SCORE and score_ally > score_enemy: phase = "won"
	elif score_enemy >= TARGET_SCORE and score_enemy > score_ally: phase = "lost"
	else:
		phase = "player"; round_number += 1; action_points.ally = TURN_AP
		deploy_budget.ally += 1; deploy_budget.enemy += 1
		for unit in units:
			if unit.side == "ally" and unit.hp > 0 and unit.get("kind", "pet") == "pet": unit.guard = false
	refresh_visibility()
