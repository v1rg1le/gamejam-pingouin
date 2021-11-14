extends Node2D
class_name PlayerState

func _handle_input(_player: KinematicBody2D, _delta: float) -> void:
	pass

func _update(_player: KinematicBody2D) -> void:
	pass

func enter(_player: KinematicBody2D) -> void:
	pass

func exit(_player: KinematicBody2D) -> void:
	pass

func _exit(_player: KinematicBody2D) -> void:
	exit(_player)

func _enter(_player: KinematicBody2D) -> void:
	_player._states.super_state_label.text = self.super_state_name
	var sub_text = ""
	if "sub_state_name" in self:
		sub_text = self.sub_state_name
	_player._states.sub_state_label.text = sub_text
#	_player._states.super_state_label.visible = false
#	_player._states.sub_state_label.visible = false
	enter(_player)

# Called when the node enters the scene tree for the first time.
func _ready():
	pass

#func go_to_state(_player: KinematicBody2D, state_name: String) -> void:
#	_player._states.current._exit()
#	_player._states.current = _player._states[state_name]
#	_player._states.current._enter(_player)

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
