extends InAirState
class_name JumpingState

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)

#	if player.direction.y == -1:
#		player._velocity.y = player.max_speed.y * player.direction.y * delta
	
	if Input.is_action_just_pressed("hook"):
		print("hoooook")
		player._states.go_to_state(player, "hooking_in_air")

func enter(player: KinematicBody2D, _previous_state: PlayerState) -> void:
	print('enter jumping')
#	player.anim_player.play("jumping")
#	player.animated_sprite.animation = "fly"
	player.direction.y = -1.0
#	player.snap = Vector2.ZERO
	player._velocity.y = player.max_speed.y * player.direction.y

func _ready():
	sub_state_name = "JUMPING"
