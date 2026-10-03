extends SceneTree

const Dungeon = preload("res://scripts/dungeon.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("失败：" + message)

func _run() -> void:
	var dungeon: Variant = Dungeon.new()
	root.add_child(dungeon)
	await process_frame
	var state := {"coins":17, "welcome":true, "active":0, "pets":[{"species":"goose", "energy":30, "asleep":false}]}
	var catalog := {"RL_SKILLS":Dungeon.SKILL_DEFAULTS}
	dungeon.open_game(state, catalog, {})
	_check(int(state.coins) == 17, "欢迎奖励由 root 管理，打开地牢不能重复发放")

	var map: Dictionary = dungeon.generate_floor(1)
	_check(map.size() >= 9 and map.size() <= 11, "每层应生成 9 到 11 个房间")
	_check(map.has("3,3"), "地牢应包含固定起点")
	var reached := {"3,3":true}
	var queue: Array[String] = ["3,3"]
	while not queue.is_empty():
		var key: String = queue.pop_front()
		var room: Dictionary = map[key]
		for direction in Dungeon.DIRS:
			if not room.doors.get(direction, false): continue
			var offset: Vector2i = Dungeon.VEC[direction]
			var next := "%d,%d" % [int(room.x)+offset.x, int(room.y)+offset.y]
			_check(map.has(next), "门必须连接到有效房间")
			if map.has(next) and not reached.has(next):
				reached[next] = true
				queue.append(next)
	_check(reached.size() == map.size(), "生成地图上的每个房间都必须可达")
	var boss_count := 0
	var treasure_count := 0
	var shop_count := 0
	for room in map.values():
		if room.type == "boss": boss_count += 1
		if room.type == "treasure": treasure_count += 1
		if room.type == "shop": shop_count += 1
	_check(boss_count == 1 and treasure_count == 1 and shop_count == 1, "每层应有唯一 Boss、宝箱和商店房")

	var charge_state := {"coins":0, "active":0, "pets":[{"species":"goose", "energy":30, "asleep":false}]}
	var actions: Array[String] = []
	dungeon.action_requested.connect(func(action: String): actions.append(action))
	dungeon.open_game(charge_state, catalog, {})
	_check(dungeon.running, "打开地牢时应立即开始并扣费")
	_check(int(charge_state.pets[0].energy) == 20, "开局应扣除 10 点精力")
	var reward_events: Array[Array] = []
	dungeon.reward_requested.connect(func(points: int, credits: int, exp: int): reward_events.append([points, credits, exp]))
	# Clear one deterministic monster room: a shot kills it; reaching its open exit awards room-clear points.
	var start: Dictionary = dungeon.rooms["3,3"]
	var exit_dir := str(start.doors.keys()[0])
	var step: Vector2i = Dungeon.VEC[exit_dir]
	var destination := "%d,%d" % [int(start.x)+step.x, int(start.y)+step.y]
	start.type = "monster"
	start.doors = {exit_dir:true}
	start.foes = [dungeon._new_foe("blob", Vector2(82, 54), 1, 50)]
	dungeon.current = "3,3"
	dungeon.player = Vector2(82, 54)
	var test_shots: Array[Dictionary] = [{"x":82.0,"y":54.0,"vx":0.0,"vy":0.0,"life":1.0,"size":2.0,"dmg":1,"pierce":0}]
	dungeon.shots = test_shots
	dungeon.fire_cd = 10.0
	dungeon._process_shots(0.01, start)
	dungeon._process_foes(0.01, start)
	match exit_dir:
		"n": dungeon.player = Vector2(88, 16)
		"s": dungeon.player = Vector2(88, 96)
		"w": dungeon.player = Vector2(16, 56)
		"e": dungeon.player = Vector2(160, 56)
	dungeon._update_game(0.01)
	_check(dungeon.current == destination, "清房并走到开放门后应进入相邻房间")
	_check(not reward_events.is_empty() and reward_events[0] == [2, 0, 1], "普通房间奖励应为 2 积分和 1 经验")
	_check(actions.has("save"), "扣费及进度变化应请求 root 保存")
	dungeon._finish(false)
	_check(reward_events.has([4, 0, 5]), "死亡奖励应至少 4 积分、5 经验")
	_check(actions.has("affinity:2"), "死亡应通知 root 增加 2 点亲密度")
	_check(dungeon.start_run(), "结算后应能再次开局")
	dungeon._finish(true)
	_check(reward_events.has([40, 100, 16]), "通关奖励应为 40 积分、100 信用点、16 经验")
	_check(actions.has("affinity:5"), "通关应通知 root 增加 5 点亲密度")

	var exits: Array[bool] = []
	dungeon.closed.connect(func(): exits.append(true))
	dungeon.close_game()
	_check(exits.size() == 1 and not dungeon.visible, "退出地牢应隐藏面板并发出 closed")
	dungeon.queue_free()
	await process_frame
	if failures == 0:
		print("地牢地图、门、战斗、奖励、扣费和退出测试通过")
	else:
		printerr("地牢测试失败：%d 项" % failures)
	quit(0 if failures == 0 else 1)
