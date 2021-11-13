extends Actor

export var stomp_impulse: = 500.0
var is_facing_left: bool = false
var _states: StateMachine
onready var animated_sprite = $"AnimatedSprite"

var direction: Vector2

func _ready():
	_states = $"StateMachine"
	_states.current_state._enter(self)

func _on_EnemyDetector_area_entered(area):
	_velocity = calculate_stomp_velocity(_velocity, stomp_impulse)

func _physics_process(delta: float) -> void:
	direction = Vector2(0,0)
	
	if Input.get_action_strength("move_right") - Input.get_action_strength("move_left") != 0:
		is_facing_left = Input.get_action_strength("move_right") - Input.get_action_strength("move_left") < 0
	animated_sprite.flip_h = is_facing_left

	handle_input(delta)
	
	_velocity.y += gravity * delta
	_velocity = move_and_slide(_velocity, FLOOR_NORMAL)

func calculate_stomp_velocity(linear_velocity: Vector2, impulse: float) -> Vector2:
	var out = linear_velocity
	out.y = -impulse
	return out

func handle_input(delta: float) -> void:
	_states.current_state._handle_input(self, delta)

func update() -> void:
	_states.current_state.update()
