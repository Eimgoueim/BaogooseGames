extends SceneTree
const Catalog = preload("res://scripts/legacy_catalog.gd")
const Gameplay = preload("res://scripts/pet_gameplay.gd")
const Gacha = preload("res://scripts/gacha.gd")
var failures := 0
var printed := 0

func compare(actual: Variant, expected: Variant, path: String) -> void:
	if (actual is float or actual is int) and (expected is float or expected is int):
		if absf(float(actual) - float(expected)) < 0.000001: return
	elif actual is Dictionary and expected is Dictionary:
		for key in expected:
			if not actual.has(key): mismatch(path + "." + key, "missing", expected[key])
			else: compare(actual[key], expected[key], path + "." + key)
		for key in actual:
			if not expected.has(key): mismatch(path + "." + key, actual[key], "unexpected")
		return
	elif actual is Array and expected is Array:
		if actual.size() != expected.size(): mismatch(path + ".length", actual.size(), expected.size())
		for index in mini(actual.size(), expected.size()): compare(actual[index], expected[index], path + "[%d]" % index)
		return
	elif typeof(actual) == typeof(expected) and actual == expected: return
	mismatch(path, actual, expected)

func mismatch(path: String, actual: Variant, expected: Variant) -> void:
	failures += 1
	if printed < 60:
		printerr(path, " actual=", actual, " expected=", expected)
		printed += 1

func _initialize() -> void:
	var catalog := Catalog.load_catalog()
	var data := Catalog.read_json("res://data/gameplay_fixtures.json")
	for fixture: Dictionary in data.fixtures:
		var state: Dictionary = fixture.state.duplicate(true)
		var cursor := [0]
		var random_source := func() -> float:
			var index: int = cursor[0]; cursor[0] += 1
			return float(fixture.randoms[index]) if index < fixture.randoms.size() else 0.5
		var game := Gameplay.new()
		game.inject_clock_and_random(int(fixture.now), random_source)
		game.setup(state, catalog)
		var gacha := Gacha.new(); gacha.random_source = random_source
		var results: Array = []
		for operation: String in fixture.operations:
			if operation.begins_with("pull:"):
				results = gacha.pull(state, catalog, int(operation.get_slice(":", 1))).results
			elif operation.begins_with("tick"):
				for index in maxi(1, int(operation.get_slice(":", 1))): game.tick()
			elif operation == "offline": game.apply_offline()
			else: game.dispatch("adopt_confirm" if operation == "confirm" else operation)
		compare(state, fixture.expected, fixture.name)
		compare(results, fixture.results, fixture.name + ".results")
	if failures == 0: print("原版 JS 与 Godot 的 %d 组完整状态行为对照通过" % data.fixtures.size())
	else: printerr("行为对照失败：", failures)
	quit(0 if failures == 0 else 1)
