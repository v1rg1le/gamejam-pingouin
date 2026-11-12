extends OnGroundState
class_name SlidingState

func _handle_input(player: CharacterBody2D, delta: float) -> void:
	super._handle_input(player, delta)

func _update(_player: CharacterBody2D) -> void:
	pass

func enter(player: CharacterBody2D, _previous_state: PlayerState) -> void:
	player.anim_player.play("sliding")

func _ready():
	sub_state_name = "SLIDING"
	super._ready()
