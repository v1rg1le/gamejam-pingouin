class_name DrawnLevel
extends RefCounted
# =============================================================================
#  DrawnLevel.gd — [CRÉATEUR 1.45] le niveau DESSINÉ par le joueur
# -----------------------------------------------------------------------------
#  Demande de l'équipe (21/11/2026) : « un mode créateur de niveau où l'on
#  dessine le niveau et les plateformes se forment toutes seules, comme les
#  petits bouts pour utiliser le grappin en plafond ».
#
#  Ce script ne crée AUCUN nœud : il garde le dessin en mémoire et sait le
#  transformer en formes de terrain. Il sert à deux endroits :
#   - l'éditeur (src/screens/LevelEditor.gd) : on y dessine, il affiche
#     l'aperçu des blocs pendant qu'on dessine ;
#   - le niveau jouable (src/levels/LevelDrawn.tscn + DrawnGenerator.gd) :
#     il construit les vrais blocs de glace à partir des mêmes données.
#  Les deux appellent les MÊMES fonctions (islands(), gaps(), hook_list()…) :
#  ce qu'on voit dans l'éditeur est exactement ce qu'on jouera.
#
#  Le principe (cf. le croquis de l'équipe) :
#   1. on dessine seulement le DESSUS du sol (le trait) ;
#   2. chaque trait devient un « îlot » : le jeu le prolonge vers le bas
#      jusqu'à un fond commun (la partie hachurée du croquis) ;
#   3. lever le doigt = fin de l'îlot ; l'espace avant le trait suivant est
#      un TROU (on y meurt si on tombe : la mort par chute existe déjà) ;
#   4. au-dessus des trous trop larges pour un saut, des blocs de glace
#      « accroche-grappin » apparaissent tout seuls (les ronds gris du
#      croquis), et on peut aussi en poser à la main ;
#   5. le départ est au début du premier trait, l'arrivée à la fin du dernier.
#
#  Nettoyage d'un trait à main levée (sinon le pingouin sentirait chaque
#  tremblement du doigt, et les petites arêtes ralentissent la glisse) :
#   a. on ne garde que les points qui vont vers la DROITE ;
#   b. simplification (Ramer-Douglas-Peucker) : on enlève les points inutiles ;
#   c. lissage (Chaikin) : les angles deviennent des courbes ;
#   d. ré-échantillonnage tous les RESAMPLE_STEP px ;
#   e. pente limitée à MAX_SLOPE_DEG (pas de mur vertical infranchissable).
#
#  Le dessin est sauvegardé dans user://niveau_dessine.json à chaque
#  changement : on le retrouve en revenant dans l'éditeur, même après avoir
#  quitté le jeu. (Plusieurs niveaux nommés = étape 3 de la feuille de route.)
# =============================================================================

## Fichier de sauvegarde du dessin en cours
const SAVE_PATH = "user://niveau_dessine.json"
## Version du format (pour pouvoir le faire évoluer plus tard sans tout casser)
const SAVE_VERSION = 1
## Scènes : l'éditeur et le niveau jouable
const EDITOR_SCENE = "res://src/screens/LevelEditor.tscn"
const LEVEL_SCENE = "res://src/levels/LevelDrawn.tscn"

## Un trait plus court que ça (en largeur) est ignoré (un simple clic, un tremblement)
const MIN_STROKE_LENGTH = 220.0
## Tolérance de la simplification : écart max (px du monde) entre le trait et sa version simplifiée
const SIMPLIFY_EPSILON = 14.0
## Nombre de passes de lissage (Chaikin). 3 = bien rond sans trop déformer
const SMOOTH_PASSES = 3
## Écart horizontal entre deux points du sol final
const RESAMPLE_STEP = 32.0
## Pente maximale du sol (le half-pipe monte plus raide, mais un trait
## presque vertical bloquerait le pingouin net)
const MAX_SLOPE_DEG = 60.0
## Deux traits séparés de moins que ça sont recollés en un seul îlot
## (on peut ainsi « reprendre » un trait sans créer de trou minuscule)
const MERGE_GAP = 70.0

## Un trou plus large que ça reçoit des blocs accroche-grappin automatiques
const HOOK_GAP_MIN = 420.0
## Un trou très large reçoit un bloc tous les HOOK_SPACING px environ
const HOOK_SPACING = 950.0
## Hauteur des blocs automatiques au-dessus du bord le plus haut du trou
## (600 dans l'atelier BALANCIER du tuto : testé, on l'attrape bien)
const HOOK_HEIGHT = 600.0
## Un trou plus large que ça, SANS bloc de grappin, est signalé en orange
## (un simple saut ne suffit pas toujours ; avec un tremplin et de la
## vitesse ça peut passer : c'est un conseil, pas une interdiction)
const JUMP_GAP_MAX = 460.0

## Le fond commun des îlots est à cette distance sous le point le plus bas
const FLOOR_MARGIN = 450.0
## Piste plate après l'arrivée (pour freiner sans tomber dans le vide)
const RUNOUT_LENGTH = 1600.0

## Les traits nettoyés (Array de PackedVector2Array, x croissants)
static var strokes: Array = []
## Blocs de grappin posés À LA MAIN (Array de Vector2, position du monde)
static var hooks: Array = []
## Blocs de grappin automatiques au-dessus des trous larges (oui / non)
static var auto_hooks: bool = true
## Le fichier a-t-il déjà été lu depuis le lancement du jeu ?
static var _loaded: bool = false


# --- 1. Nettoyage d'un trait -----------------------------------------------------

## Transforme un trait brut (les positions du doigt / de la souris) en un sol
## propre. Renvoie un tableau VIDE si le trait est trop court.
static func process_stroke(raw: PackedVector2Array) -> PackedVector2Array:
	# a. seulement les points qui avancent vers la droite
	var pts := PackedVector2Array()
	for p in raw:
		if pts.is_empty() or p.x > pts[pts.size() - 1].x + 1.0:
			pts.append(p)
	if pts.size() < 2 or pts[pts.size() - 1].x - pts[0].x < MIN_STROKE_LENGTH:
		return PackedVector2Array()
	# b. simplification
	pts = _simplify(pts, SIMPLIFY_EPSILON)
	# c. lissage (les x restent croissants : chaque nouveau point est un
	#    mélange de deux voisins)
	for i in SMOOTH_PASSES:
		pts = _chaikin(pts)
	# d. un point tous les RESAMPLE_STEP px
	pts = _resample(pts, RESAMPLE_STEP)
	# e. pente maximale
	return _clamp_slope(pts)


## Ramer-Douglas-Peucker : garde les points qui s'écartent de plus de
## `eps` de la droite entre les deux extrémités, récursivement.
static func _simplify(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[pts.size() - 1]
	var best_i := 0
	var best_d := 0.0
	for i in range(1, pts.size() - 1):
		var d: float = Geometry2D.get_closest_point_to_segment(pts[i], a, b).distance_to(pts[i])
		if d > best_d:
			best_d = d
			best_i = i
	if best_d <= eps:
		return PackedVector2Array([a, b])
	var left := _simplify(pts.slice(0, best_i + 1), eps)
	var right := _simplify(pts.slice(best_i), eps)
	left.resize(left.size() - 1)   # le point de coupure est dans les deux moitiés
	left.append_array(right)
	return left


## Lissage de Chaikin : chaque segment est remplacé par deux points placés au
## quart et aux trois quarts ; les extrémités sont conservées.
static func _chaikin(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in pts.size() - 1:
		var p: Vector2 = pts[i]
		var q: Vector2 = pts[i + 1]
		out.append(p.lerp(q, 0.25))
		out.append(p.lerp(q, 0.75))
	out.append(pts[pts.size() - 1])
	return out


## Un point tous les `step` px en x (interpolation linéaire entre les points).
static func _resample(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var x0: float = pts[0].x
	var x1: float = pts[pts.size() - 1].x
	var n: int = maxi(1, int(ceil((x1 - x0) / step)))
	var j := 0
	for k in n + 1:
		var x: float = minf(x0 + k * step, x1)
		while j < pts.size() - 2 and pts[j + 1].x < x:
			j += 1
		var a: Vector2 = pts[j]
		var b: Vector2 = pts[j + 1]
		var t: float = 0.0 if b.x - a.x < 0.001 else clampf((x - a.x) / (b.x - a.x), 0.0, 1.0)
		out.append(Vector2(x, lerpf(a.y, b.y, t)))
	return out


## Limite la pente entre deux points voisins (de gauche à droite). Si le trait
## monte ou descend trop vite, le sol suit à la pente max puis rejoint le trait.
static func _clamp_slope(pts: PackedVector2Array) -> PackedVector2Array:
	var k: float = tan(deg_to_rad(MAX_SLOPE_DEG))
	for i in range(1, pts.size()):
		var dx: float = pts[i].x - pts[i - 1].x
		var dy: float = clampf(pts[i].y - pts[i - 1].y, -dx * k, dx * k)
		pts[i] = Vector2(pts[i].x, pts[i - 1].y + dy)
	return pts


# --- 2. Ajout / retrait de traits ---------------------------------------------

## Ajoute un trait brut. Les parties qui passent AU-DESSUS ou EN DESSOUS d'un
## îlot existant sont retirées (deux sols ne peuvent pas se superposer) : le
## trait est alors coupé en morceaux, chacun nettoyé. Renvoie le nombre de
## morceaux ajoutés (0 = trait ignoré).
static func add_raw_stroke(raw: PackedVector2Array) -> int:
	var pieces: Array = []
	var cur := PackedVector2Array()
	for p in raw:
		if _x_is_taken(p.x):
			if cur.size() > 1:
				pieces.append(cur)
			cur = PackedVector2Array()
		else:
			cur.append(p)
	if cur.size() > 1:
		pieces.append(cur)
	var added := 0
	for piece in pieces:
		var clean := process_stroke(piece)
		if clean.size() >= 2:
			strokes.append(clean)
			added += 1
	strokes.sort_custom(func(a, b): return a[0].x < b[0].x)
	return added


## Vrai si l'abscisse x est déjà couverte par un trait existant.
static func _x_is_taken(x: float) -> bool:
	for s in strokes:
		if x >= s[0].x and x <= s[s.size() - 1].x:
			return true
	return false


## Retire le trait ou le bloc de grappin manuel touché en `pos` (gomme).
## `radius` = tolérance en px du monde. Renvoie vrai si quelque chose a été effacé.
static func erase_at(pos: Vector2, radius: float) -> bool:
	for i in range(hooks.size() - 1, -1, -1):
		if (hooks[i] as Vector2).distance_to(pos) < radius:
			hooks.remove_at(i)
			return true
	for i in strokes.size():
		var s: PackedVector2Array = strokes[i]
		if pos.x >= s[0].x - radius * 0.5 and pos.x <= s[s.size() - 1].x + radius * 0.5:
			if absf(surface_y_of(s, pos.x) - pos.y) < radius * 1.5:
				strokes.remove_at(i)
				return true
	return false


## Pose un bloc de grappin à la main, ou retire celui qui est déjà là.
static func toggle_hook(pos: Vector2, radius: float) -> void:
	for i in hooks.size():
		if (hooks[i] as Vector2).distance_to(pos) < radius:
			hooks.remove_at(i)
			return
	hooks.append(pos)


## Hauteur du sol d'un trait à l'abscisse x (x hors du trait = son bord le plus proche)
static func surface_y_of(s: PackedVector2Array, x: float) -> float:
	if x <= s[0].x:
		return s[0].y
	for i in range(1, s.size()):
		if s[i].x >= x:
			var t: float = (x - s[i - 1].x) / maxf(0.001, s[i].x - s[i - 1].x)
			return lerpf(s[i - 1].y, s[i].y, t)
	return s[s.size() - 1].y


# --- 3. Du dessin au niveau ----------------------------------------------------

## Les îlots du niveau, de gauche à droite : les traits presque collés
## (moins de MERGE_GAP px d'écart) sont recollés en un seul îlot.
static func islands() -> Array:
	var out: Array = []
	for s in strokes:
		var cur: PackedVector2Array = s
		if not out.is_empty():
			var last: PackedVector2Array = out[out.size() - 1]
			if cur[0].x - last[last.size() - 1].x < MERGE_GAP:
				var merged := PackedVector2Array(last)
				merged.append_array(cur)
				out[out.size() - 1] = _clamp_slope(merged)   # pas de marche trop raide au raccord
				continue
		out.append(PackedVector2Array(cur))
	return out


## Les trous entre deux îlots : {x0, x1 (bords), y0, y1 (hauteur des bords), width}
static func gaps(isl: Array) -> Array:
	var out: Array = []
	for i in isl.size() - 1:
		var a: PackedVector2Array = isl[i]
		var b: PackedVector2Array = isl[i + 1]
		var pa: Vector2 = a[a.size() - 1]
		var pb: Vector2 = b[0]
		out.append({"x0": pa.x, "x1": pb.x, "y0": pa.y, "y1": pb.y, "width": pb.x - pa.x})
	return out


## Tous les blocs de grappin du niveau : [{pos: Vector2, auto: bool}]
##  - automatiques : au-dessus des trous de plus de HOOK_GAP_MIN px,
##    un bloc tous les HOOK_SPACING px, HOOK_HEIGHT px au-dessus du bord le plus haut ;
##  - manuels : ceux posés avec l'outil « Grappin ».
static func hook_list(isl: Array) -> Array:
	var out: Array = []
	if auto_hooks:
		for g in gaps(isl):
			if g.width < HOOK_GAP_MIN:
				continue
			var n: int = maxi(1, int(round(g.width / HOOK_SPACING)))
			var top: float = minf(g.y0, g.y1)
			for k in n:
				var x: float = g.x0 + g.width * (k + 0.5) / n
				out.append({"pos": Vector2(x, top - HOOK_HEIGHT), "auto": true})
	for h in hooks:
		out.append({"pos": h, "auto": false})
	return out


## Les grands trous SANS bloc de grappin au-dessus : l'éditeur les montre en
## orange (grappin ou tremplin conseillé).
static func unsafe_gaps(isl: Array) -> Array:
	var all_hooks := hook_list(isl)
	var out: Array = []
	for g in gaps(isl):
		if g.width <= JUMP_GAP_MAX:
			continue
		var covered := false
		for h in all_hooks:
			var p: Vector2 = h.pos
			if p.x > g.x0 - 200.0 and p.x < g.x1 + 200.0:
				covered = true
		if not covered:
			out.append(g)
	return out


## Fond commun des îlots (y du monde, vers le bas = plus grand)
static func floor_y(isl: Array) -> float:
	var lowest := -INF
	for s in isl:
		for p in s:
			lowest = maxf(lowest, p.y)
	return lowest + FLOOR_MARGIN


## Le niveau est-il jouable ? (au moins un îlot)
static func is_playable() -> bool:
	return not strokes.is_empty()


# --- 4. Annuler / sauvegarder -------------------------------------------------

## Copie complète de l'état (pour « Annuler »)
static func snapshot() -> Dictionary:
	var s: Array = []
	for st in strokes:
		s.append(PackedVector2Array(st))
	return {"strokes": s, "hooks": hooks.duplicate(), "auto": auto_hooks}


## Remet un état copié par snapshot()
static func restore(snap: Dictionary) -> void:
	strokes = []
	for st in snap.strokes:
		strokes.append(PackedVector2Array(st))
	hooks = (snap.hooks as Array).duplicate()
	auto_hooks = snap.auto


## Écrit le dessin dans user://niveau_dessine.json
static func save() -> void:
	var data := {"version": SAVE_VERSION, "auto_hooks": auto_hooks, "strokes": [], "hooks": []}
	for s in strokes:
		var flat: Array = []
		for p in s:
			flat.append(snappedf(p.x, 0.1))
			flat.append(snappedf(p.y, 0.1))
		data.strokes.append(flat)
	for h in hooks:
		data.hooks.append([snappedf(h.x, 0.1), snappedf(h.y, 0.1)])
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))


## Relit le dessin sauvegardé (une seule fois par lancement du jeu : ensuite
## la version en mémoire est la plus récente).
static func load_once() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (data is Dictionary) or int(data.get("version", 0)) != SAVE_VERSION:
		return
	strokes = []
	for flat in data.get("strokes", []):
		var s := PackedVector2Array()
		for i in range(0, (flat as Array).size() - 1, 2):
			s.append(Vector2(float(flat[i]), float(flat[i + 1])))
		if s.size() >= 2:
			strokes.append(s)
	hooks = []
	for h in data.get("hooks", []):
		hooks.append(Vector2(float(h[0]), float(h[1])))
	auto_hooks = bool(data.get("auto_hooks", true))
