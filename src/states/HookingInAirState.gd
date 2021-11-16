extends InAirState
class_name HookingInAirState

const CHAIN_PULL = 25
var pull_factor = 1
var friction_chain_default = 1.65
var friction = friction_chain_default
var stretch_factor_default = 15000
var stretch_factor = stretch_factor_default

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	if player.is_on_ground:
		player._states.current = player._states.hooking_on_ground
		return

	._handle_input(player, delta)
#	player.snap = Vector2.ZERO

	if !Input.is_action_pressed("hook"):
		print('to air')
		player._states.go_to_state(player, "in_air")

# Hook physics
	if player.chain.hooked:
		if player.chain.tip.y > global_position.y:  # grapping vers le bas
			pull_original(player)
		else:  # grapping vers le haut
			swing(player, delta)

	elif !player.chain.hooked:  # check distance de la chain quand tire dans le vide
		if player.chain.distance >= player.chain.distance_max:
			player.chain.release()
			player._states.go_to_state(player, "sliding")


func pull_original(player: KinematicBody2D):
	# premier grapin pete mais qui marche bien pour se pull (au sol)
	if Input.is_action_pressed("pull"):
		pull_factor = 2

	var direction_chain = to_local(player.chain.tip).normalized() # * CHAIN_PULL
	var normale = -direction_chain.tangent()
	
	if player.chain_velocity.y > 0:
		friction = .75 # 1.65 # 0.55
#			print("friction -- vitesse chain positive")
	else:
		friction = 1.65  # .5 # 1.65 # 0.55
#			print("friction -- vitesse chain negative ")

	if sign(player.chain_velocity.x) != sign(player.facing):
#			print("friction -- changement de cote")
		friction = 0.6

	if player._velocity.x < 0:
		normale = -normale  #angle_to(Vector2(sign(player._velocity.x),0))  # avec la normale a droite, a multiplier * direction_player

#		print(normale, "   ", direction_chain)
#	player.hook_tangent.cast_to = normale*100 # DEBUG
#		var angle_traction = (normale) * CHAIN_PULL
	var angle_traction = (normale + direction_chain) * CHAIN_PULL
	player.chain_velocity = angle_traction

#		player.chain_velocity.x = angle_traction.x * friction * pull_factor
	player.chain_velocity.x *= friction * pull_factor  # seulement friction sur x suffit a fix chain (?)

	# ON DONNE VITESSE AU JOUEUR
	player._velocity += player.chain_velocity
#
#	# clamp vitesse map reelle en mode hook
	player._velocity.x = clamp(player._velocity.x, -player.MAX_SPEED_HOOKED.x, player.MAX_SPEED_HOOKED.x)
	player._velocity.y = clamp(player._velocity.y, -player.MAX_SPEED_HOOKED.y, player.MAX_SPEED_HOOKED.y)


func swing(player: KinematicBody2D, delta):
	var radius = player.global_position - player.chain.tip # points away from center
#	if vel.length() < 0.01 or radius.length() < 10: return

	var angle = acos(radius.dot(player._velocity) / (radius.length() * player._velocity.length()))
	var rad_vel = cos(angle) * player._velocity.length() 
	
	# vitesse angulaire
	player._velocity += radius.normalized() * -rad_vel
	# mode corde fixe (avec encore un peu de gravite)
	if global_position.distance_to(player.chain.tip) > player.chain.max_length and player.chain_fixed:
		return

	# Hacky way to fix gradual lengthening // a garder au cas ou
#	if global_position.distance_to(player.chain.tip) > player.chain.distance:
#		global_position = player.chain.tip + radius.normalized() * player.chain.distance
	
	if player.chain.distance < 120:  # pour eviter collision forcee entre joueur et grapin
		# on ajoute pas la vitesse lineaire pour le stretch
		return 
	
	# si joueur a une vitesse faible et est dans une petite angle sous le grapin
	if abs(radius.normalized().x) < .35 and player._velocity.abs() < player.MIN_SPEED_HOOKED:
		return

	elif sign((player.chain.tip.x - global_position.x)) == sign(player.facing):
#		print("grapin a l'avant du joueur")
		stretch_factor = stretch_factor_default * .5
	else:
#		print("grapin dans le dos du joueur")
		stretch_factor = stretch_factor_default * .5

	if Input.is_action_pressed("pull"):
		stretch_factor = stretch_factor * 3

	# vitesse lineaire pour faire le stretch 
	player._velocity += (player.chain.tip - global_position).normalized() * stretch_factor * delta

func exit(player: KinematicBody2D) -> void:
	player.chain.release()

func enter(player: KinematicBody2D, _previous_state: PlayerState) -> void:
#	player.snap = Vector2.ZERO
	pull_factor = 1  # par default
	player.chain_velocity = Vector2.ZERO
	
	var angle_aimed = player._get_aim_direction() 
	if angle_aimed == Vector2.ZERO:  # valeur par default
		angle_aimed = Vector2(500*player.facing,-500)
	player.chain.shoot(angle_aimed)
	
	player.animated_sprite.animation = "hooking"

func _ready():
	sub_state_name = "HOOKING"
