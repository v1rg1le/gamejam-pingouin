extends InAirState
class_name JumpingState


var sub_state_name = "JUMPING"

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)

	if player.direction.y == -1:
		player._velocity.y = player.max_speed.y * player.direction.y * delta

	if player.floor_detector.is_colliding():
		player._states.go_to_state(player, "idling")
#		player._states.current = player._states.idling
#		player._states.current._enter(player)
	elif Input.is_action_just_released("jump") and player._velocity.y < 0.0:
		player._velocity.y *= 0.5
	elif Input.is_action_just_pressed("hook"):
		print("hoooook")
		player._states.go_to_state(player, "hooking")
#		player._states.current = player._states.hooking
#		player._states.current._enter(player)

func _update(_player: KinematicBody2D) -> void:
	pass

func enter(player: KinematicBody2D) -> void:
	player.animated_sprite.animation = "fly"
	player.direction.y = -1.0
	player.snap = Vector2.ZERO
	player._velocity.y = player.max_speed.y * player.direction.y

# Called when the node enters the scene tree for the first time.
func _ready():
#	sub_state_name = "JUMPING"
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
