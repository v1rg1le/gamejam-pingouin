extends OnGroundState
class_name HookingOnGroundState
# =============================================================================
#  Grappin AU SOL
#  [MIGRATION GODOT 4.7] KinematicBody2D -> CharacterBody2D, ._f() -> super._f()
#  [GRAPPIN STABILISÉ] mêmes corrections que HookingInAirState :
#   - direction de traction en coordonnées GLOBALES (plus de repère tourné),
#   - pull_factor revient à 1 quand on relâche "pull",
#   - sorties d'état propres + sortie si le grappin s'est décroché seul.
#  La formule de traction au sol (normale + direction, frictions) est conservée.
# =============================================================================

const CHAIN_PULL = 15
var pull_factor = 1

func _handle_input(player: CharacterBody2D, delta: float) -> void:
	if !player.is_on_ground:
		player._states.current = player._states.hooking_in_air
		return

	super._handle_input(player, delta)
	# [GRAPPIN] l'appel parent a pu changer d'état (saut, etc.) : on s'arrête là
	if player._states.current != self:
		return

	if !Input.is_action_pressed("hook"):
		print('to ground')
		player._states.go_to_state(player, "on_ground")
		return  # [GRAPPIN]

	# Hook physics
	if player.chain.hooked:
		pull_factor = 2 if Input.is_action_pressed("pull") else 1  # [GRAPPIN] se réinitialise

		# [GRAPPIN] direction globale (avant : to_local dans un repère qui tourne avec le pingouin)
		var direction_chain = (player.chain.tip - player.global_position).normalized() # * CHAIN_PULL
		var friction = 1.65
		var normale = -direction_chain.orthogonal()

		if player.chain_velocity.y > 0:
			friction = 0.55
		else:
			if player._velocity.x < 0:
				normale = -normale  #angle_to(Vector2(sign(player._velocity.x),0))  # avec la normale a droite, a multiplier * direction_player

		var angle_traction = (normale + direction_chain) * CHAIN_PULL
		player.chain_velocity = angle_traction

		player.chain_velocity *= friction * pull_factor

		if sign(player.chain_velocity.x) != sign(player.direction.x):
			player.chain_velocity.x *= 0.6
		player._velocity += player.chain_velocity

	elif player.chain.flying:  # check distance de la chain quand tire dans le vide
		if player.chain.distance >= player.chain.distance_max:
			player.chain.release()
			player._states.go_to_state(player, "sliding")
	else:
		# [GRAPPIN] décroché tout seul : retour au sol normal
		player._states.go_to_state(player, "on_ground")

func exit(player: CharacterBody2D) -> void:
	player.chain.release()

func enter(player: CharacterBody2D, _previous_state: PlayerState) -> void:
	pull_factor = 1  # par default
	player.chain_velocity = Vector2.ZERO
	# [GRAPPIN] si on décolle pendant ce grappin, l'état "en l'air" choisira son
	# mode de traction (pull/swing) au moment de l'accroche
	player._states.hooking_in_air._mode_initialised = false
	var angle_aimed = player._get_aim_direction()
#	valeur par default
	if angle_aimed == Vector2.ZERO:
		angle_aimed = Vector2(500*player.facing,-500)

	player.chain.shoot(angle_aimed) #(get_global_mouse_position() - global_position).normalized())  #event.position - get_viewport().size * 0.5)

	player.animated_sprite.animation = "hooking"

func _ready():
	sub_state_name = "HOOKING"
