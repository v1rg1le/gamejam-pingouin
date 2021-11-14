extends CanMoveState
class_name HookingState

var sub_state_name = "HOOKING"
var super_state_name = "HOOKING"

const CHAIN_PULL = 25
var pull_factor = 1

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)

	if !Input.is_action_pressed("hook"):
		player.chain.release()
		player._states.current = player._states.in_air
		player._states.current._enter(player)

# Hook physics
	if player.chain.hooked:
		if Input.is_action_pressed("pull"):
			pull_factor = 3
		
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

	else:  # check distance de la chain quand tirer dans le vide
		if player.chain.distance >= player.chain.distance_max:
			player.chain.release()
			player._states.current = player._states.sliding
			player._states.current._enter(player)


func _update(_player: KinematicBody2D) -> void:
	pass
#	if !player.hang == null:
#		createLine(player.global_position, player.hang.global_position, player.line_hook) #Dessin
#		print("draw 2d update")

func enter(player: KinematicBody2D) -> void:
	pull_factor = 1  # par default
	player.chain_velocity = Vector2.ZERO
#			if event.pressed:
			# We clicked the mouse -> shoot()
	player.chain.shoot((get_global_mouse_position() - global_position).normalized())  #event.position - get_viewport().size * 0.5)
#		else:
			# We released the mouse -> release()
#			$Chain.player.chain.release()
#	print("chain shoot")
	
	player.animated_sprite.animation = "hooking"
#	print("hooking enter")
#	player.direction.y = -1.0
#	player.snap = Vector2.ZERO
#	player._velocity.y = player.max_speed.y * player.direction.y

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
