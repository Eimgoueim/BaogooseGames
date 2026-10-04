extends Control

signal action_requested(action: String)
const Style = preload("res://scripts/ui/legacy_ui_style.gd")
const Modals = preload("res://scripts/ui/legacy_modals.gd")
const Renderer = preload("res://scripts/room_renderer.gd")

class RollStage extends Control:
	var has_pet := false
	var elapsed := 0.0
	func _process(delta: float) -> void:
		elapsed += delta
		queue_redraw()
	func _draw() -> void:
		# 对应原 CSS radial-gradient(ellipse at 50% 130%, ..., transparent 62%)。
		var center := Vector2(size.x / 2, size.y * 1.3)
		var tint := Color(1, 1, 1, 0.30) if has_pet else Color(200.0 / 255, 225.0 / 255, 1, 0.35)
		for row in int(size.y):
			for column in range(0, int(size.x), 4):
				var distance := ((Vector2(column + 2, row) - center) / Vector2(maxf(1, size.x * 0.75), maxf(1, size.y * 1.5))).length()
				var shade := tint; shade.a *= maxf(0, 1 - distance / 0.62)
				if shade.a > 0: draw_rect(Rect2(column, row, 4, 1), shade)
		if has_pet:
			var colors := ["#ef5b5b", "#ff9b3d", "#ffd97a", "#4fc99a", "#4f7ee0"]
			for index in 5:
				var progress := clampf((elapsed - index * 0.09) / 1.55, 0, 1)
				var opacity := minf(progress / 0.28, (1 - progress) / 0.72) * 0.9
				var c := Color(colors[index]); c.a = maxf(0, opacity)
				var scale_factor := lerpf(0.55, 1.12, 1 - pow(1 - progress, 3))
				var radius := size.x * 0.75 * scale_factor
				draw_set_transform(Vector2(size.x / 2, size.y * 1.08), 0, Vector2(1, size.y / maxf(size.x, 1)))
				draw_arc(Vector2.ZERO, radius, -PI, 0, 96, c, 9, true)
			draw_set_transform(Vector2.ZERO)
			var spark := clampf(elapsed / 1.35, 0, 1)
			var spark_label := "✨"
			var font := get_theme_default_font()
			var spark_color := Color.WHITE; spark_color.a = minf(spark / 0.35, (1 - spark) / 0.65)
			draw_set_transform(Vector2(size.x * 0.5, size.y * 0.4), deg_to_rad(lerpf(-30, 24, spark)), Vector2.ONE * lerpf(0.4, 1.5, spark))
			draw_string(font, Vector2(-14, 10), spark_label, HORIZONTAL_ALIGNMENT_CENTER, 28, 28, spark_color)
			draw_set_transform(Vector2.ZERO)
		else:
			for index in 3:
				var progress := clampf((elapsed - [0.0, 0.16, 0.3][index]) / 1.75, 0, 1)
				var opacity := minf(progress / 0.22, (1 - progress) / 0.78) * 0.95
				var width: float = [74.0, 52.0, 88.0][index]
				var x: float = [-90.0, -70.0, -110.0][index] + 420 * progress
				var y: float = size.y * [0.22, 0.46, 0.68][index]
				var style := Style.panel_style(Color(1, 1, 1, maxf(0, opacity)), Color.TRANSPARENT, 13)
				style.shadow_color = Color(60.0 / 255, 40.0 / 255, 110.0 / 255, 0.18 * maxf(0, opacity))
				style.shadow_size = 7; style.shadow_offset = Vector2(0, 6)
				draw_style_box(style, Rect2(x, y, width * lerpf(0.9, 1.05, progress), 26))

var generation := 0
var rolling := false
var results: Array = []
var catalog: Dictionary
var art: Dictionary
var state: Dictionary
var vars: Dictionary
var panel: PanelContainer
var body: VBoxContainer
var summary: Label
var stage: Control
var results_scroll: ScrollContainer
var tip: Label
var results_grid: GridContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	get_viewport().size_changed.connect(_on_viewport_size_changed)

func close() -> void:
	generation += 1
	rolling = false
	visible = false

func show_results(current: Dictionary, data: Dictionary, drawings: Dictionary, items: Array) -> void:
	generation += 1
	var token := generation
	state = current; catalog = data; art = drawings; results = items
	vars = Renderer.theme_vars(state, catalog)
	for child in get_children(): remove_child(child); child.queue_free()
	Style.apply(self, vars)
	var backdrop := ColorRect.new()
	backdrop.color = Color(28.0 / 255, 22.0 / 255, 52.0 / 255, 0.52)
	add_child(backdrop); backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	panel.custom_minimum_size.x = minf(580, get_viewport_rect().size.x * 0.96)
	var style := Style.panel_style(Color(vars["--card"]), Color(vars["--line"]), 24)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	body = VBoxContainer.new(); body.add_theme_constant_override("separation", 12)
	panel.add_child(body)
	var header := HBoxContainer.new(); body.add_child(header)
	var title := Style.label("🎰 抽卡结果", 16, Color(vars["--ink"]))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(title)
	summary = Style.label("", 12, Color(vars["--purple"])); header.add_child(summary)
	var has_pet := false
	for item: Dictionary in results:
		if item.type == "pet": has_pet = true
	summary.text = "✨ 有星辉……" if has_pet else "☁️ 云在飘……"
	stage = RollStage.new(); stage.has_pet = has_pet
	stage.custom_minimum_size.y = 170; stage.clip_contents = true
	body.add_child(stage)
	var roll_hint := Style.label("✨ 星 辉 聚 集 ✨" if has_pet else "☁️ 云 朵 飘 过 ☁️", 12, Color(vars["--muted"]))
	stage.add_child(roll_hint); roll_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	roll_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; roll_hint.offset_top = -28
	results_scroll = ScrollContainer.new()
	results_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(results_scroll); results_scroll.visible = false
	var grid := GridContainer.new()
	results_grid = grid
	grid.columns = 3 if get_viewport_rect().size.x <= 540 else 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8); grid.add_theme_constant_override("v_separation", 8)
	results_scroll.add_child(grid)
	for item: Dictionary in results: build_card(grid, item)
	results_scroll.custom_minimum_size.y = minf(grid.get_combined_minimum_size().y, get_viewport_rect().size.y * 0.54)
	var footer := HBoxContainer.new(); footer.add_theme_constant_override("separation", 8); body.add_child(footer)
	tip = Style.label("", 12, Color(vars["--muted"]))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(tip)
	footer.add_child(Style.card_button("再来十连 💰100", "pull:10", emit_action, vars))
	footer.add_child(Style.card_button("关闭", "gachaclose", emit_action, vars))
	rolling = true; visible = true
	await get_tree().create_timer(1.5).timeout
	if generation == token and visible: reveal()

func emit_action(action: String) -> void:
	action_requested.emit(action)

func build_card(grid: GridContainer, item: Dictionary) -> void:
	var kind: String = item.type
	var definition: Dictionary = catalog[{"pet": "SPECIES", "wear": "WEAR", "deco": "DECOS", "food": "SHOP"}[kind]][item.key]
	var card := PanelContainer.new(); card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var color := Color(vars["--soft"])
	var border := Color(vars["--line2"])
	if kind == "pet": color = Color("#fff4d6"); border = Color("#ffc94d")
	elif kind == "wear": color = Color("#ffecf6"); border = Color("#ffb3d1")
	elif kind == "deco": border = Color("#b9d4ff")
	var style := Style.panel_style(color, border, 16)
	style.content_margin_left = 6; style.content_margin_right = 6
	style.content_margin_top = 11; style.content_margin_bottom = 11
	card.add_theme_stylebox_override("panel", style); grid.add_child(card)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 4); card.add_child(column)
	if kind == "pet":
		var sprite := Modals.PetPixel.new(); sprite.commands = art.pets[item.key]["0_awake"]
		sprite.custom_minimum_size = Vector2(40, 36); sprite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(sprite)
	else:
		var emoji := Style.label(definition.emoji, 26, Color(vars["--ink"])); emoji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(emoji)
	var name := Style.label(definition.name, 11, Color(vars["--ink"]))
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name)
	var tags := HFlowContainer.new()
	tags.alignment = FlowContainer.ALIGNMENT_CENTER
	tags.add_theme_constant_override("h_separation", 2)
	tags.add_theme_constant_override("v_separation", 2)
	column.add_child(tags)
	if kind == "pet":
		if item.spook: badge(tags, "歪！", false)
		if item.pity in ["big", "small"]: badge(tags, "大保底" if item.pity == "big" else "小保底", true)
		badge(tags, "重复 +%d⭐" % int(catalog.constants.DUP_PET_PTS) if item.dup else "NEW 限定", not item.dup)
	elif kind in ["wear", "deco"]:
		var amount: int = catalog.constants.DUP_WEAR_PTS if kind == "wear" else catalog.constants.DUP_DECO_PTS
		badge(tags, "重复 +%d⭐" % amount if item.dup else ("NEW 佩饰" if kind == "wear" else "NEW 装饰"), not item.dup)
	else: badge(tags, "已入背包", false)

func badge(parent: Control, text: String, is_new: bool) -> void:
	var panel_node := PanelContainer.new()
	panel_node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := Style.panel_style(Color(vars["--purple"] if is_new else vars["--btn"]), Color.TRANSPARENT, 8)
	style.content_margin_left = 7; style.content_margin_right = 7; style.content_margin_top = 2; style.content_margin_bottom = 2
	panel_node.add_theme_stylebox_override("panel", style); parent.add_child(panel_node)
	panel_node.add_child(Style.label(text, 9, Color.WHITE if is_new else Color("#8a7bd8")))

func reveal() -> void:
	rolling = false
	stage.visible = false; results_scroll.visible = true
	var counts := {"pet": 0, "wear": 0, "deco": 0, "food": 0}
	for item: Dictionary in results:
		if item.type != "pet" or not item.dup: counts[item.type] += 1
	summary.text = "限定 %d · 佩饰 %d · 装饰 %d · 食物 %d" % [counts.pet, counts.wear, counts.deco, counts.food]
	var c: Dictionary = catalog.constants
	tip.text = "限定宠物 %s%% · 第 %d 抽 · 保底进度 %d/%d（%d 抽必出限定，%d%% 歪星野；%d 抽必出当期限定）" % [str(float(c.PET_RATE) * 100).trim_suffix(".0"), int(state.pulls), int(state.pity), int(c.PITY_SMALL), int(c.PITY_SMALL), int(c.SPOOK_AT_PITY * 100), int(c.PITY_BIG)]
	await get_tree().process_frame
	if not visible or rolling: return
	_update_layout()

func _on_viewport_size_changed() -> void:
	if visible:
		_update_layout()

func _update_layout() -> void:
	if not is_instance_valid(panel) or not is_instance_valid(results_scroll) or not is_instance_valid(results_grid):
		return
	var viewport_size := get_viewport_rect().size
	panel.custom_minimum_size.x = minf(580.0, viewport_size.x * 0.96)
	results_grid.columns = 3 if viewport_size.x <= 540.0 else 5
	results_scroll.custom_minimum_size.y = minf(results_grid.get_combined_minimum_size().y, viewport_size.y * 0.54)
	if not rolling:
		panel.reset_size()
