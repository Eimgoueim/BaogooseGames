extends SceneTree

const Codec = preload("res://scripts/state_codec.gd")
const Repository = preload("res://scripts/save_repository.gd")
const Catalog = preload("res://scripts/legacy_catalog.gd")
const TEST_PATH := "res://.runtime/test_saves/save.json"

var failures := 0

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("失败：" + message)

func _json_equivalent(left: Variant, right: Variant) -> bool:
	var left_type := typeof(left)
	var right_type := typeof(right)
	if (left_type == TYPE_INT or left_type == TYPE_FLOAT) and (right_type == TYPE_INT or right_type == TYPE_FLOAT):
		return float(left) == float(right)
	if left_type != right_type:
		return false
	if left is Dictionary:
		if left.size() != right.size():
			return false
		for key in left:
			if not right.has(key) or not _json_equivalent(left[key], right[key]):
				return false
		return true
	if left is Array:
		if left.size() != right.size():
			return false
		for index in left.size():
			if not _json_equivalent(left[index], right[index]):
				return false
		return true
	return left == right

func _write(path: String, value: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(value)
	file.flush()
	file.close()

func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var content := file.get_as_text()
	file.close()
	return content

func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var target := ProjectSettings.globalize_path(TEST_PATH + suffix)
		if FileAccess.file_exists(TEST_PATH + suffix):
			DirAccess.remove_absolute(target)
	var parent := ProjectSettings.globalize_path(TEST_PATH.get_base_dir())
	if not DirAccess.dir_exists_absolute(parent):
		return
	for entry in DirAccess.get_files_at(parent):
		if entry.begins_with("save.json.corrupt.") or entry.begins_with("save.json.bak.previous.") or entry == "blocked_save.tmp":
			DirAccess.remove_absolute(parent.path_join(entry))

func _legacy_state() -> Dictionary:
	return {
		"ver": 2,
		"pets": [{"species": "dragon", "name": "团子", "level": 3, "exp": 17,
			"hunger": 80, "mood": 71, "clean": 66, "energy": 52, "health": 99,
			"worn": {"hat": "star"}, "future_pet_field": {"keep": true}}],
		"active": "0", "coins": 123, "inv": {"basic": 4}, "grave": [],
		"shards": {"whale": 2}, "placed": {"lamp": {"x": 0.4}}, "wear": {"star": 1},
		"collection": ["whale"],
		"future_root_field": ["nested", 1, null, false, {"array": [2.5, "keep", true]}]
	}

func _initialize() -> void:
	_cleanup()
	var input := _legacy_state()
	var normalized := Codec.normalize(input)
	_check(normalized.ok, "HTML v2 存档应规范化")
	if normalized.ok:
		_check(normalized.state.ver == 2, "HTML ver 应保留")
		_check(normalized.state.godot_save_version == 1, "应写入独立 Godot 版本")
		_check(normalized.state.active == 0 and typeof(normalized.state.active) == TYPE_INT, "active 应规范为整数")
		_check(normalized.state.future_root_field == input.future_root_field, "未知根字段应保留")
		_check(normalized.state.pets[0].future_pet_field == input.pets[0].future_pet_field, "未知宠物字段应保留")
		_check(normalized.state.inv == input.inv and normalized.state.placed == input.placed, "未迁移字段应保留")
		var repository := Repository.new()
		repository.path = TEST_PATH
		_check(repository.save_state(normalized.state) == OK, "合法存档应写入")
		var loaded := repository.load_save()
		_check(loaded.ok and _json_equivalent(loaded.state.future_root_field, input.future_root_field), "保存后未知字段应往返保留")
		_check(loaded.ok and loaded.state.pets[0].worn == input.pets[0].worn, "宠物穿戴字段应往返保留")
	_check(not Codec.normalize(null).ok, "null 应拒绝")
	_check(not Codec.normalize("save").ok, "字符串应拒绝")
	var bad_pets := _legacy_state()
	bad_pets.pets = ["dragon"]
	_check(not Codec.normalize(bad_pets).ok, "非对象宠物应拒绝")
	var bad_species := _legacy_state()
	bad_species.pets[0].species = "unknown"
	_check(not Codec.normalize(bad_species).ok, "未知 species 应拒绝")
	var bad_status := _legacy_state()
	bad_status.pets[0].health = 101
	_check(not Codec.normalize(bad_status).ok, "超界状态应拒绝")
	var nan_number := _legacy_state()
	nan_number.pets[0].exp = INF
	_check(not Codec.normalize(nan_number).ok, "非有限数值应拒绝")
	var future := _legacy_state()
	future.godot_save_version = 2
	_check(not Codec.normalize(future).ok, "未来 Godot 存档版本应拒绝")
	var invalid_html_version := _legacy_state()
	invalid_html_version.ver = 3
	_check(not Codec.normalize(invalid_html_version).ok, "未来 HTML 版本应拒绝")
	var fractional_version := _legacy_state()
	fractional_version.godot_save_version = 1.5
	_check(not Codec.normalize(fractional_version).ok, "小数 Godot 版本应拒绝")
	var fractional_active := _legacy_state()
	fractional_active.pets.append({"species": "goose", "level": 1})
	fractional_active.active = 0.5
	var active_result := Codec.normalize(fractional_active)
	_check(active_result.ok and active_result.state.active == 0 and typeof(active_result.state.active) == TYPE_INT, "分数 active 应截为整数再限界")
	for numeric_field in ["exp", "affinity"]:
		var negative := _legacy_state()
		negative.pets[0][numeric_field] = -1
		_check(not Codec.normalize(negative).ok, "负数 " + numeric_field + " 应拒绝")
	var catalog := Catalog.load_catalog()
	var catalog_default: Dictionary = catalog.get("default_state", {})
	_check(Codec.normalize(catalog_default).ok, "原始 catalog 默认存档应规范化")
	for species in ["dragon", "hoshino", "goose", "cat", "whale", "gpt", "claude", "gemini"]:
		var species_state: Dictionary = catalog_default.duplicate(true)
		species_state.pets[0].species = species
		_check(Codec.normalize(species_state).ok, "catalog 宠物种类应支持：" + species)
	var empty_pets := _legacy_state()
	empty_pets.pets = []
	empty_pets.grave = [{"species": "cat", "name": "咪咪", "level": 4}]
	_check(Codec.normalize(empty_pets).ok, "有墓碑记录的空宠物列表应兼容")
	var no_pet_no_grave := _legacy_state()
	no_pet_no_grave.pets = []
	no_pet_no_grave.grave = []
	_check(not Codec.normalize(no_pet_no_grave).ok, "无宠物且无墓碑应拒绝")

	var repo := Repository.new()
	repo.path = TEST_PATH
	_write(TEST_PATH, "{这不是 JSON")
	_write(TEST_PATH + ".bak", JSON.stringify(_legacy_state()))
	var recovered := repo.load_save()
	_check(recovered.ok and recovered.recovered_from_backup, "主档损坏时应从备份恢复并提示")
	var corrupt_before := _read(TEST_PATH)
	var rejected := repo.save_state({"pets": "bad"})
	_check(rejected != OK, "坏存档保存应返回错误")
	_check(not repo.last_error.is_empty(), "坏存档拒绝原因应写入 last_error")
	_check(_read(TEST_PATH) == corrupt_before, "拒绝坏存档不应覆盖主文件")
	_cleanup()
	var first_state := _legacy_state()
	first_state.coins = 111
	_check(repo.save_state(first_state) == OK, "首次写入应成功")
	var second_state := _legacy_state()
	second_state.coins = 222
	_check(repo.save_state(second_state) == OK, "再次写入应成功")
	var backup_state := repo._read_path(TEST_PATH + ".bak")
	_check(backup_state.ok and backup_state.state.coins == 111, "bak 应保留上一次有效主档")
	var preserved_backup := _read(TEST_PATH + ".bak")
	_write(TEST_PATH, "损坏主档原文")
	var recovery := repo.load_save()
	_check(recovery.ok and recovery.recovered_from_backup, "损坏主档应恢复 bak")
	var repaired_state := _legacy_state()
	repaired_state.coins = 333
	_check(repo.save_state(repaired_state) == OK, "从备份恢复后允许保存新主档")
	_check(_read(TEST_PATH + ".bak") == preserved_backup, "恢复后保存不能覆盖原有效 bak")
	var found_corrupt := false
	for entry in DirAccess.get_files_at(ProjectSettings.globalize_path(TEST_PATH.get_base_dir())):
		if entry.begins_with("save.json.corrupt."):
			found_corrupt = true
	_check(found_corrupt, "损坏主档原文应留在 .corrupt 旁档")
	_cleanup()
	var blocked_path := "res://.runtime/test_saves/blocked_save"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked_path))
	_write(blocked_path + ".bak", "保留的备份")
	var blocked_repo := Repository.new()
	blocked_repo.path = blocked_path
	_check(blocked_repo.save_state(_legacy_state()) != OK, "目标路径为目录时写入应返回错误")
	_check(_read(blocked_path + ".bak") == "保留的备份", "写入失败时不能丢失备份")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked_path + ".bak"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked_path))
	_cleanup()
	if failures == 0:
		print("存档测试通过")
	else:
		printerr("存档测试失败：%d 项" % failures)
	quit(0 if failures == 0 else 1)
