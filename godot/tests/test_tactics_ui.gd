extends SceneTree

const Scene = preload("res://scenes/native_room.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition: failures += 1; printerr("失败：" + message)

func _settle() -> void:
	for index in 6: await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func _click_canvas(control: Control, point: Vector2) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	click.position = root.get_final_transform() * (control.get_global_transform() * point)
	root.push_input(click, false)
	click = click.duplicate(); click.pressed = false
	root.push_input(click, false)

func _run() -> void:
	var app: Variant = Scene.instantiate()
	app.preview_mode = true; root.add_child(app); app.set_process(false)
	for species in ["goose", "cat", "gpt"]:
		var pet: Dictionary = app.state.pets[0].duplicate(true)
		pet.species = species; pet.name = species; app.state.pets.append(pet)
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
	var battle: RefCounted = screen.battle
	_check(screen.started and battle.units[0].name == original_pets[0].name, "开始后应保留宠物身份")
	var hidden_opponent: Dictionary = battle.get_unit(100)
	screen._cell_hovered(hidden_opponent.cell)
	_check(not screen.get("_log").text.contains(hidden_opponent.name), "鼠标悬停迷雾中的敌人不能泄露名字或属性")
	if DisplayServer.get_name() != "headless":
		# 按实际窗口坐标点击，验证缩放后的棋盘输入与回合按钮。
		root.size = Vector2i(1920, 1080); await _settle()
		var unit_one: Dictionary = battle.get_unit(1)
		_click_canvas(screen.board, screen.board._cell_rect(unit_one.cell).get_center())
		_check(screen.selected_id == 1, "窗口缩放后点击棋子应选中真实宠物")
		var next_cell: Vector2i = unit_one.cell + Vector2i.RIGHT
		_click_canvas(screen.board, screen.board._cell_rect(next_cell).get_center())
		_check(unit_one.cell == next_cell and unit_one.ap == 1, "窗口像素坐标点击移动应命中棋盘格")
		screen.select_unit(0)
	for dimensions in [Vector2i(1920, 1080), Vector2i(480, 720), Vector2i(1120, 960)]:
		root.size = dimensions
		await _settle()
		_check(screen.board.get_global_rect().end.x <= screen.size.x + 1 and screen.board.get_global_rect().end.y <= screen.size.y + 1, "棋盘应适应窗口尺寸")
		_check(screen.get("_sidebar").get_global_rect().end.x <= screen.size.x + 1 and screen.get("_sidebar").get_global_rect().end.y <= screen.size.y + 1, "窄窗口操作面板应在屏幕内")
		_check(screen.get("_header").size.y <= 132, "标题不能因初始容器尺寸扩张遮挡棋盘")
	root.size = Vector2i(320, 300); await _settle()
	_check(screen.get("_page_scroll").get_global_rect().end.y <= screen.size.y + 1, "极矮窗口应通过整页滚动保持内容可访问")
	_check(screen.get("_sidebar").position.y >= screen.board.position.y + screen.board.size.y, "极矮窗口的棋盘与操作面板不能重叠")
	root.size = Vector2i(1120, 960); await _settle()
	# 通过棋盘输入路由执行移动与防御。
	var unit: Dictionary = battle.get_unit(0)
	screen._cell_clicked(unit.cell + Vector2i.RIGHT)
	_check(unit.ap == 1, "点击移动格应消耗一个行动点")
	screen.guard_selected()
	_check(unit.guard and unit.ap == 0, "防御按钮应作用于当前宠物")
	screen.end_turn()
	_check(battle.phase == "enemy", "结束回合按钮应开始敌方阶段")
	var safety := 0
	while battle.phase == "enemy" and safety < 32: battle.step_enemy(); safety += 1
	screen._refresh_battle()
	_check(battle.phase == "player" and unit.ap == 2 and not unit.guard, "新回合应恢复行动力并解除防御")
	# 思考期间不推进养成，也不在返回时补算这段时间。
	var age_before: int = app.state.pets[0].ageTicks
	app.game.now_ms -= 20000
	app._process(0.1)
	_check(app.state.pets[0].ageTicks == age_before, "战棋期间应暂停养成衰减")
	# 设置一击结束的残局，通过正常攻击路由结算并验证奖励只发一次。
	for cell in battle.tiles: battle.tiles[cell] = "ground"
	var target: Dictionary = battle.get_unit(100)
	unit.cell = Vector2i(10, 10); unit.ap = 2
	target.cell = Vector2i(11, 10); target.hp = 1
	for opponent in battle.units:
		if opponent.side == "enemy" and opponent.id != target.id: opponent.hp = 0
	battle.refresh_visibility()
	screen._set_mode("attack"); screen._cell_hovered(target.cell)
	_check(screen.get("_log").text.contains("预计伤害") and screen.get("_log").text.contains("HP 1/"), "可见敌人应能查看生命与攻击伤害预估")
	var coins_before := int(app.state.coins)
	var points_before := int(app.state.points)
	var exp_before := float(app.state.exp)
	screen._set_mode("attack"); screen._cell_clicked(target.cell)
	_check(battle.phase == "won" and screen.settled, "消灭最后敌人应显示胜利并结算")
	_check(app.state.coins == coins_before + 60 and app.state.points == points_before + 10 and app.state.exp == exp_before + 20, "奖励应统一通过主场景入账")
	screen._refresh_battle(); screen._refresh_battle()
	_check(app.state.coins == coins_before + 60, "刷新胜利界面不能重复发奖")
	_check(app.state.pets[0].health == original_pets[0].health, "战斗伤害不能写回养成生命")
	screen.request_close()
	_check(not screen.visible and app.modal_key == "", "胜负界面返回应恢复房间")
	app._process(0.001)
	_check(app.state.pets[0].ageTicks == age_before, "退出战棋后不能补算暂停时间")
	# 新一局实际按钮返回编队，不能再次领取旧局奖励。
	app.handle("tactics"); app.handle("tacticsstart")
	screen.battle.phase = "lost"; screen._refresh_battle()
	if DisplayServer.get_name() != "headless":
		await _settle()
		var end_button: Control = screen.get("_end_button")
		_click_canvas(end_button, end_button.size * 0.5)
	else: screen._end_or_restart()
	_check(not screen.started and screen.get("_roster_panel").visible, "战斗结束后的按钮应真正返回编队")
	_check(app.state.coins == coins_before + 60, "重开编队不能重复领取旧局奖励")
	screen.close_game()
	app.handle("tactics"); app.handle("tacticsstart")
	screen.request_close()
	_check(screen.visible and screen.leave_pending, "进行中的战斗退出需要一次界面确认")
	screen.request_close()
	_check(not screen.visible and app.modal_key == "", "确认退出后应回到房间")
	app.queue_free(); await process_frame
	print("宠物战棋入口、编队、窗口、行动、暂停养成与奖励集成验证通过" if failures == 0 else "战棋集成验证失败：%d" % failures)
	quit(0 if failures == 0 else 1)
