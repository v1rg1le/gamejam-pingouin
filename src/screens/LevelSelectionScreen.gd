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
#  [FANTÔMES] (étape 5) :
#   - le record de chaque course est affiché sur son bouton ;
#   - interrupteur "Courir contre mon fantôme" (mémorisé entre les parties) ;
#   - sur PC, bouton "Dossier des fantômes" : ouvre le dossier où sont rangés
#     les fichiers .ghost (pour en envoyer un à un ami, ou déposer le sien).
#  [OPTIONS 1.7] bouton "Options" -> src/screens/OptionsScreen.tscn
#  [MULTI] (étape 6) bouton "Multijoueur" -> salon réseau local
#   (src/screens/MultiplayerLobby.tscn).
#  [MENU UNIQUE 1.37] demande de Manu : plus de panneau « CHILL » à droite.
#   Tous les niveaux sont dans le panneau COURSES, rangés sur deux colonnes
#   (nœud « Grid », un GridContainer) pour que la liste tienne sur un écran de
#   téléphone sans tout rétrécir. Le choix Chill / Score s'applique à tous.
#   - 704, 917 et Half-pipe n'ont pas d'arrivée : ils restent en glisse libre
#     dans les deux modes (RaceManager les traite déjà ainsi) ; en Score, leur
#     bouton l'indique (« · glisse libre »).
#   - « ∞ Sans fin ∞ » suit le mode (Chill = sans vies, Score = vies + mètres) :
#     l'ancien bouton « Sans fin » du panneau CHILL faisait doublon.
#   - L'ancien panneau CHILL n'est pas supprimé, seulement masqué (visible =
#     false dans la scène) : son étiquette CHILL d'origine et le bouton vers
#     LevelEndlessChill.tscn y restent, prêts à resservir.
#  Les boutons de niveau restent des ChangeSceneButton : on ajoute un niveau
#  en dupliquant un bouton de « Grid » dans l'éditeur et en changeant
#  next_scene_path.
# =============================================================================

@onready var first_button: Button = $Margin/VBox/Columns/RacesPanel/VBox/Grid/ButtonBateau   # [MENU UNIQUE 1.37] boutons dans « Grid »
@onready var back_button: Button = $Margin/VBox/Bottom/BackButton
@onready var version_label: Label = $Margin/VBox/Bottom/VersionLabel
@onready var ghost_toggle: CheckButton = $Margin/VBox/Bottom/GhostToggle
@onready var ghost_folder_button: Button = $Margin/VBox/Bottom/GhostFolderButton
@onready var multi_button: Button = $Margin/VBox/Bottom/MultiButton   # [MULTI]
@onready var options_button: Button = $Margin/VBox/Bottom/OptionsButton   # [OPTIONS 1.7]
@onready var races_box: VBoxContainer = $Margin/VBox/Columns/RacesPanel/VBox
@onready var races_grid: GridContainer = $Margin/VBox/Columns/RacesPanel/VBox/Grid   # [MENU UNIQUE 1.37]

## [MENU UNIQUE 1.37] Niveaux sans ligne d'arrivée : toujours en glisse libre,
## même quand le mode Score est choisi (pas de chrono, de record ni de médaille).
const FREE_RIDE_LEVELS := [
	"res://src/levels/LevelChill704.tscn",
	"res://src/levels/LevelChill917.tscn",
	"res://src/levels/LevelHalfPipe.tscn",
]


func _ready() -> void:
	# [RESPONSIVE 1.14] le grand titre « Pinpouin le ninja » se réduit quand
	# l'écran est peu haut (téléphone en paysage, interface agrandie) : il
	# prend la place qui reste au-dessus des listes, sans déborder.
	var title: TextureRect = $Margin/VBox/Title
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.custom_minimum_size = Vector2(486, 70)
	title.size_flags_vertical = Control.SIZE_EXPAND_FILL
	$Margin/VBox/Columns.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	title.size_flags_stretch_ratio = 1.0
	version_label.text = "v" + str(ProjectSettings.get_setting("application/config/version", "?"))
	back_button.pressed.connect(_go_back)
	multi_button.pressed.connect(func():   # [MULTI] vers le salon multijoueur
		get_tree().change_scene_to_file(NetSession.LOBBY_SCENE))
	options_button.pressed.connect(func():   # [OPTIONS 1.7] aide, son, échange de fantômes
		get_tree().change_scene_to_file("res://src/screens/OptionsScreen.tscn"))
	# [MODES 1.25] choix du mode (Chill / Score) en haut de la liste des
	# courses, puis records et médailles sur les boutons (mode Score seulement)
	_build_mode_switch()
	_refresh_mode()
	# [FANTÔMES] interrupteur fantôme + dossier (PC uniquement : sur téléphone on
	# ne peut pas ouvrir un dossier de l'appli dans un explorateur de fichiers)
	ghost_toggle.button_pressed = RaceManager.ghost_enabled
	ghost_toggle.toggled.connect(RaceManager.set_ghost_enabled)
	# (visibilité du bouton « Dossier des fantômes » : voir _refresh_mode, [MODES 1.25])
	# [WEB 1.17] pas de multijoueur dans le navigateur (ENet / UDP indisponibles)
	if Settings.is_web:
		multi_button.visible = false
	ghost_folder_button.pressed.connect(func():
		OS.shell_open(ProjectSettings.globalize_path(RaceManager.GHOST_DIR)))
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


# --- [MODES 1.25] Choix du mode : Chill / Score ---------------------------------
# Deux boutons à bascule (un seul enfoncé à la fois) juste sous « COURSES ».
#  - Chill : pas de chrono ni de score, pas de fantôme, on reste dans le
#    half-pipe d'arrivée autant qu'on veut ;
#  - Score : chrono, record, fantôme, médailles, 30 s de figures bonus.
# Le choix est mémorisé (Settings.game_mode, Chill par défaut). Les records,
# scores et médailles ne s'affichent sur les boutons qu'en mode Score.
var _chill_button: Button
var _score_button: Button
var _mode_hint: Label

func _build_mode_switch() -> void:
	var row := HBoxContainer.new()
	row.name = "ModeRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	_chill_button = _mode_button("Chill", group)
	_score_button = _mode_button("Score", group)
	row.add_child(_chill_button)
	row.add_child(_score_button)
	races_box.add_child(row)
	races_box.move_child(row, 1)   # juste après le titre « COURSES »
	_mode_hint = Label.new()
	_mode_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_hint.add_theme_font_size_override("font_size", 15)
	_mode_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	races_box.add_child(_mode_hint)
	races_box.move_child(_mode_hint, 2)
	_chill_button.button_pressed = Settings.game_mode == Settings.MODE_CHILL
	_score_button.button_pressed = Settings.game_mode == Settings.MODE_SCORE
	_chill_button.pressed.connect(func():
		Settings.set_option("game_mode", Settings.MODE_CHILL)
		_refresh_mode())
	_score_button.pressed.connect(func():
		Settings.set_option("game_mode", Settings.MODE_SCORE)
		_refresh_mode())


func _mode_button(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(150, 40)
	b.add_theme_font_size_override("font_size", 20)
	return b


func _refresh_mode() -> void:
	var score_mode: bool = Settings.game_mode == Settings.MODE_SCORE
	# [MENU UNIQUE 1.37] textes valables pour toute la liste (704, 917 et Half-pipe compris)
	_mode_hint.text = "Chrono, médailles et 30 s de figures bonus  ·  704, 917, Half-pipe : défi figures chronométré" if score_mode else "Tranquille : pas de chrono, reste dans le half-pipe autant que tu veux"
	# le fantôme n'existe qu'en mode Score
	ghost_toggle.visible = score_mode
	ghost_folder_button.visible = score_mode and not Settings.is_mobile_device and not Settings.is_web   # [WEB 1.17]
	# [MENU UNIQUE 1.37] les boutons sont maintenant dans la grille « Grid »
	# (séparateurs « · » resserrés et boutons élargis à 380 px dans la scène :
	# sur deux colonnes, la médaille au bout du bouton mordait sur « pts »)
	for b in races_grid.get_children():
		if not (b is Button and "next_scene_path" in b and b.next_scene_path != ""):
			continue
		if not b.has_meta("base_text"):
			b.set_meta("base_text", b.text)
		b.text = b.get_meta("base_text")
		var badge = b.get_node_or_null("MedalBadge")
		if badge == null:
			badge = preload("res://src/ui/MedalBadge.gd").new()
			badge.name = "MedalBadge"
			badge.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
			badge.offset_left = -38
			badge.offset_right = -8
			badge.offset_top = -15
			badge.offset_bottom = 15
			b.add_child(badge)
		badge.medal = 0
		if not score_mode:
			continue
		# [CRÉATEUR 1.45] le bouton « Créer un niveau » ouvre un ÉCRAN (l'éditeur),
		# pas un niveau : ni record, ni score, ni médaille à afficher dessus
		if b.next_scene_path.begins_with("res://src/screens/"):
			continue
		# [MENU UNIQUE 1.37] pas d'arrivée = pas de chrono ni de médaille, même en Score
		if b.next_scene_path in FREE_RIDE_LEVELS:
			# [DÉFI FIGURES 1.43] en Score : défi chronométré de figures
			if TrickAttack.has_challenge(b.next_scene_path):
				var mins: int = int(TrickAttack.TIME_LIMITS[b.next_scene_path.get_file().get_basename()]) / 60
				b.text += "  ·  %d min" % mins
				var bs: int = RaceManager.get_best_score(b.next_scene_path)
				if bs >= 0:
					b.text += "  ·  %d pts" % bs
				badge.medal = RaceManager.get_best_medal(b.next_scene_path)
			else:
				b.text += "   ·   glisse libre"
			continue
		# [SANS FIN 1.33] record en mètres (pas de chrono ni de points)
		if b.next_scene_path.ends_with("LevelEndless.tscn"):
			var bm: int = preload("res://src/levels/endless/EndlessScore.gd").get_best_meters()
			if bm > 0:
				b.text += "  ·  " + preload("res://src/levels/endless/EndlessScore.gd").format_meters(bm)
			badge.medal = RaceManager.get_best_medal(b.next_scene_path)
			continue
		# [FANTÔMES] record de temps et [SCORE] meilleur score du niveau
		var best: float = RaceManager.get_best_time(b.next_scene_path)
		if best >= 0.0:
			b.text += "  ·  " + RaceManager.format_time(best)
		var best_score: int = RaceManager.get_best_score(b.next_scene_path)
		if best_score >= 0:
			b.text += "   ·   %d pts" % best_score
		badge.medal = RaceManager.get_best_medal(b.next_scene_path)
