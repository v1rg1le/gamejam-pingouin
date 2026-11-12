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
#   - Au démarrage, le cadrage est identique à celui d'avant (Godot 3).
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

var _ref_cam_y = null        # hauteur de la caméra au démarrage du niveau
var _base_offsets := {}      # ParallaxLayer -> motion_offset.y d'origine


func _ready() -> void:
	scroll_ignore_camera_zoom = ignore_zoom
	for child in get_children():
		if child is ParallaxLayer:
			_base_offsets[child] = child.motion_offset.y
			# Le vertical est désormais calculé dans _process()
			child.motion_scale.y = 0.0


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var center_y: float = cam.get_screen_center_position().y
	var half_h: float = get_viewport().get_visible_rect().size.y * 0.5
	if _ref_cam_y == null:
		_ref_cam_y = center_y  # première frame : on mémorise la référence

	var dy: float = center_y - _ref_cam_y  # > 0 : la caméra est descendue
	for layer in _base_offsets:
		# Décalage qui reproduit le cadrage d'origine au démarrage
		# (avec motion_scale.y = 1, le plan était placé à -haut_de_la_caméra).
		var offset_y: float = half_h - _ref_cam_y
		if vertical_parallax_enabled:
			var depth: float = clamp(layer.motion_scale.x, 0.05, 1.0)  # proche ~0.9, loin ~0.7
			var limit: float = max_vertical_shift * depth
			var raw: float = -dy * vertical_strength * depth
			offset_y += limit * tanh(raw / limit)  # douce saturation
		layer.motion_offset.y = _base_offsets[layer] + offset_y
