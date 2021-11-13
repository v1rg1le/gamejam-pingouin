extends OnGroundState
class_name RunningState

var sub_state_name = "RUNNING"

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)
	if (Input.get_action_strength("move_right") - Input.get_action_strength("move_left")) == 0.0:
		player._states.current_state = player._states.idling
		player._states.current_state._enter(player)

func _update(player: KinematicBody2D) -> void:
	pass

func _enter(player: KinematicBody2D) -> void:
	._enter(player)
	player.animated_sprite.animation = "run"

func _ready():
	._ready()