extends SceneTree

# 生成原生渲染结果供视觉审阅。需要图形驱动，不能使用 --headless。
const Scene = preload("res://scenes/parity_viewer.tscn")

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var native := "--ui" in OS.get_cmdline_user_args()
	var scene: Control = load("res://scenes/native_room.tscn").instantiate() if native else Scene.instantiate()
	if native: scene.set("preview_mode", true)
	root.add_child(scene)
	if native:
		scene.set_process(false)
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--action="): scene.handle(argument.trim_prefix("--action="))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		printerr("无法读取原生渲染结果，请使用可用图形驱动运行")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime"))
	var error := image.save_png("res://.runtime/native_ui.png" if native else "res://.runtime/parity_preview.png")
	print("原生画面导出：", error_string(error))
	quit(0 if error == OK else 1)
