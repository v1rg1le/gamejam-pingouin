extends PlayerState
class_name StaggeredState

var super_state_name = "STAGGERED"
var sub_state_name = "STAGGERED"

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	pass

func _update(player: KinematicBody2D) -> void:
	pass

func _enter(player: KinematicBody2D) -> void:
	pass

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
