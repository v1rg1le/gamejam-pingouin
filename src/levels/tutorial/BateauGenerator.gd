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
#
#  [TUTO 1.55] Changements demandés par l'équipe (21/11) :
#   - UNE seule réussite par atelier (`need` = 1 partout) : on ne redemande
#     plus plusieurs fois le même geste ;
#   - `prompts` : les invites « Appuie sur… » qui figent le jeu AU MOMENT du
#     geste (1re tentative de l'atelier seulement), avec le bon bouton selon
#     l'appareil (ActionPrompt.gd). Chaque invite : action de l'InputMap,
#     `when` = le moment (reconnu par TutorialCoach._prompt_ready), `text` =
#     la phrase sous le bouton, `mode` (option) = "release" (relâcher) ou
#     "repress" (relâcher puis réappuyer), `after` (option) = [TUTO 1.55b]
#     le rappel court que dit la bulle une fois le geste fait. Les invites
#     passent dans l'ordre ;
#   - deux ateliers FALAISE avant la course finale (`cliff` : hauteur du
#     mur, et nombre de prises 1 ou 2), voir _add_cliff().
#  Moments (`when`) disponibles : ground, ground_descent, lip (bord d'un
#  tremplin de l'atelier), takeoff (juste après le décollage), land_soon
#  (juste avant de toucher le sol), land_crash (un peu plus tôt : le temps
#  de tourner jusque sur le dos), under_roof, hooked, aim:<prise> (la prise
#  est dans l'axe du grappin, 45° vers l'avant), swing_release, over:<n>
#  (accroché, au-dessus du n-ième mur de la falaise).
var workshop_specs = [
	{"key": "pump", "len": 6500, "need": 1, "title": "PUMP", "short": "PUMP",
		"text": "Dans les DESCENTES, appuie sur {pump} pour prendre de la vitesse. Relâche dans les montées.",
		"prompts": [{"action": "pump", "when": "ground_descent", "text": "Ça descend : garde-le enfoncé un moment pour prendre de la vitesse !", "after": "Garde {pump} dans les descentes, relâche dans les montées."}],
		"hints": ["Appuie sur {pump} quand ça descend, relâche quand ça remonte.",
			"Garde {pump} un petit moment dans la pente, puis relâche.",
			"Regarde le sol : {pump} seulement quand Pinpouin glisse vers le bas."]},
	{"key": "jump", "len": 7000, "need": 1, "title": "SAUT", "short": "SAUT",
		"text": "Saute avec {jump}, et retombe sans chuter.",
		"prompts": [{"action": "jump", "when": "ground", "text": "Saute !", "after": "Et retombe sans chuter !"}],
		"hints": ["Appuie sur {jump} quand Pinpouin touche le sol.",
			"Un saut, on atterrit… et on recommence !"]},
	{"key": "feet", "len": 11500, "need": 1, "ramps": [800, 4400, 8000], "title": "SUR LES PATTES", "short": "PATTES",
		"text": "Saute au bout des tremplins ({jump}). En l'air, relève le bec avec {rotate_trigo} : Pinpouin retombe sur ses PATTES, c'est un TAIL (+ points) ! Debout, {rotate_horaire} le couche sur le ventre ; trop de {rotate_trigo}, il tombe en arrière.",
		"prompts": [{"action": "jump", "when": "lip", "text": "Saute au bord du tremplin !", "after": "En l'air ! Attends le bon moment…"},
			{"action": "rotate_trigo", "when": "land_soon", "text": "Un PETIT appui pour relever le bec… puis relâche !", "after": "Sur les pattes ! Relâche {rotate_trigo}, sinon tu bascules en arrière."}],
		"hints": ["Relève le bec avec {rotate_trigo} avant de toucher le sol : les pattes vers la pente.",
			"Pas trop quand même : tête en bas, c'est la chute !",
			"Une fois debout, lâche {rotate_trigo} : si tu le tiens, Pinpouin bascule en arrière.",
			"Prends de l'élan avec {pump} avant le tremplin, puis saute au bord."]},
	{"key": "nose", "len": 8000, "need": 1, "ramps": [800, 4400], "title": "NOSE", "short": "NOSE",
		"text": "Comme en skate : retombe le BEC EN AVANT ! Penche Pinpouin avec {rotate_horaire} juste avant le sol. NOSE = points + petit boost.",
		"prompts": [{"action": "jump", "when": "lip", "text": "Saute au bord du tremplin !", "after": "En l'air ! Attends le bon moment…"},
			{"action": "rotate_horaire", "when": "land_soon", "text": "Un petit appui : le bec en avant !", "after": "Juste un peu : trop penché, c'est la chute !"}],
		"hints": ["Penche vers l'avant avec {rotate_horaire}, un peu plus que pour les pattes.",
			"Pas trop quand même : sur le dos, c'est la chute !",
			"Commence à pencher dès que Pinpouin redescend."]},
	{"key": "crash", "len": 4400, "need": 1, "ramps": [800], "title": "LA CHUTE", "short": "CHUTE",
		"text": "Sur le dos, ça fait mal ! Essaie UNE fois pour voir : sur le tremplin, tourne longtemps avec {rotate_trigo} et atterris sur le dos.",
		"prompts": [{"action": "jump", "when": "lip", "text": "Saute au bord du tremplin !", "after": "En l'air ! Attends le bon moment…"},
			{"action": "rotate_trigo", "when": "land_crash", "text": "Maintiens-le jusqu'au sol : sur le dos !", "after": "Garde {rotate_trigo} jusqu'au sol…"}],
		"hints": ["Tourne plus longtemps avec {rotate_trigo} : il faut toucher le sol la tête en bas.",
			"Saute au bord du tremplin ({jump}) pour avoir le temps de tourner."],
		"done_text": "Tu as vu ? Roulade, sonné 1 seconde, et les points du saut\nsont perdus. En course, évite ça !"},
	{"key": "figure", "len": 8000, "need": 1, "ramps": [800, 4400], "title": "FIGURES", "short": "FIGURE",
		"text": "En l'air, appuie sur {trix} pour une FIGURE (+100 pts). Elle doit être finie AVANT de toucher le sol.",
		"prompts": [{"action": "jump", "when": "lip", "text": "Saute au bord du tremplin !", "after": "En l'air ! Attends le bon moment…"},
			{"action": "trix", "when": "takeoff", "text": "Une figure, tout de suite après le décollage !", "after": "Elle doit finir avant le sol."}],
		"hints": ["Lance la figure tout de suite après le décollage.",
			"Une seule figure par saut, sinon elle ne finit pas à temps.",
			"Prends de l'élan avec {pump} : plus haut = plus de temps."]},
	{"key": "combo", "len": 4400, "need": 1, "ramps": [800], "title": "COMBO", "short": "COMBO",
		"text": "Plusieurs éléments dans le même saut = COMBO, points multipliés ! Une figure ({trix}) puis atterris en NOSE ({rotate_horaire}).",
		"prompts": [{"action": "jump", "when": "lip", "text": "Saute au bord du tremplin !", "after": "En l'air ! Attends le bon moment…"},
			{"action": "trix", "when": "takeoff", "text": "D'abord une figure…", "after": "… et bec en avant juste avant le sol !"},
			{"action": "rotate_horaire", "when": "land_soon", "text": "… puis un petit appui : bec en avant pour le NOSE !", "after": "Figure + NOSE = COMBO !"}],
		"hints": ["Figure tout de suite au décollage, puis penche le bec vers l'avant.",
			"Prends beaucoup d'élan avec {pump} avant le tremplin.",
			"Une vrille (un tour complet) compte aussi dans le combo."]},
	{"key": "hook", "len": 6000, "need": 1, "roof": [400, 5000], "title": "GRAPPIN", "short": "GRAPPIN",
		"text": "Vise le plafond et maintiens {hook} pour t'accrocher et te balancer. Accroché, {pull} te hisse vers le plafond.",
		"prompts": [{"action": "hook", "when": "under_roof", "text": "Grappin vers le plafond, et GARDE-le enfoncé !", "after": "Garde {hook} enfoncé : balance-toi !"},
			{"action": "pull", "when": "hooked", "text": "Accroché ! Tu peux tirer pour te hisser.", "after": "Tu te hisses vers le plafond !"}],
		"hints": ["Ne relâche pas {hook} : il faut le MAINTENIR une bonne seconde.",
			"Saute ({jump}) puis lance le grappin vers le plafond.",
			"Accroché, tu peux te balancer ou tirer avec {pull} : les deux comptent."]},
	{"key": "swing", "len": 5200, "need": 1, "hole": 1600, "title": "BALANCIER", "short": "BALANCIER",
		"text": "Un grand trou ! Accroche le bloc de glace avec {hook}, balance-toi, et lâche quand Pinpouin remonte pour passer de l'autre côté.",
		"prompts": [{"action": "pump", "when": "ground_descent", "text": "Prends de l'élan avant le trou : il faut arriver vite !", "after": "Vite ! Ensuite, grappin vers le bloc de glace."},
			{"action": "hook", "when": "aim:swing", "text": "Le bloc de glace est dans l'axe : grappin !", "after": "Garde {hook}, balance-toi… je te dirai quand lâcher."},
			{"action": "hook", "when": "swing_release", "text": "Tu remontes : lâche maintenant !", "mode": "release", "after": "Vole jusqu'à l'autre bord !"}],
		"hints": ["Lance le grappin juste avant le bord du trou.",
			"Lâche {hook} quand tu as dépassé le bloc et que tu remontes.",
			"Prends de l'élan avec {pump} avant le trou."]},
	# [TUTO 1.55] FALAISE : un mur vertical de 500 px, une prise au-dessus du
	# bord. On s'accroche, on tire ({pull}) pour se hisser, on lâche au-dessus.
	{"key": "cliff", "len": 6500, "need": 1, "cliff": {"at": 2600, "steps": [500]}, "title": "FALAISE", "short": "FALAISE",
		"text": "Une falaise ! Accroche la prise du haut avec {hook}, tire avec {pull} pour te hisser, et lâche au-dessus du bord.",
		"prompts": [{"action": "hook", "when": "aim:hold1", "text": "La prise est dans l'axe : grappin, et garde-le !", "after": "Accroché ! Maintenant, tire pour monter."},
			{"action": "pull", "when": "hooked", "text": "Tire pour te hisser le long du mur !", "after": "Tire… et lâche {hook} une fois au-dessus du bord."},
			{"action": "hook", "when": "over:1", "text": "Tu es au-dessus de la falaise : lâche !", "mode": "release", "after": "Pose-toi en haut !"}],
		"hints": ["Lance le grappin vers la prise un peu avant le pied du mur.",
			"Une fois accroché, garde {hook} ET tire avec {pull}.",
			"Accroché au mur, {pump} t'aide aussi à monter.",
			"Lâche {hook} quand Pinpouin est au-dessus du bord."]},
	# [TUTO 1.55] GRANDE FALAISE : deux murs de 500 px en escalier, avec un
	# palier entre les deux : on refait le geste deux fois de suite.
	{"key": "cliff2", "len": 8800, "need": 1, "cliff": {"at": 2800, "steps": [500, 500], "ledge": 1000}, "title": "GRANDE FALAISE", "short": "SOMMET",
		"text": "Deux murs en escalier ! Grimpe le premier, pose-toi sur la marche, puis recommence pour le second.",
		"prompts": [{"action": "hook", "when": "aim:hold1", "text": "Première prise dans l'axe : grappin !", "after": "Tire pour monter le premier mur."},
			{"action": "pull", "when": "hooked", "text": "Tire pour monter !", "after": "Lâche au-dessus de la marche."},
			{"action": "hook", "when": "over:1", "text": "Au-dessus de la marche : lâche !", "mode": "release", "after": "Sur la marche ! Vise la 2e prise un peu avant le mur."},
			{"action": "hook", "when": "aim:hold2", "text": "Deuxième prise dans l'axe : grappin !", "after": "Tire encore !"},
			{"action": "pull", "when": "hooked", "text": "Tire encore !", "after": "Lâche au-dessus du sommet."},
			{"action": "hook", "when": "over:2", "text": "Au-dessus du sommet : lâche !", "mode": "release", "after": "Tout en haut, bravo !"}],
		"hints": ["Même geste que la falaise d'avant, deux fois de suite.",
			"Sur la marche, lance le grappin vers la 2e prise assez tôt, loin du mur.",
			"Accroché, garde {hook} ET tire avec {pull} ; lâche au-dessus du bord."]},
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
		if spec.has("cliff"):
			# [TUTO 1.55] falaise : construite après la piste (_add_cliff)
			w.cliff_x = x + float(spec.cliff.at)
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
		# [TUTO 1.55] centre du bloc, pour l'invite « dans l'axe : grappin ! »
		targets["swing"] = fish.position + FISH_CENTER

	# 1 ter. [TUTO 1.55] Les falaises (et leurs prises de glace)
	for w in _workshops:
		if w.has("cliff_x"):
			_add_cliff(w)

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


# =============================================================================
#  [TUTO 1.55] FALAISES (demande de l'équipe, 21/11 : « un tuto pour grimper
#  une falaise avant la course de fin », en deux temps : une falaise simple
#  au grappin + tirer, puis une plus haute avec des prises en escalier).
# -----------------------------------------------------------------------------
#  Une falaise = des marches posées SUR la piste (la piste continue dessous :
#  aucun trou, aucun risque de chute) :
#    - un ou plusieurs murs verticaux (`steps` : hauteur de chaque mur), avec
#      entre deux murs un palier de `ledge` px ;
#    - un dessus plat de CLIFF_TOP_LENGTH px (qui garde la pente de la piste) ;
#    - une descente douce (profil en cosinus) pour rejoindre la piste.
#  Atelier FALAISE : un mur de 500 px. Atelier GRANDE FALAISE : deux murs de
#  500 px, comme un escalier (« prises en escalier ») : on grimpe le premier,
#  on se pose sur le palier, on grimpe le second.
#  (Premier essai : un seul mur de 1000 px avec une prise basse DEVANT le
#  mur. Raté aux bots : en tirant depuis le sol, Pinpouin était projeté
#  au-dessus de la prise basse et restait posé dessus.)
#  Même rendu que les tremplins (corps bleu glace + bordure de glace sur les
#  paliers et le dessus, aucun nouvel asset), collision en SEGMENTS (contour
#  seul, cf. bug vitesse -> 0). Calque 2 (« ground ») : le grappin s'y
#  accroche aussi.
#  Prises : de petites boules de glace (dessinées en code, même bleu que la
#  piste ; les gros blocs « poisson » du balancier étaient trop larges : le
#  grappin s'accrochait à leur coin, juste au-dessus du mur, et Pinpouin
#  restait pendu contre la paroi). Une prise par mur, CLIFF_HOLD_IN px APRÈS
#  le bord et CLIFF_HOLD_UP px au-dessus : un grappin lancé « par défaut »
#  (45° vers l'avant, Espace au clavier ou bouton manette sans viser) la
#  touche, et la ligne à 45° passe ~100 px au-dessus du coin du mur (pas de
#  grappin planté dans la paroi). En tirant, Pinpouin monte le long du mur
#  puis passe par-dessus le bord, vers la prise ; il lâche et se pose.
#  Les centres des prises (« hold1 », « hold2 ») et la forme de la falaise
#  (cliff_faces, cliff_tops, cliff_top_y) sont gardés dans le dictionnaire
#  de l'atelier : TutorialCoach s'en sert pour les invites et pour savoir
#  quand Pinpouin est en haut.
# =============================================================================
const CLIFF_TOP_LENGTH := 1400.0
const CLIFF_DESCENT_PER_PX := 2.2     # longueur de la descente = 2,2 × hauteur
const CLIFF_HOLD_IN := 200.0
const CLIFF_HOLD_UP := 300.0
const HOLD_RADIUS := 55.0             # rayon d'une prise de falaise
const PLAYER_HALF_H := 35.0           # centre du pingouin au-dessus du sol
# centre visuel du bloc de glace du balancier par rapport à son origine
# (StaticBody2DFish.tscn) : pour l'invite « le bloc est dans l'axe »
const FISH_CENTER := Vector2(190, -55)

## [TUTO 1.55] Centres des prises (pour les invites « dans l'axe »)
var targets := {}


func _add_cliff(w: Dictionary) -> void:
	var cx: float = w.cliff_x
	var steps_h: Array = w.cliff.steps          # hauteur de chaque marche
	var ledge: float = float(w.cliff.get("ledge", 0.0))
	var base_y := surface_y(cx)
	# contour : pied du 1er mur, puis chaque marche (mur vertical + palier)
	var top := PackedVector2Array()
	var faces := []        # x du pied de chaque mur
	var tops := []         # y du haut de chaque mur
	var x := cx
	var y := base_y
	for i in steps_h.size():
		y -= float(steps_h[i])
		faces.append(x)
		tops.append(y)
		var run: float = ledge if i < steps_h.size() - 1 else CLIFF_TOP_LENGTH
		var n := 8
		for k in n + 1:
			var px := x + run * float(k) / n
			top.append(Vector2(px, y + coeff_pente * (px - x)))
		y += coeff_pente * run
		x += run
	# descente douce jusqu'à la piste (profil en cosinus)
	var total_h: float = surface_y(x) - y
	var descent := maxf(total_h, 300.0) * CLIFF_DESCENT_PER_PX
	var top_end := x
	var top_end_y := y
	var n2 := 24
	for k in range(1, n2 + 1):
		var t := float(k) / n2
		var px := top_end + descent * t
		var kk := 0.5 - 0.5 * cos(PI * t)
		top.append(Vector2(px, lerpf(top_end_y, surface_y(px), kk)))
	var end_x := top_end + descent
	var poly := PackedVector2Array()
	poly.append(Vector2(cx, base_y + 60))        # sous la piste (pied du mur)
	poly.append_array(top)                        # murs, paliers, dessus, descente
	poly.append(Vector2(end_x, surface_y(end_x) + 60))
	var body := StaticBody2D.new()
	body.collision_layer = 2
	var col := CollisionPolygon2D.new()
	col.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
	col.polygon = poly
	body.add_child(col)
	var fill := Polygon2D.new()
	fill.color = Color(0.694118, 0.862745, 0.956863, 1)   # même bleu que sol.tscn
	fill.polygon = poly
	body.add_child(fill)
	# bordure de glace sur chaque palier et sur le dessus (pas sur les murs)
	var seg := PackedVector2Array()
	for pt in top:
		if seg.size() > 0 and absf(pt.x - seg[seg.size() - 1].x) < 1.0:
			_add_edge(body, seg)       # mur vertical : on coupe la bordure ici
			seg = PackedVector2Array()
		seg.append(pt)
	_add_edge(body, seg)
	add_child(body)
	w.cliff_faces = faces
	w.cliff_tops = tops
	w.cliff_top_y = tops[tops.size() - 1]
	w.cliff_end = end_x
	w.targets = {}
	# une prise par marche : CLIFF_HOLD_IN px après le bord, CLIFF_HOLD_UP
	# px au-dessus (« hold1 », « hold2 »…)
	for i in faces.size():
		var hold := Vector2(faces[i] + CLIFF_HOLD_IN, tops[i] - CLIFF_HOLD_UP)
		_add_hold(hold)
		w.targets["hold%d" % (i + 1)] = hold


# Bordure de glace (même rendu que la piste) le long de `pts`.
func _add_edge(body: Node, pts: PackedVector2Array) -> void:
	if pts.size() < 2:
		return
	var edge := Line2D.new()
	edge.texture = preload("res://sprites/levels/tiles/tile_ice_up_long1.png")
	edge.texture_mode = Line2D.LINE_TEXTURE_TILE
	edge.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	edge.width = 64.0
	edge.position = Vector2(0, 28)   # comme la bordure de sol.tscn
	edge.points = pts
	body.add_child(edge)


# Une prise de falaise : boule de glace de HOLD_RADIUS px, centrée en `center`
# (calque 2 « ground » : le grappin s'y accroche). Dessin en code : disque
# du même bleu que la piste, bordure plus foncée (aucun nouvel asset).
func _add_hold(center: Vector2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.position = center
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HOLD_RADIUS
	shape.shape = circle
	body.add_child(shape)
	var pts := PackedVector2Array()
	for i in 24:
		pts.append(Vector2.from_angle(TAU * i / 24.0) * HOLD_RADIUS)
	var fill := Polygon2D.new()
	fill.color = Color(0.694118, 0.862745, 0.956863, 1)   # même bleu que sol.tscn
	fill.polygon = pts
	body.add_child(fill)
	var rim := Line2D.new()
	rim.points = pts
	rim.closed = true
	rim.width = 8.0
	rim.default_color = Color(0.25, 0.55, 0.85, 1)        # bord bleu plus foncé
	body.add_child(rim)
	add_child(body)


## [TUTO 1.55] Bords des tremplins (x) entre x0 et x1 : invite « saute ! ».
func ramp_lips(x0: float, x1: float) -> Array:
	var w := 2.0 * ramp_height / tan(deg_to_rad(ramp_lip_angle_deg))
	var out := []
	for rx in ramp_positions:
		if rx >= x0 and rx < x1:
			out.append(rx + w)
	return out


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
