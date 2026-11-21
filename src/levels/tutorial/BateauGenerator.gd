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
#
#  [TUTO 1.41] Tuto par ATELIERS (demande de l'équipe, 21/11) : la piste est
#  maintenant une suite d'ateliers (PUMP, saut, pattes, nose, chute, figures,
#  combo, grappin, balancier) puis une petite COURSE FINALE chronométrée.
#  Ce fichier ne fait que CONSTRUIRE la piste (sols, tremplins, plafond, trou
#  avec un bloc de glace pour le balancier, panneaux d'entrée des ateliers,
#  ligne d'arrivée). Tout ce qui se passe pendant la partie (consignes du
#  maître, compteur de réussites, boucle, bouton « Passer ») est dans
#  TutorialCoach.gd, créé à la fin de _ready().
#  Nouveautés de la piste :
#   - les positions viennent de la liste `workshop_specs` (longueur de chaque
#     atelier, tremplins et plafond à l'intérieur) : on ajoute / allonge un
#     atelier en changeant UNE ligne, tout le reste se recale ;
#   - la piste n'est plus d'un seul morceau : elle est coupée par des TROUS
#     (`gaps`) — le grand trou du balancier, et un petit trou à sauter dans la
#     course finale. Chaque morceau est un sol (sol.tscn) ; surface_y(x) lit
#     la hauteur du bon morceau.
#  Avant la 1.41 : une seule piste continue avec 10 panneaux de texte, deux
#  tremplins et un plafond (voir l'historique git).
# =============================================================================

const UNIT_SIZE = 64
var sol_res = preload("res://src/levels/GroundGenerator/sol.tscn")
var finish_gate_res = preload("res://src/levels/FinishGate.tscn")
var sign_script = preload("res://src/levels/tutorial/TutorialSign.gd")
var fish_res = preload("res://src/levels/parts/StaticBody2DFish.tscn")   # [TUTO 1.41] prise du balancier

## Longueur de la piste (px). [TUTO 1.41] calculée dans _ready() (ateliers +
## course finale) : la valeur ici n'est plus qu'un minimum.
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
## [TUTO 1.41] début et longueur calculés depuis l'atelier « grappin ».
@export var roof_start: int = UNIT_SIZE * 160
@export var roof_length: int = UNIT_SIZE * 120
@export var roof_height: int = 450  # visible à l'écran, mais hors de portée d'un simple saut
## [TUTO 1.7] Tremplins : positions (début de la rampe), hauteur et angle du bord.
## [TUTO 1.41] positions calculées depuis les ateliers et la course finale.
@export var ramp_positions: Array[int] = [18900, 20900]
@export var ramp_height: float = 170.0
## [TUTO 1.41] 35° -> 28° : lancé à pleine vitesse (≈ 1450 px/s), un
## tremplin à 35° faisait voler ~3700 px et passer par-dessus
## le tremplin suivant. À 28° : ~2 s de vol, assez pour une figure + un nose.
@export var ramp_lip_angle_deg: float = 28.0
## Position de la ligne d'arrivée (px depuis le début de la piste).
## [TUTO 1.41] calculée : fin de la course finale.
@export var finish_x: int = UNIT_SIZE * 380

## [TUTO 1.41] Longueur de l'accueil avant le 1er atelier (px).
@export var intro_length: int = 1800
## [TUTO 1.41] Course finale : longueur (ligne de départ -> arrivée), tremplins
## et petit trou à sauter (positions depuis la ligne de départ). Le trou est
## loin des tremplins : un vol de tremplin (~3000 px) ne doit pas finir dedans.
@export var final_length: int = 17000
@export var final_ramps: Array[int] = [1500, 7600, 12600]
@export var final_gap_at: int = 5300
@export var final_gap_length: int = 520
@export var final_gap_drop: int = 260
## [TUTO 1.41] Grand trou du balancier : longueur et MONTÉE de l'autre bord
## (mêmes valeurs que le trou « GRAPPIN » du Sans fin, réglé aux bots : un
## saut seul retombe avant ; le bloc de glace est au milieu, 600 px plus haut).
@export var swing_gap_length: int = 2400
@export var swing_gap_rise: int = 200

# [TUTO 1.41] Les ateliers, dans l'ordre. Pour chacun :
#   key    : le geste (reconnu par TutorialCoach) ;
#   len    : longueur du tronçon (px) — au bout, on recommence si raté ;
#   need   : réussites demandées (3 pour les bases, 1-2 pour les gestes durs) ;
#   ramps  : tremplins (distance depuis le début de l'atelier) ;
#   roof   : plafond [début, longueur] ;  hole : trou [début] (balancier) ;
#   title  : nom affiché par le maître ; short : nom court du compteur ;
#   text   : LA consigne (une ou deux phrases, {action} = vraie touche ; la
#            bulle passe à la ligne toute seule) ;
#   hints  : indices de plus en plus précis, un par échec ;
#   done_text : (option) phrase du maître une fois l'atelier réussi.
var workshop_specs = [
	{"key": "pump", "len": 6500, "need": 3, "title": "PUMP", "short": "PUMP",
		"text": "Dans les DESCENTES, appuie sur {pump} pour prendre de la vitesse. Relâche dans les montées.",
		"hints": ["Appuie sur {pump} quand ça descend, relâche quand ça remonte.",
			"Garde {pump} un petit moment dans la pente, puis relâche.",
			"Regarde le sol : {pump} seulement quand Pinpouin glisse vers le bas."]},
	{"key": "jump", "len": 7000, "need": 3, "title": "SAUT", "short": "SAUT",
		"text": "Saute avec {jump}, et retombe sans chuter.",
		"hints": ["Appuie sur {jump} quand Pinpouin touche le sol.",
			"Un saut, on atterrit… et on recommence !"]},
	{"key": "feet", "len": 11500, "need": 3, "ramps": [800, 4400, 8000], "title": "SUR LES PATTES", "short": "PATTES",
		"text": "Saute au bout des tremplins ({jump}). En l'air, relève le bec avec {rotate_trigo} : Pinpouin retombe sur ses PATTES et glisse debout. À plat, il glisse sur le ventre.",
		"hints": ["Relève le bec avec {rotate_trigo} avant de toucher le sol : les pattes vers la pente.",
			"Pas trop quand même : tête en bas, c'est la chute !",
			"Prends de l'élan avec {pump} avant le tremplin, puis saute au bord."]},
	{"key": "nose", "len": 8000, "need": 2, "ramps": [800, 4400], "title": "NOSE", "short": "NOSE",
		"text": "Comme en skate : retombe le BEC EN AVANT ! Penche Pinpouin avec {rotate_horaire} juste avant le sol. NOSE = points + petit boost.",
		"hints": ["Penche vers l'avant avec {rotate_horaire}, un peu plus que pour les pattes.",
			"Pas trop quand même : sur le dos, c'est la chute !",
			"Commence à pencher dès que Pinpouin redescend."]},
	{"key": "crash", "len": 4400, "need": 1, "ramps": [800], "title": "LA CHUTE", "short": "CHUTE",
		"text": "Sur le dos, ça fait mal ! Essaie UNE fois pour voir : sur le tremplin, tourne longtemps avec {rotate_trigo} et atterris sur le dos.",
		"hints": ["Tourne plus longtemps avec {rotate_trigo} : il faut toucher le sol la tête en bas.",
			"Saute au bord du tremplin ({jump}) pour avoir le temps de tourner."],
		"done_text": "Tu as vu ? Roulade, sonné 1 seconde, et les points du saut\nsont perdus. En course, évite ça !"},
	{"key": "figure", "len": 8000, "need": 2, "ramps": [800, 4400], "title": "FIGURES", "short": "FIGURE",
		"text": "En l'air, appuie sur {trix} pour une FIGURE (+100 pts). Elle doit être finie AVANT de toucher le sol.",
		"hints": ["Lance la figure tout de suite après le décollage.",
			"Une seule figure par saut, sinon elle ne finit pas à temps.",
			"Prends de l'élan avec {pump} : plus haut = plus de temps."]},
	{"key": "combo", "len": 4400, "need": 1, "ramps": [800], "title": "COMBO", "short": "COMBO",
		"text": "Plusieurs éléments dans le même saut = COMBO, points multipliés ! Une figure ({trix}) puis atterris en NOSE ({rotate_horaire}).",
		"hints": ["Figure tout de suite au décollage, puis penche le bec vers l'avant.",
			"Prends beaucoup d'élan avec {pump} avant le tremplin.",
			"Une vrille (un tour complet) compte aussi dans le combo."]},
	{"key": "hook", "len": 6000, "need": 1, "roof": [400, 5000], "title": "GRAPPIN", "short": "GRAPPIN",
		"text": "Vise le plafond et maintiens {hook} pour t'accrocher et te balancer. Accroché, {pull} te hisse vers le plafond.",
		"hints": ["Ne relâche pas {hook} : il faut le MAINTENIR une bonne seconde.",
			"Saute ({jump}) puis lance le grappin vers le plafond.",
			"Accroché, tu peux te balancer ou tirer avec {pull} : les deux comptent."]},
	{"key": "swing", "len": 5200, "need": 1, "hole": 1600, "title": "BALANCIER", "short": "BALANCIER",
		"text": "Un grand trou ! Accroche le bloc de glace avec {hook}, balance-toi, et lâche quand Pinpouin remonte pour passer de l'autre côté.",
		"hints": ["Lance le grappin juste avant le bord du trou.",
			"Lâche {hook} quand tu as dépassé le bloc et que tu remontes.",
			"Prends de l'élan avec {pump} avant le trou."]},
]

# Panneaux du décor : position x sur la piste + texte ({action} = touche réelle).
# [TUTO 1.41] ce ne sont plus des explications (le maître s'en charge) mais
# de simples panneaux d'entrée « ATELIER 3 · PATTES » / « COURSE FINALE »,
# remplis dans _ready() depuis les ateliers.
var signs = []

var _track  # le sol principal (pour connaître la hauteur de la piste)
# [TUTO 1.41] tous les morceaux de piste, dans l'ordre : [{x, sol}] (x = début de la surface)
var _segments: Array = []
# [TUTO 1.41] trous de la piste : [{x, len, rise}] (rise > 0 : l'autre bord est plus HAUT)
var gaps: Array = []
var _workshops: Array = []    # ateliers avec leurs positions (pour TutorialCoach)
var _final_x := 0.0           # ligne de départ de la course finale
var _swing_hole := Vector2.ZERO   # début / fin du trou du balancier (x)


func _ready() -> void:
	# 0. [TUTO 1.41] positions des ateliers, mises bout à bout
	var x := float(intro_length)
	ramp_positions = []
	for spec in workshop_specs:
		var w: Dictionary = spec.duplicate(true)
		w.x0 = x
		w.x1 = x + float(spec.len)
		for r in spec.get("ramps", []):
			ramp_positions.append(int(x + r))
		if spec.has("roof"):
			roof_start = int(x + spec.roof[0])
			roof_length = int(spec.roof[1])
		if spec.has("hole"):
			_swing_hole = Vector2(x + spec.hole, x + spec.hole + swing_gap_length)
			gaps.append({"x": _swing_hole.x, "len": float(swing_gap_length), "rise": float(swing_gap_rise)})
		signs.append([int(x + 250), "ATELIER %d · %s" % [_workshops.size() + 1, spec.title]])
		_workshops.append(w)
		x = w.x1
	_final_x = x + 800.0
	for r in final_ramps:
		ramp_positions.append(int(_final_x + r))
	gaps.append({"x": _final_x + final_gap_at, "len": float(final_gap_length), "rise": -float(final_gap_drop)})
	finish_x = int(_final_x + final_length)
	track_length = maxi(track_length, finish_x + 2500)
	signs.append([int(_final_x), "COURSE FINALE\nle chrono part ici ▶"])

	# 1. La piste, coupée par les trous (un sol par morceau)
	var seg_x := 0.0
	var seg_y := 0.0
	for i in gaps.size() + 1:
		var end_x: float = gaps[i].x if i < gaps.size() else float(track_length)
		# surface de [seg_x, end_x] ; le sol s'arrête UNIT_SIZE avant sa
		# largeur (dernier point de surface = map_width - UNIT_SIZE)
		var sol = _add_sol(Vector2(seg_x, 0), int(end_x - seg_x) + UNIT_SIZE, bump_height, ground_thickness,
			world_seed if i == 0 else world_seed + "_%d" % i)
		if i == 0:
			_track = sol   # le 1er morceau garde la place et la graine de l'ancienne piste
		else:
			# on monte / descend le morceau pour que sa surface commence pile en seg_y
			sol.position.y = seg_y - sol.map_height * sol._noise(0.0)
		_segments.append({"x": seg_x, "sol": sol})
		if i < gaps.size():
			var edge_y := surface_y(end_x)
			seg_x = end_x + gaps[i].len
			seg_y = edge_y - gaps[i].rise

	# 1 bis. [TUTO 1.41] Bloc de glace du balancier, au milieu du grand trou,
	# 600 px au-dessus du bord de départ (comme les trous « GRAPPIN » du Sans fin)
	if _swing_hole != Vector2.ZERO:
		var fish = fish_res.instantiate()
		fish.position = Vector2((_swing_hole.x + _swing_hole.y) * 0.5, surface_y(_swing_hole.x) - 600.0)
		add_child(fish)

	# 2. Plafond d'entraînement au grappin, parallèle à la piste
	var roof_pos := Vector2(roof_start, surface_y(roof_start) - roof_height)
	_add_sol(roof_pos, roof_length, int(bump_height * 0.5), 60, world_seed + "_PLAFOND")

	# 3. Mur invisible au départ (on ne peut pas tomber en reculant)
	_add_wall(Vector2(-40, surface_y(0) - 1500), Vector2(80, 3000))

	# 4. Panneaux d'entrée des ateliers (décor seulement : [TUTO 1.41] announce = false)
	for s in signs:
		var sign_node := Node2D.new()
		sign_node.set_script(sign_script)
		sign_node.sign_text = s[1]
		sign_node.announce = false
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

	# 7. [TUTO 1.41] le maître ninja et ses ateliers
	var coach = load("res://src/levels/tutorial/TutorialCoach.gd").new()
	coach.setup(self, _workshops, _final_x)
	add_child(coach)


## [TUTO 1.41] Petit trou de la course finale : {x, len, rise} (ou null).
func final_gap():
	return gaps[-1] if not gaps.is_empty() and gaps[-1].x > _final_x else null


## [TUTO 1.41] Fin (x) du grand trou du balancier.
func hole_end() -> float:
	return _swing_hole.y


## [TUTO 1.41] Hauteur de sol « de référence » près de x, même au-dessus d'un
## trou (on prend alors le plus BAS des deux bords) : sert à la limite de chute.
func ground_y_near(x: float) -> float:
	for g in gaps:
		if x >= g.x and x < g.x + g.len:
			return maxf(surface_y(g.x - 1.0), surface_y(g.x + g.len))
	return surface_y(x)


# Hauteur (y) de la surface de la piste à l'abscisse x — même formule que sol.gd.
# [TUTO 1.41] piste en plusieurs morceaux : on lit le morceau qui commence
# avant x (au-dessus d'un trou : le morceau d'avant, prolongé).
func surface_y(x: float) -> float:
	var sol = _track
	for seg in _segments:
		if x >= seg.x:
			sol = seg.sol
	var lx: float = x - sol.position.x
	return sol.position.y + sol.map_height * sol._noise(lx) + sol.coeff_pente * lx


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
