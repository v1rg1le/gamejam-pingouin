extends CanMoveState
class_name OnGroundState
# =============================================================================
#  [MIGRATION GODOT 4.7] KinematicBody2D -> CharacterBody2D, ._f() -> super._f()
#
#  [FIX VITESSE -> 0]
#   - L'état IDLE (qui freine fort : vitesse.x * 0.1 à chaque frame) se
#     déclenchait dès que la vitesse HORIZONTALE passait sous 100 px/s.
#     Dans une montée/descente raide, vx est petit alors que le pingouin va
#     vite le long de la pente => on passait en IDLE et la vitesse tombait à
#     0 quasi instantanément. On compare maintenant la vitesse TOTALE.
#   - Après un saut, on sort tout de suite (return) : avant, la suite de la
#     fonction pouvait renvoyer immédiatement le pingouin en IDLE/RUNNING.
#   - Alignement au sol avec lerp_angle (pas de "déroulage" des vrilles).
# =============================================================================

var sub_state_name = ""
var super_state_name = "ON_GROUND"

#var autre_normale = Vector2.UP
#var real_normale = Vector2.UP

func _handle_input(player: CharacterBody2D, delta: float) -> void:
	super._handle_input(player, delta)
	
	var floor_normale = Vector2.UP
	
#	var is_on_ground = player.ground_detector_right.is_colliding() and player.ground_detector_left.is_colliding()
	if player.is_on_ground:
		floor_normale = player.ground_detector_right.get_collision_normal() + player.ground_detector_left.get_collision_normal()
#		print(real_normale)
#		player.test_raycast.cast_to = real_normale * 100
	elif player.is_almost_on_ground:
		if player.ground_detector_right.is_colliding():
			floor_normale = player.ground_detector_right.get_collision_normal()
		else:
			floor_normale = player.ground_detector_left.get_collision_normal()

#		autre_normale = (player.ground_detector_right.get_collision_point() + player.ground_detector_left.get_collision_point()).tangent().normalized()
#		player.test_raycast_2.cast_to = autre_normale * 100
#	else:
#		player.test_raycast.cast_to = Vector2.DOWN
#		player.test_raycast_2.cast_to = Vector2.DOWN

#	var floor_normale = real_normale
#	var floor_normale = player.get_floor_normale()
#	print(floor_normale)

#	if floor_normale != Vector2.ZERO:
	player.rotation = lerp_angle(player.rotation, -floor_normale.angle_to(Vector2.UP), .2)

	if Input.is_action_just_released("hook"):
		print('unhook on ground')
		player._states.hooking_on_ground.exit(player)

	if Input.is_action_just_pressed("jump"):
		print('to in air jump !')
		player._states.go_to_state(player, "jumping")
		return  # [FIX] ne pas ré-écraser l'état "jumping" plus bas dans la même frame

	if Input.is_action_just_pressed("hook"):
		print('to hook on ground')
		player._states.go_to_state(player, "hooking_on_ground")
		return

	if player._states.current.sub_state_name != "HOOKING":
		if !player.is_on_ground:
			player._states.go_to_state(player, "in_air")
			return

	#	Si le joueur est presque arrêté, on l'aide
		# [FIX VITESSE -> 0] vitesse TOTALE (et plus seulement horizontale)
		var speed = player._velocity.length()
		if speed <= player.velocity_max_idle:
			if player._states.current.sub_state_name != "IDLE":
				player._states.go_to_state(player, "idling")
			player._velocity.x = lerpf(player._velocity.x, 0.0, 0.9)
		elif speed <= player.max_running_velocity:
			if player._states.current.sub_state_name != "RUNNING":
				print("to running")
				player._states.go_to_state(player, "running")
		elif Input.is_action_pressed("pump") and player._states.current.sub_state_name != "PUMPING":
			print("pump !")
			player._states.go_to_state(player, "pumping")
		elif player._states.current.sub_state_name != "SLIDING" && player._states.current.sub_state_name != "PUMPING":
			print("to sliding")
			player._states.go_to_state(player, "sliding")

func enter(player: CharacterBody2D, _previous_state: PlayerState) -> void:
	if !player.coyote_timer.is_stopped():  # reinitalise le coyote timer seulement lors du retour au sol
		player.coyote_timer.stop()

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
