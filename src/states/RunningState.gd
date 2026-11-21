extends OnGroundState
class_name RunningState

func _handle_input(player: CharacterBody2D, delta: float) -> void:
	super._handle_input(player, delta)

func _enter(player: CharacterBody2D) -> void:
#	player.animated_sprite.animation = "run"
	player.play_ground_anim("running")   # [ATTERRISSAGES 1.40] debout ou à plat ventre

func _ready():
	sub_state_name = "RUNNING"
	super._ready()
