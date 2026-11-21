class_name UiScaler
extends RefCounted
# =============================================================================
#  UiScaler.gd — [RESPONSIVE 1.14] agrandir l'interface d'un CanvasLayer
# -----------------------------------------------------------------------------
#  Demande de l'équipe : « que le jeu soit responsive à la taille de l'écran
#  de manière générale ». Sur un téléphone, l'écran fait 1024 × 720 unités
#  (comme un PC) mais seulement ~7 cm de haut : les textes du HUD et des
#  menus en jeu devenaient minuscules.
#
#  Problème technique : agrandir un CanvasLayer (propriété `scale`) agrandit
#  aussi ses ancrages. Un menu « plein écran » devient alors plus grand que
#  l'écran, et un classement « collé en haut à droite » sort de l'écran.
#  Solution : on glisse tous les enfants du calque dans un Control racine
#  (« UiRoot ») de taille écran ÷ échelle. Les ancrages se calculent sur cette
#  racine, puis le calque agrandit le tout : le résultat remplit exactement
#  l'écran, en plus gros.
#
#  Utilisation : UiScaler.apply(mon_calque) — à la fin de son _ready().
#  Les enfants ajoutés ensuite doivent l'être dans UiScaler.root_of(calque).
#  L'échelle vient de Settings.hud_scale() (auto selon la taille physique de
#  l'écran × réglage « Taille de l'interface » des Options).
# =============================================================================

const ROOT_NAME = "UiRoot"


static func apply(layer: CanvasLayer, scale_value: float = -1.0) -> Control:
	var s: float = scale_value if scale_value > 0.0 else Settings.hud_scale()
	var root: Control = layer.get_node_or_null(ROOT_NAME)
	if root == null:
		root = Control.new()
		root.name = ROOT_NAME
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var children := layer.get_children()
		layer.add_child(root)
		for c in children:
			c.reparent(root, false)   # garde ancrages, marges et positions
		# l'écran change de taille (rotation, fenêtre PC redimensionnée…)
		# [MES NIVEAUX 1.46] la connexion est retirée quand le calque quitte
		# l'arbre : sinon, après sa libération, Godot affichait « Lambda capture
		# was freed » à chaque changement de taille de l'écran
		var vp := layer.get_viewport()
		var on_size := func():
			if is_instance_valid(layer) and is_instance_valid(root):
				_resize(layer, root)
		vp.size_changed.connect(on_size)
		layer.tree_exiting.connect(func():
			if is_instance_valid(vp) and vp.size_changed.is_connected(on_size):
				vp.size_changed.disconnect(on_size), CONNECT_ONE_SHOT)
	layer.scale = Vector2(s, s)
	_resize(layer, root)
	return root


static func _resize(layer: CanvasLayer, root: Control) -> void:
	# [MES NIVEAUX 1.46] calque déjà retiré de l'arbre (interface reconstruite
	# par l'éditeur / « Mes niveaux », ou changement d'écran) : plus de
	# viewport, rien à redimensionner
	if not layer.is_inside_tree():
		return
	var s: float = maxf(layer.scale.x, 0.01)
	root.position = Vector2.ZERO
	root.size = layer.get_viewport().get_visible_rect().size / s


## Le Control racine d'un calque agrandi (ou le calque lui-même s'il ne l'est pas).
static func root_of(layer: Node) -> Node:
	var r = layer.get_node_or_null(ROOT_NAME)
	return r if r != null else layer
