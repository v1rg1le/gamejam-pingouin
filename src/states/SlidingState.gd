extends OnGroundState
class_name SlidingState

#var sub_state_name = "SLIDING"

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)
#	if (Input.get_action_strength("move_right") - Input.get_action_strength("move_left")) == 0.0:
#		player._states.current = player._states.idling
#		player._states.current._enter(player)

func _update(_player: KinematicBody2D) -> void:
	pass

func _enter(player: KinematicBody2D) -> void:
	._enter(player)
	player.animated_sprite.animation = "slide"

func _ready():
	sub_state_name = "SLIDING"
	._ready()
