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
#
#  [OPTIONS 1.72] Demande de l'équipe : « ranger le menu des options, comme
#  un vrai UX designer, par catégorie, avec des onglets sur le côté ».
#  Les réglages sont maintenant répartis en ONGLETS à gauche :
#    JEU          mode enfant, aide au début, clin d'œil, tuto figé, fantôme
#    AFFICHAGE    plein écran (F11), taille de l'interface, zoom libre,
#                 flèches des joueurs (multi)
#    SON          musique, effets
#    FANTÔMES     échange de fantômes (l'ancienne colonne de droite)
#    DÉVELOPPEUR  panneau physique (F2), vitesse (F3), air et frottement sous
#                 la vitesse, figure fixée pour la touche FIGURE
#  Les nœuds de la scène (et les variables qui les désignent) sont gardés : ils
#  sont simplement déplacés dans les pages des onglets par _build_tabs(), à la
#  fin de _ready(). Clavier / manette : haut / bas dans les onglets, droite
#  pour entrer dans la page, gauche pour revenir aux onglets.
# =============================================================================

## [OPTIONS 1.72] Onglets, dans l'ordre : [clé, titre affiché]
const TABS := [["jeu", "JEU"], ["affichage", "AFFICHAGE"], ["son", "SON"], ["fantomes", "FANTÔMES"], ["dev", "DÉVELOPPEUR"]]
## [OPTIONS 1.72] Dernier onglet ouvert (gardé tant que le jeu tourne)
static var _last_tab := "jeu"
var _pages := {}          # clé -> VBoxContainer de la page
var _tab_buttons := {}    # clé -> Button de l'onglet

# Courses qui peuvent avoir un fantôme (mêmes niveaux que le menu "COURSES")
const RACES = [
	["Tutoriel", "res://src/levels/LevelBateau.tscn"],   # [1.24] « Tuto : Bateau » -> « Tutoriel » (Léo)
	["Flat and fun", "res://src/levels/LevelRandomFlat.tscn"],
	["Corridor", "res://src/levels/LevelRandomCorridor.tscn"],
	["Nice Slope", "res://src/levels/LevelRandomNiceSlope.tscn"],
	["Hook, you fool !", "res://src/levels/LevelRandomGap.tscn"],
	["Spaghetti", "res://src/levels/LevelRandomSpaghetti.tscn"],
	["L'Œuf", "res://src/levels/LevelEgg.tscn"],   # [MENUS 1.61] nouveau niveau, ajouté ici aussi
	["Le Gruyère de glace", "res://src/levels/LevelGruyere.tscn"],   # [GRUYÈRE 1.62] maquette de la partie 1, à tester
	["Sans fin", "res://src/levels/LevelEndless.tscn"],   # [FANTÔME SANS FIN 1.36] défi à distance
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
	# [MENUS 1.61] largeur commune des menus (marge de 5 %) : les deux
	# panneaux se partagent toute la largeur
	MenuLayout.fit($Margin)
	MenuLayout.widen_panels($Margin/VBox/Columns)
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
	# [MAÎTRE 1.19] « Clin d'œil du maître » : même style que les autres
	# interrupteurs (copie du bouton « Aide en début de niveau »), juste après lui
	var wink: CheckButton = help_on_start.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)   # sans copier ses signaux
	wink.name = "MasterWink"
	wink.text = "Clin d'œil du maître ninja"
	help_on_start.get_parent().add_child(wink)
	help_on_start.get_parent().move_child(wink, help_on_start.get_index() + 1)
	wink.button_pressed = Settings.master_wink
	wink.toggled.connect(func(v): Settings.set_option("master_wink", v))
	# [MODE ENFANT 1.23] même style, juste au-dessus de l'aide (le plus visible)
	var kid: CheckButton = help_on_start.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
	kid.name = "KidMode"
	kid.text = "Mode enfant (avance tout seul + aide)"
	kid.tooltip_text = "Pinpouin avance tout seul au sol, reçoit un coup de pouce dans les creux,\nles boutons ▶ et PUMP clignotent quand il n'avance plus et les boutons tactiles\nsont plus faciles à toucher. Pas en multijoueur."
	help_on_start.get_parent().add_child(kid)
	help_on_start.get_parent().move_child(kid, help_on_start.get_index())
	kid.button_pressed = Settings.kid_mode
	kid.toggled.connect(func(v): Settings.set_option("kid_mode", v))
	# [VITESSE 1.48] « Afficher la vitesse de Pinpouin » : même style (copie du
	# bouton « Aide en début de niveau »), juste sous « Panneau de réglage
	# physique » (les deux options « pour regarder sous le capot »)
	var speed: CheckButton = help_on_start.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
	speed.name = "ShowSpeed"
	speed.text = "Afficher la vitesse de Pinpouin"
	speed.tooltip_text = "Compteur en haut à droite : km/h, px/s et une jauge.\nLa jauge devient orange quand Pinpouin dépasse la vitesse max\n(au sol ou en l'air) et que le jeu le freine doucement.\nTouche F3 en jeu pour l'allumer / l'éteindre."
	physics_panel.get_parent().add_child(speed)
	physics_panel.get_parent().move_child(speed, physics_panel.get_index() + 1)
	speed.button_pressed = Settings.show_speed
	speed.toggled.connect(func(v): Settings.set_option("show_speed", v))
	music_slider.value = Settings.music_volume
	music_slider.value_changed.connect(func(v): Settings.set_option("music_volume", v))
	_add_sfx_slider()       # [BRUITAGES 1.34] juste sous la musique
	_add_ui_size_slider()   # [RESPONSIVE 1.14]
	_add_arrows_choice()    # [FLÈCHES 1.16]
	# --- Fantômes
	_fill_ghost_list()
	paste_button.pressed.connect(_on_paste)
	folder_button.visible = not Settings.is_mobile_device and not Settings.is_web   # [WEB 1.17]
	folder_button.pressed.connect(func():
		OS.shell_open(ProjectSettings.globalize_path(RaceManager.GHOST_DIR)))
	back_button.pressed.connect(_go_back)
	_build_tabs()   # [OPTIONS 1.72] rangement en onglets (voir l'en-tête)
	if Settings.controls != Settings.TOUCH:
		_tab_buttons[_last_tab].grab_focus()


func _fill_ghost_list() -> void:
	for c in ghost_list.get_children():
		c.queue_free()
	var n := 0
	for race in RACES:
		var best: float = RaceManager.get_best_time(race[1])
		var endless: bool = race[1].ends_with("LevelEndless.tscn")
		# [FANTÔME SANS FIN 1.36] Sans fin : le fantôme garde -mètres (pas un temps)
		if (best < 0.0) != endless or (endless and best == -1.0 and RaceManager.load_best_ghost(race[1]) == null):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := Label.new()
		l.text = "%s   %s" % [race[0], ("%d m" % -int(best)) if endless else RaceManager.format_time(best)]
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


# [RESPONSIVE 1.14] Réglage « Taille de l'interface » (80 % à 150 %).
# L'interface est déjà agrandie automatiquement sur les petits écrans
# (Settings.auto_ui_scale) ; ce curseur la multiplie, au goût de chacun.
# Créé par code sous le curseur de musique (même style), pour ne pas
# toucher à la scène. Appliqué au relâchement du curseur (sinon l'écran
# changerait de taille sous le doigt pendant qu'on le fait glisser).
# [BRUITAGES 1.34] « Volume des effets » : curseur créé par code sous celui de
# la musique (même style). Un petit son d'essai au relâchement.
func _add_sfx_slider() -> void:
	var box: VBoxContainer = music_slider.get_parent()
	var title: Label = box.get_node("MusicTitle").duplicate()
	title.text = "Volume des effets"
	title.name = "SfxTitle"   # [OPTIONS 1.72] noms pour le rangement en onglets
	var slider := HSlider.new()
	slider.name = "SfxSlider"
	slider.custom_minimum_size = music_slider.custom_minimum_size
	slider.min_value = music_slider.min_value
	slider.max_value = music_slider.max_value
	slider.step = music_slider.step
	slider.value = Settings.sfx_volume
	box.add_child(title)
	box.add_child(slider)
	slider.value_changed.connect(func(v): Settings.set_option("sfx_volume", v))
	slider.drag_ended.connect(func(_c): Sfx.play("figure_ok"))


func _add_ui_size_slider() -> void:
	var box: VBoxContainer = music_slider.get_parent()
	var title: Label = box.get_node("MusicTitle").duplicate()
	title.name = "UiSizeTitle"   # [OPTIONS 1.72]
	var slider := HSlider.new()
	slider.name = "UiSizeSlider"
	slider.custom_minimum_size = music_slider.custom_minimum_size
	slider.min_value = 0.8
	slider.max_value = 1.5
	slider.step = 0.05
	slider.value = Settings.ui_size
	box.add_child(title)
	box.add_child(slider)
	var refresh := func(v: float):
		title.text = "Taille de l'interface : %d %%" % int(round(v * 100.0))
	refresh.call(slider.value)
	slider.value_changed.connect(refresh)
	slider.drag_ended.connect(func(_changed): Settings.set_option("ui_size", slider.value))
	# clavier / manette : pas de « drag », on applique quand on quitte le curseur
	slider.focus_exited.connect(func():
		if absf(slider.value - Settings.ui_size) > 0.001:
			Settings.set_option("ui_size", slider.value))


# [FLÈCHES 1.16] Choix « Flèches des joueurs (multi) » : Toutes / Devant et
# derrière / Aucune. Liste déroulante créée par code sous la taille de
# l'interface, appliquée et mémorisée tout de suite (Settings.player_arrows).
func _add_arrows_choice() -> void:
	var box: VBoxContainer = music_slider.get_parent()
	var title: Label = box.get_node("MusicTitle").duplicate()
	title.text = "Flèches des joueurs (multi)"
	title.name = "ArrowsTitle"   # [OPTIONS 1.72]
	var choice := OptionButton.new()
	choice.name = "ArrowsChoice"
	choice.custom_minimum_size = Vector2(0, 40)
	choice.add_item("Toutes", Settings.ARROWS_ALL)
	choice.add_item("Devant et derrière seulement", Settings.ARROWS_NEIGHBOURS)
	choice.add_item("Aucune", Settings.ARROWS_NONE)
	choice.select(choice.get_item_index(Settings.player_arrows))
	choice.item_selected.connect(func(index): Settings.set_option("player_arrows", choice.get_item_id(index)))
	box.add_child(title)
	box.add_child(choice)


# =============================================================================
#  [OPTIONS 1.72] Rangement en onglets latéraux
# =============================================================================
func _build_tabs() -> void:
	var columns: HBoxContainer = $Margin/VBox/Columns
	var game_box: VBoxContainer = $Margin/VBox/Columns/GamePanel/VBox
	var ghost_box: VBoxContainer = $Margin/VBox/Columns/GhostPanel/VBox
	var panel_style: StyleBox = $Margin/VBox/Columns/GamePanel.get_theme_stylebox("panel")
	var header_model: Label = game_box.get_node("GameHeader")

	# --- nouveaux réglages (même style que les autres interrupteurs)
	var fullscreen := _new_switch("Fullscreen", "Plein écran (touche F11)", Settings.fullscreen,
		func(v): Settings.set_option("fullscreen", v),
		"Le jeu occupe tout l'écran. F11 marche aussi en jeu et dans les menus.")
	fullscreen.visible = not Settings.is_mobile_device   # téléphone : déjà plein écran
	var free_zoom := _new_switch("FreeZoom", "Zoom libre", Settings.free_zoom,
		func(v): Settings.set_option("free_zoom", v),
		"S'ajoute au zoom automatique de la caméra.")
	var zoom_help := _hint("Souris : molette (clic molette = zoom auto).\nManette : tenir le stick droit enfoncé (R3) et le pousser\nvers le haut ou le bas (clic court sur R3 = zoom auto).\nTéléphone : pincer à deux doigts dans la zone de jeu.")
	var coefs := _new_switch("ShowCoefs", "Afficher l'air et le frottement sous la vitesse", Settings.show_coefs,
		func(v): Settings.set_option("show_coefs", v),
		"Coefficients de la résistance de l'air (k) et du frottement de la glace (μ),\navec le freinage en cours. En gras quand le jeu l'applique.")
	var trick_title: Label = game_box.get_node("MusicTitle").duplicate()
	trick_title.name = "TrickTitle"
	trick_title.text = "Touche FIGURE"
	var trick_choice := OptionButton.new()
	trick_choice.name = "TrickChoice"
	trick_choice.custom_minimum_size = Vector2(0, 40)
	trick_choice.add_item("Au hasard (normal)", 0)
	for i in Settings.TRICKS.size():
		trick_choice.add_item(Settings.TRICKS[i][1], i + 1)
	trick_choice.select(Settings.fixed_trick + 1)
	trick_choice.item_selected.connect(func(index): Settings.set_option("fixed_trick", trick_choice.get_item_id(index) - 1))

	# --- mise en page : [onglets] [page]
	var layout := HBoxContainer.new()
	layout.name = "Tabs"
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 18)
	var vbox: VBoxContainer = $Margin/VBox
	vbox.add_child(layout)
	vbox.move_child(layout, columns.get_index())
	columns.visible = false   # vidée ci-dessous (nœuds déplacés), gardée pour la scène

	var tab_panel := PanelContainer.new()
	tab_panel.add_theme_stylebox_override("panel", panel_style)
	tab_panel.custom_minimum_size = Vector2(230, 0)
	layout.add_child(tab_panel)
	var tab_list := VBoxContainer.new()
	tab_list.add_theme_constant_override("separation", 8)
	tab_panel.add_child(tab_list)

	var page_panel := PanelContainer.new()
	page_panel.add_theme_stylebox_override("panel", panel_style)
	page_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(page_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_panel.add_child(scroll)

	var group := ButtonGroup.new()
	for t in TABS:
		var b := Button.new()
		b.name = "Tab_" + t[0]
		b.text = t[1]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 52)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 20)
		tab_list.add_child(b)
		_tab_buttons[t[0]] = b
		var page := VBoxContainer.new()
		page.name = "Page_" + t[0]
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 12)
		var h: Label = header_model.duplicate()
		h.text = t[1]
		page.add_child(h)
		scroll.add_child(page)
		_pages[t[0]] = page
		b.pressed.connect(_show_tab.bind(t[0]))
		# manette / clavier : arriver sur un onglet l'ouvre déjà
		b.focus_entered.connect(_show_tab.bind(t[0]))

	# --- contenu de chaque page (les nœuds existants sont déplacés)
	_move(["KidMode", "HelpOnStart", "MasterWink", "TutorialPause", "GhostEnabled"], game_box, _pages["jeu"])
	_pages["affichage"].add_child(fullscreen)
	_move(["UiSizeTitle", "UiSizeSlider"], game_box, _pages["affichage"])
	_pages["affichage"].add_child(free_zoom)
	_pages["affichage"].add_child(zoom_help)
	_move(["ArrowsTitle", "ArrowsChoice"], game_box, _pages["affichage"])
	# [GLACE 1.77] style des plateformes (glace / d'origine)
	_pages["affichage"].add_child(_new_switch("GroundStyle", "Plateformes en glace", Settings.ground_style == 1,
		func(v): Settings.set_option("ground_style", 1 if v else 0),
		"Une seule glace pour toutes les plateformes, avec un dessus clair.\nCoupé : les deux bleus et la bordure de cristaux d'origine.\nS'applique au prochain niveau lancé."))
	# [FOND 1.76] le fond glisse pendant les grands sauts et les chutes
	_pages["affichage"].add_child(_new_switch("BgFollowJumps", "Le fond suit les sauts et les chutes", Settings.bg_follow_jumps,
		func(v): Settings.set_option("bg_follow_jumps", v),
		"En haut d'un grand saut, on voit le ciel ; en bas d'une chute, le bas du glacier.\nCoupé : le fond reste fixe à l'écran."))
	# [FOND 1.75] thèmes du fond : bas du glacier et ciel lointain
	_add_theme_choice(_pages["affichage"], game_box, "BgGlacier", "Fond : bas du glacier",
		Settings.BG_GLACIER_THEMES, Settings.bg_glacier_theme, "bg_glacier_theme")
	_add_theme_choice(_pages["affichage"], game_box, "BgSky", "Fond : ciel lointain (au-dessus des nuages)",
		Settings.BG_SKY_THEMES, Settings.bg_sky_theme, "bg_sky_theme")
	_move(["MusicTitle", "MusicSlider", "SfxTitle", "SfxSlider"], game_box, _pages["son"])
	_move(["GhostHelp", "GhostList", "PasteButton", "FolderButton"], ghost_box, _pages["fantomes"])
	_pages["dev"].add_child(_hint("Pour régler et tester le jeu. Tout est coupé par défaut."))
	_move(["PhysicsPanel", "ShowSpeed"], game_box, _pages["dev"])
	_pages["dev"].add_child(coefs)
	_pages["dev"].add_child(trick_title)
	_pages["dev"].add_child(trick_choice)

	# clavier / manette : depuis une page, « gauche » revient à son onglet
	for key in _pages:
		for c in _pages[key].get_children():
			if c is Control and c.focus_mode != Control.FOCUS_NONE:
				c.focus_neighbor_left = c.get_path_to(_tab_buttons[key])
	_show_tab(_last_tab)


## Ouvre la page `key` (et coche son onglet).
func _show_tab(key: String) -> void:
	_last_tab = key
	for k in _pages:
		_pages[k].visible = k == key
	_tab_buttons[key].button_pressed = true
	# « droite » depuis l'onglet : premier réglage de la page
	for c in _pages[key].get_children():
		if c is Control and c.visible and c.focus_mode != Control.FOCUS_NONE:
			_tab_buttons[key].focus_neighbor_right = _tab_buttons[key].get_path_to(c)
			break


## Déplace des nœuds (par nom) de `from` vers `to`, dans l'ordre donné.
func _move(names: Array, from: Node, to: Node) -> void:
	for n in names:
		var node := from.get_node_or_null(n)
		if node != null:
			node.reparent(to, false)


## Interrupteur au style des autres (copie de « Aide en début de niveau »).
func _new_switch(node_name: String, text: String, value: bool, on_toggle: Callable, tip := "") -> CheckButton:
	var c: CheckButton = help_on_start.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
	c.name = node_name
	c.text = text
	c.tooltip_text = tip
	c.button_pressed = value
	c.toggled.connect(on_toggle)
	return c


## [FOND 1.75] Choix d'un thème du fond : titre, liste déroulante, aperçu de
## l'image (pixels nets, comme en jeu) et petite description. Le choix est
## mémorisé tout de suite ; il s'applique au prochain niveau lancé.
## `themes` : Settings.BG_GLACIER_THEMES ou BG_SKY_THEMES ([nom, image, texte]).
func _add_theme_choice(page: VBoxContainer, game_box: Node, node_name: String, title: String,
		themes: Array, current: int, option_key: String) -> void:
	var t: Label = game_box.get_node("MusicTitle").duplicate()   # même style de titre
	t.name = node_name + "Title"
	t.text = title
	page.add_child(t)
	var choice := OptionButton.new()
	choice.name = node_name + "Choice"
	choice.custom_minimum_size = Vector2(0, 40)
	for i in themes.size():
		choice.add_item(themes[i][0], i)
	choice.select(clampi(current, 0, themes.size() - 1))
	page.add_child(choice)
	# aperçu : l'image du thème, bande de 320 px de large agrandie ×2
	var preview := TextureRect.new()
	preview.name = node_name + "Preview"
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(0, 150)
	page.add_child(preview)
	var info := _hint("")
	page.add_child(info)
	var show := func(index: int) -> void:
		var path: String = themes[index][1]
		preview.texture = load(path) if path != "" and ResourceLoader.exists(path) else null
		preview.visible = preview.texture != null
		info.text = themes[index][2]
	show.call(choice.selected)
	choice.item_selected.connect(func(index):
		Settings.set_option(option_key, choice.get_item_id(index))
		show.call(index))


## Petit texte d'aide sous un réglage.
func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	return l
