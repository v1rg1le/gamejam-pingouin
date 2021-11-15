extends OnGroundState
class_name PumpState

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)

	if !Input.is_action_pressed("pump"):
		player._states.go_to_state(player, "on_ground")
	var coef = 1.4  # 1.2
	player._velocity = lerp(player._velocity, player.pump_accel_factor * player._velocity, 0.04)  #0.2
	player._velocity = Vector2(
		clamp(player._velocity.x, -player.max_speed.x * coef, player.max_speed.x * coef),
		clamp(player._velocity.y, -player.max_speed.y * coef, player.max_speed.y * coef)
	)

func enter(player: KinematicBody2D) -> void:
	player.animated_sprite.animation = "pump"

func _ready():
	sub_state_name = "PUMPING"

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
