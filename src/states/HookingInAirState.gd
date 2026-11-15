extends InAirState
class_name HookingInAirState
# =============================================================================
#  Grappin EN L'AIR
# -----------------------------------------------------------------------------
#  [MIGRATION GODOT 4.7] KinematicBody2D -> CharacterBody2D, ._f() -> super._f(),
#  Vector2.tangent() -> orthogonal() (même résultat).
#
#  [GRAPPIN STABILISÉ] — les 2 modes de traction d'origine sont CONSERVÉS :
#    * "pull_original" : traction quand le crochet est SOUS le joueur
#    * "swing"         : balancier + rappel quand le crochet est AU-DESSUS
#  Corrections apportées :
#   1. Direction de traction calculée en coordonnées GLOBALES.
#      Avant : to_local(tip) dans le repère de ce nœud, qui TOURNE avec le
#      pingouin (rotation en l'air / alignement au sol). Pingouin penché de
#      90° => traction envoyée sur le côté. C'était la principale cause des
#      comportements bizarres.
#   2. Hystérésis entre les 2 modes : avant, le mode changeait à CHAQUE frame
#      dès que le pingouin passait à la hauteur du crochet (tremblements).
#      Maintenant il faut dépasser d'au moins MODE_SWITCH_MARGIN pixels.
#   3. Le swing ne peut plus produire de NaN (acos d'une vitesse nulle).
#   4. pull_factor revient à 1 dès qu'on relâche "pull" (avant il restait à 2).
#   5. Comparaison "vitesse faible" corrigée : `Vector2 < Vector2` compare
#      d'abord x puis y (ordre lexicographique), pas les deux composantes.
#   6. Sorties d'état propres (return après changement d'état) et sortie
#      automatique si le grappin s'est décroché tout seul.
# =============================================================================

const CHAIN_PULL = 25
var pull_factor = 1
var friction_chain_default = 1.65
var friction = friction_chain_default
var stretch_factor_default = 15000
var stretch_factor = stretch_factor_default

# [GRAPPIN] mode de traction courant + marge d'hystérésis
const MODE_SWITCH_MARGIN = 48.0  # px
var mode_pull := true            # true = pull_original, false = swing
var _mode_initialised := false   # le mode est choisi au moment où le crochet s'accroche

func _handle_input(player: CharacterBody2D, delta: float) -> void:
	if player.is_on_ground:
		player._states.current = player._states.hooking_on_ground
		return

	super._handle_input(player, delta)
	# [GRAPPIN] l'appel parent a pu changer d'état (atterrissage, etc.) : on s'arrête là
	if player._states.current != self:
		return

	if !Input.is_action_pressed("hook"):
		print('to air')
		player._states.go_to_state(player, "in_air")
		return  # [GRAPPIN] avant : on continuait la physique du grappin après l'avoir lâché

# Hook physics
	if player.chain.hooked:
		_update_mode(player)
		if mode_pull:  # grapping vers le bas
			pull_original(player)
		else:  # grapping vers le haut
			swing(player, delta)

	elif player.chain.flying:  # check distance de la chain quand tire dans le vide
		if player.chain.distance >= player.chain.distance_max:
			player.chain.release()
			player._states.go_to_state(player, "in_air")  # [GRAPPIN] on est en l'air : "in_air" (avant "sliding")
	else:
		# [GRAPPIN] le grappin s'est décroché tout seul (trop étiré / accroche invalide)
		player._states.go_to_state(player, "in_air")


# [GRAPPIN] choisit le mode à l'accroche, puis ne change qu'avec une vraie marge
func _update_mode(player: CharacterBody2D) -> void:
	var dy = player.chain.tip.y - player.global_position.y  # > 0 : crochet sous le joueur
	if not _mode_initialised:
		mode_pull = dy > 0
		_mode_initialised = true
	elif mode_pull and dy < -MODE_SWITCH_MARGIN:
		mode_pull = false
	elif not mode_pull and dy > MODE_SWITCH_MARGIN:
		mode_pull = true


func pull_original(player: CharacterBody2D):
	# premier grapin pete mais qui marche bien pour se pull (au sol)
	pull_factor = 2 if Input.is_action_pressed("pull") else 1  # [GRAPPIN] se réinitialise

	# [GRAPPIN] direction globale joueur -> crochet (avant : to_local, repère tourné)
	var direction_chain = (player.chain.tip - player.global_position).normalized() # * CHAIN_PULL
	var normale = -direction_chain.orthogonal()

	if player.chain_velocity.y > 0:
		friction = .75 # 1.65 # 0.55
	else:
		friction = 1.65  # .5 # 1.65 # 0.55

	if sign(player.chain_velocity.x) != sign(player.facing):
		friction = 0.6

	if player._velocity.x < 0:
		normale = -normale  #angle_to(Vector2(sign(player._velocity.x),0))  # avec la normale a droite, a multiplier * direction_player

	var angle_traction = (normale + direction_chain) * CHAIN_PULL
	player.chain_velocity = angle_traction

	player.chain_velocity.x *= friction * pull_factor  # seulement friction sur x suffit a fix chain (?)

	# ON DONNE VITESSE AU JOUEUR
	player._velocity += player.chain_velocity

	# clamp vitesse map reelle en mode hook
	player._velocity.x = clamp(player._velocity.x, -player.MAX_SPEED_HOOKED.x, player.MAX_SPEED_HOOKED.x)
	player._velocity.y = clamp(player._velocity.y, -player.MAX_SPEED_HOOKED.y, player.MAX_SPEED_HOOKED.y)


func swing(player: CharacterBody2D, delta):
	var radius = player.global_position - player.chain.tip # points away from center
	# [GRAPPIN] garde-fou : rayon nul => direction indéfinie
	if radius.length() < 1.0:
		return
	var radius_dir = radius.normalized()

	# [GRAPPIN] composante radiale de la vitesse : v·r̂.
	# Identique à l'ancien `cos(acos(r·v / (|r||v|))) * |v|` mais sans division
	# par |v| (qui donnait NaN quand la vitesse était nulle).
	var rad_vel = player._velocity.dot(radius_dir)

	# vitesse angulaire
	player._velocity += radius_dir * -rad_vel
	# mode corde fixe (avec encore un peu de gravite)
	if player.global_position.distance_to(player.chain.tip) > player.chain.max_length and player.chain_fixed:
		return

	if player.chain.distance < 120:  # pour eviter collision forcee entre joueur et grapin
		# on ajoute pas la vitesse lineaire pour le stretch
		return

	# si joueur a une vitesse faible et est dans une petite angle sous le grapin
	# [GRAPPIN] comparaison composante par composante (cf. en-tête, point 5)
	if abs(radius_dir.x) < .35 and abs(player._velocity.x) < player.MIN_SPEED_HOOKED.x \
			and abs(player._velocity.y) < player.MIN_SPEED_HOOKED.y:
		return

	elif sign((player.chain.tip.x - player.global_position.x)) == sign(player.facing):
#		print("grapin a l'avant du joueur")
		stretch_factor = stretch_factor_default * .5
	else:
#		print("grapin dans le dos du joueur")
		stretch_factor = stretch_factor_default * .5

	if Input.is_action_pressed("pull"):
		stretch_factor = stretch_factor * 3

	# vitesse lineaire pour faire le stretch
	player._velocity += (player.chain.tip - player.global_position).normalized() * stretch_factor * delta

func exit(player: CharacterBody2D) -> void:
	player.chain.release()

func enter(player: CharacterBody2D, _previous_state: PlayerState) -> void:
	pull_factor = 1  # par default
	_mode_initialised = false  # [GRAPPIN] le mode sera choisi à l'accroche
	player.chain_velocity = Vector2.ZERO

	var angle_aimed = player._get_aim_direction()
	if angle_aimed == Vector2.ZERO:  # valeur par default
		angle_aimed = Vector2(500*player.facing,-500)
	player.chain.shoot(angle_aimed)

	player.animated_sprite.animation = "hooking"

func _ready():
	sub_state_name = "HOOKING"
	# [TEST ENFANT 1.22] MIGRATION GODOT 4 : en Godot 3, le _ready() de la
	# classe parente (InAirState) était appelé AUTOMATIQUEMENT ; en Godot 4 il
	# faut l'appeler soi-même. Sans ça, `coyote_timer` restait vide dans cet
	# état : appuyer sur SAUT ici provoquait une erreur de script qui
	# interrompait la lecture des commandes (pump en l'air ignoré, etc.).
	# Trouvé par le bot « enfant » qui tape sur SAUT n'importe quand.
	super._ready()
