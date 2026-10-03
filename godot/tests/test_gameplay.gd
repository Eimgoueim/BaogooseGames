extends SceneTree

const Gameplay = preload("res://scripts/pet_gameplay.gd")
const FIXED_NOW := 1_800_000_000_000

var failures := 0

func _initialize() -> void:
	_run()
	if failures == 0:
		print("Gameplay assertions passed")
		quit(0)
	else:
		push_error("Gameplay test failures: %d" % failures)
		quit(1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _game(initial: Dictionary = {}) -> RefCounted:
	var f := FileAccess.open("res://data/catalog.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var g = Gameplay.new()
	g.now_ms = FIXED_NOW
	g.random = func() -> float: return 0.5
	g.setup(initial, data)
	return g

func _run() -> void:
	_test_economy_and_items()
	_test_play_sleep_work_and_points()
	_test_adoption_and_capacity()
	_test_ticks_offline_and_poop()
	_test_bath_pauses_poop_and_cry_text()
	_test_death_revive_and_reset_identity()

func _test_economy_and_items() -> void:
	var g = _game()
	var initial_coins: int = g.state.coins
	var events: Array[Dictionary] = g.dispatch("buy:basic")
	_check(g.state.coins == initial_coins - 10, "buy deducts configured price")
	_check(g.state.inv.basic == 4, "buy adds one inventory item")
	_check(events.any(func(e): return e.type == "save") and events.any(func(e): return e.type == "toast"), "buy emits save and toast")
	var pet: Dictionary = g.state.pets[0]
	pet.hunger = 20
	var old_exp: int = pet.exp
	g.dispatch("use:basic")
	_check(g.state.inv.basic == 3, "use consumes inventory")
	_check(pet.hunger == 45.0, "basic ration restores 25 hunger")
	_check(pet.exp == old_exp + 8, "basic ration grants configured experience")
	_check(g.state.seenItems.basic == 1, "use records seen item")
	var before: int = g.state.coins
	g.dispatch("buy:fish")
	_check(g.state.coins == before, "species exclusive purchase rejected without charging")

func _test_play_sleep_work_and_points() -> void:
	var g = _game()
	var pet: Dictionary = g.state.pets[0]
	pet.energy = 50
	var mood: float = pet.mood
	g.dispatch("play")
	_check(pet.energy == 40.0 and pet.hunger == 70.0 and pet.mood == mood + 18.0, "play applies base costs and gains")
	_check(g.state.coins == 60, "deterministic 0.5 play roll yields no bonus")
	g.dispatch("sleep")
	_check(pet.asleep, "sleep toggles asleep state")
	g.dispatch("work")
	_check(g.state.coins == 60, "sleeping pet cannot work")
	g.dispatch("sleep")
	pet.energy = 50
	g.dispatch("work")
	_check(g.state.coins == 79 and pet.energy == 30.0 and g.state.workReady == FIXED_NOW + 60000, "work pays deterministic 19 coins and applies source cooldown")
	g.gain_points(10)
	g.dispatch("redeem:drink")
	_check(g.state.points == 10, "insufficient points leave points unchanged")
	g.gain_points(120)
	pet.energy = 20
	g.dispatch("redeem:drink")
	_check(g.state.points == 10 and pet.energy == 70.0, "drink exchange spends 120 and restores 50 energy")

func _test_adoption_and_capacity() -> void:
	var g = _game()
	g.dispatch("adoptpick:cat")
	_check(g.state.picked and g.state.pets.size() == 1 and g.state.pets[0].species == "cat", "first pick replaces starter pet")
	g.state.lv = 3
	var events: Array[Dictionary] = g.dispatch("adoptpick:cat")
	_check(events.any(func(e): return e.type == "dialog" and e.confirm_action == "adopt_confirm"), "duplicate species asks confirmation")
	g.dispatch("adopt_confirm")
	_check(g.state.pets.size() == 2 and g.state.pets[1].name == "咪咪2" and g.state.pets[1].level == 3, "duplicate confirmation adopts with unique name at player level")
	g.state.lv = 1
	g.dispatch("adoptpick:goose")
	_check(g.state.pets.size() == 2, "locked capacity rejects an additional pet")
	var limited: Array[Dictionary] = g.dispatch("adoptpick:whale")
	_check(limited.any(func(e): return e.type == "toast"), "uncollected limited species is rejected")

func _test_ticks_offline_and_poop() -> void:
	var g = _game()
	var p: Dictionary = g.state.pets[0]
	var age: int = p.ageTicks
	var hunger: float = p.hunger
	var events: Array[Dictionary] = g.process(FIXED_NOW + 5000)
	_check(p.ageTicks == age + 1 and p.hunger < hunger, "process runs one 5-second active tick")
	_check(events.any(func(e): return e.type == "save"), "tick requests save")
	p.poopNext = g.now_ms + 5000
	p.lx = 0.3377
	p.ly = 0.84
	g.room_size = Vector2(128, 112)
	g.ground_end = 0.82
	var poop_due: int = p.poopNext
	g.process(g.now_ms + 4900)
	events = g.process(g.now_ms + 200)
	_check(g.state.poops.size() == 1 and p.hunger < hunger - 5, "poop arrives at scheduled time and costs hunger")
	_check(g.state.poops[0].t == poop_due, "poop and tick use the exact crossed timestamp after a 4900ms + 200ms advance")
	_check(is_equal_approx(g.state.poops[0].lx, roundf(0.3377 * 128.0) / 128.0) and is_equal_approx(g.state.poops[0].ly, 0.82), "poop uses the pet pixel position clamped to room edges and ground_end")
	var before_clean: float = p.clean
	g.dispatch("cleanpoop:0")
	_check(g.state.poops.is_empty() and p.clean == minf(100.0, before_clean + 6.0), "cleaning poop clears it and restores cleanliness")
	var before_offline: float = p.hunger
	g.state.lastTick = g.now_ms - 10 * 5000
	g.now_ms += 1
	events = g.apply_offline()
	_check(p.hunger < before_offline and events.any(func(e): return e.type == "toast"), "offline applies capped source decay and a return toast")

func _test_death_revive_and_reset_identity() -> void:
	var g = _game()
	g.state.picked = true
	g.state.lv = 2
	g.dispatch("adoptpick:cat")
	g.state.active = 0
	g.state.pets[1].level = 10
	g.state.pets[1].health = 0
	g.state.pets[1].hunger = 0
	g.state.pets[1].clean = 0
	g.state.pets[1].mood = 0
	for i in range(180):
		g.now_ms += 5000
		g.tick()
	_check(g.state.pets.size() == 1 and g.state.grave.size() == 1 and g.state.grave[0].name == "咪咪", "sick bench pet dies after 180 ticks and enters grave")
	g.state.coins = 500
	g.state.lv = 10
	g.dispatch("revive:0")
	_check(g.state.pets.size() == 2 and g.state.coins == 0 and g.state.pets[g.state.active].level == 10, "eligible grave pet revives for 500 coins when an unlocked slot is available")
	var identity: Dictionary = g.state
	g.dispatch("reset_confirm")
	_check(g.state == identity and g.state.pets.size() == 1 and g.state.coins == 60, "reset restores defaults without replacing caller state dictionary")

func _test_bath_pauses_poop_and_cry_text() -> void:
	var g = _game()
	var p: Dictionary = g.state.pets[0]
	p.poopNext = FIXED_NOW + 5000
	g.bathing = true
	g.process(FIXED_NOW + 5000)
	_check(g.state.poops.is_empty() and not p.poopWarn, "bath animation pauses scheduled poop and warning")
	g.bathing = false
	g.process(g.now_ms + 1)
	_check(g.state.poops.size() == 1, "poop resumes after bath ends")
	var bench: Dictionary = g.make_pet("cat")
	bench.hunger = 0
	bench.sickT = 1
	bench.cryAt = g.now_ms - 30000
	g.state.pets.append(bench)
	var events: Array[Dictionary] = g.tick()
	var cry: Dictionary = {}
	for event in events:
		if event.type == "cry" and event.species == "cat": cry = event
	_check(cry.get("text", "") == "喵…", "bench cry event carries source species key and cry text")
