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
#        en une frame). Une partie (landing_speed_keep = 75 %, 50 % avant la 1.24) est rendue le
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
## [ATTERRISSAGES 1.40] émis à chaque atterrissage : "feet" (debout),
## "nose" (bec en avant) ou "crash" (sur le dos). Écouté par TrickScore.
signal landed(style: String)
## [ATTERRISSAGES 1.40] style d'atterrissage, posture debout / à plat ventre,
## chute en roulade et explosion de neige : voir src/actors/LandingStyle.gd
var landing: LandingStyle = null

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
#  [PHYSIQUE 1.10] Réglages de vitesse (retours de test de la 1.8)
#  Constats mesurés en simulation (pingouin lancé à 1500 px/s sur le tuto) :
#   - maintenir « avancer » FREINAIT : la vitesse était ramenée vers
#     running_speed (500), au sol comme en l'air : 1500 -> 700 px/s en 3 s ;
#   - le pump PLAFONNAIT la vitesse à max_speed × 1,4 = 980 px/s : atterrir
#     vite puis pumper faisait perdre d'un coup 500 px/s ;
#   - au-delà de 980, le pump ne donnait plus aucun boost.
#  => il valait mieux rester en l'air sans rien toucher. Nouvelles règles :
#   - « avancer » accélère jusqu'à running_speed, mais ne freine JAMAIS un
#     pingouin plus rapide qui va dans le même sens ;
#   - le pump accélère le long de la pente (beaucoup en descente, un peu en
#     montée) jusqu'à pump_max_speed, et ne fait jamais perdre de vitesse ;
#     chaque nouvel appui donne une petite impulsion (sensation de boost) ;
#   - au-dessus de ground_max_speed (sol) / air_max_speed (air), un léger
#     frottement ramène doucement la vitesse : plus de plafond brutal.
#  Toutes ces valeurs se règlent en jeu (panneau F2, cf. PhysicsTuner.gd).
# =============================================================================
## Accélération du pump (px/s²), sur terrain plat.
@export var pump_accel: float = 450.0
## Bonus en descente : × la composante de la gravité le long de la pente.
@export var pump_slope_bonus: float = 1.5
## Efficacité du pump en montée (0 = aucun effet, 1 = comme sur le plat).
@export var pump_uphill_factor: float = 0.35
## Impulsion (px/s) à chaque nouvel appui sur pump.
@export var pump_impulse: float = 90.0
## Le pump n'accélère plus au-delà de cette vitesse (sans jamais freiner).
@export var pump_max_speed: float = 1450.0
## Au sol, au-delà de cette vitesse, frottement doux.
@export var ground_max_speed: float = 1450.0
## En l'air (hors grappin), au-delà de cette vitesse, frottement doux.
@export var air_max_speed: float = 1750.0
## Part de l'excédent de vitesse perdue par seconde au-dessus des plafonds.
@export var over_speed_drag: float = 1.5
## Traînée visuelle derrière le pingouin à partir de cette vitesse (0 = jamais).
@export var speed_trail_from: float = 1200.0

# =============================================================================
#  [BOOST FIGURE 1.30] Une figure réussie donne de l'élan (idée de Manu, façon
#  Alto's Odyssey). Au moment où les points d'un saut sont gagnés (atterrissage
#  propre, cf. TrickScore.bank()), le pingouin reçoit une poussée dans le sens
#  de sa vitesse, plus forte avec le combo. Pendant trick_boost_time secondes,
#  les plafonds de vitesse « doux » sont relevés d'autant (sinon le frottement
#  au-dessus de la vitesse max mangerait le boost) et la traînée devient rose.
#  Partout (courses, Chill, Sans fin). Réglable avec F2.
# =============================================================================
## Poussée pour une figure seule (px/s).
@export var trick_boost_base: float = 220.0
## Poussée en plus par figure supplémentaire du combo (px/s).
@export var trick_boost_per_combo: float = 90.0
## Durée pendant laquelle la vitesse max est relevée (s).
@export var trick_boost_time: float = 1.6
var _trick_boost_left: float = 0.0     # temps restant du boost en cours
var _trick_boost_extra: float = 0.0    # px/s ajoutés aux plafonds pendant le boost

# =============================================================================
#  [NEIGE 1.31] Gerbe de neige et d'éclats de glace derrière Pinpouin AU SOL
#  (demande de Manu). Elle grossit avec la vitesse : 3 gerbes empilées
#  s'allument l'une après l'autre (légère, moyenne, forte) aux vitesses
#  snow_spray_speeds, et la taille / la projection des grains augmentent en
#  continu. Grains blancs (neige) et bleu clair (glace), carrés de quelques
#  pixels pour coller au pixel art. Rose pendant un boost de figure.
#  En l'air, c'est la traînée (Line2D) d'avant qui reste.
#  Dessinée en code (CPUParticles2D : marche aussi dans la version navigateur).
# =============================================================================
## Vitesses (px/s) où s'allument les gerbes légère, moyenne et forte ([] = jamais).
@export var snow_spray_speeds: Array[float] = [220.0, 650.0, 1100.0]
## Grains par gerbe (chaque gerbe en émet autant par durée de vie).
@export var snow_spray_amount: int = 28
var _sprays: Array = []                 # les 3 CPUParticles2D

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
# [1.24] 0,5 -> 0,75 (retour de Léo) : à 0,5 le pingouin perdait la moitié de
# la vitesse « écrasée » contre le sol à chaque bosse, ce qui faisait un petit
# « freeze » à répétition qui ressemblait à un bug. 0 = comportement Godot 3.
@export_range(0.0, 1.0) var landing_speed_keep: float = 0.75
# [PUMP EN L'AIR 1.27] Demande de Léo, validée par Manu (activé par défaut) :
# maintenir PUMP en l'air fait descendre plus vite, comme une gravité plus
# forte. La gravité est multipliée par air_pump_gravity tant que PUMP est
# tenu en l'air (1 = désactivé). Pas pendant le grappin (il a sa propre
# physique), ni en mode enfant (les petits appuient sur PUMP au hasard).
# Réglable en jeu dans le panneau F2 (« Gravité en pumpant en l'air »).
@export_range(1.0, 4.0) var air_pump_gravity: float = 2.0
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
	# [PHYSIQUE 1.10] réglages de glisse choisis dans le panneau F2 (s'il y en a)
	PhysicsTuner.apply_to(self)
	# [MIGRATION GODOT 4.7] Reproduire la physique de Godot 3 :
	# - MOTION_MODE_FLOATING = pas de notion de "sol" moteur (le jeu utilise ses
	#   propres raycasts), exactement comme move_and_slide(v) sans up_direction en G3.
	# - wall_min_slide_angle = 0 : sinon Godot 4 STOPPE net le mouvement quand on
	#   touche une surface presque de face (< 15°) -> autre source de "vitesse 0".
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	max_slides = 4  # valeur par défaut de Godot 3

	# [ATTERRISSAGES 1.40]
	landing = LandingStyle.new()
	landing.name = "LandingStyle"
	add_child(landing)
	landing.setup(self)
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

	# [PUMP EN L'AIR 1.27] gravité plus forte tant que PUMP est tenu en l'air
	var g: float = gravity
	if not is_on_ground and Input.is_action_pressed("pump") and not chain.hooked and not chain.flying and not Settings.kid_mode:
		g *= air_pump_gravity
	_velocity.y += g * delta

	_apply_soft_speed_caps(delta)   # [PHYSIQUE 1.10]
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
	_unstick_from_ground()   # [SOL 1.9]
	landing.update(delta)    # [ATTERRISSAGES 1.40] pattes / nose / chute
	_update_speed_trail()    # [PHYSIQUE 1.10] (en l'air seulement depuis 1.31)
	_update_snow_spray()     # [NEIGE 1.31] gerbe de neige et de glace au sol
	_update_sounds()         # [BRUITAGES 1.34] glisse, vent, atterrissage, pump

	# [FIX VITESSE -> 0] diagnostic console si la vitesse s'effondre quand même
	if debug_speed_drop:
		_report_speed_drop(velocity_before, _velocity)

	# [MORT / RESPAWN]
	_update_fall_and_safe_position(delta)


# [PHYSIQUE 1.10] Plafonds « doux » : au-dessus de la vitesse max (sol ou air),
# on retire chaque seconde over_speed_drag de l'EXCÉDENT. Pas de coupure nette.
# Le grappin garde son propre réglage (MAX_SPEED_HOOKED, dans HookingInAirState).
func _apply_soft_speed_caps(delta: float) -> void:
	if _states == null or _states.current == null or _states.current.sub_state_name == "HOOKING":
		return
	var cap := ground_max_speed if is_on_ground else air_max_speed
	# [BOOST FIGURE 1.30] plafond relevé pendant le boost (et qui redescend doucement)
	if _trick_boost_left > 0.0:
		_trick_boost_left -= delta
		cap += _trick_boost_extra * clampf(_trick_boost_left / trick_boost_time, 0.0, 1.0)
	var speed := _velocity.length()
	if speed > cap:
		var new_speed := cap + (speed - cap) * (1.0 - clampf(over_speed_drag * delta, 0.0, 1.0))
		_velocity = _velocity * (new_speed / speed)


# [PHYSIQUE 1.10] Traînée blanche derrière le pingouin à grande vitesse :
# donne la sensation de vitesse (surtout après un pump). Dessinée en code.
var _trail: Line2D = null

func _update_speed_trail() -> void:
	if _trail == null:
		_trail = Line2D.new()
		_trail.top_level = true
		_trail.z_index = -1
		_trail.width = 14.0
		_trail.joint_mode = Line2D.LINE_JOINT_ROUND
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.0))
		g.set_color(1, Color(1, 1, 1, 0.55))
		_trail.gradient = g
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.1))
		curve.add_point(Vector2(1, 1))
		_trail.width_curve = curve
		add_child(_trail)
	var speed := _velocity.length()
	# [NEIGE 1.31] au sol, c'est la gerbe de neige qui montre la vitesse :
	# la traînée (blanche, ou rose pendant un boost) ne s'affiche qu'en l'air
	if is_on_ground:
		if _trail.get_point_count() > 0:
			_trail.remove_point(0)   # elle s'efface en douceur à l'atterrissage
		return
	# [BOOST FIGURE 1.30] traînée rose pendant un boost de figure (et visible
	# même un peu en dessous de la vitesse habituelle de la traînée)
	var boosting := _trick_boost_left > 0.0
	# rose franc (couleur > 1 = plus opaque que la traînée blanche normale),
	# plus épaisse et plus longue pendant le boost
	_trail.modulate = Color(1.0, 0.35, 0.8, 1.6) if boosting else Color.WHITE
	_trail.width = 26.0 if boosting else 14.0
	if boosting and speed_trail_from > 0.0:
		speed = maxf(speed, speed_trail_from + 840.0)
	if speed_trail_from <= 0.0 or speed < speed_trail_from:
		if _trail.get_point_count() > 0:
			_trail.remove_point(0)   # la traînée s'efface en douceur
		return
	_trail.add_point(global_position + Vector2(0, 4))
	var max_points := int(clampf((speed - speed_trail_from) / 60.0, 3.0, 14.0))
	while _trail.get_point_count() > max_points:
		_trail.remove_point(0)


# =============================================================================
#  [SOL 1.9] « Pinpouin s'enfonce dans le sol » (retour de l'équipe, Chill 704)
#  Depuis la correction du bug vitesse -> 0, les sols générés n'ont plus qu'un
#  CONTOUR de collision (segments) : leur intérieur est creux. Or un sol de
#  sol.gd n'a que ~40 px d'épaisseur, et le pingouin seulement 20 px de haut
#  (capsule couchée). S'il se retrouve à l'intérieur (cas de Chill 704 : il
#  apparaissait 20 px sous la surface), il glissait sur le bord INFÉRIEUR, à
#  l'intérieur de la glace, sans jamais remonter. En Godot 3 (sol plein), le
#  moteur le repoussait dehors.
#  Ici, à chaque image : si le pingouin touche un sol généré ET que son centre
#  est à l'intérieur du polygone de ce sol, on le remonte sur la surface (rayon
#  vertical vers le bas depuis au-dessus) et on annule sa vitesse vers le bas.
# =============================================================================
func _unstick_from_ground() -> void:
	for i in get_slide_collision_count():
		var col = get_slide_collision(i).get_collider()
		if col == null or not col.has_method("generate_curve"):
			continue
		var cp: CollisionPolygon2D = col.get_node_or_null("CollisionPolygon2D")
		if cp == null or not Geometry2D.is_point_in_polygon(cp.to_local(global_position), cp.polygon):
			continue
		# remonte sur la première surface de CE sol au-dessus du pingouin
		var space := get_world_2d().direct_space_state
		var q := PhysicsRayQueryParameters2D.create(global_position + Vector2(0, -400), global_position, collision_mask, [get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.collider != col:
			return
		global_position.y = hit.position.y - 11.0   # 10 px = demi-hauteur de la capsule
		if _velocity.y > 0.0:
			_velocity.y = 0.0
		print("[SOL] pingouin ressorti de l'intérieur d'un sol à ", global_position.round())
		return


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
	Sfx.play("chute")   # [BRUITAGES 1.34] « waaah » qui s'éloigne
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
	# [SANS FIN 1.32] niveau Sans fin : début de l'île d'avant le trou raté
	var endless = get_tree().get_first_node_in_group("endless")
	if endless != null:
		var s = endless.respawn_sample(global_position.x)
		if s != null:
			return {"pos": s.pos, "vel": s.vel, "time": _last_ground_time}
	# [BONUS 1.20] pendant les figures bonus après l'arrivée, une chute (par
	# exemple dans le trou entre la dernière île et le half-pipe) fait
	# réapparaître directement sur le deck de gauche du half-pipe, sans élan :
	# on ne repart pas avant la ligne d'arrivée et on ne perd pas le bonus.
	if RaceManager.bonus_active or RaceManager.free_ride:   # [MODES 1.25] + half-pipe libre (Chill)
		var p = RaceManager.bonus_respawn_point()
		if p != null:
			return {"pos": p, "vel": Vector2(300, 0), "time": _last_ground_time}
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
	Sfx.play("reapparition", -4.0)   # [BRUITAGES 1.34] petit « pop »
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

	# [CAMÉRA 1.5] le décalage de caméra selon la vitesse est maintenant géré
	# par AdaptiveCamera.gd ("regard vers l'avant", bien plus ample que ces
	# ±20 px). On ne garde l'ancien calcul que si cette option est coupée.
	if camera.look_ahead_enabled:
		return
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
		Settings.TOUCH:
			# [MOBILE] visée fournie par le bouton GRAPPIN tactile (glissé du doigt).
			# Vector2.ZERO => les états de grappin utilisent la visée par défaut
			# (vers l'avant et le haut), comme quand on ne vise pas à la manette.
			return Settings.touch_aim
		Settings.KBD_MOUSE, _:
			return (get_global_mouse_position() - global_position).normalized()


func _on_Chain_chain_hooked(current_length):
	chain_length = current_length
	Sfx.play("grappin_accroche")   # [BRUITAGES 1.34] le crochet se plante



# [ATTERRISSAGES 1.40] Joue l'animation d'un état au sol en respectant la
# posture : debout sur les pattes (« glide_feet ») après un atterrissage bien
# droit, ou l'animation d'origine (à plat ventre) après un nose.
func play_ground_anim(anim_name: String) -> void:
	if landing != null and landing.ride_pose == "feet":
		anim_player.play("glide_feet")
	else:
		anim_player.play(anim_name)


# [BOOST FIGURE 1.30] Appelé par TrickScore.bank() quand les points d'un saut
# sont gagnés. combo = nombre de figures du saut (1 à MAX_COMBO).
func trick_boost(combo: int) -> void:
	if combo <= 0 or trick_boost_base <= 0.0:
		return
	var amount := trick_boost_base + trick_boost_per_combo * float(combo - 1)
	# direction : celle de la vitesse ; à l'arrêt, vers où regarde le pingouin
	var dir := _velocity.normalized()
	if _velocity.length() < 50.0:
		dir = Vector2(-1.0 if animated_sprite.flip_h else 1.0, 0.0)
	_velocity += dir * amount
	_trick_boost_left = trick_boost_time
	_trick_boost_extra = amount



# [NEIGE 1.31] Crée les 3 gerbes (une seule fois) puis les règle à chaque image.
func _make_snow_spray() -> void:
	# couleurs tirées au hasard pour chaque grain : neige blanche → glace bleue
	var colors := Gradient.new()
	colors.set_color(0, Color(1, 1, 1))
	colors.set_color(1, Color(0.30, 0.62, 0.98))      # éclat de glace bien bleu
	colors.add_point(0.45, Color(0.92, 0.97, 1.0))    # neige
	colors.add_point(0.75, Color(0.55, 0.80, 1.0))    # glace claire
	# fondu : opaque au départ, transparent en fin de vie
	# un grain = un carré blanc de 1 px (agrandi par scale_amount) : sans
	# texture, un CPUParticles2D ne dessine rien
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var grain := ImageTexture.create_from_image(img)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.95))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	for i in snow_spray_speeds.size():
		var p := CPUParticles2D.new()
		p.top_level = true             # les grains restent là où ils sont tombés
		p.z_index = -1                 # derrière le pingouin
		p.emitting = false
		p.amount = snow_spray_amount * (i + 1)   # 28 / 56 / 84 : de plus en plus dense
		p.lifetime = 0.45 + 0.1 * i
		p.local_coords = false
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 6.0
		p.spread = 22.0 + 6.0 * i
		p.gravity = Vector2(0, 980)
		p.damping_min = 20.0
		p.damping_max = 60.0
		p.angular_velocity_min = -180.0
		p.angular_velocity_max = 180.0
		p.texture = grain
		p.color_initial_ramp = colors
		p.color_ramp = fade
		add_child(p)
		_sprays.append(p)


func _update_snow_spray() -> void:
	if _sprays.is_empty():
		_make_snow_spray()
	var speed := _velocity.length()
	# sens de la projection : vers l'arrière et un peu vers le haut
	var back := -_velocity.normalized() if speed > 1.0 else Vector2.LEFT
	var dir := (back + Vector2(0, -1.3)).normalized()   # en panache, vers le haut
	# point de départ : sous les pattes (le pingouin suit la pente)
	var feet := global_position + Vector2(-back.x * 6.0, 14.0).rotated(rotation)
	# le pingouin bouge APRÈS ce réglage (move_and_slide) : on vise là où il
	# sera, sinon à grande vitesse la gerbe démarre loin derrière les pattes
	feet += _velocity * get_physics_process_delta_time()
	var t := clampf(speed / ground_max_speed, 0.0, 1.5)   # 0 à l'arrêt, 1 à la vitesse max
	var boosting := _trick_boost_left > 0.0
	# gerbe active seulement au sol et hors grappin / chute (pas en mode « sonné »)
	var on_snow: bool = is_on_ground and _states != null and _states.current != null \
		and _states.current.super_state_name == "ON_GROUND"
	for i in _sprays.size():
		var p: CPUParticles2D = _sprays[i]
		p.emitting = on_snow and speed >= snow_spray_speeds[i]
		p.global_position = feet
		p.direction = dir
		p.initial_velocity_min = 80.0 + 300.0 * t
		p.initial_velocity_max = 180.0 + 620.0 * t
		# taille des grains en pixels du monde (la caméra dézoome souvent ~×0,5)
		p.scale_amount_min = 5.0 + 4.0 * t + 2.0 * i
		p.scale_amount_max = 9.0 + 9.0 * t + 3.0 * i
		p.modulate = Color(1.0, 0.6, 0.9) if boosting else Color.WHITE



# =============================================================================
#  [BRUITAGES 1.34] Sons continus et petits événements du pingouin
#  (voir src/autoload/Sfx.gd). Les boucles sont redemandées à chaque image
#  avec leur volume : elles s'éteignent toutes seules quand on ne les demande
#  plus (pause, changement de niveau, pingouin figé).
# =============================================================================
var _sfx_was_ground := true
var _sfx_air_time := 0.0
var _sfx_last_vy := 0.0

func _update_sounds() -> void:
	var speed := _velocity.length()
	var dt := get_physics_process_delta_time()
	var gliding: bool = is_on_ground and _states != null and _states.current != null \
		and _states.current.super_state_name == "ON_GROUND"
	# glisse sur la glace : plus fort avec la vitesse ; « rapide » au-delà de 1100 px/s
	if gliding and speed > 60.0:
		Sfx.loop("glisse_boucle", clampf(speed / 900.0, 0.0, 1.0) * 0.55, 0.85 + clampf(speed / 1500.0, 0.0, 1.0) * 0.3)
		if speed > 1000.0:
			Sfx.loop("glisse_rapide_boucle", clampf((speed - 1000.0) / 700.0, 0.0, 1.0) * 0.5)
	# vent en l'air (après un petit moment, pour ne pas souffler à chaque bosse)
	if not is_on_ground:
		_sfx_air_time += dt
		if _sfx_air_time > 0.25:
			Sfx.loop("vent_boucle", clampf(speed / 1600.0, 0.0, 1.0) * 0.45)
			if speed > 1300.0:
				Sfx.loop("vitesse_boucle", clampf((speed - 1300.0) / 600.0, 0.0, 1.0) * 0.35)
	# fond sonore : vent arctique lointain, très doux
	Sfx.loop("ambiance_vent", 0.25)
	# atterrissage : plus fort si on tombait vite (pas en réapparaissant)
	if is_on_ground and not _sfx_was_ground and _sfx_air_time > 0.2 and not _respawning:
		var impact := clampf(_sfx_last_vy / 900.0, 0.2, 1.0)
		Sfx.play("atterrissage", linear_to_db(impact) - 2.0)
	if is_on_ground:
		_sfx_air_time = 0.0
	# pump : un « fff » à chaque appui au sol
	if is_on_ground and Input.is_action_just_pressed("pump") and not Settings.kid_mode:
		Sfx.play("pump", -5.0)
	_sfx_was_ground = is_on_ground
	_sfx_last_vy = _velocity.y
