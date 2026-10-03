extends RefCounted
class_name StateCodec

const SAVE_VERSION := 1
const SPECIES := ["dragon", "hoshino", "goose", "cat", "whale", "gpt", "claude", "gemini"]
const STATUS_FIELDS := ["hunger", "mood", "clean", "energy", "health"]
const PET_NUMBERS := ["level", "exp", "affRank", "affinity", "ageTicks", "born", "poopNext", "lx", "ly"]
const ROOT_NUMBERS := ["coins", "points", "pointsTotal", "pulls", "camYaw", "camZoom", "pity", "lastTick", "workReady"]

static func _finite_number(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value))

static func _error(message: String) -> Dictionary:
	return {"ok": false, "state": {}, "error": message}

static func normalize(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return _error("存档必须是对象")
	var state: Dictionary = raw.duplicate(true)
	if state.has("godot_save_version"):
		if not _finite_number(state.godot_save_version) or float(state.godot_save_version) != floor(float(state.godot_save_version)) or int(state.godot_save_version) > SAVE_VERSION or int(state.godot_save_version) < 1:
			return _error("不支持的 Godot 存档版本")
	if state.has("ver") and (not _finite_number(state.ver) or float(state.ver) != floor(float(state.ver)) or int(state.ver) > 2 or int(state.ver) < 1):
		return _error("不支持的 HTML 存档版本")
	if not state.has("pets") or typeof(state.pets) != TYPE_ARRAY:
		return _error("pets 必须是数组")
	# UI 与场景会遍历这些容器；拒绝损坏形状，未知字段仍原样保留。
	for key in ["inv", "seenItems", "wear", "placed", "furnOwn", "best", "decos", "shards"]:
		if state.has(key) and typeof(state[key]) != TYPE_DICTIONARY:
			return _error("字段必须是对象：" + key)
	for key in ["poops", "grave", "collection"]:
		if state.has(key) and typeof(state[key]) != TYPE_ARRAY:
			return _error("字段必须是数组：" + key)
	for key in ["theme", "accent", "banner", "title", "sel"]:
		if state.has(key) and typeof(state[key]) != TYPE_STRING:
			return _error("字段必须是文本：" + key)
	for quantity: Variant in state.get("inv", {}).values():
		if not _finite_number(quantity): return _error("背包数量无效")
	for placement: Variant in state.get("placed", {}).values():
		if typeof(placement) != TYPE_DICTIONARY: return _error("家具位置必须是对象")
		for key in ["x", "y", "s"]:
			if placement.has(key) and not _finite_number(placement[key]): return _error("家具位置数值无效")
	for poop: Variant in state.get("poops", []):
		if typeof(poop) != TYPE_DICTIONARY: return _error("排泄记录必须是对象")
		for key in ["lx", "ly", "t"]:
			if poop.has(key) and not _finite_number(poop[key]): return _error("排泄位置数值无效")
	if state.pets.is_empty():
		if typeof(state.get("grave", [])) != TYPE_ARRAY or state.get("grave", []).is_empty():
			return _error("存档没有宠物或墓碑记录")
	for key in ROOT_NUMBERS:
		if state.has(key) and not _finite_number(state[key]):
			return _error("数值字段无效：" + key)
	for index in state.pets.size():
		if typeof(state.pets[index]) != TYPE_DICTIONARY:
			return _error("宠物记录必须是对象")
		var pet: Dictionary = state.pets[index]
		if pet.has("worn") and typeof(pet.worn) != TYPE_DICTIONARY:
			return _error("佩饰记录必须是对象")
		for accessory: Variant in pet.get("worn", {}).values():
			if typeof(accessory) != TYPE_STRING: return _error("佩饰标识必须是文本")
		if pet.has("name") and typeof(pet.name) != TYPE_STRING:
			return _error("宠物名字必须是文本")
		if not pet.has("species") or typeof(pet.species) != TYPE_STRING or not SPECIES.has(pet.species):
			return _error("宠物种类无效")
		for key in PET_NUMBERS + STATUS_FIELDS:
			if pet.has(key) and not _finite_number(pet[key]):
				return _error("宠物数值字段无效：" + key)
		for key in STATUS_FIELDS:
			if pet.has(key) and (float(pet[key]) < 0.0 or float(pet[key]) > 100.0):
				return _error("宠物状态超出 0 到 100：" + key)
		if pet.has("level") and float(pet.level) < 1.0:
			return _error("宠物等级必须至少为 1")
		if pet.has("affRank") and float(pet.affRank) < 1.0:
			return _error("亲密等级必须至少为 1")
		for key in ["exp", "affinity", "ageTicks"]:
			if pet.has(key) and float(pet[key]) < 0.0:
				return _error("宠物数值不能为负数：" + key)
	if state.pets.is_empty():
		state.active = 0
	else:
		var active_value: Variant = state.get("active", 0)
		if typeof(active_value) == TYPE_STRING:
			if not String(active_value).is_valid_float():
				return _error("数值字段无效：active")
			active_value = float(active_value)
		if not _finite_number(active_value):
			return _error("数值字段无效：active")
		state.active = clampi(int(active_value), 0, state.pets.size() - 1)
	state["godot_save_version"] = SAVE_VERSION
	return {"ok": true, "state": state, "error": ""}
