extends SceneTree

# 回归：道具使用栏的左右箭头必须永远贴在栏的两个端点。
# 过去中间内容没有裁切层，道具名一长就把右箭头挤出可视区域（表现为"两边箭头不见了"）。

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

	# 塞满背包：道具多、名字长 → 制造中间内容溢出
	var inv := {}
	for k in app.catalog.SHOP.keys():
		inv[str(k)] = 999
	app.state.inv = inv
	app.handle("page:shop")
	await process_frame
	await process_frame
	await process_frame

	var pages: Control = app.pages
	var bar: Control = pages.get("_usebar")
	var track: HBoxContainer = pages.get("_use_track")
	_check(bar != null and track != null, "商店页应创建道具使用栏")
	if bar == null or track == null:
		await _finish()
		return

	var kids := track.get_child_count()
	_check(kids >= 3, "使用栏应至少有 左箭头/中间层/右箭头 三段（实际 %d）" % kids)
	var left := track.get_child(0) as Button
	var right := track.get_child(kids - 1) as Button
	_check(left != null and left.text.unicode_at(0) == 8249, "第一个子节点应是左箭头 ‹")
	_check(right != null and right.text.unicode_at(0) == 8250, "最后一个子节点应是右箭头 ›")
	if left == null or right == null:
		await _finish()
		return

	var bar_left := bar.global_position.x
	var bar_right := bar.global_position.x + bar.size.x
	_check(absf(left.global_position.x - bar_left) <= 6.0,
		"左箭头应贴在栏左端（箭头 %.1f，栏左 %.1f）" % [left.global_position.x, bar_left])
	_check(absf(right.global_position.x + right.size.x - bar_right) <= 6.0,
		"右箭头应贴在栏右端（箭头右缘 %.1f，栏右缘 %.1f）" % [right.global_position.x + right.size.x, bar_right])
	_check(right.global_position.x + right.size.x <= bar_right + 0.5,
		"右箭头不应被挤出栏外（箭头右缘 %.1f > 栏右缘 %.1f）" % [right.global_position.x + right.size.x, bar_right])

	var mid: HBoxContainer = pages.get("_use_middle")
	_check(mid != null, "使用栏应有中间内容层")
	if mid != null:
		_check(mid.clip_contents, "中间内容层必须开启 clip_contents（否则长道具名会挤掉箭头）")
		_check(mid.size.x <= bar.size.x - 60.0 + 2.0,
			"中间层宽度不应超过「栏宽 - 两个箭头」（中间 %.1f，栏 %.1f）" % [mid.size.x, bar.size.x])

	# 翻页功能仍正常
	var left0 := (pages.get("_use_track") as HBoxContainer).get_child(0) as Button
	_check(left0.disabled, "第一页时左箭头应禁用")
	app.handle("useright")
	await process_frame
	await process_frame
	var left1 := (pages.get("_use_track") as HBoxContainer).get_child(0) as Button
	_check(left1 != null and not left1.disabled, "翻到第二页后左箭头应可点")

	await _finish()

func _finish() -> void:
	if failures == 0:
		print("道具使用栏箭头测试通过")
	if app != null:
		app.queue_free()
	await process_frame
	quit(failures)
