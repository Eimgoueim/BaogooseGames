extends SceneTree

# 回归：道具栏的按钮必须跨帧存活。
# 真人点击 = 按下（帧 A）→ 抬起（帧 B）。如果道具栏每帧重建按钮，抬起时按钮
# 已经被 queue_free，pressed 不触发 → "点道具没反应 / 不能用其它道具"。
# 本测试断言：连续多帧刷新后，按钮仍是同一批实例，并且按下信号仍然有效。

const AppScene = preload("res://scenes/native_room.tscn")

var failures := 0
var app: Variant = null

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("失败：" + message)

func _inv_total() -> int:
	var total := 0
	for k in app.state.inv.keys():
		total += int(app.state.inv[k])
	return total

func _mid_buttons() -> Array:
	var out: Array = []
	var mid = app.pages.get("_use_middle")
	if mid == null:
		return out
	for c in mid.get_children():
		if c is Button:
			out.append(c)
	return out

func _run() -> void:
	app = AppScene.instantiate()
	app.set("preview_mode", true)
	root.add_child(app)
	await process_frame
	await process_frame
	var inv := {}
	for k in app.catalog.SHOP.keys():
		inv[str(k)] = 999
	app.state.inv = inv
	app.handle("page:bag")
	await process_frame
	await process_frame
	await process_frame

	var mid: Control = app.pages.get("_use_middle")
	var track: HBoxContainer = app.pages.get("_use_track")
	_check(mid != null and track != null, "背包页应创建道具栏")
	if mid == null or track == null:
		await _finish()
		return

	var chips := _mid_buttons()
	_check(chips.size() > 0, "道具栏应有道具按钮")
	if chips.is_empty():
		await _finish()
		return
	var chip: Button = chips[0]
	var chip_id := chip.get_instance_id()
	var left_arrow: Button = track.get_child(0) as Button
	var right_arrow: Button = track.get_child(track.get_child_count() - 1) as Button
	var left_id := left_arrow.get_instance_id() if left_arrow != null else 0
	var right_id := right_arrow.get_instance_id() if right_arrow != null else 0

	# 模拟真人停留：连续 40 帧刷新 UI
	for _i in 40:
		app.refresh_ui()
		await process_frame
	var chips2 := _mid_buttons()
	var still_same: bool = chips2.size() > 0 and chips2[0].get_instance_id() == chip_id
	_check(still_same, "道具按钮应跨帧存活（40 帧后实例 id 变了 → 每帧重建 → 点击会被丢掉）")
	var track2: HBoxContainer = app.pages.get("_use_track")
	var la := track2.get_child(0) as Button
	var ra := track2.get_child(track2.get_child_count() - 1) as Button
	_check(la != null and la.get_instance_id() == left_id, "左箭头应跨帧存活")
	_check(ra != null and ra.get_instance_id() == right_id, "右箭头应跨帧存活")

	# 存活的按钮上按下信号仍然有效（真人点击最终就是走到这里）
	if still_same:
		var before := _inv_total()
		var label: String = str(chips2[0].text)
		chips2[0].pressed.emit()
		await process_frame
		await process_frame
		var after := _inv_total()
		_check(after == before - 1, "按钮按下应消耗 1 个道具（%d → %d，按钮 '%s'）" % [before, after, label])

	# 翻页后内容确实换了（并且按钮仍是存活实例）
	if ra != null and not ra.disabled:
		ra.pressed.emit()
		await process_frame
		await process_frame
		var chips3 := _mid_buttons()
		_check(chips3.size() > 0, "翻页后道具栏仍应有内容")
		var changed: bool = str(chips3[0].text) != str(chips[0].text)
		_check(changed, "翻到第二页后第一个道具应变化（仍是 '%s' → 翻页没生效）" % chips3[0].text)

	await _finish()

func _finish() -> void:
	if failures == 0:
		print("道具栏点击可用性测试通过")
	if app != null:
		app.queue_free()
	await process_frame
	quit(failures)
