extends Node2D
class_name CaveGenerator
# =============================================================================
#  CaveGenerator.gd — [CAVERNES 1.63] Une caverne creusée dans une montagne,
#  générée à partir d'une GRAINE, avec N entrées et M sorties.
# -----------------------------------------------------------------------------
#  Demande de l'équipe (croquis « Caverne », 23/11) : « un node qui prendrait
#  en compte N entrées et M sorties, avec des directions données (angle θ en
#  entrée, φ en sortie), l'intérieur des galeries randomisé sans jamais aucun
#  cul-de-sac, avec une graine qu'on peut changer ». Décisions prises avec
#  l'équipe :
#   - croisements en X ET embranchements en Y ;
#   - on ne MONTE d'une galerie à l'autre qu'au grappin, par un trou ;
#   - on DESCEND d'une galerie à l'autre en se laissant tomber dans un trou
#     (salle de croisement) ;
#   - chaque entrée mène à au moins 2 sorties (s'il y en a 2 ou plus) ;
#   - routes du haut plus dures et plus rapides, routes du bas plus sûres ;
#   - le grappin ne s'accroche QU'AUX PRISES VISIBLES (la roche des cavernes
#     est dans le groupe « no_hook », voir Chain.gd) ;
#   - une graine FIXE par niveau (Chill comme Score) : même caverne pour tout
#     le monde (records, fantômes, multi). D'autres niveaux pourront tirer une
#     graine au hasard plus tard (il suffit de changer `cave_seed`).
#
#  COMMENT C'EST FAIT
#  1. LE PLAN (un graphe) : la caverne est découpée en COLONNES (largeur
#     COL_W) et en ÉTAGES (« lanes », espacés de LANE_GAP). Un nœud = un
#     étage à une colonne. Entre deux colonnes, chaque étage est soit un
#     COULOIR (tube horizontal avec une épreuve), soit une partie d'une SALLE
#     DE CROISEMENT qui réunit deux étages voisins (a et a+1) :
#        haut-gauche -> haut-droite : balancier sur une prise (rester en haut)
#        haut-gauche -> bas-droite  : on se laisse tomber (trou)
#        bas-gauche  -> bas-droite  : on glisse au fond
#        bas-gauche  -> haut-droite : on monte au grappin (deux prises)
#     Une salle avec ses 4 ouvertures est un X ; un nœud avec 2 sorties
#     possibles est un Y.
#  2. LES ROUTES : on tire au hasard des chemins d'une entrée vers une sortie
#     (marche aléatoire qui ne peut changer d'étage QUE dans une salle). Le
#     plan est la réunion de ces chemins : chaque galerie est sur un chemin
#     d'une entrée vers une sortie, donc AUCUN CUL-DE-SAC par construction.
#  3. LES CONTRÔLES (check_plan) : à partir de la géométrie réelle (toutes les
#     ouvertures des salles, pas seulement les chemins tirés), on vérifie que
#     chaque nœud est atteignable depuis une entrée, mène à une sortie, que
#     chaque sortie est atteinte et que chaque entrée a au moins 2 sorties.
#     Si une condition manque (ou s'il n'y a ni X ni Y), on refait un tirage
#     avec la MÊME graine (sous-tirage suivant) : une graine donne toujours la
#     même caverne.
#  4. LA GÉOMÉTRIE : chaque couloir / salle est un polygone creusé dans la
#     montagne. Les collisions sont des CHAÎNES DE SEGMENTS ouvertes (sols,
#     plafonds, murs) : les ouvertures entre un couloir et le suivant ne sont
#     pas des murs. La roche est dessinée en tranches verticales (montagne
#     moins les galeries), pour qu'on voie le fond (montagnes du décor) à
#     travers les galeries, sous un voile de glace léger (« galerie des
#     glaces »), en gardant le terrain bien lisible (roche opaque + contour).
#  Toutes les épreuves ont des dimensions validées au bot (gruyere_bot.gd).
#
#  Coordonnées LOCALES : le nœud (colonne 0, étage 0) est en (0, 0) ; y vers
#  le bas. Unités : px.
# =============================================================================

signal player_reached_node(c: int, l: int)

# --- Réglages exposés (le niveau les remplit avant add_child) ---------------
@export var cave_seed: int = 1
## Étages des entrées (colonne 0), du haut (0) vers le bas.
@export var entry_lanes: Array[int] = [0, 1]
## Étages des sorties (dernière colonne).
@export var exit_lanes: Array[int] = [0, 1, 2]
## Angle du sol à chaque entrée θ (degrés, > 0 = qui descend vers la droite).
@export var entry_angles: Array[float] = []
## Angle du sol à chaque sortie φ.
@export var exit_angles: Array[float] = []
## Nombre de colonnes (longueur de la caverne).
@export var columns: int = 8
## Mode « croquis » : pas de décor ni de joueur suivi (planche des graines).
@export var sketch_only: bool = false

# --- Dimensions -----------------------------------------------------------------
const COL_W := 2600.0          # largeur d'une colonne (un couloir ou une salle)
const LANE_GAP := 1250.0       # écart vertical entre deux étages (sol à sol)
const TUNNEL_H := 720.0        # hauteur d'un couloir (sol -> plafond)
const DROP := 150.0            # descente générale par colonne (on va vers le bas)
const STUB := 700.0            # couloir d'entrée / de sortie jusqu'au flanc
const LEDGE_L := 500.0         # rebord haut-gauche d'une salle
const LEDGE_R := 600.0         # rebord haut-droite d'une salle
const PIT_DEPTH := 300.0       # profondeur des puits (dans la roche, sous le sol)
## [CAVERNES 1.63] au-dessus d'un trou à balancier, le plafond monte en DÔME
## (DOME_H au-dessus du sol au lieu de TUNNEL_H) : la prise pend plus haut, la
## corde est plus longue et le balancier porte (au bot, avec une prise à 560 px
## du sol, la corde raccourcissait à ~170 px et Pinpouin restait pendu au
## milieu du trou). Le dôme s'arrête 50 px sous le fond du puits de l'étage du
## dessus (PIT_DEPTH 300 : 1250 - 300 - 900 = 50).
const DOME_H := 900.0
const HOLD_RADIUS := 55.0
const HOLD_UNDER_CEIL := 160.0 # une prise pend à 160 px sous le plafond
const MOUNTAIN_TOP := 1100.0   # roche au-dessus du plafond de l'étage du haut (au moins)
const MOUNTAIN_BOTTOM := 5000.0 # la montagne descend jusque-là sous le dernier étage
const SLAB := 500.0            # largeur des tranches de roche (dessin) : plus étroite que tout polygone creusé (couloir d'entrée : 700), donc jamais de trou au milieu d'une tranche ; 500 plutôt que 60 : ~10 fois moins de polygones à dessiner (téléphones)

const ROCK_COLOR := Color(0.30, 0.42, 0.58, 1)
const RIM_COLOR := Color(0.12, 0.24, 0.42, 1)
const RIM_WIDTH := 14.0
const GLASS_COLOR := Color(1.0, 1.0, 1.0, 0.55)    # voile de glace des galeries (léger : on voit le décor à travers)
## « galerie des glaces » : la tuile de glace pixel art de L'Œuf, à moitié transparente
const GLASS_TILE := preload("res://sprites/levels/egg/tuile_glace.png")
const EDGE_TEXTURE := preload("res://sprites/levels/tiles/tile_ice_up_long1.png")
const HOLD_TEXTURE := preload("res://sprites/levels/egg/prise.png")

# --- Résultats ------------------------------------------------------------------
var lanes_n := 1
var room_pairs: Array = []     # par intervalle : liste des étages a des salles [a, a+1]
var paths: Array = []          # routes tirées : listes d'étages (une par colonne)
var active := {}               # "c:l" -> true : nœuds utilisés
var rooms: Array = []          # {c, a, ul, ll, ur, lr}
var tubes: Array = []          # {c, l, kind, gap, lip, land, holds}
var edges := {}                # "c:l" -> [l2, ...] : passages réels vers la colonne c+1 (avec leur sorte)
var edge_kind := {}            # "c:l>l2" -> "couloir:<épreuve>" | "salle:haut" | "salle:chute" | "salle:bas" | "salle:montee"
var holds := {}                # nom -> position locale
var pits: Array = []           # Rect2 locaux : tomber dedans = réapparition
var chains: Array = []         # PackedVector2Array : collisions (segments ouverts)
var floor_chains: Array = []   # morceaux de sol (bordure de glace)
var carved: Array = []         # polygones creusés (dessin)
var mountain := PackedVector2Array()
var check := {}                # résultats des contrôles
var attempts := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	generate()
	_build_nodes()


# =============================================================================
#  Outils
# =============================================================================
func node_pos(c: int, l: int) -> Vector2:
	return Vector2(c * COL_W, l * LANE_GAP + c * DROP)


func _k(c: int, l: int) -> String:
	return "%d:%d" % [c, l]


func _hermite(p0: Vector2, p1: Vector2, a0: float, a1: float, steps := 12) -> PackedVector2Array:
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


func _join(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var out := a.duplicate()
	for i in b.size():
		if i == 0 and out.size() > 0 and out[out.size() - 1].distance_to(b[0]) < 1.0:
			continue
		out.append(b[i])
	return out


## Angle de la pente générale (le sol arrive et repart des nœuds avec cet angle).
func _joint_deg() -> float:
	return rad_to_deg(atan2(DROP, COL_W))


# =============================================================================
#  1-3. Le plan : salles, routes, contrôles (avec la même graine)
# =============================================================================
func generate() -> void:
	lanes_n = 1
	for l in entry_lanes + exit_lanes:
		lanes_n = maxi(lanes_n, l + 1)
	for attempt in 60:
		attempts = attempt + 1
		_rng.seed = hash([cave_seed, attempt])
		_draw_plan()
		check = check_plan()
		if check.ok:
			break
	_build_geometry()


## Tire les salles de chaque intervalle puis les routes.
func _draw_plan() -> void:
	room_pairs = []
	paths = []
	active = {}
	for c in columns:
		var pairs: Array = []
		if lanes_n >= 2 and _rng.randf() < 0.6:
			# une salle sur un couple d'étages voisins au hasard ; avec 4 étages,
			# parfois deux salles l'une sous l'autre (0-1 et 2-3)
			var a := _rng.randi_range(0, lanes_n - 2)
			pairs.append(a)
			if lanes_n >= 4 and _rng.randf() < 0.3:
				var b := 2 if a <= 1 else 0
				if absi(b - a) >= 2:
					pairs.append(b)
		room_pairs.append(pairs)
	# --- routes : couvrir chaque entrée et chaque sortie, puis 2 sorties par entrée
	var pairs_todo: Array = []
	for e in entry_lanes:
		pairs_todo.append([e, exit_lanes[_rng.randi() % exit_lanes.size()]])
	for x in exit_lanes:
		pairs_todo.append([entry_lanes[_rng.randi() % entry_lanes.size()], x])
	if exit_lanes.size() >= 2:
		for e in entry_lanes:
			var x2: int = exit_lanes[_rng.randi() % exit_lanes.size()]
			pairs_todo.append([e, x2])
	for i in _rng.randi_range(1, 2):
		pairs_todo.append([entry_lanes[_rng.randi() % entry_lanes.size()], exit_lanes[_rng.randi() % exit_lanes.size()]])
	for pr in pairs_todo:
		var p := _walk(pr[0], pr[1])
		if p.size() > 0:
			paths.append(p)
	for p in paths:
		for c in p.size():
			active[_k(c, p[c])] = true


## Dans l'intervalle c, l'étage l peut-il passer à l'étage l2 ? (même étage
## toujours ; étage voisin seulement si une salle réunit les deux)
func _can_move(c: int, l: int, l2: int) -> bool:
	if l2 == l:
		return true
	if absi(l2 - l) != 1:
		return false
	return mini(l, l2) in room_pairs[c]


## Marche aléatoire de l'étage `from` (colonne 0) à l'étage `to` (dernière
## colonne). On calcule d'abord, en partant de la fin, les étages d'où la
## sortie est encore atteignable, puis on ne tire que parmi eux.
func _walk(from: int, to: int) -> Array:
	var ok: Array = []
	for c in columns + 1:
		ok.append({})
	ok[columns][to] = true
	for c in range(columns - 1, -1, -1):
		for l in lanes_n:
			for l2 in ok[c + 1]:
				if _can_move(c, l, l2):
					ok[c][l] = true
	if not ok[0].has(from):
		return []
	var p: Array = [from]
	var l := from
	for c in columns:
		var opts: Array = []
		for l2 in [l, l - 1, l + 1]:
			if l2 >= 0 and l2 < lanes_n and ok[c + 1].has(l2) and _can_move(c, l, l2):
				opts.append(l2)
		# garder son étage un peu plus souvent que changer
		var pick: int = opts[0]
		if opts.size() > 1 and _rng.randf() < 0.55:
			pick = opts[1 + _rng.randi() % (opts.size() - 1)]
		p.append(pick)
		l = pick
	return p


## Passages RÉELS (d'après les ouvertures) et contrôles de l'équipe.
func check_plan() -> Dictionary:
	edges = {}
	edge_kind = {}
	rooms = []
	var x_count := 0
	for c in columns:
		var in_room := {}
		for a in room_pairs[c]:
			var ul: bool = active.has(_k(c, a))
			var ll: bool = active.has(_k(c, a + 1))
			var ur: bool = active.has(_k(c + 1, a))
			var lr: bool = active.has(_k(c + 1, a + 1))
			# une salle n'existe que si des routes l'utilisent vraiment (un
			# changement d'étage, ou les deux étages occupés)
			var diag := false
			for p in paths:
				if p[c] != p[c + 1] and mini(p[c], p[c + 1]) == a:
					diag = true
			if not diag and not (ul and ll):
				continue
			in_room[a] = true
			in_room[a + 1] = true
			rooms.append({"c": c, "a": a, "ul": ul, "ll": ll, "ur": ur, "lr": lr})
			if ul and ur: _edge(c, a, a, "salle:haut")
			if ul and lr: _edge(c, a, a + 1, "salle:chute")
			if ll and lr: _edge(c, a + 1, a + 1, "salle:bas")
			if ll and ur: _edge(c, a + 1, a, "salle:montee")
			if ul and ll and ur and lr:
				x_count += 1
		for l in lanes_n:
			if in_room.has(l):
				continue
			if active.has(_k(c, l)) and active.has(_k(c + 1, l)):
				_edge(c, l, l, "couloir")
	# --- atteignables depuis une entrée (en avançant)
	var fwd := {}
	for e in entry_lanes:
		fwd[_k(0, e)] = true
	for c in columns:
		for l in lanes_n:
			if fwd.has(_k(c, l)) and edges.has(_k(c, l)):
				for l2 in edges[_k(c, l)]:
					fwd[_k(c + 1, l2)] = true
	# --- qui mène à une sortie (en reculant)
	var bwd := {}
	for x in exit_lanes:
		bwd[_k(columns, x)] = true
	for c in range(columns - 1, -1, -1):
		for l in lanes_n:
			if edges.has(_k(c, l)):
				for l2 in edges[_k(c, l)]:
					if bwd.has(_k(c + 1, l2)):
						bwd[_k(c, l)] = true
	var dead: Array = []
	for k in active:
		if not fwd.has(k) or not bwd.has(k):
			dead.append(k)
	# --- sorties atteintes depuis chaque entrée
	var per_entry := {}
	for e in entry_lanes:
		var seen := {_k(0, e): true}
		for c in columns:
			for l in lanes_n:
				if seen.has(_k(c, l)) and edges.has(_k(c, l)):
					for l2 in edges[_k(c, l)]:
						seen[_k(c + 1, l2)] = true
		var outs: Array = []
		for x in exit_lanes:
			if seen.has(_k(columns, x)):
				outs.append(x)
		per_entry[e] = outs
	var need := mini(2, exit_lanes.size())
	var entries_ok := true
	for e in per_entry:
		if per_entry[e].size() < need:
			entries_ok = false
	var exits_ok := true
	for x in exit_lanes:
		if not fwd.has(_k(columns, x)):
			exits_ok = false
	var y_count := 0
	for k in edges:
		if edges[k].size() >= 2:
			y_count += 1
	var res := {
		"sans_cul_de_sac": dead.is_empty(),
		"entrees_2_sorties": entries_ok,
		"sorties_atteintes": exits_ok,
		"x": x_count, "y": y_count,
		"per_entry": per_entry, "dead": dead,
	}
	res.ok = res.sans_cul_de_sac and entries_ok and exits_ok and (x_count >= 1 or lanes_n < 2) and (y_count >= 1 or lanes_n < 2)
	return res


func _edge(c: int, l: int, l2: int, kind: String) -> void:
	var k := _k(c, l)
	if not edges.has(k):
		edges[k] = []
	if not (l2 in edges[k]):
		edges[k].append(l2)
	edge_kind["%d:%d>%d" % [c, l, l2]] = kind


# =============================================================================
#  4. Géométrie : couloirs, salles, entrées / sorties, montagne
# =============================================================================
var _after_swing := {}         # "c:l" : on sort de cet intervalle lancé par un balancier

func _build_geometry() -> void:
	_after_swing = {}
	tubes = []
	holds = {}
	pits = []
	chains = []
	floor_chains = []
	carved = []
	var room_at := {}
	for r in rooms:
		room_at[_k(r.c, r.a)] = r
		room_at[_k(r.c, r.a + 1)] = r
		_build_room(r)
	for c in columns:
		for l in lanes_n:
			if room_at.has(_k(c, l)):
				continue
			if edges.has(_k(c, l)) and (l in edges[_k(c, l)]):
				_build_tube(c, l)
	for i in entry_lanes.size():
		var th: float = entry_angles[i] if i < entry_angles.size() else 8.0
		_build_stub(node_pos(0, entry_lanes[i]), th, true)
	for i in exit_lanes.size():
		var ph: float = exit_angles[i] if i < exit_angles.size() else 8.0
		_build_stub(node_pos(columns, exit_lanes[i]), ph, false)
	_build_mountain()


## Épreuve d'un couloir, selon l'étage (haut = plus dur et plus rapide).
func _pick_kind(l: int) -> String:
	var r: float = float(l) / maxf(1.0, float(lanes_n - 1))   # 0 en haut, 1 en bas
	var w := {
		"glissade": lerpf(0.10, 0.50, r),
		"trou": lerpf(0.25, 0.40, r),
		"balancier": lerpf(0.35, 0.10, r),
		"double": lerpf(0.30, 0.0, r),
	}
	var total := 0.0
	for k in w:
		total += w[k]
	var x := _rng.randf() * total
	for k in w:
		x -= w[k]
		if x <= 0.0:
			return k
	return "glissade"


## Couloir de l'étage l entre les colonnes c et c+1, avec son épreuve.
func _build_tube(c: int, l: int) -> void:
	var kind := _pick_kind(l)
	# [1.63] pas de simple TROU juste après un balancier (couloir à prises ou
	# salle où l'on reste en haut) : on en ressort lancé très loin et on
	# survolait le bord du trou (au bot : 2000 px de vol, droit dans le puits,
	# à chaque réapparition). On met alors une glissade (ou un balancier).
	if kind == "trou" and _after_swing.has(_k(c - 1, l)):
		kind = "glissade" if _rng.randf() < 0.6 else "balancier"
	var p0 := node_pos(c, l)
	var p1 := node_pos(c + 1, l)
	var aj := _joint_deg()
	var base := func(x: float) -> float: return lerpf(p0.y, p1.y, (x - p0.x) / (p1.x - p0.x))
	var floor_pts := PackedVector2Array()
	var t := {"c": c, "l": l, "kind": kind, "holds": []}
	match kind:
		"glissade":
			# un creux puis une bosse : on prend de l'élan au PUMP
			var d1 := Vector2(p0.x + COL_W * 0.40, base.call(p0.x + COL_W * 0.40) + 200.0)
			var d2 := Vector2(p0.x + COL_W * 0.75, base.call(p0.x + COL_W * 0.75) + 20.0)
			floor_pts = _join(_join(_hermite(p0, d1, aj, 0.0), _hermite(d1, d2, 0.0, -8.0)), _hermite(d2, p1, -8.0, aj))
		_:
			var gap := 0.0
			match kind:
				"trou": gap = _rng.randf_range(450.0, 620.0)
				"balancier": gap = _rng.randf_range(1000.0, 1200.0)
				"double": gap = _rng.randf_range(1500.0, 1700.0)
			var xa := p0.x + (COL_W - gap) * (0.42 if kind == "trou" else 0.5)
			var lip := Vector2(xa, base.call(xa) - 30.0)
			var land := Vector2(xa + gap, base.call(xa + gap) + 70.0)
			var a := _hermite(p0, lip, aj, -14.0)           # petit tremplin au bord
			var b := _hermite(land, p1, 12.0, aj)
			# puits : on descend le long du bord, fond, on remonte sous l'arrivée
			var bottom := maxf(lip.y, land.y) + PIT_DEPTH
			floor_pts = a
			floor_pts.append(Vector2(lip.x, bottom))
			floor_pts.append(Vector2(land.x, bottom))
			floor_pts = _join(floor_pts, b)
			# zone « tombé dans le puits » : entre 180 px sous le bord et le fond (pas
			# plus bas : le couloir de l'étage du dessous commence 530 px sous ce sol)
			pits.append(Rect2(lip.x, maxf(lip.y, land.y) + 180.0, gap, PIT_DEPTH - 200.0))
			t.gap = gap
			t.lip = lip
			t.land = land
			# prises : sous le plafond, au-dessus du trou
			var n := 1 if kind == "balancier" else (2 if kind == "double" else 0)
			for k in n:
				var hx := xa + gap * (0.5 if n == 1 else (0.28 + 0.44 * k))
				var hy: float = base.call(hx) - DOME_H + HOLD_UNDER_CEIL
				var name := "c%d_e%d_%s%d" % [c, l, kind, k + 1]
				holds[name] = Vector2(hx, hy)
				t.holds.append(name)
	# plafond : ligne de la pente générale, TUNNEL_H au-dessus ; dôme (voûte
	# arrondie, DOME_H) au-dessus d'un trou à prises
	var ceil_pts := PackedVector2Array([p0 + Vector2(0, -TUNNEL_H)])
	if t.holds.size() > 0:
		var da: float = t.lip.x - 250.0
		var db: float = t.land.x + 250.0
		var ya: float = base.call(da) - TUNNEL_H
		var yb: float = base.call(db) - TUNNEL_H
		var dm := Vector2((da + db) * 0.5, base.call((da + db) * 0.5) - DOME_H)
		ceil_pts.append(Vector2(da, ya))
		ceil_pts = _join(ceil_pts, _join(_hermite(Vector2(da, ya), dm, -40.0, 0.0, 10), _hermite(dm, Vector2(db, yb), 0.0, 40.0, 10)))
	ceil_pts.append(p1 + Vector2(0, -TUNNEL_H))
	chains.append(ceil_pts)
	chains.append(floor_pts)
	floor_chains.append(floor_pts)
	var poly := ceil_pts.duplicate()
	var rev := floor_pts.duplicate()
	rev.reverse()
	poly.append_array(rev)
	carved.append(poly)
	tubes.append(t)
	if t.holds.size() > 0:
		_after_swing[_k(c, l)] = true


## Salle de croisement entre les étages a (haut) et a+1 (bas), colonnes c, c+1.
## Contour parcouru dans le sens des aiguilles d'une montre, avec pour chaque
## côté un drapeau « ouvert » (ouverture vers le couloir voisin, pas un mur).
func _build_room(r: Dictionary) -> void:
	var c: int = r.c
	var a: int = r.a
	var x0 := c * COL_W
	var x1 := x0 + COL_W
	var yul := node_pos(c, a).y
	var yur := node_pos(c + 1, a).y
	var yll := node_pos(c, a + 1).y
	var ylr := node_pos(c + 1, a + 1).y
	var H := TUNNEL_H
	var aj := _joint_deg()
	# sol du bas : un creux léger
	var mid := Vector2((x0 + x1) * 0.5, (yll + ylr) * 0.5 + 150.0)
	var floor_line := _join(_hermite(Vector2(x0, yll), mid, aj, 0.0), _hermite(mid, Vector2(x1, ylr), 0.0, aj))
	var floor_y := func(x: float) -> float:
		for i in floor_line.size() - 1:
			if floor_line[i].x <= x and floor_line[i + 1].x >= x:
				return lerpf(floor_line[i].y, floor_line[i + 1].y, (x - floor_line[i].x) / maxf(1.0, floor_line[i + 1].x - floor_line[i].x))
		return floor_line[floor_line.size() - 1].y
	var pts := PackedVector2Array()
	var open: Array = []   # open[i] : le côté pts[i] -> pts[i+1] est une ouverture
	var add := func(p: Vector2, side_open: bool) -> void:
		pts.append(p)
		open.append(side_open)
	# plafond (haut-gauche -> haut-droite)
	add.call(Vector2(x0, yul - H), false)
	# --- côté droit, de haut en bas
	if r.ur:
		add.call(Vector2(x1, yur - H), true)                  # ouverture haute droite
		add.call(Vector2(x1, yur), false)                     # dessus du rebord
		add.call(Vector2(x1 - LEDGE_R, yur), false)           # face du rebord
		if r.lr:
			add.call(Vector2(x1 - LEDGE_R, ylr - H), false)   # dessous du rebord
			add.call(Vector2(x1, ylr - H), true)              # ouverture basse droite
		else:
			# le rebord descend jusqu'au sol
			pass
	else:
		add.call(Vector2(x1, yur - H), false)                 # mur
		if r.lr:
			add.call(Vector2(x1, ylr - H), true)
	# sol (de droite à gauche), coupé par les faces des rebords sans ouverture basse
	var fx1 := x1 if (r.lr or not r.ur) else x1 - LEDGE_R
	var fx0 := x0 if (r.ll or not r.ul) else x0 + LEDGE_L
	if r.ur and not r.lr:
		add.call(Vector2(fx1, floor_y.call(fx1)), false)
	var rev := PackedVector2Array()
	for p in floor_line:
		if p.x > fx0 + 1.0 and p.x < fx1 - 1.0:
			rev.append(p)
	rev.reverse()
	if r.lr or not r.ur:
		add.call(Vector2(x1, ylr), false)
	for p in rev:
		add.call(p, false)
	# --- côté gauche, de bas en haut
	if r.ll:
		add.call(Vector2(x0, yll), true)                      # ouverture basse gauche
		add.call(Vector2(x0, yll - H), false)
		if r.ul:
			add.call(Vector2(x0 + LEDGE_L, yll - H), false)   # dessous du rebord
			add.call(Vector2(x0 + LEDGE_L, yul), false)       # face du rebord
			add.call(Vector2(x0, yul), true)                  # dessus du rebord, puis ouverture haute gauche
		else:
			pass                                              # mur jusqu'au plafond
	else:
		add.call(Vector2(fx0, floor_y.call(fx0)), false)
		if r.ul:
			add.call(Vector2(x0 + LEDGE_L, yul), false)
			add.call(Vector2(x0, yul), true)
		else:
			add.call(Vector2(x0, yll), false)
	# le dernier côté revient au premier point (plafond haut-gauche) : c'est
	# l'ouverture haute gauche si elle existe, sinon un mur
	carved.append(pts)
	var chain := PackedVector2Array()
	for i in pts.size():
		var j := (i + 1) % pts.size()
		if chain.is_empty():
			chain.append(pts[i])
		if open[i]:
			if chain.size() >= 2:
				chains.append(chain)
			chain = PackedVector2Array()
		else:
			chain.append(pts[j])
	if chain.size() >= 2:
		chains.append(chain)
	# morceaux de sol pour la bordure de glace : le sol du bas et les rebords
	var fl := PackedVector2Array()
	for p in floor_line:
		if p.x >= fx0 - 1.0 and p.x <= fx1 + 1.0:
			fl.append(p)
	floor_chains.append(fl)
	if r.ul:
		floor_chains.append(PackedVector2Array([Vector2(x0, yul), Vector2(x0 + LEDGE_L, yul)]))
	if r.ur:
		floor_chains.append(PackedVector2Array([Vector2(x1 - LEDGE_R, yur), Vector2(x1, yur)]))
	# --- prises
	var tag := "c%d_s%d" % [c, a]
	if r.ul and r.ur:
		_after_swing[_k(c, a)] = true
		# rester en haut : balancier au milieu, sous le plafond
		var hx := (x0 + LEDGE_L + x1 - LEDGE_R) * 0.5
		holds[tag + "_haut"] = Vector2(hx, lerpf(yul, yur, 0.5) - H + HOLD_UNDER_CEIL)
	if r.ll and r.ur:
		# monter : une prise au milieu de la salle, puis une au-dessus du rebord
		var mx := x1 - LEDGE_R - 450.0
		holds[tag + "_monte1"] = Vector2(mx, floor_y.call(mx) - 820.0)
		# (60 px au-dessus du rebord, 420 plus haut : depuis la prise 1, la
		# ligne de tir passe au-dessus du coin du rebord — vérifié au bot)
		holds[tag + "_monte2"] = Vector2(x1 - LEDGE_R + 60.0, yur - 420.0)


## Couloir d'entrée (vers la gauche du nœud de la colonne 0) ou de sortie.
func _build_stub(p: Vector2, ang: float, is_entry: bool) -> void:
	var d := Vector2(STUB, STUB * tan(deg_to_rad(ang)))
	var a := p - d if is_entry else p
	var b := p if is_entry else p + d
	var fl := PackedVector2Array([a, b])
	var cl := PackedVector2Array([a + Vector2(0, -TUNNEL_H), b + Vector2(0, -TUNNEL_H)])
	chains.append(fl)
	chains.append(cl)
	floor_chains.append(fl)
	carved.append(PackedVector2Array([cl[0], cl[1], fl[1], fl[0]]))


## Montagne : flancs verticaux (où débouchent les couloirs), sommets au-dessus.
func _build_mountain() -> void:
	var deco := RandomNumberGenerator.new()
	deco.seed = cave_seed * 7 + 3
	var xl := -STUB
	var xr := columns * COL_W + STUB
	var top0 := node_pos(0, 0).y - TUNNEL_H - MOUNTAIN_TOP
	var top1 := node_pos(columns, 0).y - TUNNEL_H - MOUNTAIN_TOP
	var bottom := node_pos(columns, lanes_n - 1).y + MOUNTAIN_BOTTOM
	mountain = PackedVector2Array()
	mountain.append(Vector2(xl, bottom))
	mountain.append(Vector2(xl, top0))
	var n := int((xr - xl) / 1600.0)
	for i in range(1, n):
		var x := lerpf(xl, xr, float(i) / n)
		var y := lerpf(top0, top1, float(i) / n) - deco.randf_range(200.0, 1500.0) * sin(PI * float(i) / n)
		mountain.append(Vector2(x, y))
	mountain.append(Vector2(xr, top1))
	mountain.append(Vector2(xr, bottom))
	# flancs : murs de part et d'autre des ouvertures des couloirs
	_flank_chains(xl, top0, bottom, entry_lanes, entry_angles, true)
	_flank_chains(xr, top1, bottom, exit_lanes, exit_angles, false)
	# dessus de la montagne (on peut y glisser si on passe par-dessus)
	var top := PackedVector2Array()
	for i in range(1, mountain.size() - 1):
		top.append(mountain[i])
	chains.append(top)
	floor_chains.append(top)


func _flank_chains(x: float, top: float, bottom: float, lanes: Array, angles: Array, is_entry: bool) -> void:
	var cuts: Array = []
	for i in lanes.size():
		var ang: float = angles[i] if i < angles.size() else 8.0
		var p := node_pos(0 if is_entry else columns, lanes[i])
		var dy := STUB * tan(deg_to_rad(ang))
		var y := p.y - dy if is_entry else p.y + dy
		cuts.append([y - TUNNEL_H, y])
	cuts.sort_custom(func(u, v): return u[0] < v[0])
	var y0 := top
	for cut in cuts:
		chains.append(PackedVector2Array([Vector2(x, y0), Vector2(x, cut[0])]))
		y0 = cut[1]
	chains.append(PackedVector2Array([Vector2(x, y0), Vector2(x, bottom)]))


# =============================================================================
#  Nœuds Godot : collisions, roche, voile de glace, prises
# =============================================================================
func _build_nodes() -> void:
	# --- roche : montagne moins les galeries, en tranches verticales
	var rock := Node2D.new()
	rock.name = "Roche"
	rock.z_index = 1
	add_child(rock)
	var xl := mountain[0].x
	var xr := mountain[mountain.size() - 1].x
	var bounds: Array = []
	for poly in carved:
		var mn := INF
		var mx := -INF
		for p in poly:
			mn = minf(mn, p.x)
			mx = maxf(mx, p.x)
		bounds.append(Vector2(mn, mx))
	var x := xl
	while x < xr - 0.5:
		var x2 := minf(x + SLAB, xr)
		var slab := PackedVector2Array([Vector2(x, -1e6), Vector2(x2, -1e6), Vector2(x2, 1e6), Vector2(x, 1e6)])
		var pieces: Array = Geometry2D.intersect_polygons(mountain, slab)
		for i in carved.size():
			if bounds[i].y < x or bounds[i].x > x2:
				continue
			var nxt: Array = []
			for pc in pieces:
				nxt.append_array(Geometry2D.clip_polygons(pc, carved[i]))
			pieces = nxt
		for pc in pieces:
			if Geometry2D.is_polygon_clockwise(pc) and pieces.size() > 1:
				continue   # (trou : ne devrait pas arriver avec des tranches étroites)
			var f := Polygon2D.new()
			f.polygon = pc
			f.color = ROCK_COLOR
			f.antialiased = false
			rock.add_child(f)
		x = x2
	# --- voile de glace dans les galeries (léger : on voit le décor à travers)
	if not sketch_only:
		var glass := Node2D.new()
		glass.name = "Glace"
		glass.z_index = -5
		add_child(glass)
		for poly in carved:
			var g := Polygon2D.new()
			g.polygon = poly
			g.color = GLASS_COLOR
			g.texture = GLASS_TILE
			g.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			g.texture_scale = Vector2.ONE / 6.0      # 1 pixel d'art = 6 px (comme L'Œuf)
			glass.add_child(g)
	# --- collisions : chaînes de segments (sols, plafonds, murs)
	var body := StaticBody2D.new()
	body.name = "Collisions"
	body.collision_layer = 2
	body.add_to_group("no_hook")   # [CAVERNES] le grappin ne s'accroche pas à la roche
	add_child(body)
	var rims := Node2D.new()
	rims.z_index = 2
	add_child(rims)
	for ch in chains:
		var segs := PackedVector2Array()
		for i in ch.size() - 1:
			segs.append(ch[i])
			segs.append(ch[i + 1])
		var shape := ConcavePolygonShape2D.new()
		shape.segments = segs
		var cs := CollisionShape2D.new()
		cs.shape = shape
		body.add_child(cs)
		var rim := Line2D.new()
		rim.points = ch
		rim.width = RIM_WIDTH
		rim.default_color = RIM_COLOR
		rims.add_child(rim)
	# bordure de glace sur les sols
	for fl in floor_chains:
		if fl.size() < 2:
			continue
		var edge := Line2D.new()
		edge.texture = EDGE_TEXTURE
		edge.texture_mode = Line2D.LINE_TEXTURE_TILE
		edge.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		edge.width = 64.0
		edge.position = Vector2(0, 28)
		edge.points = fl
		edge.z_index = 3
		add_child(edge)
	# --- prises (les seules accroches du grappin dans la caverne)
	for n in holds:
		_add_hold(n, holds[n])


func _add_hold(name: String, center: Vector2) -> void:
	var body := StaticBody2D.new()
	body.name = "Prise_" + name
	body.collision_layer = 2
	body.position = center
	body.z_index = 6
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HOLD_RADIUS
	shape.shape = circle
	body.add_child(shape)
	# petite tige de glace qui la relie au plafond (on comprend d'où elle pend)
	var stem := Line2D.new()
	stem.points = PackedVector2Array([Vector2.ZERO, Vector2(0, -HOLD_UNDER_CEIL - 20.0)])
	stem.width = 18.0
	stem.default_color = Color(0.75, 0.9, 1.0)
	stem.z_index = -1
	body.add_child(stem)
	var spr := Sprite2D.new()
	spr.texture = HOLD_TEXTURE
	spr.scale = Vector2(4, 4)
	body.add_child(spr)
	add_child(body)


# =============================================================================
#  Pour les bots, les captures et la planche des graines
# =============================================================================
func debug_data() -> Dictionary:
	var nodes: Array = []
	for k in active:
		var s: PackedStringArray = k.split(":")
		nodes.append([int(s[0]), int(s[1])])
	var ed: Array = []
	for k in edge_kind:
		var s: PackedStringArray = k.replace(">", ":").split(":")
		ed.append([int(s[0]), int(s[1]), int(s[2]), edge_kind[k]])
	var tb: Array = []
	for t in tubes:
		tb.append([t.c, t.l, t.kind])
	return {"seed": cave_seed, "lanes": lanes_n, "columns": columns, "entries": entry_lanes,
		"exits": exit_lanes, "nodes": nodes, "edges": ed, "tubes": tb, "rooms": rooms,
		"check": check, "attempts": attempts, "paths": paths,
		"COL_W": COL_W, "LANE_GAP": LANE_GAP, "DROP": DROP, "TUNNEL_H": TUNNEL_H}
