extends CanMoveState
class_name OnGroundState

var sub_state_name = "ON_GROUND"
var super_state_name = "ON_GROUND"
export var accel_factor = 1.3
export var velocity_min = 100
export var velocity_absolute_min = 10
export var max_running_velocity = 500

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)

	var floor_normal = player.get_floor_normal()
	if floor_normal != Vector2.ZERO:
		player.rotation = lerp(player.rotation, -floor_normal.angle_to(Vector2.UP), .2)

	if Input.is_action_just_pressed("jump") and player.floor_detector.is_colliding():
		print('to jump !')
		player._states.current = player._states.jumping
		player._states.current._enter(player)

	if Input.is_action_just_pressed("hook"):
		print('to hook')
		player._states.current = player._states.hooking
		player._states.current._enter(player)

	if Input.is_action_pressed("pump") and player.floor_detector.is_colliding():
#		print("pump !")	
		player.animated_sprite.animation = "pump"
		var coef = 1.4  # 1.2
		player._velocity = lerp(player._velocity, accel_factor * player._velocity, 0.04)  #0.2
		player._velocity = Vector2( clamp(player._velocity.x, -player.max_speed.x * coef, player.max_speed.x * coef),
									clamp(player._velocity.y, -player.max_speed.y * coef, player.max_speed.y * coef) )

	if player.floor_detector.is_colliding() == false:
		player._states.current = player._states.in_air
		player._states.current._enter(player)
		return

#	Si le joueur est presque arrêté, on l'aide
	if abs(player._velocity.x) <= velocity_min:
		if player._states.current.sub_state_name != "IDLE":
			player._states.current = player._states.idling
			player._states.current._enter(player)
		player._velocity.x = lerp(player._velocity.x, 0, 0.9)
	elif abs(player._velocity.x) <= max_running_velocity:
		if player._states.current.sub_state_name != "RUNNING":
			player._states.current = player._states.running
			player._states.current._enter(player)
#	Si le joueur est en train de slider
	elif player._states.current.sub_state_name != "SLIDING":
		print("to sliding")
		player._states.current = player._states.sliding
		player._states.current._enter(player)

func _ready():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
