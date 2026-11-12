extends InAirState
class_name JumpingState
# [MIGRATION GODOT 4.7] KinematicBody2D -> CharacterBody2D, ._f() -> super._f()

func _handle_input(player: CharacterBody2D, delta: float) -> void:
	super._handle_input(player, delta)
	# [MIGRATION GODOT 4.7 / GRAPPIN] si le parent a déjà changé d'état (atterrissage,
	# grappin...), on ne déclenche pas une 2e transition dans la même frame.
	if player._states.current != self:
		return

#	if player.direction.y == -1:
#		player._velocity.y = player.max_speed.y * player.direction.y * delta
	
	if Input.is_action_just_pressed("hook"):
		print("hoooook")
		player._states.go_to_state(player, "hooking_in_air")

func enter(player: CharacterBody2D, _previous_state: PlayerState) -> void:
	print('enter jumping')
#	player.anim_player.play("jumping")
#	player.animated_sprite.animation = "fly"
	player.direction.y = -1.0
#	player.snap = Vector2.ZERO
	player._velocity.y = player.max_speed.y * player.direction.y

func _ready():
	sub_state_name = "JUMPING"
