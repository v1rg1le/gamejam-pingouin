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

var _target_zoom: float = 1.0       # palier visé actuellement
var _pending_zoom_in: float = 1.0   # palier plus serré "en attente"
var _pending_since: float = 0.0     # depuis quand ce palier plus serré est valable
var _scan_timer: float = 0.0
@onready var _player = get_parent()


func _ready() -> void:
	# [MIGRATION GODOT 4.7] en Godot 3 les marges de "drag" étaient actives par
	# défaut ; en Godot 4 il faut les activer explicitement pour garder le même ressenti.
	drag_horizontal_enabled = true
	drag_vertical_enabled = true
	# [FINITION 13/11] paliers plus serrés sur mobile
	if Settings.is_mobile_device and not zoom_levels_mobile.is_empty():
		zoom_levels = zoom_levels_mobile
	zoom = Vector2.ONE * zoom_levels[0]


func _physics_process(delta: float) -> void:
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


# Zoom (arrondi à un palier) qui permet de voir le prochain point d'atterrissage.
func _compute_needed_zoom() -> float:
	var landing = _predict_landing_point()
	if landing == null:
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
