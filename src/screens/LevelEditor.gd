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
#  [CRÉATEUR v2 1.80] Fondations du créateur complet (plan validé le 27/11) :
#   - SÉLECTION : toucher un bloc ou un trait le sélectionne ; on le glisse
#     pour le déplacer ; un bloc a deux poignées (rond du haut = tourner,
#     carré de droite = agrandir) ; panneau de réglages à droite (taille,
#     angle ; position exacte en Expert), Dupliquer, Supprimer ;
#   - OBJETS (ancien outil Grappin) : une palette à onglets (Objets, Terrain,
#     Décor, Gros blocs) ; en 1.80 on y pose la prise de grappin, les autres
#     éléments sont annoncés (grisés) pour les versions 1.81 à 1.83 ;
#   - Annuler / Refaire sur 60 pas (Ctrl+Z, Ctrl+Y ou Ctrl+Maj+Z) ;
#   - « ▶ D'ici » : tester depuis l'endroit regardé, avec une vitesse de
#     départ (réglable en Expert) ; la course ne compte pas pour les records ;
#     au retour, l'éditeur est au même endroit ;
#   - mode SIMPLE (par défaut : peu de boutons, 1 ou 2 curseurs) / EXPERT
#     (position exacte, magnétisme sur grille de 32 px et angles de 15°,
#     raccourcis Suppr, D = dupliquer, Échap) ;
#   - traits dans les deux sens (de droite à gauche aussi) et sans limite
#     de pente.
#
#  Le monde est dessiné par CE nœud (_draw), dans les coordonnées du jeu :
#  1 px ici = 1 px en course. L'aperçu utilise les MÊMES fonctions que le
#  niveau jouable : ce qu'on voit est ce qu'on joue.
# =============================================================================

## [CRÉATEUR v2 1.80] HOOK = outil « Objets » (palette), SELECT = Sélection
enum Tool { DRAW, HOOK, ERASE, MOVE, SELECT }

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
## [CRÉATEUR v2 1.80] Magnétisme (Expert) : grille des positions et pas des angles
const SNAP_GRID = 32.0
const SNAP_ANGLE_DEG = 15.0
## [CRÉATEUR v2 1.80] Taille d'un bloc de grappin à l'échelle 1 (demi-axes de
## l'ellipse de l'aperçu, px du monde)
const HOOK_RX = 110.0
const HOOK_RY = 42.0
## [CRÉATEUR v2 1.80] Vitesse de départ de « ▶ D'ici » en mode Simple (px/s)
const TEST_SPEED_SIMPLE = 600.0
const SELECT_COLOR = Color(1.0, 0.85, 0.2)                  # sélection (jaune)
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
# --- [CRÉATEUR v2 1.80] refaire, sélection, modes ---
var _redo: Array = []              # pile « Refaire » (vidée à chaque nouvelle modification)
var _draw_dir := 0                 # sens du trait en cours : 0 = pas encore décidé, 1 = droite, -1 = gauche
var expert := false                # mode Expert (sinon Simple)
var magnet := false                # magnétisme (Expert seulement)
var _sel: Dictionary = {}          # sélection : {kind: "hook" | "stroke", index} ou {}
var _drag := ""                    # geste sur la sélection : "", "move", "rotate", "scale"
var _drag_start := Vector2.ZERO    # point du monde au début du geste
var _drag_orig := {}               # bloc avant le geste (copie)
var _drag_delta := Vector2.ZERO    # décalage d'un trait pendant qu'on le glisse (aperçu)
var _drag_snap := {}               # état avant le geste (pour Annuler)
var _coalesce_key := ""            # curseurs : une seule étape « Annuler » par réglage continu
var _coalesce_time := 0
var palette_item := "hook"         # élément choisi dans la palette de l'outil Objets
var _palette_tab := 0

# --- interface ---
var _ui_layer: CanvasLayer
var _tool_buttons := {}            # Tool -> Button
var _undo_button: Button
var _redo_button: Button           # [CRÉATEUR v2 1.80]
var _mode_button: Button           # [CRÉATEUR v2 1.80] Simple / Expert
var _magnet_button: Button         # [CRÉATEUR v2 1.80] aimant (Expert)
var _palette: PanelContainer       # [CRÉATEUR v2 1.80] palette de l'outil Objets
var _settings: PanelContainer      # [CRÉATEUR v2 1.80] réglages de la sélection
var _speed_spin: SpinBox           # [CRÉATEUR v2 1.80] vitesse de départ de « D'ici » (Expert)
var _test_button: Button
var _auto_check: CheckButton
var _hint: Label
var _info: Label
var _penguin_tex: Texture2D = preload("res://icon.png")

const TOOL_HINTS := {
	Tool.DRAW: "Dessine le SOL (dans un sens ou dans l'autre, aussi raide que tu veux). Lève le doigt : ça fait un trou.",
	Tool.HOOK: "Choisis un élément dans la palette, puis touche le niveau pour le poser. Touche un bloc pour le sélectionner.",
	Tool.ERASE: "Touche ou glisse sur un trait ou un bloc pour l'effacer.",
	Tool.MOVE: "Glisse pour déplacer la vue. Molette ou − / + pour zoomer (deux doigts sur téléphone).",
	Tool.SELECT: "Touche un bloc ou un trait pour le choisir, glisse-le pour le déplacer. Bloc : rond = tourner, carré = agrandir.",
}


func _ready() -> void:
	DrawnLevel.load_once()
	# [CRÉATEUR v2 1.80] mode et magnétisme retrouvés d'une fois sur l'autre
	expert = bool(DrawnLevel.pref("expert", false))
	magnet = bool(DrawnLevel.pref("magnet", false))
	_build_background()
	cam = Camera2D.new()
	cam.position_smoothing_enabled = false
	add_child(cam)
	cam.make_current()
	_opened_race_path = DrawnLevel.race_path()
	_build_ui()
	# [VALIDATION 1.81] retour d'une course de validation (finie ou non)
	var was_validating := DrawnLevel.validating
	DrawnLevel.validating = false
	# [CRÉATEUR v2 1.80] retour d'un test : la vue d'avant, sinon tout le dessin
	if not DrawnLevel.editor_view.is_empty():
		cam.position = DrawnLevel.editor_view.pos
		cam.zoom = Vector2.ONE * float(DrawnLevel.editor_view.zoom)
		DrawnLevel.editor_view = {}
		_opened_at = 0   # (pas de recadrage au 1er redimensionnement)
	else:
		_frame_content()
	_refresh_ui()
	if DrawnLevel.last_validation_time > 0.0:
		_flash("✔ Niveau validé ! Ton temps : %s. Or du niveau : %s. Tu peux le partager." % [
			RaceManager.format_time(DrawnLevel.last_validation_time), RaceManager.format_time(DrawnLevel.validated_gold())])
		DrawnLevel.last_validation_time = 0.0
	elif was_validating:
		_flash("Validation interrompue : finis le niveau depuis le départ pour le valider.")
	# Taille d'écran changée (fenêtre redimensionnée, téléphone tourné, ou
	# taille définitive connue après le 1er affichage) : interface recalculée
	get_viewport().size_changed.connect(_rebuild_ui)


var _rebuild_pending := false
var _opened_at := Time.get_ticks_msec()   # ouverture de l'éditeur (ms)

## Reconstruit l'interface à la bonne échelle (une seule fois par frame)
func _rebuild_ui() -> void:
	if _rebuild_pending or not is_inside_tree():
		return   # (signal reçu pendant un changement d'écran : rien à faire)
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
	# [CRÉATEUR v2 1.80] raccourcis clavier
	if event is InputEventKey and event.pressed and not event.echo:
		if _shortcut(event):
			get_viewport().set_input_as_handled()
		return
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
		elif _drag != "":
			_drag_update(_to_world(mm.position))   # [CRÉATEUR v2 1.80]
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
			_draw_dir = 0
			_raw = PackedVector2Array([wp])
		Tool.HOOK:
			# [CRÉATEUR v2 1.80] outil Objets : un bloc touché est sélectionné
			# (on peut le régler tout de suite) ; ailleurs on pose l'élément
			# choisi dans la palette
			var hit := DrawnLevel.pick_at(wp, TOUCH_RADIUS_SCREEN * 2.5 / cam.zoom.x)
			if not hit.is_empty() and hit.kind in ["hook", "obj"]:
				_select(hit)
				_begin_drag("move", wp)
			elif palette_item == "hook":
				_push_undo()
				DrawnLevel.hooks.append(DrawnLevel.make_hook(_snap_pos(wp)))
				_changed()
				_select({"kind": "hook", "index": DrawnLevel.hooks.size() - 1})
			elif palette_item in DrawnLevel.VALID_TYPES:
				# [OBJETS 1.81] pose de l'objet choisi dans la palette
				_push_undo()
				var i := DrawnLevel.add_object(DrawnLevel.make_object(palette_item, _snap_pos(wp)))
				_changed()
				_select({"kind": "obj", "index": i})
		Tool.SELECT:
			_select_press(wp)
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
	if _drag != "":
		_end_drag()   # [CRÉATEUR v2 1.80]
		return
	if not _drawing:
		return
	_drawing = false
	var before := DrawnLevel.snapshot()
	if DrawnLevel.add_raw_stroke(_raw) > 0:
		_undo.append(before)
		if _undo.size() > UNDO_MAX:
			_undo.pop_front()
		_redo.clear()
		_sel = {}   # les numéros des traits ont pu changer
		_changed()
	elif _raw.size() > 1:
		_flash("Trait trop court, ou par-dessus un sol déjà dessiné : dessine là où il n'y a pas encore de sol.")
	_raw = PackedVector2Array()
	queue_redraw()


## Ajoute un point au trait en cours (seulement s'il avance vers la droite)
func _add_point(wp: Vector2) -> void:
	# [CRÉATEUR v2 1.80] dans les deux sens : le sens est décidé dès que le
	# doigt s'est écarté de 24 px en x du point de départ ; ensuite seuls les
	# points qui continuent dans ce sens comptent
	if _draw_dir == 0:
		if absf(wp.x - _raw[0].x) < 24.0:
			return
		_draw_dir = 1 if wp.x > _raw[0].x else -1
	if (wp.x - _raw[_raw.size() - 1].x) * _draw_dir > 2.0:
		_raw.append(wp)
		queue_redraw()


func _erase_at(screen_pos: Vector2) -> void:
	var snap := DrawnLevel.snapshot()
	if DrawnLevel.erase_at(_to_world(screen_pos), TOUCH_RADIUS_SCREEN * 2.0 / cam.zoom.x):
		_undo.append(snap)
		_redo.clear()
		_sel = {}   # les numéros ont changé
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
		if _last_screen.x > vp.x * AUTO_SCROLL_EDGE and _draw_dir >= 0:
			cam.position.x += AUTO_SCROLL_SPEED * delta / cam.zoom.x
			_add_point(_to_world(_last_screen))
		elif _last_screen.x < vp.x * (1.0 - AUTO_SCROLL_EDGE) and _draw_dir < 0:
			# [CRÉATEUR v2 1.80] même chose vers la gauche quand on trace à l'envers
			cam.position.x -= AUTO_SCROLL_SPEED * delta / cam.zoom.x
			_add_point(_to_world(_last_screen))


# --- 2. Modifications ------------------------------------------------------------

func _push_undo() -> void:
	_undo.append(DrawnLevel.snapshot())
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()
	_redo.clear()   # [CRÉATEUR v2 1.80] une nouvelle modification efface « Refaire »


## Après chaque modification : sauvegarde, boutons et aperçu à jour
func _changed() -> void:
	# [MES NIVEAUX 1.46] un record existait pour le dessin d'avant : il ne compte
	# plus (sinon on raccourcirait le niveau en gardant le record) ; on prévient
	# une fois. (Annuler qui revient au dessin d'origine le fait revenir.)
	var had_record: bool = _opened_race_path != "" and RaceManager.get_best_time(_opened_race_path) >= 0.0
	DrawnLevel.save()
	_refresh_ui()
	queue_redraw()
	if had_record and not _record_warned and DrawnLevel.race_path() != _opened_race_path:
		_record_warned = true
		_flash("Niveau modifié : le record repart de zéro (Annuler pour revenir).")


func _on_undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(DrawnLevel.snapshot())   # [CRÉATEUR v2 1.80]
	DrawnLevel.restore(_undo.pop_back())
	_sel = {}
	_changed()


## [CRÉATEUR v2 1.80] Refaire : l'inverse d'Annuler
func _on_redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(DrawnLevel.snapshot())
	DrawnLevel.restore(_redo.pop_back())
	_sel = {}
	_changed()


func _on_clear() -> void:
	if not DrawnLevel.is_playable() and DrawnLevel.hooks.is_empty():
		return
	_push_undo()   # « Tout effacer » s'annule aussi
	DrawnLevel.strokes = []
	DrawnLevel.hooks = []
	DrawnLevel.objects = []
	_sel = {}
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
	DrawnLevel.return_scene = DrawnLevel.EDITOR_SCENE   # après la course : retour ici
	DrawnLevel.test_from = Vector2.INF                  # [CRÉATEUR v2 1.80] vrai départ
	_remember_view()
	get_tree().change_scene_to_file(DrawnLevel.LEVEL_SCENE)


## [CRÉATEUR v2 1.80] « ▶ D'ici » : le test part du sol sous le milieu de
## l'écran, à la vitesse choisie ; il ne compte pas pour les records.
func _on_test_here() -> void:
	if not DrawnLevel.is_playable():
		_flash("Dessine d'abord un sol !")
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var from := DrawnLevel.start_point_near(_to_world(vp * 0.5).x)
	if from == Vector2.INF:
		return
	DrawnLevel.save()
	DrawnLevel.return_scene = DrawnLevel.EDITOR_SCENE
	DrawnLevel.test_from = from
	DrawnLevel.test_speed = _speed_spin.value if expert and _speed_spin != null else TEST_SPEED_SIMPLE
	_remember_view()
	get_tree().change_scene_to_file(DrawnLevel.LEVEL_SCENE)


## [CRÉATEUR v2 1.80] La vue actuelle sera retrouvée au retour du test
func _remember_view() -> void:
	DrawnLevel.editor_view = {"pos": cam.position, "zoom": cam.zoom.x}


## [MES NIVEAUX 1.46] en quittant l'éditeur (Retour, TESTER…), les fantômes des
## anciens dessins de ce niveau sont effacés (plus de retour possible par Annuler)
func _exit_tree() -> void:
	DrawnLevel.prune_ghosts()


## [MES NIVEAUX 1.46] « Retour » mène à la liste « Mes niveaux »
func _on_back() -> void:
	DrawnLevel.save()
	get_tree().change_scene_to_file(DrawnLevel.LIST_SCENE)


# --- [MES NIVEAUX 1.46] Nom du niveau ------------------------------------------------
var _name_button: Button
var _ui_root: Control              # Control racine de l'interface (porte le thème)
var _rename_panel: PanelContainer
var _rename_edit: LineEdit
## Chemin « record » du dessin à l'ouverture : s'il avait un record et que le
## dessin change, on prévient une fois que le record repart de zéro
var _opened_race_path := ""
var _record_warned := false


## Petite fenêtre « Nom du niveau » (clavier du téléphone compris)
func _open_rename() -> void:
	if _rename_panel != null and is_instance_valid(_rename_panel):
		_rename_panel.queue_free()
	_rename_panel = PanelContainer.new()
	_rename_panel.add_theme_stylebox_override("panel", _panel_style())
	_rename_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_rename_panel.offset_left = -190
	_rename_panel.offset_right = 190
	_rename_panel.offset_top = 70
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_rename_panel.add_child(col)
	var lab := Label.new()
	lab.text = "Nom du niveau"
	lab.add_theme_color_override("font_color", Color.WHITE)
	lab.add_theme_font_size_override("font_size", 19)
	col.add_child(lab)
	_rename_edit = LineEdit.new()
	_rename_edit.text = DrawnLevel.current_name
	_rename_edit.max_length = DrawnLevel.NAME_MAX
	_rename_edit.custom_minimum_size = Vector2(340, 46)
	_rename_edit.add_theme_font_size_override("font_size", 20)
	_rename_edit.add_theme_color_override("font_color", Color.WHITE)   # lisible sur le fond sombre
	_rename_edit.select_all_on_focus = true
	_rename_edit.text_submitted.connect(func(_t): _confirm_rename())
	col.add_child(_rename_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(row)
	_button("Annuler", row, 100).pressed.connect(func(): _rename_panel.queue_free())
	_button("OK", row, 100).pressed.connect(_confirm_rename)
	_ui_root.add_child(_rename_panel)   # dans le Control qui porte le thème du jeu
	_rename_edit.grab_focus()


func _confirm_rename() -> void:
	DrawnLevel.rename(_rename_edit.text)
	if is_instance_valid(_rename_panel):
		_rename_panel.queue_free()
	_refresh_ui()


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
	#    [CRÉATEUR v2 1.80] avec leur angle et leur taille
	var manual_i := 0
	for h in DrawnLevel.hook_list(isl):
		var pos: Vector2 = h.pos
		var selected: bool = not h.auto and _sel.get("kind", "") == "hook" and _sel.index == manual_i
		# taille réelle du bloc, mais jamais plus petit que ~22 px à l'écran
		var pts := _ellipse(pos, maxf(HOOK_RX * h.scale, 22.0 / z), maxf(HOOK_RY * h.scale, 9.0 / z), h.rot)
		draw_colored_polygon(pts, Color(HOOK_COLOR, 0.55 if h.auto else 0.95))
		pts.append(pts[0])
		draw_polyline(pts, SELECT_COLOR if selected else Color(1, 1, 1, 0.6 if h.auto else 1.0), (6.0 if selected else 3.0) / z, true)
		if not h.auto:
			manual_i += 1
		if selected:
			# poignées : rond = tourner (au-dessus), carré = agrandir (à droite)
			var hd := _hook_handles(_sel.index)
			draw_line(pos, hd.rotate, SELECT_COLOR, 3.0 / z)
			draw_circle(hd.rotate, 14.0 / z, SELECT_COLOR)
			draw_circle(hd.rotate, 8.0 / z, Color(0.1, 0.15, 0.3))
			draw_line(pos, hd.scale, SELECT_COLOR, 3.0 / z)
			draw_rect(Rect2(hd.scale - Vector2.ONE * 13.0 / z, Vector2.ONE * 26.0 / z), SELECT_COLOR)

	# d2. [CRÉATEUR v2 1.80] trait sélectionné : surligné en jaune (décalé
	#     pendant qu'on le glisse, pour voir où il va)
	if _sel.get("kind", "") == "stroke" and _sel.index < DrawnLevel.strokes.size():
		var st: PackedVector2Array = DrawnLevel.strokes[_sel.index]
		var moved := PackedVector2Array()
		for q in st:
			moved.append(q + _drag_delta)
		var ok: bool = _drag_delta == Vector2.ZERO or DrawnLevel.x_range_free(moved[0].x, moved[moved.size() - 1].x, _sel.index)
		draw_polyline(moved, SELECT_COLOR if ok else DANGER_COLOR, maxf(30.0, 9.0 / z), true)

	# d3. [OBJETS 1.81] objets et décors
	_draw_objects(z, font, fs)

	# e. départ (le pingouin, à sa vraie taille) et arrivée (faisceau jaune)
	#    [OBJETS 1.81] à l'endroit des objets « Départ » / « Arrivée » s'il y en a
	if not isl.is_empty():
		var first: PackedVector2Array = isl[0]
		var sx: float = minf(first[0].x + 150.0, first[first.size() - 1].x)
		var sp := Vector2(sx, DrawnLevel.surface_y_of(first, sx))
		var st_obj := DrawnLevel.first_object("start")
		if not st_obj.is_empty():
			sp = st_obj.pos + Vector2(0, 80)
		var ps: float = maxf(120.0, 40.0 / z)   # pingouin à sa vraie taille, ou 40 px à l'écran mini
		draw_texture_rect(_penguin_tex, Rect2(sp + Vector2(-ps * 0.5, -ps * 1.05), Vector2(ps, ps)), false)
		draw_string(font, sp + Vector2(-2.0 * fs, -ps * 1.05 - fs * 0.6), "DÉPART", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		var last: PackedVector2Array = isl[isl.size() - 1]
		var fp: Vector2 = last[last.size() - 1]
		var fin_obj := DrawnLevel.first_object("finish")
		if not fin_obj.is_empty():
			fp = fin_obj.pos
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
## [CRÉATEUR v2 1.80] + angle `rot` (radians)
func _ellipse(c: Vector2, rx: float, ry: float, rot := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 24:
		var a: float = TAU * i / 24.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return pts


# --- [CRÉATEUR v2 1.80] Sélection, poignées, réglages -----------------------------

## [OBJETS 1.81] L'élément sélectionné (bloc ou objet) : Dictionary
## {pos, rot, scale (, type, props)} — modifié directement par les gestes
func _item() -> Dictionary:
	return DrawnLevel.hooks[_sel.index] if _sel.kind == "hook" else DrawnLevel.objects[_sel.index]


## [OBJETS 1.81] Demi-taille (monde) de l'élément sélectionné
func _item_half() -> Vector2:
	if _sel.kind == "hook":
		var h: Dictionary = DrawnLevel.hooks[_sel.index]
		return Vector2(HOOK_RX, HOOK_RY) * h.scale
	return DrawnLevel.object_half(DrawnLevel.objects[_sel.index])


## [OBJETS 1.81] Poignées de la sélection (bloc ou objet) : {rotate, scale}.
## Une zone de caméra (rectangle droit) n'a pas de poignée « tourner » ; sa
## poignée « agrandir » est dans son coin et règle largeur et hauteur.
func _handles() -> Dictionary:
	var it := _item()
	var hh := _item_half()
	var z: float = cam.zoom.x
	if it.get("type", "") == "camera":
		return {"rotate": Vector2.INF, "scale": it.pos + hh}
	return {"rotate": it.pos + Vector2(0, -(hh.y + 70.0 / z)).rotated(it.rot),
		"scale": it.pos + Vector2(hh.x + 45.0 / z, 0).rotated(it.rot)}


## Positions (monde) des deux poignées du bloc n° i : {rotate, scale}
func _hook_handles(i: int) -> Dictionary:
	var h: Dictionary = DrawnLevel.hooks[i]
	var z: float = cam.zoom.x
	return {"rotate": h.pos + Vector2(0, -(HOOK_RY * h.scale + 70.0 / z)).rotated(h.rot),
		"scale": h.pos + Vector2(HOOK_RX * h.scale + 45.0 / z, 0).rotated(h.rot)}


## Magnétisme : position sur la grille (Expert + aimant), sinon inchangée
func _snap_pos(p: Vector2) -> Vector2:
	return p.snapped(Vector2.ONE * SNAP_GRID) if expert and magnet else p


func _snap_angle(a: float) -> float:
	return snappedf(a, deg_to_rad(SNAP_ANGLE_DEG)) if expert and magnet else a


## Choisit (ou vide, avec {}) la sélection et met le panneau de réglages à jour
func _select(sel: Dictionary) -> void:
	_sel = sel
	_drag_delta = Vector2.ZERO
	_rebuild_settings()
	queue_redraw()


## Appui avec l'outil Sélection : une poignée du bloc choisi, sinon un
## bloc ou un trait (sélectionné et glissé), sinon le vide (on déplace la vue)
func _select_press(wp: Vector2) -> void:
	var grab: float = 26.0 / cam.zoom.x
	if _sel.get("kind", "") in ["hook", "obj"]:
		var hd := _handles()
		if hd.rotate != Vector2.INF and wp.distance_to(hd.rotate) < grab:
			_begin_drag("rotate", wp)
			return
		if wp.distance_to(hd.scale) < grab:
			_begin_drag("scale", wp)
			return
	var hit := DrawnLevel.pick_at(wp, TOUCH_RADIUS_SCREEN * 2.0 / cam.zoom.x)
	if hit.is_empty():
		_select({})
		_panning = true   # glisser dans le vide = déplacer la vue
		return
	_select(hit)
	_begin_drag("move", wp)


func _begin_drag(kind: String, wp: Vector2) -> void:
	# le panneau de réglages se cache pendant le geste : sinon, en passant
	# dessous, il « mangeait » les mouvements de la souris / du doigt
	if _settings != null and is_instance_valid(_settings):
		_settings.visible = false
	_drag = kind
	_drag_start = wp
	_drag_snap = DrawnLevel.snapshot()
	_drag_delta = Vector2.ZERO
	if _sel.kind in ["hook", "obj"]:
		_drag_orig = _item().duplicate(true)


func _drag_update(wp: Vector2) -> void:
	if _sel.is_empty():
		return
	if _sel.kind == "stroke":
		# le trait n'est vraiment déplacé qu'au lâcher (aperçu jaune / rouge)
		_drag_delta = _snap_pos(wp - _drag_start) if not (expert and magnet) else (wp - _drag_start).snapped(Vector2.ONE * SNAP_GRID)
		queue_redraw()
		return
	var h: Dictionary = _item()   # [OBJETS 1.81] bloc ou objet
	match _drag:
		"move":
			h.pos = _snap_pos(_drag_orig.pos + (wp - _drag_start))
		"rotate":
			h.rot = _snap_angle((wp - h.pos).angle() + PI * 0.5)
		"scale":
			if h.get("type", "") == "camera":
				# zone de caméra : le coin suit le doigt (largeur et hauteur)
				var half: Vector2 = _snap_pos(wp - h.pos).abs().max(Vector2(400, 300))
				h.props.w = half.x * 2.0
				h.props.h = half.y * 2.0
			else:
				var base: float = HOOK_RX if _sel.kind == "hook" else DrawnLevel.OBJECT_HALF.get(h.type, Vector2(100, 100)).x
				var d: float = (wp - h.pos).length() - 45.0 / cam.zoom.x
				h.scale = clampf(d / base, DrawnLevel.HOOK_SCALE_MIN, DrawnLevel.HOOK_SCALE_MAX)
				if expert and magnet:
					h.scale = snappedf(h.scale, 0.25)
	queue_redraw()


func _end_drag() -> void:
	var kind := _drag
	_drag = ""
	if _settings != null and is_instance_valid(_settings):
		_settings.visible = true
	if _sel.is_empty():
		return
	if _sel.kind == "stroke":
		var delta := _drag_delta
		_drag_delta = Vector2.ZERO
		if delta.length() < 1.0:
			queue_redraw()
			return
		var st: PackedVector2Array = DrawnLevel.strokes[_sel.index]
		var first := st[0]
		if DrawnLevel.move_stroke(_sel.index, delta):
			_undo.append(_drag_snap)
			_redo.clear()
			# l'ordre des traits a pu changer : on retrouve le nôtre
			for i in DrawnLevel.strokes.size():
				if DrawnLevel.strokes[i][0].is_equal_approx(first + delta):
					_sel.index = i
			_changed()
			_rebuild_settings()
		else:
			_flash("Impossible : un trait ne peut pas passer au-dessus ou en dessous d'un autre sol.")
			queue_redraw()
		return
	# bloc ou objet : une étape « Annuler » seulement s'il a vraiment bougé
	var h: Dictionary = _item()
	if JSON.stringify(h) != JSON.stringify(_drag_orig):
		_undo.append(_drag_snap)
		if _undo.size() > UNDO_MAX:
			_undo.pop_front()
		_redo.clear()
		_changed()
		_rebuild_settings()
	elif kind == "move":
		queue_redraw()


## Copie de la sélection (un bloc : décalé de 160 px ; un trait : après le
## dernier trait du niveau)
func _duplicate_sel() -> void:
	if _sel.is_empty():
		return
	if _sel.kind == "obj" and DrawnLevel.objects[_sel.index].type in DrawnLevel.UNIQUE_TYPES:
		_flash("Il n'y a qu'un seul départ et une seule arrivée par niveau.")
		return
	_push_undo()
	if _sel.kind == "hook":
		var h: Dictionary = (DrawnLevel.hooks[_sel.index] as Dictionary).duplicate()
		h.pos += Vector2(160, 0)
		DrawnLevel.hooks.append(h)
		_changed()
		_select({"kind": "hook", "index": DrawnLevel.hooks.size() - 1})
	elif _sel.kind == "obj":
		# [OBJETS 1.81] copie décalée de la largeur de l'objet
		var o: Dictionary = (DrawnLevel.objects[_sel.index] as Dictionary).duplicate(true)
		o.pos += Vector2(DrawnLevel.object_half(o).x * 2.0 + 60.0, 0)
		DrawnLevel.objects.append(o)
		_changed()
		_select({"kind": "obj", "index": DrawnLevel.objects.size() - 1})
	else:
		var i := DrawnLevel.duplicate_stroke(_sel.index)
		_changed()
		_select({"kind": "stroke", "index": i})
		_flash("Copie posée après la fin du niveau.")


func _delete_sel() -> void:
	if _sel.is_empty():
		return
	_push_undo()
	if _sel.kind == "hook":
		DrawnLevel.hooks.remove_at(_sel.index)
	elif _sel.kind == "obj":
		DrawnLevel.objects.remove_at(_sel.index)
	else:
		DrawnLevel.strokes.remove_at(_sel.index)
	_select({})
	_changed()


## Raccourcis clavier. Renvoie vrai si la touche a servi.
func _shortcut(e: InputEventKey) -> bool:
	if _rename_panel != null and is_instance_valid(_rename_panel):
		return false   # on tape le nom du niveau
	var ctrl: bool = e.ctrl_pressed or e.meta_pressed
	match e.keycode:
		KEY_Z:
			if ctrl and e.shift_pressed:
				_on_redo()
				return true
			if ctrl:
				_on_undo()
				return true
		KEY_Y:
			if ctrl:
				_on_redo()
				return true
		KEY_DELETE, KEY_BACKSPACE:
			_delete_sel()
			return true
		KEY_D:
			if ctrl or expert:
				_duplicate_sel()
				return true
		KEY_ESCAPE:
			_select({})
			return true
	return false


## Un réglage continu (curseur, case numérique) : une seule étape « Annuler »
## tant qu'on règle la même chose sans pause d'une seconde
func _undo_for_setting(key: String) -> void:
	var now := Time.get_ticks_msec()
	if key != _coalesce_key or now - _coalesce_time > 1000:
		_push_undo()
	_coalesce_key = key
	_coalesce_time = now


## Panneau de réglages de la sélection (à droite). Simple : taille et angle
## d'un bloc ; Expert : en plus la position exacte (et celle d'un trait).
func _rebuild_settings() -> void:
	if _settings != null and is_instance_valid(_settings):
		_settings.visible = false   # (libéré à la fin de l'image : ne doit plus capter la souris)
		_settings.queue_free()
		_settings = null
	if _sel.is_empty() or _ui_root == null:
		return
	_settings = PanelContainer.new()
	_settings.visible = _drag == ""   # caché pendant un geste (voir _begin_drag)
	_settings.add_theme_stylebox_override("panel", _panel_style())
	_settings.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_settings.offset_left = -250
	_settings.offset_right = -6
	_settings.offset_top = TOP_BAR_H + 6
	_settings.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_settings.add_child(col)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", SELECT_COLOR)
	col.add_child(title)
	if _sel.kind == "hook":
		title.text = "Prise de grappin"
		var h: Dictionary = DrawnLevel.hooks[_sel.index]
		_slider_row(col, "Taille", DrawnLevel.HOOK_SCALE_MIN, DrawnLevel.HOOK_SCALE_MAX, 0.05, h.scale, func(v):
			_undo_for_setting("scale")
			DrawnLevel.hooks[_sel.index].scale = v
			_changed())
		_slider_row(col, "Angle", -180.0, 180.0, 15.0 if magnet and expert else 1.0, wrapf(rad_to_deg(h.rot), -180.0, 180.0), func(v):
			_undo_for_setting("rot")
			DrawnLevel.hooks[_sel.index].rot = deg_to_rad(v)
			_changed())
		if expert:
			_spin_row(col, "X", h.pos.x, func(v):
				_undo_for_setting("x")
				DrawnLevel.hooks[_sel.index].pos.x = v
				_changed())
			_spin_row(col, "Y", h.pos.y, func(v):
				_undo_for_setting("y")
				DrawnLevel.hooks[_sel.index].pos.y = v
				_changed())
	elif _sel.kind == "obj":
		_object_settings(col, title)
	else:
		title.text = "Trait de sol"
		var st: PackedVector2Array = DrawnLevel.strokes[_sel.index]
		var info := Label.new()
		info.text = "%d m de long" % int((st[st.size() - 1].x - st[0].x) / 64.0)
		info.add_theme_color_override("font_color", Color.WHITE)
		col.add_child(info)
		if expert:
			# position du début du trait (tout le trait suit)
			_spin_row(col, "Début X", st[0].x, func(v): _move_sel_stroke_to(Vector2(v, DrawnLevel.strokes[_sel.index][0].y)))
			_spin_row(col, "Début Y", st[0].y, func(v): _move_sel_stroke_to(Vector2(DrawnLevel.strokes[_sel.index][0].x, v)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	_button("Dupliquer", row, 108).pressed.connect(_duplicate_sel)
	_button("Supprimer", row, 108).pressed.connect(_delete_sel)
	_ui_root.add_child(_settings)
	_keep_selection_visible()


## Si le panneau de réglages (à droite) cache la sélection, la vue glisse
## pour la ramener dans la partie libre de l'écran (un bloc posé près du
## bord droit restait sous le panneau, impossible à toucher)
func _keep_selection_visible() -> void:
	await get_tree().process_frame   # taille du panneau connue après la mise en page
	if not is_inside_tree():
		return
	if _sel.is_empty() or _settings == null or not is_instance_valid(_settings) or _drag != "":
		return
	var wp: Vector2
	if _sel.kind in ["hook", "obj"]:
		wp = _item().pos
	else:
		var st: PackedVector2Array = DrawnLevel.strokes[_sel.index]
		wp = st[st.size() / 2]
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var sp: Vector2 = (wp - cam.position) * cam.zoom.x + vp * 0.5
	var left_edge: float = _settings.get_global_rect().position.x * _ui_layer.scale.x - 40.0
	if sp.x > left_edge:
		cam.position.x += (sp.x - left_edge + 80.0) / cam.zoom.x
		queue_redraw()


## Expert : déplace le trait sélectionné pour que son début soit en `p`
func _move_sel_stroke_to(p: Vector2) -> void:
	var st: PackedVector2Array = DrawnLevel.strokes[_sel.index]
	var first := st[0]
	var snap := DrawnLevel.snapshot()
	if DrawnLevel.move_stroke(_sel.index, p - first):
		_undo.append(snap)
		_redo.clear()
		for i in DrawnLevel.strokes.size():
			if DrawnLevel.strokes[i][0].is_equal_approx(p):
				_sel.index = i
		_changed()
	else:
		_flash("Impossible : un trait ne peut pas passer au-dessus ou en dessous d'un autre sol.")
		_rebuild_settings.call_deferred()


func _slider_row(parent: Node, label: String, lo: float, hi: float, step: float, value: float, on_change: Callable, shown: Callable = Callable()) -> void:
	var lab := Label.new()
	# la valeur s'affiche à côté du nom (×1.5 pour la taille, 45° pour l'angle ;
	# [OBJETS 1.81] ou le texte donné par `shown`, ex. le nom du dessin d'un œuf)
	var fmt := func(v: float) -> String:
		if shown.is_valid():
			return "%s  %s" % [label, shown.call(v)]
		return "%s  %s" % [label, ("×%.2f" % v) if hi <= 10.0 else ("%d°" % int(round(v)))]
	lab.text = fmt.call(value)
	lab.add_theme_color_override("font_color", Color.WHITE)
	lab.add_theme_font_size_override("font_size", 16)
	parent.add_child(lab)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = value
	sl.custom_minimum_size = Vector2(220, 30)
	sl.focus_mode = Control.FOCUS_NONE
	sl.value_changed.connect(on_change)
	sl.value_changed.connect(func(v): lab.text = fmt.call(v))
	parent.add_child(sl)


func _spin_row(parent: Node, label: String, value: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	var lab := Label.new()
	lab.text = label
	lab.custom_minimum_size = Vector2(76, 0)
	lab.add_theme_color_override("font_color", Color.WHITE)
	lab.add_theme_font_size_override("font_size", 16)
	row.add_child(lab)
	var sp := SpinBox.new()
	sp.min_value = -DrawnLevel.COORD_MAX
	sp.max_value = DrawnLevel.COORD_MAX
	sp.step = SNAP_GRID if magnet else 1.0
	sp.value = value
	sp.custom_minimum_size = Vector2(140, 34)
	sp.get_line_edit().add_theme_color_override("font_color", Color.WHITE)   # lisible sur le fond sombre
	sp.value_changed.connect(on_change)
	row.add_child(sp)
	parent.add_child(row)


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
## la barre du haut (~960 px avec le nom du niveau) et les deux barres + un peu de dessin (~330 px).
## Sur un téléphone 20:9, l'écran logique ne fait que ~1024 x 460 px.
func _ui_scale() -> float:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	return clampf(minf(Settings.hud_scale(), minf(vp.x / 960.0, vp.y / 330.0)), 0.6, 2.0)


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
	_ui_root = root
	_ui_layer.add_child(root)
	add_child(_ui_layer)
	var s := _ui_scale()
	var wide: bool = get_viewport().get_visible_rect().size.x / s > 1080.0

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
		title.text = " CRÉER "
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", Color(1, 0.95, 0.4))
		row.add_child(title)
	# [MES NIVEAUX 1.46] nom du niveau : toucher pour le renommer
	_name_button = _button(DrawnLevel.current_name, row, 150)
	_name_button.add_theme_color_override("font_color", Color(0.10, 0.15, 0.30))
	_name_button.clip_text = true
	_name_button.tooltip_text = "Renommer le niveau"
	_name_button.pressed.connect(_open_rename)
	# [CRÉATEUR v2 1.80] Annuler / Refaire en flèches (place gagnée pour les nouveaux boutons)
	_undo_button = _button("↶", row, 50)
	_undo_button.tooltip_text = "Annuler (Ctrl+Z)"
	_undo_button.pressed.connect(_on_undo)
	_redo_button = _button("↷", row, 50)
	_redo_button.tooltip_text = "Refaire (Ctrl+Y)"
	_redo_button.pressed.connect(_on_redo)
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
	# [CRÉATEUR v2 1.80] mode Simple / Expert, et aimant (Expert)
	_mode_button = _button("Expert" if expert else "Simple", row, 96)
	_mode_button.tooltip_text = "Mode Simple (peu de réglages) ou Expert (tous les réglages, aimant, raccourcis)"
	_mode_button.pressed.connect(func(): _set_mode(not expert))
	if expert:
		_magnet_button = _button("🧲", row, 50)
		_magnet_button.toggle_mode = true
		_magnet_button.button_pressed = magnet
		_magnet_button.tooltip_text = "Aimant : grille de 32 px et angles de 15°"
		_magnet_button.toggled.connect(func(on):
			magnet = on
			DrawnLevel.set_pref("magnet", on)
			_rebuild_settings())
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
	# [CRÉATEUR v2 1.80] + Sélection ; « Grappin » devient « Objets » (palette)
	for t in [[Tool.DRAW, "Dessiner"], [Tool.HOOK, "Objets"], [Tool.SELECT, "Sélection"], [Tool.ERASE, "Gomme"], [Tool.MOVE, "Déplacer"]]:
		var b := _button(t[1], brow, 96)
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
	# [CRÉATEUR v2 1.80] largeur mini : sinon, sur un écran étroit, le texte
	# était écrasé à une lettre par ligne et la barre débordait en hauteur
	_info.custom_minimum_size = Vector2(170, 0)
	brow.add_child(_info)
	# [CRÉATEUR v2 1.80] « ▶ D'ici » (+ vitesse de départ en Expert)
	if expert:
		_speed_spin = SpinBox.new()
		_speed_spin.min_value = 0
		_speed_spin.max_value = 2500
		_speed_spin.step = 100
		_speed_spin.value = float(DrawnLevel.pref("test_speed", TEST_SPEED_SIMPLE))
		_speed_spin.suffix = "px/s"
		_speed_spin.tooltip_text = "Vitesse de départ de « D'ici »"
		_speed_spin.custom_minimum_size = Vector2(118, 40)
		_speed_spin.get_line_edit().add_theme_color_override("font_color", Color.WHITE)
		_speed_spin.value_changed.connect(func(v): DrawnLevel.set_pref("test_speed", v))
		brow.add_child(_speed_spin)
	# [VALIDATION 1.81] « ✔ Valider » : finir le niveau depuis le départ (Score)
	var val := _button("✔ Valider", brow, 112)
	val.tooltip_text = "Finis ton niveau depuis le départ : ton temps devient l'or, et tu peux le partager"
	val.pressed.connect(_on_validate)
	var here := _button("▶ D'ici", brow, 104)
	here.tooltip_text = "Tester depuis le milieu de l'écran (ne compte pas pour les records)"
	here.pressed.connect(_on_test_here)
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
	# [CRÉATEUR v2 1.80] les barres ont plus de boutons (Refaire, mode, aimant,
	# Sélection, D'ici…) : si elles ne tiennent pas dans la largeur de l'écran,
	# toute l'interface est réduite juste ce qu'il faut (téléphone en paysage)
	var vp_w: float = get_viewport().get_visible_rect().size.x
	var need: float = maxf(top.get_combined_minimum_size().x, bottom.get_combined_minimum_size().x) + 14.0
	if need * s > vp_w:
		s = maxf(0.45, vp_w / need)
		UiScaler.apply(_ui_layer, s)
	# [CRÉATEUR v2 1.80] palette (outil Objets) et réglages de la sélection
	if tool == Tool.HOOK:
		_build_palette()
	_rebuild_settings()

func _set_tool(t: int) -> void:
	# [CRÉATEUR v2 1.80] la palette n'est affichée qu'avec l'outil Objets
	if t != tool or (t == Tool.HOOK and (_palette == null or not is_instance_valid(_palette))):
		if _palette != null and is_instance_valid(_palette):
			_palette.queue_free()
			_palette = null
		if t == Tool.HOOK and _ui_root != null:
			_build_palette()
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
		# [MES NIVEAUX 1.46] record du dessin actuel (mode Score)
		var best: float = RaceManager.get_best_time(DrawnLevel.race_path())
		if best >= 0.0:
			_info.text += "  ·  record " + RaceManager.format_time(best)
		if unsafe > 0:
			_info.text += "   ·   %d grand%s trou%s sans grappin (en orange)" % [unsafe, "s" if unsafe > 1 else "", "s" if unsafe > 1 else ""]
		# [VALIDATION 1.81] état de la validation
		var gold := DrawnLevel.validated_gold()
		_info.text += ("  ·  ✔ validé, or " + RaceManager.format_time(gold)) if gold > 0.0 else "  ·  pas encore validé"
	_undo_button.disabled = _undo.is_empty()
	_redo_button.disabled = _redo.is_empty()   # [CRÉATEUR v2 1.80]
	_name_button.text = "✏  " + DrawnLevel.current_name
	_test_button.disabled = isl.is_empty()
	if _auto_check.button_pressed != DrawnLevel.auto_hooks:
		_auto_check.set_pressed_no_signal(DrawnLevel.auto_hooks)


# --- [CRÉATEUR v2 1.80] Palette de l'outil Objets, mode Simple / Expert ---------
# Palette à onglets, sur la gauche (comme les onglets des Options). Tout ce
# qui existe dans les niveaux du jeu y est listé, dans l'ordre du plan ; ce
# qui arrive dans une prochaine version est grisé avec son numéro de version.
const PALETTE := [
	["Objets", [["hook", "Prise de grappin", ""], ["egg", "Œuf à grappiner", ""], ["boost", "Boost", ""],
		["start", "Départ", ""], ["finish", "Arrivée", ""], ["checkpoint", "Point de passage", ""],
		["sign", "Panneau flèche", ""], ["camera", "Zone de caméra", ""]]],
	["Terrain", [["draw", "Sol (outil Dessiner)", ""], ["ramp", "Tremplin", "1.82"], ["halfpipe", "Half-pipe", "1.82"],
		["bowl", "Bol", "1.82"], ["slope", "Rampe", "1.82"], ["bend", "Virage en pipe", "1.82"], ["upipe", "Virage en U", "1.82"],
		["ceiling", "Plafond", "1.82"], ["floating", "Plateforme flottante", "1.82"], ["wall", "Mur", "1.82"],
		["pillar", "Pilier", "1.82"], ["balcony", "Balcon de glace", "1.82"], ["stal", "Plateforme-stalactite", "1.82"],
		["cliff", "Falaise", "1.82"]]],
	["Décor", [["arch", "Arche", ""], ["podium", "Podium FIN", ""], ["bush", "Buisson", ""], ["igloo", "Igloo", ""],
		["colisee", "Colisée", ""], ["ice1", "Bloc de glace 1", ""], ["ice2", "Bloc de glace 2", ""], ["ice3", "Petit bloc de glace", ""]]],
	["Gros blocs", [["cave", "Caverne", "1.83"], ["void", "Zone de vide", "1.83"], ["pillars", "Motif piliers", "1.83"],
		["bigegg", "Grand œuf", "1.83"], ["endless", "Tronçon du Sans fin", "1.83"]]],
]


func _build_palette() -> void:
	if _palette != null and is_instance_valid(_palette):
		_palette.queue_free()
	_palette = PanelContainer.new()
	_palette.add_theme_stylebox_override("panel", _panel_style())
	_palette.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_palette.offset_left = 6
	_palette.offset_right = 236
	_palette.offset_top = TOP_BAR_H + 6
	_palette.offset_bottom = -BOTTOM_BAR_H - 40
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_palette.add_child(col)
	var tabs := TabBar.new()
	tabs.clip_tabs = false
	for tab in PALETTE:
		tabs.add_tab(tab[0])
	tabs.current_tab = _palette_tab
	tabs.focus_mode = Control.FOCUS_NONE
	tabs.add_theme_font_size_override("font_size", 14)
	tabs.tab_changed.connect(func(i):
		_palette_tab = i
		_build_palette.call_deferred())
	col.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var group := ButtonGroup.new()
	for item in PALETTE[_palette_tab][1]:
		var soon: String = item[2]
		var b := _button(item[1] + ("  (" + soon + ")" if soon != "" else ""), list)
		b.add_theme_font_size_override("font_size", 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = soon != ""
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = item[0] == palette_item
		var id: String = item[0]
		b.pressed.connect(func():
			if id == "draw":
				_set_tool(Tool.DRAW)   # le sol se dessine avec l'outil Dessiner
				return
			palette_item = id)
	_ui_root.add_child(_palette)


## Mode Simple (par défaut) / Expert ; retenu d'une partie à l'autre
func _set_mode(on: bool) -> void:
	expert = on
	DrawnLevel.set_pref("expert", on)
	_rebuild_ui()
	_flash("Mode Expert : position exacte, aimant (🧲), vitesse de « D'ici », raccourcis Suppr, D, Échap." if on else "Mode Simple : l'essentiel, avec de gros boutons.")


# --- [OBJETS 1.81] Réglages, aperçu et validation ---------------------------------

## Nom affiché de chaque type d'objet
const OBJ_NAMES := {"egg": "Œuf à grappiner", "boost": "Boost", "start": "Départ", "finish": "Arrivée",
	"checkpoint": "Point de passage", "sign": "Panneau flèche", "camera": "Zone de caméra",
	"arch": "Arche", "podium": "Podium FIN", "bush": "Buisson", "igloo": "Igloo", "colisee": "Colisée",
	"ice1": "Bloc de glace 1", "ice2": "Bloc de glace 2", "ice3": "Petit bloc de glace"}
const EGG_STYLE_NAMES := ["", "glace", "tacheté", "craquelé", "bonnet de neige", "bébé Pinpouin"]
## Types qu'on peut tourner (les autres restent droits)
const ROTATABLE := ["egg", "boost", "arch", "podium", "bush", "igloo", "colisee", "ice1", "ice2", "ice3"]


## Change une valeur de l'objet sélectionné (props si `prop`) avec une étape « Annuler »
func _set_obj(key: String, value, prop := false) -> void:
	_undo_for_setting(key)
	var o: Dictionary = DrawnLevel.objects[_sel.index]
	if prop:
		o.props[key] = value
	else:
		o[key] = value
	_changed()


## Réglages d'un objet : Simple = 1 ou 2 curseurs ; Expert = + position, angle
func _object_settings(col: VBoxContainer, title: Label) -> void:
	var o: Dictionary = DrawnLevel.objects[_sel.index]
	var t: String = o.type
	title.text = OBJ_NAMES.get(t, t)
	match t:
		"egg":
			_slider_row(col, "Dessin", 1, 5, 1, float(o.props.get("style", 1)), func(v): _set_obj("style", int(v), true),
				func(v): return EGG_STYLE_NAMES[int(v)])
			_slider_row(col, "Taille", DrawnLevel.HOOK_SCALE_MIN, DrawnLevel.HOOK_SCALE_MAX, 0.05, o.scale, func(v): _set_obj("scale", v))
		"boost":
			_slider_row(col, "Force", 0.0, 1.0, 0.05, float(o.props.get("strength", 0.35)), func(v): _set_obj("strength", v, true),
				func(v): return "%d %%" % int(round(v * 100.0)))
			_slider_row(col, "Angle", -180.0, 180.0, 15.0 if magnet and expert else 1.0, wrapf(rad_to_deg(o.rot), -180.0, 180.0), func(v): _set_obj("rot", deg_to_rad(v)))
			var air := CheckButton.new()
			air.text = "Boost en l'air"
			air.button_pressed = bool(o.props.get("in_air", false))
			air.focus_mode = Control.FOCUS_NONE
			for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
				air.add_theme_color_override(c, Color.WHITE)
			air.toggled.connect(func(on): _set_obj("in_air", on, true))
			col.add_child(air)
		"start":
			_slider_row(col, "Élan", 0.0, 2000.0, 50.0, float(o.props.get("speed", 0.0)), func(v): _set_obj("speed", v, true),
				func(v): return "%d px/s" % int(v))
		"sign":
			_slider_row(col, "Direction", 0, 7, 1, float(DrawnLevel.SIGN_DIRS.find(str(o.props.get("dir", "droite")))), func(v): _set_obj("dir", DrawnLevel.SIGN_DIRS[int(v)], true),
				func(v): return DrawnLevel.SIGN_DIRS[int(v)])
		"camera":
			_slider_row(col, "Largeur", 800.0, 9000.0, 100.0, float(o.props.get("w", 2400.0)), func(v): _set_obj("w", v, true), func(v): return "%d px" % int(v))
			_slider_row(col, "Hauteur", 600.0, 6000.0, 100.0, float(o.props.get("h", 1400.0)), func(v): _set_obj("h", v, true), func(v): return "%d px" % int(v))
			if expert:
				_slider_row(col, "Dézoom max", 0.1, 1.0, 0.05, float(o.props.get("zoom", 0.25)), func(v): _set_obj("zoom", v, true))
		"checkpoint", "finish":
			var info := Label.new()
			info.text = "Après une chute, on repart du dernier point atteint." if t == "checkpoint" else "La ligne d'arrivée (une seule par niveau)."
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.custom_minimum_size = Vector2(220, 0)
			info.add_theme_color_override("font_color", Color.WHITE)
			col.add_child(info)
		_:
			_slider_row(col, "Taille", DrawnLevel.HOOK_SCALE_MIN, DrawnLevel.HOOK_SCALE_MAX, 0.05, o.scale, func(v): _set_obj("scale", v))
	if expert:
		if t in ROTATABLE and t != "boost":
			_slider_row(col, "Angle", -180.0, 180.0, 15.0 if magnet else 1.0, wrapf(rad_to_deg(o.rot), -180.0, 180.0), func(v): _set_obj("rot", deg_to_rad(v)))
		_spin_row(col, "X", o.pos.x, func(v): _set_obj("pos", Vector2(v, DrawnLevel.objects[_sel.index].pos.y)))
		_spin_row(col, "Y", o.pos.y, func(v): _set_obj("pos", Vector2(DrawnLevel.objects[_sel.index].pos.x, v)))


## Aperçu d'un décor : les images (Sprite2D) de sa scène, gardées en cache
## [[texture, transform, rect]] (transform depuis la racine de la scène)
var _decor_cache := {}
func _decor_sprites(type: String) -> Array:
	if _decor_cache.has(type):
		return _decor_cache[type]
	var out: Array = []
	var root: Node = load(DrawnLevel.DECOR_SCENES[type]).instantiate()
	for sp in root.find_children("*", "Sprite2D", true, false):
		if sp.texture == null or not sp.visible:
			continue
		var xf: Transform2D = sp.transform
		var n: Node = sp.get_parent()
		while n != null and n != root and n is Node2D:
			xf = n.transform * xf
			n = n.get_parent()
		out.append([sp.texture, xf, sp.get_rect(), sp.region_rect if sp.region_enabled else Rect2(Vector2.ZERO, sp.texture.get_size() / Vector2(sp.hframes, sp.vframes))])
	root.free()
	_decor_cache[type] = out
	return out


## Images de l'aperçu, gardées en mémoire : une texture chargée dans une
## variable locale de _draw() était libérée avant l'affichage de l'image
## (elle apparaissait toute blanche)
var _tex_cache := {}
func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path)
	return _tex_cache[path]


## Dessine les objets (appelé par _draw) ; `z` = zoom de la vue
func _draw_objects(z: float, font: Font, fs: int) -> void:
	for i in DrawnLevel.objects.size():
		var o: Dictionary = DrawnLevel.objects[i]
		var sel: bool = _sel.get("kind", "") == "obj" and _sel.index == i
		var hh := DrawnLevel.object_half(o)
		var xf := Transform2D(o.rot, o.pos)
		match str(o.type):
			"egg":
				var tex: Texture2D = _tex("res://sprites/levels/gruyere/oeuf_%s.png" % Settings.EGG_STYLES[clampi(int(o.props.get("style", 1)), 1, 5)])
				draw_set_transform_matrix(xf.scaled_local(Vector2.ONE * 4.0 * o.scale))
				draw_texture_rect_region(tex, Rect2(-tex.get_size() * 0.5, tex.get_size()), Rect2(Vector2.ZERO, tex.get_size()))
			"sign":
				var tex: Texture2D = _tex("res://sprites/levels/egg/panneau_%s.png" % str(o.props.get("dir", "droite")))
				draw_set_transform_matrix(xf.scaled_local(Vector2.ONE * 5.0 * o.scale))
				draw_texture_rect_region(tex, Rect2(-tex.get_size() * 0.5, tex.get_size()), Rect2(Vector2.ZERO, tex.get_size()))
			"boost":
				# chevrons colorés selon la force (blanc -> jaune -> rouge)
				var k: float = float(o.props.get("strength", 0.35))
				var c: Color = Color.WHITE.lerp(Color(1, 0.85, 0.1), minf(1.0, k * 2.0)).lerp(Color(1, 0.2, 0.15), maxf(0.0, k * 2.0 - 1.0))
				draw_set_transform_matrix(xf)
				for j in 3:
					var x0: float = -hh.x + j * hh.x * 0.66
					draw_colored_polygon(PackedVector2Array([Vector2(x0, -hh.y), Vector2(x0 + hh.x * 0.5, 0), Vector2(x0, hh.y),
						Vector2(x0 + hh.x * 0.25, hh.y), Vector2(x0 + hh.x * 0.75, 0), Vector2(x0 + hh.x * 0.25, -hh.y)]), c)
				if bool(o.props.get("in_air", false)):
					draw_string(font, Vector2(-hh.x, -hh.y - 10.0), "EN L'AIR", HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.8), c)
			"checkpoint":
				draw_set_transform_matrix(xf)
				draw_line(Vector2.ZERO, Vector2(0, -220), Color(0.17, 0.23, 0.35), maxf(10.0, 3.0 / z))
				draw_colored_polygon(PackedVector2Array([Vector2(4, -220), Vector2(110, -185), Vector2(4, -150)]), Color(1, 0.82, 0.25))
			"camera":
				draw_set_transform_matrix(Transform2D(0.0, o.pos))
				var r := Rect2(-hh, hh * 2.0)
				draw_rect(r, Color(0.6, 0.4, 1.0, 0.10))
				draw_rect(r, Color(0.6, 0.4, 1.0, 0.85), false, 4.0 / z)
				draw_string(font, r.position + Vector2(12.0 / z, fs * 1.2), "Zone de caméra (dézoom %.2f)" % float(o.props.get("zoom", 0.25)), HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.85), Color(0.85, 0.75, 1.0))
			"start", "finish":
				pass   # dessinés avec le départ et l'arrivée (voir _draw)
			_:
				if DrawnLevel.DECOR_SCENES.has(o.type):
					for spr in _decor_sprites(o.type):
						draw_set_transform_matrix(xf.scaled_local(Vector2.ONE * o.scale) * spr[1])
						draw_texture_rect_region(spr[0], spr[2], spr[3])
		draw_set_transform_matrix(Transform2D.IDENTITY)
		if sel:
			# cadre jaune et poignées
			draw_set_transform_matrix(Transform2D(0.0 if o.type == "camera" else o.rot, o.pos))
			draw_rect(Rect2(-hh, hh * 2.0), SELECT_COLOR, false, 5.0 / z)
			draw_set_transform_matrix(Transform2D.IDENTITY)
			var hd := _handles()
			if hd.rotate != Vector2.INF and o.type in ROTATABLE:
				draw_line(o.pos, hd.rotate, SELECT_COLOR, 3.0 / z)
				draw_circle(hd.rotate, 14.0 / z, SELECT_COLOR)
				draw_circle(hd.rotate, 8.0 / z, Color(0.1, 0.15, 0.3))
			if not (o.type in ["start", "finish", "checkpoint"]):
				draw_rect(Rect2(hd.scale - Vector2.ONE * 13.0 / z, Vector2.ONE * 26.0 / z), SELECT_COLOR)


## « ✔ Valider » : course en mode Score depuis le vrai départ ; à l'arrivée,
## le temps devient l'or du niveau (DrawnLevel.record_validation)
func _on_validate() -> void:
	if not DrawnLevel.is_playable():
		_flash("Dessine d'abord un sol !")
		return
	DrawnLevel.save()
	DrawnLevel.validating = true
	DrawnLevel.last_validation_time = 0.0
	if DrawnLevel.validation_prev_mode < 0:
		DrawnLevel.validation_prev_mode = Settings.game_mode
	Settings.game_mode = Settings.MODE_SCORE   # la validation se court en mode Score
	DrawnLevel.return_scene = DrawnLevel.EDITOR_SCENE
	DrawnLevel.test_from = Vector2.INF
	_remember_view()
	get_tree().change_scene_to_file(DrawnLevel.LEVEL_SCENE)
