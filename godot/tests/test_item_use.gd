extends SceneTree

# 回归：道具使用栏只应列出"能对宠物使用"的道具；
# 佩饰/家具/装饰不属于宠物道具（各有自己的页面），不该混进道具栏，
# 而且万一被调用也不能白消耗玩家的东西。

const AppScene = preload("res://scenes/native_room.tscn")

var failures := 0
var app: Variant = null

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("失败：" + message)

func _run() -> void:
	app = AppScene.instantiate()
	app.set("preview_mode", true)
	root.add_child(app)
	await process_frame
	await process_frame
	var inv := {}
	for k in app.catalog.SHOP.keys():
		inv[str(k)] = 5
	app.state.inv = inv
	app.handle("page:bag")
	await process_frame
	await process_frame

	var keys: Array = app.pages.call("_bar_set").keys
	_check(keys.size() > 0, "道具栏应有可用道具")
	var bad: Array[String] = []
	for k in keys:
		var item: Dictionary = app.catalog.SHOP[k]
		if item.has("wear") or item.has("furn") or item.has("deco"):
			bad.append(str(k))
	_check(bad.is_empty(), "道具栏不应出现佩饰/家具/装饰，实际混入：" + str(bad))
	for want in ["basic", "can", "soap", "potion"]:
		_check(keys.has(want), "「" + want + "」这类能给宠物用的道具应仍在道具栏")

	# 误用佩饰：不该消耗
	var before_crown := int(app.state.inv.get("crown", 0))
	app.handle("use:crown")
	await process_frame
	await process_frame
	_check(int(app.state.inv.get("crown", 0)) == before_crown,
		"误用佩饰不应消耗（%d -> %d）" % [before_crown, int(app.state.inv.get("crown", 0))])

	# 正常道具：照常消耗并生效
	var before_soap := int(app.state.inv.get("soap", 0))
	app.handle("use:soap")
	await process_frame
	await process_frame
	_check(int(app.state.inv.get("soap", 0)) == before_soap - 1,
		"正常道具应照常消耗（%d -> %d）" % [before_soap, int(app.state.inv.get("soap", 0))])

	if failures == 0:
		print("道具使用栏内容与误用保护测试通过")
	if app != null:
		app.queue_free()
	await process_frame
	quit(failures)
