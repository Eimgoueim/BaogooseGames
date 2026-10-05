extends SceneTree

const Scene = preload("res://scenes/native_room.tscn")
const Battle = preload("res://scripts/tactics/battle_state.gd")
const Skills = preload("res://scripts/tactics/skill_catalog.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("失败：" + message)

func _settle() -> void:
	for index in 6:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

func _click_canvas(control: Control, point: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = root.get_final_transform() * (control.get_global_transform() * point)
	root.push_input(click, false)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click, false)

func _click_button(button: Button) -> void:
	if DisplayServer.get_name() == "headless":
		button.emit_signal("pressed")
	else:
		_click_canvas(button, button.size * 0.5)
		await _settle()

func _click_sidebar_button(screen: Control, button: Button) -> void:
	var scroll: ScrollContainer = screen.get("_sidebar_scroll")
	scroll.ensure_control_visible(button)
	await _settle()
	await _click_button(button)

func _click_cell(screen: Control, cell: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		screen._cell_clicked(cell)
	else:
		_click_canvas(screen.board, screen.board._cell_rect(cell).get_center())
		await _settle()

func _hover_cell(screen: Control, cell: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		screen._cell_hovered(cell)
	else:
		var motion := InputEventMouseMotion.new()
		motion.position = root.get_final_transform() * (screen.board.get_global_transform() * screen.board._cell_rect(cell).get_center())
		root.push_input(motion, false)
		await _settle()

func _drive_battle_process(screen: Control, battle: RefCounted, limit: int = 200) -> int:
	var steps := 0
	while (battle.phase == "enemy" or battle.has_pending_reactions()) and steps < limit:
		screen._process(1.0)
		steps += 1
		if DisplayServer.get_name() != "headless":
			await process_frame
	return steps

func _restore_battle_formation(battle: RefCounted, initial_cells: Dictionary) -> void:
	for cell in battle.tiles:
		battle.tiles[cell] = "ground"
	for unit in battle.units:
		if initial_cells.has(int(unit.id)):
			unit.cell = initial_cells[int(unit.id)]
		unit.hp = unit.max_hp
		unit.guard = false
	battle.refresh_visibility()

func _living_soldiers(battle: RefCounted, side: String) -> int:
	var count := 0
	for unit in battle.units:
		if unit.get("kind", "pet") == "soldier" and unit.side == side and int(unit.hp) > 0:
			count += 1
	return count

func _run() -> void:
	var app: Variant = Scene.instantiate()
	app.preview_mode = true
	root.add_child(app)
	app.set_process(false)
	for species in ["goose", "cat", "gpt"]:
		var pet: Dictionary = app.state.pets[0].duplicate(true)
		pet.species = species
		pet.name = species
		app.state.pets.append(pet)
	var original_pets: Array = app.state.pets.duplicate(true)
	for theme_key in app.catalog.THEMES:
		app.state.theme = theme_key
		app.handle("tactics")
		await _settle()
		_check(app.tactics.visible and app.tactics.get("_start_button") != null, "六主题应能打开战棋编队：" + theme_key)
	app.handle("tactics")
	await _settle()
	_check(app.tactics.visible and app.modal_key == "tactics" and not app.tactics.started, "房间入口应打开编队页面")
	_check(app.tactics.roster_indices.size() == 4, "默认战队由已有宠物组成")
	app.handle("tacticsstart")
	await _settle()
	var screen: Control = app.tactics
	screen.set_process(false)
	var battle: RefCounted = screen.battle
	var initial_cells: Dictionary = {}
	for initial_unit in battle.units:
		initial_cells[int(initial_unit.id)] = initial_unit.cell
	_check(screen.started and battle.units[0].name == original_pets[0].name, "开始后应保留宠物身份")
	_check(screen.get("_squad_buttons").get_child_count() == 4, "侧栏只列出我方宠物")
	_check(str(screen.get("_status").text).contains("共享行动点") and not str(screen.get("_status").text).contains("宠物行动点"), "顶部状态应显示阵营共享行动点")
	_check(int(battle.action_points.ally) == Battle.TURN_AP, "开局应设置我方共享行动点")
	var hidden_opponent: Dictionary = battle.get_unit(100)
	screen._cell_hovered(hidden_opponent.cell)
	_check(not screen.get("_log").text.contains(hidden_opponent.name), "鼠标悬停迷雾中的敌人不能泄露名字或属性")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1920, 1080)
		await _settle()
		var unit_one: Dictionary = battle.get_unit(1)
		_click_canvas(screen.board, screen.board._cell_rect(unit_one.cell).get_center())
		await _settle()
		_check(screen.selected_id == 1, "窗口缩放后点击棋子应选中真实宠物")
		var next_cell: Vector2i = unit_one.cell + Vector2i.RIGHT
		_click_canvas(screen.board, screen.board._cell_rect(next_cell).get_center())
		await _settle()
		_check(unit_one.cell == next_cell and int(battle.action_points.ally) == Battle.TURN_AP - 1, "窗口像素坐标点击移动应命中格子并消耗共享一点")
		screen.select_unit(0)
	for dimensions in [Vector2i(1920, 1080), Vector2i(480, 720), Vector2i(1120, 960)]:
		root.size = dimensions
		await _settle()
		_check(screen.board.get_global_rect().end.x <= screen.size.x + 1 and screen.board.get_global_rect().end.y <= screen.size.y + 1, "棋盘应适应窗口尺寸")
		_check(screen.get("_sidebar").get_global_rect().end.x <= screen.size.x + 1 and screen.get("_sidebar").get_global_rect().end.y <= screen.size.y + 1, "窄窗口操作面板应在屏幕内")
		_check(screen.get("_header").size.y <= 132, "标题不能因初始容器尺寸扩张遮挡棋盘")
	root.size = Vector2i(320, 300)
	await _settle()
	_check(screen.get("_page_scroll").get_global_rect().end.y <= screen.size.y + 1, "极矮窗口应通过整页滚动保持内容可访问")
	_check(screen.get("_sidebar").position.y >= screen.board.position.y + screen.board.size.y, "极矮窗口的棋盘与操作面板不能重叠")
	root.size = Vector2i(1120, 960)
	await _settle()

	# 部署必须由按钮进入模式，再从绿色合法格放置；部署不消耗共享行动点。
	var action_points_before_deploy: int = battle.action_points.ally
	var deploy_budget_before: int = battle.deploy_budget.ally
	await _click_sidebar_button(screen, screen.get("_deploy_button"))
	_check(screen.action_mode == "deploy", "部署按钮应进入部署模式")
	var ally_soldier_cell := Vector2i(3, 12)
	_check(screen.board.deployment_cells.has(ally_soldier_cell), "我方已知控制区的可见空格应标为合法部署格")
	await _click_cell(screen, ally_soldier_cell)
	var ally_soldier: Dictionary = battle.unit_at(ally_soldier_cell)
	_check(ally_soldier.get("kind", "") == "soldier" and ally_soldier.side == "ally", "点击合法格应新增我方小兵")
	_check(battle.deploy_budget.ally == deploy_budget_before - 1 and battle.action_points.ally == action_points_before_deploy, "部署消耗名额但不消耗共享行动点")
	_check(screen.get("_squad_buttons").get_child_count() == 4, "部署小兵后侧栏仍只列出宠物")
	var selected_before_soldier_click: int = screen.selected_id
	var ap_before_soldier_click: int = battle.action_points.ally
	await _click_cell(screen, ally_soldier_cell)
	_check(screen.selected_id == selected_before_soldier_click and battle.action_points.ally == ap_before_soldier_click, "点击己方小兵不能选中或直接操作它")

	# 加入一个敌方小兵响应夹具，后续所有响应通过 screen._process 手动驱动。
	var saved_phase: String = battle.phase
	battle.phase = "enemy"
	var enemy_soldier_result: Dictionary = battle.deploy_soldier("enemy", Vector2i(20, 10))
	battle.phase = saved_phase
	_check(enemy_soldier_result.get("ok", false), "敵方控制区应能部署响应测试小兵")
	var enemy_soldier: Dictionary = battle.get_unit(int(enemy_soldier_result.get("id", -1)))
	if not enemy_soldier.is_empty():
		initial_cells[int(enemy_soldier.id)] = Vector2i(20, 10)
		enemy_soldier.cell = Vector2i(4, 10)
	initial_cells[int(ally_soldier.id)] = ally_soldier_cell
	battle.refresh_visibility()

	var pet_zero: Dictionary = battle.get_unit(0)
	var pet_one: Dictionary = battle.get_unit(1)
	var expected_ap := int(battle.action_points.ally)
	await _click_cell(screen, Vector2i(3, 10))
	_check(pet_zero.cell == Vector2i(3, 10) and battle.action_points.ally == expected_ap - 1, "第一只宠物移动消耗一点共享行动点；位置=%s/AP=%d/%d/phase=%s" % [str(pet_zero.cell), battle.action_points.ally, expected_ap, battle.phase])
	_check(battle.has_pending_reactions(), "宠物成功行动后应排入敌方小兵响应")
	var reactions_after_first: int = await _drive_battle_process(screen, battle)
	_check(reactions_after_first > 0 and not battle.has_pending_reactions(), "小兵响应应由界面 process 队列完整处理")
	_check(int(battle.action_points.ally) == expected_ap - 1, "敌方小兵响应不能额外扣除我方共享行动点")
	var expected_after_first := int(battle.action_points.ally)
	screen.select_unit(1)
	var second_destination: Vector2i = pet_one.cell + Vector2i.RIGHT
	var second_move_cost: int = battle.movement_cost(1, second_destination)
	await _click_cell(screen, second_destination)
	_check(second_move_cost > 0 and pet_one.cell == second_destination and battle.action_points.ally == expected_after_first - second_move_cost, "切换第二只宠物后仍扣同一共享行动点池；位置=%s/目标=%s/费用=%d/AP=%d/预计=%d/phase=%s/selected=%d" % [str(pet_one.cell), str(second_destination), second_move_cost, battle.action_points.ally, expected_after_first - second_move_cost, battle.phase, screen.selected_id])
	var expected_after_second := int(battle.action_points.ally)
	await _drive_battle_process(screen, battle)
	_check(int(battle.action_points.ally) == expected_after_second, "第二次小兵响应不能额外消耗共享行动点")
	var guard_button: Button = screen.get("_guard_button")
	await _click_sidebar_button(screen, guard_button)
	_check(pet_one.guard and battle.action_points.ally == expected_after_second - Battle.DEFEND_COST, "防御按钮扣除阵营共享点数；guard=%s/AP=%d/expected=%d" % [str(pet_one.guard), battle.action_points.ally, expected_after_second - Battle.DEFEND_COST])
	_check(str(screen.get("_status").text).contains("共享行动点"), "行动后顶部仍显示共享点数")
	var expected_after_guard := int(battle.action_points.ally)
	await _drive_battle_process(screen, battle)
	_check(int(battle.action_points.ally) == expected_after_guard, "防御引发的小兵响应不能额外扣除共享行动点")
	await _click_button(screen.get("_end_button"))
	_check(battle.phase == "enemy", "结束回合按钮应开始敌方阶段；phase=%s/AP=%d" % [battle.phase, battle.action_points.ally])
	var enemy_round_steps: int = await _drive_battle_process(screen, battle, 200)
	await _settle()
	_check(enemy_round_steps < 200 and battle.phase == "player", "敌方宠物与小兵响应应在安全上限内完成；steps=%d/phase=%s/EnemyAP=%d" % [enemy_round_steps, battle.phase, battle.action_points.enemy])
	_check(int(battle.action_points.ally) == Battle.TURN_AP, "新回合应恢复我方共享行动点；AP=%d/phase=%s" % [battle.action_points.ally, battle.phase])
	_check(not pet_one.guard, "新回合应解除宠物防御；guard=%s/phase=%s" % [str(pet_one.guard), battle.phase])

	# 普通技能按真实技能面板、目标预览和棋盘点击执行；充能属于单只宠物。
	_restore_battle_formation(battle, initial_cells)
	pet_zero.cell = Vector2i(10, 10)
	pet_one.cell = Vector2i(10, 11)
	var skill_targets := [battle.get_unit(100), battle.get_unit(101), battle.get_unit(102)]
	skill_targets[0].cell = Vector2i(11, 10)
	skill_targets[1].cell = Vector2i(12, 10)
	skill_targets[2].cell = Vector2i(11, 11)
	for skill_target in skill_targets:
		skill_target.max_hp = 60
		skill_target.hp = 60
	battle.refresh_visibility()
	screen.select_unit(0)
	await _click_sidebar_button(screen, screen.get("_skills_button"))
	_check(screen.action_mode == "skill" and screen.get("_skills_panel").visible, "释放技能按钮应打开技能面板")
	var skill_buttons: Dictionary = screen.get("_skill_buttons")
	_check(skill_buttons.size() == 3 and skill_buttons.has("pulse") and skill_buttons.has("shockwave") and skill_buttons.has("overload"), "技能面板应列出 pulse、shockwave 和 overload")
	_check(skill_buttons.get("overload").disabled and int(pet_zero.charge) == 0, "充能未满时大招按钮应禁用")
	var charge_test_ap := int(battle.action_points.ally)
	var hp_before_wave: Array[int] = [skill_targets[0].hp, skill_targets[1].hp, skill_targets[2].hp]
	await _click_sidebar_button(screen, skill_buttons["shockwave"])
	_check(screen.selected_skill_id == "shockwave" and str(screen.get("_skill_info").text).contains("震荡波"), "点击技能按钮应切换到震荡波并更新技能信息")
	_check(screen.board.skill_targets.has(skill_targets[0].cell), "可见且合法的敌人应显示橙色技能目标框")
	await _hover_cell(screen, skill_targets[0].cell)
	_check(screen.board.skill_area.size() == 5 and screen.board.skill_hit_cells.size() == 3, "震荡波悬停应显示菱形范围及三个已知命中格")
	_check(screen.get("_log").text.contains("对手1") and screen.get("_log").text.contains("对手2") and screen.get("_log").text.contains("对手3"), "技能预览应展示多个可见目标的伤害")
	await _click_cell(screen, skill_targets[0].cell)
	_check(skill_targets[0].hp < hp_before_wave[0] and skill_targets[1].hp < hp_before_wave[1] and skill_targets[2].hp < hp_before_wave[2], "施放震荡波应命中范围内的多个敌人")
	_check(battle.action_points.ally == charge_test_ap - 6 and pet_zero.charge == 1 and pet_one.charge == 0, "普通技能扣共享6点并只增加施法宠物的充能")
	var shockwave_reactions: int = await _drive_battle_process(screen, battle)
	_check(shockwave_reactions == 1 and not battle.has_pending_reactions(), "一次技能施放应让敌方小兵只响应一次")

	# 第二只宠物使用不同普通技能；其充能独立于第一只宠物。
	screen.select_unit(1)
	skill_buttons = screen.get("_skill_buttons")
	await _click_sidebar_button(screen, skill_buttons["pulse"])
	_check(screen.selected_skill_id == "pulse", "第二只宠物应能选择 pulse")
	var pulse_cost_before := int(battle.action_points.ally)
	var second_target_hp := int(skill_targets[2].hp)
	await _hover_cell(screen, skill_targets[2].cell)
	_check(screen.board.skill_area.size() == 1 and screen.board.skill_hit_cells.size() == 1, "pulse 悬停应只预览单体目标")
	await _click_cell(screen, skill_targets[2].cell)
	_check(skill_targets[2].hp < second_target_hp and battle.action_points.ally == pulse_cost_before - 4, "pulse 应命中单体并扣共享4点")
	_check(pet_one.charge == 1 and pet_zero.charge == 1, "第二只宠物施法只增加自己的充能")
	await _drive_battle_process(screen, battle)
	_restore_battle_formation(battle, initial_cells)
	_check(pet_zero.charge == 1 and pet_one.charge == 1, "普通技能充能应在敌方回合前保留")
	await _click_button(screen.get("_end_button"))
	_check(battle.phase == "enemy", "技能测试后结束回合应开始敌方阶段")
	var skill_enemy_steps: int = await _drive_battle_process(screen, battle, 200)
	await _settle()
	_check(skill_enemy_steps < 200 and battle.phase == "player", "技能测试后的敌方回合及小兵响应应完整结束")
	_check(battle.action_points.ally == Battle.TURN_AP and pet_zero.charge == 1 and pet_one.charge == 1, "跨回合共享点重置且两只宠物各自保留充能")

	# 思考期间不推进养成，也不在返回时补算这段时间。
	var age_before: int = app.state.pets[0].ageTicks
	app.game.now_ms -= 20000
	app._process(0.1)
	_check(app.state.pets[0].ageTicks == age_before, "战棋期间应暂停养成衰减")

	# 下一轮使用独立宠物充能三格，实际施放大招并确认共享花费和一次小兵响应。
	_restore_battle_formation(battle, initial_cells)
	pet_zero.cell = Vector2i(10, 10)
	pet_one.cell = Vector2i(10, 11)
	var target: Dictionary = battle.get_unit(100)
	var area_targets: Array[Dictionary] = [target, battle.get_unit(101), battle.get_unit(102)]
	area_targets[0].cell = Vector2i(11, 10)
	area_targets[1].cell = Vector2i(12, 10)
	area_targets[2].cell = Vector2i(11, 11)
	for area_target in area_targets:
		area_target.max_hp = 60
		area_target.hp = 60
	battle.refresh_visibility()
	screen.select_unit(0)
	await _click_sidebar_button(screen, screen.get("_skills_button"))
	skill_buttons = screen.get("_skill_buttons")
	await _click_sidebar_button(screen, skill_buttons["pulse"])
	await _hover_cell(screen, target.cell)
	var charge_before_pulse := int(pet_zero.charge)
	var ap_before_pulse := int(battle.action_points.ally)
	var pulse_reaction_count := _living_soldiers(battle, "enemy")
	await _click_cell(screen, target.cell)
	_check(pet_zero.charge == charge_before_pulse + 1 and battle.action_points.ally == ap_before_pulse - 4, "pulse命中后充能+1且消耗共享4点")
	var pulse_reactions: int = await _drive_battle_process(screen, battle)
	_check(pulse_reactions == pulse_reaction_count and not battle.has_pending_reactions(), "普通技能命中后每个敌小兵应恰好响应一次；响应步数=%d/施法前敌兵数=%d" % [pulse_reactions, pulse_reaction_count])
	await _click_sidebar_button(screen, skill_buttons["shockwave"])
	await _hover_cell(screen, target.cell)
	_check(screen.board.skill_hit_cells.size() == 3, "pet充到大招前shockwave仍能预览多目标")
	var ap_before_shockwave := int(battle.action_points.ally)
	await _click_cell(screen, target.cell)
	_check(pet_zero.charge == charge_before_pulse + 2 and battle.action_points.ally == ap_before_shockwave - 6, "第二次普通技能继续独立累加充能并扣6点")
	await _drive_battle_process(screen, battle)
	_check(pet_zero.charge == Skills.CHARGE_MAX, "同一宠物成功命中三次普通技能后充能满格")
	_check(not screen.get("_skill_buttons")["overload"].disabled, "充满三格后大招按钮应启用")
	await _click_sidebar_button(screen, screen.get("_skill_buttons")["overload"])
	_check(screen.selected_skill_id == "overload" and str(screen.get("_skill_info").text).contains("消耗 3 格充能"), "大招按钮应显示消耗三格充能")
	await _hover_cell(screen, target.cell)
	_check(screen.board.skill_area.size() == 13 and screen.board.skill_hit_cells.has(area_targets[0].cell) and screen.board.skill_hit_cells.has(area_targets[1].cell) and screen.board.skill_hit_cells.has(area_targets[2].cell), "overload悬停应显示13格几何范围并标记三名已知宠物命中格；area=%d/hits=%d/cell=%s/targets=%s" % [screen.board.skill_area.size(), screen.board.skill_hit_cells.size(), str(target.cell), str(screen.board.skill_targets)])
	var ap_before_ultimate := int(battle.action_points.ally)
	await _click_cell(screen, target.cell)
	var ultimate_reaction_count := _living_soldiers(battle, "enemy")
	_check(pet_zero.charge == 0 and battle.action_points.ally == ap_before_ultimate - 8, "大招应消耗共享8点并清空施法宠物的充能")
	var ultimate_reactions: int = await _drive_battle_process(screen, battle)
	_check(ultimate_reactions == ultimate_reaction_count and not battle.has_pending_reactions(), "大招结算后每个敌方小兵应恰好响应一次且不递归；响应=%d/施法后存活=%d" % [ultimate_reactions, ultimate_reaction_count])
	_check(pet_one.charge == 1, "施放大招不能消耗第二只宠物的独立充能")

	# 用普通技能结束残局，检查主场景奖励只入账一次。
	for enemy in battle.units:
		if enemy.side == "enemy" and enemy.get("kind", "pet") == "pet":
			enemy.hp = 0
	target.cell = Vector2i(11, 10)
	target.hp = 1
	for enemy in battle.units:
		if enemy.side == "enemy" and enemy.get("kind", "pet") == "soldier":
			enemy.hp = 0
	battle.refresh_visibility()
	await _click_sidebar_button(screen, screen.get("_skill_buttons")["pulse"])
	await _hover_cell(screen, target.cell)
	_check(screen.get("_log").text.contains("预计伤害") and screen.board.skill_targets.has(target.cell), "最终pulse目标应显示已知伤害预览")
	var coins_before := int(app.state.coins)
	var points_before := int(app.state.points)
	var exp_before := float(app.state.exp)
	await _click_cell(screen, target.cell)
	_check(battle.phase == "won" and screen.settled, "pulse消灭最后一只敌方宠物应显示胜利并结算")
	_check(app.state.coins == coins_before + 60 and app.state.points == points_before + 10 and app.state.exp == exp_before + 20, "奖励应统一通过主场景入账")
	screen._refresh_battle()
	screen._refresh_battle()
	_check(app.state.coins == coins_before + 60, "刷新胜利界面不能重复发奖")
	_check(app.state.pets[0].health == original_pets[0].health, "战斗伤害不能写回养成生命")
	screen.request_close()
	_check(not screen.visible and app.modal_key == "", "胜负界面返回应恢复房间")
	app._process(0.001)
	_check(app.state.pets[0].ageTicks == age_before, "退出战棋后不能补算暂停时间")

	# 结束按钮必须真实返回编队，且不能重复领取奖励。
	app.handle("tactics")
	app.handle("tacticsstart")
	await _settle()
	screen = app.tactics
	screen.set_process(false)
	screen.battle.phase = "lost"
	screen._refresh_battle()
	await _click_button(screen.get("_end_button"))
	_check(not screen.started and screen.get("_roster_panel").visible, "战斗结束后的按钮应真正返回编队")
	_check(app.state.coins == coins_before + 60, "重开编队不能重复领取旧局奖励")
	screen.close_game()
	app.handle("tactics")
	app.handle("tacticsstart")
	await _settle()
	screen = app.tactics
	screen.set_process(false)
	await _click_button(screen.get("_exit_button"))
	_check(screen.visible and screen.leave_pending, "进行中的战斗退出需要一次界面确认")
	await _click_button(screen.get("_exit_button"))
	_check(not screen.visible and app.modal_key == "", "确认退出后应回到房间")
	app.queue_free()
	await process_frame
	print("宠物战棋入口、共享行动点、部署、窗口、暂停养成与奖励集成验证通过" if failures == 0 else "战棋集成验证失败：%d" % failures)
	quit(0 if failures == 0 else 1)
