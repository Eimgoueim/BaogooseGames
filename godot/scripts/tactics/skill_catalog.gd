extends RefCounted

const CHARGE_MAX := 3
const NORMAL_CHARGE_GAIN := 1
const ULTIMATE_CHARGE_COST := CHARGE_MAX
const PULSE_RADIUS := 0
const SHOCKWAVE_RADIUS := 1
const OVERLOAD_RADIUS := 2
const BASIC_SKILL := "pulse"
const DEFAULT_LOADOUT: Array[String] = ["pulse", "shockwave", "overload"]

const DEFINITIONS := {
	"pulse": {
		"id": "pulse",
		"name": "能量冲击",
		"kind": "normal",
		"cost": 4,
		"damage_scale": 1.0,
		"radius": PULSE_RADIUS,
		"range_bonus": 0,
		"description": "对宠物射程内、视线畅通且当前可见的敌人造成单体伤害。命中时获得 %d 格充能（上限 %d）。" % [NORMAL_CHARGE_GAIN, CHARGE_MAX],
	},
	"shockwave": {
		"id": "shockwave",
		"name": "震荡波",
		"kind": "normal",
		"cost": 6,
		"damage_scale": 0.75,
		"radius": SHOCKWAVE_RADIUS,
		"range_bonus": 0,
		"description": "以射程内的可见敌人为中心，伤害半径 %d 的菱形范围内敌军；墙体遮挡，不伤己方。命中时获得 %d 格充能（上限 %d）。" % [SHOCKWAVE_RADIUS, NORMAL_CHARGE_GAIN, CHARGE_MAX],
	},
	"overload": {
		"id": "overload",
		"name": "能量爆发",
		"kind": "ultimate",
		"cost": 8,
		"damage_scale": 1.6,
		"radius": OVERLOAD_RADIUS,
		"range_bonus": 0,
		"description": "以射程内的可见敌人为中心，伤害半径 %d 的菱形范围内敌军；墙体遮挡，不伤己方。需要并消耗 %d 格充能。" % [OVERLOAD_RADIUS, ULTIMATE_CHARGE_COST],
	},
}

const SPECIES_LOADOUTS := {
	"dragon": ["pulse", "shockwave", "overload"],
	"goose": ["pulse", "shockwave", "overload"],
	"cat": ["pulse", "shockwave", "overload"],
	"whale": ["pulse", "shockwave", "overload"],
	"hoshino": ["pulse", "shockwave", "overload"],
	"gpt": ["pulse", "shockwave", "overload"],
	"claude": ["pulse", "shockwave", "overload"],
	"gemini": ["pulse", "shockwave", "overload"],
}


static func loadout_for(species: String) -> Array[String]:
	var configured: Array = SPECIES_LOADOUTS.get(species, DEFAULT_LOADOUT)
	var result: Array[String] = []
	for skill_id in configured:
		result.append(str(skill_id))
	return result


static func definition(id: String) -> Dictionary:
	if not DEFINITIONS.has(id):
		return {}
	var result: Dictionary = DEFINITIONS[id].duplicate(true)
	return result
