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
	if scroll.is_ancestor_of(button):
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

func _drive_reactions(screen: Control, battle: RefCounted, limit: int = 200) -> int:
	var steps := 0
	while battle.has_pending_reactions() and steps < limit:
		screen._process(1.0)
		steps += 1
		if DisplayServer.get_name() != "headless": await process_frame
	return steps

func _drive_until_player(screen: Control, battle: RefCounted, limit: int = 2000) -> int:
	var steps := 0
	while (battle.phase != "player" or battle.has_pending_reactions()) and steps < limit:
		screen._process(1.0)
		steps += 1
		if DisplayServer.get_name() != "headless": await process_frame
	return steps

func _drive_until_next_round(screen: Control, battle: RefCounted, old_round: int, limit: int = 2000) -> int:
	var steps := 0
	while battle.round_number == old_round and steps < limit:
		screen._process(1.0)
		steps += 1
		if DisplayServer.get_name() != "headless": await process_frame
	return steps

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
	_check(screen.started and battle.units[0].name == original_pets[0].name, "开始后应保留宠物身份")
	_check(screen.get("_squad_buttons").get_child_count() == 4, "侧栏只列出我方宠物，不把自动小兵放进宠物栏")
	_check(_living_soldiers(battle, "ally") == 6 and _living_soldiers(battle, "enemy") == 6, "开局双方应各有六名小兵在前线")
	_check(str(screen.get("_status").text).contains("双方交替") and str(screen.get("_status").text).contains("共享行动点"), "状态栏应说明双方交替及阵营共享行动点")
	_check(str(screen.get("_status").text).contains("我方指令"), "首轮开局应显示当前我方指令权")
	_check(int(battle.action_points.ally) == Battle.TURN_AP and int(battle.action_points.enemy) == Battle.TURN_AP, "开局双方各有完整共享行动点")
	_check(str(screen.get("_end_button").text).contains("结束本轮") and str(screen.get("_end_button").text).contains("空格"), "结束按钮应明确显示结束本轮与空格快捷键")
	var setup_help_found := false
	for child in screen.get("_roster_body").get_children():
		if child is Label and str(child.text).contains("增援") and str(child.text).contains("小兵在前方"):
			setup_help_found = true
	_check(setup_help_found, "开场帮助应介绍前线兵线及前方增援")
	var hidden_opponent: Dictionary = battle.get_unit(100)
	screen._cell_hovered(hidden_opponent.cell)
	_check(not screen.get("_log").text.contains(hidden_opponent.name), "鼠标悬停迷雾中的敌人不能泄露名字或属性")

	# 图形环境验证窗口缩放后真实宠物选择、移动和指令交替。
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1920, 1080)
		await _settle()
		var unit_one: Dictionary = battle.get_unit(1)
		_click_canvas(screen.board, screen.board._cell_rect(unit_one.cell).get_center())
		await _settle()
		_check(screen.selected_id == 1, "窗口缩放后点击棋子应选中真实宠物")
		var options: Dictionary = battle.reachable_cells(1)
		var destination := Vector2i(-1, -1)
		for cell in options.keys():
			if cell != unit_one.cell:
				destination = cell
				break
		_check(destination.x >= 0, "开局宠物应有至少一个可走格")
		if destination.x >= 0:
			_click_canvas(screen.board, screen.board._cell_rect(destination).get_center())
			await _settle()
			_check(unit_one.cell == destination and battle.phase == "player" and battle.has_pending_reactions(), "真实像素点击移动应命中格子并先排入小兵响应")
			var response_count := _living_soldiers(battle, "enemy")
			var response_steps: int = await _drive_reactions(screen, battle)
			_check(response_steps == response_count and battle.phase == "enemy" and not battle.has_pending_reactions(), "敌方六名小兵应各响应一次，再交出指令权")
			var locked_pet: Dictionary = battle.get_unit(0)
			var locked_cell: Vector2i = locked_pet.cell
			_click_canvas(screen.board, screen.board._cell_rect(locked_cell).get_center())
			await _settle()
			_check(locked_pet.cell == locked_cell and screen.selected_id == 1, "敌方指令权期间应锁住我方宠物输入")
			var enemy_ap_before: int = battle.action_points.enemy
			var relay_steps: int = await _drive_until_player(screen, battle)
			_check(relay_steps > 0 and relay_steps < 2000 and battle.phase == "player", "敌方宠物完成一次指令及我方小兵响应后应交回操作权")
			_check(battle.action_points.ally == Battle.TURN_AP - int(options[destination]), "双方轮换时我方共享行动点不回满")
			_check(battle.action_points.enemy < enemy_ap_before or battle.round_number > 1, "敌方宠物指令应消耗敌方共享行动点")
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
	if battle.phase != "player":
		await _drive_until_player(screen, battle)
	_check(battle.phase == "player", "继续功能测试前应通过真实自动行动轮回到我方指令")

	# 真实按钮部署到已知、稳定且可见的控制区；免费部署不交出指令权。
	var action_points_before_deploy: int = battle.action_points.ally
	var deploy_budget_before: int = battle.deploy_budget.ally
	await _click_sidebar_button(screen, screen.get("_deploy_button"))
	_check(screen.action_mode == "deploy", "部署按钮应进入部署模式")
	var legal_cells: Array = battle.deployment_cells("ally").keys()
	_check(not legal_cells.is_empty(), "开局稳定控制区应提供可见合法增援格")
	if not legal_cells.is_empty():
		var ally_soldier_cell: Vector2i = legal_cells[0]
		_check(screen.board.deployment_cells.has(ally_soldier_cell), "合法部署格应由棋盘显示绿色范围")
		await _click_cell(screen, ally_soldier_cell)
		var ally_soldier: Dictionary = battle.unit_at(ally_soldier_cell)
		_check(ally_soldier.get("kind", "") == "soldier" and ally_soldier.side == "ally", "点击合法格应新增我方小兵")
		_check(battle.deploy_budget.ally == deploy_budget_before - 1 and battle.action_points.ally == action_points_before_deploy and battle.phase == "player", "部署消耗名额但不消耗共享行动点或交出指令权")
		_check(screen.get("_squad_buttons").get_child_count() == 4, "部署后宠物栏仍只列宠物")
		var selected_before_soldier_click: int = screen.selected_id
		await _click_cell(screen, ally_soldier_cell)
		_check(screen.selected_id == selected_before_soldier_click and battle.action_points.ally == action_points_before_deploy, "点击己方小兵不能选中或直接操作它")

	# 正常结束本轮交出全部剩余点数；只有敌方也结束后才重置双方AP并交换先手。
	var round_before_end: int = battle.round_number
	var ally_ap_before_end: int = battle.action_points.ally
	await _click_button(screen.get("_end_button"))
	_check(battle.round_done.ally and battle.phase == "enemy", "结束本轮应标记我方已结束并交给敌方")
	_check(battle.action_points.ally == ally_ap_before_end and battle.round_number == round_before_end, "我方结束本轮时保留未用点数，不能提前结算或回满")
	_check(str(screen.get("_status").text).contains("已结束"), "状态栏应标出已经结束本轮的一方")
	var full_round_steps: int = await _drive_until_next_round(screen, battle, round_before_end, 2000)
	await _settle()
	_check(full_round_steps > 0 and full_round_steps < 2000 and battle.round_number == round_before_end + 1, "敌方用完/结束剩余指令后应在安全上限内结算整轮")
	_check(battle.action_points.ally == Battle.TURN_AP and battle.action_points.enemy == Battle.TURN_AP, "双方结束后才同时重置共享行动点")
	_check(battle.round_starter == "enemy" and battle.phase == "enemy", "下一輪应交换先手")
	var next_enemy_steps: int = await _drive_until_player(screen, battle)
	_check(next_enemy_steps > 0 and battle.phase == "player", "敌方先手实际下达一条指令后应交给我方")

	# 技能预览与施法使用真实 UI。此隔离夹具只令敌方标记本轮已结束，
	# 让我方合法连续演示技能，不修改移动/响应/整轮结算行为。
	var pet_zero: Dictionary = battle.get_unit(0)
	var pet_one: Dictionary = battle.get_unit(1)
	var skill_targets: Array[Dictionary] = [battle.get_unit(100), battle.get_unit(101), battle.get_unit(102)]
	pet_zero.cell = Vector2i(10, 10)
	pet_one.cell = Vector2i(10, 11)
	for index in battle.units.size():
		var unit: Dictionary = battle.units[index]
		if unit.side == "ally" and unit.get("kind", "pet") == "pet" and unit.id not in [0, 1]: unit.cell = Vector2i(0, index)
		if unit.side == "enemy" and unit.get("kind", "pet") == "pet" and unit.id not in [100, 101, 102]: unit.cell = Vector2i(23, index)
	skill_targets[0].cell = Vector2i(11, 10)
	skill_targets[1].cell = Vector2i(12, 10)
	skill_targets[2].cell = Vector2i(11, 11)
	for target in skill_targets:
		target.max_hp = 100
		target.hp = 100
	pet_zero.charge = 0
	pet_one.charge = 0
	battle.action_points.ally = Battle.TURN_AP
	battle.round_done.ally = false
	battle.round_done.enemy = true
	battle.phase = "player"
	battle.refresh_visibility()
	screen.select_unit(0)
	await _click_sidebar_button(screen, screen.get("_skills_button"))
	_check(screen.action_mode == "skill" and screen.get("_skills_panel").visible, "释放技能按钮应打开技能面板")
	var skill_buttons: Dictionary = screen.get("_skill_buttons")
	_check(skill_buttons.size() == 3 and skill_buttons.has("pulse") and skill_buttons.has("shockwave") and skill_buttons.has("overload"), "技能面板应列出三招")
	_check(skill_buttons.get("overload").disabled and int(pet_zero.charge) == 0, "充能未满时大招按钮应禁用")
	var ap_before_wave: int = battle.action_points.ally
	var hp_before_wave: Array[int] = [skill_targets[0].hp, skill_targets[1].hp, skill_targets[2].hp]
	await _click_sidebar_button(screen, skill_buttons["shockwave"])
	_check(screen.selected_skill_id == "shockwave", "点击技能按钮应选择震荡波")
	_check(screen.board.skill_targets.has(skill_targets[0].cell), "可见且合法的敌人应显示技能目标框")
	await _hover_cell(screen, skill_targets[0].cell)
	_check(screen.board.skill_area.size() == 5 and screen.board.skill_hit_cells.size() == 3, "震荡波悬停显示范围及多个已知命中格")
	_check(screen.get("_log").text.contains("对手1") and screen.get("_log").text.contains("对手2") and screen.get("_log").text.contains("对手3"), "技能预览应展示多个可见目标的伤害")
	await _click_cell(screen, skill_targets[0].cell)
	_check(skill_targets[0].hp < hp_before_wave[0] and skill_targets[1].hp < hp_before_wave[1] and skill_targets[2].hp < hp_before_wave[2], "震荡波应命中范围内多个敌人")
	_check(battle.action_points.ally == ap_before_wave - 6 and pet_zero.charge == 1, "施法扣共享行动点并只增加施法宠物充能")
	var skill_reaction_count: int = _living_soldiers(battle, "enemy")
	var shockwave_reactions: int = await _drive_reactions(screen, battle)
	_check(shockwave_reactions == skill_reaction_count, "技能行动后对方所有存活小兵各响应一次")
	_check(battle.phase == "player", "夹具中对方已结束后，小兵响应完成应继续我方指令")
	screen.select_unit(1)
	await _click_sidebar_button(screen, skill_buttons["pulse"])
	var pet_one_target_hp: int = skill_targets[2].hp
	await _click_cell(screen, skill_targets[2].cell)
	_check(skill_targets[2].hp < pet_one_target_hp and pet_one.charge == 1 and pet_zero.charge == 1, "第二只宠物的普通技能应命中且充能独立")
	await _drive_reactions(screen, battle)

	# 独立充能夹具用三次 pulse（12点）和 ultimate（8点），不跨回合伪造指令权。
	pet_zero.charge = 0
	pet_one.charge = 0
	battle.action_points.ally = Battle.TURN_AP
	battle.round_done.ally = false
	battle.round_done.enemy = true
	battle.phase = "player"
	battle.refresh_visibility()
	screen.select_unit(0)
	await _click_sidebar_button(screen, screen.get("_skills_button"))
	skill_buttons = screen.get("_skill_buttons")
	await _click_sidebar_button(screen, skill_buttons["pulse"])
	var pulse_target: Dictionary = skill_targets[0]
	for charge_index in 3:
		var target_hp_before: int = pulse_target.hp
		await _hover_cell(screen, pulse_target.cell)
		_check(screen.board.skill_area.size() == 1 and screen.board.skill_hit_cells.size() == 1, "pulse预览应标记单体可见敌人")
		await _click_cell(screen, pulse_target.cell)
		_check(pulse_target.hp < target_hp_before and pet_zero.charge == charge_index + 1, "每次成功命中普通技能后充能加一")
		await _drive_reactions(screen, battle)
	_check(not skill_buttons["overload"].disabled and pet_zero.charge == Skills.CHARGE_MAX, "充满三格后大招按钮启用")
	await _click_sidebar_button(screen, skill_buttons["overload"])
	_check(screen.selected_skill_id == "overload" and str(screen.get("_skill_info").text).contains("消耗 3 格充能"), "大招按钮应显示消耗三格充能")
	await _hover_cell(screen, pulse_target.cell)
	_check(screen.board.skill_area.size() == 13 and screen.board.skill_hit_cells.size() >= 1, "大招悬停应显示13格几何范围与可见命中")
	var ultimate_ap_before: int = battle.action_points.ally
	await _click_cell(screen, pulse_target.cell)
	_check(pet_zero.charge == 0 and battle.action_points.ally == ultimate_ap_before - 8, "大招消耗8共享行动点并清空施法者充能")
	await _drive_reactions(screen, battle)
	_check(pet_one.charge == 0, "大招不能消耗另一只宠物的充能")

	# 战棋期间暂停养成，不在返回时补算这段时间。
	var age_before: int = app.state.pets[0].ageTicks
	app.game.now_ms -= 20000
	app._process(0.1)
	_check(app.state.pets[0].ageTicks == age_before, "战棋期间应暂停养成衰减")

	# 终局奖励使用独立残局 fixture，通过真实 pulse 点击结束；结算只入账一次。
	for enemy in battle.units:
		if enemy.side == "enemy" and enemy.get("kind", "pet") == "pet": enemy.hp = 0
	var last_enemy: Dictionary = skill_targets[0]
	last_enemy.hp = 1
	last_enemy.cell = Vector2i(11, 10)
	pet_zero.cell = Vector2i(10, 10)
	battle.action_points.ally = Battle.TURN_AP
	battle.round_done.ally = false
	battle.round_done.enemy = true
	battle.phase = "player"
	battle.refresh_visibility()
	screen.select_unit(0)
	await _click_sidebar_button(screen, screen.get("_skills_button"))
	skill_buttons = screen.get("_skill_buttons")
	await _click_sidebar_button(screen, skill_buttons["pulse"])
	await _hover_cell(screen, last_enemy.cell)
	_check(screen.get("_log").text.contains("预计伤害") and screen.board.skill_targets.has(last_enemy.cell), "残局目标应显示可见伤害预览")
	var coins_before := int(app.state.coins)
	var points_before := int(app.state.points)
	var exp_before := float(app.state.exp)
	await _click_cell(screen, last_enemy.cell)
	_check(battle.phase == "won" and screen.settled, "消灭最后一只敌方宠物应胜利并结算")
	_check(app.state.coins == coins_before + 60 and app.state.points == points_before + 10 and app.state.exp == exp_before + 20, "奖励应统一通过主场景入账")
	screen._refresh_battle()
	screen._refresh_battle()
	_check(app.state.coins == coins_before + 60, "刷新胜利界面不能重复发奖")
	_check(app.state.pets[0].health == original_pets[0].health, "战斗伤害不能写回养成生命")
	screen.request_close()
	_check(not screen.visible and app.modal_key == "", "胜负界面返回应恢复房间")
	app._process(0.001)
	_check(app.state.pets[0].ageTicks == age_before, "退出战棋后不能补算暂停时间")

	# 结束按钮实际返回编队，且不重复领奖；进行中的战斗返回仍需双确认。
	app.handle("tactics")
	app.handle("tacticsstart")
	await _settle()
	screen = app.tactics
	screen.set_process(false)
	screen.battle.phase = "lost" # 仅模拟终局界面的返回入口。
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
	print("宠物战棋交替指令、前线部署、技能充能、窗口、暂停养成与奖励集成验证通过" if failures == 0 else "战棋集成验证失败：%d" % failures)
	quit(0 if failures == 0 else 1)
