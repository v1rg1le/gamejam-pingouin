extends OnGroundState
class_name SlidingState

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)

func _update(_player: KinematicBody2D) -> void:
	pass

func enter(player: KinematicBody2D, _previous_state: PlayerState) -> void:
	player.anim_player.play("sliding")

func _ready():
	sub_state_name = "SLIDING"
	._ready()
