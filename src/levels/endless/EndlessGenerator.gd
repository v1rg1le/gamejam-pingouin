extends Node2D
# =============================================================================
#  EndlessGenerator.gd — [SANS FIN 1.32] niveau « Sans fin » façon Alto's Odyssey
# =============================================================================
#  Idée de Manu : un niveau sans fin où le but est d'aller le plus loin possible,
#  avec des trous qu'on passe d'abord en sautant, puis au grappin « normal »,
#  puis au grappin de manière plus subtile.
#
#  Principe : le terrain est fabriqué AU FUR ET À MESURE devant le pingouin,
#  par « tronçons ». Un tronçon = une île de glace (un sol de sol.gd, en légère
#  descente pour garder de la vitesse) suivie d'un TROU d'un certain type :
#
#    SAUT            petit trou : un saut suffit (ou même la vitesse seule)
#    GRAND_SAUT      grand trou : il faut de la vitesse (PUMP) ET sauter
#    GRAPPIN         trou trop long pour sauter, une prise (poisson) au milieu
#    GRAPPIN_DOUBLE  très long trou, deux prises à enchaîner
#    GRAPPIN_MONTEE  l'île d'arrivée est PLUS HAUTE : on se balance sous la
#                    prise et on lâche dans la remontée pour être projeté
#    PLAFOND         long trou sous un plafond de glace : on s'y accroche et
#                    on avance de prise en prise
#
#  La difficulté monte avec la distance : au début, que des petits sauts ;
#  les grappins arrivent peu à peu (voir _pick_type). Chaque type de trou a été
#  réglé avec des bots (outil hors projet endless_bot.gd) : un bot qui ne fait
#  que sauter doit passer les trous « saut » et ÉCHOUER aux trous « grappin »,
#  un bot qui utilise le grappin doit tous les passer.
#
#  Chute (mode Chill) : on réapparaît au DÉBUT de l'île d'avant le trou raté,
#  avec un peu d'élan (respawn_sample, appelé par Player._pick_respawn_sample).
#
#  Les tronçons loin derrière sont libérés : la mémoire reste constante.
#  Aucun asset ajouté : îles, plafonds et prises sont les scènes du jeu.
# =============================================================================

const UNIT_SIZE := 64

enum { SAUT, GRAND_SAUT, GRAPPIN, GRAPPIN_DOUBLE, GRAPPIN_MONTEE, PLAFOND }
const TYPE_NAMES := ["saut", "grand saut", "grappin", "grappin double", "grappin montée", "plafond"]

var sol_res = preload("res://src/levels/GroundGenerator/sol.tscn")
var fish_res = preload("res://src/levels/parts/StaticBody2DFish.tscn")

## Pour les tests : -1 = tirage normal ; sinon, tous les trous de ce type.
@export var force_type: int = -1
## Longueur des îles (px), tirée entre ces deux valeurs.
@export var island_min: float = 3000.0
@export var island_max: float = 4600.0
## Pente des îles (descente : + = vers le bas), comme une piste de glisse.
@export var island_slope: float = 0.10
## Hauteur des bosses des îles (px).
@export var island_bumps: int = 110
## Terrain fabriqué jusqu'à cette distance devant le pingouin (px).
@export var build_ahead: float = 9000.0
## Tronçons libérés au-delà de cette distance derrière le pingouin (px).
@export var free_behind: float = 7000.0

var rng := RandomNumberGenerator.new()
var chunks: Array = []        # un dictionnaire par tronçon (voir _add_chunk)
var _count := 0               # nombre de tronçons créés depuis le départ
var _next_start := Vector2.ZERO   # où commence la prochaine île (surface, monde)
var _player = null
var last_ground_chunk = null  # dernier tronçon dont le pingouin a touché l'île


func _ready() -> void:
	add_to_group("endless")
	# graine de la course (même terrain pour un fantôme / le multi plus tard)
	rng.seed = RaceManager.race_seed if RaceManager.race_seed != 0 else randi()
	# 1re île : longue, pour prendre de l'élan
	_next_start = Vector2(0, 0)
	_add_chunk(SAUT, 6500.0)
	while _next_start.x < build_ahead:
		_add_chunk(_pick_type(), rng.randf_range(island_min, island_max))
	# pingouin posé au début de la 1re île
	_player = get_parent().get_node_or_null("Player")
	if _player != null:
		_player.global_position = Vector2(250, surface_y(chunks[0], 250) - 60)


# -----------------------------------------------------------------------------
#  Choix du type de trou selon la distance (n° de tronçon)
# -----------------------------------------------------------------------------
func _pick_type() -> int:
	if force_type >= 0:
		return force_type
	var k := _count
	if k < 3:
		return SAUT
	# poids de chaque type : les grappins arrivent peu à peu
	var w := [
		maxf(1.0, 5.0 - k * 0.25),           # SAUT : de moins en moins
		3.0 if k >= 3 else 0.0,              # GRAND_SAUT
		4.0 if k >= 5 else 0.0,              # GRAPPIN
		2.5 if k >= 9 else 0.0,              # GRAPPIN_DOUBLE
		2.5 if k >= 12 else 0.0,             # GRAPPIN_MONTEE
		2.0 if k >= 8 else 0.0,              # PLAFOND
	]
	# jamais deux fois de suite le même trou difficile
	if not chunks.is_empty() and chunks[-1].type >= GRAPPIN:
		w[chunks[-1].type] *= 0.3
	var total := 0.0
	for v in w:
		total += v
	var r := rng.randf() * total
	for i in w.size():
		r -= w[i]
		if r <= 0.0:
			return i
	return SAUT


# -----------------------------------------------------------------------------
#  Un tronçon = une île + le trou qui la suit (+ prises / plafond)
# -----------------------------------------------------------------------------
func _add_chunk(gap_type: int, length: float) -> void:
	var start := _next_start
	var sol = _make_island(start, length)
	# fin réelle de l'île : dernier point de la surface (map_width - UNIT_SIZE ;
	# sol.end_x est le dernier point du CONTOUR, qui revient au coin de départ)
	var end := Vector2(sol.position.x + sol.map_width - UNIT_SIZE, sol.position.y + sol.end_y)
	# difficulté douce : les trous s'allongent un peu avec la distance (max +15 %)
	var hard := clampf(_count / 40.0, 0.0, 1.0)
	var gap := 0.0
	var dy := 0.0          # dénivelé île suivante (+ = plus bas)
	var anchors: Array = []
	var ceiling = null
	match gap_type:
		SAUT:
			gap = rng.randf_range(450.0, 700.0) * (1.0 + 0.15 * hard)
			dy = rng.randf_range(80.0, 220.0)
		GRAND_SAUT:
			gap = rng.randf_range(950.0, 1250.0) * (1.0 + 0.15 * hard)
			dy = rng.randf_range(200.0, 380.0)
		GRAPPIN:
			# arrivée un peu plus HAUTE : même lancé à pleine vitesse, un saut
			# retombe avant (réglé aux bots : le bot « saut seul » échoue)
			gap = rng.randf_range(2300.0, 2700.0)
			dy = -rng.randf_range(150.0, 250.0)
			anchors.append(Vector2(end.x + gap * 0.5, end.y - 600.0))
		GRAPPIN_DOUBLE:
			# trop long pour un saut (> 4000 px) ; arrivée au même niveau ou un
			# peu plus bas, 2e prise près de l'arrivée (2 balanciers coûtent de la
			# vitesse : réglé aux bots)
			gap = rng.randf_range(4000.0, 4500.0)
			dy = rng.randf_range(0.0, 120.0)
			anchors.append(Vector2(end.x + gap * 0.3, end.y - 600.0))
			anchors.append(Vector2(end.x + gap * 0.74, end.y - 600.0))
		GRAPPIN_MONTEE:
			# arrivée BEAUCOUP plus haute : impossible au saut, il faut lâcher
			# la prise dans la remontée du balancier
			gap = rng.randf_range(1600.0, 1900.0)
			dy = -rng.randf_range(420.0, 520.0)
			# prise ~400 px au-dessus de l'île d'arrivée : le grappin TIRE vers
			# elle (traction) ; on lâche en la passant pour être projeté dessus
			anchors.append(Vector2(end.x + gap * 0.55, end.y + dy - 400.0))
		PLAFOND:
			gap = rng.randf_range(3800.0, 4400.0)
			dy = -rng.randf_range(100.0, 200.0)
			ceiling = _make_ceiling(Vector2(end.x - 300.0, end.y - 640.0), gap + 600.0)
	for a in anchors:
		var f = fish_res.instantiate()
		f.position = a
		add_child(f)
	var chunk := {
		"index": _count, "type": gap_type, "sol": sol,
		"island_start": start, "island_end": end,
		"gap_end": end.x + gap, "landing_y": end.y + dy,
		"anchors": anchors, "ceiling": ceiling,
		"nodes": [sol] + ([ceiling] if ceiling != null else []),
	}
	for c in get_children():
		if c.get_scene_file_path().contains("StaticBody2DFish") and not c.has_meta("chunk"):
			c.set_meta("chunk", _count)
			chunk.nodes.append(c)
	chunks.append(chunk)
	_count += 1
	_next_start = Vector2(end.x + gap, end.y + dy)


## Île de glace dont la SURFACE commence exactement en `start`.
func _make_island(start: Vector2, length: float):
	var sol = sol_res.instantiate()
	sol.set_collision_layer(2)          # calque « ground », comme les autres sols
	sol.coeff_pente = island_slope
	sol.noise_octaves = 1
	sol.noise_period = 2600
	sol.noise_persistence = 0.2
	sol.noise_lacunarity = 3
	sol.world_seed = "SANSFIN_%d_%d" % [rng.seed, _count]
	sol.is_boost = false
	sol.is_igloo = true                 # quelques décorations (igloos, glaçons)
	sol.igloo_treshold = 0.01
	sol.is_final_map = false
	sol.map_width = int(length)
	sol.map_height = island_bumps
	sol.h = 300                         # îles flottantes bien épaisses
	sol.position = start
	add_child(sol)                      # _ready du sol : forme calculée ici
	# on remonte / descend l'île pour que sa surface commence pile en start.y
	var s0: float = sol.map_height * sol._noise(0.0)
	sol.position.y -= s0
	return sol


## Plafond de glace presque plat (même recette que les plafonds des Chill).
func _make_ceiling(pos: Vector2, length: float):
	var sol = sol_res.instantiate()
	sol.set_collision_layer(2)
	sol.coeff_pente = 0.0
	sol.noise_octaves = 1
	sol.noise_persistence = 0.2
	sol.noise_lacunarity = 3
	sol.world_seed = "SANSFIN_PLAFOND_%d" % _count
	sol.is_boost = false
	sol.is_igloo = false
	sol.is_final_map = false
	sol.map_width = int(length)
	sol.map_height = 24
	sol.h = 60
	sol.position = pos
	add_child(sol)
	return sol


## Hauteur de la surface d'une île à l'abscisse monde x.
func surface_y(chunk: Dictionary, x: float) -> float:
	var sol = chunk.sol
	var lx: float = x - sol.position.x
	return sol.position.y + sol.map_height * sol._noise(lx) + sol.coeff_pente * lx


# -----------------------------------------------------------------------------
#  Au fil de la partie : fabriquer devant, libérer derrière, limite de chute
# -----------------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		return
	var px: float = _player.global_position.x
	while _next_start.x < px + build_ahead:
		_add_chunk(_pick_type(), rng.randf_range(island_min, island_max))
	while chunks.size() > 2 and chunks[0].gap_end < px - free_behind:
		for n in chunks[0].nodes:
			if is_instance_valid(n):
				n.queue_free()
		chunks.pop_front()
	# limite de « chute infinie » : sous le trou en cours (le décor descend sans
	# fin, le calcul automatique du pingouin au chargement ne suffit pas)
	var c = chunk_at(px)
	# île où le pingouin glisse en ce moment (pour la réapparition)
	if c != null and _player.is_on_ground and px >= c.island_start.x - 50.0 and px <= c.island_end.x + 50.0:
		last_ground_chunk = c
	if c != null:
		_player.fall_death_y = maxf(c.island_end.y, c.landing_y) + 1400.0


## Tronçon dont l'île ou le trou contient x (null si avant le départ).
func chunk_at(x: float):
	for c in chunks:
		if x <= c.gap_end:
			return c
	return chunks[-1] if not chunks.is_empty() else null


## [SANS FIN 1.32] Point de réapparition après une chute : début de l'île
## d'avant le trou raté, avec un peu d'élan (Player._pick_respawn_sample).
func respawn_sample(x: float):
	# l'île de départ du trou raté = la dernière île où il a glissé (en tombant,
	# le pingouin peut dériver sous l'île SUIVANTE : chunk_at(x) la donnerait,
	# et on sauterait le trou raté)
	var c = last_ground_chunk
	if c == null or not chunks.has(c):
		c = chunk_at(x)
	if c == null:
		return null
	var rx: float = c.island_start.x + 350.0
	return {"pos": Vector2(rx, surface_y(c, rx) - 30.0), "vel": Vector2(450.0, 0.0)}
