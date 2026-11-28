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
var _auto_check: Button           # [ICÔNES 1.82] bouton-icône à bascule (était une CheckButton)
var _hint: Label
var _info: Label
var _penguin_tex: Texture2D = preload("res://icon.png")

const TOOL_HINTS := {
	Tool.DRAW: "Dessine le SOL (dans un sens ou dans l'autre, aussi raide que tu veux). Lève le doigt : ça fait un trou.",
	Tool.HOOK: "Choisis un élément dans la palette, puis touche le niveau pour le poser. Touche un bloc pour le sélectionner.",
	Tool.ERASE: "Touche ou glisse sur un trait ou un bloc pour l'effacer.",
	Tool.MOVE: "Glisse pour déplacer la vue. Molette ou − / + pour zoomer (deux doigts sur téléphone).",
	Tool.SELECT: "Touche un élément pour le choisir, glisse-le pour le déplacer. Rond = tourner, carré = agrandir, losanges = étirer une forme.",
}


func _ready() -> void:
	DrawnLevel.load_once()
	# [CRÉATEUR v2 1.80] mode et magnétisme retrouvés d'une fois sur l'autre
	expert = bool(DrawnLevel.pref("expert", false))
	magnet = bool(DrawnLevel.pref("magnet", false))
	# [SURVOL 1.82] infos au survol : par défaut en Expert seulement
	hover_info = bool(DrawnLevel.pref(_hover_pref_key(), expert))
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
		elif _carving:
			_carve_add(_to_world(mm.position))   # [TAILLÉE 1.85]
		elif _drag != "":
			_drag_update(_to_world(mm.position))   # [CRÉATEUR v2 1.80]
		elif _drawing:
			_add_point(_to_world(mm.position))
		elif _erasing:
			_erase_at(mm.position)


## Appui (clic gauche ou un doigt) selon l'outil choisi
func _press(screen_pos: Vector2) -> void:
	var wp := _to_world(screen_pos)
	# [TAILLÉE 1.85] outil de taille actif sur le bloc sélectionné : le doigt
	# trace / creuse / rebouche (deux doigts déplacent toujours la vue)
	if _carve_target() >= 0:
		_carving = true
		_carve_pts = PackedVector2Array([wp])
		queue_redraw()
		return
	match tool:
		Tool.DRAW:
			_drawing = true
			_draw_dir = 0
			_raw = PackedVector2Array([wp])
		Tool.HOOK:
			# [CRÉATEUR v2 1.80] outil Objets : un bloc touché est sélectionné
			# (on peut le régler tout de suite) ; ailleurs on pose l'élément
			# choisi dans la palette
			if _press_handles(wp):   # [FORMES 1.83] étirer la forme qu'on vient de poser
				queue_redraw()
				return
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
				if palette_item == "carved":
					# [TAILLÉE 1.85] l'origin du bloc est son coin haut-gauche : on le
					# remonte pour que le doigt tienne l'entrée (en bas à gauche,
					# posée sur le sol) — sinon le bloc tombe trop bas pour se coller
					DrawnLevel.objects[i].pos.y -= (DrawnLevel.carved_entry_exit(DrawnLevel.objects[i])[0] as Vector2).y
				if DrawnLevel.is_shape(DrawnLevel.objects[i]):
					_snap_flash(DrawnLevel.snap_shape(i))   # [FORMES 1.83] se colle au sol
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
	if _carving:
		_finish_carve()   # [TAILLÉE 1.85]
		return
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
	_carving = false        # [TAILLÉE 1.85] (même chose pour un coup de pioche)
	_carve_pts = PackedVector2Array()
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
	# [ICÔNES 1.82] bulles d'aide ; [SURVOL 1.82] le halo pulse
	_tip_tick()
	if not _hover.is_empty():
		queue_redraw()
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
	_set_hover({})   # [SURVOL 1.82] les numéros des éléments ont pu changer
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
	var free := Rect2(Vector2(10, _top_bar_h) * s, vp - Vector2(20, _top_bar_h + _bottom_bar_h + 30) * s)
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

	# d3. [OBJETS 1.81] objets et décors ([FORMES 1.83] formes : jusqu'au fond commun)
	_draw_bottom = bottom if not isl.is_empty() else INF
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
		var fp: Vector2 = DrawnLevel.chain_end(last[last.size() - 1])   # [FORMES 1.83] au bout des formes collées
		var fin_obj := DrawnLevel.first_object("finish")
		if not fin_obj.is_empty():
			fp = fin_obj.pos
		var beam := PackedVector2Array([fp + Vector2(-70, 0), fp + Vector2(70, 0), fp + Vector2(42, -1600), fp + Vector2(-42, -1600)])
		draw_polygon(beam, PackedColorArray([Color(1, 0.95, 0.4, 0.6), Color(1, 0.95, 0.4, 0.6), Color(1, 0.95, 0.4, 0), Color(1, 0.95, 0.4, 0)]))
		draw_string(font, fp + Vector2(-2.3 * fs, -160.0), "ARRIVÉE", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.95, 0.4))

	# e2. [SURVOL 1.82] halo de l'élément survolé (par-dessus le reste)
	_draw_hover(z)

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
	var z: float = cam.zoom.x
	if _sel.kind == "obj" and DrawnLevel.is_shape(it):
		return _shape_handles(it, z)
	var hh := _item_half()
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
	if sel != _sel:
		carve_tool = ""   # [TAILLÉE 1.85] l'outil de taille ne vaut que pour son bloc
	_sel = sel
	if _hover == sel:
		_set_hover({})   # [SURVOL 1.82] sélectionné : le halo de survol s'efface
	_drag_delta = Vector2.ZERO
	_rebuild_settings()
	queue_redraw()


## Appui avec l'outil Sélection : une poignée du bloc choisi, sinon un
## bloc ou un trait (sélectionné et glissé), sinon le vide (on déplace la vue)
func _select_press(wp: Vector2) -> void:
	if _press_handles(wp):
		return
	var hit := DrawnLevel.pick_at(wp, TOUCH_RADIUS_SCREEN * 2.0 / cam.zoom.x)
	if hit.is_empty():
		_select({})
		_panning = true   # glisser dans le vide = déplacer la vue
		return
	_select(hit)
	_begin_drag("move", wp)


## Appui sur une poignée de la sélection (rond = tourner, carré = agrandir ;
## [FORMES 1.83] losanges = étirer en largeur / en hauteur). Vrai si oui.
func _press_handles(wp: Vector2) -> bool:
	var grab: float = 26.0 / cam.zoom.x
	if not (_sel.get("kind", "") in ["hook", "obj"]):
		return false
	var hd := _handles()
	for k in ["rotate", "scale", "w", "h"]:
		var p: Vector2 = hd.get(k, Vector2.INF)
		if p != Vector2.INF and wp.distance_to(p) < grab:
			_begin_drag(k, wp)
			return true
	return false


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
		# [FORMES 1.83] étirement : écart entre la dimension et la position de
		# la poignée (la poignée reste sous le doigt pendant le geste)
		if kind in ["w", "h"]:
			var lp: Vector2 = (wp - _item().pos).rotated(-float(_item().rot))
			var cur: float = DrawnLevel.shape_prop(_item(), kind)
			_stretch_offset = cur - (lp.x if kind == "w" else (lp.y if _item().type in SHAPE_H_DOWN else -lp.y))


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
		"w", "h":
			# [FORMES 1.83] étirer une forme (largeur / hauteur ou profondeur)
			var lp: Vector2 = (wp - h.pos).rotated(-float(h.rot))
			var v: float = (lp.x if _drag == "w" else (lp.y if h.type in SHAPE_H_DOWN else -lp.y)) + _stretch_offset
			if expert and magnet:
				v = snappedf(v, SNAP_GRID)
			h.props[_drag] = clampf(v, DrawnLevel.SHAPE_MIN, DrawnLevel.SHAPE_MAX)
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
	# [FORMES 1.83] une forme lâchée près du sol s'y colle (choix de l'équipe)
	if _sel.kind == "obj" and DrawnLevel.is_shape(_item()) and kind in ["move", "w", "h", "rotate"]:
		_snap_flash(DrawnLevel.snap_shape(_sel.index))
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
		if DrawnLevel.is_shape(o):
			# [FORMES 1.83] la copie se pose à la sortie de l'original (on enchaîne
			# tremplin + tremplin, half-pipe + half-pipe…)
			var g := DrawnLevel.shape_geometry(DrawnLevel.objects[_sel.index])
			if g.exit != Vector2.INF:
				o.pos += g.exit - DrawnLevel.shape_geometry(o).entry if DrawnLevel.shape_geometry(o).entry != Vector2.INF else Vector2.ZERO
			_snap_flash(DrawnLevel.snap_shape(DrawnLevel.objects.size() - 1))
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
	_settings.offset_top = _top_bar_h + 6
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
	if _tip != null and is_instance_valid(_tip):
		_ui_root.move_child(_tip, -1)   # [ICÔNES 1.82] la bulle reste au-dessus
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
		# [FORMES 1.84] forme : c'est le losange de largeur (à droite) qui doit
		# rester visible (il se cachait sous le panneau sur les formes larges)
		if _sel.kind == "obj" and DrawnLevel.is_shape(_item()):
			var hw: Vector2 = _handles().get("w", Vector2.INF)
			if hw != Vector2.INF:
				wp = hw
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


# --- [ICÔNES 1.82] Boutons en icônes et bulles d'aide ------------------------------
# Demande de l'équipe (27/11) : « que chaque bouton de cet éditeur soit une
# image ou une icône, avec au survol un rappel de ce qu'il fait si on reste
# dessus ». Choix de l'équipe : pixel art du jeu ; un petit mot sous l'icône
# en mode Simple, l'icône seule en mode Expert.
# Les icônes (32 x 32) et les vignettes de la palette (48 x 48) sont générées
# par tools/art/icones_editeur.py dans sprites/ui/editor/.

const ICON_DIR := "res://sprites/ui/editor/"

## Bulle de chaque bouton : id -> [nom, ce qu'il fait, raccourci ("" si aucun),
## mot écrit sous l'icône en mode Simple]. L'id est aussi le nom de l'icône.
const TIPS := {
	"retour": ["Retour", "Revenir à « Mes niveaux ». Ton niveau est enregistré à chaque modification.", "", "Retour"],
	"nom": ["Nom du niveau", "Toucher pour renommer le niveau.", "", ""],
	"annuler": ["Annuler", "Défait la dernière modification (jusqu'à 60 fois).", "Ctrl+Z", "Annuler"],
	"refaire": ["Refaire", "Refait ce qui vient d'être annulé.", "Ctrl+Y", "Refaire"],
	"effacer": ["Tout effacer", "Vide tout le niveau (Annuler le fait revenir).", "", "Effacer"],
	"grappins": ["Grappins auto", "Pose tout seul des prises de grappin au-dessus des trous trop larges pour un saut. Icône pâle = coupé.", "", "Grappins"],
	"simple": ["Mode Simple", "L'essentiel, avec de gros boutons. Toucher pour passer en mode Expert (tous les réglages).", "", "Simple"],
	"expert": ["Mode Expert", "Tous les réglages, l'aimant et les raccourcis. Toucher pour revenir en mode Simple.", "", "Expert"],
	"aimant": ["Aimant", "Grille de 32 px et angles de 15° pour poser, glisser et tourner. Icône pâle = coupé.", "", "Aimant"],
	"survol": ["Infos au survol", "Passe la souris sur un élément du niveau : il s'éclaire en bleu et ses infos s'affichent. Icône pâle = coupé.", "", "Infos"],
	"zoom_moins": ["Dézoomer", "Voir le niveau de plus loin.", "Molette · deux doigts", "Moins"],
	"zoom_plus": ["Zoomer", "Voir le niveau de plus près.", "Molette · deux doigts", "Plus"],
	"tout_voir": ["Tout voir", "Cadre la vue sur tout le niveau.", "", "Tout voir"],
	"dessiner": ["Dessiner", "Trace le dessus du sol, dans un sens ou dans l'autre, aussi raide que tu veux. Lever le doigt fait un trou.", "", "Dessiner"],
	"objets": ["Objets", "Ouvre la palette (grappins, œufs, boosts, départ, arrivée, panneaux, décors…), puis touche le niveau pour poser.", "", "Objets"],
	"selection": ["Sélection", "Touche un élément pour le régler, glisse-le pour le déplacer. Rond = tourner, carré = agrandir, losanges = étirer une forme.", "Suppr · D (Expert)", "Choisir"],
	"gomme": ["Gomme", "Touche ou glisse sur un trait, un bloc ou un objet pour l'effacer.", "", "Gomme"],
	"deplacer": ["Déplacer la vue", "Glisse pour te promener dans le niveau.", "Clic droit · deux doigts", "Bouger"],
	"valider": ["Valider", "Finis ton niveau depuis le départ : ton temps devient l'or et tu peux le partager.", "", "Valider"],
	"dici": ["Tester d'ici", "Lance Pinpouin depuis le milieu de l'écran. Ne compte pas pour les records.", "", "D'ici"],
	"tester": ["Tester", "Joue ton niveau depuis le départ.", "", ""],
}

var _top_bar_h: float = TOP_BAR_H        # hauteur réelle de la barre du haut (unités de l'interface)
var _bottom_bar_h: float = BOTTOM_BAR_H  # hauteur réelle de la barre du bas
var _top_panel: PanelContainer           # barres (pour savoir si la souris est sur l'interface)
var _bottom_panel: PanelContainer


## Bouton-icône des barres. `toggle` : bouton à bascule (outil, aimant…).
## Simple : icône + mot dessous ; Expert : icône seule (plus compact).
func _ibutton(id: String, parent: Node, toggle := false) -> Button:
	var b := Button.new()
	b.icon = _tex(ICON_DIR + id + ".png")
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = toggle
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tip: Array = TIPS.get(id, [id, "", "", id])
	if expert:
		b.custom_minimum_size = Vector2(50, 46)
	else:
		b.text = tip[3]
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(62, 58)
	b.set_meta("tip", id)
	_register_tip(b)
	parent.add_child(b)
	return b


## Bouton à bascule éteint (aimant coupé, grappins auto coupés…) : icône pâle
func _dim_if_off(b: Button) -> void:
	if b == null or not is_instance_valid(b):
		return
	var a := 1.0 if b.button_pressed else 0.4
	for c in ["icon_normal_color", "icon_hover_color", "icon_focus_color", "font_color", "font_hover_color"]:
		b.add_theme_color_override(c, Color(1, 1, 1, a))


# Bulles d'aide. Souris : la bulle s'ouvre après TIP_DELAY_MS sur le bouton
# et se ferme quand on le quitte ou qu'on clique. Doigt (pas de survol) :
# un appui long de TIP_DELAY_MS ouvre la bulle SANS déclencher le bouton
# (il est désactivé le temps de lever le doigt), elle reste 2 s.
const TIP_DELAY_MS := 550
var _tip: PanelContainer
var _tip_title: Label
var _tip_body: Label
var _tip_keys: Label
var _tip_button: Button = null    # bouton visé (bulle en attente ou affichée)
var _tip_due := 0                 # heure (ms) d'ouverture de la bulle
var _tip_by_press := false        # true = appui long au doigt
var _tip_hide_at := 0             # fermeture automatique (ms), 0 = non
var _mouse_is_touch := false      # dernier évènement souris = souris émulée par un doigt
var _suppressed: Array = []       # boutons désactivés le temps d'un appui long


func _build_tip(root: Control) -> void:
	_tip = PanelContainer.new()
	var st := _panel_style()
	st.bg_color = Color(0.06, 0.09, 0.18, 0.95)
	st.border_color = Color(1.0, 0.85, 0.3, 0.9)
	_tip.add_theme_stylebox_override("panel", st)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.add_child(col)
	_tip_title = _tip_label(col, 17, Color(1.0, 0.9, 0.4))
	_tip_body = _tip_label(col, 14, Color.WHITE)
	_tip_keys = _tip_label(col, 13, Color(0.6, 0.85, 1.0))
	root.add_child(_tip)


func _tip_label(parent: Node, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(250, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## Branche la bulle sur un bouton. La bulle vient de la méta « tip » : un id
## de TIPS, ou directement [nom, rôle, raccourci] (cases de la palette).
func _register_tip(b: Button) -> void:
	b.tooltip_text = ""   # pas de bulle Godot en double
	b.mouse_entered.connect(func():
		if not _mouse_is_touch:
			_tip_arm(b, false))
	b.mouse_exited.connect(func():
		if _tip_button == b and not _tip_by_press:
			_tip_hide())
	b.button_down.connect(func():
		if _mouse_is_touch:
			_tip_arm(b, true)    # doigt : on attend l'appui long
		else:
			_tip_hide())         # souris : un clic ferme la bulle
	b.button_up.connect(func():
		if _tip_button == b and _tip_by_press and not _tip.visible:
			_tip_button = null)  # appui court : rien à montrer


func _tip_arm(b: Button, by_press: bool) -> void:
	_tip_hide()
	_tip_button = b
	_tip_by_press = by_press
	_tip_due = Time.get_ticks_msec() + TIP_DELAY_MS


func _tip_hide() -> void:
	_tip_button = null
	_tip_hide_at = 0
	if _tip != null and is_instance_valid(_tip):
		_tip.visible = false


## Ouvre la bulle du bouton visé, sous lui (barre du haut) ou au-dessus
func _tip_show() -> void:
	var b := _tip_button
	if b == null or not is_instance_valid(b) or not b.is_visible_in_tree() or _tip == null:
		_tip_button = null
		return
	var meta = b.get_meta("tip", "")
	var t: Array = meta if meta is Array else TIPS.get(str(meta), [str(meta), "", ""])
	_tip_title.text = t[0]
	_tip_body.text = t[1]
	_tip_body.visible = t[1] != ""
	_tip_keys.text = ("Raccourci : " + t[2]) if t[2] != "" else ""
	_tip_keys.visible = t[2] != ""
	_tip.visible = true
	_tip.reset_size()
	var r: Rect2 = b.get_global_rect()
	var area: Vector2 = _ui_root.size
	var sz: Vector2 = _tip.get_combined_minimum_size()
	var y: float = r.end.y + 8.0 if r.get_center().y < area.y * 0.5 else r.position.y - sz.y - 8.0
	var x: float = clampf(r.get_center().x - sz.x * 0.5, 6.0, maxf(6.0, area.x - sz.x - 6.0))
	_tip.position = Vector2(x, clampf(y, 6.0, maxf(6.0, area.y - sz.y - 6.0)))
	if _tip_by_press:
		# appui long : le bouton ne se déclenchera pas au lever du doigt
		if not b.disabled:
			b.disabled = true
			_suppressed.append(b)


## Bulles et survol : à chaque évènement, AVANT l'interface (pour savoir si
## la « souris » vient d'un doigt, et rendre la main aux boutons suspendus)
func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_is_touch = event.device == InputEvent.DEVICE_ID_EMULATION
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		_mouse_is_touch = true
	var released: bool = (event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and not event.pressed)
	if released:
		for b in _suppressed:
			if is_instance_valid(b):
				b.disabled = false
		_suppressed.clear()
		if _tip != null and is_instance_valid(_tip) and _tip.visible and _tip_by_press:
			_tip_hide_at = Time.get_ticks_msec() + 2000
	if event is InputEventMouseButton and event.pressed and not _mouse_is_touch and _tip != null and is_instance_valid(_tip) and _tip.visible:
		_tip_hide()
	# [SURVOL 1.82] la vraie souris se déplace : élément survolé mis à jour
	if event is InputEventMouseMotion and not _mouse_is_touch:
		_update_hover(event.position)


## Horloge des bulles (appelée par _process)
func _tip_tick() -> void:
	var now := Time.get_ticks_msec()
	if _tip_button != null and _tip != null and is_instance_valid(_tip) and not _tip.visible and now >= _tip_due:
		_tip_show()
	if _tip_hide_at > 0 and now >= _tip_hide_at:
		_tip_hide()


# --- [SURVOL 1.82] Survol des éléments du niveau -----------------------------------
# Demande de l'équipe : « si le curseur survole un élément du niveau, il est
# en surbrillance et on donne ses infos avec ses stats ; ça doit différer
# visiblement de la sélection ; survol désactivable ». Donc :
#  - SURVOL : halo bleu glacier qui pulse doucement + petite fiche (lecture
#    seule) à côté du curseur, sans poignées ;
#  - SÉLECTION (inchangée) : cadre jaune plein, poignées, panneau de réglages.
# Bouton 👁 (« Infos au survol ») dans la barre du haut ; activé par défaut
# en Expert seulement (choix de l'équipe), retenu séparément pour chaque mode.
# Souris seulement : un doigt ne « survole » pas.

const HOVER_COLOR := Color(0.55, 0.95, 1.0)
var hover_info := false            # infos au survol actives ?
var _hover: Dictionary = {}        # élément survolé {kind, index} ou {}
var _hover_button: Button
var _hover_card: PanelContainer
var _hover_title: Label
var _hover_body: Label


func _hover_pref_key() -> String:
	return "hover_expert" if expert else "hover_simple"


func _build_hover_card(root: Control) -> void:
	_hover_card = PanelContainer.new()
	var st := _panel_style()
	st.bg_color = Color(0.05, 0.12, 0.2, 0.9)
	st.border_color = Color(HOVER_COLOR, 0.9)
	st.set_corner_radius_all(8)
	_hover_card.add_theme_stylebox_override("panel", st)
	_hover_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_card.visible = false
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	_hover_card.add_child(col)
	_hover_title = Label.new()
	_hover_title.add_theme_font_size_override("font_size", 16)
	_hover_title.add_theme_color_override("font_color", HOVER_COLOR)
	_hover_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_hover_title)
	_hover_body = Label.new()
	_hover_body.add_theme_font_size_override("font_size", 14)
	_hover_body.add_theme_color_override("font_color", Color.WHITE)
	_hover_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_hover_body)
	root.add_child(_hover_card)


## Le point d'écran est-il sur l'interface (barres, palette, réglages) ?
func _over_ui(screen_pos: Vector2) -> bool:
	if _ui_layer == null:
		return false
	var s: float = _ui_layer.scale.x
	for p in [_top_panel, _bottom_panel, _palette, _settings]:
		if p != null and is_instance_valid(p) and p.visible:
			var r: Rect2 = p.get_global_rect()
			if Rect2(r.position * s, r.size * s).has_point(screen_pos):
				return true
	return false


## Cherche l'élément sous la souris et place la fiche à côté du curseur
func _update_hover(screen_pos: Vector2) -> void:
	if not hover_info or _drawing or _drag != "" or _panning or _two_finger or _over_ui(screen_pos):
		_set_hover({})
		return
	var hit := DrawnLevel.pick_at(_to_world(screen_pos), TOUCH_RADIUS_SCREEN * 1.3 / cam.zoom.x)
	if not hit.is_empty() and not _sel.is_empty() and hit.kind == _sel.kind and hit.index == _sel.index:
		hit = {}   # déjà sélectionné : le cadre jaune et le panneau suffisent
	_set_hover(hit)
	if _hover_card != null and is_instance_valid(_hover_card) and _hover_card.visible:
		var s: float = _ui_layer.scale.x
		var p: Vector2 = screen_pos / s + Vector2(22, 22)
		var sz: Vector2 = _hover_card.get_combined_minimum_size()
		var area: Vector2 = _ui_root.size
		if p.x + sz.x > area.x - 6.0:
			p.x = screen_pos.x / s - sz.x - 16.0   # trop à droite : à gauche du curseur
		if p.y + sz.y > area.y - _bottom_bar_h:
			p.y = screen_pos.y / s - sz.y - 16.0  # trop bas : au-dessus
		_hover_card.position = p


func _set_hover(h: Dictionary) -> void:
	if h == _hover:
		return
	_hover = h
	queue_redraw()
	if _hover_card == null or not is_instance_valid(_hover_card):
		return
	if h.is_empty():
		_hover_card.visible = false
		return
	var info := _hover_info(h)
	_hover_title.text = info[0]
	_hover_body.text = info[1]
	_hover_card.visible = true
	_hover_card.reset_size()


## Titre et lignes de stats de l'élément h ({kind, index})
func _hover_info(h: Dictionary) -> Array:
	var lines: Array = []
	var title := ""
	match str(h.kind):
		"hook":
			var k: Dictionary = DrawnLevel.hooks[h.index]
			title = "Prise de grappin"
			lines.append("Taille ×%.2f   ·   angle %d°" % [k.scale, int(round(rad_to_deg(k.rot)))])
			lines.append("Position %d, %d" % [int(k.pos.x), int(k.pos.y)])
		"stroke":
			var st: PackedVector2Array = DrawnLevel.strokes[h.index]
			title = "Trait de sol"
			var steep := 0.0
			for i in st.size() - 1:
				var d: Vector2 = st[i + 1] - st[i]
				if d.length() > 1.0:
					steep = maxf(steep, rad_to_deg(atan2(absf(d.y), absf(d.x))))
			var w: float = st[st.size() - 1].x - st[0].x
			lines.append("Longueur %d m (%d px)" % [int(w / 64.0), int(w)])
			lines.append("Dénivelé %+d px   ·   pente max %d°" % [int(-(st[st.size() - 1].y - st[0].y)), int(round(steep))])
			lines.append("De x %d à x %d" % [int(st[0].x), int(st[st.size() - 1].x)])
		"obj":
			var o: Dictionary = DrawnLevel.objects[h.index]
			var t: String = o.type
			title = OBJ_NAMES.get(t, t)
			var size_angle := "Taille ×%.2f   ·   angle %d°" % [float(o.scale), int(round(rad_to_deg(o.rot)))]
			match t:
				"egg":
					lines.append("Dessin : " + EGG_STYLE_NAMES[clampi(int(o.props.get("style", 1)), 1, 5)])
					lines.append(size_angle)
				"boost":
					lines.append("Force %d %%   ·   %s" % [int(round(float(o.props.get("strength", 0.35)) * 100.0)),
						"en l'air" if bool(o.props.get("in_air", false)) else "au sol"])
					lines.append(size_angle)
				"start":
					lines.append("Élan de départ %d px/s" % int(o.props.get("speed", 0.0)))
				"finish":
					lines.append("Ligne d'arrivée (une seule par niveau)")
				"checkpoint":
					lines.append("Après une chute, on repart d'ici")
				"sign":
					lines.append("Direction : %s   ·   taille ×%.2f" % [str(o.props.get("dir", "droite")), float(o.scale)])
				"camera":
					lines.append("%d × %d px   ·   dézoom jusqu'à %.2f" % [int(o.props.get("w", 2400.0)), int(o.props.get("h", 1400.0)), float(o.props.get("zoom", 0.25))])
				_:
					if DrawnLevel.is_shape(o):
						lines.append_array(_shape_stats(o))   # [FORMES 1.83]
					else:
						lines.append(size_angle)
			lines.append("Position %d, %d" % [int(o.pos.x), int(o.pos.y)])
	if tool != Tool.SELECT:
		lines.append("(outil Sélection pour le régler)")
	return [title, "\n".join(lines)]


## Halo du survol (appelé à la fin de _draw) : bleu glacier qui pulse, sans
## poignées — bien différent du cadre jaune de la sélection
func _draw_hover(z: float) -> void:
	if _hover.is_empty():
		return
	var a: float = 0.5 + 0.25 * sin(Time.get_ticks_msec() * 0.006)
	var glow := Color(HOVER_COLOR, a * 0.45)
	var line := Color(HOVER_COLOR, a + 0.2)
	match str(_hover.kind):
		"hook":
			if _hover.index >= DrawnLevel.hooks.size():
				return
			var k: Dictionary = DrawnLevel.hooks[_hover.index]
			var pts := _ellipse(k.pos, maxf(HOOK_RX * k.scale, 22.0 / z) + 16.0 / z, maxf(HOOK_RY * k.scale, 9.0 / z) + 16.0 / z, k.rot)
			pts.append(pts[0])
			draw_polyline(pts, glow, 16.0 / z, true)
			draw_polyline(pts, line, 3.0 / z, true)
		"stroke":
			if _hover.index >= DrawnLevel.strokes.size():
				return
			var st: PackedVector2Array = DrawnLevel.strokes[_hover.index]
			draw_polyline(st, glow, maxf(60.0, 26.0 / z), true)
			draw_polyline(st, line, maxf(10.0, 3.0 / z), true)
		"obj":
			if _hover.index >= DrawnLevel.objects.size():
				return
			var o: Dictionary = DrawnLevel.objects[_hover.index]
			if DrawnLevel.is_shape(o):
				# [FORMES 1.83] halo le long du contour de la forme
				var pts: PackedVector2Array = DrawnLevel.shape_geometry(o, _draw_bottom).poly
				pts.append(pts[0])
				draw_polyline(pts, glow, 16.0 / z, true)
				draw_polyline(pts, line, 3.0 / z, true)
				return
			var hh: Vector2 = DrawnLevel.object_half(o) + Vector2.ONE * 14.0 / z
			draw_set_transform_matrix(Transform2D(0.0 if o.type == "camera" else float(o.rot), o.pos))
			draw_rect(Rect2(-hh, hh * 2.0), Color(HOVER_COLOR, 0.10))
			draw_rect(Rect2(-hh, hh * 2.0), glow, false, 14.0 / z)
			draw_rect(Rect2(-hh, hh * 2.0), line, false, 3.0 / z)
			draw_set_transform_matrix(Transform2D.IDENTITY)


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
	_top_panel = top   # [SURVOL 1.82]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	top.add_child(row)
	# [ICÔNES 1.82] tous les boutons des barres sont des icônes pixel art
	# (sprites/ui/editor/, générées par tools/art/icones_editeur.py) ; en mode
	# Simple un petit mot est écrit sous l'icône, en Expert l'icône est seule.
	# Au survol (souris, ~0,5 s) ou par appui long (doigt), une bulle rappelle
	# le nom, le rôle et le raccourci du bouton (voir « Bulles d'aide » plus bas).
	_ibutton("retour", row).pressed.connect(_on_back)
	if wide:
		var title := Label.new()
		title.text = " CRÉER "
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", Color(1, 0.95, 0.4))
		row.add_child(title)
	# [MES NIVEAUX 1.46] nom du niveau : toucher pour le renommer
	# (le nom du niveau reste écrit : c'est une information, avec l'icône crayon)
	_name_button = _button(DrawnLevel.current_name, row, 150)
	_name_button.icon = _tex(ICON_DIR + "nom.png")
	_name_button.add_theme_color_override("font_color", Color(0.10, 0.15, 0.30))
	_name_button.clip_text = true
	_name_button.set_meta("tip", "nom")
	_register_tip(_name_button)
	_name_button.pressed.connect(_open_rename)
	# [CRÉATEUR v2 1.80] Annuler / Refaire
	_undo_button = _ibutton("annuler", row)
	_undo_button.pressed.connect(_on_undo)
	_redo_button = _ibutton("refaire", row)
	_redo_button.pressed.connect(_on_redo)
	_ibutton("effacer", row).pressed.connect(_on_clear)
	# [ICÔNES 1.82] « Grappins auto » devient un bouton-icône à bascule (même
	# nom de variable `_auto_check` qu'avant ; éteint = icône pâle)
	_auto_check = _ibutton("grappins", row, true)
	_auto_check.button_pressed = DrawnLevel.auto_hooks
	_auto_check.toggled.connect(_on_auto_toggled)
	_auto_check.toggled.connect(func(_on): _dim_if_off(_auto_check))
	_dim_if_off(_auto_check)
	# [CRÉATEUR v2 1.80] mode Simple / Expert, et aimant (Expert)
	_mode_button = _ibutton("expert" if expert else "simple", row)
	_mode_button.pressed.connect(func(): _set_mode(not expert))
	if expert:
		_magnet_button = _ibutton("aimant", row, true)
		_magnet_button.button_pressed = magnet
		_magnet_button.toggled.connect(func(on):
			magnet = on
			DrawnLevel.set_pref("magnet", on)
			_dim_if_off(_magnet_button)
			_rebuild_settings())
		_dim_if_off(_magnet_button)
	# [SURVOL 1.82] œil : infos au survol des éléments du niveau (on / off)
	_hover_button = _ibutton("survol", row, true)
	_hover_button.button_pressed = hover_info
	_hover_button.toggled.connect(func(on):
		hover_info = on
		DrawnLevel.set_pref(_hover_pref_key(), on)
		_dim_if_off(_hover_button)
		_set_hover({})
		_flash("Infos au survol : activées." if on else "Infos au survol : coupées."))
	_dim_if_off(_hover_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_ibutton("zoom_moins", row).pressed.connect(func(): _zoom_at(get_viewport().get_visible_rect().size * 0.5, 1.0 / 1.3))
	_ibutton("zoom_plus", row).pressed.connect(func(): _zoom_at(get_viewport().get_visible_rect().size * 0.5, 1.3))
	_ibutton("tout_voir", row).pressed.connect(func():
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
	_bottom_panel = bottom   # [SURVOL 1.82]
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	bottom.add_child(brow)
	var group := ButtonGroup.new()
	# [CRÉATEUR v2 1.80] + Sélection ; « Grappin » devient « Objets » (palette)
	# [ICÔNES 1.82] outils en icônes (le 2e élément = nom de l'icône et de la bulle)
	for t in [[Tool.DRAW, "dessiner"], [Tool.HOOK, "objets"], [Tool.SELECT, "selection"], [Tool.ERASE, "gomme"], [Tool.MOVE, "deplacer"]]:
		var b := _ibutton(t[1], brow, true)
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
		_speed_spin.tooltip_text = "Vitesse de départ de « D'ici »"   # (bulle Godot : ce n'est pas un bouton)
		_speed_spin.custom_minimum_size = Vector2(118, 40)
		_speed_spin.get_line_edit().add_theme_color_override("font_color", Color.WHITE)
		_speed_spin.value_changed.connect(func(v): DrawnLevel.set_pref("test_speed", v))
		brow.add_child(_speed_spin)
	# [VALIDATION 1.81] « ✔ Valider » : finir le niveau depuis le départ (Score)
	_ibutton("valider", brow).pressed.connect(_on_validate)
	_ibutton("dici", brow).pressed.connect(_on_test_here)
	# [ICÔNES 1.82] TESTER, le bouton principal, garde son mot dans les deux
	# modes (icône à gauche du texte) : c'est lui qu'on cherche des yeux
	_test_button = _button("TESTER", brow, 150)
	_test_button.icon = _tex(ICON_DIR + "tester.png")
	_test_button.add_theme_font_size_override("font_size", 22)
	_test_button.set_meta("tip", "tester")
	_register_tip(_test_button)
	_test_button.pressed.connect(_on_test)

	# [ICÔNES 1.82] hauteur réelle des barres (plus hautes en mode Simple, à
	# cause du mot sous chaque icône) : la palette, le panneau de réglages,
	# l'aide et le cadrage se placent dessous / dessus
	_top_bar_h = maxf(TOP_BAR_H, top.get_combined_minimum_size().y + 6.0)
	_bottom_bar_h = maxf(BOTTOM_BAR_H, bottom.get_combined_minimum_size().y + 6.0)

	# Aide de l'outil : texte seul (contour sombre), juste au-dessus de la barre du bas
	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_left = 14
	_hint.offset_right = -14
	_hint.offset_bottom = -_bottom_bar_h - 8
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_outline_color", Color(0.08, 0.12, 0.25))
	_hint.add_theme_constant_override("outline_size", 7)
	root.add_child(_hint)

	# [SURVOL 1.82] fiche d'infos de l'élément survolé, et [ICÔNES 1.82] bulle
	# d'aide des boutons : créées une fois, cachées, au-dessus de tout
	_build_hover_card(root)
	_build_tip(root)

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
	_name_button.text = DrawnLevel.current_name   # [ICÔNES 1.82] le crayon est maintenant l'icône du bouton
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
	# [ICÔNES 1.82] plan décalé d'une version (la 1.82 est consacrée à
	# l'ergonomie) ; [FORMES 1.83] les formes du terrain arrivent en deux fois
	# (choix de l'équipe) : 10 formes en 1.83, balcon / plateforme-stalactite /
	# falaise en 1.84 ; gros blocs en 1.85
	["Terrain", [["draw", "Sol (outil Dessiner)", ""], ["ramp", "Tremplin", ""], ["halfpipe", "Half-pipe", ""],
		["bowl", "Bol", ""], ["slope", "Rampe", ""], ["bend", "Virage en pipe", ""], ["upipe", "Virage en U", ""],
		["ceiling", "Plafond", ""], ["floating", "Plateforme flottante", ""], ["wall", "Mur", ""],
		["pillar", "Pilier", ""], ["balcony", "Balcon de glace", ""], ["stal", "Plateforme-stalactite", ""],
		["cliff", "Falaise", ""]]],   # [FORMES 2 1.86]
	["Décor", [["arch", "Arche", ""], ["podium", "Podium FIN", ""], ["bush", "Buisson", ""], ["igloo", "Igloo", ""],
		["colisee", "Colisée", ""], ["ice1", "Bloc de glace 1", ""], ["ice2", "Bloc de glace 2", ""], ["ice3", "Petit bloc de glace", ""]]],
	# [CAVERNE 1.84] demande de l'équipe (28/11) : cavernes d'abord — caverne
	# générée (sinueuse) en 1.84, caverne taillée à la main en 1.85 ; le reste
	# est décalé (balcon, stalactite, falaise 1.86 ; autres gros blocs 1.87)
	["Gros blocs", [["cave", "Caverne", ""], ["carved", "Caverne taillée", ""], ["void", "Zone de vide", "1.87"],
		["pillars", "Motif piliers", "1.87"], ["bigegg", "Grand œuf", "1.87"], ["endless", "Tronçon du Sans fin", "1.87"]]],
]

## [ICÔNES 1.82] Bulle de chaque case de la palette (ce que fait l'élément)
const PALETTE_TIPS := {
	"hook": "Une prise où accrocher le grappin. Tourne-la et agrandis-la avec les poignées.",
	"egg": "Un œuf de glace solide où le grappin s'accroche (5 dessins).",
	"boost": "Flèches qui accélèrent Pinpouin, au sol ou en l'air. Blanc = doux, rouge = très fort.",
	"start": "Où Pinpouin part, avec un élan réglable (un seul par niveau).",
	"finish": "La ligne d'arrivée (une seule par niveau).",
	"checkpoint": "Après une chute, Pinpouin repart du dernier point de passage atteint.",
	"sign": "Un panneau pour montrer le chemin (8 directions).",
	"camera": "Tant que Pinpouin est dans cette zone, la caméra recule pour montrer la suite.",
	"draw": "Le sol se trace avec l'outil Dessiner.",
	"ramp": "Un tremplin : pose-le au bout d'un sol, il s'y colle. Étire-le avec les losanges.",
	"halfpipe": "Un half-pipe creusé pour les figures : pose-le entre deux sols (il se colle aux bouts).",
	"bowl": "Un bol (creux arrondi) : pose-le entre deux sols.", "slope": "Une rampe à boosts pour monter, avec un palier en haut.",
	"bend": "Un virage en morceau de tuyau qui relève Pinpouin (angle réglable en Expert).", "upipe": "Un demi-tuyau qui renvoie Pinpouin vers la gauche, la tête en bas.",
	"ceiling": "Un plafond. Avec stalactites : le grappin s'y accroche ; lisse : non (réglage Expert).", "floating": "Une plateforme qui flotte en l'air.",
	"wall": "Un mur (plus de 75° : ni PUMP ni saut pour le grimper).", "pillar": "Un pilier qui sort du vide, comme dans le Gruyère.",
	# [FORMES 2 1.86]
	"balcony": "Un balcon de glace qui sort du bout d'un sol, avec des stalactites dessous (le grappin s'y accroche).",
	"stal": "Une plateforme-stalactite comme dans L'Œuf. Bouton « Série » : un escalier de plateformes avec leurs prises.",
	"cliff": "Une falaise en forme de montagne (paroi à pic, sommet arrondi, longue descente), avec une prise de grappin pour la grimper.",
	"arch": "L'arche de glace.", "podium": "Le podium FIN.", "bush": "Un buisson enneigé.", "igloo": "Un igloo.",
	"colisee": "Le Colisée de glace.", "ice1": "Un bloc de glace.", "ice2": "Un autre bloc de glace.", "ice3": "Un petit bloc de glace.",
	"cave": "Une caverne générée par une graine : galeries qui montent et descendent, routes qui se croisent, sans cul-de-sac. 🎲 pour en tirer une autre.",
	"carved": "Un bloc de glace (rectangle, œuf, rond, montagne ou forme libre) à creuser toi-même : tracer la galerie, pioche, truelle.", "void": "Une zone de vide avec échelle d'œufs.",
	"pillars": "Le motif piliers du Gruyère.", "bigegg": "Le grand œuf de L'Œuf.", "endless": "Un tronçon du Sans fin.",
}


## [ICÔNES 1.82] Vignette d'une case de la palette, sous forme de morceaux
## [texture, transform, rect, région] (comme _decor_sprites) : la vraie image
## de l'objet quand elle existe (œuf, boost, panneau, Pinpouin pour le
## départ, décor ENTIER avec tous ses morceaux), sinon une vignette pixel art
## de sprites/ui/editor/palette_*.png
var _thumb_cache := {}
func _palette_thumb(id: String) -> Array:
	if _thumb_cache.has(id):
		return _thumb_cache[id]
	var parts: Array = []
	var single: Texture2D = null
	match id:
		"egg":
			single = _tex("res://sprites/levels/gruyere/oeuf_glace.png")
		"boost":
			single = _tex("res://sprites/actors/boost/Speed_arrow1.png")
		"sign":
			single = _tex("res://sprites/levels/egg/panneau_droite.png")
		"start":
			single = _penguin_tex
		"finish":
			parts = _decor_sprites("arch")
		_:
			if DrawnLevel.DECOR_SCENES.has(id):
				parts = _decor_sprites(id)
			elif ResourceLoader.exists(ICON_DIR + "palette_" + id + ".png"):
				single = _tex(ICON_DIR + "palette_" + id + ".png")
	if single != null:
		var sz: Vector2 = single.get_size()
		parts = [[single, Transform2D.IDENTITY, Rect2(-sz * 0.5, sz), Rect2(Vector2.ZERO, sz)]]
	_thumb_cache[id] = parts
	return parts


## [ICÔNES 1.82] Petite zone qui dessine une vignette (morceaux ci-dessus)
## centrée et ajustée à sa taille ; agrandissement en nombre entier pour
## garder le pixel art net
class PaletteThumb extends Control:
	var parts: Array = []

	func _draw() -> void:
		if parts.is_empty():
			return
		var box := Rect2()
		var first := true
		for p in parts:
			var r: Rect2 = p[2]
			for c in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
				var q: Vector2 = (p[1] as Transform2D) * c
				if first:
					box = Rect2(q, Vector2.ZERO)
					first = false
				else:
					box = box.expand(q)
		if box.size.x <= 0.0 or box.size.y <= 0.0:
			return
		var k: float = minf(size.x / box.size.x, size.y / box.size.y)
		if k > 1.0:
			k = floorf(k)   # petites images : x1, x2… (net)
		var fit := Transform2D(0.0, Vector2(k, k), 0.0, size * 0.5 - box.get_center() * k)
		for p in parts:
			draw_set_transform_matrix(fit * (p[1] as Transform2D))
			draw_texture_rect_region(p[0], p[2], p[3])
		draw_set_transform_matrix(Transform2D.IDENTITY)


## [ICÔNES 1.82] Palette en grille de vignettes (2 colonnes) : image de
## l'objet + son nom dessous ; bulle d'aide au survol / appui long ; les
## éléments à venir sont grisés avec leur version
func _build_palette() -> void:
	if _palette != null and is_instance_valid(_palette):
		_palette.queue_free()
	_palette = PanelContainer.new()
	var pst := _panel_style()
	pst.bg_color.a = 1.0   # [ICÔNES 1.82] opaque : le niveau ne se voit plus à travers les cases grisées
	_palette.add_theme_stylebox_override("panel", pst)
	_palette.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_palette.offset_left = 6
	_palette.offset_right = 236
	_palette.offset_top = _top_bar_h + 6
	_palette.offset_bottom = -_bottom_bar_h - 40
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
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	var group := ButtonGroup.new()
	for item in PALETTE[_palette_tab][1]:
		var soon: String = item[2]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(98, 100)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = soon != ""
		# vignette (en haut) et nom (en bas), posés sur le bouton ; ils
		# laissent passer les clics au bouton
		var inner := VBoxContainer.new()
		inner.set_anchors_preset(Control.PRESET_FULL_RECT)
		inner.offset_left = 4
		inner.offset_right = -4
		inner.offset_top = 6
		inner.offset_bottom = -4
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_theme_constant_override("separation", 2)
		b.add_child(inner)
		var thumb := PaletteThumb.new()
		thumb.name = "Vignette"
		thumb.parts = _palette_thumb(item[0])
		thumb.custom_minimum_size = Vector2(86, 54)
		thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(thumb)
		var lbl := Label.new()
		lbl.text = item[1] + ("  (" + soon + ")" if soon != "" else "")
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(lbl)
		if soon != "":
			inner.modulate = Color(1, 1, 1, 0.45)   # à venir : grisé
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = item[0] == palette_item
		var desc: String = PALETTE_TIPS.get(item[0], "")
		if soon != "":
			desc += " Arrive en " + soon + "."
		b.set_meta("tip", [item[1], desc, ""])
		_register_tip(b)
		var id: String = item[0]
		b.pressed.connect(func():
			if id == "draw":
				_set_tool(Tool.DRAW)   # le sol se dessine avec l'outil Dessiner
				return
			palette_item = id)
		grid.add_child(b)
	_ui_root.add_child(_palette)
	# (la bulle d'aide reste au-dessus de la palette)
	if _tip != null and is_instance_valid(_tip):
		_ui_root.move_child(_tip, -1)
	if _hover_card != null and is_instance_valid(_hover_card):
		_ui_root.move_child(_hover_card, -1)


## Mode Simple (par défaut) / Expert ; retenu d'une partie à l'autre
func _set_mode(on: bool) -> void:
	expert = on
	DrawnLevel.set_pref("expert", on)
	hover_info = bool(DrawnLevel.pref(_hover_pref_key(), on))   # [SURVOL 1.82] réglage propre à chaque mode
	_set_hover({})
	_rebuild_ui()
	_flash("Mode Expert : position exacte, aimant (🧲), vitesse de « D'ici », raccourcis Suppr, D, Échap." if on else "Mode Simple : l'essentiel, avec de gros boutons.")


# --- [OBJETS 1.81] Réglages, aperçu et validation ---------------------------------

## Nom affiché de chaque type d'objet
const OBJ_NAMES := {"egg": "Œuf à grappiner", "boost": "Boost", "start": "Départ", "finish": "Arrivée",
	"checkpoint": "Point de passage", "sign": "Panneau flèche", "camera": "Zone de caméra",
	"arch": "Arche", "podium": "Podium FIN", "bush": "Buisson", "igloo": "Igloo", "colisee": "Colisée",
	"ice1": "Bloc de glace 1", "ice2": "Bloc de glace 2", "ice3": "Petit bloc de glace",
	# [FORMES 1.83]
	"ramp": "Tremplin", "halfpipe": "Half-pipe", "bowl": "Bol", "slope": "Rampe à boosts", "bend": "Virage en pipe",
	"upipe": "Virage en U", "ceiling": "Plafond", "floating": "Plateforme flottante", "wall": "Mur", "pillar": "Pilier",
	"cave": "Caverne",   # [CAVERNE 1.84]
	"carved": "Caverne taillée",   # [TAILLÉE 1.85]
	"balcony": "Balcon de glace", "stal": "Plateforme-stalactite", "cliff": "Falaise"}   # [FORMES 2 1.86]
const EGG_STYLE_NAMES := ["", "glace", "tacheté", "craquelé", "bonnet de neige", "bébé Pinpouin"]
## Types qu'on peut tourner (les autres restent droits)
const ROTATABLE := ["egg", "boost", "arch", "podium", "bush", "igloo", "colisee", "ice1", "ice2", "ice3",
	"ramp", "halfpipe", "bowl", "slope", "bend", "upipe", "ceiling", "floating", "wall", "pillar",   # [FORMES 1.83]
	"stal"]   # [FORMES 2 1.86] (le balcon et la falaise restent droits : tournés, ils seraient à l'envers)


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
	if DrawnLevel.is_shape(o):
		_shape_settings(col, o)   # [FORMES 1.83]
		return
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
				if DrawnLevel.is_shape(o):
					_draw_shape(o, z)   # [FORMES 1.83]
				elif DrawnLevel.DECOR_SCENES.has(o.type):
					for spr in _decor_sprites(o.type):
						draw_set_transform_matrix(xf.scaled_local(Vector2.ONE * o.scale) * spr[1])
						draw_texture_rect_region(spr[0], spr[2], spr[3])
		draw_set_transform_matrix(Transform2D.IDENTITY)
		if sel and DrawnLevel.is_shape(o):
			_draw_shape_selection(o, z)   # [FORMES 1.83] contour jaune + poignées d'étirement
		elif sel:
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


# --- [FORMES 1.83] Formes du terrain dans l'éditeur ---------------------------------
# Géométrie commune : DrawnLevel.shape_geometry (le jeu construit la même).
# Poignées : rond = tourner ; losanges = étirer en largeur (à droite) et en
# hauteur / profondeur (en haut, ou en bas pour les formes creusées et celles
# qui pendent). Mode Simple : tailles toutes faites (Petit / Moyen / Grand).

## Formes dont la hauteur `h` se compte vers le BAS (creusées, ou qui pendent)
const SHAPE_H_DOWN := ["halfpipe", "bowl", "ceiling", "floating", "pillar", "carved",
	"balcony", "stal"]   # [FORMES 2 1.86] épaisseur comptée vers le bas
## Dimensions étirables de chaque forme
const SHAPE_STRETCH := {"ramp": ["w", "h"], "halfpipe": ["w", "h"], "bowl": ["w", "h"], "slope": ["w", "h"],
	"bend": ["w"], "upipe": ["h"], "ceiling": ["w", "h"], "floating": ["w", "h"], "wall": ["w", "h"], "pillar": ["w", "h"],
	"cave": [],   # [CAVERNE 1.84] taille réglée par la longueur et les étages
	"carved": ["w", "h"],   # [TAILLÉE 1.85] taille du bloc
	"balcony": ["w", "h"], "stal": ["w", "h"], "cliff": ["w", "h"]}   # [FORMES 2 1.86]
## Nom du réglage `h` selon la forme
const SHAPE_H_NAME := {"halfpipe": "Profondeur", "bowl": "Profondeur", "ceiling": "Épaisseur", "floating": "Épaisseur",
	"upipe": "Diamètre", "pillar": "Hauteur",
	"balcony": "Épaisseur", "stal": "Épaisseur", "cliff": "Hauteur"}   # [FORMES 2 1.86]
## [FORMES 2 1.86] Nom du réglage `w` quand ce n'est pas une largeur
const SHAPE_W_NAME := {"bend": "Rayon", "balcony": "Longueur", "stal": "Longueur", "cliff": "Sommet"}
## [FORMES 2 1.86] Série de plateformes-stalactites (bouton « Série ») :
## nombre de plateformes et montée d'une marche à l'autre (retenus d'une
## série à l'autre pendant la séance)
var stal_count := 5
var stal_rise: float = DrawnLevel.STAL_RISE
var _stretch_offset := 0.0      # écart doigt / dimension pendant un étirement
var _draw_bottom := INF         # fond commun des îlots pendant _draw


## Message après l'aimantation d'une forme
func _snap_flash(how: String) -> void:
	match how:
		"bout":
			_flash("Forme collée au bout du sol.")
		"sol":
			_flash("Forme posée sur le sol.")


## Poignées d'une forme (monde) : {rotate, scale (aucune), w, h}
func _shape_handles(o: Dictionary, z: float) -> Dictionary:
	var g := DrawnLevel.shape_geometry(o)
	var f: Rect2 = g.frame
	var xf := Transform2D(float(o.rot), o.pos)
	var out := {"scale": Vector2.INF, "w": Vector2.INF, "h": Vector2.INF}
	var down: bool = o.type in SHAPE_H_DOWN
	# rond « tourner » : toujours AU-DESSUS de la forme ; pour les formes qui
	# montent (losange « hauteur » en haut au milieu), décalé vers la gauche
	# pour ne pas se superposer au losange
	var rx: float = f.get_center().x if down else f.position.x + f.size.x * 0.2
	out.rotate = xf * Vector2(rx, f.position.y - 80.0 / z)
	if o.type in ["cave", "carved"]:
		out.rotate = Vector2.INF   # [CAVERNE 1.84] une caverne ne se tourne pas
	var dims: Array = SHAPE_STRETCH.get(o.type, [])
	if "w" in dims:
		out.w = xf * Vector2(f.end.x + 45.0 / z, f.get_center().y if o.type != "bend" else -12.0 / z)
	if "h" in dims:
		out.h = xf * Vector2(f.get_center().x, (f.end.y + 45.0 / z) if down else (f.position.y - 45.0 / z))
	return out


## Aperçu d'une forme : la même glace que les îlots (remplissage + trait bleu
## sur la ligne de glisse) ; boosts de la rampe ; plafond lisse en plus foncé
func _draw_shape(o: Dictionary, z: float) -> void:
	if o.type == "cave":
		_draw_cave(o, z)   # [CAVERNE 1.84]
		return
	if o.type == "carved":
		_draw_carved(o, z)   # [TAILLÉE 1.85]
		return
	var g := DrawnLevel.shape_geometry(o, _draw_bottom)
	var fill := ICE_COLOR
	if o.type == "ceiling" and DrawnLevel.shape_prop(o, "hook") < 0.5:
		fill = ICE_COLOR.darkened(0.18)   # non accrochable
	if g.poly.size() >= 3:
		var tris := Geometry2D.triangulate_polygon(g.poly)
		if tris.is_empty():
			draw_polyline(g.poly, fill, 6.0 / z)
		else:
			draw_colored_polygon(g.poly, fill)
	draw_polyline(g.top, EDGE_COLOR, maxf(24.0, 5.0 / z), true)
	# [FORMES 2 1.86] glaçons sous les plateformes-stalactites (décor : en jeu,
	# les mêmes images que dans L'Œuf)
	for ic in g.icicles:
		var p0: Vector2 = ic[0]
		var ln: float = ic[1]
		draw_colored_polygon(PackedVector2Array([p0 + Vector2(-34, 0), p0 + Vector2(34, 0), p0 + Vector2(0, ln)]), ICE_COLOR.darkened(0.12))
	for b in g.boosts:
		var k: float = DrawnLevel.shape_prop(o, "strength")
		var c: Color = Color.WHITE.lerp(Color(1, 0.85, 0.1), minf(1.0, k * 2.0)).lerp(Color(1, 0.2, 0.15), maxf(0.0, k * 2.0 - 1.0))
		draw_set_transform_matrix(Transform2D(b.rot, b.pos))
		for j in 3:
			var x0: float = -60.0 + j * 40.0
			draw_colored_polygon(PackedVector2Array([Vector2(x0, -30), Vector2(x0 + 30, 0), Vector2(x0, 30), Vector2(x0 + 15, 30), Vector2(x0 + 45, 0), Vector2(x0 + 15, -30)]), c)
		draw_set_transform_matrix(Transform2D.IDENTITY)


## Sélection d'une forme : contour jaune + poignées (rond = tourner, losanges = étirer)
func _draw_shape_selection(o: Dictionary, z: float) -> void:
	var pts: PackedVector2Array = DrawnLevel.shape_geometry(o, _draw_bottom).poly
	pts.append(pts[0])
	draw_polyline(pts, SELECT_COLOR, 5.0 / z, true)
	var hd := _shape_handles(o, z)
	var f: Rect2 = DrawnLevel.shape_geometry(o).frame
	if hd.rotate != Vector2.INF:
		var anchor: Vector2 = Transform2D(float(o.rot), o.pos) * Vector2(_hd_x_of(hd, o), f.position.y)
		draw_line(anchor, hd.rotate, SELECT_COLOR, 3.0 / z)
		draw_circle(hd.rotate, 14.0 / z, SELECT_COLOR)
		draw_circle(hd.rotate, 8.0 / z, Color(0.1, 0.15, 0.3))
	for k in ["w", "h"]:
		var p: Vector2 = hd[k]
		if p == Vector2.INF:
			continue
		var r: float = 17.0 / z
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), SELECT_COLOR)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r * 0.45), p + Vector2(r * 0.45, 0), p + Vector2(0, r * 0.45), p + Vector2(-r * 0.45, 0)]), Color(0.1, 0.15, 0.3))


## Pied du trait du rond « tourner » : juste sous lui, sur le haut de la forme
func _hd_x_of(hd: Dictionary, o: Dictionary) -> float:
	return ((hd.rotate as Vector2) - o.pos).rotated(-float(o.rot)).x


## Lignes de stats d'une forme (fiche de survol)
func _shape_stats(o: Dictionary) -> Array:
	var lines: Array = []
	if o.type == "carved":
		# [TAILLÉE 1.85]
		var cd := DrawnLevel.carved_data(o)
		lines.append("Bloc : %s, %d × %d px" % [DrawnLevel.CARVED_BASE_NAMES.get(str(o.props.get("base", "rect")), "?"), int(DrawnLevel.shape_prop(o, "w")), int(DrawnLevel.shape_prop(o, "h"))])
		lines.append("%d coup%s (galeries, pioche, truelle)" % [cd.ops, "s" if cd.ops > 1 else ""])
		lines.append("Une galerie traverse le bloc" if cd.crosses else "⚠ Aucune galerie ne traverse le bloc de part en part")
		return lines
	if o.type == "cave":
		# [CAVERNE 1.84]
		var cd := DrawnLevel.cave_data(o)
		lines.append("Graine %d   ·   %d colonnes   ·   %d étages" % [int(DrawnLevel.shape_prop(o, "seed")), int(DrawnLevel.shape_prop(o, "columns")), int(DrawnLevel.shape_prop(o, "lanes"))])
		var amp := DrawnLevel.shape_prop(o, "amp")
		lines.append("Plate" if amp < 1.0 else "Sinuosité %d px (vagues de %.1f colonnes)" % [int(amp), DrawnLevel.shape_prop(o, "wave")])
		lines.append("Entrée : étage %d   ·   sortie : étage %d" % [int(DrawnLevel.shape_prop(o, "entry")) + 1, int(DrawnLevel.shape_prop(o, "exit")) + 1])
		lines.append("Plan vérifié : aucun cul-de-sac" if cd.ok else "Attention : plan non vérifié, essaie une autre graine")
		return lines
	var dims: Array = SHAPE_STRETCH.get(o.type, [])
	var parts: Array = []
	if "w" in dims:
		parts.append("%s %d px" % [SHAPE_W_NAME.get(o.type, "Largeur"), int(DrawnLevel.shape_prop(o, "w"))])
	if "h" in dims:
		parts.append("%s %d px" % [SHAPE_H_NAME.get(o.type, "Hauteur"), int(DrawnLevel.shape_prop(o, "h"))])
	lines.append("   ·   ".join(parts))
	match str(o.type):
		"ramp":
			lines.append("Angle de sortie %d°" % int(DrawnLevel.shape_prop(o, "lip")))
		"bend":
			lines.append("Virage de %d°" % int(DrawnLevel.shape_prop(o, "angle")))
		"slope":
			lines.append("Boosts : force %d %%" % int(round(DrawnLevel.shape_prop(o, "strength") * 100.0)))
		"ceiling":
			lines.append("Accrochable au grappin" if DrawnLevel.shape_prop(o, "hook") > 0.5 else "Lisse : le grappin ne s'y accroche pas")
		# [FORMES 2 1.86]
		"balcony":
			lines.append("Dessous accrochable au grappin")
		"cliff":
			lines.append("Prise automatique au-dessus de la paroi" if DrawnLevel.shape_prop(o, "holds") > 0.5 else "Sans prise automatique")
	if absf(float(o.rot)) > 0.01:
		lines.append("Tournée de %d°" % int(round(rad_to_deg(float(o.rot)))))
	var g := DrawnLevel.shape_geometry(o)
	if g.entry != Vector2.INF:
		for st in DrawnLevel.strokes:
			if (st[st.size() - 1] as Vector2).distance_to(g.entry) < 2.0:
				lines.append("Collée au bout d'un sol")
				break
	return lines


## Réglages d'une forme. Simple : tailles toutes faites + largeur / hauteur ;
## Expert : + réglages propres (angle de sortie, virage, boosts, accrochable),
## angle de la forme, position exacte.
func _shape_settings(col: VBoxContainer, o: Dictionary) -> void:
	var t: String = o.type
	if t == "cave":
		_cave_settings(col, o)   # [CAVERNE 1.84]
		return
	if t == "carved":
		_carved_settings(col, o)   # [TAILLÉE 1.85]
		return
	var dims: Array = SHAPE_STRETCH.get(t, [])
	# tailles toutes faites (choix de l'équipe : surtout pour le mode Simple ;
	# gardées en Expert, elles servent aussi)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	col.add_child(row)
	for preset in DrawnLevel.SHAPE_PRESETS:
		var f: float = DrawnLevel.SHAPE_PRESETS[preset]
		var b := _button(preset, row, 72)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(func():
			_push_undo()
			var it: Dictionary = DrawnLevel.objects[_sel.index]
			for k in dims:
				it.props[k] = float(DrawnLevel.SHAPE_DEFAULTS[t][k]) * f
			_snap_flash(DrawnLevel.snap_shape(_sel.index))
			_changed()
			_rebuild_settings())
	if "w" in dims:
		_slider_row(col, SHAPE_W_NAME.get(t, "Largeur"), 150.0, 3000.0, 10.0, DrawnLevel.shape_prop(o, "w"), func(v): _set_obj("w", v, true), func(v): return "%d px" % int(v))
	if "h" in dims:
		_slider_row(col, SHAPE_H_NAME.get(t, "Hauteur"), 60.0, 3000.0, 10.0, DrawnLevel.shape_prop(o, "h"), func(v): _set_obj("h", v, true), func(v): return "%d px" % int(v))
	# [FORMES 2 1.86] réglages propres, en Simple aussi (choix de l'équipe)
	if t == "cliff":
		_cliff_settings(col, o)
	elif t == "stal":
		_stal_settings(col, o)
	if expert:
		match t:
			"ramp":
				_slider_row(col, "Angle de sortie", 5.0, 70.0, 1.0, DrawnLevel.shape_prop(o, "lip"), func(v): _set_obj("lip", v, true), func(v): return "%d°" % int(v))
			"bend":
				_slider_row(col, "Virage", 30.0, 150.0, 5.0, DrawnLevel.shape_prop(o, "angle"), func(v): _set_obj("angle", v, true), func(v): return "%d°" % int(v))
			"slope":
				_slider_row(col, "Force des boosts", 0.0, 1.0, 0.05, DrawnLevel.shape_prop(o, "strength"), func(v): _set_obj("strength", v, true), func(v): return "%d %%" % int(round(v * 100.0)))
			"ceiling":
				var hk := CheckButton.new()
				hk.text = "Accrochable (stalactites)"
				hk.button_pressed = DrawnLevel.shape_prop(o, "hook") > 0.5
				hk.focus_mode = Control.FOCUS_NONE
				for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
					hk.add_theme_color_override(c, Color.WHITE)
				hk.toggled.connect(func(on): _set_obj("hook", on, true))
				col.add_child(hk)
		_slider_row(col, "Angle", -180.0, 180.0, 15.0 if magnet else 1.0, wrapf(rad_to_deg(o.rot), -180.0, 180.0), func(v): _set_obj("rot", deg_to_rad(v)))
		_spin_row(col, "X", o.pos.x, func(v): _set_obj("pos", Vector2(v, DrawnLevel.objects[_sel.index].pos.y)))
		_spin_row(col, "Y", o.pos.y, func(v): _set_obj("pos", Vector2(DrawnLevel.objects[_sel.index].pos.x, v)))


# --- [FORMES 2 1.86] Réglages de la falaise et des plateformes-stalactites -----------

## Petit interrupteur blanc (même style que « Accrochable » du plafond)
func _check_row(col: VBoxContainer, text: String, on: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		c.add_theme_color_override(k, Color.WHITE)
	c.toggled.connect(cb)
	col.add_child(c)
	return c


## Falaise : prise automatique (choix de l'équipe : oui, avec option) ;
## « Détacher la prise » la change en prise normale, qu'on déplace, tourne ou
## supprime à la main (la prise automatique est alors coupée).
func _cliff_settings(col: VBoxContainer, o: Dictionary) -> void:
	var on: bool = DrawnLevel.shape_prop(o, "holds") > 0.5
	_check_row(col, "Prise automatique", on, func(v): _set_obj("holds", v, true); _rebuild_settings())
	if on:
		var b := _button("Détacher la prise (la déplacer à la main)", col)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_detach_cliff_holds)


func _detach_cliff_holds() -> void:
	if _sel.get("kind", "") != "obj":
		return
	var o: Dictionary = DrawnLevel.objects[_sel.index]
	var hs: Array = DrawnLevel.shape_geometry(o).holds
	if hs.is_empty():
		return
	_push_undo()
	for hp in hs:
		DrawnLevel.hooks.append(DrawnLevel.make_hook(hp))
	o.props.holds = false
	_changed()
	_flash("Prise détachée : touche-la pour la déplacer.")
	_rebuild_settings()


## Plateforme-stalactite : une par une (poignées, Dupliquer) + « Série »
## (choix de l'équipe) : un escalier alterné comme le chemin de gauche de
## L'Œuf, avec une prise de grappin par marche. Nombre de plateformes en
## Simple ; montée d'une marche à l'autre en Expert.
func _stal_settings(col: VBoxContainer, o: Dictionary) -> void:
	_slider_row(col, "Série : plateformes", 2.0, float(DrawnLevel.STAL_SERIES_MAX), 1.0, float(stal_count),
		func(v): stal_count = int(v), func(v): return "%d" % int(v))
	if expert:
		_slider_row(col, "Série : montée", 400.0, 1200.0, 20.0, stal_rise,
			func(v): stal_rise = v, func(v): return "%d px" % int(v))
	var b := _button("Série (escalier + prises)", col)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(func():
		_push_undo()
		var n := DrawnLevel.stal_series(_sel.index, stal_count, stal_rise)
		_changed()
		_flash("%d plateformes ajoutées, chacune avec sa prise." % n))


# --- [CAVERNE 1.84] Caverne générée dans l'éditeur ----------------------------------

const CAVE_ROCK := Color(0.33, 0.47, 0.64)      # roche (aperçu)
const CAVE_GALLERY := Color(0.80, 0.90, 0.97)   # galeries creusées (aperçu)


## Aperçu d'une caverne : montagne, galeries creusées, sols (trait bleu),
## prises (ronds gris), entrée et sortie
func _draw_cave(o: Dictionary, z: float) -> void:
	var cd := DrawnLevel.cave_data(o)
	draw_set_transform(o.pos)
	_safe_polygon(cd.mountain, CAVE_ROCK)
	for poly in cd.outer:
		_safe_polygon(poly, CAVE_ROCK)
	for poly in cd.galleries:
		_safe_polygon(poly, CAVE_GALLERY)
	for fl in cd.floors:
		if (fl as PackedVector2Array).size() >= 2:
			draw_polyline(fl, EDGE_COLOR, maxf(14.0, 4.0 / z), true)
	for hp in cd.holds:
		draw_circle(hp, maxf(55.0, 9.0 / z), HOOK_COLOR)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Polygone plein si on peut le trianguler (sinon son contour : pas d'erreur)
func _safe_polygon(poly: PackedVector2Array, c: Color) -> void:
	if poly.size() < 3:
		return
	if Geometry2D.triangulate_polygon(poly).is_empty():
		var closed := PackedVector2Array(poly)
		closed.append(poly[0])
		draw_polyline(closed, c, 6.0)
	else:
		draw_colored_polygon(poly, c)


## Change un réglage de la caverne, puis la recolle au sol (son entrée peut
## avoir bougé : autre étage d'entrée, autre longueur…)
func _set_cave(key: String, v) -> void:
	_set_obj(key, v, true)
	DrawnLevel.snap_shape(_sel.index)
	queue_redraw()


## Réglages d'une caverne. Simple : nouvelle graine (🎲), Petit / Moyen /
## Grand (longueur), étages, sinuosité ; Expert : + étage d'entrée et de
## sortie, longueur des vagues, graine exacte, position.
func _cave_settings(col: VBoxContainer, o: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	col.add_child(row)
	var dice := _button("🎲 Autre caverne", row, 150)
	dice.add_theme_font_size_override("font_size", 15)
	dice.pressed.connect(func():
		_push_undo()
		DrawnLevel.objects[_sel.index].props.seed = float(randi_range(1, 99999))
		DrawnLevel.snap_shape(_sel.index)
		_changed()
		_rebuild_settings())
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	col.add_child(row2)
	for preset in [["Petit", 3], ["Moyen", 5], ["Grand", 8]]:
		var b := _button(preset[0], row2, 72)
		b.add_theme_font_size_override("font_size", 15)
		var n: int = preset[1]
		b.pressed.connect(func():
			_push_undo()
			DrawnLevel.objects[_sel.index].props.columns = float(n)
			DrawnLevel.snap_shape(_sel.index)
			_changed()
			_rebuild_settings())
	_slider_row(col, "Longueur", 3, 10, 1, DrawnLevel.shape_prop(o, "columns"), func(v): _set_cave("columns", float(v)), func(v): return "%d colonnes" % int(v))
	_slider_row(col, "Étages", 2, 4, 1, DrawnLevel.shape_prop(o, "lanes"), func(v):
		_set_cave("lanes", float(v))
		# la sortie suit l'étage du bas (réglage Simple : on entre en haut, on sort en bas)
		if not expert:
			_set_cave("exit", float(v) - 1.0), func(v): return "%d" % int(v))
	_slider_row(col, "Sinuosité", 0.0, 1800.0, 100.0, DrawnLevel.shape_prop(o, "amp"), func(v): _set_cave("amp", v),
		func(v): return "plate" if v < 1.0 else ("douce" if v < 600.0 else ("forte" if v < 1200.0 else "montagnes russes")))
	if expert:
		var lanes := int(DrawnLevel.shape_prop(o, "lanes"))
		_slider_row(col, "Étage d'entrée", 1, lanes, 1, DrawnLevel.shape_prop(o, "entry") + 1.0, func(v): _set_cave("entry", float(v) - 1.0), func(v): return "%d" % int(v))
		_slider_row(col, "Étage de sortie", 1, lanes, 1, DrawnLevel.shape_prop(o, "exit") + 1.0, func(v): _set_cave("exit", float(v) - 1.0), func(v): return "%d" % int(v))
		_slider_row(col, "Vagues", 1.0, 6.0, 0.5, DrawnLevel.shape_prop(o, "wave"), func(v): _set_cave("wave", v), func(v): return "%.1f colonnes" % v)
		_spin_row(col, "Graine", DrawnLevel.shape_prop(o, "seed"), func(v): _set_cave("seed", float(clampi(int(v), 1, 99999))))
		_spin_row(col, "X", o.pos.x, func(v): _set_obj("pos", Vector2(v, DrawnLevel.objects[_sel.index].pos.y)))
		_spin_row(col, "Y", o.pos.y, func(v): _set_obj("pos", Vector2(DrawnLevel.objects[_sel.index].pos.x, v)))


# --- [TAILLÉE 1.85] Caverne taillée à la main dans l'éditeur -------------------------
# Outils (panneau du bloc sélectionné) : ✏ Tracer (la galerie suit le doigt :
# tunnel de la hauteur choisie, sol lissé), ⛏ Pioche (creuse au pinceau),
# 🧱 Truelle (rebouche, seulement dans le bloc), ◯ Forme libre (on dessine le
# contour du bloc). Un doigt = l'outil, deux doigts = déplacer / zoomer la vue
# (choix de l'équipe). Chaque geste est une étape « Annuler ».

var carve_tool := ""                     # "", "tunnel", "dig", "fill", "outline"
var carve_width: float = 520.0           # hauteur des galeries tracées
var carve_brush: float = 160.0           # rayon de la pioche / truelle
var _carving := false
var _carve_pts := PackedVector2Array()   # points du geste (monde)
const CARVE_HINTS := {
	"tunnel": "Trace la galerie avec le doigt : elle suit ton trait (deux doigts pour bouger la vue).",
	"dig": "Frotte pour creuser la roche à la pioche (deux doigts pour bouger la vue).",
	"fill": "Frotte pour reboucher à la truelle (seulement dans le bloc).",
	"outline": "Dessine le contour du bloc d'un seul trait : il se ferme tout seul.",
}


## Index du bloc à tailler si un outil de taille est actif, sinon -1
func _carve_target() -> int:
	if carve_tool == "" or _sel.get("kind", "") != "obj" or _sel.index >= DrawnLevel.objects.size():
		return -1
	return _sel.index if DrawnLevel.objects[_sel.index].type == "carved" else -1


func _set_carve_tool(t: String) -> void:
	carve_tool = t
	if t == "":
		_set_tool(tool)   # aide de l'outil normal
	else:
		_hint.text = CARVE_HINTS.get(t, "")
	_rebuild_settings()
	queue_redraw()


func _carve_add(wp: Vector2) -> void:
	var step: float = 24.0 if carve_tool in ["tunnel", "outline"] else maxf(20.0, carve_brush * 0.35)
	if _carve_pts.is_empty() or _carve_pts[_carve_pts.size() - 1].distance_to(wp) >= step:
		_carve_pts.append(wp)
		queue_redraw()


## Un point tous les `step` px le long du trait, dans n'importe quel sens
## (DrawnLevel._resample_arc garde des x croissants : bon pour un sol, pas
## pour une galerie qui monte à la verticale ou revient en arrière)
func _resample_free(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	if pts.size() < 2:
		return pts
	var out := PackedVector2Array([pts[0]])
	var carry := 0.0
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var seg := a.distance_to(b)
		var d := step - carry
		while d <= seg:
			out.append(a.lerp(b, d / maxf(seg, 0.001)))
			d += step
		carry = seg - (d - step)
	if out[out.size() - 1].distance_to(pts[pts.size() - 1]) > 4.0:
		out.append(pts[pts.size() - 1])
	return out


## Aimant d'une galerie tracée (après lissage) : commencée près de l'entrée du
## bloc, elle démarre par un bout de plancher bien plat pile au niveau du sol
## dessiné (et pareil à la sortie). Sans ça, le lissage laisse une petite
## marche de quelques px au bord du bloc : un mur qui arrête Pinpouin net.
## Le plancher est 8 px SOUS le sol à l'entrée et 8 px AU-DESSUS à la sortie :
## une toute petite descente à chaque bout, jamais une marche à monter.
func _carve_magnet(o: Dictionary, local: PackedVector2Array, near_in: bool, near_out: bool) -> PackedVector2Array:
	var es := DrawnLevel.carved_entry_exit(o)
	var rr: float = carve_width * 0.5
	var drop := 8.0
	var changed := false
	if near_in:
		var yin: float = (es[0] as Vector2).y - rr + drop
		var xin: float = (es[0] as Vector2).x
		var keep := PackedVector2Array([Vector2(xin - rr, yin), Vector2(xin + rr, yin)])
		for p in local:
			if p.x > xin + rr + 40.0 or keep.size() > 2:
				keep.append(p)
		local = keep
		changed = true
	if near_out:
		var yout: float = (es[1] as Vector2).y - rr - drop
		var xout: float = (es[1] as Vector2).x
		# on enlève la fin du trait qui touche la sortie (en partant du bout)
		var cut := local.size()
		while cut > (2 if near_in else 0) and local[cut - 1].x > xout - rr - 40.0:
			cut -= 1
		local = local.slice(0, cut)
		local.append(Vector2(xout - rr, yout))
		local.append(Vector2(xout + rr, yout))
		changed = true
	if changed:
		# un passage de Chaikin arrondit les raccords ; le plancher plat reste
		# plat au bord du bloc (le 3/4 du segment plat est encore dans le plat)
		local = _resample_free(DrawnLevel._chaikin(local), 40.0)
	return local


## Fin d'un geste de taille : il devient un « coup » du bloc (une étape Annuler)
func _finish_carve() -> void:
	_carving = false
	var i := _carve_target()
	var pts := _carve_pts
	_carve_pts = PackedVector2Array()
	if i < 0 or pts.is_empty():
		queue_redraw()
		return
	var o: Dictionary = DrawnLevel.objects[i]
	var local := PackedVector2Array()
	for p in pts:
		local.append(p - o.pos)
	if carve_tool == "outline":
		_finish_outline(i, local)
		return
	if carve_tool == "tunnel":
		if local.size() < 2:
			_flash("Trace la galerie en glissant le doigt.")
			queue_redraw()
			return
		var near_in: bool = local[0].distance_to(DrawnLevel.carved_entry_exit(o)[0]) < carve_width * 1.2
		var near_out: bool = local[local.size() - 1].distance_to(DrawnLevel.carved_entry_exit(o)[1]) < carve_width * 1.2
		# trait lissé comme les sols dessinés : sol de galerie sans à-coups
		# (rééchantillonné le long du trait : une galerie peut revenir en arrière)
		local = _resample_free(DrawnLevel._chaikin(DrawnLevel._chaikin(DrawnLevel._simplify(local, 12.0))), 40.0)
		local = _carve_magnet(o, local, near_in, near_out)
	var flat: Array = []
	for p in local:
		flat.append(snappedf(p.x, 0.1))
		flat.append(snappedf(p.y, 0.1))
	var r: float = carve_width * 0.5 if carve_tool == "tunnel" else carve_brush
	_push_undo()
	var ops: Array = (o.props.get("ops", []) as Array).duplicate()
	if ops.size() >= DrawnLevel.CARVE_MAX_OPS:
		_flash("Ce bloc a déjà beaucoup de coups : utilise « Tout reboucher » ou un autre bloc.")
		_undo.pop_back()
		return
	ops.append({"k": carve_tool, "r": clampf(r, DrawnLevel.CARVE_R_MIN, DrawnLevel.CARVE_R_MAX), "p": flat})
	o.props.ops = ops
	_changed()
	_rebuild_settings()
	queue_redraw()


## Contour libre : le bloc prend la forme dessinée ; les coups déjà faits
## restent au même endroit dans le monde
func _finish_outline(i: int, local: PackedVector2Array) -> void:
	var poly := DrawnLevel._chaikin(DrawnLevel._simplify(local, 16.0))
	if poly.size() < 3 or Geometry2D.triangulate_polygon(poly).is_empty():
		_flash("Contour trop petit ou qui se croise : dessine une boucle simple.")
		queue_redraw()
		return
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	if r.size.x < DrawnLevel.CARVED_MIN or r.size.y < DrawnLevel.CARVED_MIN:
		_flash("Contour trop petit : le bloc fait au moins %d px." % int(DrawnLevel.CARVED_MIN))
		queue_redraw()
		return
	_push_undo()
	var o: Dictionary = DrawnLevel.objects[i]
	var flat: Array = []
	for p in poly:
		flat.append(snappedf((p.x - r.position.x) / r.size.x, 0.0001))
		flat.append(snappedf((p.y - r.position.y) / r.size.y, 0.0001))
	o.props.base = "free"
	o.props.outline = flat
	o.props.w = r.size.x
	o.props.h = r.size.y
	# l'origine du bloc bouge : les coups sont décalés d'autant (même place à l'écran)
	var ops: Array = []
	for op in o.props.get("ops", []):
		var q: Dictionary = (op as Dictionary).duplicate(true)
		var pf: Array = q.get("p", [])
		for k in range(0, pf.size() - 1, 2):
			pf[k] = float(pf[k]) - r.position.x
			pf[k + 1] = float(pf[k + 1]) - r.position.y
		q.p = pf
		ops.append(q)
	o.props.ops = ops
	o.pos += r.position
	carve_tool = ""
	_changed()
	_rebuild_settings()
	queue_redraw()


## Aperçu d'une caverne taillée : roche, galeries (clair), contours, et le
## geste en cours
func _draw_carved(o: Dictionary, z: float) -> void:
	var cd := DrawnLevel.carved_data(o)
	draw_set_transform(o.pos)
	for v in cd.veil:
		_safe_polygon(v, CAVE_GALLERY)
	for pc in cd.pieces:
		_safe_polygon(pc, CAVE_ROCK)
	for ch in cd.chains:
		if (ch as PackedVector2Array).size() >= 2:
			draw_polyline(ch, EDGE_COLOR, maxf(8.0, 3.0 / z), true)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if _carving and _carve_pts.size() >= 1 and _carve_target() >= 0 and DrawnLevel.objects[_carve_target()] == o:
		var col: Color = {"tunnel": Color(0.8, 0.95, 1.0, 0.6), "dig": Color(1.0, 0.6, 0.3, 0.5), "fill": Color(0.25, 0.35, 0.55, 0.7), "outline": Color(1, 0.9, 0.3, 0.9)}[carve_tool]
		var wdt: float = carve_width if carve_tool == "tunnel" else (carve_brush * 2.0 if carve_tool != "outline" else 8.0 / z)
		if _carve_pts.size() == 1:
			draw_circle(_carve_pts[0], wdt * 0.5, col)
		else:
			draw_polyline(_carve_pts, col, wdt, true)


## Réglages d'une caverne taillée
func _carved_settings(col: VBoxContainer, o: Dictionary) -> void:
	var cd := DrawnLevel.carved_data(o)
	# bloc de départ
	var lb := Label.new()
	lb.text = "Bloc de départ"
	lb.add_theme_color_override("font_color", Color.WHITE)
	col.add_child(lb)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	col.add_child(grid)
	for bname in ["rect", "egg", "round", "mountain"]:
		var b := _button(DrawnLevel.CARVED_BASE_NAMES[bname], grid, 72)
		b.add_theme_font_size_override("font_size", 14)
		b.toggle_mode = true
		b.button_pressed = str(o.props.get("base", "rect")) == bname
		b.pressed.connect(func():
			_push_undo()
			DrawnLevel.objects[_sel.index].props.base = bname
			_changed()
			_rebuild_settings())
	var fb := _button("Forme libre", grid, 72)
	fb.add_theme_font_size_override("font_size", 14)
	fb.toggle_mode = true
	fb.button_pressed = carve_tool == "outline" or str(o.props.get("base", "")) == "free"
	fb.pressed.connect(func(): _set_carve_tool("outline"))
	# outils de taille
	var lt := Label.new()
	lt.text = "Tailler"
	lt.add_theme_color_override("font_color", Color.WHITE)
	col.add_child(lt)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	col.add_child(row)
	for tt in [["tunnel", "✏ Tracer"], ["dig", "⛏ Pioche"], ["fill", "🧱 Truelle"]]:
		var b := _button(tt[1], row, 72)
		b.add_theme_font_size_override("font_size", 14)
		b.toggle_mode = true
		b.button_pressed = carve_tool == tt[0]
		var which: String = tt[0]
		b.pressed.connect(func(): _set_carve_tool("" if carve_tool == which else which))
	if carve_tool != "":
		var done := _button("✋ Fini (déplacer le bloc)", col, 220)
		done.add_theme_font_size_override("font_size", 14)
		done.pressed.connect(func(): _set_carve_tool(""))
	# largeur de la galerie / taille de la pioche
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	col.add_child(row2)
	var sizes: Dictionary = DrawnLevel.CARVE_WIDTHS if carve_tool != "dig" and carve_tool != "fill" else DrawnLevel.CARVE_BRUSHES
	for nm in sizes:
		var v: float = sizes[nm]
		var b := _button(nm, row2, 72)
		b.add_theme_font_size_override("font_size", 14)
		b.toggle_mode = true
		b.button_pressed = is_equal_approx(v, carve_width if sizes == DrawnLevel.CARVE_WIDTHS else carve_brush)
		b.pressed.connect(func():
			if sizes == DrawnLevel.CARVE_WIDTHS:
				carve_width = v
			else:
				carve_brush = v
			_rebuild_settings())
	if expert:
		_slider_row(col, "Galerie", 200.0, 1600.0, 20.0, carve_width, func(v): carve_width = v, func(v): return "%d px" % int(v))
		_slider_row(col, "Pioche", DrawnLevel.CARVE_R_MIN, 500.0, 10.0, carve_brush, func(v): carve_brush = v, func(v): return "%d px" % int(v))
	# état et « tout reboucher »
	var warn := Label.new()
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.custom_minimum_size = Vector2(220, 0)
	warn.text = "Une galerie traverse le bloc." if cd.crosses else "⚠ Aucune galerie ne traverse le bloc de part en part."
	warn.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7) if cd.crosses else Color(1.0, 0.8, 0.4))
	col.add_child(warn)
	if cd.ops > 0:
		var clr := _button("Tout reboucher", col, 160)
		clr.add_theme_font_size_override("font_size", 14)
		clr.pressed.connect(func():
			_push_undo()
			DrawnLevel.objects[_sel.index].props.ops = []
			_changed()
			_rebuild_settings())
	if expert:
		_spin_row(col, "X", o.pos.x, func(v): _set_obj("pos", Vector2(v, DrawnLevel.objects[_sel.index].pos.y)))
		_spin_row(col, "Y", o.pos.y, func(v): _set_obj("pos", Vector2(DrawnLevel.objects[_sel.index].pos.x, v)))


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
