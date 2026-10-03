class_name LegacyCatalog
extends RefCounted

# 配置从原 HTML 提取；迁移中不另写一套数值。
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("缺少迁移数据：" + path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("迁移数据不是 JSON 对象：" + path)
		return {}
	return parsed

static func load_catalog() -> Dictionary:
	return read_json("res://data/catalog.json")
