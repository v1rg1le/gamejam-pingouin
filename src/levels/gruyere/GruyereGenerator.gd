extends Node2D
# =============================================================================
#  GruyereGenerator.gd — [GRUYÈRE 1.62] « Le Gruyère de glace » (MAQUETTE)
# -----------------------------------------------------------------------------
#  Niveau imaginé par l'équipe (croquis du 22/11 : piliers, plafonds-guides,
#  bols à tremplin, œufs à grappiner, puis cavernes reliées et arrivée dans un
#  half-pipe). Ce fichier construit la PARTIE 1 (à l'air libre) ; les
#  cavernes viendront ensuite (étape 2 du plan validé avec l'équipe).
#
#  Comme pour L'Œuf (EggGenerator.gd), toute la géométrie est CALCULÉE ici à
#  partir des constantes ci-dessous : aucune scène dessinée à la main. C'est
#  une maquette « grise » (couleurs unies + bordure de glace du jeu) : on
#  valide d'abord le parcours aux bots, l'habillage pixel art viendra après.
#
#  LE MOTIF (répété 3 fois, de plus en plus dur, demande de l'équipe) :
#   1. PILIERS : trois colonnes de glace séparées par des trous sur le VIDE.
#      Le dessus de chaque pilier est une VAGUE : on descend dans un creux puis
#      on remonte vers un petit tremplin au bord (lèvre à LIP_DEG).
#   2. PLAFOND-GUIDE : au-dessus du 2e trou pend un bloc dont le DESSOUS est
#      une voûte (∩). Si Pinpouin saute trop haut ou trop loin, il glisse
#      contre la voûte, qui le rabat sur le pilier suivant (« glisse contre la
#      paroi du haut pour se rediriger vers la prochaine plateforme »). S'il va
#      moins vite, il ne la touche pas : c'est un filet de sécurité, pas un
#      piège. La voûte est COURBE (pas de coin) pour ne jamais casser la
#      vitesse d'un coup (souvenir du bug « vitesse -> 0 »).
#   3. GRAND BOL : longue descente pour prendre de la vitesse (PUMP), fond
#      plat, puis remontée qui finit en TREMPLIN À 45° au bord d'une falaise
#      (« angle à 45° pour partir le plus haut et le plus loin possible »).
#   4. GRAND SAUT au-dessus du vide, la CAMÉRA DÉZOOME pour montrer où l'on va
#      (cadres rouges du croquis : zones de dézoom, pas de zoom permanent).
#      - Motif 1 : on se pose directement sur la pente du pilier suivant
#        (on apprend le saut).
#      - Motifs 2 et 3 : la plateforme suivante est PLUS HAUTE que la fin du
#        saut : il faut GRAPPINER UN ŒUF à la toute fin, se balancer et lâcher
#        au-dessus de la plateforme (« il faut utiliser le grappin à la toute
#        fin pour réussir à monter sur la plateforme suivante »).
#  Difficulté croissante (tableaux indexés par motif) : piliers plus étroits,
#  trous plus larges, creux plus profonds, saut plus long, œuf plus haut.
#
#  OÙ ON PLACE LES SAUTS : la trajectoire est calculée ici (gravité + air,
#  mêmes lois que Player._apply_air_drag_and_friction) à partir d'une vitesse
#  de décollage attendue (JUMP_SPEED), mesurée au bot. La plateforme d'arrivée
#  (ou l'œuf) est posée sur cette trajectoire.
#
#  RÉAPPARITIONS : points de passage (groupe « course_checkpoints », comme
#  L'Œuf) au début de chaque série de piliers et au bord de chaque bol.
#  MODE ENFANT : tout le parcours va vers la droite (forward_dir = +1).
#
#  Coordonnées : celles de Godot (y vers le BAS), unités : px. Départ en (0, 0).
# =============================================================================

# --- Couleurs de la maquette (mêmes que L'Œuf) --------------------------------
const ICE_COLOR := Color(0.694118, 0.862745, 0.956863, 1)   # bleu clair de la glace du jeu
const ROCK_COLOR := Color(0.36, 0.52, 0.70, 1)              # piliers (bleu plus sombre, lisible sur le ciel)
const CEIL_COLOR := Color(0.30, 0.44, 0.62, 1)              # plafonds-guides (encore un peu plus sombres)
const RIM_COLOR := Color(0.16, 0.36, 0.60, 1)               # contour
const RIM_WIDTH := 14.0
const EGG_COLOR := Color(0.86, 0.95, 1.0, 1)                # œufs à grappiner (presque blancs : on les repère)
const EDGE_TEXTURE := preload("res://sprites/levels/tiles/tile_ice_up_long1.png")
var half_pipe_res = preload("res://src/levels/GroundGenerator/HalfPipe.tscn")
var finish_gate_res = preload("res://src/levels/FinishGate.tscn")

# --- Physique (doit rester égale à celle du joueur, voir Player.gd) ----------
#  On la relit sur un Player au démarrage si possible (voir _read_physics) ;
#  ces valeurs ne servent que de repli.
var G := 800.0                 # Player.gravity
var K := 3.4730e-5             # Player.drag_coefficient() (air, par unité de masse)

# --- Dimensions générales -------------------------------------------------------
const PILLAR_DEPTH := 6000.0   # les piliers descendent jusque-là sous leur dessus : dessous, le vide
const SKY_TOP := -9000.0       # haut des blocs-plafonds (au-dessus de tout ce qu'on voit)

# --- Tableaux par motif (index 0, 1, 2 = de plus en plus dur) ----------------
## Largeur des piliers « vague » (px).
const WAVE_W := [1500.0, 1350.0, 1200.0]
## Profondeur du creux de la vague sous le bord d'entrée du pilier.
const WAVE_DIP := [300.0, 340.0, 380.0]
## Hauteur de la lèvre (bord de sortie) au-dessus du creux.
const WAVE_RISE := [170.0, 190.0, 210.0]
## Angle de la lèvre (montée au bord du pilier, en degrés).
const LIP_DEG := 24.0
## Largeur des trous entre piliers.
const GAP_W := [520.0, 600.0, 680.0]
## Le pilier suivant commence plus bas que la lèvre de (px).
const NEXT_DROP := 120.0
## Départ : haut de la pente de lancement (le 1er pilier commence en (0, 0)).
const START_RAMP := Vector2(-1500.0, -800.0)
## Pilier où l'on se pose après l'œuf (motifs 2 et 3) : long, pour ne pas le
## survoler quand le balancier lance fort (au bot : 2600 px de vol après le
## lâcher avec un pilier de 1950 px).
const HIGH_LAND_W := 3000.0

## Bol : profondeur sous son bord d'entrée, remontée jusqu'à la lèvre du
## tremplin, longueur du fond plat.
const BOWL_DEPTH := [1900.0, 2000.0, 2100.0]
## [maquette] 1150 au départ : la remontée mangeait trop d'élan (bot : 2070 px/s
## au fond, 1330 seulement à la lèvre). Remontée plus courte = saut plus vif.
const BOWL_CLIMB := [750.0, 800.0, 850.0]
const BOWL_FLAT := [700.0, 600.0, 500.0]
const KICK_DEG := 45.0         # angle du tremplin au bord du bol

## Vitesse de décollage attendue au bord du bol (px/s), mesurée au bot
## (avec PUMP dans la descente). Sert à placer l'arrivée du saut.
## Mesuré au bot (PUMP dans les descentes) : 1559-1568 / 1583-1589 / 1515-1568 ;
## sans PUMP à peine moins (1562 au 1er bol). On prend un peu en dessous : un
## joueur moins rapide doit encore pouvoir accrocher l'œuf.
const JUMP_SPEED := [1540.0, 1560.0, 1530.0]
## Motif 1 : l'arrivée (pente descendante) commence à cette fraction de la
## portée et SOUS la trajectoire de LAND_BELOW px.
const LAND_FRAC := 0.62
const LAND_BELOW := 260.0
## Motifs 2 et 3 : bord de la plateforme haute à cette fraction de la portée
## « au niveau de la lèvre », et AU-DESSUS de la trajectoire de PLAT_ABOVE px
## (sans grappin on passe dessous et on tombe).
const PLAT_FRAC := [0.0, 1.04, 1.07]
const PLAT_ABOVE := [0.0, 260.0, 320.0]
## Œuf : position par rapport au bord gauche de la plateforme haute.
## EGG_BACK > 0 : en arrière du bord (au-dessus du vide) ; < 0 : AU-DESSUS de
## la plateforme. EGG_UP : hauteur au-dessus de son dessus.
## Essais au bot (maquette) : œuf au-dessus du vide (380 / 520, puis 600 / 640)
## -> le bas du balancier passe SOUS le niveau de la plateforme, Pinpouin tape
## le flanc du pilier, et la petite traction élastique du grappin raccourcit la
## corde : il finissait pendu sous l'œuf sans pouvoir atteindre le bord.
## Solution retenue : la même géométrie que les ateliers FALAISE du tuto et la
## montée de L'Œuf (prise un peu en retrait du bord, au-dessus de la
## plateforme) : on se plaque contre le flanc, on TIRE pour monter le long du
## pilier, on lâche au-dessus et on se pose. Avec une corde courte, un bon
## joueur passe directement par-dessus en balancier.
const EGG_BACK := [0.0, -120.0, -120.0]
const EGG_UP := [0.0, 420.0, 460.0]
## [ŒUF 1.63] la descente après l'œuf : son bord est à EGG_DROP SOUS l'œuf
## et au moins EGG_LAND_MIN à sa droite.
const EGG_DROP := 650.0
const EGG_LAND_MIN := 250.0
const EGG_RX := 130.0          # demi-largeur (collision = ellipse : le crochet s'y plante)
const EGG_RY := 170.0          # demi-hauteur

# --- Résultats (pour les bots, la caméra, les captures) ----------------------
var spawn_point := Vector2.ZERO
var checkpoints: Array = []    # [{name, pos, vel, x}] dans l'ordre (x = seuil de passage)
var _cp := 0
var holds := {}                # nom -> centre des œufs
var jump_zones: Array = []     # [{rect: Rect2, target: Vector2, motif}] zones de dézoom
var pillars: Array = []        # [{x0, x1, top: PackedVector2Array}] (pour le bot : sol sous lui)
var bowls: Array = []          # [{entry: Vector2, lip: Vector2}]
var platforms_high: Array = [] # [{edge: Vector2, egg: String}] plateformes à atteindre au grappin
var finish_x := 0.0


func _init() -> void:
	add_to_group("course_checkpoints")   # Player._pick_respawn_sample nous trouve par ce groupe
	add_to_group("course_direction")     # KidAssist (mode enfant) aussi


func _ready() -> void:
	_read_physics()
	var cur := Vector2(0, 0)             # bord d'entrée du pilier courant
	# --- départ : un petit sommet, on descend tout de suite (croquis : « Départ »)
	# [maquette] départ en haut d'une pente (800 px au-dessus du 1er creux) :
	# au bot, sans PUMP, partir à plat ne donnait que 450 px/s au 1er trou
	# (impossible à franchir). Ici on arrive lancé, même sans pomper.
	spawn_point = Vector2(START_RAMP.x + 150.0, START_RAMP.y - 80.0)
	checkpoints.append({"name": "départ", "pos": spawn_point, "vel": Vector2(300, 0), "x": -INF})
	for m in 3:
		cur = _build_motif(m, cur)
	_add_caves(cur)   # [CAVERNES 1.63] (remplace l'arrivée provisoire de la 1.62)
	get_parent()._set_spawn_position(spawn_point)


## Relit g et k sur un vrai Player (si la scène du joueur se charge) pour que
## les trajectoires calculées ici soient celles du jeu, même si l'équipe a
## changé la physique dans le code.
func _read_physics() -> void:
	var res = load("res://src/actors/Player.gd")
	if res == null:
		return
	var p = res.new()
	G = p.gravity
	K = p.drag_coefficient()
	p.free()


# =============================================================================
#  Outils de géométrie
# =============================================================================

## Courbe d'Hermite de p0 à p1, avec un angle de départ et d'arrivée (degrés ;
## 0 = horizontal vers la droite, > 0 = qui DESCEND, puisque y va vers le bas).
## Sert à faire des profils lisses, sans cassure (la glisse aime les courbes).
func _hermite(p0: Vector2, p1: Vector2, a0: float, a1: float, steps := 24) -> PackedVector2Array:
	var l := p0.distance_to(p1)
	var t0 := Vector2.from_angle(deg_to_rad(a0)) * l
	var t1 := Vector2.from_angle(deg_to_rad(a1)) * l
	var out := PackedVector2Array()
	for i in steps + 1:
		var s := float(i) / steps
		var s2 := s * s
		var s3 := s2 * s
		out.append(p0 * (2 * s3 - 3 * s2 + 1) + t0 * (s3 - 2 * s2 + s) + p1 * (-2 * s3 + 3 * s2) + t1 * (s3 - s2))
	return out


## Ajoute `b` à `a` sans répéter le point commun.
func _join(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var out := a.duplicate()
	for i in b.size():
		if i == 0 and out.size() > 0 and out[out.size() - 1].distance_to(b[0]) < 1.0:
			continue
		out.append(b[i])
	return out


## Corps de glace : remplissage + collision en SEGMENTS (contour seul, comme
## tous les sols du jeu depuis le correctif « vitesse -> 0 ») + bordure de
## glace sur les dessus (`edges`). Calque 2 (« ground ») : on y glisse ET le
## grappin s'y accroche.
func _add_body(poly: PackedVector2Array, edges: Array = [], z := 0, color := ROCK_COLOR) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.z_index = z
	var col := CollisionPolygon2D.new()
	col.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
	col.polygon = poly
	body.add_child(col)
	var fill := Polygon2D.new()
	fill.color = color
	fill.polygon = poly
	body.add_child(fill)
	var rim := Line2D.new()
	rim.points = poly
	rim.closed = true
	rim.width = RIM_WIDTH
	rim.default_color = RIM_COLOR
	body.add_child(rim)
	for e in edges:
		_add_edge(body, e)
	add_child(body)
	return body


## Bordure de glace (même rendu que la piste, voir EggGenerator._add_edge).
func _add_edge(parent: Node, pts: PackedVector2Array) -> void:
	if pts.size() < 2:
		return
	var edge := Line2D.new()
	edge.texture = EDGE_TEXTURE
	edge.texture_mode = Line2D.LINE_TEXTURE_TILE
	edge.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	edge.width = 64.0
	edge.position = Vector2(0, 28)
	edge.points = pts
	parent.add_child(edge)


## Pilier : un dessus (polyligne de gauche à droite) et des flancs verticaux
## qui descendent de PILLAR_DEPTH sous le point le plus bas du dessus.
func _add_pillar(top: PackedVector2Array) -> void:
	var low := -INF
	for p in top:
		low = maxf(low, p.y)
	var poly := top.duplicate()
	poly.append(Vector2(top[top.size() - 1].x, low + PILLAR_DEPTH))
	poly.append(Vector2(top[0].x, low + PILLAR_DEPTH))
	_add_body(poly, [top], 2)
	pillars.append({"x0": top[0].x, "x1": top[top.size() - 1].x, "top": top})


## Trajectoire d'un saut (gravité + air), depuis `p0` à la vitesse `v0`.
## Renvoie les points jusqu'à `y_max` (vers le bas) ou `t_max` secondes.
func _trajectory(p0: Vector2, v0: Vector2, y_max: float, t_max := 8.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var p := p0
	var v := v0
	var dt := 1.0 / 120.0
	var t := 0.0
	while t < t_max and p.y < y_max:
		out.append(p)
		v += Vector2(0, G) * dt - v * (K * v.length()) * dt
		p += v * dt
		t += dt
	return out


## y de la trajectoire à l'abscisse x (dernier point si au-delà).
func _traj_y(traj: PackedVector2Array, x: float) -> float:
	for i in traj.size() - 1:
		if traj[i].x <= x and traj[i + 1].x > x:
			return lerpf(traj[i].y, traj[i + 1].y, (x - traj[i].x) / (traj[i + 1].x - traj[i].x))
	return traj[traj.size() - 1].y


# =============================================================================
#  Un motif : 3 piliers (plafond-guide au-dessus du 2e trou), bol, grand saut
# =============================================================================
## `entry` : bord gauche du 1er pilier (son dessus). Renvoie le bord gauche du
## pilier d'arrivée du saut (= 1er pilier du motif suivant).
func _build_motif(m: int, entry: Vector2) -> Vector2:
	var cur := entry
	# ---- 1. Piliers « vague » --------------------------------------------------
	for k in 3:
		var w: float = WAVE_W[m]
		var first := (k == 0)
		var top: PackedVector2Array
		if first and m > 0:
			# pilier d'arrivée du grand saut (motifs 2 et 3) : on y monte au
			# grappin, son bord gauche est un sommet arrondi, puis on redescend
			# [maquette] creux plus profond et plus loin (70 % de la largeur) :
			# au bot, posé lentement après l'œuf, Pinpouin ne pouvait plus
			# remonter la lèvre d'un pilier aussi long (100 px/s, chute au bord).
			# Ici toute la 1re partie descend : on reprend de l'élan.
			top = _wave_top(cur, HIGH_LAND_W, m, 26.0, 0.7, 380.0)
		elif first:
			# pilier de départ : la pente de lancement puis la vague
			top = _join(_hermite(START_RAMP, cur, 0.0, 30.0, 16), _wave_top(cur, w + 300.0, m, 30.0))
		else:
			top = _wave_top(cur, w, m, 28.0)
		_add_pillar(top)
		if k == 0:
			var cpi := 2 if m > 0 else 18     # (motif 1 : après la pente de lancement)
			checkpoints.append({"name": "piliers %d" % (m + 1), "pos": top[cpi] + Vector2(0, -60),
				"vel": Vector2(900, 0), "x": top[0].x + 50.0})
		var lip: Vector2 = top[top.size() - 1]
		var gap: float = GAP_W[m]
		var next_edge := Vector2(lip.x + gap, lip.y + NEXT_DROP)
		# [maquette] plafond-guide au-dessus des TROIS trous de chaque série (le
		# croquis en montre un) : au bot, on arrive parfois très vite du grand
		# saut (1400 px/s) et on survolait le pilier suivant ; avant le bol, un
		# saut trop long faisait atterrir à plat au fond du bol (élan perdu :
		# 1210 px/s au tremplin au lieu de 1560). Le plafond rabat sur la pente ;
		# à vitesse normale on ne le touche pas.
		_add_guide_ceiling(lip, next_edge)
		if k == 2:
			# le dernier trou mène au bol : il commence au même niveau
			next_edge = Vector2(lip.x + gap, lip.y + NEXT_DROP)
		cur = next_edge
	# ---- 2. Grand bol + tremplin à 45° ----------------------------------------
	var lip := _add_bowl(m, cur)
	# réapparition sur le 3e PILIER, dans son creux, lancé à 1000 px/s : on
	# refait le petit saut vers le bol et on y arrive avec l'élan normal.
	# (Essais au bot : repartir dans la descente du bol ne marche pas, car
	# Player limite la vitesse de réapparition à 1200 px/s -> 1170 px/s
	# seulement au tremplin au lieu de 1570 : saut trop court à chaque fois.)
	var p3: Dictionary = pillars[pillars.size() - 2]
	var p3_mid: Vector2 = p3.top[p3.top.size() / 2]
	checkpoints.append({"name": "bol %d" % (m + 1), "pos": p3_mid + Vector2(0, -70),
		"vel": Vector2(1000.0, 0.0), "x": cur.x + 60.0})
	# ---- 3. Grand saut ----------------------------------------------------------
	var v0 := Vector2.from_angle(deg_to_rad(-KICK_DEG)) * float(JUMP_SPEED[m])
	var traj := _trajectory(lip, v0, lip.y + 3000.0)
	# portée « au niveau de la lèvre » (là où la trajectoire repasse à lip.y)
	var range_x := lip.x
	for i in range(1, traj.size()):
		if traj[i].y >= lip.y and traj[i].x > lip.x + 100.0:
			range_x = traj[i].x
			break
	var span := range_x - lip.x
	var land_edge: Vector2
	var target: Vector2
	if m == 0:
		# on se pose sur une pente qui descend, un peu sous la trajectoire
		var x := lip.x + span * LAND_FRAC
		land_edge = Vector2(x, _traj_y(traj, x) + LAND_BELOW)
		target = land_edge + Vector2(400, 200)
	else:
		# plateforme plus haute que la fin du saut : il faut l'œuf
		var x2: float = lip.x + span * float(PLAT_FRAC[m])
		land_edge = Vector2(x2, _traj_y(traj, x2) - float(PLAT_ABOVE[m]))
		var egg := land_edge + Vector2(-float(EGG_BACK[m]), -float(EGG_UP[m]))
		var name := "oeuf%d" % (m + 1)
		_add_egg(name, egg)
		# distance la plus courte entre la trajectoire prévue et l'œuf (le
		# grappin porte à 1200 px ; on vise 600-850 pour un lancer confortable)
		var dmin := INF
		for q in traj:
			dmin = minf(dmin, q.distance_to(egg))
		print("[GRUYÈRE] %s : à %d px de la trajectoire prévue" % [name, roundi(dmin)])
		# [ŒUF 1.63] demande de l'équipe : l'œuf GARDE SA PLACE, mais la descente
		# qui suit est PLUS BAS : on attrape l'œuf par en dessous, on passe en
		# balancier sous lui et on se laisse retomber dans la descente.
		# Le bord de la descente est posé EGG_DROP sous l'œuf, puis repoussé
		# vers la droite tant que la trajectoire du saut (sans grappin) arrive
		# au-dessus de lui : sans l'œuf, on passe sous le bord et on tombe.
		var ey: float = egg.y + EGG_DROP
		var ex: float = egg.x + EGG_LAND_MIN
		while _traj_y(traj, ex) < ey + 150.0 and ex < egg.x + 1500.0:
			ex += 50.0
		land_edge = Vector2(ex, ey)
		platforms_high.append({"edge": land_edge, "egg": name, "motif": m})
		target = egg
	# zone de dézoom : de la remontée du bol jusqu'à l'arrivée
	var top_y := lip.y - span * 0.35 - 600.0
	var rect := Rect2(Vector2(lip.x - 1400.0, top_y), Vector2(land_edge.x - lip.x + 1800.0, land_edge.y - top_y + 900.0))
	jump_zones.append({"rect": rect, "target": target, "motif": m, "lip": lip, "traj": traj})
	return land_edge


## Dessus d'un pilier « vague » : on entre par `edge`, on descend dans un creux
## (pente d'entrée `in_deg`), puis on remonte vers la lèvre (LIP_DEG) au bord droit.
func _wave_top(edge: Vector2, w: float, m: int, in_deg: float, valley_frac := 0.5, extra_dip := 0.0) -> PackedVector2Array:
	var dip: float = WAVE_DIP[m] + extra_dip
	var rise: float = WAVE_RISE[m]
	var valley := Vector2(edge.x + w * valley_frac, edge.y + dip)
	var lip := Vector2(edge.x + w, edge.y + dip - rise)
	var a := _hermite(edge, valley, in_deg, 0.0, 16)
	var b := _hermite(valley, lip, 0.0, -LIP_DEG, 16)
	return _join(a, b)


## Plafond-guide au-dessus du trou entre `lip` (bord du pilier qu'on quitte) et
## `next_edge` (bord du pilier suivant) : bloc qui pend du ciel, dessous en
## voûte (∩) qui rabat vers le bas sur le pilier suivant.
func _add_guide_ceiling(lip: Vector2, next_edge: Vector2) -> void:
	var gap := next_edge.x - lip.x
	var a := Vector2(lip.x - 260.0, lip.y - 330.0)               # côté gauche, au-dessus de la lèvre
	var b := Vector2(lip.x + gap * 0.45, lip.y - 380.0)          # sommet de la voûte
	var c := Vector2(next_edge.x + 380.0, next_edge.y - 150.0)   # rabat sur le pilier suivant
	var under := _join(_hermite(a, b, -18.0, 0.0, 14), _hermite(b, c, 0.0, 34.0, 18))
	var poly := PackedVector2Array()
	poly.append(Vector2(a.x, SKY_TOP))
	poly.append_array(under)
	poly.append(Vector2(c.x, SKY_TOP))
	# pas de bordure de glace en dessous (on y glisse sur le « dos ») : contour seul
	_add_body(poly, [], 3, CEIL_COLOR)


## Grand bol : longue descente, fond plat, remontée en tremplin à 45° au bord
## d'une falaise. `entry` : bord gauche. Renvoie la lèvre du tremplin.
func _add_bowl(m: int, entry: Vector2) -> Vector2:
	var depth: float = BOWL_DEPTH[m]
	var climb: float = BOWL_CLIMB[m]
	var flat: float = BOWL_FLAT[m]
	var mid := Vector2(entry.x + depth * 0.55, entry.y + depth * 0.55)        # milieu de la descente (~45°)
	var b1 := Vector2(entry.x + depth * 1.25, entry.y + depth)                 # début du fond
	var b2 := Vector2(b1.x + flat, b1.y)                                      # fin du fond
	var lip := Vector2(b2.x + climb * 1.35, b1.y - climb)                     # lèvre du tremplin
	var top := _hermite(entry, mid, 15.0, 42.0, 18)
	top = _join(top, _hermite(mid, b1, 42.0, 0.0, 18))
	top = _join(top, PackedVector2Array([b1, b2]))
	top = _join(top, _hermite(b2, lip, 0.0, -KICK_DEG, 22))
	_add_pillar(top)
	bowls.append({"entry": entry, "mid": mid, "lip": lip, "bottom": b1})
	return lip


## Petite prise ronde (même dessin que les prises des cavernes et de L'Œuf).
const HOLD_TEXTURE := preload("res://sprites/levels/egg/prise.png")
func _add_small_hold(name: String, center: Vector2) -> void:
	holds[name] = center
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.position = center
	body.z_index = 6
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 55.0
	shape.shape = circle
	body.add_child(shape)
	var spr := Sprite2D.new()
	spr.texture = HOLD_TEXTURE
	spr.scale = Vector2(4, 4)
	body.add_child(spr)
	add_child(body)


## Œuf à grappiner : ellipse de glace (collision en polygone : le crochet s'y
## plante, Pinpouin peut aussi s'y poser). Clin d'œil au niveau L'Œuf.
func _add_egg(name: String, center: Vector2) -> void:
	holds[name] = center
	var poly := PackedVector2Array()
	for i in 32:
		var t := TAU * i / 32.0
		# un peu plus étroit en haut (forme d'œuf, comme EggGenerator)
		var s := sin(t)
		poly.append(center + Vector2(EGG_RX * cos(t) * (1.0 + 0.12 * s), EGG_RY * s))
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.z_index = 6
	var col := CollisionPolygon2D.new()
	col.polygon = poly
	body.add_child(col)
	var fill := Polygon2D.new()
	fill.color = EGG_COLOR
	fill.polygon = poly
	body.add_child(fill)
	var rim := Line2D.new()
	rim.points = poly
	rim.closed = true
	rim.width = 10.0
	rim.default_color = RIM_COLOR
	body.add_child(rim)
	add_child(body)


# =============================================================================
#  [CAVERNES 1.63] Partie 2 : trois cavernes, des passages à l'air libre entre
#  elles, et l'arrivée de tous les chemins dans le half-pipe.
# -----------------------------------------------------------------------------
#  Plan validé avec l'équipe (23/11) :
#   - 3 cavernes générées (CaveGenerator), une GRAINE FIXE chacune (même niveau
#     en Chill et en Score) ;
#   - entre deux cavernes, un PASSAGE À L'AIR LIBRE : chaque sortie s'ouvre sur
#     un rebord, en face le balcon de l'entrée du même étage (un saut) ; tomber
#     entre les deux ramène sur le sol de l'étage le plus bas, qui mène à
#     l'entrée la plus basse (jamais de chute mortelle dans un passage) ;
#   - fin : la sortie du HAUT se laisse tomber dans le half-pipe ; la sortie
#     du BAS arrive sous lui et on y monte au grappin (deux prises).
#  Étages des entrées / sorties : chaque entrée doit être servie par une
#  sortie du même étage (ou être l'étage le plus bas).
# =============================================================================
## [1.66] 4 cavernes (choix de l'équipe : « 4 cavernes + 3 zones de vide »).
## La 3e sort maintenant par 3 étages (avant : 2, c'était la dernière).
## Angles θ (entrées) et φ (sorties) [1.66] : -18 = tremplin, 55 = rampe
## d'accueil (on arrive en tombant), +55 en sortie = on plonge, -55 en entrée =
## on arrive par EN DESSOUS (tube courbe). Voir CaveGenerator.entry_angles.
## Zone de vide 2 : la sortie du bas de la caverne 2 plonge (+70) dans un
## grand virage en U (PipeBend, boosts) qui remonte dans l'entrée du bas de
## la caverne 3 par en dessous (-55) : la redirection « façon quarter pipe ».
const CAVES := [
	{"seed": 1440, "entries": [0, 1], "exits": [0, 1, 2], "theta": [8.0, 8.0], "phi": [-18.0, -18.0, -18.0]},
	{"seed": 2302, "entries": [0, 1, 2], "exits": [0, 1, 2, 3], "theta": [55.0, 55.0, 55.0], "phi": [-18.0, -18.0, -18.0, 70.0], "phi_r": [0.0, 0.0, 0.0, 500.0]},
	{"seed": 3303, "entries": [0, 1, 2, 3], "exits": [0, 1, 2], "theta": [55.0, 55.0, 55.0, -55.0], "theta_r": [0.0, 0.0, 0.0, 800.0], "phi": [-18.0, -18.0, -18.0]},
	{"seed": 4404, "entries": [0, 1, 2], "exits": [0, 1], "theta": [55.0, 55.0, 55.0], "phi": [8.0, 8.0]},
]
# -----------------------------------------------------------------------------
#  [1.66] ZONES DE VIDE entre deux cavernes (croquis « Interconnexion des
#  cavernes » de l'équipe) : chaque sortie 1, 2, 3 peut mener à chaque
#  entrée A, B, C, « en utilisant le grappin ou non ». Choix de l'équipe :
#  « saut + œufs pour changer ».
#   - chaque SORTIE se termine par un TREMPLIN (virage PipeBend de +8° à
#     -18°) qui lance Pinpouin au-dessus du vide ;
#   - chaque ENTRÉE a une RAMPE D'ACCUEIL courbe (virage de 55° vers 8°,
#     rayon 1400) : on se pose dessus en tombant, dans le sens de la pente ;
#   - les entrées de la caverne suivante sont un étage (LANE_GAP) + 150 px
#     plus bas que les sorties de même numéro : calculé avec la vraie
#     physique (gravité + air), de 65 à 130 km/h (1000 à 2200 px/s) on
#     retombe dans l'entrée EN FACE ; plus lent, une entrée plus bas ; tout
#     en bas, plus lent = le VIDE (réapparition au dernier carrefour) ;
#   - pour MONTER d'une entrée (ou deux), il faut les ŒUFS : un œuf par
#     sortie (sauf celle du haut), juste après le tremplin, au-dessus de la
#     trajectoire de l'étage du dessous ; ils forment une échelle (on peut
#     enchaîner deux œufs pour monter de deux étages) ; deux œufs au-dessus
#     de l'étage du haut servent de balançoire pour prendre de la vitesse.
# -----------------------------------------------------------------------------
const VOID_FAR := 2500.0       # distance horizontale bout du tremplin -> flanc de la caverne suivante
const VOID_DROP := 1100.0      # l'entrée « en face » est 1100 px plus bas que le bout du tremplin
const KICK_TURN := -26.0       # tremplin : de +8° (pente du couloir de sortie) à -18°
const KICK_RADIUS := 900.0
const CATCH_DEG := 55.0        # rampe d'accueil : de 55° (on tombe) à 8° (couloir d'entrée)
const CATCH_RADIUS := 1400.0
const LADDER_EGG := Vector2(400.0, -500.0)   # œuf de l'échelle, depuis le bout du tremplin de son étage
var void_zones: Array = []     # [{rect, a, b, kick_ends: {l: Vector2}, mouths: {l: Vector2}, eggs: {l: name}}]
const CAVE_COLUMNS := 10       # [1.63] 10 colonnes : ~35 à 45 s par caverne au bot (niveau visé : 3 à 5 min pour un joueur)
const PASS_W := 1450.0         # largeur d'un passage (flanc à flanc)
const PASS_DROP := 150.0       # le flanc suivant commence un peu plus bas
const EXIT_LEDGE := 300.0      # rebord devant une sortie
const BALCONY := 450.0         # balcon devant une entrée
const FINAL_LEDGE := 700.0     # long rebord devant la sortie du haut de la dernière caverne
const STUB_TAN := 0.140541     # tan(8°) : pente des couloirs d'entrée et de sortie
var caves: Array = []          # CaveGenerator
var hp_holds: Array = []       # prises de la montée vers le half-pipe (bot)
var cave_cp = null             # dernier carrefour atteint dans les cavernes
var cave_lip := Vector2.ZERO   # lèvre du pilier qui fait face à la caverne 1 (bot)
var hp_x := 0.0                # bord gauche du half-pipe (bot)
var hp_deck_y := 0.0


func _cave_origin_for_entry(lane0_start: Vector2) -> Vector2:
	# le couloir d'entrée de l'étage 0 commence à `lane0_start` (sur le flanc)
	return lane0_start + Vector2(CaveGenerator.STUB, CaveGenerator.STUB * STUB_TAN)


func _make_cave(i: int, origin: Vector2) -> CaveGenerator:
	var cfg: Dictionary = CAVES[i]
	var g := CaveGenerator.new()
	g.name = "Caverne%d" % (i + 1)
	g.cave_seed = cfg.seed
	g.entry_lanes.assign(cfg.entries)
	g.exit_lanes.assign(cfg.exits)
	g.entry_angles.assign(cfg.get("theta", []))     # [1.66] angles θ / φ
	g.exit_angles.assign(cfg.get("phi", []))
	g.entry_radii.assign(cfg.get("theta_r", []))
	g.exit_radii.assign(cfg.get("phi_r", []))
	g.columns = CAVE_COLUMNS
	g.position = origin
	add_child(g)
	caves.append(g)
	return g


## Début (sur le flanc) du couloir d'entrée de l'étage l / fin du couloir de sortie.
func _entry_start(g: CaveGenerator, l: int) -> Vector2:
	return g.position + g.node_pos(0, l) - Vector2(CaveGenerator.STUB, CaveGenerator.STUB * STUB_TAN)


func _exit_end(g: CaveGenerator, l: int) -> Vector2:
	return g.position + g.node_pos(g.columns, l) + Vector2(CaveGenerator.STUB, CaveGenerator.STUB * STUB_TAN)


## Petit bloc de roche (rebord, balcon) collé à un flanc : dessus de a à b.
func _add_ledge(a: Vector2, b: Vector2, thick := 220.0) -> void:
	var top := PackedVector2Array([a, b])
	var poly := PackedVector2Array([a, b, Vector2(b.x, b.y + thick), Vector2(a.x, a.y + thick)])
	_add_body(poly, [top], 3)


func _add_caves(edge: Vector2) -> void:
	# --- pilier d'arrivée de l'œuf 3 : longue descente, petite lèvre au bout
	var lipp := edge + Vector2(2400.0, 520.0)
	var top := _join(_hermite(edge, edge + Vector2(1200.0, 420.0), 26.0, 12.0, 16), _hermite(edge + Vector2(1200.0, 420.0), lipp, 12.0, -6.0, 12))
	_add_pillar(top)
	cave_lip = lipp
	checkpoints.append({"name": "avant les cavernes", "pos": top[4] + Vector2(0, -60), "vel": Vector2(700, 0), "x": edge.x + 50.0})
	# --- caverne 1 : son entrée du haut en face de la lèvre, l'autre en dessous
	var e0 := lipp + Vector2(EXIT_LEDGE * 0.0 + BALCONY + 700.0, PASS_DROP)
	var g1 := _make_cave(0, _cave_origin_for_entry(e0))
	_add_ledge(e0 - Vector2(BALCONY, 0), e0)
	# sol de l'étage 1 : du pied du pilier jusqu'à l'entrée basse (on y retombe)
	var e1 := _entry_start(g1, 1)
	var fl := _hermite(Vector2(lipp.x, e1.y - 60.0), e1, 6.0, 8.0, 10)
	var poly := fl.duplicate()
	poly.append(Vector2(e1.x, e1.y + 4000.0))
	poly.append(Vector2(lipp.x, e1.y + 4000.0))
	_add_body(poly, [fl], 2)
	# --- cavernes suivantes, avec une ZONE DE VIDE avant chacune [1.66]
	# (avant : un passage à l'air libre, _add_passage, gardé plus bas)
	var prev := g1
	for i in range(1, CAVES.size()):
		var k0 := _kick_end(prev, 0)
		var g := _make_cave(i, _cave_origin_for_entry(k0 + Vector2(VOID_FAR, VOID_DROP)))
		_add_void_zone(prev, g)
		prev = g
	_add_final(prev)


## [1.66] Bout du virage de sortie de l'étage l (tremplin ou plongeon),
## construit par la caverne elle-même (exit_angles).
func _kick_end(g: CaveGenerator, l: int) -> Vector2:
	return g.position + g.exit_tips[l].pos


## [1.66] Rampe d'accueil d'une entrée : virage de CATCH_DEG (on arrive en
## tombant) vers 8° (le couloir), qui se termine pile à l'entrée `mouth`.
func _catch_line(mouth: Vector2) -> PackedVector2Array:
	var arc := PipeBend.arc(Vector2.ZERO, CATCH_DEG, 8.0 - CATCH_DEG, CATCH_RADIUS)
	var shift := mouth - arc[arc.size() - 1]
	var out := PackedVector2Array()
	for q in arc:
		out.append(q + shift)
	return out


## [1.66] Bloc de roche sous une ligne de sol (épaisseur `thick`).
func _add_slab(top: PackedVector2Array, thick := 240.0) -> void:
	var poly := top.duplicate()
	for i in range(top.size() - 1, -1, -1):
		poly.append(top[i] + Vector2(0, thick))
	_add_body(poly, [top], 3)


## [1.66] Zone de vide entre la caverne `a` (sorties) et `b` (entrées) : voir
## l'en-tête « ZONES DE VIDE ».
func _add_void_zone(a: CaveGenerator, b: CaveGenerator) -> void:
	var zone := {"a": a, "b": b, "kick_ends": {}, "mouths": {}, "eggs": {}}
	var top_kick := _kick_end(a, a.exit_lanes.min())
	# tremplins et rampes d'accueil : construits par les cavernes (angles θ / φ)
	for l in a.exit_lanes:
		zone.kick_ends[l] = _kick_end(a, l)
	for l in b.entry_lanes:
		zone.mouths[l] = _entry_start(b, l)
	# une sortie qui PLONGE (φ > 8) vers une entrée PAR EN DESSOUS (θ < 8) du
	# même étage : virage en U entre les deux
	for l in a.exit_lanes:
		if b.entry_lanes.has(l) and a.exit_tips[l].heading > 8.0 and b.entry_tips[l].heading < 8.0:
			_add_u_pipe(a.position + a.exit_tips[l].pos, a.exit_tips[l].heading,
				b.position + b.entry_tips[l].pos, b.entry_tips[l].heading)
	# échelle d'œufs : un œuf par sortie sauf la plus haute (pour monter)
	var zi := void_zones.size() + 1
	for l in a.exit_lanes:
		if l == a.exit_lanes.min() or a.exit_tips[l].heading > 8.0:
			continue
		var name := "vide%d_oeuf%d" % [zi, l]
		_add_egg(name, zone.kick_ends[l] + LADDER_EGG)
		zone.eggs[l] = name
	# balançoires au-dessus de l'étage du haut (prendre de la vitesse)
	_add_egg("vide%d_haut1" % zi, top_kick + Vector2(1000.0, -800.0))
	_add_egg("vide%d_haut2" % zi, top_kick + Vector2(1900.0, -800.0))
	# rectangle de la zone (caméra, bot)
	var x0 := _exit_end(a, a.exit_lanes.min()).x
	var x1 := _entry_start(b, b.entry_lanes.min()).x
	zone.rect = Rect2(x0, top_kick.y - 2500.0, x1 - x0, 9000.0)
	void_zones.append(zone)


## Passage à l'air libre entre la caverne `a` (sorties) et `b` (entrées).
func _add_passage(a: CaveGenerator, b: CaveGenerator) -> void:
	var low: int = a.exit_lanes.max()
	for l in a.exit_lanes:
		if l == low:
			continue
		var x := _exit_end(a, l)
		_add_ledge(x, x + Vector2(EXIT_LEDGE, -25.0))      # petite lèvre pour sauter
	for l in b.entry_lanes:
		if l == low:
			continue
		var e := _entry_start(b, l)
		_add_ledge(e - Vector2(BALCONY, 0), e)
	# étage le plus bas : un sol continu de la sortie à l'entrée (on y retombe)
	var xs := _exit_end(a, low)
	var es := _entry_start(b, low)
	var mid := (xs + es) * 0.5 + Vector2(0, 220.0)
	var fl := _join(_hermite(xs, mid, 8.0, 0.0, 10), _hermite(mid, es, 0.0, 8.0, 10))
	var poly := fl.duplicate()
	poly.append(Vector2(es.x, es.y + 4000.0))
	poly.append(Vector2(xs.x, xs.y + 4000.0))
	_add_body(poly, [fl], 2)


## [1.66] Virage en U entre une sortie qui plonge (p0, cap h0 > 0) et une
## entrée par en dessous (p1 = début de son tube, cap h1 < 0) : descente
## droite, virage vers le plat, fond droit, virage vers le haut, montée droite
## avec boosts (PipeBend partout). On cherche les longueurs droites qui
## raccordent les deux bouts ; montée de 700 px si possible, moins sinon.
func _add_u_pipe(p0: Vector2, h0: float, p1: Vector2, h1: float) -> void:
	var r1 := 500.0
	var r2 := 500.0
	var u1 := Vector2.from_angle(deg_to_rad(h0))
	var u2 := Vector2.from_angle(deg_to_rad(h1))
	var arc1 := PipeBend.arc(Vector2.ZERO, h0, -h0, r1)
	var arc2 := PipeBend.arc(Vector2.ZERO, 0.0, h1, r2)
	var d1 := arc1[arc1.size() - 1]
	var d2 := arc2[arc2.size() - 1]
	var l2 := 700.0
	var l1 := 0.0
	var lb := -1.0
	while l2 >= 0.0:
		var rest := p1 - p0 - d1 - d2 - u2 * l2
		l1 = rest.y / u1.y
		lb = rest.x - l1 * u1.x
		if l1 >= 0.0 and lb >= 0.0:
			break
		l2 -= 50.0
	if l1 < 0.0 or lb < 0.0:
		push_warning("[GRUYÈRE] virage en U impossible entre %s et %s" % [p0, p1])
		return
	var a := p0 + u1 * l1
	var b := a + d1
	var c := b + Vector2(lb, 0.0)
	var d := c + d2
	var line := PipeBend.join([PackedVector2Array([p0, a]), PipeBend.arc(a, h0, -h0, r1),
		PackedVector2Array([b, c]), PipeBend.arc(c, 0.0, h1, r2), PackedVector2Array([d, p1])])
	_add_slab(line, 260.0)
	for bz in PipeBend.boosts_along(line, 360.0, 2.5, 150.0):
		_add_boost_node(bz)
	u_pipes.append(line)
	print("[GRUYÈRE] virage en U : descente %d, fond %d, montée %d" % [l1, lb, l2])


var u_pipes: Array = []        # [1.66] virages en U (bot, images)


## Fin : half-pipe entre les deux sorties de la dernière caverne.
## [1.66] Retour de test : « finir par une montée avec un boost plutôt qu'un
## grappin si on arrive d'en bas ». La sortie du BAS file sur une RAMPE
## (virages PipeBend : creux, montée droite à 28°, arrondi sur le deck) avec
## des boosts ; elle arrive pile sur le deck gauche du half-pipe. La sortie
## du HAUT a toujours son rebord et se laisse tomber dans le half-pipe.
const FINAL_RAMP_DEG := 28.0
func _add_final(g: CaveGenerator) -> void:
	var x0 := _exit_end(g, 0)
	var x1 := _exit_end(g, 1)
	var hp = half_pipe_res.instantiate()
	var hp_w: float = hp.map_width
	var deck_y := x0.y + 350.0
	# --- rampe de la sortie du bas : creux (virage vers le haut), montée
	# droite, puis arrondi (virage vers le bas) qui se pose sur le deck
	var bend1 := PipeBend.join([PipeBend.straight(x1, 8.0, 250.0),
		PipeBend.arc(x1 + Vector2.from_angle(deg_to_rad(8.0)) * 250.0, 8.0, -(8.0 + FINAL_RAMP_DEG), 900.0)])
	var p1 := bend1[bend1.size() - 1]
	var r2 := 450.0
	var top_rise := r2 * (1.0 - cos(deg_to_rad(FINAL_RAMP_DEG)))
	var climb_len := (p1.y - top_rise - deck_y) / sin(deg_to_rad(FINAL_RAMP_DEG))
	var line := PipeBend.join([bend1, PipeBend.straight(p1, -FINAL_RAMP_DEG, climb_len)])
	var p2 := line[line.size() - 1]
	line = PipeBend.join([line, PipeBend.arc(p2, -FINAL_RAMP_DEG, FINAL_RAMP_DEG, r2)])
	var hx: float = line[line.size() - 1].x
	# la sortie du haut doit avoir la place de tomber dans le half-pipe
	hx = maxf(hx, x0.x + FINAL_LEDGE + 350.0)
	hp_x = hx
	hp_deck_y = deck_y
	hp.with_finish = false
	hp.position = Vector2(hx, deck_y + 512.0)
	add_child(hp)
	# raccord exact : le dernier point de la rampe est le coin du deck
	line[line.size() - 1] = Vector2(hx, deck_y)
	var poly := line.duplicate()
	poly.append(Vector2(hx, x1.y + 4000.0))
	poly.append(Vector2(x1.x, x1.y + 4000.0))
	_add_body(poly, [line], 2)
	# boosts de la montée (couleur = force, selon la pente)
	for bz in PipeBend.boosts_along(line, 380.0, 2.5, 200.0):
		_add_boost_node(bz)
	final_ramp = line
	# sortie du haut : un rebord, puis on se laisse tomber dans le half-pipe
	_add_ledge(x0, x0 + Vector2(FINAL_LEDGE, -40.0))
	hp_holds = []
	# arche : sur le deck gauche ; bande haute (on arrive aussi en tombant)
	finish_x = hx + 260.0
	var gate = finish_gate_res.instantiate()
	gate.position = Vector2(finish_x, deck_y)
	gate.finish_band_height = 2200.0
	add_child(gate)
	# mur au bout du half-pipe (on ne le survole pas)
	var wx: float = hx + hp_w
	_add_body(PackedVector2Array([Vector2(wx, deck_y - 3000.0), Vector2(wx + 600.0, deck_y - 3000.0),
		Vector2(wx + 600.0, deck_y + 5000.0), Vector2(wx, deck_y + 5000.0)]), [], 2)
	print("[GRUYÈRE] half-pipe en ", hp.position, " ; arche x = ", finish_x)


var final_ramp := PackedVector2Array()   # [1.66] rampe finale (bot)
const BOOST_SCENE := preload("res://src/levels/boost/BoostArea.tscn")


## [1.66] Pose un boost (format {pos, rot, strength, scale, air}).
func _add_boost_node(bz: Dictionary) -> void:
	var ba = BOOST_SCENE.instantiate()
	ba.position = bz.pos
	ba.rotation_degrees = bz.rot
	ba.boost_strength = bz.strength
	ba.arrow_scale = bz.scale
	ba.in_air = bz.air
	ba.z_index = 5
	add_child(ba)


# =============================================================================
#  Points de passage, caméra
# =============================================================================
func _physics_process(_delta: float) -> void:
	var p = get_tree().get_first_node_in_group("player")
	if p == null or p._respawning:
		return
	var pos: Vector2 = p.global_position
	var next := _cp + 1
	if next < checkpoints.size() and p.is_on_ground and pos.x > checkpoints[next].x:
		_cp = next
		print("[GRUYÈRE] point de passage : ", checkpoints[_cp].name)
	_cave_checkpoints(p, pos)
	_update_camera_focus(p)


## [CAVERNES 1.63] Dans les cavernes, le point de passage est le dernier
## CARREFOUR (nœud) touché au sol : on réapparaît sur la route qu'on avait
## prise, juste après le carrefour. Un PUITS (trou sans galerie dessous) fait
## réapparaître là.
func _cave_checkpoints(p, pos: Vector2) -> void:
	for g in caves:
		var lp: Vector2 = pos - g.position
		if lp.x < -CaveGenerator.STUB - 50.0 or lp.x > g.columns * CaveGenerator.COL_W + CaveGenerator.STUB + 50.0:
			continue
		for r in g.pits:
			if r.has_point(lp):
				print("[GRUYÈRE] puits : réapparition au dernier carrefour")
				p.die()
				return
		if not p.is_on_ground:
			continue
		for k in g.active:
			var s: PackedStringArray = k.split(":")
			var c := int(s[0])
			var l := int(s[1])
			if c >= g.columns:
				continue
			var n: Vector2 = g.node_pos(c, l)
			if lp.x > n.x - 100.0 and lp.x < n.x + 300.0 and absf(lp.y - n.y) < 160.0:
				var key := "%s:%s" % [g.name, k]
				if cave_cp == null or cave_cp.key != key:
					cave_cp = {"key": key, "pos": g.position + n + Vector2(140.0, -70.0), "vel": Vector2(700.0, 0.0), "cave": g, "c": c, "l": l}
					print("[GRUYÈRE] carrefour : ", key)


## Caméra : dans une zone de grand saut (cadres rouges du croquis), on garde
## l'arrivée (ou l'œuf) dans le cadre ; ailleurs, la caméra adaptative normale.
func _update_camera_focus(p) -> void:
	if not ("focus_point" in p.camera):
		return
	var pos: Vector2 = p.global_position
	var target = null
	for z in jump_zones:
		if z.rect.has_point(pos) and pos.x < z.target.x + 200.0:
			target = z.target
			break
	var target2 = null
	var min_zoom := 0.4
	if target == null:
		var vf := _void_focus(pos)
		if vf[0] != null:
			target = vf[0]
			target2 = vf[1]
			min_zoom = 0.33     # [1.66] le vide est large : on voit l'autre rive
	if target == null:
		var cf := _cave_focus(pos)
		target = cf[0]
		target2 = cf[1]
	p.camera.focus_min_zoom = min_zoom if target != null else p.camera.FOCUS_MIN_ZOOM
	p.camera.focus_point = target
	if "focus_point2" in p.camera:
		p.camera.focus_point2 = target2


## [CAVERNES 1.64] Dans une caverne, la caméra dézoome pour montrer la
## galerie du DESSUS et celle du DESSOUS (demande de l'équipe) : on garde dans
## le cadre les carrefours de la colonne suivante sur les étages voisins
## (ceux qui existent). Pas de dézoom s'il n'y a qu'une galerie à cet endroit.
## Le cadre change seulement d'une colonne à l'autre (pas de zoom qui pompe).
func _cave_focus(pos: Vector2) -> Array:
	for g in caves:
		var lp: Vector2 = pos - g.position
		if lp.x < 0.0 or lp.x >= g.columns * CaveGenerator.COL_W:
			continue
		var c := int(lp.x / CaveGenerator.COL_W)
		var base: float = lp.x * CaveGenerator.DROP / CaveGenerator.COL_W
		var l := clampi(roundi((lp.y - base + 150.0) / CaveGenerator.LANE_GAP), 0, g.lanes_n - 1)
		var up = null
		var down = null
		var mid := Vector2(0.0, -CaveGenerator.TUNNEL_H * 0.5)
		if l > 0 and g.active.has("%d:%d" % [c + 1, l - 1]):
			up = g.position + g.node_pos(c + 1, l - 1) + mid
		if l < g.lanes_n - 1 and g.active.has("%d:%d" % [c + 1, l + 1]):
			down = g.position + g.node_pos(c + 1, l + 1) + mid
		# [1.66] retour de test : « tout en bas, la caméra ne montre pas tout le
		# chemin du bas ». Quand il n'y a pas de galerie dessous, on garde dans
		# le cadre le SOL de sa propre galerie un peu plus loin (et 260 px
		# en dessous : les trous sur le vide se voient)
		if down == null:
			down = g.position + g.node_pos(c + 1, l) + Vector2(0.0, 260.0)
		if up == null:
			return [down, null]
		return [up, down]
	return [null, null]


## [1.66] Dans une zone de vide : la caméra garde dans le cadre l'entrée
## « en face » (rampe d'accueil) et l'œuf de l'étage (pour monter).
func _void_focus(pos: Vector2) -> Array:
	for z in void_zones:
		if not z.rect.has_point(pos):
			continue
		# étage : le tremplin le plus bas qui est encore au-dessus de Pinpouin
		# (+300 px de marge : juste après le saut, on est un peu sous le bout)
		var lane: int = z.kick_ends.keys().min()
		for l in z.kick_ends:
			if z.kick_ends[l].y <= pos.y + 300.0 and l > lane:
				lane = l
		var mouth = null
		for l in z.mouths:
			if l >= lane and (mouth == null or l < mouth[0]):
				mouth = [l, z.mouths[l]]
		var egg = null
		if z.eggs.has(lane):
			egg = holds[z.eggs[lane]]
		if mouth == null:
			return [egg, null]
		return [mouth[1] + Vector2(-300.0, -250.0), egg]
	return [null, null]


## Appelé par Player._pick_respawn_sample : point de passage atteint en dernier.
func respawn_sample(_pos: Vector2):
	if RaceManager.bonus_active or RaceManager.free_ride:
		return null
	if cave_cp != null:
		return {"pos": cave_cp.pos, "vel": cave_cp.vel}
	var c: Dictionary = checkpoints[_cp]
	return {"pos": c.pos, "vel": c.vel}


## [MODE ENFANT] tout le parcours va vers la droite.
func forward_dir(_pos: Vector2) -> float:
	return 1.0


func progress(pos: Vector2) -> float:
	return pos.x


func kid_skip() -> void:
	# [CAVERNES 1.63] dans une caverne : carrefour suivant sur le même étage
	# (sinon n'importe quel carrefour de la colonne suivante)
	if cave_cp != null:
		var g = cave_cp.cave
		var c: int = cave_cp.c + 1
		if c < g.columns:
			var l: int = cave_cp.l
			if not g.active.has("%d:%d" % [c, l]):
				for l2 in g.lanes_n:
					if g.active.has("%d:%d" % [c, l2]):
						l = l2
						break
			cave_cp = {"key": "%s:%d:%d" % [g.name, c, l], "pos": g.position + g.node_pos(c, l) + Vector2(140.0, -70.0), "vel": Vector2(700.0, 0.0), "cave": g, "c": c, "l": l}
		return
	if _cp + 1 < checkpoints.size():
		_cp += 1


func current_checkpoint() -> int:
	return _cp
