extends CanMoveState
class_name InAirState
# =============================================================================
#  [MIGRATION GODOT 4.7] export/onready -> @export/@onready, ._f() -> super._f()
#
#  [FIX VITESSE -> 0] La touche Shift est liée à la fois à "pull" (tirer sur le
#  grappin) ET à "trix" (figure). En tirant sur le grappin en l'air, on lançait
#  donc une figure sans le vouloir : le grappin lâchait, et si on touchait le
#  sol pendant la figure => état STAGGERED => vitesse forcée à 0 pendant 2 s.
#  => On ne déclenche plus de figure pendant le grappin (ni dans la frame où
#     on vient de le lâcher).
#
#  [GRAPPIN] alignement au sol avec lerp_angle (au lieu de lerp) : après des
#  vrilles en l'air la rotation peut valoir 4π, et lerp faisait "dérouler"
#  toutes les vrilles à l'atterrissage (raycasts en travers => contacts ratés).
# =============================================================================

var sub_state_name = ""
var super_state_name = "IN AIR"

@export var rotation_speed = 8

@onready var coyote_timer  # defini dans ready (path en fonction du level lancé) # : = get_node("/root/LevelChill704/Player/StateMachine/CoyoteTimer")

func _handle_input(player: CharacterBody2D, delta: float) -> void:
	super._handle_input(player, delta)

	var input_speed = Input.get_action_strength("rotate_horaire") - Input.get_action_strength("rotate_trigo")

	if input_speed != 0:
		player.rotation = lerpf(player.rotation, player.rotation + rotation_speed * input_speed * delta, .8)
	if player.rotation != 0 and input_speed == 0:  # input_speed == 0:
		# si pas dans les etats hook
		if player._states.current.sub_state_name != "HOOKING":
			player.rotation = lerp_angle(player.rotation, 0.0, 0.02)  # aide trop a replaquer ? 0.04

	var floor_normale = Vector2.UP
	if player.is_almost_on_ground:
		if player.ground_detector_right.is_colliding():
			floor_normale = player.ground_detector_right.get_collision_normal()
		else:
			floor_normale = player.ground_detector_left.get_collision_normal()
		player.rotation = lerp_angle(player.rotation, -floor_normale.angle_to(Vector2.UP), .2)

	# [FIX VITESSE -> 0] pas de figure pendant le grappin (Shift = pull ET trix)
	var is_hooking = player._states.current.sub_state_name == "HOOKING" or Input.is_action_pressed("hook")
	if Input.is_action_just_pressed("trix") && player._states.current.sub_state_name != "TRIXING" && !is_hooking:
		print('to trix')
		player._states.go_to_state(player, "trixing")
		return

	# (en figure, c'est TrixState qui gère l'atterrissage -> STAGGERED, comme avant)
	if player.is_on_ground and player._states.current.sub_state_name != "TRIXING":
		print('to ground')
		player._states.go_to_state(player, "on_ground")
		return  # [GRAPPIN] ne pas enchaîner d'autres transitions dans la même frame

	if Input.is_action_just_pressed("hook"):
		print('to hook in air')
		player._states.go_to_state(player, "hooking_in_air")
		return

	if Input.is_action_just_released("hook"):
		print('unhook in air')
		player._states.hooking_in_air.exit(player)

	if Input.is_action_just_pressed("jump") and !coyote_timer.is_stopped() and \
		!(player._states.current.sub_state_name in ["HOOKING", "TRIXING", "JUMPING"]) and \
		player._velocity.y > 0:
		print('to coyote jump !')
		player._states.go_to_state(player, "jumping")

	# pump léger sur l'axe y en l'air
	if Input.is_action_just_pressed("pump") and player._velocity.y > 0:  # player going down
		player._velocity.y += player.gravity * delta * 3
		print("pump")

func enter(player: CharacterBody2D, previous_state: PlayerState) -> void:
	if coyote_timer.is_stopped() and player._velocity.y > 0 and \
		!(previous_state.super_state_name in ["IN AIR"]):
		print("coyote ON")
		coyote_timer.start()

	player.anim_player.play("jumping")

func _ready():
	coyote_timer = get_parent().get_node("CoyoteTimer")
	coyote_timer.one_shot = true  # false pour que coyote_timer fonctionne bien
	# on peut niquer le game en reactivant le timer si player recoit OnGroundState (grapping + rotation contre un mur, meme a 90°)
	coyote_timer.wait_time = .33

func exit(_player: CharacterBody2D) -> void:
#	coyote_timer.stop()  # stopper lors du retour au sol
	pass
