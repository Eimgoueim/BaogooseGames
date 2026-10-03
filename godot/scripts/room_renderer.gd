class_name RoomRenderer
extends RefCounted

# 原版 pxResize / pxRoom / pxDraw 的原生实现。基础像素画仍来自原绘制指令。
var commands: Array = []
var layout: Dictionary = {}
var catalog: Dictionary
var art: Dictionary
var state: Dictionary
var visual: Dictionary
var time := 0.0

static func js_round(value: float) -> int:
	return int(floor(value + 0.5))

static func geometry(screen: Vector2) -> Dictionary:
	var vw := maxf(320.0, screen.x)
	var vh := maxf(300.0, screen.y)
	var aw := 180
	var ah := js_round(aw * vh / vw)
	if ah < 108:
		ah = 108
		aw = js_round(ah * vw / vh)
	if ah > 260:
		ah = 260
		aw = js_round(ah * vw / vh)
	var width := clampi(aw, 120, 360)
	var height := clampi(ah, 104, 260)
	var bottom := height - 14 - js_round(30.0 / (vh / height))
	var ground := clampf(0.8 - 150.0 / vh, 0.3, 0.8)
	var ground_end := maxf(ground + 0.02, minf((bottom - 3.0) / height, ground + 200.0 / vh))
	return {"width": width, "height": height, "wall": js_round(height * 0.52), "bottom": bottom,
		"ground": ground, "ground_end": ground_end, "top_ui": js_round(17.0 / height * vh) + js_round(vh * 0.012)}

static func color(value: String) -> Color:
	if value.begins_with("rgba"):
		var numbers := value.trim_prefix("rgba(").trim_suffix(")").split(",")
		return Color(float(numbers[0]) / 255.0, float(numbers[1]) / 255.0, float(numbers[2]) / 255.0, float(numbers[3]))
	return Color.from_string(value, Color.WHITE)

static func quantize(value: Color) -> Color:
	return Color(clampf(js_round(value.r * 255.0), 0, 255) / 255.0, clampf(js_round(value.g * 255.0), 0, 255) / 255.0, clampf(js_round(value.b * 255.0), 0, 255) / 255.0, value.a)

static func mix(a: Color, b: Color, factor: float) -> Color:
	return quantize(a.lerp(b, factor))

static func shade(a: Color, factor: float) -> Color:
	return quantize(Color(a.r * factor, a.g * factor, a.b * factor, a.a))

static func shift_hue(value: Color, degrees: float) -> Color:
	# 与原 hexToHsl/shiftHue 相同的 HSL 调整，不能使用 HSV 代替。
	var high := maxf(value.r, maxf(value.g, value.b))
	var low := minf(value.r, minf(value.g, value.b))
	var light := (high + low) / 2.0
	var hue := 0.0
	var saturation := 0.0
	if high != low:
		var delta := high - low
		saturation = delta / (2.0 - high - low) if light > 0.5 else delta / (high + low)
		if high == value.r:
			hue = (value.g - value.b) / delta + (6.0 if value.g < value.b else 0.0)
		elif high == value.g:
			hue = (value.b - value.r) / delta + 2.0
		else:
			hue = (value.r - value.g) / delta + 4.0
		hue *= 60.0
	hue = fposmod(hue + degrees, 360.0)
	saturation = minf(1.0, saturation * 1.05)
	light = minf(0.84, light * 1.18)
	var chroma := (1.0 - absf(2.0 * light - 1.0)) * saturation
	var second := chroma * (1.0 - absf(fposmod(hue / 60.0, 2.0) - 1.0))
	var offset := light - chroma / 2.0
	var base: Color
	if hue < 60: base = Color(chroma, second, 0)
	elif hue < 120: base = Color(second, chroma, 0)
	elif hue < 180: base = Color(0, chroma, second)
	elif hue < 240: base = Color(0, second, chroma)
	elif hue < 300: base = Color(second, 0, chroma)
	else: base = Color(chroma, 0, second)
	return quantize(Color(base.r + offset, base.g + offset, base.b + offset))

static func theme_vars(current: Dictionary, data: Dictionary) -> Dictionary:
	var theme: Dictionary = data.THEMES.get(current.get("theme", "sakura"), data.THEMES.sakura)
	var vars: Dictionary = theme.vars.duplicate(true)
	var accent := str(current.get("accent", ""))
	if accent.length() == 7 and accent.begins_with("#") and Color.html_is_valid(accent):
		vars["--accent"] = accent
		vars["--purple"] = accent
		vars["--ds"] = accent
		vars["--pink"] = "#" + shift_hue(color(accent), 38).to_html(false)
		vars["--ds2"] = "#" + shift_hue(color(accent), 24).to_html(false)
	return vars

func fill(x: float, y: float, width: float, height: float, c: Color) -> void:
	var w := js_round(width)
	var h := js_round(height)
	if w > 0 and h > 0:
		commands.append([js_round(x), js_round(y), w, h, c.r, c.g, c.b, c.a])

func ellipse(cx: float, cy: float, width: float, height: float, c: Color) -> void:
	var a := width / 2.0
	var b := height / 2.0
	for dy in range(-int(floor(b)), int(floor(b)) + 1):
		var fraction := 1.0 - dy * dy / (b * b)
		if fraction <= 0: continue
		var half_width := js_round(a * sqrt(fraction))
		fill(cx - half_width, cy + dy, half_width * 2 + 1, 1, c)

func room(night: bool) -> void:
	var vars := theme_vars(state, catalog)
	var soft := color(vars.get("--soft", "#faf9ff"))
	var card := color(vars.get("--card", "#ffffff"))
	var btn := color(vars.get("--btn", "#f4f2fd"))
	var accent := color(vars.get("--purple", "#8b7bff"))
	var pink := color(vars.get("--pink", "#ff8fb1"))
	var warm := color(vars.get("--warm", "#ffb37a"))
	var floor_base := mix(mix(soft, warm, 0.42), accent, 0.12)
	var c := {"wall": shade(card, 0.28) if night else soft, "wallDot": shade(card, 0.36) if night else shade(soft, 0.94),
		"floor": mix(shade(btn, 0.24), warm, 0.10) if night else floor_base,
		"floorLine": shade(btn, 0.32) if night else shade(floor_base, 0.86),
		"band": mix(shade(card, 0.44), warm, 0.18) if night else mix(soft, warm, 0.34),
		"frame": shade(card, 0.52) if night else mix(btn, accent, 0.22),
		"sky": color("#27406e" if night else "#bfe3ff"), "skyDeep": color("#1b2c50" if night else "#a8d6ff"),
		"rug": mix(shade(pink, 0.42), warm, 0.22) if night else mix(mix(pink, Color.WHITE, 0.30), warm, 0.24),
		"warmSoft": mix(warm, Color.WHITE, 0.42), "lamp": shade(warm, 1.02), "lampGlow": mix(warm, color("#ffd9a8"), 0.35)}
	c.lampGlow.a = 0.20
	var w: int = layout.width
	var h: int = layout.height
	var wall: int = layout.wall
	fill(0, 0, w, h, c.wall)
	for x in range(0, w, 8): fill(x, 0, 2, wall, c.wallDot)
	var ww := maxi(30, js_round(w * 0.17))
	var wh := maxi(22, js_round(wall * 0.56))
	var wx := w - ww - js_round(w * 0.05)
	var wy := js_round(wall * 0.13)
	fill(wx - 2, wy - 2, ww + 4, wh + 4, c.frame)
	fill(wx, wy, ww, wh, c.sky)
	fill(wx, wy, ww, js_round(wh * 0.42), c.skyDeep)
	for puff: Array in [[0, 0.30, 14, 3.2], [0.45, 0.56, 19, 2.1], [0.78, 0.20, 11, 4.0]]:
		var cloud_width: float = puff[2]
		var travel := ww + cloud_width + 8
		var cx: float = wx - cloud_width - 4 + fposmod(puff[0] * travel + time * puff[3], travel)
		var cy: float = wy + js_round(wh * puff[1])
		for piece: Array in [[0, 2, cloud_width - 4, 4], [3, 0, cloud_width - 10, 4], [-3, 4, cloud_width - 2, 3], [1, 6, cloud_width - 12, 2]]:
			var x0 := js_round(cx + piece[0])
			var y0 := js_round(cy + piece[1])
			var x1 := mini(x0 + js_round(piece[2]), wx + ww)
			var y1 := mini(y0 + js_round(piece[3]), wy + wh)
			x0 = maxi(x0, wx)
			y0 = maxi(y0, wy)
			fill(x0, y0, x1 - x0, y1 - y0, Color(1, 1, 1, 0.92))
	if night:
		fill(wx + ww - 12, wy + 5, 7, 7, color("#ffe9a8"))
		fill(wx + ww - 15, wy + 9, 12, 2, color("#ffe9a8"))
		fill(0, wall - 34, w, 34, Color(1, 220.0 / 255, 140.0 / 255, 0.05))
	else:
		fill(wx + js_round(ww * 0.55), wy + wh - 6, 13, 3, mix(color(vars.get("--mint", "#4fc9a8")), Color.WHITE, 0.3))
	fill(wx + js_round(ww / 2.0), wy, 2, wh, c.frame)
	fill(wx, wy + js_round(wh / 2.0), ww, 2, c.frame)
	fill(0, wall, w, h - wall, c.floor)
	for y in range(wall + 7, h, 9): fill(0, y, w, 1, c.floorLine)
	for x in range(0, w, 26): fill(x, wall, 1, h - wall, c.floorLine)
	fill(0, wall - 3, w, 3, c.band)
	var lamp_x := js_round(w * 0.095)
	var base := wall + 5
	ellipse(lamp_x, base + 3, 36, 10, c.lampGlow)
	fill(lamp_x - 5, base + 1, 11, 2, shade(c.lamp, 0.55))
	fill(lamp_x, base - 13, 1, 14, shade(c.lamp, 0.72))
	fill(lamp_x - 5, base - 20, 11, 3, c.lamp)
	fill(lamp_x - 4, base - 17, 9, 4, c.warmSoft)
	fill(lamp_x - 1, base - 23, 3, 1, shade(c.lamp, 1.15))
	fill(lamp_x - 3, base - 16, 7, 2, warm)
	var carpet_x := js_round(w / 2.0)
	var carpet_y := maxi(wall + 19, mini(layout.bottom - 21, js_round((wall + layout.bottom) / 2.0)))
	ellipse(carpet_x, carpet_y, 100, 35, Color.WHITE)
	ellipse(carpet_x, carpet_y, 88, 26, c.rug)
	for i in 16:
		var angle := i / 16.0 * TAU
		fill(js_round(carpet_x + cos(angle) * 46) - 1, js_round(carpet_y + sin(angle) * 14.5) - 1, 2, 2, Color.WHITE)
	ellipse(carpet_x, carpet_y, 74, 18, mix(c.rug, Color.WHITE, 0.22))

func append_art(recipe: Array, at: Vector2, scale_factor: float = 1.0, flip: bool = false, rounded: bool = false, ink: Color = Color.TRANSPARENT) -> void:
	for raw: Array in recipe:
		var x: float = at.x + (-raw[0] - raw[2] if flip else raw[0]) * scale_factor
		var y: float = at.y + raw[1] * scale_factor
		var c := Color(float(raw[4]), float(raw[5]), float(raw[6]), float(raw[7]))
		if ink.a > 0 and absf(c.r - 220.0 / 255.0) < 0.001 and absf(c.g - 232.0 / 255.0) < 0.001:
			c = ink
		if rounded:
			fill(x, y, raw[2] * scale_factor, raw[3] * scale_factor, c)
		else:
			commands.append([x, y, raw[2] * scale_factor, raw[3] * scale_factor, c.r, c.g, c.b, c.a])

func pet_at(pet: Dictionary) -> Vector2:
	var x := clampf(float(pet.get("lx", 0.5)), 0.08, 0.92)
	var y := clampf(float(pet.get("ly", 0.8)), 0.14, layout.ground_end)
	return Vector2(js_round(x * layout.width), js_round(y * layout.height))

func stage(pet: Dictionary) -> int:
	var index := 0
	var stages: Array = catalog.SPECIES[pet.species].stages
	for i in stages.size():
		if float(pet.get("level", 1)) >= float(stages[i].min): index = i
	return index

func pet(p: Dictionary, at: Vector2) -> void:
	var key: String = p.species
	var sleeping: bool = p.get("asleep", false)
	var annoyed: bool = float(visual.get("annoy", 0)) > 0 and not sleeping
	var pose := "sleep" if sleeping else ("annoy" if annoyed else str(visual.get("face", "awake")))
	if pose == "ok": pose = "awake"
	var flipped: bool = float(visual.get("dir", 1)) < 0
	var head := -13 if key == "goose" else (-25 if key in ["dragon", "cat"] else -27)
	var estimate := -13 if key == "goose" else -27
	for accessory: String in p.get("worn", {}).values():
		if art.wear.has(accessory) and catalog.WEAR_BACK.has(accessory):
			append_art(art.wear[accessory], at + Vector2(0, estimate + 27), 1, flipped)
	append_art(art.pets[key][str(stage(p)) + "_" + pose], at, 1, flipped)
	for accessory: String in p.get("worn", {}).values():
		if art.wear.has(accessory) and not catalog.WEAR_BACK.has(accessory):
			append_art(art.wear[accessory], at + Vector2(0, head + 27), 1, flipped)
	if sleeping:
		for bubble: Array in [[10, -5, 3], [14, -11, 4], [19, -18, 5]]:
			var x: float = at.x + bubble[0]
			if flipped: x = at.x - bubble[0] - bubble[2]
			fill(x, at.y + head + bubble[1], bubble[2], bubble[2], color("#cfd9f5"))
	elif pose == "sick":
		for x in [12, 16]: fill(at.x + x, at.y + head - 7, 2, 5, color("#ef5b5b"))
	elif visual.get("face", "") == "happy" and float(visual.get("hop", 0)) > 0.2:
		for x in [-18, 16]: fill(at.x + x, at.y + head - 3, 2, 2, color("#ff8fb1"))
	if annoyed:
		for spike: Array in [[13, -6], [17, -3], [17, -10]]:
			fill(at.x + spike[0], at.y + head + spike[1], 2, 2, color("#ef5b5b"))

func sleeping_pet(p: Dictionary, at: Vector2) -> void:
	var bed: Dictionary = state.get("placed", {}).get("bed", {})
	var has_bed := not bed.is_empty()
	var scale_factor := float(bed.get("s", 1))
	var origin := Vector2(js_round(bed.get("x", 0.5) * layout.width), js_round(bed.get("y", 0.9) * layout.height)) if has_bed else at
	var pet_origin := origin - Vector2(js_round(4 * scale_factor), js_round(4 * scale_factor)) if has_bed else at
	pet(p, pet_origin)
	var width := js_round(22 * scale_factor) if has_bed else 30
	var height := js_round(10 * scale_factor) if has_bed else 13
	var x := js_round(origin.x - width / 2.0)
	var y := pet_origin.y - 8 + js_round(sin(time * 1.5))
	if not has_bed:
		fill(x - 3, y + 3, 7, height - 3, color("#f2f6fb"))
		fill(x - 3, y + 3, 7, 1, Color.WHITE)
	fill(x, y + height - 3, width, 3, color("#7fa9d8"))
	fill(x, y, width, height, color("#9fc4ee"))
	fill(x, y, width, 2, color("#cfe4fb"))
	fill(x, y, 2, height, color("#cfe4fb"))
	fill(x + width - 2, y, 2, height, color("#cfe4fb"))
	for i in range(4, width - 6, 7):
		fill(x + i, y + 5, 2, 2, Color.WHITE)
		if height > 10: fill(x + i + 3, y + 9, 2, 2, Color.WHITE)
	var zy := pet_origin.y - 24 - js_round(fposmod(time, 2.2) * 3)
	fill(pet_origin.x + 9, zy, 4, 1, color("#cfd9f5"))
	fill(pet_origin.x + 10, zy + 1, 2, 1, color("#cfd9f5"))
	fill(pet_origin.x + 9, zy + 2, 4, 1, color("#cfd9f5"))

func menu_rects() -> Array:
	var result: Array = []
	for row: String in ["top", "bottom"]:
		var list: Array = catalog.MENU.filter(func(item: Dictionary) -> bool: return item.row == row)
		var width := clampi(int(floor((layout.width - 10.0 - (list.size() - 1) * 2) / list.size())), 7, 13)
		var start := js_round((layout.width - list.size() * width - (list.size() - 1) * 2) / 2.0)
		for i in list.size():
			result.append({"key": list[i].key, "name": list[i].name, "row": row, "x": start + i * (width + 2), "y": (3 if row == "top" else layout.bottom) + 1, "w": width, "h": 11})
	return result

func menu_disabled(key: String, p: Dictionary) -> bool:
	var asleep: bool = p.get("asleep", false)
	var inventory_count := 0
	for quantity: Variant in state.get("inv", {}).values(): inventory_count += maxi(0, int(quantity))
	match key:
		"feed": return asleep or inventory_count == 0
		"play": return asleep or float(p.get("energy", 0)) < 10
		"bath": return asleep or (float(p.get("clean", 0)) >= 98 and state.get("poops", []).is_empty() and not (float(p.get("poopNext", 0)) > 0 and Time.get_unix_time_from_system() * 1000 > float(p.poopNext) - 9000))
		"work": return asleep or float(state.get("workReady", 0)) > float(visual.get("now", Time.get_unix_time_from_system() * 1000)) or float(p.get("energy", 0)) < 20
		"games": return asleep
	return false

func build(current: Dictionary, data: Dictionary, drawings: Dictionary, screen: Vector2, seconds: float = 0, effects: Dictionary = {}) -> Array:
	state = current
	catalog = data
	art = drawings
	time = seconds
	visual = effects
	commands = []
	layout = geometry(screen)
	var p: Dictionary = state.pets[clampi(int(state.get("active", 0)), 0, state.pets.size() - 1)] if not state.pets.is_empty() else {}
	room(p.get("asleep", false))
	var placed: Dictionary = state.get("placed", {})
	var keys: Array = placed.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return float(placed[a].get("y", 0)) < float(placed[b].get("y", 0)))
	for key: String in keys:
		if not art.furniture.has(key): continue
		var q: Dictionary = placed[key]
		var x := clampf(float(q.get("x", 0.5)), 0.06, 0.94)
		var y := clampf(float(q.get("y", 0.85)), 0.30, maxf(0.36, (layout.bottom - 8.0) / layout.height))
		var at := Vector2(js_round(x * layout.width), js_round(y * layout.height))
		var scale_factor := clampf(float(q.get("s", 1)), 0.5, 2)
		if state.get("edit", false) and state.get("sel", "") == key: fill(at.x - 1, 0, 1, layout.height, Color(139.0 / 255, 123.0 / 255, 1, 0.35))
		append_art(art.furniture[key], at, scale_factor, false, true)
		if state.get("edit", false) and state.get("sel", "") == key:
			furniture_buttons(key, at, scale_factor)
	for poop: Dictionary in state.get("poops", []): append_art(art.effects.poop, pet_at(poop))
	if not p.is_empty():
		var at := pet_at(p)
		at.y -= js_round(float(visual.get("hop", 0)) * 7)
		if visual.get("bob", false) and not p.get("asleep", false): at.y -= 1
		if p.get("poopWarn", false) and not p.get("asleep", false): at.y -= int(js_round(time * 26)) % 2
		if float(visual.get("bath", 0)) > 0:
			append_art(art.effects.bath_back, at + Vector2(0, 1))
			append_art(art.pets[p.species][str(stage(p)) + "_happy"], at + Vector2(0, 3 + js_round(sin(time * 4))))
			append_art(art.effects.bath_front, at + Vector2(0, 1))
			for bubble: Dictionary in visual.get("bath_bubbles", []):
				fill(bubble.x - bubble.r, bubble.y - bubble.r, bubble.r * 2, bubble.r * 2, color("#eef8ff"))
				fill(bubble.x - bubble.r, bubble.y - bubble.r, 1, 1, Color.WHITE)
		elif p.get("asleep", false): sleeping_pet(p, at)
		else: pet(p, at)
	for heart: Dictionary in visual.get("hearts", []):
		if heart.t > 0: continue
		var ink := color("#ef5b8d"); ink.a = clampf(heart.life, 0, 1)
		fill(heart.x, heart.y, 2, 2, ink); fill(heart.x + 4, heart.y, 2, 2, ink)
		fill(heart.x, heart.y + 2, 6, 2, ink); fill(heart.x + 2, heart.y + 4, 2, 2, ink)
	if state.get("decor", false) and state.get("memoUnlocked", false):
		fill(10, 12, 2, 6, color("#ffd97a"))
		fill(8, 14, 6, 2, color("#ffd97a"))
	fill(0, 2, layout.width, 14, Color(46.0 / 255, 58.0 / 255, 36.0 / 255, 0.88))
	fill(0, 2, layout.width, 1, Color(1, 1, 1, 0.18))
	fill(0, layout.bottom - 1, layout.width, layout.height - layout.bottom + 1, Color(46.0 / 255, 58.0 / 255, 36.0 / 255, 0.88))
	fill(0, layout.bottom - 1, layout.width, 1, Color(1, 1, 1, 0.18))
	for icon: Dictionary in menu_rects():
		var on: bool = str(visual.get("hover", "")) == icon.key
		if on: fill(icon.x - 1, icon.y - 1, icon.w + 2, icon.h + 2, Color(246.0 / 255, 1, 228.0 / 255, 0.22))
		var ink := Color(220.0 / 255, 232.0 / 255, 196.0 / 255, 0.34) if menu_disabled(icon.key, p) else (color("#f6ffe4") if on else color("#dCE8C4"))
		append_art(art.icons[icon.key], Vector2(icon.x + js_round((icon.w - 11) / 2.0), icon.y), 1, false, true, ink)
	return commands

func furniture_buttons(key: String, at: Vector2, scale_factor: float) -> void:
	var w: float = catalog.PLACE[key].w * scale_factor
	var h: float = catalog.PLACE[key].h * scale_factor
	var x := clampi(js_round(at.x + w / 2 + 3), 2, layout.width - 24)
	var y := clampi(js_round(at.y - h - 3), 20, layout.bottom - 14)
	var x0 := at.x - w / 2
	var y0 := at.y - h
	fill(x0, y0, w, 1, color("#8b7bff"))
	fill(x0, y0 + h - 1, w, 1, color("#8b7bff"))
	fill(x0, y0, 1, h, color("#8b7bff"))
	fill(x0 + w - 1, y0, 1, h, color("#8b7bff"))
	for offset in [0, 12]:
		fill(x + offset - 1, y - 1, 11, 11, Color(12.0 / 255, 9.0 / 255, 26.0 / 255, 0.5))
		fill(x + offset, y, 9, 9, color("#4fc9a8" if offset == 0 else "#ff6b6b"))
	for point: Array in [[1,4], [3,6], [5,3], [6,1]]: fill(x + point[0], y + point[1], 2, 2, Color.WHITE)
	for point: Array in [[1,1], [6,6], [6,1], [1,6]]: fill(x + 12 + point[0], y + point[1], 2, 2, Color.WHITE)
