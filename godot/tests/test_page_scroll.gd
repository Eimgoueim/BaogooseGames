extends SceneTree

# 回归：商店/抽卡/积分这类浮动页面每帧都会被 refresh_ui() 刷新，
# 过去 _rebuild() 会重建整个 ScrollContainer，导致滚动位置跳回顶部。
# 断言：连续刷新 UI、以及内容变化触发重建之后，滚动位置都必须保持。

const AppScene = preload("res://scenes/native_room.tscn")

var failures := 0
var app: Variant = null

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("失败：" + message)

func _scroll() -> ScrollContainer:
	if app == null or app.pages == null:
		return null
	return app.pages.get("_scroll") as ScrollContainer

func _run() -> void:
	app = AppScene.instantiate()
	if app == null:
		printerr("失败：主场景应能实例化")
		quit(1)
		return
	app.set("preview_mode", true)
	root.add_child(app)
	await process_frame
	await process_frame

	app.handle("page:shop")
	await process_frame
	await process_frame
	var sc := _scroll()
	_check(sc != null, "商店页应创建可滚动的 ScrollContainer")
	if sc == null:
		await _finish()
		return

	sc.scroll_vertical = 160
	await process_frame
	sc = _scroll()
	var moved := 0 if sc == null else sc.scroll_vertical
	_check(moved > 0, "商店页内容应可滚动（滚动到 %d）" % moved)
	if moved <= 0:
		await _finish()
		return

	# ① 连续刷新（旧实现在这里每帧把滚动重置为 0）
	var bad := 0
	for _i in 30:
		app.refresh_ui()
		await process_frame
		sc = _scroll()
		if sc == null or sc.scroll_vertical != moved:
			bad += 1
	_check(bad == 0, "连续 30 帧刷新后滚动位置应保持（异常帧 %d 帧）" % bad)

	# ② 内容真的变化（金币变动 → 必须重建）后也要保持
	bad = 0
	app.state.coins = int(app.state.get("coins", 0)) + 1
	for _i in 6:
		app.refresh_ui()
		await process_frame
		sc = _scroll()
		if sc == null or sc.scroll_vertical != moved:
			bad += 1
	_check(bad == 0, "内容变化重建后滚动位置应保持（异常帧 %d 帧）" % bad)

	await _finish()

func _finish() -> void:
	if failures == 0:
		print("商店页滚动位置保持测试通过")
	if app != null:
		app.queue_free()
	await process_frame
	quit(failures)
