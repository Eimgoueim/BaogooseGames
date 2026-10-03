extends Control

signal gameplay_action_requested(action: String)

const Catalog = preload("res://scripts/legacy_catalog.gd")
const Renderer = preload("res://scripts/room_renderer.gd")
const Canvas = preload("res://scripts/legacy_canvas.gd")
const Codec = preload("res://scripts/state_codec.gd")
const Repository = preload("res://scripts/save_repository.gd")
const Hud = preload("res://scripts/ui/legacy_hud.gd")
const Pages = preload("res://scripts/ui/legacy_pages.gd")
const Modals = preload("res://scripts/ui/legacy_modals.gd")
const Style = preload("res://scripts/ui/legacy_ui_style.gd")

var state: Dictionary = {}
var catalog: Dictionary = {}
var art: Dictionary = {}
var page_key := ""
var modal_key := ""
var preview_mode := false
var hud: Control
var pages: Control
var modals: Control
var renderer := Renderer.new()
var repository := Repository.new()
var pixel_viewport: SubViewport
var canvas: Control
var clock := 0.0
var visual := {"face": "ok", "dir": 1, "annoy": 0.0, "hover": "", "bob": false}
var drag: Dictionary = {}
var fall_speed := 0.0
var falling := false
var walk_wait := 0.0
var walk_target := Vector2(0.5, 0.8)
var dialog_action := ""
var hint: Label
var music_button: Button
var toast_layer: VBoxContainer
var download_dialog: FileDialog

func _ready() -> void:
	catalog = Catalog.load_catalog()
	art = Catalog.read_json("res://data/art.json")
	repository.path = "user://godot-ui/save.json"
	for argument in OS.get_cmdline_user_args():
		if argument == "--preview" or argument.begins_with("--save="): preview_mode = true
	state = hydrate(catalog.default_state)
	if not preview_mode and (FileAccess.file_exists(repository.path) or FileAccess.file_exists(repository.path + ".bak")):
		var result: Dictionary = repository.load_save()
		if result.ok: state = hydrate(result.state)
		else:
			push_warning(result.error)
			# 无可恢复存档时以只读模式查看，避免默认状态覆盖坏档。
			preview_mode = true
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--save="):
			var path := argument.trim_prefix("--save=")
			var imported: Dictionary = Codec.normalize(JSON.parse_string(FileAccess.get_file_as_string(path)))
			if not imported.ok:
				push_error(imported.error)
				get_tree().quit(1)
				return
			state = hydrate(imported.state)
			# 从旧版加载只作为预览，不自动写入或覆盖玩家文件。
			preview_mode = true
	create_room()
	hud = Hud.new()
	pages = Pages.new()
	modals = Modals.new()
	for control: Control in [hud, pages, modals]:
		add_child(control)
		control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		control.action_requested.connect(handle)
	modals.save_import_requested.connect(import_save)
	toast_layer = VBoxContainer.new()
	toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_layer)
	resized.connect(refresh_ui)
	refresh_ui()
	if not preview_mode and not state.get("picked", false): handle("adoptopen")
	print("Godot 原生界面已启动；养成循环、抽卡结算、地牢与音频仍待迁移。")

func hydrate(raw: Dictionary) -> Dictionary:
	var result: Dictionary = catalog.default_state.duplicate(true)
	result.merge(raw.duplicate(true), true)
	if not catalog.THEMES.has(result.theme): result.theme = "sakura"
	for index in result.pets.size():
		var pet_record: Dictionary = result.pets[index]
		var base: Dictionary = catalog.default_state.pets[0].duplicate(true)
		if catalog.SPECIES.has(pet_record.get("species", "")):
			base.merge(catalog.SPECIES[pet_record.species].base, true)
		base.merge(pet_record, true)
		# 旧存档也可能使用 128×112 的像素坐标。
		var layout := Renderer.geometry(size)
		var lx := float(base.get("lx", 0.5))
		var ly := float(base.get("ly", layout.ground))
		base.lx = clampf(lx / 128.0 if lx > 1.5 else lx, 0.08, 0.92)
		base.ly = clampf(ly / 112.0 if ly > 1.5 else ly, layout.ground, layout.ground_end)
		result.pets[index] = base
	result.edit = false
	result.sel = ""
	return result

func create_room() -> void:
	pixel_viewport = SubViewport.new()
	pixel_viewport.disable_3d = true
	pixel_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(pixel_viewport)
	canvas = Canvas.new()
	pixel_viewport.add_child(canvas)
	var presentation := TextureRect.new()
	presentation.texture = pixel_viewport.get_texture()
	presentation.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	presentation.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	presentation.stretch_mode = TextureRect.STRETCH_SCALE
	presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(presentation)
	presentation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var lcd := ColorRect.new()
	lcd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/lcd_overlay.gdshader")
	lcd.material = material
	add_child(lcd)
	lcd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint = Style.label("拖动宠物陪它玩 · 点房间抚摸 · 点上下图标用功能", 10, Color.WHITE)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	music_button = Style.button("🎵", "bgm", handle, Renderer.theme_vars(state, catalog))
	music_button.custom_minimum_size = Vector2(30, 30)
	add_child(music_button)
	download_dialog = FileDialog.new()
	download_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	download_dialog.access = FileDialog.ACCESS_FILESYSTEM
	download_dialog.filters = PackedStringArray(["*.json ; JSON"])
	download_dialog.file_selected.connect(func(path: String) -> void:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			toast("⚠️ 导出失败：" + error_string(FileAccess.get_open_error()))
			return
		file.store_string(modals.get_save_text() if not modals.get_save_text().is_empty() else JSON.stringify(state))
		file.close())
	add_child(download_dialog)

func active_pet() -> Dictionary:
	if state.get("pets", []).is_empty(): return {}
	return state.pets[clampi(int(state.get("active", 0)), 0, state.pets.size() - 1)]

func redraw_room() -> void:
	if canvas == null: return
	var p := active_pet()
	visual.face = "sick" if float(p.get("health", 100)) <= 0 else ("happy" if float(p.get("health", 100)) >= 25 and float(p.get("mood", 0)) >= 75 else "awake")
	canvas.commands = renderer.build(state, catalog, art, size, clock, visual)
	pixel_viewport.size = Vector2i(renderer.layout.width, renderer.layout.height)
	canvas.queue_redraw()

func refresh_ui() -> void:
	if hud == null: return
	redraw_room()
	var vars := Renderer.theme_vars(state, catalog)
	var ui_catalog: Dictionary = catalog.duplicate(false)
	ui_catalog.THEMES = catalog.THEMES.duplicate(true)
	ui_catalog.THEMES[state.theme].vars = vars
	hud.refresh(state, ui_catalog, art, float(renderer.layout.top_ui))
	if not page_key.is_empty(): pages.show_page(page_key, state, ui_catalog, art, float(renderer.layout.top_ui))
	else: pages.close_page()
	pages.refresh_usebar(page_key, not page_key.is_empty() or not modal_key.is_empty(), state, ui_catalog, vars)
	hint.position = Vector2(maxf(0, (size.x - hint.size.x) / 2), size.y - 89)
	music_button.position = Vector2(10, size.y - 134)
	if toast_layer != null:
		toast_layer.position = Vector2(size.x / 2 - 260, size.y - 64)
		toast_layer.size.x = 520

func save_state() -> bool:
	if preview_mode: return false
	var error := repository.save_state(state)
	if error != OK: toast("⚠️ 保存失败：" + repository.last_error)
	return error == OK

func toast(text: String) -> void:
	if toast_layer == null: return
	var label := Style.label(text, 13, Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_layer.add_child(label)
	get_tree().create_timer(3.2).timeout.connect(label.queue_free)

func close_panels() -> void:
	if state.get("edit", false):
		state.edit = false
		state.sel = ""
		redraw_room()
		save_state()
	page_key = ""
	modal_key = ""
	pages.close_page()
	modals.close_modal()
	refresh_ui()

func open_modal(key: String) -> void:
	close_panels()
	modal_key = key
	modals.show_modal(key, state, catalog, art)
	refresh_ui()

func handle(action: String) -> void:
	var split := action.split(":", true, 1)
	var key: String = split[0]
	var argument: String = split[1] if split.size() > 1 else ""
	match key:
		"page", "tab":
			var same := page_key == argument
			close_panels()
			if not same: page_key = argument
			refresh_ui()
		"pageclose", "themeclose", "adoptclose", "saveclose", "dlgcancel": close_panels()
		"themeopen":
			if modal_key == "theme": close_panels()
			else: open_modal("theme")
		"savepanel":
			if modal_key == "save": close_panels()
			else: open_modal("save")
		"adopt", "adoptopen":
			if key == "adopt" and modal_key == "adopt": close_panels()
			else: open_modal("adopt")
		"theme":
			if catalog.THEMES.has(argument):
				state.theme = argument
				modals.show_modal("theme", state, catalog, art)
				toast("🎨 已切换到「" + catalog.THEMES[argument].name + "」")
				refresh_ui()
				save_state()
		"accentapply":
			state.accent = modals.get_accent()
			modals.show_modal("theme", state, catalog, art)
			toast("🧡 自定义主色：" + state.accent)
			refresh_ui()
			save_state()
		"accentclear":
			state.accent = ""
			modals.show_modal("theme", state, catalog, art)
			toast("已恢复该风格的默认配色")
			refresh_ui()
			save_state()
		"switch":
			if argument.is_valid_int() and int(argument) >= 0 and int(argument) < state.pets.size():
				state.active = int(argument)
				drag = {}
				falling = false
				visual.dir = 1
				walk_wait = 0.4
				toast("🔁 换成 " + active_pet().name + " 出战")
				refresh_ui()
				save_state()
		"rename":
			if active_pet().is_empty(): return
			close_panels()
			modal_key = "dialog"
			dialog_action = "rename"
			modals.show_dialog({"title": "给「" + active_pet().name + "」改名", "body": "输入 1-8 个字：", "input": true, "value": active_pet().name, "confirmText": "保存"}, Renderer.theme_vars(state, catalog))
			refresh_ui()
		"dlgok":
			if dialog_action == "rename" and not active_pet().is_empty():
				var new_name: String = modals.get_dialog_text().strip_edges().substr(0, 8)
				if new_name.is_empty(): toast("名字不能为空"); return
				active_pet().name = new_name
				toast("以后就叫你「" + new_name + "」啦")
				save_state()
			close_panels()
		"savenow":
			if preview_mode: toast("只读预览：未写入存档")
			elif save_state(): toast("💾 已即时保存")
		"saveexport": modals.set_save_text(JSON.stringify(state))
		"savecopy": DisplayServer.clipboard_set(modals.get_save_text() if not modals.get_save_text().is_empty() else JSON.stringify(state)); toast("📋 存档已复制")
		"savedownload": download_dialog.current_file = "包鹅存档.json"; download_dialog.popup_centered(Vector2i(720, 480))
		"saveimport": import_save(modals.get_save_text())
		"banner":
			for banner: Dictionary in catalog.BANNERS:
				if banner.key == argument: state.banner = argument; refresh_ui(); save_state(); break
		"wear":
			if not catalog.WEAR.has(argument) or not state.wear.get(argument, false) or active_pet().is_empty(): return
			var slot: String = catalog.WEAR[argument].slot
			var worn: Dictionary = active_pet().get("worn", {})
			if worn.get(slot, "") == argument: worn.erase(slot)
			else: worn[slot] = argument
			active_pet().worn = worn
			refresh_ui()
			save_state()
		"edit", "furnedit":
			state.edit = not state.edit if key == "edit" else true
			if not state.edit: state.sel = ""
			refresh_ui()
			save_state()
		"sel": select_furniture(argument)
		"scl": scale_furniture(float(argument))
		"furnback":
			state.placed.erase(argument)
			if state.sel == argument: state.sel = ""
			refresh_ui()
			save_state()
		"useleft", "useright":
			pages.shift_use_page(-1 if key == "useleft" else 1)
			refresh_ui()
		"feed": handle("page:bag")
		_:
			# 经济与养成由下一阶段的领域模块接管，界面只传递原版操作意图。
			gameplay_action_requested.emit(action)
			print("原版操作意图：", action)

func import_save(raw: String) -> void:
	var json := JSON.new()
	if json.parse(raw) != OK:
		toast("⚠️ 导入失败：" + json.get_error_message())
		return
	var result: Dictionary = Codec.normalize(json.data)
	if not result.ok:
		toast("⚠️ 导入失败：" + result.error)
		return
	state = hydrate(result.state)
	close_panels()
	save_state()
	toast("📥 导入成功：" + str(state.pets.size()) + " 只宠物")

func select_furniture(key: String) -> void:
	if not catalog.PLACE.has(key): return
	var item: Dictionary = catalog.PLACE[key]
	var owned: bool = not not (state.furnOwn.get(key, false) if item.kind == "furn" else state.decos.get(item.get("key", key), false))
	if not owned: return
	state.edit = true
	state.sel = key
	if not state.placed.has(key):
		var default_position: Dictionary = item.def
		var q := {"x": float(default_position.x) / 128, "y": float(default_position.y) / 112, "s": float(default_position.get("s", 1))}
		clamp_furniture(q)
		for other: Dictionary in state.placed.values():
			if absf(other.x - q.x) < 0.09 and absf(other.y - q.y) < 0.06:
				q.x = 0.10 if q.x + 0.12 > 0.94 else q.x + 0.12
				break
		state.placed[key] = q
	refresh_ui()
	save_state()

func clamp_furniture(q: Dictionary) -> void:
	q.x = clampf(float(q.get("x", 0.5)), 0.06, 0.94)
	q.y = clampf(float(q.get("y", 0.85)), 0.30, maxf(0.36, (renderer.layout.bottom - 8.0) / renderer.layout.height))
	q.s = clampf(float(q.get("s", 1)), 0.5, 2)

func scale_furniture(amount: float) -> void:
	if state.sel.is_empty() or not state.placed.has(state.sel): return
	var q: Dictionary = state.placed[state.sel]
	q.s = clampf(Renderer.js_round((q.s + amount) * 100) / 100.0, 0.5, 2)
	refresh_ui()
	save_state()

func _process(delta: float) -> void:
	if canvas == null: return
	delta = minf(delta, 0.1)
	clock += delta
	visual.bob = int(floor(clock * 2)) % 2 == 1
	visual.annoy = maxf(0, visual.annoy - delta)
	var p := active_pet()
	if not p.is_empty() and drag.is_empty() and not state.edit:
		if falling:
			fall_speed += 2.6 * delta
			p.ly = minf(renderer.layout.ground_end, p.get("ly", renderer.layout.ground) + fall_speed * delta)
			if p.ly >= renderer.layout.ground:
				p.ly = renderer.layout.ground
				falling = false
				save_state()
		elif not p.asleep:
			walk_wait -= delta
			if walk_wait <= 0:
				var at := Vector2(float(p.get("lx", 0.5)), float(p.get("ly", 0.8)))
				var target := Vector2(clampf(walk_target.x, 0.08, 0.92), clampf(walk_target.y, renderer.layout.ground, renderer.layout.ground_end))
				var distance := (target - at) * Vector2(renderer.layout.width, renderer.layout.height)
				if absf(distance.x) < 2 and absf(distance.y) < 2:
					walk_target = Vector2(randf_range(0.08, 0.92), randf_range(renderer.layout.ground, renderer.layout.ground_end))
					walk_wait = randf_range(0.6, 3.0)
				else:
					var step: Vector2 = distance.normalized() * 0.055 * renderer.layout.width * minf(delta, 0.1)
					p.lx = clampf(at.x + step.x / renderer.layout.width, 0.08, 0.92)
					p.ly = clampf(at.y + step.y / renderer.layout.height, renderer.layout.ground, renderer.layout.ground_end)
					if absf(distance.x) > 3: visual.dir = -1 if distance.x < 0 else 1
	redraw_room()

func _gui_input(event: InputEvent) -> void:
	if canvas == null: return
	var screen_position := get_local_mouse_position()
	var point := screen_position / size * Vector2(renderer.layout.width, renderer.layout.height)
	if event is InputEventMouseMotion:
		if not drag.is_empty():
			if drag.kind == "pet" and not active_pet().is_empty():
				active_pet().lx = clampf((point.x - drag.dx) / renderer.layout.width, 0.08, 0.92)
				active_pet().ly = clampf((point.y - drag.dy) / renderer.layout.height, 0.14, renderer.layout.ground_end)
				visual.annoy = 3.0
			elif drag.kind == "furniture":
				var q: Dictionary = state.placed[drag.key]
				q.x = (point.x - drag.dx) / renderer.layout.width
				q.y = (point.y - drag.dy) / renderer.layout.height
				clamp_furniture(q)
			redraw_room()
		else:
			visual.hover = ""
			hint.text = "拖动宠物陪它玩 · 点房间抚摸 · 点上下图标用功能"
			for icon: Dictionary in renderer.menu_rects():
				if Rect2(icon.x - 2, icon.y - 2, icon.w + 4, icon.h + 4).has_point(point):
					visual.hover = icon.key
					hint.text = "▸ " + icon.name
	elif event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed and state.edit:
			scale_furniture(0.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.25)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: pointer_down(point)
			else: pointer_up()
			accept_event()

func pointer_down(point: Vector2) -> void:
	for icon: Dictionary in renderer.menu_rects():
		if Rect2(icon.x - 2, icon.y - 2, icon.w + 4, icon.h + 4).has_point(point):
			if icon.row == "top":
				if icon.key in ["adopt", "save", "theme"]: handle({"adopt": "adopt", "save": "savepanel", "theme": "themeopen"}[icon.key])
				else: handle("page:" + icon.key)
			else:
				if not renderer.menu_disabled(icon.key, active_pet()): handle(icon.key)
			return
	if state.edit:
		if state.placed.has(state.sel):
			var item: Dictionary = catalog.PLACE[state.sel]
			var selected: Dictionary = state.placed[state.sel]
			var origin := Vector2(Renderer.js_round(selected.x * renderer.layout.width), Renderer.js_round(selected.y * renderer.layout.height))
			var x := clampi(Renderer.js_round(origin.x + item.w * selected.s / 2 + 3), 2, renderer.layout.width - 24)
			var y := clampi(Renderer.js_round(origin.y - item.h * selected.s - 3), 20, renderer.layout.bottom - 14)
			if Rect2(x - 4, y - 4, 17, 17).has_point(point): state.sel = ""; refresh_ui(); save_state(); return
			if Rect2(x + 8, y - 4, 17, 17).has_point(point): handle("furnback:" + state.sel); return
		var keys: Array = state.placed.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return state.placed[a].y > state.placed[b].y)
		for key: String in keys:
			if not catalog.PLACE.has(key): continue
			var q: Dictionary = state.placed[key]
			var item: Dictionary = catalog.PLACE[key]
			var at := Vector2(Renderer.js_round(q.x * renderer.layout.width), Renderer.js_round(q.y * renderer.layout.height))
			if Rect2(at.x - item.w * q.s / 2 - 2, at.y - item.h * q.s - 2, item.w * q.s + 4, item.h * q.s + 5).has_point(point):
				state.sel = key
				drag = {"kind": "furniture", "key": key, "dx": point.x - at.x, "dy": point.y - at.y}
				refresh_ui()
				return
		state.sel = ""
		refresh_ui()
	elif not active_pet().is_empty():
		var at := renderer.pet_at(active_pet())
		if Rect2(at.x - 14, at.y - 34, 28, 38).has_point(point):
			drag = {"kind": "pet", "dx": point.x - at.x, "dy": point.y - at.y}
			falling = false
			visual.annoy = 3.0
		else: drag = {"kind": "tap"}

func pointer_up() -> void:
	if drag.get("kind", "") == "pet":
		var p := active_pet()
		if float(p.get("ly", 0.8)) < renderer.layout.ground - 0.01:
			falling = true
			fall_speed = 0.25
		else:
			p.ly = clampf(float(p.get("ly", 0.8)), renderer.layout.ground, renderer.layout.ground_end)
			walk_wait = maxf(walk_wait, 1.6)
			visual.annoy = 1.2
			save_state()
	elif drag.get("kind", "") == "furniture": save_state()
	elif drag.get("kind", "") == "tap": handle("pet")
	drag = {}

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER and modal_key == "dialog": handle("dlgok"); get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	# 释放时指针可能已移到 HUD/弹窗；仍然结束原房间的拖拽。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not drag.is_empty():
		pointer_up()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and not drag.is_empty(): pointer_up()
