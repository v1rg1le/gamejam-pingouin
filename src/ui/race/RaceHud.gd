extends CanvasLayer
# =============================================================================
#  RaceHud.gd — [FANTÔMES] chrono à l'écran + résultat à l'arrivée
# -----------------------------------------------------------------------------
#  Créé par RaceManager au début d'une course (niveaux avec arrivée seulement).
#  - En haut à gauche : temps en cours et record du niveau.
#  - À l'arrivée : grand bandeau "NOUVEAU RECORD !" ou "Temps : ... (record ...)".
#  Tout est dessiné en code (aucun nouvel asset).
#  [MULTI] (étape 6) en course réseau :
#   - grand compte à rebours "3, 2, 1, GO !" au centre (show_countdown) ;
#   - en haut à droite, le classement en direct (set_ranking) : les arrivés
#     avec leur temps, puis ceux encore en course.
# =============================================================================

var _time_label: Label
var _best_label: Label
var _result_panel: PanelContainer
var _result_label: Label
var _countdown_label: Label     # [MULTI] 3-2-1-GO
var _ranking_label: Label       # [MULTI] classement en direct
var _go_timer: float = 0.0      # [MULTI] durée d'affichage du "GO !"


func _ready() -> void:
	layer = 35  # au-dessus du jeu, sous le menu pause (60) et les boutons tactiles (50)
	var box := VBoxContainer.new()
	box.position = Vector2(18, 12)
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_time_label = _make_label(30, Color(1, 1, 1))
	_best_label = _make_label(17, Color(1, 0.94, 0.4))
	box.add_child(_time_label)
	box.add_child(_best_label)

	_result_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.1, 0.22, 0.88)
	style.border_color = Color(1, 0.94, 0.4)
	style.set_border_width_all(4)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(22)
	_result_panel.add_theme_stylebox_override("panel", style)
	_result_panel.visible = false
	_result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_label = _make_label(36, Color(1, 1, 1))
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_panel.add_child(_result_label)
	add_child(_result_panel)
	_result_panel.resized.connect(_center_result)

	# [MULTI] compte à rebours : très gros chiffres au centre de l'écran
	_countdown_label = _make_label(120, Color(1, 0.94, 0.4))
	_countdown_label.add_theme_constant_override("outline_size", 18)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown_label.offset_bottom = -260   # dans le haut de l'écran, pas sur le pingouin
	_countdown_label.visible = false
	add_child(_countdown_label)
	# [MULTI] classement : en haut à droite, sous le bouton pause tactile
	_ranking_label = _make_label(17, Color(1, 1, 1))
	_ranking_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ranking_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_ranking_label.offset_left = -320
	_ranking_label.offset_right = -18
	_ranking_label.offset_top = 84
	_ranking_label.visible = false
	add_child(_ranking_label)


func _make_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.14, 0.26))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(_delta: float) -> void:
	_time_label.text = RaceManager.format_time(RaceManager.race_time)
	# [MULTI] le "GO !" reste affiché 0,8 s puis disparaît
	if _go_timer > 0.0:
		_go_timer -= _delta
		if _go_timer <= 0.0:
			_countdown_label.visible = false


func set_best(best: float) -> void:
	if best == -2.0:   # [MULTI] code spécial envoyé par RaceManager avant le départ
		_best_label.text = "En attente des autres joueurs…"
		return
	_best_label.text = ("Record  " + RaceManager.format_time(best)) if best >= 0.0 else "Pas encore de record"


## [MULTI] Affiche le compte à rebours (secondes restantes ; <= 0 -> "GO !").
func show_countdown(remaining: float) -> void:
	_countdown_label.visible = true
	if remaining > 0.0:
		_countdown_label.text = str(ceili(remaining))
		_best_label.text = "Prêt ?"
	elif _go_timer <= 0.0:
		_countdown_label.text = "GO !"
		_go_timer = 0.8
		set_best(RaceManager.get_best_time(RaceManager.level_path))


## [MULTI] Classement en direct : liste [[nom, temps], ...] (temps -1 = en course).
func set_ranking(ranking: Array) -> void:
	var lines := PackedStringArray()
	var rank := 1
	for entry in ranking:
		if entry[1] >= 0.0:
			lines.append("%d. %s   %s" % [rank, entry[0], RaceManager.format_time(entry[1])])
			rank += 1
		else:
			lines.append("%s   …" % entry[0])
	_ranking_label.text = "\n".join(lines)
	_ranking_label.visible = ranking.size() > 0


func show_result(time: float, is_record: bool, previous_best: float) -> void:
	if is_record:
		_result_label.text = "NOUVEAU RECORD !\n" + RaceManager.format_time(time)
		if previous_best >= 0.0:
			_result_label.text += "  (-%.2f s)" % (previous_best - time)
		set_best(time)
	else:
		_result_label.text = "Temps : " + RaceManager.format_time(time) + "\nRecord : " + RaceManager.format_time(previous_best)
	_result_panel.visible = true
	_result_panel.reset_size()
	_center_result()


## [MULTI] Résultat d'une course en réseau : la place avant tout.
func show_multi_result(time: float, rank: int, total: int) -> void:
	var place := "1re place !" if rank == 1 else "%de place" % rank
	_result_label.text = place + "\n" + RaceManager.format_time(time)
	# d'autres joueurs encore en course ? (le classement se complète en haut à droite)
	var finished := 0
	for entry in NetSession.ranking():
		if entry[1] >= 0.0:
			finished += 1
	if finished < total:
		_result_label.text += "\nEn attente des autres…"
	_result_panel.visible = true
	_result_panel.reset_size()
	_center_result()


func _center_result() -> void:
	var vs: Vector2 = _result_panel.get_viewport_rect().size
	_result_panel.position = (vs - _result_panel.size) * 0.5 - Vector2(0, 80)
