extends SceneTree

# 回归：地牢两个老 bug
# ① 怪物"卡墙上"：坐标必须按身体半径夹在房间内（以前只夹中心到 WALL+4，半个身子陷进墙里）
# ② 开门杀：进房间要有足够无敌时间，且门口的敌人只会后退、不会追到门口打玩家
const Dungeon = preload("res://scripts/dungeon.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("失败：" + message)

func _body_radius(kind: String) -> float:
	if kind == "boss":
		return 15.0
	if kind == "fly":
		return 6.0
	return 9.0

func _run() -> void:
	var dungeon: Variant = Dungeon.new()
	root.add_child(dungeon)
	await process_frame
	var state := {"coins": 17, "welcome": true, "active": 0, "pets": [{"species": "goose", "energy": 30, "asleep": false}]}
	var catalog := {"RL_SKILLS": Dungeon.SKILL_DEFAULTS}
	dungeon.open_game(state, catalog, {})

	var map: Dictionary = dungeon.generate_floor(1)
	# 找一个怪物房
	var monster_key := ""
	for key in map.keys():
		if map[key].type == "monster":
			monster_key = key
			break
	_check(monster_key != "", "第 1 层应有怪物房")
	if monster_key == "":
		_end()
		return
	var room: Dictionary = map[monster_key]
	dungeon._enter(monster_key, "s")
	await process_frame
	_check(room.foes.size() > 0, "怪物房应有敌人")

	# ① 进门无敌时间足够（防开门杀）
	_check(float(dungeon.get("grace")) >= 1.0, "进房间的无敌时间应 >= 1.0 秒（实际 %.2f）" % float(dungeon.get("grace")))

	# ② 刷怪离门口要有安全距离（多种随机布局都要满足）
	var near_door_spawn := 0
	var checked_foes := 0
	for seed_value in [11, 22, 33, 44, 55, 66, 77, 88]:
		dungeon.rng.seed = seed_value
		var sample_map: Dictionary = dungeon.generate_floor(1)
		for sample_room in sample_map.values():
			if sample_room.type != "monster": continue
			for foe in sample_room.foes:
				checked_foes += 1
				if bool(dungeon.call("_near_door", Vector2(foe.x, foe.y), 14.0)):
					near_door_spawn += 1
	_check(checked_foes > 20, "多种子下应检查到足够多的敌人（实际 %d 只）" % checked_foes)
	_check(near_door_spawn == 0, "敌人不应刷在门口附近（%d 只检查里发现 %d 只越界）" % [checked_foes, near_door_spawn])

	# ③ 把一只敌人放在门口：它应该往房间中心退，而不是贴着门口
	var probe := {"kind": "blob", "x": Dungeon.LOGICAL.x / 2, "y": Dungeon.WALL + 2, "hp": 99, "t": 0.0, "vx": 0.0, "vy": 0.0, "hit": 0.0}
	room.foes = [probe]
	var start_y := float(probe.y)
	for _i in 40:
		dungeon._process_foes(0.05, room)
	_check(room.foes.size() > 0, "门口的敌人不应被直接移除")
	if room.foes.size() > 0:
		var moved: float = float(room.foes[0].y) - start_y
		_check(moved > 10.0, "靠近门口的敌人应向房间中心后退（实际位移 %.1f）" % moved)
		_check(not bool(dungeon.call("_near_door", Vector2(room.foes[0].x, room.foes[0].y), 0.0)),
			"敌人不应停在门口区域内（x=%.1f y=%.1f）" % [room.foes[0].x, room.foes[0].y])

	# ④ 长时间奔跑后，任何敌人都不能陷进墙里（按身体半径检查）
	var wall_violations := 0
	for _i in 120:
		dungeon._process_foes(0.02, room)
		dungeon._update_game(0.02)
		for foe in room.foes:
			var body := _body_radius(str(foe.kind))
			var x := float(foe.x)
			var y := float(foe.y)
			if x < Dungeon.WALL + body - 0.01 or x > Dungeon.LOGICAL.x - Dungeon.WALL - body + 0.01 \
				or y < Dungeon.WALL + body - 0.01 or y > Dungeon.LOGICAL.y - Dungeon.WALL - body + 0.01:
				wall_violations += 1
	_check(wall_violations == 0, "敌人不应陷进墙里（发现 %d 次越界，说明卡墙）" % wall_violations)

	# ⑤ 开门杀：敌人紧贴玩家，但处于进门无敌期内不能掉血
	dungeon.set("grace", 1.6)
	dungeon.set("invincible", 0.0)
	dungeon.player = Vector2(Dungeon.LOGICAL.x / 2, Dungeon.WALL + 14)
	var before_hp := int(dungeon.get("hp"))
	room.foes = [{"kind": "blob", "x": Dungeon.LOGICAL.x / 2, "y": Dungeon.WALL + 20, "hp": 99, "t": 0.0, "vx": 0.0, "vy": 0.0, "hit": 0.0}]
	for _i in 20:
		dungeon._process_foes(0.05, room)
	_check(int(dungeon.get("hp")) == before_hp, "进门无敌期内不应掉血（%d -> %d）" % [before_hp, int(dungeon.get("hp"))])

	_end()

func _end() -> void:
	if failures == 0:
		print("地牢卡墙与开门杀测试通过")
	quit(failures)
