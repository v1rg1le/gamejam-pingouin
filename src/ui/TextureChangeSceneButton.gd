tool
extends TextureButton

export(String, FILE) var next_scene_path: = ""

func _on_PlayButton_button_up():
	get_tree().paused = false
	var error = get_tree().change_scene(next_scene_path)
	if error != 0:
		print("ERROR: ", error)
		
#	SceneChanger.goto_scene(next_scene_path, get_tree().current_scene)
		

func _get_configuration_warning() -> String:
	return "next_scene_path must be set for button to work" if next_scene_path == "" else ""
