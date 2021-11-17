extends CanMoveState
class_name InAirState

var sub_state_name = ""
var super_state_name = "IN AIR"

export var rotation_speed = 8

onready var coyote_timer  # defini dans ready (path en fonction du level lancé) # : = get_node("/root/LevelChill704/Player/StateMachine/CoyoteTimer")

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)

	var input_speed = Input.get_action_strength("rotate_horaire") - Input.get_action_strength("rotate_trigo")
#	player.rotation += rotation_speed * input_speed * delta
#	print(player.rotation + rotation_speed * input_speed * delta)

	if input_speed != 0:
		player.rotation = lerp(player.rotation, player.rotation + rotation_speed * input_speed * delta, .8)
	if player.rotation != 0 and input_speed == 0:  # input_speed == 0:
		# si pas dans les etats hook
		if player._states.current.sub_state_name != "HOOKING":
			player.rotation = lerp(player.rotation, 0, 0.02)  # aide trop a replaquer ? 0.04

	var floor_normale = Vector2.UP
	if player.is_almost_on_ground:
		print('almost on ground from air')
		if player.ground_detector_right.is_colliding():
			floor_normale = player.ground_detector_right.get_collision_normal()
		else:
			floor_normale = player.ground_detector_left.get_collision_normal()
		player.rotation = lerp(player.rotation, -floor_normale.angle_to(Vector2.UP), .2)

	if Input.is_action_just_pressed("trix") && player._states.current.sub_state_name != "TRIXING":
		print('to trix')
		player._states.go_to_state(player, "trixing")

	if player.is_on_ground:
		print('to ground')
		player._states.go_to_state(player, "on_ground")

	if Input.is_action_just_pressed("hook"):
		print('to hook in air')
		player._states.go_to_state(player, "hooking_in_air")

	if Input.is_action_just_released("hook"):
		print('unhook in air')
		player._states.hooking_in_air.exit(player)

	if Input.is_action_just_pressed("jump") and !coyote_timer.is_stopped() and \
		!(player._states.current.sub_state_name in ["HOOKING", "TRIXING", "JUMPING"]) and \
		player._velocity.y > 0:
		print('to coyote jump !')
#		coyote_timer.stop()
		player._states.go_to_state(player, "jumping")

	# pump léger sur l'axe y en l'air
	if Input.is_action_just_pressed("pump") and player._velocity.y > 0:  # player going down
		player._velocity.y += player.gravity * delta * 3
		print("pump")

func enter(player: KinematicBody2D, previous_state: PlayerState) -> void:
	if coyote_timer.is_stopped() and player._velocity.y > 0 and \
		!(previous_state.super_state_name in ["IN AIR"]):
		print("coyote ON")
		coyote_timer.start()
#	player.snap = Vector2.ZERO

	player.anim_player.play("jumping")

func _ready():
#	coyote_timer = get_node("/root/%s/Player/StateMachine/CoyoteTimer" % get_tree().current_scene.name)
	coyote_timer = get_parent().get_node("CoyoteTimer")
#	coyote_timer = Timer.new()
#	add_child(coyote_timer)
	coyote_timer.one_shot = true  # false pour que coyote_timer fonctionne bien
	# on peut niquer le game en reactivant le timer si player recoit OnGroundState (grapping + rotation contre un mur, meme a 90°)
	coyote_timer.wait_time = .33
#	pass

func exit(_player: KinematicBody2D) -> void:
#	coyote_timer.stop()  # stopper lors du retour au sol
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
