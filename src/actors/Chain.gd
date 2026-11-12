"""
This script controls the chain.
"""
extends Node2D
# =============================================================================
#  [MIGRATION GODOT 4.7]
#   - onready -> @onready, deg2rad -> deg_to_rad, KinematicBody2D -> CharacterBody2D
#   - ATTENTION : Vector2.angle_to_point() a changé de SENS en Godot 4
#     (G3 : angle de (a - b) ; G4 : angle de (b - a)). On calcule désormais
#     l'angle explicitement avec (a - b).angle() pour garder le même rendu.
#
#  [GRAPPIN STABILISÉ]
#   - Le crochet (Tip) ne fait plus partie du calque de collision 1 : il était
#     détecté comme un "corps" par les Area2D (ligne d'arrivée déclenchée par
#     le crochet, etc.). Il garde son masque (sol) pour s'accrocher.
#   - La distance est mesurée depuis le joueur (inchangé) mais le décrochage
#     "trop étiré" passe par un signal pour que l'état du joueur le sache.
#   - Le crochet ne peut plus s'accrocher DANS le joueur ni à une distance
#     ridiculement courte (cause de tractions erratiques).
# =============================================================================

@onready var links = $Links		# A slightly easier reference to the links
var direction := Vector2(1,0)	# The direction in which the chain was shot
var tip := Vector2(0,0)			# The global position the tip should be in
								# We use an extra var for this, because the chain is
								# connected to the player and thus all .position
								# properties would get messed with when the player
								# moves.
@onready var tip_collision_shape = $Tip/CollisionShape2D

const distance_max = 1200  # distance max quand tirer dans le vide
const distance_max_stretch = 2000 # distance max du grapin une fois accroche
const SPEED = 50	# The speed with which the chain moves
const max_length = 300  # utiliser pour le mode corde fixe
const distance_min_hook = 40  # [GRAPPIN] en dessous, l'accroche est ignorée (crochet collé au joueur)

var distance = 0  # pour checker distance max
var flying = false	# Whether the chain is moving through the air
var hooked = false	# Whether the chain has connected to a wall
var current_length = 0


signal chain_hooked(current_length)
signal chain_released  # [GRAPPIN] émis quand le grappin lâche tout seul (trop étiré)

func _ready() -> void:
	# [GRAPPIN] le crochet n'est "visible" pour personne (calque 0) mais
	# continue de détecter le sol grâce à son masque (calque 2 = ground).
	$Tip.collision_layer = 0
	tip_collision_shape.disabled = true

# shoot() shoots the chain in a given direction
func shoot(dir: Vector2) -> void:
	# [GRAPPIN] direction nulle ou invalide => on ne tire pas n'importe où
	if dir == Vector2.ZERO or is_nan(dir.x) or is_nan(dir.y):
		dir = Vector2(1, -1)
	direction = dir.normalized()	# Normalize the direction and save it
	flying = true					# Keep track of our current scan
	hooked = false
	tip = self.global_position + Vector2(50, 50) * direction  # reset the tip position to the player's position
	# un peu a cote sinon collision shape chain entre en contact avec le joueur
	$Tip.global_position = tip
	tip_collision_shape.set_deferred("disabled", false)  # reactive la collision shape si jamais


# release() the chain
func release() -> void:
	flying = false	# Not flying anymore
	hooked = false	# Not attached anymore
	tip_collision_shape.set_deferred("disabled", true)

# Every graphics frame we update the visuals
func _process(_delta: float) -> void:
	self.visible = flying or hooked	# Only visible if flying or attached to something
	if not self.visible:
		return	# Not visible -> nothing to draw
	var tip_loc = to_local(tip)	# Easier to work in local coordinates
	# We rotate the links (= chain) and the tip to fit on the line between self.position (= origin = player.position) and the tip
	# [MIGRATION GODOT 4.7] G3: position.angle_to_point(tip_loc) == (position - tip_loc).angle()
	var chain_angle = (self.position - tip_loc).angle()
	links.rotation = chain_angle - deg_to_rad(90)
	$Tip.rotation = chain_angle - deg_to_rad(90)
	links.position = tip_loc						# The links are moved to start at the tip
	links.region_rect.size.y = tip_loc.length()		# and get extended for the distance between (0,0) and the tip

# Every physics frame we update the tip position
func _physics_process(_delta: float) -> void:
	$Tip.global_position = tip	# The player might have moved and thus updated the position of the tip -> reset it
	distance = tip.distance_to(get_parent().global_position)

	if flying:
		# `if move_and_collide()` always moves, but returns true if we did collide
		if $Tip.move_and_collide(direction * SPEED):
			var hook_distance = $Tip.global_position.distance_to(get_parent().global_position)
			if hook_distance < distance_min_hook:
				# [GRAPPIN] accroche quasiment sur le joueur : instable, on annule
				release()
				emit_signal("chain_released")
			else:
				hooked = true	# Got something!
				flying = false	# Not flying anymore
				current_length = hook_distance
				distance = hook_distance
				emit_signal("chain_hooked", current_length)
	tip = $Tip.global_position	# set `tip` as starting position for next frame

	if hooked and distance > distance_max_stretch:
		release()
		emit_signal("chain_released")
