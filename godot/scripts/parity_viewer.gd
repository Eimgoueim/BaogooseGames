extends Control

const Catalog = preload("res://scripts/legacy_catalog.gd")
const Codec = preload("res://scripts/state_codec.gd")
const Canvas = preload("res://scripts/legacy_canvas.gd")

var fixture: Dictionary = {}
var imported_state: Dictionary = {}

func _ready() -> void:
	var requested := "theme_sakura"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture="):
			requested = argument.trim_prefix("--fixture=")
		elif argument.begins_with("--save="):
			var path := argument.trim_prefix("--save=")
			if not FileAccess.file_exists(path):
				push_error("找不到旧版存档：" + path)
				get_tree().quit(1)
				return
			var result: Dictionary = Codec.normalize(JSON.parse_string(FileAccess.get_file_as_string(path)))
			if not result.ok:
				push_error(result.error)
				get_tree().quit(1)
				return
			imported_state = result.state
	var fixtures := Catalog.read_json("res://data/visual_fixtures.json")
	if not fixtures.has(requested):
		push_error("未知视觉基准：" + requested)
		get_tree().quit(1)
		return
	fixture = fixtures[requested]
	# 原 Canvas 先在逻辑分辨率栅格化，再以最近邻放大；避免重新缩放矩形改变像素边缘。
	var viewport := SubViewport.new()
	viewport.size = Vector2i(int(fixture.width), int(fixture.height))
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var canvas := Canvas.new()
	canvas.commands = fixture.commands
	viewport.add_child(canvas)
	var presentation := TextureRect.new()
	presentation.texture = viewport.get_texture()
	presentation.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	presentation.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	presentation.stretch_mode = TextureRect.STRETCH_SCALE
	presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(presentation)
	presentation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	print("Godot 原版 Canvas 视觉基准：", requested, "；DOM 面板和游戏交互仍在迁移中。")
	if not imported_state.is_empty():
		print("已只读校验旧版存档，宠物数量：", imported_state.pets.size(), "；全部未迁移字段保留。")
