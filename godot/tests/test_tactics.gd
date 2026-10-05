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

func _soldier(id: int, side: String, cell: Vector2i) -> Dictionary:
	return {"id":id, "kind":"soldier", "side":side, "cell":cell, "name":"测试兵", "species":"goose", "level":1, "hp":12, "max_hp":12, "move":2, "sight":4, "range":1, "damage":3, "guard":false, "pet_index":-1}

func _hold_enemy_pets(battle: Variant) -> void:
	battle.deploy_budget.enemy = 0
	for enemy: Dictionary in _side_units(battle, "enemy"):
		enemy.move = 0
		enemy.sight = 0
		enemy.range = 1

func _finish_enemy_phase(battle: Variant) -> void:
	var guard := 0
	while battle.phase == "enemy" and guard < 200:
		battle.step_enemy()
		guard += 1

func _finish_full_round(battle: Variant) -> void:
	if battle.phase == "player": battle.end_player_turn()
	_finish_enemy_phase(battle)

func _run() -> void:
	catalog = _load_catalog()
	_test_setup_copies_pets()
	_test_map_and_movement()
	_test_combat_and_visibility()
	_test_enemy_turn_visibility()
	_test_enemy_does_not_know_hidden_ally_positions()
	_test_fog_does_not_leak_terrain()
	_test_shared_action_points()
	_test_regions_and_scoring()
	_test_deployment_and_soldiers()
	_test_reactions()
	_test_enemy_shared_action_points()
	_test_terminal_input_lock()
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
	_check(battle.tiles.size() == 24 * 24 and battle.regions.size() == 9, "地图应由 24×24 格子和 3×3 区域组成")
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
	ally.cell = Vector2i(1, 1)
	ally.sight = 24
	for cell: Vector2i in battle.tiles:
		battle.tiles[cell] = "wall"
	for x in range(1, 24):
		var cell := Vector2i(x, 1)
		if battle.tiles.has(cell): battle.tiles[cell] = "ground"
	battle.tiles[Vector2i(1, 2)] = "ground"
	battle.tiles[Vector2i(2, 1)] = "brush"
	battle.tiles[Vector2i(4, 1)] = "wall"
	battle.tiles[Vector2i(2, 2)] = "water"
	battle.refresh_visibility()
	var options: Dictionary = battle.reachable_cells(int(ally.id))
	_check(options.get(Vector2i(3, 1), -1) == 3, "经灌木两格的实际移动成本应为 3 点")
	_check(not options.has(Vector2i(4, 1)) and not options.has(Vector2i(2, 2)), "墙体和水域都不能进入移动范围")
	battle.tiles[Vector2i(4, 1)] = "ground"; battle.tiles[Vector2i(2, 2)] = "ground"
	battle.refresh_visibility()
	var move_result: Dictionary = battle.move_unit(int(ally.id), Vector2i(3, 1))
	_check(move_result.get("ok", false) and move_result.get("cost", -1) == 3, "移动应按实际路径扣除灌木2点和普通格1点")
	_check(battle.action_points.ally == BattleState.TURN_AP - 3, "路径移动费用应从己方共享行动点池扣除")
	var long_move: Dictionary = battle.move_unit(int(ally.id), Vector2i(23, 1))
	_check(long_move.get("ok", false) and long_move.get("cost", -1) == 20, "玩家宠物应能一次走完超出profile.move的实际长路径")
	_check(battle.action_points.ally == 1, "长路径继续从同一共享行动点池扣费")
	var no_ap: Dictionary = battle.move_unit(int(ally.id), Vector2i(4, 1))
	_check(not no_ap.get("ok", false), "共享行动点不足时应拒绝移动")

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
	_check(attack.get("cost", -1) == BattleState.ATTACK_COST and battle.action_points.ally == BattleState.TURN_AP - 4, "攻击应从己方共享池扣除4点")
	var too_far: Dictionary = battle.attack_unit(int(ally.id), Vector2i(20, 20))
	_check(not too_far.get("ok", false), "超出射程的攻击应拒绝")
	var defender := _unit(battle, "ally", 1)
	var defense: Dictionary = battle.defend_unit(int(defender.id))
	_check(defense.get("ok", false) and defense.get("cost", -1) == BattleState.DEFEND_COST and battle.action_points.ally == BattleState.TURN_AP - 6, "防御应花费共享池2点行动点")
	_check(defender.guard, "防御应给予单位护卫状态")

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
	var empty_hidden := _new_battle()
	_ground(empty_hidden)
	var empty_scout := _unit(empty_hidden, "ally")
	_put(empty_scout, Vector2i(1, 1)); empty_scout.sight = 1
	for index in range(_side_units(hidden, "enemy").size()):
		var hidden_foe := _unit(hidden, "enemy", index)
		var empty_foe := _unit(empty_hidden, "enemy", index)
		hidden_foe.cell = Vector2i(20, 20) if index == 0 else Vector2i(21, 5 + index)
		empty_foe.cell = Vector2i(22, 22) if index == 0 else Vector2i(21, 5 + index)
	hidden.refresh_visibility(); empty_hidden.refresh_visibility()
	var empty_options: Dictionary = empty_hidden.reachable_cells(int(empty_scout.id))
	_check(options == empty_options, "隐藏敌人的位置不能改变玩家看到的可达格")
	# 寻路只知道迷雾中的地形；移动时碰到未发现的敌人应停在其前方。
	scout.sight = 1
	_put(scout, Vector2i(1, 1))
	_put(unseen, Vector2i(5, 1))
	hidden.refresh_visibility()
	var interrupted: Dictionary = hidden.move_unit(int(scout.id), Vector2i(7, 1))
	_check(interrupted.get("ok", false) and scout.cell == Vector2i(4, 1), "接触隐藏敌人时移动应在敌人前中断")
	_check(interrupted.get("cost", -1) == 3 and hidden.action_points.ally == BattleState.TURN_AP - 3, "遇隐藏障碍只应扣除实际走过的路径点数")

	_put(scout, Vector2i(3, 3))
	_put(unseen, Vector2i(5, 3))
	hidden.tiles[Vector2i(4, 3)] = "wall"
	hidden.refresh_visibility()
	_check(not hidden.visible_cells.has(unseen.cell), "墙体应遮断单位视线")
	_check(hidden.explored_cells.has(Vector2i(3, 3)), "己方视野应记录探索记忆")
	_put(unseen, Vector2i(8, 8))
	hidden.refresh_visibility()
	_check(hidden.explored_cells.has(Vector2i(3, 3)), "离开视野后探索记忆仍应保留")
	var line_battle := _new_battle()
	_ground(line_battle)
	var shooter := _unit(line_battle, "ally")
	var target := _unit(line_battle, "enemy")
	_put(shooter, Vector2i(5, 5)); shooter.range = 4
	_put(target, Vector2i(7, 5))
	line_battle.tiles[Vector2i(6, 5)] = "wall"
	line_battle.visible_cells[target.cell] = true
	_check(not line_battle.has_line_of_sight(shooter.cell, target.cell), "墙体应阻断攻击视线")
	var blocked_attack: Dictionary = line_battle.attack_unit(int(shooter.id), target.cell)
	_check(not blocked_attack.get("ok", false), "即使目标单元格在视野数据中，墙体遮挡也应阻止攻击")

func _test_enemy_turn_visibility() -> void:
	var battle := _new_battle()
	_ground(battle)
	battle.deploy_budget.enemy = 0
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
	first.deploy_budget.enemy = 0; second.deploy_budget.enemy = 0
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
	_check(first_enemy.cell == second_enemy.cell and first.action_points.enemy == second.action_points.enemy, "盟友处于不同隐蔽位置时，敌军第一单位坐标和敌方共用行动点应一致")
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

func _test_shared_action_points() -> void:
	var battle := _new_battle()
	_ground(battle)
	var first := _unit(battle, "ally", 0)
	var second := _unit(battle, "ally", 1)
	_put(first, Vector2i(1, 1)); _put(second, Vector2i(1, 22))
	first.sight = 24; second.sight = 6
	battle.refresh_visibility()
	_check(battle.action_points.ally == BattleState.TURN_AP and BattleState.TURN_AP == 24, "己方共享行动点池应从24点开始")
	var far_cell := Vector2i(16, 22)
	var remaining_cell := Vector2i(15, 22)
	_check(battle.reachable_cells(int(second.id)).has(far_cell), "行动前另一只宠物应能使用共享池中的15点路径")
	var spend: Dictionary = battle.move_unit(int(first.id), Vector2i(11, 1))
	_check(spend.get("ok", false) and spend.get("cost", -1) == 10, "第一只宠物应能为共享池分配十点移动")
	_check(battle.action_points.ally == 14 and not battle.reachable_cells(int(second.id)).has(far_cell), "一只寵物的移動应立即缩小另一只宠物的可达范围")
	var remaining_use: Dictionary = battle.move_unit(int(second.id), remaining_cell)
	_check(remaining_use.get("ok", false) and remaining_use.get("cost", -1) == 14, "另一只宠物应能使用行动池里剩余的14点")
	_check(battle.action_points.ally == 0, "任意宠物消耗都应共同扣减至零")
	var rejected: Dictionary = battle.defend_unit(int(first.id))
	_check(not rejected.get("ok", false), "共享池为零时任何宠物都不能继续行动")

func _test_regions_and_scoring() -> void:
	var battle := _new_battle(2)
	_ground(battle)
	_hold_enemy_pets(battle)
	var ally := _unit(battle, "ally", 0)
	var friend := _unit(battle, "ally", 1)
	_put(ally, Vector2i(2, 2))
	_put(friend, Vector2i(2, 3))
	var enemies := _side_units(battle, "enemy")
	for index in enemies.size(): _put(enemies[index], Vector2i(17 + index, 17))
	var neutral_region: Dictionary = battle.region_at(Vector2i(4, 4))
	var empty_enemy_region: Dictionary = battle.region_at(Vector2i(20, 12))
	_check(battle.regions.size() == 9 and neutral_region.name == "R1" and empty_enemy_region.name == "R6", "区域应按3×3布局命名R1到R9")
	_check(neutral_region.owner == "neutral", "中立区开局应为neutral")
	ally.cell = Vector2i(4, 4)
	battle.refresh_visibility()
	_check(neutral_region.owner == "neutral", "进入中立区后不能即时改变区域归属")
	_finish_full_round(battle)
	_check(battle.phase == "player", "完整敌方回合结束后应开始新回合")
	_check(neutral_region.owner == "ally", "只由己方存活单位占据的区域应在完整轮结束时捕获")
	_check(empty_enemy_region.owner == "enemy", "无单位区域应保留此前owner")
	_check(battle.score_ally >= 1 and battle.score_enemy >= 1, "每个完整双方回合应按区域owner结算得分")
	_check(battle.action_points.ally == BattleState.TURN_AP, "新己方回合开始时共享行动点应重置")
	_check(battle.deploy_budget.ally == 2 and battle.deploy_budget.enemy == 1, "新回合應增加雙方部署預算，敵方已用部署預算應補回")

	var contest := _new_battle(2)
	_ground(contest); _hold_enemy_pets(contest)
	for region: Dictionary in contest.regions: region.owner = "neutral"
	var contested_region: Dictionary = contest.region_at(Vector2i(4, 12))
	contested_region.owner = "ally"
	var contest_ally := _unit(contest, "ally", 0)
	var contest_enemy := _unit(contest, "enemy", 0)
	_put(contest_ally, Vector2i(1, 9)); contest_ally.sight = 0
	_put(_unit(contest, "ally", 1), Vector2i(2, 9))
	_put(contest_enemy, Vector2i(7, 15)); contest_enemy.sight = 0
	for i in range(1, _side_units(contest, "enemy").size()): _put(_unit(contest, "enemy", i), Vector2i(18 + i, 20))
	contest.refresh_visibility()
	_check(contested_region.contested and contested_region.owner == "ally", "区域内敌我存活单位应形成实际争夺，同时保留上一owner")
	_check(contest.region_memory.has(contested_region.id) and not contest.region_memory[contested_region.id].contested, "迷雾记忆不能泄漏不可见敌人造成的区域争夺")
	_finish_full_round(contest)
	_check(contested_region.contested and contested_region.owner == "ally", "争夺区域结算后应保留owner")
	_check(contest.score_ally == 0, "争夺区域不应产生占领分")

	var soldier_capture := _new_battle(2)
	_ground(soldier_capture); _hold_enemy_pets(soldier_capture)
	var deploy_options: Array = soldier_capture.deployment_cells("ally").keys()
	var deployed: Dictionary = soldier_capture.deploy_soldier("ally", deploy_options[0])
	var soldier: Dictionary = soldier_capture.get_unit(int(deployed.id))
	_put(soldier, Vector2i(12, 12))
	var soldier_region: Dictionary = soldier_capture.region_at(soldier.cell)
	_check(soldier.kind == "soldier" and soldier_region.owner == "neutral", "部署的小兵初始应为小兵种类且等待完整轮捕区")
	soldier_capture.end_player_turn()
	soldier_capture.action_points.enemy = 0
	_finish_enemy_phase(soldier_capture)
	_check(soldier_region.owner == "ally", "小兵作为己方存活单位应能单独占领区域")

	# 九个区域都有己方小兵，R9还有存活敌宠形成争夺，其余八区每轮各得一分。
	var scoring := _new_battle(2)
	_ground(scoring); _hold_enemy_pets(scoring)
	var scoring_enemies := _side_units(scoring, "enemy")
	for index in scoring_enemies.size(): _put(scoring_enemies[index], Vector2i(17 + index, 17))
	var next_id := 3000
	for region: Dictionary in scoring.regions:
		var center: Vector2i = region.rect.position + region.rect.size / 2
		scoring.units.append(_soldier(next_id, "ally", center)); next_id += 1
	scoring.refresh_visibility()
	var rounds := 0
	while scoring.phase == "player" and scoring.score_ally < BattleState.TARGET_SCORE and rounds < 5:
		scoring.end_player_turn()
		scoring.action_points.enemy = 0
		_finish_enemy_phase(scoring)
		rounds += 1
	_check(BattleState.TARGET_SCORE == 30, "胜利目标应为30分")
	_check(scoring.phase == "won" and scoring.score_ally >= BattleState.TARGET_SCORE, "区域控制应通过完整轮计分达到30分获胜")
	var enemies_alive := 0
	for enemy_unit: Dictionary in scoring_enemies:
		if enemy_unit.hp > 0: enemies_alive += 1
	_check(enemies_alive > 0, "区域计分获胜时敌方宠物应仍存活")

func _test_deployment_and_soldiers() -> void:
	var battle := _new_battle(2)
	_ground(battle)
	var ally := _unit(battle, "ally", 0)
	ally.sight = 6
	_unit(battle, "ally", 1).sight = 1
	battle.refresh_visibility()
	_check(battle.deploy_budget.ally == 1 and battle.deploy_budget.enemy == 1, "双方开局部署预算均为1")
	var choices: Array = battle.deployment_cells("ally").keys()
	_check(not choices.is_empty(), "己方R4内可见且空闲的格子应可部署")
	var before_ap: int = battle.action_points.ally
	var enemy_soldier := _soldier(8000, "enemy", Vector2i(20, 20))
	battle.units.append(enemy_soldier)
	battle.refresh_visibility()
	var deploy_cell: Vector2i = choices[0]
	var deploy: Dictionary = battle.deploy_soldier("ally", deploy_cell)
	_check(deploy.get("ok", false) and battle.deploy_budget.ally == 0, "成功部署应消耗一个己方预算")
	_check(battle.action_points.ally == before_ap and not battle.has_pending_reactions(), "手动部署不消耗宠物行动点，也不触发响应")
	var soldier: Dictionary = battle.get_unit(int(deploy.id))
	_check(soldier.kind == "soldier" and soldier.hp == 12 and soldier.damage == 3 and soldier.move == 2 and soldier.sight == 4 and soldier.range == 1, "小兵参数应匹配规定数值")
	soldier.sight = 0
	battle.refresh_visibility()
	_check(battle.reachable_cells(int(soldier.id)).is_empty(), "小兵不能进入宠物的移动指令")
	_check(not battle.move_unit(int(soldier.id), deploy_cell + Vector2i.RIGHT).get("ok", false), "小兵不能被玩家直接移动")
	_check(not battle.attack_unit(int(soldier.id), deploy_cell + Vector2i.RIGHT).get("ok", false), "小兵不能被玩家直接攻击")
	_check(not battle.defend_unit(int(soldier.id)).get("ok", false), "小兵不能被玩家直接防御")
	battle.deploy_budget.ally = 1
	_check(not battle.deploy_soldier("ally", deploy_cell).get("ok", false), "被占据的格子不能重复部署")
	_check(battle.visible_cells.has(Vector2i(8, 10)), "部署规则测试的中立格应处于己方可见范围")
	_check(not battle.deploy_soldier("ally", Vector2i(8, 10)).get("ok", false), "可见中立区域不能部署己方小兵")
	_check(not battle.deployment_cells("ally").has(Vector2i(0, 15)), "己方区域中未被视野揭示的格子不能部署")
	var wall_cell: Vector2i = battle.deployment_cells("ally").keys()[0] if not battle.deployment_cells("ally").is_empty() else Vector2i(-1, -1)
	_check(wall_cell.x >= 0, "扣除预算前部署区域应仍有其他可见空格")
	if wall_cell.x >= 0:
		battle.tiles[wall_cell] = "wall"
		_check(not battle.deployment_cells("ally").has(wall_cell), "不可通行格不能部署")
		battle.tiles[wall_cell] = "ground"
	battle.deploy_budget.ally = 0
	var hidden_deploy: Dictionary = battle.deploy_soldier("enemy", Vector2i(20, 20))
	_check(not hidden_deploy.get("ok", false), "玩家阶段不能手动部署敌方小兵")
	_check(battle.end_player_turn(), "无响应处理时应能进入敌方回合")
	var enemy_count_before := _side_units(battle, "enemy").filter(func(unit: Dictionary): return unit.kind == "soldier").size()
	var enemy_step: Dictionary = battle.step_enemy()
	_check(enemy_step.get("action", "") == "deploy", "敌方回合第一步应自动部署小兵")
	_check(not battle.has_pending_reactions(), "敌方自动部署不应触发响应")
	var enemy_count_after := _side_units(battle, "enemy").filter(func(unit: Dictionary): return unit.kind == "soldier").size()
	_check(enemy_count_after == enemy_count_before + 1 and battle.deploy_budget.enemy == 0, "敌方自动部署应消耗一个预算")
	_finish_enemy_phase(battle)
	_check(battle.deploy_budget.ally == 1 and battle.deploy_budget.enemy == 1, "完整新回合应补充双方部署预算")

func _test_reactions() -> void:
	# 小兵响应一次、无AP递归并在处理期间锁定宠物操作。
	var battle := _new_battle(2)
	_ground(battle)
	var actor := _unit(battle, "ally", 0)
	_put(actor, Vector2i(5, 5))
	var first_soldier := _soldier(8100, "enemy", Vector2i(6, 5))
	var second_soldier := _soldier(8101, "enemy", Vector2i(8, 5))
	battle.units.append(first_soldier); battle.units.append(second_soldier)
	battle.refresh_visibility()
	var valid_deploy_cell: Vector2i = battle.deployment_cells("ally").keys()[0]
	var defended: Dictionary = battle.defend_unit(int(actor.id))
	_check(defended.get("ok", false) and battle.has_pending_reactions(), "宠物防御成功后应排入对方存活小兵响应")
	var points_before_block: int = battle.action_points.ally
	var enemy_points_before_reactions: int = battle.action_points.enemy
	_check(not battle.move_unit(int(_unit(battle, "ally", 1).id), Vector2i(3, 3)).get("ok", false), "响应处理中应锁定所有宠物移动")
	_check(not battle.end_player_turn(), "响应处理中应锁定结束回合")
	_check(not battle.deploy_soldier("ally", valid_deploy_cell).get("ok", false), "响应处理中应锁定部署")
	_check(battle.action_points.ally == points_before_block, "被锁定的操作不得扣行动点")
	var seen_reactions: Array[int] = []
	while battle.has_pending_reactions():
		var reaction: Dictionary = battle.step_reaction()
		seen_reactions.append(int(reaction.get("actor_id", -1)))
	_check(seen_reactions.size() == 2 and seen_reactions.has(first_soldier.id) and seen_reactions.has(second_soldier.id), "对方每只存活小兵应各响应一次")
	_check(not battle.has_pending_reactions(), "小兵响应不能递归触发新响应")
	_check(battle.action_points.ally == points_before_block and battle.action_points.enemy == enemy_points_before_reactions, "小兵响应不得消耗任一方共享行动点")
	var target := _unit(battle, "enemy")
	_put(target, Vector2i(6, 5)); actor.range = 2
	battle.refresh_visibility()
	var attack: Dictionary = battle.attack_unit(int(actor.id), target.cell)
	_check(attack.get("ok", false) and battle.has_pending_reactions(), "宠物攻击成功后也应排入对方小兵响应")
	var attack_points_ally: int = battle.action_points.ally
	var attack_points_enemy: int = battle.action_points.enemy
	var attack_reactions := 0
	while battle.has_pending_reactions():
		battle.step_reaction()
		attack_reactions += 1
	_check(attack_reactions == 2 and battle.action_points.ally == attack_points_ally and battle.action_points.enemy == attack_points_enemy, "攻击响应应每只小兵一次且不扣共享行动点")
	var move_actor := _unit(battle, "ally", 1)
	var after_reaction: Dictionary = battle.move_unit(int(_unit(battle, "ally", 1).id), Vector2i(3, 3))
	_check(after_reaction.get("ok", false) and battle.has_pending_reactions(), "宠物移动成功后应再次排入对方小兵响应")
	var move_points_ally: int = battle.action_points.ally
	var move_points_enemy: int = battle.action_points.enemy
	var move_reactions := 0
	while battle.has_pending_reactions():
		battle.step_reaction()
		move_reactions += 1
	_check(move_reactions == 2 and battle.action_points.ally == move_points_ally and battle.action_points.enemy == move_points_enemy, "移动响应应每只小兵一次且不扣共享行动点")
	_check(not battle.has_pending_reactions(), "移动响应完成后应解除输入锁且不递归")

	# 小兵响应独立于宠物剩余行动点，死亡小兵应跳过。
	var depleted := _new_battle(2)
	_ground(depleted)
	var depleted_actor := _unit(depleted, "ally")
	_put(depleted_actor, Vector2i(1, 1))
	depleted_actor.sight = 1
	depleted.action_points.ally = 1
	var dead_soldier := _soldier(8200, "enemy", Vector2i(5, 1))
	var live_soldier := _soldier(8201, "enemy", Vector2i(7, 1))
	depleted.units.append(dead_soldier); depleted.units.append(live_soldier)
	depleted.refresh_visibility()
	var final_move: Dictionary = depleted.move_unit(int(depleted_actor.id), Vector2i(2, 1))
	_check(final_move.get("ok", false) and depleted.action_points.ally == 0 and depleted.has_pending_reactions(), "最後1點移動扣至0後仍應安排士兵響應")
	dead_soldier.hp = 0
	var skipped: Dictionary = depleted.step_reaction()
	_check(skipped.get("skipped", false), "已死亡的待响应小兵应安全跳过")
	var last_reaction: Dictionary = depleted.step_reaction()
	_check(last_reaction.get("actor_id", -1) == live_soldier.id and not depleted.has_pending_reactions(), "存活小兵应在零宠物行动点时完成响应且不递归")
	_check(depleted.action_points.ally == 0, "零宠物行动点下的小兵响应不应增加或消耗行动点")

	# enemy AI先消解敌方宠物指令引发的我方小兵响应。
	var enemy_turn := _new_battle(2)
	_ground(enemy_turn)
	enemy_turn.deploy_budget.enemy = 0
	var enemy_pet := _unit(enemy_turn, "enemy")
	_put(enemy_pet, Vector2i(20, 12))
	var reacting_ally := _soldier(8300, "ally", Vector2i(2, 2))
	enemy_turn.units.append(reacting_ally)
	enemy_turn.refresh_visibility()
	_check(enemy_turn.end_player_turn(), "敌方响应场景应进入敌方回合")
	var enemy_action: Dictionary = enemy_turn.step_enemy()
	_check(enemy_action.get("action", "") in ["move", "attack", "defend"], "敌宠物应先执行一次行动")
	_check(enemy_turn.has_pending_reactions(), "敌方宠物行动后应排入我方小兵响应")
	var ally_points_before_response: int = enemy_turn.action_points.ally
	var enemy_points_before_response: int = enemy_turn.action_points.enemy
	var auto_reaction: Dictionary = enemy_turn.step_enemy()
	_check(auto_reaction.get("reaction", false) and auto_reaction.get("actor_id", -1) == reacting_ally.id, "step_enemy应先处理我方小兵响应")
	_check(not enemy_turn.has_pending_reactions(), "step_enemy处理响应后应清空响应队列")
	_check(enemy_turn.action_points.ally == ally_points_before_response and enemy_turn.action_points.enemy == enemy_points_before_response, "敌方小兵响应也不得消耗任一方共享行动点")

func _test_enemy_shared_action_points() -> void:
	var battle := _new_battle(2)
	_ground(battle)
	battle.deploy_budget.enemy = 0
	var foes := _side_units(battle, "enemy")
	_put(foes[0], Vector2i(20, 2)); _put(foes[1], Vector2i(20, 4))
	for foe: Dictionary in foes: foe.sight = 0
	for ally: Dictionary in _side_units(battle, "ally"): ally.sight = 0
	battle.refresh_visibility()
	_check(battle.end_player_turn() and battle.action_points.enemy == BattleState.TURN_AP, "敵方自己的回合开始时应重置共享点数")
	var start_points: int = battle.action_points.enemy
	var first: Dictionary = battle.step_enemy()
	var after_first: int = battle.action_points.enemy
	var second: Dictionary = battle.step_enemy()
	var after_second: int = battle.action_points.enemy
	_check(first.get("actor_id", -1) != second.get("actor_id", -1), "敌方宠物应轮流获得行动机会")
	_check(after_first < start_points and after_second < after_first, "敌方宠物行动应共同消耗敌方共享池")
	_finish_enemy_phase(battle)
	_check(battle.phase == "player", "敌方共享池消耗完后应结束敌方回合")
	var ally := _unit(battle, "ally")
	battle.action_points.ally = 1
	_check(battle.end_player_turn() and battle.action_points.enemy == BattleState.TURN_AP, "下一次敌方回合开始应重新获得完整共享行动点")

func _test_terminal_input_lock() -> void:
	var battle := _new_battle(1)
	_ground(battle)
	var ally := _unit(battle, "ally")
	var enemies := _side_units(battle, "enemy")
	for foe: Dictionary in enemies: foe.hp = 0
	var last_pet := enemies[0]
	last_pet.hp = 1
	last_pet.cell = ally.cell + Vector2i.RIGHT
	var soldier := _soldier(8400, "enemy", ally.cell + Vector2i.DOWN)
	battle.units.append(soldier)
	battle.visible_cells[last_pet.cell] = true
	var victory: Dictionary = battle.attack_unit(int(ally.id), last_pet.cell)
	_check(victory.get("ok", false) and battle.phase == "won", "击败最后一只敌宠后应获胜，即使敌方还有小兵存活")
	_check(soldier.hp > 0, "终局宠物全灭场景中的敌方小兵仍存活")
	_check(not battle.move_unit(int(ally.id), ally.cell + Vector2i(2, 0)).get("ok", false), "终局阶段必须拒绝宠物行动")
	_check(not battle.deploy_soldier("ally", ally.cell + Vector2i.DOWN).get("ok", false), "终局阶段必须拒绝部署")
