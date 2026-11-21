extends Node
class_name LandingStyle
# =============================================================================
#  LandingStyle.gd — [ATTERRISSAGES 1.40] comment Pinpouin retombe au sol
# -----------------------------------------------------------------------------
#  Demande de Manu (21/11), comme en skate :
#   - atterrir bien droit       -> il glisse DEBOUT sur ses pattes (nouvelle
#                                  animation « glide_feet », avec le dessin de
#                                  Pinpouin debout déjà dans le jeu) ;
#                                  juste visuel, il reste debout jusqu'au
#                                  prochain saut (choix de Manu) ;
#   - atterrir le bec en avant  -> NOSE : il glisse à plat ventre (la glisse
#                                  d'origine), « NOSE ! » + points + petit
#                                  boost, comme une figure réussie ;
#   - atterrir sur le dos       -> CHUTE : explosion de neige, roulade en
#                                  boule, puis assis étourdi 1 s (CrashState).
#  Tolérance choisie : « généreux », chute seulement au-delà de 120° de
#  travers par rapport à la pente.
#
#  Comment on mesure : l'angle compte AVANT que le jeu ne redresse Pinpouin
#  tout seul (InAirState l'aligne sur la pente dès qu'un capteur touche le
#  sol). On garde donc, à chaque image en l'air, l'angle entre le pingouin et
#  la pente qui est sous lui (rayon vers le bas, indépendant de sa rotation),
#  et on lit la dernière valeur au moment du contact.
#  Attention : les 2 capteurs de sol (GroundDetector) tournent avec le
#  pingouin. Sur le dos, ils regardent vers le CIEL : c'est donc le contact
#  du corps avec le sol (move_and_slide) qui détecte la chute.
#
#  Créé par Player._ready() ; Player._physics_process() appelle update()
#  juste après le mouvement, AVANT que TrickScore ne valide les points de la
#  même image (le « Nose » compte donc dans le combo du saut).
# =============================================================================

## Au-delà de cet écart avec la pente (degrés), c'est la chute.
const CRASH_ANGLE_DEG := 120.0
## Bec en avant d'au moins cet angle (degrés) : nose.
const NOSE_ANGLE_DEG := 35.0
## Points du nose (une figure = 100) ; comptent dans le combo du saut.
const NOSE_POINTS := 50
## Temps en l'air minimum pour que l'atterrissage compte (s).
const MIN_AIR_TIME := 0.25

## Posture au sol : "feet" (debout) ou "belly" (à plat ventre, la glisse
## d'origine). Au départ du niveau : à plat ventre, comme avant.
var ride_pose := "belly"
## Dernier « angle de la pente » trouvé sous le pingouin (rotation à avoir
## pour être bien posé dessus). Sert à remettre Pinpouin droit après une chute.
var last_slope_rotation := 0.0

var player = null
var _air_time := 0.0
var _approach_rel := 0.0          # écart pingouin / pente juste avant le contact (rad)
var _was_grounded := true
var _feet_visual := false         # vrai tant qu'on modifie le dessin (penché, rebond)
var _bob_t := 0.0
var _grain: ImageTexture = null


func setup(p) -> void:
	player = p


## Appelé par Player._physics_process, après move_and_slide.
func update(delta: float) -> void:
	if player == null or player._respawning:
		return
	var st = player._states.current
	var hooked: bool = player.chain.hooked
	# un VRAI sol seulement (surface tournée vers le haut) : à l'envers sous une
	# île, les capteurs (qui tournent avec le pingouin) touchent le DESSOUS de
	# l'île, ce qui n'est pas un atterrissage (bug vu en test : fausse chute)
	var grounded: bool = _ray_on_floor(player.ground_detector_right) \
		or _ray_on_floor(player.ground_detector_left) or _body_on_floor()
	if not grounded:
		_air_time += delta
		# on retient l'écart avec la pente tant que le jeu ne redresse pas
		# encore le pingouin tout seul (aucun capteur ne touche le sol)
		if not hooked:
			_approach_rel = angle_difference(_slope_rotation_below(), player.rotation)
	elif not _was_grounded and _air_time >= MIN_AIR_TIME and not hooked \
			and st.super_state_name != "CRASH" and st.super_state_name != "STAGGERED":
		_on_landing(st)
	if grounded:
		_air_time = 0.0
	_was_grounded = grounded
	_update_feet_visual(delta)


func _on_landing(st) -> void:
	var rel := _approach_rel
	var forward: float = rel * player.facing      # > 0 : bec vers le bas, vers l'avant
	if absf(rel) > deg_to_rad(CRASH_ANGLE_DEG):
		if Settings.kid_mode:
			# [MODE ENFANT] pas de chute : Pinpouin se retrouve sur ses pattes
			player.rotation = last_slope_rotation
			_set_pose("feet")
			return
		print("[ATTERRISSAGE] chute sur le dos (%d°)" % int(rad_to_deg(rel)))
		player.emit_signal("landed", "crash")
		snow_burst(player.global_position, player._velocity)
		player._states.go_to_state(player, "crashing")
		return
	if st.sub_state_name == "TRIXING":
		return   # figure pas finie : c'est la « figure ratée » d'avant (StaggeredState)
	if forward > deg_to_rad(NOSE_ANGLE_DEG):
		_set_pose("belly")
		player.emit_signal("landed", "nose")
	else:
		_set_pose("feet")
		player.emit_signal("landed", "feet")


func _set_pose(pose: String) -> void:
	ride_pose = pose
	# l'état au sol a peut-être déjà lancé son animation dans cette image : on
	# la relance avec la bonne posture
	var sub: String = player._states.current.sub_state_name
	var anims := {"SLIDING": "sliding", "RUNNING": "running", "PUMPING": "pumping"}
	if anims.has(sub):
		player.play_ground_anim(anims[sub])


## Ce capteur touche-t-il un sol tourné vers le haut (pas un plafond) ?
func _ray_on_floor(ray: RayCast2D) -> bool:
	return ray.is_colliding() and ray.get_collision_normal().y < -0.3


## Le corps touche-t-il un sol (et pas un mur ou un plafond) ? Sur le dos, les
## capteurs regardent en l'air : c'est le seul moyen de voir le contact.
func _body_on_floor() -> bool:
	for i in player.get_slide_collision_count():
		var n: Vector2 = player.get_slide_collision(i).get_normal()
		if n.y < -0.6:
			return true
	return false


## Rotation qu'aurait le pingouin bien posé sur la pente juste sous lui
## (même formule qu'OnGroundState). Rayon vertical, indépendant de sa rotation.
func _slope_rotation_below() -> float:
	var space = player.get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(player.global_position,
		player.global_position + Vector2(0, 700), player.collision_mask, [player.get_rid()])
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return last_slope_rotation
	var n: Vector2 = hit.normal
	if n.y > -0.3:
		return last_slope_rotation    # paroi presque verticale : on garde l'ancienne
	last_slope_rotation = -n.angle_to(Vector2.UP)
	return last_slope_rotation


# --- Glisse debout : petit penché en arrière (comme un surfeur) et léger
#     rebond du dessin. Rien n'est modifié sur l'image elle-même. ------------
func _update_feet_visual(delta: float) -> void:
	var spr: AnimatedSprite2D = player.animated_sprite
	if spr.animation == "glide_feet":
		_bob_t += delta
		_feet_visual = true
		var speed: float = player._velocity.length()
		var lean := clampf(speed / 1500.0, 0.0, 1.0) * 0.22   # plus vite = plus penché
		spr.rotation = -lean * player.facing
		var crouch: bool = Input.is_action_pressed("pump")    # PUMP : il se tasse
		spr.scale = Vector2(1.06, 0.88) if crouch else Vector2.ONE
		spr.offset = Vector2(0, -15 + (3.0 if crouch else 0.0) + sin(_bob_t * 14.0) * 0.6)
	elif _feet_visual:
		_feet_visual = false
		if player._states.current.super_state_name != "CRASH":
			spr.rotation = 0.0
		spr.scale = Vector2.ONE
		spr.offset = Vector2(0, -15)


# --- Explosion de neige : cache la roulade (et le passage dos → fesses) ----
## at : point de départ ; vel : vitesse du pingouin (la neige part avec lui,
## sinon à grande vitesse elle reste derrière) ; size : 1 = normal.
func snow_burst(at: Vector2, vel: Vector2 = Vector2.ZERO, size: float = 1.0) -> void:
	if _grain == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_grain = ImageTexture.create_from_image(img)
	var colors := Gradient.new()
	colors.set_color(0, Color(1, 1, 1))
	colors.set_color(1, Color(0.55, 0.80, 1.0))
	colors.add_point(0.6, Color(0.9, 0.96, 1.0))
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1.0))
	fade.add_point(0.6, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	# 1) gros paquets de neige lents, juste sur le pingouin (le masquent)
	# 2) éclats rapides projetés tout autour
	var specs := [
		{"amount": 34, "life": 0.8, "vmin": 40.0, "vmax": 180.0, "smin": 22.0, "smax": 40.0, "grav": 120.0, "radius": 18.0},
		{"amount": 80, "life": 0.9, "vmin": 220.0, "vmax": 650.0, "smin": 6.0, "smax": 13.0, "grav": 980.0, "radius": 10.0},
	]
	for sp in specs:
		var p := CPUParticles2D.new()
		p.top_level = true
		p.z_index = 110                 # devant le pingouin (dessin z 100)
		p.one_shot = true
		p.explosiveness = 0.95
		p.amount = int(sp.amount * size)
		p.lifetime = sp.life
		p.local_coords = false
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = sp.radius
		# vers le haut, penché dans le sens de la glisse, et plus vite si
		# Pinpouin va vite : le nuage avance avec lui et le cache
		var fwd := vel * 0.55
		p.direction = (Vector2(0, -1) * 300.0 + fwd).normalized()
		p.spread = 100.0
		p.initial_velocity_min = sp.vmin + fwd.length() * 0.8
		p.initial_velocity_max = sp.vmax + fwd.length()
		p.gravity = Vector2(0, sp.grav)
		p.damping_min = 30.0
		p.damping_max = 90.0
		p.angular_velocity_min = -200.0
		p.angular_velocity_max = 200.0
		p.scale_amount_min = sp.smin * size
		p.scale_amount_max = sp.smax * size
		p.texture = _grain
		p.color_initial_ramp = colors
		p.color_ramp = fade
		player.get_parent().add_child(p)
		p.global_position = at + Vector2(0, -6)
		p.emitting = true
		p.get_tree().create_timer(sp.life + 0.3).timeout.connect(p.queue_free)
