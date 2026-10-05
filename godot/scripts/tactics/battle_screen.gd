extends Control

signal closed
signal victory_requested(points: int, credits: int, experience: int)

const Battle = preload("res://scripts/tactics/battle_state.gd")
const Board = preload("res://scripts/tactics/battle_board.gd")
const Style = preload("res://scripts/ui/legacy_ui_style.gd")
const Renderer = preload("res://scripts/room_renderer.gd")

var battle := Battle.new()
var board: Control
var state: Dictionary = {}
var catalog: Dictionary = {}
var art: Dictionary = {}
var vars: Dictionary = {}
var roster_indices: Array[int] = []
var selected_id := -1
var action_mode := "move"
var started := false
var settled := false
var leave_pending := false
var _enemy_delay := 0.0
var _message := ""
var _roster_panel: PanelContainer
var _roster_body: VBoxContainer
var _roster_scroll: ScrollContainer
var _header: PanelContainer
var _sidebar: PanelContainer
var _sidebar_scroll: ScrollContainer
var _info: Label
var _status: Label
var _log: Label
var _squad_buttons: VBoxContainer
var _squad_scroll: ScrollContainer
var _end_button: Button
var _move_button: Button
var _attack_button: Button
var _guard_button: Button
var _exit_button: Button
var _start_button: Button
var _layout_pending := false
var _page_scroll: ScrollContainer
var _content: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	resized.connect(_layout)

func open_game(current: Dictionary, data: Dictionary, drawings: Dictionary) -> void:
	state = current; catalog = data; art = drawings
	vars = Renderer.theme_vars(state, catalog)
	Style.apply(self, vars)
	started = false; settled = false; leave_pending = false
	selected_id = -1; roster_indices.clear()
	for index in state.get("pets", []).size():
		if roster_indices.size() == 4: break
		if float(state.pets[index].get("health", 0)) > 0: roster_indices.append(index)
	_build()
	visible = true
	_refresh_roster()
	_layout()

func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := Style.panel_style(Color(vars.get("--card", "#ffffff")), Color(vars.get("--line", "#eceaf6")), 18)
	style.content_margin_left = 14; style.content_margin_right = 14
	style.content_margin_top = 12; style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _button(text: String, callback: Callable, primary := false) -> Button:
	return Style.card_button(text, "", func(_action: String) -> void: callback.call(), vars, primary)

func _label(text: String, font_size := 14) -> Label:
	var label := Style.label(text, font_size, Color(vars.get("--ink", "#2c2b3d")))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _build() -> void:
	for child in get_children(): remove_child(child); child.queue_free()
	var background := ColorRect.new()
	background.color = Color(vars.get("--bg", "#f4f2fd"))
	add_child(background); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page_scroll = ScrollContainer.new(); _page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_page_scroll); _page_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content = Control.new(); _content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE; _page_scroll.add_child(_content)
	_header = _panel(); _content.add_child(_header)
	var header_column := VBoxContainer.new(); _header.add_child(header_column)
	var top := HBoxContainer.new(); header_column.add_child(top)
	var title := _label("宠物战棋 · 双据点争夺", 18)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(title)
	_exit_button = _button("返回房间", request_close); top.add_child(_exit_button)
	_status = _label("选择你的出战战队", 14); header_column.add_child(_status)
	board = Board.new(); board.battle = battle; board.art = art; board.catalog = catalog
	board.clip_contents = true; _content.add_child(board); board.cell_clicked.connect(_cell_clicked)
	board.cell_hovered.connect(_cell_hovered)
	_sidebar = _panel(); _content.add_child(_sidebar)
	_sidebar_scroll = ScrollContainer.new(); _sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sidebar.add_child(_sidebar_scroll)
	var column := VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8); _sidebar_scroll.add_child(column)
	_info = _label("", 14); column.add_child(_info)
	var actions := HBoxContainer.new(); column.add_child(actions)
	_move_button = _button("移动", func() -> void: _set_mode("move")); actions.add_child(_move_button)
	_attack_button = _button("攻击", func() -> void: _set_mode("attack")); actions.add_child(_attack_button)
	_guard_button = _button("防御", guard_selected); actions.add_child(_guard_button)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size.y = 160
	_squad_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; column.add_child(scroll)
	_squad_buttons = VBoxContainer.new(); _squad_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(_squad_buttons)
	_end_button = _button("结束回合  [空格]", _end_or_restart, true); column.add_child(_end_button)
	var fit := _button("查看全图", func() -> void: board.fit_board()); column.add_child(fit)
	_log = _label("", 12); _log.custom_minimum_size.y = 42; column.add_child(_log)
	var help := _label("左键选择／操作 · Tab 切换宠物\n右键或中键拖地图 · 滚轮缩放\n移动／攻击各 1 行动点，防御减伤 3\n占点每回合得分，先达 6 分或全灭获胜", 12); column.add_child(help)
	_roster_panel = _panel(); _content.add_child(_roster_panel)
	var setup_scroll := ScrollContainer.new(); setup_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_roster_panel.add_child(setup_scroll)
	_roster_body = VBoxContainer.new(); _roster_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; setup_scroll.add_child(_roster_body)
	_roster_body.add_child(_label("编组宠物战队", 20))
	_roster_body.add_child(_label("从已有宠物中选择 1–4 只。战棋使用独立生命值，倒下不会造成宠物永久死亡；战棋期间养成计时暂停。"))
	_roster_scroll = ScrollContainer.new(); _roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_roster_body.add_child(_roster_scroll)
	_start_button = _button("开始对战", start_battle, true); _roster_body.add_child(_start_button)
	_roster_body.add_child(_label("地图上◆为任务据点。未知区域隐藏地形，探索过的区域保留地形，视野之外的敌人不显示。\n胜利奖励：60 信用点 · 10 积分 · 20 玩家经验", 12))
	board.visible = false; _sidebar.visible = false

func _refresh_roster() -> void:
	for child in _roster_scroll.get_children(): _roster_scroll.remove_child(child); child.queue_free()
	var entries := VBoxContainer.new(); entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _roster_scroll.add_child(entries)
	for index in state.get("pets", []).size():
		var pet: Dictionary = state.pets[index]
		var profile: Array = Battle.PROFILES.get(pet.get("species", "dragon"), Battle.PROFILES.dragon)
		var growth := clampi(int(pet.get("level", 1)) - 1, 0, 10)
		var text := "%s %s · Lv.%d\n生命 %d · 移动 %d · 视野 %d · 射程 %d" % ["✓" if index in roster_indices else "○", pet.get("name", "宠物"), int(pet.get("level", 1)), int(profile[0]) + growth * 2, profile[1], profile[2], profile[3]]
		var button := _button(text, _toggle_roster.bind(index), index in roster_indices)
		button.disabled = float(pet.get("health", 0)) <= 0
		button.tooltip_text = "需要先恢复健康" if button.disabled else "点击加入或移出战队"
		entries.add_child(button)
	if state.get("pets", []).is_empty(): entries.add_child(_label("先领养宠物，再来组成战队吧。"))
	_start_button.disabled = roster_indices.is_empty()
	_start_button.text = "开始对战 · %d/4 只出战" % roster_indices.size()
	_layout()

func _toggle_roster(index: int) -> void:
	if index in roster_indices: roster_indices.erase(index)
	elif roster_indices.size() < 4: roster_indices.append(index)
	_refresh_roster()

func start_battle() -> void:
	if roster_indices.is_empty() or started: return
	var pets: Array = []
	for index in roster_indices:
		if index >= state.get("pets", []).size(): continue
		var pet: Dictionary = state.pets[index].duplicate(true)
		pet.pet_index = index; pets.append(pet)
	if pets.is_empty(): return
	battle.setup(pets, catalog)
	started = true; settled = false; leave_pending = false; _enemy_delay = 0
	_roster_panel.visible = false; board.visible = true; _sidebar.visible = true
	selected_id = 0; action_mode = "move"
	_message = "选择宠物，再点蓝色格移动；攻击模式点可见敌人。"
	_layout(); _refresh_battle()
	board.fit_board()

func _layout() -> void:
	if not is_instance_valid(_header): return
	# 极矮窗口允许整页滚动，避免棋盘和操作面板互相覆盖。
	var area := Vector2(size.x - (18 if size.y < 640 else 0), maxf(640, size.y))
	_content.custom_minimum_size = area
	var narrow := area.x < 760
	var header_height := 130.0 if narrow else 112.0
	_header.position = Vector2(12, 12); _header.size = Vector2(area.x - 24, header_height)
	var content_top := header_height + 24
	if narrow:
		var sidebar_height := minf(390, area.y * 0.50)
		_sidebar.position = Vector2(12, area.y - sidebar_height - 12)
		_sidebar.size = Vector2(area.x - 24, sidebar_height)
		board.position = Vector2(12, content_top); board.size = Vector2(area.x - 24, maxf(64, area.y - content_top - sidebar_height - 24))
	else:
		_sidebar.position = Vector2(area.x - 322, content_top); _sidebar.size = Vector2(310, area.y - content_top - 12)
		board.position = Vector2(12, content_top); board.size = Vector2(area.x - 346, area.y - content_top - 12)
	var width := minf(620, area.x - 24)
	_roster_panel.custom_minimum_size.x = width
	_roster_scroll.custom_minimum_size.y = minf(minf(360, maxi(1, state.get("pets", []).size()) * 72), maxf(80, area.y - content_top - 230))
	_roster_panel.size.x = width
	_roster_panel.size.y = maxf(80, area.y - content_top - 12)
	_roster_panel.position = Vector2((area.x - width) * 0.5, content_top)
	if not _layout_pending:
		_layout_pending = true
		call_deferred("_fit_after_layout")

func _fit_after_layout() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(_header): _layout_pending = false; return
	# 换行标签首次分配宽度前会报告过高的最小高度，等待容器排版后收回。
	_header.reset_size()
	_header.size = Vector2(_content.custom_minimum_size.x - 24, 130 if size.x < 760 else 112)
	var top := 154 if size.x < 760 else 136
	_roster_panel.size.y = minf(_content.custom_minimum_size.y - top - 12, _roster_body.get_combined_minimum_size().y + 28)
	_layout_pending = false

func select_unit(id: int, focus := false) -> void:
	var unit := battle.get_unit(id)
	if unit.is_empty() or unit.side != "ally" or unit.hp <= 0: return
	selected_id = id; leave_pending = false
	if focus: board.focus_cell(unit.cell)
	_refresh_battle()

func _set_mode(mode: String) -> void:
	action_mode = mode
	_message = "点蓝色格移动" if mode == "move" else "点视野内且在射程中的敌人攻击"
	_refresh_battle()

func _cell_clicked(cell: Vector2i) -> void:
	if not started or battle.phase != "player": return
	leave_pending = false
	var occupant := battle.unit_at(cell)
	if not occupant.is_empty() and occupant.side == "ally": select_unit(occupant.id); return
	var result: Dictionary
	if action_mode == "attack":
		result = battle.attack_unit(selected_id, cell)
		_message = "造成 %d 伤害%s" % [result.damage, "，敌人倒下" if result.get("defeated", false) else ""] if result.ok else result.error
	else:
		board.preview_path = battle.path_to(selected_id, cell)
		result = battle.move_unit(selected_id, cell)
		_message = (result.get("error", "") if not str(result.get("error", "")).is_empty() else "移动完成，视野已更新") if result.ok else result.error
	_refresh_battle()

func _cell_hovered(cell: Vector2i) -> void:
	if not started or battle.phase != "player": return
	if action_mode == "move": board.preview_path = battle.path_to(selected_id, cell)
	else: board.preview_path.clear()
	_log.text = _message
	var target := battle.unit_at(cell)
	if not target.is_empty() and target.side == "enemy" and battle.visible_cells.has(cell):
		_log.text = "%s · HP %d/%d · 射程 %d · 伤害 %d%s" % [target.name, target.hp, target.max_hp, target.range, target.damage, " · 防御中" if target.guard else ""]
	if action_mode == "attack":
		var result := battle.attack_preview(selected_id, cell)
		if result.ok: _log.text += "\n预计伤害 %d，点击攻击" % result.damage
		elif not target.is_empty() and battle.visible_cells.has(cell): _log.text += "\n" + result.error
	board.queue_redraw()

func guard_selected() -> void:
	var result := battle.defend_unit(selected_id)
	_message = "进入防御，本次敌方回合受到的伤害减少 3" if result.ok else result.error
	_refresh_battle()

func end_turn() -> void:
	if not started or not battle.end_player_turn(): return
	leave_pending = false; _enemy_delay = 0.25; _message = "敌方回合……"
	_refresh_battle()

func _process(delta: float) -> void:
	if not visible or not started or battle.phase != "enemy": return
	_enemy_delay -= delta
	if _enemy_delay > 0: return
	var result := battle.step_enemy()
	_enemy_delay = 0.4 if result.get("visible", false) else 0.10
	if result.get("visible", false) and not str(result.get("message", "")).is_empty(): _message = result.message
	_refresh_battle()

func _refresh_battle() -> void:
	if not started: return
	var names := {"player": "我方行动", "enemy": "敌方行动", "won": "战斗胜利", "lost": "战斗失利"}
	_status.text = "第 %d 回合 · %s · 我方 %d/%d — 敌方 %d/%d" % [battle.round_number, names[battle.phase], battle.score_ally, Battle.TARGET_SCORE, battle.score_enemy, Battle.TARGET_SCORE]
	var unit := battle.get_unit(selected_id)
	if not unit.is_empty():
		_info.text = "%s · HP %d/%d · 行动 %d\n移动 %d · 视野 %d · 射程 %d · 伤害 %d%s" % [unit.name, unit.hp, unit.max_hp, unit.ap, unit.move, unit.sight, unit.range, unit.damage, "\n防御中" if unit.guard else ""]
	board.selected_id = selected_id
	board.reachable = battle.reachable_cells(selected_id) if action_mode == "move" else {}
	board.preview_path.clear(); board.queue_redraw()
	for child in _squad_buttons.get_children(): _squad_buttons.remove_child(child); child.queue_free()
	for ally in battle.units:
		if ally.side != "ally": continue
		var button := _button("%s · HP %d/%d · 行动 %d%s" % [ally.name, ally.hp, ally.max_hp, ally.ap, " ✓" if ally.id == selected_id else ""], select_unit.bind(ally.id, true), ally.id == selected_id)
		button.disabled = ally.hp <= 0; _squad_buttons.add_child(button)
	_squad_scroll.custom_minimum_size.y = minf(180, _squad_buttons.get_child_count() * 48)
	var can_act: bool = battle.phase == "player" and not unit.is_empty() and unit.hp > 0 and unit.ap > 0
	_move_button.disabled = battle.phase != "player" or (not can_act and (unit.is_empty() or int(unit.get("stride", 0)) <= 0))
	_attack_button.disabled = not can_act; _guard_button.disabled = not can_act or unit.get("guard", false)
	_move_button.text = "移动 ✓" if action_mode == "move" else "移动"
	_attack_button.text = "攻击 ✓" if action_mode == "attack" else "攻击"
	_end_button.disabled = battle.phase != "player"
	if battle.phase in ["won", "lost"]:
		_message = "胜利！奖励：60 信用点、10 积分、20 玩家经验。" if battle.phase == "won" else "本局结束。宠物会安全返回房间，可以重新编队挑战。"
		if not settled:
			settled = true
			if battle.phase == "won": victory_requested.emit(Battle.VICTORY_POINTS, Battle.VICTORY_CREDITS, Battle.VICTORY_EXPERIENCE)
		_end_button.disabled = false; _end_button.text = "重新编队"
	_log.text = _message
	_exit_button.text = "确认返回" if leave_pending else "返回房间"

func _restart_roster() -> void:
	open_game(state, catalog, art)

func _end_or_restart() -> void:
	if battle.phase in ["won", "lost"]: _restart_roster()
	else: end_turn()

func request_close() -> void:
	if started and battle.phase in ["player", "enemy"] and not leave_pending:
		leave_pending = true
		_message = "再次点击返回或按 Esc 确认离开。本局进度不会保留。"
		_refresh_battle(); return
	close_game()

func close_game() -> void:
	visible = false; started = false; leave_pending = false
	closed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_ESCAPE: request_close()
		KEY_SPACE:
			if started and battle.phase in ["won", "lost"]: _restart_roster()
			else: end_turn()
		KEY_TAB:
			if not started: return
			var allies: Array[int] = []
			for unit in battle.units:
				if unit.side == "ally" and unit.hp > 0: allies.append(unit.id)
			if not allies.is_empty(): select_unit(allies[(allies.find(selected_id) + 1) % allies.size()], true)
		_: return
	get_viewport().set_input_as_handled()
