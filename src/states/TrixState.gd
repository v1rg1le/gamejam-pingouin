extends InAirState
class_name TrixState

func _handle_input(player: CharacterBody2D, delta: float) -> void:
	super._handle_input(player, delta)
	# [MIGRATION GODOT 4.7 / FIX] si l'état parent a déjà changé d'état dans cette
	# frame (saut, grappin, atterrissage...), on ne superpose pas une 2e transition.
	if player._states.current != self:
		return
#	print("trix")
	
#	if trix est fini
#		print('end trix')
#		player._states.current = player._states.on_ground/in_air
#		player._states.current._enter(player)
#		return

	if player.is_on_ground:
		print('to staggered')
		player._states.go_to_state(player, "staggered")
#		player._states.current = player._states.staggered
#		player._states.current._enter(player)

func _update(_player: CharacterBody2D) -> void:
	pass

func enter(player: CharacterBody2D, _previous_state: PlayerState) -> void:
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
	# [TEST ENFANT 1.22] MIGRATION GODOT 4 : en Godot 3, le _ready() de la
	# classe parente (InAirState) était appelé AUTOMATIQUEMENT ; en Godot 4 il
	# faut l'appeler soi-même. Sans ça, `coyote_timer` restait vide dans cet
	# état : appuyer sur SAUT ici provoquait une erreur de script qui
	# interrompait la lecture des commandes (pump en l'air ignoré, etc.).
	# Trouvé par le bot « enfant » qui tape sur SAUT n'importe quand.
	super._ready()

func exit(player: CharacterBody2D) -> void:
	pass
	player.animated_sprite.rotation_degrees = 0
