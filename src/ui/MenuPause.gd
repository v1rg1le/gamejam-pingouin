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
	# [TEST ENFANT 1.22] … et sur téléphone / tablette aussi : un enfant qui
	# tapote partout fermait l'appli dans plus d'une partie sur deux ! Sur
	# mobile on quitte une appli avec le geste « retour » / « accueil »
	# (iOS interdit même aux applis de se fermer toutes seules).
	if Settings.is_web or Settings.is_mobile_device:
		pause_overlay.get_node("VBoxContainer/QuitButton").visible = false
	# [MODE ENFANT 1.23] « Choisir un niveau » a « étirer en hauteur » dans sa
	# propre scène (ChangeSceneButton.tscn) : sans « Quitter le jeu » en
	# dessous, il prenait toute la place restante (bouton 2 fois trop haut).
	# Ici, il garde la même hauteur que les autres boutons.
	pause_overlay.get_node("VBoxContainer/ChangeSceneButton").size_flags_vertical = Control.SIZE_FILL
	# [TEST ENFANT 1.22] boutons « qui font perdre la partie » : il faut les
	# toucher DEUX fois (le 1er toucher affiche « Sûr ? Touche encore »).
	# Différé : en multi, « Choisir un niveau » est d'abord renommé plus bas.
	_setup_confirm_buttons.call_deferred()
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
	# [TEST ENFANT 1.22] on quitte la session réseau seulement quand le
	# départ est CONFIRMÉ (2e toucher), juste avant de partir vers le salon
	# (avant : dès l'appui, même si on ne confirmait pas).
	change_button.set_meta("before_confirm", NetSession.leave)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		self.paused = not paused  # self eplicite pour que GODOT utilise la fonction set_paused
		# [MIGRATION GODOT 4.7] SceneTree.set_input_as_handled() n'existe plus :
		# c'est maintenant le Viewport qui marque l'événement comme traité.
		get_viewport().set_input_as_handled()  # pour ne pas propager l'event dans les autres programmes

func set_paused(value: bool) -> void:
	paused = value
	_reset_confirm_buttons()   # [TEST ENFANT 1.22] on repart toujours de zéro
	scene_tree.paused = value and not NetSession.in_race   # [MULTI] pas de vraie pause en réseau
	pause_overlay.visible = value
	# [FINITION 13/11] navigation clavier / manette : le bouton "Resume" prend
	# le focus à l'ouverture de la pause (inutile en tactile).
	if value and Settings.controls != Settings.TOUCH:
		var resume = pause_overlay.get_node_or_null("VBoxContainer/ResumeButton")
		if resume != null:
			resume.grab_focus()


# --- [TEST ENFANT 1.22] Confirmation des boutons « dangereux » --------------
# Le « test enfant » (bot qui tapote l'écran au hasard) ouvrait souvent le
# menu pause puis touchait Recommencer / Choisir un niveau / Quitter le jeu
# sans le vouloir : partie perdue, voire appli fermée.
# Désormais ces boutons demandent un 2e toucher dans les 3 secondes :
#   1er toucher -> le texte devient « Sûr ? Touche encore » (en orange)
#   2e toucher  -> l'action d'origine (inchangée) est lancée
# Les scripts des boutons (QuitButton.gd, RestartButton.gd,
# ChangeSceneButton.gd) ne sont PAS modifiés : on débranche simplement leur
# signal « button_up » branché dans les .tscn et on le rebranche ici, derrière
# la confirmation. « Reprendre » reste immédiat.
const CONFIRM_DELAY := 3.0                 # secondes pour confirmer
const CONFIRM_TEXT := "Sûr ? Touche encore"
var _confirm_buttons := []                 # boutons protégés
var _confirm_armed: Button = null          # bouton qui attend son 2e toucher
var _confirm_time := 0.0                   # temps restant pour confirmer


func _setup_confirm_buttons() -> void:
	var box := pause_overlay.get_node("VBoxContainer")
	# nom du nœud -> méthode d'origine branchée dans le .tscn
	var guarded := {"RestartButton": "_on_RestartButton_button_up",
		"ChangeSceneButton": "_on_PlayButton_button_up",
		"QuitButton": "_on_QuitButton_button_up"}
	for node_name in guarded:
		var b: Button = box.get_node_or_null(node_name)
		if b == null:
			continue
		var original := Callable(b, guarded[node_name])
		if b.button_up.is_connected(original):
			b.button_up.disconnect(original)
		b.set_meta("original_text", b.text)
		b.button_up.connect(_on_guarded_button_up.bind(b, original))
		_confirm_buttons.append(b)


func _on_guarded_button_up(b: Button, original: Callable) -> void:
	if _confirm_armed != b:
		# 1er toucher : on demande confirmation (un seul bouton armé à la fois)
		_reset_confirm_buttons()
		_confirm_armed = b
		_confirm_time = CONFIRM_DELAY
		b.text = CONFIRM_TEXT
		b.add_theme_color_override("font_color", Color(1, 0.6, 0.2))
		b.add_theme_color_override("font_hover_color", Color(1, 0.6, 0.2))
		return
	# 2e toucher dans les temps : action d'origine
	_reset_confirm_buttons()
	if b.has_meta("before_confirm"):
		b.get_meta("before_confirm").call()   # ex. quitter la session réseau
	original.call()


func _reset_confirm_buttons() -> void:
	_confirm_armed = null
	for b in _confirm_buttons:
		if is_instance_valid(b):
			b.text = b.get_meta("original_text")
			b.remove_theme_color_override("font_color")
			b.remove_theme_color_override("font_hover_color")


# Le menu pause tourne pendant la pause (process_mode du nœud) : on compte le
# délai de confirmation avec le temps réel du jeu en pause.
func _process(delta: float) -> void:
	if _confirm_armed == null:
		return
	_confirm_time -= delta
	if _confirm_time <= 0.0:
		_reset_confirm_buttons()
