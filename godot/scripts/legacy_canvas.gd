extends Control

const Commands = preload("res://scripts/pixel_commands.gd")

var commands: Array = []

func _draw() -> void:
	Commands.paint(self, commands)
