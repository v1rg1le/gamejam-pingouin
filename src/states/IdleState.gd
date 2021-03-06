extends OnGroundState
class_name IdleState

func _handle_input(player: KinematicBody2D, delta: float) -> void:
#	If input not handled
#	Call parent method
	._handle_input(player, delta)
	if Input.get_action_strength("move_right") - Input.get_action_strength("move_left") != 0:
		var input_speed = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		player.direction.x = input_speed
		player._velocity.x = lerp(player._velocity.x, player.max_speed.x * input_speed, _get_h_weight(player, input_speed))
		player._states.current = player._states.running
		player._states.current._enter(player)

func enter(player: KinematicBody2D, _previous_state: PlayerState) -> void:
#	player.animated_sprite.animation = "idle"
#	player.anim_player.play("idle")
	player.anim_player.queue("idle")

# Called when the node enters the scene tree for the first time.
func _ready():
	sub_state_name = "IDLE"
	._ready()
