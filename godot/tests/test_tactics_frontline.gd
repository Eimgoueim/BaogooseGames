extends SceneTree

const BattleState = preload("res://scripts/tactics/battle_state.gd")
const BattleMap = preload("res://scripts/tactics/battle_map.gd")

var failures := 0
var catalog: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("失败：" + message)

func _pets(count: int = 2) -> Array:
	var result: Array = []
	for index in count:
		result.append({"species":"goose", "name":"前线测试鹅%d" % index, "health":100, "energy":75, "level":1})
	return result

func _battle(clean := true, count: int = 2) -> RefCounted:
	var battle = BattleState.new()
	battle.setup(_pets(count), catalog)
	if clean:
		var kept: Array[Dictionary] = []
		for unit: Dictionary in battle.units:
			if unit.get("kind", "pet") != "soldier": kept.append(unit)
		battle.units = kept
	if clean:
		for cell: Vector2i in battle.tiles: battle.tiles[cell] = "ground"
	return battle

func _side(battle: Variant, side: String, kind := "pet") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit: Dictionary in battle.units:
		if unit.side == side and unit.get("kind", "pet") == kind: result.append(unit)
	return result

func _unit(battle: Variant, side: String, index := 0) -> Dictionary:
	var result := _side(battle, side)
	return result[index] if index < result.size() else {}

func _soldier(id: int, side: String, cell: Vector2i) -> Dictionary:
	return {"id":id,"kind":"soldier","side":side,"cell":cell,"name":"前线兵","hp":12,"max_hp":12,"move":BattleState.SOLDIER_MOVE,"sight":BattleState.SOLDIER_SIGHT,"range":1,"damage":3,"guard":false,"pet_index":-1}

func _enemy_until_ally(battle: Variant) -> void:
	var guard := 0
	while battle.phase == "enemy" and not battle.round_done.enemy and guard < 100:
		battle.step_enemy()
		guard += 1

func _finish_round(battle: Variant) -> void:
	var round_before: int = battle.round_number
	var guard := 0
	while battle.phase not in ["won", "lost"] and battle.round_number == round_before and guard < 200:
		if battle.phase == "player" and not battle.round_done.ally: battle.end_player_turn()
		elif battle.phase == "enemy": battle.step_enemy()
		guard += 1

func _run() -> void:
	var file := FileAccess.open("res://data/catalog.json", FileAccess.READ)
	catalog = JSON.parse_string(file.get_as_text()) as Dictionary
	_test_initial_frontline()
	_test_soldiers_hold_lateral_frontline_without_hidden_knowledge()
	_test_one_action_handoff_and_guards()
	_test_zero_ap_and_voluntary_pass()
	_test_captured_region_deployment_and_hidden_contest()
	if failures == 0: print("前线部署、交替指令权、轮结算与增援测试通过")
	else: printerr("前线测试失败：%d 项" % failures)
	quit(0 if failures == 0 else 1)

func _test_initial_frontline() -> void:
	var battle := _battle(false, 4)
	var ally_pets := _side(battle, "ally")
	var enemy_pets := _side(battle, "enemy")
	var ally_soldiers := _side(battle, "ally", "soldier")
	var enemy_soldiers := _side(battle, "enemy", "soldier")
	_check(ally_pets.size() == 4 and enemy_pets.size() == 5, "开局应保留双方原有宠物编制")
	_check(ally_soldiers.size() == 6 and enemy_soldiers.size() == 6, "开局应免费部署双方各六名小兵")
	var expected_ally := BattleMap.ALLY_FRONTLINE_SPAWNS
	var expected_enemy := BattleMap.ENEMY_FRONTLINE_SPAWNS
	var actual_ally: Array[Vector2i] = []
	var actual_enemy: Array[Vector2i] = []
	for soldier: Dictionary in ally_soldiers: actual_ally.append(soldier.cell)
	for soldier: Dictionary in enemy_soldiers: actual_enemy.append(soldier.cell)
	_check(actual_ally == expected_ally and actual_enemy == expected_enemy, "小兵出生位置应匹配两侧镜像前线")
	for soldier: Dictionary in ally_soldiers + enemy_soldiers:
		_check(soldier.hp == 12 and soldier.damage == 3 and soldier.move == 1 and soldier.sight == 2, "初始前线小兵应使用标准生命、伤害、移动和视野参数")
	var cells := {}
	var ids := {}
	for unit: Dictionary in battle.units:
		_check(battle.tiles.has(unit.cell) and battle.tiles[unit.cell] not in ["wall", "water"], "所有初始宠物和小兵出生格都必须可通行")
		_check(not cells.has(unit.cell), "初始宠物和小兵出生位置不能重叠")
		_check(not ids.has(unit.id), "初始宠物和小兵ID必须唯一")
		cells[unit.cell] = true; ids[unit.id] = true
	for index in ally_soldiers.size():
		_check(ally_soldiers[index].cell.x + enemy_soldiers[index].cell.x == BattleMap.SIZE.x - 1, "两侧前线出生点应按地图宽度镜像")
	for soldier: Dictionary in ally_soldiers:
		_check(soldier.cell.x > ally_pets.map(func(pet: Dictionary): return pet.cell.x).min(), "己方小兵前线应在己方宠物出生线之前")
	for soldier: Dictionary in enemy_soldiers:
		_check(soldier.cell.x < enemy_pets.map(func(pet: Dictionary): return pet.cell.x).min(), "敌方小兵前线应在敌方宠物出生线之前")
	_check(battle.deploy_budget.ally == 1 and battle.deploy_budget.enemy == 1, "免费初始编制不能消耗后续部署预算")

func _test_soldiers_hold_lateral_frontline_without_hidden_knowledge() -> void:
	var unknown_owner := _battle()
	var secretly_ally_owned := _battle()
	for battle: Variant in [unknown_owner, secretly_ally_owned]:
		for pet: Dictionary in _side(battle, "ally") + _side(battle, "enemy"):
			pet.sight = 0; pet.move = 0
		var soldier := _soldier(7200, "ally", Vector2i(6, 12))
		battle.units.append(soldier)
		battle.region_at(Vector2i(12, 12)).owner = "neutral"
		battle.deploy_budget.enemy = 0
		battle.refresh_visibility()
	secretly_ally_owned.region_at(Vector2i(12, 12)).owner = "ally"
	secretly_ally_owned.refresh_visibility()
	var first_soldier := _side(unknown_owner, "ally", "soldier")[0]
	var second_soldier := _side(secretly_ally_owned, "ally", "soldier")[0]
	_check(not unknown_owner.region_memory.has(unknown_owner.region_at(Vector2i(12, 12)).id) and not secretly_ally_owned.region_memory.has(secretly_ally_owned.region_at(Vector2i(12, 12)).id), "未看见的中央区归属不应进入双方记忆")
	for pair: Array in [[unknown_owner, first_soldier], [secretly_ally_owned, second_soldier]]:
		var battle: Variant = pair[0]
		var soldier: Dictionary = pair[1]
		battle.end_player_turn()
		var guard := 0
		while battle.phase == "enemy" and guard < 100:
			var result: Dictionary = battle.step_enemy()
			if result.get("reaction", false) and result.get("actor_id", -1) == soldier.id: break
			guard += 1
	_check(first_soldier.cell == second_soldier.cell and first_soldier.cell.x > 6 and first_soldier.cell.x <= 11 and first_soldier.cell.y == 12, "初始兵线应沿横向朝中央集结，且不能利用未见的区域归属改变路线")

func _test_one_action_handoff_and_guards() -> void:
	var battle := _battle()
	var ally := _unit(battle, "ally")
	var target := _unit(battle, "enemy")
	ally.cell = Vector2i(5, 10); ally.range = 4; ally.sight = 24
	target.cell = Vector2i(8, 10); target.hp = 1000; target.max_hp = 1000; target.sight = 0; target.move = 0
	for foe: Dictionary in _side(battle, "enemy"):
		foe.sight = 0; foe.move = 0
	var reserve := _unit(battle, "ally", 1)
	reserve.cell = Vector2i(4, 10); reserve.sight = 0
	battle.deploy_budget.enemy = 0
	var ally_soldier := _soldier(7000, "ally", Vector2i(5, 11))
	var enemy_soldier := _soldier(7001, "enemy", Vector2i(8, 11))
	battle.units.append(ally_soldier); battle.units.append(enemy_soldier)
	battle.refresh_visibility()
	var round_before: int = battle.round_number
	var enemy_ap_before: int = battle.action_points.enemy
	var cast: Dictionary = battle.cast_skill(int(ally.id), "pulse", target.cell)
	_check(cast.get("ok", false) and battle.has_pending_reactions(), "合法技能指令应成功并安排对方小兵响应")
	_check(battle.action_points.ally == BattleState.TURN_AP - 4 and battle.action_points.enemy == enemy_ap_before, "一次宠物指令只扣己方共享点数")
	var locked: Dictionary = battle.cast_skill(int(ally.id), "pulse", target.cell)
	_check(not locked.get("ok", false), "第一条宠物指令提交后不能连续点第二次施法")
	var enemy_reactions := 0
	while battle.has_pending_reactions():
		var reaction: Dictionary = battle.step_reaction()
		if reaction.get("actor_id", -1) == enemy_soldier.id: enemy_reactions += 1
	_check(enemy_reactions == 1 and battle.phase == "enemy", "响应只结算一次且清空后交给对方")
	_check(battle.action_points.ally == BattleState.TURN_AP - 4 and battle.action_points.enemy == enemy_ap_before, "小兵响应不能重置或花费任一方共享AP")
	var hp_after_response: int = target.hp
	var ap_after_response: int = battle.action_points.ally
	var charge_after_response: int = ally.charge
	var repeated: Dictionary = battle.cast_skill(int(ally.id), "pulse", target.cell)
	_check(not repeated.get("ok", false) and target.hp == hp_after_response and battle.action_points.ally == ap_after_response and ally.charge == charge_after_response, "响应结束但敌方持有指令权时重复施法仍须原子拒绝")
	var enemy_result: Dictionary = battle.step_enemy()
	_check(enemy_result.get("ok", false) and enemy_result.get("action", "") in ["skill", "move", "defend", "yield", "round"], "敌方机会应仅推进一条有效指令或结束本轮")
	while battle.has_pending_reactions(): battle.step_enemy()
	_check(battle.phase == "player" or battle.phase == "enemy" and battle.round_done.ally, "敌方指令结算后应交回己方，或因本轮结束保持敌方结算")
	_check(battle.action_points.ally == BattleState.TURN_AP - 4, "交替指令权不能提前重置共享AP")
	_check(battle.round_number == round_before, "双方仍有本轮机会时不能提前结算区域")
	if battle.phase != "player": _enemy_until_ally(battle)
	var defend: Dictionary = battle.defend_unit(int(reserve.id))
	_check(defend.get("ok", false) and reserve.guard, "防御成功后应跨越对手指令机会保留守卫")
	while battle.has_pending_reactions(): battle.step_reaction()
	if battle.phase == "enemy": _enemy_until_ally(battle)
	_check(reserve.guard, "守卫状态不能在交替指令权时提前清除")
	var charge: int = int(ally.charge)
	_finish_round(battle)
	_check(int(ally.charge) == charge, "充能应跨完整轮保留")
	_check(not reserve.guard and battle.round_number == round_before + 1, "只在完整双方结束后清除守卫并推进轮数")
	_check(battle.round_starter == "enemy" and battle.phase == "enemy", "后续轮应轮换由敌方先手")

func _test_zero_ap_and_voluntary_pass() -> void:
	var exhausted := _battle()
	var ally := _unit(exhausted, "ally")
	var target := _unit(exhausted, "enemy")
	ally.cell = Vector2i(5, 10); ally.range = 4; ally.sight = 24
	target.cell = Vector2i(8, 10); target.hp = 1000; target.sight = 0; target.move = 0
	for foe: Dictionary in _side(exhausted, "enemy"):
		foe.sight = 0; foe.move = 0
	exhausted.deploy_budget.enemy = 0
	exhausted.action_points.ally = 4
	exhausted.refresh_visibility()
	var cast: Dictionary = exhausted.cast_skill(int(ally.id), "pulse", target.cell)
	_check(cast.get("ok", false) and exhausted.round_done.ally and exhausted.phase == "enemy", "最后4AP成功施法后应自动结束己方本轮机会")
	var enemy_points: int = exhausted.action_points.enemy
	var before_round: int = exhausted.round_number
	var guard := 0
	while exhausted.round_number == before_round and exhausted.phase == "enemy" and guard < 100:
		exhausted.step_enemy(); guard += 1
	_check(exhausted.round_number == before_round + 1 and exhausted.action_points.enemy == BattleState.TURN_AP and exhausted.action_points.ally == BattleState.TURN_AP, "敌方仍可行动并完成后才统一重置双方AP")
	_check(enemy_points == BattleState.TURN_AP and exhausted.round_starter == "enemy", "零AP自动结束后轮先手仍按公平顺序切换")

	var passed := _battle()
	for foe: Dictionary in _side(passed, "enemy"):
		foe.sight = 0; foe.move = 0
	passed.deploy_budget.enemy = 0
	var ally_ap: int = passed.action_points.ally
	var round_number: int = passed.round_number
	_check(passed.end_player_turn() and passed.round_done.ally and passed.phase == "enemy", "己方可以主动放弃剩余本轮行动点")
	var result: Dictionary = passed.step_enemy()
	_check(result.get("ok", false) and passed.action_points.ally == ally_ap and passed.round_number == round_number, "主动让出后敌方仍有自己的机会，且未过早结算轮次")
	var limit := 0
	while passed.round_number == round_number and passed.phase == "enemy" and limit < 100:
		passed.step_enemy(); limit += 1
	_check(passed.round_number == round_number + 1 and passed.round_starter == "enemy", "敌方结束后完整轮只结算一次并轮换先手")
	_check(passed.score_ally == 1 and passed.score_enemy == 1, "首轮各自初始占领区应恰好各计一分")

	var enemy_exhausted := _battle()
	var guard_pet := _unit(enemy_exhausted, "ally")
	guard_pet.sight = 0
	for foe: Dictionary in _side(enemy_exhausted, "enemy"):
		foe.sight = 0; foe.move = 0
	var mover := _unit(enemy_exhausted, "enemy")
	mover.move = 1
	enemy_exhausted.action_points.enemy = 1
	enemy_exhausted.deploy_budget.enemy = 0
	enemy_exhausted.refresh_visibility()
	var scoring_round: int = enemy_exhausted.round_number
	var start_score_ally: int = enemy_exhausted.score_ally
	var start_score_enemy: int = enemy_exhausted.score_enemy
	_check(enemy_exhausted.defend_unit(int(guard_pet.id)).get("ok", false) and enemy_exhausted.phase == "enemy", "己方真实防御指令应让出机会给敌方")
	var enemy_move: Dictionary = enemy_exhausted.step_enemy()
	_check(enemy_move.get("action", "") == "move" and mover.cell != BattleMap.ENEMY_SPAWNS[0], "敌方剩余1AP时应实际移动并耗尽共享池")
	_check(enemy_exhausted.round_done.enemy and enemy_exhausted.phase == "player" and enemy_exhausted.action_points.enemy == 0, "敌方AP耗尽后应结束本方机会并把操作权交回己方")
	var ally_ap_before_move: int = enemy_exhausted.action_points.ally
	var ally_move: Dictionary = enemy_exhausted.move_unit(int(_unit(enemy_exhausted, "ally", 1).id), Vector2i(3, 11))
	_check(ally_move.get("ok", false) and enemy_exhausted.action_points.ally == ally_ap_before_move - int(ally_move.cost) and enemy_exhausted.round_number == scoring_round, "敌方耗尽后己方仍可继续行动，且本轮尚未结算")
	_check(enemy_exhausted.end_player_turn(), "己方完成剩余行动后可主动结束本轮")
	_check(enemy_exhausted.round_number == scoring_round + 1 and enemy_exhausted.score_ally == start_score_ally + 1 and enemy_exhausted.score_enemy == start_score_enemy + 1, "最后一方结束后区域分数只结算一次")
	_check(enemy_exhausted.action_points.ally == BattleState.TURN_AP and enemy_exhausted.action_points.enemy == BattleState.TURN_AP, "完整轮结束时双方共享AP统一恢复")

func _test_captured_region_deployment_and_hidden_contest() -> void:
	var battle := _battle()
	var ally := _unit(battle, "ally")
	ally.cell = Vector2i(7, 11); ally.sight = 3
	for foe: Dictionary in _side(battle, "enemy"):
		foe.sight = 0; foe.move = 0
	battle.refresh_visibility()
	var center_cell := Vector2i(10, 11)
	_check(battle.region_at(center_cell).owner == "neutral" and not battle.deployment_cells("ally").has(center_cell), "中立前线区未捕获前不能部署")
	var move: Dictionary = battle.move_unit(int(ally.id), Vector2i(8, 11))
	_check(move.get("ok", false) and battle.phase == "enemy", "宠物真实移动进入新区域并交出操作权")
	_finish_round(battle)
	_check(battle.region_at(center_cell).owner == "ally", "完整轮结算时己方宠物应捕获新区域")
	if battle.phase == "enemy": _enemy_until_ally(battle)
	var deployment_cells: Dictionary = battle.deployment_cells("ally")
	_check(deployment_cells.has(center_cell), "稳定控制新区域后应解锁该区可见空地增援")
	var ap_before: int = battle.action_points.ally
	var budget_before: int = battle.deploy_budget.ally
	var deploy: Dictionary = battle.deploy_soldier("ally", center_cell)
	_check(deploy.get("ok", false) and battle.deploy_budget.ally == budget_before - 1 and battle.action_points.ally == ap_before, "增援消耗部署预算，不耗宠物AP")
	_check(battle.phase == "player", "手动部署不交出宠物指令权")

	var hidden := _battle()
	var home_pet := _unit(hidden, "ally")
	home_pet.cell = Vector2i(2, 10); home_pet.sight = 2
	var hidden_contester := _soldier(7100, "enemy", Vector2i(7, 15))
	hidden.units.append(hidden_contester)
	hidden.refresh_visibility()
	var contested_cell := Vector2i(3, 10)
	var home_region: Dictionary = hidden.region_at(contested_cell)
	_check(home_region.contested and not hidden.region_memory.get(home_region.id, {}).get("contested", false), "隐藏敌军实际争夺不能泄漏到己方区域记忆")
	_check(hidden.deployment_cells("ally").has(contested_cell), "部署高亮只能按己方记忆，不能直接泄漏隐藏争夺")
	var hidden_budget: int = hidden.deploy_budget.ally
	var rejected: Dictionary = hidden.deploy_soldier("ally", contested_cell)
	_check(not rejected.get("ok", false) and hidden.deploy_budget.ally == hidden_budget and hidden.phase == "player", "实际争夺区即使被迷雾隐藏也要拒绝部署且不耗预算或换手")
