extends PlayerState
class_name CanMoveState

#var super_state_name = "CAN MOVE"

#export var running_speed = 500

func _handle_input(player: CharacterBody2D, delta: float) -> void:
	super._handle_input(player, delta)
	
	var input_speed = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	if input_speed != 0:
#		player.direction.x = input_speed
#		player.running_speed * input_speed
		# [PHYSIQUE 1.10] avant : la vitesse était TOUJOURS ramenée vers
		# running_speed × input, donc maintenir « avancer » à 1500 px/s freinait
		# jusqu'à 500 px/s (mesuré : 1500 -> 700 en 3 s). Maintenant :
		#  - si on va déjà plus vite que running_speed DANS LE SENS demandé, on
		#    ne touche à rien (avancer ne freine jamais) ;
		#  - sinon (plus lent, ou sens opposé = freinage) : comme avant.
		var target: float = player.running_speed * input_speed
		var same_direction: bool = signf(player._velocity.x) == signf(input_speed)
		if not (same_direction and absf(player._velocity.x) >= absf(target)):
			player._velocity.x = lerp(player._velocity.x, target, 0.01)  #_get_h_weight(player, input_speed))

#	var input_speed = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
#	player.direction.x = input_speed
#	player._velocity.x = lerp(player._velocity.x, player.max_speed.x * input_speed, _get_h_weight(player, input_speed))
#	player._velocity.x = lerp(player._velocity.x, 0, .01)

#	player._velocity.x

func _get_h_weight(player: CharacterBody2D, input_speed) -> float:
#	if player._state.super_state_name == "ON_GROUND":
#	return 20.0
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
