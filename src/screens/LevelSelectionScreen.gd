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
#  [MENUS 1.61] nouveau plan de l'équipe (croquis) : un seul grand panneau,
#   - en haut, « MODE : ○ CHILL / ● SCORE » avec une phrase sous chaque choix ;
#   - trois colonnes : « Autres modes » (Tutoriel, Sans fin, Niveaux custom),
#     « Niveaux » (les 6 courses avec arrivée, dont L'Œuf) et « Défis
#     figures » (704, 917, Half-pipe) — ce dernier titre devient « Glisse
#     libre » en Chill (pas de défi chronométré dans ce mode) ;
#   - « Niveaux custom » ouvre « Mes niveaux », qui a deux onglets (Mes
#     niveaux / Communauté) ; le bouton « Niveaux de la communauté » reste
#     dans la scène mais masqué ;
#   - fantôme (interrupteur + dossier) : déplacés dans Options (ils y étaient
#     déjà) ; les nœuds restent ici, masqués ;
#   - le logo « Pinpouin » passe en bas à droite, à côté du numéro de version ;
#   - en Score, chaque bouton montre son record sur une 2e ligne ;
#   - largeur : règle commune des menus (MenuLayout : marge de 5 %).
#  Les boutons de niveau restent des ChangeSceneButton : on ajoute un niveau
#  en dupliquant un bouton de « Grid » dans l'éditeur et en changeant
#  next_scene_path.
# =============================================================================

@onready var first_button: Button = $Margin/VBox/Columns/RacesPanel/VBox/Cols/LeftCol/ButtonBateau   # [MENUS 1.61] colonne « Autres modes »
@onready var back_button: Button = $Margin/VBox/Bottom/BackButton
@onready var version_label: Label = $Margin/VBox/Bottom/VersionLabel
@onready var ghost_toggle: CheckButton = $Margin/VBox/Bottom/GhostToggle
@onready var ghost_folder_button: Button = $Margin/VBox/Bottom/GhostFolderButton
@onready var multi_button: Button = $Margin/VBox/Bottom/MultiButton   # [MULTI]
@onready var options_button: Button = $Margin/VBox/Bottom/OptionsButton   # [OPTIONS 1.7]
@onready var races_box: VBoxContainer = $Margin/VBox/Columns/RacesPanel/VBox
@onready var races_grid: GridContainer = $Margin/VBox/Columns/RacesPanel/VBox/Cols/MidCol/Grid   # [MENUS 1.61] colonne « Niveaux »
@onready var left_col: VBoxContainer = $Margin/VBox/Columns/RacesPanel/VBox/Cols/LeftCol     # [MENUS 1.61]
@onready var right_col: VBoxContainer = $Margin/VBox/Columns/RacesPanel/VBox/Cols/RightCol   # [MENUS 1.61]
@onready var right_header: Label = $Margin/VBox/Columns/RacesPanel/VBox/Cols/RightCol/RightHeader
@onready var right_sub: Label = $Margin/VBox/Columns/RacesPanel/VBox/Cols/RightCol/RightSub

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
	# [MENUS 1.61] le logo est maintenant un petit logo en bas à droite (plan
	# de l'équipe) : la place libérée en haut va aux colonnes de niveaux.
	var title: TextureRect = $Margin/VBox/Bottom/Title
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# [MENUS 1.61] largeur commune des menus : marge de 5 % de chaque côté
	MenuLayout.fit($Margin)
	MenuLayout.widen_panels($Margin/VBox/Columns)
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
	_add_quit_button()   # [QUITTER 1.73]
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
	# [MENUS 1.61] plan de l'équipe : « MODE : » à gauche, puis deux choix
	# radio l'un sous l'autre, chacun suivi d'une courte explication. Toute la
	# ligne est cliquable (le bouton radio porte aussi le nom du mode).
	var row := HBoxContainer.new()
	row.name = "ModeRow"
	row.add_theme_constant_override("separation", 22)
	var title := Label.new()
	title.text = "MODE :"
	title.add_theme_font_override("font", preload("res://assets/font/Roboto-Medium.ttf"))
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	var choices := VBoxContainer.new()
	choices.add_theme_constant_override("separation", 2)
	row.add_child(choices)
	var group := ButtonGroup.new()
	_chill_button = _mode_button("CHILL", group, choices, "Pas de score ni de limite de temps")
	_score_button = _mode_button("SCORE", group, choices, "Score, chrono et médailles  ·  défis figures chronométrés")
	races_box.add_child(row)
	races_box.move_child(row, 1)   # juste après le titre « COURSES » (masqué)
	# trait fin sous le choix du mode, comme sur le croquis (sépare les colonnes)
	var line := HSeparator.new()
	line.modulate = Color(1, 1, 1, 0.35)
	races_box.add_child(line)
	races_box.move_child(line, 2)
	_mode_hint = right_sub   # [MENUS 1.61] l'explication du mode est maintenant à côté de chaque choix
	_chill_button.button_pressed = Settings.game_mode == Settings.MODE_CHILL
	_score_button.button_pressed = Settings.game_mode == Settings.MODE_SCORE
	_chill_button.pressed.connect(func():
		Settings.set_option("game_mode", Settings.MODE_CHILL)
		_refresh_mode())
	_score_button.pressed.connect(func():
		Settings.set_option("game_mode", Settings.MODE_SCORE)
		_refresh_mode())


## [MENUS 1.61] un choix radio : rond + NOM du mode (CheckBox d'un
## ButtonGroup) puis son explication, en plus petit.
func _mode_button(text: String, group: ButtonGroup, parent: Control = null, hint: String = "") -> Button:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	var b := CheckBox.new()
	b.text = text
	b.button_group = group
	b.custom_minimum_size = Vector2(150, 36)
	b.add_theme_font_size_override("font_size", 22)
	for c in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Color.WHITE if c != "font_pressed_color" and c != "font_hover_pressed_color" else Color(1, 0.94, 0.4))
	# pas de fond de bouton : un vrai choix « radio » (rond + nom), comme sur le
	# croquis ; un léger fond au survol / au focus clavier pour qu'on voie où on est
	for st_name in ["normal", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st_name, StyleBoxEmpty.new())
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 0.10)
	hover.set_corner_radius_all(8)
	for st_name in ["hover", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(st_name, hover)
	line.add_child(b)
	var l := Label.new()
	l.text = hint
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.88, 0.93, 1, 0.9))
	line.add_child(l)
	if parent != null:
		parent.add_child(line)
	return b


func _refresh_mode() -> void:
	var score_mode: bool = Settings.game_mode == Settings.MODE_SCORE
	# [MENU UNIQUE 1.37] textes valables pour toute la liste (704, 917 et Half-pipe compris)
	# le fantôme n'existe qu'en mode Score
	# [MENUS 1.61] fantôme : réglé dans Options (choix de l'équipe), plus ici
	ghost_toggle.visible = false
	ghost_folder_button.visible = false
	# [MENUS 1.61] colonne de droite : défi chronométré en Score, glisse libre en Chill
	right_header.text = "Défis figures" if score_mode else "Glisse libre"
	right_sub.text = "Un max de points dans le temps imparti" if score_mode else "Pas d'arrivée : glisse et figures sans fin"
	# [MENU UNIQUE 1.37] les boutons sont maintenant dans la grille « Grid »
	# (séparateurs « · » resserrés et boutons élargis à 380 px dans la scène :
	# sur deux colonnes, la médaille au bout du bouton mordait sur « pts »)
	for b in _level_buttons():
		if not b.has_meta("base_text"):
			b.set_meta("base_text", b.text)
		b.text = b.get_meta("base_text")
		# [MENUS 1.61] en Score, le record va sur une 2e ligne (colonnes plus
		# étroites qu'avant) : tous les boutons de niveau ont alors la même
		# hauteur, record ou pas
		var two_lines: bool = score_mode and not b.next_scene_path.begins_with("res://src/screens/")
		b.custom_minimum_size.y = 64 if two_lines else 52
		var before: String = b.text
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
				var line := "%d min" % mins
				var bs: int = RaceManager.get_best_score(b.next_scene_path)
				line += ("  ·  record %d pts" % bs) if bs >= 0 else "  ·  pas encore de score"
				b.text = before + "\n" + line
				badge.medal = RaceManager.get_best_medal(b.next_scene_path)
			else:
				b.text = before + "\nglisse libre"
			continue
		# [SANS FIN 1.33] record en mètres (pas de chrono ni de points)
		if b.next_scene_path.ends_with("LevelEndless.tscn"):
			var bm: int = preload("res://src/levels/endless/EndlessScore.gd").get_best_meters()
			b.text = before + "\n" + (("record " + preload("res://src/levels/endless/EndlessScore.gd").format_meters(bm)) if bm > 0 else "pas encore de record")
			badge.medal = RaceManager.get_best_medal(b.next_scene_path)
			continue
		# [FANTÔMES] record de temps et [SCORE] meilleur score du niveau
		var best: float = RaceManager.get_best_time(b.next_scene_path)
		var best_score: int = RaceManager.get_best_score(b.next_scene_path)
		var rec := PackedStringArray()
		if best >= 0.0:
			rec.append(RaceManager.format_time(best))
		if best_score >= 0:
			rec.append("%d pts" % best_score)
		b.text = before + "\n" + ("  ·  ".join(rec) if not rec.is_empty() else "pas encore de record")
		badge.medal = RaceManager.get_best_medal(b.next_scene_path)


## [MENUS 1.61] Tous les boutons de niveau des trois colonnes (ceux qui
## ouvrent un niveau ou un écran), dans l'ordre d'affichage.
func _level_buttons() -> Array:
	var out := []
	for col in [left_col, races_grid, right_col]:
		for b in col.get_children():
			if b is Button and b.visible and "next_scene_path" in b and b.next_scene_path != "":
				out.append(b)
	return out


# =============================================================================
#  [QUITTER 1.73] Bouton « Quitter le jeu » dans le menu principal
# -----------------------------------------------------------------------------
#  Demande de l'équipe : il n'y avait pas de moyen de quitter le jeu depuis le
#  menu (seulement dans le menu pause, en pleine course).
#  - Même style que « Options » (copie du bouton), juste après lui en bas.
#  - PC seulement : masqué dans le navigateur (on ne peut pas fermer un
#    onglet) et sur téléphone (on quitte une appli avec le geste « accueil »),
#    comme « Quitter le jeu » du menu pause.
#  - Confirmation comme dans le menu pause : 1er clic -> « Sûr ? Clique
#    encore » (rouge foncé, lisible sur le bouton bleu clair) pendant 3 s ; 2e clic -> le jeu se ferme.
# =============================================================================
const QUIT_CONFIRM_DELAY := 3.0
var _quit_armed := false

func _add_quit_button() -> void:
	if Settings.is_web or Settings.is_mobile_device:
		return
	var b: Button = options_button.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
	b.name = "QuitButton"
	b.text = "  Quitter le jeu  "
	options_button.get_parent().add_child(b)
	options_button.get_parent().move_child(b, options_button.get_index() + 1)
	b.pressed.connect(_on_quit_pressed.bind(b))


func _on_quit_pressed(b: Button) -> void:
	if not _quit_armed:
		_quit_armed = true
		b.text = "  Sûr ? Clique encore  "
		b.add_theme_color_override("font_color", Color(0.75, 0.15, 0.05))
		b.add_theme_color_override("font_hover_color", Color(0.75, 0.15, 0.05))
		b.add_theme_color_override("font_focus_color", Color(0.75, 0.15, 0.05))
		get_tree().create_timer(QUIT_CONFIRM_DELAY).timeout.connect(func():
			if is_instance_valid(b):
				_quit_armed = false
				b.text = "  Quitter le jeu  "
				b.remove_theme_color_override("font_color")
				b.remove_theme_color_override("font_hover_color")
				b.remove_theme_color_override("font_focus_color"))
		return
	get_tree().quit()
