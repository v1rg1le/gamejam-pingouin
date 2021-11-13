extends Node2D
class_name PlayerState


func _handle_input(_player: KinematicBody2D, _delta: float) -> void:
	pass

func _update(_player: KinematicBody2D) -> void:
	pass

func enter(_player: KinematicBody2D) -> void:
	pass

func _enter(player: KinematicBody2D) -> void:
	player._states.super_state_label.text = self.super_state_name
	player._states.sub_state_label.text = self.sub_state_name
	player._states.super_state_label.visible = false
	player._states.sub_state_label.visible = false
	enter(player)

# Called when the node enters the scene tree for the first time.
func _ready():
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
