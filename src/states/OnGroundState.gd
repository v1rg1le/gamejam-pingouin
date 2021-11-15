extends CanMoveState
class_name OnGroundState

var sub_state_name = ""
var super_state_name = "ON_GROUND"

var to_idle_countdown = 10

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)

	var floor_normal = player.get_floor_normal()
	if floor_normal != Vector2.ZERO:
		player.rotation = lerp(player.rotation, -floor_normal.angle_to(Vector2.UP), .2)

	if Input.is_action_just_released("hook"):
		print('unhook on ground')
		player._states.hooking_on_ground.exit(player)

	if Input.is_action_just_pressed("jump") and player.floor_detector.is_colliding():
		print('to jump !')
		player._states.go_to_state(player, "jumping")

	if Input.is_action_just_pressed("hook"):
		print('to hook on ground')
		player._states.go_to_state(player, "hooking_on_ground")
		return

	if player._states.current.sub_state_name != "HOOKING":
		
		if player.floor_detector.is_colliding() == false:
			player._states.go_to_state(player, "in_air")
			return

		if Input.is_action_just_pressed("pump") and player.floor_detector.is_colliding() and player._states.current.sub_state_name != "PUMPING":
			print("pump !")
			player._states.go_to_state(player, "pumping")
			return
	#		player.animated_sprite.animation = "pump"
	#		var coef = 1.4  # 1.2
	#		player._velocity = lerp(player._velocity, accel_factor * player._velocity, 0.04)  #0.2
	#		player._velocity = Vector2( clamp(player._velocity.x, -player.max_speed.x * coef, player.max_speed.x * coef),
	#									clamp(player._velocity.y, -player.max_speed.y * coef, player.max_speed.y * coef) )

	#	Si le joueur est presque arrêté, on l'aide
		if abs(player._velocity.x) <= player.velocity_max_idle:
#			to_idle_countdown -= 1
#			if to_idle_countdown <= 0:
			if player._states.current.sub_state_name != "IDLE":
				player._states.go_to_state(player, "idling")
			player._velocity.x = lerp(player._velocity.x, 0, 0.9)
		elif abs(player._velocity.x) <= player.max_running_velocity:
			if player._states.current.sub_state_name != "RUNNING":
				print("to running")
				player._states.go_to_state(player, "running")
#			to_idle_countdown = 10
	#	Si le joueur est en train de slider
		elif player._states.current.sub_state_name != "SLIDING" && player._states.current.sub_state_name != "PUMPING":
			print("to sliding")
			player._states.go_to_state(player, "sliding")
#			player.anim_player.play("run")
#			to_idle_countdown = 10

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
