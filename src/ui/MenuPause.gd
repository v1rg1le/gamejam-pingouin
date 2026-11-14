extends Control

# cache the scene tree node in a var
@onready var scene_tree: = get_tree()
@onready var pause_overlay: ColorRect = get_node("PauseOverlay")

var paused: = false: set = set_paused


# [MULTI] (étape 6) en course réseau, le menu pause s'adapte :
#  - le jeu n'est PAS mis en pause (les autres continuent de courir, et notre
#    chrono doit rester juste) : le menu s'affiche simplement par-dessus ;
#  - "Recommencer" est masqué (le pingouin réapparaît déjà tout seul après
#    une chute, et recharger le niveau désynchroniserait la course) ;
#  - "Choisir un niveau" devient "Quitter la course" : on quitte la partie
#    réseau et on revient au salon multijoueur.
func _ready() -> void:
	# [WEB 1.17] dans le navigateur, « Quitter le jeu » ne peut rien fermer : masqué
	if Settings.is_web:
		pause_overlay.get_node("VBoxContainer/QuitButton").visible = false
	# [RESPONSIVE 1.14] le calque « UserInterface » (parent du menu pause) est
	# agrandi sur les petits écrans (voir UiScaler.gd). Différé : on ne
	# déplace pas un nœud pendant son propre _ready().
	if get_parent() is CanvasLayer:
		UiScaler.apply.call_deferred(get_parent())
	if not NetSession.in_race:
		return
	var box := pause_overlay.get_node("VBoxContainer")
	box.get_node("RestartButton").visible = false
	var change_button = box.get_node("ChangeSceneButton")
	change_button.text = "Quitter la course"
	change_button.next_scene_path = NetSession.LOBBY_SCENE
	# button_down arrive avant button_up (qui change de scène) : on quitte
	# la session réseau juste avant de partir vers le salon.
	change_button.button_down.connect(NetSession.leave)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		self.paused = not paused  # self eplicite pour que GODOT utilise la fonction set_paused
		# [MIGRATION GODOT 4.7] SceneTree.set_input_as_handled() n'existe plus :
		# c'est maintenant le Viewport qui marque l'événement comme traité.
		get_viewport().set_input_as_handled()  # pour ne pas propager l'event dans les autres programmes

func set_paused(value: bool) -> void:
	paused = value
	scene_tree.paused = value and not NetSession.in_race   # [MULTI] pas de vraie pause en réseau
	pause_overlay.visible = value
	# [FINITION 13/11] navigation clavier / manette : le bouton "Resume" prend
	# le focus à l'ouverture de la pause (inutile en tactile).
	if value and Settings.controls != Settings.TOUCH:
		var resume = pause_overlay.get_node_or_null("VBoxContainer/ResumeButton")
		if resume != null:
			resume.grab_focus()
