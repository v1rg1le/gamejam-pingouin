extends OnGroundState
class_name RunningState

#var sub_state_name = "RUNNING"

export var running_speed = 500

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)
#	
	var input_speed = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	player.direction.x = input_speed
	player._velocity.x = lerp(player._velocity.x, running_speed * input_speed, _get_h_weight(player, input_speed))

func _update(_player: KinematicBody2D) -> void:
	pass

func _enter(player: KinematicBody2D) -> void:
	._enter(player)
	player.animated_sprite.animation = "run"

func _ready():
	sub_state_name = "RUNNING"
	._ready()
