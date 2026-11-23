extends OnGroundState
class_name PumpState

func _handle_input(player: CharacterBody2D, delta: float) -> void:
	super._handle_input(player, delta)

	if !Input.is_action_pressed("pump"):
		player._states.go_to_state(player, "on_ground")
	if player._states.current != self:
		return
	# [PHYSIQUE 1.10] Nouveau pump (l'ancien calcul, pour mémoire) :
	#   var coef = 1.4
	#   player._velocity = lerp(player._velocity, player.pump_accel_factor * player._velocity, 0.04)
	#   puis vitesse bornée à max_speed × coef = 980 px/s  <- faisait PERDRE
	#   de la vitesse dès qu'on arrivait plus vite que 980 (après un saut).
	# Maintenant : accélération le long du mouvement, plus forte en descente,
	# jusqu'à pump_max_speed ; au-delà, le pump n'enlève rien.
	# [1.68] plus de limite : le pump est une puissance (gain = P / v), voir
	# Player.pump_power().
	# [PUMP MUR 1.54] Le calcul du pump est maintenant dans
	# Player.apply_pump_accel() (même formule qu'avant, inchangée) : il est
	# partagé avec le grappin au sol (HookingOnGroundState), qui pumpe le
	# long d'un mur quand le crochet tient au-dessus de Pinpouin.
	# Sur un MUR en montée, sans grappin, le pump n'a plus d'effet (voir
	# Player.pump_blocked_on_wall) : on ne remonte plus le half-pipe au pump.
	player.apply_pump_accel(delta)


func enter(player: CharacterBody2D, _previous_state: PlayerState) -> void:
	player.play_ground_anim("pumping")   # [ATTERRISSAGES 1.40] debout ou à plat ventre
	# [PHYSIQUE 1.10] petite impulsion à chaque nouvel appui (sensation de
	# boost), seulement en dessous de la vitesse max du pump
	player.apply_pump_impulse()   # [PUMP MUR 1.54] même impulsion, sauf sur un mur en montée

func _ready():
	sub_state_name = "PUMPING"

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
