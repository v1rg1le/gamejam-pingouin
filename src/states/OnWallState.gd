extends CanMoveState
class_name OnWallState

var super_state_name = "ON GROUND"

#onready var coyote_timer: Timer = $Timer
#onready var coyote_timer: Timer = Timer.new(

func _handle_input(player: KinematicBody2D, delta: float) -> void:
#	print(coyote_timer.time_left)
#	player._states.label3.text = String(coyote_timer.time_left)
#	if !player.floor_detector.is_colliding() and coyote_timer.is_stopped():
#		coyote_timer.start(0.5)
#		print("coyote timer started")
#	if (Input.is_action_just_pressed("jump") and (player.floor_detector.is_colliding() or coyote_timer.time_left > 0 )):
	._handle_input(player, delta)
#	player.direction.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	if Input.is_action_just_pressed("jump"): # and player.floor_detector.is_colliding():
		print('wall jump !')
#		player._states.current_state = player._states.jumping
#		player._states.current_state._enter(player)

# Called when the node enters the scene tree for the first time.
func _ready():
#	coyote_timer = get_tree().create_timer(10.0)
#	coyote_timer.set_one_shot(true)
#	coyote_timer.process_mode = 1
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
