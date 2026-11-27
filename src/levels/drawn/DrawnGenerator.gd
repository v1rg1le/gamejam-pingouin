extends Node2D
# =============================================================================
#  DrawnGenerator.gd — [CRÉATEUR 1.45] construit le niveau dessiné
# -----------------------------------------------------------------------------
#  Placé dans src/levels/LevelDrawn.tscn (copie de LevelBateau.tscn : même
#  fond en parallaxe, même interface ; seul le générateur change).
#  Il lit le dessin de DrawnLevel.gd et crée :
#   - un bloc de glace par îlot : le trait dessiné en haut, prolongé vers le
#     bas jusqu'au fond commun (comme la partie hachurée du croquis) ;
#     même rendu que les tremplins du tuto (BateauGenerator._add_ramp) :
#     remplissage bleu de sol.tscn + bordure de glace texturée ;
#     collision en SEGMENTS (contour seul) : c'est le correctif du bug
#     « vitesse -> 0 » (pas d'arêtes internes fantômes) ;
#   - les blocs accroche-grappin (le poisson de glace de l'atelier BALANCIER
#     du tuto, res://src/levels/parts/StaticBody2DFish.tscn) ;
#   - un mur invisible avant le départ, une piste de freinage + un mur après
#     l'arrivée ;
#   - l'arrivée (FinishGate, avec son grand faisceau jaune) au bout du
#     dernier trait : elle renvoie dans l'éditeur après la course ;
#   - un bouton « ✏ Éditer » pour retourner dessiner à tout moment.
#  La mort par chute est déjà gérée par Player.gd (_compute_fall_death_y :
#  sous le point le plus bas du décor = chute, puis respawn un peu avant).
# =============================================================================

const UNIT_SIZE = 64
## Le poisson de glace du tuto sert de bloc accroche-grappin (art existant)
var fish_res = preload("res://src/levels/parts/StaticBody2DFish.tscn")
var finish_gate_res = preload("res://src/levels/FinishGate.tscn")
## Bordure de glace des sols (même texture que sol.tscn)
var edge_texture = preload("res://sprites/levels/tiles/tile_ice_up_long1.png")

## Même bleu que le remplissage de sol.tscn
const ICE_COLOR = Color(0.694118, 0.862745, 0.956863, 1)
## Pente de la piste de freinage après l'arrivée (légère descente)
const RUNOUT_SLOPE = 0.03

var _islands: Array = []   # les îlots (PackedVector2Array), copiés depuis DrawnLevel


func _ready() -> void:
	DrawnLevel.load_once()
	_islands = DrawnLevel.islands()
	# Sécurité : niveau vide (ex. lancé directement depuis l'éditeur Godot) ->
	# une petite piste en pente pour ne pas tomber dans le vide.
	if _islands.is_empty():
		var demo := PackedVector2Array()
		for i in 60:
			demo.append(Vector2(i * 64.0, i * 64.0 * 0.15))
		_islands = [demo]

	# 1. Piste de freinage : le dernier îlot est prolongé après l'arrivée
	var last: PackedVector2Array = _islands[_islands.size() - 1]
	var finish_pos: Vector2 = last[last.size() - 1]
	var runout := PackedVector2Array(last)
	var steps: int = int(DrawnLevel.RUNOUT_LENGTH / DrawnLevel.RESAMPLE_STEP)
	for k in range(1, steps + 1):
		var dx: float = k * DrawnLevel.RESAMPLE_STEP
		runout.append(finish_pos + Vector2(dx, dx * RUNOUT_SLOPE))
	_islands[_islands.size() - 1] = runout

	# 2. Un bloc de glace par îlot, jusqu'au fond commun
	var bottom: float = DrawnLevel.floor_y(_islands)
	for top in _islands:
		_add_island(top, bottom)

	# 3. Blocs accroche-grappin (calculés sur le dessin d'origine, sans la piste
	#    de freinage : c'est ce que l'éditeur a montré)
	for h in DrawnLevel.hook_list(DrawnLevel.islands()):
		var fish = fish_res.instantiate()
		fish.position = h.pos
		# [CRÉATEUR v2 1.80] angle et taille réglés dans l'éditeur (la forme
		# de glace d'IceStyle et la collision suivent le nœud)
		fish.rotation = h.rot
		fish.scale = Vector2.ONE * h.scale
		add_child(fish)

	# 4. Murs : avant le départ (on ne recule pas dans le vide) et au bout de
	#    la piste de freinage
	var first: PackedVector2Array = _islands[0]
	_add_wall(Vector2(first[0].x - 80.0, first[0].y - 1500.0), Vector2(80, 3000))
	var end_p: Vector2 = runout[runout.size() - 1]
	_add_wall(Vector2(end_p.x, end_p.y - 1500.0), Vector2(80, 3000))

	# 4b. [OBJETS 1.81] objets posés dans le créateur
	_build_objects()

	# 5. Arrivée au bout du trait ; après la course, retour dans l'éditeur
	#    (après TESTER) ou dans « Mes niveaux » (après JOUER) [MES NIVEAUX 1.46]
	#    [OBJETS 1.81] ou là où l'objet « Arrivée » a été posé
	var gate = finish_gate_res.instantiate()
	gate.next_scene_path = DrawnLevel.return_scene
	var fin_obj := DrawnLevel.first_object("finish")
	gate.position = fin_obj.pos if not fin_obj.is_empty() else finish_pos
	add_child(gate)

	# 6. Départ : un peu après le début du premier trait
	var sx: float = minf(first[0].x + 150.0, first[first.size() - 1].x)
	# [CRÉATEUR v2 1.80] « Tester d'ici » : départ à l'endroit choisi dans
	# l'éditeur, lancé à la vitesse réglée (vers la droite) ; on remet
	# test_from à INF tout de suite (un « Rejouer » repart du vrai départ)
	if DrawnLevel.testing_from_here():
		var from := DrawnLevel.test_from
		DrawnLevel.test_from = Vector2.INF
		get_parent()._set_spawn_position(from)
		_launch_player.call_deferred(DrawnLevel.test_speed)
	else:
		# [OBJETS 1.81] objet « Départ » : position et élan choisis dans le créateur
		var st_obj := DrawnLevel.first_object("start")
		if not st_obj.is_empty():
			get_parent()._set_spawn_position(st_obj.pos)
			if float(st_obj.props.get("speed", 0.0)) > 0.0:
				_launch_player.call_deferred(float(st_obj.props.speed))
		else:
			get_parent()._set_spawn_position(Vector2(sx, DrawnLevel.surface_y_of(first, sx) - 80.0))

	# 7. Bouton « ✏ Éditer » (pas sur un niveau de la communauté : lecture seule)
	if not DrawnLevel.is_official:
		_add_edit_button()


# --- [OBJETS 1.81] Objets du créateur ---------------------------------------------
# Chaque objet est construit avec les MÊMES pièces que les niveaux du jeu :
# œufs du Gruyère (collision ellipse + dessins de la 1.79), boosts
# (BoostArea.tscn), panneaux de L'Œuf, décors (scènes de decoration/, plantés
# dans la neige par IceStyle). Points de passage et zones de caméra sont de
# la logique (voir _physics_process et respawn_sample).

## Œuf à l'échelle 1 (comme GruyereGenerator : EGG_RX, EGG_RY)
const EGG_RX = 130.0
const EGG_RY = 170.0
const EGG_COLOR := Color(0.86, 0.95, 1.0, 1)
var boost_res = preload("res://src/levels/boost/BoostArea.tscn")
var _checkpoints: Array = []   # positions des points de passage
var _cp := -1                  # dernier point de passage atteint (-1 = aucun)
var _cameras: Array = []       # zones de caméra : [{rect: Rect2, zoom}]
var _in_camera := false


func _build_objects() -> void:
	for o in DrawnLevel.objects:
		match str(o.type):
			"egg":
				_add_egg(o)
			"boost":
				var b = boost_res.instantiate()
				b.position = o.pos
				b.rotation = o.rot
				b.boost_strength = clampf(float(o.props.get("strength", 0.35)), 0.0, 1.0)
				b.in_air = bool(o.props.get("in_air", false))
				b.arrow_scale = 2.0 * float(o.scale)
				add_child(b)
			"checkpoint":
				_checkpoints.append(o.pos)
				_add_flag(o.pos)
			"sign":
				var spr := Sprite2D.new()
				var dir := str(o.props.get("dir", "droite"))
				spr.texture = load("res://sprites/levels/egg/panneau_%s.png" % (dir if dir in DrawnLevel.SIGN_DIRS else "droite"))
				spr.scale = Vector2.ONE * 5.0 * float(o.scale)
				spr.position = o.pos
				spr.rotation = o.rot
				spr.z_index = 1
				add_child(spr)
			"camera":
				var h := DrawnLevel.object_half(o)
				_cameras.append({"rect": Rect2(o.pos - h, h * 2.0), "zoom": clampf(float(o.props.get("zoom", 0.25)), 0.1, 1.0)})
			_:
				if DrawnLevel.DECOR_SCENES.has(o.type):
					var d = load(DrawnLevel.DECOR_SCENES[o.type]).instantiate()
					d.position = o.pos
					d.rotation = o.rot
					d.scale = Vector2.ONE * float(o.scale)
					add_child(d)
	if not _checkpoints.is_empty():
		add_to_group("course_checkpoints")   # Player._pick_respawn_sample nous demande où repartir


## Œuf à grappiner : même collision que le Gruyère (le crochet s'y plante,
## Pinpouin peut s'y poser) et l'un des 5 dessins de la 1.79
func _add_egg(o: Dictionary) -> void:
	var sc: float = float(o.scale)
	var poly := PackedVector2Array()
	for i in 32:
		var t := TAU * i / 32.0
		var sn := sin(t)
		poly.append(Vector2(EGG_RX * cos(t) * (1.0 + 0.12 * sn), EGG_RY * sn) * sc)
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.z_index = 6
	body.position = o.pos
	body.rotation = o.rot
	var col := CollisionPolygon2D.new()
	col.polygon = poly
	body.add_child(col)
	var style: int = clampi(int(o.props.get("style", 1)), 1, Settings.EGG_STYLES.size() - 1)
	var spr := Sprite2D.new()
	spr.texture = load("res://sprites/levels/gruyere/oeuf_%s.png" % Settings.EGG_STYLES[style])
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2.ONE * 4.0 * sc
	body.add_child(spr)
	add_child(body)


## Petit drapeau de point de passage (décor : poteau + fanion jaune)
func _add_flag(pos: Vector2) -> void:
	var pole := Line2D.new()
	pole.points = PackedVector2Array([pos, pos + Vector2(0, -220)])
	pole.width = 10.0
	pole.default_color = Color(0.17, 0.23, 0.35)
	pole.z_index = 1
	add_child(pole)
	var flag := Polygon2D.new()
	flag.polygon = PackedVector2Array([pos + Vector2(4, -220), pos + Vector2(110, -185), pos + Vector2(4, -150)])
	flag.color = Color(1.0, 0.82, 0.25)
	flag.z_index = 1
	add_child(flag)


func _physics_process(_delta: float) -> void:
	if _checkpoints.is_empty() and _cameras.is_empty():
		return
	var p = get_tree().get_first_node_in_group("player")
	if p == null:
		return
	# points de passage : atteint quand Pinpouin passe à moins de 350 px
	for i in _checkpoints.size():
		if i != _cp and p.global_position.distance_to(_checkpoints[i]) < 350.0:
			_cp = i
	# zones de caméra : toute la zone reste à l'écran tant qu'on est dedans
	var zone = null
	for z in _cameras:
		if z.rect.has_point(p.global_position):
			zone = z
	if zone != null:
		p.camera.focus_point = zone.rect.position
		p.camera.focus_point2 = zone.rect.end
		p.camera.focus_min_zoom = zone.zoom
		_in_camera = true
	elif _in_camera:
		p.camera.focus_point = null
		p.camera.focus_point2 = null
		p.camera.focus_min_zoom = p.camera.FOCUS_MIN_ZOOM
		_in_camera = false


## Player._pick_respawn_sample : après une chute, au dernier point de passage
## atteint (null = règle habituelle : un peu avant la chute)
func respawn_sample(_pos: Vector2):
	if _cp < 0 or RaceManager.bonus_active or RaceManager.free_ride:
		return null
	return {"pos": _checkpoints[_cp] + Vector2(0, -60), "vel": Vector2(400, 0)}


## [CRÉATEUR v2 1.80] Donne la vitesse de départ de « Tester d'ici » au
## pingouin (il est créé par LevelRandom après ce générateur : on attend
## qu'il existe).
func _launch_player(speed: float) -> void:
	for i in 10:
		var p = get_tree().get_first_node_in_group("player")
		if p != null:
			p._velocity = Vector2(speed, 0.0)
			return
		await get_tree().physics_frame


## Un îlot = le trait en haut + le fond plat en bas.
## (StaticBody2D sur le calque 2 « ground » : on y glisse ET le grappin s'y accroche)
func _add_island(top: PackedVector2Array, bottom: float) -> void:
	var poly := PackedVector2Array(top)
	poly.append(Vector2(top[top.size() - 1].x, bottom))
	poly.append(Vector2(top[0].x, bottom))
	var body := StaticBody2D.new()
	body.collision_layer = 2
	var col := CollisionPolygon2D.new()
	col.build_mode = CollisionPolygon2D.BUILD_SEGMENTS   # [FIX VITESSE -> 0] contour seul
	# [CRÉATEUR v2 1.80] collision lissée en courbe C² comme tous les autres
	# niveaux depuis la 1.71 (SmoothCurve : au plus 1° d'un segment au
	# suivant, angles vifs > 30° gardés) ; utile maintenant qu'il n'y a plus
	# de limite de pente. Le dessin garde les points du trait.
	col.polygon = SmoothCurve.smooth_closed(poly)
	body.add_child(col)
	var fill := Polygon2D.new()
	fill.color = ICE_COLOR
	fill.polygon = poly
	body.add_child(fill)
	# Bordure de glace : comme dans sol.tscn, décalée de 28 px vers l'intérieur
	var edge := Line2D.new()
	edge.texture = edge_texture
	edge.texture_mode = Line2D.LINE_TEXTURE_TILE
	edge.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	edge.width = 64.0
	edge.position = Vector2(0, 28)
	edge.points = top
	body.add_child(edge)
	add_child(body)


## Mur invisible (même principe que BateauGenerator._add_wall)
func _add_wall(pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = size * 0.5
	body.position = pos
	body.add_child(shape)
	add_child(body)


## Bouton « ✏ Éditer » en haut au centre : retour immédiat dans l'éditeur
## (le dessin est déjà sauvegardé). Calque 41 : au-dessus du HUD de course.
func _add_edit_button() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 41
	layer.process_mode = Node.PROCESS_MODE_ALWAYS   # marche aussi pendant une pause
	var btn := Button.new()
	btn.text = "  ✏  Éditer  "
	btn.theme = preload("res://src/theme_main.tres")
	btn.focus_mode = Control.FOCUS_NONE   # n'attrape pas Entrée / A de la manette
	btn.set_anchors_preset(Control.PRESET_CENTER_TOP)
	btn.offset_left = -80
	btn.offset_right = 80
	btn.offset_top = 10
	btn.offset_bottom = 54
	btn.pressed.connect(func():
		get_tree().paused = false
		Engine.time_scale = 1.0
		DrawnLevel.return_scene = DrawnLevel.EDITOR_SCENE   # on revient tester depuis l'éditeur
		get_tree().change_scene_to_file(DrawnLevel.EDITOR_SCENE))
	layer.add_child(btn)
	add_child(layer)
	UiScaler.apply(layer)   # même taille d'interface que le reste (option + téléphone)
