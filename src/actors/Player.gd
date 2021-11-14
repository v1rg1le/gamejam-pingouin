extends KinematicBody2D

export var stomp_impulse: = 500.0
var facing: int = 1
var _states: StateMachine
onready var animated_sprite = $"AnimatedSprite"
var snap: Vector2 = Vector2.DOWN
onready var floor_detector: RayCast2D = $"FloorDetector"
#onready var rotator: = $"Rotator"


onready var chain: = $Chain
var chain_velocity := Vector2(0,0)

# from Actor
const SUPER_MAX_SPEED = Vector2(3000, 3000)
export var max_speed: = Vector2(700, 600)  # Vector2(1000, 600) // 500 ?
export var max_speed_chain: = Vector2(14, 20) # Vector2(50, 60)  # Vector2(1000, 600)
export var gravity: float = 800.0

var _velocity: Vector2 = Vector2.ZERO

# from OnGroundState
export var accel_factor_pump = 1.3
export var velocity_max_idle = 100  # velocity min for running state
export var max_running_velocity = 500  # velocity max for running state

onready var hook_tangent = $HookTangent

onready var anim_player = $AnimationPlayer

var hang #Permet de garder en mémoire le node auquel le joueur est accroché avec le grappin

var direction: Vector2

onready var camera: = $Camera2D
export var running_speed = 500

func _ready():
	_states = $"StateMachine"
	_states.current._enter(self)

func _on_EnemyDetector_area_entered(_area):
	_velocity = calculate_stomp_velocity(_velocity, stomp_impulse)

func _physics_process(delta: float) -> void:
	
	if abs(_velocity.x) > 10:
		facing = _velocity.x > 0
	animated_sprite.flip_h = facing != 1

	handle_input(delta)

#	snap = (floor_detector.position + floor_detector.cast_to)
#	$TestSnap.cast_to = (floor_detector.position + floor_detector.cast_to) #DEBUG
	
	_velocity.y += gravity * delta
	
#	_velocity = Vector2( clamp(_velocity.x, 0, max_speed.x),
#					clamp(_velocity.y, 0, max_speed.y) )
	
	_velocity.x = clamp(_velocity.x, -SUPER_MAX_SPEED.x, SUPER_MAX_SPEED.x)
	_velocity.y = clamp(_velocity.y, -SUPER_MAX_SPEED.y, SUPER_MAX_SPEED.y)
	
	_velocity = move_and_slide_with_snap(_velocity, Vector2.DOWN, Vector2.UP)
#	_velocity = move_and_slide_with_snap(_velocity, snap, Vector2.UP)

func _process(delta): # camera follows player velocity
	var x = _velocity.x / 2
	var y = _velocity.y / 3
	camera.offset = lerp(camera.offset, Vector2(x,y), 0.1)

#	NE MARCHE PAS TRES BIEN
#	var offset_min = 100
#	var viewport = Vector2(
#		get_viewport().size.x,
#		get_viewport().size.y
#	)
#	var x = (_velocity.x / 3) #+ (viewport.x /2)
#	var y = (_velocity.y / 4) #+ (viewport.y /2)
#	var temp_offset
#	print(camera.offset)
#	print(Vector2(x,y))
#
#	if _velocity.x < 0:
#		viewport.x = viewport.x / 2
#	print(viewport)
#
#	temp_offset = lerp(camera.offset, Vector2(x,y), .5)
#	print(temp_offset)
#	temp_offset = Vector2(
#		clamp(temp_offset.x, offset_min, viewport.x - offset_min),
#		clamp(temp_offset.y, offset_min, viewport.y - offset_min)
#	)
#	print("-")
#	print(temp_offset)
#	camera.offset = temp_offset
#	print("---")

func calculate_stomp_velocity(linear_velocity: Vector2, impulse: float) -> Vector2:
	var out = linear_velocity
	out.y = -impulse
	return out

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
