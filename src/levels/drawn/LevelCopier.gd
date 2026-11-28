class_name LevelCopier
extends RefCounted
# =============================================================================
#  LevelCopier.gd — [COPIES DU JEU 1.92] un niveau du jeu -> un niveau du créateur
# -----------------------------------------------------------------------------
#  Choix de l'équipe (28/11) : « Copier les niveaux officiels — tous, même
#  Gruyère et L'Œuf ». Ce script regarde un niveau du jeu DÉJÀ CONSTRUIT
#  (ses générateurs ont tourné : sols, cavernes, prises…) et en fait les
#  données d'un niveau du créateur (même format que les fichiers de « Mes
#  niveaux », voir DrawnLevel._drawing_data). Il ne crée et ne modifie aucun
#  nœud.
#
#  Il est appelé par l'outil tools/copie_niveaux_jeu.gd, qui écrit une copie
#  de chaque niveau dans res://src/levels/drawn/jeu/ (DrawnLevel.GAME_COPY_DIR) :
#  dans le jeu, copier un niveau est alors instantané.
#
#  Ce que devient chaque morceau du niveau :
#   - corps de sol (sol.tscn) et tremplin du départ (Tremplin.tscn) : un
#     TRAIT (le dessus du sol), seulement si RIEN n'est dessous — un trait
#     descend jusqu'au fond commun et engloutirait ce qui est dessous ;
#   - tout autre terrain (sols empilés, half-pipe de l'arrivée, roche de
#     L'Œuf, piliers / balcons / zones de vide du Gruyère, plafonds des
#     niveaux Chill…) : un MORCEAU DE GLACE (« piece »), contour exact ;
#   - cavernes du Gruyère (CaveGenerator) : objet « Caverne » avec ses
#     réglages d'origine (props.cfg), reconstruite par le même générateur ;
#   - prises « poisson » (StaticBody2DFish) et boules de glace (corps rond) :
#     prises de grappin ; œufs du Gruyère : objets « Œuf » ;
#   - boosts, décors (buissons, igloos, glaçons, arche, podium…), ligne
#     d'arrivée, position de départ, points de passage : les objets du créateur.
#  Les niveaux Chill (704, 917) se recopient à l'infini (ChillLoop) : on ne
#  prend que le terrain d'ORIGINE, pas les copies de la boucle.
#  Ce qui n'a pas d'équivalent dans le créateur (panneaux du tuto, logique de
#  caméra de L'Œuf…) est compté dans `skipped` (affiché par l'outil).
# =============================================================================

## Simplification des contours (Ramer-Douglas-Peucker, px) : invisible à l'œil
const SIMPLIFY_EPS := 1.5
## Tolérance « quelque chose est dessous » (px)
const BELOW_MARGIN := 8.0
## Scènes de sol qui peuvent devenir des traits
const STROKE_SCENES := ["sol.tscn", "Tremplin.tscn"]


## Données d'un niveau du créateur à partir du niveau du jeu `root` (déjà
## construit). `info` : {name, order, scene, rules, ambiance}. Renvoie le
## dictionnaire à écrire en JSON, avec en plus "report" (comptes, pour l'outil).
static func capture(root: Node, info: Dictionary) -> Dictionary:
	var report := {"strokes": 0, "pieces": 0, "hooks": 0, "caves": 0, "eggs": 0, "boosts": 0,
		"decor": 0, "skipped": {}}
	var keep_roots := _chill_sources(root)   # [] = tout le niveau
	var solids: Array = []   # {poly (monde), stroke_ok, hook}
	var hooks: Array = []
	var objects: Array = []
	var caves: Array = []
	var segment_sets: Array = []   # contours en segments, traités après (il faut le départ)
	# --- 1. cavernes générées (Gruyère) : objet « Caverne » + leur zone (on
	#        ne recopie pas les corps qu'elles ont construits)
	for n in root.find_children("*", "Node2D", true, false):
		if n.get_script() != null and str(n.get_script().resource_path).ends_with("CaveGenerator.gd"):
			caves.append(n)
			objects.append(_cave_object(n))
			report.caves += 1
	# --- 2. corps solides
	for body in root.find_children("*", "StaticBody2D", true, false):
		if not _kept(body, keep_roots) or _under_any(body, caves) or _is_actor(body):
			continue
		if str(body.scene_file_path).ends_with("StaticBody2DFish.tscn"):
			hooks.append(_hook_entry(body.global_position, body.global_rotation, body.global_scale.x))
			report.hooks += 1
			continue
		var egg := _egg_of(body)
		if not egg.is_empty():
			objects.append(egg)
			report.eggs += 1
			continue
		var stroke_ok := false
		for s in STROKE_SCENES:
			stroke_ok = stroke_ok or str(body.scene_file_path).ends_with(s)
		var hook := not body.is_in_group("no_hook")
		for c in body.get_children():
			if c is CollisionPolygon2D and (c as CollisionPolygon2D).polygon.size() >= 3:
				solids.append({"poly": (c as CollisionPolygon2D).global_transform * (c as CollisionPolygon2D).polygon,
					"stroke_ok": stroke_ok, "hook": hook})
			elif c is CollisionShape2D and (c as CollisionShape2D).shape != null:
				var sh: Shape2D = (c as CollisionShape2D).shape
				var xf: Transform2D = (c as CollisionShape2D).global_transform
				if sh is CircleShape2D:
					# boule de glace à grappiner (L'Œuf, Gruyère) : prise de grappin
					hooks.append(_hook_entry(xf.origin, 0.0, (sh as CircleShape2D).radius * xf.get_scale().x / 55.0))
					report.hooks += 1
				elif sh is RectangleShape2D:
					var e: Vector2 = (sh as RectangleShape2D).size * 0.5
					solids.append({"poly": xf * PackedVector2Array([Vector2(-e.x, -e.y), Vector2(e.x, -e.y), Vector2(e.x, e.y), Vector2(-e.x, e.y)]),
						"stroke_ok": false, "hook": hook})
				elif sh is ConvexPolygonShape2D:
					solids.append({"poly": xf * (sh as ConvexPolygonShape2D).points, "stroke_ok": false, "hook": hook})
				elif sh is ConcavePolygonShape2D:
					# contour en segments (grande caverne qui entoure L'Œuf) : voir _segments_to_solids
					segment_sets.append({"segs": xf * (sh as ConcavePolygonShape2D).segments, "hook": hook})
				else:
					_skip(report, "collision " + sh.get_class())
	# --- 2b. contours en segments : une enceinte (le départ est dedans) devient
	#         un cadre de roche autour ; sinon, un bloc plein
	var player0 := root.get_tree().get_first_node_in_group("player") if root.is_inside_tree() else null
	var start_pos: Vector2 = player0.global_position if player0 != null else Vector2.INF
	for ss in segment_sets:
		for poly in _segments_to_solids(ss.segs, start_pos):
			solids.append({"poly": poly, "stroke_ok": false, "hook": ss.hook})
	# --- 3. traits : le dessus des sols sous lesquels il n'y a rien
	var strokes: Array = []
	for i in solids.size():
		var s: Dictionary = solids[i]
		if not s.stroke_ok:
			continue
		var top := _top_chain(s.poly)
		if top.size() < 2 or _something_below(top, i, solids, caves):
			continue
		var simple := _rdp(top, SIMPLIFY_EPS)
		if simple.size() < 2 or simple[simple.size() - 1].x - simple[0].x < DrawnLevel.MIN_STROKE_LENGTH * 0.5:
			continue
		strokes.append(simple)
		s["as_stroke"] = true
	strokes.sort_custom(func(a, b): return (a as PackedVector2Array)[0].x < (b as PackedVector2Array)[0].x)
	report.strokes = strokes.size()
	# --- 4. morceaux de glace : tout le reste du terrain
	for s in solids:
		if s.get("as_stroke", false):
			continue
		var pc := _piece_object(s.poly, s.hook)
		if pc.is_empty():
			_skip(report, "contour illisible")
			continue
		objects.append(pc)
		report.pieces += 1
	# --- 5. objets : boosts, décors, arrivée, départ, points de passage
	for n in root.find_children("*", "", true, false):
		if not (n is Node2D) or not _kept(n, keep_roots) or _under_any(n, caves) or _is_actor(n):
			continue
		var path := str(n.scene_file_path)
		if path.ends_with("BoostArea.tscn"):
			objects.append({"t": "boost", "x": n.global_position.x, "y": n.global_position.y, "r": n.global_rotation,
				"s": clampf(float(n.get("arrow_scale")) / 2.0, 0.3, 3.0),
				"p": {"strength": clampf(float(n.get("boost_strength")), 0.0, 1.0), "in_air": bool(n.get("in_air"))}})
			report.boosts += 1
		elif path.ends_with("FinishGate.tscn"):
			objects.append({"t": "finish", "x": n.global_position.x, "y": n.global_position.y, "r": 0.0, "s": 1.0, "p": {}})
		elif path != "":
			for t in DrawnLevel.DECOR_SCENES:
				if DrawnLevel.DECOR_SCENES[t] == path:
					objects.append({"t": t, "x": n.global_position.x, "y": n.global_position.y, "r": n.global_rotation,
						"s": n.global_scale.x, "p": {}})
					report.decor += 1
			if path.ends_with("Warning.tscn") or path.ends_with("TutorialSign.tscn"):
				_skip(report, path.get_file())
		elif n.get_script() != null and str(n.get_script().resource_path).ends_with("TutorialSign.gd"):
			_skip(report, "panneau du tuto")
	var player := root.get_tree().get_first_node_in_group("player") if root.is_inside_tree() else null
	if player != null:
		objects.append({"t": "start", "x": player.global_position.x, "y": player.global_position.y, "r": 0.0, "s": 1.0,
			"p": {"speed": 0.0}})
	# points de passage des générateurs (L'Œuf, Gruyère, tuto) : où l'on repart après une chute
	for g in root.get_tree().get_nodes_in_group("course_checkpoints") if root.is_inside_tree() else []:
		var cps = g.get("checkpoints")
		if cps is Array:
			for cp in cps:
				var pos = cp.get("pos") if cp is Dictionary else cp
				if pos is Vector2:
					# le créateur repart 60 px au-dessus du point (DrawnGenerator.respawn_sample) ;
					# les générateurs l'ont déjà compté : on le retire
					var p := {}
					var vel = cp.get("vel") if cp is Dictionary else null
					if vel is Vector2 and absf((vel as Vector2).x - 400.0) > 1.0:
						p["speed"] = clampf(absf((vel as Vector2).x), 0.0, 1200.0)
					objects.append({"t": "checkpoint", "x": pos.x, "y": pos.y + 60.0, "r": 0.0, "s": 1.0, "p": p})
	# --- 6. données du niveau (même format que DrawnLevel._drawing_data)
	var data := {"version": DrawnLevel.SAVE_VERSION, "name": str(info.get("name", "Niveau")), "author": "Pinpouin",
		"order": int(info.get("order", 999)), "scene": str(info.get("scene", "")),
		"auto_hooks": false,   # les prises d'origine suffisent (pas de prises en plus)
		"strokes": [], "hooks": [], "objects": [],
		"rules": info.get("rules", {}), "ambiance": info.get("ambiance", {})}
	for st in strokes:
		var flat: Array = []
		for p in st:
			flat.append(snappedf(p.x, 0.1))
			flat.append(snappedf(p.y, 0.1))
		data.strokes.append(flat)
	for h in hooks:
		data.hooks.append(h)
	for o in objects:
		for k in ["x", "y", "r", "s"]:
			o[k] = snappedf(float(o[k]), 0.001 if k == "r" else 0.1 if k != "s" else 0.01)
		data.objects.append(o)
	data["report"] = report
	return data


# --- outils ----------------------------------------------------------------------

## Niveaux Chill : les nœuds de terrain d'ORIGINE (ChillLoop._sources) ; [] sinon
static func _chill_sources(root: Node) -> Array:
	for n in root.find_children("*", "Node2D", true, false):
		if n.get_script() != null and str(n.get_script().resource_path).ends_with("ChillLoop.gd"):
			var src = n.get("_sources")
			if src is Array and not (src as Array).is_empty():
				return src
	return []


## Le nœud fait-il partie du terrain gardé ? (tout, hors niveaux Chill)
static func _kept(n: Node, keep_roots: Array) -> bool:
	if keep_roots.is_empty():
		return true
	for r in keep_roots:
		if is_instance_valid(r) and (n == r or (r as Node).is_ancestor_of(n)):
			return true
	# les objets hors du terrain bouclé (décor posé à la main…) sont gardés,
	# les copies de la boucle (nœuds ajoutés par ChillLoop) non
	var p := n.get_parent()
	while p != null:
		if p.get_script() != null and str(p.get_script().resource_path).ends_with("ChillLoop.gd"):
			return false
		if str(p.name).begins_with("Plateforms") or str(p.name).begins_with("Objects"):
			return false
		p = p.get_parent()
	return true


static func _under_any(n: Node, parents: Array) -> bool:
	for p in parents:
		if (p as Node).is_ancestor_of(n):
			return true
	return false


## Pingouin, fantôme, interface : pas du terrain
static func _is_actor(n: Node) -> bool:
	var p: Node = n
	while p != null:
		if p is CharacterBody2D or p is CanvasLayer or p.is_in_group("player"):
			return true
		p = p.get_parent()
	return false


static func _skip(report: Dictionary, what: String) -> void:
	report.skipped[what] = int(report.skipped.get(what, 0)) + 1


## Prise de grappin au format des fichiers ([x, y] ou [x, y, angle, taille])
static func _hook_entry(pos: Vector2, rot: float, sc: float) -> Array:
	sc = clampf(sc, DrawnLevel.HOOK_SCALE_MIN, DrawnLevel.HOOK_SCALE_MAX)
	if absf(rot) < 0.001 and absf(sc - 1.0) < 0.01:
		return [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1)]
	return [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1), snappedf(rot, 0.001), snappedf(sc, 0.01)]


## Œuf à grappiner du Gruyère (corps avec le dessin « DessinOeuf », ou ellipse
## de 32 points de la taille d'un œuf) -> objet « Œuf » ; {} sinon
static func _egg_of(body: Node) -> Dictionary:
	var spr := body.get_node_or_null("DessinOeuf")
	var poly: PackedVector2Array
	for c in body.get_children():
		if c is CollisionPolygon2D:
			poly = (c as CollisionPolygon2D).global_transform * (c as CollisionPolygon2D).polygon
	if poly.size() != 32:
		return {}
	var fr := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		fr = fr.expand(p)
	var looks_like := absf(fr.size.x - 2.0 * 130.0 * 1.0) < 60.0 and absf(fr.size.y - 2.0 * 170.0) < 40.0
	if spr == null and not looks_like:
		return {}
	var style := 1
	if spr is Sprite2D and (spr as Sprite2D).texture != null:
		var file := (spr as Sprite2D).texture.resource_path.get_file().get_basename()   # oeuf_<style>
		var i: int = Settings.EGG_STYLES.find(file.trim_prefix("oeuf_"))
		if i > 0:
			style = i
	var c := fr.get_center()
	return {"t": "egg", "x": c.x, "y": c.y, "r": 0.0, "s": snappedf(fr.size.y / 340.0, 0.01), "p": {"style": style}}


## Caverne générée -> objet « Caverne » du créateur, avec ses réglages d'origine
static func _cave_object(g: Node) -> Dictionary:
	var cfg := {"entries": Array(g.entry_lanes), "exits": Array(g.exit_lanes),
		"theta": Array(g.entry_angles), "phi": Array(g.exit_angles),
		"theta_r": Array(g.entry_radii), "phi_r": Array(g.exit_radii),
		"bend_r": g.entry_bend_radius, "columns": g.columns, "balcony": g.balcony_style}
	var lanes := 1
	for l in cfg.entries + cfg.exits:
		lanes = maxi(lanes, int(l) + 1)
	return {"t": "cave", "x": g.global_position.x, "y": g.global_position.y, "r": 0.0, "s": 1.0,
		"p": {"seed": float(g.cave_seed), "columns": float(g.columns), "lanes": float(clampi(lanes, 2, 4)),
			"entry": float(cfg.entries[0]), "exit": float(cfg.exits[0]), "amp": 0.0, "wave": 2.5, "cfg": cfg}}


## Morceau de glace : contour simplifié, en coordonnées locales (coin
## haut-gauche) ; {} si le contour est illisible
static func _piece_object(poly: PackedVector2Array, hook: bool) -> Dictionary:
	var eps := SIMPLIFY_EPS
	var simple := _rdp_closed(poly, eps)
	while simple.size() > DrawnLevel.PIECE_MAX_POINTS and eps < 200.0:
		eps *= 2.0
		simple = _rdp_closed(poly, eps)
	if simple.size() < 3:
		return {}
	var fr := Rect2(simple[0], Vector2.ZERO)
	for p in simple:
		fr = fr.expand(p)
	var flat: Array = []
	for p in simple:
		flat.append(snappedf(p.x - fr.position.x, 0.1))
		flat.append(snappedf(p.y - fr.position.y, 0.1))
	var props := {"pts": flat}
	if not hook:
		props["hook"] = false
	return {"t": "piece", "x": fr.position.x, "y": fr.position.y, "r": 0.0, "s": 1.0, "p": props}


## Dessus d'un contour fermé : de son point le plus à gauche à son point le
## plus à droite, par le côté le plus haut ; vide s'il ne va pas toujours
## vers la droite (sol qui revient en arrière : pas un trait)
static func _top_chain(poly: PackedVector2Array) -> PackedVector2Array:
	var n := poly.size()
	var il := 0
	var ir := 0
	for i in n:
		if poly[i].x < poly[il].x:
			il = i
		if poly[i].x > poly[ir].x:
			ir = i
	var a := PackedVector2Array()   # il -> ir dans un sens
	var b := PackedVector2Array()   # il -> ir dans l'autre
	var i := il
	while true:
		a.append(poly[i])
		if i == ir:
			break
		i = (i + 1) % n
	i = il
	while true:
		b.append(poly[i])
		if i == ir:
			break
		i = (i - 1 + n) % n
	var top := a if _mean_y(a) < _mean_y(b) else b
	var out := PackedVector2Array()
	for p in top:
		if out.is_empty() or p.x > out[out.size() - 1].x + 0.05:
			out.append(p)
		elif p.x < out[out.size() - 1].x - 2.0:
			return PackedVector2Array()   # revient en arrière : pas un trait
	return out


static func _mean_y(p: PackedVector2Array) -> float:
	var s := 0.0
	for q in p:
		s += q.y
	return s / maxf(1.0, p.size())


## Hauteur du trait `top` à l'abscisse x (INF hors du trait)
static func _y_at(top: PackedVector2Array, x: float) -> float:
	if x < top[0].x or x > top[top.size() - 1].x:
		return INF
	var lo := 0
	var hi := top.size() - 1
	while hi - lo > 1:
		var m := (lo + hi) / 2
		if top[m].x <= x:
			lo = m
		else:
			hi = m
	var p: Vector2 = top[lo]
	var q: Vector2 = top[hi]
	return p.y if q.x - p.x < 0.001 else lerpf(p.y, q.y, (x - p.x) / (q.x - p.x))


## Y a-t-il du terrain SOUS le trait (autre corps, caverne) ? Un trait
## descend jusqu'au fond commun : il l'engloutirait.
static func _something_below(top: PackedVector2Array, self_i: int, solids: Array, caves: Array) -> bool:
	for j in solids.size():
		if j == self_i:
			continue
		var poly: PackedVector2Array = solids[j].poly
		var n := poly.size()
		for k in n:
			var p: Vector2 = poly[k]
			var q: Vector2 = poly[(k + 1) % n]
			# le point et quelques points le long du bord (les grands bords droits)
			var steps: int = clampi(int(p.distance_to(q) / 200.0), 0, 50)
			for s in steps + 1:
				var r: Vector2 = p.lerp(q, float(s) / float(steps + 1))
				var y := _y_at(top, r.x)
				if y != INF and r.y > y + BELOW_MARGIN:
					if OS.get_environment("COPIE_DEBUG") != "":
						print("  dessous : trait x=[%d, %d] bloqué par le corps %d en %s (dessus y=%d)" % [top[0].x, top[top.size() - 1].x, j, str(r.round()), y])
					return true
	for g in caves:
		var m = g.get("mountain")
		if m is PackedVector2Array:
			for p in m:
				var w: Vector2 = (g as Node2D).global_transform * p
				var y := _y_at(top, w.x)
				if y != INF and w.y > y + BELOW_MARGIN:
					return true
	return false


## Ramer-Douglas-Peucker sur une ligne ouverte
static func _rdp(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	if pts.size() < 3:
		return PackedVector2Array(pts)
	var keep := PackedByteArray()
	keep.resize(pts.size())
	keep.fill(0)
	keep[0] = 1
	keep[pts.size() - 1] = 1
	var stack: Array = [[0, pts.size() - 1]]
	while not stack.is_empty():
		var seg: Array = stack.pop_back()
		var a: int = seg[0]
		var b: int = seg[1]
		var best := -1.0
		var bi := -1
		for i in range(a + 1, b):
			var d := _seg_dist(pts[i], pts[a], pts[b])
			if d > best:
				best = d
				bi = i
		if bi != -1 and best > eps:
			keep[bi] = 1
			stack.append([a, bi])
			stack.append([bi, b])
	var out := PackedVector2Array()
	for i in pts.size():
		if keep[i] == 1:
			out.append(pts[i])
	return out


## Ramer-Douglas-Peucker sur un contour fermé (coupé en deux au point le plus
## éloigné du premier)
static func _rdp_closed(poly: PackedVector2Array, eps: float) -> PackedVector2Array:
	var n := poly.size()
	if n < 4:
		return PackedVector2Array(poly)
	var far := 0
	for i in n:
		if poly[i].distance_squared_to(poly[0]) > poly[far].distance_squared_to(poly[0]):
			far = i
	var a := poly.slice(0, far + 1)
	var b := poly.slice(far)
	b.append(poly[0])
	var ra := _rdp(a, eps)
	var rb := _rdp(b, eps)
	ra.remove_at(ra.size() - 1)
	rb.remove_at(rb.size() - 1)
	ra.append_array(rb)
	return ra


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## [COPIES DU JEU 1.92] Contour en segments -> polygones pleins.
## Les segments sont remis bout à bout en chaînes ; deux chaînes qui ne se
## touchent pas (les puits du bas de la caverne de L'Œuf) sont reliées PAR EN
## DESSOUS, loin sous le contour : le puits reste ouvert (on y tombe toujours).
## Si le départ est DANS la boucle, c'est une enceinte : la roche est autour
## (cadre découpé en bandes verticales, pour des morceaux sans trou) ; sinon
## c'est un bloc plein.
static func _segments_to_solids(segs: PackedVector2Array, start: Vector2) -> Array:
	var chains: Array = []
	var cur := PackedVector2Array()
	for i in range(0, segs.size() - 1, 2):
		var a: Vector2 = segs[i]
		var b: Vector2 = segs[i + 1]
		if cur.is_empty():
			cur.append(a)
		elif cur[cur.size() - 1].distance_to(a) > 1.0:
			chains.append(cur)
			cur = PackedVector2Array([a])
		cur.append(b)
	if not cur.is_empty():
		chains.append(cur)
	if chains.is_empty():
		return []
	var fr := Rect2(chains[0][0], Vector2.ZERO)
	for c in chains:
		for p in c:
			fr = fr.expand(p)
	const MARGIN := 800.0
	var deep: float = fr.end.y + MARGIN + 600.0   # sous le cadre : les puits restent ouverts
	var loop := PackedVector2Array()
	for k in chains.size():
		var c: PackedVector2Array = chains[k]
		var nxt: PackedVector2Array = chains[(k + 1) % chains.size()]
		loop.append_array(c)
		if c[c.size() - 1].distance_to(nxt[0]) > 1.0:
			loop.append(Vector2(c[c.size() - 1].x, deep))
			loop.append(Vector2(nxt[0].x, deep))
	if start == Vector2.INF or not Geometry2D.is_point_in_polygon(start, loop):
		return [loop]
	# enceinte : cadre = rectangle agrandi moins l'intérieur, par bandes
	var out: Array = []
	var box := fr.grow(MARGIN)
	const BAND := 3000.0
	var x := box.position.x
	while x < box.end.x:
		var slab := PackedVector2Array([Vector2(x, box.position.y), Vector2(minf(x + BAND, box.end.x), box.position.y),
			Vector2(minf(x + BAND, box.end.x), box.end.y), Vector2(x, box.end.y)])
		for piece in Geometry2D.clip_polygons(slab, loop):
			# (Godot rend les trous dans le sens des aiguilles d'une montre : il
			# n'y en a pas ici, l'intérieur traverse chaque bande ou en sort)
			if not Geometry2D.is_polygon_clockwise(piece) and (piece as PackedVector2Array).size() >= 3:
				out.append(piece)
		x += BAND
	return out
