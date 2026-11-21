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

	var title := Label.new()
	title.text = "MES NIVEAUX"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color.WHITE)
	col.add_child(title)
	var sub := Label.new()
	sub.text = "Tes niveaux dessinés. Record, médaille et fantôme en mode Score (comme les autres courses)."
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
	var add := _button("+  Nouveau niveau", bottom, 220)
	add.add_theme_font_size_override("font_size", 21)
	add.pressed.connect(_on_new)
	if Settings.controls != Settings.TOUCH:
		var first = _list.get_child(0).get_child(0) if _list.get_child_count() > 0 and _list.get_child(0).get_child_count() > 0 else add
		if first is Button:
			first.grab_focus()

	# Échelle : celle du jeu, réduite si l'écran est petit (téléphone 20:9)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	UiScaler.apply(_layer, clampf(minf(Settings.hud_scale(), minf(vp.x / 760.0, vp.y / 380.0)), 0.6, 2.0))


func _fill_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var levels := DrawnLevel.list_levels()
	if levels.is_empty():
		var empty := Label.new()
		empty.text = "Pas encore de niveau.\nTouche « + Nouveau niveau » et dessine le premier !"
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
		# JOUER : nom + record ; médaille au bout du bouton
		var path: String = DrawnLevel.race_path_of(e)
		var text: String = "▶  " + str(e.name)
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
		play.pressed.connect(func(): _on_play(id))
		_button("Modifier", row, 110).pressed.connect(func(): _on_edit(id))
		var del := _button("Supprimer", row, 120)
		del.pressed.connect(func(): _on_delete(id, del))


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
