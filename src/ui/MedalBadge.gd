extends Control
# =============================================================================
#  [MODES 1.25] Pastille de médaille (bronze / argent / or), dessinée en code
# -----------------------------------------------------------------------------
#  Affichée au bout des boutons de course de la sélection des niveaux (mode
#  Score). Aucun nouvel asset : un disque de la couleur de la médaille, un
#  liseré clair et une petite étoile au centre.
#  medal : 0 = aucune (rien n'est dessiné), 1 = bronze, 2 = argent, 3 = or.
# =============================================================================

const COLORS := [Color(0, 0, 0, 0), Color(0.80, 0.50, 0.25), Color(0.80, 0.83, 0.88), Color(1.0, 0.82, 0.25)]

var medal: int = 0:
	set(value):
		medal = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(30, 30)


func _draw() -> void:
	if medal <= 0:
		return
	var c := size * 0.5
	var r: float = minf(size.x, size.y) * 0.45
	draw_circle(c, r, COLORS[medal])
	draw_arc(c, r, 0.0, TAU, 32, Color(1, 1, 1, 0.9), 2.0, true)
	# petite étoile à 5 branches
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + i * PI / 5
		var rr := r * (0.55 if i % 2 == 0 else 0.24)
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, Color(1, 1, 1, 0.9))
