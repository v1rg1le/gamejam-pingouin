extends OnGroundState
class_name RunningState

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)

func _enter(player: KinematicBody2D) -> void:
	player.anim_player.play("run")

func _ready():
	sub_state_name = "RUNNING"
	._ready()
