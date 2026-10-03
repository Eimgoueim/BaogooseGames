class_name PixelCommands
extends RefCounted

# 回放原 Canvas 的矩形，保留绘制顺序、透明度与变换后的坐标。
# 不生成替代美术、不使用抗锯齿，也不将像素画重新描边。
static func paint(target: CanvasItem, commands: Array) -> void:
	for command: Array in commands:
		var rectangle := Rect2(float(command[0]), float(command[1]), float(command[2]), float(command[3]))
		var color := Color(float(command[4]), float(command[5]), float(command[6]), float(command[7]))
		target.draw_rect(rectangle, color, true)
