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
	var v: Vector2 = player._velocity
	var speed := v.length()
	if speed < 1.0 or speed >= player.pump_max_speed:
		return
	var dir := v / speed
	# composante de la direction vers le bas : > 0 en descente, < 0 en montée
	var slope := clampf(dir.y, -1.0, 1.0)
	var accel: float = player.pump_accel
	if slope > 0.0:
		accel += player.gravity * slope * player.pump_slope_bonus
	elif slope < 0.0:
		accel *= player.pump_uphill_factor
	var new_speed := minf(speed + accel * delta, player.pump_max_speed)
	player._velocity = dir * new_speed

func enter(player: CharacterBody2D, _previous_state: PlayerState) -> void:
	player.anim_player.play("pumping")
	# [PHYSIQUE 1.10] petite impulsion à chaque nouvel appui (sensation de
	# boost), seulement en dessous de la vitesse max du pump
	var speed: float = player._velocity.length()
	if speed > 1.0 and speed < player.pump_max_speed:
		player._velocity *= minf(speed + player.pump_impulse, player.pump_max_speed) / speed

func _ready():
	sub_state_name = "PUMPING"

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
