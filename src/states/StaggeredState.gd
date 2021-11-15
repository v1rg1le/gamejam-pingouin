extends PlayerState
class_name StaggeredState

var super_state_name: = "STAGGERED"
var sub_state_name: = "STAGGERED"

export var staggered_time: = 2.0
var timer: Timer

func _handle_input(player: KinematicBody2D, delta: float) -> void:
#	._handle_input(player, delta)
	if timer.is_stopped():
		print("timer fini")
		player._states.go_to_state(player, "idling")
	else:
		player._velocity = Vector2.ZERO

func enter(player: KinematicBody2D) -> void:
	print('entering staggered')
	player.anim_player.play("staggered")
	timer.start()

func _ready():
	timer = Timer.new()
	timer.set_one_shot(true)
	timer.set_wait_time(staggered_time)
	add_child(timer)
