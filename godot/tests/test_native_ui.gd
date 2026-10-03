extends SceneTree

const AppScene = preload("res://scenes/native_room.tscn")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("失败：" + message)

func _run() -> void:
	var app_script := load("res://scripts/native_room.gd") as GDScript
	_check(app_script != null and app_script.can_instantiate(), "native_room.gd 及其 UI 依赖必须能编译")
	if app_script == null or not app_script.can_instantiate():
		quit(1)
		return
	var app: Variant = AppScene.instantiate()
	_check(app != null, "原生主场景应能实例化")
	if app == null:
		quit(1)
		return
	_check(app.get_script() == app_script, "主场景节点应挂载 native_room.gd")
	if app.get_script() != app_script:
		quit(1)
		return
	app.set("preview_mode", true)
	root.add_child(app)
	await process_frame
	_check(app.get("state") is Dictionary, "启动后 state 应为字典")
	_check(app.get("hud") != null and app.get("pages") != null and app.get("modals") != null, "主场景应创建 HUD、页面和弹窗成员")
	if app.get("pages") == null or app.get("modals") == null:
		app.queue_free()
		await process_frame
		quit(1)
		return
	_check(app.page_key == "" and app.modal_key == "", "预览启动应无页面和弹窗")

	for key in ["shop", "bag", "wear", "room", "gacha", "points"]:
		app.handle("page:" + key)
		_check(app.page_key == key, "页面路由应打开 " + key)
		_check(app.modal_key == "", "打开页面时弹窗状态应关闭：" + key)
		var panel: Control = app.pages.get("_panel")
		var expected_panel: bool = key in ["shop", "gacha", "points"]
		_check((panel != null and panel.visible) == expected_panel, "原版 CSS 显示规则应匹配页面：" + key)
		if key == "points":
			var body: VBoxContainer = app.pages.get("_body")
			var point_shop: Dictionary = app.catalog.get("POINT_SHOP", {})
			_check(body != null and body.get_child_count() == point_shop.size() + 2, "积分兑换页应完整渲染所有商品")

	app.handle("themeopen")
	_check(app.page_key == "" and app.modal_key == "theme", "风格面板应关闭页面并设为 theme 弹窗")
	app.handle("theme:ocean")
	_check(app.state.get("theme", "") == "ocean", "选择深海蓝应更新 state.theme")
	var ocean_accent := str(app.modals.get_accent()).trim_prefix("#").to_lower()
	_check(ocean_accent.begins_with("2f6fd0"), "风格面板应加载深海蓝主色，而非空色值")
	app.handle("adoptopen")
	await process_frame
	await process_frame
	var adoption_body: VBoxContainer = app.modals.get("_body")
	var adoption_header := adoption_body.get_child(0) as HBoxContainer
	var adoption_hint := adoption_header.get_child(1) as Label
	_check(adoption_hint.size.x > 100 and adoption_hint.size.y < 100, "领养提示应按原版横向排版，不应被挤成单字竖排")
	var adoption_panel: Control = app.modals.get("_panel")
	_check(adoption_panel.size.x <= 581 and adoption_panel.size.y < 700, "领养卡片应保持原版宽度与列表限高")

	app.handle("savepanel")
	_check(app.page_key == "" and app.modal_key == "save", "存档面板应关闭页面并打开 save 弹窗")
	app.handle("saveclose")
	_check(app.modal_key == "", "关闭存档面板应清除弹窗状态")

	var pets: Array = app.state.get("pets", [])
	if not pets.is_empty():
		var second_pet: Dictionary = pets[0].duplicate(true)
		pets.append(second_pet)
		app.state.pets = pets
		app.handle("switch:1")
		_check(int(app.state.get("active", -1)) == 1, "switch:1 应切换到第二只宠物")
	else:
		_check(false, "预览状态应有宠物以验证切换")

	app.handle("rename")
	_check(app.page_key == "" and app.modal_key == "dialog", "改名操作应打开 dialog 弹窗")
	app.modals.get("_dialog_input").text = "包鹅"
	app.handle("dlgok")
	_check(app.active_pet().name == "包鹅" and app.modal_key == "", "改名确认应保存名称并关闭对话框")

	app.state.wear.crown = 1
	var star_slot: String = app.catalog.WEAR.crown.slot
	app.handle("wear:crown")
	_check(app.active_pet().worn.get(star_slot, "") == "crown", "已有佩饰应穿到原版部位")
	app.handle("wear:crown")
	_check(not app.active_pet().worn.has(star_slot), "再次点击同一佩饰应卸下")

	app.state.furnOwn.lamp = 1
	app.handle("sel:lamp")
	_check(app.state.edit and app.state.sel == "lamp" and app.state.placed.has("lamp"), "已有家具应进入原生摆放模式")
	app.handle("scl:0.25")
	_check(is_equal_approx(float(app.state.placed.lamp.s), 1.25), "家具应按原版增量缩放")
	var q: Dictionary = app.state.placed.lamp
	var at := Vector2(q.x * app.renderer.layout.width, q.y * app.renderer.layout.height)
	app.pointer_down(at + Vector2(0, -3))
	_check(app.drag.get("kind", "") == "furniture", "家具像素范围应响应原生鼠标命中")
	app.pointer_up()
	app.handle("furnback:lamp")
	_check(not app.state.placed.has("lamp") and app.state.furnOwn.lamp == 1, "收回家具应保留拥有权")
	app.close_panels()
	app.active_pet().ly = app.renderer.layout.ground
	app.redraw_room()
	app.pointer_down(app.renderer.pet_at(app.active_pet()) - Vector2(0, 10))
	_check(app.drag.get("kind", "") == "pet", "宠物应能被原生输入选中拖拽")
	app.active_pet().ly = 0.2
	app.pointer_up()
	_check(app.falling and app.drag.is_empty(), "高处释放宠物应进入原版掉落过程")
	for frame in 10:
		app._process(0.1)
		if not app.falling: break
	_check(not app.falling and is_equal_approx(float(app.active_pet().ly), app.renderer.layout.ground), "掉落应停在原版地面线")

	app.handle("savepanel")
	app.handle("saveexport")
	var exported: Dictionary = JSON.parse_string(app.modals.get_save_text())
	_check(exported.pets[1].name == "包鹅", "存档文本应导出当前原生状态")
	var before: Dictionary = app.state.duplicate(true)
	app.import_save("invalid json")
	_check(app.state == before, "损坏导入不能改变当前状态")
	exported.future_field = {"keep": [1, "unknown"]}
	app.import_save(JSON.stringify(exported))
	_check(app.state.future_field.keep[1] == "unknown" and float(app.state.future_field.keep[0]) == 1, "界面导入必须保留未迁移字段")
	app.repository.path = "res://.runtime/ui_save_%d.json" % Time.get_ticks_usec()
	_check(not app.save_state() and not FileAccess.file_exists(app.repository.path), "只读预览不得写入存档")
	app.preview_mode = false
	_check(app.save_state(), "普通模式应接入原生保存仓库")
	var loaded: Dictionary = app.repository.load_save()
	_check(loaded.ok and loaded.state.future_field.keep[1] == "unknown" and float(loaded.state.future_field.keep[0]) == 1, "界面保存应保留未知数据")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(app.repository.path))

	app.queue_free()
	await process_frame
	if failures == 0:
		print("原生 UI 路由测试通过")
	else:
		printerr("原生 UI 路由测试失败：%d 项" % failures)
	quit(0 if failures == 0 else 1)
