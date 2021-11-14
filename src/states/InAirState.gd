extends CanMoveState
class_name InAirState

#var sub_state_name = "IN AIR"
var super_state_name = "IN AIR"

export var rotation_speed = 8

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)

	var input_speed = Input.get_action_strength("rotate_horaire") - Input.get_action_strength("rotate_trigo")
	player.rotation += rotation_speed * input_speed * delta

	if Input.is_action_just_pressed("trix"):
		print('to trix')
		player._states.go_to_state(player, "trixing")
#		player._states.current = player._states.trixing
#		player._states.current._enter(player)

	if player.floor_detector.is_colliding():
		print('to ground')
		player._states.go_to_state(player, "on_ground")
#		player._states.current = player._states.on_ground
#		player._states.current._enter(player)

	if Input.is_action_just_pressed("hook"):
		print('to hook')
		player._states.go_to_state(player, "hooking")
#		player._states.current = player._states.hooking
#		player._states.current._enter(player)

	if Input.is_action_just_released("hook"):
		print('unhook in air')
		player._states.hooking.exit(player)

	# pump léger sur l'axe y en l'air
	if Input.is_action_just_pressed("pump") and player._velocity.y > 0:  # player going down
		player._velocity.y += player.gravity * delta * 3
		print("pump")

func enter(player: KinematicBody2D) -> void:
	player.snap = Vector2.ZERO
	player.anim_player.play("jumping")

func _ready():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
