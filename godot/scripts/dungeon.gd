extends Control
class_name PetDungeon

signal closed
signal reward_requested(points: int, credits: int, exp: int)
signal action_requested(action: String)
signal sound_requested(kind: String)

const LOGICAL := Vector2(176, 112)
const WALL := 16
const GRID := 7
const FLOORS := 5
const DIRS := ["n", "s", "e", "w"]
const VEC := {"n": Vector2i(0, -1), "s": Vector2i(0, 1), "e": Vector2i(1, 0), "w": Vector2i(-1, 0)}
const OPP := {"n": "s", "s": "n", "e": "w", "w": "e"}
const SKILL_DEFAULTS := [
	{"key":"dmg", "name":"力量", "type":"攻击", "emoji":"💪", "desc":"伤害 +1"},
	{"key":"rate", "name":"急速", "type":"射速", "emoji":"⚡", "desc":"射速大幅提升"},
	{"key":"triple", "name":"三重射击", "type":"弹幕", "emoji":"🔱", "desc":"一次打三发"},
	{"key":"pierce", "name":"穿透", "type":"穿透", "emoji":"📌", "desc":"子弹可穿透敌人"},
	{"key":"fast", "name":"疾风", "type":"弹速", "emoji":"👟", "desc":"子弹更快更远"},
	{"key":"run", "name":"轻快", "type":"移速", "emoji":"🎽", "desc":"移动更快"},
	{"key":"hp", "name":"生命", "type":"生命", "emoji":"❤️", "desc":"最大生命 +1 并回满"},
	{"key":"big", "name":"巨弹", "type":"弹体", "emoji":"⚫", "desc":"子弹变大更好命中"}
]
const PET_COLORS := {
	"dragon":{"body":"#7fd6a2", "body2":"#a8ecc4", "acc":"#ffd97a", "eye":"#2f4a3a"},
	"cat":{"body":"#ffd9a8", "body2":"#fff0d0", "acc":"#ff9bb3", "eye":"#4a3a2a"},
	"goose":{"body":"#ffffff", "body2":"#eef3fa", "acc":"#ff9b3d", "eye":"#3a2f52"},
	"hoshino":{"body":"#ffffff", "body2":"#ffffff", "acc":"#ffffff", "eye":"#3b2f52"},
	"whale":{"body":"#ffffff", "body2":"#ffffff", "acc":"#ffffff", "eye":"#2b3566"},
	"gpt":{"body":"#ffffff", "body2":"#ffffff", "acc":"#ffffff", "eye":"#3a3f66"},
	"claude":{"body":"#ffffff", "body2":"#ffffff", "acc":"#ffffff", "eye":"#4a3527"},
	"gemini":{"body":"#ffffff", "body2":"#ffffff", "acc":"#ffffff", "eye":"#5a4a6a"}
}
const C := {"bg":"#1b1730", "trim":"#241f3f", "floor":"#2e3a2c", "floor2":"#354133", "door":"#e0c37a", "blocked":"#7a4a4a", "gold":"#ffd166", "cream":"#ffe9a8"}

var state: Dictionary = {}
var catalog: Dictionary = {}
var art: Dictionary = {}
var rng := RandomNumberGenerator.new()
var running := false
var ended := false
var win := false
var floor := 1
var player := Vector2(88, 56)
var face := "s"
var hp := 6
var max_hp := 6
var invincible := 0.0
var grace := 0.0
var fire_cd := 0.0
var elapsed := 0.0
var message := ""
var message_time := 0.0
var rooms: Dictionary = {}
var current := "3,3"
var shots: Array[Dictionary] = []
var foe_shots: Array[Dictionary] = []
var picks: Array[Dictionary] = []
var floats: Array[Dictionary] = []
var skills: Array[String] = []
var credits := 0
var gold := 0
var kills := 0
var chest_total := 0
var chest_got := 0
var cleared_rooms := 0
var bonus := {"dmg":1, "cd":0.3, "speed":160.0, "spread":1, "pierce":0, "move":62.0, "size":2.0}
var keys: Dictionary = {}
var mouse_aim := Vector2.ZERO
var mouse_firing := false
var pet_color := Color.WHITE
var pet_color2 := Color("#e7d9ff")
var pet_acc := Color("#e7d9ff")
var pet_eye := Color("#3a2f52")
var chest_rate := 0.6
var chest_credits := 10
var gold_rate := 0.6
var clear_bonus := 100
var cost := 10
var _view_rect := Rect2()
var _close_rect := Rect2()
var _restart_rect := Rect2()
var _exit_rect := Rect2()
var _test_rewards: Array[Dictionary] = []
var _hint_label: Label
var _message_label: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	rng.randomize()
	_hint_label = Label.new()
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_font_size_override("font_size", 16)
	_hint_label.add_theme_color_override("font_color", Color("#ddd9ef"))
	add_child(_hint_label)
	_message_label = Label.new()
	_message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.add_theme_font_size_override("font_size", 16)
	_message_label.add_theme_color_override("font_color", Color("#ffe9a8"))
	add_child(_message_label)

func open_game(game_state: Dictionary, game_catalog: Dictionary, game_art: Dictionary) -> void:
	state = game_state
	catalog = game_catalog
	art = game_art
	var constants: Dictionary = catalog.get("constants", {})
	chest_rate = float(constants.get("RL_CHEST_RATE", 0.6))
	chest_credits = int(constants.get("RL_CHEST_CREDITS", 10))
	gold_rate = float(constants.get("RL_GOLD_RATE", 0.6))
	clear_bonus = int(constants.get("RL_CLEAR_BONUS", 100))
	cost = int(constants.get("RL_COST", 10))
	visible = true
	ended = false
	_refresh_pet_colors()
	if not start_run():
		visible = false
		action_requested.emit("toast:" + message)
		closed.emit()
		return
	visible = true
	queue_redraw()

func close_game() -> void:
	running = false
	visible = false
	keys.clear()
	closed.emit()

func start_run() -> bool:
	var pets: Array = state.get("pets", [])
	var active := int(state.get("active", 0))
	if active < 0 or active >= pets.size() or not pets[active] is Dictionary:
		_set_message("⚠️ 没有可出战的宠物")
		return false
	var pet: Dictionary = pets[active]
	if bool(pet.get("asleep", false)):
		_set_message("😴 它睡着了，先叫醒它再出战")
		return false
	if float(pet.get("energy", 0)) < cost:
		_set_message("⚡ 精力不够（需要 %d），先让它休息一下" % cost)
		return false
	pet["energy"] = clampf(float(pet.energy) - cost, 0, 100)
	pets[active] = pet
	state["pets"] = pets
	action_requested.emit("save")
	floor = 1
	hp = 6
	max_hp = 6
	invincible = 0.0
	grace = 0.0
	fire_cd = 0.0
	elapsed = 0.0
	credits = 0
	gold = 0
	skills.clear()
	kills = 0
	chest_got = 0
	cleared_rooms = 0
	ended = false
	win = false
	bonus = {"dmg":1, "cd":0.3, "speed":160.0, "spread":1, "pierce":0, "move":62.0, "size":2.0}
	shots.clear()
	foe_shots.clear()
	picks.clear()
	floats.clear()
	keys.clear()
	rooms = generate_floor(1)
	_enter("3,3", "")
	running = true
	action_requested.emit("toast:🎲 出战！5 层地牢，打完第 5 层 BOSS 通关奖励 💰100")
	sound_requested.emit("dungeon")
	action_requested.emit("save")
	queue_redraw()
	return true

func generate_floor(target_floor: int) -> Dictionary:
	var result: Dictionary = {}
	var origin := Vector2i(3, 3)
	result[_key(origin)] = _new_room(origin, "start")
	var total := 9 + rng.randi_range(0, 2)
	var guard := 0
	while result.size() < total and guard < 800:
		guard += 1
		var values: Array = result.values()
		var room: Dictionary = values[rng.randi_range(0, values.size() - 1)]
		var direction: String = DIRS[rng.randi_range(0, 3)]
		var next: Vector2i = Vector2i(room.x, room.y) + VEC[direction]
		if next.x < 0 or next.y < 0 or next.x >= GRID or next.y >= GRID:
			continue
		var nk := _key(next)
		if not result.has(nk): result[nk] = _new_room(next, "monster")
		room.doors[direction] = true
		result[nk].doors[OPP[direction]] = true
	var extra_links := 0
	for key in result.keys():
		var room: Dictionary = result[key]
		for direction in DIRS:
			if extra_links >= 3: break
			if room.doors.has(direction): continue
			var next: Vector2i = Vector2i(room.x, room.y) + VEC[direction]
			var nk := _key(next)
			if result.has(nk) and not result[nk].doors.has(OPP[direction]) and rng.randf() < 0.16:
				room.doors[direction] = true
				result[nk].doors[OPP[direction]] = true
				extra_links += 1
	# 按原版 BFS 验证可达性，并将最远房间设为 Boss 房。
	var queue: Array[Vector2i] = [origin]
	var seen := {_key(origin): true}
	var far := origin
	var far_d := 0
	while not queue.is_empty():
		var at: Vector2i = queue.pop_front()
		var room: Dictionary = result[_key(at)]
		if int(room.dist) > far_d:
			far_d = int(room.dist)
			far = at
		for direction in DIRS:
			if not room.doors.has(direction): continue
			var next: Vector2i = at + VEC[direction]
			var nk := _key(next)
			if not result.has(nk) or seen.has(nk): continue
			seen[nk] = true
			result[nk].dist = int(room.dist) + 1
			queue.append(next)
	for key in result.keys():
		if not seen.has(key): result.erase(key)
	for room in result.values():
		for direction in DIRS:
			if room.doors.has(direction):
				var nk := _key(Vector2i(room.x, room.y) + VEC[direction])
				if not result.has(nk): room.doors.erase(direction)
	result[_key(far)].type = "boss"
	var pool: Array[String] = []
	for key in result.keys():
		if result[key].type == "monster" and int(result[key].dist) >= 2: pool.append(key)
	var ti := _take_pool(pool)
	if not ti.is_empty():
		result[ti].type = "treasure"
		result[ti].foes = []
	var si := _take_pool(pool)
	if not si.is_empty():
		result[si].type = "shop"
		result[si].foes = []
	chest_total = 0
	for room in result.values():
		if room.type in ["boss", "treasure", "shop"]: continue
		room.chest = rng.randf() < chest_rate
		if room.chest: chest_total += 1
	var hp_add := target_floor - 1
	for room in result.values():
		if room.type != "monster": continue
		var count := mini(2 + target_floor + int(int(room.dist) / 3) + (1 if rng.randf() < 0.35 else 0), 6)
		for i in count:
			var choices := ["blob", "fly"] if int(room.dist) < 3 else ["blob", "fly", "shooter"]
			var kind: String = choices[rng.randi_range(0, choices.size() - 1)]
			var point := Vector2.ZERO
			for attempt in 24:
				point = Vector2(rng.randf_range(30, LOGICAL.x - 30), rng.randf_range(30, LOGICAL.y - 30))
				if not _near_door(point, 4) and point.distance_to(LOGICAL * 0.5) > 26: break
			room.foes.append(_new_foe(kind, point, (2 if kind == "fly" else 3) + hp_add, rng.randf_range(0, 2)))
	return result

func _new_room(at: Vector2i, kind: String) -> Dictionary:
	return {"x":at.x, "y":at.y, "doors":{}, "type":kind, "foes":[], "chest":false, "dist":0, "seen":false, "done":false, "bossDone":false, "spawned":false, "skillGot":false}

func _new_foe(kind: String, at: Vector2, health: int, timer: float) -> Dictionary:
	return {"kind":kind, "x":at.x, "y":at.y, "hp":health, "t":timer, "vx":0.0, "vy":0.0, "hit":0.0}

func _take_pool(pool: Array[String]) -> String:
	return pool.pop_at(rng.randi_range(0, pool.size() - 1)) if not pool.is_empty() else ""

func _key(at: Vector2i) -> String:
	return "%d,%d" % [at.x, at.y]

func _process(delta: float) -> void:
	if not visible: return
	var dt := minf(delta, 0.05)
	if running and message_time > 0: message_time -= dt
	if running: _update_game(dt)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var key := OS.get_keycode_string(key_event.keycode).to_lower()
		if key_event.pressed and not key_event.echo:
			if key in ["escape"]: close_game(); get_viewport().set_input_as_handled(); return
			keys[key] = true
		else: keys[key] = false
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _restart_rect.has_point(mb.position): start_run(); get_viewport().set_input_as_handled(); return
				if _exit_rect.has_point(mb.position): close_game(); get_viewport().set_input_as_handled(); return
				if not _view_rect.has_point(mb.position): return
				var logical := _to_logical(mb.position)
				mouse_aim = logical
				if running: _fire(mouse_aim.x - player.x, mouse_aim.y - 4 - player.y)
				mouse_firing = true
			else: mouse_firing = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _view_rect.has_point(mm.position):
			mouse_aim = _to_logical(mm.position)
			if mm.button_mask & MOUSE_BUTTON_MASK_LEFT != 0: mouse_firing = true
		else: mouse_firing = false
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _view_rect.has_point(touch.position):
			mouse_aim = _to_logical(touch.position)
			if running: _fire(mouse_aim.x - player.x, mouse_aim.y - 4 - player.y)
			mouse_firing = true
		else: mouse_firing = false
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if _view_rect.has_point(drag.position):
			mouse_aim = _to_logical(drag.position)
			mouse_firing = true
		else: mouse_firing = false
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		# Godot maps the legacy controller layout: left stick/D-pad move, right stick/ABXY fire, Start/Select exit.
		if event is InputEventJoypadButton:
			var jb := event as InputEventJoypadButton
			var devices := Input.get_connected_joypads()
			if not devices.is_empty() and jb.device == devices[0] and jb.pressed and jb.button_index in [JOY_BUTTON_START, JOY_BUTTON_BACK]: close_game()

func _to_logical(point: Vector2) -> Vector2:
	if _view_rect.size.x <= 0 or _view_rect.size.y <= 0: return Vector2.ZERO
	return Vector2((point.x - _view_rect.position.x) * LOGICAL.x / _view_rect.size.x, (point.y - _view_rect.position.y) * LOGICAL.y / _view_rect.size.y)

func _update_game(dt: float) -> void:
	var room: Dictionary = rooms.get(current, {})
	if room.is_empty(): return
	grace = maxf(0, grace - dt)
	invincible = maxf(0, invincible - dt)
	fire_cd = maxf(0, fire_cd - dt)
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or keys.get("a", false): move.x -= 1
	if Input.is_key_pressed(KEY_D) or keys.get("d", false): move.x += 1
	if Input.is_key_pressed(KEY_W) or keys.get("w", false): move.y -= 1
	if Input.is_key_pressed(KEY_S) or keys.get("s", false): move.y += 1
	var devices := Input.get_connected_joypads()
	if not devices.is_empty():
		var device: int = devices[0]
		var joy_x := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		var joy_y := Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
		if absf(joy_x) <= 0.25: joy_x = 0
		if absf(joy_y) <= 0.25: joy_y = 0
		move += Vector2(joy_x, joy_y)
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT): move.x = -1
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT): move.x = 1
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP): move.y = -1
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN): move.y = 1
		if Input.is_joy_button_pressed(device, JOY_BUTTON_START) or Input.is_joy_button_pressed(device, JOY_BUTTON_BACK): close_game(); return
	if move.length() > 0:
		move = move.normalized()
		face = ("e" if move.x > 0 else "w") if absf(move.x) > absf(move.y) else ("s" if move.y > 0 else "n")
		player += move * float(bonus.move) * dt
	player.x = clampf(player.x, WALL, LOGICAL.x - WALL)
	player.y = clampf(player.y, WALL, LOGICAL.y - WALL)
	# 原版移动后立即检查换层与过门；切换成功就返回，不再更新旧房间。
	if room.get("trapdoor", {}).size() > 0 and player.distance_to(Vector2(room.trapdoor.x, room.trapdoor.y)) < 12:
		_next_floor()
		return
	if room.foes.is_empty():
		var direction := _door_at_player(room)
		if direction != "":
			var next := _key(Vector2i(room.x, room.y) + VEC[direction])
			if rooms.has(next):
				if room.type == "monster" and not room.done:
					room.done = true
					cleared_rooms += 1
					_emit_reward(2, 0, 1)
					if rng.randf() < gold_rate:
						gold += 1
						floats.append({"x":LOGICAL.x/2, "y":LOGICAL.y/2+12, "text":"gold", "life":1.2})
						_set_message("🪙 清光房间 +1 金币（共 %d）" % gold)
				_enter(next, direction)
				return
	else:
		if player.y <= WALL + 1 or player.y >= LOGICAL.y - WALL - 1 or player.x <= WALL + 1 or player.x >= LOGICAL.x - WALL - 1:
			if message_time <= 0: _set_message("🚪 先清光房间里的怪（还剩 %d）" % room.foes.size())
	if not Input.is_key_pressed(KEY_UP) and not Input.is_key_pressed(KEY_DOWN) and not Input.is_key_pressed(KEY_LEFT) and not Input.is_key_pressed(KEY_RIGHT) and not Input.is_key_pressed(KEY_I) and not Input.is_key_pressed(KEY_J) and not Input.is_key_pressed(KEY_K) and not Input.is_key_pressed(KEY_L):
		if not devices.is_empty():
			var device: int = devices[0]
			var aim_x := Input.get_joy_axis(device, JOY_AXIS_RIGHT_X)
			var aim_y := Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)
			if absf(aim_x) <= 0.25: aim_x = 0
			if absf(aim_y) <= 0.25: aim_y = 0
			if aim_x != 0 or aim_y != 0: _fire(aim_x, aim_y)
			else:
				var buttons := Vector2.ZERO
				if Input.is_joy_button_pressed(device, JOY_BUTTON_Y): buttons.x = 1
				if Input.is_joy_button_pressed(device, JOY_BUTTON_B): buttons.x = -1
				if Input.is_joy_button_pressed(device, JOY_BUTTON_A): buttons.y = 1
				if Input.is_joy_button_pressed(device, JOY_BUTTON_X): buttons.y = -1
				if buttons != Vector2.ZERO: _fire(buttons.x, buttons.y)
	else:
		var aim := Vector2.ZERO
		if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_J): aim.x -= 1
		if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_L): aim.x += 1
		if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_I): aim.y -= 1
		if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_K): aim.y += 1
		if aim != Vector2.ZERO: _fire(aim.x, aim.y)
	if Input.is_key_pressed(KEY_SPACE): _fire(VEC[face].x, VEC[face].y)
	if mouse_firing: _fire(mouse_aim.x - player.x, mouse_aim.y - 4 - player.y)
	_process_shots(dt, room)
	_process_foes(dt, room)
	_process_enemy_shots(dt)
	_process_pickups(room)
	for f in floats:
		f.y -= 14 * dt
		f.life -= dt
	floats = floats.filter(func(f): return f.life > 0)
	if room.type == "boss" and not room.bossDone and room.foes.is_empty() and room.spawned:
		room.bossDone = true
		if floor < FLOORS:
			room.trapdoor = {"x":LOGICAL.x / 2, "y":LOGICAL.y / 2}
			_set_message("⬇️ 出现陷阱门，走过去进入第 %d 层" % (floor + 1))
		else:
			_finish(true)
			return
	elapsed += dt

func _door_at_player(room: Dictionary) -> String:
	var near_x := absf(player.x - LOGICAL.x / 2) < 11
	var near_y := absf(player.y - LOGICAL.y / 2) < 11
	if room.doors.get("n", false) and player.y <= WALL + 0.5 and near_x: return "n"
	if room.doors.get("s", false) and player.y >= LOGICAL.y - WALL - 0.5 and near_x: return "s"
	if room.doors.get("w", false) and player.x <= WALL + 0.5 and near_y: return "w"
	if room.doors.get("e", false) and player.x >= LOGICAL.x - WALL - 0.5 and near_y: return "e"
	return ""

func _process_shots(dt: float, room: Dictionary) -> void:
	var keep: Array[Dictionary] = []
	for shot in shots:
		shot.x += shot.vx * dt; shot.y += shot.vy * dt; shot.life -= dt
		if shot.life <= 0 or shot.x < WALL - 6 or shot.x > LOGICAL.x - WALL + 6 or shot.y < WALL - 6 or shot.y > LOGICAL.y - WALL + 6: continue
		var hit := false
		for foe in room.foes:
			var radius := (13.0 if foe.kind == "boss" else 8.0) + float(shot.size)
			if Vector2(shot.x, shot.y).distance_to(Vector2(foe.x, foe.y)) < radius:
				foe.hp -= int(shot.dmg); foe.hit = 0.12
				if int(shot.pierce) > 0: shot.pierce -= 1
				else: hit = true
				break
		if not hit: keep.append(shot)
	shots = keep

func _process_foes(dt: float, room: Dictionary) -> void:
	var keep: Array[Dictionary] = []
	for foe in room.foes:
		if foe.hit > 0: foe.hit -= dt
		foe.t -= dt
		var delta := player - Vector2(foe.x, foe.y)
		var distance := maxf(delta.length(), 1)
		if foe.kind == "blob":
			foe.x += delta.x / distance * 26 * dt; foe.y += delta.y / distance * 26 * dt
		elif foe.kind == "fly":
			if is_zero_approx(foe.vx) and is_zero_approx(foe.vy):
				var angle := rng.randf_range(0, TAU); foe.vx = cos(angle) * 48; foe.vy = sin(angle) * 48
			foe.x += foe.vx * dt; foe.y += foe.vy * dt
			if foe.x < WALL + 3 or foe.x > LOGICAL.x - WALL - 3: foe.vx *= -1
			if foe.y < WALL + 3 or foe.y > LOGICAL.y - WALL - 3: foe.vy *= -1
			foe.x = clampf(foe.x, WALL + 3, LOGICAL.x - WALL - 3); foe.y = clampf(foe.y, WALL + 3, LOGICAL.y - WALL - 3)
		elif foe.kind == "shooter" and foe.t <= 0:
			foe.t = 2
			var angle := atan2(delta.y, delta.x)
			foe_shots.append({"x":foe.x, "y":foe.y, "vx":cos(angle) * 74, "vy":sin(angle) * 74, "life":3.0})
		elif foe.kind == "boss":
			foe.x += delta.x / distance * 20 * dt; foe.y += delta.y / distance * 20 * dt
			if foe.t <= 0:
				foe.t = 2.4
				var count := 6 if floor >= 3 else 5
				var speed := 60.0 if floor >= 3 else 52.0
				for i in count:
					var angle := float(i) / count * TAU + elapsed
					foe_shots.append({"x":foe.x, "y":foe.y, "vx":cos(angle) * speed, "vy":sin(angle) * speed, "life":3.0})
		if _near_door(Vector2(foe.x, foe.y), 0):
			var push := LOGICAL * 0.5 - Vector2(foe.x, foe.y)
			foe.x += push.normalized().x * 40 * dt; foe.y += push.normalized().y * 40 * dt
		foe.x = clampf(foe.x, WALL + 4, LOGICAL.x - WALL - 4); foe.y = clampf(foe.y, WALL + 4, LOGICAL.y - WALL - 4)
		var radius := 15.0 if foe.kind == "boss" else 10.0
		if grace <= 0 and Vector2(foe.x, foe.y).distance_to(player) < radius: _hurt(1)
		if foe.hp <= 0: _kill(foe)
		else: keep.append(foe)
	room.foes = keep

func _process_enemy_shots(dt: float) -> void:
	var keep: Array[Dictionary] = []
	for shot in foe_shots:
		shot.x += shot.vx * dt; shot.y += shot.vy * dt; shot.life -= dt
		if shot.life <= 0 or shot.x < 4 or shot.x > LOGICAL.x - 4 or shot.y < 4 or shot.y > LOGICAL.y - 4: continue
		if Vector2(shot.x, shot.y).distance_to(player - Vector2(0, 4)) < 8: _hurt(1)
		else: keep.append(shot)
	foe_shots = keep

func _process_pickups(room: Dictionary) -> void:
	if room.get("chest", false) and player.distance_to(Vector2(LOGICAL.x / 2, LOGICAL.y / 2 + 6)) < 14:
		room.chest = false; chest_got += 1
		var roll := rng.randf()
		var credited := roll < 0.55
		if credited:
			credits += chest_credits
			_emit_reward(0, chest_credits, 0)
			floats.append({"x":LOGICAL.x/2, "y":LOGICAL.y/2+2, "text":"+%d" % chest_credits, "life":1.4})
			_set_message("🎁 宝箱 +%d 信用点" % chest_credits)
		elif roll < 0.78 and hp < max_hp:
			hp = mini(max_hp, hp + 1)
			floats.append({"x":LOGICAL.x/2, "y":LOGICAL.y/2+2, "text":"heart", "life":1.4})
			_set_message("🎁 宝箱：回血 +1（❤%d/%d）" % [hp, max_hp])
		else:
			gold += 1
			floats.append({"x":LOGICAL.x/2, "y":LOGICAL.y/2+2, "text":"gold", "life":1.4})
			_set_message("🎁 宝箱：金币 +1（🪙%d）" % gold)
		if not credited: _emit_action_save()
	for pick in picks:
		if Vector2(pick.x, pick.y).distance_to(player - Vector2(0, 4)) < 10:
			if pick.kind == "gold": gold += 1; _set_message("🪙 +1 金币（共 %d）" % gold)
			else:
				hp = mini(max_hp, hp + 1)
				floats.append({"x":pick.x, "y":pick.y, "text":"heart", "life":1.0})
		else: continue
		pick["taken"] = true
	picks = picks.filter(func(p): return not p.get("taken", false))
	if room.type == "treasure" and not room.skillGot and player.distance_to(Vector2(LOGICAL.x/2, LOGICAL.y/2+6)) < 16:
		room.skillGot = true
		_gain_skill(_random_skill())
		floats.append({"x":LOGICAL.x/2, "y":LOGICAL.y/2, "text":"SKILL", "life":1.4})
		_emit_action_save()
	if room.type == "shop":
		for i in room.get("shop", []).size():
			var item: Dictionary = room.shop[i]
			var at := Vector2(34 + i * 54, LOGICAL.y / 2 + 6)
			if item.bought or player.distance_to(at) >= 13: continue
			if gold >= int(item.price):
				gold -= int(item.price); item.bought = true; _gain_skill(str(item.key))
			elif message_time <= 0: _set_message("🪙 金币不够：%s 需要 %d 金币（清房间会掉金币）" % [_skill(str(item.key)).get("name", "道具"), item.price])

func _fire(dx: float, dy: float) -> void:
	if fire_cd > 0 or not running: return
	var direction := Vector2(dx, dy).normalized()
	if direction == Vector2.ZERO: direction = Vector2.DOWN
	fire_cd = float(bonus.cd)
	var count := int(bonus.spread)
	var angle := direction.angle()
	for i in count:
		var a := angle + (0.0 if count == 1 else (float(i) - float(count - 1) / 2) * 0.22)
		var v := Vector2(cos(a), sin(a))
		shots.append({"x":clampf(player.x + v.x * 8, WALL + 2, LOGICAL.x - WALL - 2), "y":clampf(player.y - 4 + v.y * 8, WALL + 2, LOGICAL.y - WALL - 2), "vx":v.x * float(bonus.speed), "vy":v.y * float(bonus.speed), "dmg":bonus.dmg, "pierce":bonus.pierce, "size":bonus.size, "life":1.6})
	face = ("e" if direction.x > 0 else "w") if absf(direction.x) > absf(direction.y) else ("s" if direction.y > 0 else "n")

func _enter(key: String, from: String) -> void:
	if not rooms.has(key): return
	current = key
	shots.clear(); foe_shots.clear(); picks.clear(); floats.clear()
	var room: Dictionary = rooms[key]
	if room.type == "boss" and not room.spawned:
		room.spawned = true
		room.foes = [_new_foe("boss", Vector2(LOGICAL.x/2, LOGICAL.y/2-8), 12 + 5 * (floor-1), 1.6)]
	if room.type == "shop" and not room.has("shop"):
		room.shop = []
		for i in 3: room.shop.append({"key":_random_skill(), "price":3+rng.randi_range(0,2), "bought":false})
	grace = 0.8
	match from:
		"n": player = Vector2(LOGICAL.x/2, LOGICAL.y-WALL-8)
		"s": player = Vector2(LOGICAL.x/2, WALL+8)
		"w": player = Vector2(LOGICAL.x-WALL-8, LOGICAL.y/2)
		"e": player = Vector2(WALL+8, LOGICAL.y/2)
		_: player = LOGICAL/2
	room.seen = true
	_set_message("👑 第 %d 层 BOSS！" % floor if room.type == "boss" else "💎 宝箱房：金宝箱给技能" if room.type == "treasure" else "🛒 商店：走到技能上用金币买" if room.type == "shop" else "第 %d 层起点" % floor if room.type == "start" else "怪物房 · 剩 %d" % room.foes.size())

func _next_floor() -> void:
	floor += 1
	rooms = generate_floor(floor)
	_enter("3,3", "")
	_set_message("⬇️ 进入第 %d 层！" % floor)
	_emit_action_save()

func _hurt(amount: int) -> void:
	if invincible > 0 or not running: return
	hp -= amount; invincible = 0.9
	if hp <= 0: hp = 0; _finish(false)

func _kill(foe: Dictionary) -> void:
	kills += 1
	floats.append({"x":foe.x,"y":foe.y,"text":"boom","life":0.5})
	var roll := rng.randf()
	if roll < 0.22: picks.append({"x":foe.x,"y":foe.y,"kind":"heart"})
	elif roll < 0.34: picks.append({"x":foe.x,"y":foe.y,"kind":"gold"})

func _finish(won: bool) -> void:
	if ended: return
	running = false; ended = true; win = won
	sound_requested.emit("home")
	action_requested.emit("affinity:%d" % (5 if won else 2))
	if won:
		_emit_reward(40, clear_bonus, 16)
		action_requested.emit("toast:🏆 通关 5 层！信用点 +%d" % clear_bonus)
	else:
		_emit_reward(maxi(4, int(credits / 2)), 0, 5)
	# 原版 rlFinish 写汇总后立即调用 rlHUD，实际被旧的 RL.msg 覆盖；迁移保留这个时机。
	_emit_action_save()

func _gain_skill(key: String) -> void:
	match key:
		"dmg": bonus.dmg += 1
		"rate": bonus.cd = maxf(0.12, bonus.cd * 0.68)
		"triple": bonus.spread = mini(3, bonus.spread + 1)
		"pierce": bonus.pierce += 1
		"fast": bonus.speed += 60
		"run": bonus.move += 18
		"hp": max_hp += 1; hp = max_hp
		"big": bonus.size += 1
	skills.append(key)
	var item := _skill(key)
	floats.append({"x":player.x,"y":player.y-20,"text":item.get("emoji", ""),"life":1.6})
	_set_message("✨ 获得技能：%s %s（%s）" % [item.get("emoji", ""), item.get("name", key), item.get("desc", "")])

func _skill(key: String) -> Dictionary:
	var values: Variant = catalog.get("RL_SKILLS", catalog.get("rl_skills", SKILL_DEFAULTS))
	if values is Array:
		for value in values:
			if value is Dictionary and value.get("key", "") == key: return value
	for value in SKILL_DEFAULTS:
		if value.key == key: return value
	return {}

func _random_skill() -> String:
	var values: Variant = catalog.get("RL_SKILLS", catalog.get("rl_skills", SKILL_DEFAULTS))
	var source: Array = values if values is Array and not values.is_empty() else SKILL_DEFAULTS
	return str(source[rng.randi_range(0, source.size()-1)].get("key", "dmg"))

func _set_message(text: String) -> void:
	message = text; message_time = 2.8

func _emit_reward(points: int, credits_award: int, experience: int) -> void:
	_test_rewards.append({"points":points,"credits":credits_award,"exp":experience})
	reward_requested.emit(points, credits_award, experience)

func _emit_action_save() -> void:
	action_requested.emit("save")

func _refresh_pet_colors() -> void:
	var pets: Array = state.get("pets", [])
	var active := int(state.get("active", 0))
	if active < 0 or active >= pets.size(): return
	var species := str(pets[active].get("species", "goose"))
	var cfg: Dictionary = PET_COLORS.get(species, PET_COLORS.goose)
	pet_color = Color.from_string(str(cfg.get("body", "#ffffff")), Color.WHITE)
	pet_color2 = Color.from_string(str(cfg.get("body2", "#ffffff")), Color.WHITE)
	pet_acc = Color.from_string(str(cfg.get("acc", cfg.body2)), Color.WHITE)
	pet_eye = Color.from_string(str(cfg.get("eye", "#3a2f52")), Color("#3a2f52"))

func _near_door(at: Vector2, extra: float) -> bool:
	var pad := 22.0
	var zones := [Rect2(LOGICAL.x/2-pad-extra, -extra, pad*2+extra*2, WALL+10+extra*2), Rect2(LOGICAL.x/2-pad-extra, LOGICAL.y-WALL-10-extra, pad*2+extra*2, WALL+10+extra*2), Rect2(-extra, LOGICAL.y/2-pad-extra, WALL+10+extra*2, pad*2+extra*2), Rect2(LOGICAL.x-WALL-10-extra, LOGICAL.y/2-pad-extra, WALL+10+extra*2, pad*2+extra*2)]
	for zone in zones:
		if zone.has_point(at): return true
	return false

func _draw() -> void:
	if not visible: return
	draw_rect(Rect2(Vector2.ZERO, size), Color("#05060d"), true)
	var top := 32.0
	_close_rect = Rect2()
	_draw_label("🎲 宠物地牢", Vector2(14, 25), 19, Color.WHITE)
	var hud := "🏢%d/%d · ❤%d/%d · 🪙%d · 🎁%d/%d" % [floor, FLOORS, hp, max_hp, gold, chest_got, chest_total]
	if not skills.is_empty():
		hud += " · "
		for skill_key in skills: hud += str(_skill(skill_key).get("emoji", ""))
	var hud_width := maxf(20, minf(430, size.x-330))
	if ThemeDB.fallback_font:
		draw_string(ThemeDB.fallback_font, Vector2(size.x-hud_width-10, 27), hud, HORIZONTAL_ALIGNMENT_RIGHT, hud_width, 23, Color(0,0,0,0.55))
		draw_string(ThemeDB.fallback_font, Vector2(size.x-hud_width-10, 26), hud, HORIZONTAL_ALIGNMENT_RIGHT, hud_width, 23, Color.WHITE)
	var scale_factor := minf((size.x-20)/LOGICAL.x, (size.y-92)/LOGICAL.y)
	var game_size := LOGICAL * scale_factor
	var play_area_height := maxf(0, size.y-92)
	_view_rect = Rect2(Vector2((size.x-game_size.x)/2, 34+(play_area_height-game_size.y)/2), game_size)
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color("#151129")
	shadow.set_corner_radius_all(8)
	shadow.shadow_color = Color(0,0,0,0.5)
	shadow.shadow_size = 30
	shadow.shadow_offset = Vector2(0,10)
	draw_style_box(shadow, _view_rect)
	var canvas_back := StyleBoxFlat.new()
	canvas_back.bg_color = Color("#151129")
	canvas_back.set_corner_radius_all(8)
	draw_style_box(canvas_back, _view_rect)
	draw_set_transform(_view_rect.position, 0, Vector2(scale_factor, scale_factor))
	_draw_room()
	draw_set_transform(Vector2.ZERO)
	_draw_round_canvas_corners()
	_draw_shop_chips()
	var hint := "WASD 移动 · 方向键/IJKL 射击 · 鼠标点击也能打 · 宝箱给信用点，金宝箱给技能，商店用金币买技能"
	hint += " · 🎮 手柄已连接" if not Input.get_connected_joypads().is_empty() else " · 手柄：左摇杆移动 / 右摇杆射击"
	_hint_label.text = hint
	_hint_label.visible = true
	_hint_label.position = Vector2(12, size.y-26)
	_hint_label.size = Vector2(maxf(60,size.x-238), 22)
	_message_label.text = message if message_time > 0 else ""
	_message_label.visible = true
	_message_label.position = Vector2(12, size.y-47)
	_message_label.size = Vector2(maxf(60,size.x-238), 20)
	_restart_rect = Rect2(size.x-212, size.y-36, 128, 28)
	_exit_rect = Rect2(size.x-76, size.y-36, 64, 28)
	draw_rect(_restart_rect, Color("#6b5aa0"), true)
	_draw_label("🔁 再战一局", _restart_rect.position + Vector2(8, 19), 14, Color.WHITE)
	draw_rect(_exit_rect, Color("#29243d"), true)
	_draw_label("关闭", _exit_rect.position + Vector2(11, 19), 14, Color.WHITE)

func _draw_round_canvas_corners() -> void:
	var cut := Color("#05060d")
	for index in 8:
		var distance := 8.0 - float(index)
		var inset := roundi(8.0 - sqrt(maxf(0.0, 64.0-distance*distance)))
		if inset <= 0: continue
		draw_rect(Rect2(_view_rect.position.x+index, _view_rect.position.y, 1, inset), cut, true)
		draw_rect(Rect2(_view_rect.end.x-1-index, _view_rect.position.y, 1, inset), cut, true)
		draw_rect(Rect2(_view_rect.position.x+index, _view_rect.end.y-inset, 1, inset), cut, true)
		draw_rect(Rect2(_view_rect.end.x-1-index, _view_rect.end.y-inset, 1, inset), cut, true)

func _draw_shop_chips() -> void:
	var room: Dictionary = rooms.get(current, {})
	if room.get("type", "") != "shop": return
	var items: Array = room.get("shop", [])
	var chip_width := 116.0
	var spacing := 8.0
	var total_width := items.size() * chip_width + maxi(0, items.size()-1) * spacing
	var x0 := (size.x-total_width)/2
	var y := _view_rect.end.y+5
	for i in items.size():
		var item: Dictionary = items[i]
		var near := player.distance_to(Vector2(34+i*54, LOGICAL.y/2+6)) < 18
		var chip := Rect2(x0+i*(chip_width+spacing), y, chip_width, 25)
		draw_rect(chip, Color(0.42,0.35,0.63,0.35) if not item.bought else Color(0.25,0.25,0.29,0.38), true)
		draw_rect(chip, Color("#ffe9a8") if near else Color(0.56,0.49,0.82,0.75), false, 1.0)
		var kind := str(_skill(str(item.key)).get("type", "道具"))
		var label_color := Color("#ffe9a8")
		if item.bought: label_color.a = 0.38
		_draw_label("%s  %d🪙" % [kind, item.price], chip.position+Vector2(9,17), 13, label_color)
		if item.bought: draw_line(chip.position+Vector2(8,13), chip.position+Vector2(chip_width-8,13), Color("#ffe9a8",0.38), 1)

func _draw_room() -> void:
	var room: Dictionary = rooms.get(current, {})
	_draw_rect(0,0,LOGICAL.x,LOGICAL.y,Color(C.bg))
	for x in range(0, 176, 8): _draw_rect(x,0,4,4,Color(C.trim)); _draw_rect(x,108,4,4,Color(C.trim))
	var floor_a := Color("#3a3524") if room.get("type", "") == "treasure" else Color("#25332c") if room.get("type", "") == "shop" else Color(C.floor)
	var floor_b := Color("#453d28") if room.get("type", "") == "treasure" else Color("#2c3f35") if room.get("type", "") == "shop" else Color(C.floor2)
	_draw_rect(WALL,WALL,LOGICAL.x-WALL*2,LOGICAL.y-WALL*2,floor_a)
	for y in range(WALL, 96, 8):
		for x in range(WALL, 160, 8):
			if int(x/8+y/8)%2 == 0: _draw_rect(x,y,8,8,floor_b)
	if room:
		for direction in DIRS:
			if not room.doors.get(direction, false): continue
			var col := Color(C.door) if room.foes.is_empty() else Color(C.blocked)
			match direction:
				"n": _draw_rect(78,0,20,WALL,floor_a); _draw_rect(78,0,20,3,col)
				"s": _draw_rect(78,96,20,WALL,floor_a); _draw_rect(78,109,20,3,col)
				"w": _draw_rect(0,40,WALL,20,floor_a); _draw_rect(0,40,3,20,col)
				"e": _draw_rect(160,40,WALL,20,floor_a); _draw_rect(173,40,3,20,col)
		if room.get("chest", false): _draw_chest(88,62,false)
		if room.get("type", "") == "treasure" and not room.get("skillGot", false): _draw_chest(88,62,true)
		if room.get("type", "") == "shop": _draw_shop(room)
		if room.get("trapdoor", {}).size() > 0: _draw_rect(76,48,24,16,Color("#0d0a18")); _draw_rect(79,51,18,10,Color("#241a3a")); _draw_rect(79,48,18,2,Color("#6b5aa0"))
		for foe in room.foes: _draw_foe(foe)
	for pick in picks:
		if pick.kind == "gold": _draw_coin(pick.x,pick.y)
		else: _draw_rect(pick.x-4,pick.y-4,4,4,Color("#ff5b7a")); _draw_rect(pick.x,pick.y-4,4,4,Color("#ff5b7a")); _draw_rect(pick.x-2,pick.y-1,6,4,Color("#ff5b7a"))
	if not ended and (invincible <= 0 or int(elapsed*18)%2 != 0): _draw_pet(player.x, player.y)
	for shot in shots: _draw_rect(shot.x-shot.size,shot.y-shot.size,shot.size*2,shot.size*2,Color("#bfe9ff"))
	for shot in foe_shots: _draw_rect(shot.x-2,shot.y-2,4,4,Color("#ff9ec0"))
	for popup in floats: _draw_rect(popup.x-4,popup.y-3,8,5,Color(1.0,0.91,0.66,0.92))
	_draw_minimap()

func _draw_rect(x: float, y: float, w: float, h: float, color: Color) -> void:
	draw_rect(Rect2(roundf(x), roundf(y), roundf(w), roundf(h)), color, true)

func _draw_chest(x: float, y: float, is_gold: bool) -> void:
	var base := Color("#c9962c") if is_gold else Color("#a9743c")
	var lid := Color("#e8b53c") if is_gold else Color("#c98a45")
	_draw_rect(x-9,y-3,18,9,base); _draw_rect(x-9,y-9,18,6,lid); _draw_rect(x-9,y-9,18,2,Color(C.gold) if is_gold else Color("#e6ab61")); _draw_rect(x-2,y-6,4,7,Color(C.gold))
	if is_gold: _draw_rect(x-11,y-12,4,4,Color("#fff3c4")); _draw_rect(x+7,y-12,4,4,Color("#fff3c4"))

func _draw_coin(x: float, y: float) -> void:
	_draw_rect(x-3,y-3,6,6,Color(C.gold)); _draw_rect(x-2,y-2,4,4,Color("#e8b53c")); _draw_rect(x-1,y-1,2,2,Color("#fff3c4"))

func _draw_pet(x: float, y: float) -> void:
	_draw_rect(x-6,y+5,12,2,Color(0.07,0.05,0.16,0.35)); _draw_rect(x-5,y-1,10,7,pet_color2); _draw_rect(x-6,y-8,12,8,pet_color); _draw_rect(x-7,y-10,3,3,pet_acc); _draw_rect(x+4,y-10,3,3,pet_acc); _draw_rect(x-3,y-5,2,3,pet_eye); _draw_rect(x+1,y-5,2,3,pet_eye)

func _draw_foe(foe: Dictionary) -> void:
	if foe.hit > 0: return
	match foe.kind:
		"boss":
			_draw_rect(foe.x-13,foe.y-13,26,26,Color("#6b3f8f")); _draw_rect(foe.x-10,foe.y-17,20,5,Color("#8a5cb0")); _draw_rect(foe.x-8,foe.y-8,5,5,Color(C.gold)); _draw_rect(foe.x+3,foe.y-8,5,5,Color(C.gold)); _draw_rect(foe.x-6,foe.y+3,12,3,Color("#3d2154"))
		"blob":
			_draw_rect(foe.x-8,foe.y-6,16,14,Color("#5ec46b")); _draw_rect(foe.x-4,foe.y-9,8,4,Color("#7ddc88")); _draw_rect(foe.x-4,foe.y-2,3,3,Color("#12341c")); _draw_rect(foe.x+1,foe.y-2,3,3,Color("#12341c"))
		"fly":
			_draw_rect(foe.x-5,foe.y-5,10,10,Color("#f0f2ff")); _draw_rect(foe.x-9,foe.y-3,4,3,Color("#c8d2ff")); _draw_rect(foe.x+5,foe.y-3,4,3,Color("#c8d2ff")); _draw_rect(foe.x-3,foe.y-2,2,2,Color("#2a2350")); _draw_rect(foe.x+1,foe.y-2,2,2,Color("#2a2350"))
		_:
			_draw_rect(foe.x-7,foe.y-6,14,13,Color("#c96a9a")); _draw_rect(foe.x-5,foe.y-9,10,4,Color("#e08bb4")); _draw_rect(foe.x-4,foe.y-2,3,3,Color("#3a1030")); _draw_rect(foe.x+1,foe.y-2,3,3,Color("#3a1030"))

func _draw_shop(room: Dictionary) -> void:
	for i in room.get("shop", []).size():
		var item: Dictionary = room.shop[i]
		var x: float = 34 + i * 54
		var col := Color("#4a3f6b") if not item.bought else Color("#3a3a44")
		_draw_rect(x-11,62-4,22,10,col); _draw_rect(x-11,62-12,22,9,Color("#6b5aa0") if not item.bought else Color("#4a4a55")); _draw_rect(x-11,62-12,22,2,Color("#8f7cd0") if not item.bought else Color("#6a6a78"))
		if not item.bought:
			_draw_rect(x-6,62-9,12,4,Color(C.cream)); _draw_rect(x-4,69,3,3,Color(C.gold)); _draw_rect(x+1,69,3,3,Color(C.gold)); _draw_rect(x-4,72,8,2,Color("#e8b53c"))
		else: _draw_rect(x-5,62-8,10,3,Color("#5a5a66"))

func _draw_minimap() -> void:
	var cells: Array = []
	for key in rooms.keys():
		if rooms[key].seen or key == current: cells.append(rooms[key])
	if cells.is_empty(): return
	var min_x := 99; var max_x := -1; var min_y := 99; var max_y := -1
	for room in cells: min_x = mini(min_x, room.x); max_x = maxi(max_x, room.x); min_y = mini(min_y, room.y); max_y = maxi(max_y, room.y)
	var step := 5
	var origin := Vector2(LOGICAL.x-3-((max_x-min_x+1)*step+5), LOGICAL.y-3-((max_y-min_y+1)*step+5))
	_draw_rect(origin.x,origin.y,(max_x-min_x+1)*step+5,(max_y-min_y+1)*step+5,Color(0.04,0.03,0.09,0.72))
	for room in cells:
		var at := origin + Vector2(3+(room.x-min_x)*step,3+(room.y-min_y)*step)
		for d in ["e", "s"]:
			if room.doors.get(d, false):
				var next_key := _key(Vector2i(room.x,room.y)+VEC[d])
				if rooms.has(next_key) and (rooms[next_key].seen or next_key == current): _draw_rect(at.x+4,at.y+1,2,3,Color("#8f7cd0")) if d == "e" else _draw_rect(at.x+1,at.y+4,3,2,Color("#8f7cd0"))
		var col := Color("#ffe9a8") if _key(Vector2i(room.x,room.y)) == current else Color("#d06a9a") if room.type == "boss" else Color("#e8b53c") if room.type == "treasure" else Color("#4fc9a8") if room.type == "shop" else Color("#9aa7ff") if room.type == "start" else Color("#6b7bbf")
		_draw_rect(at.x,at.y,4,4,col)
		if _key(Vector2i(room.x,room.y)) == current: _draw_rect(at.x,at.y,4,1,Color.WHITE)

func _draw_label(text: String, at: Vector2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	if font: draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
