extends OnGroundState
class_name RunningState

#var sub_state_name = "RUNNING"

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)

func _update(_player: KinematicBody2D) -> void:
	pass

func enter(player: KinematicBody2D) -> void:
#	._enter(player)
	player.animated_sprite.animation = "run"

func _ready():
	sub_state_name = "RUNNING"
	._ready()
