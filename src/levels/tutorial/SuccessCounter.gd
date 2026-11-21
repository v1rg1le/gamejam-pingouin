extends Node2D
class_name SuccessCounter
# =============================================================================
#  SuccessCounter.gd — [TUTO 1.41] compteur de réussites au-dessus de Pinpouin
# -----------------------------------------------------------------------------
#  Pendant un atelier du tuto, on voit juste sous le pingouin
#  combien de fois l'action a été réussie : « SAUT  ● ● ○ ». Le regard du
#  joueur est sur Pinpouin : c'est là que l'information doit être, pas dans
#  un coin de l'écran.
#   - set_goal(nom, besoin) : nouvel atelier (tous les ronds vides) ;
#   - set_count(n)          : n ronds pleins, petit « pop » quand ça monte ;
#   - flash(texte, couleur) : mot rapide au-dessus (« +1 ! », « Encore ! »).
#  Il suit le pingouin sans tourner avec lui (top_level), et reste lisible
#  quel que soit le zoom de la caméra (taille corrigée par le zoom).
#  Aucun asset : deux Label dessinés en code.
# =============================================================================

# SOUS le pingouin (unités écran) : au-dessus, il passait derrière la bulle du
# maître quand la caméra place Pinpouin dans le haut de l'écran (vu en test).
const OFFSET := Vector2(0, 95)

var player: Node2D = null
var _label: Label
var _flash: Label
var _flash_tween: Tween
var _name := ""
var _need := 0
var _count := 0


func _ready() -> void:
	top_level = true          # ne tourne pas avec le pingouin
	z_index = 60              # devant le décor et les panneaux
	_label = _make(30, Color(1, 1, 1))
	_flash = _make(34, Color(1, 0.94, 0.4))
	_flash.modulate.a = 0.0
	visible = false


func _make(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.07, 0.16))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(500, 44)
	l.position = Vector2(-250, -22)
	add_child(l)
	return l


func set_goal(goal_name: String, need: int) -> void:
	_name = goal_name
	_need = need
	_count = 0
	visible = need > 0
	_redraw()


func set_count(n: int) -> void:
	var up := n > _count
	_count = n
	_redraw()
	if up:
		_label.pivot_offset = _label.size * 0.5
		_label.scale = Vector2(1.35, 1.35)
		create_tween().tween_property(_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func flash(text: String, color: Color) -> void:
	_flash.text = text
	_flash.add_theme_color_override("font_color", color)
	_flash.position = Vector2(-250, 25)
	_flash.modulate.a = 1.0
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.set_parallel(true)
	_flash_tween.tween_property(_flash, "position:y", 55.0, 0.9)
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.9).set_delay(0.4)


# Le nom en texte, les ronds DESSINÉS (les caractères ● / ○ de la police
# sortaient tous pareils avec le contour : on ne voyait pas les réussites).
const PIP_R := 11.0          # rayon d'un rond
const PIP_GAP := 30.0        # écart entre deux ronds

func _redraw() -> void:
	_label.text = _name
	# le nom à gauche, les ronds à droite, l'ensemble centré sur le pingouin
	var name_w: float = _label.get_theme_font("font").get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	var total: float = name_w + 18.0 + _need * PIP_GAP
	_label.position.x = -total * 0.5 - (_label.size.x - name_w) * 0.5
	queue_redraw()


func _draw() -> void:
	if _need <= 0:
		return
	var name_w: float = _label.get_theme_font("font").get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	var total: float = name_w + 18.0 + _need * PIP_GAP
	var x0: float = -total * 0.5 + name_w + 18.0 + PIP_GAP * 0.5
	for i in _need:
		var c := Vector2(x0 + i * PIP_GAP, 0)
		draw_circle(c, PIP_R + 3.0, Color(0.04, 0.07, 0.16))            # contour sombre
		if i < _count:
			draw_circle(c, PIP_R, Color(1, 0.94, 0.4))                   # réussi : plein, jaune
		else:
			draw_circle(c, PIP_R, Color(1, 1, 1, 0.35))                  # à faire : vide
			draw_arc(c, PIP_R, 0.0, TAU, 24, Color(1, 1, 1), 2.5)


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	# taille constante à l'écran : on annule le zoom de la caméra
	var zoom := 1.0
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		zoom = maxf(cam.zoom.x, 0.05)
	scale = Vector2.ONE / zoom
	global_position = player.global_position + OFFSET / zoom
