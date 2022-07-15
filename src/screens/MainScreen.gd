extends Control

onready var pic1 = get_node("TextureRectAnim")
onready var pic2 = get_node("TextureRectAnim2")
onready var pic3 = get_node("TextureRectAnim3")

func _ready():
	pass

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton :
		if event.pressed:
			var error = get_tree().change_scene("res://src/screens/LevelSelectionScreen.tscn")
			if error != 0:
					print("ERROR: ", error)


func _on_TextureButton_button_up():
	var error = get_tree().change_scene("res://src/screens/LevelSelectionScreen.tscn")
	if error != 0:
		print("ERROR: ", error)


func do_fucking_animation_pinpouin():
	# de l'importance de faire les dessins dans la meme resolution
	# @Lory-Ann Lehmann
	if pic1.visible:
		pic1.visible = false
		pic2.visible = true
	elif pic2.visible:
		pic2.visible = false
		pic3.visible = true
	elif pic3.visible:
		pic3.visible = false
		pic1.visible = true

func _on_AnimationTimer_timeout():
	do_fucking_animation_pinpouin()
