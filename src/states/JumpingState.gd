extends InAirState
class_name JumpingState
# [MIGRATION GODOT 4.7] KinematicBody2D -> CharacterBody2D, ._f() -> super._f()

func _handle_input(player: CharacterBody2D, delta: float) -> void:
	super._handle_input(player, delta)
	# [MIGRATION GODOT 4.7 / GRAPPIN] si le parent a déjà changé d'état (atterrissage,
	# grappin...), on ne déclenche pas une 2e transition dans la même frame.
	if player._states.current != self:
		return

#	if player.direction.y == -1:
#		player._velocity.y = player.max_speed.y * player.direction.y * delta
	
	if Input.is_action_just_pressed("hook"):
		print("hoooook")
		player._states.go_to_state(player, "hooking_in_air")

func enter(player: CharacterBody2D, _previous_state: PlayerState) -> void:
	print('enter jumping')
	Sfx.play("saut", -3.0)   # [BRUITAGES 1.34]
#	player.anim_player.play("jumping")
#	player.animated_sprite.animation = "fly"
	player.direction.y = -1.0
#	player.snap = Vector2.ZERO
	# [SAUT MUR 1.58] contre un mur (> 75°) sans grappin accroché au-dessus :
	# le saut ne fait plus grimper. Pinpouin se décolle du mur à l'horizontale
	# (du côté où regarde la paroi) et GARDE sa vitesse verticale : il ne gagne
	# pas de hauteur. Détail et choix de l'équipe : Player.wall_jump_normal().
	var wall_n: Vector2 = player.wall_jump_normal()
	if wall_n != Vector2.ZERO:
		var side: float = signf(wall_n.x) if absf(wall_n.x) > 0.01 else -float(player.facing)
		player._velocity.x = side * player.WALL_JUMP_PUSH
		print("saut contre un mur : repousse (normale %s, au sol %s)" % [wall_n.snapped(Vector2(0.01, 0.01)), player.is_on_ground])
		return
	player._velocity.y = player.max_speed.y * player.direction.y

func _ready():
	sub_state_name = "JUMPING"
	# [TEST ENFANT 1.22] MIGRATION GODOT 4 : en Godot 3, le _ready() de la
	# classe parente (InAirState) était appelé AUTOMATIQUEMENT ; en Godot 4 il
	# faut l'appeler soi-même. Sans ça, `coyote_timer` restait vide dans cet
	# état : appuyer sur SAUT ici provoquait une erreur de script qui
	# interrompait la lecture des commandes (pump en l'air ignoré, etc.).
	# Trouvé par le bot « enfant » qui tape sur SAUT n'importe quand.
	super._ready()
