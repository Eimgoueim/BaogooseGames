extends Control

signal closed
signal victory_requested(points: int, credits: int, experience: int)

const Battle = preload("res://scripts/tactics/battle_state.gd")
const Skills = preload("res://scripts/tactics/skill_catalog.gd")
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
var selected_skill_id := Skills.BASIC_SKILL
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
var _skills_button: Button
var _skills_panel: VBoxContainer
var _skill_entries: VBoxContainer
var _skill_buttons: Dictionary = {}
var _skill_info: Label
var _guard_button: Button
var _deploy_button: Button
var _territories: Label
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
	selected_skill_id = Skills.BASIC_SKILL; _skill_buttons.clear()
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
	var title := _label("宠物战棋 · 区域争夺", 18)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(title)
	_exit_button = _button("返回房间", request_close); top.add_child(_exit_button)
	_status = _label("选择你的出战战队", 14); header_column.add_child(_status)
	board = Board.new(); board.battle = battle; board.art = art; board.catalog = catalog
	board.clip_contents = true; _content.add_child(board); board.cell_clicked.connect(_cell_clicked)
	board.cell_hovered.connect(_cell_hovered)
	_sidebar = _panel(); _content.add_child(_sidebar)
	var sidebar_frame := VBoxContainer.new(); _sidebar.add_child(sidebar_frame)
	_sidebar_scroll = ScrollContainer.new(); _sidebar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sidebar_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar_frame.add_child(_sidebar_scroll)
	var column := VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8); _sidebar_scroll.add_child(column)
	_info = _label("", 14); column.add_child(_info)
	var actions := HBoxContainer.new(); column.add_child(actions)
	_move_button = _button("移动", func() -> void: _set_mode("move")); actions.add_child(_move_button)
	_skills_button = _button("释放技能", func() -> void: _set_mode("skill")); actions.add_child(_skills_button)
	_guard_button = _button("防御 %d" % Battle.DEFEND_COST, guard_selected); actions.add_child(_guard_button)
	_skills_panel = VBoxContainer.new(); column.add_child(_skills_panel)
	_skill_entries = VBoxContainer.new(); _skills_panel.add_child(_skill_entries)
	_skill_info = _label("", 12); _skills_panel.add_child(_skill_info)
	_log = _label("", 12); _log.custom_minimum_size.y = 86
	_log.max_lines_visible = 4; _log.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_log.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(_log)
	_deploy_button = _button("增援小兵", func() -> void: _set_mode("deploy")); column.add_child(_deploy_button)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size.y = 160
	_squad_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; column.add_child(scroll)
	_squad_buttons = VBoxContainer.new(); _squad_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL; scroll.add_child(_squad_buttons)
	_end_button = _button("结束本轮  [空格]", _end_or_restart, true); sidebar_frame.add_child(_end_button)
	_end_button.tooltip_text = "放弃本轮剩余指令；对方结束后统一结算区域与补给"
	var fit := _button("查看全图", func() -> void: board.fit_board()); column.add_child(fit)
	_territories = _label("", 12); column.add_child(_territories)
	var help := _label("左键选择／操作 · Tab 切换宠物\n右键或中键拖地图 · 滚轮缩放\n双方交替：一次宠物指令后交给对方\n每方每轮共享 %d 点，换手不回满\n普通格 1、灌木 2；防御 %d 点，减伤 3\n点释放技能，再选技能和可见敌人\n普通技能命中加 1 格，各宠物独立充能\n满 %d 格可用大招，充能跨轮保留\n指令后先由对方小兵各响应一次\n开局已有兵线，小兵也参与夺区\n增援不耗点，可放在稳定控制区前方\n结束本轮放弃余点，双方结束后结算\n每区每轮 1 分，达到 %d 分并领先获胜\n消灭对方全部宠物也可获胜" % [Battle.TURN_AP, Battle.DEFEND_COST, Skills.CHARGE_MAX, Battle.TARGET_SCORE], 12); column.add_child(help)
	_roster_panel = _panel(); _content.add_child(_roster_panel)
	var setup_scroll := ScrollContainer.new(); setup_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_roster_panel.add_child(setup_scroll)
	_roster_body = VBoxContainer.new(); _roster_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; setup_scroll.add_child(_roster_body)
	_roster_body.add_child(_label("编组宠物战队", 20))
	_roster_body.add_child(_label("从已有宠物中选择 1–4 只。战棋使用独立生命值，倒下不会造成宠物永久死亡；战棋期间养成计时暂停。"))
	_roster_scroll = ScrollContainer.new(); _roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_roster_body.add_child(_roster_scroll)
	_start_button = _button("开始对战", start_battle, true); _roster_body.add_child(_start_button)
	_roster_body.add_child(_label("开局双方各有 %d 名小兵在前方，宠物从后排展开。双方轮流下一个宠物指令；对方小兵响应后，交出指令权。\n每方每轮共享 %d 行动点；双方都结束后才回满、结算区域并各增加 1 个增援名额，下一轮交换先手。控制前方区域可以就近增援。\n每只宠物有两招普通技能和一招充能大招，目前使用相同占位技能。普通技能命中积攒充能，满 %d 格可释放大招。\n区域内单方单位驻守则获得控制；双方同在则争夺中、不产分，也不能增援。小兵也能夺区。\n未知地形和视野外敌人隐藏，区域显示己方已知归属。\n胜利奖励：60 信用点 · 10 积分 · 20 玩家经验" % [Battle.Map.ALLY_FRONTLINE_SPAWNS.size(), Battle.TURN_AP, Skills.CHARGE_MAX], 12))
	board.visible = false; _sidebar.visible = false

func _refresh_roster() -> void:
	for child in _roster_scroll.get_children(): _roster_scroll.remove_child(child); child.queue_free()
	var entries := VBoxContainer.new(); entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _roster_scroll.add_child(entries)
	for index in state.get("pets", []).size():
		var pet: Dictionary = state.pets[index]
		var profile: Array = Battle.PROFILES.get(pet.get("species", "dragon"), Battle.PROFILES.dragon)
		var growth := clampi(int(pet.get("level", 1)) - 1, 0, 10)
		var text := "%s %s · Lv.%d\n生命 %d · 视野 %d · 射程 %d" % ["✓" if index in roster_indices else "○", pet.get("name", "宠物"), int(pet.get("level", 1)), int(profile[0]) + growth * 2, profile[2], profile[3]]
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
	selected_skill_id = Skills.BASIC_SKILL
	_message = "双方交替下指令，每轮各 %d 点。小兵在前方，控制新区域后可以就近增援。" % Battle.TURN_AP
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
	if unit.is_empty() or unit.side != "ally" or unit.hp <= 0 or unit.get("kind", "pet") != "pet": return
	selected_id = id; leave_pending = false
	if focus: board.focus_cell(unit.cell)
	_refresh_battle()

func _set_mode(mode: String) -> void:
	action_mode = mode
	match mode:
		"move": _message = "点蓝色格移动，悬停可查看预计点数"
		"skill": _message = "选择技能，再点射程内的可见敌人；悬停可预览范围与伤害"
		"deploy": _message = "点绿色空格增援小兵：仅限己方稳定控制区域的可见空地，前方控制区也可部署"
	_refresh_battle()

func _select_skill(skill_id: String) -> void:
	var unit := battle.get_unit(selected_id)
	if unit.is_empty() or skill_id not in unit.get("skills", []): return
	selected_skill_id = skill_id; action_mode = "skill"; leave_pending = false
	var skill := Skills.definition(skill_id)
	_message = "%s：选择橙框中的可见敌人作为目标" % skill.name
	_refresh_battle()

func _skill_report(result: Dictionary) -> String:
	var summaries: Array[String] = []
	for hit: Dictionary in result.get("hits", []):
		summaries.append("%s %d%s" % [hit.name, hit.damage, "（倒下）" if hit.defeated else ""])
	return "%s · 消耗 %d 点\n%s" % [result.skill_name, result.cost, "、".join(summaries)]

func _cell_clicked(cell: Vector2i) -> void:
	if not started or battle.phase != "player" or battle.has_pending_reactions(): return
	leave_pending = false
	if action_mode == "deploy":
		var deployed := battle.deploy_soldier("ally", cell)
		_message = "小兵已增援，不消耗点数或交出指令；将在敌方宠物行动后自动行动，也可夺区" if deployed.ok else deployed.error
		if deployed.ok and int(battle.deploy_budget.ally) <= 0: action_mode = "move"
		_refresh_battle(); return
	var occupant := battle.unit_at(cell)
	if not occupant.is_empty() and occupant.side == "ally":
		if occupant.get("kind", "pet") == "pet": select_unit(occupant.id)
		else:
			_message = "我方小兵 · HP %d/%d · 自动移动 %d 格 · 伤害 %d；不能手动控制" % [occupant.hp, occupant.max_hp, occupant.move, occupant.damage]
			_refresh_battle()
		return
	var result: Dictionary
	if action_mode == "skill":
		result = battle.cast_skill(selected_id, selected_skill_id, cell)
		_message = _skill_report(result) if result.ok else result.error
	else:
		board.preview_path = battle.path_to(selected_id, cell)
		result = battle.move_unit(selected_id, cell)
		_message = "移动消耗 %d 点%s" % [result.cost, "；" + result.error if not str(result.get("error", "")).is_empty() else "，视野已更新"] if result.ok else result.error
	if battle.has_pending_reactions() or battle.phase == "enemy": _enemy_delay = 0.20
	_refresh_battle()

func _cell_hovered(cell: Vector2i) -> void:
	if not started or battle.phase != "player" or battle.has_pending_reactions(): return
	board.skill_area.clear(); board.skill_hit_cells.clear()
	if action_mode == "move": board.preview_path = battle.path_to(selected_id, cell)
	else: board.preview_path.clear()
	_log.text = _message
	if action_mode == "move" and not board.preview_path.is_empty():
		var cost := battle.movement_cost(selected_id, cell)
		_log.text = "预计移动消耗 %d 点 · 剩余 %d 点\n未探索地形按普通格估计，遇阻只扣实际路程" % [cost, int(battle.action_points.ally) - cost]
	elif action_mode == "deploy" and board.deployment_cells.has(cell):
		_log.text = "%s · 点击增援小兵，不消耗点数或交出指令权" % battle.region_at(cell).name
	var target := battle.unit_at(cell)
	if not target.is_empty() and target.side == "enemy" and battle.visible_cells.has(cell):
		_log.text = "%s · HP %d/%d · 射程 %d · 伤害 %d%s" % [target.name, target.hp, target.max_hp, target.range, target.damage, " · 防御中" if target.guard else ""]
	if action_mode == "skill":
		var result := battle.skill_preview(selected_id, selected_skill_id, cell)
		if result.ok:
			board.skill_area = result.area
			var hits: Array[String] = []
			for hit: Dictionary in result.hits:
				board.skill_hit_cells[hit.cell] = true
				hits.append("%s %d%s" % [hit.name, hit.damage, "（可击倒）" if hit.defeated else ""])
			_log.text += "\n%s · 预计伤害：%s · 消耗 %d 点\n橙色为技能范围，仅预览已见敌军" % [result.skill_name, "、".join(hits), result.cost]
		elif not target.is_empty() and battle.visible_cells.has(cell): _log.text += "\n" + result.error
	_log.tooltip_text = _log.text
	board.queue_redraw()

func guard_selected() -> void:
	var result := battle.defend_unit(selected_id)
	_message = "消耗 %d 点进入防御，受到的伤害减少 3" % Battle.DEFEND_COST if result.ok else result.error
	if battle.has_pending_reactions() or battle.phase == "enemy": _enemy_delay = 0.20
	_refresh_battle()

func end_turn() -> void:
	var old_round := battle.round_number
	if not started or not battle.end_player_turn(): return
	leave_pending = false; _enemy_delay = 0.20
	_message = "双方已结束，区域结算后开始新一轮" if battle.round_number != old_round else "我方已结束本轮；对方继续剩余指令，然后统一结算"
	_refresh_battle()

func _process(delta: float) -> void:
	if not visible or not started or (battle.phase != "enemy" and not battle.has_pending_reactions()): return
	_enemy_delay -= delta
	if _enemy_delay > 0: return
	var old_round := battle.round_number
	var result := battle.step_reaction() if battle.has_pending_reactions() else battle.step_enemy()
	_enemy_delay = (0.10 if result.get("visible", false) else 0.02) if result.get("reaction", false) else (0.28 if result.get("visible", false) else 0.06)
	if result.get("visible", false) and not str(result.get("message", "")).is_empty(): _message = result.message
	if battle.round_number != old_round: _message = "双方已结束，区域与补给已结算；第 %d 轮%s先下指令" % [battle.round_number, "我方" if battle.round_starter == "ally" else "敌方"]
	_refresh_battle()

func _refresh_battle() -> void:
	if not started: return
	var names := {"player": "我方指令", "enemy": "敌方指令", "won": "战斗胜利", "lost": "战斗失利"}
	var phase_name: String = "小兵响应中" if battle.has_pending_reactions() else names[battle.phase]
	_status.text = "第 %d 轮 · %s · 双方交替 · 胜利分 %d — %d / %d\n共享行动点 我方 %d/%d%s · 敌方 %d/%d%s" % [battle.round_number, phase_name, battle.score_ally, battle.score_enemy, Battle.TARGET_SCORE, battle.action_points.ally, Battle.TURN_AP, "（已结束）" if battle.round_done.ally else "", battle.action_points.enemy, Battle.TURN_AP, "（已结束）" if battle.round_done.enemy else ""]
	var unit := battle.get_unit(selected_id)
	if not unit.is_empty():
		_info.text = "%s · HP %d/%d\n视野 %d · 技能射程 %d · 威力 %d%s\n大招充能 %s %d/%d%s" % [unit.name, unit.hp, unit.max_hp, unit.sight, unit.range, unit.damage, " · 防御中" if unit.guard else "", "●".repeat(int(unit.get("charge", 0))) + "○".repeat(maxi(0, Skills.CHARGE_MAX - int(unit.get("charge", 0)))), unit.get("charge", 0), Skills.CHARGE_MAX, " · 就绪" if int(unit.get("charge", 0)) >= Skills.CHARGE_MAX else ""]
	_refresh_skill_panel(unit)
	var region_lines: Array[String] = []
	var owners := {"neutral": "中立", "ally": "我方", "enemy": "敌方"}
	for region in battle.regions:
		var record: Dictionary = battle.region_memory.get(region.id, {})
		region_lines.append("%s %s" % [region.name, "未知" if record.is_empty() else ("争夺" if record.get("contested", false) else owners[record.get("owner", "neutral")])])
	_territories.text = "区域归属（己方已知）\n%s\n%s\n%s" % [" · ".join(region_lines.slice(0, 3)), " · ".join(region_lines.slice(3, 6)), " · ".join(region_lines.slice(6, 9))]
	board.selected_id = selected_id
	board.reachable = battle.reachable_cells(selected_id) if action_mode == "move" else {}
	board.deployment_cells = battle.deployment_cells("ally") if action_mode == "deploy" else {}
	board.skill_targets = battle.skill_targets(selected_id, selected_skill_id) if action_mode == "skill" else {}
	board.skill_area.clear(); board.skill_hit_cells.clear()
	board.preview_path.clear(); board.queue_redraw()
	for child in _squad_buttons.get_children(): _squad_buttons.remove_child(child); child.queue_free()
	for ally in battle.units:
		if ally.side != "ally" or ally.get("kind", "pet") != "pet": continue
		var button := _button("%s · HP %d/%d · 充能 %d/%d%s" % [ally.name, ally.hp, ally.max_hp, ally.get("charge", 0), Skills.CHARGE_MAX, " ✓" if ally.id == selected_id else ""], select_unit.bind(ally.id, true), ally.id == selected_id)
		button.clip_text = true
		button.tooltip_text = "%s · HP %d/%d · 大招充能 %d/%d" % [ally.name, ally.hp, ally.max_hp, ally.get("charge", 0), Skills.CHARGE_MAX]
		button.disabled = ally.hp <= 0; _squad_buttons.add_child(button)
	_squad_scroll.custom_minimum_size.y = minf(180, _squad_buttons.get_child_count() * 48)
	var can_act: bool = battle.phase == "player" and not battle.has_pending_reactions() and not unit.is_empty() and unit.hp > 0 and int(battle.action_points.ally) > 0
	_move_button.disabled = not can_act
	_skills_button.disabled = battle.phase != "player" or battle.has_pending_reactions() or unit.is_empty() or unit.hp <= 0
	_guard_button.disabled = not can_act or int(battle.action_points.ally) < Battle.DEFEND_COST or unit.get("guard", false)
	_move_button.text = "移动 ✓" if action_mode == "move" else "移动"
	_skills_button.text = "释放技能 ✓" if action_mode == "skill" else "释放技能"
	_deploy_button.text = "增援小兵 · 剩余 %d%s" % [battle.deploy_budget.ally, " ✓" if action_mode == "deploy" else ""]
	_deploy_button.disabled = battle.phase != "player" or battle.has_pending_reactions() or int(battle.deploy_budget.ally) <= 0
	_end_button.disabled = battle.phase != "player" or battle.has_pending_reactions()
	if battle.phase in ["won", "lost"]:
		_message = "胜利！奖励：60 信用点、10 积分、20 玩家经验。" if battle.phase == "won" else "本局结束。宠物会安全返回房间，可以重新编队挑战。"
		if not settled:
			settled = true
			if battle.phase == "won": victory_requested.emit(Battle.VICTORY_POINTS, Battle.VICTORY_CREDITS, Battle.VICTORY_EXPERIENCE)
		_end_button.disabled = false; _end_button.text = "重新编队"
	_log.text = _message
	_log.tooltip_text = _message
	_exit_button.text = "确认返回" if leave_pending else "返回房间"

func _refresh_skill_panel(unit: Dictionary) -> void:
	_skills_panel.visible = action_mode == "skill"
	var loadout := battle.skill_loadout(selected_id)
	var ids: Array[String] = []
	for skill in loadout: ids.append(skill.id)
	if selected_skill_id not in ids and not ids.is_empty(): selected_skill_id = ids[0]
	if _skill_buttons.keys() != ids:
		for child in _skill_entries.get_children(): _skill_entries.remove_child(child); child.queue_free()
		_skill_buttons.clear()
		for skill in loadout:
			var button := _button("", _select_skill.bind(skill.id))
			_skill_buttons[skill.id] = button; _skill_entries.add_child(button)
	for skill in loadout:
		var button: Button = _skill_buttons[skill.id]
		var ready := battle.skill_ready(selected_id, skill.id)
		button.disabled = not ready.ok
		button.text = "%s%s · %d 点%s" % ["大招 · " if skill.kind == "ultimate" else "", skill.name, skill.cost, " ✓" if action_mode == "skill" and selected_skill_id == skill.id else ""]
		button.tooltip_text = skill.description + ("\n" + ready.error if not ready.ok else "")
	var selected := Skills.definition(selected_skill_id)
	if selected.is_empty() or unit.is_empty(): _skill_info.text = ""; return
	_skill_info.text = "%s · 射程 %d · %s\n威力 ×%.2f · %s\n仅伤敌军，墙体遮挡" % [selected.name, int(unit.range) + int(selected.range_bonus), "单体" if int(selected.radius) == 0 else "菱形范围半径 %d" % selected.radius, selected.damage_scale, "消耗 %d 格充能" % Skills.CHARGE_MAX if selected.kind == "ultimate" else "命中充能 +1"]

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
				if unit.side == "ally" and unit.hp > 0 and unit.get("kind", "pet") == "pet": allies.append(unit.id)
			if not allies.is_empty(): select_unit(allies[(allies.find(selected_id) + 1) % allies.size()], true)
		_: return
	get_viewport().set_input_as_handled()
