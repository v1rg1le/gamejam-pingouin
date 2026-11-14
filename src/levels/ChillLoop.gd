extends Node2D
# =============================================================================
#  ChillLoop.gd — [CHILL 1.9] les niveaux Chill deviennent VRAIMENT infinis
# -----------------------------------------------------------------------------
#  Retour de l'équipe sur la 1.8 : « les niveaux chill ne bouclent pas à
#  l'infini. Pinpouin finit par tomber, réapparaît au bout de 2 s et se rejette
#  dans le vide en boucle ». En effet : au bout du dernier sol, il n'y avait
#  plus rien, et la réapparition (2 s en arrière, avec son élan) le relançait
#  droit dans le vide.
#
#  Principe (aucune nouvelle ressource, aucun nœud existant modifié) :
#   - au chargement, on repère le DÉBUT du terrain (1er point du sol le plus à
#     gauche) et sa FIN (dernier point du sol le plus à droite) ;
#   - on recopie les nœuds de terrain (`Plateforms`, et `Objects` s'il existe :
#     les boosts) bout à bout : la copie n°k est décalée de k × (fin - début),
#     donc son début se raccorde exactement à la fin de la copie précédente ;
#   - pendant le jeu, on garde toujours COPIES_AHEAD copies devant le pingouin
#     et on supprime celles qu'il a laissées loin derrière : le terrain est
#     infini, sans coupure, et la mémoire reste stable.
#  Les sols sont regénérés à l'identique par sol.gd (même graine `world_seed`).
#  À poser dans un niveau Chill (nœud "BoucleInfinie", déjà fait pour 704 et 917).
# =============================================================================

@export var terrain_nodes: Array[String] = ["Plateforms", "Objects"]
## Nombre de copies gardées devant le pingouin.
@export var copies_ahead: int = 2
## Chevauchement (px) au raccord, pour qu'il n'y ait jamais de fente entre deux
## copies (la nouvelle copie commence un tout petit peu avant la fin).
@export var joint_overlap: float = 2.0

var _period := Vector2.ZERO      # décalage entre deux copies (fin - début)
var _start := Vector2.ZERO       # début du terrain d'origine (monde)
var _copies := {}                # k -> Array de nœuds copiés
var _sources: Array = []         # nœuds de terrain d'origine
var _ready_done := false


func _ready() -> void:
	# les sols calculent leur forme dans leur propre _ready() : on attend la
	# fin du chargement de la scène avant de mesurer
	_setup.call_deferred()


func _setup() -> void:
	var level := get_parent()
	for n in terrain_nodes:
		var node := level.get_node_or_null(n)
		if node != null:
			_sources.append(node)
	var lines: Array = []
	for src in _sources:
		_collect_lines(src, lines)
	if lines.is_empty():
		push_warning("[CHILL] aucun sol trouvé : pas de boucle infinie")
		return
	var first := Vector2(INF, 0)
	var last := Vector2(-INF, 0)
	for line in lines:
		var pts: PackedVector2Array = line.points
		if pts.is_empty():
			continue
		# la ligne d'un sol fait le tour complet du polygone (dessus + dessous) :
		# aux deux bouts, on garde le point le plus HAUT (la surface)
		for lp in pts:
			var p: Vector2 = line.global_transform * lp
			if p.x < first.x - 0.5 or (absf(p.x - first.x) <= 0.5 and p.y < first.y):
				first = p
			if p.x > last.x + 0.5 or (absf(p.x - last.x) <= 0.5 and p.y < last.y):
				last = p
	_start = first
	_period = last - first - Vector2(joint_overlap, 0)
	if _period.x < 500.0:
		push_warning("[CHILL] terrain trop court pour boucler")
		return
	_ready_done = true
	print("[CHILL] boucle infinie : début ", first.round(), " fin ", last.round(), " décalage ", _period.round())


func _collect_lines(node: Node, out: Array) -> void:
	# les sols (sol.gd) dessinent leur surface dans un Line2D enfant
	if node is Line2D and node.get_parent() != null and node.get_parent().has_method("generate_curve"):
		out.append(node)
	for c in node.get_children():
		_collect_lines(c, out)


func _physics_process(_delta: float) -> void:
	if not _ready_done:
		return
	var player = get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		return
	# n° de la copie sous le pingouin (0 = terrain d'origine)
	var k_here := int(floor((player.global_position.x - _start.x) / _period.x))
	for k in range(maxi(1, k_here - 1), k_here + copies_ahead + 1):
		if not _copies.has(k):
			_spawn_copy(k)
	for k in _copies.keys():
		if k < k_here - 1:      # laissée loin derrière : on libère
			for n in _copies[k]:
				n.queue_free()
			_copies.erase(k)


func _spawn_copy(k: int) -> void:
	var nodes := []
	for src in _sources:
		var copy: Node = _copy_node(src)
		copy.name = "%s_boucle%d" % [src.name, k]
		if copy is Node2D:
			copy.position = src.position + _period * k
		src.get_parent().add_child(copy)
		nodes.append(copy)
	_copies[k] = nodes
	# le terrain descend plus bas : la limite de « chute infinie » du pingouin
	# (calculée au chargement d'après le point le plus bas du décor) doit suivre
	var player = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("_compute_fall_death_y"):
		player._compute_fall_death_y.call_deferred()


# Copie « propre » d'un nœud de terrain :
#  - un sol généré (sol.gd) n'est PAS dupliqué tel quel (il contient déjà ses
#    décorations ajoutées au chargement, qui seraient ajoutées une 2e fois) :
#    on crée une instance neuve de sa scène avec les mêmes réglages, et il se
#    regénère à l'identique (même graine) ;
#  - un simple conteneur (Plateforms, Objects) est recréé et ses enfants copiés ;
#  - le reste (boosts, poissons…) est dupliqué normalement.
func _copy_node(src: Node) -> Node:
	if src.has_method("generate_curve") and src.scene_file_path != "":
		var inst: Node = load(src.scene_file_path).instantiate()
		for prop in src.get_property_list():
			if prop.usage & PROPERTY_USAGE_STORAGE and prop.name != "script":
				inst.set(prop.name, src.get(prop.name))
		return inst
	if src.get_class() == "Node2D" and src.scene_file_path == "" and src.get_script() == null:
		var box := Node2D.new()
		box.transform = src.transform
		for c in src.get_children():
			box.add_child(_copy_node(c))
		return box
	return src.duplicate()
