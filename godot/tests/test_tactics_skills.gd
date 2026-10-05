extends SceneTree

const BattleState = preload("res://scripts/tactics/battle_state.gd")
const SkillCatalog = preload("res://scripts/tactics/skill_catalog.gd")

var failures := 0
var catalog: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("失败：" + message)

func _new_battle(pet_count: int = 2) -> RefCounted:
	var pets: Array = []
	for index in pet_count:
		pets.append({"species":"goose", "name":"技能测试鹅%d" % index, "health":100, "energy":75, "level":1})
	var battle = BattleState.new()
	battle.setup(pets, catalog)
	var keep: Array[Dictionary] = []
	for unit: Dictionary in battle.units:
		if unit.get("kind", "pet") != "soldier": keep.append(unit)
	battle.units = keep
	return battle

func _enemy_until_player(battle: Variant) -> void:
	var guard := 0
	while battle.phase == "enemy" and not battle.round_done.enemy and guard < 100:
		battle.step_enemy()
		guard += 1
	for foe: Dictionary in _units(battle, "enemy"):
		foe.guard = false

func _full_round(battle: Variant) -> void:
	var start: int = battle.round_number
	var guard := 0
	while battle.phase not in ["won", "lost"] and battle.round_number == start and guard < 200:
		if battle.phase == "player" and not battle.round_done.ally: battle.end_player_turn()
		elif battle.phase == "enemy": battle.step_enemy()
		guard += 1

func _units(battle: Variant, side: String, kind: String = "pet") -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for unit: Dictionary in battle.units:
		if unit.side == side and unit.get("kind", "pet") == kind:
			found.append(unit)
	return found

func _unit(battle: Variant, side: String, index: int = 0) -> Dictionary:
	var found := _units(battle, side)
	return found[index] if index < found.size() else {}

func _ground(battle: Variant) -> void:
	for cell: Vector2i in battle.tiles:
		battle.tiles[cell] = "ground"

func _put(unit: Dictionary, cell: Vector2i) -> void:
	unit.cell = cell

func _arrange_cluster(battle: Variant, caster_cell := Vector2i(5, 5), center_cell := Vector2i(6, 5)) -> Array[Dictionary]:
	_ground(battle)
	var caster := _unit(battle, "ally")
	caster.cell = caster_cell
	caster.range = 4
	caster.sight = 12
	caster.damage = 10
	var foes := _units(battle, "enemy")
	for index in foes.size():
		foes[index].hp = 100; foes[index].max_hp = 100
		foes[index].sight = 0; foes[index].move = 0
	foes[0].cell = center_cell
	if foes.size() > 1: foes[1].cell = center_cell + Vector2i.RIGHT
	if foes.size() > 2: foes[2].cell = center_cell + Vector2i.DOWN
	for index in range(3, foes.size()): foes[index].cell = Vector2i(20, index)
	var friend := _unit(battle, "ally", 1)
	friend.cell = center_cell + Vector2i.UP
	friend.sight = 0
	battle.refresh_visibility()
	return foes

func _assert_failed_cast(battle: Variant, unit: Dictionary, skill_id: String, cell: Vector2i, message: String) -> void:
	var old_ap: int = battle.action_points[unit.side]
	var old_charge: int = int(unit.get("charge", 0))
	var old_units: Array[Dictionary] = battle.units.duplicate(true)
	var had_pending_reactions: bool = battle.has_pending_reactions()
	var result: Dictionary = battle.cast_skill(int(unit.id), skill_id, cell)
	_check(not result.get("ok", false), message)
	_check(battle.action_points[unit.side] == old_ap and int(unit.get("charge", 0)) == old_charge and battle.units == old_units, message + "不得扣AP、充能或改变任何单位")
	_check(battle.has_pending_reactions() == had_pending_reactions, message + "不得改变已有响应队列")

func _run() -> void:
	var file := FileAccess.open("res://data/catalog.json", FileAccess.READ)
	catalog = JSON.parse_string(file.get_as_text()) as Dictionary
	_test_catalog_and_normal_skills()
	_test_species_loadouts_and_copy_isolation()
	_test_charge_and_ultimate()
	_test_rejected_casts_are_atomic()
	_test_aoe_visibility_friend_fire_and_walls()
	_test_enemy_skill_choice_uses_visible_targets()
	if failures == 0:
		print("战术技能目录、伤害、范围、充能、雾、响应与AI测试通过")
	else:
		printerr("战术技能测试失败：%d 项" % failures)
	quit(0 if failures == 0 else 1)

func _test_catalog_and_normal_skills() -> void:
	var battle := _new_battle(2)
	var caster := _unit(battle, "ally")
	var friend := _unit(battle, "ally", 1)
	var foes := _arrange_cluster(battle)
	caster = _unit(battle, "ally")
	friend = _unit(battle, "ally", 1)
	var loadout: Array[Dictionary] = battle.skill_loadout(int(caster.id))
	_check(loadout.size() == 3 and loadout[0].id == "pulse" and loadout[1].id == "shockwave" and loadout[2].id == "overload", "宠物应获得完整且有序的技能配置")
	_check(caster.charge == 0 and caster.charge_max == SkillCatalog.CHARGE_MAX and SkillCatalog.BASIC_SKILL == "pulse", "宠物充能应从0开始并使用目录上限")
	_check(battle.skill_loadout(int(_unit(battle, "ally", 1).id)).size() == 3, "每只宠物应拥有独立技能栏")
	var isolated_loadout: Array[Dictionary] = battle.skill_loadout(int(caster.id))
	isolated_loadout[0].name = "被测试修改的技能名"
	_check(battle.skill_loadout(int(caster.id))[0].name == "能量冲击" and battle.skill_loadout(int(friend.id))[0].name == "能量冲击", "修改返回技能栏不能污染目录或另一只宠物")
	var isolated_definition: Dictionary = SkillCatalog.definition("pulse")
	isolated_definition.name = "被测试修改的目录定义"
	_check(SkillCatalog.definition("pulse").name == "能量冲击" and battle.skill_loadout(int(caster.id))[0].name == "能量冲击", "修改返回技能定义不能污染目录或单位技能栏")
	var center: Vector2i = foes[0].cell
	var primary_hp: int = foes[0].hp
	var pulse_preview: Dictionary = battle.skill_preview(int(caster.id), "pulse", center)
	_check(pulse_preview.get("ok", false) and pulse_preview.hits.size() == 1 and pulse_preview.hits[0].id == foes[0].id, "pulse预览应只命中指定单体敌人")
	_check(pulse_preview.damage == caster.damage and pulse_preview.cost == 4, "pulse应造成1倍伤害并花费4AP")
	var pulse: Dictionary = battle.cast_skill(int(caster.id), "pulse", center)
	_check(pulse.get("ok", false) and foes[0].hp == primary_hp - int(pulse_preview.damage), "pulse施放应应用预览伤害")
	_check(caster.charge == 1 and pulse.charge_gain == 1, "成功普通技能施放应增加一格充能")
	_check(battle.action_points.ally == BattleState.TURN_AP - 4, "pulse实际施放应消耗4点共享AP")
	_check(friend.hp == friend.max_hp, "技能不得对己方造成伤害")
	_enemy_until_player(battle)

	var wave_preview: Dictionary = battle.skill_preview(int(caster.id), "shockwave", center)
	_check(wave_preview.get("ok", false) and wave_preview.hits.size() == 3 and wave_preview.cost == 6, "shockwave应以半径1命中三个相邻敌人并花费6AP")
	var expected_wave_damage := maxi(1, roundi(float(caster.damage) * 0.75))
	_check(wave_preview.damage == expected_wave_damage, "shockwave应造成0.75倍伤害")
	var foe_hps: Array[int] = []
	for foe: Dictionary in foes: foe_hps.append(foe.hp)
	var wave: Dictionary = battle.cast_skill(int(caster.id), "shockwave", center)
	_check(wave.get("ok", false) and wave.hits.size() == 3, "范围技能应一次命中范围内所有有效敌人")
	for index in range(3):
		_check(foes[index].hp == foe_hps[index] - expected_wave_damage, "shockwave应对每个命中敌人应用0.75倍伤害")
	_check(caster.charge == 2, "命中多个敌人的一次范围技能只增加一格充能")
	_check(friend.hp == friend.max_hp and not wave.hits.any(func(hit: Dictionary): return hit.id == friend.id), "shockwave必须排除范围内友军")
	_enemy_until_player(battle)
	_check(_unit(battle, "ally", 1).charge == 0, "另一只宠物不得共享或继承施法者充能")

func _test_species_loadouts_and_copy_isolation() -> void:
	var species_list: Array[String] = ["dragon", "goose", "cat", "whale", "hoshino", "gpt", "claude", "gemini", "unknown_species"]
	for species: String in species_list:
		var battle := BattleState.new()
		battle.setup([{"species":species, "name":"技能配置测试", "health":100, "energy":75, "level":1}], catalog)
		var pet := _unit(battle, "ally")
		var loadout: Array[Dictionary] = battle.skill_loadout(int(pet.id))
		_check(loadout.size() == 3 and loadout.filter(func(skill: Dictionary): return skill.kind == "normal").size() == 2 and loadout.filter(func(skill: Dictionary): return skill.kind == "ultimate").size() == 1, "%s应恰有2个普通技能和1个大招" % species)
		_check(loadout.map(func(skill: Dictionary): return skill.id) == ["pulse", "shockwave", "overload"], "%s技能配置应保留默认技能次序" % species)

func _test_charge_and_ultimate() -> void:
	var battle := _new_battle(3)
	var foes := _arrange_cluster(battle)
	var caster := _unit(battle, "ally")
	var center: Vector2i = foes[0].cell
	foes[3].cell = center + Vector2i(2, 0)
	battle.refresh_visibility()
	_assert_failed_cast(battle, caster, "overload", center, "未满充能时大招必须失败")
	var pulse: Dictionary = battle.cast_skill(int(caster.id), "pulse", center)
	_check(pulse.get("ok", false) and caster.charge == 1, "第一次pulse应充能至1")
	_enemy_until_player(battle)
	var wave: Dictionary = battle.cast_skill(int(caster.id), "shockwave", center)
	_check(wave.get("ok", false) and wave.hits.size() == 3 and caster.charge == 2, "多目标shockwave一次施放仍只充能1格")
	_enemy_until_player(battle)
	pulse = battle.cast_skill(int(caster.id), "pulse", center)
	_check(pulse.get("ok", false) and caster.charge == SkillCatalog.CHARGE_MAX, "第三次普通技能应充满3格")
	_enemy_until_player(battle)
	var capped: Dictionary = battle.cast_skill(int(caster.id), "pulse", center)
	_check(capped.get("ok", false) and caster.charge == SkillCatalog.CHARGE_MAX, "普通技能充能不得超过上限3")

	_enemy_until_player(battle)
	_check(battle.end_player_turn(), "满充能宠物应可结束己方回合")
	_full_round(battle)
	_check(caster.charge == SkillCatalog.CHARGE_MAX, "充能应跨完整回合保留")
	_enemy_until_player(battle)
	var before_hp: int = foes[0].hp
	var outer_hp: int = foes[3].hp
	var ultimate_preview: Dictionary = battle.skill_preview(int(caster.id), "overload", center)
	_check(ultimate_preview.get("ok", false) and ultimate_preview.hits.size() == 4 and ultimate_preview.area.has(foes[3].cell) and ultimate_preview.cost == 8, "满充能overload应命中半径2范围并花费8AP")
	_check(ultimate_preview.damage == maxi(1, roundi(float(caster.damage) * 1.6)), "overload应造成1.6倍伤害")
	var ultimate: Dictionary = battle.cast_skill(int(caster.id), "overload", center)
	_check(ultimate.get("ok", false) and foes[0].hp == before_hp - int(ultimate_preview.damage) and foes[3].hp == outer_hp - int(ultimate_preview.damage), "overload施放应应用伤害至半径2的外缘敌人")
	_check(caster.charge == 0 and ultimate.charge_spent == SkillCatalog.CHARGE_MAX, "大招成功施放后应扣除3格并清空充能")
	_check(battle.action_points.ally == BattleState.TURN_AP - 8, "overload应从共享池扣除8AP")
	_enemy_until_player(battle)
	for index in 4:
		var next: Dictionary = battle.cast_skill(int(caster.id), "pulse", center)
		_check(next.get("ok", false), "充能归零后普通技能仍应可用")
		if index < 3: _enemy_until_player(battle)
	_check(caster.charge == SkillCatalog.CHARGE_MAX, "充能达到3格后更多普通施法仍应封顶")

	var passive := _new_battle()
	var passive_pet := _unit(passive, "ally")
	passive_pet.cell = Vector2i(1, 1)
	passive.refresh_visibility()
	var moving: Dictionary = passive.move_unit(int(passive_pet.id), Vector2i(2, 1))
	_enemy_until_player(passive)
	var defending: Dictionary = passive.defend_unit(int(_unit(passive, "ally", 1).id))
	_check(moving.get("ok", false) and defending.get("ok", false) and passive_pet.charge == 0, "移动和防御不得积累技能充能")

func _test_rejected_casts_are_atomic() -> void:
	var battle := _new_battle()
	var foes := _arrange_cluster(battle)
	var caster := _unit(battle, "ally")
	var center: Vector2i = foes[0].cell
	var enemy_soldier := {"id":9000, "kind":"soldier", "side":"enemy", "cell":Vector2i(20,20), "name":"响应兵", "hp":12, "max_hp":12, "move":2, "sight":0, "range":1, "damage":3}
	battle.units.append(enemy_soldier)
	battle.refresh_visibility()
	var friend := _unit(battle, "ally", 1)
	_assert_failed_cast(battle, caster, "pulse", friend.cell, "不能把己方宠物作为技能目标")
	_assert_failed_cast(battle, caster, "pulse", Vector2i(5, 6), "不能把空格作为技能目标")
	_assert_failed_cast(battle, caster, "pulse", Vector2i(-1, 5), "不能把地图边界外作为技能目标")
	_assert_failed_cast(battle, caster, "unknown", center, "未知技能必须失败")
	caster.skills = ["pulse"]
	_assert_failed_cast(battle, caster, "shockwave", center, "未学习技能必须失败")
	caster.skills = ["pulse", "shockwave", "overload"]
	_assert_failed_cast(battle, caster, "overload", center, "缺少充能时大招必须失败")
	battle.action_points.ally = 3
	_assert_failed_cast(battle, caster, "pulse", center, "共享AP不足时技能必须失败")
	battle.action_points.ally = BattleState.TURN_AP
	caster.range = 1
	foes[0].cell = Vector2i(8, 5)
	battle.refresh_visibility()
	_check(battle.visible_cells.has(foes[0].cell) and battle.has_line_of_sight(caster.cell, foes[0].cell), "超射程目标测试中的敌人应实际存在且可见无遮挡")
	_assert_failed_cast(battle, caster, "pulse", foes[0].cell, "超出宠物射程的技能必须失败")
	caster.range = 4
	battle.tiles[Vector2i(7, 5)] = "wall"
	battle.visible_cells[foes[0].cell] = true
	_assert_failed_cast(battle, caster, "pulse", foes[0].cell, "被墙遮挡的技能必须失败")
	battle.tiles[Vector2i(7, 5)] = "ground"
	caster.sight = 1
	battle.refresh_visibility()
	_assert_failed_cast(battle, caster, "pulse", foes[0].cell, "不可见敌人不能作为技能目标")
	caster.sight = 12
	caster.hp = 0
	_assert_failed_cast(battle, caster, "pulse", foes[0].cell, "死亡宠物不能施放技能")

	var phase_battle := _new_battle()
	var phase_foe := _arrange_cluster(phase_battle)[0]
	var phase_caster := _unit(phase_battle, "ally")
	phase_battle.deploy_budget.enemy = 0
	phase_battle.end_player_turn()
	_assert_failed_cast(phase_battle, phase_caster, "pulse", phase_foe.cell, "错误回合不能施放技能")

func _test_aoe_visibility_friend_fire_and_walls() -> void:
	var battle := _new_battle(2)
	var foes := _arrange_cluster(battle)
	var caster := _unit(battle, "ally")
	var friend := _unit(battle, "ally", 1)
	var center: Vector2i = foes[0].cell
	var hidden := _unit(battle, "enemy", 1)
	caster.cell = Vector2i(4, 5)
	caster.sight = 2
	hidden.cell = center + Vector2i.RIGHT
	friend.cell = center + Vector2i.UP
	battle.refresh_visibility()
	_check(battle.visible_cells.has(center) and not battle.visible_cells.has(hidden.cell), "范围边缘敌军应处于未探索迷雾")
	var preview: Dictionary = battle.skill_preview(int(caster.id), "shockwave", center)
	_check(preview.get("ok", false) and preview.hits.size() == 1 and preview.hits[0].id == foes[0].id, "AoE预览与命中列表不能泄露范围内隐藏敌人")
	_check(preview.area.has(hidden.cell), "范围预览应保留固定几何形状，不裁剪未知格")
	var hidden_hp: int = hidden.hp
	var friend_hp: int = friend.hp
	var enemy_soldier := {"id":9100, "kind":"soldier", "side":"enemy", "cell":Vector2i(20,20), "name":"响应兵", "hp":12, "max_hp":12, "move":2, "sight":0, "range":1, "damage":3}
	battle.units.append(enemy_soldier)
	battle.refresh_visibility()
	var cast: Dictionary = battle.cast_skill(int(caster.id), "shockwave", center)
	_check(cast.get("ok", false) and cast.hits.size() == 1 and cast.hits[0].id == foes[0].id, "AOE战报只能列出施法前已见目标")
	_check(hidden.hp < hidden_hp, "AoE实际结算应命中范围内且与施法者/中心LOS畅通的隐藏敌人")
	_check(friend.hp == friend_hp, "范围技能不能误伤友军")
	_check(battle.has_pending_reactions(), "一次范围施法只排入一次小兵响应批次")
	_assert_failed_cast(battle, friend, "pulse", center, "小兵响应进行中应拒绝其他宠物施法")
	var responses := 0
	while battle.has_pending_reactions():
		battle.step_reaction()
		responses += 1
	_check(responses == 1, "一次AoE命中多个敌人仍只触发每名对方小兵一次响应")

	var walls := _new_battle()
	_ground(walls)
	var wall_caster := _unit(walls, "ally")
	var wall_foes := _units(walls, "enemy")
	wall_caster.cell = Vector2i(6, 8); wall_caster.range = 4; wall_caster.sight = 12; wall_caster.charge = 3
	wall_foes[0].cell = Vector2i(8, 8)
	wall_foes[1].cell = Vector2i(7, 9) # 仅被施法者墙角遮断
	wall_foes[2].cell = Vector2i(8, 10) # 被范围中心与目标间的墙遮断
	walls.tiles[Vector2i(6, 9)] = "wall"
	walls.tiles[Vector2i(8, 9)] = "wall"
	walls.refresh_visibility()
	# 显式标记目标为已见，单独验证 AoE 自身的双 LOS 限制。
	walls.visible_cells[wall_foes[1].cell] = true
	walls.visible_cells[wall_foes[2].cell] = true
	var wall_preview: Dictionary = walls.skill_preview(int(wall_caster.id), "overload", wall_foes[0].cell)
	_check(wall_preview.get("ok", false) and wall_preview.hits.size() == 1 and wall_preview.hits[0].id == wall_foes[0].id, "AoE只能命中与中心和施法者都无遮挡的敌人")
	_check(wall_preview.area.has(wall_foes[1].cell) and wall_preview.area.has(wall_foes[2].cell), "技能几何范围不能因墙体被裁剪")

func _test_enemy_skill_choice_uses_visible_targets() -> void:
	var with_hidden := _new_battle(3)
	var without_hidden := _new_battle(3)
	for battle: Variant in [with_hidden, without_hidden]:
		_ground(battle)
		battle.deploy_budget.enemy = 0
		var enemy_caster := _unit(battle, "enemy")
		enemy_caster.cell = Vector2i(10, 10)
		enemy_caster.sight = 2
		enemy_caster.charge = SkillCatalog.CHARGE_MAX
		enemy_caster.range = 1
		for index in range(1, _units(battle, "enemy").size()):
			var other_enemy := _unit(battle, "enemy", index)
			other_enemy.cell = Vector2i(22, index)
			other_enemy.sight = 0
		var visible_target := _unit(battle, "ally", 0)
		visible_target.cell = Vector2i(11, 10)
		var nearby_visible := _unit(battle, "ally", 2)
		nearby_visible.cell = Vector2i(11, 11)
		for ally: Dictionary in _units(battle, "ally"): ally.sight = 0
	with_hidden.refresh_visibility(); without_hidden.refresh_visibility()
	var hidden_target := _unit(with_hidden, "ally", 1)
	hidden_target.cell = Vector2i(13, 10)
	_unit(without_hidden, "ally", 1).cell = Vector2i(1, 20)
	with_hidden.refresh_visibility(); without_hidden.refresh_visibility()
	var enemy := _unit(with_hidden, "enemy")
	_check(with_hidden.enemy_visible_cells.has(Vector2i(11, 10)) and with_hidden.enemy_visible_cells.has(Vector2i(11, 11)) and not with_hidden.enemy_visible_cells.has(hidden_target.cell), "AI场景应有两个可见目标和一个范围内隐藏敌人")
	_check(with_hidden.end_player_turn() and without_hidden.end_player_turn(), "AI技能对照战斗都应进入敌方回合")
	var result_with_hidden: Dictionary = with_hidden.step_enemy()
	var result_without_hidden: Dictionary = without_hidden.step_enemy()
	_check(result_with_hidden.get("action", "") == "skill" and result_with_hidden.get("skill_id", "") == "overload", "AI满充能时应优先释放范围大招")
	_check(result_with_hidden == result_without_hidden, "AI选技能与目标只能依据可见敌军，不能利用隐藏目标")
	_check(hidden_target.hp < hidden_target.max_hp, "AI选定可见范围中心后，大招结算仍可命中LOS畅通的隐藏敌人")
	_check(enemy.charge == 0 and with_hidden.action_points.enemy == BattleState.TURN_AP - 8, "敌方大招也应清空充能并消耗8点共享AP")
