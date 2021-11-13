extends KinematicBody2D
class_name Actor

# Declare member variables here. Examples:
export var max_speed: = Vector2(300, 600)
export var gravity: float = 800.0

var FLOOR_NORMAL = Vector2.UP

var _velocity: Vector2 = Vector2.ZERO

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func _physics_process(delta: float) -> void:
#	_velocity.y += gravity * delta
	pass
