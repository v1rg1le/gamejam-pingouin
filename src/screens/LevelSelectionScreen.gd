extends Control

func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		var error = get_tree().change_scene("res://src/screens/MainScreen.tscn")
		if error != 0:
			print("ERROR: ", error)
