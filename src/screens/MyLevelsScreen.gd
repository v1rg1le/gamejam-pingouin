extends Control
# =============================================================================
#  MyLevelsScreen.gd — [MES NIVEAUX 1.46] la liste des niveaux dessinés
# -----------------------------------------------------------------------------
#  Ouvert par le bouton « Mes niveaux » de la sélection des niveaux (ce
#  bouton s'appelait « Créer un niveau » en 1.45 et ouvrait directement
#  l'éditeur). Une ligne par niveau dessiné (DrawnLevel.list_levels(), le
#  plus récent en haut) :
#    [ JOUER : nom · record · médaille ]  [ Modifier ]  [ Supprimer ]
#  - JOUER lance le niveau ; après l'arrivée on revient ICI ;
#  - Modifier ouvre l'éditeur sur ce niveau ;
#  - Supprimer demande un 2e toucher (« Sûr ? », 3 s), comme le menu pause ;
#    le fichier et les fantômes du niveau sont effacés.
#  En bas : « ◀ Retour » (sélection des niveaux) et « + Nouveau niveau ».
#  Records, médailles et fantômes se font en mode SCORE, comme pour les
#  autres courses (choix Chill / Score de l'écran de sélection) : la médaille
#  vient du temps de référence (distance ÷ RaceManager.REF_SPEED).
#  Interface construite par le code (comme l'éditeur), à l'échelle du jeu
#  (UiScaler) mais réduite si l'écran est petit.
# =============================================================================

# [PARTAGE 1.47] le même écran sert aussi aux « Niveaux de la communauté »
# (CommunityLevelsScreen.tscn, community = true) : niveaux livrés avec le jeu,
# avec leur auteur, seulement « Jouer » (ni Modifier, ni Partager, ni Supprimer).
# Dans « Mes niveaux », chaque ligne gagne un bouton « Partager » (code à
# copier, avec ou sans fantôme, ou fichier .pinpouin) et le bas de l'écran
# un bouton « Ajouter un code » (niveau reçu d'un ami).
@export var community: bool = false

const CONFIRM_DELAY := 3.0               # secondes pour confirmer une suppression
const CONFIRM_TEXT := "Sûr ?"

var _layer: CanvasLayer
var _list: VBoxContainer
var _confirm_id := ""                    # niveau en attente de confirmation de suppression
var _confirm_time := 0.0
var _confirm_button: Button


func _ready() -> void:
	DrawnLevel.load_once()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.4, 0.486275, 0.584314, 1)   # même fond que la sélection des niveaux
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_build()
	get_viewport().size_changed.connect(_build_deferred)


func _process(delta: float) -> void:
	if _confirm_id != "":
		_confirm_time -= delta
		if _confirm_time <= 0.0:
			_confirm_id = ""
			if is_instance_valid(_confirm_button):
				_confirm_button.text = "Supprimer"


func _unhandled_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		if _popup != null and is_instance_valid(_popup):
			_close_popup()   # Échap / retour : ferme d'abord la fenêtre ouverte
		else:
			_go_back()


var _rebuild_pending := false

func _build_deferred() -> void:
	if _rebuild_pending or not is_inside_tree():
		return   # (signal reçu pendant un changement d'écran : rien à faire)
	_rebuild_pending = true
	await get_tree().process_frame
	_rebuild_pending = false
	if is_inside_tree():
		_build()


## (Re)construit tout l'écran
func _build() -> void:
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	_layer = CanvasLayer.new()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = preload("res://src/theme_main.tres")
	_layer.add_child(root)
	add_child(_layer)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	root.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	# [MENUS 1.61] « Niveaux custom » : deux ONGLETS en haut, « Mes niveaux »
	# et « Communauté » (choix de l'équipe : un seul bouton dans le menu des
	# niveaux). L'onglet actif est enfoncé ; l'autre ouvre l'autre écran (les
	# deux écrans existaient déjà : même script, community = vrai / faux).
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 6)
	col.add_child(tabs)
	var group := ButtonGroup.new()
	for tab in [["MES NIVEAUX", false, "res://src/screens/MyLevelsScreen.tscn"],
			["COMMUNAUTÉ", true, "res://src/screens/CommunityLevelsScreen.tscn"]]:
		var tb := Button.new()
		tb.text = tab[0]
		tb.toggle_mode = true
		tb.button_group = group
		tb.button_pressed = tab[1] == community
		tb.custom_minimum_size = Vector2(240, 48)
		tb.add_theme_font_size_override("font_size", 22)
		if tab[1] != community:
			var target: String = tab[2]
			tb.pressed.connect(func(): get_tree().change_scene_to_file(target))
		tabs.add_child(tb)
	var title := Label.new()   # ancien titre, gardé pour l'accessibilité du code : masqué (les onglets le remplacent)
	title.text = "NIVEAUX DE LA COMMUNAUTÉ" if community else "MES NIVEAUX"
	title.visible = false
	col.add_child(title)
	var sub := Label.new()
	sub.text = "Les meilleurs niveaux dessinés par les joueurs. Record, médaille et fantôme en mode Score." if community \
		else "Tes niveaux dessinés. Record, médaille et fantôme en mode Score (comme les autres courses)."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.88, 0.93, 1.0))
	col.add_child(sub)

	# Liste (avec défilement si elle est longue)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()   # même style que les panneaux des menus
	st.bg_color = Color(0.105882, 0.152941, 0.270588, 0.72)
	st.border_color = Color(1, 1, 1, 0.55)
	st.set_border_width_all(3)
	st.set_corner_radius_all(14)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 12
	st.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", st)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	_fill_list()

	# Bas : Retour · Nouveau niveau
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	col.add_child(bottom)
	var back := _button("◀  Retour", bottom, 140)
	back.pressed.connect(_go_back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	var add: Button = back
	if community:
		var info := Label.new()
		info.text = "Envoie tes meilleurs niveaux à l'équipe (bouton Partager) : les plus cool arrivent ici !"
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 15)
		info.add_theme_color_override("font_color", Color(0.88, 0.93, 1.0))
		bottom.remove_child(spacer)
		spacer.queue_free()
		bottom.add_child(info)
	else:
		_button("Ajouter un code", bottom, 170).pressed.connect(_open_import)
		add = _button("+  Nouveau niveau", bottom, 220)
		add.add_theme_font_size_override("font_size", 21)
		add.pressed.connect(_on_new)
	_root = root
	if Settings.controls != Settings.TOUCH:
		var first = _list.get_child(0).get_child(0) if _list.get_child_count() > 0 and _list.get_child(0).get_child_count() > 0 else add
		if first is Button:
			first.grab_focus()

	# Échelle : celle du jeu, réduite si l'écran est petit (téléphone 20:9)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	UiScaler.apply(_layer, clampf(minf(Settings.hud_scale(), minf(vp.x / 760.0, vp.y / 380.0)), 0.6, 2.0))
	# [MENUS 1.61] même marge que les autres menus (5 % de chaque côté, voir MenuLayout)
	var m := int(round(MenuLayout.side_margin(vp.x / maxf(_layer.scale.x, 0.01))))
	margin.add_theme_constant_override("margin_left", m)
	margin.add_theme_constant_override("margin_right", m)


func _fill_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var levels := DrawnLevel.list_official() if community else DrawnLevel.list_levels()
	if levels.is_empty():
		var empty := Label.new()
		empty.text = "Pas encore de niveau ici." if community else "Pas encore de niveau.\nTouche « + Nouveau niveau » et dessine le premier !"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 19)
		empty.add_theme_color_override("font_color", Color.WHITE)
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list.add_child(empty)
		return
	for e in levels:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_list.add_child(row)
		# [PARTAGE v2 1.91] miniature « silhouette » du niveau (choix de
		# l'équipe) : sol et blocs en glace sur le ciel, prises, départ, arrivée
		var data: Dictionary = DrawnLevel.official_data(e.slug) if community else DrawnLevel.level_data(e.id)
		if not data.is_empty():
			var th := TextureRect.new()
			th.texture = DrawnLevel.thumbnail(data)
			th.custom_minimum_size = Vector2(DrawnLevel.THUMB_SIZE) * Vector2(1.05, 1.05)
			th.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			th.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			th.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			th.name = "Miniature"
			row.add_child(th)
		# JOUER : nom + record ; médaille au bout du bouton
		var path: String = DrawnLevel.race_path_of(e)
		var text: String = "▶  " + str(e.name)
		if str(e.get("author", "")) != "":
			text += "  ·  par " + str(e.author)   # [PARTAGE 1.47] niveau reçu ou de la communauté
		# [PARTAGE v2 1.91] copie d'un niveau d'un autre : auteur d'origine cité
		var origin: Dictionary = e.get("based_on", {})
		if not origin.is_empty() and str(origin.get("author", "")) != "":
			text += "  ·  d'après " + str(origin.author)
		# [RÈGLES 1.90] défi figures : meilleur score en points ; glisse libre : pas de record
		var kind := str(e.get("type", "course"))
		if kind == "tricks":
			text += "  ·  ✦ défi"
			var pts: int = RaceManager.get_best_score(path)
			if pts > 0:
				text += "  ·  %d pts" % pts
		elif kind == "free":
			text += "  ·  glisse libre"
		else:
			var best: float = RaceManager.get_best_time(path)
			if best >= 0.0:
				text += "  ·  " + RaceManager.format_time(best)
		var play := _button(text, row, 0)
		play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		play.alignment = HORIZONTAL_ALIGNMENT_LEFT
		play.clip_text = true
		var badge = preload("res://src/ui/MedalBadge.gd").new()
		badge.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		badge.offset_left = -38
		badge.offset_right = -8
		badge.offset_top = -15
		badge.offset_bottom = 15
		badge.medal = RaceManager.get_best_medal(path)
		play.add_child(badge)
		var id: String = e.id
		if community:
			var slug: String = e.slug
			play.pressed.connect(func(): _on_play_official(slug))
			# [PARTAGE v2 1.91] « Copier pour modifier » : une copie à toi dans
			# « Mes niveaux », ouverte dans le créateur (l'auteur reste cité)
			var cp := _button("Copier pour modifier", row, 200)
			cp.tooltip_text = "Une copie de ce niveau dans « Mes niveaux », à modifier comme tu veux (l'auteur d'origine reste cité)."
			cp.pressed.connect(func(): _on_copy_official(slug))
			continue
		play.pressed.connect(func(): _on_play(id))
		_button("Modifier", row, 104).pressed.connect(func(): _on_edit(id))
		var entry: Dictionary = e
		_button("Partager", row, 104).pressed.connect(func(): _open_share(entry))
		var del := _button("Supprimer", row, 116)
		del.pressed.connect(func(): _on_delete(id, del))
	if community:
		_fill_game_levels()   # [COPIES DU JEU 1.92]


## [COPIES DU JEU 1.92] Sous la Communauté : « — Niveaux du jeu — ». Choix de
## l'équipe : TOUS les niveaux du jeu se copient, même le Gruyère et L'Œuf.
## ▶ lance le vrai niveau (record, médaille et fantôme du jeu) ; « Copier
## pour modifier » met une copie dans « Mes niveaux » et l'ouvre dans le
## créateur (le niveau du jeu ne change jamais).
func _fill_game_levels() -> void:
	var games := DrawnLevel.list_game_levels()
	if games.is_empty():
		return
	var sep := Label.new()
	sep.text = "—  Niveaux du jeu  —"
	sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sep.add_theme_font_size_override("font_size", 19)
	sep.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	sep.name = "NiveauxDuJeu"
	_list.add_child(sep)
	for g in games:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_list.add_child(row)
		var data := DrawnLevel.game_level_data(g.slug)
		if not data.is_empty():
			var th := TextureRect.new()
			th.texture = DrawnLevel.thumbnail(data)   # (gardée en cache comme les autres)
			th.custom_minimum_size = Vector2(DrawnLevel.THUMB_SIZE) * Vector2(1.05, 1.05)
			th.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			th.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			th.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			th.name = "Miniature"
			row.add_child(th)
		# record du VRAI niveau (même chemin que dans la sélection des niveaux)
		var scene: String = g.scene
		var text: String = "▶  " + str(g.name) + "  ·  niveau du jeu"
		if g.type == "tricks":
			text += "  ·  ✦ défi"
			var pts: int = RaceManager.get_best_score(scene)
			if pts > 0:
				text += "  ·  %d pts" % pts
		else:
			var best: float = RaceManager.get_best_time(scene)
			if best >= 0.0:
				text += "  ·  " + RaceManager.format_time(best)
		var play := _button(text, row, 0)
		play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		play.alignment = HORIZONTAL_ALIGNMENT_LEFT
		play.clip_text = true
		var badge = preload("res://src/ui/MedalBadge.gd").new()
		badge.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		badge.offset_left = -38
		badge.offset_right = -8
		badge.offset_top = -15
		badge.offset_bottom = 15
		badge.medal = RaceManager.get_best_medal(scene)
		play.add_child(badge)
		play.pressed.connect(func(): get_tree().change_scene_to_file(scene))
		var slug: String = g.slug
		var cp := _button("Copier pour modifier", row, 200)
		cp.name = "Copier_" + slug
		cp.tooltip_text = "Une copie de ce niveau du jeu dans « Mes niveaux », à modifier comme tu veux (le niveau du jeu ne change pas)."
		cp.pressed.connect(func(): _on_copy_game(slug))


## [COPIES DU JEU 1.92] copie d'un niveau du jeu, ouverte dans le créateur
func _on_copy_game(slug: String) -> void:
	var new_id := DrawnLevel.copy_game_level(slug)
	if new_id != "" and DrawnLevel.open_level(new_id):
		get_tree().change_scene_to_file(DrawnLevel.EDITOR_SCENE)


func _button(text: String, parent: Node, min_w: float) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 46)
	b.add_theme_font_size_override("font_size", 19)
	parent.add_child(b)
	return b


func _on_play(id: String) -> void:
	if not DrawnLevel.open_level(id):
		_fill_list()
		return
	DrawnLevel.return_scene = DrawnLevel.LIST_SCENE   # après l'arrivée : retour à la liste
	get_tree().change_scene_to_file(DrawnLevel.LEVEL_SCENE)


## [PARTAGE 1.47] niveau de la communauté : après l'arrivée, retour à cette liste
func _on_play_official(slug: String) -> void:
	if not DrawnLevel.open_official(slug):
		return
	DrawnLevel.return_scene = DrawnLevel.COMMUNITY_SCENE
	get_tree().change_scene_to_file(DrawnLevel.LEVEL_SCENE)


## [PARTAGE v2 1.91] copie d'un niveau de la Communauté, ouverte dans le créateur
func _on_copy_official(slug: String) -> void:
	var d := DrawnLevel.official_data(slug)
	if d.is_empty():
		return
	var new_id := DrawnLevel.copy_to_mine(d)
	if DrawnLevel.open_level(new_id):
		get_tree().change_scene_to_file(DrawnLevel.EDITOR_SCENE)


func _on_edit(id: String) -> void:
	if DrawnLevel.open_level(id):
		get_tree().change_scene_to_file(DrawnLevel.EDITOR_SCENE)


func _on_new() -> void:
	DrawnLevel.new_level(DrawnLevel.next_free_name())
	get_tree().change_scene_to_file(DrawnLevel.EDITOR_SCENE)


## Supprimer : 1er toucher = « Sûr ? », 2e toucher dans les 3 s = suppression
func _on_delete(id: String, b: Button) -> void:
	if _confirm_id != id:
		if is_instance_valid(_confirm_button):
			_confirm_button.text = "Supprimer"
		_confirm_id = id
		_confirm_time = CONFIRM_DELAY
		_confirm_button = b
		b.text = CONFIRM_TEXT
		return
	_confirm_id = ""
	DrawnLevel.delete_level(id)
	_fill_list()


func _go_back() -> void:
	get_tree().change_scene_to_file("res://src/screens/LevelSelectionScreen.tscn")


# --- [PARTAGE 1.47] Fenêtres « Partager » et « Ajouter un code » ---------------------
var _root: Control                       # Control racine (porte le thème du jeu)
var _popup: Control                      # fenêtre ouverte (fond assombri + panneau)
var _popup_msg: Label                    # message en bas de la fenêtre


## Ouvre une fenêtre centrée (fond assombri qui bloque les touchers derrière).
## Renvoie la colonne où mettre le contenu.
func _open_popup(title_text: String) -> VBoxContainer:
	_close_popup()
	_popup = ColorRect.new()
	(_popup as ColorRect).color = Color(0, 0, 0, 0.45)
	_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_popup)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup.add_child(center)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.105882, 0.152941, 0.270588, 0.96)
	st.border_color = Color(1, 1, 1, 0.7)
	st.set_border_width_all(3)
	st.set_corner_radius_all(14)
	for side in ["left", "right", "top", "bottom"]:
		st.set("content_margin_" + side, 18)
	panel.add_theme_stylebox_override("panel", st)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(560, 0)
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var t := Label.new()
	t.text = title_text
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color(1, 0.95, 0.4))
	col.add_child(t)
	_popup_msg = Label.new()
	_popup_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_popup_msg.add_theme_font_size_override("font_size", 16)
	_popup_msg.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75))
	return col


func _close_popup() -> void:
	if _popup != null and is_instance_valid(_popup):
		_popup.queue_free()
	_popup = null


func _label(parent: Node, text: String, size: int = 17) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	parent.add_child(l)
	return l


## « Partager » : nom de créateur, code (avec ou sans fantôme), fichier
func _open_share(entry: Dictionary) -> void:
	var col := _open_popup("Partager « %s »" % entry.name)
	var own: bool = str(entry.get("author", "")) == ""
	var author_edit := LineEdit.new()
	if own:
		_label(col, "Ton nom de créateur (affiché avec ton niveau) :")
		author_edit.text = DrawnLevel.author_name()
		author_edit.placeholder_text = "prénom ou pseudo"
		author_edit.max_length = DrawnLevel.NAME_MAX
		author_edit.custom_minimum_size = Vector2(0, 44)
		author_edit.add_theme_font_size_override("font_size", 19)
		_light_text(author_edit)
		col.add_child(author_edit)
	else:
		_label(col, "Niveau de %s : il garde son auteur." % entry.author)
	var save_author := func():
		if own and author_edit.text.strip_edges() != "":
			DrawnLevel.set_author_name(author_edit.text)
	# [VALIDATION 1.81] un niveau à toi se partage une fois VALIDÉ (fini du
	# départ à l'arrivée avec « ✔ Valider » dans l'éditeur) : décision de l'équipe
	if own and not DrawnLevel.entry_validated(entry):
		_label(col, "Pour partager ce défi, fais-le d'abord avec « ✔ Valider » dans l'éditeur : tes points deviendront l'or du niveau." if str(entry.get("type", "course")) == "tricks"
			else "Pour partager ce niveau, finis-le d'abord avec « ✔ Valider » dans l'éditeur : ton temps deviendra l'or du niveau.")
		_button("Fermer", col, 0).pressed.connect(_close_popup)
		return
	var b1 := _button("Copier le code du niveau", col, 0)
	b1.pressed.connect(func():
		save_author.call()
		_copy_code(DrawnLevel.share_code(entry.id, false), false))
	var has_ghost := DrawnLevel.has_ghost(entry)
	var b2 := _button("Copier le code + mon fantôme" if has_ghost else "Code + fantôme : fais d'abord un temps (mode Score)", col, 0)
	b2.disabled = not has_ghost
	b2.pressed.connect(func():
		save_author.call()
		_copy_code(DrawnLevel.share_code(entry.id, true), true))
	# fichier .pinpouin : PC (dossier) et navigateur (téléchargement) ; pas sur téléphone
	if not Settings.is_mobile_device:
		var b3 := _button("Télécharger le fichier" if Settings.is_web else "Exporter un fichier (.pinpouin)", col, 0)
		b3.pressed.connect(func():
			save_author.call()
			var path := DrawnLevel.export_file(entry.id, str(entry.name))
			if path == "":
				_popup_msg.text = "Impossible d'écrire le fichier."
			elif Settings.is_web:
				_popup_msg.text = "Fichier téléchargé : " + path
			else:
				OS.shell_open(ProjectSettings.globalize_path(DrawnLevel.EXPORT_DIR))
				_popup_msg.text = "Fichier enregistré : " + ProjectSettings.globalize_path(path))
	col.add_child(_popup_msg)
	_button("Fermer", col, 0).pressed.connect(_close_popup)


func _copy_code(code: String, with_ghost: bool) -> void:
	if code == "":
		_popup_msg.text = "Ce niveau n'est pas encore enregistré."
		return
	DisplayServer.clipboard_set(code)
	_popup_msg.text = "Code copié (%d Ko%s) ! Colle-le dans un message ; ton ami le colle dans « Ajouter un code »." % [
		maxi(1, code.length() / 1024), ", avec ton fantôme" if with_ghost else ""]


## « Ajouter un code » : coller le code d'un niveau reçu
func _open_import() -> void:
	var col := _open_popup("Ajouter un niveau reçu")
	_label(col, "Colle ici le code (il commence par PINPOUIN-NIVEAU) :")
	var box := TextEdit.new()
	box.custom_minimum_size = Vector2(0, 110)
	box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_theme_font_size_override("font_size", 14)
	_light_text(box)
	col.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var paste := _button("Coller", row, 120)
	paste.pressed.connect(func(): box.text = DisplayServer.clipboard_get())
	var addb := _button("Ajouter", row, 140)
	addb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	addb.pressed.connect(func():
		var res := DrawnLevel.decode_code(box.text)
		if not res.ok:
			_popup_msg.add_theme_color_override("font_color", Color(1, 0.7, 0.5))
			_popup_msg.text = res.msg
			return
		_popup_msg.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75))
		_popup_msg.text = DrawnLevel.import_level(res.data)
		_fill_list())
	col.add_child(_popup_msg)
	_button("Fermer", col, 0).pressed.connect(_close_popup)


## Texte blanc sur fond sombre pour les champs de saisie (le thème du jeu met
## un texte foncé, illisible sur le fond des fenêtres)
func _light_text(c: Control) -> void:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.08, 0.16)
	st.border_color = Color(1, 1, 1, 0.5)
	st.set_border_width_all(2)
	st.set_corner_radius_all(6)
	st.content_margin_left = 8
	st.content_margin_right = 8
	c.add_theme_stylebox_override("normal", st)
	c.add_theme_stylebox_override("focus", st)
	c.add_theme_color_override("font_color", Color.WHITE)
	c.add_theme_color_override("caret_color", Color.WHITE)
	c.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.45))
