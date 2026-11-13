extends Control
# =============================================================================
#  LevelSelectionScreen.gd — écran de sélection des niveaux
# -----------------------------------------------------------------------------
#  [FINITION 13/11] nouvelle mise en page (l'ancienne scène est conservée dans
#  src/screens/archive/LevelSelectionScreen_v1.tscn) :
#   - titre en haut, panneau "COURSES" (niveaux avec arrivée, le tuto en
#     premier) et panneau "CHILL" (niveaux sans fin, avec l'étiquette CHILL
#     d'origine, dans le bon sens) ;
#   - navigation complète au clavier / à la manette : le tuto a le focus au
#     démarrage, flèches / stick pour se déplacer, Entrée / A pour lancer ;
#   - bouton "Retour" (utile sur mobile, où il n'y a pas de touche Échap) ;
#   - numéro de version lu dans les réglages du projet (application/config/version).
#  Les boutons de niveau restent des ChangeSceneButton : on ajoute un niveau
#  en dupliquant un bouton dans l'éditeur et en changeant next_scene_path.
# =============================================================================

@onready var first_button: Button = $Margin/VBox/Columns/RacesPanel/VBox/ButtonBateau
@onready var back_button: Button = $Margin/VBox/Bottom/BackButton
@onready var version_label: Label = $Margin/VBox/Bottom/VersionLabel


func _ready() -> void:
	version_label.text = "v" + str(ProjectSettings.get_setting("application/config/version", "?"))
	back_button.pressed.connect(_go_back)
	# Focus initial seulement si on joue au clavier / à la manette (en tactile,
	# le cadre jaune de focus serait inutile).
	if Settings.controls != Settings.TOUCH:
		first_button.grab_focus()
	# Si le joueur passe au clavier/manette en cours de route, on lui donne un focus
	Settings.controls_changed.connect(func(scheme):
		if scheme != Settings.TOUCH and get_viewport().gui_get_focus_owner() == null:
			first_button.grab_focus())


func _unhandled_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		_go_back()


func _go_back() -> void:
	var error = get_tree().change_scene_to_file("res://src/screens/MainScreen.tscn")
	if error != 0:
		print("ERROR: ", error)
