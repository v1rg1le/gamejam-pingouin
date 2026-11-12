extends Control

func _unhandled_input(event: InputEvent) -> void:
	# [MOBILE] un toucher d'écran compte aussi comme "appuyer sur une touche"
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton or event is InputEventScreenTouch :
		if event.pressed:
			var error = get_tree().change_scene_to_file("res://src/screens/LevelSelectionScreen.tscn")
			if error != 0:
				print("ERROR: ", error)
