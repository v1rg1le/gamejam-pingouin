extends Node2D
# =============================================================================
#  LevelEditor.gd — [CRÉATEUR 1.45] l'éditeur de niveau DESSINÉ
# -----------------------------------------------------------------------------
#  Écran ouvert par le bouton « Créer un niveau » de la sélection des niveaux.
#  On dessine le DESSUS du sol au doigt ou à la souris ; les blocs de glace,
#  les trous, les blocs de grappin, le départ et l'arrivée se forment tout
#  seuls (règles et nettoyage du trait : src/levels/drawn/DrawnLevel.gd).
#  « TESTER » lance tout de suite le niveau (src/levels/LevelDrawn.tscn) ;
#  après l'arrivée, ou avec le bouton « Éditer » en course, on revient ici.
#
#  Outils (barre du bas) :
#   - DESSINER : un trait = un îlot ; lever le doigt = trou avant le suivant.
#     On dessine de gauche à droite (les retours en arrière sont ignorés) ;
#     un trait au-dessus d'un sol existant est coupé (en rouge pendant le tracé).
#     Près du bord droit de l'écran, la vue avance toute seule.
#   - GRAPPIN : toucher pose un bloc accroche-grappin ; toucher un bloc posé
#     à la main le retire.
#   - GOMME : toucher (ou glisser sur) un trait ou un bloc l'efface.
#   - DÉPLACER : glisser déplace la vue.
#  Toujours disponibles : molette = zoom, clic droit / milieu = déplacer ;
#  sur téléphone, deux doigts = déplacer + zoomer (pincer). Boutons − / +.
#  Barre du haut : Retour, Annuler, Tout effacer, Plafonds auto (blocs de
#  grappin automatiques au-dessus des trous larges).
#
#  Le monde est dessiné par CE nœud (_draw), dans les coordonnées du jeu :
#  1 px ici = 1 px en course. L'aperçu utilise les MÊMES fonctions que le
#  niveau jouable : ce qu'on voit est ce qu'on joue.
# =============================================================================

enum Tool { DRAW, HOOK, ERASE, MOVE }

## Zoom de la vue (Camera2D.zoom) : petit = on voit plus loin
const ZOOM_MIN = 0.06
const ZOOM_MAX = 0.9
const ZOOM_DEFAULT = 0.22
## Tolérance (en px d'ÉCRAN) pour toucher un trait / un bloc avec la gomme ou le grappin
const TOUCH_RADIUS_SCREEN = 34.0
## Défilement automatique quand on dessine près du bord droit (px d'écran / s)
const AUTO_SCROLL_SPEED = 520.0
const AUTO_SCROLL_EDGE = 0.86     # à partir de 86 % de la largeur de l'écran
## Nombre maximum d'étapes « Annuler »
const UNDO_MAX = 60
## Hauteur des barres de l'interface (px, avant mise à l'échelle) : sert à
## placer l'aide et à cadrer le dessin dans la zone libre
const TOP_BAR_H = 70.0
const BOTTOM_BAR_H = 70.0

## Couleurs de l'aperçu
const ICE_COLOR = Color(0.694118, 0.862745, 0.956863, 1)   # remplissage de sol.tscn
const EDGE_COLOR = Color(0.23, 0.55, 0.85)                 # le « trait bleu » du croquis
const STROKE_COLOR = Color(0.05, 0.22, 0.55)               # trait en cours
const HOOK_COLOR = Color(0.62, 0.66, 0.72)                 # les ronds gris du croquis
const DANGER_COLOR = Color(1.0, 0.25, 0.2)
const WARN_COLOR = Color(1.0, 0.55, 0.1)                   # grand trou sans grappin (orange)

var tool: int = Tool.DRAW
var cam: Camera2D

# --- trait en cours / gestes ---
var _raw := PackedVector2Array()   # positions du doigt (monde) du trait en cours
var _drawing := false
var _erasing := false
var _panning := false
var _last_screen := Vector2.ZERO   # dernière position du pointeur (écran)
var _touches := {}                 # doigts posés : index -> position écran
var _two_finger := false           # geste à deux doigts en cours (dessin suspendu)
var _pinch_center := Vector2.ZERO
var _pinch_dist := 0.0
var _undo: Array = []              # pile de DrawnLevel.snapshot()

# --- interface ---
var _ui_layer: CanvasLayer
var _tool_buttons := {}            # Tool -> Button
var _undo_button: Button
var _test_button: Button
var _auto_check: CheckButton
var _hint: Label
var _info: Label
var _penguin_tex: Texture2D = preload("res://icon.png")

const TOOL_HINTS := {
	Tool.DRAW: "Dessine le SOL de gauche à droite. Lève le doigt : ça fait un trou. Le jeu crée les blocs tout seul.",
	Tool.HOOK: "Touche pour poser un bloc de grappin. Touche un bloc posé à la main pour le retirer.",
	Tool.ERASE: "Touche ou glisse sur un trait ou un bloc pour l'effacer.",
	Tool.MOVE: "Glisse pour déplacer la vue. Molette ou − / + pour zoomer (deux doigts sur téléphone).",
}


func _ready() -> void:
	DrawnLevel.load_once()
	_build_background()
	cam = Camera2D.new()
	cam.position_smoothing_enabled = false
	add_child(cam)
	cam.make_current()
	_build_ui()
	_frame_content()
	_refresh_ui()
	# Taille d'écran changée (fenêtre redimensionnée, téléphone tourné, ou
	# taille définitive connue après le 1er affichage) : interface recalculée
	get_viewport().size_changed.connect(_rebuild_ui)


var _rebuild_pending := false
var _opened_at := Time.get_ticks_msec()   # ouverture de l'éditeur (ms)

## Reconstruit l'interface à la bonne échelle (une seule fois par frame)
func _rebuild_ui() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	await get_tree().process_frame
	_rebuild_pending = false
	if not is_inside_tree():
		return
	var hint_text: String = _hint.text
	_ui_layer.queue_free()
	_tool_buttons = {}
	_build_ui()
	_refresh_ui()
	_hint.text = hint_text
	# juste après l'ouverture (taille définitive de l'écran), on recadre le dessin
	if Time.get_ticks_msec() - _opened_at < 1500:
		_frame_content()
		queue_redraw()


# --- 1. Gestes ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Deux doigts (téléphone) : déplacer + zoomer ; le trait en cours est annulé
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() >= 2:
			_start_two_finger()
		elif _touches.is_empty():
			_two_finger = false
		return
	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _two_finger and _touches.size() >= 2:
			_update_two_finger()
		return
	# Gestes de pavé tactile (portable)
	if event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
		return
	if event is InputEventPanGesture:
		cam.position += event.delta * 12.0 / cam.zoom.x
		queue_redraw()
		return
	if _two_finger:
		return   # la souris « émulée » du 1er doigt est ignorée pendant un geste à deux doigts
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		_last_screen = mb.position
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.15)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / 1.15)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press(mb.position)
			else:
				_release()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		_last_screen = mm.position
		if _panning:
			cam.position -= mm.relative / cam.zoom.x
			queue_redraw()
		elif _drawing:
			_add_point(_to_world(mm.position))
		elif _erasing:
			_erase_at(mm.position)


## Appui (clic gauche ou un doigt) selon l'outil choisi
func _press(screen_pos: Vector2) -> void:
	var wp := _to_world(screen_pos)
	match tool:
		Tool.DRAW:
			_drawing = true
			_raw = PackedVector2Array([wp])
		Tool.HOOK:
			_push_undo()
			DrawnLevel.toggle_hook(wp, TOUCH_RADIUS_SCREEN * 2.5 / cam.zoom.x)
			_changed()
		Tool.ERASE:
			_erasing = true
			_erase_at(screen_pos)
		Tool.MOVE:
			_panning = true
	queue_redraw()


## Relâchement : fin du trait, de la gomme ou du déplacement
func _release() -> void:
	_panning = false
	_erasing = false
	if not _drawing:
		return
	_drawing = false
	var before := DrawnLevel.snapshot()
	if DrawnLevel.add_raw_stroke(_raw) > 0:
		_undo.append(before)
		if _undo.size() > UNDO_MAX:
			_undo.pop_front()
		_changed()
	elif _raw.size() > 1:
		_flash("Trait trop court, ou par-dessus un sol déjà dessiné : dessine dans le vide, de gauche à droite.")
	_raw = PackedVector2Array()
	queue_redraw()


## Ajoute un point au trait en cours (seulement s'il avance vers la droite)
func _add_point(wp: Vector2) -> void:
	if wp.x > _raw[_raw.size() - 1].x + 2.0:
		_raw.append(wp)
		queue_redraw()


func _erase_at(screen_pos: Vector2) -> void:
	var snap := DrawnLevel.snapshot()
	if DrawnLevel.erase_at(_to_world(screen_pos), TOUCH_RADIUS_SCREEN * 2.0 / cam.zoom.x):
		_undo.append(snap)
		_changed()


func _start_two_finger() -> void:
	_drawing = false        # le 2e doigt annule le trait commencé par le 1er
	_raw = PackedVector2Array()
	_panning = false
	_erasing = false
	_two_finger = true
	var pts: Array = _touches.values()
	_pinch_center = (pts[0] + pts[1]) * 0.5
	_pinch_dist = maxf(1.0, (pts[0] as Vector2).distance_to(pts[1]))
	queue_redraw()


func _update_two_finger() -> void:
	var pts: Array = _touches.values()
	var c: Vector2 = (pts[0] + pts[1]) * 0.5
	var d: float = maxf(1.0, (pts[0] as Vector2).distance_to(pts[1]))
	cam.position -= (c - _pinch_center) / cam.zoom.x
	_zoom_at(c, d / _pinch_dist)
	_pinch_center = c
	_pinch_dist = d


## Zoom en gardant fixe le point du monde sous `screen_pos`
func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := _to_world(screen_pos)
	var z: float = clampf(cam.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	cam.zoom = Vector2(z, z)
	cam.position += before - _to_world(screen_pos)
	queue_redraw()


## Écran -> monde. Calcul direct (la Camera2D ne met à jour la vue qu'à la
## frame suivante : get_global_mouse_position() serait en retard après un zoom).
func _to_world(screen_pos: Vector2) -> Vector2:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	return cam.position + (screen_pos - vp * 0.5) / cam.zoom.x


func _process(delta: float) -> void:
	# Défilement automatique en dessinant près du bord droit : on peut tracer
	# un long niveau d'un seul geste
	if _drawing:
		var vp: Vector2 = get_viewport().get_visible_rect().size
		if _last_screen.x > vp.x * AUTO_SCROLL_EDGE:
			cam.position.x += AUTO_SCROLL_SPEED * delta / cam.zoom.x
			_add_point(_to_world(_last_screen))


# --- 2. Modifications ------------------------------------------------------------

func _push_undo() -> void:
	_undo.append(DrawnLevel.snapshot())
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()


## Après chaque modification : sauvegarde, boutons et aperçu à jour
func _changed() -> void:
	DrawnLevel.save()
	_refresh_ui()
	queue_redraw()


func _on_undo() -> void:
	if _undo.is_empty():
		return
	DrawnLevel.restore(_undo.pop_back())
	_changed()


func _on_clear() -> void:
	if not DrawnLevel.is_playable() and DrawnLevel.hooks.is_empty():
		return
	_push_undo()   # « Tout effacer » s'annule aussi
	DrawnLevel.strokes = []
	DrawnLevel.hooks = []
	_changed()
	_flash("Tout est effacé. « Annuler » pour revenir en arrière.")


func _on_auto_toggled(on: bool) -> void:
	if on == DrawnLevel.auto_hooks:
		return
	_push_undo()
	DrawnLevel.auto_hooks = on
	_changed()


func _on_test() -> void:
	if not DrawnLevel.is_playable():
		_flash("Dessine d'abord un sol !")
		return
	DrawnLevel.save()
	get_tree().change_scene_to_file(DrawnLevel.LEVEL_SCENE)


func _on_back() -> void:
	DrawnLevel.save()
	get_tree().change_scene_to_file("res://src/screens/LevelSelectionScreen.tscn")


## Cadre la vue sur tout le dessin (ou une vue de départ si c'est vide)
func _frame_content() -> void:
	var isl := DrawnLevel.islands()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if isl.is_empty():
		cam.zoom = Vector2(ZOOM_DEFAULT, ZOOM_DEFAULT)
		cam.position = Vector2(vp.x * 0.5 / ZOOM_DEFAULT - 400.0, 0)
		return
	var r := Rect2(isl[0][0], Vector2.ZERO)
	for s in isl:
		for p in s:
			r = r.expand(p)
	for h in DrawnLevel.hook_list(isl):
		r = r.expand(h.pos)
	r = r.grow_individual(300.0, 300.0, 700.0, 300.0)   # à droite : place pour « ARRIVÉE »
	# Zone libre de l'écran (hors barre du haut, colonne d'outils et bas),
	# en px d'écran ; l'interface est agrandie par UiScaler sur téléphone
	var s: float = _ui_layer.scale.x
	var free := Rect2(Vector2(10, TOP_BAR_H) * s, vp - Vector2(20, TOP_BAR_H + BOTTOM_BAR_H + 30) * s)
	var z: float = clampf(minf(free.size.x / r.size.x, free.size.y / r.size.y), ZOOM_MIN, ZOOM_DEFAULT)
	cam.zoom = Vector2(z, z)
	# le centre du dessin tombe au centre de la zone libre
	cam.position = r.get_center() - (free.get_center() - vp * 0.5) / z


# --- 3. Dessin de l'aperçu -------------------------------------------------------

func _draw() -> void:
	var z: float = cam.zoom.x
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var view := Rect2(_to_world(Vector2.ZERO), vp / z)
	var font: Font = ThemeDB.fallback_font
	var fs: int = int(20.0 / z)   # taille de texte constante à l'écran

	# a. quadrillage léger (un carreau = 512 px, la taille d'environ 4 pingouins)
	var step := 512.0
	var gx: float = floor(view.position.x / step) * step
	while gx < view.end.x:
		draw_line(Vector2(gx, view.position.y), Vector2(gx, view.end.y), Color(1, 1, 1, 0.13), 1.5 / z)
		gx += step
	var gy: float = floor(view.position.y / step) * step
	while gy < view.end.y:
		draw_line(Vector2(view.position.x, gy), Vector2(view.end.x, gy), Color(1, 1, 1, 0.13), 1.5 / z)
		gy += step

	var isl := DrawnLevel.islands()
	if isl.is_empty() and not _drawing:
		var c := view.get_center()
		draw_string(font, c + Vector2(-9.0 * fs, 0), "Dessine le sol ici, de gauche à droite", HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 1.3), Color(1, 1, 1, 0.85))

	# b. îlots : bloc rempli jusqu'au fond + trait du dessus
	var bottom: float = DrawnLevel.floor_y(isl) if not isl.is_empty() else 0.0
	for s in isl:
		var poly := PackedVector2Array(s)
		poly.append(Vector2(s[s.size() - 1].x, bottom))
		poly.append(Vector2(s[0].x, bottom))
		draw_colored_polygon(poly, ICE_COLOR)
		# hachures (comme le croquis) pour bien voir que le jeu « remplit »
		var hx: float = s[0].x
		while hx < s[s.size() - 1].x:
			var top_y: float = DrawnLevel.surface_y_of(s, hx)
			var hb: float = minf(bottom, top_y + 360.0)
			draw_line(Vector2(hx, top_y + 40.0), Vector2(minf(hx + (hb - top_y - 40.0), s[s.size() - 1].x), hb), Color(1, 1, 1, 0.35), 2.0 / z)
			hx += 260.0
		draw_polyline(s, EDGE_COLOR, maxf(24.0, 5.0 / z), true)

	# c. grands trous sans grappin en orange : un simple saut ne suffit pas
	#    toujours (ça passe avec un bon tremplin et de la vitesse, d'où
	#    « conseillé » et pas « impossible » : le bot l'a franchi sur un tremplin)
	for g in DrawnLevel.unsafe_gaps(isl):
		var top: float = minf(g.y0, g.y1) - 700.0
		draw_rect(Rect2(g.x0, top, g.width, bottom - top), Color(WARN_COLOR, 0.22))
		draw_string(font, Vector2(g.x0 + 20.0 / z, top + fs * 1.5), "Grand trou !", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, WARN_COLOR)
		draw_string(font, Vector2(g.x0 + 20.0 / z, top + fs * 2.8), "Grappin ou tremplin conseillé", HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.8), WARN_COLOR)

	# d. blocs de grappin (ronds gris ; plus pâles = automatiques)
	for h in DrawnLevel.hook_list(isl):
		# taille réelle du bloc, mais jamais plus petit que ~22 px à l'écran
		var pts := _ellipse(h.pos, maxf(110.0, 22.0 / z), maxf(42.0, 9.0 / z))
		draw_colored_polygon(pts, Color(HOOK_COLOR, 0.55 if h.auto else 0.95))
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.6 if h.auto else 1.0), 3.0 / z, true)

	# e. départ (le pingouin, à sa vraie taille) et arrivée (faisceau jaune)
	if not isl.is_empty():
		var first: PackedVector2Array = isl[0]
		var sx: float = minf(first[0].x + 150.0, first[first.size() - 1].x)
		var sp := Vector2(sx, DrawnLevel.surface_y_of(first, sx))
		var ps: float = maxf(120.0, 40.0 / z)   # pingouin à sa vraie taille, ou 40 px à l'écran mini
		draw_texture_rect(_penguin_tex, Rect2(sp + Vector2(-ps * 0.5, -ps * 1.05), Vector2(ps, ps)), false)
		draw_string(font, sp + Vector2(-2.0 * fs, -ps * 1.05 - fs * 0.6), "DÉPART", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		var last: PackedVector2Array = isl[isl.size() - 1]
		var fp: Vector2 = last[last.size() - 1]
		var beam := PackedVector2Array([fp + Vector2(-70, 0), fp + Vector2(70, 0), fp + Vector2(42, -1600), fp + Vector2(-42, -1600)])
		draw_polygon(beam, PackedColorArray([Color(1, 0.95, 0.4, 0.6), Color(1, 0.95, 0.4, 0.6), Color(1, 0.95, 0.4, 0), Color(1, 0.95, 0.4, 0)]))
		draw_string(font, fp + Vector2(-2.3 * fs, -160.0), "ARRIVÉE", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.95, 0.4))

	# f. trait en cours (en rouge là où il passe au-dessus d'un sol existant)
	if _drawing and _raw.size() > 1:
		for i in _raw.size() - 1:
			var mid: float = (_raw[i].x + _raw[i + 1].x) * 0.5
			var col: Color = DANGER_COLOR if DrawnLevel._x_is_taken(mid) else STROKE_COLOR
			draw_line(_raw[i], _raw[i + 1], col, 6.0 / z, true)


## Points d'une ellipse (pour dessiner les blocs de grappin)
func _ellipse(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 24:
		var a: float = TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


# --- 4. Interface -------------------------------------------------------------

## Fond de ciel (dégradé) derrière le dessin
func _build_background() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	var sky := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.44, 0.66, 0.87))
	grad.set_color(1, Color(0.80, 0.90, 0.97))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	sky.texture = tex
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(sky)
	add_child(layer)


func _panel_style() -> StyleBoxFlat:
	var st := StyleBoxFlat.new()   # même style que les panneaux des menus
	st.bg_color = Color(0.105882, 0.152941, 0.270588, 0.78)
	st.border_color = Color(1, 1, 1, 0.55)
	st.set_border_width_all(2)
	st.set_corner_radius_all(12)
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	return st


func _button(text: String, parent: Node, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 46)
	b.add_theme_font_size_override("font_size", 19)
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b


## [CRÉATEUR 1.45] Échelle de l'interface de l'éditeur : celle du jeu
## (option + bonus téléphone), mais réduite si l'écran est trop petit pour
## la barre du haut (~800 px) et les deux barres + un peu de dessin (~330 px).
## Sur un téléphone 20:9, l'écran logique ne fait que ~1024 x 460 px.
func _ui_scale() -> float:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	return clampf(minf(Settings.hud_scale(), minf(vp.x / 800.0, vp.y / 330.0)), 0.6, 2.0)


## Interface (deux barres, pour laisser le maximum de place au dessin, même
## sur un téléphone en paysage) :
##  - en haut : Retour · (titre si la place le permet) · Annuler · Tout
##    effacer · Grappins auto · − · + · Tout voir ;
##  - en bas : les 4 outils · infos du niveau · TESTER ;
##  - juste au-dessus de la barre du bas : l'aide de l'outil (texte seul).
func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # les clics hors des boutons vont au dessin
	root.theme = preload("res://src/theme_main.tres")
	_ui_layer.add_child(root)
	add_child(_ui_layer)
	var s := _ui_scale()
	var wide: bool = get_viewport().get_visible_rect().size.x / s > 960.0

	# Barre du haut
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _panel_style())
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 6
	top.offset_right = -6
	top.offset_top = 6
	root.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	top.add_child(row)
	_button("◀  Retour", row, 100).pressed.connect(_on_back)
	if wide:
		var title := Label.new()
		title.text = "  CRÉER UN NIVEAU  "
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", Color(1, 0.95, 0.4))
		row.add_child(title)
	_undo_button = _button("Annuler", row, 96)
	_undo_button.pressed.connect(_on_undo)
	_button("Tout effacer", row, 110).pressed.connect(_on_clear)
	_auto_check = CheckButton.new()
	_auto_check.text = "Grappins auto"
	_auto_check.add_theme_font_size_override("font_size", 19)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		_auto_check.add_theme_color_override(c, Color.WHITE)
	_auto_check.focus_mode = Control.FOCUS_NONE
	_auto_check.button_pressed = DrawnLevel.auto_hooks
	_auto_check.toggled.connect(_on_auto_toggled)
	row.add_child(_auto_check)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_button("−", row, 46).pressed.connect(func(): _zoom_at(get_viewport().get_visible_rect().size * 0.5, 1.0 / 1.3))
	_button("+", row, 46).pressed.connect(func(): _zoom_at(get_viewport().get_visible_rect().size * 0.5, 1.3))
	_button("Tout voir", row, 96).pressed.connect(func():
		_frame_content()
		queue_redraw())

	# Barre du bas : outils · infos · TESTER
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", _panel_style())
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 6
	bottom.offset_right = -6
	bottom.offset_bottom = -6
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(bottom)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	bottom.add_child(brow)
	var group := ButtonGroup.new()
	for t in [[Tool.DRAW, "Dessiner"], [Tool.HOOK, "Grappin"], [Tool.ERASE, "Gomme"], [Tool.MOVE, "Déplacer"]]:
		var b := _button(t[1], brow, 100)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = t[0] == tool
		var which: int = t[0]
		b.pressed.connect(func(): _set_tool(which))
		_tool_buttons[t[0]] = b
	_info = Label.new()
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 15)
	_info.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	brow.add_child(_info)
	_test_button = _button("TESTER  ▶", brow, 150)
	_test_button.add_theme_font_size_override("font_size", 22)
	_test_button.pressed.connect(_on_test)

	# Aide de l'outil : texte seul (contour sombre), juste au-dessus de la barre du bas
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_left = 14
	_hint.offset_right = -14
	_hint.offset_bottom = -BOTTOM_BAR_H - 8
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_outline_color", Color(0.08, 0.12, 0.25))
	_hint.add_theme_constant_override("outline_size", 7)
	root.add_child(_hint)

	UiScaler.apply(_ui_layer, s)

func _set_tool(t: int) -> void:
	tool = t
	if _tool_buttons.has(t) and not _tool_buttons[t].button_pressed:
		_tool_buttons[t].set_pressed_no_signal(true)
	_hint.text = TOOL_HINTS[t]
	_hint.remove_theme_color_override("font_color")
	_hint.add_theme_color_override("font_color", Color.WHITE)


## Message temporaire (en jaune) à la place de l'aide de l'outil
func _flash(text: String) -> void:
	_hint.text = text
	_hint.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	var t := get_tree().create_timer(4.0)
	t.timeout.connect(func():
		if is_instance_valid(_hint) and _hint.text == text:
			_set_tool(tool))


func _refresh_ui() -> void:
	_set_tool(tool)
	var isl := DrawnLevel.islands()
	var n_hooks: int = DrawnLevel.hook_list(isl).size()
	var unsafe: int = DrawnLevel.unsafe_gaps(isl).size()
	if isl.is_empty():
		_info.text = "Pas encore de sol."
	else:
		var length_m: int = int((isl[isl.size() - 1][isl[isl.size() - 1].size() - 1].x - isl[0][0].x) / 64.0)
		_info.text = "%d îlot%s  ·  %d trou%s  ·  %d grappin%s  ·  %d m" % [
			isl.size(), "s" if isl.size() > 1 else "",
			isl.size() - 1, "s" if isl.size() > 2 else "",
			n_hooks, "s" if n_hooks > 1 else "", length_m]
		if unsafe > 0:
			_info.text += "   ·   %d grand%s trou%s sans grappin (en orange)" % [unsafe, "s" if unsafe > 1 else "", "s" if unsafe > 1 else ""]
	_undo_button.disabled = _undo.is_empty()
	_test_button.disabled = isl.is_empty()
	if _auto_check.button_pressed != DrawnLevel.auto_hooks:
		_auto_check.set_pressed_no_signal(DrawnLevel.auto_hooks)
