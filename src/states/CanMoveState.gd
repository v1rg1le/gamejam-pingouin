extends PlayerState
class_name CanMoveState

#var super_state_name = "CAN MOVE"

func _handle_input(player: KinematicBody2D, delta: float) -> void:
	._handle_input(player, delta)
	var input_speed = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	player.direction.x = input_speed

	var out_velocity = player._velocity

	out_velocity.x = lerp(out_velocity.x, player.max_speed.x * input_speed, _get_h_weight(player, input_speed)) #_get_h_weight(player, input_speed))
	player._velocity = out_velocity

func _get_h_weight(player: KinematicBody2D, input_speed) -> float:
#	if player.is_on_floor():
#		return 20.0
#	elif is_wall_sliding:
#		return 0.1
#	else:
#		return 0.2
#	else:
	if input_speed == 0:  # si pas de direction on sarrete vite
		return 0.01
	# si le joueur appuie dans le meme sens que dans le mouvement
	# et que la vitesse du perso > vitesse maximale
	# les frottements sont plus faibles:
	# permet d'aller plus loin: bonne impression pour un plateformer
	elif input_speed == sign(player.direction.x) and abs(player.direction.x) > player.max_speed.x:  # max_jump_velocity:  # move_speed:
		return 0.1
	else:
		return 0.2
	# return 0.3 if is_on_floor() else 0.1

# Called when the node enters the scene tree for the first time.
func _ready():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
