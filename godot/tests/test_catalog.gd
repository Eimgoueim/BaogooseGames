extends SceneTree

const Catalog = preload("res://scripts/legacy_catalog.gd")
const Codec = preload("res://scripts/state_codec.gd")

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr(message)

func _initialize() -> void:
	var catalog := Catalog.load_catalog()
	var art := Catalog.read_json("res://data/art.json")
	var fixtures := Catalog.read_json("res://data/visual_fixtures.json")
	check(catalog.source_sha256 == art.source_sha256, "配置和美术应来自同一份 HTML")
	check(catalog.SPECIES.size() == 8, "应迁移原版 8 种宠物配置")
	check(catalog.THEMES.size() == 6, "应保留原版 6 套主题")
	check(catalog.PLACE.size() == 20, "应保留家具和装饰品共 20 种")
	check(catalog.RL_SKILLS.size() == 8, "应保留地牢技能配置")
	check(Codec.normalize(catalog.default_state).ok, "真实原版默认存档应能读取")
	for species: String in catalog.SPECIES:
		var state: Dictionary = catalog.default_state.duplicate(true)
		state.pets[0].species = species
		check(Codec.normalize(state).ok, "应兼容宠物种类：" + species)
		check(art.pets.has(species), "缺失原版像素画：" + species)
		check(art.pets[species].size() == 20, "应包含四成长阶段与五表情：" + species)
	for fixture_name: String in fixtures:
		var fixture: Dictionary = fixtures[fixture_name]
		check(fixture.width > 0 and fixture.height > 0, "视觉基准尺寸应有效")
		check(not fixture.commands.is_empty(), "视觉基准不可为空：" + fixture_name)
		for command: Array in fixture.commands:
			check(command.size() == 8, "矩形指令结构应完整")
			for value: Variant in command:
				check((value is float or value is int) and is_finite(float(value)), "指令应是有限数值")
	if failures == 0:
		print("原版配置和 25 个 Canvas 视觉基准校验通过")
	quit(0 if failures == 0 else 1)
