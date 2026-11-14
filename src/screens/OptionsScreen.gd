extends Control
# =============================================================================
#  OptionsScreen.gd — [OPTIONS 1.7] écran des réglages
# -----------------------------------------------------------------------------
#  Ouvert depuis la sélection des niveaux (bouton "Options").
#  Colonne gauche "AIDE ET SON" (tout est mémorisé dans user://pinpouin.cfg) :
#   - Aide en début de niveau : carte des commandes + du score, jeu en pause
#     au départ de chaque niveau (Settings.help_on_start) ;
#   - Pause pour lire les panneaux du tuto (Settings.tutorial_pause) ;
#   - Courir contre mon fantôme (RaceManager.ghost_enabled, même réglage que
#     l'interrupteur du menu des niveaux) ;
#   - Volume de la musique (Settings.music_volume) ;
#   - [PHYSIQUE 1.10] Panneau de réglage physique : bouton ⚙ en jeu en mode
#     tactile (au clavier, F2 ouvre le panneau dans tous les cas).
#  Colonne droite "ÉCHANGER DES FANTÔMES" (marche aussi sur téléphone) :
#   - une ligne par course où l'on a un record : bouton "Copier" -> le
#     fantôme est mis dans le presse-papiers sous forme de texte, à envoyer
#     par message à un ami ;
#   - "Coller le fantôme d'un ami" : lit le presse-papiers et ajoute le
#     fantôme (RaceManager.import_ghost_text) ;
#   - "Dossier des fantômes" (PC seulement) : comme dans le menu des niveaux.
# =============================================================================

# Courses qui peuvent avoir un fantôme (mêmes niveaux que le menu "COURSES")
const RACES = [
	["Tuto : Bateau", "res://src/levels/LevelBateau.tscn"],
	["Flat and fun", "res://src/levels/LevelRandomFlat.tscn"],
	["Corridor", "res://src/levels/LevelRandomCorridor.tscn"],
	["Nice Slope", "res://src/levels/LevelRandomNiceSlope.tscn"],
	["Hook, you fool !", "res://src/levels/LevelRandomGap.tscn"],
	["Spaghetti", "res://src/levels/LevelRandomSpaghetti.tscn"],
]

@onready var help_on_start: CheckButton = $Margin/VBox/Columns/GamePanel/VBox/HelpOnStart
@onready var tutorial_pause: CheckButton = $Margin/VBox/Columns/GamePanel/VBox/TutorialPause
@onready var ghost_enabled: CheckButton = $Margin/VBox/Columns/GamePanel/VBox/GhostEnabled
@onready var physics_panel: CheckButton = $Margin/VBox/Columns/GamePanel/VBox/PhysicsPanel   # [PHYSIQUE 1.10]
@onready var music_slider: HSlider = $Margin/VBox/Columns/GamePanel/VBox/MusicSlider
@onready var ghost_list: VBoxContainer = $Margin/VBox/Columns/GhostPanel/VBox/GhostList
@onready var paste_button: Button = $Margin/VBox/Columns/GhostPanel/VBox/PasteButton
@onready var folder_button: Button = $Margin/VBox/Columns/GhostPanel/VBox/FolderButton
@onready var status_label: Label = $Margin/VBox/StatusLabel
@onready var back_button: Button = $Margin/VBox/Bottom/BackButton
@onready var version_label: Label = $Margin/VBox/Bottom/VersionLabel


func _ready() -> void:
	version_label.text = "v" + str(ProjectSettings.get_setting("application/config/version", "?"))
	# --- Aide et son
	help_on_start.button_pressed = Settings.help_on_start
	help_on_start.toggled.connect(func(v): Settings.set_option("help_on_start", v))
	tutorial_pause.button_pressed = Settings.tutorial_pause
	tutorial_pause.toggled.connect(func(v): Settings.set_option("tutorial_pause", v))
	ghost_enabled.button_pressed = RaceManager.ghost_enabled
	ghost_enabled.toggled.connect(RaceManager.set_ghost_enabled)
	# [PHYSIQUE 1.10] affiche le bouton ⚙ en jeu (tactile) ; F2 marche toujours au clavier
	physics_panel.button_pressed = Settings.physics_panel
	physics_panel.toggled.connect(func(v): Settings.set_option("physics_panel", v))
	music_slider.value = Settings.music_volume
	music_slider.value_changed.connect(func(v): Settings.set_option("music_volume", v))
	# --- Fantômes
	_fill_ghost_list()
	paste_button.pressed.connect(_on_paste)
	folder_button.visible = not Settings.is_mobile_device
	folder_button.pressed.connect(func():
		OS.shell_open(ProjectSettings.globalize_path(RaceManager.GHOST_DIR)))
	back_button.pressed.connect(_go_back)
	if Settings.controls != Settings.TOUCH:
		help_on_start.grab_focus()


func _fill_ghost_list() -> void:
	for c in ghost_list.get_children():
		c.queue_free()
	var n := 0
	for race in RACES:
		var best: float = RaceManager.get_best_time(race[1])
		if best < 0.0:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := Label.new()
		l.text = "%s   %s" % [race[0], RaceManager.format_time(best)]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 17)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		var b := Button.new()
		b.text = "Copier"
		b.custom_minimum_size = Vector2(100, 38)
		b.pressed.connect(_on_copy.bind(race[1], race[0]))
		row.add_child(l)
		row.add_child(b)
		ghost_list.add_child(row)
		n += 1
	if n == 0:
		var l := Label.new()
		l.text = "Pas encore de record : termine une course !"
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
		ghost_list.add_child(l)


func _on_copy(level_path: String, race_name: String) -> void:
	var text := RaceManager.export_ghost_text(level_path)
	if text == "":
		status_label.text = "Pas de fantôme pour cette course."
		return
	DisplayServer.clipboard_set(text)
	status_label.text = "Fantôme « %s » copié (%d Ko de texte) : colle-le dans un message pour ton ami." % [race_name, ceili(text.length() / 1024.0)]


func _on_paste() -> void:
	var text := DisplayServer.clipboard_get()
	if text.strip_edges() == "":
		status_label.text = "Le presse-papiers est vide : copie d'abord le message de ton ami."
		return
	status_label.text = RaceManager.import_ghost_text(text)
	_fill_ghost_list()


func _unhandled_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		_go_back()


func _go_back() -> void:
	get_tree().change_scene_to_file("res://src/screens/LevelSelectionScreen.tscn")
