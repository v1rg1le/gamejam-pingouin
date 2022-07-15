extends Button

func _on_RestartButton_button_up():
	get_tree().paused = false
#	Score._reset()
	MusicController.play(MusicController.tracks[0])
	var error = get_tree().reload_current_scene()
	if error != 0:
		print("ERROR: ", error)

