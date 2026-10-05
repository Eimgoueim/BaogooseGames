extends SceneTree

# 回归：道具栏只有一页时，不应摆一个按不动的死箭头；
# 多页时箭头要显示且能真的翻页（这就是玩家报的「按翻页键没反应」）。

const AppScene = preload("res://scenes/native_room.tscn")

var failures := 0
var app: Variant = null

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("失败：" + message)

func _arrows() -> Array:
	var out: Array = []
	var track = app.pages.get("_use_track")
	if track == null:
		return out
	var count := track.get_child_count()
	if count < 2:
		return out
	out.append(track.get_child(0))
	out.append(track.get_child(count - 1))
	return out

func _run() -> void:
	app = AppScene.instantiate()
	app.set("preview_mode", true)
	root.add_child(app)
	await process_frame
	await process_frame

	# 场景 A：只有两三种道具 → 只有一页
	app.state.inv = {"basic": 5, "can": 5, "snack": 5}
	app.handle("page:bag")
	app.refresh_ui()
	await process_frame
	await process_frame
	var keys_a: Array = app.pages.call("_bar_set").keys
	_check(keys_a.size() > 0 and keys_a.size() <= 10, "两三种道具应只有一页（实际 %d 种）" % keys_a.size())
	var aa := _arrows()
	_check(aa.size() == 2, "道具栏两端应有箭头按钮")
	if aa.size() == 2:
		var left: Button = aa[0]
		var right: Button = aa[1]
		_check(not left.visible and not right.visible, "只有一页时不应显示按不动的死箭头")

	# 场景 B：道具很多 → 多页，箭头显示且能翻页
	var inv := {}
	for k in app.catalog.SHOP.keys():
		inv[str(k)] = 5
	app.state.inv = inv
	app.refresh_ui()
	await process_frame
	await process_frame
	var bb := _arrows()
	_check(bb.size() == 2, "道具栏两端应有箭头按钮")
	if bb.size() == 2:
		var left2: Button = bb[0]
		var right2: Button = bb[1]
		_check(left2.visible and right2.visible, "道具多到多页时应显示左右箭头")
		_check(right2 != null and not right2.disabled, "多页时右箭头应可点")
		if right2 != null and not right2.disabled:
			right2.pressed.emit()
			await process_frame
			await process_frame
			var cc := _arrows()
			if cc.size() == 2:
				var left3: Button = cc[0]
				_check(left3 != null and not left3.disabled, "翻页后左箭头应变为可点（说明真的翻页了）")

	if failures == 0:
		print("道具栏翻页与箭头状态测试通过")
	if app != null:
		app.queue_free()
	await process_frame
	quit(failures)
