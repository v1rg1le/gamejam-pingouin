extends Node2D
# =============================================================================
#  EggGenerator.gd — [ŒUF 1.59, refait en 1.60] « L'Œuf » (1.61 ; d'abord « Le Half-Pipe de l'œuf »)
# -----------------------------------------------------------------------------
#  Niveau imaginé par l'équipe (croquis « Level_Egg_V2 », 22/11), plan v3
#  validé : un seul tour d'environ 3 minutes autour d'un grand œuf de glace,
#  sans retour possible (mur derrière le départ, paroi fermée jusqu'à l'œuf).
#
#  VUE DE CÔTÉ (gravité vers le bas). Toute la géométrie est calculée ici, à
#  partir de quelques constantes (taille de l'œuf, du couloir, des trous…) :
#  aucune scène dessinée à la main. [1.60] Habillage pixel art : images
#  générées par tools/art/egg_art.py (sprites/levels/egg/), mêmes couleurs que
#  les sprites du jeu ; bordure de glace et half-pipe existants inchangés.
#
#  LE PARCOURS (sens des aiguilles d'une montre) :
#   1. DÉPART sur une plateforme en haut. À gauche : un mur jusqu'au plafond
#      (pas de retour à gauche). À droite : la plateforme se prolonge en
#      TOBOGGAN qui rejoint l'épaule de l'œuf (la « paroi ajoutée » du plan
#      v3 : on ne peut pas passer dessous vers le half-pipe).
#   2. [1.60] ZIGZAG À DROITE : corniches de glace alternées (œuf / paroi),
#      en pente, qui font aller Pinpouin de droite à gauche jusqu'au BOL du
#      bas (coin arrondi).
#   3. LE BAS, VERS LA GAUCHE : trois trous qui tombent dans le VIDE
#      (puits) : un saut (avec un tremplin au bord), un balancier (prise au
#      bout d'une stalactite qui pend sous l'œuf), un grappin double (deux
#      stalactites). La caméra dézoome pour montrer la stalactite suivante.
#   4. [1.60] CHEMIN DE GAUCHE (remplace la cheminée) : une MARCHE (rampe
#      arrondie) puis 12 plateformes-stalactites alternées, de prise en prise
#      au grappin : on monte le long du bord de la plateforme, on lâche
#      au-dessus et on s'y pose.
#   5. LE DOS DE L'ŒUF : la 13e plateforme est un PONT vers la droite, puis
#      un PLAFOND suspendu au-dessus d'une CREVASSE creusée dans l'œuf (deux
#      prises) : le raccourci par le dos de l'œuf est fermé. Tomber dans la
#      crevasse = réapparition au début du pont.
#   6. ARRIVÉE au bord de la FENTE creusée dans le haut de l'œuf, puis chute
#      dans le HALF-PIPE au cœur de l'œuf (30 s de figures bonus en Score,
#      glisse libre en Chill : règles de RaceManager inchangées).
#  Des PANNEAUX FLÈCHES marquent chaque changement de direction.
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
## [ŒUF 1.59] maquette : la grotte, le départ, le pont et les
## stalactites sont d'un bleu plus sombre, pour qu'on lise bien les parois
## sur le fond (le bleu clair de la glace se confondait avec le ciel clair).
const ROCK_COLOR := Color(0.36, 0.52, 0.70, 1)
const RIM_COLOR := Color(0.16, 0.36, 0.60, 1)   # contour de toutes les surfaces
const RIM_WIDTH := 14.0
const EDGE_TEXTURE := preload("res://sprites/levels/tiles/tile_ice_up_long1.png")
var half_pipe_res = preload("res://src/levels/GroundGenerator/HalfPipe.tscn")

# --- [ŒUF 1.60] Habillage pixel art -------------------------------------------
# Toutes ces images sont générées par tools/art/egg_art.py (palette des sprites
# du jeu). ART_SCALE : 1 pixel d'art = 6 pixels du monde (fin, comme la
# bordure de glace de la piste).
const ART_SCALE := 6.0
const ART_EGG_PAD := 4.0          # marge (en pixels d'art) autour de l'œuf dans oeuf_glace.png
const EGG_TEXTURE := preload("res://sprites/levels/egg/oeuf_glace.png")
const ICE_TILE := preload("res://sprites/levels/egg/tuile_glace.png")     # stalactites, corniches, plateformes
const CAVE_TILE := preload("res://sprites/levels/egg/tuile_roche.png")    # fond sombre de la grotte
const HOLD_TEXTURE := preload("res://sprites/levels/egg/prise.png")
const ICICLE_TEXTURES := [
	preload("res://sprites/levels/egg/stalactite_0.png"),
	preload("res://sprites/levels/egg/stalactite_1.png"),
	preload("res://sprites/levels/egg/stalactite_2.png"),
	preload("res://sprites/levels/egg/stalactite_3.png"),
]
const SIGN_DIR := "res://sprites/levels/egg/panneau_%s.png"   # droite, gauche, haut, bas, haut-droite…
const SIGN_SCALE := 5.0           # comme le panneau « attention » (warning.png)
var _deco_rng := RandomNumberGenerator.new()   # glaçons : graine fixe = même décor à chaque partie
var finish_gate_res = preload("res://src/levels/FinishGate.tscn")

# --- L'œuf (ellipse un peu plus étroite en haut : forme d'œuf) ---------------
const EGG_A := 10000.0        # demi-largeur
const EGG_B := 3400.0         # demi-hauteur ([1.60] 4000 -> 3400 : montée de gauche moins haute)
const EGG_K := 0.13           # resserrement du haut (0 = ellipse)

# --- La « grotte » autour de l'œuf (rectangle aux coins arrondis) -----------
const OUT_L := -13600.0       # paroi gauche
const OUT_R := 13600.0        # paroi droite
const OUT_TOP := -7200.0      # plafond
const OUT_BOT := 6200.0       # sol du bas
const R_TOP := 2500.0         # rayon des coins du haut
const R_BOT := 4000.0         # rayon du coin bas-droit (le grand « bol » d'arrivée de la descente)
const R_BL := 700.0           # [1.60] rayon du coin bas-gauche : plus petit que la hauteur de la « marche » (800), donc caché dessous
const FAR := 40000.0          # le sol extérieur est rempli jusque-là (rien ne se voit au-delà)
const SHAFT_DEPTH := 3500.0   # profondeur des parois des puits (collision) ; dessous : le vide

# --- 1. Départ ----------------------------------------------------------------
const START_WALL_X0 := -600.0  # mur derrière le départ (gauche)
const START_WALL_X1 := 400.0
const PLATFORM_Y := -5800.0    # dessus de la plateforme de départ
const PLATFORM_END_X := 4800.0 # fin de la pente de départ, début du toboggan
const PLATFORM_DROP := 450.0   # la plateforme descend de ça (pente d'élan, ~6°)
const MASSIF_UNDER_Y := -5450.0 # dessous de la plateforme (au-dessus de la fente ; sous le dessus de la pente)
const SLIDE_END_X := 7400.0    # le toboggan rejoint l'œuf ici

# --- 2. Tremplins (abscisse le long des surfaces) ---------------------------
const KICK_H := 170.0          # hauteur d'un tremplin
const KICK_LIP_DEG := 22.0     # angle ajouté au bord (par rapport à la pente)

# --- 3. Les trous du bas : [centre x, largeur, nombre de stalactites] -------
const GAPS := [[5600.0, 900.0, 0], [1200.0, 2200.0, 1], [-6200.0, 3400.0, 2]]
const HOLD_RADIUS := 55.0      # boule de glace (comme les prises du tuto)
const STALACTITE_HOLD_UP := 850.0 # prise à 850 px au-dessus du sol : à portée (1200) à 45°

# --- 2 bis. [1.60] ZIGZAG à droite : corniches-stalactites alternées --------
#  Demande de l'équipe : « à droite, des stalactites pour faire faire un petit
#  zigzag au joueur ». Des corniches plates (glace + glaçons dessous),
#  légèrement penchées, accrochées une fois à la paroi, une fois à l'œuf :
#  Pinpouin tombe de l'une sur la suivante en changeant de sens à chaque fois.
const ZZ_TOP_Y := -1500.0      # hauteur (bout accroché) de la 1re corniche
const ZZ_DROP := 550.0         # écart de hauteur entre deux corniches
const ZZ_SLOPE_DEG := 10.0      # pente de chaque corniche (vers son bout libre)
const ZZ_GAP := 700.0          # passage laissé entre le bout libre et la paroi d'en face
const ZZ_THICK := 170.0        # épaisseur d'une corniche

# --- 4. [1.60] Chemin de GAUCHE : plateformes-stalactites + prises -----------
#  Demande de l'équipe : à la place de la cheminée, « un chemin avec des
#  plateformes plates successives comme des stalactites du bas, et des zones
#  d'accroche pour passer de stalactite en stalactite ». Les plateformes
#  alternent : accrochée à la paroi gauche, puis flottante côté œuf, etc.,
#  chacune LP_RISE plus haut que la précédente. Leurs bouts « intérieurs »
#  sont alignés sur LP_MID_X : debout au bout d'une plateforme, la prise de la
#  suivante est juste au-dessus, à portée du grappin (≤ 1200 px). Même
#  géométrie que les ateliers FALAISE du tuto (prise un peu au-dessus et en
#  retrait du bord) : grappin, tirer, lâcher au-dessus, se poser.
#  Tout en bas, une MARCHE (rampe arrondie qui finit à 60°) : l'élan du bas
#  fait sauter Pinpouin dessus.
const LP_MID_X := -11800.0     # bouts intérieurs des plateformes (milieu du couloir)
const LP_STEP_Y := 5400.0      # dessus de la marche (800 px au-dessus du sol)
const LP_RISE := 760.0         # chaque plateforme est 760 px plus haut que la précédente
const LP_COUNT := 13           # nombre de « sauts » (impair) : la 13e plateforme est le pont
const LP_W := 1900.0           # longueur des plateformes flottantes (côté œuf)
const LP_THICK := 180.0        # épaisseur
const LP_HOLD_IN := 60.0       # prise : à 60 px du bord de la plateforme (dans la colonne d'en face)…
const LP_HOLD_UP := 300.0      # … et au-dessus de son dessus
const LP_RAMP_R := 1600.0      # rayon de la rampe de la marche (finit à 60° : 0,5 R = 800 px)
const CH_EMBED := 15.0         # prises encastrées dans les plafonds (retour 1.57)

# --- 5. Pont, crevasse et plafond ----------------------------------------------
const BRIDGE_Y := LP_STEP_Y - LP_COUNT * LP_RISE   # dessus du pont (= -4480)
const BRIDGE_END_X := -6200.0  # fin du pont
const BRIDGE_DROP := 650.0     # le pont descend de ça vers la droite (on y reprend de l'élan)
const CEIL_X0 := -6700.0       # plafond suspendu au-dessus de la crevasse
const CEIL_X1 := -1200.0
const CEIL_UNDER := 650.0      # dessous du plafond, au-dessus du BOUT du pont ; [1.68] 750 -> 650 : avec la résistance de l'air au grappin, le balancier sur la 1re prise retombe ~70 px plus bas et la 2e prise était hors de portée (1200 px)
const BRIDGE_FALL_Y := -2600.0 # sous cette hauteur (côté gauche) = chute : réapparition
## [1.60] CREVASSE dans le dos de l'œuf (choix de l'équipe, pour fermer le
## raccourci « on remonte le dos de l'œuf en glissant ») : une grande fente
## entre le pont et le sommet. Sans le plafond à grappin, on tombe dedans et
## on réapparaît au début du pont.
const CREV_X0 := -5800.0
const CREV_X1 := -1800.0
const CREV_BOTTOM_Y := -300.0  # fond de la crevasse (dans l'œuf)

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
	_deco_rng.seed = 1600
	_build_egg_profile()
	_add_cave_background()   # [1.60] fond de roche sombre derrière tout le niveau
	var slot_x1: float = SLOT_X0 + _half_pipe_width() + 2.0
	_add_outer_cave()
	_add_egg(SLOT_X0, slot_x1)
	_add_start_massif(slot_x1)
	_add_kickers()
	_add_right_zigzag()      # [1.60]
	_add_gaps_and_stalactites()
	_add_left_path()         # [1.60] remplace la cheminée
	_add_ceiling()
	_add_finish_and_half_pipe(slot_x1)
	_define_checkpoints()
	_add_signs()             # [1.60] panneaux flèches (le parcours du bot)
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
	# [LISSAGE C² 1.71] collision lissée (SmoothCurve.gd : courbe limite C²,
	# au plus 1° d'un segment au suivant ; murs et coins nets gardés) ; le
	# dessin garde les points d'origine (écart de 1 à 3 px, invisible).
	col.polygon = SmoothCurve.smooth_closed(poly)
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


## [1.60] Habille le remplissage (Polygon2D) d'un corps avec une texture pixel
## art. Sans `offset`, la texture est une tuile répétée (glace, roche) calée
## sur les coordonnées du monde : les morceaux voisins se raccordent.
## Rappel Godot 4 : texel = (sommet + texture_offset) * texture_scale.
func _skin(body: Node, tex: Texture2D, offset := Vector2.ZERO) -> void:
	for c in body.get_children():
		if c is Polygon2D:
			c.texture = tex
			c.color = Color.WHITE                        # pas de teinte : couleurs de l'image
			c.texture_offset = offset
			c.texture_scale = Vector2.ONE / ART_SCALE
			if offset == Vector2.ZERO:
				c.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


## [1.60] Rangée de glaçons (sprites) sous une plateforme ou une corniche,
## de `a` à `b` (son dessus) ; `thick` = épaisseur : ils pendent sous le
## dessous. Décor seul (pas de collision) : on ne s'y cogne pas.
func _add_icicles(a: Vector2, b: Vector2, thick: float, max_len := 1e9) -> void:
	var length := a.distance_to(b)
	var x := 40.0
	while x < length - 40.0:
		var p := a.lerp(b, x / length) + Vector2(0, thick - 30.0)
		var spr := Sprite2D.new()
		spr.texture = ICICLE_TEXTURES[_deco_rng.randi() % ICICLE_TEXTURES.size()]
		spr.centered = false
		var sc := ART_SCALE * _deco_rng.randf_range(0.6, 1.0)
		# pas plus longs que `max_len` (ils ne doivent pas cacher la prise ni
		# la plateforme du dessous)
		sc = minf(sc, max_len / spr.texture.get_height())
		spr.scale = Vector2(sc, sc)
		spr.position = p - Vector2(spr.texture.get_width() * sc * 0.5, 0)
		spr.z_index = 2
		add_child(spr)
		x += _deco_rng.randf_range(110.0, 260.0)


## [1.60] Panneaux flèches : un à chaque changement de direction du
## parcours (relevé avec le bot « bon joueur »). Décor seul. Chaque panneau
## est posé sur la surface : `ground` = point du sol sous son poteau.
func _add_signs() -> void:
	var g1: Array = GAPS[0]
	var g3: Array = GAPS[2]
	var signs := [
		# départ : on fonce vers la droite, sur le toboggan
		[Vector2(spawn_point.x + 300.0, _profile_y(_slide, spawn_point.x + 300.0)), "droite"],
		# l'épaule de l'œuf : on plonge vers le zigzag
		[Vector2(7600.0, egg_top_y(7600.0)), "bas-droite"],
	]
	# zigzag : sur chaque corniche, le sens de sa pente
	for z in zigzag:
		var a: Vector2 = z.top[0]
		var b: Vector2 = z.top[1]
		var at := a.lerp(b, 0.25)
		signs.append([at, "bas-droite" if b.x > a.x else "bas-gauche"])
	signs.append_array([
		# fond du bol droit : demi-tour, tout le bas se fait vers la gauche
		[Vector2(OUT_R - 2600.0, OUT_BOT), "gauche"],
		# avant le 1er trou : on saute au bout du tremplin
		[Vector2(g1[0] + g1[1] * 0.5 + 1400.0, OUT_BOT), "haut-gauche"],
		# après le 3e trou : la marche du chemin de gauche
		[Vector2(g3[0] - g3[1] * 0.5 - 1200.0, OUT_BOT), "gauche"],
		# sur la marche : on monte, de prise en prise
		[Vector2(LP_MID_X - 900.0, LP_STEP_Y), "haut"],
		# à mi-hauteur (plateforme côté paroi) : on continue de monter
		[Vector2(LP_MID_X - 700.0, LP_STEP_Y - LP_MID_CP * LP_RISE), "haut"],
		# début du pont : vers la droite
		[Vector2(LP_MID_X + 500.0, BRIDGE_Y + BRIDGE_DROP * pow(500.0 / (BRIDGE_END_X - LP_MID_X), 2.0)), "droite"],
		# bout du pont : au grappin, sous le plafond, par-dessus la crevasse
		[Vector2(BRIDGE_END_X - 350.0, BRIDGE_Y + BRIDGE_DROP * pow((BRIDGE_END_X - 350.0 - LP_MID_X) / (BRIDGE_END_X - LP_MID_X), 2.0)), "haut-droite"],
		# sur l'œuf, après la crevasse : l'arrivée est à droite
		[Vector2(CREV_X1 + 500.0, egg_top_y(CREV_X1 + 500.0)), "droite"],
	])
	for sg in signs:
		_add_sign(sg[0], sg[1])


func _add_sign(ground: Vector2, direction: String) -> void:
	var spr := Sprite2D.new()
	spr.texture = load(SIGN_DIR % direction)
	spr.scale = Vector2(SIGN_SCALE, SIGN_SCALE)
	# le pied du tas de neige est à la ligne 61 de l'image (64 px, centrée)
	spr.position = ground - Vector2(0, (61.0 - 32.0) * SIGN_SCALE) + Vector2(0, 2.0 * SIGN_SCALE)
	spr.z_index = 1
	add_child(spr)


## [1.60] « Grotte plus sombre » : un grand fond de roche sombre derrière
## tout le niveau (il masque le ciel/les montagnes du décor parallaxe, qui
## donnaient l'impression d'être dehors). z_index très bas : derrière tout.
func _add_cave_background() -> void:
	var bg := Polygon2D.new()
	bg.polygon = PackedVector2Array([Vector2(OUT_L - 3000, OUT_TOP - 3000), Vector2(OUT_R + 3000, OUT_TOP - 3000),
		Vector2(OUT_R + 3000, OUT_BOT + SHAFT_DEPTH + 3000), Vector2(OUT_L - 3000, OUT_BOT + SHAFT_DEPTH + 3000)])
	bg.texture = CAVE_TILE
	bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	bg.texture_scale = Vector2.ONE / ART_SCALE
	bg.z_index = -100
	add_child(bg)


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
	# [1.60] boule de glace pixel art avec anneau bleu vif (prise.png, 28 px :
	# x4 = 112 px, à peu près le diamètre de la collision 2 x HOLD_RADIUS)
	var spr := Sprite2D.new()
	spr.texture = HOLD_TEXTURE
	spr.scale = Vector2(4, 4)        # échelle entière : pixels nets
	body.add_child(spr)
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


func _chain_to_segments(chain_in: PackedVector2Array, segs: PackedVector2Array) -> void:
	# [LISSAGE C² 1.71] chaîne de collision lissée (SmoothCurve.gd)
	var chain := SmoothCurve.smooth_open(chain_in)
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
	var top_edge_crev := PackedVector2Array() # dessus de l'œuf à gauche de la crevasse
	var notch_done := false
	var crev_done := false
	for p in _egg_top:                       # x décroissant : de la droite vers la gauche
		if p.x < slot_x1 and p.x > slot_x0:
			if not notch_done:
				notch_done = true
				poly.append(Vector2(slot_x1, egg_top_y(slot_x1)))
				poly.append(Vector2(slot_x1, slot_bottom))
				poly.append(Vector2(slot_x0, slot_bottom))
				poly.append(Vector2(slot_x0, egg_top_y(slot_x0)))
			continue
		# [1.60] crevasse dans le dos de l'œuf (fond irrégulier, en V)
		if p.x < CREV_X1 and p.x > CREV_X0:
			if not crev_done:
				crev_done = true
				poly.append(Vector2(CREV_X1, egg_top_y(CREV_X1)))
				poly.append(Vector2(CREV_X1 - 250.0, CREV_BOTTOM_Y - 500.0))
				poly.append(Vector2((CREV_X0 + CREV_X1) * 0.5, CREV_BOTTOM_Y))
				poly.append(Vector2(CREV_X0 + 250.0, CREV_BOTTOM_Y - 500.0))
				poly.append(Vector2(CREV_X0, egg_top_y(CREV_X0)))
			continue
		poly.append(p)
		if p.y < -EGG_B * 0.15:              # bordure sur le dessus seulement
			if p.x >= slot_x1:
				top_edge_r.append(p)
			elif p.x <= CREV_X0:
				top_edge_crev.append(p)
			else:
				top_edge_l.append(p)
	for i in range(1, _egg_bottom.size() - 1):
		poly.append(_egg_bottom[i])
	var egg_body := _add_body(poly, [top_edge_r, top_edge_l, top_edge_crev], 0, ICE_COLOR)
	# [1.60] l'œuf en pixel art : la texture est calculée sur la même équation
	# (EGG_A, EGG_B, EGG_K) ; texel = (monde + offset) * scale, et le centre de
	# l'œuf est au texel (PAD + A/S, PAD + B/S). Le polygone découpe la fente
	# du half-pipe et la crevasse.
	_skin(egg_body, EGG_TEXTURE, Vector2(ART_EGG_PAD * ART_SCALE + EGG_A, ART_EGG_PAD * ART_SCALE + EGG_B))


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
	_skin(_add_body(poly, [top], 5, ICE_COLOR), ICE_TILE)


func _add_kickers() -> void:
	# sur le toboggan (à 55 % de sa longueur). [1.60] Plus de tremplins sur
	# l'épaule de l'œuf : la descente se fait maintenant par le zigzag.
	var i := int(_slide.size() * 0.55)
	_add_kicker(_slide[i], (_slide[i + 1] - _slide[i]).normalized())
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
			_skin(_add_body(poly, [], 3), ICE_TILE)     # [1.60] glace pixel art
			_add_hold("trou%d_%d" % [gi + 1, k + 1], tip)


# =============================================================================
#  2 bis. [1.60] Zigzag à droite : corniches alternées paroi / œuf
# =============================================================================
var zigzag: Array = []          # [{attach: "mur"|"oeuf", top: [a, b]}] (pour les bots, la caméra)

func _add_right_zigzag() -> void:
	var y := ZZ_TOP_Y
	# La 1re corniche part de l'œuf et descend vers la paroi : Pinpouin, qui
	# arrive de l'épaule de l'œuf en allant vers la droite, garde son élan.
	var on_wall := false
	var tilt := tan(deg_to_rad(ZZ_SLOPE_DEG))
	while y < OUT_BOT - R_BOT - 100.0:
		var a: Vector2                                          # bout accroché (le plus haut)
		var b: Vector2                                          # bout libre (plus bas)
		if on_wall:
			a = Vector2(OUT_R + 150.0, y)
			# le bout libre doit rester à ZZ_GAP de l'œuf À SA PROPRE hauteur
			# (l'œuf s'élargit en descendant) : deux itérations suffisent.
			b = Vector2(_egg_reach_right(y) + ZZ_GAP, y)
			for _it in 2:
				b.y = y + absf(b.x - a.x) * tilt
				b.x = _egg_reach_right(b.y) + ZZ_GAP
		else:
			a = Vector2(egg_side_x(y, true) - 150.0, y)        # enfoncé de 150 dans l'œuf
			b = Vector2(OUT_R - ZZ_GAP, y)
		b.y = y + absf(b.x - a.x) * tilt
		var dirx := signf(b.x - a.x)
		var poly := PackedVector2Array([a, b, b + Vector2(0, ZZ_THICK * 0.6),
			b + Vector2(-dirx * 80.0, ZZ_THICK), a + Vector2(0, ZZ_THICK)])
		_skin(_add_body(poly, [PackedVector2Array([a, b])], 3), ICE_TILE)
		_add_icicles(a.lerp(b, 0.08), b, ZZ_THICK * 0.6)   # glaçons qui pendent dessous
		zigzag.append({"attach": "mur" if on_wall else "oeuf", "top": [a, b]})
		y = b.y + ZZ_DROP
		on_wall = not on_wall


## Le plus loin à droite que l'œuf s'étend AU-DESSUS de y : sous le « ventre »
## de l'œuf, une corniche doit dépasser son point le plus large, sinon
## Pinpouin, en tombant, se coincerait entre la corniche et l'œuf.
func _egg_reach_right(y: float) -> float:
	var r := egg_side_x(y, true)
	for q in _egg_top:
		if q.y <= y:
			r = maxf(r, q.x)
	for q in _egg_bottom:
		if q.y <= y:
			r = maxf(r, q.x)
	return r


## x du flanc de l'œuf (droit si `right`, sinon gauche) à la hauteur y.
func egg_side_x(y: float, right: bool) -> float:
	var pts := PackedVector2Array()
	pts.append_array(_egg_top)
	pts.append_array(_egg_bottom)
	var best := 0.0
	# hors de la hauteur de l'œuf : on renvoie son point le plus à droite/gauche
	# (évite qu'une corniche sous l'œuf ne s'étire jusqu'au milieu du niveau)
	var extreme := 0.0
	for q in pts:
		extreme = maxf(extreme, q.x) if right else minf(extreme, q.x)
	for i in pts.size() - 1:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		if (y - p0.y) * (y - p1.y) <= 0.0 and p0.y != p1.y:
			var x := lerpf(p0.x, p1.x, (y - p0.y) / (p1.y - p0.y))
			if (right and x > best) or (not right and x < best):
				best = x
	return best if best != 0.0 else extreme


# =============================================================================
#  4. [1.60] Chemin de gauche : marche, plateformes-stalactites, prises, pont
# =============================================================================
var left_path: Array = []       # [{top_y, x0, x1, hold}] de bas en haut (0 = la marche)

func _add_left_path() -> void:
	var y0 := LP_STEP_Y
	# --- la MARCHE : remplit le coin bas-gauche jusqu'à LP_STEP_Y ; à droite,
	# une rampe arrondie (arc de cercle tangent au sol, qui finit à 60°) : avec
	# l'élan du bas, Pinpouin décolle du bord et se pose sur la marche.
	var c := Vector2(LP_MID_X + LP_RAMP_R * sin(deg_to_rad(60.0)), OUT_BOT - LP_RAMP_R)
	var ramp := PackedVector2Array()
	for i in 25:
		var ang := deg_to_rad(lerpf(90.0, 150.0, float(i) / 24.0))    # du sol vers le bord
		ramp.append(c + Vector2(cos(ang), sin(ang)) * LP_RAMP_R)
	var step := PackedVector2Array([Vector2(OUT_L - 200.0, OUT_BOT + 200.0), Vector2(ramp[0].x, OUT_BOT + 200.0)])
	step.append_array(ramp)
	step.append(Vector2(OUT_L - 200.0, y0))
	var step_top := PackedVector2Array([Vector2(OUT_L, y0), ramp[ramp.size() - 1]])
	var ramp_edge := PackedVector2Array(ramp)
	ramp_edge.reverse()
	_add_body(step, [step_top, ramp_edge], 3)
	left_path.append({"top_y": y0, "x0": OUT_L, "x1": ramp[ramp.size() - 1].x, "hold": null})
	# --- plateformes alternées, puis le pont (dernière, côté œuf)
	for k in range(1, LP_COUNT + 1):
		var top_y := y0 - k * LP_RISE
		var egg_side := k % 2 == 1
		# La prise est au-dessus du niveau de la plateforme k, mais dans la
		# colonne d'en face (côté de la plateforme k-1, d'où l'on tire) : si elle
		# était au-dessus de la plateforme elle-même, le grappin se planterait
		# dans son dessous. On monte donc à la verticale le long de son bord,
		# puis on se pose dessus en lâchant.
		var hold := Vector2(LP_MID_X + (-LP_HOLD_IN if egg_side else LP_HOLD_IN), top_y - LP_HOLD_UP)
		_add_hold("p%d" % k, hold)
		if k == LP_COUNT:
			_add_bridge(top_y)
			left_path.append({"top_y": top_y, "x0": LP_MID_X, "x1": BRIDGE_END_X, "hold": hold})
			break
		var x0 := LP_MID_X if egg_side else OUT_L - 150.0
		var x1 := LP_MID_X + LP_W if egg_side else LP_MID_X
		var poly := PackedVector2Array([Vector2(x0, top_y), Vector2(x1, top_y), Vector2(x1, top_y + LP_THICK * 0.7),
			Vector2(x1 - 60.0, top_y + LP_THICK), Vector2(x0 + 60.0, top_y + LP_THICK), Vector2(x0, top_y + LP_THICK * 0.7)])
		_skin(_add_body(poly, [PackedVector2Array([Vector2(x0, top_y), Vector2(x1, top_y)])], 3), ICE_TILE)
		# « comme des stalactites du bas » : une rangée de glaçons dessous
		# (pas dans les 300 px du couloir où l'on monte, ni plus longs que 330 px)
		if egg_side:
			_add_icicles(Vector2(x0 + 300.0, top_y), Vector2(x1 - 60.0, top_y), LP_THICK, 330.0)
		else:
			_add_icicles(Vector2(OUT_L + 60.0, top_y), Vector2(x1 - 300.0, top_y), LP_THICK, 330.0)
		left_path.append({"top_y": top_y, "x0": x0, "x1": x1, "hold": hold})


## Le pont : dernière plateforme du chemin de gauche (côté œuf), en pente
## douce vers la droite jusqu'au-dessus de la crevasse.
func _add_bridge(top_y: float) -> void:
	var top := PackedVector2Array()
	for i in 21:
		var s := float(i) / 20.0
		top.append(Vector2(lerpf(LP_MID_X, BRIDGE_END_X, s), top_y + BRIDGE_DROP * s * s))
	var end_y := top_y + BRIDGE_DROP
	var poly := PackedVector2Array(top)
	poly.append_array(PackedVector2Array([Vector2(BRIDGE_END_X + 60.0, end_y + 120.0),
		Vector2(BRIDGE_END_X - 80.0, end_y + LP_THICK), Vector2(LP_MID_X + 60.0, top_y + LP_THICK),
		Vector2(LP_MID_X, top_y + LP_THICK * 0.7)]))
	_skin(_add_body(poly, [top], 3), ICE_TILE)
	_add_icicles(top[3], top[top.size() - 2], LP_THICK, 450.0)


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
	_add_hold("plafond1", Vector2(-5200.0, under + CH_EMBED))
	_add_hold("plafond2", Vector2(-2700.0, under + CH_EMBED))


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
	var mid: Dictionary = left_path[LP_MID_CP]
	checkpoints = [
		{"name": "départ", "pos": spawn_point, "vel": Vector2(300, 0)},
		{"name": "bol droit", "pos": Vector2(g1[0] + g1[1] * 0.5 + 2600.0, OUT_BOT - 60.0), "vel": Vector2(-1200, 0)},
		{"name": "trou 2", "pos": Vector2(g2[0] + g2[1] * 0.5 + 1500.0, OUT_BOT - 60.0), "vel": Vector2(-1200, 0)},
		{"name": "trou 3", "pos": Vector2(g3[0] + g3[1] * 0.5 + 1500.0, OUT_BOT - 60.0), "vel": Vector2(-1200, 0)},
		{"name": "marche", "pos": Vector2(LP_MID_X - 500.0, LP_STEP_Y - 60.0), "vel": Vector2.ZERO},
		{"name": "mi-hauteur", "pos": Vector2((mid.x0 + mid.x1) * 0.5, mid.top_y - 60.0), "vel": Vector2.ZERO},
		{"name": "pont", "pos": Vector2(LP_MID_X + 400.0, BRIDGE_Y - 60.0), "vel": Vector2(400, 0)},
		# [1.60] de l'autre côté de la crevasse (surtout pour le mode enfant :
		# après deux chutes dans la crevasse, le « pont magique » l'y pose)
		{"name": "crevasse franchie", "pos": Vector2(CREV_X1 + 600.0, egg_top_y(CREV_X1 + 600.0) - 60.0), "vel": Vector2(300, 0)},
	]

const LP_MID_CP := 6           # plateforme du point de passage « mi-hauteur » (côté paroi)


## Point atteint ? (vérifié à chaque image ; on ne revient jamais en arrière)
func _physics_process(_delta: float) -> void:
	var p = get_tree().get_first_node_in_group("player")
	if p == null or p._respawning:
		return
	var pos: Vector2 = p.global_position
	var next := _cp + 1
	if next < checkpoints.size():
		var reached := false
		var mid: Dictionary = left_path[LP_MID_CP]
		match next:
			1: reached = pos.y > OUT_BOT - 1500.0 and pos.x > GAPS[0][0] + GAPS[0][1] * 0.5
			2: reached = pos.y > OUT_BOT - 1500.0 and pos.x < GAPS[0][0] - GAPS[0][1] * 0.5
			3: reached = pos.y > OUT_BOT - 1500.0 and pos.x < GAPS[1][0] - GAPS[1][1] * 0.5
			4: reached = p.is_on_ground and pos.x < LP_MID_X and absf(pos.y - LP_STEP_Y) < 120.0
			5: reached = p.is_on_ground and pos.x < mid.x1 and absf(pos.y - mid.top_y) < 120.0
			7: reached = p.is_on_ground and pos.x > CREV_X1 and pos.y < CREV_BOTTOM_Y - 1500.0
			6: reached = p.is_on_ground and pos.x > LP_MID_X and pos.x < BRIDGE_END_X and pos.y < BRIDGE_Y + BRIDGE_DROP + 100.0 and pos.y > BRIDGE_Y - 200.0
		if reached:
			_cp = next
			print("[ŒUF] point de passage : ", checkpoints[_cp].name)
	# chutes qui ramènent au dernier point de passage (au lieu de tout refaire) :
	#  - depuis le haut du chemin de gauche, retombé sous la mi-hauteur ;
	#  - depuis le pont : dans la crevasse ou sur le dos de l'œuf.
	if not p._respawning:
		var mid2: Dictionary = left_path[LP_MID_CP]
		if _cp == 5 and pos.y > mid2.top_y + 1500.0 and pos.x < -8000.0:
			p.die()
		elif _cp == 6 and pos.y > BRIDGE_FALL_Y and pos.x < -800.0:
			p.die()
	_update_camera_focus(p)


## [1.60] Caméra : dans le bas, on dézoome pour voir la prochaine stalactite ;
## sur le chemin de gauche, pour voir la prochaine prise (AdaptiveCamera
## garde ce point dans le cadre, zoom 0,5 au plus large).
func _update_camera_focus(p) -> void:
	if not ("focus_point" in p.camera):
		return
	var pos: Vector2 = p.global_position
	var target = null
	if _cp == 0 and pos.x > 4000.0:
		# en l'air au-dessus de l'œuf, puis dans le zigzag : on cadre la
		# prochaine corniche (sinon on ne voit que le fond de la grotte)
		for z in zigzag:
			var a: Vector2 = z.top[0]
			var b: Vector2 = z.top[1]
			if minf(a.y, b.y) > pos.y + 150.0:
				target = (a + b) * 0.5
				break
	elif _cp >= 1 and _cp <= 3 and pos.y > OUT_BOT - 2600.0:
		# le bas : on cadre la prochaine stalactite (à gauche) — le haut de
		# son corps, pour la voir en entier avec sa prise au bout
		var best := INF
		for n in holds:
			if not str(n).begins_with("trou"):
				continue
			var h: Vector2 = holds[n]
			var d := pos.x - h.x                     # on va vers la gauche
			if d > -300.0 and d < 4800.0 and d < best:
				best = d
				target = h + Vector2(0, -500)
	elif (_cp == 4 or _cp == 5) and pos.x < LP_MID_X + LP_W + 300.0:
		for k in range(1, left_path.size()):
			var lp: Dictionary = left_path[k]
			if lp.top_y < pos.y - 100.0:            # la prochaine plateforme au-dessus
				target = lp.hold
				break
	# en bas, on s'autorise à dézoomer plus (0,33) : les stalactites sont à
	# plus de 3000 px les unes des autres
	p.camera.focus_min_zoom = 0.33 if (_cp >= 1 and _cp <= 3 and target != null) else p.camera.FOCUS_MIN_ZOOM
	p.camera.focus_point = target


## Appelé par Player._pick_respawn_sample : point de passage atteint en dernier.
func respawn_sample(_pos: Vector2):
	if RaceManager.bonus_active or RaceManager.free_ride:
		return null                       # après l'arrivée : bord du half-pipe (RaceManager)
	var c: Dictionary = checkpoints[_cp]
	return {"pos": c.pos, "vel": c.vel}


## [MODE ENFANT] sens « vers l'avant » à cet endroit : +1 droite, -1 gauche, 0 (pas de poussée).
func forward_dir(pos: Vector2) -> float:
	if pos.y > OUT_BOT - R_BOT - 200.0 and pos.x < OUT_R - R_BOT:
		return -1.0                       # le bas : vers la gauche
	if pos.x < LP_MID_X + LP_W + 200.0 and pos.y > BRIDGE_Y - 200.0:
		return 0.0                        # chemin de gauche : on grimpe (au grappin)
	if pos.x > 7000.0 and pos.y > ZZ_TOP_Y - 600.0:
		return 0.0                        # zigzag : le sens change à chaque corniche
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
