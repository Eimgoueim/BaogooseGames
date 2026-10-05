extends Control

signal action_requested(action: String)

const UIStyle = preload("res://scripts/ui/legacy_ui_style.gd")
const Renderer = preload("res://scripts/room_renderer.gd")

const PAGE_NAMES := {
	"shop": "🛍️ 商店", "bag": "🎒 背包", "wear": "🎀 佩饰",
	"room": "🛋️ 房间", "gacha": "🎰 抽卡", "points": "🏆 积分"
}
const SHOP_GROUPS := [
	["daily", "🍙 日常用品"], ["ba", "🎓 碧蓝档案主题"],
	["wear", "🎀 佩饰"], ["furn", "🛋️ 家具"]
]
const SLOT_NAMES := {"head": "头部", "face": "脸部", "neck": "颈部", "back": "背部"}

var _state: Dictionary = {}
var _catalog: Dictionary = {}
var _art: Dictionary = {}
var _vars: Dictionary = {}
var _page := ""
var _panel: PanelContainer
var _body: VBoxContainer
var _scroll: ScrollContainer
var _viewport_size := Vector2(1120, 960)
var _top_ui := 96.0
var _usebar: PanelContainer
var _use_track: HBoxContainer
var _use_middle: HBoxContainer    # 中间内容层：可伸缩 + 裁切，保证两端箭头永远可见
var _bar_signature := ""           # 道具栏内容指纹：没变就不重建按钮
var _use_page := 0
var _use_kind := ""
var _signature := ""            # 页面内容指纹：没变就不重建（否则每帧重建会让滚动条跳回顶部）
var _pending_scroll := -1       # 重建后待恢复的滚动位置
var _pending_left := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_update_layout()

func _page_signature() -> String:
	var st := _state
	var species := ""
	var levels := 0
	for p in st.get("pets", []):
		species += str(p.get("species", "")) + ","
		levels += int(p.get("level", 1))
	match _page:
		"shop":
			return str(st.get("coins"), st.get("inv"), st.get("furnOwn"), st.get("decos"), st.get("wear"),
				st.get("collection"), st.get("seenItems"), st.get("hasToy"), species, levels)
		"gacha":
			return str(st.get("coins"), st.get("points"), st.get("pity"), st.get("pulls"),
				st.get("collection"), st.get("decos"), st.get("wear"), st.get("furnOwn"), st.get("hasToy"))
		"points":
			return str(st.get("points"), st.get("coins"), st.get("title"), st.get("decor"),
				st.get("memoUnlocked"), st.get("shards"), st.get("grave"))
		_:
			return str(st)

func show_page(page: String, state: Dictionary, catalog: Dictionary, art: Dictionary, top_ui: float) -> void:
	_page = page
	_state = state
	_catalog = catalog
	_art = art
	_top_ui = top_ui
	_vars = _theme_vars()
	visible = true
	var sig := str(page, "|", top_ui, "|", _page_signature(), "|", str(_vars).hash())
	if sig == _signature and is_instance_valid(_scroll):
		_update_layout()      # 内容没变：只更新布局，保住滚动位置
		return
	_signature = sig
	_rebuild()
	_update_layout()

func close_page() -> void:
	_signature = ""
	_pending_scroll = -1
	_page = ""
	refresh_usebar("", false, {}, _catalog, _vars)
	visible = false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_panel = null
	_body = null
	_scroll = null
	_usebar = null
	_use_track = null
	_use_middle = null

func refresh_usebar(page: String, any_open: bool, state: Dictionary, catalog: Dictionary, vars: Dictionary) -> void:
	_page = page
	_state = state
	_catalog = catalog
	_vars = vars
	visible = any_open
	if not any_open:
		if is_instance_valid(_usebar): _usebar.queue_free()
		_usebar = null
		_use_track = null
		_use_middle = null
		_bar_signature = ""
		return
	if not is_instance_valid(_usebar):
		_usebar = PanelContainer.new()
		_usebar.mouse_filter = Control.MOUSE_FILTER_STOP
		var bar_style := UIStyle.panel_style(Color(0.094, 0.071, 0.173, 0.42), Color(0, 0, 0, 0), 14)
		bar_style.corner_radius_bottom_left = 0
		bar_style.corner_radius_bottom_right = 0
		bar_style.content_margin_left = 6
		bar_style.content_margin_right = 6
		bar_style.content_margin_bottom = 4
		_usebar.add_theme_stylebox_override("panel", bar_style)
		add_child(_usebar)
	var vp := get_viewport_rect().size
	_usebar.position = Vector2(0, vp.y - 38)
	_usebar.size = Vector2(vp.x, 38)
	if not is_instance_valid(_use_track):
		_use_track = HBoxContainer.new()
		_use_track.add_theme_constant_override("separation", 5)
		_use_track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_usebar.add_child(_use_track)
	var bar_data := _bar_set()
	if bar_data.kind != _use_kind:
		_use_kind = bar_data.kind
		_use_page = 0
	var size := maxi(3, int(floor((maxf(320.0, vp.x) - 112.0) / 92.0)))
	var pages := maxi(1, int(ceil(float(bar_data.keys.size()) / size)))
	_use_page = clampi(_use_page, 0, pages - 1)
	# 内容没变就别重建：真人点击是"按下 → 抬起"跨帧完成的，每帧重建会让抬起落在
	# 已经被 queue_free 的按钮上，pressed 永远不触发（表现为"点道具没反应"）
	var sig := str(_page, "|", bar_data.kind, "|", _use_page, "|", bar_data.keys, "|", int(vp.x),
		"|", str(_state.get("inv")), "|", str(_state.get("wear")), "|", str(_state.get("furnOwn")),
		"|", str(_state.get("decos")), "|", str(_state.get("placed")), "|", str(_state.get("sel")),
		"|", str(_state.get("edit")), "|", str(_state.get("coins")), "|", str(_state.get("points")),
		"|", str(_active_pet(_state.get("pets", [])).get("asleep", false)))
	if sig == _bar_signature and is_instance_valid(_use_track) and is_instance_valid(_use_middle) \
		and _use_track.get_child_count() >= 3 and _use_middle.get_child_count() > 0:
		return
	_bar_signature = sig
	for child in _use_track.get_children():
		_use_track.remove_child(child)
		child.queue_free()
	# 左箭头固定在栏的最左端
	var previous := _bar_button("‹", "useleft")
	previous.custom_minimum_size = Vector2(30, 30)
	previous.disabled = _use_page <= 0
	_use_track.add_child(previous)
	# 中间层：吃掉剩余宽度并裁切，道具名再长也只会裁中间，不会把两侧箭头挤出屏幕
	_use_middle = HBoxContainer.new()
	_use_middle.add_theme_constant_override("separation", 5)
	_use_middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_use_middle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_use_middle.alignment = BoxContainer.ALIGNMENT_CENTER
	_use_middle.clip_contents = true
	_use_track.add_child(_use_middle)
	if pages > 1:
		_add_text_to(_use_middle, str(bar_data.label) + " " + str(_use_page + 1) + "/" + str(pages), 10, Color(1, 1, 1, 0.82))
	for extra in _bar_extras(str(bar_data.kind)):
		var b := _bar_button(str(extra.text), str(extra.action))
		b.custom_minimum_size = Vector2(0, 30)
		b.disabled = _as_bool(extra.get("disabled", false))
		_use_middle.add_child(b)
	if bar_data.keys.is_empty():
		_add_text_to(_use_middle, str(bar_data.empty), 10, Color(1, 1, 1, 0.82))
	else:
		for key in bar_data.keys.slice(_use_page * size, mini(bar_data.keys.size(), (_use_page + 1) * size)):
			var chip := _bar_chip(str(bar_data.kind), str(key))
			_use_middle.add_child(chip)
	# 右箭头固定在栏的最右端
	var next := _bar_button("›", "useright")
	next.custom_minimum_size = Vector2(30, 30)
	next.disabled = _use_page >= pages - 1
	_use_track.add_child(next)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_layout()

func _update_layout() -> void:
	_viewport_size = get_viewport_rect().size
	if is_instance_valid(_panel):
		var width := minf(560.0, _viewport_size.x * 0.92)
		var top := _top_ui + 12.0
		var max_height := minf(_viewport_size.y * 0.64, _viewport_size.y - top - 50.0)
		var natural_height: float = _panel.get_child(0).get_combined_minimum_size().y
		var preferred_height := natural_height
		if _page in ["shop", "gacha"]:
			preferred_height = maxf(preferred_height, max_height)
		elif _page == "points":
			var point_rows: int = _catalog.get("POINT_SHOP", {}).size()
			preferred_height = maxf(preferred_height, 72.0 + 76.0 * point_rows + (52.0 if int(_state.get("points", 0)) <= 0 else 0.0))
		var height := minf(max_height, maxf(150.0, preferred_height))
		_panel.position = Vector2((_viewport_size.x - width) * 0.5, _viewport_size.y * 0.5 - height * 0.46)
		_panel.size = Vector2(width, height)
	if is_instance_valid(_usebar):
		_usebar.position = Vector2(0, _viewport_size.y - 38)
		_usebar.size = Vector2(_viewport_size.x, 38)

func _theme_vars() -> Dictionary:
	var themes: Dictionary = _catalog.get("THEMES", {})
	var theme: Dictionary = themes.get(str(_state.get("theme", "sakura")), {})
	return theme.get("vars", {})

func _rebuild() -> void:
	var keep_scroll := 0
	if is_instance_valid(_scroll):
		keep_scroll = _scroll.scroll_vertical
	# 只重建页面本身，底部道具栏原样保留：
	# 真人点击是"按下 → 抬起"跨帧完成的，若每次刷新都把道具栏按钮释放掉，
	# 抬起就落在已 queue_free 的按钮上，pressed 不触发（表现为"道具点了没反应"）
	for child in get_children():
		if child == _usebar:
			continue
		remove_child(child)
		child.queue_free()
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	UIStyle.apply(self, _vars)
	var card_color := Renderer.color(str(_vars.get("--glass", "rgba(255,255,255,.86)")))
	_panel.add_theme_stylebox_override("panel", UIStyle.panel_style(card_color, _color_from_theme("--line2", Color(0.85, 0.84, 0.92)), 20))
	add_child(_panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	_panel.add_child(outer)
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 14)
	header_margin.add_theme_constant_override("margin_right", 14)
	header_margin.add_theme_constant_override("margin_top", 11)
	header_margin.add_theme_constant_override("margin_bottom", 11)
	outer.add_child(header_margin)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	var header_style := UIStyle.panel_style(_color_from_theme("--btn", Color(0.95, 0.94, 0.98)), _color_from_theme("--line2", Color(0.85, 0.84, 0.92)), 0)
	header_style.set_border_width_all(0)
	header_style.border_width_bottom = 1
	header_margin.add_theme_stylebox_override("panel", header_style)
	header_margin.add_child(header)
	var title := UIStyle.label(PAGE_NAMES.get(_page, ""), 14, _ink())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_button: Button = UIStyle.card_button("✕ 关闭", "pageclose", Callable(self, "_emit_action"), _vars)
	header.add_child(close_button)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(_scroll)
	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 14)
	content_margin.add_theme_constant_override("margin_right", 14)
	content_margin.add_theme_constant_override("margin_top", 10)
	content_margin.add_theme_constant_override("margin_bottom", 12)
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content_margin)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 7)
	_body.add_theme_stylebox_override("panel", UIStyle.panel_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	content_margin.add_child(_body)
	match _page:
		"shop": _build_shop()
		"gacha": _build_gacha()
		"points": _build_points()
	if _page in ["shop", "bag", "wear", "room", "gacha", "points"]:
		refresh_usebar(_page, true, _state, _catalog, _vars)
	var floating := _page in ["shop", "gacha", "points"]
	_panel.visible = floating
	if not floating:
		_panel.queue_free()
		_panel = null
		_body = null
		_scroll = null
	_update_layout()
	call_deferred("_update_layout")
	if keep_scroll > 0 and is_instance_valid(_scroll):
		_scroll.scroll_vertical = keep_scroll    # 先同步恢复一次，多数情况当帧就位
		_pending_scroll = keep_scroll            # 若布局未算完被夹到 0，随后几帧再补
		_pending_left = 6

func _process(_delta: float) -> void:
	if _pending_scroll >= 0 and is_instance_valid(_scroll):
		_scroll.scroll_vertical = _pending_scroll
		if _scroll.scroll_vertical == _pending_scroll or _pending_left <= 0:
			_pending_scroll = -1
		else:
			_pending_left -= 1

func _build_shop() -> void:
	var shop: Dictionary = _catalog.get("SHOP", {})
	var inv: Dictionary = _state.get("inv", {})
	var pets: Array = _state.get("pets", [])
	var pet: Dictionary = _active_pet(pets)
	var species: Dictionary = _catalog.get("SPECIES", {}).get(str(pet.get("species", "")), {})
	var fav_items: Array = species.get("perks", {}).get("favItems", [])
	for group in SHOP_GROUPS:
		var keys: Array = []
		for key in shop:
			if shop[key].get("cat", "") == group[0]: keys.append(key)
		if keys.is_empty(): continue
		_add_text(group[1], 14, _accent())
		for key in keys:
			var item: Dictionary = shop[key]
			var owned := _as_bool(_state.get("wear", {}).get(key, false)) if item.get("wear", false) else (_as_bool(_state.get("furnOwn", {}).get(item.get("furnKey", ""), false)) if item.get("furn", false) else (_as_bool(_state.get("hasToy", false)) if item.get("once", false) else false))
			var locked: bool = (item.has("only") and item.only != pet.get("species", "")) or (item.get("onlyKind", "") == "ai" and not species.get("ai", false))
			var lock_name := str(_catalog.get("SPECIES", {}).get(str(item.get("only", "")), {}).get("name", "AI 型"))
			var tags: Array[String] = []
			if item.get("fresh", false) and not _state.get("seenItems", {}).get(key, false): tags.append("🆕 新品")
			if locked: tags.append(lock_name + "专属")
			if fav_items.has(key): tags.append("❤ 喜爱")
			var name := str(item.get("name", key)) + " x" + str(int(inv.get(key, 0)))
			if not tags.is_empty(): name += "  " + " · ".join(tags)
			var row := _row()
			_add_text_to(row, str(item.get("emoji", "")), 25, _ink())
			var info := _column(row)
			_add_text_to(info, name, 13, _ink())
			_add_text_to(info, str(item.get("desc", "")), 11, _muted())
			_add_text_to(row, "💰" + str(int(item.get("price", 0))), 12, Color(1, 0.63, 0.18))
			var action_button := _button("已拥有" if owned else "购买", "buy:" + str(key))
			action_button.disabled = owned or locked or int(_state.get("coins", 0)) < int(item.get("price", 0))
			row.add_child(action_button)

func _build_bag() -> void:
	var decos: Dictionary = _catalog.get("DECOS", {})
	var owned_decos: Dictionary = _state.get("decos", {})
	var rows := 0
	for key in decos:
		var count := int(owned_decos.get(key, 0))
		if count <= 0: continue
		if rows == 0: _add_text("🎀 装饰品（摆在宠物场景里）", 14, _accent())
		rows += 1
		var item: Dictionary = decos[key]
		var row := _row()
		_add_text_to(row, str(item.get("emoji", "")), 25, _ink())
		var info := _column(row)
		_add_text_to(info, str(item.get("name", key)) + " x" + str(count), 13, _ink())
		_add_text_to(info, "已摆出，重复获得会折算 15 积分", 11, _muted())
	if rows == 0: _add_text("背包是空的", 14, Color(0.84, 0.83, 0.88))

func _build_wear() -> void:
	var wear: Dictionary = _catalog.get("WEAR", {})
	var owned: Dictionary = _state.get("wear", {})
	var pet := _active_pet(_state.get("pets", []))
	var worn: Dictionary = pet.get("worn", {})
	var slot_line := ""
	for slot in ["head", "face", "neck", "back"]:
		var key := str(worn.get(slot, ""))
		var adornment: Dictionary = wear.get(key, {})
		if not slot_line.is_empty(): slot_line += "    "
		slot_line += SLOT_NAMES[slot] + "：" + (str(adornment.get("emoji", "")) + str(adornment.get("name", "")) if not key.is_empty() else "空")
	_add_text(slot_line, 12, _ink())
	var keys: Array = []
	for key in wear:
		if owned.get(key, false): keys.append(key)
	_add_text("已拥有 " + str(keys.size()) + "/" + str(wear.size()) + " · 点一下给「" + str(pet.get("name", "")) + "」戴上或脱下", 12, _muted())
	if keys.is_empty():
		_add_text("还没有佩饰～去商店「🎀 佩饰」买，或者抽卡碰碰运气", 13, Color(0.84, 0.83, 0.88))
		return
	for key in keys:
		var item: Dictionary = wear[key]
		var slot := str(item.get("slot", ""))
		var on := str(worn.get(slot, "")) == str(key)
		var button := _button(str(item.get("emoji", "")) + "  " + str(item.get("name", key)) + "\n" + SLOT_NAMES.get(slot, slot) + (" · 佩戴中" if on else ""), "wear:" + str(key))
		button.custom_minimum_size = Vector2(0, 62)
		_body.add_child(button)

func _build_room() -> void:
	var place: Dictionary = _catalog.get("PLACE", {})
	var furn_own: Dictionary = _state.get("furnOwn", {})
	var decos: Dictionary = _state.get("decos", {})
	var owned: Array[String] = []
	for key in place:
		var item: Dictionary = place[key]
		var is_owned := _as_bool(furn_own.get(key, false)) if item.get("kind", "") == "furn" else _as_bool(decos.get(item.get("key", key), 0))
		if is_owned: owned.append(str(key))
	var placed: Dictionary = _state.get("placed", {})
	var badges := _row()
	_add_badge(badges, "布置模式：" + ("开" if _state.get("edit", false) else "关"), _state.get("edit", false))
	_add_badge(badges, "已摆放 " + str(placed.size()))
	_add_badge(badges, "拥有 " + str(owned.size()))
	var edit := _as_bool(_state.get("edit", false))
	_body.add_child(_button("✅ 完成布置" if edit else "🛋️ 开始布置", "edit", true))
	var selected := str(_state.get("sel", ""))
	if not selected.is_empty():
		var scale := int(round(float(placed.get(selected, {}).get("s", 1.0)) * 100))
		var scale_row := _row()
		_add_text_to(scale_row, "大小 " + str(scale) + "%", 12, Color.WHITE)
		scale_row.add_child(_button("－", "scl:-0.25"))
		scale_row.add_child(_button("＋", "scl:0.25"))
	else:
		_add_text("点房间里或下面列表里的家具来选中", 12, _muted())
	_add_text("我的家具与装饰（点一下摆放 / 已摆放的点一下选中，选中后可拖动或缩放）", 13, _accent())
	if owned.is_empty():
		_add_text("还没有家具～去商店「🛋️ 家具」买，装饰品可以抽卡抽到", 13, Color(0.84, 0.83, 0.88))
		return
	for key in owned:
		var item: Dictionary = place[key]
		var is_placed := placed.has(key)
		var is_selected := selected == key
		var factor := int(round(float(placed.get(key, {}).get("s", 1.0)) * 100)) if is_placed else 0
		var row := _row()
		row.add_child(_button(str(item.get("emoji", "")) + "  " + str(item.get("name", key)) + "  " + (str(factor) + "%" if is_placed else "未摆放") + (" · 选中" if is_selected else ""), "sel:" + key))
		_add_text("已摆放" if is_placed else "摆放", 11, _muted())
		row.add_child(_button("收回", "furnback:" + key))

func _build_gacha() -> void:
	_add_text("🎴 选择卡池", 14, _accent())
	var banners: Array = _catalog.get("BANNERS", [])
	var collection: Array = _state.get("collection", [])
	var species: Dictionary = _catalog.get("SPECIES", {})
	for banner in banners:
		var pet_key := str(banner.get("pet", ""))
		var pet_def: Dictionary = species.get(pet_key, {})
		var selected := str(banner.get("key", "")) == str(_state.get("banner", ""))
		var collected := collection.has(pet_key)
		var caption := str(banner.get("emoji", "")) + " " + str(banner.get("name", ""))
		caption += "\n" + str(banner.get("desc", "")) + "｜" + str(pet_def.get("tag", ""))
		if selected: caption += " · 当前"
		if collected: caption += " · 已获得"
		_body.add_child(_button(caption, "banner:" + str(banner.get("key", ""))))
	var pulls: Dictionary = _catalog.get("constants", {})
	var buttons := _row()
	buttons.add_child(_button("单抽 💰" + str(int(pulls.get("PULL_1", 10))), "pull:1", true))
	buttons.add_child(_button("十连 💰" + str(int(pulls.get("PULL_10", 100))), "pull:10"))
	var total := 0.0
	var food := 0.0
	var deco := 0.0
	for entry in _catalog.get("GACHA", []):
		var weight := float(entry.get("w", 0))
		total += weight
		if entry.get("kind", "") == "food": food += weight
		elif entry.get("kind", "") == "deco": deco += weight
	var pet_rate := float(pulls.get("PET_RATE", 0.015))
	var dup_pet := int(pulls.get("DUP_PET_PTS", 200))
	_add_text("🎯 当前卡池限定 " + str(_current_banner_name()) + " 概率 " + _percent(pet_rate) + "%（重复折算 " + str(dup_pet) + " 积分）\n🍮 食物 " + str(roundi(food / maxf(total, 1.0) * (1.0 - pet_rate) * 100.0)) + "% · 🎀 装饰品 " + str(roundi(deco / maxf(total, 1.0) * (1.0 - pet_rate) * 100.0)) + "%\n已抽 " + str(int(_state.get("pulls", 0))) + " 次 · 当前信用点 💰" + str(int(_state.get("coins", 0))), 12, _muted())
	_add_text("📖 限定图鉴", 14, _accent())
	for key in _catalog.get("LIMIT_KEYS", []):
		var item: Dictionary = species.get(str(key), {})
		var collected := collection.has(key)
		var in_team := false
		for team_pet in _state.get("pets", []):
			if team_pet.get("species", "") == key: in_team = true
		var banner: Dictionary = _banner_for_pet(str(key))
		var name := str(item.get("name", "？？？")) if collected else "？？？"
		var desc := str(item.get("desc", "")) if collected else (str(banner.get("name", "抽卡")) + " 里 3% 概率获得" if not banner.is_empty() else "抽卡 3% 概率获得")
		var row := _row()
		_add_text_to(row, str(item.get("icon", "🐾")) if collected else "❔", 24, _ink())
		var info := _column(row)
		_add_text_to(info, name + (" · 已获得" if collected else " · 未解锁") + (" · 养成中" if in_team else ""), 13, _ink())
		_add_text_to(info, desc, 11, _muted())
		if collected and not in_team: row.add_child(_button("领养", "adoptpick:" + str(key)))
		else: _add_text("3%", 12, Color(1, 0.83, 0.45))
	var deco_defs: Dictionary = _catalog.get("DECOS", {})
	var owned_decos: Dictionary = _state.get("decos", {})
	var owned_keys: Array[String] = []
	for key in deco_defs:
		if int(owned_decos.get(key, 0)) > 0: owned_keys.append(str(key))
	_add_text("🎀 已收集装饰 " + str(owned_keys.size()) + "/" + str(deco_defs.size()), 14, _accent())
	var collected_names := "还没有装饰品"
	if not owned_keys.is_empty():
		var emojis: Array[String] = []
		for key in owned_keys: emojis.append(str(deco_defs[key].get("emoji", "")))
		collected_names = " ".join(emojis)
	_add_text("🎀  " + collected_names + "\n装饰品会直接摆进宠物场景，重复获得折算积分", 12, _muted())

func _build_points() -> void:
	var points := int(_state.get("points", 0))
	_add_text("⭐ 当前积分 " + str(points) + " · 累计获得 " + str(int(_state.get("pointsTotal", 0))), 14, _accent())
	if points <= 0: _add_text("还没有积分～去「🎮 宠物地牢」打一局吧", 13, Color(0.84, 0.83, 0.88))
	var shop: Dictionary = _catalog.get("POINT_SHOP", {})
	for key in shop:
		var item: Dictionary = shop[key]
		var owned := _as_bool(_state.get(str(item.get("flag", "")), false)) if item.has("flag") else false
		var row := _row()
		_add_text_to(row, str(item.get("emoji", "")), 24, _ink())
		var info := _column(row)
		_add_text_to(info, str(item.get("name", key)) + (" · 已拥有" if owned else ""), 13, _ink())
		_add_text_to(info, str(item.get("desc", "")), 11, _muted())
		_add_text_to(row, "⭐" + str(int(item.get("cost", 0))), 12, Color(1, 0.63, 0.18))
		var button := _button("已兑换" if owned else "兑换", "redeem:" + str(key))
		button.disabled = owned or points < int(item.get("cost", 0))
		row.add_child(button)

func _bar_set() -> Dictionary:
	var pet := _active_pet(_state.get("pets", []))
	var species: Dictionary = _catalog.get("SPECIES", {}).get(str(pet.get("species", "")), {})
	var kind := "bag"
	var label := "🎒 道具"
	var act := "use"
	var keys: Array[String] = []
	var empty := "🎒 背包里没有可用的道具"
	if _page == "wear":
		kind = "wear"
		label = "🎀 佩饰"
		act = "wear"
		empty = "🎀 还没有佩饰～去商店买或抽卡"
		for key in _catalog.get("WEAR", {}):
			if _state.get("wear", {}).get(key, false): keys.append(str(key))
	elif _page == "room":
		kind = "room"
		label = "🛋️ 家具"
		act = "sel"
		empty = "🛋️ 家具都摆好啦（点房间里选中的家具，绿勾保存 / 红叉收回）"
		for key in _catalog.get("PLACE", {}):
			var item: Dictionary = _catalog.PLACE[key]
			var has := _as_bool(_state.get("furnOwn", {}).get(key, false)) if item.get("kind", "") == "furn" else _as_bool(_state.get("decos", {}).get(item.get("key", key), 0))
			if has and not _state.get("placed", {}).has(key): keys.append(str(key))
	else:
		for key in _state.get("inv", {}):
			var item: Dictionary = _catalog.get("SHOP", {}).get(key, {})
			if int(_state.inv[key]) <= 0 or item.is_empty(): continue
			# 佩饰/家具/装饰不是"喂给宠物用"的道具（各有自己的页面：🎀 佩饰 / 🛋️ 房间），
			# 混在道具栏里点了只会白消耗，所以这里不列
			if _is_place_or_wear(item): continue
			if item.get("only", "") != "" and item.only != pet.get("species", ""): continue
			if item.get("onlyKind", "") == "ai" and not species.get("ai", false): continue
			keys.append(str(key))
	return {"kind": kind, "label": label, "act": act, "keys": keys, "empty": empty}

func _is_place_or_wear(item: Dictionary) -> bool:
	return item.has("wear") or item.has("furn") or item.has("deco")

func _bar_extras(kind: String) -> Array[Dictionary]:
	var extras: Array[Dictionary] = []
	var pet := _active_pet(_state.get("pets", []))
	if kind == "bag":
		var has_food := false
		for key in _bar_set().keys:
			if _catalog.get("SHOP", {}).get(key, {}).get("effects", {}).has("hunger"): has_food = true
		if has_food: extras.append({"text": "🍚 一键", "action": "feedbest", "disabled": _as_bool(pet.get("asleep", false))})
	elif kind == "room":
		extras.append({"text": "🛠️ " + ("完成" if _state.get("edit", false) else "布置"), "action": "edit"})
		var selected := str(_state.get("sel", ""))
		if not selected.is_empty() and _state.get("placed", {}).has(selected):
			extras.append({"text": "－", "action": "scl:-0.25"})
			extras.append({"text": "＋", "action": "scl:0.25"})
			extras.append({"text": "收回", "action": "furnback:" + selected})
	elif kind == "gacha":
		var constants: Dictionary = _catalog.get("constants", {})
		extras.append({"text": "单抽💰" + str(constants.get("PULL_1", 10)), "action": "pull:1"})
		extras.append({"text": "十连💰" + str(constants.get("PULL_10", 100)), "action": "pull:10"})
	return extras

func _bar_chip(kind: String, key: String) -> Button:
	var action := "use:" + key
	var text := ""
	var disabled := false
	var pet := _active_pet(_state.get("pets", []))
	var catalog_shop: Dictionary = _catalog.get("SHOP", {})
	if kind == "wear":
		var item: Dictionary = _catalog.get("WEAR", {}).get(key, {})
		var worn: Dictionary = pet.get("worn", {})
		var is_on: bool = worn.get(key, "") == key or worn.values().has(key)
		action = "wear:" + key
		text = str(item.get("emoji", "")) + str(item.get("name", key)).substr(0, 4) + "  " + ("戴着" if is_on else "空")
	elif kind == "room":
		var item: Dictionary = _catalog.get("PLACE", {}).get(key, {})
		var placed: Dictionary = _state.get("placed", {})
		var is_placed := placed.has(key)
		var is_selected := str(_state.get("sel", "")) == key
		action = "sel:" + key
		text = str(item.get("emoji", "")) + str(item.get("name", key)).substr(0, 4) + "  " + (str(int(round(float(placed.get(key, {}).get("s", 1.0)) * 100))) + "%" if is_placed else "未摆")
		if is_selected: text = "✓ " + text
	else:
		var item: Dictionary = catalog_shop.get(key, {})
		text = str(item.get("emoji", "")) + str(item.get("name", key)).substr(0, 4) + " x" + str(int(_state.get("inv", {}).get(key, 0)))
		action = "use:" + key
		var species: Dictionary = _catalog.SPECIES.get(pet.get("species", ""), {})
		disabled = _as_bool(pet.get("asleep", false)) or (item.has("only") and item.only != pet.get("species", "")) or (item.get("onlyKind", "") == "ai" and not species.get("ai", false))
	var button := _bar_button(text, action)
	button.disabled = disabled
	button.custom_minimum_size = Vector2(0, 26)
	return button

func _active_pet(pets: Variant) -> Dictionary:
	if not pets is Array or pets.is_empty(): return {}
	var index := clampi(int(_state.get("active", 0)), 0, pets.size() - 1)
	return pets[index]

func _as_bool(value: Variant) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return value != 0
	if value is String:
		return not value.is_empty()
	return false

func _current_banner_name() -> String:
	var current := _banner_for_pet(str(_state.get("banner", "whale")), true)
	return str(current.get("emoji", "")) + " " + str(_catalog.get("SPECIES", {}).get(str(current.get("pet", "")), {}).get("name", ""))

func _banner_for_pet(value: String, by_key := false) -> Dictionary:
	for banner in _catalog.get("BANNERS", []):
		if (banner.get("key", "") == value if by_key else banner.get("pet", "") == value): return banner
	return {}

func _percent(value: float) -> String:
	return ("%.1f" % (value * 100.0)).trim_suffix(".0")

func _row() -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row_bg := _color_from_theme("--soft", Color(0.97, 0.97, 0.99))
	var row_style := UIStyle.panel_style(row_bg, _color_from_theme("--line2", Color(0.90, 0.89, 0.94)), 16)
	row_style.content_margin_left = 12
	row_style.content_margin_right = 12
	row_style.content_margin_top = 10
	row_style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", row_style)
	panel.add_child(row)
	_body.add_child(panel)
	return row

func _column(parent: Control) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 3)
	parent.add_child(column)
	return column

func _add_text(text: String, size := 13, color := Color.WHITE) -> Label:
	return _add_text_to(_body, text, size, color)

func _add_text_to(parent: Control, text: String, size: int, color: Color) -> Label:
	var label := UIStyle.label(text, size, color)
	if parent is HBoxContainer:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _button(text: String, action: String, primary := false) -> Button:
	return UIStyle.card_button(text, action, Callable(self, "_emit_action"), _vars, primary)

func _bar_button(text: String, action: String) -> Button:
	var button := UIStyle.button(text, action, Callable(self, "_emit_action"), _vars)
	var normal := UIStyle.panel_style(Color(1, 1, 1, 0.16), Color.TRANSPARENT, 11)
	normal.content_margin_left = 9
	normal.content_margin_right = 9
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_font_size_override("font_size", UIStyle.readable_font_size(11))
	return button

func _emit_action(action: String) -> void:
	if action == "pageclose":
		close_page()
	action_requested.emit(action)

func shift_use_page(amount: int) -> void:
	var bar_data := _bar_set()
	var size := maxi(3, int(floor((maxf(320.0, get_viewport_rect().size.x) - 112.0) / 92.0)))
	var pages := maxi(1, int(ceil(float(bar_data.keys.size()) / size)))
	_use_page = clampi(_use_page + amount, 0, pages - 1)
	refresh_usebar(_page, true, _state, _catalog, _vars)

func _add_badge(parent: Control, text: String, active := false) -> void:
	var label := _add_text_to(parent, text, 11, _accent() if active else Color.WHITE)
	label.add_theme_stylebox_override("normal", UIStyle.panel_style(Color(0.25, 0.23, 0.32, 0.88), Color(0, 0, 0, 0), 12))

func _accent() -> Color:
	return _color_from_theme("--purple", Color(0.68, 0.60, 1.0))

func _muted() -> Color:
	return _color_from_theme("--muted", Color(0.75, 0.73, 0.80))

func _ink() -> Color:
	return _color_from_theme("--ink", Color(0.17, 0.16, 0.24))

func _color_from_theme(key: String, fallback: Color) -> Color:
	var value := str(_vars.get(key, ""))
	if value.begins_with("#"):
		return Color.html(value)
	return fallback
