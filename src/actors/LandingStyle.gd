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
## [ATTERRISSAGES 1.41] Bec relevé d'au moins cet angle (degrés), pattes
## vers le sol : il retombe DEBOUT. Demande de l'équipe (21/11) : « si on
## atterrit sur le ventre, on glisse sur le ventre comme avant ; on n'est
## debout que si l'on tombe sur les pattes ». Avant (1.40), tout atterrissage
## ni nose ni chute mettait Pinpouin debout.
##   bec en avant > 35°        -> nose (ventre, points)
##   entre -30° et +35°        -> ventre (glisse d'origine)
##   bec relevé de 30° à 120°  -> pattes (debout)
##   au-delà de 120°           -> chute
const FEET_ANGLE_DEG := 30.0
## Temps en l'air minimum pour que l'atterrissage compte (s).
const MIN_AIR_TIME := 0.25

# =============================================================================
#  [TAIL 1.50] Atterrissage bec relevé = « TAIL ! » + glisse en équilibre
# -----------------------------------------------------------------------------
#  Demande de l'équipe (21/11) :
#   1. « tail » doit marcher comme « nose » : un atterrissage bec relevé (la
#      glisse debout, sur les pattes) rapporte TAIL_POINTS, compte dans le
#      combo du saut et donne le petit boost de figure (TrickScore._on_landed,
#      style "feet" : le nom du signal ne change pas, le tuto s'en sert) ;
#   2. pendant la glisse en tail, on peut BASCULER avec les touches de
#      rotation (choix de l'équipe) :
#        - bec vers l'avant ({rotate_horaire} en allant à droite) : Pinpouin
#          se couche et glisse sur le VENTRE (rien à gagner : les points du
#          tail sont déjà gagnés à l'atterrissage) ;
#        - bec vers l'arrière ({rotate_trigo} en allant à droite) : il penche
#          vers le DOS ; trop penché (TAIL_FALL_DEG) = CHUTE avec la roulade
#          (CrashState) ; en relâchant avant, il se redresse tout seul.
#      Le sens « avant / arrière » suit le sens de la glisse (facing), comme
#      pour le nose (même convention qu'_on_landing).
#  `tail_tilt` (radians) : 0 = debout ; > 0 = penché vers l'avant (ventre) ;
#  < 0 = penché vers l'arrière (dos). Il ne change QUE le dessin (le corps
#  du pingouin reste collé à la pente, comme avant) : aucune influence sur la
#  physique de la glisse.
#  Mode enfant : pas de chute, l'inclinaison s'arrête juste avant.
# =============================================================================
## Points d'un atterrissage en tail (comme le nose).
const TAIL_POINTS := 50
## Vitesse à laquelle on penche en tenant une touche de rotation (degrés / s).
const TAIL_TILT_SPEED_DEG := 140.0
## Vitesse à laquelle il se redresse tout seul quand on relâche (degrés / s).
const TAIL_RETURN_SPEED_DEG := 220.0
## Penché vers l'avant d'au moins cet angle : il se couche sur le ventre.
const TAIL_TO_BELLY_DEG := 35.0
## Penché vers l'arrière d'au moins cet angle : chute (roulade).
const TAIL_FALL_DEG := 70.0

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
## [TAIL 1.50] inclinaison du dessin en tail (rad) : > 0 vers le ventre, < 0 vers le dos
var tail_tilt := 0.0
## [TAIL 1.50] vrai juste après une apparition (début de niveau, réapparition
## après une chute, retour au début d'un atelier du tuto) : le pingouin
## « tombe » à sa place, ce n'est pas un vrai saut. Sans ça, il retombait
## bec relevé sur le tremplin de départ et gagnait un « TAIL ! » gratuit
## (50 points + boost) au début de chaque niveau (vu en test).
var fresh_spawn := true
var _grain: ImageTexture = null


func setup(p) -> void:
	player = p
	# [TAIL 1.50] une réapparition est aussi une « apparition »
	if player.has_signal("respawned"):
		player.respawned.connect(func(): fresh_spawn = true)


## Appelé par Player._physics_process, après move_and_slide.
func update(delta: float) -> void:
	if player == null or player._respawning:
		return
	var st = player._states.current
	var hooked: bool = player.chain.hooked
	# un VRAI sol seulement (surface tournée vers le haut) : à l'envers sous une
	# île, les capteurs (qui tournent avec le pingouin) touchent le DESSOUS de
	# l'île, ce qui n'est pas un atterrissage (bug vu en test : fausse chute)
	# [1.66] on_real_floor : contact SOUS Pinpouin (un plafond n'est jamais
	# un atterrissage, même si sa normale paraît tournée vers le haut)
	var grounded: bool = on_real_floor()
	if not grounded:
		_air_time += delta
		# on retient l'écart avec la pente tant que le jeu ne redresse pas
		# encore le pingouin tout seul (aucun capteur ne touche le sol)
		if not hooked:
			_approach_rel = angle_difference(_slope_rotation_below(), player.rotation)
	elif fresh_spawn:
		# [TAIL 1.50] premier contact après une apparition : ni tail, ni nose,
		# ni chute ; la posture reste celle du départ (sur le ventre)
		fresh_spawn = false
	elif not _was_grounded and _air_time >= MIN_AIR_TIME and not hooked \
			and st.super_state_name != "CRASH" and st.super_state_name != "STAGGERED":
		_on_landing(st)
	if grounded:
		_air_time = 0.0
	_was_grounded = grounded
	_update_tail_balance(delta, grounded, hooked)   # [TAIL 1.50]
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
	elif forward < -deg_to_rad(FEET_ANGLE_DEG):
		# [ATTERRISSAGES 1.41] bec RELEVÉ (pattes vers le sol) : debout
		# [TAIL 1.50] = « TAIL ! » : TrickScore ajoute TAIL_POINTS au saut
		tail_tilt = 0.0
		_set_pose("feet")
		player.emit_signal("landed", "feet")
	else:
		# [ATTERRISSAGES 1.41] à plat, parallèle à la pente : sur le ventre,
		# la glisse d'origine (avant la 1.41, c'était debout)
		_set_pose("belly")
		player.emit_signal("landed", "belly")


func _set_pose(pose: String) -> void:
	ride_pose = pose
	# l'état au sol a peut-être déjà lancé son animation dans cette image : on
	# la relance avec la bonne posture
	var sub: String = player._states.current.sub_state_name
	var anims := {"SLIDING": "sliding", "RUNNING": "running", "PUMPING": "pumping"}
	if anims.has(sub):
		player.play_ground_anim(anims[sub])


# [TAIL 1.50] Équilibre pendant la glisse debout (voir l'en-tête « TAIL »).
# Appelé à chaque image physique par update(). Ne fait rien hors de la glisse
# debout au sol (en l'air, au grappin, pendant une chute…).
func _update_tail_balance(delta: float, grounded: bool, hooked: bool) -> void:
	var st = player._states.current
	var riding: bool = ride_pose == "feet" and grounded and not hooked \
		and st.super_state_name == "ON_GROUND" and st.sub_state_name != "HOOKING"
	if not riding:
		tail_tilt = 0.0
		return
	# touche « vers l'avant » / « vers l'arrière » selon le sens de la glisse :
	# en allant à droite, horaire = bec vers l'avant (comme pour le nose)
	var input: float = (Input.get_action_strength("rotate_horaire") - Input.get_action_strength("rotate_trigo")) * player.facing
	if absf(input) > 0.1:
		tail_tilt += input * deg_to_rad(TAIL_TILT_SPEED_DEG) * delta
	else:
		# relâché : il se redresse tout seul
		tail_tilt = move_toward(tail_tilt, 0.0, deg_to_rad(TAIL_RETURN_SPEED_DEG) * delta)

	# trop vers l'avant : il se couche sur le ventre (aucun point en plus)
	if tail_tilt >= deg_to_rad(TAIL_TO_BELLY_DEG):
		tail_tilt = 0.0
		_set_pose("belly")
		snow_burst(player.global_position, player._velocity, 0.45)   # petit « flop » dans la neige
		Sfx.play("atterrissage", -6.0)
		return

	# trop vers l'arrière : chute (roulade), sauf en mode enfant
	if tail_tilt <= -deg_to_rad(TAIL_FALL_DEG):
		if Settings.kid_mode:
			tail_tilt = -deg_to_rad(TAIL_FALL_DEG - 5.0)   # [MODE ENFANT] il ne tombe jamais
			return
		print("[TAIL] perte d'équilibre vers l'arrière : chute")
		tail_tilt = 0.0
		player.emit_signal("landed", "crash")   # même effet qu'une chute sur le dos (points, tuto)
		snow_burst(player.global_position, player._velocity)
		player._states.go_to_state(player, "crashing")


## Ce capteur touche-t-il un sol tourné vers le haut (pas un plafond) ?
## [1.66] Vrai si Pinpouin touche un VRAI sol (surface tournée vers le haut).
## Sert à TrixState / CrashState / StaggeredState : toucher un PLAFOND en
## pleine figure (capteurs tournés vers le haut, Pinpouin à l'envers) n'est
## pas un atterrissage.
## Vu au test : contre un plafond de caverne (segments), la normale renvoyée
## peut pointer vers le haut ; on exige donc AUSSI que le point de contact
## soit SOUS le centre de Pinpouin.
func on_real_floor() -> bool:
	var y0: float = player.global_position.y - 4.0
	for ray in [player.ground_detector_right, player.ground_detector_left]:
		if _ray_on_floor(ray) and ray.get_collision_point().y > y0:
			return true
	for i in player.get_slide_collision_count():
		var c = player.get_slide_collision(i)
		if c.get_normal().y < -0.6 and c.get_position().y > y0:
			return true
	return false


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
		# [TAIL 1.50] + l'inclinaison choisie au clavier (vers le ventre / le dos)
		spr.rotation = (tail_tilt - lean) * player.facing
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
