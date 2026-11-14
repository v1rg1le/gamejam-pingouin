extends Camera2D
# =============================================================================
#  AdaptiveCamera.gd — [NOUVEAU] caméra à dézoom intelligent
# -----------------------------------------------------------------------------
#  Objectif : dézoomer quand le pingouin NE VOIT PAS la prochaine plateforme,
#  sans "respirer" en permanence (il est en l'air quasiment tout le temps,
#  un zoom qui bouge sans arrêt donne la nausée).
#
#  Principe :
#   1. Toutes les `scan_interval` secondes (pas à chaque frame), on prédit la
#      trajectoire balistique du pingouin (vitesse + gravité) et on cherche,
#      par raycasts sur le calque "ground", le point où il va atterrir.
#   2. On calcule le zoom nécessaire pour voir À LA FOIS le pingouin et ce
#      point d'atterrissage (avec une marge). Si aucun atterrissage n'est
#      trouvé (au-dessus du vide), on dézoome au maximum autorisé.
#   3. Anti-nausée :
#      - le zoom est arrondi à quelques PALIERS fixes (zoom_levels) : de
#        petites variations de trajectoire ne changent donc rien ;
#      - dézoomer est rapide (on doit voir le danger), re-zoomer est lent ET
#        retardé (zoom_in_delay) : il faut que le besoin de dézoom ait
#        disparu depuis un moment avant de revenir ;
#      - pendant le grappin, on garde le zoom courant (trajectoire non balistique) ;
#      - lissage exponentiel (amorti doux, pas de à-coups).
#
#  [CAMÉRA 1.5] (demande de l'équipe, 14/11) :
#   4. REGARD VERS L'AVANT : plus le pingouin va vite, plus la caméra regarde
#      devant lui. À pleine vitesse, il est affiché dans le quart GAUCHE de
#      l'écran (s'il va vers la droite) : on voit arriver les obstacles.
#      Avant, c'était l'inverse : le lissage de position de Godot faisait
#      "traîner" la caméra derrière lui, et il se retrouvait à DROITE.
#      => le lissage intégré est coupé, la caméra suit le pingouin exactement
#      et c'est le décalage d'avance (offset) qui est lissé, lui.
#      En chute, la vue descend un peu (on voit où on va tomber).
#   5. AU-DESSUS D'UN TROU (aucun atterrissage prévu) : la caméra lance des
#      rayons tout autour du pingouin, à la portée du grappin (distance_max de
#      Chain.gd = 1200 px), et dézoome / se recentre pour montrer TOUTES les
#      prises trouvées (palier spécial gap_zoom, plus large que les autres,
#      utilisé uniquement dans ce cas). Le pingouin reste toujours à l'écran.
#
#  [MIGRATION GODOT 4.7] Rappel : en Godot 4, zoom < 1 = VUE PLUS LARGE
#  (c'était l'inverse en Godot 3).
#  Tout est réglable dans l'inspecteur du nœud Camera2D du Player.
# =============================================================================

## Active / désactive le dézoom intelligent (le mode debug caméra le coupe).
@export var adaptive_zoom_enabled: bool = true
## Paliers de zoom autorisés, du plus proche (1.0) au plus large.
## [FINITION 13/11] le dézoom max passe de 0.5 à 0.7 : à 0.5 le pingouin
## devenait minuscule (≈20 px de haut) et on ne le voyait plus.
@export var zoom_levels: Array[float] = [1.0, 0.85, 0.7]
## [FINITION 13/11] paliers utilisés sur téléphone / tablette (écran plus petit :
## on dézoome encore moins pour que le pingouin reste bien visible).
@export var zoom_levels_mobile: Array[float] = [1.0, 0.9, 0.8]
## Fréquence d'analyse de la trajectoire (s).
@export var scan_interval: float = 0.2
## Jusqu'où (en secondes de vol) on cherche le point d'atterrissage.
@export var prediction_time: float = 2.5
## Pas de simulation de la trajectoire (s).
@export var prediction_step: float = 0.1
## Marge d'écran (fraction) à garder autour du point d'atterrissage.
@export_range(0.0, 0.45) var screen_margin: float = 0.12
## Temps de réponse (s) pour dézoomer / re-zoomer (lissage exponentiel).
@export var zoom_out_time: float = 0.5
@export var zoom_in_time: float = 1.5
## Délai (s) pendant lequel un zoom plus serré doit rester valable avant d'y revenir.
@export var zoom_in_delay: float = 1.0
## [MOBILE] En mode tactile, décale la vue (px) : vers le bas pour que le
## pingouin apparaisse plus haut, et VERS L'AVANT (x multiplié par le sens de
## la glisse) pour qu'il reste à gauche des gros boutons de droite.
@export var touch_view_shift: Vector2 = Vector2(180, 110)
## Masque de collision du sol (calque 2 = "ground").
@export_flags_2d_physics var ground_mask: int = 2

@export_group("Regard vers l'avant (1.5)")
## [CAMÉRA 1.5] Active le regard vers l'avant (sinon : ancien comportement).
@export var look_ahead_enabled: bool = true
## Part de la demi-largeur d'écran dont la vue avance à pleine vitesse.
## 0.55 => le pingouin est à ~22 % du bord gauche de l'écran.
@export_range(0.0, 0.8) var look_ahead_fraction: float = 0.55
## Fraction utilisée en mode tactile (les gros boutons occupent les côtés).
@export_range(0.0, 0.8) var look_ahead_fraction_touch: float = 0.45
## Vitesse (px/s) à partir de laquelle la vue commence à avancer...
@export var look_ahead_min_speed: float = 150.0
## ... et vitesse (px/s) à laquelle l'avance est maximale.
@export var look_ahead_full_speed: float = 1300.0
## En chute : la vue descend de vitesse_verticale × ce facteur (px)...
@export var look_down_factor: float = 0.15
## ... au maximum de cette part de la demi-hauteur d'écran.
@export_range(0.0, 0.6) var look_down_max_fraction: float = 0.3
## Temps de réponse (s) du décalage (lissage : pas d'à-coup aux demi-tours).
@export var look_ahead_time: float = 0.8

@export_group("Dézoom au-dessus des trous (1.5)")
## [CAMÉRA 1.5] Au-dessus d'un trou, montrer les prises à portée du grappin.
@export var gap_view_enabled: bool = true
## Palier de zoom supplémentaire, autorisé UNIQUEMENT au-dessus d'un trou.
@export var gap_zoom: float = 0.55
@export var gap_zoom_mobile: float = 0.65
## Nombre de rayons lancés en cercle autour du pingouin.
@export var gap_ray_count: int = 32
## Le pingouin reste au moins à cette part de la demi-largeur du bord.
@export_range(0.0, 0.5) var gap_player_margin: float = 0.15

var _target_zoom: float = 1.0       # palier visé actuellement
var _pending_zoom_in: float = 1.0   # palier plus serré "en attente"
var _pending_since: float = 0.0     # depuis quand ce palier plus serré est valable
var _scan_timer: float = 0.0
@onready var _player = get_parent()

# [CAMÉRA 1.5]
var _in_gap: bool = false             # dernier scan : au-dessus d'un trou
var _gap_offset: Vector2 = Vector2.ZERO  # décalage pour centrer les prises du grappin
var _gap_zoom_needed: float = 1.0     # zoom qui montre toutes les prises
var _view_offset: Vector2 = Vector2.ZERO # décalage lissé appliqué à la caméra


func _ready() -> void:
	# [MIGRATION GODOT 4.7] en Godot 3 les marges de "drag" étaient actives par
	# défaut ; en Godot 4 il faut les activer explicitement pour garder le même ressenti.
	drag_horizontal_enabled = true
	drag_vertical_enabled = true
	# [FINITION 13/11] paliers plus serrés sur mobile
	if Settings.is_mobile_device and not zoom_levels_mobile.is_empty():
		zoom_levels = zoom_levels_mobile
		gap_zoom = gap_zoom_mobile
	zoom = Vector2.ONE * zoom_levels[0]
	if look_ahead_enabled:
		# [CAMÉRA 1.5] la caméra colle au pingouin (plus de traîne horizontale,
		# qui le plaçait à droite à grande vitesse) ; c'est l'offset d'avance qui
		# est lissé. On garde la marge verticale ("drag") : la vue ne monte /
		# descend pas à chaque bosse.
		position_smoothing_enabled = false
		drag_horizontal_enabled = false


func _physics_process(delta: float) -> void:
	if look_ahead_enabled and _player != null:
		if not _player.DEBUG_CAM:   # le mode debug caméra pilote l'offset à la main
			_update_view_offset(delta)   # [CAMÉRA 1.5] (inclut le décalage tactile)
	else:
		# [MOBILE] décalage doux de la vue quand les boutons tactiles sont affichés
		var wanted_shift := Vector2.ZERO
		if Settings.controls == Settings.TOUCH and _player != null:
			wanted_shift = Vector2(touch_view_shift.x * _player.facing, touch_view_shift.y)
		position = position.lerp(wanted_shift, 1.0 - exp(-delta * 1.5))  # lent : pas d'à-coup aux demi-tours

	if not adaptive_zoom_enabled or _player == null:
		return

	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = scan_interval
		_choose_target_zoom()

	# Lissage exponentiel : rapide pour dézoomer, lent pour re-zoomer.
	var current := zoom.x
	var tau := zoom_out_time if _target_zoom < current else zoom_in_time
	var k := 1.0 - exp(-delta / max(0.01, tau / 3.0))
	current = lerpf(current, _target_zoom, k)
	zoom = Vector2(current, current)


# Choisit le palier de zoom à viser (avec la logique anti-nausée).
func _choose_target_zoom() -> void:
	# Pendant le grappin la trajectoire n'est pas balistique : on ne change rien.
	if _player.chain.hooked or _player.chain.flying:
		return

	var wanted := _compute_needed_zoom()
	var now := Time.get_ticks_msec() / 1000.0

	if wanted < _target_zoom:
		# Besoin de voir plus large : on y va tout de suite.
		_target_zoom = wanted
		_pending_zoom_in = wanted
		_pending_since = now
	elif wanted > _target_zoom:
		# On pourrait re-zoomer : seulement si c'est valable depuis zoom_in_delay.
		if not is_equal_approx(wanted, _pending_zoom_in):
			_pending_zoom_in = wanted
			_pending_since = now
		elif now - _pending_since >= zoom_in_delay:
			_target_zoom = wanted
	else:
		_pending_zoom_in = wanted
		_pending_since = now


# [CAMÉRA 1.5] Décalage de la vue (offset de la Camera2D, en pixels du monde).
# NB : on passe par `offset` et non plus par `position` : la caméra est enfant
# du pingouin, qui TOURNE en l'air ; un décalage de `position` tournait avec
# lui (la vue balayait pendant les vrilles), `offset` ne tourne pas.
func _update_view_offset(delta: float) -> void:
	position = position.lerp(Vector2.ZERO, 1.0 - exp(-delta * 3.0))  # ancien décalage tactile -> 0
	var half_view: Vector2 = get_viewport_rect().size * 0.5 / zoom.x   # demi-vue en px du monde
	var target := Vector2.ZERO
	if _in_gap and gap_view_enabled:
		# Au-dessus d'un trou : on recentre sur les prises du grappin
		target = _gap_offset
	else:
		# Regard vers l'avant : proportionnel à la vitesse horizontale
		var vx: float = _player._velocity.x
		var k := clampf((absf(vx) - look_ahead_min_speed) / maxf(1.0, look_ahead_full_speed - look_ahead_min_speed), 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)   # courbe douce (smoothstep) : pas de seuil brutal
		var frac := look_ahead_fraction_touch if Settings.controls == Settings.TOUCH else look_ahead_fraction
		target.x = signf(vx) * k * frac * half_view.x
		# En chute : on regarde un peu plus bas (jamais vers le haut : inutile)
		target.y = clampf(_player._velocity.y * look_down_factor, 0.0, look_down_max_fraction * half_view.y)
		# Tactile : on garde le décalage historique (pingouin au-dessus des boutons,
		# et un minimum d'avance pour qu'il reste à gauche des boutons de droite)
		if Settings.controls == Settings.TOUCH:
			target.y += touch_view_shift.y
			if absf(target.x) < touch_view_shift.x:
				target.x = touch_view_shift.x * _player.facing
	# Le pingouin doit rester visible quoi qu'il arrive
	var lim := half_view * (1.0 - gap_player_margin * 2.0)
	target = target.clamp(-lim, lim)
	var tau := maxf(0.05, look_ahead_time)
	if _in_gap and gap_view_enabled:
		tau *= 2.0   # au-dessus d'un trou : recentrage plus lent (les prises changent à chaque scan)
	_view_offset = _view_offset.lerp(target, 1.0 - exp(-delta / (tau / 3.0)))
	offset = _view_offset


# Zoom (arrondi à un palier) qui permet de voir le prochain point d'atterrissage.
func _compute_needed_zoom() -> float:
	var landing = _predict_landing_point()
	_in_gap = landing == null and not _player.is_on_ground
	if landing == null:
		# [CAMÉRA 1.5] Au-dessus d'un trou : vue qui montre les prises du grappin
		if gap_view_enabled:
			_scan_hook_targets()
			return _gap_zoom_needed
		# Pas de plateforme en vue sur la trajectoire : vue la plus large.
		return zoom_levels[zoom_levels.size() - 1]

	var half_view: Vector2 = get_viewport_rect().size * 0.5 * (1.0 - screen_margin)
	var d: Vector2 = (landing - _player.global_position).abs()
	var needed := 1.0
	if d.x > 0.0:
		needed = min(needed, half_view.x / d.x)
	if d.y > 0.0:
		needed = min(needed, half_view.y / d.y)

	# Arrondi au palier le plus serré qui suffit (le premier <= needed).
	for z in zoom_levels:
		if z <= needed + 0.001:
			return z
	return zoom_levels[zoom_levels.size() - 1]


# [CAMÉRA 1.5] Lance gap_ray_count rayons en cercle, à la portée du grappin, et
# calcule le décalage + le zoom qui montrent toutes les prises touchées.
func _scan_hook_targets() -> void:
	var space := get_world_2d().direct_space_state
	var origin: Vector2 = _player.global_position
	var reach: float = _player.chain.distance_max   # portée du grappin (Chain.gd)
	var box := Rect2(origin, Vector2.ZERO)
	var hits := 0
	for i in gap_ray_count:
		var dir := Vector2.RIGHT.rotated(TAU * i / gap_ray_count)
		var query := PhysicsRayQueryParameters2D.create(origin, origin + dir * reach, ground_mask, [_player.get_rid()])
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			box = box.expand(hit.position)
			hits += 1
	var view: Vector2 = get_viewport_rect().size
	var widest: float = minf(gap_zoom, zoom_levels[zoom_levels.size() - 1])
	if hits == 0:
		# rien à portée : vue large, centrée un peu devant
		_gap_offset = Vector2(signf(_player._velocity.x) * view.x * 0.25 / widest, 0.0)
		_gap_zoom_needed = widest
		return
	box = box.grow(80.0)   # un peu d'air autour des prises
	# Zoom qui fait tenir la boîte dans l'écran (avec marge), arrondi au palier
	var needed := minf(view.x * (1.0 - screen_margin) / box.size.x, view.y * (1.0 - screen_margin) / box.size.y)
	_gap_zoom_needed = widest
	for z in zoom_levels:
		if z <= needed + 0.001:
			_gap_zoom_needed = z
			break
	# On centre la vue sur la boîte (le clamp de _update_view_offset garde le
	# pingouin à l'écran si toutes les prises ne tiennent pas)
	_gap_offset = box.get_center() - origin


# Simule la chute libre du pingouin et renvoie le 1er point de contact avec le
# sol (Vector2), ou null si rien n'est touché pendant `prediction_time`.
func _predict_landing_point():
	var space := get_world_2d().direct_space_state
	var pos: Vector2 = _player.global_position
	var vel: Vector2 = _player._velocity
	var g := Vector2(0, _player.gravity)
	var t := 0.0
	while t < prediction_time:
		var next_vel: Vector2 = vel + g * prediction_step
		var next_pos: Vector2 = pos + (vel + next_vel) * 0.5 * prediction_step
		var query := PhysicsRayQueryParameters2D.create(pos, next_pos, ground_mask, [_player.get_rid()])
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			return hit.position
		pos = next_pos
		vel = next_vel
		t += prediction_step
	return null
