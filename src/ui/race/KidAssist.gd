extends CanvasLayer
# =============================================================================
#  [MODE ENFANT 1.23] Aide de jeu pour les petits (Options → « Mode enfant »)
# -----------------------------------------------------------------------------
#  ORIGINE : le « test enfant » de la 1.22 (bot qui tapote l'écran au hasard,
#  68 parties) a montré qu'un enfant qui ne comprend pas ▶ / PUMP s'arrête sur
#  du plat ou dans un creux et reste parfois plus de 2 minutes sans avancer :
#  sur Flat, Corridor et Hook you fool !, 1 enfant sur 30 arrivait au bout.
#
#  CE QUE FAIT CE NŒUD (seulement si Settings.kid_mode est activé) :
#   1. POUSSÉE AUTOMATIQUE : au sol, si le pingouin va moins vite que
#      KID_PUSH_SPEED vers la droite et que l'enfant n'appuie pas sur ◀, il
#      est poussé doucement vers l'avant (KID_PUSH_ACCEL px/s²), comme si on
#      tenait ▶. Il ne pousse jamais au-delà de KID_PUSH_SPEED : les pentes,
#      le pump et le grappin restent les seuls moyens d'aller vite.
#   2. COUP DE POUCE DANS LES CREUX : si malgré la poussée le pingouin n'a
#      pas avancé depuis KID_STUCK_TIME secondes (creux trop profond), on lui
#      donne une petite impulsion vers l'avant et vers le haut.
#   3. AIDE VISUELLE : après KID_HINT_DELAY secondes sans avancer, des cercles
#      jaunes clignotent autour des boutons ▶ et PUMP (en tactile), ou un
#      message rappelle les touches (clavier / manette).
#   4. PONT MAGIQUE : après KID_GAP_DEATHS chutes de suite dans le même trou
#      (le test enfant tombait jusqu'à 50 fois sur « Hook you fool ! », où il
#      faut le grappin), Pinpouin réapparaît sur l'île suivante, avec un petit
#      message « Coup de pouce ! ».
#
#  Créé par RaceManager au début de chaque niveau (solo uniquement : jamais
#  en multijoueur, ce serait un avantage injuste). Le joueur garde la main sur
#  tout : la poussée s'arrête dès qu'il appuie sur ◀, qu'il est en l'air ou
#  accroché au grappin.
#  Les zones de toucher plus larges des boutons sont gérées directement dans
#  TouchControls._button_at() (même réglage Settings.kid_mode).
# =============================================================================

const KID_PUSH_SPEED := 650.0     # px/s : vitesse visée par la poussée auto (◀▶ « normal » = 500)
const KID_PUSH_ACCEL := 420.0     # px/s² : douceur de la poussée
const KID_STUCK_TIME := 4.0       # s sans avancer avant le coup de pouce
const KID_STUCK_KICK := Vector2(550, -420)   # impulsion du coup de pouce (avant + haut)
const KID_HINT_DELAY := 6.0       # s sans avancer avant d'afficher l'aide visuelle
const PROGRESS_STEP := 150.0      # px : avancer de ça « compte » comme un progrès
const KID_GAP_DEATHS := 2         # chutes de suite au même trou avant le « pont magique »
const SAME_GAP_RANGE := 400.0     # px : deux chutes dont le trou commence au même endroit = même trou
const LAND_SEARCH := 6000.0       # px : distance max où l'on cherche l'île suivante
const KID_COURSE_RESCUE_TIME := 15.0   # [ŒUF 1.59] s sans avancer avant d'aller au point de passage suivant

var player = null                 # le pingouin (Player.gd), donné par setup()
var _best_x := -INF               # x le plus à droite atteint
var _still_time := 0.0            # temps depuis le dernier progrès
var _kick_cooldown := 0.0         # évite d'enchaîner les coups de pouce
var _hint_time := 0.0             # horloge du clignotement
var _canvas: Control              # zone de dessin de l'aide visuelle
var _label: Label                 # message clavier / manette
var _gap_deaths := 0              # chutes de suite au même endroit
var _gap_x := -INF                # x du bord du trou de la dernière chute
var _gap_y := 0.0                 # hauteur de la piste au bord de ce trou
var _bridge_pending := false      # téléporter après la prochaine réapparition
var _toast: Label                 # message « Coup de pouce ! »
var _fall_from_x := -INF          # [RÈGLES 1.90] x du dernier endroit sûr avant la chute
var _toast_time := 0.0


## [RÈGLES 1.90] Le niveau a-t-il des ponts magiques posés à la main ?
## (le générateur des niveaux du créateur, s'il en a au moins un ; sinon null)
func _bridges():
	var g = get_tree().get_first_node_in_group("kid_bridges")
	if g == null or not g.has_method("kid_bridge_after") or DrawnLevel.bridge_points().is_empty():
		return null
	return g


func setup(p) -> void:
	player = p
	# « pont magique » : on écoute les chutes du pingouin
	player.died.connect(_on_player_died)
	player.respawned.connect(_on_player_respawned)


func _on_player_died() -> void:
	if not Settings.kid_mode:
		return
	# [ŒUF 1.59] niveau à points de passage : deux chutes de suite depuis le
	# même point = on passe au point suivant (le « pont magique » de ce niveau)
	var course = get_tree().get_first_node_in_group("course_checkpoints")
	# [RÈGLES 1.90] correctif : les niveaux du créateur sont aussi dans ce
	# groupe (points de passage) mais n'ont pas de « point suivant » à la
	# L'Œuf (pas de kid_skip) : avant, le mode enfant y plantait à la 1re
	# chute. Ils passent par la règle des trous ci-dessous.
	if course != null and course.has_method("kid_skip"):
		var cp: int = course.current_checkpoint()
		_gap_deaths = _gap_deaths + 1 if is_equal_approx(_gap_x, float(cp)) else 1
		_gap_x = float(cp)
		if _gap_deaths >= KID_GAP_DEATHS:
			course.kid_skip()
			_gap_deaths = 0
			_gap_x = -INF
			_show_toast("Coup de pouce !")
		return
	# Le trou est repéré par SON BORD : depuis le dernier endroit sûr avant la
	# chute, on cherche où le sol s'arrête devant. L'endroit exact de la mort
	# (et même le dernier endroit sûr) varie beaucoup selon l'élan ; le bord du
	# trou, lui, est toujours le même.
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var x = _gap_start(space, player.last_safe_position.x, player.last_safe_position.y)
	_fall_from_x = player.last_safe_position.x
	if x == null and _bridges() != null:
		# [RÈGLES 1.90] pas de trou repéré (chute d'une galerie, d'un œuf…)
		# mais le créateur a posé des ponts magiques : on compte les chutes
		# au même endroit d'où l'on est tombé
		x = player.last_safe_position.x
	if x == null:
		_gap_deaths = 0   # pas de trou devant (chute en arrière, bout du niveau…)
		return
	# même trou que la chute précédente ?
	if absf(x - _gap_x) < SAME_GAP_RANGE:
		_gap_deaths += 1
	else:
		_gap_deaths = 1
	_gap_x = x
	_gap_y = player.last_safe_position.y
	if _gap_deaths >= KID_GAP_DEATHS:
		_bridge_pending = true
	print("[MODE ENFANT] chute à x=%d (%d de suite au même trou)" % [x, _gap_deaths])


func _on_player_respawned() -> void:
	if not _bridge_pending:
		return
	_bridge_pending = false
	var landing = null
	# [RÈGLES 1.90] niveau du créateur avec des ponts magiques posés : le
	# premier pont après l'endroit d'où l'on est tombé ; sinon on cherche l'île
	# suivante comme avant
	var provider = _bridges()
	if provider != null:
		landing = provider.kid_bridge_after(_fall_from_x)
	if landing == null:
		landing = _find_landing(_gap_x, _gap_y)
	if landing == null:
		print("[MODE ENFANT] pont magique : pas de sol trouvé après x=%d" % _gap_x)
		return   # rien trouvé devant (fin de niveau…) : réapparition normale
	player.global_position = landing + Vector2(0, -60)
	player._velocity = Vector2(KID_PUSH_SPEED, 0)
	player.camera.reset_smoothing()
	_gap_deaths = 0
	_gap_x = -INF
	_best_x = player.global_position.x
	_still_time = 0.0
	_show_toast("Coup de pouce !")
	print("[MODE ENFANT] pont magique : posé en x=%d après %d chutes" % [landing.x, KID_GAP_DEATHS])


## Cherche l'île suivante : rayons verticaux tous les 64 px depuis le bord
## d'où l'on est tombé. On avance d'abord jusqu'au TROU (plus de sol), puis
## jusqu'au premier sol après le trou ; on se pose 300 px plus loin pour être
## bien sur l'île et pas au bord. Les prises de grappin flottantes, plus
## haut que la piste, ne sont pas vues (rayon limité autour de la piste).
func _gap_start(space: PhysicsDirectSpaceState2D, from_x: float, ref_y: float):
	var x := from_x
	while x < from_x + LAND_SEARCH:
		if _ground_at(space, x, ref_y) == null:
			return x
		x += 64.0
	return null


func _find_landing(from_x: float, ref_y: float):
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var x := from_x
	var in_gap := false
	while x < from_x + LAND_SEARCH:
		var hit = _ground_at(space, x, ref_y)
		if hit == null:
			in_gap = true
		elif in_gap:
			var safer = _ground_at(space, x + 300.0, ref_y)
			return safer if safer != null else hit
		x += 64.0
	return null


func _ground_at(space: PhysicsDirectSpaceState2D, x: float, ref_y: float):
	# Le rayon part un peu au-dessus de la piste (pas de 900 px : il touchait
	# les prises de grappin « poisson » posées 500 px au-dessus des trous, ou
	# le dessus des plafonds) et descend loin (les îles suivantes sont plus bas).
	var q := PhysicsRayQueryParameters2D.create(Vector2(x, ref_y - 300.0), Vector2(x, ref_y + 2500.0), player.collision_mask, [player.get_rid()])
	var r := space.intersect_ray(q)
	if r.is_empty() or r.normal.y > -0.6:   # pas de sol, ou paroi trop raide
		return null
	var body = r.collider
	if body is Node and str(body.scene_file_path).contains("StaticBody2DFish"):
		return null   # prise de grappin, pas un sol
	return r.position


func _ready() -> void:
	layer = 60   # au-dessus du jeu et des boutons tactiles, sous les menus
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hint)
	_canvas.visible = false   # caché tant qu'on n'a pas besoin d'aide
	add_child(_canvas)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", Color(1, 0.94, 0.4))
	_label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.2))
	_label.add_theme_constant_override("outline_size", 8)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.offset_left = -400
	_label.offset_right = 400
	_label.offset_top = -150
	_label.offset_bottom = -90
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	add_child(_label)
	# message « Coup de pouce ! » (même style, en haut de l'écran)
	_toast = _label.duplicate()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -400
	_toast.offset_right = 400
	_toast.offset_top = 110
	_toast.offset_bottom = 160
	_toast.add_theme_font_size_override("font_size", 36)
	add_child(_toast)


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_time = 2.0


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or not Settings.kid_mode:
		_set_hint(false)
		return
	if get_tree().paused or player.process_mode == Node.PROCESS_MODE_DISABLED:
		return
	# [ŒUF 1.59] « vers l'avant » n'est pas toujours la droite : dans « Le
	# Half-Pipe de l'œuf », le bas se parcourt vers la GAUCHE et la cheminée
	# vers le haut. Le niveau le dit (groupe « course_direction ») : sens
	# (+1, -1, ou 0 = pas de poussée) et avancement le long du tour.
	var course = get_tree().get_first_node_in_group("course_direction")
	var fwd: float = 1.0
	var prog: float = player.global_position.x
	if course != null:
		fwd = course.forward_dir(player.global_position)
		prog = course.progress(player.global_position)
	# --- Progrès : a-t-on avancé ? (vers la droite, ou le long du tour) ---
	if prog > _best_x + PROGRESS_STEP:
		_best_x = prog
		_still_time = 0.0
	else:
		_still_time += delta
	_kick_cooldown = maxf(0.0, _kick_cooldown - delta)

	var hooked: bool = player.chain.hooked or player.chain.flying
	# « en arrière » = la touche du sens opposé à l'avant
	var wants_back: bool = Input.is_action_pressed("move_right" if fwd < 0.0 else "move_left")
	# --- 1. Poussée automatique (au sol, pas de grappin, pas de « en arrière ») ---
	if fwd != 0.0 and player.is_on_ground and not hooked and not wants_back and player._velocity.x * fwd < KID_PUSH_SPEED:
		player._velocity.x = fwd * minf(player._velocity.x * fwd + KID_PUSH_ACCEL * delta, KID_PUSH_SPEED)
	# --- 2. Coup de pouce si coincé dans un creux ---
	if fwd != 0.0 and _still_time > KID_STUCK_TIME and _kick_cooldown <= 0.0 and player.is_on_ground and not hooked and not wants_back:
		player._velocity += Vector2(KID_STUCK_KICK.x * fwd, KID_STUCK_KICK.y)
		_kick_cooldown = 2.0
	# --- [ŒUF 1.59] coincé longtemps (ex. au pied de la cheminée, où il faut
	# le grappin) : on emmène l'enfant au point de passage suivant ---
	if course != null and _still_time > KID_COURSE_RESCUE_TIME and not hooked:
		_still_time = 0.0
		course.kid_skip()
		var cs = course.respawn_sample(player.global_position)
		if cs != null:
			player.teleport_to(cs.pos, cs.vel)
			_show_toast("Coup de pouce !")
	# --- 3. Aide visuelle ---
	_set_hint(_still_time > KID_HINT_DELAY)


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.visible = _toast_time > 0.0
	if _canvas.visible:
		_hint_time += delta
		_canvas.queue_redraw()


func _set_hint(on: bool) -> void:
	var touch: bool = Settings.controls == Settings.TOUCH
	_canvas.visible = on and touch
	_label.visible = on and not touch
	if on and not touch:
		_label.text = TutorialSign.resolve_text("Maintiens {move_right} pour avancer\net {pump} dans les descentes !")


# Cercles jaunes qui « respirent » autour de ▶ et de PUMP (positions réelles
# des boutons, lues dans TouchControls pour suivre la taille de l'écran).
func _draw_hint() -> void:
	var tc = get_node_or_null("/root/TouchControls")
	if tc == null:
		return
	var pulse := 0.5 + 0.5 * sin(_hint_time * 6.0)
	var col := Color(1, 0.94, 0.4, 0.45 + 0.5 * pulse)
	for id in ["right", "pump"]:
		var b: Dictionary = tc._get_button(id)
		if b.is_empty():
			continue
		var c: Vector2 = tc._pos(b)
		var r: float = b.r + 10.0 + 14.0 * pulse
		_canvas.draw_arc(c, r, 0.0, TAU, 48, col, 7.0, true)
		_canvas.draw_arc(c, r + 16.0, 0.0, TAU, 48, Color(col, col.a * 0.4), 4.0, true)
