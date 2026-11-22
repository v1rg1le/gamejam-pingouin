extends Node2D
# =============================================================================
#  EggGenerator.gd — [ŒUF 1.59] niveau « Le Half-Pipe de l'œuf » (MAQUETTE)
# -----------------------------------------------------------------------------
#  Niveau imaginé par l'équipe (croquis « Level_Egg_V2 », 22/11), plan v3
#  validé : un seul tour d'environ 3 minutes autour d'un grand œuf de glace,
#  sans retour possible (mur derrière le départ, paroi fermée jusqu'à l'œuf).
#
#  VUE DE CÔTÉ (gravité vers le bas). Toute la géométrie est calculée ici, à
#  partir de quelques constantes (taille de l'œuf, du couloir, des trous…) :
#  aucune scène dessinée à la main, aucun nouvel asset (mêmes couleurs et
#  même bordure de glace que les sols existants, prises = boules de glace du
#  tuto, half-pipe = HalfPipe.tscn existant).
#
#  LE PARCOURS (sens des aiguilles d'une montre) :
#   1. DÉPART sur une plateforme en haut. À gauche : un mur jusqu'au plafond
#      (pas de retour à gauche). À droite : la plateforme se prolonge en
#      TOBOGGAN qui rejoint l'épaule de l'œuf (la « paroi ajoutée » du plan
#      v3 : on ne peut pas passer dessous vers le half-pipe).
#   2. DESCENTE À DROITE : tremplins posés sur le toboggan et l'épaule de
#      l'œuf ; ils lancent Pinpouin vers la paroi extérieure, qu'il longe
#      jusqu'au BOL du bas (coin arrondi).
#   3. LE BAS, VERS LA GAUCHE : trois trous qui tombent dans le VIDE
#      (puits) : un saut (avec un tremplin au bord), un balancier (prise au
#      bout d'une stalactite qui pend sous l'œuf), un grappin double (deux
#      stalactites).
#   4. LA CHEMINÉE : le bol de gauche fait remonter le long de la paroi
#      gauche ; un pilier forme une cheminée ; on grimpe en zigzag de prise
#      en prise (calcul repris de l'atelier CHEMINÉE du tuto) jusqu'à une
#      petite galerie de sortie ouverte à droite.
#   5. LE DOS DE L'ŒUF : un pont part du haut du pilier vers la droite, puis
#      un PLAFOND suspendu au-dessus du vide (deux prises) mène au sommet de
#      l'œuf. Tomber sous le pont = réapparition au début du pont (sinon on
#      glisserait jusqu'en bas de la cheminée).
#   6. ARRIVÉE au bord de la FENTE creusée dans le haut de l'œuf, puis chute
#      dans le HALF-PIPE au cœur de l'œuf (30 s de figures bonus en Score,
#      glisse libre en Chill : règles de RaceManager inchangées).
#
#  RÉAPPARITIONS : des points de passage (CHECKPOINTS) le long du tour. Une
#  chute (vide, ou sous le pont) fait réapparaître au dernier point atteint
#  (Player._pick_respawn_sample interroge ce nœud, groupe
#  « course_checkpoints », comme il le fait déjà pour le tuto et le Sans fin).
#
#  MODE ENFANT : le bas se parcourt vers la GAUCHE ; KidAssist demande à ce
#  nœud le sens « vers l'avant » (forward_dir) et l'avancement (progress)
#  au lieu de supposer « toujours vers la droite ».
#
#  Coordonnées : celles de Godot (y vers le BAS). Le centre de l'œuf est en
#  (0, 0). Unités : px.
# =============================================================================

const ICE_COLOR := Color(0.694118, 0.862745, 0.956863, 1)   # même bleu que sol.tscn (l'œuf, les tremplins)
## [ŒUF 1.59] maquette : la grotte, le départ, le pilier, le pont et les
## stalactites sont d'un bleu plus sombre, pour qu'on lise bien les parois
## sur le fond (le bleu clair de la glace se confondait avec le ciel clair).
const ROCK_COLOR := Color(0.36, 0.52, 0.70, 1)
const RIM_COLOR := Color(0.16, 0.36, 0.60, 1)   # contour de toutes les surfaces
const RIM_WIDTH := 14.0
const EDGE_TEXTURE := preload("res://sprites/levels/tiles/tile_ice_up_long1.png")
var half_pipe_res = preload("res://src/levels/GroundGenerator/HalfPipe.tscn")
var finish_gate_res = preload("res://src/levels/FinishGate.tscn")

# --- L'œuf (ellipse un peu plus étroite en haut : forme d'œuf) ---------------
const EGG_A := 10000.0        # demi-largeur
const EGG_B := 4000.0         # demi-hauteur
const EGG_K := 0.13           # resserrement du haut (0 = ellipse)

# --- La « grotte » autour de l'œuf (rectangle aux coins arrondis) -----------
const OUT_L := -13600.0       # paroi gauche
const OUT_R := 13600.0        # paroi droite
const OUT_TOP := -7800.0      # plafond
const OUT_BOT := 6800.0       # sol du bas
const R_TOP := 2500.0         # rayon des coins du haut
const R_BOT := 4500.0         # rayon du coin bas-droit (le grand « bol » d'arrivée de la descente)
const R_BL := 2500.0          # rayon du coin bas-gauche, plus serré : l'élan du bas fait
                              # monter Pinpouin jusque DANS la cheminée (à gauche du pilier)
const FAR := 40000.0          # le sol extérieur est rempli jusque-là (rien ne se voit au-delà)
const SHAFT_DEPTH := 3500.0   # profondeur des parois des puits (collision) ; dessous : le vide

# --- 1. Départ ----------------------------------------------------------------
const START_WALL_X0 := -600.0  # mur derrière le départ (gauche)
const START_WALL_X1 := 400.0
const PLATFORM_Y := -6400.0    # dessus de la plateforme de départ
const PLATFORM_END_X := 4800.0 # fin de la pente de départ, début du toboggan
const PLATFORM_DROP := 450.0   # la plateforme descend de ça (pente d'élan, ~6°)
const MASSIF_UNDER_Y := -6050.0 # dessous de la plateforme (au-dessus de la fente ; sous le dessus de la pente)
const SLIDE_END_X := 7400.0    # le toboggan rejoint l'œuf ici

# --- 2. Tremplins (abscisse le long des surfaces) ---------------------------
const KICK_H := 170.0          # hauteur d'un tremplin
const KICK_LIP_DEG := 22.0     # angle ajouté au bord (par rapport à la pente)

# --- 3. Les trous du bas : [centre x, largeur, nombre de stalactites] -------
const GAPS := [[5600.0, 900.0, 0], [1200.0, 2200.0, 1], [-6200.0, 3400.0, 2]]
const HOLD_RADIUS := 55.0      # boule de glace (comme les prises du tuto)
const STALACTITE_HOLD_UP := 850.0 # prise à 850 px au-dessus du sol : à portée (1200) à 45°

# --- 4. Cheminée ----------------------------------------------------------------
const CH_WIDTH := 850.0        # largeur du couloir de la cheminée
const PILLAR_W := 700.0        # épaisseur du pilier
const CH_HANG := Vector2(60, 140) # où Pinpouin arrive sous une prise en tirant (comme le tuto)
const CH_EMBED := 15.0         # prises encastrées dans les parois (retour 1.57)
const CH_LOWEST_Y := 4100.0    # on arrête les prises sous cette hauteur (dans le bol, à portée
                               # depuis l'endroit où l'élan du bas fait remonter Pinpouin)
const GALLERY_H := 380.0       # hauteur de la galerie de sortie
const GALLERY_L := 1300.0      # longueur du plafond de la galerie après le bord du pilier

# --- 5. Pont et plafond -------------------------------------------------------
const BRIDGE_Y := -4800.0      # dessus du pont (au-dessus du sommet de l'œuf, -4000)
const BRIDGE_END_X := -6200.0  # fin du pont
const BRIDGE_DROP := 650.0     # le pont descend de ça vers la droite (on y reprend de l'élan)
const CEIL_X0 := -6700.0       # plafond suspendu au-dessus du vide
const CEIL_X1 := -1300.0
const CEIL_UNDER := 800.0      # dessous du plafond, au-dessus du BOUT du pont
const BRIDGE_FALL_Y := -2600.0 # sous cette hauteur (côté gauche) = chute : réapparition

# --- 6. Fente + half-pipe -----------------------------------------------------
const SLOT_X0 := 1000.0        # bord gauche de la fente (l'arrivée est juste avant)
const SLOT_DROP := 1500.0      # chute du bord de la fente jusqu'aux decks du half-pipe

var spawn_point := Vector2.ZERO
var finish_x := 0.0
var checkpoints: Array = []    # [{pos, vel, name}] dans l'ordre du parcours
var _cp := 0                   # dernier point atteint (index)
var holds := {}                # nom -> centre (pour les bots et les captures)
var _egg_top := PackedVector2Array()     # dessus de l'œuf (x décroissant)
var _egg_bottom := PackedVector2Array()  # dessous de l'œuf (x croissant)


func _init() -> void:
	add_to_group("course_checkpoints")   # Player._pick_respawn_sample nous trouve par ce groupe
	add_to_group("course_direction")     # KidAssist (mode enfant) aussi


func _ready() -> void:
	_build_egg_profile()
	var slot_x1: float = SLOT_X0 + _half_pipe_width() + 2.0
	_add_outer_cave()
	_add_egg(SLOT_X0, slot_x1)
	_add_start_massif(slot_x1)
	_add_kickers()
	_add_gaps_and_stalactites()
	_add_chimney_and_bridge()
	_add_ceiling()
	_add_finish_and_half_pipe(slot_x1)
	_define_checkpoints()
	get_parent()._set_spawn_position(spawn_point)


# =============================================================================
#  Outils de géométrie
# =============================================================================

## Point de l'œuf pour l'angle t (t = 90° : sommet, y vers le bas).
func _egg_point(t: float) -> Vector2:
	var s := sin(t)
	return Vector2(EGG_A * cos(t) * (1.0 - EGG_K * s), -EGG_B * s)


func _build_egg_profile() -> void:
	var n := 720
	for i in n + 1:
		_egg_top.append(_egg_point(PI * i / n))           # de x = +A à x = -A (dessus)
		_egg_bottom.append(_egg_point(PI + PI * i / n))  # de x = -A à x = +A (dessous)


## Hauteur (y) du DESSUS de l'œuf à l'abscisse x.
func egg_top_y(x: float) -> float:
	return _profile_y(_egg_top, x)


## Hauteur (y) du DESSOUS de l'œuf à l'abscisse x.
func egg_bottom_y(x: float) -> float:
	return _profile_y(_egg_bottom, x)


func _profile_y(pts: PackedVector2Array, x: float) -> float:
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		if (x - a.x) * (x - b.x) <= 0.0 and a.x != b.x:
			return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return 0.0


## Corps de glace : remplissage + collision en SEGMENTS (contour seul, comme
## tous les sols du jeu depuis le correctif « vitesse -> 0 ») + bordures de
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
	var rim := Line2D.new()          # contour lisible (maquette)
	rim.points = poly
	rim.closed = true
	rim.width = RIM_WIDTH
	rim.default_color = RIM_COLOR
	body.add_child(rim)
	for e in edges:
		_add_edge(body, e)
	add_child(body)
	return body


## Remplissage seul (sans collision) : sol extérieur loin des surfaces jouées.
func _add_fill(poly: PackedVector2Array) -> void:
	var fill := Polygon2D.new()
	fill.color = ROCK_COLOR
	fill.polygon = poly
	add_child(fill)


## Bordure de glace (même rendu que la piste, voir BateauGenerator._add_edge).
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


## Prise de grappin : boule de glace (même dessin que les prises du tuto).
func _add_hold(name: String, center: Vector2) -> void:
	holds[name] = center
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.position = center
	body.z_index = 6
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HOLD_RADIUS
	shape.shape = circle
	body.add_child(shape)
	var pts := PackedVector2Array()
	for i in 24:
		pts.append(Vector2.from_angle(TAU * i / 24.0) * HOLD_RADIUS)
	var fill := Polygon2D.new()
	fill.color = ICE_COLOR
	fill.polygon = pts
	body.add_child(fill)
	var rim := Line2D.new()
	rim.points = pts
	rim.closed = true
	rim.width = 8.0
	rim.default_color = Color(0.25, 0.55, 0.85, 1)
	body.add_child(rim)
	add_child(body)


## Arc de cercle (centre c, rayon r, de l'angle a0 à a1, en degrés).
func _arc(c: Vector2, r: float, a0: float, a1: float, steps := 24) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in steps + 1:
		out.append(c + Vector2.from_angle(deg_to_rad(lerpf(a0, a1, float(i) / steps))) * r)
	return out


# =============================================================================
#  La grotte : sol extérieur (rectangle aux coins arrondis) + puits du vide
# =============================================================================
func _add_outer_cave() -> void:
	var tl := Vector2(OUT_L + R_TOP, OUT_TOP + R_TOP)   # centres des arcs
	var tr := Vector2(OUT_R - R_TOP, OUT_TOP + R_TOP)
	var br := Vector2(OUT_R - R_BOT, OUT_BOT - R_BOT)
	var bl := Vector2(OUT_L + R_BL, OUT_BOT - R_BL)
	# --- contour intérieur (ce que touche Pinpouin), dans le sens des aiguilles
	var arc_tr := _arc(tr, R_TOP, -90, 0)
	var arc_br := _arc(br, R_BOT, 0, 90, 32)
	var arc_bl := _arc(bl, R_BL, 90, 180, 32)
	var arc_tl := _arc(tl, R_TOP, 180, 270)
	# chaîne : sol du bas d'abord découpé par les puits
	var segs := PackedVector2Array()
	var chain := PackedVector2Array()
	chain.append_array(arc_tl)
	chain.append_array(arc_tr)
	chain.append_array(arc_br)
	# sol du bas, de droite à gauche, avec les puits
	var bottom_pts := PackedVector2Array()
	var gx_sorted := GAPS.duplicate()
	gx_sorted.sort_custom(func(a, b): return a[0] > b[0])   # de droite à gauche
	chain.append(Vector2(OUT_R - R_BOT, OUT_BOT))
	for g in gx_sorted:
		var x_right: float = g[0] + g[1] * 0.5
		var x_left: float = g[0] - g[1] * 0.5
		chain.append(Vector2(x_right, OUT_BOT))
		chain.append(Vector2(x_right, OUT_BOT + SHAFT_DEPTH))   # paroi droite du puits
		_chain_to_segments(chain, segs)
		chain = PackedVector2Array([Vector2(x_left, OUT_BOT + SHAFT_DEPTH), Vector2(x_left, OUT_BOT)])
	chain.append(Vector2(OUT_L + R_BL, OUT_BOT))
	chain.append_array(arc_bl)
	chain.append(arc_tl[0])                                     # paroi gauche jusqu'au coin du haut
	_chain_to_segments(chain, segs)
	var body := StaticBody2D.new()
	body.collision_layer = 2
	var shape := CollisionShape2D.new()
	var concave := ConcavePolygonShape2D.new()
	concave.segments = segs
	shape.shape = concave
	body.add_child(shape)
	add_child(body)
	for i in range(0, segs.size(), 2):     # contour lisible (maquette)
		var rim := Line2D.new()
		rim.points = PackedVector2Array([segs[i], segs[i + 1]])
		rim.width = RIM_WIDTH
		rim.default_color = RIM_COLOR
		rim.z_index = 1
		body.add_child(rim)
	# bordure de glace sur les sols (bols + sol du bas entre les puits)
	var floor_edges := []
	var right_floor := PackedVector2Array(arc_br)
	var cur := right_floor
	for g in gx_sorted:
		cur.append(Vector2(g[0] + g[1] * 0.5, OUT_BOT))
		floor_edges.append(cur)
		cur = PackedVector2Array([Vector2(g[0] - g[1] * 0.5, OUT_BOT)])
	cur.append(Vector2(OUT_L + R_BL, OUT_BOT))
	cur.append_array(arc_bl)
	floor_edges.append(cur)
	for e in floor_edges:
		_add_edge(body, e)
	# --- remplissage (sans collision) : bandes + coins
	_add_fill(PackedVector2Array([Vector2(-FAR, -FAR), Vector2(FAR, -FAR), Vector2(FAR, OUT_TOP), Vector2(-FAR, OUT_TOP)]))
	_add_fill(PackedVector2Array([Vector2(-FAR, OUT_TOP), Vector2(OUT_L, OUT_TOP), Vector2(OUT_L, FAR), Vector2(-FAR, FAR)]))
	_add_fill(PackedVector2Array([Vector2(OUT_R, OUT_TOP), Vector2(FAR, OUT_TOP), Vector2(FAR, FAR), Vector2(OUT_R, FAR)]))
	var gl := GAPS.duplicate()
	gl.sort_custom(func(a, b): return a[0] < b[0])               # de gauche à droite
	var x0 := OUT_L
	for g in gl:
		_add_fill(PackedVector2Array([Vector2(x0, OUT_BOT), Vector2(g[0] - g[1] * 0.5, OUT_BOT), Vector2(g[0] - g[1] * 0.5, FAR), Vector2(x0, FAR)]))
		x0 = g[0] + g[1] * 0.5
	_add_fill(PackedVector2Array([Vector2(x0, OUT_BOT), Vector2(OUT_R, OUT_BOT), Vector2(OUT_R, FAR), Vector2(x0, FAR)]))
	for corner in [[Vector2(OUT_L, OUT_TOP), arc_tl], [Vector2(OUT_R, OUT_TOP), arc_tr],
			[Vector2(OUT_R, OUT_BOT), arc_br], [Vector2(OUT_L, OUT_BOT), arc_bl]]:
		var p := PackedVector2Array([corner[0]])
		p.append_array(corner[1])
		_add_fill(p)


func _chain_to_segments(chain: PackedVector2Array, segs: PackedVector2Array) -> void:
	for i in chain.size() - 1:
		segs.append(chain[i])
		segs.append(chain[i + 1])


# =============================================================================
#  L'œuf, avec la fente du half-pipe creusée dans son sommet
# =============================================================================
func _add_egg(slot_x0: float, slot_x1: float) -> void:
	var slot_bottom: float = egg_top_y(slot_x0) + SLOT_DROP + 512.0 + 700.0   # sous le socle du half-pipe
	var poly := PackedVector2Array()
	var top_edge_r := PackedVector2Array()   # dessus de l'œuf à droite de la fente
	var top_edge_l := PackedVector2Array()   # dessus de l'œuf à gauche de la fente
	var notch_done := false
	for p in _egg_top:                       # x décroissant : de la droite vers la gauche
		if p.x < slot_x1 and p.x > slot_x0:
			if not notch_done:
				notch_done = true
				poly.append(Vector2(slot_x1, egg_top_y(slot_x1)))
				poly.append(Vector2(slot_x1, slot_bottom))
				poly.append(Vector2(slot_x0, slot_bottom))
				poly.append(Vector2(slot_x0, egg_top_y(slot_x0)))
			continue
		poly.append(p)
		if p.y < -EGG_B * 0.15:              # bordure sur le dessus seulement
			if p.x >= slot_x1:
				top_edge_r.append(p)
			else:
				top_edge_l.append(p)
	for i in range(1, _egg_bottom.size() - 1):
		poly.append(_egg_bottom[i])
	_add_body(poly, [top_edge_r, top_edge_l], 0, ICE_COLOR)


func _half_pipe_width() -> float:
	var hp = half_pipe_res.instantiate()
	var w: float = hp.map_width
	hp.free()
	return w


# =============================================================================
#  1. Départ : mur à gauche, plateforme, toboggan jusqu'à l'épaule de l'œuf
#  (un seul bloc : la zone sous la plateforme est pleine, donc aucun chemin
#  vers la fente depuis le départ).
# =============================================================================
func _add_start_massif(slot_x1: float) -> void:
	var poly := PackedVector2Array()
	poly.append(Vector2(START_WALL_X0, OUT_TOP - 300.0))
	poly.append(Vector2(START_WALL_X1, OUT_TOP - 300.0))
	var top := PackedVector2Array()
	top.append(Vector2(START_WALL_X1, PLATFORM_Y))
	# pente d'élan (courbe douce : plate au départ, ~10° à la fin)
	for i in range(1, 21):
		var s := float(i) / 20.0
		top.append(Vector2(lerpf(START_WALL_X1, PLATFORM_END_X, s), PLATFORM_Y + PLATFORM_DROP * s * s))
	# toboggan : courbe de Bézier cubique du bout de la pente jusqu'à l'œuf,
	# tangente aux deux bouts (même pente que l'œuf au point d'arrivée :
	# aucune cassure), plus raide au milieu.
	var p0 := Vector2(PLATFORM_END_X, PLATFORM_Y + PLATFORM_DROP)
	var p1 := Vector2(SLIDE_END_X, egg_top_y(SLIDE_END_X))
	var d0 := Vector2(1.0, 2.0 * PLATFORM_DROP / (PLATFORM_END_X - START_WALL_X1)).normalized()
	var d1 := Vector2(1.0, (egg_top_y(SLIDE_END_X + 5.0) - egg_top_y(SLIDE_END_X - 5.0)) / 10.0).normalized()
	var k := p0.distance_to(p1) * 0.35
	var c0 := p0 + d0 * k
	var c1 := p1 - d1 * k
	var steps := 40
	for i in range(1, steps + 1):
		var s := float(i) / steps
		var u := 1.0 - s
		top.append(p0 * (u * u * u) + c0 * (3.0 * u * u * s) + c1 * (3.0 * u * s * s) + p1 * (s * s * s))
	poly.append_array(top)
	_slide = top
	# retour le long du dessus de l'œuf, jusqu'au bord droit de la fente
	var x := SLIDE_END_X - 100.0
	while x > slot_x1:
		poly.append(Vector2(x, egg_top_y(x)))
		x -= 100.0
	poly.append(Vector2(slot_x1, egg_top_y(slot_x1)))
	poly.append(Vector2(slot_x1, MASSIF_UNDER_Y))
	poly.append(Vector2(START_WALL_X0, MASSIF_UNDER_Y))
	_add_body(poly, [top], 4)
	spawn_point = Vector2(START_WALL_X1 + 600.0, PLATFORM_Y - 80.0)

var _slide := PackedVector2Array()   # dessus de la plateforme + toboggan (pour les tremplins)


# =============================================================================
#  2. Tremplins : sur le toboggan, sur l'épaule de l'œuf, et au bord du 1er trou
# =============================================================================
## Tremplin posé sur une surface : profil en parabole qui part dans l'axe de
## la pente (pas de cassure à l'entrée) et se relève de KICK_LIP_DEG au bord.
## `p` : pied du tremplin, `d` : direction de la descente (unitaire).
func _add_kicker(p: Vector2, d: Vector2) -> void:
	var n := Vector2(d.y, -d.x)                       # normale « vers le haut » de la surface
	if n.y > 0.0:
		n = -n
	var w := 2.0 * KICK_H / tan(deg_to_rad(KICK_LIP_DEG))
	var top := PackedVector2Array()
	var poly := PackedVector2Array()
	for i in 17:
		var s := float(i) / 16.0
		top.append(p + d * (s * w) + n * (KICK_H * s * s))
	poly.append_array(top)
	poly.append(p + d * w - n * 60.0)                 # bord : retour dans la surface
	poly.append(p - n * 60.0)
	_add_body(poly, [top], 5, ICE_COLOR)


func _add_kickers() -> void:
	# sur le toboggan (à 55 % de sa longueur) et sur l'épaule de l'œuf
	var i := int(_slide.size() * 0.55)
	_add_kicker(_slide[i], (_slide[i + 1] - _slide[i]).normalized())
	for kx in [8400.0, 9300.0]:
		var a := Vector2(kx, egg_top_y(kx))
		var b := Vector2(kx + 20.0, egg_top_y(kx + 20.0))
		_add_kicker(a, (b - a).normalized())
	# bord droit du 1er trou (le SAUT) : on va vers la gauche
	var g: Array = GAPS[0]
	var lip := Vector2(g[0] + g[1] * 0.5, OUT_BOT)
	var w := 2.0 * KICK_H / tan(deg_to_rad(KICK_LIP_DEG))
	_add_kicker(lip + Vector2(w, 0), Vector2(-1, 0))


# =============================================================================
#  3. Les trous du bas : stalactites (avec leur prise au bout) sous l'œuf
# =============================================================================
func _add_gaps_and_stalactites() -> void:
	for gi in GAPS.size():
		var g: Array = GAPS[gi]
		var n: int = g[2]
		for k in n:
			# une stalactite : au milieu du trou (balancier) ou à 1/4 et 3/4
			# (grappin double)
			var fx: float = 0.5 if n == 1 else (0.78 - 0.5 * k)
			var hx: float = g[0] + g[1] * (fx - 0.5)
			var tip := Vector2(hx, OUT_BOT - STALACTITE_HOLD_UP)
			var root_y := egg_bottom_y(hx) - 80.0
			var poly := PackedVector2Array([Vector2(hx - 260, root_y), Vector2(hx + 260, root_y),
				Vector2(hx + 90, tip.y - 120), Vector2(hx, tip.y - 40), Vector2(hx - 90, tip.y - 120)])
			_add_body(poly, [], 3)
			_add_hold("trou%d_%d" % [gi + 1, k + 1], tip)


# =============================================================================
#  4. Cheminée (paroi gauche + pilier) et 5. pont vers le sommet de l'œuf
# -----------------------------------------------------------------------------
#  Prises calculées DE HAUT EN BAS (même règle que l'atelier CHEMINÉE du
#  tuto, à l'envers) : la prise de sortie E est sous le plafond de la
#  galerie, juste après le bord du pilier ; chaque prise du dessous est
#  placée pour que, pendu sous elle (CH_HANG), la suivante soit dans l'axe
#  du grappin lancé sans viser (45° vers le haut). On s'arrête sous
#  CH_LOWEST_Y : plus bas, l'élan du bol fait monter tout seul.
# =============================================================================
func _add_chimney_and_bridge() -> void:
	var px0 := OUT_L + CH_WIDTH          # face gauche du pilier
	var px1 := px0 + PILLAR_W
	var roof_under := BRIDGE_Y - GALLERY_H
	var e := Vector2(px0 + 90.0, roof_under + CH_EMBED)
	var lx := OUT_L - CH_EMBED            # prise encastrée dans la paroi gauche
	var rx := px0 + CH_EMBED              # prise encastrée dans le pilier
	var list := []                        # de haut en bas
	var above := e
	var left_side := true                 # la prise sous E est à gauche
	while true:
		# à gauche : dans la paroi… qui devient le bol (arrondi) en bas
		var hx: float = rx
		if left_side:
			hx = lx
			var yb: float = above.y + 600.0
			if yb > OUT_BOT - R_BL:
				hx = _bowl_left_x(yb) - CH_EMBED
		var hang_x: float = hx + (CH_HANG.x if left_side else -CH_HANG.x)
		var hang_y: float = above.y + absf(above.x - hang_x)
		var h := Vector2(hx, hang_y - CH_HANG.y)
		if h.y > CH_LOWEST_Y or list.size() >= 14 or h.y < above.y + 200.0:
			break   # assez bas (ou garde-fou : jamais plus de 14 prises)
		list.append(h)
		above = h
		left_side = not left_side
	list.reverse()                        # de bas en haut
	for k in list.size():
		_add_hold("c%d" % (k + 1), list[k])
	_add_hold("sortie", e)
	# bas du pilier : juste sous sa prise la plus basse (on passe dessous en
	# remontant le bol, puis on entre dans la cheminée à gauche du pilier)
	var pillar_bottom := 0.0
	for h in list:
		if h.x > OUT_L + CH_WIDTH * 0.5:
			pillar_bottom = maxf(pillar_bottom, h.y + 160.0)
	# pilier + pont (un seul bloc en L)
	# dessus du pont : plat sur le pilier, puis une pente douce (courbe) vers la droite
	var top := PackedVector2Array([Vector2(px0, BRIDGE_Y)])
	for i in 21:
		var s := float(i) / 20.0
		top.append(Vector2(lerpf(px1, BRIDGE_END_X, s), BRIDGE_Y + BRIDGE_DROP * s * s))
	var end_y := BRIDGE_Y + BRIDGE_DROP
	var poly := PackedVector2Array([Vector2(px0, pillar_bottom)])
	poly.append_array(top)
	poly.append_array(PackedVector2Array([Vector2(BRIDGE_END_X + 60.0, end_y + 180.0),
		Vector2(BRIDGE_END_X - 80.0, end_y + 320.0), Vector2(px1, BRIDGE_Y + 420.0), Vector2(px1, pillar_bottom)]))
	_add_body(poly, [top], 3)
	# plafond de la galerie de sortie, accroché à la paroi gauche
	var roof := PackedVector2Array([Vector2(OUT_L - 200.0, roof_under - 160.0), Vector2(px0 + GALLERY_L, roof_under - 160.0),
		Vector2(px0 + GALLERY_L + 40.0, roof_under - 80.0), Vector2(px0 + GALLERY_L, roof_under), Vector2(OUT_L - 200.0, roof_under)])
	_add_body(roof, [], 3)
	_chimney = {"px0": px0, "px1": px1, "bottom": pillar_bottom}

var _chimney := {}


## x de la paroi du bol de gauche (coin arrondi du bas) à la hauteur y.
func _bowl_left_x(y: float) -> float:
	var c := Vector2(OUT_L + R_BL, OUT_BOT - R_BL)
	var dy := clampf(y - c.y, 0.0, R_BL)
	return c.x - sqrt(R_BL * R_BL - dy * dy)


# =============================================================================
#  5. Plafond suspendu au-dessus du vide, entre le pont et le sommet de l'œuf
# =============================================================================
func _add_ceiling() -> void:
	var under := BRIDGE_Y + BRIDGE_DROP - CEIL_UNDER
	var poly := PackedVector2Array([Vector2(CEIL_X0, under - 260.0), Vector2(CEIL_X1, under - 260.0),
		Vector2(CEIL_X1 + 60.0, under - 120.0), Vector2(CEIL_X1, under), Vector2(CEIL_X0, under), Vector2(CEIL_X0 - 60.0, under - 130.0)])
	_add_body(poly, [], 3)
	_add_hold("plafond1", Vector2(-5500.0, under + CH_EMBED))
	_add_hold("plafond2", Vector2(-3000.0, under + CH_EMBED))


# =============================================================================
#  6. Arrivée au bord de la fente, half-pipe au fond
# =============================================================================
func _add_finish_and_half_pipe(slot_x1: float) -> void:
	var lip_y := egg_top_y(SLOT_X0)
	finish_x = SLOT_X0 - 250.0
	var gate = finish_gate_res.instantiate()
	gate.position = Vector2(finish_x, egg_top_y(finish_x))
	gate.finish_band_height = 1500.0      # seulement au ras de l'œuf (pas au départ, plus haut)
	add_child(gate)
	var hp = half_pipe_res.instantiate()
	hp.with_finish = false                # l'arrivée est au bord de la fente, pas dans le half-pipe
	hp.position = Vector2(SLOT_X0 + 1.0, lip_y + SLOT_DROP + 512.0)
	add_child(hp)


# =============================================================================
#  Points de réapparition (checkpoints)
# =============================================================================
func _define_checkpoints() -> void:
	var g1: Array = GAPS[0]
	var g2: Array = GAPS[1]
	var g3: Array = GAPS[2]
	checkpoints = [
		{"name": "départ", "pos": spawn_point, "vel": Vector2(300, 0)},
		{"name": "bol droit", "pos": Vector2(g1[0] + g1[1] * 0.5 + 2600.0, OUT_BOT - 60.0), "vel": Vector2(-1200, 0)},
		{"name": "trou 2", "pos": Vector2(g2[0] + g2[1] * 0.5 + 1500.0, OUT_BOT - 60.0), "vel": Vector2(-1200, 0)},
		{"name": "trou 3", "pos": Vector2(g3[0] + g3[1] * 0.5 + 1500.0, OUT_BOT - 60.0), "vel": Vector2(-1200, 0)},
		{"name": "cheminée", "pos": Vector2(OUT_L + R_BL + 2500.0, OUT_BOT - 60.0), "vel": Vector2(-1200, 0)},
		{"name": "pont", "pos": Vector2(_chimney.px0 + 500.0, BRIDGE_Y - 60.0), "vel": Vector2(400, 0)},
	]


## Point atteint ? (vérifié à chaque image ; on ne revient jamais en arrière)
func _physics_process(_delta: float) -> void:
	var p = get_tree().get_first_node_in_group("player")
	if p == null or p._respawning:
		return
	var pos: Vector2 = p.global_position
	var next := _cp + 1
	if next < checkpoints.size():
		var reached := false
		match next:
			1: reached = pos.y > OUT_BOT - R_BOT and pos.x > GAPS[0][0] + GAPS[0][1] * 0.5
			2: reached = pos.y > OUT_BOT - 1500.0 and pos.x < GAPS[0][0] - GAPS[0][1] * 0.5
			3: reached = pos.y > OUT_BOT - 1500.0 and pos.x < GAPS[1][0] - GAPS[1][1] * 0.5
			4: reached = pos.y > OUT_BOT - 1500.0 and pos.x < GAPS[2][0] - GAPS[2][1] * 0.5
			5: reached = pos.y < BRIDGE_Y + 100.0 and pos.x > _chimney.px0 and pos.x < BRIDGE_END_X and p.is_on_ground
		if reached:
			_cp = next
			print("[ŒUF] point de passage : ", checkpoints[_cp].name)
	# 5. tombé sous le pont (on glisserait jusqu'en bas de la cheminée) :
	# réapparition au début du pont
	if _cp == 5 and pos.y > BRIDGE_FALL_Y and pos.x < -800.0 and not p._respawning:
		p.die()


## Appelé par Player._pick_respawn_sample : point de passage atteint en dernier.
func respawn_sample(_pos: Vector2):
	if RaceManager.bonus_active or RaceManager.free_ride:
		return null                       # après l'arrivée : bord du half-pipe (RaceManager)
	var c: Dictionary = checkpoints[_cp]
	return {"pos": c.pos, "vel": c.vel}


## [MODE ENFANT] sens « vers l'avant » à cet endroit : +1 droite, -1 gauche, 0 (cheminée).
func forward_dir(pos: Vector2) -> float:
	if pos.y > OUT_BOT - R_BOT - 200.0 and pos.x < OUT_R - R_BOT:
		return -1.0                       # le bas : vers la gauche
	if pos.x < _chimney.get("px1", OUT_L) + 200.0 and pos.y > BRIDGE_Y:
		return 0.0                        # dans la cheminée : on grimpe
	return 1.0


## [MODE ENFANT] avancement le long du tour (sert à « a-t-il progressé ? »).
func progress(pos: Vector2) -> float:
	return _cp * 100000.0 + (pos.x if forward_dir(pos) > 0.0 else -pos.x if forward_dir(pos) < 0.0 else -pos.y)


## [MODE ENFANT] « pont magique » : passer au point suivant après deux chutes.
func kid_skip() -> void:
	if _cp + 1 < checkpoints.size():
		_cp += 1
		print("[ŒUF] mode enfant : point suivant ", checkpoints[_cp].name)


func current_checkpoint() -> int:
	return _cp
