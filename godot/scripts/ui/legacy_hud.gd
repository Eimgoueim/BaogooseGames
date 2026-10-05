class_name LegacyHUD
extends Control

const Style = preload("res://scripts/ui/legacy_ui_style.gd")
const Catalog = preload("res://scripts/legacy_catalog.gd")

signal action_requested(action: String)

const STAT_ROWS: Array[Dictionary] = [
	{"key": "hunger", "emoji": "🍖"},
	{"key": "mood", "emoji": "😊"},
	{"key": "clean", "emoji": "🫧"},
	{"key": "energy", "emoji": "⚡"},
	{"key": "health", "emoji": "❤️"},
]

class PetPixel extends Control:
	var commands: Array = []

	func _draw() -> void:
		if commands.is_empty():
			return
		# paintPetThumbs 的 40×36 画布、(20,34) 原点与 1.1 倍缩放。
		var canvas_scale := minf(size.x / 40.0, size.y / 36.0)
		var scale_factor := canvas_scale * 1.1
		var origin := Vector2(size.x * 0.5, 34.0 * canvas_scale)
		for command: Array in commands:
			var rect := Rect2(
				origin.x + float(command[0]) * scale_factor,
				origin.y + float(command[1]) * scale_factor,
				float(command[2]) * scale_factor,
				float(command[3]) * scale_factor
			)
			var color := Color(float(command[4]), float(command[5]), float(command[6]), float(command[7]))
			draw_rect(rect, color, true)

var _catalog: Dictionary = {}
var _art: Dictionary = {}
var _vars: Dictionary = {}
var _left: VBoxContainer
var _slots: GridContainer
var _slots_title: Label
var _last_state: Dictionary = {}
var _last_top_ui: float = 96.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_catalog = Catalog.load_catalog()
	_vars = _theme_vars(_catalog, "sakura")
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()

func refresh(state: Dictionary, catalog: Dictionary, art: Dictionary, top_ui: float) -> void:
	_last_state = state
	_last_top_ui = top_ui
	_catalog = catalog if not catalog.is_empty() else Catalog.load_catalog()
	_art = art
	_vars = _theme_vars(_catalog, str(state.get("theme", "sakura")))
	Style.apply(self, _vars)
	if _left == null:
		_build()
	_update_left(state)
	_update_slots(state)
	_layout()

func _build() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_left = VBoxContainer.new()
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left.add_theme_constant_override("separation", 0)
	add_child(_left)
	_slots = GridContainer.new()
	_slots.columns = 6
	_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots.add_theme_constant_override("h_separation", 3)
	_slots.add_theme_constant_override("v_separation", 2)
	add_child(_slots)
	_slots_title = Style.label("", 8, Color.WHITE)
	_slots_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_slots_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_slots_title.add_theme_color_override("font_shadow_color", Color(0.08, 0.06, 0.15, 0.9))
	_slots_title.add_theme_constant_override("shadow_offset_x", 1)
	_slots_title.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_slots_title)

func _update_left(state: Dictionary) -> void:
	for child: Node in _left.get_children():
		_left.remove_child(child)
		child.queue_free()
	var pets: Array = state.get("pets", [])
	var active_index := int(state.get("active", 0))
	var pet: Dictionary = pets[active_index] if active_index >= 0 and active_index < pets.size() and pets[active_index] is Dictionary else {}
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override("separation", 6)
	_left.add_child(head)
	var pet_name := str(pet.get("name", "??"))
	var name_label := Style.label(pet_name, 15)
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.custom_minimum_size.x = 42.0
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(name_label)
	var level_label := Style.label("Lv.%d" % int(pet.get("level", 0)), 11, Color("#ffe9a8"))
	head.add_child(level_label)
	var rename_button := Style.button("✎", "rename", _emit_action, _vars)
	rename_button.custom_minimum_size = Vector2(18, 17)
	head.add_child(rename_button)

	var stat_box := VBoxContainer.new()
	stat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat_box.add_theme_constant_override("separation", 3)
	_add_spacer(_left, 6)
	_left.add_child(stat_box)
	var exp_need := 40 + int(pet.get("level", 1)) * 35
	var aff_need := 60 + int(pet.get("affRank", 1)) * 50
	for row: Dictionary in STAT_ROWS:
		_add_stat(stat_box, str(row.key), str(row.emoji), float(pet.get(row.key, 0)), "")
	_add_stat(stat_box, "exp", "🆙", minf(100.0, roundf(float(pet.get("exp", 0)) / maxf(1.0, float(exp_need)) * 100.0)), "经验 %s/%s" % [str(floori(float(pet.get("exp", 0)))), str(exp_need)])
	_add_stat(stat_box, "aff", "💗", minf(100.0, roundf(float(pet.get("affinity", 0)) / maxf(1.0, float(aff_need)) * 100.0)), "羁绊 Lv.%s · %s/%s" % [str(pet.get("affRank", 1)), str(floori(float(pet.get("affinity", 0)))), str(aff_need)])

	var resources := HFlowContainer.new()
	resources.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resources.add_theme_constant_override("h_separation", 5)
	resources.add_theme_constant_override("v_separation", 2)
	_add_spacer(_left, 6)
	_left.add_child(resources)
	_add_resource(resources, "💰", str(floori(float(state.get("coins", 0)))))
	_add_resource(resources, "⭐", str(floori(float(state.get("points", 0)))))
	_add_resource(resources, "🎒", str(_total_items(state.get("inv", {}))))

	var status_line := HFlowContainer.new()
	status_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_line.add_theme_constant_override("h_separation", 4)
	status_line.add_theme_constant_override("v_separation", 2)
	_add_spacer(_left, 5)
	_left.add_child(status_line)
	for tag: Dictionary in _status_tags(state, pet):
		_add_tag(status_line, str(tag.emoji), str(tag.tone), str(tag.text))

func _add_stat(parent: VBoxContainer, key: String, emoji: String, value: float, description: String) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var icon := Style.label(emoji, 9)
	icon.custom_minimum_size = Vector2(20, 18)
	icon.tooltip_text = (description if not description.is_empty() else key) + "：" + str(roundi(value)) + "%"
	row.add_child(icon)
	var bar := HBoxContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 1)
	bar.custom_minimum_size = Vector2(109, 9)
	row.add_child(bar)
	var on_cells := roundi(clampf(value, 0.0, 100.0) / 100.0 * 10.0)
	var tone := ""
	if key == "exp":
		tone = "exp"
	elif key == "aff":
		tone = "aff"
	elif value < 25.0:
		tone = "bad"
	elif value < 50.0:
		tone = "warn"
	for index in range(10):
		var cell := ColorRect.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.custom_minimum_size = Vector2(10, 9)
		cell.color = _bar_color(tone) if index < on_cells else Color(1.0, 1.0, 1.0, 0.16)
		bar.add_child(cell)

func _add_resource(parent: HFlowContainer, emoji: String, value: String) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", Style.panel_style(Color(0.118, 0.086, 0.212, 0.42), Color.TRANSPARENT, 8))
	var chip := HBoxContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_constant_override("separation", 2)
	var icon := Style.label(emoji, 10)
	chip.add_child(icon)
	var amount := Style.label(value, 10)
	amount.add_theme_font_size_override("font_size", 15)
	chip.add_child(amount)
	panel.add_child(chip)
	parent.add_child(panel)

func _add_tag(parent: HFlowContainer, emoji: String, tone: String, description: String) -> void:
	var tag := PanelContainer.new()
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.custom_minimum_size = Vector2(17, 14)
	tag.tooltip_text = description
	tag.add_theme_stylebox_override("panel", Style.panel_style(Color(0.118, 0.086, 0.212, 0.42), Color.TRANSPARENT, 8))
	var icon := Style.label(emoji, 9)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.add_child(icon)
	parent.add_child(tag)

func _update_slots(state: Dictionary) -> void:
	for child: Node in _slots.get_children():
		_slots.remove_child(child)
		child.queue_free()
	var pets: Array = state.get("pets", [])
	var active_index := int(state.get("active", 0))
	var unlocked := clampi(int(state.get("lv", 1)), 1, 10)
	_slots.columns = 3 if get_viewport_rect().size.x <= 560.0 else 6
	_slots_title.text = "👤Lv.%d · 🐾%d/%d" % [int(state.get("lv", 1)), pets.size(), unlocked]
	for index in range(10):
		var pet: Dictionary = pets[index] if index < pets.size() and pets[index] is Dictionary else {}
		var slot := Button.new()
		slot.flat = true
		slot.focus_mode = Control.FOCUS_NONE
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.custom_minimum_size = Vector2(0, 64)
		slot.add_theme_stylebox_override("normal", Style.panel_style(Color.TRANSPARENT, Color.TRANSPARENT, 6))
		slot.add_theme_stylebox_override("hover", Style.panel_style(Color(1.0, 1.0, 1.0, 0.06), Color.TRANSPARENT, 6))
		slot.add_theme_stylebox_override("pressed", Style.panel_style(Color(1.0, 1.0, 1.0, 0.1), Color.TRANSPARENT, 6))
		_slots.add_child(slot)
		if pet.is_empty():
			if index < unlocked:
				slot.text = "＋"
				slot.tooltip_text = "领养第 %s 只" % str(index + 1)
				slot.add_theme_font_size_override("font_size", 19)
				slot.add_theme_color_override("font_color", Color("#7c7b92"))
				slot.pressed.connect(func() -> void: action_requested.emit("adoptopen"))
			else:
				slot.text = "🔒"
				slot.disabled = true
				slot.modulate.a = 0.45
				slot.tooltip_text = "升到 Lv.%s 解锁这个栏位" % str(index + 1)
				slot.add_theme_font_size_override("font_size", 15)
			continue
		var is_active := index == active_index
		var critical := not is_active and (float(pet.get("health", 100)) <= 0.0 or float(pet.get("hunger", 100)) < 12.0 or float(pet.get("sickT", 0)) > 0.0)
		var needs_care := not is_active and (float(pet.get("hunger", 100)) < 30.0 or float(pet.get("health", 100)) <= 0.0)
		if is_active:
			slot.add_theme_stylebox_override("normal", Style.panel_style(Color(1.0, 1.0, 1.0, 0.04), Color("#ffe9a8"), 6))
		elif critical:
			slot.add_theme_stylebox_override("normal", Style.panel_style(Color(1.0, 0.3, 0.3, 0.05), Color("#ff4d4d"), 6))
		elif needs_care:
			slot.add_theme_stylebox_override("normal", Style.panel_style(Color(1.0, 0.6, 0.25, 0.08), Color("#ff9b9b"), 6))
		var layout := VBoxContainer.new()
		layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layout.add_theme_constant_override("separation", 0)
		layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		slot.add_child(layout)
		var thumbnail := PetPixel.new()
		thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumbnail.custom_minimum_size = Vector2(24, 24)
		thumbnail.commands = _pet_commands(pet)
		layout.add_child(thumbnail)
		var pet_label := Style.label(str(pet.get("name", "??")), 7)
		pet_label.add_theme_font_size_override("font_size", 14)
		pet_label.custom_minimum_size = Vector2(0, 8)
		pet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pet_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		layout.add_child(pet_label)
		var suffix := "💤" if bool(pet.get("asleep", false)) else ""
		var level := Style.label("Lv.%d%s" % [int(pet.get("level", 0)), suffix], 6, Color("#ffe9a8"))
		level.add_theme_font_size_override("font_size", 14)
		level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		layout.add_child(level)
		slot.tooltip_text = "%s Lv.%d · ❤️%s%% ⚡%s%%" % [str(pet.get("name", "??")), int(pet.get("level", 0)), str(roundi(float(pet.get("health", 0)))), str(roundi(float(pet.get("energy", 0))))]
		slot.pressed.connect(func() -> void: action_requested.emit("switch:%s" % str(index)))

func _pet_commands(pet: Dictionary) -> Array:
	var species_key := str(pet.get("species", ""))
	var species: Dictionary = _art.get("pets", {}).get(species_key, {})
	var stage := 0
	var spec: Dictionary = _catalog.get("SPECIES", {}).get(species_key, {})
	for index in range(spec.get("stages", []).size()):
		if int(pet.get("level", 1)) >= int(spec.stages[index].get("min", 1)):
			stage = index
	var face := "sleep" if bool(pet.get("asleep", false)) else "awake"
	var key := "%s_%s" % [str(stage), face]
	if not species.has(key):
		key = "%s_awake" % str(stage)
	return species.get(key, [])

func _status_tags(state: Dictionary, pet: Dictionary) -> Array[Dictionary]:
	var tags: Array[Dictionary] = []
	if pet.is_empty():
		if not state.get("grave", []).is_empty():
			tags.append({"emoji": "💀", "tone": "bad", "text": "宠物已离世"})
		else:
			tags.append({"emoji": "✨", "tone": "good", "text": "状态超好"})
		return tags
	var species: Dictionary = _catalog.get("SPECIES", {}).get(str(pet.get("species", "")), {})
	if bool(pet.get("asleep", false)):
		tags.append({"emoji": "😴", "tone": "good", "text": "睡觉中"})
	if float(pet.get("health", 100)) <= 0.0:
		tags.append({"emoji": "🤒", "tone": "bad", "text": "生病了，快用药水"})
	elif float(pet.get("health", 100)) < 25.0:
		tags.append({"emoji": "😷", "tone": "warn", "text": "身体虚弱"})
	var poops: Array = state.get("poops", [])
	if not poops.is_empty():
		tags.append({"emoji": "💩", "tone": "bad", "text": "地上有 %s 坨，点它清理" % str(poops.size())})
	if bool(pet.get("poopWarn", false)) and not bool(pet.get("asleep", false)):
		tags.append({"emoji": "💩", "tone": "warn", "text": "想拉屎：点 🛁 清洁键帮它"})
	if float(pet.get("hunger", 100)) < 25.0:
		tags.append({"emoji": "🍖", "tone": "bad", "text": "饿坏了"})
	elif float(pet.get("hunger", 100)) < 50.0:
		tags.append({"emoji": "🍖", "tone": "warn", "text": "有点饿"})
	if float(pet.get("mood", 100)) < 30.0:
		tags.append({"emoji": "😢", "tone": "warn", "text": "不开心"})
	if float(pet.get("clean", 100)) < 30.0:
		tags.append({"emoji": "🫧", "tone": "warn", "text": "脏兮兮"})
	if float(pet.get("energy", 100)) < 25.0:
		tags.append({"emoji": "⚡", "tone": "warn", "text": "累了"})
	if bool(species.get("limited", false)):
		tags.append({"emoji": str(species.get("icon", "✨")), "tone": "lim", "text": "%s：抽卡限定" % str(species.get("name", "??"))})
	if bool(species.get("ai", false)):
		tags.append({"emoji": "🤖", "tone": "ba", "text": "AI 型宠物"})
	var species_key := str(pet.get("species", ""))
	if species_key == "gpt":
		tags.append({"emoji": "🧠", "tone": "ba", "text": "学得快"})
	elif species_key == "claude":
		tags.append({"emoji": "🌼", "tone": "lim", "text": "菊之 AI"})
	elif species_key == "gemini":
		tags.append({"emoji": "🌈", "tone": "lim", "text": "彩虹双子"})
	elif species_key == "whale":
		tags.append({"emoji": "🍚", "tone": "ba", "text": "爱白饭"})
	if int(pet.get("affRank", 1)) >= 9:
		tags.append({"emoji": "💗", "tone": "ba", "text": "羁绊 Lv.%s" % str(pet.get("affRank", 1))})
	if not str(state.get("title", "")).is_empty():
		tags.append({"emoji": "🏅", "tone": "ba", "text": str(state.get("title", ""))})
	var hungry := 0
	for index in range(state.get("pets", []).size()):
		var other: Dictionary = state.pets[index]
		if index != int(state.get("active", 0)) and float(other.get("hunger", 100)) < 30.0:
			hungry += 1
	if hungry > 0:
		tags.append({"emoji": "🍽️", "tone": "warn", "text": "有 %s 只在家饿着" % str(hungry)})
	if tags.is_empty():
		tags.append({"emoji": "✨", "tone": "good", "text": "状态超好"})
	return tags

func _layout() -> void:
	if _left == null or _slots == null:
		return
	var viewport_size := get_viewport_rect().size
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var left_width := minf(viewport_size.x * 0.46, 230.0)
	_left.position = Vector2(12.0, _last_top_ui)
	_left.size = Vector2(left_width, maxf(0.0, viewport_size.y - _last_top_ui))
	var narrow := viewport_size.x <= 560.0
	var right_width := minf(viewport_size.x * 0.44, 210.0) if narrow else viewport_size.x * 0.32
	if not narrow:
		right_width = minf(right_width, 360.0)
	_slots.columns = 3 if narrow else 6
	_slots_title.position = Vector2(viewport_size.x - right_width - 2.0, _last_top_ui)
	_slots_title.size = Vector2(right_width, 22.0)
	_slots.position = Vector2(viewport_size.x - right_width - 2.0, _last_top_ui + 24.0)
	_slots.size = Vector2(right_width, 132.0)
	for child: Control in _slots.get_children():
		child.custom_minimum_size.x = 0.0
		child.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _emit_action(action: String) -> void:
	action_requested.emit(action)

func _total_items(inventory: Variant) -> int:
	if not inventory is Dictionary:
		return 0
	var total := 0
	for value: Variant in inventory.values():
		total += maxi(0, int(value))
	return total

func _add_spacer(parent: VBoxContainer, height: float) -> void:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size.y = height
	parent.add_child(spacer)

func _theme_vars(catalog: Dictionary, theme_key: String) -> Dictionary:
	var themes: Dictionary = catalog.get("THEMES", {})
	var theme: Dictionary = themes.get(theme_key, themes.get("sakura", {}))
	return theme.get("vars", {})

func _bar_color(tone: String) -> Color:
	match tone:
		"warn": return Color("#ffd27a")
		"bad": return Color("#ff8f8f")
		"exp": return Color("#9fd8ff")
		"aff": return Color("#ffb3d1")
		_: return Color("#8ce6b4")
