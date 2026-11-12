@tool
extends Button

@export_file var next_scene_path: String = ""  # [MIGRATION] export(String, FILE) -> @export_file

func _on_PlayButton_button_up():
	get_tree().paused = false
	var error = get_tree().change_scene_to_file(next_scene_path)
	if error != 0:
		print("ERROR: ", error)
		
#	SceneChanger.goto_scene(next_scene_path, get_tree().current_scene)
		

# [MIGRATION GODOT 4.7] _get_configuration_warning() -> _get_configuration_warnings()
# qui renvoie maintenant une liste (PackedStringArray) au lieu d'un texte.
func _get_configuration_warnings() -> PackedStringArray:
	if next_scene_path == "":
		return PackedStringArray(["next_scene_path must be set for button to work"])
	return PackedStringArray()
