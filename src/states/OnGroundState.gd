extends CanMoveState
class_name OnGroundState

var sub_state_name = "ON_GROUND"
var super_state_name = "ON_GROUND"
#export var accel_factor_pump = 1.3
#export var velocity_max_idle = 100  # velocity min for running state
#export var max_running_velocity = 500  # velocity max for running state

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)

	var floor_normal = player.get_floor_normal()
	if floor_normal != Vector2.ZERO:
		player.rotation = lerp(player.rotation, -floor_normal.angle_to(Vector2.UP), .2)
	
	if player.floor_detector.is_colliding() == false:
		player._states.go_to_state(player, "in_air")
#		player._states.current = player._states.in_air
#		player._states.current._enter(player)
		return

	if Input.is_action_just_released("hook"):
		print('unhook on ground')
		player._states.hooking.exit(player)

	if Input.is_action_just_pressed("jump") and player.floor_detector.is_colliding():
		print('to jump !')
		player._states.go_to_state(player, "jumping")
#		player._states.current = player._states.jumping
#		player._states.current._enter(player)

	if Input.is_action_just_pressed("hook"):
		print('to hook')
		player._states.go_to_state(player, "hooking")
#		player._states.current = player._states.hooking
#		player._states.current._enter(player)
		return

	if Input.is_action_pressed("pump") and player.floor_detector.is_colliding():
#		print("pump !")	
#		player.animated_sprite.animation = "pump"
		player.anim_player.play("pump")
		var coef = 1.4  # 1.2
		player._velocity = lerp(player._velocity, player.accel_factor_pump * player._velocity, 0.04)  #0.2
		player._velocity = Vector2( clamp(player._velocity.x, -player.max_speed.x * coef, player.max_speed.x * coef),
									clamp(player._velocity.y, -player.max_speed.y * coef, player.max_speed.y * coef) )


#	Si le joueur est presque arrêté, on l'aide
	if abs(player._velocity.x) <= player.velocity_max_idle:
		if player._states.current.sub_state_name != "IDLE":
			player._states.go_to_state(player, "idling")
#			player._states.current = player._states.idling
#			player._states.current._enter(player)
		player._velocity.x = lerp(player._velocity.x, 0, 0.9)
	elif abs(player._velocity.x) <= player.max_running_velocity:
		if player._states.current.sub_state_name != "RUNNING":
			player._states.go_to_state(player, "running")
#			player._states.current = player._states.running
#			player._states.current._enter(player)
#	Si le joueur est en train de slider
	elif player._states.current.sub_state_name != "SLIDING":
		print("to sliding")
		player._states.go_to_state(player, "sliding")
		player.anim_player.play("run")

func _ready():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
