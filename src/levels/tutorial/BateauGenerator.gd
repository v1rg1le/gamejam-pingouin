extends Node2D
# =============================================================================
#  BateauGenerator.gd — [MAP BATEAU] niveau d'apprentissage, simple et SANS TROU
# -----------------------------------------------------------------------------
#  Réutilise les briques existantes (sol.tscn, FinishGate.tscn) mais, à la
#  différence de GroundGenerator.gd :
#   - pas de tremplin ni de trou : UNE seule longue piste continue ;
#   - légère descente régulière (coeff_pente) : on garde de la vitesse sans rien faire ;
#   - relief doux (grande période, faible hauteur) et sol épais (impossible de passer à travers) ;
#   - un mur invisible au départ : impossible de tomber en reculant ;
#   - un PLAFOND au milieu pour s'entraîner au grappin sans aucun risque ;
#   - des panneaux (TutorialSign) qui expliquent chaque commande avec les
#     touches du périphérique utilisé (clavier, manette ou tactile) ;
#   - une ligne d'arrivée posée sur la piste, bien visible.
#   - [TUTO 1.7] deux TREMPLINS d'entraînement après le plafond : les sauts de
#     la piste sont trop courts (< 1 s) pour une vrille ou un combo ; un
#     tremplin donne ~1,2 à 1,6 s de vol. Le sol continue dessous : aucun
#     risque de chute.
#  Tous les réglages sont exportés pour pouvoir ajuster le niveau dans l'éditeur.
# =============================================================================

const UNIT_SIZE = 64
var sol_res = preload("res://src/levels/GroundGenerator/sol.tscn")
var finish_gate_res = preload("res://src/levels/FinishGate.tscn")
var sign_script = preload("res://src/levels/tutorial/TutorialSign.gd")

## Longueur de la piste (px).
@export var track_length: int = UNIT_SIZE * 400
## Pente moyenne (0.06 ≈ 3,4° de descente) : assez pour avancer seul.
@export var coeff_pente: float = 0.06
## Relief doux : bosses espacées (période) et basses (hauteur).
@export var noise_period: int = 1300
@export var bump_height: int = 110
## Épaisseur du sol (px) : bien épais, on ne peut pas le traverser.
@export var ground_thickness: int = 240
## Graine choisie par calcul parmi 400 : le départ ne fait que descendre et la
## pire montée de toute la piste ne dépasse pas ~3°.
@export var world_seed: String = "BATEAU397"
## Plafond d'entraînement au grappin : début, longueur et hauteur au-dessus de la piste.
@export var roof_start: int = UNIT_SIZE * 160
@export var roof_length: int = UNIT_SIZE * 120
@export var roof_height: int = 450  # visible à l'écran, mais hors de portée d'un simple saut
## [TUTO 1.7] Tremplins : positions (début de la rampe), hauteur et angle du bord.
@export var ramp_positions: Array[int] = [18900, 20900]
@export var ramp_height: float = 170.0
@export var ramp_lip_angle_deg: float = 35.0
## Position de la ligne d'arrivée (px depuis le début de la piste).
@export var finish_x: int = UNIT_SIZE * 380

# Panneaux : position x sur la piste + texte ({action} = touche réelle).
# [SCORE 1.5] 3 panneaux expliquent le score (départ, vrilles, combos) et le
# panneau des figures annonce leurs points.
var signs = [
	[700,   "Bienvenue sur la banquise !\nAvancer : {move_right}    Reculer : {move_left}\nPrends de l'élan, la piste descend jusqu'à l'arrivée."],
	[1900,  "SCORE = points de VITESSE + points de FIGURES\n3000 pts au temps de référence, +100 par seconde gagnée.\nUne figure réussie = 100 pts = 1 seconde !"],
	[3200,  "Sauter : {jump}"],
	[6000,  "PUMP : {pump} dans les DESCENTES\npour prendre de la vitesse.\nRelâche dans les montées."],
	[8600,  "En l'air, tourne avec {rotate_trigo} / {rotate_horaire}\npour retomber bien à plat.\nDans les grands sauts : un tour complet = VRILLE, +150 pts !"],
	[10800, "GRAPPIN : vise le plafond et maintiens {hook}\npour t'accrocher. Lâche pour te décrocher."],
	[13800, "Accroché : maintiens aussi {pull}\npour te hisser vers le plafond."],
	[17600, "FIGURE en l'air : {trix}  =  +100 pts\nTermine-la avant de toucher le sol,\nsinon tu es sonné et tu perds les points du saut !"],
	[18300, "TREMPLINS droit devant ! Prends de l'élan avec {pump}\net saute au bord ({jump}) pour un GRAND SAUT.\nCOMBO : plusieurs figures ou vrilles dans le même saut\n= points multipliés (×2, ×3… jusqu'à ×5), si tu atterris bien !"],
	[22300, "Dernière ligne droite :\nfonce sous l'arche !"],
]

var _track  # le sol principal (pour connaître la hauteur de la piste)


func _ready() -> void:
	# 1. La piste principale (un seul sol continu)
	_track = _add_sol(Vector2.ZERO, track_length, bump_height, ground_thickness, world_seed)

	# 2. Plafond d'entraînement au grappin, parallèle à la piste
	var roof_pos := Vector2(roof_start, surface_y(roof_start) - roof_height)
	_add_sol(roof_pos, roof_length, int(bump_height * 0.5), 60, world_seed + "_PLAFOND")

	# 3. Mur invisible au départ (on ne peut pas tomber en reculant)
	_add_wall(Vector2(-40, surface_y(0) - 1500), Vector2(80, 3000))

	# 4. Panneaux d'explication
	for s in signs:
		var sign_node := Node2D.new()
		sign_node.set_script(sign_script)
		sign_node.sign_text = s[1]
		sign_node.position = Vector2(s[0], surface_y(s[0]) - 170)
		add_child(sign_node)

	# 4 bis. [TUTO 1.7] Tremplins d'entraînement (vrilles, combos)
	for rx in ramp_positions:
		_add_ramp(rx)

	# 5. Ligne d'arrivée posée sur la piste
	var gate = finish_gate_res.instantiate()
	gate.position = Vector2(finish_x, surface_y(finish_x))
	add_child(gate)

	# 6. Point de départ du joueur (LevelRandom.gd l'ajoute après ce _ready)
	get_parent()._set_spawn_position(Vector2(250, surface_y(250) - 80))


# Hauteur (y) de la surface de la piste à l'abscisse x — même formule que sol.gd.
func surface_y(x: float) -> float:
	return _track.position.y + _track.map_height * _track._noise(x) + _track.coeff_pente * x


func _add_sol(pos: Vector2, width: int, height: int, thickness: int, seed_text: String):
	var sol = sol_res.instantiate()
	sol.set_collision_layer(2)   # calque "ground", comme dans GroundGenerator.gd
	sol.coeff_pente = coeff_pente
	sol.noise_octaves = 1
	sol.noise_period = noise_period
	sol.noise_persistence = 0.2
	sol.noise_lacunarity = 3
	sol.world_seed = seed_text
	sol.is_boost = false
	sol.is_igloo = true
	sol.igloo_treshold = 0.01
	sol.is_final_map = false
	sol.map_width = width
	sol.map_height = height
	sol.h = thickness
	sol.position = pos
	add_child(sol)
	return sol


# [TUTO 1.7] Tremplin posé sur la piste : profil en arc de parabole (pente 0 au
# pied, ramp_lip_angle_deg au bord) pour ne pas « casser » la vitesse à
# l'entrée ; bord vertical à l'arrivée. Même rendu que les sols (corps bleu
# glace + bordure texturée tile_ice_up_long1, aucun nouvel asset). Collision
# en SEGMENTS (contour seul), comme les sols générés : pas de collision
# « fantôme » sur les arêtes internes (cf. bug vitesse -> 0).
func _add_ramp(x0: float) -> void:
	var slope := tan(deg_to_rad(ramp_lip_angle_deg))
	var w := 2.0 * ramp_height / slope   # longueur pour atteindre l'angle voulu au bord
	var top := PackedVector2Array()
	var steps := 16
	for i in steps + 1:
		var t := float(i) / steps
		var x := x0 + t * w
		top.append(Vector2(x, surface_y(x) - ramp_height * t * t))
	# contour fermé : dessus de la rampe, bord vertical, puis retour sous la piste
	var poly := PackedVector2Array(top)
	poly.append(Vector2(x0 + w, surface_y(x0 + w) + 60))
	poly.append(Vector2(x0, surface_y(x0) + 60))
	var body := StaticBody2D.new()
	body.collision_layer = 2   # calque "ground" : le grappin s'y accroche aussi
	var col := CollisionPolygon2D.new()
	col.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
	col.polygon = poly
	body.add_child(col)
	var fill := Polygon2D.new()
	fill.color = Color(0.694118, 0.862745, 0.956863, 1)   # même bleu que sol.tscn
	fill.polygon = poly
	body.add_child(fill)
	var edge := Line2D.new()
	edge.texture = preload("res://sprites/levels/tiles/tile_ice_up_long1.png")
	edge.texture_mode = Line2D.LINE_TEXTURE_TILE
	edge.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	edge.width = 64.0
	edge.position = Vector2(0, 28)   # comme la bordure de sol.tscn
	edge.points = top
	body.add_child(edge)
	add_child(body)


func _add_wall(pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = size * 0.5
	body.position = pos
	body.add_child(shape)
	add_child(body)
