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
		add_child(fish)

	# 4. Murs : avant le départ (on ne recule pas dans le vide) et au bout de
	#    la piste de freinage
	var first: PackedVector2Array = _islands[0]
	_add_wall(Vector2(first[0].x - 80.0, first[0].y - 1500.0), Vector2(80, 3000))
	var end_p: Vector2 = runout[runout.size() - 1]
	_add_wall(Vector2(end_p.x, end_p.y - 1500.0), Vector2(80, 3000))

	# 5. Arrivée au bout du trait ; après la course, retour dans l'éditeur
	var gate = finish_gate_res.instantiate()
	gate.next_scene_path = DrawnLevel.EDITOR_SCENE
	gate.position = finish_pos
	add_child(gate)

	# 6. Départ : un peu après le début du premier trait
	var sx: float = minf(first[0].x + 150.0, first[first.size() - 1].x)
	get_parent()._set_spawn_position(Vector2(sx, DrawnLevel.surface_y_of(first, sx) - 80.0))

	# 7. Bouton « ✏ Éditer »
	_add_edit_button()


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
	col.polygon = poly
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
		get_tree().change_scene_to_file(DrawnLevel.EDITOR_SCENE))
	layer.add_child(btn)
	add_child(layer)
	UiScaler.apply(layer)   # même taille d'interface que le reste (option + téléphone)
