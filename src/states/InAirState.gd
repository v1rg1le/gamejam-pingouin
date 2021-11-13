extends CanMoveState
class_name InAirState

var super_state_name = "IN AIR"

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	
	._handle_input(player, delta)
	
#	player.rotation = lerp(player.rotation, -player.get_floor_normal().angle_to(Vector2.UP), .2)
	print(player.floor_detector.is_colliding())

	if player.floor_detector.is_colliding():
		print('land !')
		player._states.current_state = player._states.idling
		player._states.current_state._enter(player)
		
	if Input.is_action_just_pressed("hook"):
		player._states.current_state = player._states.hooking
		player._states.current_state._enter(player)

func _ready():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
