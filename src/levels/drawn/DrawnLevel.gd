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
			var n: int = maxi(1, int(round(g.width / HOOK_SPACING)))
			var top: float = minf(g.y0, g.y1)
			for k in n:
				var x: float = g.x0 + g.width * (k + 0.5) / n
				out.append({"pos": Vector2(x, top - HOOK_HEIGHT), "auto": true, "rot": 0.0, "scale": 1.0})
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
	"arch", "podium", "bush", "igloo", "colisee", "ice1", "ice2", "ice3"]
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
	return {"type": type, "pos": pos, "rot": 0.0, "scale": 1.0, "props": props}


## Demi-taille d'un objet (zone de caméra : son rectangle ; sinon OBJECT_HALF x taille)
static func object_half(o: Dictionary) -> Vector2:
	if o.type == "camera":
		return Vector2(float(o.props.get("w", 2400.0)), float(o.props.get("h", 1400.0))) * 0.5
	return OBJECT_HALF.get(o.type, Vector2(100, 100)) * float(o.get("scale", 1.0))


## Le point `pos` touche-t-il l'objet ? (rectangle tourné, + tolérance ;
## une zone de caméra ne se touche que par son bord ou son centre, pour ne
## pas empêcher de toucher ce qu'elle contient)
static func object_hit(o: Dictionary, pos: Vector2, radius: float) -> bool:
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
