extends InAirState
class_name HookingInAirState
# =============================================================================
#  Grappin EN L'AIR
# -----------------------------------------------------------------------------
#  [MIGRATION GODOT 4.7] KinematicBody2D -> CharacterBody2D, ._f() -> super._f(),
#  Vector2.tangent() -> orthogonal() (même résultat).
#
#  [GRAPPIN STABILISÉ] — les 2 modes de traction d'origine sont CONSERVÉS :
#    * "pull_original" : traction quand le crochet est SOUS le joueur
#    * "swing"         : balancier + rappel quand le crochet est AU-DESSUS
#  Corrections apportées :
#   1. Direction de traction calculée en coordonnées GLOBALES.
#      Avant : to_local(tip) dans le repère de ce nœud, qui TOURNE avec le
#      pingouin (rotation en l'air / alignement au sol). Pingouin penché de
#      90° => traction envoyée sur le côté. C'était la principale cause des
#      comportements bizarres.
#   2. Hystérésis entre les 2 modes : avant, le mode changeait à CHAQUE frame
#      dès que le pingouin passait à la hauteur du crochet (tremblements).
#      Maintenant il faut dépasser d'au moins MODE_SWITCH_MARGIN pixels.
#   3. Le swing ne peut plus produire de NaN (acos d'une vitesse nulle).
#   4. pull_factor revient à 1 dès qu'on relâche "pull" (avant il restait à 2).
#   5. Comparaison "vitesse faible" corrigée : `Vector2 < Vector2` compare
#      d'abord x puis y (ordre lexicographique), pas les deux composantes.
#   6. Sorties d'état propres (return après changement d'état) et sortie
#      automatique si le grappin s'est décroché tout seul.
# =============================================================================

const CHAIN_PULL = 25
## [GRAPPIN 1.58] longueur de corde en dessous de laquelle, sans tirer, Pinpouin
## n'est plus retenu contre la prise : il retombe à cette distance du crochet
## (voir swing()). En tirant ({pull}), aucune limite.
const ROPE_MIN_LENGTH := 160.0
var pull_factor = 1
var friction_chain_default = 1.65
var friction = friction_chain_default
var stretch_factor_default = 15000
var stretch_factor = stretch_factor_default

# [GRAPPIN] mode de traction courant + marge d'hystérésis
const MODE_SWITCH_MARGIN = 48.0  # px
var mode_pull := true            # true = pull_original, false = swing
var _was_hooked := false         # [GRAPPIN SANS FREIN 1.53] déjà accroché à l'image d'avant ?
var _just_hooked := false        # [GRAPPIN SANS FREIN 1.53] 1re image où le crochet tient
var _mode_initialised := false   # le mode est choisi au moment où le crochet s'accroche

func _handle_input(player: CharacterBody2D, delta: float) -> void:
	if player.is_on_ground:
		player._states.current = player._states.hooking_on_ground
		return

	super._handle_input(player, delta)
	# [GRAPPIN] l'appel parent a pu changer d'état (atterrissage, etc.) : on s'arrête là
	if player._states.current != self:
		return

	if !Input.is_action_pressed("hook"):
		print('to air')
		player._states.go_to_state(player, "in_air")
		return  # [GRAPPIN] avant : on continuait la physique du grappin après l'avoir lâché

# Hook physics
	if player.chain.hooked:
		# [GRAPPIN SANS FREIN 1.53] vrai seulement à la 1re image accrochée
		_just_hooked = not _was_hooked
		_was_hooked = true
		_update_mode(player)
		if mode_pull:  # grapping vers le bas
			pull_original(player)
		else:  # grapping vers le haut
			swing(player, delta)

	elif player.chain.flying:  # check distance de la chain quand tire dans le vide
		if player.chain.distance >= player.chain.distance_max:
			player.chain.release()
			player._states.go_to_state(player, "in_air")  # [GRAPPIN] on est en l'air : "in_air" (avant "sliding")
	else:
		# [GRAPPIN] le grappin s'est décroché tout seul (trop étiré / accroche invalide)
		player._states.go_to_state(player, "in_air")


# [GRAPPIN] choisit le mode à l'accroche, puis ne change qu'avec une vraie marge
func _update_mode(player: CharacterBody2D) -> void:
	var dy = player.chain.tip.y - player.global_position.y  # > 0 : crochet sous le joueur
	if not _mode_initialised:
		mode_pull = dy > 0
		_mode_initialised = true
	elif mode_pull and dy < -MODE_SWITCH_MARGIN:
		mode_pull = false
	elif not mode_pull and dy > MODE_SWITCH_MARGIN:
		mode_pull = true


func pull_original(player: CharacterBody2D):
	# premier grapin pete mais qui marche bien pour se pull (au sol)
	pull_factor = 2 if Input.is_action_pressed("pull") else 1  # [GRAPPIN] se réinitialise

	# [GRAPPIN] direction globale joueur -> crochet (avant : to_local, repère tourné)
	var direction_chain = (player.chain.tip - player.global_position).normalized() # * CHAIN_PULL
	var normale = -direction_chain.orthogonal()

	if player.chain_velocity.y > 0:
		friction = .75 # 1.65 # 0.55
	else:
		friction = 1.65  # .5 # 1.65 # 0.55

	if sign(player.chain_velocity.x) != sign(player.facing):
		friction = 0.6

	if player._velocity.x < 0:
		normale = -normale  #angle_to(Vector2(sign(player._velocity.x),0))  # avec la normale a droite, a multiplier * direction_player

	var angle_traction = (normale + direction_chain) * CHAIN_PULL
	player.chain_velocity = angle_traction

	player.chain_velocity.x *= friction * pull_factor  # seulement friction sur x suffit a fix chain (?)

	# ON DONNE VITESSE AU JOUEUR
	player._velocity += player.chain_velocity

	# clamp vitesse map reelle en mode hook
	# [GRAPPIN SANS FREIN 1.53] Ce plafond (1000 px/s par axe) est GARDÉ tel
	# quel dans ce mode « traction » (crochet au niveau ou sous le joueur).
	# Essai fait puis abandonné : ne plus brider sous la vitesse d'arrivée.
	# Résultat aux bots : Pinpouin fonçait à 1400 px/s droit dans le bloc de
	# glace accroché (prise à sa hauteur, devant lui), s'y écrasait et restait
	# pendu dessous (grappin double du Sans fin : 7 réussites sur 18 au lieu
	# de 18/19). Le vrai coup de frein mesuré (1525 -> 826 px/s) venait du
	# balancier (swing, plus bas) : c'est là qu'il est corrigé.
	player._velocity.x = clamp(player._velocity.x, -player.MAX_SPEED_HOOKED.x, player.MAX_SPEED_HOOKED.x)
	player._velocity.y = clamp(player._velocity.y, -player.MAX_SPEED_HOOKED.y, player.MAX_SPEED_HOOKED.y)


func swing(player: CharacterBody2D, delta):
	var radius = player.global_position - player.chain.tip # points away from center
	# [GRAPPIN] garde-fou : rayon nul => direction indéfinie
	if radius.length() < 1.0:
		return
	var radius_dir = radius.normalized()

	# [GRAPPIN] composante radiale de la vitesse : v·r̂.
	# Identique à l'ancien `cos(acos(r·v / (|r||v|))) * |v|` mais sans division
	# par |v| (qui donnait NaN quand la vitesse était nulle).
	var rad_vel = player._velocity.dot(radius_dir)

	# vitesse angulaire
	# [GRAPPIN SANS FREIN 1.53, EN OPTION] (Player.hook_keep_speed, panneau F2,
	# COUPÉ par défaut : le comportement d'origine reste celui du jeu tant que
	# l'équipe ne l'a pas essayé en jouant. Voir section 63 de la doc.)
	# Ce calcul supprime, à chaque image, la vitesse
	# dans l'axe de la corde (balancier « rigide », comportement d'origine,
	# gardé tel quel ensuite). Problème : à l'image où le crochet ACCROCHE,
	# Pinpouin fonce souvent VERS la prise (prise devant lui) ; toute cette
	# vitesse était effacée d'un coup : un tiers de la vitesse perdue en une
	# image (mesuré aux bots : 1525 -> 826 px/s en vitesse horizontale,
	# section 58 de la doc de migration).
	# Maintenant, à cette seule image-là, la vitesse est RÉORIENTÉE le long de
	# la corde (direction du balancier) au lieu d'être effacée, en gardant sa
	# valeur quand on arrive de biais (voir le détail juste en dessous).
	# On ne le fait PAS aux images suivantes : la petite traction élastique
	# vers le crochet (stretch, plus bas) redonne de la vitesse vers
	# l'intérieur à chaque image ; la réorienter à chaque fois créerait de la
	# vitesse de nulle part. (Une 1re version « corde molle » laissait cette
	# traction s'accumuler et aspirait Pinpouin vers la prise : abandonnée.)
	# Réorientation PROGRESSIVE, selon l'angle d'arrivée (part de la vitesse
	# déjà le long du balancier, « tangentielle ») :
	#   - arrivée de biais (prise devant et au-dessus, le cas mesuré) : part
	#     tangentielle >= 70 % -> toute la vitesse est gardée ;
	#   - Pinpouin fonce DROIT sur la prise (part tangentielle <= 30 %) :
	#     comportement d'origine (vitesse dans l'axe effacée). Sans cette
	#     limite, toute la vitesse partait à angle droit : vu aux bots, prise
	#     à la même hauteur droit devant -> Pinpouin envoyé à la verticale à
	#     1450 px/s ;
	#   - entre les deux : mélange progressif.
	# [GRAPPIN 1.58] CORDE TROP COURTE = on ne reste plus « collé » à la prise.
	# Retour de l'équipe (vidéo 1.57, atelier BALANCIER) : accroché au bloc de
	# glace, la petite traction élastique (stretch, plus bas) raccourcit la
	# corde à chaque balancement ; Pinpouin finissait à ~70 px du crochet,
	# plaqué contre le flanc du bloc. Là, ce calcul « corde rigide » effaçait
	# aussi la GRAVITÉ (qui tire dans l'axe de la corde) : il flottait immobile
	# sous le bloc, sans pouvoir se balancer (mesuré : 13 px/s pendant 5 s).
	# Maintenant, sous ROPE_MIN_LENGTH et sans tirer ({pull}), on n'efface plus
	# la vitesse qui l'ÉLOIGNE du crochet : il retombe au bout d'une corde de
	# ROPE_MIN_LENGTH, d'où il peut de nouveau se balancer. En tirant, rien ne
	# change (falaises, cheminée : on doit pouvoir se hisser tout près de la
	# prise).
	var rope_too_short: bool = radius.length() < ROPE_MIN_LENGTH and not Input.is_action_pressed("pull")
	if rope_too_short and rad_vel > 0.0:
		pass   # il s'éloigne du crochet : on le laisse retomber (pas de stretch non plus)
	elif _just_hooked and rad_vel < 0.0 and player.hook_keep_speed >= 0.5:
		var speed_before: float = player._velocity.length()
		var tangential: Vector2 = player._velocity - radius_dir * rad_vel
		var t_len: float = tangential.length()
		if t_len > 1.0 and speed_before > 1.0:
			var keep: float = clampf((t_len / speed_before - 0.3) / 0.4, 0.0, 1.0)
			player._velocity = tangential / t_len * lerpf(t_len, speed_before, keep)
		else:
			player._velocity = tangential
	else:
		player._velocity += radius_dir * -rad_vel
	# [GRAPPIN 1.58] corde trop courte (et on ne tire pas) : pas de traction
	# élastique vers le crochet, sinon elle le replaquerait contre la prise.
	if rope_too_short:
		return
	# mode corde fixe (avec encore un peu de gravite)
	if player.global_position.distance_to(player.chain.tip) > player.chain.max_length and player.chain_fixed:
		return

	if player.chain.distance < 120:  # pour eviter collision forcee entre joueur et grapin
		# on ajoute pas la vitesse lineaire pour le stretch
		return

	# si joueur a une vitesse faible et est dans une petite angle sous le grapin
	# [GRAPPIN] comparaison composante par composante (cf. en-tête, point 5)
	# [FALAISE 1.55] SAUF si le joueur TIRE ({pull}) : pendu presque à la
	# verticale sous la prise et presque immobile (contre un mur, par
	# exemple), cette sortie anticipée empêchait toute traction. Vu avec le
	# nouvel atelier « Falaise » du tuto : grappin accroché, bouton « tirer »
	# enfoncé… et Pinpouin restait pendu sans monter. Sans « tirer », rien ne
	# change (le pingouin pend tranquillement, comme avant).
	if abs(radius_dir.x) < .35 and abs(player._velocity.x) < player.MIN_SPEED_HOOKED.x \
			and abs(player._velocity.y) < player.MIN_SPEED_HOOKED.y \
			and not Input.is_action_pressed("pull"):
		return

	elif sign((player.chain.tip.x - player.global_position.x)) == sign(player.facing):
#		print("grapin a l'avant du joueur")
		stretch_factor = stretch_factor_default * .5
	else:
#		print("grapin dans le dos du joueur")
		stretch_factor = stretch_factor_default * .5

	if Input.is_action_pressed("pull"):
		stretch_factor = stretch_factor * 3

	# vitesse lineaire pour faire le stretch
	player._velocity += (player.chain.tip - player.global_position).normalized() * stretch_factor * delta

func exit(player: CharacterBody2D) -> void:
	# [BRUITAGES 1.34] on lâche une corde accrochée (pas un lancer dans le vide)
	if player.chain.hooked:
		Sfx.play("grappin_lacher", -4.0)
	player.chain.release()

func enter(player: CharacterBody2D, _previous_state: PlayerState) -> void:
	pull_factor = 1  # par default
	Sfx.play("grappin_lancer", -2.0)   # [BRUITAGES 1.34]
	_mode_initialised = false  # [GRAPPIN] le mode sera choisi à l'accroche
	_was_hooked = false        # [GRAPPIN SANS FREIN 1.53] nouvelle accroche à venir
	_just_hooked = false
	player.chain_velocity = Vector2.ZERO

	var angle_aimed = player._get_aim_direction()
	if angle_aimed == Vector2.ZERO:  # valeur par default
		angle_aimed = Vector2(500*player.facing,-500)
	player.chain.shoot(angle_aimed)

	player.animated_sprite.animation = "hooking"

func _ready():
	sub_state_name = "HOOKING"
	# [TEST ENFANT 1.22] MIGRATION GODOT 4 : en Godot 3, le _ready() de la
	# classe parente (InAirState) était appelé AUTOMATIQUEMENT ; en Godot 4 il
	# faut l'appeler soi-même. Sans ça, `coyote_timer` restait vide dans cet
	# état : appuyer sur SAUT ici provoquait une erreur de script qui
	# interrompait la lecture des commandes (pump en l'air ignoré, etc.).
	# Trouvé par le bot « enfant » qui tape sur SAUT n'importe quand.
	super._ready()
