extends CanMoveState
class_name HookingState

var super_state_name = "HOOKING"
var sub_state_name = "HOOKING"

const CHAIN_PULL = 12
var pull_factor = 1

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)


	if !Input.is_action_pressed("hook"):
		player.chain.release()
#		if player.floor_detector.is_colliding():
		player._states.current_state = player._states.running
		player._states.current_state._enter(player)
#		else:
#			player._states.current_state = player._states.jumping  # mettre falling
#			print("mettre falling sous etat de jumping ")
#			player._states.current_state._enter(player)

	if Input.is_action_pressed("pull") and player.chain.hooked:
		pull_factor = 3


# Hook physics
	if player.chain.hooked:
		var normale = 0
			# `to_local(player.chain.tip).normalized()` is the direction that the chain is pulling
		player.chain_velocity = to_local(player.chain.tip).normalized() * CHAIN_PULL
#		print(to_local(player.chain.tip).normalized())
		if player.chain_velocity.y > 0:
				# Pulling down isn't as strong
#			player.chain_velocity.y *= 0.55 * pull_factor
#			player.chain_velocity.x *= 0.55 * pull_factor
			var direction_chain = to_local(player.chain.tip).normalized()
			normale = direction_chain.angle_to(Vector2(1*player.direction.x,0))  # avec la normale a droite, a multiplier * direction_player
			player.chain_velocity *= normale * 0.4 * pull_factor
		else:
			var direction_chain = to_local(player.chain.tip).normalized()
			if player.direction.x == 1:
				# Pulling up is stronger
				normale = direction_chain.angle_to(Vector2(1*player.direction.x,0))  # avec la normale a droite, a multiplier * direction_player
			else: #if player.direction.x == -1:
				normale = direction_chain.angle_to(Vector2(-1*player.direction.x,0))  # avec la normale a droite, a multiplier * direction_player
			
#			var dvec = (point_b - point_a).normalized()
			# Rotate 90 degrees.
#			var normal = Vector2(direction_chain.y*player.direction.x, -direction_chain.x*player.direction.x)
			
			player.chain_velocity *= normale * 1.65 * pull_factor

		
		if sign(player.chain_velocity.x) != sign(player.direction.x):
				# if we are trying to walk in a different
				# direction than the chain is pulling
				# reduce its pull
			player.chain_velocity.x *= 0.6
#		if player.chain_velocity.y > 0 and player._velocity.y < 0:
#			player.chain_velocity.y *= 0.3
#			print("he lbat essaye de monter")
				
		
#		player.chain_velocity.x = clamp(player.chain_velocity.x, -player.max_speed_chain.x, player.max_speed_chain.x)
#		player.chain_velocity.y = clamp(player.chain_velocity.y, -player.max_speed_chain.y, player.max_speed_chain.y)
		player._velocity += player.chain_velocity


	elif !player.chain.hooked:  # check distance de la chain quand tirer dans le vide
		if player.chain.distance >= player.chain.distance_max:
			player.chain.release()
			player._states.current_state = player._states.running
			player._states.current_state._enter(player)





# code de manu -- fonctionne pas avec KinematicBody2D

##		#set position of our grapple to our player
#	player.hook.node_a = player.get_path()
#	player.hook.global_position = player.global_position
#	#Direction du raycast par rapport à la souris
#	player.raycast_hook.look_at(get_global_mouse_position())
#
##	if Input.is_action_pressed("hook"):
##		player.is_hook = true 
##		print("clic")
#	if player.raycast_hook.is_colliding():
##		is_hook = true
##			print("hook")
#		var thingtostick = player.raycast_hook.get_collider()
#		var distance = player.raycast_hook.get_collision_point().distance_to(player.global_position)
#
#		print(distance)
##		print(player.raycast_hook.length)
##		distance = 100
#		player.hook.length = distance
#		player.hook.global_rotation_degrees = player.raycast_hook.global_rotation_degrees - 90 #Attention le -90 est important
#		player.hook.rest_length = distance * 0#.7 #When the bodies attached to the spring joint move they 
##			stretch or squash it.The joint always tries to resize towards this length.
#
#		player.hook.node_b = thingtostick.get_path()
#		player.hang = thingtostick
#		print(get_node(player.hook.node_b).global_position)
#
##		print(player.hook.node_b)  # , player.hook.node_a)
#
##	if Input.is_action_pressed("pull") && is_hook:
##		print("press pull")
##		hook.rest_length = lerp(hook.rest_length,hook.rest_length*0.9,0.2)
##		print(hook.length)
##
##	if Input.is_action_pressed("push") && is_hook:
##		print("press pull")
##		hook.rest_length = lerp(hook.rest_length,hook.rest_length*1.1,0.2)
##		print(hook.length)
#
#		if !Input.is_action_pressed("hook"):
#			player.hook.node_b = player.hook.node_a
#			removeLine(player.line_hook) ##Dessin
#			player.hang = null
#			if player.floor_detector.is_colliding():
#				player._states.current_state = player._states.running
#				player._states.current_state._enter(player)
#			else:
#				player._states.current_state = player._states.jumping  # mettre falling
#				print("mettre falling sous etat de jumping ")
#				player._states.current_state._enter(player)
##		is_hook=false
#
#
#	removeLine(player.line_hook) ##Dessin
##	if is_hook: #Dessin
#	if !player.hang == null:
#		createLine(player.global_position, player.hang.global_position, player.line_hook) #Dessin
##		breakpoint

	


func _update(_player: KinematicBody2D) -> void:
	pass
#	if !player.hang == null:
#		createLine(player.global_position, player.hang.global_position, player.line_hook) #Dessin
#		print("draw 2d update")

func enter(player: KinematicBody2D) -> void:
	pull_factor = 1  # par default
	
#			if event.pressed:
			# We clicked the mouse -> shoot()
	player.chain.shoot((get_global_mouse_position() - global_position).normalized())  #event.position - get_viewport().size * 0.5)
#		else:
			# We released the mouse -> release()
#			$Chain.player.chain.release()
#	print("chain shoot")
	
#	player.snap = Vector2.ZERO
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
