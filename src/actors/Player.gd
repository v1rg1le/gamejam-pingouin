extends Actor

export var stomp_impulse: = 500.0
var facing: int = 1
var _states: StateMachine
onready var animated_sprite = $"AnimatedSprite"
var snap: Vector2 = Vector2.DOWN
onready var floor_detector: RayCast2D = $"FloorDetector"

onready var chain: = $Chain
var chain_velocity := Vector2(0,0)

const SUPER_MAX_SPEED = Vector2(3000, 3000)

onready var raycast_hook = $HookDetector
onready var hook_tangent = $HookTangent
#onready var line_hook = get_node("/root/LevelTest/LineHook")


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
