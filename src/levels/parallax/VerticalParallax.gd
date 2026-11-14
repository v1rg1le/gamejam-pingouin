extends ParallaxBackground
# =============================================================================
#  VerticalParallax.gd — [NOUVEAU] parallax vertical propre pour les fonds
# -----------------------------------------------------------------------------
#  Problème d'origine : les ParallaxLayer avaient motion_scale.y = 1, donc les
#  fonds étaient "collés" au monde verticalement. Dès que le niveau descendait
#  ou montait de quelques milliers de pixels, les fonds sortaient de l'écran.
#  Mettre motion_scale.y à 0 les colle à l'écran, mais on perd toute
#  sensation de profondeur verticale.
#
#  Solution :
#   - L'horizontal reste EXACTEMENT géré comme avant par Godot (motion_scale.x).
#   - Le vertical est piloté ici : chaque plan se décale d'une fraction du
#     déplacement vertical de la caméra, proportionnelle à sa profondeur
#     (on réutilise motion_scale.x : 0.9 = plan proche, 0.7 = plan lointain),
#     ce qui conserve la perspective entre les plans.
#   - Ce décalage est "adouci" par une tangente hyperbolique (tanh) : il suit
#     la caméra sur les petits mouvements puis sature à `max_vertical_shift`.
#     Résultat : les fonds ne quittent JAMAIS l'écran, même après une chute
#     de 10 000 px, et le mouvement reste fluide (pas de butée brutale).
#   - Le cadrage de référence est celui que les graphistes avaient réglé dans
#     l'éditeur pour une caméra à la hauteur `reference_camera_y` (y = 0 par
#     défaut, là où les niveaux ont été dessinés). Avant, un niveau qui
#     démarrait plus haut (tremplin à y = -1600) n'affichait déjà aucun fond.
#   - Garde-fou : le plan le plus bas (glacier) ne remonte jamais au-dessus
#     du bas de l'écran, et le plan le plus haut ne descend jamais sous le haut
#     de l'écran -> on ne voit plus de "vide" gris sous le décor.
#   - Les fonds ignorent le zoom de la caméra adaptative (un paysage lointain
#     ne change pas de taille quand on dézoome), ce qui évite aussi de voir
#     leurs bords quand la caméra s'élargit.
#  Script à poser sur le nœud ParallaxBackground d'un niveau (déjà fait pour
#  tous les niveaux existants).
#
#  [FOND 1.8] (demande de l'équipe, 14/11 : « pas de coupure nette, une boucle
#  infinie qui suit les pentes et s'adapte à la forme du niveau ») :
#   1. BOUCLE HORIZONTALE INFINIE : chaque plan reçoit un motion_mirroring.x
#      égal à la largeur de son motif (largeur de l'image × échelle du sprite,
#      320 × 10 = 3200 px pour les fonds actuels). Godot répète alors le plan
#      à l'infini ; comme l'image est elle-même répétée (texture_repeat), le
#      raccord est invisible. Avant : chaque plan s'arrêtait au bout de sa
#      région (70 000 px), ce qui coupait le fond sur les niveaux longs
#      (ex. le tuto Bateau, vers x = 14 000).
#   2. LE FOND SUIT LES PENTES : la hauteur de référence n'est plus fixe. Elle
#      suit la caméra en douceur (moyenne glissante, follow_time ≈ 3 s) :
#        - sur une longue descente ou montée, le fond « accompagne » le niveau
#          et garde la même composition à l'écran (glacier en bas, ciel en
#          haut), au lieu de rester bloqué en butée ;
#        - sur les mouvements rapides (sauts, chutes, grappin), l'écart avec
#          cette référence donne toujours l'effet de profondeur entre les
#          plans (le proche bouge plus que le lointain).
#      follow_time = 0 revient à l'ancien comportement (référence fixe).
#   3. PLUS DE BORD NET EN HAUT ET EN BAS DES IMAGES : chaque image de fond
#      s'arrêtait sur une ligne droite (bas du ciel, bas des montagnes…). Dès
#      que le parallax décalait un peu les plans, on voyait ces coupures.
#      On PROLONGE donc chaque image, sans nouvel asset : la dernière ligne
#      entièrement opaque de l'image est étirée vers le bas (et, pour le plan
#      le plus lointain, la première ligne vers le haut). Ces prolongements
#      sont des Sprite2D enfants, dessinés DERRIÈRE l'image d'origine
#      (show_behind_parent), qui reste intacte. Les falaises du glacier se
#      prolongent ainsi naturellement vers le bas, le ciel vers le haut.
# =============================================================================

## Active le parallax vertical (sinon : fonds fixes verticalement à l'écran).
@export var vertical_parallax_enabled: bool = true
## Part du déplacement vertical de la caméra répercutée sur le plan le plus proche.
@export_range(0.0, 1.0) var vertical_strength: float = 0.15
## Décalage vertical maximum (px écran) du plan le plus proche.
@export var max_vertical_shift: float = 220.0
## Les fonds ne suivent pas le zoom de la caméra.
@export var ignore_zoom: bool = true
## Hauteur de caméra (monde) pour laquelle les fonds sont exactement à leur
## place "éditeur". Le décalage vertical est calculé par rapport à elle.
@export var reference_camera_y: float = 0.0
## [FOND 1.8] Temps (s) que met la référence verticale à rejoindre la caméra :
## le fond suit les pentes du niveau. 0 = référence fixe (ancien comportement).
@export var follow_time: float = 3.0
## [FOND 1.8] Boucle horizontale infinie des plans (motion_mirroring).
@export var infinite_horizontal: bool = true
## [FOND 1.8] Prolonge les images vers le haut / le bas (plus de bord net).
@export var extend_vertically: bool = true
## [FOND 1.9] Parallaxe « lisible » (retour de l'équipe sur la 1.8 : fond
## dégradé, « veines grises qui bougent à peine ») :
##  - les images sont agrandies de façon UNIFORME (×5 en largeur comme en
##    hauteur, au lieu de ×10 en largeur et ×5 en hauteur, qui étirait le
##    pixel-art en longues traînées horizontales) ;
##  - les vitesses de défilement suivent la profondeur réelle des plans : le
##    plus au fond (glacier) défile lentement, le plus en avant (montagnes)
##    plus vite. Avant, elles étaient de 0,7 à 0,9 : les fonds défilaient
##    presque aussi vite que la piste, sans effet de profondeur.
@export var readable_parallax: bool = true
## Vitesses de défilement, du plan le plus au fond au plus en avant.
@export var parallax_speeds: Array[float] = [0.2, 0.35, 0.5]
## Force de l'effet vertical en mode lisible (remplace vertical_strength).
@export_range(0.0, 1.0) var readable_vertical_strength: float = 0.3

## [FOND 1.8] Décalage (px écran) de toute la composition : > 0 la descend.
@export var anchor_offset: float = 0.0
## [FOND 1.8] Longueur des prolongements, en pixels de l'image d'origine
## (× l'échelle du sprite : 2000 × 5 = 10 000 px à l'écran).
@export var extension_rows: float = 2000.0

var _follow_y = null         # [FOND 1.8] hauteur de caméra moyenne (suit les pentes)

var _ref_cam_y = null        # = reference_camera_y (gardé en variable pour lisibilité)
var _base_offsets := {}      # ParallaxLayer -> motion_offset.y d'origine
var _orig_y := {}            # ParallaxLayer -> position.y d'origine (éditeur)
var _bounds := {}            # ParallaxLayer -> Rect2 du sprite dans le repère du plan
var _bottom_layer = null     # plan dont le bas est le plus bas (sert de "sol" du décor)
var _top_layer = null        # plan dont le haut est le plus haut (ciel)


func _ready() -> void:
	scroll_ignore_camera_zoom = ignore_zoom
	if readable_parallax:
		_apply_readable_parallax()   # [FOND 1.9] avant toute mesure
	for child in get_children():
		if child is ParallaxLayer:
			_base_offsets[child] = child.motion_offset.y
			# [MIGRATION GODOT 4.7] la répétition de texture n'est plus une option
			# d'import mais une propriété du nœud : sans elle, les fonds (région de
			# 7000 px sur une image de 320 px) s'affichaient étirés / tronqués.
			child.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			# Position "éditeur" du plan : si la caméra a déjà fait défiler le
			# fond avant ce _ready (joueur placé dans la scène), on retire ce défilement.
			_orig_y[child] = child.position.y - (scroll_offset.y + scroll_base_offset.y) * child.motion_scale.y - child.motion_offset.y
			_bounds[child] = _layer_bounds(child)
			# Le vertical est désormais calculé dans _process()
			child.motion_scale.y = 0.0
			# [FOND 1.8] boucle horizontale infinie
			if infinite_horizontal:
				var period := _layer_period(child)
				if period > 0.0:
					child.motion_mirroring.x = period
	# [FOND 1.8] prolongements haut / bas (après le calcul des _bounds d'origine)
	if extend_vertically:
		_extend_all()
	# Repère les plans extrêmes (bas / haut) pour le garde-fou anti-vide
	for layer in _bounds:
		var r: Rect2 = _bounds[layer]
		if r.size == Vector2.ZERO:
			continue
		if _bottom_layer == null or _orig_y[layer] + r.end.y > _orig_y[_bottom_layer] + _bounds[_bottom_layer].end.y:
			_bottom_layer = layer
		if _top_layer == null or _orig_y[layer] + r.position.y < _orig_y[_top_layer] + _bounds[_top_layer].position.y:
			_top_layer = layer


# [FOND 1.9] Échelle uniforme + vitesses de défilement selon la profondeur.
# L'ordre de profondeur est celui des z_index des images (glacier -126 au fond,
# nuages -123, montagnes -120 devant), pas l'ordre dans l'arbre.
func _apply_readable_parallax() -> void:
	var layers := []
	for child in get_children():
		if child is ParallaxLayer:
			var spr = null
			for c in child.get_children():
				if c is Sprite2D:
					spr = c
					break
			layers.append([spr.z_index if spr != null else 0, child, spr])
	layers.sort_custom(func(a, b): return a[0] < b[0])
	for i in layers.size():
		var layer: ParallaxLayer = layers[i][1]
		var spr = layers[i][2]
		layer.motion_scale.x = parallax_speeds[mini(i, parallax_speeds.size() - 1)]
		if spr != null and absf(spr.scale.x) != absf(spr.scale.y):
			spr.scale.x = signf(spr.scale.x) * absf(spr.scale.y)
	vertical_strength = readable_vertical_strength


# [FOND 1.8] Prolonge les images de fond. L'ordre d'affichage des plans est
# donné par leur z_index (dans les niveaux : glacier -126 au fond, nuages -123,
# montagnes -120 devant), pas par leur ordre dans l'arbre :
#  - chaque image dont la RÉGION coupe le dessin en ligne droite (ex. le bas
#    des nuages, coupé à la ligne 180 alors que le dessin s'arrête à 200 par
#    un bord ondulé) retrouve son bord naturel : la région est agrandie
#    jusqu'au bout du dessin, sans rien déplacer à l'écran ;
#  - une image qui touche son bord HAUT par une ligne pleine (le ciel) est
#    prolongée vers le haut avec sa couleur dominante ;
#  - le plan le plus au fond (le glacier) est prolongé vers le bas (sa
#    dernière ligne étirée : les falaises continuent) et vers le haut
#    (couleur de sa brume), pour qu'aucun vide n'apparaisse jamais derrière.
func _extend_all() -> void:
	var sprites := []
	for layer in _base_offsets:
		for c in layer.get_children():
			if c is Sprite2D and c.texture != null:
				sprites.append(c)
	if sprites.is_empty():
		return
	var back: Sprite2D = sprites[0]
	for spr in sprites:
		if spr.z_index < back.z_index:
			back = spr
	for spr in sprites:
		_extend_sprite(spr, spr == back)


func _extend_sprite(spr: Sprite2D, is_back: bool) -> void:
	var img: Image = spr.texture.get_image()
	if img == null:
		return
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	if not spr.region_enabled:
		return
	var used := img.get_used_rect()          # lignes réellement dessinées
	var reg: Rect2 = spr.region_rect
	# 1. Région coupée en plein dessin -> on la rallonge jusqu'au bord du dessin
	#    (seulement dans l'image, sans répétition verticale)
	if reg.end.y < used.end.y and reg.end.y > used.position.y:
		var grow := used.end.y - reg.end.y
		reg.size.y += grow
		spr.region_rect = reg
		if spr.centered:
			spr.position.y += grow * 0.5 * spr.scale.y   # le haut reste au même endroit
	if reg.position.y > used.position.y and reg.position.y < used.end.y:
		var grow_up := reg.position.y - used.position.y
		reg.position.y -= grow_up
		reg.size.y += grow_up
		spr.region_rect = reg
		if spr.centered:
			spr.position.y -= grow_up * 0.5 * spr.scale.y
	var rect: Rect2 = spr.get_rect()
	# lignes de l'image affichées par la région
	var r0 := clampi(int(ceil(reg.position.y)), 0, h - 1)
	var r1 := clampi(int(floor(reg.end.y)) - 1, 0, h - 1)
	var top_row := -1
	var bottom_row := -1
	for r in range(r0, r1 + 1):
		if _row_opaque(img, r):
			if top_row < 0:
				top_row = r
			bottom_row = r
	# 2. Vers le haut : si l'image touche son haut par une ligne pleine (ciel),
	#    ou pour le plan du fond (couleur de la 1re ligne pleine)
	if top_row >= 0 and (top_row <= used.position.y + 1 or is_back):
		_add_extension(spr, reg, top_row, rect.position.y + (top_row - reg.position.y), false, rect, img)
	# 3. Vers le bas : plan du fond uniquement (sinon il cacherait les plans
	#    situés derrière lui)
	if is_back and bottom_row >= 0:
		_add_extension(spr, reg, bottom_row, rect.position.y + (bottom_row + 1 - reg.position.y), true, rect, img)


func _add_extension(spr: Sprite2D, reg: Rect2, row: int, edge_y: float, downward: bool, rect: Rect2, img: Image) -> void:
	var ext := Sprite2D.new()
	ext.name = "Prolongement" + ("Bas" if downward else "Haut")
	ext.texture = spr.texture
	ext.centered = false
	ext.region_enabled = true
	# [FOND 1.9] un seul pixel de la couleur dominante de la ligne, étiré : un
	# aplat uni. (En 1.8, la ligne entière était étirée vers le bas : ça
	# faisait les longues « veines grises » verticales signalées par l'équipe.)
	var x := _dominant_pixel_x(img, row)
	ext.region_rect = Rect2(x, row, 1, 1)
	ext.scale = Vector2(reg.size.x, extension_rows)
	ext.position = Vector2(rect.position.x, edge_y - (0.0 if downward else extension_rows))
	ext.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ext.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ext.show_behind_parent = true   # l'image d'origine reste dessinée par-dessus
	spr.add_child(ext)


func _dominant_pixel_x(img: Image, r: int) -> int:
	var counts := {}
	var first := {}
	for x in img.get_width():
		var c := img.get_pixel(x, r)
		counts[c] = counts.get(c, 0) + 1
		if not first.has(c):
			first[c] = x
	var best = null
	for c in counts:
		if best == null or counts[c] > counts[best]:
			best = c
	return first[best]


func _row_opaque(img: Image, r: int) -> bool:
	for x in img.get_width():
		if img.get_pixel(x, r).a < 0.99:
			return false
	return true


# [FOND 1.8] Largeur (px du plan) après laquelle le motif se répète : largeur de
# l'image × échelle si l'image est répétée dans la région du sprite, sinon
# largeur du sprite entier. 0 si le plan n'a pas d'image.
func _layer_period(layer: Node) -> float:
	for c in layer.get_children():
		if c is Sprite2D and c.texture != null:
			var tex_w: float = c.texture.get_size().x
			var reg_w: float = c.region_rect.size.x if c.region_enabled else tex_w
			var w: float = tex_w if reg_w > tex_w else reg_w
			return absf(w * c.scale.x)
	return 0.0


# Rectangle (dans le repère du ParallaxLayer) réellement VISIBLE de ses Sprite2D :
# on ignore les lignes transparentes de l'image (ex. le haut de
# Background_glacier.png est vide), sinon le garde-fou croirait le bas de
# l'écran couvert alors qu'on y voit le vide.
func _layer_bounds(layer: Node) -> Rect2:
	var rect := Rect2()
	var first := true
	for c in layer.get_children():
		if c is Sprite2D and c.texture != null:
			var tex_size: Vector2 = c.texture.get_size()
			var used := Rect2(Vector2.ZERO, tex_size)
			var img: Image = c.texture.get_image()
			if img != null:
				used = Rect2(img.get_used_rect())
			var reg: Rect2 = c.region_rect if c.region_enabled else Rect2(Vector2.ZERO, tex_size)
			var y0: float = max(reg.position.y, used.position.y)
			var y1: float = min(reg.end.y, used.end.y)
			if y1 <= y0:
				continue
			var full: Rect2 = c.get_rect()  # rectangle local du sprite (taille de la région)
			var visible_local := Rect2(full.position.x, full.position.y + (y0 - reg.position.y), full.size.x, y1 - y0)
			var r: Rect2 = c.transform * visible_local
			rect = r if first else rect.merge(r)
			first = false
	return rect


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var center_y: float = cam.get_screen_center_position().y
	var half_h: float = get_viewport().get_visible_rect().size.y * 0.5
	if _ref_cam_y == null:
		_ref_cam_y = reference_camera_y

	# [FOND 1.8] la référence suit la caméra en douceur (le fond suit les pentes)
	if _follow_y == null:
		_follow_y = center_y
	if follow_time > 0.0:
		_follow_y = lerpf(_follow_y, center_y, 1.0 - exp(-_delta / follow_time))
	var dy: float = center_y - (_follow_y if follow_time > 0.0 else _ref_cam_y)  # > 0 : la caméra est descendue
	var offsets := {}
	for layer in _base_offsets:
		# Décalage qui reproduit le cadrage "éditeur" quand la caméra est à la
		# hauteur de référence (avec motion_scale.y = 1, le plan était placé
		# à -haut_de_la_caméra).
		var offset_y: float = half_h - _ref_cam_y
		if vertical_parallax_enabled:
			var depth: float = clamp(layer.motion_scale.x, 0.05, 1.0)  # proche ~0.9, loin ~0.7
			var limit: float = max_vertical_shift * depth
			var raw: float = -dy * vertical_strength * depth
			offset_y += limit * tanh(raw / limit)  # douce saturation
		offsets[layer] = offset_y

	# Garde-fou anti-vide : même correction pour tous les plans (la
	# composition et la perspective entre plans restent intactes).
	var correction := 0.0
	var view_h := half_h * 2.0
	if extend_vertically and _bottom_layer != null:
		# [FOND 1.8] composition FIXE à l'écran : le bas de l'image du glacier
		# (plan le plus bas) est calé sur le bas de l'écran — c'est la mise en
		# page que le garde-fou produisait déjà la plupart du temps. Les plans
		# gardent leur disposition d'origine entre eux ; seul l'écart caméra /
		# référence (sauts, chutes) les fait bouger, chacun selon sa profondeur.
		# Les images étant prolongées, ces mouvements ne montrent jamais de bord.
		var b = _bottom_layer
		var anchor: float = view_h - (_base_offsets[b] + (half_h - _ref_cam_y) + _orig_y[b] + _bounds[b].end.y) + anchor_offset
		for layer in offsets:
			layer.motion_offset.y = _base_offsets[layer] + offsets[layer] + anchor
		return
	if _bottom_layer != null:
		var bottom: float = _base_offsets[_bottom_layer] + offsets[_bottom_layer] + _orig_y[_bottom_layer] + _bounds[_bottom_layer].end.y
		if bottom < view_h:
			correction = view_h - bottom          # on redescend le décor
	if correction == 0.0 and _top_layer != null:
		var top: float = _base_offsets[_top_layer] + offsets[_top_layer] + _orig_y[_top_layer] + _bounds[_top_layer].position.y
		if top > 0.0:
			correction = -top                     # on remonte le décor
	for layer in offsets:
		layer.motion_offset.y = _base_offsets[layer] + offsets[layer] + correction
