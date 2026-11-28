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
#  Le dessin est sauvegardé à chaque changement : on le retrouve en revenant
#  dans l'éditeur, même après avoir quitté le jeu.
#  [MES NIVEAUX 1.46] plusieurs niveaux nommés, un fichier chacun dans
#  user://niveaux/ (voir la partie 5 en bas de ce fichier).
# =============================================================================

## Version du format (pour pouvoir le faire évoluer plus tard sans tout casser)
## [CRÉATEUR v2 1.80] format 2 : les prises de grappin ont un angle et une
## taille, et une liste d'objets typés (`objects`) est prête pour les objets
## de la 1.81 (œufs, boosts, départ…). Les fichiers et codes du format 1 se
## lisent toujours (voir _read_file / _apply / decode_code).
const SAVE_VERSION = 2
## Plus vieux format encore lu
const SAVE_VERSION_MIN = 1
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
## [CRÉATEUR v2 1.80] décision de l'équipe (27/11) : PLUS DE LIMITE DE PENTE
## sur les traits (le seul garde-fou sera la validation, en 1.81). La
## constante ne sert plus qu'au raccord de deux traits presque collés (voir
## islands()), pour ne pas créer une marche verticale par accident.
const MAX_SLOPE_DEG = 60.0
## [CRÉATEUR v2 1.80] écart entre deux points du sol le long du trait
## (ré-échantillonnage à la longueur, plus seulement en x : une pente raide
## garde autant de points qu'un plat)
const RESAMPLE_ARC = 32.0
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
## Blocs de grappin posés À LA MAIN.
## [CRÉATEUR v2 1.80] chaque bloc est un Dictionary {pos: Vector2 (monde),
## rot: float (radians), scale: float (1 = taille d'origine)} (avant : un
## simple Vector2). Voir make_hook().
static var hooks: Array = []
## [CRÉATEUR v2 1.80] Objets typés du format 2 : [{type: String, pos: Vector2,
## rot: float, scale: float, props: Dictionary}]. Vide en 1.80 (les prises de
## grappin restent dans `hooks` pour que les niveaux existants gardent la
## même empreinte, donc leurs records) ; les objets de la 1.81 s'y rangeront.
static var objects: Array = []
## Blocs de grappin automatiques au-dessus des trous larges (oui / non)
static var auto_hooks: bool = true
## Le fichier a-t-il déjà été lu depuis le lancement du jeu ?
static var _loaded: bool = false


# --- 1. Nettoyage d'un trait -----------------------------------------------------

## Transforme un trait brut (les positions du doigt / de la souris) en un sol
## propre. Renvoie un tableau VIDE si le trait est trop court.
static func process_stroke(raw: PackedVector2Array) -> PackedVector2Array:
	# [CRÉATEUR v2 1.80] on peut dessiner dans les DEUX sens : un trait tracé
	# de droite à gauche est simplement retourné (le sol se lit toujours de
	# gauche à droite, c'est le sens de la course)
	if raw.size() >= 2 and raw[raw.size() - 1].x < raw[0].x:
		raw = raw.duplicate()
		raw.reverse()
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
	# d. un point tous les RESAMPLE_ARC px LE LONG du trait [CRÉATEUR v2 1.80]
	#    (avant : tous les RESAMPLE_STEP px en x, ce qui laissait très peu de
	#    points dans les pentes raides)
	# e. [CRÉATEUR v2 1.80] plus de pente maximale (décision de l'équipe) :
	#    _clamp_slope n'est plus appelé ici
	return _resample_arc(pts, RESAMPLE_ARC)


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


## [CRÉATEUR v2 1.80] Un point tous les `step` px mesurés LE LONG du trait ;
## les x restent strictement croissants (un sol se lit de gauche à droite),
## même dans une pente presque verticale.
static func _resample_arc(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array([pts[0]])
	var carry := 0.0   # longueur déjà parcourue depuis le dernier point posé
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var seg := a.distance_to(b)
		var d := step - carry
		while d <= seg:
			var q := a.lerp(b, d / maxf(seg, 0.001))
			if q.x > out[out.size() - 1].x + 0.5:
				out.append(q)
			d += step
		carry = seg - (d - step)
	var last: Vector2 = pts[pts.size() - 1]
	if last.x > out[out.size() - 1].x + 0.5:
		out.append(last)
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
	# [OBJETS 1.81] les objets d'abord (dessinés par-dessus le reste)
	for i in range(objects.size() - 1, -1, -1):
		if object_hit(objects[i], pos, radius):
			objects.remove_at(i)
			return true
	for i in range(hooks.size() - 1, -1, -1):
		if (hooks[i].pos as Vector2).distance_to(pos) < radius * maxf(1.0, hooks[i].scale):
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
		if (hooks[i].pos as Vector2).distance_to(pos) < radius:
			hooks.remove_at(i)
			return
	hooks.append(make_hook(pos))


## [CRÉATEUR v2 1.80] Un bloc de grappin posé à la main
static func make_hook(pos: Vector2, rot := 0.0, scale := 1.0) -> Dictionary:
	return {"pos": pos, "rot": rot, "scale": scale}


# --- [CRÉATEUR v2 1.80] Sélection, déplacement, copie --------------------------
# L'outil « Sélection » de l'éditeur touche un bloc de grappin ou un trait
# de sol, le déplace, le copie ou le supprime. Les règles (un seul sol par
# abscisse : deux traits ne se superposent pas) restent celles du dessin.

## Ce qui est sous `pos` : {kind: "hook" | "stroke", index: int} ou {} (rien).
## Les blocs passent avant les traits (ils sont dessinés par-dessus).
static func pick_at(pos: Vector2, radius: float) -> Dictionary:
	# [OBJETS 1.81] {kind: "obj", index} pour un objet de la liste `objects`
	for i in range(objects.size() - 1, -1, -1):
		if object_hit(objects[i], pos, radius):
			return {"kind": "obj", "index": i}
	for i in range(hooks.size() - 1, -1, -1):
		if (hooks[i].pos as Vector2).distance_to(pos) < radius * maxf(1.0, hooks[i].scale):
			return {"kind": "hook", "index": i}
	for i in strokes.size():
		var st: PackedVector2Array = strokes[i]
		if pos.x >= st[0].x - radius * 0.5 and pos.x <= st[st.size() - 1].x + radius * 0.5:
			if absf(surface_y_of(st, pos.x) - pos.y) < radius * 1.5:
				return {"kind": "stroke", "index": i}
	return {}


## Vrai si la bande d'abscisses [x0, x1] ne touche aucun trait (sauf `except_i`)
static func x_range_free(x0: float, x1: float, except_i := -1) -> bool:
	for i in strokes.size():
		if i == except_i:
			continue
		var st: PackedVector2Array = strokes[i]
		if x1 >= st[0].x and x0 <= st[st.size() - 1].x:
			return false
	return true


## Décale un trait de `delta`. Refusé (false, rien ne bouge) s'il viendrait
## au-dessus ou en dessous d'un autre trait.
static func move_stroke(i: int, delta: Vector2) -> bool:
	var st: PackedVector2Array = strokes[i]
	if not x_range_free(st[0].x + delta.x, st[st.size() - 1].x + delta.x, i):
		return false
	var moved := PackedVector2Array()
	for q in st:
		moved.append(q + delta)
	strokes[i] = moved
	strokes.sort_custom(func(a, b): return a[0].x < b[0].x)
	return true


## Copie d'un trait, posée juste après le dernier trait du niveau (à la
## même hauteur de départ que l'original). Renvoie l'index de la copie.
static func duplicate_stroke(i: int) -> int:
	var st: PackedVector2Array = strokes[i]
	var end_x: float = strokes[strokes.size() - 1][strokes[strokes.size() - 1].size() - 1].x
	var delta := Vector2(end_x + 400.0 - st[0].x, 0.0)
	var copy := PackedVector2Array()
	for q in st:
		copy.append(q + delta)
	strokes.append(copy)
	strokes.sort_custom(func(a, b): return a[0].x < b[0].x)
	return strokes.find(copy)


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
			if gap_bridged(g.x0, g.x1):
				continue   # [FORMES 1.83] trou enjambé par un tremplin, un half-pipe…
			var n: int = maxi(1, int(round(g.width / HOOK_SPACING)))
			var top: float = minf(g.y0, g.y1)
			for k in n:
				var x: float = g.x0 + g.width * (k + 0.5) / n
				out.append({"pos": Vector2(x, top - HOOK_HEIGHT), "auto": true, "rot": 0.0, "scale": 1.0})
	# [FORMES 2 1.86] prise automatique de chaque falaise (désactivable dans
	# ses réglages, ou « détachée » en prise normale qu'on déplace à la main)
	for o in objects:
		if str(o.get("type", "")) == "cliff":
			for hp in shape_geometry(o).holds:
				out.append({"pos": hp, "auto": true, "rot": 0.0, "scale": 1.0})
	for h in hooks:
		# [CRÉATEUR v2 1.80] angle et taille du bloc posé à la main
		out.append({"pos": h.pos, "auto": false, "rot": h.rot, "scale": h.scale})
	return out


## Les grands trous SANS bloc de grappin au-dessus : l'éditeur les montre en
## orange (grappin ou tremplin conseillé).
static func unsafe_gaps(isl: Array) -> Array:
	var all_hooks := hook_list(isl)
	var out: Array = []
	for g in gaps(isl):
		if g.width <= JUMP_GAP_MAX:
			continue
		if gap_bridged(g.x0, g.x1):
			continue   # [FORMES 1.83] enjambé par des formes
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
	return not strokes.is_empty() or has_carved()   # [GROTTE 1.87] ou tout en grotte


## [GROTTE 1.87] Le niveau a-t-il au moins une caverne taillée ?
static func has_carved() -> bool:
	for o in objects:
		if str(o.get("type", "")) == "carved":
			return true
	return false


## [CRÉATEUR v2 1.80] Taille d'un bloc de grappin posé à la main (réglage)
const HOOK_SCALE_MIN = 0.5
const HOOK_SCALE_MAX = 2.5


# --- 4. Annuler ----------------------------------------------------------------

## Copie complète de l'état (pour « Annuler »)
static func snapshot() -> Dictionary:
	var s: Array = []
	for st in strokes:
		s.append(PackedVector2Array(st))
	# [CRÉATEUR v2 1.80] copie PROFONDE : les blocs sont des Dictionary
	return {"strokes": s, "hooks": hooks.duplicate(true), "auto": auto_hooks, "objects": objects.duplicate(true)}


## Remet un état copié par snapshot()
static func restore(snap: Dictionary) -> void:
	strokes = []
	for st in snap.strokes:
		strokes.append(PackedVector2Array(st))
	hooks = (snap.hooks as Array).duplicate(true)
	auto_hooks = snap.auto
	objects = (snap.get("objects", []) as Array).duplicate(true)


# --- 5. [MES NIVEAUX 1.46] Plusieurs niveaux nommés -------------------------------
# Demande de l'équipe (21/11, étape 3 de la feuille de route) : garder
# plusieurs niveaux dessinés, avec un nom, et les retrouver dans « Mes
# niveaux » avec record, médaille et fantôme comme les vrais niveaux.
#  - Un fichier par niveau : user://niveaux/<id>.json (nom, dessin, dates).
#    L'id est fixe (créé une fois) : renommer ne change pas l'id.
#  - Le niveau ouvert est mémorisé (current_id, current_name) ; save() écrit
#    ce niveau-là. Un niveau sans aucun trait n'est pas écrit sur le disque
#    (pas de niveaux vides dans la liste).
#  - Records / médailles / scores / fantômes : RaceManager range tout par
#    « chemin de niveau ». Un niveau dessiné reçoit un chemin VIRTUEL
#    res://src/levels/LevelDrawn_<id>_<empreinte>.tscn (race_path()), où
#    l'empreinte change dès qu'on modifie le dessin : un record fait sur
#    l'ancien dessin ne compte plus pour le nouveau (sinon on pourrait
#    raccourcir le niveau puis garder le record). Les fantômes de l'ancien
#    dessin sont effacés en quittant l'éditeur (prune_ghosts).
#  - Reprise de la 1.45 : l'ancien fichier unique user://niveau_dessine.json
#    devient « Mon niveau 1 » (le fichier d'origine est laissé en place).

## Dossier des niveaux dessinés
const LEVELS_DIR = "user://niveaux"
## Ancien fichier unique de la 1.45 (repris une fois comme « Mon niveau 1 »)
const OLD_SAVE_PATH = "user://niveau_dessine.json"
## Longueur max d'un nom de niveau
const NAME_MAX = 24

## Niveau ouvert : identifiant (nom du fichier) et nom affiché
static var current_id: String = ""
static var current_name: String = ""
## Où revenir après une course sur un niveau dessiné : l'éditeur (après
## TESTER) ou la liste « Mes niveaux » (après JOUER)
static var return_scene: String = EDITOR_SCENE
## Écran « Mes niveaux »
const LIST_SCENE = "res://src/screens/MyLevelsScreen.tscn"


## Le dessin en dictionnaire (coordonnées arrondies au 1/10 de px) : sert à
## l'écriture du fichier ET à l'empreinte (mêmes arrondis = même empreinte
## avant et après un passage par le disque).
static func _drawing_data() -> Dictionary:
	var data := {"auto_hooks": auto_hooks, "strokes": [], "hooks": []}
	for s in strokes:
		var flat: Array = []
		for p in s:
			flat.append(snappedf(p.x, 0.1))
			flat.append(snappedf(p.y, 0.1))
		data.strokes.append(flat)
	for h in hooks:
		# [CRÉATEUR v2 1.80] un bloc sans angle ni taille s'écrit comme en
		# format 1 ([x, y]) : les niveaux existants gardent la même empreinte
		# (donc leurs records et fantômes) ; sinon [x, y, angle, taille]
		var rot: float = snappedf(h.rot, 0.001)
		var sc: float = snappedf(h.scale, 0.01)
		if is_zero_approx(rot) and is_equal_approx(sc, 1.0):
			data.hooks.append([snappedf(h.pos.x, 0.1), snappedf(h.pos.y, 0.1)])
		else:
			data.hooks.append([snappedf(h.pos.x, 0.1), snappedf(h.pos.y, 0.1), rot, sc])
	# [CRÉATEUR v2 1.80] objets typés : seulement s'il y en a (même empreinte sinon)
	if not objects.is_empty():
		var objs: Array = []
		for o in objects:
			objs.append({"t": str(o.type), "x": snappedf(o.pos.x, 0.1), "y": snappedf(o.pos.y, 0.1),
				"r": snappedf(o.get("rot", 0.0), 0.001), "s": snappedf(o.get("scale", 1.0), 0.01),
				"p": o.get("props", {})})
		data["objects"] = objs
	return data


## Empreinte du dessin (8 caractères) : change dès que le dessin change
static func content_hash() -> String:
	return JSON.stringify(_drawing_data()).md5_text().substr(0, 8)


## Chemin « virtuel » du niveau ouvert pour RaceManager (records, fantômes…)
static func race_path() -> String:
	return "res://src/levels/LevelDrawn_%s_%s.tscn" % [current_id, content_hash()]


## Écrit le niveau ouvert dans user://niveaux/<id>.json
static func save() -> void:
	if current_id == "":   # (sécurité) niveau sans id : on lui en donne un, sans toucher au dessin
		current_id = "n%d_%04d" % [int(Time.get_unix_time_from_system()), randi() % 10000]
		current_name = next_free_name()
	if is_official:
		return   # [PARTAGE 1.47] niveau de la communauté : lecture seule
	if strokes.is_empty() and hooks.is_empty() and objects.is_empty():
		return   # niveau vide : pas de fichier (il apparaîtra au 1er trait)
	DirAccess.make_dir_recursive_absolute(LEVELS_DIR)
	var path := LEVELS_DIR.path_join(current_id + ".json")
	var data := _drawing_data()
	data["version"] = SAVE_VERSION
	data["name"] = current_name
	data["hash"] = content_hash()
	data["author"] = current_author   # [PARTAGE 1.47] "" = toi ; sinon l'auteur d'un niveau reçu
	var old = _read_file(path)
	data["created"] = old.get("created", Time.get_unix_time_from_system()) if old != null else Time.get_unix_time_from_system()
	# [VALIDATION 1.81] la validation est gardée (elle ne vaut que pour son empreinte)
	if old != null and old.has("validated_hash"):
		data["validated_hash"] = old.validated_hash
		data["gold_time"] = old.get("gold_time", 0.0)
	data["modified"] = Time.get_unix_time_from_system()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()


## Efface les fantômes des anciens dessins du niveau ouvert (appelé en
## quittant l'éditeur : tant qu'on y est, « Annuler » peut revenir au
## dessin d'origine et retrouver son record).
static func prune_ghosts() -> void:
	if current_id != "":
		_delete_ghosts(current_id, content_hash())


## Lit un fichier de niveau (Dictionary) ou null s'il est absent / illisible
static func _read_file(path: String):
	if not FileAccess.file_exists(path):
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	# [CRÉATEUR v2 1.80] formats 1 et 2 acceptés
	if not (data is Dictionary) or int(data.get("version", 0)) < SAVE_VERSION_MIN or int(data.get("version", 0)) > SAVE_VERSION:
		return null
	return data


## Met le dessin d'un dictionnaire lu sur le disque dans les variables du niveau
static func _apply(data: Dictionary) -> void:
	strokes = []
	for flat in data.get("strokes", []):
		var s := PackedVector2Array()
		for i in range(0, (flat as Array).size() - 1, 2):
			s.append(Vector2(float(flat[i]), float(flat[i + 1])))
		if s.size() >= 2:
			strokes.append(s)
	hooks = []
	for h in data.get("hooks", []):
		# [CRÉATEUR v2 1.80] [x, y] (format 1) ou [x, y, angle, taille]
		if (h as Array).size() >= 4:
			hooks.append(make_hook(Vector2(float(h[0]), float(h[1])), float(h[2]), clampf(float(h[3]), HOOK_SCALE_MIN, HOOK_SCALE_MAX)))
		else:
			hooks.append(make_hook(Vector2(float(h[0]), float(h[1]))))
	auto_hooks = bool(data.get("auto_hooks", true))
	objects = []
	for o in data.get("objects", []):
		if o is Dictionary:
			objects.append({"type": str(o.get("t", "")), "pos": Vector2(float(o.get("x", 0)), float(o.get("y", 0))),
				"rot": float(o.get("r", 0.0)), "scale": float(o.get("s", 1.0)), "props": o.get("p", {})})


## Au 1er appel : reprise de l'ancien fichier 1.45, puis ouverture du dernier
## niveau modifié (ou d'un nouveau niveau vide s'il n'y en a aucun).
static func load_once() -> void:
	if _loaded:
		return
	_loaded = true
	if list_levels().is_empty():
		var old = _read_file(OLD_SAVE_PATH)
		if old != null and not (old.get("strokes", []) as Array).is_empty():
			new_level("Mon niveau 1")
			_apply(old)
			save()
			print("[CRÉATEUR] dessin de la 1.45 repris : « Mon niveau 1 »")
			return
	var all := list_levels()
	if all.is_empty():
		new_level(next_free_name())
	else:
		open_level(all[0].id)


## Tous les niveaux enregistrés, du plus récemment modifié au plus ancien :
## [{id, name, modified, hash}]
static func list_levels() -> Array:
	var out: Array = []
	var dir := DirAccess.open(LEVELS_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var data = _read_file(LEVELS_DIR.path_join(file))
		if data == null:
			continue
		out.append({"id": file.get_basename(), "name": str(data.get("name", "?")),
			"modified": float(data.get("modified", 0)), "hash": str(data.get("hash", "")),
			"author": str(data.get("author", ""))})
	out.sort_custom(func(a, b): return a.modified > b.modified)
	return out


## Chemin virtuel (records, médaille…) d'un niveau de la liste
static func race_path_of(entry: Dictionary) -> String:
	return "res://src/levels/LevelDrawn_%s_%s.tscn" % [entry.id, entry.hash]


## Nouveau niveau vide (pas encore écrit : il le sera au 1er trait)
static func new_level(level_name: String) -> void:
	_loaded = true
	current_id = "n%d_%04d" % [int(Time.get_unix_time_from_system()), randi() % 10000]
	current_name = level_name
	current_author = ""
	current_gold = 0.0
	is_official = false
	strokes = []
	hooks = []
	objects = []
	auto_hooks = true


## Ouvre un niveau enregistré
static func open_level(id: String) -> bool:
	var data = _read_file(LEVELS_DIR.path_join(id + ".json"))
	if data == null:
		return false
	_loaded = true
	current_id = id
	current_name = str(data.get("name", "?"))
	current_author = str(data.get("author", ""))
	current_gold = 0.0
	is_official = false
	_apply(data)
	# [VALIDATION 1.81] niveau validé tel quel : son or est le temps du créateur
	if str(data.get("validated_hash", "")) == content_hash():
		current_gold = float(data.get("gold_time", 0.0))
	return true


## Renomme le niveau ouvert (le fichier garde son id)
static func rename(level_name: String) -> void:
	level_name = level_name.strip_edges().left(NAME_MAX)
	if level_name == "":
		return
	current_name = level_name
	save()


## Supprime un niveau et ses fantômes. Si c'était le niveau ouvert, le
## plus récent restant est ouvert (ou un nouveau niveau vide).
static func delete_level(id: String) -> void:
	DirAccess.remove_absolute(LEVELS_DIR.path_join(id + ".json"))
	_delete_ghosts(id, "")
	if id == current_id:
		var all := list_levels()
		if all.is_empty():
			new_level(next_free_name())
		else:
			open_level(all[0].id)


## Efface les fantômes d'un niveau dessiné (sauf ceux de l'empreinte `keep`)
static func _delete_ghosts(id: String, keep: String) -> void:
	var dir := DirAccess.open("user://ghosts")
	if dir == null:
		return
	var prefix := "LevelDrawn_%s_" % id
	for file in dir.get_files():
		if file.begins_with(prefix) and file.ends_with(".ghost") and (keep == "" or not file.contains(keep)):
			dir.remove(file)


## « Mon niveau N » avec le premier N libre
static func next_free_name() -> String:
	var names := {}
	for e in list_levels():
		names[e.name] = true
	var n := 1
	while names.has("Mon niveau %d" % n):
		n += 1
	return "Mon niveau %d" % n


# --- 6. [PARTAGE 1.47] Code de partage, export, niveaux de la communauté ---------
# Demande de l'équipe (21/11) : partager un niveau dessiné, et pouvoir
# l'exporter pour ajouter au jeu les niveaux qu'on trouve cool.
#  - CODE : "PINPOUIN-NIVEAU:1:<taille>:<base64>:FIN" (même principe que les
#    fantômes en texte de la 1.7 : var_to_bytes -> zstd -> base64). Il
#    contient le nom, l'auteur, le dessin et, au choix, le meilleur fantôme.
#    Quelques Ko sans fantôme, ~10 à 25 Ko avec. ":FIN" marque la fin : on
#    peut coller le code au milieu d'un message.
#  - IMPORT : le niveau arrive dans « Mes niveaux » avec un nouvel id (le
#    fantôme éventuel est rangé sous son chemin de record). bytes_to_var
#    refuse les objets : un code piégé ne peut pas exécuter de code ; tout
#    est vérifié (tailles, nombres finis) avant d'être gardé.
#  - EXPORT FICHIER : le même code dans un fichier texte .pinpouin (dossier
#    ouvrable sur PC, téléchargement dans le navigateur).
#  - NIVEAUX DE LA COMMUNAUTÉ : fichiers JSON (même format qu'un niveau de
#    user://niveaux, + "gold_time" mesuré au bot) dans OFFICIAL_DIR, livrés
#    avec le jeu. Ni modifiables ni supprimables dans le jeu. Records sous
#    l'id "off-<nom du fichier>".

const CODE_PREFIX = "PINPOUIN-NIVEAU:1:"
const CODE_VERSION = 1
## [CRÉATEUR v2 1.80] version de code la plus récente comprise (2 : blocs
## tournés / agrandis, objets typés)
const CODE_VERSION_MAX = 2
## Niveaux de la communauté livrés avec le jeu
const OFFICIAL_DIR = "res://src/levels/drawn/officiels"
## Écran des niveaux de la communauté
const COMMUNITY_SCENE = "res://src/screens/CommunityLevelsScreen.tscn"
## Fichiers exportés sur PC
const EXPORT_DIR = "user://niveaux_exportes"
## Réglage « nom de créateur » (affiché avec les niveaux partagés)
const CONFIG_PATH = "user://pinpouin.cfg"
## Limites de sécurité à l'import
const MAX_STROKES = 300
const MAX_POINTS = 40000
const COORD_MAX = 2000000.0

## Auteur du niveau ouvert ("" = toi), temps de l'or (niveaux officiels, 0 = calculé)
static var current_author: String = ""
static var current_gold: float = 0.0
## Le niveau ouvert est-il un niveau de la communauté (lecture seule) ?
static var is_official: bool = false


## Ton nom de créateur (vide tant qu'il n'a pas été choisi)
static func author_name() -> String:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	return str(cfg.get_value("creator", "author", ""))


static func set_author_name(n: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("creator", "author", n.strip_edges().left(NAME_MAX))
	cfg.save(CONFIG_PATH)


## Auteur à afficher pour un niveau ("" si c'est le tien)
static func author_of(level_id: String) -> String:
	var data = _read_file(LEVELS_DIR.path_join(level_id + ".json"))
	if data == null:
		return ""
	return str(data.get("author", ""))


## Code de partage du niveau `level_id` (avec son meilleur fantôme si
## with_ghost et s'il en a un). "" si le niveau n'existe pas.
static func share_code(level_id: String, with_ghost: bool) -> String:
	var data = _read_file(LEVELS_DIR.path_join(level_id + ".json"))
	if data == null:
		return ""
	var payload := {"v": CODE_VERSION, "name": str(data.get("name", "?")),
		"author": str(data.get("author", "")) if str(data.get("author", "")) != "" else author_name(),
		"auto_hooks": bool(data.get("auto_hooks", true)),
		"strokes": data.get("strokes", []), "hooks": data.get("hooks", [])}
	# [CRÉATEUR v2 1.80] un niveau qui utilise le format 2 (blocs tournés ou
	# agrandis, objets) part en code de version 2 ; sinon le code reste en
	# version 1 et se lit aussi dans les anciennes versions du jeu
	var v2: bool = data.has("objects")
	for h in data.get("hooks", []):
		v2 = v2 or (h as Array).size() >= 4
	if v2:
		payload.v = CODE_VERSION_MAX
		payload["objects"] = data.get("objects", [])
	# [VALIDATION 1.81] le temps du créateur voyage avec le niveau validé :
	# ceux qui le reçoivent ont les mêmes médailles
	if str(data.get("validated_hash", "")) == str(data.get("hash", "")) and float(data.get("gold_time", 0.0)) > 0.0:
		payload["gold"] = float(data.gold_time)
	if with_ghost:
		var g = RaceManager.load_best_ghost(race_path_of({"id": level_id, "hash": str(data.get("hash", ""))}))
		if g != null:
			payload["ghost"] = g
	var raw := var_to_bytes(payload)
	return CODE_PREFIX + str(raw.size()) + ":" + Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_ZSTD)) + ":FIN"


## Le niveau a-t-il un fantôme (meilleur temps) à partager ?
static func has_ghost(entry: Dictionary) -> bool:
	return RaceManager.get_best_time(race_path_of(entry)) >= 0.0


## Lit un code collé. Renvoie {ok: true, data: {...}} ou {ok: false, msg: "..."}.
static func decode_code(text: String) -> Dictionary:
	text = text.strip_edges()
	var start := text.find(CODE_PREFIX)
	if start < 0:
		if text.contains("PINPOUIN-FANTOME"):
			return {"ok": false, "msg": "C'est un code de FANTÔME : colle-le dans Options > échange de fantômes."}
		return {"ok": false, "msg": "Ce texte n'est pas un code de niveau Pinpouin."}
	var rest := text.substr(start + CODE_PREFIX.length())
	var end := rest.find(":FIN")
	if end < 0:
		return {"ok": false, "msg": "Code incomplet : il a été coupé (il doit finir par :FIN)."}
	rest = rest.substr(0, end)
	for ws in [" ", "\n", "\r", "\t"]:   # retours à la ligne ajoutés par les messageries
		rest = rest.replace(ws, "")
	var sep := rest.find(":")
	if sep < 0:
		return {"ok": false, "msg": "Code incomplet (texte coupé ?)."}
	var size := int(rest.substr(0, sep))
	var b64 := rest.substr(sep + 1)
	if RegEx.create_from_string("^[A-Za-z0-9+/]+=*$").search(b64) == null:
		return {"ok": false, "msg": "Code abîmé (caractères en trop ?)."}
	var packed := Marshalls.base64_to_raw(b64)
	if size <= 0 or size > 8_000_000 or packed.is_empty():
		return {"ok": false, "msg": "Code incomplet (texte coupé ?)."}
	var raw := packed.decompress(size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != size:
		return {"ok": false, "msg": "Code abîmé (texte coupé ?)."}
	var data = bytes_to_var(raw)   # sans objets : pas de code exécutable
	if typeof(data) != TYPE_DICTIONARY or int(data.get("v", 0)) < CODE_VERSION or int(data.get("v", 0)) > CODE_VERSION_MAX:
		return {"ok": false, "msg": "Code d'une autre version du jeu, ou abîmé."}
	var err := _validate(data)
	if err != "":
		return {"ok": false, "msg": err}
	return {"ok": true, "data": data}


## Vérifie un niveau reçu (tailles, nombres). "" si tout va bien.
static func _validate(data: Dictionary) -> String:
	if not (data.get("strokes") is Array) or not (data.get("hooks") is Array):
		return "Code abîmé (dessin illisible)."
	var strokes_in: Array = data.strokes
	if strokes_in.is_empty() or strokes_in.size() > MAX_STROKES:
		return "Ce niveau est vide ou trop grand."
	var n := 0
	for flat in strokes_in:
		if not (flat is Array) or (flat as Array).size() < 4 or (flat as Array).size() % 2 != 0:
			return "Code abîmé (trait illisible)."
		n += (flat as Array).size() / 2
		for v in flat:
			if not (typeof(v) in [TYPE_FLOAT, TYPE_INT]) or not is_finite(float(v)) or absf(float(v)) > COORD_MAX:
				return "Code abîmé (nombres invalides)."
	if n > MAX_POINTS or (data.hooks as Array).size() > 500:
		return "Ce niveau est trop grand."
	for h in data.hooks:
		# [CRÉATEUR v2 1.80] [x, y] ou [x, y, angle, taille]
		if not (h is Array) or not ((h as Array).size() in [2, 4]):
			return "Code abîmé (bloc de grappin illisible)."
		for v in h:
			if not (typeof(v) in [TYPE_FLOAT, TYPE_INT]) or not is_finite(float(v)) or absf(float(v)) > COORD_MAX:
				return "Code abîmé (bloc de grappin illisible)."
	if data.has("objects") and (not (data.objects is Array) or (data.objects as Array).size() > 2000):
		return "Code abîmé (objets illisibles)."
	# [OBJETS 1.81] chaque objet : type connu, nombres finis
	for o in data.get("objects", []):
		if not (o is Dictionary) or not (str(o.get("t", "")) in VALID_TYPES):
			return "Code abîmé (objet inconnu)."
		for k in ["x", "y", "r", "s"]:
			var v = o.get(k, 0.0)
			if not (typeof(v) in [TYPE_FLOAT, TYPE_INT]) or not is_finite(float(v)) or absf(float(v)) > COORD_MAX:
				return "Code abîmé (objet illisible)."
		if not (o.get("p", {}) is Dictionary):
			return "Code abîmé (objet illisible)."
	return ""


## Ajoute dans « Mes niveaux » un niveau lu par decode_code(). Le niveau
## ouvert n'est pas changé. Renvoie le message à afficher.
static func import_level(data: Dictionary) -> String:
	load_once()
	var keep := _state()
	# un niveau identique (même dessin) est déjà là ?
	strokes = []
	hooks = []
	_apply({"strokes": data.strokes, "hooks": data.hooks, "auto_hooks": bool(data.get("auto_hooks", true)),
		"objects": data.get("objects", [])})
	var h := content_hash()
	for e in list_levels():
		if e.hash == h:
			var msg := "Tu as déjà ce niveau : « %s »." % e.name
			if data.has("ghost") and _store_ghost(data.ghost, race_path_of(e)):
				msg += "\nSon fantôme a été ajouté."
			_back_to(keep)
			return msg
	var level_name := str(data.get("name", "Niveau reçu")).strip_edges().left(NAME_MAX)
	if level_name == "":
		level_name = "Niveau reçu"
	var names := {}
	for e in list_levels():
		names[e.name] = true
	var final_name := level_name
	var k := 2
	while names.has(final_name):
		final_name = "%s (%d)" % [level_name.left(NAME_MAX - 4), k]
		k += 1
	var snap := snapshot()
	new_level(final_name)
	restore(snap)
	current_author = str(data.get("author", "")).strip_edges().left(NAME_MAX)
	save()
	# [VALIDATION 1.81] niveau reçu validé : on garde son or
	var gold := float(data.get("gold", 0.0)) if (typeof(data.get("gold", 0.0)) in [TYPE_FLOAT, TYPE_INT]) else 0.0
	if gold > 0.0 and gold < 36000.0:
		var path := LEVELS_DIR.path_join(current_id + ".json")
		var fd = _read_file(path)
		if fd != null:
			fd["validated_hash"] = content_hash()
			fd["gold_time"] = gold
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f != null:
				f.store_string(JSON.stringify(fd))
				f.close()
	var msg := "Niveau ajouté : « %s »%s." % [final_name, (" par " + current_author) if current_author != "" else ""]
	if data.has("ghost") and _store_ghost(data.ghost, race_path()):
		msg += "\nAvec son fantôme : à toi de le battre (mode Score) !"
	_back_to(keep)
	return msg


## Range un fantôme reçu sous le chemin de record d'un niveau
static func _store_ghost(g, path: String) -> bool:
	if typeof(g) != TYPE_DICTIONARY or typeof(g.get("samples")) != TYPE_PACKED_FLOAT32_ARRAY \
			or int(g.get("version", 0)) != RaceManager.GHOST_FORMAT_VERSION:
		return false
	g.level = path
	DirAccess.make_dir_recursive_absolute(RaceManager.GHOST_DIR)
	var file := RaceManager.GHOST_DIR.path_join("%s_ami_%d.ghost" % [path.get_file().get_basename(), Time.get_unix_time_from_system()])
	var f := FileAccess.open_compressed(file, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	f.store_var(g)
	f.close()
	RaceManager._best_cache.erase(path)
	return true


## État complet du niveau ouvert (pour y revenir après un import / un calcul)
static func _state() -> Dictionary:
	return {"id": current_id, "name": current_name, "snap": snapshot(), "author": current_author,
		"gold": current_gold, "official": is_official}


## Revient au niveau qui était ouvert avant un import
static func _back_to(keep: Dictionary) -> void:
	current_id = keep.id
	current_name = keep.name
	restore(keep.snap)
	current_author = keep.author
	current_gold = keep.gold
	is_official = keep.official


## Écrit le code dans un fichier .pinpouin. Sur PC : dossier EXPORT_DIR
## (renvoie le chemin) ; dans le navigateur : téléchargement.
static func export_file(level_id: String, level_name: String) -> String:
	var code := share_code(level_id, false)
	if code == "":
		return ""
	var safe := ""
	for c in level_name:
		safe += c if (c.is_valid_identifier() or c in "0123456789-") else "_"
	var file_name := (safe if safe != "" else "niveau") + ".pinpouin"
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(code.to_utf8_buffer(), file_name, "text/plain")
		return file_name
	DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	var path := EXPORT_DIR.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(code + "\n")
	f.close()
	return path


## Niveaux de la communauté : [{id ("off-<fichier>"), slug, name, author, hash, gold}]
static func list_official() -> Array:
	var out: Array = []
	var dir := DirAccess.open(OFFICIAL_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		# dans le jeu exporté, Godot peut lister « x.json.remap » / « .import » : on garde le nom d'origine
		var base := file.replace(".remap", "").replace(".import", "")
		if not base.ends_with(".json"):
			continue
		var slug := base.get_basename()
		var data = _read_file(OFFICIAL_DIR.path_join(base))
		if data == null:
			continue
		var found := false
		for e in out:
			found = found or e.slug == slug
		if found:
			continue
		var tmp := {"id": "off-" + slug, "slug": slug, "name": str(data.get("name", slug)),
			"author": str(data.get("author", "")), "gold": float(data.get("gold_time", 0.0)),
			"order": int(data.get("order", 999)), "hash": ""}
		tmp.hash = _hash_of(data)
		out.append(tmp)
	out.sort_custom(func(a, b): return a.order < b.order or (a.order == b.order and a.name < b.name))
	return out


## Empreinte d'un niveau lu sur le disque (même calcul que content_hash)
static func _hash_of(data: Dictionary) -> String:
	var keep := _state()
	_apply(data)
	var h := content_hash()
	_back_to(keep)
	return h


## Ouvre un niveau de la communauté (lecture seule)
static func open_official(slug: String) -> bool:
	var data = _read_file(OFFICIAL_DIR.path_join(slug + ".json"))
	if data == null:
		return false
	_loaded = true
	current_id = "off-" + slug
	current_name = str(data.get("name", slug))
	current_author = str(data.get("author", ""))
	current_gold = float(data.get("gold_time", 0.0))
	is_official = true
	_apply(data)
	return true


# --- 7. [CRÉATEUR v2 1.80] « Tester d'ici », vue de l'éditeur, préférences ------
# « Tester d'ici » (demande du plan validé le 27/11) : on lance le test à
# l'endroit regardé dans l'éditeur, avec une vitesse de départ réglable.
#  - test_from : point de départ (Vector2.INF = départ normal du niveau) ;
#  - test_speed : vitesse de départ (px/s, vers la droite) ;
#  - une course lancée « d'ici » ne compte JAMAIS (ni record, ni fantôme,
#    ni médaille) : RaceManager garde alors le chemin réel LevelDrawn.tscn,
#    qui n'enregistre rien (voir RaceManager._prepare_level) ;
#  - DrawnGenerator lit ces valeurs à la construction du niveau puis remet
#    test_from à INF (un « Rejouer » repart du vrai départ).
# editor_view garde la caméra de l'éditeur : en revenant d'un test, on
# retrouve l'éditeur exactement là où on l'avait laissé.

## Point de départ du test (INF = départ normal)
static var test_from: Vector2 = Vector2.INF
## Vitesse de départ du test (px/s)
static var test_speed: float = 600.0
## Vue de l'éditeur à retrouver : {pos: Vector2, zoom: float} ({} = cadrer le dessin)
static var editor_view: Dictionary = {}


## Vrai si le prochain lancement du niveau est un « Tester d'ici »
static func testing_from_here() -> bool:
	return test_from != Vector2.INF


## Préférence de l'éditeur (mode Expert, magnétisme…) gardée dans pinpouin.cfg
static func pref(key: String, default_value):
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	return cfg.get_value("creator", key, default_value)


static func set_pref(key: String, value) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("creator", key, value)
	cfg.save(CONFIG_PATH)


## Point de départ pour « Tester d'ici » à l'abscisse x : sur le sol du trait
## qui passe par x (ou du trait le plus proche), 80 px au-dessus.
## Vector2.INF s'il n'y a aucun sol.
static func start_point_near(x: float) -> Vector2:
	var isl := islands()
	if isl.is_empty():
		return Vector2.INF
	var best: PackedVector2Array = isl[0]
	var best_d := INF
	for st in isl:
		var d := 0.0
		if x < st[0].x:
			d = st[0].x - x
		elif x > st[st.size() - 1].x:
			d = x - st[st.size() - 1].x
		if d < best_d:
			best_d = d
			best = st
	var sx := clampf(x, best[0].x + 40.0, best[best.size() - 1].x - 40.0)
	return Vector2(sx, surface_y_of(best, sx) - 80.0)


# --- 8. [OBJETS 1.81] Objets de jeu et décors ---------------------------------------
# Étape 2 du plan du créateur (27/11) : tout ce que les niveaux du jeu savent
# poser devient un objet du créateur. Chaque objet est un Dictionary de la
# liste `objects` : {type, pos, rot, scale, props}. Types et réglages (props) :
#   egg        œuf à grappiner (même collision que le Gruyère : ellipse
#              130 x 170 à l'échelle 1) ; props.style 1 à 5 = les 5 dessins
#              de la 1.79 (glace, tacheté, craquelé, bonnet de neige, bébé) ;
#   boost      flèches « Trackmania » (BoostArea) ; props.strength 0..1
#              (blanc -> jaune -> rouge), props.in_air (boost en l'air) ;
#   start      départ (un seul) ; props.speed = élan de départ (px/s) ;
#   finish     arrivée (une seule ; sinon au bout du dernier trait) ;
#   checkpoint point de passage : après une chute, on repart du dernier atteint ;
#   sign       panneau flèche ; props.dir parmi SIGN_DIRS ;
#   camera     zone de caméra : rectangle props.w x props.h autour de pos ;
#              tant que Pinpouin est dedans, la caméra garde toute la zone
#              à l'écran (dézoom jusqu'à props.zoom) ;
#   arch, podium, bush, igloo, colisee, ice1, ice2, ice3 : décors (scènes
#              du jeu, plantés dans la neige par IceStyle comme partout).

## Scène de chaque décor
const DECOR_SCENES := {
	"arch": "res://src/levels/Arche.tscn",
	"podium": "res://src/levels/decoration/FinishPodium.tscn",
	"bush": "res://src/levels/decoration/Buisson.tscn",
	"igloo": "res://src/levels/decoration/Igloo.tscn",
	"colisee": "res://src/levels/decoration/Colisee.tscn",
	"ice1": "res://src/levels/decoration/IceMedium1.tscn",
	"ice2": "res://src/levels/decoration/IceMedium2.tscn",
	"ice3": "res://src/levels/decoration/IceSmall.tscn",
}
## Directions des panneaux (images sprites/levels/egg/panneau_<dir>.png)
const SIGN_DIRS := ["droite", "haut-droite", "haut", "haut-gauche", "gauche", "bas-gauche", "bas", "bas-droite"]
## Demi-taille (px du monde, échelle 1) de chaque type : sert à toucher l'objet
## dans l'éditeur et à placer les poignées
const OBJECT_HALF := {
	"egg": Vector2(130, 170), "boost": Vector2(130, 70), "start": Vector2(60, 90), "finish": Vector2(80, 220),
	"checkpoint": Vector2(50, 130), "sign": Vector2(110, 110), "arch": Vector2(220, 260), "podium": Vector2(200, 160),
	"bush": Vector2(110, 80), "igloo": Vector2(200, 140), "colisee": Vector2(300, 220), "ice1": Vector2(120, 120),
	"ice2": Vector2(120, 120), "ice3": Vector2(80, 80),
}
## Tous les types connus (vérification des codes reçus)
const VALID_TYPES := ["egg", "boost", "start", "finish", "checkpoint", "sign", "camera",
	"arch", "podium", "bush", "igloo", "colisee", "ice1", "ice2", "ice3",
	# [FORMES 1.83] formes du terrain (voir la partie 10)
	"ramp", "halfpipe", "bowl", "slope", "bend", "upipe", "ceiling", "floating", "wall", "pillar",
	"cave",   # [CAVERNE 1.84]
	"carved",   # [TAILLÉE 1.85]
	"balcony", "stal", "cliff"]   # [FORMES 2 1.86]
## Types dont il ne peut y avoir qu'un seul exemplaire
const UNIQUE_TYPES := ["start", "finish"]

## Rang du prochain œuf posé (dessin du mélange, comme dans le Gruyère)
static var _egg_cycle := 0


## Nouvel objet avec ses réglages par défaut
static func make_object(type: String, pos: Vector2) -> Dictionary:
	var props := {}
	match type:
		"egg":
			props = {"style": 1 + _egg_cycle % 5}
			_egg_cycle += 1
		"boost":
			props = {"strength": 0.35, "in_air": false}
		"start":
			props = {"speed": 0.0}
		"sign":
			props = {"dir": "droite"}
		"camera":
			props = {"w": 2400.0, "h": 1400.0, "zoom": 0.25}
		_:
			if SHAPE_DEFAULTS.has(type):
				props = (SHAPE_DEFAULTS[type] as Dictionary).duplicate()   # [FORMES 1.83] taille « Moyen »
	return {"type": type, "pos": pos, "rot": 0.0, "scale": 1.0, "props": props}


## Demi-taille d'un objet (zone de caméra : son rectangle ; sinon OBJECT_HALF x taille)
static func object_half(o: Dictionary) -> Vector2:
	if is_shape(o):
		return (shape_geometry(o).frame as Rect2).size * 0.5   # [FORMES 1.83]
	if o.type == "camera":
		return Vector2(float(o.props.get("w", 2400.0)), float(o.props.get("h", 1400.0))) * 0.5
	return OBJECT_HALF.get(o.type, Vector2(100, 100)) * float(o.get("scale", 1.0))


## Le point `pos` touche-t-il l'objet ? (rectangle tourné, + tolérance ;
## une zone de caméra ne se touche que par son bord ou son centre, pour ne
## pas empêcher de toucher ce qu'elle contient)
static func object_hit(o: Dictionary, pos: Vector2, radius: float) -> bool:
	if str(o.get("type", "")) == "carved":
		return carved_hit(o, pos, radius)   # [GROTTE 1.87] la roche, pas les galeries
	if is_shape(o):
		return shape_hit(o, pos, radius)   # [FORMES 1.83] la vraie forme, pas un rectangle
	var local: Vector2 = (pos - o.pos).rotated(-float(o.get("rot", 0.0)))
	var h := object_half(o)
	if o.type == "camera":
		var inside := absf(local.x) < h.x + radius * 0.5 and absf(local.y) < h.y + radius * 0.5
		var near_edge := absf(local.x) > h.x - radius * 0.5 or absf(local.y) > h.y - radius * 0.5
		return inside and (near_edge or local.length() < radius)
	return absf(local.x) < h.x + radius * 0.3 and absf(local.y) < h.y + radius * 0.3


## Pose un objet (un départ / une arrivée remplace l'ancien). Renvoie son index.
static func add_object(o: Dictionary) -> int:
	if o.type in UNIQUE_TYPES:
		for i in range(objects.size() - 1, -1, -1):
			if objects[i].type == o.type:
				objects.remove_at(i)
	objects.append(o)
	return objects.size() - 1


## Le premier objet d'un type ({} s'il n'y en a pas)
static func first_object(type: String) -> Dictionary:
	for o in objects:
		if o.type == type:
			return o
	return {}


# --- 9. [VALIDATION 1.81] Finir son niveau pour le partager --------------------------
# Décision de l'équipe (27/11) : pas de limite de pente, mais il faut FINIR
# son niveau pour le partager, et l'or est le temps du créateur (comme dans
# Trackmania). Bouton « ✔ Valider » de l'éditeur : une course en mode Score
# depuis le vrai départ ; à l'arrivée, le temps est gardé avec l'empreinte du
# niveau. Toute modification change l'empreinte : il faut revalider. Un
# meilleur temps de validation améliore l'or. Argent = or + 25 %, bronze =
# or + 60 % (RaceManager, comme les autres niveaux).

## Course de validation en cours (lancée par « ✔ Valider »)
## [UX 1.88] empreinte du niveau au dernier TESTER (étape « Tester » cochée
## tant qu'on ne le modifie pas ; pour la séance)
static var tested_hash := ""
static var validating := false
## Mode de jeu à remettre après la validation (elle se court en mode Score)
static var validation_prev_mode := -1
## Résultat de la dernière validation, pour le message de l'éditeur (0 = aucune)
static var last_validation_time := 0.0


## Vrai si le niveau ouvert est validé tel qu'il est maintenant
static func is_validated() -> bool:
	var data = _read_file(LEVELS_DIR.path_join(current_id + ".json")) if current_id != "" else null
	return data != null and str(data.get("validated_hash", "")) == content_hash() and float(data.get("gold_time", 0.0)) > 0.0


## Or du niveau ouvert s'il est validé (0 sinon)
static func validated_gold() -> float:
	if not is_validated():
		return 0.0
	return float(_read_file(LEVELS_DIR.path_join(current_id + ".json")).get("gold_time", 0.0))


## Vrai si le niveau `entry` de la liste est validé (bouton Partager)
static func entry_validated(entry: Dictionary) -> bool:
	var data = _read_file(LEVELS_DIR.path_join(str(entry.id) + ".json"))
	return data != null and str(data.get("validated_hash", "")) == str(data.get("hash", "")) and float(data.get("gold_time", 0.0)) > 0.0


## Appelé par RaceManager à l'arrivée d'une course de validation
static func record_validation(time: float) -> void:
	validating = false
	last_validation_time = time
	if current_id == "" or is_official:
		return
	save()
	var path := LEVELS_DIR.path_join(current_id + ".json")
	var data = _read_file(path)
	if data == null:
		return
	var h := content_hash()
	var old: float = float(data.get("gold_time", 0.0)) if str(data.get("validated_hash", "")) == h else 0.0
	data["validated_hash"] = h
	data["gold_time"] = time if old <= 0.0 else minf(old, time)
	current_gold = data.gold_time
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data))
		f.close()


# --- 10. [FORMES 1.83] Formes du terrain ------------------------------------------
# Étape 1.83 du plan du créateur (claude/plan-createur-niveau.md) : les
# pièces de glisse et les structures des niveaux du jeu, posées d'un toucher
# et étirées avec des poignées. Choix de l'équipe (28/11) :
#  - une forme posée près du sol S'Y COLLE (son entrée s'aimante au bout
#    d'un trait ou à la sortie d'une autre forme ; sinon, posée juste au-dessus
#    d'un sol, elle se pose dessus) ; posée dans le vide, elle flotte ;
#  - superposition LIBRE : une forme peut passer au-dessus ou en dessous du
#    sol et des autres formes (tunnels, plafonds, étages) ;
#  - en mode Simple : tailles toutes faites (Petit / Moyen / Grand) + poignées.
# Une forme est un objet de la liste `objects` (même format, mêmes gestes,
# même Annuler / Refaire) ; ses dimensions sont dans ses `props`. Toute la
# géométrie est calculée ICI (shape_geometry), pour que l'éditeur dessine
# exactement ce que le jeu construit (DrawnGenerator._add_shape).
#
# Repère local de chaque forme (avant rotation) : x vers la droite, y vers le
# bas, origine = point d'ENTRÉE (là où Pinpouin arrive, au niveau du sol).
#   ramp     tremplin : courbe qui monte de (0,0) à la lèvre (w, -h), angle de
#            sortie `lip` (degrés) ;
#   halfpipe half-pipe creusé : deux murs arrondis et un fond plat, profondeur
#            h, largeur w, petit rebord de chaque côté ;
#   bowl     bol creusé : creux arrondi (cosinus), profondeur h ;
#   slope    rampe à boosts : pente arrondie aux deux bouts, palier en haut,
#            boosts le long de la pente (`strength`) ;
#   bend     virage en pipe : quart de tuyau qui relève Pinpouin, rayon w,
#            angle `angle` (30° à 150°) ;
#   upipe    virage en U : demi-tuyau qui renvoie Pinpouin vers la gauche,
#            diamètre h ;
#   ceiling  plafond : dalle (épaisseur h), accrochable (`hook`, avec
#            stalactites comme les plafonds des cavernes) ou non (lisse) ;
#   floating plateforme flottante : dessus plat, dessous en biseau ;
#   wall     mur : bloc qui monte du sol, hauteur h, épaisseur w ;
#   pillar   pilier : colonne qui descend dans le vide depuis son dessus (Gruyère).

const SHAPE_TYPES := ["ramp", "halfpipe", "bowl", "slope", "bend", "upipe", "ceiling", "floating", "wall", "pillar",
	"cave",   # [CAVERNE 1.84] caverne générée par une graine (voir la partie 11)
	"carved",   # [TAILLÉE 1.85] caverne taillée à la main (voir la partie 12)
	# [FORMES 2 1.86] 2e partie des formes du terrain (voir la partie 13)
	"balcony", "stal", "cliff"]
## Réglages par défaut (taille « Moyen »)
const SHAPE_DEFAULTS := {
	"ramp": {"w": 640.0, "h": 240.0, "lip": 32.0},
	"halfpipe": {"w": 1400.0, "h": 520.0},
	"bowl": {"w": 1200.0, "h": 320.0},
	"slope": {"w": 900.0, "h": 450.0, "strength": 0.6},
	"bend": {"w": 520.0, "angle": 90.0},
	"upipe": {"h": 700.0},
	"ceiling": {"w": 900.0, "h": 130.0, "hook": true},
	"floating": {"w": 640.0, "h": 150.0},
	"wall": {"w": 130.0, "h": 700.0},
	"pillar": {"w": 240.0, "h": 1400.0},
	# [CAVERNE 1.84] graine, longueur (colonnes), étages, étage d'entrée et de
	# sortie, sinuosité (amplitude de la vague, px) et longueur des vagues
	"cave": {"seed": 1.0, "columns": 5.0, "lanes": 3.0, "entry": 0.0, "exit": 2.0, "amp": 900.0, "wave": 2.5},
	# [TAILLÉE 1.85] bloc de départ, taille, contour libre (0..1), opérations
	"carved": {"base": "rect", "w": 3200.0, "h": 1600.0, "outline": [], "ops": []},
	# [FORMES 2 1.86] balcon (longueur, épaisseur à la racine), plateforme-
	# stalactite (longueur, épaisseur), falaise (h = hauteur de la paroi,
	# w = longueur du sommet, holds = prise automatique au-dessus de la paroi)
	"balcony": {"w": 1100.0, "h": 130.0},
	"stal": {"w": 1400.0, "h": 180.0},
	"cliff": {"w": 1400.0, "h": 1100.0, "holds": true},
}
## Tailles toutes faites du mode Simple : facteur sur la largeur et la hauteur
const SHAPE_PRESETS := {"Petit": 0.6, "Moyen": 1.0, "Grand": 1.6}
## Bornes des dimensions (px du monde)
const SHAPE_MIN := 60.0
const SHAPE_MAX := 4000.0
## Formes qui s'aimantent au sol (entrée au bout d'un trait / posées dessus)
const SHAPE_GROUNDED := ["ramp", "halfpipe", "bowl", "slope", "bend", "upipe", "wall", "cave", "carved",
	"balcony", "cliff"]   # [FORMES 2 1.86] le balcon part du bout d'un sol, la falaise monte du sol
## Formes creusées (sous le niveau du sol) : seulement aimantées par les
## bouts (posées au milieu d'un sol, le sol les remplirait)
const SHAPE_DUG := ["halfpipe", "bowl"]
## Distance d'aimantation (px du monde)
const SHAPE_SNAP := 240.0
## Glace sous le niveau du sol des formes posées au sol (pour se fondre dans le sol)
const SHAPE_DEPTH := 260.0
## Rebord plat de chaque côté des formes creusées / avant un virage
const SHAPE_LIP := 70.0
## Épaisseur de glace des tuyaux (virages)
const SHAPE_BAND := 140.0
## Palier en haut de la rampe à boosts
const SLOPE_DECK := 240.0


static func is_shape(o: Dictionary) -> bool:
	return str(o.get("type", "")) in SHAPE_TYPES


## Valeur bornée d'un réglage de forme (les codes reçus ne peuvent pas
## fabriquer de formes géantes)
static func shape_prop(o: Dictionary, key: String) -> float:
	if o.type == "carved" and key in ["w", "h"]:
		# [TAILLÉE 1.85] un bloc à creuser peut être bien plus grand qu'une forme
		var vv = o.props.get(key, SHAPE_DEFAULTS.carved[key])
		var ff := float(vv) if typeof(vv) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(vv)) else float(SHAPE_DEFAULTS.carved[key])
		# [GROTTE 1.87] grand comme un niveau entier
		return clampf(ff, CARVED_MIN, CARVED_MAX_W if key == "w" else CARVED_MAX_H)
	var d = SHAPE_DEFAULTS.get(o.type, {}).get(key, 0.0)
	var v = o.props.get(key, d)
	if typeof(v) == TYPE_BOOL:
		return 1.0 if v else 0.0
	var f := float(v) if typeof(v) in [TYPE_FLOAT, TYPE_INT] else float(d)
	if not is_finite(f):
		f = float(d)
	match key:
		# [CAVERNE 1.84] réglages de la caverne
		"seed":
			return float(clampi(int(f), 1, 99999))
		"columns":
			# au moins 2 colonnes de plus que d'étages (pour descendre d'un étage
			# à l'autre, il faut des salles de croisement)
			return float(clampi(int(f), maxi(3, int(shape_prop(o, "lanes")) + 2), 10))
		"lanes":
			return float(clampi(int(f), 2, 4))
		"entry", "exit":
			return float(clampi(int(f), 0, int(shape_prop(o, "lanes")) - 1))
		"amp":
			return clampf(f, 0.0, 1800.0)
		"wave":
			return clampf(f, 1.0, 6.0)
		"lip":
			return clampf(f, 5.0, 70.0)
		"angle":
			return clampf(f, 30.0, 150.0)
		"strength":
			return clampf(f, 0.0, 1.0)
	return clampf(f, SHAPE_MIN, SHAPE_MAX)


## Géométrie d'une forme, en coordonnées du monde :
##  poly  : contour fermé de la glace (collision et remplissage)
##  top   : la ligne où l'on glisse (bordure de glace du rendu « d'origine »)
##  entry / exit : points d'entrée et de sortie (Vector2.INF si aucun)
##  frame : rectangle utile en repère LOCAL (poignées, sélection)
##  boosts : [{pos, rot}] (rampe à boosts)
## `bottom` (y du monde, facultatif) : fond commun des îlots ; une forme posée
## au sol (et non tournée) descend alors jusque-là, comme les îlots, au lieu
## de s'arrêter SHAPE_DEPTH px sous le sol (sinon : bloc suspendu dans le vide)
static func shape_geometry(o: Dictionary, bottom: float = INF) -> Dictionary:
	var t: String = o.type
	var w := shape_prop(o, "w")
	var h := shape_prop(o, "h")
	var SHAPE_DEPTH: float = DrawnLevel.SHAPE_DEPTH
	if is_finite(bottom) and absf(float(o.get("rot", 0.0))) < 0.01 and t in SHAPE_GROUNDED:
		SHAPE_DEPTH = maxf(SHAPE_DEPTH, bottom - o.pos.y - (h if t in SHAPE_DUG else 0.0))
	var top := PackedVector2Array()
	var poly := PackedVector2Array()
	var entry := Vector2.ZERO
	var exit := Vector2.INF
	var frame := Rect2()
	var boosts: Array = []
	var icicles: Array = []   # [FORMES 2 1.86] glaçons décoratifs [pos locale, longueur]
	var holds: Array = []     # [FORMES 2 1.86] prises automatiques (positions locales)
	match t:
		"balcony":
			# [FORMES 2 1.86] balcon de glace à stalactites (comme ceux du
			# Gruyère, CaveGenerator._balcony_shape style 2) : dalle qui sort du
			# bout du sol, plus fine vers le bout, gouttes rondes dessous, nez
			# arrondi. Choix de l'équipe : dessous TOUJOURS accrochable.
			var b := balcony_outline(w, h)
			top = b[0]
			poly = b[1]
			entry = Vector2(0, 0)
			exit = Vector2(w, 0)
			frame = Rect2(0, 0, w, h + 140.0)
		"stal":
			# [FORMES 2 1.86] plateforme-stalactite de L'Œuf (EggGenerator.
			# _add_left_path) : dessus plat, flancs biseautés, rangée de glaçons
			# dessous (décor seul, comme dans L'Œuf)
			top = PackedVector2Array([Vector2(0, 0), Vector2(w, 0)])
			poly = PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.7),
				Vector2(w - 60.0, h), Vector2(60.0, h), Vector2(0, h * 0.7)])
			icicles = stal_icicles(w, h)
			entry = Vector2.INF
			frame = Rect2(0, 0, w, h)
		"cliff":
			# [FORMES 2 1.86] falaise en montagne du tuto (BateauGenerator.
			# _add_cliff) : paroi de 75 à 100° (petit surplomb), sommet bombé,
			# longue descente douce jusqu'au niveau du départ
			var c := cliff_outline(w, h)
			top = c[0]
			poly = PackedVector2Array([Vector2(0, SHAPE_DEPTH)])
			poly.append_array(top)
			poly.append(Vector2(top[top.size() - 1].x, SHAPE_DEPTH))
			entry = Vector2(0, 0)
			exit = top[top.size() - 1]
			frame = Rect2(0, -h - CLIFF_DOME, exit.x, h + CLIFF_DOME)
			if shape_prop(o, "holds") > 0.5:
				holds.append(c[1])
		"carved":
			# [TAILLÉE 1.85] contour = le bloc de départ ; on se pose sur le sol
			# par le coin bas-gauche (entrée) / bas-droite (sortie)
			poly = carved_base(o)
			top = PackedVector2Array(poly)
			# entrée / sortie un peu AU-DESSUS du bas du bloc : il reste de la
			# roche sous la galerie (sinon le sol s'arrête au ras du bloc et
			# Pinpouin passe dessous) ; prises sur le contour (œuf, rond…)
			var es := carved_entry_exit(o, poly)
			entry = es[0]
			exit = es[1]
			frame = Rect2(0, 0, w, h)
		"cave":
			# [CAVERNE 1.84] contour = la montagne ; entrée / sortie = début du
			# couloir d'entrée et fin du couloir de sortie (sur les flancs)
			var cd := cave_data(o)
			poly = cd.mountain
			for i in range(1, poly.size() - 1):
				top.append(poly[i])
			entry = cd.entry
			exit = cd.exit
			frame = cd.frame
		"ramp":
			# courbe y = -h * x^p : pente nulle au départ, angle `lip` à la lèvre
			var lip := deg_to_rad(shape_prop(o, "lip"))
			var p: float = maxf(1.0, tan(lip) * w / h)
			for i in 25:
				var k := i / 24.0
				top.append(Vector2(w * k, -h * pow(k, p)))
			poly = PackedVector2Array(top)
			poly.append(Vector2(w, SHAPE_DEPTH))
			poly.append(Vector2(0, SHAPE_DEPTH))
			exit = Vector2(w, -h)
			frame = Rect2(0, -h, w, h)
		"halfpipe":
			# rayon des courbes : la profondeur, sans dépasser 45 % de la largeur
			# (au-delà, les murs ont une partie verticale au-dessus de la courbe)
			var r: float = minf(h, w * 0.45)
			top = PackedVector2Array([Vector2(-SHAPE_LIP, 0), Vector2(0, 0)])
			if h - r > 1.0:
				top.append(Vector2(0, h - r))
			for i in range(1, 13):
				var a := PI * 0.5 * i / 12.0   # 0 -> 90° : du mur gauche vers le fond
				top.append(Vector2(r - r * cos(a), h - r + r * sin(a)))
			for i in range(0, 13):
				var a := PI * 0.5 * i / 12.0   # 0 -> 90° : du fond vers le mur droit
				top.append(Vector2(w - r + r * sin(a), h - r + r * cos(a)))
			if h - r > 1.0:
				top.append(Vector2(w, 0))
			top.append(Vector2(w + SHAPE_LIP, 0))
			poly = PackedVector2Array(top)
			poly.append(Vector2(w + SHAPE_LIP, h + SHAPE_DEPTH))
			poly.append(Vector2(-SHAPE_LIP, h + SHAPE_DEPTH))
			entry = Vector2(-SHAPE_LIP, 0)
			exit = Vector2(w + SHAPE_LIP, 0)
			frame = Rect2(0, 0, w, h)
		"bowl":
			top.append(Vector2(-SHAPE_LIP, 0))
			for i in 33:
				var k := i / 32.0
				top.append(Vector2(w * k, h * (1.0 - cos(TAU * k)) * 0.5))
			top.append(Vector2(w + SHAPE_LIP, 0))
			poly = PackedVector2Array(top)
			poly.append(Vector2(w + SHAPE_LIP, h + SHAPE_DEPTH))
			poly.append(Vector2(-SHAPE_LIP, h + SHAPE_DEPTH))
			entry = Vector2(-SHAPE_LIP, 0)
			exit = Vector2(w + SHAPE_LIP, 0)
			frame = Rect2(0, 0, w, h)
		"slope":
			# f(k) = k - sin(2 pi k) / (2 pi) : départ et arrivée à plat, pente au milieu
			for i in 33:
				var k := i / 32.0
				top.append(Vector2(w * k, -h * (k - sin(TAU * k) / TAU)))
			top.append(Vector2(w + SLOPE_DECK, -h))
			poly = PackedVector2Array(top)
			poly.append(Vector2(w + SLOPE_DECK, SHAPE_DEPTH))
			poly.append(Vector2(0, SHAPE_DEPTH))
			exit = Vector2(w + SLOPE_DECK, -h)
			frame = Rect2(0, -h, w + SLOPE_DECK, h)
			var n: int = maxi(1, int(round(w / 320.0)))
			for j in n:
				var k: float = 0.25 + 0.5 * (j + 0.5) / n
				var p0 := Vector2(w * k, -h * (k - sin(TAU * k) / TAU))
				var slope := -h / w * (1.0 - cos(TAU * k))   # dy/dx
				var ang := atan(slope)
				boosts.append({"pos": p0 + Vector2(0, -70).rotated(ang), "rot": ang})
		"bend":
			# quart de tuyau : centre (0, -r) ; on part vers la droite et la
			# piste se relève jusqu'à l'angle choisi
			var r := w
			var amax := deg_to_rad(shape_prop(o, "angle"))
			top.append(Vector2(-SHAPE_LIP, 0))
			for i in 25:
				var a := amax * i / 24.0
				top.append(Vector2(r * sin(a), -r + r * cos(a)))
			poly = PackedVector2Array(top)
			for i in range(24, -1, -1):
				var a := amax * i / 24.0
				poly.append(Vector2((r + SHAPE_BAND) * sin(a), -r + (r + SHAPE_BAND) * cos(a)))
			poly.append(Vector2(-SHAPE_LIP, SHAPE_BAND))
			exit = top[top.size() - 1]
			frame = Rect2(0, -r, r, r)
		"upipe":
			# demi-tuyau : on entre en bas vers la droite, on ressort en haut
			# vers la gauche (la tête en bas, comme dans le Gruyère)
			var rr := h * 0.5
			top.append(Vector2(-SHAPE_LIP, 0))
			for i in 33:
				var a := -PI * 0.5 + PI * i / 32.0
				top.append(Vector2(rr * cos(a), -rr - rr * sin(a)))
			top.append(Vector2(-SHAPE_LIP, -h))
			poly = PackedVector2Array(top)
			poly.append(Vector2(-SHAPE_LIP, -h - SHAPE_BAND))
			for i in range(32, -1, -1):
				var a := -PI * 0.5 + PI * i / 32.0
				poly.append(Vector2((rr + SHAPE_BAND) * cos(a), -rr - (rr + SHAPE_BAND) * sin(a)))
			poly.append(Vector2(-SHAPE_LIP, SHAPE_BAND))
			exit = Vector2(-SHAPE_LIP, -h)
			frame = Rect2(0, -h, rr, h)
		"ceiling":
			# dalle ; accrochable : stalactites rondes dessous (comme les
			# plafonds accrochables des cavernes), sinon dessous lisse
			top = PackedVector2Array([Vector2(0, 0), Vector2(w, 0)])
			poly = PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h)])
			if shape_prop(o, "hook") > 0.5:
				var n: int = maxi(1, int(w / 110.0))
				var step := w / n
				for j in range(n - 1, -1, -1):
					var cx := step * (j + 0.5)
					var dep := 34.0 + 22.0 * float((j * 7) % 3)   # longueurs variées (sans hasard : même forme à chaque fois)
					for q in 7:
						var a := PI * q / 6.0
						poly.append(Vector2(cx + step * 0.45 * cos(a), h + dep * sin(a)))
			poly.append(Vector2(0, h))
			entry = Vector2.INF
			frame = Rect2(0, 0, w, h)
		"floating":
			top = PackedVector2Array([Vector2(0, 0), Vector2(w, 0)])
			var b: float = minf(h * 0.8, w * 0.25)
			poly = PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.35), Vector2(w - b, h), Vector2(b, h), Vector2(0, h * 0.35)])
			entry = Vector2.INF
			frame = Rect2(0, 0, w, h)
		"wall":
			top = PackedVector2Array([Vector2(0, 0), Vector2(0, -h), Vector2(w, -h), Vector2(w, 0)])
			poly = PackedVector2Array([Vector2(0, SHAPE_DEPTH), Vector2(0, -h), Vector2(w, -h), Vector2(w, SHAPE_DEPTH)])
			frame = Rect2(0, -h, w, h)
		"pillar":
			top = PackedVector2Array([Vector2(0, 0), Vector2(w, 0)])
			poly = PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
			entry = Vector2.INF
			frame = Rect2(0, 0, w, h)
	var xf := Transform2D(0.0 if t in ["cave", "carved"] else float(o.get("rot", 0.0)), o.pos)   # (une caverne ne se tourne pas)
	var out := {"poly": xf * poly, "top": xf * top, "frame": frame, "boosts": [], "icicles": [], "holds": [],
		"entry": xf * entry if entry != Vector2.INF else Vector2.INF,
		"exit": xf * exit if exit != Vector2.INF else Vector2.INF}
	for b in boosts:
		out.boosts.append({"pos": xf * b.pos, "rot": b.rot + float(o.get("rot", 0.0))})
	for ic in icicles:
		out.icicles.append([xf * (ic[0] as Vector2), ic[1]])
	for hp in holds:
		out.holds.append(xf * (hp as Vector2))
	return out


## Le point touche-t-il la forme ? (dedans, ou à moins de `radius` / 2 du bord)
static func shape_hit(o: Dictionary, pos: Vector2, radius: float) -> bool:
	var poly: PackedVector2Array = shape_geometry(o).poly
	if Geometry2D.is_point_in_polygon(pos, poly):
		return true
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		if Geometry2D.get_closest_point_to_segment(pos, a, b).distance_to(pos) < radius * 0.5:
			return true
	return false


## Aimante la forme n° i au sol (choix de l'équipe : « se colle au sol ») :
##  1. son entrée au bout d'un trait, ou à la sortie d'une autre forme ;
##  2. sinon sa sortie au début d'un trait, ou à l'entrée d'une autre forme ;
##  3. sinon (formes qui montent du sol) posée sur le sol juste en dessous.
## Renvoie "bout", "sol" ou "" (rien à moins de SHAPE_SNAP : elle flotte).
static func snap_shape(i: int) -> String:
	var o: Dictionary = objects[i]
	if not (o.type in SHAPE_GROUNDED):
		return ""
	var g := shape_geometry(o)
	var ends: Array = []     # où une forme peut COMMENCER
	var starts: Array = []   # où une forme peut FINIR
	for s in strokes:
		ends.append(s[s.size() - 1])
		starts.append(s[0])
	for j in objects.size():
		if j != i and is_shape(objects[j]):
			var gj := shape_geometry(objects[j])
			if gj.exit != Vector2.INF:
				ends.append(gj.exit)
			if gj.entry != Vector2.INF:
				starts.append(gj.entry)
	var best := SHAPE_SNAP
	var move := Vector2.INF
	if g.entry != Vector2.INF:
		for p in ends:
			var d: float = (p as Vector2).distance_to(g.entry)
			if d < best:
				best = d
				move = p - g.entry
	if move == Vector2.INF and g.exit != Vector2.INF:
		for p in starts:
			var d: float = (p as Vector2).distance_to(g.exit)
			if d < best:
				best = d
				move = p - g.exit
	if move != Vector2.INF:
		o.pos += move
		return "bout"
	if o.type in SHAPE_DUG or g.entry == Vector2.INF:
		return ""
	for s in strokes:
		if g.entry.x >= s[0].x and g.entry.x <= s[s.size() - 1].x:
			var dy: float = surface_y_of(s, g.entry.x) - g.entry.y
			if absf(dy) < SHAPE_SNAP * 1.4:
				o.pos.y += dy
				return "sol"
	return ""


## Le trou [x0, x1] est-il enjambé par des formes posées au sol (tremplin,
## half-pipe…) ? Alors pas de grappin automatique ni d'alerte « Grand trou ».
static func gap_bridged(x0: float, x1: float) -> bool:
	var spans: Array = []
	for o in objects:
		if is_shape(o) and o.type in SHAPE_GROUNDED:
			var poly: PackedVector2Array = shape_geometry(o).poly
			var lo := INF
			var hi := -INF
			for p in poly:
				lo = minf(lo, p.x)
				hi = maxf(hi, p.x)
			spans.append(Vector2(lo, hi))
	spans.sort_custom(func(a, b): return a.x < b.x)
	var reach := x0 + 40.0   # (un petit jour de 40 px à chaque bout est toléré)
	for sp in spans:
		if sp.x <= reach:
			reach = maxf(reach, sp.y)
	return reach >= x1 - 40.0


## Bout de la chaîne de formes collées à partir du point `p` (le bout du
## dernier sol, en général) : tant qu'une forme posée au sol a son entrée en
## `p`, on passe à sa sortie. Sert à placer l'arrivée automatique à la fin
## d'un half-pipe ou à la lèvre d'un tremplin collé au bout du niveau (sinon
## la course s'arrêtait à l'entrée de la forme).
static func chain_end(p: Vector2) -> Vector2:
	for _guard in 64:
		var moved := false
		for o in objects:
			if is_shape(o) and o.type in SHAPE_GROUNDED:
				var g := shape_geometry(o)
				if g.entry != Vector2.INF and g.exit != Vector2.INF and g.entry.distance_to(p) < 2.0 and g.exit.x > p.x:
					p = g.exit
					moved = true
					break
		if not moved:
			break
	return p



# --- 11. [CAVERNE 1.84] Caverne générée (gros bloc du créateur) ----------------------
# Demande de l'équipe (28/11) : des cavernes aux trajectoires plus sinueuses
# (hauts, bas, galeries qui se suivent). Dans le créateur, la caverne est une
# « forme » de plus (même aimantation, sélection, survol, Annuler) : c'est le
# MÊME générateur que le Gruyère (CaveGenerator), avec la vague du mode
# sinueux. Une entrée (en haut à gauche par défaut), une sortie (en bas à
# droite par défaut) ; à l'intérieur, les routes se croisent (salles en X et
# en Y), sans cul-de-sac (vérifié par CaveGenerator.check_plan).
# La géométrie est calculée une fois par jeu de réglages (cache).

static var _cave_cache := {}
## Script du générateur, chargé seulement quand on s'en sert : DrawnLevel est
## lu par RaceManager (chargé au démarrage AVANT l'autoload Sfx) ; citer
## CaveGenerator directement faisait compiler trop tôt BoostArea.gd, qui
## utilise Sfx (« Identifier not found: Sfx » : plus aucun boost dans le jeu)
const CAVE_SCRIPT := "res://src/levels/cave/CaveGenerator.gd"


## Générateur de caverne (CaveGenerator) prêt à générer, pas encore dans
## l'arbre, avec les réglages de o
static func make_cave_generator(o: Dictionary) -> Node2D:
	var g = load(CAVE_SCRIPT).new()
	g.cave_seed = int(shape_prop(o, "seed"))
	g.columns = int(shape_prop(o, "columns"))
	var lanes := int(shape_prop(o, "lanes"))
	var e := int(shape_prop(o, "entry"))
	var x := int(shape_prop(o, "exit"))
	g.entry_lanes.assign([e])
	# le nombre d'étages d'une caverne = l'étage le plus bas d'une entrée ou
	# d'une sortie : si ni l'entrée ni la sortie choisies ne sont en bas, une
	# 2e sortie est ouverte à l'étage du bas (sinon la caverne aurait moins
	# d'étages que demandé)
	if maxi(e, x) < lanes - 1:
		g.exit_lanes.assign([x, lanes - 1])
	else:
		g.exit_lanes.assign([x])
	g.sinuous_amp = shape_prop(o, "amp")
	g.sinuous_wave = shape_prop(o, "wave")
	g.max_attempts = 500   # (voir CaveGenerator.max_attempts)
	return g


## Données de dessin et d'aimantation d'une caverne (coordonnées LOCALES) :
## mountain, galleries (polygones creusés), floors (lignes de sol), holds
## (prises), entry, exit, frame, ok (plan vérifié : pas de cul-de-sac)
static func cave_data(o: Dictionary) -> Dictionary:
	var key := "%d|%d|%d|%d|%d|%.0f|%.2f" % [int(shape_prop(o, "seed")), int(shape_prop(o, "columns")), int(shape_prop(o, "lanes")),
		int(shape_prop(o, "entry")), int(shape_prop(o, "exit")), shape_prop(o, "amp"), shape_prop(o, "wave")]
	if _cave_cache.has(key):
		return _cave_cache[key]
	var g = make_cave_generator(o)
	g.generate()
	var fr := Rect2(g.mountain[0], Vector2.ZERO)
	for p in g.mountain:
		fr = fr.expand(p)
	var d := {"mountain": PackedVector2Array(g.mountain), "galleries": g.carved.duplicate(), "floors": g.floor_chains.duplicate(),
		"holds": g.holds.values(), "entry": g.flank_point(g.entry_lanes[0], true), "exit": g.flank_point(g.exit_lanes[0], false),
		"frame": fr, "ok": bool(g.check.get("ok", false)), "outer": g.outer_polys.duplicate()}
	g.free()
	if _cave_cache.size() > 64:
		_cave_cache.clear()
	_cave_cache[key] = d
	return d



# --- 12. [TAILLÉE 1.85] Caverne taillée à la main ------------------------------------
# Demande de l'équipe (28/11) : « partir d'un bloc œuf, rectangulaire ou autre
# et pouvoir le tailler » (« cavernes taillées à la main », pour les distinguer
# des cavernes générées par une graine). Choix : on part d'un bloc rectangle,
# œuf, rond, montagne ou d'un contour libre dessiné au doigt ; on le creuse en
# TRAÇANT la galerie (tunnel de largeur étroite / normale / large, valeur libre
# en Expert), à la PIOCHE (pinceau rond) et on rebouche à la TRUELLE ;
# grappin accroché PARTOUT dans la roche taillée ; avertissement (pas de
# blocage) si aucune galerie ne traverse le bloc de part en part.
#
# Données (props) : base, w, h, outline (contour libre, coordonnées 0..1 du
# bloc), ops = liste des coups dans l'ordre : {k: "tunnel" | "dig" | "fill",
# r: rayon, p: [x0, y0, x1, y1…]} en coordonnées locales du bloc (origine en
# haut à gauche). La roche est RECALCULÉE à partir du bloc et des coups (une
# fois par état : cache), comme le font les cavernes générées :
#  - dessin : tranches verticales de CARVE_SLAB px (bloc ∩ tranche, moins les
#    galeries, plus les rebouchages) : jamais de trou au milieu d'un morceau
#    (tout coup est plus large qu'une tranche) ;
#  - contours : les bords des morceaux, sauf les coupures entre tranches là où
#    il y a de la roche des deux côtés ; orientés roche à DROITE du sens de
#    parcours (comme les bordures des sols : IceStyle pose la neige sur les
#    morceaux tournés vers le haut et un fin contour ailleurs) ;
#  - collisions : ces mêmes contours, en segments (pas d'arêtes intérieures).

const CARVED_BASES := ["rect", "egg", "round", "mountain", "free"]
const CARVED_BASE_NAMES := {"rect": "Rectangle", "egg": "Œuf", "round": "Rond", "mountain": "Montagne", "free": "Forme libre"}
const CARVED_MIN := 600.0
const CARVED_MAX := 9000.0
## [GROTTE 1.87] taille maximale d'un bloc à creuser (demande de l'équipe :
## « grand comme un niveau entier ») ; CARVED_MAX reste la taille Grand
const CARVED_MAX_W := 60000.0
const CARVED_MAX_H := 16000.0
## Largeur des tranches de roche (moins que le plus petit coup : 2 x CARVE_R_MIN)
const CARVE_SLAB := 96.0
## Rayon des coups (px) : un coup plus petit pourrait laisser un trou dans une tranche
const CARVE_R_MIN := 60.0
const CARVE_R_MAX := 900.0
## Hauteur des galeries tracées (choix de l'équipe : 3 tailles, libre en Expert)
const CARVE_WIDTHS := {"Étroite": 300.0, "Normale": 520.0, "Large": 800.0}
## Rayons de la pioche / truelle
const CARVE_BRUSHES := {"Petite": 90.0, "Moyenne": 160.0, "Grosse": 280.0}
## Limites (codes reçus : pas de calcul géant)
const CARVE_MAX_OPS := 1500   # [GROTTE 1.87] 400 -> 1500 (grottes grandes comme un niveau)
const CARVE_MAX_POINTS := 8000

static var _carved_cache := {}


## Contour du bloc de départ (coordonnées locales, origine en haut à gauche)
static func carved_base(o: Dictionary) -> PackedVector2Array:
	var w := shape_prop(o, "w")
	var h := shape_prop(o, "h")
	var b := str(o.props.get("base", "rect"))
	var out := PackedVector2Array()
	match b:
		"egg":
			# même forme que les œufs du jeu (pointe un peu plus fine en haut)
			for i in 48:
				var t := TAU * i / 48.0
				var sn := sin(t)
				out.append(Vector2(w * 0.5 + w * 0.5 / 1.12 * cos(t) * (1.0 + 0.12 * sn), h * 0.5 + h * 0.5 * sn))
		"round":
			for i in 48:
				var t := TAU * i / 48.0
				out.append(Vector2(w * 0.5 + w * 0.5 * cos(t), h * 0.5 + h * 0.5 * sin(t)))
		"mountain":
			# dessous plat, flancs raides, sommet arrondi (comme les falaises du tuto)
			out.append(Vector2(0, h))
			for i in 33:
				var k := i / 32.0
				out.append(Vector2(w * k, h - h * pow(sin(PI * k), 0.55) * (0.92 + 0.08 * cos(TAU * 2.0 * k))))
			out.append(Vector2(w, h))
		"free":
			var fl = o.props.get("outline", [])
			if fl is Array and fl.size() >= 6 and fl.size() <= 2000:
				for i in range(0, fl.size() - 1, 2):
					var x := float(fl[i])
					var y := float(fl[i + 1])
					if is_finite(x) and is_finite(y):
						out.append(Vector2(clampf(x, 0.0, 1.0) * w, clampf(y, 0.0, 1.0) * h))
			if out.size() < 3 or Geometry2D.triangulate_polygon(out).is_empty():
				out = PackedVector2Array()   # contour illisible : rectangle
	if out.size() < 3:
		# rectangle aux coins arrondis
		var r: float = minf(120.0, minf(w, h) * 0.2)
		for q in 4:
			var c: Vector2 = [Vector2(w - r, h - r), Vector2(r, h - r), Vector2(r, r), Vector2(w - r, r)][q]
			for i in 7:
				var a := PI * 0.5 * q + PI * 0.5 * i / 6.0
				out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


## Hauteur de roche gardée sous l'entrée / la sortie (le plancher des galeries)
const CARVE_FLOOR := 260.0


## [TAILLÉE 1.85] Entrée (gauche) et sortie (droite) du bloc : là où la ligne
## « CARVE_FLOOR au-dessus du bas » coupe le contour (le sol s'y colle)
static func carved_entry_exit(o: Dictionary, base: PackedVector2Array = PackedVector2Array()) -> Array:
	if base.is_empty():
		base = carved_base(o)
	var w := shape_prop(o, "w")
	var h := shape_prop(o, "h")
	var y := h - minf(CARVE_FLOOR, h * 0.3)
	var lo := INF
	var hi := -INF
	for i in base.size():
		var a: Vector2 = base[i]
		var b: Vector2 = base[(i + 1) % base.size()]
		if (a.y - y) * (b.y - y) <= 0.0 and absf(b.y - a.y) > 0.001:
			var x := a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y)
			lo = minf(lo, x)
			hi = maxf(hi, x)
	if lo == INF:
		return [Vector2(0, y), Vector2(w, y)]
	return [Vector2(lo, y), Vector2(hi, y)]


## Polygones d'un coup (tunnel / pioche / truelle) : le trait « épaissi » de
## son rayon, bouts arrondis ; un seul point = un rond
static func carve_op_polys(op: Dictionary) -> Array:
	var r := clampf(float(op.get("r", 160.0)) if typeof(op.get("r", 0)) in [TYPE_FLOAT, TYPE_INT] else 160.0, CARVE_R_MIN, CARVE_R_MAX)
	var flat = op.get("p", [])
	var pts := PackedVector2Array()
	if flat is Array:
		for i in range(0, mini(flat.size(), CARVE_MAX_POINTS * 2) - 1, 2):
			var x := float(flat[i]) if typeof(flat[i]) in [TYPE_FLOAT, TYPE_INT] else NAN
			var y := float(flat[i + 1]) if typeof(flat[i + 1]) in [TYPE_FLOAT, TYPE_INT] else NAN
			if is_finite(x) and is_finite(y) and absf(x) < COORD_MAX and absf(y) < COORD_MAX:
				out_append_unique(pts, Vector2(x, y))
	if pts.is_empty():
		return []
	if pts.size() == 1:
		var c := PackedVector2Array()
		for i in 24:
			c.append(pts[0] + Vector2.from_angle(TAU * i / 24.0) * r)
		return [c]
	var res: Array = Geometry2D.offset_polyline(pts, r, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
	var out: Array = []
	for pl in res:
		if not Geometry2D.is_polygon_clockwise(pl) or res.size() == 1:
			out.append(pl)
	return out


static func out_append_unique(pts: PackedVector2Array, p: Vector2) -> void:
	if pts.is_empty() or pts[pts.size() - 1].distance_to(p) > 2.0:
		pts.append(p)


## Bord gauche / droit d'un polygone
static func _x_span(poly: PackedVector2Array) -> Vector2:
	var lo := INF
	var hi := -INF
	for p in poly:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	return Vector2(lo, hi)


## Roche d'une caverne taillée (coordonnées LOCALES), calculée une fois par état :
##  pieces : morceaux de roche (tranches) ; veil : galeries (voile de glace) ;
##  chains : contours orientés (roche à droite) ; segs : collisions (paires de
##  points) ; frame ; crosses : une galerie traverse le bloc de part en part
static func carved_data(o: Dictionary) -> Dictionary:
	# [GROTTE 1.87] clé du cache par hash() (calculé en C++) au lieu du JSON
	# + sha256 : avec une grotte grande comme un niveau, la clé seule coûtait
	# ~5 ms à chaque toucher / survol
	var key := [str(o.props.get("base", "rect")), shape_prop(o, "w"), shape_prop(o, "h"), o.props.get("outline", []), o.props.get("ops", [])].hash()
	if _carved_cache.has(key):
		return _carved_cache[key]
	var base := carved_base(o)
	var fr := Rect2(base[0], Vector2.ZERO)
	for p in base:
		fr = fr.expand(p)
	# coups, dans l'ordre, avec leur étendue en x (pour ne pas les tester partout)
	var ops: Array = []
	var raw_ops = o.props.get("ops", [])
	if raw_ops is Array:
		for op in raw_ops.slice(0, CARVE_MAX_OPS):
			if not (op is Dictionary):
				continue
			var k := str(op.get("k", ""))
			if not (k in ["tunnel", "dig", "fill"]):
				continue
			for pl in carve_op_polys(op):
				ops.append([k, pl, _x_span(pl)])
	# 1) tranches de roche
	var pieces: Array = []     # [poly, slab_left_x]
	var x0: float = floor(fr.position.x / CARVE_SLAB) * CARVE_SLAB
	var x := x0
	while x < fr.end.x:
		var slab := PackedVector2Array([Vector2(x, fr.position.y - 10.0), Vector2(x + CARVE_SLAB, fr.position.y - 10.0),
			Vector2(x + CARVE_SLAB, fr.end.y + 10.0), Vector2(x, fr.end.y + 10.0)])
		var ps: Array = Geometry2D.intersect_polygons(base, slab)
		for op in ops:
			if op[2].y < x or op[2].x > x + CARVE_SLAB:
				continue
			if op[0] == "fill":
				# truelle : on rebouche, mais seulement dans le bloc de départ
				for add in Geometry2D.intersect_polygons(op[1], slab):
					for add2 in Geometry2D.intersect_polygons(add, base):
						var m: PackedVector2Array = add2
						var keep: Array = []
						for pp in ps:
							var mg: Array = Geometry2D.merge_polygons(pp, m)
							var outer: Array = mg.filter(func(q): return not Geometry2D.is_polygon_clockwise(q))
							if outer.size() == 1:
								m = outer[0]
							else:
								keep.append(pp)
						keep.append(m)
						ps = keep
			else:
				var nx: Array = []
				for pp in ps:
					nx.append_array(Geometry2D.clip_polygons(pp, op[1]))
				ps = nx
		for pp in ps:
			if Geometry2D.is_polygon_clockwise(pp) and ps.size() > 1:
				continue   # (trou : ne devrait pas arriver, les coups sont plus larges qu'une tranche)
			if pp.size() >= 3:
				pieces.append([pp, x])
		x += CARVE_SLAB
	# 2) contours : bords des morceaux, orientés roche à droite (-d.y, d.x),
	#    sauf les coupures entre tranches avec de la roche des deux côtés
	var segs: Array = []       # [a, b] orientés
	var cuts := {}             # x de coupure -> {"l": [Vector2(y0, y1)…], "r": […]}
	for pc in pieces:
		var poly: PackedVector2Array = pc[0]
		var sx: float = pc[1]
		var n := poly.size()
		# sens du polygone : la roche est-elle à droite de son 1er bord utile ?
		var flip := false
		for i in n:
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % n]
			if a.distance_to(b) > 1.0:
				var d := (b - a).normalized()
				var probe := (a + b) * 0.5 + Vector2(-d.y, d.x) * 0.5
				flip = not Geometry2D.is_point_in_polygon(probe, poly)
				break
		for i in n:
			var a: Vector2 = poly[i]
			var b: Vector2 = poly[(i + 1) % n]
			if a.distance_to(b) < 0.01:
				continue
			if flip:
				var tmp := a
				a = b
				b = tmp
			var on_l := absf(a.x - sx) < 0.01 and absf(b.x - sx) < 0.01
			var on_r := absf(a.x - sx - CARVE_SLAB) < 0.01 and absf(b.x - sx - CARVE_SLAB) < 0.01
			if on_l or on_r:
				var cx: float = sx if on_l else sx + CARVE_SLAB
				if not cuts.has(cx):
					cuts[cx] = {"l": [], "r": []}
				# roche à gauche de la coupure = morceau de la tranche de gauche (on_r)
				cuts[cx]["l" if on_r else "r"].append(Vector2(minf(a.y, b.y), maxf(a.y, b.y)))
			else:
				segs.append([a, b])
	for cx in cuts:
		var L: Array = _merge_intervals(cuts[cx].l)
		var R: Array = _merge_intervals(cuts[cx].r)
		# roche seulement à gauche : on descend (roche à droite du sens = vers -x)
		for iv in _subtract_intervals(L, R):
			segs.append([Vector2(cx, iv.x), Vector2(cx, iv.y)])
		# roche seulement à droite : on monte
		for iv in _subtract_intervals(R, L):
			segs.append([Vector2(cx, iv.y), Vector2(cx, iv.x)])
	# 3) chaînes (bout à bout) pour les bordures dessinées
	var by_start := {}
	for i in segs.size():
		var k := _pt_key(segs[i][0])
		if not by_start.has(k):
			by_start[k] = []
		by_start[k].append(i)
	var used := {}
	var chains: Array = []
	for i in segs.size():
		if used.has(i):
			continue
		var ch := PackedVector2Array([segs[i][0], segs[i][1]])
		used[i] = true
		var cur := i
		for _guard in segs.size():
			var nk := _pt_key(segs[cur][1])
			var nxt := -1
			for j in by_start.get(nk, []):
				if not used.has(j):
					nxt = j
					break
			if nxt < 0:
				break
			used[nxt] = true
			ch.append(segs[nxt][1])
			cur = nxt
		chains.append(ch)
	var flat_segs := PackedVector2Array()
	for sg in segs:
		flat_segs.append(sg[0])
		flat_segs.append(sg[1])
	# 4) galeries (voile de glace) et avertissement « traverse de part en part »
	var veil: Array = []
	var air: Array = []
	for op in ops:
		if op[0] == "fill":
			continue
		for v in Geometry2D.intersect_polygons(base, op[1]):
			if not Geometry2D.is_polygon_clockwise(v):
				veil.append(v)
		air.append(op[1])
	var crosses := false
	var merged: Array = []
	for a in air:
		var m: PackedVector2Array = a
		var keep: Array = []
		for pp in merged:
			var mg: Array = Geometry2D.merge_polygons(pp, m)
			var outer: Array = mg.filter(func(q): return not Geometry2D.is_polygon_clockwise(q))
			if outer.size() == 1:
				m = outer[0]
			else:
				keep.append(pp)
		keep.append(m)
		merged = keep
	for m in merged:
		var sp := _x_span(m)
		if sp.x <= fr.position.x + 10.0 and sp.y >= fr.end.x - 10.0:
			crosses = true
	# [GROTTE 1.87] index par tranche (x / CARVE_SLAB) : morceaux et segments
	# qui touchent chaque tranche. Un toucher ne teste plus que sa tranche
	# (grotte grande comme un niveau : des milliers de segments)
	var grid := {}
	for pi in pieces.size():
		var gk := int(floor(float(pieces[pi][1]) / CARVE_SLAB))
		if not grid.has(gk):
			grid[gk] = [[], []]
		grid[gk][0].append(pi)
	for k in range(0, flat_segs.size() - 1, 2):
		var sx0 := int(floor(minf(flat_segs[k].x, flat_segs[k + 1].x) / CARVE_SLAB))
		var sx1 := int(floor(maxf(flat_segs[k].x, flat_segs[k + 1].x) / CARVE_SLAB))
		for gk in range(sx0, sx1 + 1):
			if not grid.has(gk):
				grid[gk] = [[], []]
			grid[gk][1].append(k)
	# [GROTTE 1.87] toute la roche (et tout le voile) en UN maillage de
	# triangles, calculé une fois : l'éditeur le dessine d'un seul appel (des
	# centaines de morceaux à trianguler à chaque image faisaient ramer)
	var rock_mesh := _tri_mesh(pieces.map(func(pc): return pc[0]))
	var veil_mesh := _tri_mesh(veil)
	var d := {"pieces": pieces.map(func(pc): return pc[0]), "veil": veil, "chains": chains, "segs": flat_segs,
		"frame": fr, "crosses": crosses, "ops": raw_ops.size() if raw_ops is Array else 0, "grid": grid,
		"rock_mesh": rock_mesh, "veil_mesh": veil_mesh}
	if _carved_cache.size() > 32:
		_carved_cache.clear()
	_carved_cache[key] = d
	return d


static func _pt_key(p: Vector2) -> String:
	return "%d:%d" % [roundi(p.x * 10.0), roundi(p.y * 10.0)]


## Réunion d'intervalles [Vector2(début, fin)…] (triés, fusionnés)
static func _merge_intervals(iv: Array) -> Array:
	var a := iv.duplicate()
	a.sort_custom(func(p, q): return p.x < q.x)
	var out: Array = []
	for v in a:
		if not out.is_empty() and v.x <= out[out.size() - 1].y + 0.01:
			out[out.size() - 1].y = maxf(out[out.size() - 1].y, v.y)
		else:
			out.append(v)
	return out


## A moins B (intervalles réunis)
static func _subtract_intervals(A: Array, B: Array) -> Array:
	var out: Array = []
	for a in A:
		var pieces: Array = [a]
		for b in B:
			var nx: Array = []
			for p in pieces:
				if b.y <= p.x or b.x >= p.y:
					nx.append(p)
					continue
				if b.x > p.x:
					nx.append(Vector2(p.x, b.x))
				if b.y < p.y:
					nx.append(Vector2(b.y, p.y))
			pieces = nx
		for p in pieces:
			if p.y - p.x > 0.5:
				out.append(p)
	return out


# =============================================================================
#  Partie 13 — [FORMES 2 1.86] balcon, plateforme-stalactite, falaise
# =============================================================================
# Choix de l'équipe (28/11) : dessous du balcon TOUJOURS accrochable ;
# plateformes-stalactites posées une par une + bouton « Série » (escalier
# alterné comme le chemin de gauche de L'Œuf) ; falaise avec une prise
# automatique au-dessus de la paroi, désactivable et détachable.

## Profil de la paroi (angle depuis l'horizontale, part de la hauteur) :
## le même que BateauGenerator.FACE_PROFILE (falaises du tuto)
const CLIFF_FACE := [[78.0, 0.22], [90.0, 0.18], [100.0, 0.14], [84.0, 0.22], [76.0, 0.12],
	[55.0, 0.05], [35.0, 0.04], [18.0, 0.03]]
const CLIFF_DOME := 60.0            # le sommet est bombé (arrondi)
const CLIFF_DESCENT := 2.2          # longueur de la descente = 2,2 × hauteur
const CLIFF_HOLD_IN := 200.0        # prise : 200 px après le haut de la paroi…
const CLIFF_HOLD_UP := 300.0        # … et 300 px au-dessus (comme dans le tuto)
## Série de plateformes-stalactites (bouton « Série ») : valeurs de L'Œuf
const STAL_RISE := 760.0            # chaque plateforme est 760 px plus haut
const STAL_HOLD_IN := 60.0          # prise : 60 px du bord, dans la colonne d'en face…
const STAL_HOLD_UP := 300.0         # … 300 px au-dessus du dessus
const STAL_SERIES_MAX := 12


## Balcon : [ligne du dessus, contour] en local (racine en (0, 0))
static func balcony_outline(w: float, h: float) -> Array:
	var top := PackedVector2Array()
	var under := PackedVector2Array()
	var n := maxi(8, int(w / 12.0))
	# gouttes rondes dessous : pas de hasard (même balcon à chaque partie),
	# largeurs et longueurs qui varient selon un motif fixe
	var drips: Array = []
	var x := 70.0
	var k := 0
	while x < w - 60.0:
		var dw: float = 44.0 + 32.0 * float((k * 5) % 4) / 3.0
		drips.append([x + dw * 0.5, dw, (60.0 + 140.0 * float((k * 7) % 5) / 4.0) * (1.0 - 0.6 * x / w)])
		x += dw + 4.0 + 32.0 * float((k * 3) % 3) / 2.0
		k += 1
	for i in n + 1:
		var d := w * i / n
		var u := d / w
		top.append(Vector2(d, 0))
		var base := 0.46 * h + 0.54 * h * (1.0 - u)     # plus fin vers le bout
		var t := base + 140.0 * pow(maxf(0.0, 1.0 - d / 220.0), 2.0)   # congé à la racine
		for dr in drips:
			var dx: float = (d - dr[0]) / (dr[1] * 0.5)
			if absf(dx) < 1.0:
				t = maxf(t, base + dr[2] * sqrt(1.0 - dx * dx))
		var r := minf(t, 70.0)
		if d > w - r:
			var v := (d - (w - r)) / r
			t *= sqrt(maxf(0.0, 1.0 - v * v))
		under.append(Vector2(d, maxf(t, 0.0)))
	var poly := PackedVector2Array(top)
	for i in range(under.size() - 1, -1, -1):
		if under[i].y > 0.5 or i == 0:
			poly.append(under[i])
	return [top, poly]


## Glaçons sous une plateforme-stalactite : [pos locale du haut, longueur]
## (pas de hasard ; pas dans les 300 px du bout gauche, où l'on monte au
## grappin le long du bord dans L'Œuf, ni plus longs que 330 px)
static func stal_icicles(w: float, h: float) -> Array:
	var out: Array = []
	var x := 100.0
	var k := 0
	while x < w - 100.0:
		out.append([Vector2(x, h - 30.0), 140.0 + 190.0 * float((k * 7) % 5) / 4.0])
		x += 110.0 + 150.0 * float((k * 3) % 4) / 3.0
		k += 1
	return out


## Falaise : [ligne du dessus (pied de la paroi en (0, 0), fin de la
## descente à droite au niveau 0), position de la prise]
static func cliff_outline(w: float, h: float) -> Array:
	var top := PackedVector2Array([Vector2.ZERO])
	var x := 0.0
	var y := 0.0
	for sec in CLIFF_FACE:
		var dh: float = h * float(sec[1])
		x += dh / tan(deg_to_rad(float(sec[0])))
		y -= dh
		top.append(Vector2(x, y))
	var hold := Vector2(x + CLIFF_HOLD_IN, y - CLIFF_HOLD_UP)
	# sommet bombé
	for k in range(1, 13):
		var t := k / 12.0
		top.append(Vector2(x + w * t, y - CLIFF_DOME * sin(PI * t)))
	x += w
	# descente douce (profil en cosinus) jusqu'au niveau du pied
	var descent := h * CLIFF_DESCENT
	for k in range(1, 25):
		var t := k / 24.0
		top.append(Vector2(x + descent * t, lerpf(y, 0.0, 0.5 - 0.5 * cos(PI * t))))
	return [top, hold]


## Série de plateformes-stalactites à partir de l'objet n° i (bouton
## « Série ») : `count` plateformes en tout, en escalier alterné (une à
## droite, une à gauche, chacune STAL_RISE plus haut), une prise de grappin
## par marche dans la colonne d'en face (comme dans L'Œuf). Renvoie le
## nombre de plateformes ajoutées.
static func stal_series(i: int, count: int, rise: float = STAL_RISE) -> int:
	var o: Dictionary = objects[i]
	var w := shape_prop(o, "w")
	var added := 0
	# les plateformes alternent autour du bout droit de la première (le
	# « couloir » où l'on monte au grappin)
	var mid_x: float = o.pos.x + w
	for k in range(1, clampi(count, 2, STAL_SERIES_MAX)):
		var q: Dictionary = (o as Dictionary).duplicate(true)
		var right := k % 2 == 1
		q.pos = Vector2(mid_x if right else mid_x - w, o.pos.y - k * rise)
		q.rot = 0.0
		objects.append(q)
		# prise : au-dessus du dessus de la nouvelle plateforme, mais dans la
		# colonne d'en face (sinon le grappin se plante dans son dessous)
		var hold := Vector2(mid_x + (-STAL_HOLD_IN if right else STAL_HOLD_IN), q.pos.y - STAL_HOLD_UP)
		hooks.append(make_hook(hold))
		added += 1
	return added


# =============================================================================
#  Partie 14 — [GROTTE 1.87] grandes cavernes taillées, niveau tout en grotte
# =============================================================================
# Demande de l'équipe (28/11) : une caverne taillée grande comme un niveau,
# pour faire un niveau uniquement dedans, avec boosts, déco… dans les
# galeries. Choix de l'équipe : bouton « Remplir le niveau » ; un toucher
# dans une galerie POSE l'objet choisi (on sélectionne le bloc en touchant sa
# roche).

## Taille du bloc « Remplir le niveau » sur un niveau vide
const FILL_DEFAULT := Vector2(16000, 5000)
## Marges autour du niveau quand on le remplit (gauche, haut, droite, bas)
const FILL_MARGIN := [900.0, 1400.0, 900.0, 1000.0]
## Chambre creusée autour du départ / de l'arrivée posés par « Remplir »
const FILL_ROOM_R := 520.0


## Le point (monde) est-il dans la roche d'une caverne taillée ? (dedans,
## ou à moins de radius / 2 de sa paroi)
static func carved_hit(o: Dictionary, pos: Vector2, radius: float) -> bool:
	var lp: Vector2 = pos - o.pos
	var fr := Rect2(0, 0, shape_prop(o, "w"), shape_prop(o, "h")).grow(minf(radius, 80.0))
	if not fr.has_point(lp):
		return false
	var cd := carved_data(o)
	var grid: Dictionary = cd.grid
	var gk0 := int(floor((lp.x - 80.0) / CARVE_SLAB))
	var gk1 := int(floor((lp.x + 80.0) / CARVE_SLAB))
	for gk in range(gk0, gk1 + 1):
		if grid.has(gk):
			for pi in grid[gk][0]:
				if Geometry2D.is_point_in_polygon(lp, cd.pieces[pi]):
					return true
	# près d'une paroi : seulement à 80 px au plus (une galerie fait ~500 px de
	# haut : avec le rayon de toucher entier, tout toucher dans une galerie
	# aurait pris le bloc au lieu de poser l'objet)
	var near: float = minf(radius * 0.5, 80.0)
	var segs: PackedVector2Array = cd.segs
	for gk in range(gk0, gk1 + 1):
		if grid.has(gk):
			for k in grid[gk][1]:
				if Geometry2D.get_closest_point_to_segment(lp, segs[k], segs[k + 1]).distance_to(lp) < near:
					return true
	return false


## Le point (monde) est-il dans une galerie (de l'air DANS un bloc taillé) ?
static func carved_air_at(pos: Vector2) -> bool:
	for o in objects:
		if str(o.get("type", "")) != "carved":
			continue
		var lp: Vector2 = pos - o.pos
		if not Rect2(0, 0, shape_prop(o, "w"), shape_prop(o, "h")).has_point(lp):
			continue
		if not Geometry2D.is_point_in_polygon(lp, carved_base(o)):
			continue
		if not carved_hit(o, pos, 0.0):
			return true
	return false


## Départ et arrivée par défaut d'un niveau tout en grotte : le bout le plus
## à gauche des galeries creusées (tracer / pioche) et le bout le plus à
## droite ; sans galerie, l'entrée et la sortie du premier bloc
static func carved_default_ends() -> Array:
	var first := Vector2.INF
	var last := Vector2.INF
	for o in objects:
		if str(o.get("type", "")) != "carved":
			continue
		for op in o.props.get("ops", []):
			if not (op is Dictionary) or str(op.get("k", "")) == "fill":
				continue
			var pf: Array = op.get("p", [])
			for k in range(0, pf.size() - 1, 2):
				var q: Vector2 = o.pos + Vector2(float(pf[k]), float(pf[k + 1]))
				if not carved_air_at(q):
					continue   # (bout de galerie hors du bloc ou rebouché)
				if first == Vector2.INF or q.x < first.x:
					first = q
				if last == Vector2.INF or q.x > last.x:
					last = q
	if first == Vector2.INF:
		for o in objects:
			if str(o.get("type", "")) == "carved":
				var g := shape_geometry(o)
				return [g.entry + Vector2(0, -120), g.exit + Vector2(0, -120)]
	return [first, last]


## Rectangle (monde) de tout ce qui est dans le niveau, sauf l'objet n° skip
## (Rect2() si le niveau est vide)
static func level_bounds(skip: int = -1) -> Rect2:
	var r := Rect2()
	var any := false
	var pts := PackedVector2Array()
	for st in strokes:
		pts.append_array(st)
	for h in hooks:
		pts.append(h.pos)
	for i in objects.size():
		if i == skip:
			continue
		var o: Dictionary = objects[i]
		if is_shape(o):
			pts.append_array(shape_geometry(o).poly)
		else:
			pts.append(o.pos)
	for p in pts:
		if not any:
			r = Rect2(p, Vector2.ZERO)
			any = true
		else:
			r = r.expand(p)
	return r if any else Rect2()


## [GROTTE 1.87] Maillage de triangles de plusieurs polygones :
## [points, indices] (les polygones qui ne se triangulent pas sont sautés)
static func _tri_mesh(polys: Array) -> Array:
	var pts := PackedVector2Array()
	var idx := PackedInt32Array()
	for pl in polys:
		var poly: PackedVector2Array = pl
		if poly.size() < 3:
			continue
		var tri := Geometry2D.triangulate_polygon(poly)
		if tri.is_empty():
			continue
		var base := pts.size()
		pts.append_array(poly)
		for t in tri:
			idx.append(base + t)
	return [pts, idx]
