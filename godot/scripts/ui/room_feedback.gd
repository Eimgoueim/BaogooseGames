extends Control
const Style = preload("res://scripts/ui/legacy_ui_style.gd")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func floating(emoji: String) -> void:
	for index in 3:
		var label := Style.label(emoji, 18)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.position = Vector2(size.x * randf_range(0.18, 0.8), size.y * 0.76)
		add_child(label)
		label.modulate.a = 0; label.scale = Vector2(0.6, 0.6)
		var tween := label.create_tween()
		tween.tween_interval(index * 0.12)
		tween.set_parallel()
		tween.tween_property(label, "modulate:a", 1.0, 0.3375)
		tween.tween_property(label, "scale", Vector2(1.15, 1.15), 1.35)
		tween.tween_property(label, "position:y", label.position.y - 58, 1.35)
		tween.chain().tween_property(label, "modulate:a", 0.0, 0.2)
		tween.tween_callback(label.queue_free)

func gain(text: String) -> void:
	if text.is_empty(): return
	var panel := PanelContainer.new()
	var style := Style.panel_style(Color(60.0 / 255, 45.0 / 255, 110.0 / 255, 0.92), Color.TRANSPARENT, 20)
	style.content_margin_left = 11; style.content_margin_right = 11; style.content_margin_top = 4; style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(Style.label(text, 13)); add_child(panel)
	panel.position = Vector2(size.x / 2 - panel.get_combined_minimum_size().x / 2, size.y * 0.46 + 10)
	panel.modulate.a = 0
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.28)
	tween.parallel().tween_property(panel, "position:y", size.y * 0.46, 0.28)
	tween.tween_property(panel, "position:y", size.y * 0.46 - 46, 1.12)
	tween.parallel().tween_property(panel, "modulate:a", 0.0, 1.12)
	tween.tween_callback(panel.queue_free)

func feed(emoji: String, text: String) -> void:
	var label := Style.label(emoji, 26); label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(size.x - 32, size.y * 0.26); label.modulate.a = 0
	add_child(label)
	var tween := label.create_tween()
	tween.set_parallel()
	tween.tween_property(label, "modulate:a", 1.0, 0.12)
	tween.tween_property(label, "position", Vector2(size.x * 0.52, size.y * 0.46), 0.48).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "rotation", deg_to_rad(-16), 0.48)
	tween.chain().tween_property(label, "position", Vector2(size.x * 0.48, size.y * 0.58), 0.32)
	tween.parallel().tween_property(label, "rotation", 0.0, 0.32)
	tween.parallel().tween_property(label, "scale", Vector2(0.5, 0.5), 0.32)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.32)
	tween.chain().tween_callback(label.queue_free)
	for index in 3:
		var crumb := Style.label(["✨", "🍽️", "💛"][index], 12)
		crumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crumb.position = Vector2(size.x * (0.42 + index * 0.06), size.y * 0.58); add_child(crumb)
		var motion := crumb.create_tween().set_parallel()
		motion.tween_property(crumb, "position", crumb.position + Vector2((index - 1) * 28, -26), 1)
		motion.tween_property(crumb, "rotation", PI, 1)
		motion.tween_property(crumb, "modulate:a", 0.0, 1)
		motion.chain().tween_callback(crumb.queue_free)
	gain(text)

func cry(text: String) -> void:
	var panel := PanelContainer.new(); panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := Style.panel_style(Color(30.0 / 255, 22.0 / 255, 54.0 / 255, 0.78), Color.TRANSPARENT, 11)
	style.content_margin_left = 9; style.content_margin_right = 9; style.content_margin_top = 2; style.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(Style.label(text, 13)); add_child(panel)
	panel.position = Vector2(size.x / 2 - panel.get_combined_minimum_size().x / 2, size.y * 0.34)
	get_tree().create_timer(1.3).timeout.connect(panel.queue_free)
