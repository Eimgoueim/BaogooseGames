extends SceneTree

const AppScene = preload("res://scenes/native_room.tscn")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("失败：" + message)

func _run() -> void:
	_check(ResourceLoader.exists("res://shaders/frosted_glass.gdshader"), "root modal dialog引用的磨砂玻璃shader必须存在")
	var app: Variant = AppScene.instantiate()
	app.preview_mode = true
	root.add_child(app)
	await process_frame
	await process_frame
	_check(app.state is Dictionary and app.game.state == app.state, "root启动后 domain 必须绑定 root state")
	_check(app.dungeon != null and app.audio != null and app.results_ui != null, "root应创建地牢、音频与抽卡结果界面")
	if app.state.is_empty() or app.game.state.is_empty():
		app.queue_free()
		await process_frame
		quit(1)
		return

	# 主场景的购买、使用与抚摸必须操作同一份领域状态。
	var start_coins := int(app.state.coins)
	var start_food := int(app.state.inv.basic)
	app.state.pets[app.state.active].hunger = 25.0
	app.handle("buy:basic")
	_check(int(app.state.coins) == start_coins - 10 and int(app.state.inv.basic) == start_food + 1, "buy action应从root进入domain并扣款加库存")
	app.handle("use:basic")
	_check(int(app.state.inv.basic) == start_food and float(app.active_pet().hunger) > 25.0, "use action应消耗食物并更新出战宠物")
	var affinity_before := float(app.active_pet().affinity)
	app.handle("pet")
	_check(float(app.active_pet().affinity) >= affinity_before + 2.0, "pet action应经过root路由并提升亲密度")

	# 重复领养先确认，再由 dlgok 派发 adopt_confirm。
	app.state.picked = true
	app.state.lv = 2
	app.state.pets[0].level = 2
	var pets_before: int = app.state.pets.size()
	app.handle("adoptpick:dragon")
	_check(app.modal_key == "dialog" and app.dialog_action == "adopt_confirm", "重复领养应进入确认对话框")
	_check(app.state.pets.size() == pets_before, "确认前不能添加重复宠物")
	app.handle("dlgok")
	_check(app.state.pets.size() == pets_before + 1 and app.state.pets[-1].species == "dragon", "确认后应通过domain添加重复宠物")

	# 抽卡结果在原版 1.5 秒动画结束后才出现。
	app.state.coins = 400
	app.gacha.random_source = func() -> float: return 0.999
	var pulls_before := int(app.state.pulls)
	var coins_before_pull := int(app.state.coins)
	app.handle("pull:10")
	_check(app.modal_key == "gacha" and app.results_ui.visible and app.results_ui.rolling, "pull action应打开抽卡动画结果面板")
	_check(int(app.state.pulls) == pulls_before + 10 and int(app.state.coins) == coins_before_pull - 100, "十连应扣100信用点并记录10抽")
	await create_timer(1.65).timeout
	await process_frame
	_check(not app.results_ui.rolling and app.results_ui.results_scroll.visible, "等待1.5秒后应展示抽卡结果")
	app.handle("gachaclose")
	_check(app.modal_key == "" and not app.results_ui.visible, "gachaclose应清理结果面板状态")

	# 出战只扣费一次，每次地牢奖励只由主场景入账一次。
	app.state.pets[app.state.active].energy = 75.68
	var dungeon_coins := int(app.state.coins)
	var points_before := int(app.state.points)
	var exp_before := float(app.state.pets[app.state.active].exp)
	app.handle("games")
	_check(app.modal_key == "rl" and app.dungeon.visible and app.dungeon.running, "games应通过root打开并自动开始地牢")
	_check(is_equal_approx(float(app.state.pets[app.state.active].energy), 65.68), "地牢费用应保留小数精力并扣除10")
	_check(app.audio.track == "dungeon", "地牢开始应切换到dungeon音轨")
	app.dungeon._emit_reward(0, 10, 0)
	_check(int(app.state.coins) == dungeon_coins + 10, "宝箱信用点经reward signal应只入账一次")
	app.dungeon._finish(true)
	_check(int(app.state.coins) == dungeon_coins + 110, "通关信用点经root应再入账100且只一次")
	_check(int(app.state.points) == points_before + 40 and float(app.state.pets[app.state.active].exp) >= exp_before + 16, "通关积分和经验应由root domain结算")
	app.dungeon.close_game()
	_check(app.modal_key == "" and app.audio.track == "home", "关闭地牢应回到home音轨并清除弹窗")

	# 导入后必须重新绑定领域状态，避免继续写旧字典。
	var imported: Dictionary = app.state.duplicate(true)
	imported.coins = 777
	imported.points = 31
	app.import_save(JSON.stringify(imported))
	_check(int(app.state.coins) == 777 and int(app.state.points) == 31, "root应导入合法存档")
	_check(app.game.state == app.state, "导入后domain必须重新绑定root state")
	app.game.state.coins = 778
	_check(int(app.state.coins) == 778, "导入后domain写入应落到root state")

	# 推进一个养成周期，并由主场景消费定时事件。
	var active_before_tick: Dictionary = app.state.pets[app.state.active].duplicate(true)
	var tick_events: Array = app.game.advance_time(5000)
	app.consume_events(tick_events)
	_check(int(app.state.pets[app.state.active].ageTicks) == int(active_before_tick.ageTicks) + 1, "养成domain每5秒应执行一次tick并增加年龄")

	# 重置需要确认，并保持主场景与领域逻辑引用同一字典。
	var root_state_identity: Dictionary = app.state
	var pets_before_reset: int = app.state.pets.size()
	app.handle("reset")
	_check(app.dialog_action == "reset_confirm" and app.state.pets.size() == pets_before_reset, "reset应先要求确认")
	app.handle("dlgok")
	_check(app.state.pets.size() == 1 and int(app.state.coins) == 60 and int(app.state.points) == 0, "确认reset应恢复默认进度")
	_check(app.state == root_state_identity and app.game.state == app.state, "reset应保留state字典并维持domain绑定")

	app.queue_free()
	await process_frame
	if failures == 0:
		print("完整游戏root/domain集成测试通过")
	else:
		printerr("完整游戏集成测试失败：%d 项" % failures)
	quit(0 if failures == 0 else 1)
