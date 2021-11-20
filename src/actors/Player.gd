extends KinematicBody2D

export var stomp_impulse: = 500.0
var facing: int = 1
var _states: StateMachine
onready var animated_sprite = $"AnimatedSprite"

export var pump_accel_factor = 1.3

onready var chain: = $Chain
var chain_velocity := Vector2(0,0)
onready var chain_length = 0
export(bool) var chain_fixed = false

# from Actor
const SUPER_MAX_SPEED = Vector2(3000, 3000)
const MAX_SPEED_HOOKED = Vector2(1000,1000)
const MIN_SPEED_HOOKED = Vector2(200,200)
export var max_speed: = Vector2(700, 600)  # Vector2(1000, 600) // 500 ?
export var max_speed_chain: = Vector2(14, 20) # Vector2(50, 60)  # Vector2(1000, 600)
export var gravity: float = 800.0

var _velocity: Vector2 = Vector2.ZERO

# from OnGroundState
export var accel_factor_pump = 1.3
export var velocity_max_idle = 100  # velocity min for running state
export var max_running_velocity = 500  # velocity max for running state

var is_on_ground: bool = false
var is_almost_on_ground: bool = false
onready var ground_detector_right: = $GroundDetectorRight
onready var ground_detector_left: = $GroundDetectorLeft
#onready var test_raycast = $TestRaycast
onready var coyote_timer  # initalise dans ready pour get nom de scene actuelle : = get_node("/root/LevelChill704/Player/StateMachine/CoyoteTimer")

onready var anim_player = $AnimationPlayer

var direction: Vector2

onready var camera: = $Camera2D
export var running_speed = 500

func _ready():
	_states = $"StateMachine"
	_states.current._enter(self)
	coyote_timer = $"StateMachine/CoyoteTimer"

func _physics_process(delta: float) -> void:
	is_on_ground = ground_detector_right.is_colliding() and ground_detector_left.is_colliding()
	is_almost_on_ground = \
		(ground_detector_right.is_colliding() and !ground_detector_left.is_colliding()) or \
		(!ground_detector_right.is_colliding() and ground_detector_left.is_colliding())

	handle_input(delta)

	if abs(_velocity.x) > 10:
		facing = 1 if _velocity.x > 0 else -1
	animated_sprite.flip_h = facing != 1

	_velocity.y += gravity * delta
#	_velocity = Vector2( clamp(_velocity.x, 0, max_speed.x),
#					clamp(_velocity.y, 0, max_speed.y) )

	_velocity.x = clamp(_velocity.x, -SUPER_MAX_SPEED.x, SUPER_MAX_SPEED.x)
	_velocity.y = clamp(_velocity.y, -SUPER_MAX_SPEED.y, SUPER_MAX_SPEED.y)
	# HookinInAirState clamp la _velocity avec player.MAX_SPEED_HOOKED

	# DEBUG Label velocity, angle
	_states.label3.text = str(Vector2(
		floor(_velocity.length()),
			-floor(rad2deg(_velocity.angle()))
		))
	print("-pos :",Vector3(
		floor(position.x),
			floor(position.y),
				floor(rad2deg(_velocity.angle()))
		))
	print("  speed :",floor(_velocity.length()))
#	_states.label3.text = str(Vector2(floor(position.x),floor(position.x)))
	

	_velocity = move_and_slide(_velocity)

func _process(_delta): # camera follows player velocity on x
#	CAMERA MANU FONCTIONNE WOULLAH
	var viewport = Vector2(
		get_viewport().size.x,
		get_viewport().size.y
	)
	var camera_offset_percentage_x = 0.8
	var camera_offset_x = clamp(
		pow( abs(_velocity.x) / SUPER_MAX_SPEED.x, 0.5),
		-camera_offset_percentage_x,
		camera_offset_percentage_x)
	camera.offset.x = lerp( camera.offset.x , sign(_velocity.x) * camera_offset_x * camera.zoom.x * viewport.x / 2, 0.1)

func handle_input(delta: float) -> void:
	_states.current._handle_input(self, delta)

func update() -> void:
	_states.current.update()

func _get_aim_direction() -> Vector2:
	match Settings.controls:
		Settings.GAMEPAD:
			return Vector2(
				Input.get_action_strength("aim_right") - Input.get_action_strength("aim_left"),
				Input.get_action_strength("aim_down") - Input.get_action_strength("aim_up")).normalized()
		Settings.KBD_MOUSE, _:
			return (get_global_mouse_position() - global_position).normalized()


func _on_Chain_chain_hooked(current_length):
	chain_length = current_length
