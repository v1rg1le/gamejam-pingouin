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

# --- [PLAFONDS 1.29] Plafonds pour s'accrocher au grappin --------------------
# Retour de Léo : « Les chill levels ont pas de plafond, donc c'est peu
# dynamique ». Au chargement, on pose des PLAFONDS (des sols de glace,
# comme celui du tutoriel) au-dessus de la piste, par tronçons :
#  - un plafond de ceiling_length px tous les ceiling_period px ;
#  - à ceiling_clearance px au-dessus du point le PLUS HAUT de la piste sous
#    lui (jamais dans une piste, même dans 704 où il y a des pistes à
#    plusieurs étages), à portée de grappin (1200 px) ;
#  - incliné comme la piste (pente mesurée sous le tronçon).
# Ils font partie du terrain d'origine (dans « Plateforms ») : la boucle
# infinie les recopie avec le reste. add_ceilings = false pour les retirer.
@export var add_ceilings: bool = true
@export var ceiling_length: float = 1600.0
@export var ceiling_period: float = 4200.0
@export var ceiling_clearance: float = 450.0   # comme le plafond du tutoriel : visible à l'écran, hors de portée d'un simple saut
@export var ceiling_margin: float = 1500.0   # pas de plafond au tout début / à la toute fin

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
	if add_ceilings and not lines.is_empty():
		_add_ceilings(lines, level)
		lines.clear()
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



# --- [PLAFONDS 1.29] ---------------------------------------------------------
# Points de la piste (monde) regroupés par tranches de 64 px : pour chaque
# tranche, le point le plus HAUT (y le plus petit) de tous les sols.
func _surface_buckets(lines: Array, flipped: bool) -> Dictionary:
	var buckets := {}
	for line in lines:
		# sols retournés (pistes du haut de 704) : ils servent déjà de plafond ;
		# on les compte à part (flipped = true) pour ne pas poser de plafond
		# là où il y en a déjà un, ni au-dessus d'eux (hors de portée)
		if (line.get_parent().scale.y < 0.0) != flipped:   # (global_scale ne marche pas : (-1,-1) = rotation de 180°)
			continue
		for lp in line.points:
			var p: Vector2 = line.global_transform * lp
			var k := int(floor(p.x / 64.0))
			# piste normale : point le plus HAUT ; sol retourné : son dessous (le plus BAS)
			if not buckets.has(k) or (p.y > buckets[k] if flipped else p.y < buckets[k]):
				buckets[k] = p.y
	return buckets


func _highest_between(buckets: Dictionary, x0: float, x1: float) -> float:
	var best := INF
	for k in range(int(floor(x0 / 64.0)), int(floor(x1 / 64.0)) + 1):
		if buckets.has(k):
			best = minf(best, buckets[k])
	return best


func _add_ceilings(lines: Array, level: Node) -> void:
	var plateforms := level.get_node_or_null("Plateforms")
	if plateforms == null:
		return
	var buckets := _surface_buckets(lines, false)
	var roofs := _surface_buckets(lines, true)
	var keys := buckets.keys()
	if keys.is_empty():
		return
	keys.sort()
	var x_min: float = keys[0] * 64.0
	var x_max: float = keys[-1] * 64.0
	var sol_res = load("res://src/levels/GroundGenerator/sol.tscn")
	var n := 0
	var x := x_min + ceiling_margin
	while x + ceiling_length < x_max - ceiling_margin:
		var y_start := _highest_between(buckets, x - 64.0, x + 64.0)
		var y_end := _highest_between(buckets, x + ceiling_length - 64.0, x + ceiling_length + 64.0)
		var top := _highest_between(buckets, x, x + ceiling_length)
		# déjà un sol retourné au-dessus de ce tronçon : il sert de plafond
		# (seulement s'il est à portée de grappin : moins de 1100 px au-dessus
		# de la piste ; plus haut, il ne sert à rien et on pose notre plafond)
		var has_roof := _roof_in_reach(roofs, buckets, x - 400.0, x + ceiling_length + 400.0)
		if y_start < INF and y_end < INF and top < INF and not has_roof:
			var slope: float = (y_end - y_start) / ceiling_length
			# hauteur du plafond : ceiling_clearance au-dessus du point le plus
			# haut de la piste, en suivant la pente (repère local du plafond)
			var lift := INF
			for k in range(int(floor(x / 64.0)), int(floor((x + ceiling_length) / 64.0)) + 1):
				if buckets.has(k):
					lift = minf(lift, buckets[k] - slope * (k * 64.0 - x))
			var sol = sol_res.instantiate()
			sol.set_collision_layer(2)     # calque « ground », comme les autres sols
			sol.coeff_pente = slope
			sol.noise_octaves = 1
			sol.noise_persistence = 0.2
			sol.noise_lacunarity = 3
			sol.world_seed = "PLAFOND_%d" % n
			sol.is_boost = false
			sol.is_igloo = false
			sol.is_final_map = false
			sol.map_width = int(ceiling_length)
			sol.map_height = 24            # presque plat
			sol.h = 60                     # épaisseur
			sol.position = Vector2(x, lift - ceiling_clearance - 24)
			sol.name = "Plafond%d" % n
			plateforms.add_child(sol)
			n += 1
		x += ceiling_period
	print("[CHILL] plafonds ajoutés : ", n)


# [PLAFONDS 1.29] y a-t-il un sol retourné à portée de grappin (entre 150 et
# 1100 px au-dessus de la piste) quelque part au-dessus de ce tronçon ?
# On regarde le DESSOUS du sol retourné (y le plus grand de la tranche).
func _roof_in_reach(roofs: Dictionary, ground: Dictionary, x0: float, x1: float) -> bool:
	for k in range(int(floor(x0 / 64.0)), int(floor(x1 / 64.0)) + 1):
		if roofs.has(k) and ground.has(k):
			var gap: float = ground[k] - roofs[k]
			if gap > 150.0 and gap < 1100.0:
				return true
	return false
