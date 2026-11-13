extends Node
# =============================================================================
#  RaceManager.gd — [FANTÔMES] autoload : seed de course, chrono, records, fantôme
# -----------------------------------------------------------------------------
#  Première brique du multijoueur (feuille de route, étape 5).
#
#  1. SEED DE COURSE
#     Chaque fois qu'un niveau (res://src/levels/...) est chargé, on choisit un
#     seed de course. TOUT le hasard qui modifie le terrain passe par lui :
#       - les graines des îles "random_seed" (GroundGenerator, GroundGeneratorBlock,
#         SpaghettiGenerator) -> next_seed_index()
#       - le choix des décorations (sol.gd) -> deco_rng
#     => même seed = exactement le même terrain. Si un fantôme existe pour le
#     niveau, on reprend SON seed : on court sur le même terrain que lui.
#
#  2. CHRONO + RECORD
#     Le chrono démarre quand le pingouin apparaît, s'arrête à la ligne
#     d'arrivée (FinishGate appelle finish_race()), et se met en pause avec le
#     jeu. Les niveaux sans arrivée (Chill) n'ont ni chrono ni fantôme.
#
#  3. FANTÔME
#     Pendant la course, on enregistre 30 fois par seconde la position, la
#     rotation, l'animation et le grappin du pingouin. En cas de record, la
#     course est sauvegardée dans user://ghosts/<niveau>.ghost. À la course
#     suivante, un pingouin transparent la rejoue en même temps que le joueur.
#     Partage : copier un fichier .ghost dans le dossier des fantômes d'un ami
#     (bouton "Dossier des fantômes" dans le menu, sur PC). Le plus rapide des
#     fantômes présents pour un niveau est celui qui court.
# =============================================================================

signal race_finished(time: float, is_record: bool, previous_best: float)

const GHOST_DIR = "user://ghosts"
const CONFIG_PATH = "user://pinpouin.cfg"
const SAMPLE_INTERVAL = 1.0 / 30.0   # 30 échantillons par seconde
const GHOST_FORMAT_VERSION = 1

## Courir contre son meilleur fantôme (réglable dans le menu des niveaux).
var ghost_enabled: bool = true

var level_path: String = ""         # niveau en cours
var race_seed: int = 0              # seed de la course en cours
var race_time: float = 0.0          # chrono (s)
var racing: bool = false            # chrono en marche
var has_finish: bool = false        # le niveau a une ligne d'arrivée
var deco_rng := RandomNumberGenerator.new()  # hasard des décorations (sol.gd)

var _rng := RandomNumberGenerator.new()      # hasard du terrain (graines des îles)
var _player = null
var _sample_timer: float = 0.0
var _rec := {}                      # course en cours d'enregistrement
var _ghost_data = null              # fantôme chargé pour ce niveau (ou null)
var _ghost_node = null              # nœud GhostPenguin dans la scène
var _hud = null                     # RaceHud (chrono à l'écran)
var _best_cache := {}               # niveau -> meilleur temps (s)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE   # le chrono s'arrête pendant la pause
	DirAccess.make_dir_recursive_absolute(GHOST_DIR)
	_load_config()
	# On repère l'arrivée d'une nouvelle scène de niveau AVANT que ses enfants
	# (les générateurs de terrain) ne fassent leur _ready().
	get_tree().node_added.connect(_on_node_added)


# --- 1. Seed de course --------------------------------------------------------
func _on_node_added(node: Node) -> void:
	if node.get_parent() != get_tree().root:
		return
	var path := node.scene_file_path
	if path.begins_with("res://src/levels/"):
		_prepare_level(path)
	else:
		_reset_race()
		level_path = ""   # menus : pas de course


func _prepare_level(path: String) -> void:
	_reset_race()
	level_path = path
	_ghost_data = load_best_ghost(path) if ghost_enabled else null
	# Même terrain que le fantôme, sinon un nouveau seed (terrain aléatoire comme avant)
	if _ghost_data != null:
		race_seed = int(_ghost_data.seed)
	else:
		race_seed = randi()
	_rng.seed = race_seed
	deco_rng.seed = race_seed ^ 0x5bd1e995
	print("[COURSE] ", path.get_file(), " | seed ", race_seed, " | fantôme : ", _ghost_data != null)


## Graine d'île "aléatoire" (0..199), tirée du seed de course.
## Remplace randi() % 200 dans les générateurs.
func next_seed_index() -> int:
	return _rng.randi() % 200


func _reset_race() -> void:
	racing = false
	race_time = 0.0
	has_finish = false
	_player = null
	_rec = {}
	_sample_timer = 0.0
	_ghost_node = null
	_hud = null


# --- 2. Chrono + enregistrement ----------------------------------------------
func _physics_process(delta: float) -> void:
	if level_path == "":
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player != null:
			_start_race()
		return
	if not racing:
		return
	race_time += delta
	_sample_timer -= delta
	if _sample_timer <= 0.0:
		_sample_timer += SAMPLE_INTERVAL
		_record_sample()


func _start_race() -> void:
	has_finish = not get_tree().get_nodes_in_group("finish_gate").is_empty()
	if not has_finish:
		return  # niveau "Chill" : pas de chrono
	racing = true
	race_time = 0.0
	_sample_timer = 0.0
	_rec = {"version": GHOST_FORMAT_VERSION, "level": level_path, "seed": race_seed,
		"anims": [], "samples": PackedFloat32Array(), "time": 0.0}
	var scene := get_tree().current_scene
	_hud = preload("res://src/ui/race/RaceHud.gd").new()
	scene.add_child(_hud)
	_hud.set_best(get_best_time(level_path))
	if _ghost_data != null:
		_ghost_node = preload("res://src/ui/race/GhostPenguin.gd").new()
		_ghost_node.setup(_ghost_data, _player)
		scene.add_child(_ghost_node)


# Un échantillon = 10 nombres : t, x, y, rotation, n° d'animation, image,
# retourné (0/1), accroché (0/1), crochet x, crochet y.
func _record_sample() -> void:
	var spr = _player.animated_sprite
	var anim := str(spr.animation)
	var idx: int = _rec.anims.find(anim)
	if idx == -1:
		_rec.anims.append(anim)
		idx = _rec.anims.size() - 1
	var tip: Vector2 = _player.chain.tip
	var hooked: bool = _player.chain.hooked or _player.chain.flying
	_rec.samples.append_array(PackedFloat32Array([race_time, _player.global_position.x, _player.global_position.y,
		_player.rotation + spr.rotation, idx, spr.frame, 1.0 if spr.flip_h else 0.0,
		1.0 if hooked else 0.0, tip.x, tip.y]))


## Appelé par la ligne d'arrivée. Renvoie true si c'est un nouveau record.
func finish_race() -> bool:
	if not racing:
		return false
	racing = false
	_record_sample()  # dernière position exacte
	var previous_best := get_best_time(level_path)
	var is_record := previous_best < 0.0 or race_time < previous_best
	if is_record:
		_rec.time = race_time
		_save_ghost(_rec)
	print("[COURSE] arrivée en ", format_time(race_time), " | record : ", is_record)
	if _hud != null and is_instance_valid(_hud):
		_hud.show_result(race_time, is_record, previous_best)
	emit_signal("race_finished", race_time, is_record, previous_best)
	return is_record


# --- 3. Fichiers fantômes ------------------------------------------------------
func _ghost_path(path: String) -> String:
	return GHOST_DIR.path_join(path.get_file().get_basename() + ".ghost")


func _save_ghost(data: Dictionary) -> void:
	var f := FileAccess.open_compressed(_ghost_path(data.level), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_warning("[COURSE] impossible d'écrire le fantôme")
		return
	f.store_var(data)
	f.close()
	_best_cache.erase(data.level)


func _read_ghost(file_path: String):
	var f := FileAccess.open_compressed(file_path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return null
	var data = f.get_var()
	f.close()
	if typeof(data) != TYPE_DICTIONARY or not data.has("samples") or int(data.get("version", 0)) != GHOST_FORMAT_VERSION:
		return null
	return data


## Le plus rapide des fantômes présents dans user://ghosts pour ce niveau
## (le sien, ou un fichier reçu d'un ami).
func load_best_ghost(path: String):
	var best = null
	var dir := DirAccess.open(GHOST_DIR)
	if dir == null:
		return null
	for file in dir.get_files():
		if not file.ends_with(".ghost"):
			continue
		var data = _read_ghost(GHOST_DIR.path_join(file))
		if data != null and data.level == path and (best == null or data.time < best.time):
			best = data
	return best


## Meilleur temps connu pour un niveau (en secondes), -1 s'il n'y en a pas.
func get_best_time(path: String) -> float:
	if not _best_cache.has(path):
		var g = load_best_ghost(path)
		_best_cache[path] = float(g.time) if g != null else -1.0
	return _best_cache[path]


static func format_time(t: float) -> String:
	if t < 0.0:
		return "--:--.--"
	var m := int(t / 60.0)
	var s := fmod(t, 60.0)
	return "%d:%05.2f" % [m, s]


# --- Réglages -----------------------------------------------------------------
func set_ghost_enabled(value: bool) -> void:
	ghost_enabled = value
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("race", "ghost_enabled", value)
	cfg.save(CONFIG_PATH)


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		ghost_enabled = cfg.get_value("race", "ghost_enabled", true)
