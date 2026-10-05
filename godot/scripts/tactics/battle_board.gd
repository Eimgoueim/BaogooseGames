extends Control

signal cell_clicked(cell: Vector2i)
signal cell_hovered(cell: Vector2i)

const BOARD_SIZE := Vector2i(24, 24)
const TILE_SIZE := 40.0
const ZOOM_MIN := 0.65
const ZOOM_MAX := 1.8

var battle: RefCounted
var art: Dictionary = {}
var catalog: Dictionary = {}
var selected_id: int = -1
var reachable: Dictionary = {}
var preview_path: Array[Vector2i] = []
var deployment_cells: Dictionary = {}

var _zoom := 1.0
var _camera_center := Vector2(480.0, 480.0)
var _dragging := false
var _drag_last := Vector2.ZERO
var _touch_index := -1
var _touch_start := Vector2.ZERO
var _touch_last := Vector2.ZERO
var _touch_moved := false

const TERRAIN_COLORS := {
	"ground": Color("#c9d8b7"), "road": Color("#e4d2a5"),
	"wall": Color("#827b72"), "water": Color("#8fc8d0"),
	"brush": Color("#a8c995")
}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(_on_resized)
	mouse_exited.connect(func() -> void: cell_hovered.emit(Vector2i(-1, -1)))
	fit_board()

func fit_board() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_zoom = minf(size.x / (BOARD_SIZE.x * TILE_SIZE), size.y / (BOARD_SIZE.y * TILE_SIZE))
	_camera_center = Vector2(BOARD_SIZE) * TILE_SIZE * 0.5
	_clamp_camera()
	queue_redraw()

func focus_cell(cell: Vector2i) -> void:
	_camera_center = (Vector2(cell) + Vector2(0.5, 0.5)) * TILE_SIZE
	_clamp_camera()
	queue_redraw()

func _on_resized() -> void:
	_clamp_camera()
	queue_redraw()

func _clamp_camera() -> void:
	if size.x <= 0.0 or size.y <= 0.0 or _zoom <= 0.0:
		return
	var half := size / (2.0 * _zoom)
	var extent := Vector2(BOARD_SIZE) * TILE_SIZE
	for axis in 2:
		if half[axis] * 2.0 >= extent[axis]:
			_camera_center[axis] = extent[axis] * 0.5
		else:
			_camera_center[axis] = clampf(_camera_center[axis], half[axis], extent[axis] - half[axis])

func _origin() -> Vector2:
	return size * 0.5 - _camera_center * _zoom

func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(_origin() + Vector2(cell) * TILE_SIZE * _zoom, Vector2.ONE * TILE_SIZE * _zoom)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#252a32"), true)
	if battle == null:
		return
	var tiles: Dictionary = battle.get("tiles")
	var visible: Dictionary = battle.get("visible_cells")
	var explored: Dictionary = battle.get("explored_cells")
	var font := get_theme_default_font()
	var font_size := maxi(14, roundi(14.0 * _zoom))
	var last_seen_cells := _last_seen_cells(explored, visible)
	var regions_value: Variant = battle.get("regions")
	var regions: Array = regions_value if regions_value is Array else []
	var memory_value: Variant = battle.get("region_memory")
	var region_memory: Dictionary = memory_value if memory_value is Dictionary else {}
	var origin := _origin()
	var first_x := maxi(0, floori((-origin.x) / (TILE_SIZE * _zoom)))
	var first_y := maxi(0, floori((-origin.y) / (TILE_SIZE * _zoom)))
	var last_x := mini(BOARD_SIZE.x - 1, ceili((size.x - origin.x) / (TILE_SIZE * _zoom)))
	var last_y := mini(BOARD_SIZE.y - 1, ceili((size.y - origin.y) / (TILE_SIZE * _zoom)))
	for y in range(first_y, last_y + 1):
		for x in range(first_x, last_x + 1):
			var cell := Vector2i(x, y)
			var rect := _cell_rect(cell)
			if not explored.has(cell):
				draw_rect(rect, Color("#333943"), true)
			else:
				var ground: String = str(tiles.get(cell, "ground"))
				draw_rect(rect, TERRAIN_COLORS.get(ground, TERRAIN_COLORS.ground), true)
				if ground == "brush":
					draw_circle(rect.position + rect.size * Vector2(0.28, 0.34), rect.size.x * 0.08, Color("#7fae70", 0.5))
					draw_circle(rect.position + rect.size * Vector2(0.72, 0.7), rect.size.x * 0.1, Color("#7fae70", 0.42))
				elif ground == "water":
					draw_line(rect.position + rect.size * Vector2(0.15, 0.35), rect.position + rect.size * Vector2(0.85, 0.35), Color("#d6f1e9", 0.55), maxf(1.0, _zoom * 2.0))
				elif ground == "wall":
					draw_rect(Rect2(rect.position + rect.size * 0.12, rect.size * 0.76), Color("#a39b89"), true)
			var region_state := _region_memory_for_cell(cell, regions, region_memory)
			if not region_state.is_empty():
				draw_rect(rect, _region_tint(region_state), true)
			if explored.has(cell) and not visible.has(cell):
				draw_rect(rect, Color("#344050", 0.48), true)
			if last_seen_cells.has(cell):
				draw_circle(rect.get_center(), rect.size.x * 0.16, Color("#5c4c4a", 0.55))
				draw_string(font, rect.position + Vector2(rect.size.x * 0.36, rect.size.y * 0.7), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#f1d7c0", 0.78))
			if reachable.has(cell):
				draw_rect(rect, Color(0.25, 0.58, 0.95, 0.38 if explored.has(cell) else 0.15), true)
			if deployment_cells.has(cell):
				draw_rect(rect, Color(0.20, 0.8, 0.45, 0.32), true)
			if cell in preview_path:
				draw_rect(rect.grow(-rect.size.x * 0.34), Color(0.3, 0.68, 1.0, 0.85), true)
			draw_rect(rect, Color(0.18, 0.22, 0.2, 0.3), false, maxf(1.0, _zoom))
			if battle.has_method("unit_at"):
				var unit: Dictionary = battle.call("unit_at", cell)
				if not unit.is_empty() and int(unit.get("hp", 0)) > 0:
					var side := str(unit.get("side", ""))
					if side == "ally" or visible.has(cell):
						_draw_unit(unit, rect, font, font_size)
	_draw_regions(regions, region_memory, font, font_size)
	if selected_id >= 0:
		for unit in battle.get("units"):
			if int(unit.get("id", -2)) == selected_id and str(unit.get("kind", "pet")) == "pet":
				var selected_cell: Vector2i = unit.get("cell", Vector2i(-1, -1))
				if explored.has(selected_cell):
					draw_rect(_cell_rect(selected_cell).grow(-_zoom * 2.0), Color("#fff2a6"), false, maxf(2.0, _zoom * 3.0))
				break

func _region_memory_for_cell(cell: Vector2i, regions: Array, memory: Dictionary) -> Dictionary:
	for region in regions:
		var area: Rect2i = region.get("rect", Rect2i())
		if area.has_point(cell):
			var record: Variant = memory.get(int(region.get("id", -1)), {})
			return record if record is Dictionary else {"owner": "neutral", "contested": false}
	return {}

func _region_tint(memory: Dictionary) -> Color:
	if bool(memory.get("contested", false)):
		return Color(0.95, 0.77, 0.22, 0.12)
	match str(memory.get("owner", "neutral")):
		"ally": return Color(0.22, 0.72, 0.43, 0.13)
		"enemy": return Color(0.82, 0.29, 0.34, 0.13)
		_: return Color(0.52, 0.55, 0.59, 0.07)

func _draw_regions(regions: Array, memory: Dictionary, font: Font, font_size: int) -> void:
	for index in regions.size():
		var region: Dictionary = regions[index]
		var area: Rect2i = region.get("rect", Rect2i())
		var screen_rect := Rect2(_origin() + Vector2(area.position) * TILE_SIZE * _zoom, Vector2(area.size) * TILE_SIZE * _zoom)
		var record: Variant = memory.get(int(region.get("id", -1)), {})
		var known: Dictionary = record if record is Dictionary else {}
		var tint := _region_tint(known)
		var outline := Color(tint.r, tint.g, tint.b, 0.86)
		if bool(known.get("contested", false)):
			outline = Color("#f1c94d")
		draw_rect(screen_rect, outline, false, maxf(2.0, _zoom * 2.0))
		var title := str(region.get("name", "R%d" % (index + 1)))
		if bool(known.get("contested", false)):
			title += " · 争夺"
		else:
			match str(known.get("owner", "neutral")):
				"ally": title += " · 我方"
				"enemy": title += " · 敌方"
		var label_rect := Rect2(screen_rect.position + Vector2(3.0, 3.0), Vector2(minf(screen_rect.size.x - 6.0, 154.0 * _zoom), maxf(20.0, 19.0 * _zoom)))
		if label_rect.size.x > 0.0 and label_rect.size.y > 0.0:
			draw_rect(label_rect, Color("#222b30", 0.7), true)
			draw_string(font, label_rect.position + Vector2(3.0, label_rect.size.y * 0.78), title, HORIZONTAL_ALIGNMENT_LEFT, label_rect.size.x - 6.0, font_size, Color("#f3f0df"))

func _draw_unit(unit: Dictionary, rect: Rect2, font: Font, font_size: int) -> void:
	var kind := str(unit.get("kind", "pet"))
	var inset := rect.size.x * (0.22 if kind == "soldier" else 0.13)
	var token := Rect2(rect.position + Vector2(inset, inset), rect.size - Vector2.ONE * inset * 2.0)
	var side := str(unit.get("side", "ally"))
	if kind == "soldier":
		var side_color := Color("#c64e5b") if side == "enemy" else Color("#58b681")
		draw_rect(token.grow(rect.size.x * 0.06), side_color, false, maxf(2.0, _zoom * 2.5))
	elif side == "enemy":
		draw_rect(token.grow(rect.size.x * 0.025), Color("#c64e5b"), false, maxf(2.0, _zoom * 2.0))
	var species := "goose" if kind == "soldier" else str(unit.get("species", ""))
	var pets: Dictionary = art.get("pets", {})
	var species_art: Dictionary = pets.get(species, {})
	var stage := 0
	var definition: Dictionary = catalog.get("SPECIES", {}).get(species, {})
	for index in definition.get("stages", []).size():
		if int(unit.get("level", 1)) >= int(definition.stages[index].get("min", 1)): stage = index
	var commands: Array = species_art.get("%d_awake" % stage, species_art.get("0_awake", []))
	if not commands.is_empty():
		var bounds := _command_bounds(commands)
		var scale_factor := minf(token.size.x / maxf(1.0, bounds.size.x), token.size.y / maxf(1.0, bounds.size.y))
		var target_size := bounds.size * scale_factor
		var offset := token.get_center() - target_size * 0.5 - bounds.position * scale_factor
		for command in commands:
			if command.size() < 8:
				continue
			var color := Color(float(command[4]), float(command[5]), float(command[6]), float(command[7]))
			if side == "enemy":
				color = Color(color.r * 0.94, color.g * 0.7, color.b * 0.72, color.a)
			var part := Rect2(offset + Vector2(float(command[0]), float(command[1])) * scale_factor, Vector2(float(command[2]), float(command[3])) * scale_factor)
			draw_rect(part, color, true)
	else:
		draw_circle(token.get_center(), token.size.x * 0.34, Color("#6cae91") if side == "ally" else Color("#cf6570"))
	var hp := maxi(0, int(unit.get("hp", 0)))
	var max_hp := maxi(1, int(unit.get("max_hp", 1)))
	var bar := Rect2(rect.position.x + rect.size.x * 0.13, rect.position.y + rect.size.y * 0.06, rect.size.x * 0.74, maxf(2.0, rect.size.y * 0.065))
	draw_rect(bar, Color("#432f39"), true)
	bar.size.x *= clampf(float(hp) / max_hp, 0.0, 1.0)
	draw_rect(bar, Color("#74c786") if hp * 2 >= max_hp else Color("#e9a46f"), true)
	if kind == "pet" and _zoom >= 0.75:
		var unit_name := str(unit.get("name", species))
		var name_limit := 2 if unit_name.to_utf8_buffer().size() > unit_name.length() else 4
		if unit_name.length() > name_limit:
			unit_name = unit_name.substr(0, name_limit)
		draw_string(font, Vector2(rect.position.x, rect.end.y - rect.size.y * 0.08), unit_name, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, Color("#26303b"))
	if kind == "soldier":
		var badge_color := Color("#c64e5b") if side == "enemy" else Color("#399568")
		var badge_size := maxf(18.0, rect.size.x * 0.4) if rect.size.x >= 24 else rect.size.x * 0.32
		var badge := Rect2(rect.end - Vector2.ONE * (badge_size + rect.size.x * 0.04), Vector2.ONE * badge_size)
		draw_rect(badge, badge_color, true)
		if rect.size.x >= 24:
			draw_string(font, badge.position + Vector2(0.0, badge.size.y * 0.82), "兵", HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, maxi(14, roundi(14.0 * _zoom)), Color.WHITE)

func _command_bounds(commands: Array) -> Rect2:
	var left := INF
	var top := INF
	var right := -INF
	var bottom := -INF
	for command in commands:
		if command.size() < 4:
			continue
		left = minf(left, float(command[0]))
		top = minf(top, float(command[1]))
		right = maxf(right, float(command[0]) + float(command[2]))
		bottom = maxf(bottom, float(command[1]) + float(command[3]))
	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top)) if is_finite(left) else Rect2(0, 0, 1, 1)

func _last_seen_cells(explored: Dictionary, visible: Dictionary) -> Dictionary:
	var cells: Dictionary = {}
	var memories: Variant = battle.get("last_seen_enemies")
	if memories is Dictionary:
		for cell_value in memories:
			var record: Variant = memories[cell_value]
			if record is Dictionary:
				_add_last_seen_cell(cells, record, visible, explored)
	elif memories is Array:
		for record in memories:
			if record is Dictionary:
				_add_last_seen_cell(cells, record, visible, explored)
	return cells

func _add_last_seen_cell(cells: Dictionary, record: Dictionary, visible: Dictionary, explored: Dictionary) -> void:
	var cell_value: Variant = record.get("cell", Vector2i(-1, -1))
	if not cell_value is Vector2i:
		return
	var cell: Vector2i = cell_value
	if not explored.has(cell) or visible.has(cell):
		return
	cells[cell] = true

func _cell_at_position(position: Vector2) -> Vector2i:
	var local := (position - _origin()) / (TILE_SIZE * _zoom)
	var cell := Vector2i(floori(local.x), floori(local.y))
	if cell.x < 0 or cell.y < 0 or cell.x >= BOARD_SIZE.x or cell.y >= BOARD_SIZE.y:
		return Vector2i(-1, -1)
	return cell

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				var before := _camera_center + (button.position - size * 0.5) / _zoom
				var minimum := minf(ZOOM_MIN, minf(size.x, size.y) / (BOARD_SIZE.x * TILE_SIZE))
				_zoom = clampf(_zoom * (1.12 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12), minimum, ZOOM_MAX)
				_camera_center = before - (button.position - size * 0.5) / _zoom
				_clamp_camera()
				queue_redraw()
			accept_event()
		elif button.button_index == MOUSE_BUTTON_MIDDLE or button.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = button.pressed
			_drag_last = button.position
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			var cell := _cell_at_position(button.position)
			if cell.x >= 0 and cell.y >= 0:
				cell_clicked.emit(cell)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_camera_center -= motion.relative / _zoom
		_drag_last = motion.position
		_clamp_camera()
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion:
		cell_hovered.emit(_cell_at_position((event as InputEventMouseMotion).position))
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			if _touch_index < 0:
				_touch_index = touch.index
				_touch_start = touch.position
				_touch_last = touch.position
				_touch_moved = false
		else:
			if touch.index == _touch_index:
				if not _touch_moved and _touch_start.distance_to(touch.position) < 8.0:
					var cell := _cell_at_position(touch.position)
					if cell.x >= 0 and cell.y >= 0:
						cell_clicked.emit(cell)
				_touch_index = -1
				accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_index:
			if _touch_start.distance_to(drag.position) >= 8.0:
				_touch_moved = true
				_camera_center -= drag.relative / _zoom
				_clamp_camera()
				queue_redraw()
			_touch_last = drag.position
			accept_event()
