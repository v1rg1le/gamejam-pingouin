extends OnGroundState
class_name HookingOnGroundState

const CHAIN_PULL = 15
var pull_factor = 1

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	if player.floor_detector.is_colliding() == false:
		player._states.current = player._states.hooking_in_air
		return
	
	._handle_input(player, delta)
	player.snap = Vector2.ZERO

	if !Input.is_action_pressed("hook"):
		print('to ground')
		player._states.go_to_state(player, "on_ground")

# Hook physics
	if player.chain.hooked:
		if Input.is_action_pressed("pull"):
			pull_factor = 2
		
		var direction_chain = to_local(player.chain.tip).normalized() # * CHAIN_PULL
		var friction = 1.65
		var normale = -direction_chain.tangent()

		if player.chain_velocity.y > 0:
			friction = 0.55
		else:
			if player._velocity.x < 0:
				normale = -normale  #angle_to(Vector2(sign(player._velocity.x),0))  # avec la normale a droite, a multiplier * direction_player

			player.hook_tangent.cast_to = normale*100 # DEBUG
#			player.chain_velocity = normale * CHAIN_PULL

		var angle_traction = (normale + direction_chain) * CHAIN_PULL
		player.chain_velocity = angle_traction

		player.chain_velocity *= friction * pull_factor

		if sign(player.chain_velocity.x) != sign(player.direction.x):
			player.chain_velocity.x *= 0.6
		player._velocity += player.chain_velocity

	elif !player.chain.hooked:  # check distance de la chain quand tire dans le vide
		if player.chain.distance >= player.chain.distance_max:
			player.chain.release()
			player._states.go_to_state(player, "sliding")


func _update(_player: KinematicBody2D) -> void:
	pass
#	if !player.hang == null:
#		createLine(player.global_position, player.hang.global_position, player.line_hook) #Dessin
#		print("draw 2d update")

func exit(player: KinematicBody2D) -> void:
	player.chain.release()

func enter(player: KinematicBody2D) -> void:
	player.snap = Vector2.ZERO
	pull_factor = 1  # par default
	player.chain_velocity = Vector2.ZERO
	var angle_aimed = player._get_aim_direction() 
#	valeur par default
	if angle_aimed == Vector2.ZERO:
		angle_aimed = Vector2(500*player.facing,-500)

	player.chain.shoot(angle_aimed) #(get_global_mouse_position() - global_position).normalized())  #event.position - get_viewport().size * 0.5)
	
	player.animated_sprite.animation = "hooking"

func _ready():
	sub_state_name = "HOOKING"

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
