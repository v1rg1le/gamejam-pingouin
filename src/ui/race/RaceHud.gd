extends CanvasLayer
# =============================================================================
#  RaceHud.gd — [FANTÔMES] chrono à l'écran + résultat à l'arrivée
# -----------------------------------------------------------------------------
#  Créé par RaceManager au début d'une course (niveaux avec arrivée seulement).
#  - En haut à gauche : temps en cours et record du niveau.
#  - À l'arrivée : grand bandeau "NOUVEAU RECORD !" ou "Temps : ... (record ...)".
#  Tout est dessiné en code (aucun nouvel asset).
# =============================================================================

var _time_label: Label
var _best_label: Label
var _result_panel: PanelContainer
var _result_label: Label


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


func set_best(best: float) -> void:
	_best_label.text = ("Record  " + RaceManager.format_time(best)) if best >= 0.0 else "Pas encore de record"


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


func _center_result() -> void:
	var vs: Vector2 = _result_panel.get_viewport_rect().size
	_result_panel.position = (vs - _result_panel.size) * 0.5 - Vector2(0, 80)
