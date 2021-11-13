extends OnGroundState
class_name IdleState

#var state_name = "IDLE"
var sub_state_name = "IDLE"

func _handle_input(player: KinematicBody2D, delta: float) -> void:
#	If input not handled
#	Call parent method
	._handle_input(player, delta)
	if Input.get_action_strength("move_right") - Input.get_action_strength("move_left") != 0:
		player._states.current_state = player._states.running
		player._states.current_state._enter(player)

func _update(player: KinematicBody2D) -> void:
	pass

func enter(player: KinematicBody2D) -> void:
	player.animated_sprite.animation = "idle"
	pass

# Called when the node enters the scene tree for the first time.
func _ready():
	._ready()

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
