extends RefCounted
class_name SaveRepository

var path: String = "user://save.json"
var last_error: String = ""

func _save_failure(code: Error, message: String) -> Error:
	last_error = message
	return code

func _read_path(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {"ok": false, "state": {}, "error": "存档不存在：" + file_path}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "state": {}, "error": "无法读取存档：" + file_path + "（" + error_string(FileAccess.get_open_error()) + "）"}
	var content := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		return {"ok": false, "state": {}, "error": "读取存档失败：" + error_string(read_error)}
	var json := JSON.new()
	var parse_error := json.parse(content)
	if parse_error != OK:
		return {"ok": false, "state": {}, "error": "存档 JSON 损坏：" + json.get_error_message()}
	return StateCodec.normalize(json.data)

func load_save() -> Dictionary:
	if not FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			var backup := _read_path(path + ".bak")
			if backup.ok:
				backup.error = "主存档不存在，已从备份恢复"
				backup["recovered_from_backup"] = true
				return backup
		return {"ok": false, "state": {}, "error": "存档不存在"}
	var primary := _read_path(path)
	if primary.ok:
		primary["recovered_from_backup"] = false
		return primary
	var backup := _read_path(path + ".bak")
	if backup.ok:
		backup.error = "主存档无效，已从备份恢复（" + primary.error + "）"
		backup["recovered_from_backup"] = true
		return backup
	primary["recovered_from_backup"] = false
	primary.error += "；备份也不可用：" + backup.error
	return primary

func _ensure_parent_directory(file_path: String) -> Error:
	var absolute := ProjectSettings.globalize_path(file_path)
	var parent := absolute.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent):
		return DirAccess.make_dir_recursive_absolute(parent)
	return OK

func _unique_sidecar_path(base_path: String, suffix: String) -> String:
	var candidate := base_path + suffix + "." + str(Time.get_ticks_usec())
	var serial := 0
	while FileAccess.file_exists(candidate) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(candidate)):
		serial += 1
		candidate = base_path + suffix + "." + str(Time.get_ticks_usec()) + "." + str(serial)
	return candidate

func save_state(state: Dictionary) -> Error:
	last_error = ""
	var normalized := StateCodec.normalize(state)
	if not normalized.ok:
		return _save_failure(ERR_INVALID_DATA, "拒绝保存无效存档：" + normalized.error)
	var temp_path := path + ".tmp"
	var backup_path := path + ".bak"
	var dir_error := _ensure_parent_directory(path)
	if dir_error != OK:
		return _save_failure(dir_error, "无法创建存档目录：" + error_string(dir_error))
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		return _save_failure(open_error, "无法打开临时存档：" + error_string(open_error))
	file.store_string(JSON.stringify(normalized.state, "\t"))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return _save_failure(write_error, "写入临时存档失败：" + error_string(write_error))
	var verify := _read_path(temp_path)
	if not verify.ok:
		return _save_failure(ERR_FILE_CORRUPT, "临时存档校验失败：" + verify.error)
	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(path):
		var current := _read_path(path)
		if current.ok:
			var staged_backup := ""
			if FileAccess.file_exists(backup_path):
				staged_backup = _unique_sidecar_path(path, ".bak.previous")
				var stage_error := DirAccess.rename_absolute(absolute_backup, ProjectSettings.globalize_path(staged_backup))
				if stage_error != OK:
					return _save_failure(stage_error, "暂存旧备份失败：" + error_string(stage_error))
			var preserve_error := DirAccess.rename_absolute(absolute_path, absolute_backup)
			if preserve_error != OK:
				if not staged_backup.is_empty():
					DirAccess.rename_absolute(ProjectSettings.globalize_path(staged_backup), absolute_backup)
				return _save_failure(preserve_error, "保留上次有效主档失败：" + error_string(preserve_error))
			if not staged_backup.is_empty():
				DirAccess.remove_absolute(ProjectSettings.globalize_path(staged_backup))
		else:
			# 损坏主档单独留存，保留现有 .bak 的有效版本。
			var corrupt_path := _unique_sidecar_path(path, ".corrupt")
			var move_bad := DirAccess.rename_absolute(absolute_path, ProjectSettings.globalize_path(corrupt_path))
			if move_bad != OK:
				return _save_failure(move_bad, "保留损坏主档失败：" + error_string(move_bad))
	var replace := DirAccess.rename_absolute(absolute_temp, absolute_path)
	if replace != OK:
		return _save_failure(replace, "替换主存档失败：" + error_string(replace))
	return OK
