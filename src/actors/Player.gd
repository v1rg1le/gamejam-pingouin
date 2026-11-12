extends CharacterBody2D
# =============================================================================
#  Player.gd — le pingouin ninja
# -----------------------------------------------------------------------------
#  [MIGRATION GODOT 4.7]
#   - KinematicBody2D  -> CharacterBody2D
#   - export / onready  -> @export / @onready
#   - move_and_slide(v) -> la vitesse passe par la propriété `velocity`.
#     ATTENTION : en Godot 4 (mode "floating"), move_and_slide() NE MODIFIE
#     PLUS la vitesse après une collision (seule la position glisse).
#     En Godot 3, la vitesse renvoyée était "glissée" le long de chaque
#     normale de collision. On reproduit donc ce comportement à la main dans
#     _apply_godot3_slide() pour garder EXACTEMENT les sensations du jeu.
#
#  [FIX VITESSE -> 0]  (bug prioritaire)
#   Cause principale identifiée : les "collisions fantômes". Le sol généré est
#   un grand polygone concave que le moteur découpe en morceaux convexes.
#   Les arêtes INTERNES entre ces morceaux renvoient parfois une normale
#   quasi horizontale ; en Godot 3 `velocity.slide(normale)` annulait alors
#   toute la vitesse horizontale EN UNE SEULE FRAME.
#   Corrections (en couches, pour être robuste) :
#     1. Les sols générés utilisent maintenant des collisions en "segments"
#        (plus d'arêtes internes) -> voir sol.gd / HalfPipe.gd / Tremplin.gd.
#     2. Filtre anti-arête-fantôme ici : si une collision aux pieds donne une
#        normale incohérente avec le sol mesuré par les 2 raycasts, on utilise
#        la normale du sol à la place.
#     3. Amorti d'atterrissage : retomber "contre" une pente (fond de vallée)
#        effaçait toute la vitesse qui rentrait dans le sol (900 -> 60 px/s
#        en une frame). Une partie (landing_speed_keep = 50 %) est rendue le
#        long de la pente. Mettre landing_speed_keep à 0 = comportement d'origine.
#     4. Garde anti-NaN (le swing du grappin pouvait produire des NaN).
#     5. Diagnostic : si la vitesse s'effondre quand même, un message
#        "[SPEED DROP]" explique la cause dans la console (désactivable via
#        debug_speed_drop). Les chocs contre un plafond/mur réel restent normaux.
#   Autres causes corrigées ailleurs : conflit de touche Shift (pull/trix)
#   dans InAirState.gd, freinage "idle" trop brutal dans OnGroundState.gd.
#
#  [MORT / RESPAWN]  (nouveau)
#   Chute infinie gérée : sous le point le plus bas du niveau (+ marge), ou
#   après une chute rapide trop longue (max_fall_time), le pingouin
#   réapparaît là où il glissait au sol ~2 s avant sa chute, AVEC l'élan
#   qu'il avait à ce moment-là (pour pouvoir retenter le saut). Chaque mort
#   successive rembobine un peu plus loin. respawn_on_death = false donne
#   un "game over" (rechargement du niveau) à la place.
# =============================================================================

# --- Signaux ajoutés (mort / respawn) : utiles pour l'UI ou le son plus tard ---
signal died
signal respawned

@export var stomp_impulse: = 500.0
var facing: int = 1
var _states: StateMachine
@onready var animated_sprite = $"AnimatedSprite2D"  # [MIGRATION] nœud renommé AnimatedSprite -> AnimatedSprite2D
#var snap: Vector2 = Vector2.DOWN
#onready var floor_detector: RayCast2D = $"FloorDetector"
#onready var rotator: = $"Rotator"

@export var pump_accel_factor = 1.3

@onready var chain: = $Chain
var chain_velocity := Vector2(0,0)
@onready var chain_length = 0
@export var chain_fixed: bool = false

# from Actor
const SUPER_MAX_SPEED = Vector2(3000, 3000)
const MAX_SPEED_HOOKED = Vector2(1000,1000)
const MIN_SPEED_HOOKED = Vector2(200,200)
@export var max_speed: = Vector2(700, 600)  # Vector2(1000, 600) // 500 ?
@export var max_speed_chain: = Vector2(14, 20) # Vector2(50, 60)  # Vector2(1000, 600)
@export var gravity: float = 800.0

var _velocity: Vector2 = Vector2.ZERO

# from OnGroundState
@export var accel_factor_pump = 1.3
@export var velocity_max_idle = 100  # velocity min for running state
@export var max_running_velocity = 500  # velocity max for running state

var is_on_ground: bool = false
var is_almost_on_ground: bool = false
@onready var ground_detector_right: = $GroundDetectorRight
@onready var ground_detector_left: = $GroundDetectorLeft
#onready var test_raycast = $TestRaycast
@onready var coyote_timer  # initalise dans ready pour get nom de scene actuelle : = get_node("/root/LevelChill704/Player/StateMachine/CoyoteTimer")

@onready var anim_player = $AnimationPlayer

var direction: Vector2

@export var DEBUG_CAM: bool = false
@onready var camera: = $Camera2D
@export var running_speed = 500

# =============================================================================
#  [FIX VITESSE -> 0] Réglages du filtre anti-collision-fantôme
# =============================================================================
## Active le filtre qui ignore les normales "fantômes" des arêtes internes.
@export var ghost_collision_filter: bool = true
## Écart d'angle max (degrés) toléré entre la normale de collision et la
## normale du sol mesurée par les raycasts. Au-delà => arête fantôme.
@export var ghost_normal_max_angle_deg: float = 35.0
## Affiche "[SPEED DROP] ..." dans la console si la vitesse s'effondre.
@export var debug_speed_drop: bool = true
# Compteur de frames consécutives où le filtre a agi alors que le pingouin
# n'avançait pas : si ça dure, c'est un VRAI mur -> on arrête de filtrer.
var _ghost_filter_blocked_frames: int = 0
## Fraction (0..1) de la vitesse "écrasée" contre le sol lors d'un atterrissage
## qui est rendue le long de la pente. 0 = comportement Godot 3 d'origine.
@export_range(0.0, 1.0) var landing_speed_keep: float = 0.5
## Vitesse d'impact minimale (px/s, perpendiculaire au sol) pour appliquer l'amorti.
@export var landing_impact_min: float = 250.0
const GHOST_FILTER_MAX_BLOCKED_FRAMES = 6

# =============================================================================
#  [MORT / RESPAWN] Réglages
# =============================================================================
## true : on réapparaît au dernier point sûr. false : on recharge le niveau (game over).
@export var respawn_on_death: bool = true
## Marge (px) sous le point le plus bas du décor avant de considérer la chute comme mortelle.
@export var fall_death_margin: float = 1500.0
## Durée max (s) d'une chute RAPIDE ininterrompue (sécurité si le niveau n'a pas de fond).
@export var max_fall_time: float = 4.0
## Vitesse verticale (px/s) à partir de laquelle on considère qu'on "tombe vite".
@export var fast_fall_speed: float = 900.0
var last_safe_position: Vector2 = Vector2.ZERO  # dernier endroit sûr (au sol, sans grappin)
## Au respawn, on "rembobine" de ce nombre de secondes avant la dernière glisse
## au sol, et on rend la vitesse qu'on avait à ce moment-là : on peut donc
## retenter le saut avec de l'élan (sinon on réapparaît au bord du trou, à
## l'arrêt, et on retombe en boucle).
@export var respawn_rewind_time: float = 2.0
var _safe_history: Array = []      # échantillons {pos, vel, time} pris au sol
var _last_ground_time: float = 0.0
var _respawn_sample = null         # échantillon choisi pour le respawn en cours
var fall_death_y: float = INF                    # calculé au démarrage du niveau
var death_count: int = 0                         # nombre de morts (pour l'UI si besoin)
var _fall_timer: float = 0.0
var _safe_ground_timer: float = 0.0
var _respawning: bool = false


func _ready():
	# [MIGRATION GODOT 4.7] Reproduire la physique de Godot 3 :
	# - MOTION_MODE_FLOATING = pas de notion de "sol" moteur (le jeu utilise ses
	#   propres raycasts), exactement comme move_and_slide(v) sans up_direction en G3.
	# - wall_min_slide_angle = 0 : sinon Godot 4 STOPPE net le mouvement quand on
	#   touche une surface presque de face (< 15°) -> autre source de "vitesse 0".
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	max_slides = 4  # valeur par défaut de Godot 3

	add_to_group("player")  # [NOUVEAU] permet à la caméra / l'arrivée / le niveau de retrouver le joueur
	_states = $"StateMachine"
	_states.current._enter(self)
#	coyote_timer = get_node("/root/%s/Player/StateMachine/CoyoteTimer" % get_tree().current_scene.name)
	coyote_timer = $"StateMachine/CoyoteTimer"

	# [MORT / RESPAWN] point de départ = premier point sûr ; le "fond" du niveau
	# est calculé une fois que tout le décor (généré en _ready) existe.
	last_safe_position = global_position
	call_deferred("_compute_fall_death_y")

func _on_EnemyDetector_area_entered(_area):
	_velocity = calculate_stomp_velocity(_velocity, stomp_impulse)

func _physics_process(delta: float) -> void:
	if _respawning:
		return  # [MORT / RESPAWN] le pingouin est "gelé" pendant la petite animation de respawn

	is_on_ground = ground_detector_right.is_colliding() and ground_detector_left.is_colliding()
	is_almost_on_ground = \
		(ground_detector_right.is_colliding() and !ground_detector_left.is_colliding()) or \
		(!ground_detector_right.is_colliding() and ground_detector_left.is_colliding())

	handle_input(delta)

	if abs(_velocity.x) > 10:
		facing = 1 if _velocity.x > 0 else -1
	animated_sprite.flip_h = facing != 1

	_velocity.y += gravity * delta

	_velocity.x = clamp(_velocity.x, -SUPER_MAX_SPEED.x, SUPER_MAX_SPEED.x)
	_velocity.y = clamp(_velocity.y, -SUPER_MAX_SPEED.y, SUPER_MAX_SPEED.y)
	# HookinInAirState clamp la _velocity avec player.MAX_SPEED_HOOKED

	# [FIX VITESSE -> 0] garde anti-NaN : un NaN dans la vitesse "contamine"
	# tout (position, caméra...) ; on revient à la dernière valeur saine.
	_sanitize_velocity()

	# [MIGRATION GODOT 4.7] équivalent de `_velocity = move_and_slide(_velocity)`
	var velocity_before: Vector2 = _velocity
	velocity = _velocity
	move_and_slide()
	_velocity = _apply_godot3_slide(velocity_before)

	# [FIX VITESSE -> 0] diagnostic console si la vitesse s'effondre quand même
	if debug_speed_drop:
		_report_speed_drop(velocity_before, _velocity)

	# [MORT / RESPAWN]
	_update_fall_and_safe_position(delta)


# =============================================================================
#  [MIGRATION GODOT 4.7] + [FIX VITESSE -> 0]
#  Reproduit le `lv = lv.slide(collision.normal)` de Godot 3 pour chaque
#  collision, en remplaçant les normales "fantômes" par la normale du sol.
# =============================================================================
func _apply_godot3_slide(v: Vector2) -> Vector2:
	var count := get_slide_collision_count()
	if count == 0:
		_ghost_filter_blocked_frames = 0
		return v

	var ground_normal := _get_ground_normal()
	var filter_used := false
	var v_in := v                       # vitesse avant impact (pour l'amorti d'atterrissage)
	var impact_normal := Vector2.ZERO   # normale du dernier contact "pieds" sur un sol praticable
	for i in count:
		var col: KinematicCollision2D = get_slide_collision(i)
		var n: Vector2 = col.get_normal()
		if _is_ghost_collision(col, n, ground_normal):
			# Arête fantôme : on glisse le long du VRAI sol (normale des raycasts)
			n = ground_normal
			filter_used = true
		if to_local(col.get_position()).y >= 3.0 and n.y < -0.5:  # contact aux pieds, pente < 60°
			impact_normal = n
		v = v.slide(n)

	# [FIX VITESSE -> 0] Amorti d'atterrissage : quand on retombe "contre" une
	# pente (fond de vallée, bosse en face), la projection pure de Godot 3
	# supprimait toute la composante qui rentre dans le sol => 900 px/s -> 60 px/s
	# en une frame. On rend une partie (landing_speed_keep) de cette vitesse
	# perdue, redirigée le long de la pente dans le sens du mouvement.
	# Ne s'applique qu'aux VRAIS impacts (composante normale > landing_impact_min),
	# jamais au simple contact de glisse (sinon : mouvement perpétuel).
	if landing_speed_keep > 0.0 and impact_normal != Vector2.ZERO:
		var normal_speed: float = -v_in.dot(impact_normal)
		var lost: float = v_in.length() - v.length()
		if normal_speed > landing_impact_min and lost > 0.0:
			var dir: Vector2 = v.normalized()
			if v.length() < 1.0:
				dir = impact_normal.orthogonal()
				if dir.dot(v_in) < 0.0:
					dir = -dir
			v = dir * (v.length() + lost * landing_speed_keep)

	# Sécurité "vrai mur" : si le filtre agit mais qu'on n'avance plus du tout
	# pendant plusieurs frames, c'est qu'il y a un véritable obstacle.
	if filter_used and get_real_velocity().length() < 0.2 * v.length():
		_ghost_filter_blocked_frames += 1
	else:
		_ghost_filter_blocked_frames = 0
	return v


# Normale moyenne du sol sous le pingouin, mesurée par les 2 raycasts.
# Renvoie Vector2.ZERO si aucun raycast ne touche.
func _get_ground_normal() -> Vector2:
	var n := Vector2.ZERO
	if ground_detector_right.is_colliding():
		n += ground_detector_right.get_collision_normal()
	if ground_detector_left.is_colliding():
		n += ground_detector_left.get_collision_normal()
	return n.normalized() if n != Vector2.ZERO else Vector2.ZERO


# Une collision est considérée "fantôme" si :
#  - le filtre est actif et n'est pas bloqué (cf. vrai mur),
#  - un raycast voit le sol juste sous le pingouin,
#  - le contact est au niveau des pieds (moitié basse de la capsule),
#  - et la normale diffère trop de celle du sol mesuré.
func _is_ghost_collision(col: KinematicCollision2D, n: Vector2, ground_normal: Vector2) -> bool:
	if not ghost_collision_filter or ground_normal == Vector2.ZERO:
		return false
	if _ghost_filter_blocked_frames >= GHOST_FILTER_MAX_BLOCKED_FRAMES:
		return false
	var local_contact: Vector2 = to_local(col.get_position())
	if local_contact.y < 3.0:  # contact sur le côté / le haut => vrai obstacle
		return false
	return abs(rad_to_deg(n.angle_to(ground_normal))) > ghost_normal_max_angle_deg


# Remplace une vitesse invalide (NaN / infini) par la dernière vitesse saine.
var _last_sane_velocity: Vector2 = Vector2.ZERO
func _sanitize_velocity() -> void:
	if is_nan(_velocity.x) or is_nan(_velocity.y) or is_inf(_velocity.x) or is_inf(_velocity.y):
		if debug_speed_drop:
			print("[SPEED DROP] vitesse NaN/inf détectée (état ", _current_state_name(), ") -> restaurée")
		_velocity = _last_sane_velocity
	else:
		_last_sane_velocity = _velocity


func _report_speed_drop(before: Vector2, after: Vector2) -> void:
	var b := before.length()
	if b < 300.0 or after.length() > 0.25 * b:
		return
	var msg := "[SPEED DROP] %d -> %d px/s | état=%s" % [int(b), int(after.length()), _current_state_name()]
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		msg += " | collision avec %s normale=%s" % [str(col.get_collider()), str(col.get_normal().snapped(Vector2(0.01, 0.01)))]
	print(msg)


func _current_state_name() -> String:
	if _states == null or _states.current == null:
		return "?"
	var s = _states.current
	return "%s/%s" % [s.get("super_state_name"), s.get("sub_state_name")]


# =============================================================================
#  [MORT / RESPAWN]
# =============================================================================
# Cherche le point le plus bas de tout le décor (sols générés, blocs, niveaux
# faits main) pour savoir à partir d'où la chute est "infinie".
func _compute_fall_death_y() -> void:
	var lowest := -INF
	for node in get_tree().current_scene.find_children("*", "CollisionPolygon2D", true, false):
		var poly: CollisionPolygon2D = node
		for p in poly.polygon:
			lowest = max(lowest, poly.to_global(p).y)
	for node in get_tree().current_scene.find_children("*", "CollisionShape2D", true, false):
		var cs: CollisionShape2D = node
		if cs.shape != null and cs.get_parent() is StaticBody2D:
			var r: Rect2 = cs.shape.get_rect()
			lowest = max(lowest, cs.to_global(r.end).y)
			lowest = max(lowest, cs.to_global(r.position).y)
	if lowest == -INF:
		fall_death_y = INF  # pas de décor trouvé : seule la règle "chute trop longue" s'applique
	else:
		fall_death_y = lowest + fall_death_margin
	print("[MORT] limite de chute du niveau : y = ", fall_death_y)


func _update_fall_and_safe_position(delta: float) -> void:
	# Mémorise un point sûr : au sol depuis un petit moment et sans grappin.
	if is_on_ground and not chain.hooked:
		_safe_ground_timer += delta
		_last_ground_time = Time.get_ticks_msec() / 1000.0
		if _safe_ground_timer > 0.25:
			# un échantillon toutes les 0.25 s environ (on garde ~10 s d'historique)
			_safe_ground_timer = 0.0
			last_safe_position = global_position
			_safe_history.append({"pos": global_position, "vel": _velocity, "time": _last_ground_time})
			if _safe_history.size() > 40:
				_safe_history.pop_front()
	else:
		_safe_ground_timer = 0.0

	# Règle 1 : on est passé sous le fond du niveau.
	if global_position.y > fall_death_y:
		die()
		return

	# Règle 2 : chute rapide ininterrompue trop longue (niveau sans fond, etc.).
	if not is_on_ground and not is_almost_on_ground and not chain.hooked and _velocity.y > fast_fall_speed:
		_fall_timer += delta
		if _fall_timer > max_fall_time:
			die()
	else:
		_fall_timer = 0.0


func die() -> void:
	if _respawning:
		return
	death_count += 1
	print("[MORT] chute ! (mort n°", death_count, ")")
	emit_signal("died")
	if not respawn_on_death:
		# Variante "game over" : on recharge simplement le niveau.
		get_tree().call_deferred("reload_current_scene")
		return
	_respawning = true
	_respawn_sample = _pick_respawn_sample()
	chain.release()
	_fall_timer = 0.0
	# Petit fondu de l'image du pingouin pour que la téléportation ne soit pas brutale.
	var tween := create_tween()
	tween.tween_property(animated_sprite, "modulate:a", 0.0, 0.25)
	tween.tween_callback(_do_respawn)
	tween.tween_property(animated_sprite, "modulate:a", 1.0, 0.35)


# Choisit l'échantillon "sûr" pris environ respawn_rewind_time secondes avant
# la dernière glisse au sol (ou le plus ancien disponible).
func _pick_respawn_sample():
	if _safe_history.is_empty():
		return null
	var limit := _last_ground_time - respawn_rewind_time
	var chosen = _safe_history[0]
	for sample in _safe_history:
		if sample.time <= limit:
			chosen = sample
	return chosen


func _do_respawn() -> void:
	if _respawn_sample != null:
		global_position = _respawn_sample.pos + Vector2(0, -30)
		# On rend l'élan qu'on avait à cet endroit (limité pour rester jouable).
		_velocity = _respawn_sample.vel.limit_length(1200.0)
		# On oublie l'historique postérieur : si on meurt encore, on rembobine plus loin.
		while _safe_history.size() > 1 and _safe_history.back().time > _respawn_sample.time:
			_safe_history.pop_back()
		_last_ground_time = _respawn_sample.time
	else:
		global_position = last_safe_position + Vector2(0, -40)
		# On repart avec un petit élan dans le sens où l'on regardait.
		_velocity = Vector2(200 * facing, 0)
	rotation = 0.0
	chain_velocity = Vector2.ZERO
	_states.go_to_state(self, "in_air")
	camera.reset_smoothing()  # la caméra saute directement au pingouin
	_respawning = false
	emit_signal("respawned")


func _input(event):
	if Input.is_action_pressed("debug_cam_right") and DEBUG_CAM:
		camera.offset += Vector2(1000,0)
#		camera.offset += lerp(camera.offset, Vector2(1000,0), 0.1)
	elif Input.is_action_pressed("debug_cam_left")  and DEBUG_CAM:
		camera.offset -= Vector2(1000,0)
#		camera.offset += lerp(camera.offset, Vector2(-1000,0), 0.1)

	if event.is_action_pressed("toggle_debug"):
		print('cam debug: ', DEBUG_CAM)
		if DEBUG_CAM:
			DEBUG_CAM = false
			camera.zoom = Vector2(1,1)
			camera.adaptive_zoom_enabled = true  # [NOUVEAU] on rend la main au zoom intelligent
			set_process(true)
		else:
			DEBUG_CAM = true


func _process(_delta): # camera follows player velocity

	if DEBUG_CAM:
		# [MIGRATION GODOT 4.7] le zoom est INVERSÉ en Godot 4 :
		# zoom 10 (G3, vue très large) == zoom 0.1 (G4).
		camera.adaptive_zoom_enabled = false
		camera.zoom = Vector2(0.1, 0.1)
		set_process(false)

	var x = _velocity.x / 2
	var y = _velocity.y / 3
	x = clamp(x, -20, 20)
	y = clamp(y, -20, 20)
	camera.offset = lerp(camera.offset, Vector2(x,y), 0.1)


func calculate_stomp_velocity(linear_velocity: Vector2, impulse: float) -> Vector2:
	var out = linear_velocity
	out.y = -impulse
	return out

func handle_input(delta: float) -> void:
	_states.current._handle_input(self, delta)

# [MIGRATION GODOT 4.7] `update()` existe déjà dans CanvasItem en G3 mais plus en G4 ;
# la fonction (inutilisée) est conservée telle quelle pour ne rien casser.
func update() -> void:
	_states.current._update(self)

func _get_aim_direction() -> Vector2:
	match Settings.controls:
		Settings.GAMEPAD:
			return Vector2(
				Input.get_action_strength("aim_right") - Input.get_action_strength("aim_left"),
				Input.get_action_strength("aim_down") - Input.get_action_strength("aim_up")).normalized()
		Settings.KBD_MOUSE, _:
			return (get_global_mouse_position() - global_position).normalized()


func _on_Chain_chain_hooked(current_length):
	chain_length = current_length
