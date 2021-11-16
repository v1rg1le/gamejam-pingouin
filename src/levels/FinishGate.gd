extends Node2D


func _on_Area2D_body_entered(_body):
	yield()
#	var error = get_tree().change_scene("res://src/screens/FinishedScreen.gd")
	var error = get_tree().change_scene("res://src/screens/LevelSelectionScreen.tscn")
	if error != 0:
		print("ERROR: ", error)
