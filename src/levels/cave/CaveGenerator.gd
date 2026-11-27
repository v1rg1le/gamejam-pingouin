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
#  [CAVERNES 1.65] Retours de l'équipe après la 1.64 :
#   - le DESSOUS de la galerie du dessus (le plafond d'un couloir) est
#     ACCROCHABLE sur toute sa longueur, avec un habillage de glace à
#     stalactites qui le rend lisible ; les murs et le reste de la roche
#     restent non accrochables ;
#   - plus de trous mortels entre deux galeries : on change d'étage
#     seulement aux salles et on « descend juste la galerie ». Les épreuves
#     des étages du haut deviennent des CUVETTES (creux arrondi : on peut y
#     glisser sans mourir). TOUT EN BAS seulement, un trou donne sur le VIDE ;
#   - les montées obligatoires au grappin deviennent des RAMPES avec des
#     BOOSTS (BoostArea, mode turbo) ; `climb_style = "grappin"` remet les
#     anciennes montées (levier de difficulté pour de futures cavernes) ;
#   - de petits boosts « rappels » dans les glissades du bas, et un boost en
#     l'air au-dessus des trous du vide.
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
## Angle d'ARRIVÉE à chaque entrée θ (degrés, de -90 à +90) : +90 = on
## arrive en tombant par au-dessus, -90 = on arrive en montant par en dessous,
## 8 (par défaut) = dans la pente du couloir. [1.66] Si θ ≠ 8, un VIRAGE en
## morceau de pipe (PipeBend) est construit DEVANT l'entrée, hors de la
## montagne : rampe d'accueil courbe si l'on arrive par au-dessus, tube courbe
## (plafond qui plaque Pinpouin, boosts en l'air) si l'on arrive par en dessous.
@export var entry_angles: Array[float] = []
## Angle de DÉPART à chaque sortie φ (degrés, de -90 à +90) : < 8 = tremplin
## qui relance vers le haut (virage concave), > 8 = bord arrondi qui plonge.
@export var exit_angles: Array[float] = []
## [1.66] Rayons des virages devant les entrées / après les sorties.
@export var entry_bend_radius: float = 1400.0
@export var exit_bend_radius: float = 900.0
## [1.66] Rayons par entrée / sortie (facultatif, même ordre que les étages ;
## 0 ou absent = le rayon commun ci-dessus).
@export var entry_radii: Array[float] = []
@export var exit_radii: Array[float] = []
## Nombre de colonnes (longueur de la caverne).
@export var columns: int = 8
## Mode « croquis » : pas de décor ni de joueur suivi (planche des graines).
@export var sketch_only: bool = false
## [1.65] Montées obligatoires (galerie du bas qui ne continue pas) :
## "rampe" = pente montante avec boosts (Gruyère) ; "grappin" = deux prises
## (plus difficile : levier pour de futures cavernes).
@export var climb_style: String = "rampe"
## [1.65] Trous mortels seulement à l'étage du bas (ils donnent sur le vide).
## false = anciens trous à tous les étages.
@export var pits_only_bottom: bool = true
## [1.65] Plafonds des couloirs accrochables au grappin.
@export var hookable_ceilings: bool = true

# --- Dimensions -----------------------------------------------------------------
const COL_W := 2600.0          # largeur d'une colonne (un couloir ou une salle)
## [CAVERNES 1.64] 1250 -> 950 : cavernes moins hautes (demande de l'équipe) ;
## avec le dézoom, on voit la galerie du dessus et celle du dessous.
const LANE_GAP := 950.0        # écart vertical entre deux étages (sol à sol)
const TUNNEL_H := 620.0        # hauteur d'un couloir (sol -> plafond) [1.64 : 720 -> 620]
const DROP := 150.0            # descente générale par colonne (on va vers le bas)
const STUB := 700.0            # couloir d'entrée / de sortie jusqu'au flanc
const LEDGE_L := 500.0         # rebord haut-gauche d'une salle
const LEDGE_R := 600.0         # rebord haut-droite d'une salle
const PIT_DEPTH := 220.0       # profondeur des puits (dans la roche, sous le sol) [1.64 : 300 -> 220, il reste 110 px de roche au-dessus du couloir du dessous]
## [CAVERNES 1.63] au-dessus d'un trou à balancier, le plafond monte en DÔME
## (DOME_H au-dessus du sol au lieu de TUNNEL_H) : la prise pend plus haut, la
## corde est plus longue et le balancier porte (au bot, avec une prise à 560 px
## du sol, la corde raccourcissait à ~170 px et Pinpouin restait pendu au
## milieu du trou). Le dôme s'arrête 50 px sous le fond du puits de l'étage du
## dessus (PIT_DEPTH 300 : 1250 - 300 - 900 = 50).
## [1.64] étages plus serrés (950) : le dôme (860) n'est creusé que si l'étage
## du dessus n'a RIEN de creusé dans cet intervalle (sinon pas de prises dans
## ce couloir : on y met un trou ou une glissade). L'étage du haut a toujours
## de la roche au-dessus : les balanciers y restent nombreux (« plus dur en
## haut », comme prévu).
const DOME_H := 860.0
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
## [1.65] habillage des plafonds accrochables : bandeau de glace et stalactites
## (nouvelle image, 32×16 px d'art, affichée ×4)
const CEIL_TEXTURE := preload("res://sprites/levels/cave/plafond_glace.png")
## [1.66] bandeau de glace LISSE (nouvelle image) : les stalactites sont
## maintenant posées une par une (voir STAL_*), plus espacées et de tailles
## variées, au lieu d'un motif qui se répète
const CEIL_SMOOTH_TEXTURE := preload("res://sprites/levels/cave/plafond_glace_lisse.png")
const STAL_TEXTURES := [
	preload("res://sprites/levels/cave/stalactite_1.png"),
	preload("res://sprites/levels/cave/stalactite_2.png"),
	preload("res://sprites/levels/cave/stalactite_3.png"),
	preload("res://sprites/levels/cave/stalactite_4.png"),
]
## [1.66] Stalactites (demande de l'équipe) : tous les STAL_SPACING px le long
## d'un plafond, on lit un BRUIT (valeur entre -1 et 1, qui varie doucement) :
## au-dessus du seuil STAL_THRESHOLD = une stalactite, d'autant plus grande
## que la valeur est haute ; en dessous = plafond lisse. Le bruit dépend de la
## graine de la caverne (même décor pour tout le monde).
const STAL_SPACING := 110.0
const STAL_THRESHOLD := 0.0
const STAL_NOISE_FREQ := 0.004
const STAL_SIZES := [0.08, 0.16, 0.26]   # paliers du bruit : petite, moyenne, grande, très grande
const BOOST_SCENE := preload("res://src/levels/boost/BoostArea.tscn")
## [1.65] profondeur d'une cuvette (creux arrondi sans danger, étages du haut) :
## il reste ~90 px de roche au-dessus du couloir du dessous
const BOWL_DEPTH := 170.0
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
var signs: Array = []          # [1.64] panneaux {pos (sol), dir}
var chains: Array = []         # PackedVector2Array : collisions (segments ouverts)
var chain_hook: Array = []     # [1.65] pour chaque chaîne : accrochable au grappin (plafond) ?
var ceil_chains: Array = []    # [1.65] plafonds accrochables (habillage de stalactites)
var glass_polys: Array = []    # [1.65] polygones du voile de glace (pas les fentes du vide)
var boosts: Array = []         # [1.65] boosts {pos, rot, strength, scale, air}
var outer_polys: Array = []    # [1.66] blocs de roche des virages hors de la montagne
## [1.66] Bout des virages : étage -> {pos, heading}. Sortie : là où le
## virage lâche Pinpouin ; entrée : début du virage (côté vide).
var exit_tips := {}
var entry_tips := {}
const STUB_DEG := 8.0          # [1.66] pente des couloirs d'entrée et de sortie (fixe)
const DIVE_STRAIGHT := 600.0   # [1.66] tout droit après un virage qui plonge
var floor_chains: Array = []   # morceaux de sol (bordure de glace)

# -----------------------------------------------------------------------------
# [LISSAGE 1.70] Sols lissés « comme Flat and fun »
# -----------------------------------------------------------------------------
# Retour de l'équipe : « encore des bugs dus au terrain dans les cavernes,
# plus sur Flat and fun ». Mesure (outil terrain_stats.gd, hors projet) :
# Flat = une seule courbe, un point tous les 64 px, 0,4 % de cassures de plus
# de 10° ; cavernes = 448 morceaux (courbes de 8 à 12 points raccordées bout
# à bout), 8 % de cassures de plus de 10° dont 146 de plus de 25°. Chaque
# cassure fait perdre de la vitesse ou décoller Pinpouin de quelques pixels.
# Remède à la source (1.70) : les morceaux de sol qui se touchent bout à bout
# sont recollés, puis chaque coin « de sol » est arrondi. 1.70 : petits arcs
# de Bézier, 4° au plus par segment. [LISSAGE C² 1.71] : arrondi commun à
# tous les niveaux (src/levels/SmoothCurve.gd) : courbe limite C² (courbure
# continue), 1° au plus par segment. Murs et plafonds accrochables : pas
# touchés. Écart à la forme d'origine : 1 à 3 px.
## [LISSAGE 1.70] Interrupteur (false = collisions d'avant la 1.70).
@export var smooth_floors := true

# --- [BALCONS 1.79] Bouts de plateforme hors de la montagne ----------------
# Demande de l'équipe (27/11) : les bouts de sol qui sortent des cavernes
# (tremplins de sortie, rampes d'accueil des entrées) doivent être mieux
# intégrés : pas de trait bleu entre eux et la caverne, et une forme de
# « balcon de glace sans barrière », avec des stalactites aux formes arrondies.
# Seul le DESSIN du dessous change : le dessus (la collision où l'on glisse)
# est exactement le même ; le dessous n'a jamais eu de collision.
#   0 = bloc d'origine (bande droite de 240-260 px sous le sol)
#   1 = console arrondie (épaisse contre la caverne, fine au bout, nez rond)
#   2 = stalactites rondes (fine dalle + gouttes de longueurs variées)
#   3 = grosse goutte (un seul renflement arrondi sous le balcon)
#   4 = corniche (dalle fine, petites gouttes rondes régulières)
@export var balcony_style := 0
## Dessous des virages hors de la montagne : [ligne du sol, épaisseur,
## index du point contre le flanc (0 ou dernier)] (voir _outer_slab).
var bend_slabs: Array = []
## [LISSAGE 1.70] (Réglages de l'arrondi : depuis la 1.71, dans
## src/levels/SmoothCurve.gd, communs à tous les niveaux.)
## [LISSAGE 1.70] Deux bouts de chaînes à moins de cette distance sont le
## même point (raccord entre deux morceaux de sol).
const SMOOTH_JOIN_EPS := 1.0
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


## [1.65] Ajoute une chaîne de collision ; `hook` = plafond accrochable.
func _add_chain(pts: PackedVector2Array, hook := false) -> void:
	if pts.size() < 2:
		return
	var h := hook and hookable_ceilings
	chains.append(pts)
	chain_hook.append(h)
	if h:
		ceil_chains.append(pts)


## [LISSAGE 1.70] Recolle bout à bout les chaînes de sol (non accrochables)
## dont un bout touche le bout d'une autre et qui continuent à peu près dans
## le même sens, puis arrondit les coins de chaque chaîne. Remplit à nouveau
## `chains` / `chain_hook` (les plafonds accrochables restent tels quels :
## leurs prises et leur habillage de stalactites en dépendent).
func _smooth_collision_chains() -> void:
	var keep: Array = []          # chaînes accrochables : inchangées
	var pool: Array = []          # chaînes à recoller / lisser
	for ci in chains.size():
		if chain_hook[ci]:
			keep.append(chains[ci])
		else:
			pool.append(chains[ci])
	# --- 1. recollage : une chaîne qui finit là où une autre commence (ou
	# finit : on la retourne) et qui continue dans un sens voisin (< 60°)
	# devient une seule chaîne. Sans ça, le raccord entre deux morceaux est
	# un coin que le lissage ne voit pas (deux formes de collision séparées).
	var merged := true
	while merged:
		merged = false
		for i in pool.size():
			var a: PackedVector2Array = pool[i]
			for j in pool.size():
				if i == j:
					continue
				var b: PackedVector2Array = pool[j]
				var joined := _try_join(a, b)
				if joined.size() > 0:
					pool[i] = joined
					pool.remove_at(j)
					merged = true
					break
			if merged:
				break
	# --- 2. arrondi des coins de chaque chaîne
	chains = []
	chain_hook = []
	for ch in pool:
		# [LISSAGE C² 1.71] arrondi commun à tous les niveaux (SmoothCurve.gd) :
		# courbe limite C², au plus 1° d'un segment au suivant (1.70 : arcs
		# de Bézier à 4°, avec des sauts de courbure aux bouts de chaque arc)
		# coins nets seulement au-delà de 60° et arrondi large (« wide ») : la
		# bordure des cavernes est dessinée sur la collision lissée
		chains.append(SmoothCurve.smooth_open(ch, SmoothCurve.MAX_TURN_DEG, 60.0, true))
		chain_hook.append(false)
	for ch in keep:
		chains.append(ch)
		chain_hook.append(true)


## [LISSAGE 1.70] Essaie de mettre `b` au bout de `a` (en retournant l'une ou
## l'autre si besoin). Renvoie la chaîne recollée, ou un tableau vide si les
## bouts ne se touchent pas ou si le raccord ferait un angle > 60°.
func _try_join(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	if a.size() < 2 or b.size() < 2:
		return PackedVector2Array()
	var variants := [[a, b], [a, _reversed(b)], [_reversed(a), b], [_reversed(a), _reversed(b)]]
	for v in variants:
		var p: PackedVector2Array = v[0]
		var q: PackedVector2Array = v[1]
		if p[p.size() - 1].distance_to(q[0]) > SMOOTH_JOIN_EPS:
			continue
		var d1: Vector2 = p[p.size() - 1] - p[p.size() - 2]
		var d2: Vector2 = q[1] - q[0]
		if d1.length() < 0.01 or d2.length() < 0.01:
			continue
		if absf(rad_to_deg(d1.angle_to(d2))) > 60.0:
			continue      # vrai coin (sol contre mur) : on ne recolle pas
		var out := p.duplicate()
		for k in range(1, q.size()):
			out.append(q[k])
		return out
	return PackedVector2Array()


func _reversed(c: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in range(c.size() - 1, -1, -1):
		out.append(c[k])
	return out


## [1.65] Ajoute un boost (BoostArea en mode turbo) posé en `pos` (sur le sol
## pour un boost de sol), tourné de `rot_deg`, de force 0..1.
func _add_boost(pos: Vector2, rot_deg: float, strength: float, arrow_scale: float, air := false) -> void:
	boosts.append({"pos": pos, "rot": rot_deg, "strength": strength, "scale": arrow_scale, "air": air})


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
var _carved_at := {}           # "c:l" : l'étage l est creusé dans l'intervalle c (couloir ou salle)

func _build_geometry() -> void:
	_after_swing = {}
	_carved_at = {}
	tubes = []
	holds = {}
	pits = []
	signs = []
	chains = []
	chain_hook = []
	ceil_chains = []
	glass_polys = []
	boosts = []
	outer_polys = []
	bend_slabs = []
	exit_tips = {}
	entry_tips = {}
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
		var th: float = entry_angles[i] if i < entry_angles.size() else STUB_DEG
		_build_stub(node_pos(0, entry_lanes[i]), STUB_DEG, true)
		var er: float = entry_radii[i] if i < entry_radii.size() and entry_radii[i] > 0.0 else entry_bend_radius
		_build_entry_bend(entry_lanes[i], clampf(th, -90.0, 90.0), er)
	for i in exit_lanes.size():
		var ph: float = exit_angles[i] if i < exit_angles.size() else STUB_DEG
		_build_stub(node_pos(columns, exit_lanes[i]), STUB_DEG, false)
		var xr: float = exit_radii[i] if i < exit_radii.size() and exit_radii[i] > 0.0 else exit_bend_radius
		_build_exit_bend(exit_lanes[i], clampf(ph, -90.0, 90.0), xr)
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
	# [1.65] un trou n'est mortel qu'à l'étage du BAS (il donne sur le vide) ;
	# ailleurs, l'épreuve se fait au-dessus d'une CUVETTE sans danger
	var deadly := (l == lanes_n - 1) or not pits_only_bottom
	# [1.63] pas de simple TROU juste après un balancier (couloir à prises ou
	# salle où l'on reste en haut) : on en ressort lancé très loin et on
	# survolait le bord du trou (au bot : 2000 px de vol, droit dans le puits,
	# à chaque réapparition). On met alors une glissade (ou un balancier).
	if deadly and kind == "trou" and _after_swing.has(_k(c - 1, l)):
		kind = "glissade" if _rng.randf() < 0.6 else "balancier"
	# [1.64] pas de prises (donc pas de dôme) si l'étage du dessus est creusé ici
	if (kind == "balancier" or kind == "double") and l > 0 and _carved_at.has(_k(c, l - 1)):
		kind = "glissade" if _after_swing.has(_k(c - 1, l)) else "trou"
	# [1.65] hors de l'étage du bas, le « trou » devient une cuvette
	if kind == "trou" and not deadly:
		kind = "cuvette"
	var p0 := node_pos(c, l)
	var p1 := node_pos(c + 1, l)
	var aj := _joint_deg()
	var base := func(x: float) -> float: return lerpf(p0.y, p1.y, (x - p0.x) / (p1.x - p0.x))
	var floor_pts := PackedVector2Array()
	var t := {"c": c, "l": l, "kind": kind, "holds": [], "deadly": false}
	var void_slot := PackedVector2Array()     # [1.65] fente vers le vide (étage du bas)
	var side_a := PackedVector2Array()        # [1.65] sol avant le trou du vide
	var side_b := PackedVector2Array()        # [1.65] sol après le trou du vide
	match kind:
		"glissade":
			# un creux puis une bosse : on prend de l'élan au PUMP
			var d1 := Vector2(p0.x + COL_W * 0.40, base.call(p0.x + COL_W * 0.40) + 200.0)
			var d2 := Vector2(p0.x + COL_W * 0.75, base.call(p0.x + COL_W * 0.75) + 20.0)
			floor_pts = _join(_join(_hermite(p0, d1, aj, 0.0), _hermite(d1, d2, 0.0, -8.0)), _hermite(d2, p1, -8.0, aj))
			# [1.65] « petit rappel » : un boost jaune sur la remontée, dans la
			# moitié basse de la caverne (là où l'on va le moins vite), une
			# glissade sur deux environ
			# [1.66] routes équivalentes (demande de l'équipe) : les rappels sont
			# maintenant à TOUS les étages (avant : moitié basse seulement)
			if _rng.randf() < 0.55:
				var bx := p0.x + COL_W * 0.55
				var by := _sample_y(floor_pts, bx)
				_add_boost(Vector2(bx, by), _slope_deg(floor_pts, bx), 0.28, 2.0)
		_:
			var gap := 0.0
			match kind:
				"trou", "cuvette": gap = _rng.randf_range(450.0, 620.0)
				"balancier": gap = _rng.randf_range(1000.0, 1200.0)
				"double": gap = _rng.randf_range(1500.0, 1700.0)
			var xa := p0.x + (COL_W - gap) * (0.42 if (kind == "trou" or kind == "cuvette") else 0.5)
			var lip := Vector2(xa, base.call(xa) - 30.0)
			var land := Vector2(xa + gap, base.call(xa + gap) + 70.0)
			var a := _hermite(p0, lip, aj, -14.0)           # petit tremplin au bord
			var b := _hermite(land, p1, 12.0, aj)
			if deadly:
				# [1.65] étage du bas : le trou traverse la montagne et donne
				# sur le VIDE. Le sol descend le long des bords jusque sous la
				# montagne ; la fente est creusée dans la roche (sans voile).
				var deep := node_pos(columns, lanes_n - 1).y + MOUNTAIN_BOTTOM + 400.0
				side_a = a
				side_b = b
				floor_pts = a.duplicate()
				floor_pts.append(Vector2(lip.x, deep))
				floor_pts.append(Vector2(land.x, deep))
				floor_pts = _join(floor_pts, b)
				void_slot = PackedVector2Array([lip, land, Vector2(land.x, deep), Vector2(lip.x, deep)])
				# zone « tombé dans le vide » : dès 150 px sous le bord
				pits.append(Rect2(lip.x, maxf(lip.y, land.y) + 150.0, gap, deep - maxf(lip.y, land.y)))
				t.deadly = true
				# [1.65] boost EN L'AIR au milieu d'un trou simple : grande
				# flèche qui aide à passer (et montre le chemin)
				if kind == "trou":
					_add_boost(Vector2(xa + gap * 0.5, lip.y - 130.0), -12.0, 0.4, 3.0, true)
			else:
				# [1.65] cuvette : creux arrondi, sans danger (on glisse dedans
				# et on remonte de l'autre côté ; au PUMP ou au grappin au plafond)
				var mid := Vector2((lip.x + land.x) * 0.5, maxf(lip.y, land.y) + BOWL_DEPTH)
				floor_pts = _join(_join(_join(a, _hermite(lip, mid, 60.0, 0.0, 10)), _hermite(mid, land, 0.0, -55.0, 10)), b)
			t.gap = gap
			t.lip = lip
			t.land = land
			# [1.66] ROUTES ÉQUIVALENTES (demande de l'équipe : « toutes les
			# routes équivalentes, plus ou moins de boosts sur les couches pour
			# compenser ») : mesuré au bot, les étages du haut (balanciers,
			# doubles prises) étaient ~2 fois plus lents que le bas. On donne :
			#  - au-dessus d'un trou à prises, un boost EN L'AIR au milieu (on
			#    peut passer sans le grappin ; le balancier reste un raccourci) ;
			#  - un boost au sol à l'arrivée de chaque trou (on repart vite).
			if not deadly and (kind == "balancier" or kind == "double"):
				_add_boost(Vector2(xa + gap * 0.5, lip.y - 160.0), -10.0, 0.5, 3.0, true)
			if not deadly:
				var lx := land.x + 120.0
				_add_boost(Vector2(lx, _sample_y(b, lx)), _slope_deg(b, lx), 0.4, 2.0)
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
	_add_chain(ceil_pts, true)      # [1.65] plafond accrochable
	_add_chain(floor_pts)
	if t.deadly:
		# le sol de part et d'autre du trou a sa bordure de glace, pas les parois
		floor_chains.append(side_a)
		floor_chains.append(side_b)
	else:
		floor_chains.append(floor_pts)
	var poly := ceil_pts.duplicate()
	if t.deadly:
		# le voile de glace et la roche : couloir fermé au niveau des bords ;
		# la fente du vide est creusée à part (pas de voile dedans)
		var rev2 := _join(side_a, side_b)
		rev2.reverse()
		poly.append_array(rev2)
		carved.append(void_slot)
	else:
		var rev := floor_pts.duplicate()
		rev.reverse()
		poly.append_array(rev)
	carved.append(poly)
	glass_polys.append(poly)
	tubes.append(t)
	_carved_at[_k(c, l)] = true
	if t.holds.size() > 0:
		_after_swing[_k(c, l)] = true


## [1.65] Hauteur d'une ligne brisée (x croissants) en x.
func _sample_y(line: PackedVector2Array, x: float) -> float:
	for i in line.size() - 1:
		if line[i].x <= x and line[i + 1].x >= x and line[i + 1].x > line[i].x:
			return lerpf(line[i].y, line[i + 1].y, (x - line[i].x) / (line[i + 1].x - line[i].x))
	return line[line.size() - 1].y


## [1.65] Pente (degrés, < 0 = qui monte vers la droite) d'une ligne brisée en x.
func _slope_deg(line: PackedVector2Array, x: float) -> float:
	return rad_to_deg(atan2(_sample_y(line, x + 25.0) - _sample_y(line, x - 25.0), 50.0))


## Salle de croisement entre les étages a (haut) et a+1 (bas), colonnes c, c+1.
## Contour parcouru dans le sens des aiguilles d'une montre, avec pour chaque
## côté un drapeau « ouvert » (ouverture vers le couloir voisin, pas un mur).
func _build_room(r: Dictionary) -> void:
	var c: int = r.c
	var a: int = r.a
	_carved_at[_k(c, a)] = true
	_carved_at[_k(c, a + 1)] = true
	var x0 := c * COL_W
	var x1 := x0 + COL_W
	var yul := node_pos(c, a).y
	var yur := node_pos(c + 1, a).y
	var yll := node_pos(c, a + 1).y
	var ylr := node_pos(c + 1, a + 1).y
	var H := TUNNEL_H
	var aj := _joint_deg()
	# [1.65] RAMPE : la galerie du bas ne continue pas (lr fermé) mais celle du
	# haut, oui -> au lieu de monter au grappin, le sol remonte en pente douce
	# (~21°) jusqu'à la sortie haute, avec des boosts (voir plus bas)
	var ramp: bool = climb_style == "rampe" and r.ll and r.ur and not r.lr
	r["ramp"] = ramp
	# sol du bas : un creux léger
	var mid := Vector2((x0 + x1) * 0.5, (yll + ylr) * 0.5 + 150.0)
	var floor_line := _join(_hermite(Vector2(x0, yll), mid, aj, 0.0), _hermite(mid, Vector2(x1, ylr), 0.0, aj))
	var ramp_a := Vector2.ZERO
	var ramp_e := Vector2.ZERO
	if ramp:
		# petit creux en entrant, ligne droite qui monte, puis on rejoint le
		# seuil de la sortie haute en (x1, yur) avec la pente générale
		ramp_a = Vector2(x0 + 550.0, yll - 40.0)
		ramp_e = Vector2(x1 - 200.0, yur + 30.0)
		var alpha := rad_to_deg(atan2(ramp_a.y - ramp_e.y, ramp_e.x - ramp_a.x))
		floor_line = _join(_join(_hermite(Vector2(x0, yll), ramp_a, aj, -alpha, 10),
			_hermite(ramp_a, ramp_e, -alpha, -alpha, 12)), _hermite(ramp_e, Vector2(x1, yur), -alpha, aj, 8))
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
	if r.ur and ramp:
		add.call(Vector2(x1, yur - H), true)                  # ouverture haute droite (la rampe y arrive)
	elif r.ur:
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
	var fx1 := x1 if (r.lr or not r.ur or ramp) else x1 - LEDGE_R
	var fx0 := x0 if (r.ll or not r.ul) else x0 + LEDGE_L
	if r.ur and not r.lr and not ramp:
		add.call(Vector2(fx1, floor_y.call(fx1)), false)
	var rev := PackedVector2Array()
	for p in floor_line:
		if p.x > fx0 + 1.0 and p.x < fx1 - 1.0:
			rev.append(p)
	rev.reverse()
	if ramp:
		add.call(Vector2(x1, yur), false)                     # haut de la rampe
	elif r.lr or not r.ur:
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
	glass_polys.append(pts)
	# [1.65] chaînes de collision : on coupe aux ouvertures ET quand on passe
	# d'un plafond (accrochable) à autre chose. Un côté est un plafond si
	# l'intérieur de la salle est SOUS lui : le contour tourne dans le sens
	# des aiguilles d'une montre (y vers le bas), donc l'intérieur est à
	# droite du sens de parcours, c'est-à-dire du côté (-d.y, d.x).
	var chain := PackedVector2Array()
	var chain_is_ceil := false
	for i in pts.size():
		var j := (i + 1) % pts.size()
		if open[i]:
			_add_chain(chain, chain_is_ceil)
			chain = PackedVector2Array()
			continue
		var d := pts[j] - pts[i]
		var is_ceil := Vector2(-d.y, d.x).normalized().y > 0.7
		if chain.size() > 0 and is_ceil != chain_is_ceil:
			_add_chain(chain, chain_is_ceil)
			chain = PackedVector2Array()
		if chain.is_empty():
			chain.append(pts[i])
			chain_is_ceil = is_ceil
		chain.append(pts[j])
	_add_chain(chain, chain_is_ceil)
	# morceaux de sol pour la bordure de glace : le sol du bas et les rebords
	var fl := PackedVector2Array()
	for p in floor_line:
		if p.x >= fx0 - 1.0 and p.x <= fx1 + 1.0:
			fl.append(p)
	floor_chains.append(fl)
	if r.ul:
		floor_chains.append(PackedVector2Array([Vector2(x0, yul), Vector2(x0 + LEDGE_L, yul)]))
	if r.ur and not ramp:
		floor_chains.append(PackedVector2Array([Vector2(x1 - LEDGE_R, yur), Vector2(x1, yur)]))
	# --- prises
	var tag := "c%d_s%d" % [c, a]
	if r.ul and r.ur:
		_after_swing[_k(c, a)] = true
		# rester en haut : balancier au milieu, sous le plafond
		var hx := (x0 + LEDGE_L + x1 - LEDGE_R) * 0.5
		holds[tag + "_haut"] = Vector2(hx, lerpf(yul, yur, 0.5) - H + HOLD_UNDER_CEIL)
	if ramp:
		# [1.65] boosts de la rampe : un boost ORANGE au pied (là où la pente
		# commence), puis deux « rappels » jaunes sur la montée : avec eux on
		# grimpe tout seul, même en arrivant lentement (vérifié au bot)
		var run := ramp_e.x - ramp_a.x
		for bz in [[ramp_a.x - 150.0, 0.45, 3.0], [ramp_a.x + run * 0.35, 0.28, 2.0], [ramp_a.x + run * 0.72, 0.28, 2.0]]:
			var bx: float = bz[0]
			_add_boost(Vector2(bx, floor_y.call(bx)), rad_to_deg(atan2(floor_y.call(bx + 25.0) - floor_y.call(bx - 25.0), 50.0)), bz[1], bz[2])
	elif r.ll and r.ur:
		# monter : une prise au milieu de la salle, puis une au-dessus du rebord
		var mx := x1 - LEDGE_R - 450.0
		holds[tag + "_monte1"] = Vector2(mx, floor_y.call(mx) - 700.0)   # [1.64] 820 -> 700 (étages plus serrés)
		if not r.lr:
			# [1.64] la seule suite de la galerie du bas est de MONTER : un
			# panneau « haut » au pied du rebord (sans lui, en jeu, on croyait
			# à un cul-de-sac : les prises étaient hors de l'écran)
			signs.append({"pos": Vector2(x1 - LEDGE_R - 160.0, floor_y.call(x1 - LEDGE_R - 160.0)), "dir": "haut"})
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
	_add_chain(fl)
	_add_chain(cl, true)      # [1.65] plafond du couloir d'entrée / de sortie : accrochable
	floor_chains.append(fl)
	carved.append(PackedVector2Array([cl[0], cl[1], fl[1], fl[0]]))
	glass_polys.append(carved[carved.size() - 1])


## [1.66] Bout du couloir sur le flanc (entrée : côté gauche ; sortie : droit).
func flank_point(l: int, is_entry: bool) -> Vector2:
	var d := Vector2(STUB, STUB * tan(deg_to_rad(STUB_DEG)))
	return node_pos(0, l) - d if is_entry else node_pos(columns, l) + d


## [1.66] Bloc de roche sous (ou sur) une ligne : `thick` > 0 vers le bas.
func _outer_slab(line: PackedVector2Array, thick: float, flank_first := true, balcony := false) -> void:
	var poly := line.duplicate()
	for i in range(line.size() - 1, -1, -1):
		poly.append(line[i] + Vector2(0, thick))
	# [BALCONS 1.79] les bouts « à l'air libre » (tremplin, rampe d'accueil)
	# pourront être redessinés en balcon (voir balcony_style) ; on garde la
	# ligne du sol et le côté du flanc pour ça
	if balcony and balcony_style > 0:
		bend_slabs.append([line, thick, flank_first])
		return
	outer_polys.append(poly)


## [BALCONS 1.79] Forme d'un balcon de glace sous la ligne de sol `line`.
## Renvoie [polygone, ligne du dessous (pour le fin contour), bande du flanc
## à retirer des contours]. Le dessus du polygone EST la ligne du sol (la
## collision ne change pas). Le dessous est calculé le long du balcon, de la
## caverne (s = 0) au bout (s = L), selon balcony_style ; toutes les formes
## sont arrondies (gouttes en demi-ellipses, nez rond au bout, congé arrondi
## contre la caverne pour que le balcon ait l'air de sortir de la roche).
func _balcony_shape(line: PackedVector2Array, thick: float, flank_first: bool) -> Array:
	var pts: PackedVector2Array = line if flank_first else PipeBend.reversed(line)
	# rééchantillonnage tous les ~6 px (les gouttes ont besoin de points serrés)
	var top := PackedVector2Array([pts[0]])
	var sd: Array = [0.0]
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var n := maxi(1, ceili(a.distance_to(b) / 6.0))
		for k in range(1, n + 1):
			var q := a.lerp(b, float(k) / n)
			sd.append(sd[-1] + q.distance_to(top[-1]))
			top.append(q)
	var L: float = sd[-1]
	# gouttes (graine fixe : même balcon à chaque partie)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([cave_seed, Vector2i(pts[0].round())])
	var drips: Array = []   # [centre s, largeur, longueur]
	if balcony_style == 2:
		var s := 70.0
		while s < L - 60.0:
			var w := rng.randf_range(44.0, 76.0)
			drips.append([s + w * 0.5, w, rng.randf_range(60.0, 200.0) * (1.0 - 0.6 * s / L)])
			s += w + rng.randf_range(4.0, 36.0)
	elif balcony_style == 4:
		var s := 60.0
		while s < L - 50.0:
			drips.append([s + 18.0, 36.0, rng.randf_range(22.0, 46.0)])
			s += 54.0
	var under := PackedVector2Array()
	for i in top.size():
		var d: float = sd[i]
		var u := d / maxf(L, 1.0)
		var base: float
		match balcony_style:
			1:   # console : épaisse contre la caverne, de plus en plus fine
				base = 40.0 + (thick * 1.25 - 40.0) * pow(1.0 - u, 1.7)
			2:   # dalle fine qui s'amincit, gouttes par-dessous
				base = 60.0 + 70.0 * (1.0 - u)
			3:   # un seul gros renflement arrondi (goutte) côté caverne
				base = 55.0 + 60.0 * (1.0 - u) + 230.0 * exp(-pow((u - 0.32) / 0.22, 2.0))
			_:   # corniche : dalle fine régulière
				base = 48.0
		# congé arrondi contre la caverne (le balcon « sort » de la roche)
		var t := base + 140.0 * pow(maxf(0.0, 1.0 - d / 220.0), 2.0)
		# gouttes en demi-ellipses (fond rond)
		for dr in drips:
			var dx: float = (d - dr[0]) / (dr[1] * 0.5)
			if absf(dx) < 1.0:
				t = maxf(t, base + dr[2] * sqrt(1.0 - dx * dx))
		# nez arrondi : le dessous remonte en quart d'ellipse jusqu'au bout
		var r := minf(t, 70.0)
		if d > L - r:
			var v := (d - (L - r)) / r
			t *= sqrt(maxf(0.0, 1.0 - v * v))
		under.append(top[i] + Vector2(0.0, t))
	var poly := top.duplicate()
	for i in range(under.size() - 1, -1, -1):
		poly.append(under[i])
	# bande du flanc : de 12 px sous le sol jusqu'au bas du balcon, 12 px de
	# chaque côté du flanc (le contour de la montagne passe là)
	var f: Vector2 = top[0]
	var cut := PackedVector2Array([f + Vector2(-12.0, 12.0), f + Vector2(12.0, 12.0),
		under[0] + Vector2(12.0, 4.0), under[0] + Vector2(-12.0, 4.0)])
	return [poly, under, cut]


## [1.66] Toit d'un tube courbe hors de la montagne : bloc au-dessus du
## plafond `ceil_line`, dont le DESSUS est une pente qui descend en
## s'éloignant du flanc (vu au bot : sur un toit presque plat collé au flanc,
## Pinpouin restait coincé dans le coin). Ce qui tombe dessus glisse vers le
## vide (et le virage en dessous).
## `flank_first` : le premier point de ceil_line est contre le flanc (sortie) ;
## sinon c'est le dernier (entrée).
func _roof_slab(ceil_line: PackedVector2Array, flank_first: bool) -> void:
	# bande de roche de 240 px au-dessus du plafond (polygone simple), avec
	# une collision sur son DESSUS
	var top := PackedVector2Array()
	for q in ceil_line:
		top.append(q + Vector2(0, -240.0))
	var band := ceil_line.duplicate()
	for i in range(top.size() - 1, -1, -1):
		band.append(top[i])
	outer_polys.append(band)
	_add_chain(top)
	if flank_first:
		return            # plongeon : le dessus descend déjà en s'éloignant du flanc
	# entrée par en dessous : le dessus près du flanc descend VERS le flanc
	# (coin où l'on resterait coincé) -> un coin de roche en pente qui
	# renvoie vers le vide
	var corner: Vector2 = top[top.size() - 1]
	var k := top.size() - 1
	while k > 0 and corner.distance_to(top[k]) < 700.0:
		k -= 1
	var wedge := PackedVector2Array([top[k], corner, corner + Vector2(0, -320.0)])
	outer_polys.append(wedge)
	_add_chain(PackedVector2Array([corner + Vector2(0, -320.0), top[k]]))


## [1.66] Virage APRÈS une sortie (hors de la montagne), voir exit_angles.
func _build_exit_bend(l: int, phi: float, radius: float) -> void:
	var p0 := flank_point(l, false)
	if absf(phi - STUB_DEG) < 0.5:
		exit_tips[l] = {"pos": p0, "heading": STUB_DEG}
		return
	var line := PipeBend.arc(p0, STUB_DEG, phi - STUB_DEG, radius)
	var dive := phi > STUB_DEG + 10.0
	if dive:
		# le tube continue tout droit après le virage : un Pinpouin qui a
		# décollé du bord arrondi touche le plafond même tard (la tangente au
		# départ ne recoupe le plafond qu'à ~acos(R / (R + TUNNEL_H)) du début)
		line = PipeBend.join([line, PipeBend.straight(line[line.size() - 1], phi, DIVE_STRAIGHT)])
	_add_chain(line)
	floor_chains.append(line)
	_outer_slab(line, 260.0, true, not dive)   # [BALCONS 1.79] tremplin = balcon
	exit_tips[l] = {"pos": line[line.size() - 1], "heading": phi}
	if dive:
		# PLONGEON : le sol tourne vers le bas (bord arrondi) ; à grande vitesse
		# Pinpouin décollait et passait par-dessus le virage suivant (vu au bot
		# à 1550 px/s). Un PLAFOND à l'extérieur du virage (même centre, rayon
		# + TUNNEL_H) le plaque et le fait plonger dans la bonne direction.
		var center := p0 + Vector2.from_angle(deg_to_rad(STUB_DEG + 90.0)) * radius
		var ceil_line := PackedVector2Array()
		var n_arc := line.size() - 1          # le dernier point est le bout du tout droit
		for i in n_arc:
			ceil_line.append(center + (line[i] - center).normalized() * (radius + TUNNEL_H))
		ceil_line.append(ceil_line[n_arc - 1] + Vector2.from_angle(deg_to_rad(phi)) * DIVE_STRAIGHT)
		_add_chain(ceil_line)
		_roof_slab(ceil_line, true)


## [1.66] Virage AVANT une entrée (hors de la montagne), voir entry_angles.
func _build_entry_bend(l: int, theta: float, radius: float) -> void:
	var mouth := flank_point(l, true)
	if absf(theta - STUB_DEG) < 0.5:
		entry_tips[l] = {"pos": mouth, "heading": STUB_DEG}
		return
	# arc de theta vers 8°, déplacé pour finir pile à l'entrée
	var arc := PipeBend.arc(Vector2.ZERO, theta, STUB_DEG - theta, radius)
	var shift := mouth - arc[arc.size() - 1]
	var floor_line := PackedVector2Array()
	for q in arc:
		floor_line.append(q + shift)
	_add_chain(floor_line)
	floor_chains.append(floor_line)
	_outer_slab(floor_line, 240.0, false, theta > STUB_DEG)   # [BALCONS 1.79] rampe d'accueil = balcon
	entry_tips[l] = {"pos": floor_line[0], "heading": theta}
	if theta < STUB_DEG:
		# ARRIVÉE PAR EN DESSOUS : on monte, le virage tourne vers le bas (le
		# sol est à l'intérieur du virage) ; c'est le PLAFOND, à l'extérieur,
		# qui plaque Pinpouin et le ramène dans la pente du couloir. Plafond =
		# même centre, rayon + TUNNEL_H. Des boosts EN L'AIR au milieu du
		# tube, dans le sens de la marche, gardent la vitesse.
		var center := mouth + Vector2.from_angle(deg_to_rad(STUB_DEG + 90.0)) * radius
		var ceil_line := PackedVector2Array()
		for q in floor_line:
			ceil_line.append(center + (q - center).normalized() * (radius + TUNNEL_H))
		_add_chain(ceil_line)
		_roof_slab(ceil_line, false)
		var n := floor_line.size()
		for k in [int(n * 0.2), int(n * 0.55)]:
			var q: Vector2 = floor_line[k]
			var mid := center + (q - center).normalized() * (radius + TUNNEL_H * 0.5)
			var hd := rad_to_deg((floor_line[k + 1] - floor_line[k]).angle())
			var climb := -hd
			boosts.append({"pos": mid, "rot": hd, "strength": PipeBend.boost_strength_for_slope(climb), "scale": 3.0, "air": true})


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
	_add_chain(top)
	floor_chains.append(top)


func _flank_chains(x: float, top: float, bottom: float, lanes: Array, angles: Array, is_entry: bool) -> void:
	var cuts: Array = []
	for i in lanes.size():
		var ang: float = STUB_DEG                 # [1.66] couloirs toujours à 8°
		var p := node_pos(0 if is_entry else columns, lanes[i])
		var dy := STUB * tan(deg_to_rad(ang))
		var y := p.y - dy if is_entry else p.y + dy
		cuts.append([y - TUNNEL_H, y])
	cuts.sort_custom(func(u, v): return u[0] < v[0])
	var y0 := top
	for cut in cuts:
		_add_chain(PackedVector2Array([Vector2(x, y0), Vector2(x, cut[0])]))
		y0 = cut[1]
	_add_chain(PackedVector2Array([Vector2(x, y0), Vector2(x, bottom)]))


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
	# --- [1.66] blocs des virages hors de la montagne
	for poly in outer_polys:
		var f := Polygon2D.new()
		f.polygon = poly
		f.color = ROCK_COLOR
		f.z_index = 1
		add_child(f)
	# --- [BALCONS 1.79] bouts à l'air libre redessinés en balcons de glace
	var flank_cuts: Array = []   # bandes à retirer des contours (raccord au flanc)
	var balcony_unders: Array = []   # dessous des balcons (collision accrochable)
	for bs in bend_slabs:
		var shape: Array = _balcony_shape(bs[0], bs[1], bs[2])
		var bp := Polygon2D.new()
		bp.name = "Balcon"
		bp.polygon = shape[0]
		bp.color = ROCK_COLOR      # même glace que la montagne (restylée par IceStyle)
		bp.z_index = 1
		add_child(bp)
		# fin contour sur le DESSOUS seulement (pas contre la caverne)
		var under_rim := Line2D.new()
		under_rim.points = shape[1]
		under_rim.width = 6.0
		under_rim.default_color = RIM_COLOR
		under_rim.joint_mode = Line2D.LINE_JOINT_ROUND
		under_rim.z_index = 2
		add_child(under_rim)
		flank_cuts.append(shape[2])
		balcony_unders.append(shape[1])
	# --- voile de glace dans les galeries (léger : on voit le décor à travers)
	if not sketch_only:
		var glass := Node2D.new()
		glass.name = "Glace"
		glass.z_index = -5
		add_child(glass)
		for poly in glass_polys:       # [1.65] pas de voile dans les fentes du vide
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
	# [1.65] les plafonds accrochables : un corps à part, HORS du groupe
	# « no_hook » (même calque 2 : le pingouin et le grappin les touchent)
	var ceil_body := StaticBody2D.new()
	ceil_body.name = "Plafonds"
	ceil_body.collision_layer = 2
	add_child(ceil_body)
	var rims := Node2D.new()
	rims.z_index = 2
	add_child(rims)
	# [BALCONS 1.79] choix de l'équipe : le DESSOUS des balcons (stalactites)
	# est accrochable au grappin, comme les plafonds à stalactites des
	# cavernes (même corps « Plafonds », hors du groupe no_hook). C'est aussi
	# une vraie surface : Pinpouin ne passe plus à travers le dessous.
	for under in balcony_unders:
		var segs_b := PackedVector2Array()
		for i in under.size() - 1:
			segs_b.append(under[i])
			segs_b.append(under[i + 1])
		var shape_b := ConcavePolygonShape2D.new()
		shape_b.segments = segs_b
		var cs_b := CollisionShape2D.new()
		cs_b.name = "DessousBalcon"
		cs_b.shape = shape_b
		ceil_body.add_child(cs_b)
	# [LISSAGE 1.70] avant de fabriquer les collisions : on recolle les
	# morceaux de sol bout à bout, puis on arrondit leurs cassures (voir
	# _smooth_collision_chains plus bas). Ce sont ces chaînes lissées qui
	# servent aux collisions ET à la bordure dessinée (rims).
	if smooth_floors:
		_smooth_collision_chains()
	for ci in chains.size():
		var ch: PackedVector2Array = chains[ci]
		var segs := PackedVector2Array()
		for i in ch.size() - 1:
			segs.append(ch[i])
			segs.append(ch[i + 1])
		var shape := ConcavePolygonShape2D.new()
		shape.segments = segs
		var cs := CollisionShape2D.new()
		cs.shape = shape
		if chain_hook[ci]:
			ceil_body.add_child(cs)
		else:
			body.add_child(cs)
		# [BALCONS 1.79] pas de trait bleu entre un balcon et la caverne : le
		# morceau de flanc caché derrière le balcon est retiré du contour
		var pieces: Array = [ch]
		for cut in flank_cuts:
			var nxt: Array = []
			for pc in pieces:
				nxt.append_array(Geometry2D.clip_polyline_with_polygon(pc, cut))
			pieces = nxt
		for pc in pieces:
			if pc.size() < 2:
				continue
			var rim := Line2D.new()
			rim.points = pc
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
	# --- [1.65] habillage des plafonds accrochables : bandeau de glace et
	# stalactites (l'œil comprend « ici, le grappin accroche »)
	var stal_noise := FastNoiseLite.new()
	stal_noise.seed = cave_seed * 13 + 5
	stal_noise.frequency = STAL_NOISE_FREQ
	for ch in ceil_chains:
		var ice := Line2D.new()
		ice.texture = CEIL_SMOOTH_TEXTURE      # [1.66] bandeau lisse
		ice.texture_mode = Line2D.LINE_TEXTURE_TILE
		ice.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		ice.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ice.width = 32.0                       # 8 px d'art × 4
		ice.position = Vector2(0, 12)          # le bandeau colle au plafond
		ice.points = ch
		ice.z_index = 3
		add_child(ice)
		_add_stalactites(ch, stal_noise)
	# --- [1.65] boosts (BoostArea en mode turbo)
	for bz in boosts:
		var ba = BOOST_SCENE.instantiate()
		ba.position = bz.pos
		ba.rotation_degrees = bz.rot
		ba.boost_strength = bz.strength
		ba.arrow_scale = bz.scale
		ba.in_air = bz.air
		ba.z_index = 5
		add_child(ba)
	# --- prises (accroches du grappin dans la caverne, avec les plafonds)
	for n in holds:
		_add_hold(n, holds[n])
	# --- [1.64] panneaux (montées obligatoires)
	for sg in signs:
		var spr := Sprite2D.new()
		spr.texture = load("res://sprites/levels/egg/panneau_%s.png" % sg.dir)
		spr.scale = Vector2(5, 5)
		spr.centered = false
		spr.position = sg.pos - Vector2(spr.texture.get_width() * 2.5, spr.texture.get_height() * 5.0 - 6.0)
		spr.z_index = 4
		add_child(spr)


## [1.66] Stalactites le long d'un plafond (voir STAL_*). Elles pendent à la
## verticale ; 4 tailles d'image selon la valeur du bruit.
func _add_stalactites(ch: PackedVector2Array, noise: FastNoiseLite) -> void:
	var dist := STAL_SPACING * 0.5
	var walked := 0.0
	for i in ch.size() - 1:
		var a := ch[i]
		var b := ch[i + 1]
		var seg := a.distance_to(b)
		while dist <= walked + seg and seg > 0.0:
			var p := a.lerp(b, (dist - walked) / seg)
			dist += STAL_SPACING
			# un plafond presque vertical (bord d'un dôme raide) : pas de stalactite
			if absf((b - a).normalized().x) < 0.5:
				continue
			var n := noise.get_noise_2d(p.x + position.x, p.y + position.y)
			if n <= STAL_THRESHOLD:
				continue                              # plafond lisse
			# taille selon la hauteur du bruit (le bruit dépasse rarement 0,6)
			var k := 0
			for lim in STAL_SIZES:
				if n > lim:
					k += 1
			k = clampi(k, 0, 3)
			var spr := Sprite2D.new()
			spr.texture = STAL_TEXTURES[k]
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.scale = Vector2(5, 5)
			spr.centered = false
			spr.offset = Vector2(-spr.texture.get_width() * 0.5, 0)
			spr.position = p + Vector2(0, 16)        # sous le bandeau
			spr.z_index = 3
			add_child(spr)
		walked += seg


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
		"boosts": boosts, "ceilings": ceil_chains.size(),
		"check": check, "attempts": attempts, "paths": paths,
		"COL_W": COL_W, "LANE_GAP": LANE_GAP, "DROP": DROP, "TUNNEL_H": TUNNEL_H}
