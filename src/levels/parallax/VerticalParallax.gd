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

var _ref_cam_y = null        # = reference_camera_y (gardé en variable pour lisibilité)
var _base_offsets := {}      # ParallaxLayer -> motion_offset.y d'origine
var _orig_y := {}            # ParallaxLayer -> position.y d'origine (éditeur)
var _bounds := {}            # ParallaxLayer -> Rect2 du sprite dans le repère du plan
var _bottom_layer = null     # plan dont le bas est le plus bas (sert de "sol" du décor)
var _top_layer = null        # plan dont le haut est le plus haut (ciel)


func _ready() -> void:
	scroll_ignore_camera_zoom = ignore_zoom
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
	# Repère les plans extrêmes (bas / haut) pour le garde-fou anti-vide
	for layer in _bounds:
		var r: Rect2 = _bounds[layer]
		if r.size == Vector2.ZERO:
			continue
		if _bottom_layer == null or _orig_y[layer] + r.end.y > _orig_y[_bottom_layer] + _bounds[_bottom_layer].end.y:
			_bottom_layer = layer
		if _top_layer == null or _orig_y[layer] + r.position.y < _orig_y[_top_layer] + _bounds[_top_layer].position.y:
			_top_layer = layer


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

	var dy: float = center_y - _ref_cam_y  # > 0 : la caméra est descendue
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
