extends SceneTree

# 需要原生图形驱动；以原版 Canvas 指令合成的像素采样为对照。
const Catalog = preload("res://scripts/legacy_catalog.gd")
const Canvas = preload("res://scripts/legacy_canvas.gd")

func _initialize() -> void:
	call_deferred("verify_pixels")

func verify_pixels() -> void:
	var fixtures := Catalog.read_json("res://data/visual_fixtures.json")
	var failures := 0
	var samples_checked := 0
	for fixture_name: String in fixtures:
		var fixture: Dictionary = fixtures[fixture_name]
		var viewport := SubViewport.new()
		viewport.size = Vector2i(int(fixture.width), int(fixture.height))
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var canvas := Canvas.new()
		canvas.commands = fixture.commands
		viewport.add_child(canvas)
		await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image == null or image.is_empty():
			printerr("无法读取图形驱动的渲染结果")
			quit(1)
			return
		for sample: Array in fixture.samples:
			var actual := image.get_pixel(int(sample[0]), int(sample[1]))
			var expected := Color(float(sample[2]) / 255.0, float(sample[3]) / 255.0, float(sample[4]) / 255.0)
			samples_checked += 1
			# 浏览器与 GPU 的透明混合舍入可相差 1 到 2 个色阶。
			if absf(actual.r - expected.r) > 2.1 / 255.0 or absf(actual.g - expected.g) > 2.1 / 255.0 or absf(actual.b - expected.b) > 2.1 / 255.0:
				if failures < 5:
					printerr("像素不一致：", fixture_name, " ", sample, " actual=", actual)
				failures += 1
		viewport.queue_free()
		await process_frame
	if failures == 0:
		print("25 个原生视觉基准、", samples_checked, " 个像素采样验证通过")
	else:
		printerr("像素验证失败：", failures)
	quit(0 if failures == 0 else 1)
