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
const Gameplay = preload("res://scripts/pet_gameplay.gd")
const Gacha = preload("res://scripts/gacha.gd")
const Results = preload("res://scripts/ui/gacha_results.gd")
const Feedback = preload("res://scripts/ui/room_feedback.gd")
const Audio = preload("res://scripts/legacy_audio.gd")
const Dungeon = preload("res://scripts/dungeon.gd")
const Tactics = preload("res://scripts/tactics/battle_screen.gd")
const UI_REFERENCE_SIZE := Vector2i(1120, 960)

var game := Gameplay.new()
var gacha := Gacha.new()
var results_ui: Control
var feedback: Control
var audio: Node
var dungeon: Control
var tactics: Control
var tactics_button: Button
var audio_started := false
var loaded_save := false
var prior_window_mode := DisplayServer.WINDOW_MODE_WINDOWED
var dungeon_fullscreen := false
var bath_spawn := 0.0
var bath_seed := 0.0

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
	_sync_ui_scale()
	get_window().size_changed.connect(_sync_ui_scale)
	catalog = Catalog.load_catalog()
	art = Catalog.read_json("res://data/art.json")
	repository.path = "user://godot-ui/save.json"
	for argument in OS.get_cmdline_user_args():
		if argument == "--preview" or argument.begins_with("--save="): preview_mode = true
	state = hydrate(catalog.default_state)
	if not preview_mode and (FileAccess.file_exists(repository.path) or FileAccess.file_exists(repository.path + ".bak")):
		var result: Dictionary = repository.load_save()
		if result.ok: state = hydrate(result.state); loaded_save = true
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
	game.inject_clock_and_random(int(Time.get_unix_time_from_system() * 1000))
	game.setup(state, catalog)
	if not preview_mode and not loaded_save:
		state = hydrate(game.default_state())
		game.setup(state, catalog)
	audio = Audio.new()
	add_child(audio)
	audio.setup(bool(state.bgm))
	feedback = Feedback.new()
	add_child(feedback)
	results_ui = Results.new()
	add_child(results_ui)
	results_ui.action_requested.connect(handle)
	dungeon = Dungeon.new()
	add_child(dungeon)
	dungeon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dungeon.action_requested.connect(handle)
	dungeon.reward_requested.connect(dungeon_reward)
	dungeon.sound_requested.connect(func(kind: String) -> void:
		if kind in ["home", "dungeon"]: audio.play_track(kind)
		else: audio.cry(kind))
	dungeon.closed.connect(func() -> void:
		modal_key = ""
		if dungeon_fullscreen and DisplayServer.get_name() != "headless": DisplayServer.window_set_mode(prior_window_mode)
		dungeon_fullscreen = false
		if audio_started: audio.play_track("home")
		refresh_ui())
	tactics = Tactics.new()
	add_child(tactics)
	tactics.victory_requested.connect(tactics_reward)
	tactics.closed.connect(func() -> void:
		modal_key = ""
		if audio_started: audio.play_track("home")
		refresh_ui()
		save_state())
	toast_layer = VBoxContainer.new()
	toast_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_layer.add_theme_constant_override("separation", 8)
	add_child(toast_layer)
	resized.connect(refresh_ui)
	refresh_ui()
	if loaded_save: consume_events(game.apply_offline())
	if not preview_mode and not state.get("welcome", false):
		state.coins += 1000
		state.welcome = true
		toast("🎁 欢迎！首次打开赠送 1000 信用点")
		save_state()
	if not preview_mode and not state.get("picked", false): open_modal("adopt")
	refresh_ui()
	print("Godot 原生游戏已启动。")

func _sync_ui_scale() -> void:
	# 大窗口统一缩放原生文字和控件；小窗口保持 1:1，继续使用窄屏布局。
	# canvas_items 让字体按实际分辨率绘制，房间独立的像素画布仍使用最近邻采样。
	var window := get_window()
	var reference := Vector2i(mini(window.size.x, UI_REFERENCE_SIZE.x), mini(window.size.y, UI_REFERENCE_SIZE.y))
	if window.content_scale_size != reference:
		window.content_scale_size = reference

func consume_events(events: Array) -> void:
	var changed := false
	var saving := false
	for event: Dictionary in events:
		match event.type:
			"toast": toast(event.text)
			"changed": changed = true
			"save": saving = true
			"effect":
				feedback.floating(event.kind)
				visual.hop = 0.8
				if event.kind == "💗":
					if not visual.has("hearts"): visual.hearts = []
					for index in 4: visual.hearts.append({"x": renderer.pet_at(active_pet()).x + (index - 1) * 5, "y": Renderer.js_round(renderer.layout.height * 0.5) + index * 2, "life": 1.0, "t": index * 0.12})
			"feed": feedback.feed(event.emoji, event.text); visual.hop = 1.0
			"bath": visual.bath = 3.2; visual.bath_bubbles = []; bath_spawn = 0; bath_seed = randf() * 10; audio.splash()
			"cry": feedback.cry(str(event.get("text", catalog.CRIES.get(event.species, "呜…")))); audio.cry(event.species)
			"dialog":
				dialog_action = event.confirm_action
				modal_key = "dialog"
				modals.show_dialog(event.opts, Renderer.theme_vars(state, catalog))
			"adopt_close": close_panels()
	if changed:
		if modal_key == "adopt": modals.show_modal("adopt", state, catalog, art)
		refresh_ui()
	if saving: save_state()

func dungeon_reward(points: int, credits: int, experience: int) -> void:
	game.drain_events()
	game.gain_points(points, credits, experience)
	consume_events(game.drain_events())
	refresh_ui()
	save_state()
	if dungeon.ended: audio.play_track("home")

func tactics_reward(points: int, credits: int, experience: int) -> void:
	game.drain_events()
	game.gain_points(points, credits, experience)
	consume_events(game.drain_events())
	refresh_ui()
	save_state()

func start_audio() -> void:
	if audio_started or audio == null: return
	audio_started = true
	audio.play_track("home")

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
	var legacy_level := 1
	for pet_record: Dictionary in result.pets: legacy_level = maxi(legacy_level, int(pet_record.level))
	var imported_level := float(raw.get("lv", 0))
	result.lv = maxf(1, imported_level if imported_level != 0 else legacy_level)
	result.exp = maxf(0, float(raw.get("exp", 0)))
	for pet_record: Dictionary in result.pets:
		pet_record.level = result.lv
		pet_record.exp = result.exp
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
	hint = Style.label("拖动宠物陪它玩（它会不耐烦）· 点房间抚摸 · 点屏幕上图标用功能", 10, Color.WHITE)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	music_button = Style.button("🎵", "bgm", handle, Renderer.theme_vars(state, catalog))
	music_button.custom_minimum_size = Vector2(30, 30)
	add_child(music_button)
	tactics_button = Style.button("⚔ 宠物战棋", "tactics", handle, Renderer.theme_vars(state, catalog))
	tactics_button.custom_minimum_size = Vector2(126, 34)
	tactics_button.tooltip_text = "组成宠物战队，在战争迷雾中争夺据点"
	add_child(tactics_button)
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
	game.room_size = Vector2(renderer.layout.width, renderer.layout.height)
	game.ground_end = renderer.layout.ground_end
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
	hint.size = Vector2(size.x * 0.88, 44)
	hint.position = Vector2(size.x * 0.06, size.y - 94)
	hint.text = "拖动家具摆放 · 滚轮或按钮缩放 · 点空处取消选中" if state.edit else "拖动宠物陪它玩（它会不耐烦）· 点房间抚摸 · 点屏幕上图标用功能"
	music_button.position = Vector2(10, size.y - 134)
	tactics_button.position = Vector2(48, size.y - 136)
	music_button.text = "🎵" if state.bgm else "🔇"
	if toast_layer != null:
		var toast_width := minf(520, size.x * 0.88)
		toast_layer.position = Vector2((size.x - toast_width) / 2, size.y - 24 - toast_layer.get_combined_minimum_size().y)
		toast_layer.size.x = toast_width

func save_state() -> bool:
	if preview_mode: return false
	state.lastTick = int(Time.get_unix_time_from_system() * 1000)
	var error := repository.save_state(state)
	if error != OK: toast("⚠️ 保存失败：" + repository.last_error)
	return error == OK

func toast(text: String) -> void:
	if toast_layer == null: return
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var transparent := Style.panel_style(Color.TRANSPARENT, Color.TRANSPARENT, 999)
	panel.add_theme_stylebox_override("panel", transparent)
	toast_layer.add_child(panel)
	var blur := ColorRect.new()
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glass := ShaderMaterial.new()
	glass.shader = preload("res://shaders/frosted_glass.gdshader")
	glass.set_shader_parameter("blur_radius", 9.0)
	glass.set_shader_parameter("corner_radius", 999.0)
	blur.material = glass
	blur.resized.connect(func() -> void: glass.set_shader_parameter("rect_size", blur.size))
	panel.add_child(blur)
	var tint := PanelContainer.new()
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := Style.panel_style(Color(0.17, 0.16, 0.24, 0.28), Color(1, 1, 1, 0.26), 999)
	style.content_margin_left = 17; style.content_margin_right = 17; style.content_margin_top = 9; style.content_margin_bottom = 9
	style.shadow_color = Color(0, 0, 0, 0.16); style.shadow_size = 13; style.shadow_offset = Vector2(0, 10)
	tint.add_theme_stylebox_override("panel", style)
	panel.add_child(tint)
	var label := Style.label(text, 13, Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = minf(label.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, size.x * 0.88 - 34)
	label.add_theme_color_override("font_shadow_color", Color(0.08, 0.05, 0.17, 0.85))
	label.add_theme_constant_override("shadow_offset_y", 1)
	tint.add_child(label)
	panel.tree_exited.connect(func() -> void: if is_inside_tree(): refresh_ui())
	get_tree().create_timer(3.2).timeout.connect(panel.queue_free)
	refresh_ui()

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
	if results_ui != null: results_ui.close()
	refresh_ui()

func open_modal(key: String) -> void:
	close_panels()
	modal_key = key
	modals.show_modal(key, state, catalog, art)
	refresh_ui()

func handle(action: String) -> void:
	start_audio()
	var split := action.split(":", true, 1)
	var key: String = split[0]
	var argument: String = split[1] if split.size() > 1 else ""
	match key:
		"save": save_state()
		"accentlive": state.accent = argument; refresh_ui()
		"toast": toast(argument)
		"affinity":
			game.drain_events()
			game.add_affinity(float(argument))
			consume_events(game.drain_events())
			refresh_ui()
			save_state()
		"bgm":
			state.bgm = not state.bgm
			audio.set_music_enabled(state.bgm)
			music_button.text = "🎵" if state.bgm else "🔇"
			save_state()
		"games", "hub", "rlrestart":
			close_panels()
			dungeon.open_game(state, catalog, art)
			if dungeon.visible:
				modal_key = "rl"
				if not preview_mode and DisplayServer.get_name() != "headless":
					if not dungeon_fullscreen: prior_window_mode = DisplayServer.window_get_mode()
					dungeon_fullscreen = true
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				audio.play_track("dungeon")
				save_state()
		"rlclose": dungeon.close_game()
		"tactics":
			if dungeon.visible: dungeon.close_game()
			close_panels()
			tactics.open_game(state, catalog, art)
			modal_key = "tactics"
			audio.play_track("home")
		"tacticsstart":
			if tactics.visible: tactics.start_battle()
		"tacticsclose":
			if tactics.visible: tactics.request_close()
		"pull":
			var result: Dictionary = gacha.pull(state, catalog, int(argument))
			if not result.ok: toast(result.error); return
			modals.close_modal()
			modal_key = "gacha"
			results_ui.show_results(state, catalog, art, result.results)
			refresh_ui()
			save_state()
		"gachaclose":
			results_ui.close()
			modal_key = ""
			refresh_ui()
		"page", "tab":
			var same := page_key == argument
			close_panels()
			if not same: page_key = argument
			refresh_ui()
		"pageclose", "themeclose", "adoptclose", "saveclose": close_panels()
		"dlgcancel":
			game.dispatch("adopt_cancel")
			dialog_action = ""
			close_panels()
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
			var confirmed := dialog_action
			close_panels()
			if confirmed != "rename": consume_events(game.dispatch(confirmed))
			if confirmed == "reset_confirm": toast("🐣 新的小家伙出生啦！")
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
			gameplay_action_requested.emit(action)
			consume_events(game.dispatch(action))

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
	game.setup(state, catalog)
	game.inject_clock_and_random(int(Time.get_unix_time_from_system() * 1000))
	audio.set_music_enabled(bool(state.bgm))
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
	if tactics != null and tactics.visible:
		# 策略思考期间暂停养成；推进时间戳，避免回房间时补算这段时间。
		var timestamp := int(Time.get_unix_time_from_system() * 1000)
		var pause_ms := maxi(0, timestamp - game.now_ms)
		game.now_ms = timestamp
		state.lastTick = timestamp
		for pet: Dictionary in state.pets:
			if int(pet.get("poopNext", 0)) > 0: pet.poopNext += pause_ms
		return
	game.bathing = float(visual.get("bath", 0)) > 0
	consume_events(game.process(int(Time.get_unix_time_from_system() * 1000)))
	delta = minf(delta, 0.1)
	clock += delta
	visual.bob = int(floor(clock * 2)) % 2 == 1
	visual.annoy = maxf(0, visual.annoy - delta)
	visual.hop = maxf(0, float(visual.get("hop", 0)) - delta * 2.2)
	visual.bath = maxf(0, float(visual.get("bath", 0)) - delta)
	var hearts: Array = []
	for heart: Dictionary in visual.get("hearts", []):
		heart.t -= 0.02
		if heart.t <= 0: heart.life -= 0.018; heart.y -= 0.55
		if heart.life > 0: hearts.append(heart)
	visual.hearts = hearts
	if float(visual.bath) > 0 and not active_pet().is_empty():
		bath_spawn += delta
		var at := renderer.pet_at(active_pet())
		if bath_spawn > 0.16:
			bath_spawn = 0
			visual.bath_bubbles.append({"x": at.x + randf() * 22 - 11, "y": at.y - 2, "r": 1 if randf() < 0.5 else 2, "v": 6 + randf() * 8, "life": 1.0})
		var live: Array = []
		for bubble: Dictionary in visual.bath_bubbles:
			bubble.y -= bubble.v * delta
			bubble.x += sin((bubble.y + bath_seed) * 0.5) * 6 * delta
			bubble.life -= delta * 0.55
			if bubble.life > 0 and bubble.y > at.y - 30: live.append(bubble)
		visual.bath_bubbles = live
	var p := active_pet()
	if not p.is_empty() and drag.is_empty() and not state.edit:
		if falling:
			fall_speed += 2.6 * delta
			p.ly = minf(renderer.layout.ground_end, p.get("ly", renderer.layout.ground) + fall_speed * delta)
			if p.ly >= renderer.layout.ground:
				p.ly = renderer.layout.ground
				falling = false
				visual.hop = 0.6
				visual.annoy = 1.2
				feedback.cry(str(catalog.CRIES.get(p.species, "呜…")))
				audio.cry(p.species)
				save_state()
		elif not p.asleep and float(visual.get("bath", 0)) <= 0:
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
	if event is InputEventScreenTouch or event is InputEventScreenDrag: screen_position = event.position
	var point := screen_position / size * Vector2(renderer.layout.width, renderer.layout.height)
	if event is InputEventMouseMotion or event is InputEventScreenDrag:
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
			hint.text = "拖动家具摆放 · 滚轮或按钮缩放 · 点空处取消选中" if state.edit else "拖动宠物陪它玩（它会不耐烦）· 点房间抚摸 · 点屏幕上图标用功能"
			for icon: Dictionary in renderer.menu_rects():
				if Rect2(icon.x - 2, icon.y - 2, icon.w + 4, icon.h + 4).has_point(point):
					visual.hover = icon.key
					hint.text = "▸ " + icon.name
	elif event is InputEventScreenTouch:
		if event.pressed: pointer_down(point)
		else: pointer_up()
		accept_event()
	elif event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed and state.edit:
			scale_furniture(0.25 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.25)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: pointer_down(point)
			else: pointer_up()
			accept_event()

func pointer_down(point: Vector2) -> void:
	start_audio()
	for icon: Dictionary in renderer.menu_rects():
		if Rect2(icon.x - 2, icon.y - 2, icon.w + 4, icon.h + 4).has_point(point):
			if icon.row == "top":
				if icon.key in ["adopt", "save", "theme"]: handle({"adopt": "adopt", "save": "savepanel", "theme": "themeopen"}[icon.key])
				else: handle("page:" + icon.key)
			else:
				if not renderer.menu_disabled(icon.key, active_pet()): handle(icon.key)
			return
	if not state.edit:
		for index in range(state.get("poops", []).size() - 1, -1, -1):
			var poop: Dictionary = state.poops[index]
			var at := renderer.pet_at(poop)
			if absf(point.x - at.x) <= 7 and point.y <= at.y + 2 and point.y >= at.y - 9: handle("cleanpoop:" + str(index)); return
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
	if (event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey) and event.pressed: start_audio()
	if event is InputEventScreenTouch and not event.pressed and not drag.is_empty(): pointer_up()
	# 释放时指针可能已移到 HUD/弹窗；仍然结束原房间的拖拽。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not drag.is_empty():
		pointer_up()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and not drag.is_empty(): pointer_up()
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not state.is_empty(): save_state()
