extends SceneTree

const BattleState = preload("res://scripts/tactics/battle_state.gd")

var failures := 0
var catalog: Dictionary

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("失败：" + message)

func _load_catalog() -> Dictionary:
	var file := FileAccess.open("res://data/catalog.json", FileAccess.READ)
	return JSON.parse_string(file.get_as_text()) as Dictionary

func _new_battle(pet_count: int = 2) -> RefCounted:
	var save_pets: Array = []
	for i in range(pet_count):
		save_pets.append({"species":"goose", "name":"测试鹅%d" % i, "health":100, "energy":75, "level":1})
	var battle = BattleState.new()
	battle.setup(save_pets, catalog)
	return battle

func _side_units(battle: Variant, side: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for unit: Dictionary in battle.units:
		if str(unit.side) == side:
			found.append(unit)
	return found

func _unit(battle: Variant, side: String, index: int = 0) -> Dictionary:
	var found := _side_units(battle, side)
	return found[index] if index < found.size() else {}

func _ground(battle: Variant) -> void:
	for cell: Vector2i in battle.tiles:
		battle.tiles[cell] = "ground"

func _put(unit: Dictionary, cell: Vector2i) -> void:
	unit.cell = cell

func _run() -> void:
	catalog = _load_catalog()
	_test_setup_copies_pets()
	_test_map_and_movement()
	_test_combat_and_visibility()
	_test_enemy_turn_visibility()
	_test_enemy_does_not_know_hidden_ally_positions()
	_test_fog_does_not_leak_terrain()
	_test_objectives_scoring_and_terminal()
	if failures == 0:
		print("战术战斗状态、地图、视野、回合与胜负测试通过")
	else:
		printerr("战术测试失败：%d 项" % failures)
	quit(0 if failures == 0 else 1)

func _test_setup_copies_pets() -> void:
	var pets: Array = [
		{"species":"goose", "name":"包鹅", "health":63, "energy":42, "level":7, "custom":"保留原档"},
		{"species":"cat", "name":"咪咪", "health":88, "energy":90, "level":3},
		{"species":"dragon", "name":"团子", "health":100, "energy":80, "level":2},
		{"species":"whale", "name":"大肥鱼", "health":75, "energy":50, "level":5},
		{"species":"goose", "name":"第五只", "health":100, "energy":100, "level":1},
	]
	var before := pets.duplicate(true)
	var battle := BattleState.new()
	battle.setup(pets, catalog)
	_check(_side_units(battle, "ally").size() == 4, "只从存档复制最多四只宠物进入战斗")
	_check(pets == before, "战斗初始化不得改动存档中的宠物数据")
	if not battle.units.is_empty():
		battle.units[0].hp = 1
		_check(pets[0].health == 63 and pets[0].custom == "保留原档", "战斗单位修改不应回写宠物原档")

func _test_map_and_movement() -> void:
	var battle := _new_battle()
	var ally := _unit(battle, "ally")
	var enemy := _unit(battle, "enemy")
	_check(not ally.is_empty() and not enemy.is_empty(), "战场应为双方生成单位")
	_check(battle.tiles.size() == 24 * 24, "固定地图应有 24×24 个格子")
	var reached := {ally.cell:true}
	var queue: Array[Vector2i] = [ally.cell]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for offset: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next := cell + offset
			if battle.tiles.has(next) and not ["wall", "water"].has(battle.tiles[next]) and not reached.has(next):
				reached[next] = true
				queue.append(next)
	_check(reached.has(enemy.cell), "地图的可通行地形应让双方出生区域连通")

	_ground(battle)
	ally = _unit(battle, "ally")
	for cell: Vector2i in battle.tiles:
		battle.tiles[cell] = "wall"
	for cell: Vector2i in [ally.cell, ally.cell + Vector2i.RIGHT, ally.cell + Vector2i(2, 0), ally.cell + Vector2i(3, 0)]:
		if battle.tiles.has(cell): battle.tiles[cell] = "ground"
	battle.tiles[ally.cell + Vector2i.RIGHT] = "brush"
	var options: Dictionary = battle.reachable_cells(int(ally.id))
	_check(options.get(ally.cell + Vector2i(2, 0), -1) == 3, "经灌木两格的路径成本应为 3")
	var move_result: Dictionary = battle.move_unit(int(ally.id), ally.cell + Vector2i.RIGHT)
	_check(move_result.get("ok", false), "有足够移动预算时应能进入灌木")
	_check(ally.ap == 1, "移动行动应消耗 1 点行动力")
	battle.tiles[ally.cell + Vector2i.RIGHT] = "wall"
	var blocked: Dictionary = battle.move_unit(int(ally.id), ally.cell + Vector2i.RIGHT)
	_check(not blocked.get("ok", false), "墙体目的地应拒绝移动")
	ally.ap = 0
	var no_ap: Dictionary = battle.move_unit(int(ally.id), ally.cell + Vector2i(2, 0))
	_check(not no_ap.get("ok", false), "没有行动力时应拒绝移动")

func _test_combat_and_visibility() -> void:
	var battle := _new_battle()
	_ground(battle)
	var ally := _unit(battle, "ally")
	var enemy := _unit(battle, "enemy")
	_put(ally, Vector2i(5, 5))
	_put(enemy, Vector2i(6, 5))
	battle.refresh_visibility()
	var hp: int = enemy.hp
	var attack: Dictionary = battle.attack_unit(int(ally.id), enemy.cell)
	_check(attack.get("ok", false) and enemy.hp < hp, "视野与射程内的敌人应受到攻击")
	_check(ally.ap == 1, "攻击应消耗 1 点行动力")
	var too_far: Dictionary = battle.attack_unit(int(ally.id), Vector2i(20, 20))
	_check(not too_far.get("ok", false), "超出射程的攻击应拒绝")

	var hidden := _new_battle()
	_ground(hidden)
	var scout := _unit(hidden, "ally")
	var unseen := _unit(hidden, "enemy")
	_put(scout, Vector2i(1, 1))
	_put(unseen, Vector2i(20, 20))
	hidden.refresh_visibility()
	_check(not hidden.visible_cells.has(unseen.cell), "远处敌人应保持隐藏")
	var hidden_attack: Dictionary = hidden.attack_unit(int(scout.id), unseen.cell)
	_check(not hidden_attack.get("ok", false), "攻击者不能对非可见敌人发起攻击")
	var options: Dictionary = hidden.reachable_cells(int(scout.id))
	_check(not options.has(unseen.cell), "移动范围数据不能泄露隐藏敌人的格子")
	# 寻路只知道迷雾中的地形；移动时碰到未发现的敌人应停在其前方。
	scout.sight = 1
	_put(scout, Vector2i(1, 1))
	_put(unseen, Vector2i(5, 1))
	hidden.refresh_visibility()
	var interrupted: Dictionary = hidden.move_unit(int(scout.id), Vector2i(7, 1))
	_check(interrupted.get("ok", false) and scout.cell == Vector2i(4, 1), "接触隐藏敌人时移动应在敌人前中断")
	_check(scout.stride > 0 and scout.ap == 1, "遇隐藏障碍后应保留剩余移动距离并只消耗一次行动力")

	_put(scout, Vector2i(3, 3))
	_put(unseen, Vector2i(5, 3))
	hidden.tiles[Vector2i(4, 3)] = "wall"
	hidden.refresh_visibility()
	_check(not hidden.visible_cells.has(unseen.cell), "墙体应遮断单位视线")
	_check(hidden.explored_cells.has(Vector2i(3, 3)), "己方视野应记录探索记忆")
	_put(unseen, Vector2i(8, 8))
	hidden.refresh_visibility()
	_check(hidden.explored_cells.has(Vector2i(3, 3)), "离开视野后探索记忆仍应保留")
	var defender := _unit(hidden, "ally", 1)
	if not defender.is_empty():
		var defense: Dictionary = hidden.defend_unit(int(defender.id))
		_check(defense.get("ok", false) and defender.guard, "防御应消耗行动并获得一次护卫状态")

func _test_enemy_turn_visibility() -> void:
	var battle := _new_battle()
	_ground(battle)
	var ally := _unit(battle, "ally")
	var enemy := _unit(battle, "enemy")
	_put(ally, Vector2i(1, 1))
	_put(enemy, Vector2i(20, 20))
	battle.refresh_visibility()
	var hidden_cell: Vector2i = ally.cell
	var did_end: bool = battle.end_player_turn()
	_check(did_end and battle.phase == "enemy", "结束玩家回合应进入敌方阶段")
	var step: Dictionary = battle.step_enemy()
	_check(step.get("ok", true), "敌方阶段应能逐步结算")
	_check(enemy.cell != hidden_cell, "敌方单位不应依据全图坐标直接攻击不可见盟友")
	_check(not battle.enemy_explored_cells.is_empty(), "敌军视野应记录自己的探索范围")

func _test_enemy_does_not_know_hidden_ally_positions() -> void:
	var first := _new_battle()
	var second := _new_battle()
	_ground(first); _ground(second)
	var first_ally := _unit(first, "ally")
	var second_ally := _unit(second, "ally")
	_put(first_ally, Vector2i(1, 1))
	_put(second_ally, Vector2i(1, 20))
	for battle: Variant in [first, second]:
		var enemy := _unit(battle, "enemy")
		_put(enemy, Vector2i(20, 12))
		enemy.sight = 3
		for other_enemy: Dictionary in _side_units(battle, "enemy"):
			other_enemy.sight = 3
		battle.refresh_visibility()
	_check(not first.enemy_visible_cells.has(first_ally.cell) and not second.enemy_visible_cells.has(second_ally.cell), "两个盟友位置都应不可见")
	_check(first.end_player_turn() and second.end_player_turn(), "对照战斗都应进入敌方阶段")
	var first_step: Dictionary = first.step_enemy()
	var second_step: Dictionary = second.step_enemy()
	var first_enemy := _unit(first, "enemy")
	var second_enemy := _unit(second, "enemy")
	_check(first_step == second_step, "敌军第一步的行动结果不能受不可见盟友位置影响")
	_check(first_enemy.cell == second_enemy.cell and first_enemy.ap == second_enemy.ap, "盟友处于不同隐蔽位置时，敌军第一单位的坐标和行动力应一致")
	_check(first_enemy.cell != Vector2i(1, 1) and first_enemy.cell != Vector2i(1, 20), "敌军不能直接向未发现盟友的位置移动")

func _test_fog_does_not_leak_terrain() -> void:
	var wall_map := _new_battle()
	var ground_map := _new_battle()
	_ground(wall_map); _ground(ground_map)
	var wall_scout := _unit(wall_map, "ally")
	var ground_scout := _unit(ground_map, "ally")
	_put(wall_scout, Vector2i(1, 1)); _put(ground_scout, Vector2i(1, 1))
	wall_scout.sight = 1; ground_scout.sight = 1
	var unknown_cell := Vector2i(5, 1)
	wall_map.tiles[unknown_cell] = "wall"
	ground_map.tiles[unknown_cell] = "ground"
	wall_map.refresh_visibility(); ground_map.refresh_visibility()
	_check(not wall_map.explored_cells.has(unknown_cell) and not ground_map.explored_cells.has(unknown_cell), "对照中的地形格都应处于未探索状态")
	var wall_reachable: Dictionary = wall_map.reachable_cells(int(wall_scout.id))
	var ground_reachable: Dictionary = ground_map.reachable_cells(int(ground_scout.id))
	_check(wall_reachable == ground_reachable, "视野外的墙与地面不能改变移动范围显示")

func _test_objectives_scoring_and_terminal() -> void:
	var battle := _new_battle()
	_ground(battle)
	var ally := _unit(battle, "ally")
	var enemy := _unit(battle, "enemy")
	var objective: Vector2i = battle.objectives[0].cell
	_put(ally, objective + Vector2i.LEFT)
	_put(enemy, Vector2i(22, 22))
	battle.refresh_visibility()
	var capture: Dictionary = battle.move_unit(int(ally.id), objective)
	_check(capture.get("ok", false) and battle.objectives[0].owner == "ally", "单位进入据点后应占领据点")
	var old_score: int = battle.score_ally
	_check(battle.end_player_turn(), "玩家可结束回合以开始完整回合结算")
	var guard_count := 0
	while battle.phase == "enemy" and guard_count < 20:
		battle.step_enemy()
		guard_count += 1
	_check(battle.phase == "player" or battle.phase == "won" or battle.phase == "lost", "敌方行动结束后应开始新玩家回合")
	_check(battle.score_ally >= old_score, "己方占据据点应推进得分")
	_check(BattleState.TARGET_SCORE == 6, "双方目标分数应为 6")

	# 终局规则独立设置，避免依赖地图上实际战斗的随机结果。
	battle.score_ally = BattleState.TARGET_SCORE - 1
	if ally.cell != objective:
		_put(ally, objective)
	battle.objectives[0].owner = "ally"
	if battle.phase != "player":
		battle.phase = "player"
	for unit: Dictionary in battle.units:
		if unit.side == "enemy": unit.hp = 0
	# 清除最后一名敌人应完成终局；若实现以回合结算判定，则推进一回合。
	battle.refresh_visibility()
	battle.end_player_turn()
	guard_count = 0
	while battle.phase == "enemy" and guard_count < 20:
		battle.step_enemy()
		guard_count += 1
	_check(battle.phase == "won" or battle.score_ally >= BattleState.TARGET_SCORE, "全灭或达到目标分应获胜")
	var rejected: Dictionary = battle.move_unit(int(ally.id), ally.cell + Vector2i.RIGHT)
	_check(not rejected.get("ok", false), "终局阶段必须拒绝后续行动输入")

	# 敌军仍存活且无法移动到据点，单靠连续占点的实际结算达到六分。
	var scoring := _new_battle()
	_ground(scoring)
	var scoring_allies := _side_units(scoring, "ally")
	var first_objective: Vector2i = scoring.objectives[0].cell
	var second_objective: Vector2i = scoring.objectives[1].cell
	_put(scoring_allies[0], first_objective + Vector2i.LEFT)
	_put(scoring_allies[1], second_objective + Vector2i.LEFT)
	var scoring_enemies := _side_units(scoring, "enemy")
	for enemy_unit: Dictionary in scoring_enemies:
		enemy_unit.move = 0
		enemy_unit.sight = 0
		enemy_unit.range = 1
		scoring._capture_objectives()
		# 防止路径显示状态因测试摆位而残留。
		scoring.refresh_visibility()
	for index in range(2):
		var scoring_ally: Dictionary = scoring_allies[index]
		var target: Vector2i = first_objective if index == 0 else second_objective
		var capture_result: Dictionary = scoring.move_unit(int(scoring_ally.id), target)
		_check(capture_result.get("ok", false), "己方单位应能从据点旁进入据点")
	_check(scoring.objectives[0].owner == "ally" and scoring.objectives[1].owner == "ally", "两个据点应由实际移动占领")
	var round_guard := 0
	while scoring.phase == "player" and round_guard < 8:
		scoring.end_player_turn()
		while scoring.phase == "enemy":
			scoring.step_enemy()
		round_guard += 1
	var living_enemies := 0
	for enemy_unit: Dictionary in scoring_enemies:
		if enemy_unit.hp > 0: living_enemies += 1
	_check(scoring.phase == "won" and scoring.score_ally >= BattleState.TARGET_SCORE, "连续控制两个据点应通过实际计分达到六分获胜")
	_check(living_enemies > 0, "占点获胜场景中的敌军应仍然存活")
