extends InAirState
class_name TrixState

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)
#	print("trix")
	
#	if trix est fini
#		print('end trix')
#		player._states.current = player._states.on_ground/in_air
#		player._states.current._enter(player)
#		return

	if player.floor_detector.is_colliding():
		print('to staggered')
		player._states.go_to_state(player, "staggered")
#		player._states.current = player._states.staggered
#		player._states.current._enter(player)

func _update(_player: KinematicBody2D) -> void:
	pass

func enter(player: KinematicBody2D) -> void:
#	player.animated_sprite.animation = "spin"
	var animations = ["trick_spin", "trick_boule", "trick_etoile_ninja", "trick_carpe"]
	randomize()
#	player.anim_player.play("trick_spin")
#	player.anim_player.play("trick_boule")
#	player.anim_player.play("trick_etoile_ninja")
#	player.anim_player.play("trick_carpe")

	player.anim_player.play(animations[randi() % animations.size()])
#	print(animations[randi() % animations.size()])

#	lancer le trix
	print('entering trix')

# Called when the node enters the scene tree for the first time.
func _ready():
	sub_state_name = "TRIXING"

#func exit(_player: KinematicBody2D) -> void:
#	pass
#	player.AnimatedSprite.rotation_degree = 0
