extends Actor

export var stomp_impulse: = 500.0
var facing: int = 1
var _states: StateMachine
onready var animated_sprite = $"AnimatedSprite"
var snap: Vector2 = Vector2.UP
onready var floor_detector: RayCast2D = $"FloorDetector"

onready var chain = $Chain
var chain_velocity := Vector2(0,0)

#onready var hook = $Hook
onready var raycast_hook = $HookDetector
onready var hook_tangent = $HookTangent
#onready var line_hook = get_node("/root/LevelTest/LineHook")


var hang #Permet de garder en mémoire le node auquel le joueur est accroché avec le grappin

var direction: Vector2

func _ready():
	_states = $"StateMachine"
	_states.current_state._enter(self)

func _on_EnemyDetector_area_entered(_area):
	_velocity = calculate_stomp_velocity(_velocity, stomp_impulse)

func _physics_process(delta: float) -> void:
	direction = Vector2(0,0)
	var temp_sign
	
	if Input.get_action_strength("move_right") - Input.get_action_strength("move_left") != 0:
		temp_sign = sign(Input.get_action_strength("move_right") - Input.get_action_strength("move_left"))
		facing = temp_sign 
	animated_sprite.flip_h = facing != 1

	handle_input(delta)
	
	_velocity.y += gravity * delta
	_velocity = move_and_slide_with_snap(_velocity, FLOOR_NORMAL, snap)

func calculate_stomp_velocity(linear_velocity: Vector2, impulse: float) -> Vector2:
	var out = linear_velocity
	out.y = -impulse
	return out

func handle_input(delta: float) -> void:
	_states.current_state._handle_input(self, delta)

func update() -> void:
	_states.current_state.update()

func _get_aim_direction() -> Vector2:
	match Settings.controls:
		Settings.GAMEPAD:
			return Vector2(
				Input.get_action_strength("aim_right") - Input.get_action_strength("aim_left"),
				Input.get_action_strength("aim_down") - Input.get_action_strength("aim_up")).normalized()
		Settings.KBD_MOUSE, _:
			return (get_global_mouse_position() - global_position).normalized()
