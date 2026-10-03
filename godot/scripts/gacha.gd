extends RefCounted

# 逐句迁移 pull / pickGachaItem；随机源可注入，以便对照原版序列。
var random_source: Callable

func random_value() -> float:
	return float(random_source.call()) if random_source.is_valid() else randf()

func pull(state: Dictionary, catalog: Dictionary, amount: int) -> Dictionary:
	var constants: Dictionary = catalog.constants
	var times := 10 if amount >= 10 else 1
	var cost := int(constants.PULL_10 if times == 10 else constants.PULL_1)
	if float(state.coins) < cost:
		return {"ok": false, "results": [], "error": "💰 信用点不够（需要 %d），去打工或玩小游戏赚吧" % cost}
	state.coins -= cost
	var results: Array[Dictionary] = []
	for index in times:
		state.pulls += 1
		state.pity = int(state.get("pity", 0)) + 1
		var banner: Dictionary = catalog.BANNERS[0]
		for candidate: Dictionary in catalog.BANNERS:
			if candidate.key == state.banner: banner = candidate; break
		var pet_key := ""
		var pity_kind := ""
		if state.pity >= constants.PITY_BIG:
			pet_key = banner.pet
			pity_kind = "big"
		elif state.pity >= constants.PITY_SMALL:
			pet_key = banner.get("spook", "hoshino") if random_value() < constants.SPOOK_AT_PITY else banner.pet
			pity_kind = "small" if pet_key == banner.pet else "spook"
		elif random_value() < constants.PET_RATE:
			pet_key = banner.get("spook", "hoshino") if random_value() < constants.SPOOK_RATE else banner.pet
		if not pet_key.is_empty():
			state.pity = 0
			var is_new: bool = not state.collection.has(pet_key)
			if is_new: state.collection.append(pet_key)
			else: award_duplicate(state, int(constants.DUP_PET_PTS))
			results.append({"type": "pet", "key": pet_key, "dup": not is_new, "pity": pity_kind, "spook": pet_key != banner.pet})
		else:
			var item := pick_item(catalog.GACHA)
			var key: String = item.key
			match item.kind:
				"wear":
					var is_new: bool = not state.wear.get(key, 0)
					if is_new: state.wear[key] = 1
					else: award_duplicate(state, int(constants.DUP_WEAR_PTS))
					results.append({"type": "wear", "key": key, "dup": not is_new})
				"deco":
					var is_new: bool = not state.decos.get(key, 0)
					state.decos[key] = int(state.decos.get(key, 0)) + 1
					if not is_new: award_duplicate(state, int(constants.DUP_DECO_PTS))
					results.append({"type": "deco", "key": key, "dup": not is_new})
				_:
					state.inv[key] = int(state.inv.get(key, 0)) + 1
					results.append({"type": "food", "key": key, "amount": 1})
	return {"ok": true, "results": results, "error": ""}

func award_duplicate(state: Dictionary, points: int) -> void:
	state.points += points
	state.pointsTotal += points

func pick_item(table: Array) -> Dictionary:
	var total := 0.0
	for item: Dictionary in table: total += float(item.w)
	var value := random_value() * total
	for item: Dictionary in table:
		value -= float(item.w)
		if value < 0: return item
	return table[-1]
