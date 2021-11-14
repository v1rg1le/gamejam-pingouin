extends Control

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton :
		if event.pressed:
			var error = get_tree().change_scene("res://src/screens/LevelSelectionScreen.tscn")
			if error != 0:
				print("ERROR: ", error)
