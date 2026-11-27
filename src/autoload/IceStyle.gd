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
## Un morceau de contour reçoit le dessus de glace si sa face « dessus » est
## tournée vers le haut (composante verticale de la normale, en jeu) :
## -0.35 = jusqu'à ~70° de pente. Les flancs, les murs et les dessous n'en
## ont pas (avant, la bordure de cristaux faisait tout le tour, dessous compris).
const EDGE_UP_MIN := 0.35
## Largeur du fin contour des flancs, dessous et plafonds.
const SIDE_WIDTH := 4.0

var _body_mat: ShaderMaterial


func _ready() -> void:
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = BODY_SHADER
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
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


func _restyle_line(l: Line2D) -> void:
	if l.texture != null:
		if l.texture.resource_path in OLD_EDGE_TEXTURES:
			_replace_edge(l)
		return
	if _matches(l.default_color, RIM_COLORS):
		l.default_color = ICE_RIM


## Remplace une bordure de cristaux par le dessus de glace : on garde le
## Line2D d'origine (caché, rien n'est supprimé) et on pose, à côté, un
## Line2D par morceau de contour tourné vers le haut.
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
	var runs: Array = []
	var cur := PackedVector2Array()
	# morceaux qui ne regardent pas vers le haut (dessous, murs, plafonds) :
	# ils reçoivent un fin contour (comme les piliers du Gruyère), pour que
	# les plafonds à grappin et les flancs restent bien lisibles
	var side_runs: Array = []
	var side := PackedVector2Array()
	for i in seg_count:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var d := b - a
		if d.length_squared() < 0.01:
			continue
		# face « dessus » du Line2D = à gauche du sens de tracé : (d.y, -d.x)
		var up_local := Vector2(d.y, -d.x).normalized()
		var up_world := basis.basis_xform(up_local).normalized()
		if -up_world.y >= EDGE_UP_MIN:
			if cur.is_empty():
				cur.append(a)
			cur.append(b)
			if side.size() >= 2:
				side_runs.append(side)
			side = PackedVector2Array()
		else:
			if side.is_empty():
				side.append(a)
			side.append(b)
			if cur.size() >= 2:
				runs.append(cur)
			cur = PackedVector2Array()
	if cur.size() >= 2:
		runs.append(cur)
	if side.size() >= 2:
		side_runs.append(side)
	for r in side_runs:
		var c := Line2D.new()
		c.name = "ContourGlace"
		c.points = r
		c.width = SIDE_WIDTH
		c.default_color = ICE_RIM
		c.joint_mode = Line2D.LINE_JOINT_ROUND
		c.z_index = l.z_index
		c.z_as_relative = l.z_as_relative
		c.set_meta("ice_style", true)
		parent.add_child(c)
	# contour fermé : le dernier morceau rejoint peut-être le premier
	if l.closed and runs.size() >= 2 and runs[0][0] == runs[runs.size() - 1][runs[runs.size() - 1].size() - 1]:
		var last: PackedVector2Array = runs.pop_back()
		last.append_array(runs[0].slice(1))
		runs[0] = last
	for r in runs:
		var e := Line2D.new()
		e.name = "DessusGlace"
		e.points = r
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
		parent.add_child(e)
	l.visible = false


func _matches(c: Color, list: Array) -> bool:
	for k in list:
		if absf(c.r - k.r) + absf(c.g - k.g) + absf(c.b - k.b) < 0.03 and absf(c.a - k.a) < 0.05:
			return true
	return false
