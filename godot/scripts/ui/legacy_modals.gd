extends Control

signal action_requested(action: String)
signal save_import_requested(raw: String)

const UIStyle = preload("res://scripts/ui/legacy_ui_style.gd")
const RoomRenderer = preload("res://scripts/room_renderer.gd")
const SPECIES_ORDER := ["dragon", "hoshino", "goose", "cat", "whale", "gpt", "claude", "gemini"]
const THEME_ORDER := ["sakura", "ocean", "forest", "clay", "mint", "night"]

class PetPixel extends Control:
	var commands: Array = []

	func _draw() -> void:
		if commands.is_empty():
			return
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

var input_text: TextEdit
var _dialog_input: LineEdit
var _accent_input: ColorPickerButton
var _active_kind := ""
var _current_state: Dictionary = {}
var _catalog: Dictionary = {}
var _art: Dictionary = {}
var _vars: Dictionary = {}
var _panel: PanelContainer
var _body: VBoxContainer
var _species_scroll: ScrollContainer
var _species_grid: GridContainer

func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func show_modal(kind: String, state: Dictionary, catalog: Dictionary, art: Dictionary) -> void:
	_active_kind = kind
	_current_state = state
	_catalog = catalog
	_art = art
	_vars = _theme_vars(state)
	_rebuild()
	visible = true

func close_modal() -> void:
	visible = false
	_active_kind = ""

func show_dialog(opts: Dictionary, vars: Dictionary) -> void:
	_active_kind = "dialog"
	_vars = vars
	_rebuild_dialog(opts)
	visible = true

func get_save_text() -> String:
	return input_text.text if is_instance_valid(input_text) else ""

func set_save_text(text: String) -> void:
	if is_instance_valid(input_text):
		input_text.text = text

func get_dialog_text() -> String:
	return _dialog_input.text if is_instance_valid(_dialog_input) else ""

func get_accent() -> String:
	return "#" + _accent_input.color.to_html(false) if is_instance_valid(_accent_input) else ""

func _rebuild() -> void:
	_clear_children()
	UIStyle.apply(self, _vars)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.11, 0.086, 0.20, 0.52)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(minf(580.0, get_viewport_rect().size.x * 0.96), 0)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_panel.add_theme_stylebox_override("panel", UIStyle.panel_style(_color_var("--card", "#ffffff"), _color_var("--line", "#eceaf6"), 24))
	center.add_child(_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)
	var scroll := ScrollContainer.new()
	var viewport_height := get_viewport_rect().size.y
	scroll.custom_minimum_size = Vector2(0, 1)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	margin.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)
	match _active_kind:
		"theme": _build_theme()
		"adopt": _build_adopt()
		"save": _build_save()
		_: _build_theme()
	call_deferred("_fit_modal_after_layout", scroll, _body, viewport_height)

func _rebuild_dialog(opts: Dictionary) -> void:
	_clear_children()
	UIStyle.apply(self, _vars)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.11, 0.086, 0.20, 0.52)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(minf(430.0, get_viewport_rect().size.x * 0.94), 0)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var night := str(_current_state.get("theme", "")) == "night"
	var panel_fill := Color(44.0 / 255.0, 34.0 / 255.0, 66.0 / 255.0, 0.32) if night else Color(1.0, 1.0, 1.0, 0.30)
	var panel_frame := StyleBoxFlat.new()
	panel_frame.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	panel_frame.border_color = Color(1.0, 1.0, 1.0, 0.5)
	panel_frame.set_border_width_all(1)
	panel_frame.set_corner_radius_all(24)
	_panel.add_theme_stylebox_override("panel", panel_frame)
	center.add_child(_panel)
	var blur := ColorRect.new()
	blur.name = "FrostedBlur"
	blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var blur_material := ShaderMaterial.new()
	blur_material.shader = load("res://shaders/frosted_glass.gdshader")
	blur_material.set_shader_parameter("blur_radius", 12.0)
	blur_material.set_shader_parameter("corner_radius", 24.0)
	blur.material = blur_material
	blur.resized.connect(_sync_blur_size.bind(blur, blur_material))
	_panel.add_child(blur)
	call_deferred("_sync_blur_size", blur, blur_material)
	var tint := Panel.new()
	tint.name = "FrostedTint"
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint.add_theme_stylebox_override("panel", UIStyle.panel_style(panel_fill, Color.TRANSPARENT, 24))
	_panel.add_child(tint)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	margin.add_child(_body)
	_body.add_child(UIStyle.label(str(opts.get("title", "提示")), 16, _ink()))
	var body_label: Label = UIStyle.label(str(opts.get("body", "")), 14, _ink())
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(body_label)
	_dialog_input = null
	if bool(opts.get("input", false)):
		_dialog_input = LineEdit.new()
		_dialog_input.max_length = 8
		_dialog_input.text = str(opts.get("value", ""))
		_style_input(_dialog_input)
		_body.add_child(_dialog_input)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	_body.add_child(actions)
	if not str(opts.get("confirmText", "")).is_empty():
		var cancel := _button("取消", "dlgcancel")
		_style_dialog_button(cancel, false)
		actions.add_child(cancel)
	var confirm := _button(str(opts.get("confirmText", "知道了")), "dlgok")
	_style_dialog_button(confirm, true)
	actions.add_child(confirm)

func _style_dialog_button(button: Button, primary: bool) -> void:
	var fill := Color(1.0, 1.0, 1.0, 0.34)
	var primary_style := _primary_dialog_button_style() if primary else null
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style: StyleBox
		if primary:
			style = primary_style
		else:
			var flat := StyleBoxFlat.new()
			flat.bg_color = fill
			flat.set_corner_radius_all(10)
			style = flat
		style.content_margin_left = 12.0
		style.content_margin_right = 12.0
		style.content_margin_top = 7.0
		style.content_margin_bottom = 7.0
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", Color.WHITE if primary else _color_var("--ink", "#2c2b3d"))
	button.add_theme_color_override("font_hover_color", Color.WHITE if primary else _color_var("--ink", "#2c2b3d"))
	button.add_theme_color_override("font_pressed_color", Color.WHITE if primary else _color_var("--ink", "#2c2b3d"))

func _primary_dialog_button_style() -> StyleBoxTexture:
	const width := 96
	const height := 40
	const radius := 10.0
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var left := Color(139.0 / 255.0, 123.0 / 255.0, 1.0, 0.72)
	var right := Color(1.0, 143.0 / 255.0, 177.0 / 255.0, 0.72)
	var half := Vector2(width * 0.5, height * 0.5)
	for y in range(height):
		for x in range(width):
			var q := Vector2(absf(x + 0.5 - half.x), absf(y + 0.5 - half.y)) - half + Vector2.ONE * radius
			var distance := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
			var coverage := clampf((1.0 - distance) * 0.5, 0.0, 1.0)
			var color := left.lerp(right, float(x + y) / float(width + height - 2))
			color.a *= coverage
			image.set_pixel(x, y, color)
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(image)
	style.texture_margin_left = radius
	style.texture_margin_right = radius
	style.texture_margin_top = radius
	style.texture_margin_bottom = radius
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style

func _sync_blur_size(blur: ColorRect, material: ShaderMaterial) -> void:
	if is_instance_valid(blur) and is_instance_valid(material):
		material.set_shader_parameter("rect_size", blur.size)

func _build_theme() -> void:
	var current_theme := str(_current_state.get("theme", "sakura"))
	var current_accent := str(_current_state.get("accent", ""))
	_add_header("🎨 界面风格", _theme_hint(current_theme, current_accent), _color_var("--purple", "#8b7bff"))
	var grid := GridContainer.new()
	grid.columns = 2 if get_viewport_rect().size.x <= 480.0 else 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_body.add_child(grid)
	var themes: Dictionary = _catalog.get("THEMES", {})
	for key in THEME_ORDER:
		var theme: Dictionary = themes.get(key, {})
		var btn := _button("", "theme:" + key)
		btn.custom_minimum_size = Vector2(0, 95)
		var theme_vars: Dictionary = theme.get("vars", {})
		var is_current: bool = str(key) == current_theme and current_accent.is_empty()
		var theme_bg := _dict_color(theme_vars, "--btn", "#f4f2fd") if is_current else _dict_color(theme_vars, "--soft", "#faf9ff")
		var theme_border := _color_var("--purple", "#8b7bff") if is_current else _dict_color(theme_vars, "--line2", "#e6e2f7")
		btn.add_theme_stylebox_override("normal", UIStyle.panel_style(theme_bg, theme_border, 16))
		btn.add_theme_stylebox_override("hover", UIStyle.panel_style(theme_bg.lightened(0.04), _color_var("--purple", "#8b7bff"), 16))
		btn.add_theme_stylebox_override("pressed", UIStyle.panel_style(theme_bg.darkened(0.03), _color_var("--purple", "#8b7bff"), 16))
		grid.add_child(btn)
		var inset := MarginContainer.new()
		inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inset.add_theme_constant_override("margin_left", 6)
		inset.add_theme_constant_override("margin_right", 6)
		inset.add_theme_constant_override("margin_top", 8)
		inset.add_theme_constant_override("margin_bottom", 8)
		btn.add_child(inset)
		var cell := VBoxContainer.new()
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_theme_constant_override("separation", 6)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inset.add_child(cell)
		var emoji: Label = UIStyle.label(str(theme.get("emoji", "")), 18, _ink())
		emoji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(emoji)
		var name: Label = UIStyle.label(str(theme.get("name", key)), 12, _ink())
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(name)
		var palette: HBoxContainer = HBoxContainer.new()
		palette.alignment = BoxContainer.ALIGNMENT_CENTER
		palette.add_theme_constant_override("separation", 4)
		cell.add_child(palette)
		for color_key in ["--purple", "--pink", "--bg1"]:
			var swatch := Panel.new()
			swatch.custom_minimum_size = Vector2(15, 15)
			var swatch_color := Color.from_string(str(theme_vars.get(color_key, "#ffffff")), Color.WHITE)
			swatch.add_theme_stylebox_override("panel", UIStyle.panel_style(swatch_color, Color(0, 0, 0, 0.08), 8))
			palette.add_child(swatch)
		_set_mouse_ignore(inset)
	var accent_row := HBoxContainer.new()
	accent_row.add_theme_constant_override("separation", 8)
	_body.add_child(accent_row)
	accent_row.add_child(UIStyle.label("自定义主色", 12, _muted()))
	_accent_input = ColorPickerButton.new()
	_accent_input.custom_minimum_size = Vector2(42, 32)
	var accent := str(_current_state.get("accent", ""))
	if accent.is_empty():
		accent = str(_vars.get("--purple", "#8b7bff"))
	_accent_input.color = Color.from_string(accent, Color("#8b7bff"))
	_accent_input.color_changed.connect(func(color: Color) -> void: action_requested.emit("accentlive:#" + color.to_html(false)))
	accent_row.add_child(_accent_input)
	accent_row.add_child(_button("应用", "accentapply"))
	accent_row.add_child(_button("恢复默认", "accentclear"))
	_add_footer("配色会一起存进存档", "themeclose")

func _build_adopt() -> void:
	var unlocked := _unlocked_species()
	var pets: Array = _current_state.get("pets", [])
	var slots := _slots_unlocked()
	var hint := "首次选择：点一只作为你的初始宠物（之后升级解锁更多栏位）"
	if bool(_current_state.get("picked", false)):
		hint = "队伍 %d/%d · 点整张卡片即可领养" % [pets.size(), slots]
		if pets.size() >= slots:
			hint += "（栏位已满，升级解锁）"
	_add_header("🐾 领养宠物", hint)
	var grave: Array = _current_state.get("grave", [])
	if not grave.is_empty():
		_body.add_child(UIStyle.label("🪦 已离世的伙伴（玩家等级 Lv.10 可复活：💰500，限定宠物还需 🧩10 碎片）· 当前玩家等级 Lv.%d" % int(_current_state.get("lv", 1)), 12, _ink()))
		for i in grave.size():
			_add_grave_row(grave[i], i)
	var species_data: Dictionary = _catalog.get("SPECIES", {})
	var species_scroll := ScrollContainer.new()
	_species_scroll = species_scroll
	species_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	species_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(species_scroll)
	var species_grid := GridContainer.new()
	_species_grid = species_grid
	species_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner_width := minf(580.0, get_viewport_rect().size.x * 0.96) - 32.0
	species_grid.columns = maxi(1, int(floor((inner_width + 8.0) / 158.0)))
	species_grid.add_theme_constant_override("h_separation", 8)
	species_grid.add_theme_constant_override("v_separation", 8)
	species_scroll.add_child(species_grid)
	for key in SPECIES_ORDER:
		var spec: Dictionary = species_data.get(key, {})
		var locked := bool(spec.get("limited", false)) and not unlocked.has(key)
		var count := 0
		for pet in pets:
			if pet is Dictionary and pet.get("species", "") == key and not bool(pet.get("dead", false)):
				count += 1
		var card := _button("", "adoptpick:" + key)
		card.custom_minimum_size = Vector2(150, 102)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if locked:
			card.modulate = Color(1, 1, 1, 0.55)
		species_grid.add_child(card)
		var inset := MarginContainer.new()
		inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inset.add_theme_constant_override("margin_left", 8)
		inset.add_theme_constant_override("margin_right", 8)
		inset.add_theme_constant_override("margin_top", 5)
		inset.add_theme_constant_override("margin_bottom", 5)
		inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(inset)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inset.add_child(row)
		var thumb := _make_thumbnail(key, locked)
		thumb.custom_minimum_size = Vector2(50, 50)
		thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(thumb)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(info)
		info.add_child(UIStyle.label("？？？" if locked else str(spec.get("name", key)) + (" · " + str(spec.get("tag", ""))), 13, _ink()))
		var desc := "抽卡限定：去「🎰 抽卡」有 %s%% 概率获得" % _pet_probability() if locked else str(spec.get("desc", ""))
		var descr: Label = UIStyle.label(desc, 11, _muted())
		descr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(descr)
		if count > 0:
			info.add_child(UIStyle.label("已养 %d 只" % count, 10, Color("#2c8f74")))
		_set_mouse_ignore(inset)
	_add_footer("首次选择＝选定初始宠物 · 之后每升 1 级解锁 1 个栏位 · 限定宠物只能靠抽卡解锁", "adoptclose")

func _build_save() -> void:
	var pets: Array = _current_state.get("pets", [])
	var saved_at := _save_time_text()
	_add_header("💾 存档", saved_at + " · %d/10 只宠物" % pets.size())
	var row := GridContainer.new()
	row.columns = 2
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	_body.add_child(row)
	for item in [["即时保存", "savenow"], ["导出到文本框", "saveexport"], ["复制存档", "savecopy"], ["下载 .json", "savedownload"], ["🐾 领养新宠物", "adoptopen"], ["🔄 重开游戏", "reset"]]:
		row.add_child(_button(item[0], item[1]))
	input_text = TextEdit.new()
	input_text.custom_minimum_size = Vector2(0, 132)
	input_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_text.placeholder_text = "点「导出到文本框」会在这里显示存档 JSON；也可以把备份 JSON 粘贴进来后点「导入存档」"
	input_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_style_input(input_text)
	_body.add_child(input_text)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	_body.add_child(actions)
	actions.add_child(_button("导入存档", "saveimport"))
	actions.add_child(_button("关闭", "saveclose"))

func _add_grave_row(entry: Variant, index: int) -> void:
	if not entry is Dictionary:
		return
	var spec: Dictionary = _catalog.get("SPECIES", {}).get(entry.get("species", "dragon"), {})
	var lvl := int(entry.get("level", 0))
	var limited := bool(spec.get("limited", false))
	var shards: Dictionary = _current_state.get("shards", {})
	var shard_count := int(shards.get(entry.get("species", ""), 0))
	var can_level := int(_current_state.get("lv", 1)) >= 10
	var can_revive := can_level and int(_current_state.get("coins", 0)) >= 500 and (not limited or shard_count >= 10)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_body.add_child(row)
	var desc := "💀 %s · %s · 离世时 Lv.%d" % [str(entry.get("name", "")), str(spec.get("name", "")), lvl]
	if limited:
		desc += " · 🧩%d" % shard_count
	var label: Label = UIStyle.label(desc, 11, _ink())
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var btn := _button("✨ 复活" if can_revive else ("Lv.10 才能复活" if not can_level else "条件不足"), "revive:%d" % index)
	btn.disabled = not can_revive
	row.add_child(btn)

func _make_thumbnail(key: String, locked: bool) -> Control:
	if locked:
		return UIStyle.label("❔", 28, _muted())
	var species_art: Dictionary = _art.get("pets", {}).get(key, {})
	var thumbnail := PetPixel.new()
	thumbnail.custom_minimum_size = Vector2(56, 56)
	thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumbnail.commands = species_art.get("0_awake", [])
	return thumbnail

func _add_header(title: String, hint: String, hint_color: Color = Color("#8b7bff")) -> void:
	var row := HBoxContainer.new()
	_body.add_child(row)
	var heading: Label = UIStyle.label(title, 16, _ink())
	heading.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(heading)
	var hint_label: Label = UIStyle.label(hint, 12, hint_color)
	hint_label.custom_minimum_size.x = 220
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(hint_label)

func _add_footer(text: String, close_action: String) -> void:
	var row := HBoxContainer.new()
	_body.add_child(row)
	var hint: Label = UIStyle.label(text, 11, _muted())
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(hint)
	row.add_child(_button("关闭", close_action))

func _button(text: String, action: String) -> Button:
	var primary := action == "saveimport" or action == "dlgok"
	return UIStyle.card_button(text, action, Callable(self, "_on_action"), _vars, primary)

func _on_action(action: String) -> void:
	if action == "saveexport":
		set_save_text(JSON.stringify(_current_state))
	if action == "saveimport":
		save_import_requested.emit(get_save_text())
		return
	action_requested.emit(action)

func _style_input(control: Control) -> void:
	control.add_theme_color_override("font_color", _ink())
	control.add_theme_color_override("font_placeholder_color", _muted())
	control.add_theme_stylebox_override("normal", UIStyle.panel_style(_color_var("--soft", "#faf9ff"), _color_var("--line2", "#e6e2f7"), 14))
	control.add_theme_stylebox_override("focus", UIStyle.panel_style(_color_var("--soft", "#faf9ff"), _color_var("--purple", "#8b7bff"), 14))

func _theme_vars(state: Dictionary) -> Dictionary:
	return RoomRenderer.theme_vars(state, _catalog)

func _theme_hint(theme_key: String, accent: String) -> String:
	var themes: Dictionary = _catalog.get("THEMES", {})
	var theme: Dictionary = themes.get(theme_key, themes.get("sakura", {}))
	var text := "当前：" + str(theme.get("name", theme_key))
	if not accent.is_empty():
		text += " + 自定义主色 " + accent
	return text

func _unlocked_species() -> Array:
	var result: Array = _current_state.get("collection", []).duplicate()
	for pet in _current_state.get("pets", []):
		if pet is Dictionary and not result.has(pet.get("species", "")):
			result.append(pet.get("species", ""))
	return result

func _save_time_text() -> String:
	var stamp := int(_current_state.get("lastTick", _current_state.get("last_tick", 0)))
	if stamp <= 0:
		stamp = int(Time.get_unix_time_from_system())
	if stamp > 100000000000:
		stamp = int(stamp / 1000)
	var zone := Time.get_time_zone_from_system()
	stamp += int(zone.get("bias", 0)) * 60
	var parts := Time.get_datetime_dict_from_unix_time(stamp)
	return "上次保存 %02d:%02d:%02d" % [parts.hour, parts.minute, parts.second]

func _slots_unlocked() -> int:
	var max_pets := int(_catalog.get("constants", {}).get("MAX_PETS", 10))
	return maxi(1, mini(max_pets, int(_current_state.get("lv", 1))))

func _pet_probability() -> String:
	var rate := float(_catalog.get("constants", {}).get("PET_RATE", 0.015)) * 100.0
	return str(rate).trim_suffix(".0")

func _set_mouse_ignore(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control:
			_set_mouse_ignore(child)

func _fit_modal_after_layout(scroll: ScrollContainer, body: VBoxContainer, viewport_height: float) -> void:
	await get_tree().process_frame
	if not is_instance_valid(scroll) or not is_instance_valid(body):
		return
	if is_instance_valid(_species_grid) and is_instance_valid(_species_scroll):
		for card in _species_grid.get_children():
			if card is Button and card.get_child_count() > 0:
				var content: Control = card.get_child(0)
				card.custom_minimum_size.y = maxf(74.0, content.get_combined_minimum_size().y + 10.0)
		_species_scroll.custom_minimum_size.y = minf(_species_grid.get_combined_minimum_size().y, viewport_height * 0.44) if is_instance_valid(_species_grid) and is_instance_valid(_species_scroll) else 0.0
	var natural_height := body.get_combined_minimum_size().y
	scroll.custom_minimum_size.y = minf(maxf(120.0, natural_height), viewport_height * 0.88)

func _ink() -> Color:
	return _color_var("--ink", "#2c2b3d")

func _muted() -> Color:
	return _color_var("--muted", "#7c7b92")

func _color_var(key: String, fallback: String) -> Color:
	var value: Variant = _vars.get(key, fallback)
	return value if value is Color else Color.from_string(str(value), Color(fallback))

func _dict_color(values: Dictionary, key: String, fallback: String) -> Color:
	return Color.from_string(str(values.get(key, fallback)), Color(fallback))

func _clear_children() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	input_text = null
	_dialog_input = null
	_accent_input = null
	_panel = null
	_body = null
	_species_scroll = null
	_species_grid = null
