extends Node
## [GLACE 1.77] Style unique « glace » pour toutes les plateformes.
##
## Demande de l'équipe (27/11) : « on a deux types de plateformes (bleu clair
## et bleu foncé), j'aimerais uniformiser la couleur et leur donner un côté
## glace, avec un motif léger parce qu'on défile vite ; et changer la ligne
## bleue pour un côté plus "dessus de la glace" ».
##
## Plutôt que de retoucher chaque générateur (sol.tscn, tremplins, half-pipes,
## Gruyère, L'Œuf, cavernes, tuto, niveaux dessinés…), ce nœud global regarde
## chaque Polygon2D / Line2D qui entre dans le jeu et, s'il reconnaît un
## morceau de terrain (à sa couleur ou à sa texture d'origine), il lui
## applique le nouveau style :
##   - corps (bleu clair ET bleu « roche ») -> ICE_BODY + shader ice_body
##     (grandes facettes très discrètes, accrochées au monde) ; l'intérieur
##     des cavernes prend une glace un peu plus profonde (ICE_DEEP) ;
##   - bordure de cristaux (tile_ice_up_long1 / tile_ice_up_1) -> nouvelle
##     image ice_surface.png : liseré blanc + couche claire qui s'efface ;
##   - contours foncés (RIM_COLOR des générateurs) -> bleu glace plus doux.
## Ce qui n'est PAS du terrain n'est pas touché : œufs à grappin (presque
## blancs, on doit les repérer), voiles et images texturées (glace des
## galeries, pixel art de L'Œuf, plafonds accrochables à stalactites),
## boosts, arrivée, fantômes…
## Rien n'est supprimé : les images d'origine restent dans le projet et
## l'option « Plateformes : D'origine » (Settings.ground_style = 0) remet
## l'ancien rendu.

## Corps de toutes les plateformes (glace bleu moyen : lisible sur le glacier
## clair du fond comme sur les montagnes sombres).
const ICE_BODY := Color(0.52, 0.73, 0.89, 1.0)
## Glace plus profonde : masse de la montagne des cavernes (on distingue
## mieux les galeries).
const ICE_DEEP := Color(0.43, 0.61, 0.77, 1.0)
## Contours (à la place des contours bleu foncé de la maquette).
const ICE_RIM := Color(0.27, 0.47, 0.70, 1.0)

## Couleurs d'origine reconnues comme « corps de plateforme ».
const BODY_COLORS := [
	Color(0.694118, 0.862745, 0.956863, 1),   # glace claire (sol.tscn, tremplins, œuf, tuto, dessinés)
	Color(0.36, 0.52, 0.70, 1),               # piliers du Gruyère, roche de L'Œuf
	Color(0.30, 0.44, 0.62, 1),               # plafonds-guides du Gruyère
]
## Couleurs d'origine des masses de caverne (-> ICE_DEEP).
const DEEP_COLORS := [
	Color(0.30, 0.42, 0.58, 1),               # roche des cavernes
]
## Couleurs d'origine des contours foncés.
const RIM_COLORS := [
	Color(0.16, 0.36, 0.60, 1),               # Gruyère, L'Œuf
	Color(0.12, 0.24, 0.42, 1),               # cavernes
	Color(0.25, 0.55, 0.85, 1),               # tuto (bord des plateformes)
]
## Bordures d'origine (cristaux bleus) remplacées par le dessus de glace.
const OLD_EDGE_TEXTURES := [
	"res://sprites/levels/tiles/tile_ice_up_long1.png",
	"res://sprites/levels/LevelTest/tile_ice_up_1.png",
]
const SURFACE_TEXTURE := preload("res://sprites/levels/tiles/ice_surface.png")
const BODY_SHADER := preload("res://src/levels/ice_body.gdshader")
## Bordure : 96 px de large, CENTRÉE sur la surface (voir tools/art/ice_style.py) :
## couche de neige de 20 à 28 px sur la glace, quelques bosses au-dessus.
const EDGE_WIDTH := 96.0
## Un morceau de contour reçoit la neige si sa face « dessus » regarde vers
## le haut (u = composante verticale de sa normale, en jeu : 1 = plat,
## 0 = mur vertical, < 0 = surplomb / plafond). [NEIGE 1.78] jusqu'à presque
## la verticale (u > EDGE_UP_MIN) : la neige continue dans les half-pipes et
## sur les pentes raides, de plus en plus fine (voir _snow_scale) ; seuls les
## murs verticaux, dessous et plafonds n'en ont pas (fin contour à la place).
const EDGE_UP_MIN := 0.02
## [NEIGE 1.78] épaisseur de la neige sur les pentes : pleine jusqu'à ~53°
## (u >= SNOW_FULL_U), puis de plus en plus fine jusqu'à SNOW_MIN_SCALE
## au bord du mur vertical. Continu à l'œil, pas de coupure.
const SNOW_FULL_U := 0.6
const SNOW_MIN_SCALE := 0.2
## [NEIGE 1.78] passage vertical court (lèvre de half-pipe) recouvert de
## neige fine s'il relie deux morceaux enneigés : longueur max (px) et
## tolérance de surplomb (u > -SNOW_BRIDGE_U).
const SNOW_BRIDGE_MAX := 260.0
## [NEIGE 1.78] au-delà de cet angle entre deux segments, la neige est
## coupée (angle vif : rebord carré, comme la « coping » d'un skatepark).
const SNOW_SPLIT_DEG := 40.0
const SNOW_BRIDGE_U := 0.15
## Largeur du fin contour des flancs, dessous et plafonds.
const SIDE_WIDTH := 4.0

var _body_mat: ShaderMaterial


func _ready() -> void:
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = BODY_SHADER
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	# [PRISES 1.78] blocs-prises du grappin : forme de bloc de glace tirée au
	# hasard (graine fixe par niveau et par emplacement), quel que soit le
	# style choisi (la forme compte pour le jeu : même collision pour tous)
	if n is StaticBody2D and str(n.scene_file_path).contains("StaticBody2DFish") and not n.has_meta("ice_fish"):
		_reshape_fish.call_deferred(n)
		return
	# [DÉCOR 1.78] décorations posées sur le sol : recalées sur la neige
	if n is Node2D and _is_decoration(n) and not n.has_meta("ice_deco"):
		_snap_decoration(n)
		return
	if not (n is Polygon2D or n is Line2D) or n.has_meta("ice_style"):
		return
	# différé : certains générateurs règlent la couleur ou la texture juste
	# APRÈS add_child ; on regarde le nœud une fois qu'il est complet
	_restyle.call_deferred(n)


func _restyle(n: Node) -> void:
	if not is_instance_valid(n) or not n.is_inside_tree():
		return
	if Settings.ground_style == 0:
		return   # « D'origine » : on ne touche à rien
	if n is Polygon2D:
		_restyle_body(n)
	elif n is Line2D:
		_restyle_line(n)


func _restyle_body(p: Polygon2D) -> void:
	if p.texture != null or p.material != null:
		return   # images (pixel art, voiles) : pas du corps uni
	if _matches(p.color, BODY_COLORS):
		p.color = ICE_BODY
	elif _matches(p.color, DEEP_COLORS):
		p.color = ICE_DEEP
	else:
		return
	p.material = _body_mat
	# [CONTINUITÉ 1.78] la glace « normale » participe à la fusion du dessin
	# des plateformes collées (la glace profonde des cavernes reste à part)
	if p.color == ICE_BODY:
		_queue_fusion(p)


func _restyle_line(l: Line2D) -> void:
	if l.texture != null:
		if l.texture.resource_path in OLD_EDGE_TEXTURES:
			_replace_edge(l)
		return
	if _matches(l.default_color, RIM_COLORS):
		l.default_color = ICE_RIM


## Remplace une bordure de cristaux par le dessus de glace : on garde le
## Line2D d'origine (caché, rien n'est supprimé) et on pose, à côté, un
## Line2D de neige par morceau de contour tourné vers le haut, et un fin
## contour sur le reste (murs, dessous, plafonds).
func _replace_edge(l: Line2D) -> void:
	var pts: PackedVector2Array = l.points
	if pts.size() < 2 or not (l.get_parent() is CanvasItem):
		return
	var parent := l.get_parent() as CanvasItem
	# l'ancienne bordure était décalée (+28 px) vers l'intérieur du sol ; ses
	# points sont ceux de la surface, exprimés dans le repère du parent
	var basis: Transform2D = parent.get_global_transform()
	var n := pts.size()
	var seg_count := n if l.closed else n - 1
	# 1) chaque segment : ses deux bouts et son « u » (vers le haut = 1)
	var segs: Array = []
	for i in seg_count:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var d := b - a
		if d.length_squared() < 0.01:
			continue
		# face « dessus » du Line2D = à gauche du sens de tracé : (d.y, -d.x)
		var up_world := basis.basis_xform(Vector2(d.y, -d.x)).normalized()
		segs.append([a, b, -up_world.y])
	# 2) on regroupe les segments qui se suivent : neige (u > EDGE_UP_MIN)
	#    ou contour (le reste)
	var groups: Array = []   # [neige ?, [segments]]
	for sg in segs:
		var snowy: bool = sg[2] > EDGE_UP_MIN
		if groups.is_empty() or groups[-1][0] != snowy or groups[-1][1][-1][1] != sg[0]:
			groups.append([snowy, [sg]])
		else:
			groups[-1][1].append(sg)
	# contour fermé : le dernier groupe rejoint peut-être le premier
	if l.closed and groups.size() >= 2 and groups[0][0] == groups[-1][0] \
			and groups[-1][1][-1][1] == groups[0][1][0][0]:
		var last: Array = groups.pop_back()
		last[1].append_array(groups[0][1])
		groups[0] = last
	# [NEIGE 1.78] petit passage vertical (lèvre d'un half-pipe, bout de
	# tremplin) entre deux morceaux enneigés : la neige fine continue dessus,
	# pour que la couche paraisse continue à l'œil. Les grands murs, les
	# dessous et les surplombs gardent le fin contour.
	for gi in groups.size():
		var g: Array = groups[gi]
		if g[0] or groups.size() < 3 and not l.closed:
			continue
		var prev_snow: bool = groups[(gi - 1 + groups.size()) % groups.size()][0] if (gi > 0 or l.closed) else false
		var next_snow: bool = groups[(gi + 1) % groups.size()][0] if (gi < groups.size() - 1 or l.closed) else false
		if not (prev_snow and next_snow):
			continue
		var length := 0.0
		var vertical := true
		for sg in g[1]:
			length += (sg[1] - sg[0]).length()
			vertical = vertical and sg[2] > -SNOW_BRIDGE_U
		if vertical and length < SNOW_BRIDGE_MAX:
			g[0] = true
	# on recolle les groupes enneigés devenus voisins
	var merged: Array = []
	for g in groups:
		if not merged.is_empty() and merged[-1][0] == g[0] and merged[-1][1][-1][1] == g[1][0][0]:
			merged[-1][1].append_array(g[1])
		else:
			merged.append(g)
	groups = merged
	# [NEIGE 1.78] coupe aux angles vifs (rebord d'un half-pipe, bord d'un
	# deck, bout de tremplin) : chaque morceau s'arrête net sur l'angle avec
	# sa propre épaisseur. Sans ça, la bande de neige s'enroulait autour du
	# rebord (bosse arrondie) et passait en biseau d'une épaisseur à l'autre :
	# le haut du half-pipe avait l'air arrondi ou coupé en biais.
	var split_groups: Array = []
	for g in groups:
		var piece: Array = []
		for sg in g[1]:
			if not piece.is_empty():
				var d0: Vector2 = piece[-1][1] - piece[-1][0]
				var d1: Vector2 = sg[1] - sg[0]
				if absf(rad_to_deg(d0.angle_to(d1))) > SNOW_SPLIT_DEG:
					split_groups.append([g[0], piece])
					piece = []
			piece.append(sg)
		if not piece.is_empty():
			split_groups.append([g[0], piece])
	groups = split_groups
	for g in groups:
		var run: Array = g[1]
		var line_pts := PackedVector2Array([run[0][0]])
		for sg in run:
			line_pts.append(sg[1])
		if g[0]:
			_add_snow_line(parent, l, line_pts, run)
		else:
			var c := Line2D.new()
			c.name = "ContourGlace"
			c.points = line_pts
			c.width = SIDE_WIDTH
			c.default_color = ICE_RIM
			c.joint_mode = Line2D.LINE_JOINT_ROUND
			c.z_index = l.z_index
			c.z_as_relative = l.z_as_relative
			c.set_meta("ice_style", true)
			parent.add_child(c)
	l.visible = false


## [NEIGE 1.78] Épaisseur relative de la neige selon u (1 = plat, 0 = mur).
static func _snow_scale(u: float) -> float:
	return lerpf(SNOW_MIN_SCALE, 1.0, smoothstep(EDGE_UP_MIN, SNOW_FULL_U, maxf(u, 0.0)))


## Pose la neige sur un morceau de contour. [NEIGE 1.78] Sur les pentes
## raides (half-pipes, tremplins, bosses fortes), la couche s'amincit en
## douceur grâce à une courbe de largeur (Line2D.width_curve) : la neige est
## centrée sur la surface, donc la rétrécir garde la surface au même endroit
## et rend la couche (et les bosses) plus fines.
func _add_snow_line(parent: CanvasItem, l: Line2D, line_pts: PackedVector2Array, run: Array) -> void:
	var e := Line2D.new()
	e.name = "DessusGlace"
	e.points = line_pts
	e.width = EDGE_WIDTH
	e.texture = SURFACE_TEXTURE
	e.texture_mode = Line2D.LINE_TEXTURE_TILE
	e.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	e.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	e.default_color = Color.WHITE
	e.joint_mode = Line2D.LINE_JOINT_ROUND
	e.z_index = l.z_index
	e.z_as_relative = l.z_as_relative
	e.set_meta("ice_style", true)   # pour ne pas le retraiter
	# épaisseur à chaque point = moyenne des deux segments voisins
	var total := 0.0
	for sg in run:
		total += (sg[1] - sg[0]).length()
	var scales: Array = []
	var any_thin := false
	for i in run.size() + 1:
		var u: float
		if i == 0:
			u = run[0][2]
		elif i == run.size():
			u = run[-1][2]
		else:
			u = (run[i - 1][2] + run[i][2]) * 0.5
		var m := _snow_scale(u)
		any_thin = any_thin or m < 0.98
		scales.append(m)
	if any_thin and total > 0.0:
		var curve := Curve.new()
		curve.bake_resolution = clampi(int(total / 12.0), 100, 4096)
		var dist := 0.0
		var last_m := -1.0
		for i in scales.size():
			if i > 0:
				dist += (run[i - 1][1] - run[i - 1][0]).length()
			var m: float = scales[i]
			# on ne garde que les points où l'épaisseur change (courbe légère)
			if absf(m - last_m) > 0.01 or i == scales.size() - 1:
				curve.add_point(Vector2(clampf(dist / total, 0.0, 1.0), m), 0.0, 0.0,
					Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
				last_m = m
		e.width_curve = curve
	parent.add_child(e)


# --- [CONTINUITÉ 1.78] Fusion du dessin des plateformes collées -------------
# Demande de l'équipe (27/11) : « entre deux plateformes côte à côte, les
# lignes bleues de contour se chevauchent, dans plusieurs niveaux ; peut-on
# rendre le design plus continu ? ». Choix de l'équipe : FUSIONNER LE DESSIN,
# dans TOUS les niveaux ; un trou entre deux morceaux n'est rebouché (au
# dessin) que s'il est plus petit que Pinpouin et qu'il ne pourrait de toute
# façon pas tomber dedans.
#
# Pourquoi il y avait des doubles lignes : chaque morceau de terrain (sol,
# tremplin, half-pipe, pilier du Gruyère, morceau de L'Œuf…) est un corps à
# part, avec SON contour sur tout son tour. Deux morceaux collés = deux
# contours l'un sur l'autre au milieu de ce qui devrait être un seul bloc.
#
# Ce que fait cette partie (dessin seulement : les COLLISIONS NE CHANGENT PAS,
# la glisse est exactement la même) :
#   1) chaque corps de glace (Polygon2D restylé ICE_BODY) est noté ; une fois
#      le niveau construit (2 images), on cherche les groupes de corps qui se
#      touchent ou qui sont séparés de moins de FUSION_GAP ;
#   2) pour chaque groupe d'au moins 2 corps, on calcule UNE forme (union des
#      corps + « ponts » qui rebouchent les fentes trop étroites pour
#      Pinpouin) ;
#   3) on cache (sans les supprimer) les contours et la neige propres à
#      chaque morceau, et on redessine un seul contour + une seule couche de
#      neige sur le tour de la forme fusionnée (même code que _replace_edge :
#      même neige, mêmes pentes, mêmes rebords nets) ;
#   4) les remplissages d'origine restent affichés : ils ont la même couleur
#      et le même motif accroché au monde (ice_body.gdshader), donc ils se
#      raccordent sans couture ; les ponts reçoivent le même remplissage.
# Niveaux qui se construisent en jouant (Sans fin, morceaux aléatoires) : un
# nouveau morceau qui touche un groupe le fait recalculer ; un morceau qui
# disparaît (libéré derrière Pinpouin) aussi.

## Écart (px) en dessous duquel deux morceaux sont « collés » et la fente est
## rebouchée au dessin. Pinpouin = capsule de 40 x 20 px (Player.tscn) : par
## une fente de moins de 20 px il ne passe dans AUCUN sens (ni à plat, ni
## debout, ni en vrille) ; au-delà, il pourrait y tomber -> on laisse le trou.
const FUSION_GAP := 20.0
## Petite marge (px) pour que deux bords posés exactement l'un contre l'autre
## (même ligne de points) soient bien vus comme « collés » par le calcul.
const FUSION_EPS := 1.5
## Marge (px) pour reconnaître les lignes d'un morceau (elles sont SUR son bord).
const FUSION_LINE_MARGIN := 8.0
## Interrupteur (debug / comparaison avant-après).
var fusion_enabled := true
## Affiche dans la console le nombre de groupes et le temps de calcul.
var fusion_debug := false
## (debug) false = fusionne aussi les corps qui se croisent.
var fusion_cross_check := true

var _fusion_known := {}     # Polygon2D -> true : corps de glace connus
var _fusion_pending := {}   # Polygon2D -> true : arrivés depuis le dernier calcul
var _fusion_dirty := {}     # id de groupe -> true : un membre est parti
var _fusion_groups := {}    # id -> {"fills": Array, "nodes": Array, "hidden": Array}
var _fusion_next_id := 0
var _fusion_scheduled := false
## Un calcul tourne en arrière-plan (on n'en lance pas deux à la fois).
var _fusion_busy := false


## Note un corps de glace pour la fusion (appelé par _restyle_body).
func _queue_fusion(p: Polygon2D) -> void:
	if not fusion_enabled or p.name == "BlocGlace":
		return   # prises du grappin : blocs isolés, jamais fusionnés
	if p.polygons.size() > 0 or p.invert_enabled or p.polygon.size() < 3:
		return   # formes spéciales (multi-polygones, inversées) : on n'y touche pas
	_fusion_known[p] = true
	_fusion_pending[p] = true
	if not p.has_meta("ice_fusion_watch"):
		p.set_meta("ice_fusion_watch", true)
		p.tree_exiting.connect(_on_fusion_fill_exiting.bind(p))
	_schedule_fusion()


## Un corps quitte le jeu (morceau libéré, niveau fermé) : son groupe sera
## recalculé avec les membres restants.
func _on_fusion_fill_exiting(p: Polygon2D) -> void:
	_fusion_known.erase(p)
	_fusion_pending.erase(p)
	if p.has_meta("ice_group"):
		_fusion_dirty[p.get_meta("ice_group")] = true
		_schedule_fusion()


func _schedule_fusion() -> void:
	if _fusion_scheduled:
		return
	_fusion_scheduled = true
	_run_fusion.call_deferred()


func _run_fusion() -> void:
	# 2 images : les générateurs ont fini (formes, bordures, neige posée par
	# _replace_edge en différé) avant qu'on regarde les contours
	await get_tree().process_frame
	await get_tree().process_frame
	while _fusion_busy:
		await get_tree().process_frame
	_fusion_scheduled = false
	await _fusion_pass()


static func _fusion_valid(n) -> bool:
	return is_instance_valid(n) and n.is_inside_tree() and not n.is_queued_for_deletion()


## Un passage de fusion. Trois temps :
##   1) ici (jeu) : on relève les formes des corps et des lignes, en
##      coordonnées du monde ;
##   2) en ARRIÈRE-PLAN (WorkerThreadPool) : tout le calcul géométrique
##      (voisins, ponts, union, sens des tours, lignes à cacher). Les grands
##      sols font des milliers de points : sur le fil du jeu, Chill 704
##      faisait une saccade de 0,7 s au départ ; en arrière-plan, le jeu
##      continue de tourner pendant ce temps ;
##   3) de retour ici : on crée les nœuds (ponts, contour, neige) et on cache
##      les anciennes lignes. Pendant le calcul, le niveau est affiché comme
##      avant (avec ses doubles lignes) : ça ne dure que quelques images.
func _fusion_pass() -> void:
	# groupes dont un membre est parti : on défait leur dessin, les membres
	# restants seront regroupés
	for gid in _fusion_dirty.keys():
		if _fusion_groups.has(gid):
			_fusion_teardown(gid)
	var had_dirty := not _fusion_dirty.is_empty()
	_fusion_dirty.clear()
	if _fusion_pending.is_empty() and not had_dirty:
		return
	_fusion_pending.clear()
	if Settings.ground_style == 0 or not fusion_enabled:
		return
	var t0 := Time.get_ticks_usec()
	# --- 1) relevé des formes -------------------------------------------
	# lignes déjà cachées par un groupe existant : relevées aussi (le groupe
	# peut être refait et devra les cacher à nouveau)
	var hidden_now := {}
	for g in _fusion_groups.values():
		for l in g["hidden"]:
			hidden_now[l] = true
	var fills: Array = []    # nœuds Polygon2D (même ordre que bodies)
	var bodies: Array = []   # [forme, cadre, calque, groupe, parent, gonflée GAP, gonflée EPS]
	var parents := {}        # nœud parent -> numéro
	var lines: Array = []    # nœuds Line2D (même ordre que line_data)
	var line_data: Array = []   # [points du monde échantillonnés, numéro du parent]
	for f in _fusion_known.keys():
		if not _fusion_valid(f):
			_fusion_known.erase(f)
			continue
		if not f.is_visible_in_tree():
			continue
		var xf: Transform2D = f.get_global_transform()
		var poly := PackedVector2Array()
		for v in f.polygon:
			poly.append(xf * (v + f.offset))
		if Geometry2D.is_polygon_clockwise(poly):
			poly.reverse()   # même sens pour tous (les sols retournés scale.y < 0)
		var rect := Rect2(poly[0], Vector2.ZERO)
		for v in poly:
			rect = rect.expand(v)
		var par: Node = f.get_parent()
		if not parents.has(par):
			parents[par] = parents.size()
			var pxf: Transform2D = par.get_global_transform() if par is CanvasItem else Transform2D.IDENTITY
			for c in par.get_children():
				if not (c is Line2D) or not _is_ice_line(c):
					continue
				if not c.visible and not hidden_now.has(c):
					continue   # bordure d'origine déjà cachée par _replace_edge
				# les points des lignes sont ceux de la surface dans le repère
				# du parent (voir _replace_edge) ; 40 points au plus suffisent
				var pts: PackedVector2Array = c.points
				var sample := PackedVector2Array()
				if pts.size() > 0:
					var step := maxi(1, pts.size() / 40)
					for k in range(0, pts.size(), step):
						sample.append(pxf * pts[k])
					sample.append(pxf * pts[-1])
				lines.append(c)
				line_data.append([sample, parents[par]])
		fills.append(f)
		bodies.append([poly, rect, f.get_canvas().get_id(), f.get_meta("ice_group", -1),
			parents[par], null, null])
	var group_sizes := {}
	for gid in _fusion_groups:
		group_sizes[gid] = _fusion_groups[gid]["fills"].size()
	var job := {"bodies": bodies, "lines": line_data, "group_sizes": group_sizes}
	if fusion_debug:
		job["debug_cross"] = []
		job["cross_check"] = fusion_cross_check
	# --- 2) calcul en arrière-plan ---------------------------------------
	_fusion_busy = true
	var task := WorkerThreadPool.add_task(_fusion_compute.bind(job), false, "Fusion glace")
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	_fusion_busy = false
	# --- 3) dessin ------------------------------------------------------
	_fusion_apply(job.get("result", []), fills, lines)
	if fusion_debug:
		var hidden := 0
		for g in _fusion_groups.values():
			hidden += g["hidden"].size()
		print("[fusion] corps=%d groupes=%d lignes cachées=%d  %.1f ms (calcul %.1f ms en arrière-plan)" % [
			_fusion_known.size(), _fusion_groups.size(), hidden,
			(Time.get_ticks_usec() - t0) / 1000.0, job.get("compute_ms", 0.0)])
		if not job["debug_cross"].is_empty():
			print("[fusion] croisements écartés : ", job["debug_cross"])


## [Arrière-plan] Tout le calcul géométrique d'un passage (aucun nœud ici :
## uniquement Geometry2D et des tableaux). Résultat dans job["result"] : une
## entrée par groupe à (re)dessiner.
static func _fusion_compute(job: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var bodies: Array = job["bodies"]
	var line_data: Array = job["lines"]
	var group_sizes: Dictionary = job["group_sizes"]
	# qui touche qui (à moins de FUSION_GAP) : union-find
	var parent_of: Array = range(bodies.size())
	var pairs: Array = []   # [i, j, collés (EPS) ?]
	for key in _candidate_pairs(bodies):
		var i: int = key.x
		var j: int = key.y
		if bodies[i][2] != bodies[j][2]:
			continue   # pas sur le même calque d'affichage
		if bodies[i][3] >= 0 and bodies[i][3] == bodies[j][3]:
			# déjà dans le même groupe dessiné : on sait qu'ils se touchent
			# (pas de calcul) ; le groupe ne sera de toute façon pas refait
			# s'il n'a pas changé
			pairs.append([i, j, true])
		elif _pieces_overlap(_dil(bodies, i, 5), _dil(bodies, j, 5)):
			var touching := _pieces_overlap(_dil(bodies, i, 6), _dil(bodies, j, 6))
			# deux rubans qui se CROISENT (en X, comme les pistes de Chill 704)
			# ne sont pas des plateformes côte à côte : chacun garde son dessin
			if touching and job.get("cross_check", true) and _crosses(bodies[i][0], bodies[j][0]):
				if job.has("debug_cross"):
					job["debug_cross"].append(bodies[i][1].intersection(bodies[j][1]).get_center())
				continue
			pairs.append([i, j, touching])
		else:
			continue
		var ri := _uf_find(parent_of, i)
		var rj := _uf_find(parent_of, j)
		if ri != rj:
			parent_of[ri] = rj
	var comps := {}
	for i in bodies.size():
		var r := _uf_find(parent_of, i)
		if not comps.has(r):
			comps[r] = []
		comps[r].append(i)
	var results: Array = []
	for r in comps:
		var comp: Array = comps[r]
		if comp.size() < 2:
			continue
		# groupe déjà dessiné et inchangé (mêmes membres) : rien à refaire
		var old := {}
		var all_grouped := true
		for i in comp:
			if bodies[i][3] >= 0:
				old[bodies[i][3]] = true
			else:
				all_grouped = false
		if all_grouped and old.size() == 1 and group_sizes.get(old.keys()[0], -1) == comp.size():
			continue
		var in_comp := {}
		var comp_parents := {}
		for i in comp:
			in_comp[i] = true
			comp_parents[bodies[i][4]] = true
		# morceaux à unir : les corps (gonflés de EPS) + les ponts
		var shapes: Array = []
		var bridges: Array = []
		for i in comp:
			for pc in _dil(bodies, i, 6):
				if not Geometry2D.is_polygon_clockwise(pc):
					shapes.append(pc)
		# ponts : pour deux corps séparés par une fente < FUSION_GAP, on
		# « ferme » la paire (gonflée de FUSION_GAP/2, fusionnée, dégonflée
		# d'autant) : la fente se remplit, le reste de la forme ne bouge pas
		for pr in pairs:
			if not in_comp.has(pr[0]) or pr[2]:
				continue   # autre groupe, ou déjà collés : pas besoin de pont
			var a: Array = _dil(bodies, pr[0], 5)
			var b: Array = _dil(bodies, pr[1], 5)
			if a.size() != 1 or b.size() != 1:
				continue
			var m := Geometry2D.merge_polygons(a[0], b[0])
			if m.size() != 1:
				continue   # la paire entoure un trou (ou ne se touche pas) : pas de pont
			for e in Geometry2D.offset_polygon(m[0], -FUSION_GAP * 0.5, Geometry2D.JOIN_MITER):
				if Geometry2D.is_polygon_clockwise(e):
					continue
				bridges.append(e)
				for pe in Geometry2D.offset_polygon(e, FUSION_EPS, Geometry2D.JOIN_MITER):
					if not Geometry2D.is_polygon_clockwise(pe):
						shapes.append(pe)
		var u := _union_all(shapes)
		var outers: Array = u[0]
		var holes: Array = u[1]
		if outers.is_empty():
			continue
		# tours orientés « air à gauche » (attendu par _replace_edge)
		var loops: Array = []
		for loop in outers + holes:
			loops.append(_air_on_left(loop, outers, holes))
		# lignes des morceaux posées sur le bord de la forme -> à cacher
		var grown: Array = []
		for o in outers:
			for g in Geometry2D.offset_polygon(o, FUSION_LINE_MARGIN, Geometry2D.JOIN_MITER):
				if not Geometry2D.is_polygon_clockwise(g):
					grown.append(g)
		var shrunk_holes: Array = []
		for h in holes:
			var hc: PackedVector2Array = h.duplicate()
			if Geometry2D.is_polygon_clockwise(hc):
				hc.reverse()   # offset_polygon attend une forme « pleine »
			shrunk_holes.append_array(Geometry2D.offset_polygon(hc, -FUSION_LINE_MARGIN, Geometry2D.JOIN_MITER))
		var hide: Array = []
		for li in line_data.size():
			if comp_parents.has(line_data[li][1]) and _points_on_region(line_data[li][0], grown, shrunk_holes):
				hide.append(li)
		results.append({"members": comp, "old": old.keys(), "bridges": bridges,
			"loops": loops, "hide": hide})
	job["result"] = results
	job["compute_ms"] = (Time.get_ticks_usec() - t0) / 1000.0


## [Jeu] Crée le dessin des groupes calculés en arrière-plan.
func _fusion_apply(results: Array, fills: Array, lines: Array) -> void:
	for r in results:
		var members: Array = []
		var ok := true
		for i in r["members"]:
			members.append(fills[i])
			ok = ok and _fusion_valid(fills[i])
		if not ok:
			# un morceau est parti pendant le calcul : on recommencera
			for f in members:
				if _fusion_valid(f):
					_fusion_pending[f] = true
			_schedule_fusion()
			continue
		for gid in r["old"]:
			if _fusion_groups.has(gid):
				_fusion_teardown(gid)
		var gid := _fusion_next_id
		_fusion_next_id += 1
		var min_z := 1 << 20
		for f in members:
			min_z = mini(min_z, _abs_z(f))
		# conteneur : sous l'ancêtre commun des corps (il disparaît avec le
		# niveau), en « top_level » pour dessiner en coordonnées du monde
		var holder := Node2D.new()
		holder.name = "GlaceFusion"
		holder.top_level = true
		holder.set_meta("ice_style", true)
		_common_ancestor(members).add_child(holder)
		holder.global_transform = Transform2D.IDENTITY
		# remplissage des ponts (même glace, même motif accroché au monde)
		for e in r["bridges"]:
			var bp := Polygon2D.new()
			bp.name = "PontGlace"
			bp.polygon = e
			bp.color = ICE_BODY
			bp.material = _body_mat
			bp.z_as_relative = false
			bp.z_index = min_z
			bp.set_meta("ice_style", true)
			holder.add_child(bp)
		# lignes propres à chaque morceau : cachées (pas supprimées)
		var hidden: Array = []
		var max_z := min_z
		for li in r["hide"]:
			var l: Line2D = lines[li]
			if not is_instance_valid(l):
				continue
			# déjà cachée par un groupe encore en place : on la laisse à lui
			var taken := false
			for g in _fusion_groups.values():
				if g["hidden"].has(l):
					taken = true
					break
			if taken:
				continue
			max_z = maxi(max_z, _abs_z(l))
			l.visible = false
			hidden.append(l)
		# un seul contour + une seule neige sur chaque tour de la forme
		for loop in r["loops"]:
			var bord := Line2D.new()
			bord.name = "BordFusion"
			bord.points = loop
			bord.closed = true
			bord.z_as_relative = false
			bord.z_index = max_z
			bord.set_meta("ice_style", true)
			holder.add_child(bord)
			_replace_edge(bord)   # neige / fin contour, exactement comme ailleurs
		for f in members:
			f.set_meta("ice_group", gid)
			_fusion_pending.erase(f)
		_fusion_groups[gid] = {"fills": members, "nodes": [holder], "hidden": hidden}


## Défait le dessin d'un groupe : remet les lignes d'origine, enlève le dessin.
func _fusion_teardown(gid) -> void:
	var g: Dictionary = _fusion_groups[gid]
	for l in g["hidden"]:
		if is_instance_valid(l):
			l.visible = true
	for n in g["nodes"]:
		if is_instance_valid(n):
			n.queue_free()
	for f in g["fills"]:
		if is_instance_valid(f) and f.get_meta("ice_group", -1) == gid:
			f.remove_meta("ice_group")
			_fusion_pending[f] = true
	_fusion_groups.erase(gid)


## Paires de corps « peut-être voisins » (test rapide avant le vrai calcul,
## coûteux sur les grands sols de milliers de points) : on pose des points
## tous les FUSION_CELL px le long du bord de chaque corps dans une grille ;
## deux corps dont des points tombent dans la même case ou dans des cases
## voisines sont candidats. Plus : un corps entièrement dans le cadre d'un
## autre et dont un point est dedans (morceau posé dans un autre).
const FUSION_CELL := 64.0
static func _candidate_pairs(bodies: Array) -> Dictionary:
	var grid := {}   # Vector2i -> {numéro: true}
	for i in bodies.size():
		var poly: PackedVector2Array = bodies[i][0]
		var n := poly.size()
		for k in n:
			var a := poly[k]
			var b := poly[(k + 1) % n]
			var steps := maxi(1, ceili(a.distance_to(b) / FUSION_CELL))
			for s in steps:
				var c := Vector2i((a.lerp(b, float(s) / steps) / FUSION_CELL).floor())
				if not grid.has(c):
					grid[c] = {}
				grid[c][i] = true
	var out := {}
	for c in grid:
		var here: Array = grid[c].keys()
		# même case + 4 cases voisines (les 4 autres sont vues depuis l'autre côté)
		for off in [Vector2i(0, 0), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
			if not grid.has(c + off):
				continue
			var other: Array = grid[c + off].keys()
			for i in here:
				for j in other:
					if i != j:
						out[Vector2i(mini(i, j), maxi(i, j))] = true
	for i in bodies.size():
		for j in bodies.size():
			if i != j and bodies[i][1].encloses(bodies[j][1]) \
					and Geometry2D.is_point_in_polygon(bodies[j][0][0], bodies[i][0]):
				out[Vector2i(mini(i, j), maxi(i, j))] = true
	return out


## Forme gonflée d'un corps, calculée une seule fois : index 5 = de
## FUSION_GAP/2 (recherche des voisins, ponts), index 6 = de FUSION_EPS (union).
static func _dil(bodies: Array, i: int, which: int) -> Array:
	if bodies[i][which] == null:
		var delta := FUSION_GAP * 0.5 if which == 5 else FUSION_EPS
		bodies[i][which] = Geometry2D.offset_polygon(bodies[i][0], delta, Geometry2D.JOIN_MITER)
	return bodies[i][which]


static func _uf_find(parent_of: Array, i: int) -> int:
	while parent_of[i] != i:
		parent_of[i] = parent_of[parent_of[i]]
		i = parent_of[i]
	return i


## Deux listes de morceaux (résultats d'offset_polygon) se recouvrent-elles ?
static func _pieces_overlap(a: Array, b: Array) -> bool:
	for pa in a:
		if Geometry2D.is_polygon_clockwise(pa):
			continue
		for pb in b:
			if Geometry2D.is_polygon_clockwise(pb):
				continue
			if not Geometry2D.intersect_polygons(pa, pb).is_empty():
				return true
	return false


## Deux corps se croisent-ils (l'un coupe l'autre en deux morceaux) ? Deux
## morceaux posés bout à bout, ou l'un un peu enfoncé dans l'autre, ne se
## coupent pas : il reste un seul morceau de chacun hors de l'autre.
static func _crosses(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for pair in [[a, b], [b, a]]:
		var pieces := 0
		for piece in Geometry2D.clip_polygons(pair[0], pair[1]):
			if not Geometry2D.is_polygon_clockwise(piece) and absf(_area(piece)) > 64.0:
				pieces += 1
		if pieces >= 2:
			return true
	return false


## Union de plusieurs polygones (sens identique) -> [contours extérieurs, trous].
## Geometry2D ne sait unir que deux formes à la fois : on ajoute les morceaux
## un par un ; les trous déjà trouvés sont rognés par chaque nouveau morceau.
static func _union_all(polys: Array) -> Array:
	var outers: Array = []
	var holes: Array = []
	for p in polys:
		var cur: PackedVector2Array = p
		var i := 0
		while i < outers.size():
			if Geometry2D.intersect_polygons(outers[i], cur).is_empty():
				i += 1
				continue
			var res := Geometry2D.merge_polygons(outers[i], cur)
			var outs: Array = []
			for r in res:
				if Geometry2D.is_polygon_clockwise(r):
					holes.append(r)
				else:
					outs.append(r)
			if outs.is_empty():
				i += 1
				continue
			# le plus grand contour devient la forme courante
			outs.sort_custom(func(x, y): return absf(_area(x)) > absf(_area(y)))
			cur = outs[0]
			outers.remove_at(i)
			i = 0
		outers.append(cur)
		# un trou recouvert (même en partie) par le nouveau morceau rétrécit
		var kept: Array = []
		for h in holes:
			var hh: PackedVector2Array = h.duplicate()
			if Geometry2D.is_polygon_clockwise(hh):
				hh.reverse()
			for piece in Geometry2D.clip_polygons(hh, p):
				if not Geometry2D.is_polygon_clockwise(piece) and absf(_area(piece)) > 4.0:
					var pc: PackedVector2Array = piece.duplicate()
					pc.reverse()   # on garde les trous dans le sens « trou »
					kept.append(pc)
		holes = kept
	return [outers, holes]


static func _area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		s += p[i].cross(p[(i + 1) % p.size()])
	return s * 0.5


## Remet un tour dans le sens attendu par _replace_edge : l'air (le dessus)
## à gauche du sens de tracé, la glace à droite.
static func _air_on_left(loop: PackedVector2Array, outers: Array, holes: Array) -> PackedVector2Array:
	var best := 0
	var best_len := -1.0
	for i in loop.size():
		var l := loop[i].distance_squared_to(loop[(i + 1) % loop.size()])
		if l > best_len:
			best_len = l
			best = i
	var a := loop[best]
	var b := loop[(best + 1) % loop.size()]
	var d := (b - a).normalized()
	var probe := (a + b) * 0.5 + Vector2(d.y, -d.x) * 2.0
	var solid := false
	for o in outers:
		if Geometry2D.is_point_in_polygon(probe, o):
			solid = true
			break
	if solid:
		for h in holes:
			if Geometry2D.is_point_in_polygon(probe, h):
				solid = false
				break
	var out := loop.duplicate()
	if solid:
		out.reverse()
	return out


## Ligne du style glace (neige, fin contour, contour recoloré) ?
func _is_ice_line(l: Line2D) -> bool:
	if l.texture == SURFACE_TEXTURE:
		return true
	return l.texture == null and (_matches(l.default_color, [ICE_RIM]) or _matches(l.default_color, RIM_COLORS))


## Tous les points (échantillonnés) d'une ligne sont-ils sur le bord de la
## forme fusionnée (dans la forme gonflée, hors des trous rétrécis) ?
static func _points_on_region(pts: PackedVector2Array, grown: Array, shrunk_holes: Array) -> bool:
	if pts.is_empty():
		return false
	for p in pts:
		var inside := false
		for g in grown:
			if Geometry2D.is_point_in_polygon(p, g):
				inside = true
				break
		if not inside:
			return false
		for h in shrunk_holes:
			if Geometry2D.is_point_in_polygon(p, h):
				return false
	return true


## Profondeur d'affichage réelle (z_index cumulé des parents « relatifs »).
static func _abs_z(n: Node) -> int:
	var z := 0
	while n is Node2D:
		z += n.z_index
		if not n.z_as_relative:
			break
		n = n.get_parent()
	return z


static func _common_ancestor(nodes: Array) -> Node:
	var a: Node = nodes[0].get_parent()
	for n in nodes:
		while a != null and not a.is_ancestor_of(n):
			a = a.get_parent()
	return a


# --- [PRISES 1.78] Blocs-prises du grappin (StaticBody2DFish.tscn) ---------
# Demande de l'équipe (27/11) : « les blocs bleu clair en glace aussi ; garde
# à peu près le même diamètre mais rends sa forme aléatoire avec une seed ;
# dans les niveaux la seed est fixe, avec des formes différentes d'un niveau
# (et d'un bloc) à l'autre ».
# Le bloc d'origine est dessiné par l'addon SmartShape 2D (SS2D_Shape_Closed,
# toujours en forme de « poisson ») : il est caché (pas supprimé) et remplacé
# par un bloc de glace à facettes :
#   - même « diamètre » : la nouvelle forme reste DANS le contour d'origine
#     (8 à 11 sommets posés sur les rayons du contour d'origine, chacun
#     rentré de 0 à 18 %) : même allongement, même place pour la corde et le
#     balancier (un bloc rond de même aire débordait sous la prise et
#     Pinpouin le heurtait en se balançant, vu au bot de Hook you fool) ;
#   - graine = nom du niveau + emplacement du bloc : toujours la même forme
#     au même endroit d'un même niveau, une autre ailleurs ;
#   - la collision suit la nouvelle forme (le grappin s'accroche au bord du
#     bloc tel qu'on le voit) ;
#   - corps + bordure créés avec les couleurs / textures d'origine : le style
#     glace + neige (ou « D'origine ») s'applique ensuite comme au terrain.
const FISH_SIDES_MIN := 8
const FISH_SIDES_MAX := 11
## Chaque sommet est rentré de 0 à 18 % par rapport au contour d'origine.
const FISH_INSET := Vector2(0.82, 1.0)

func _reshape_fish(body: StaticBody2D) -> void:
	if not is_instance_valid(body) or not body.is_inside_tree() or body.has_meta("ice_fish"):
		return
	var col := body.get_node_or_null("CollisionPolygon2D") as CollisionPolygon2D
	if col == null or col.polygon.size() < 3:
		return
	body.set_meta("ice_fish", true)
	# forme d'origine dans le repère du bloc : aire et centre
	var orig := PackedVector2Array()
	for q in col.polygon:
		orig.append(col.transform * q)
	var area := 0.0
	var cen := Vector2.ZERO
	for i in orig.size():
		var a: Vector2 = orig[i]
		var b: Vector2 = orig[(i + 1) % orig.size()]
		var cr := a.cross(b)
		area += cr
		cen += (a + b) * cr
	if absf(area) < 1.0:
		return
	cen /= (3.0 * area)
	# graine : niveau + emplacement (arrondi à 8 px)
	var rng := RandomNumberGenerator.new()
	var gp := (body.global_position / 8.0).round()
	rng.seed = hash("%s|%d|%d" % [_level_name(body), int(gp.x), int(gp.y)])
	var sides := rng.randi_range(FISH_SIDES_MIN, FISH_SIDES_MAX)
	var start := rng.randf() * TAU
	# points du contour d'origine gardés EXACTS : le plus bas, le plus à
	# gauche, le plus à droite. C'est là que le grappin accroche (on tire
	# d'en dessous, de côté) : la corde garde la même longueur et le
	# balancier la même hauteur qu'avant (sinon, au bot de Hook you fool,
	# Pinpouin redescendait trop bas et tapait la paroi de l'île suivante).
	var keep: Array = []
	var lo: Vector2 = orig[0]
	var le: Vector2 = orig[0]
	var ri: Vector2 = orig[0]
	for q in orig:
		if q.y > lo.y: lo = q
		if q.x < le.x: le = q
		if q.x > ri.x: ri = q
	for q in [lo, le, ri]:
		keep.append([(q - cen).angle(), q])
	var pts: Array = keep.duplicate()
	for k in sides:
		var ang := start + (float(k) + rng.randf_range(-0.3, 0.3)) * TAU / float(sides)
		var dir := Vector2(cos(ang), sin(ang))
		# distance du centre au contour d'origine dans cette direction
		var reach := _ray_to_outline(cen, dir, orig)
		if reach <= 0.0:
			continue
		# trop près d'un point gardé : inutile
		var near := false
		for kp in keep:
			if absf(angle_difference(ang, kp[0])) < 0.25:
				near = true
		if near:
			continue
		# dessus (dir.y < -0.2) : forme libre, rentrée de 0 à 18 % ;
		# dessous et côtés : presque exact (0 à 4 %)
		var inset := rng.randf_range(FISH_INSET.x, FISH_INSET.y) if dir.y < -0.2 else rng.randf_range(0.96, 1.0)
		pts.append([ang, cen + dir * reach * inset])
	pts.sort_custom(func(x, y): return wrapf(x[0], 0.0, TAU) < wrapf(y[0], 0.0, TAU))
	var poly := PackedVector2Array()
	for e2 in pts:
		poly.append(e2[1])
	if poly.size() < 3:
		return
	# collision : la nouvelle forme
	col.transform = Transform2D.IDENTITY
	col.polygon = poly
	# l'ancien dessin (SmartShape) : caché, et il ne touche plus la collision
	var ss := body.get_node_or_null("SS2D_Shape_Closed")
	if ss != null:
		if "collision_polygon_node_path" in ss:
			ss.collision_polygon_node_path = NodePath()
		ss.visible = false
	# nouveau dessin, aux couleurs d'origine (le style s'applique ensuite)
	var fill := Polygon2D.new()
	fill.name = "BlocGlace"
	fill.polygon = poly
	fill.color = BODY_COLORS[0]
	body.add_child(fill)
	var edge := Line2D.new()
	edge.name = "BordBloc"
	edge.points = poly
	edge.closed = true
	edge.width = 32.0
	edge.texture = load(OLD_EDGE_TEXTURES[1])
	edge.texture_mode = Line2D.LINE_TEXTURE_TILE
	edge.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	body.add_child(edge)


## Distance du point c au contour `outline` dans la direction dir (premier
## bord rencontré ; 0 si aucun).
static func _ray_to_outline(c: Vector2, dir: Vector2, outline: PackedVector2Array) -> float:
	var best := INF
	var far := c + dir * 100000.0
	for i in outline.size():
		var hit = Geometry2D.segment_intersects_segment(c, far, outline[i], outline[(i + 1) % outline.size()])
		if hit != null:
			best = minf(best, c.distance_to(hit))
	return best if best < INF else 0.0


## Nom du niveau qui contient ce nœud (la scène posée sous la racine).
func _level_name(n: Node) -> String:
	var cur := n
	while cur.get_parent() != null and cur.get_parent() != get_tree().root:
		cur = cur.get_parent()
	return cur.scene_file_path if cur.scene_file_path != "" else str(cur.name)


# --- [DÉCOR 1.78] Décorations plantées dans la neige ------------------------
# Demande de l'équipe (27/11) : « la petite arche de glace d'arrivée : les
# pingouins sont dans la glace, j'aimerais qu'ils soient sur la neige ;
# réaligne les décorations sur la neige, un peu enfoncées dedans à chaque
# fois ». Les décorations (arche d'arrivée, podium FIN, blocs de glace,
# buissons, igloos, panneaux, Colisée, grande arche) sont posées par les
# générateurs à une hauteur fixe au-dessus du sol, sans regarder où est la
# surface ; avec la couche de neige, certaines paraissaient enfoncées dans la
# glace, d'autres flottaient. Ici, une fois le niveau en place (2 images de
# physique), on cherche la surface juste sous la décoration (rayon vers le
# bas, calque « ground ») et on pose le bas RÉEL de ses images (la dernière
# ligne de pixels non transparents) à `deco_sink` px SOUS la surface : la
# décoration a l'air plantée dans la neige (la couche fait 20 à 28 px).
# `deco_mound` ajoute en plus un petit tas de neige devant le pied.
# Seulement avec le style glace (« D'origine » : rien ne bouge).
const DECO_SCENES := [
	"res://src/levels/decoration/",
	"res://src/levels/FinishGate.tscn",
	"res://src/levels/Arche.tscn",
]
## Profondeur dans la neige (px sous la surface du sol) du bas des images.
var deco_sink: float = 10.0
## Petit tas de neige devant le pied des décorations.
## Choix D de l'équipe (27/11) : 10 px dans la neige + petit tas au pied.
var deco_mound: bool = true
var _alpha_bottom := {}   # texture -> dernière ligne non transparente


func _is_decoration(n: Node) -> bool:
	var path := str(n.scene_file_path)
	if path == "":
		return false
	for d in DECO_SCENES:
		if path.begins_with(d):
			return true
	return false


func _snap_decoration(n: Node2D) -> void:
	n.set_meta("ice_deco", true)
	# attendre que le niveau soit construit et que la physique connaisse le sol
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_instance_valid(n) or not n.is_inside_tree() or Settings.ground_style == 0:
		return
	var sprites: Array = n.find_children("*", "Sprite2D", true, false)
	if sprites.is_empty():
		return
	# bas réel des images et largeur occupée (repère du monde)
	var base := -INF
	var x_min := INF
	var x_max := -INF
	for sp in sprites:
		if not sp.visible or sp.texture == null:
			continue
		var r: Rect2 = sp.get_rect()
		var last_row := _texture_bottom_row(sp.texture, sp)
		var bottom_local := Vector2(r.position.x, r.position.y + last_row)
		var b: Vector2 = sp.global_transform * bottom_local
		var b2: Vector2 = sp.global_transform * (bottom_local + Vector2(r.size.x, 0.0))
		base = maxf(base, maxf(b.y, b2.y))
		x_min = minf(x_min, minf(b.x, b2.x))
		x_max = maxf(x_max, maxf(b.x, b2.x))
	if base == -INF:
		return
	# surface sous la décoration : on prend la plus haute de 3 mesures
	# (gauche, centre, droite du pied) pour ne jamais flotter au-dessus d'un creux
	var space := n.get_world_2d().direct_space_state
	var surface := INF
	for fx in [0.25, 0.5, 0.75]:
		var x: float = lerpf(x_min, x_max, fx)
		var q := PhysicsRayQueryParameters2D.create(Vector2(x, base - 260.0), Vector2(x, base + 260.0), 2)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			surface = minf(surface, hit.position.y)
	if surface == INF:
		return   # pas de sol tout près (décor en l'air) : on n'y touche pas
	n.global_position.y += surface + deco_sink - base
	if deco_mound:
		_add_snow_mound(n, Vector2((x_min + x_max) * 0.5, surface), x_max - x_min)


## Dernière ligne non transparente d'une image (en pixels de l'image, région
## comprise) ; la hauteur entière si on ne peut pas lire l'image.
func _texture_bottom_row(tex: Texture2D, sp: Sprite2D) -> float:
	var h: float = sp.get_rect().size.y
	if sp.region_enabled or sp.hframes > 1 or sp.vframes > 1:
		return h
	if _alpha_bottom.has(tex):
		return _alpha_bottom[tex]
	var img := tex.get_image()
	var row := h
	if img != null:
		if img.is_compressed():
			img = img.duplicate()
			img.decompress()
		row = 0.0
		for y in range(img.get_height() - 1, -1, -1):
			var opaque := false
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.5:
					opaque = true
					break
			if opaque:
				row = float(y + 1)
				break
	_alpha_bottom[tex] = row
	return row


## Petit tas de neige devant le pied d'une décoration (variante « tas »).
## Dessiné en marches de 4 px (comme le pixel art) : une bosse de neige
## blanche avec le même fin contour bleu que le dessus de la neige, qui
## couvre le pied de la décoration.
func _add_snow_mound(n: Node2D, foot: Vector2, width: float) -> void:
	var w := snappedf(clampf(width * 0.8, 24.0, 240.0), 8.0)
	var hgt := clampf(w * 0.1, 8.0, 16.0)
	var top := PackedVector2Array()
	var cols := int(w / 4.0)
	for i in cols:
		var t := (float(i) + 0.5) / float(cols)
		var y := -snappedf(hgt * sqrt(maxf(0.0, 1.0 - pow(2.0 * t - 1.0, 2.0))), 4.0)
		var x0 := -w * 0.5 + 4.0 * i
		top.append(Vector2(x0, y))
		top.append(Vector2(x0 + 4.0, y))
	var poly := top.duplicate()
	poly.append(Vector2(w * 0.5, 12.0))
	poly.append(Vector2(-w * 0.5, 12.0))
	var m := Polygon2D.new()
	m.name = "TasDeNeige"
	m.polygon = poly
	m.color = Color(0.97, 0.99, 1.0)
	m.set_meta("ice_style", true)
	var rim := Line2D.new()
	rim.points = top
	rim.width = 4.0
	rim.default_color = Color(0.30, 0.50, 0.73, 1.0)
	rim.joint_mode = Line2D.LINE_JOINT_SHARP
	rim.set_meta("ice_style", true)
	m.add_child(rim)
	n.get_parent().add_child(m)
	m.global_position = foot.snapped(Vector2(4.0, 4.0)) + Vector2(0.0, 4.0)
	m.z_index = (n.z_index if n.z_as_relative else 0) + 1


func _matches(c: Color, list: Array) -> bool:
	for k in list:
		if absf(c.r - k.r) + absf(c.g - k.g) + absf(c.b - k.b) < 0.03 and absf(c.a - k.a) < 0.05:
			return true
	return false
