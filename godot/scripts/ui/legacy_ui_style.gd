class_name LegacyUIStyle
extends RefCounted

# 紧凑版 6–12px 字号即使随全屏放大仍偏小，正文统一保留可读下限。
static func readable_font_size(size: int) -> int:
	return maxi(14, roundi(size * 1.25))

static func apply(control: Control, vars: Dictionary) -> void:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "微软雅黑", "Segoe UI", "Segoe UI Emoji"])
	theme.default_font = font
	theme.default_font_size = readable_font_size(12)
	theme.set_color("font_color", "Label", _color(vars, "--ink", Color("#2c2b3d")))
	theme.set_color("font_color", "Button", Color.WHITE)
	control.theme = theme

static func panel_style(bg: Color, border: Color = Color.TRANSPARENT, radius: int = 11) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	return style

static func button(text: String, action: String, emit: Callable, vars: Dictionary) -> Button:
	var result := Button.new()
	result.text = text
	result.focus_mode = Control.FOCUS_NONE
	result.mouse_filter = Control.MOUSE_FILTER_STOP
	result.add_theme_font_size_override("font_size", readable_font_size(10))
	result.add_theme_color_override("font_color", Color.WHITE)
	result.add_theme_color_override("font_hover_color", Color.WHITE)
	result.add_theme_stylebox_override("normal", panel_style(Color(0.12, 0.09, 0.21, 0.42), Color.TRANSPARENT, 8))
	result.add_theme_stylebox_override("hover", panel_style(Color(0.16, 0.12, 0.28, 0.56), Color.TRANSPARENT, 8))
	result.add_theme_stylebox_override("pressed", panel_style(Color(0.16, 0.12, 0.28, 0.68), Color.TRANSPARENT, 8))
	result.pressed.connect(func() -> void:
		if emit.is_valid():
			emit.call(action)
	)
	return result

static func card_button(text: String, action: String, emit: Callable, vars: Dictionary, primary: bool = false) -> Button:
	var result := Button.new()
	result.text = text
	result.focus_mode = Control.FOCUS_NONE
	result.mouse_filter = Control.MOUSE_FILTER_STOP
	result.add_theme_font_size_override("font_size", readable_font_size(12))
	var ink := _color(vars, "--ink", Color("#2c2b3d"))
	var accent := _color(vars, "--purple", Color("#8b7bff"))
	var base := accent if primary else _color(vars, "--btn", Color("#f4f2fd"))
	var hover := base.lightened(0.07) if not primary else base.lightened(0.09)
	var pressed := base.darkened(0.07)
	result.add_theme_color_override("font_color", Color.WHITE if primary else ink)
	result.add_theme_color_override("font_hover_color", Color.WHITE if primary else ink)
	result.add_theme_color_override("font_pressed_color", Color.WHITE if primary else ink)
	result.add_theme_color_override("font_disabled_color", Color(ink.r, ink.g, ink.b, 0.42))
	result.add_theme_stylebox_override("normal", _card_button_style(base, primary))
	result.add_theme_stylebox_override("hover", _card_button_style(hover, primary))
	result.add_theme_stylebox_override("pressed", _card_button_style(pressed, primary))
	result.add_theme_stylebox_override("disabled", _card_button_style(base, primary))
	result.pressed.connect(func() -> void:
		if emit.is_valid():
			emit.call(action)
	)
	return result

static func label(text: String, size: int = 12, color: Color = Color.WHITE) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", readable_font_size(size))
	result.add_theme_color_override("font_color", color)
	if color == Color.WHITE:
		result.add_theme_color_override("font_shadow_color", Color(0.08, 0.05, 0.17, 0.8))
		result.add_theme_constant_override("shadow_offset_x", 0)
		result.add_theme_constant_override("shadow_offset_y", 1)
	return result

static func _card_button_style(color: Color, primary: bool) -> StyleBoxFlat:
	var style := panel_style(color, Color.TRANSPARENT, 12)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	if primary:
		style.shadow_color = Color(0.55, 0.48, 1.0, 0.28)
		style.shadow_size = 5
	return style

static func _color(vars: Dictionary, key: String, fallback: Color) -> Color:
	var value: Variant = vars.get(key, fallback)
	if value is Color:
		return value
	if value is String:
		return Color.from_string(value, fallback)
	return fallback
