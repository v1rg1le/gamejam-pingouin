extends Control

# cache the scene tree node in a var
@onready var scene_tree: = get_tree()
@onready var pause_overlay: ColorRect = get_node("PauseOverlay")

var paused: = false: set = set_paused

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		self.paused = not paused  # self eplicite pour que GODOT utilise la fonction set_paused
		# [MIGRATION GODOT 4.7] SceneTree.set_input_as_handled() n'existe plus :
		# c'est maintenant le Viewport qui marque l'événement comme traité.
		get_viewport().set_input_as_handled()  # pour ne pas propager l'event dans les autres programmes

func set_paused(value: bool) -> void:
	paused = value
	scene_tree.paused = value
	pause_overlay.visible = value
	# [FINITION 13/11] navigation clavier / manette : le bouton "Resume" prend
	# le focus à l'ouverture de la pause (inutile en tactile).
	if value and Settings.controls != Settings.TOUCH:
		var resume = pause_overlay.get_node_or_null("VBoxContainer/ResumeButton")
		if resume != null:
			resume.grab_focus()
