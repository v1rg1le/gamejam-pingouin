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

	# [1.66] retour de l'équipe : en pleine figure contre un PLAFOND, les
	# capteurs (qui tournent avec Pinpouin, à l'envers) touchaient le plafond :
	# le jeu croyait à un atterrissage raté, lançait la roulade et laissait
	# Pinpouin « posé » en l'air (comme sur un mur blanc invisible). On ne
	# compte plus que les vrais sols ; contre un plafond, la figure continue
	# et Pinpouin retombe normalement.
	if player.is_on_ground and player.landing.on_real_floor():
		# [ROULADE 1.50] Demande de l'équipe : toucher le sol en pleine figure
		# fait la même chute que sur le dos (neige + roulade 0,5 s + étourdi
		# 1 s, CrashState), au lieu de rester sonné 2 s arrêté net.
		# Mode enfant : pas de roulade (comme la chute sur le dos), juste
		# étourdi 1 s (StaggeredState.staggered_time, 2 -> 1 s en 1.50).
		if Settings.kid_mode:
			print('to staggered')
			player._states.go_to_state(player, "staggered")
		else:
			print('figure ratée : roulade')
			player.landing.snow_burst(player.global_position, player._velocity)
			player._states.go_to_state(player, "crashing")
#		player._states.current = player._states.staggered
#		player._states.current._enter(player)

func _update(_player: CharacterBody2D) -> void:
	pass

func enter(player: CharacterBody2D, _previous_state: PlayerState) -> void:
	Sfx.play("figure_whoosh")   # [BRUITAGES 1.34] figure lancée
#	player.animated_sprite.animation = "spin"
	var animations = ["trick_spin", "trick_boule", "trick_etoile_ninja", "trick_carpe"]
	randomize()
#	player.anim_player.play("trick_spin")
#	player.anim_player.play("trick_boule")
#	player.anim_player.play("trick_etoile_ninja")
#	player.anim_player.play("trick_carpe")

	# [DEV 1.72] Onglet « Développeur » des options : figure fixée (pour
	# tester une figure précise) ; -1 = au hasard, comme avant
	if Settings.fixed_trick >= 0 and Settings.fixed_trick < Settings.TRICKS.size():
		player.anim_player.play(Settings.TRICKS[Settings.fixed_trick][0])
	else:
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
