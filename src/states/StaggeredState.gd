extends PlayerState
class_name StaggeredState

var super_state_name: = "STAGGERED"
var sub_state_name: = "STAGGERED"

@export var staggered_time: = 2.0
var timer: Timer

var animations = ["stuck", "staggered"]
# [ATTERRISSAGES 1.40] la chute (CrashState) impose une durée plus courte
# (1 s) et le dessin « assis étourdi » ; remis à zéro après usage.
var next_time := -1.0
var next_anim := ""

func _handle_input(player: CharacterBody2D, _delta: float) -> void:
#	._handle_input(player, delta)
	if timer.is_stopped():
#		print("timer fini")
		player._states.go_to_state(player, "idling")
	else:
		player._velocity = Vector2.ZERO

func enter(player: CharacterBody2D, _previous_state: PlayerState) -> void:
	print('entering staggered')
	Sfx.play("figure_rate")   # [BRUITAGES 1.34] « boing », Pinpouin sonné
#	player.anim_player.play("staggered")
#	player.anim_player.play("stuck")
	randomize()
	# [ATTERRISSAGES 1.40] dessin et durée imposés par une chute, sinon comme avant
	player.anim_player.play(next_anim if next_anim != "" else animations[randi() % animations.size()])
	timer.start(next_time if next_time > 0.0 else staggered_time)
	next_time = -1.0
	next_anim = ""

func _ready():
	timer = Timer.new()
	timer.set_one_shot(true)
	timer.set_wait_time(staggered_time)
	add_child(timer)
