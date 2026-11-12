extends OnGroundState
class_name RunningState

func _handle_input(player: CharacterBody2D, delta: float) -> void:
	super._handle_input(player, delta)

func _enter(player: CharacterBody2D) -> void:
#	player.animated_sprite.animation = "run"
	player.anim_player.play("running")

func _ready():
	sub_state_name = "RUNNING"
	super._ready()
