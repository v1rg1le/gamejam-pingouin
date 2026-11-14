extends Control

func _unhandled_input(event: InputEvent) -> void:
	# [MOBILE] un toucher d'écran compte aussi comme "appuyer sur une touche"
	# [ENTRÉES 1.14] même tri que l'écran titre (pas les touches de volume)
	if Settings.is_continue_press(event):
		if true:  # (bloc conservé tel quel : même indentation qu'avant)
			var error = get_tree().change_scene_to_file("res://src/screens/LevelSelectionScreen.tscn")
			if error != 0:
				print("ERROR: ", error)
