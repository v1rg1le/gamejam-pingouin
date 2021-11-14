extends InAirState
class_name TrixState

#var sub_state_name = "TRIXING"
#var super_state_name = "IN AIR"

func _handle_input(player: KinematicBody2D, _delta: float) -> void:
#	._handle_input(player, delta)
#	print("trix")
	
#	if trix est fini
#		print('end trix')
#		player._states.current = player._states.on_ground/in_air
#		player._states.current._enter(player)
#		return

	if player.floor_detector.is_colliding():
		print('to staggered')
		player._states.current = player._states.staggered
		player._states.current._enter(player)

func _update(_player: KinematicBody2D) -> void:
	pass

func enter(player: KinematicBody2D) -> void:
	player.animated_sprite.animation = "trix"
#	lancer le trix
	print('entering trix')

# Called when the node enters the scene tree for the first time.
func _ready():
	sub_state_name = "TRIXING"

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
