extends SceneTree

const AppScene = preload("res://scenes/native_room.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("失败：" + message)

func _settle() -> void:
	for index in 6: await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func _check_scale(app: Control) -> void:
	var expected := maxf(1.0, minf(root.size.x / 1120.0, root.size.y / 960.0))
	var actual := root.get_stretch_transform().get_scale()
	_check(absf(actual.x - expected) < 0.01 and absf(actual.y - expected) < 0.01, "字体与控件应等比缩放：%s，实际 %s" % [root.size, actual])
	_check((app.size * expected - Vector2(root.size)).length() < 3, "界面应填满窗口，不能拉伸变形或出现黑边")
	for label: Label in app.find_children("*", "Label", true, false):
		_check(label.get_theme_font_size("font_size") >= 14, "UI 文字不能退回难以阅读的小字号：" + label.text)
	var slots: GridContainer = app.hud.get("_slots")
	_check(slots.get_global_rect().end.x <= app.size.x + 1, "加大字体后宠物栏不能溢出右边界")
	print("UI 尺寸：", root.size, "，逻辑尺寸：", app.size, "，缩放：", actual)

func _run() -> void:
	var app: Variant = AppScene.instantiate()
	app.preview_mode = true
	root.add_child(app)
	app.set_process(false)
	app.handle("rename")
	var input: LineEdit = app.modals.get("_dialog_input")
	input.text = "全屏适配"
	for dimensions in [Vector2i(1120, 960), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440), Vector2i(480, 720), Vector2i(1120, 960)]:
		root.size = dimensions
		await _settle()
		_check_scale(app)
		_check(app.modals.get("_dialog_input") == input and input.text == "全屏适配", "尺寸改变不能重建改名输入框或丢失输入")
		var panel: Control = app.modals.get("_panel")
		_check(panel.get_global_rect().position.x >= -1 and panel.get_global_rect().end.x <= app.size.x + 1, "弹窗不能超出视口")
	app.handle("dlgok")
	for action in ["adoptopen", "themeopen", "savepanel"]:
		app.handle(action)
		await _settle()
		var panel: Control = app.modals.get("_panel")
		var editor: TextEdit = app.modals.input_text
		if is_instance_valid(editor): editor.text = "保留未提交的存档输入"
		for dimensions in [Vector2i(480, 720), Vector2i(2560, 1440)]:
			root.size = dimensions
			await _settle()
			var bounds := panel.get_global_rect()
			_check(bounds.position.x >= -1 and bounds.end.x <= app.size.x + 1 and bounds.position.y >= -1 and bounds.end.y <= app.size.y + 1, action + " 调整窗口后应完整可见")
			if is_instance_valid(editor):
				_check(app.modals.input_text == editor and editor.text == "保留未提交的存档输入", "存档输入应保留")
	app.state.coins = 1000
	app.handle("pull:10")
	await _settle()
	var stage: Control = app.results_ui.stage
	var generation: int = app.results_ui.generation
	root.size = Vector2i(480, 720)
	await _settle()
	_check(app.results_ui.stage == stage and app.results_ui.generation == generation, "窗口切换不能重启抽卡动画")
	_check(app.results_ui.results_grid.columns == 3, "窄窗口抽卡结果应使用三列")
	var roll_bounds: Rect2 = app.results_ui.panel.get_global_rect()
	_check(roll_bounds.position.x >= -1 and roll_bounds.end.x <= app.size.x + 1, "抽卡动画面板应适配窄窗口")
	app.results_ui.reveal()
	await _settle()
	root.size = Vector2i(2560, 1440)
	await _settle()
	_check(not app.results_ui.rolling and app.results_ui.results_grid.columns == 5, "放大窗口应保留揭晓状态并恢复五列")
	app.handle("gachaclose")
	app.handle("games")
	app.dungeon.set_process(false)
	root.size = Vector2i(1920, 1080)
	await _settle()
	_check_scale(app)
	if DisplayServer.get_name() != "headless":
		# 使用窗口像素坐标点击缩放后的退出按钮，验证输入映射没有偏移。
		var exit_rect: Rect2 = app.dungeon.get("_exit_rect")
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = root.get_final_transform() * exit_rect.get_center()
		root.push_input(click, false)
		await _settle()
		_check(not app.dungeon.visible, "缩放后点击退出地牢应命中按钮")
		root.mode = Window.MODE_FULLSCREEN
		await _settle()
		_check_scale(app)
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1120, 960)
		await _settle()
		_check_scale(app)
	print("UI 缩放及窗口切换验证通过" if failures == 0 else "UI 缩放验证失败：%d" % failures)
	quit(0 if failures == 0 else 1)
