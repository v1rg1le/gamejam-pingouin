extends CanMoveState
class_name JumpingState

var super_state_name = "JUMPING"
var sub_state_name = "JUMPING"

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)

	if player.direction.y == -1:
		player._velocity.y = player.max_speed.y * player.direction.y #* delta

	if player.is_on_floor():
		player._states.current_state = player._states.idling
		player._states.current_state._enter(player)
#		return
	elif Input.is_action_just_released("jump") and player._velocity.y < 0.0:
		player._velocity.y = 0.0
	print(player._velocity)
#		TODO state falling

func _update(player: KinematicBody2D) -> void:
	pass

func enter(player: KinematicBody2D) -> void:
	player.animated_sprite.animation = "spin"
	player.direction.y = -1.0
#	player._velocity.y = -1000
	player._velocity.y = player.max_speed.y * player.direction.y
#	player._velocity.y += player.gravity

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
