extends Control

func _ready():
	$TextureRect2/AnimatedSprite.playing = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton :
		if event.pressed:
			var error = get_tree().change_scene("res://src/levels/LevelTest2.tscn")
			if error != 0:
					print("ERROR: ", error)


func _on_TextureButton_button_up():
	var error = get_tree().change_scene("res://src/levels/LevelTest2.tscn")
	if error != 0:
		print("ERROR: ", error)
