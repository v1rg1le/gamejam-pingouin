extends CanMoveState
class_name InAirState

var sub_state_name = ""
var super_state_name = "IN AIR"

export var rotation_speed = 8

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)

	var input_speed = Input.get_action_strength("rotate_horaire") - Input.get_action_strength("rotate_trigo")
#	player.rotation += rotation_speed * input_speed * delta
#	print(player.rotation + rotation_speed * input_speed * delta)

	if !input_speed == 0:
		player.rotation = lerp(player.rotation, player.rotation + rotation_speed * input_speed * delta, .8)
	if !player.rotation == 0 and input_speed == 0:  # input_speed == 0:
		# si pas dans les etats hook
		if player._states.current.sub_state_name != "HOOKING":
			player.rotation = lerp(player.rotation, 0, 0.02)  # aide trop a replaquer ? 0.04

	if Input.is_action_just_pressed("trix") && player._states.current.sub_state_name != "TRIXING":
		print('to trix')
		player._states.go_to_state(player, "trixing")

	if player.floor_detector.is_colliding():
		print('to ground')
		player._states.go_to_state(player, "on_ground")

	if Input.is_action_just_pressed("hook"):
		print('to hook in air')
		player._states.go_to_state(player, "hooking_in_air")

	if Input.is_action_just_released("hook"):
		print('unhook in air')
		player._states.hooking_in_air.exit(player)

	# pump léger sur l'axe y en l'air
	if Input.is_action_just_pressed("pump") and player._velocity.y > 0:  # player going down
		player._velocity.y += player.gravity * delta * 3
		print("pump")

func enter(player: KinematicBody2D) -> void:
	player.snap = Vector2.ZERO
	player.anim_player.play("jumping")

func _ready():
	pass
