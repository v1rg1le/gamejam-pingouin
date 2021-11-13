extends CanMoveState
class_name OnGroundState

var super_state_name = "ON GROUND"

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	
	._handle_input(player, delta)
	
#	print(player.get_floor_normal())
	# player.snap = -player.get_floor_normal()
	player.rotation = lerp(player.rotation, -player.get_floor_normal().angle_to(Vector2.UP), .2)
#	print(player.floor_detector.is_colliding())

	if Input.is_action_just_pressed("jump") and player.floor_detector.is_colliding():
		print('jump !')
		player._states.current_state = player._states.jumping
		player._states.current_state._enter(player)
		
	if Input.is_action_just_pressed("hook"):
		player._states.current_state = player._states.hooking
		player._states.current_state._enter(player)

func _ready():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
