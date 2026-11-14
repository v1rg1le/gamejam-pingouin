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
#
#  4. [MULTI] COURSE EN RÉSEAU LOCAL (étape 6, avec NetSession)
#     Quand NetSession.in_race est vrai :
#       - le seed est celui choisi par l'hôte (tout le monde a le même terrain),
#         et il n'y a pas de fantôme (les vrais adversaires le remplacent) ;
#       - le pingouin est figé (process_mode DISABLED) jusqu'à la fin du compte
#         à rebours 3-2-1-GO, lancé par l'hôte quand TOUT le monde est chargé ;
#       - l'état du pingouin local est envoyé 20 fois par seconde ;
#       - les pingouins des autres (RemotePenguin) sont créés à la réception de
#         leur premier état, et supprimés s'ils se déconnectent ;
#       - à l'arrivée, le temps est annoncé à tous et le HUD affiche le classement.
#
#  5. [SCORE 1.5] SCORE = POINTS DE VITESSE + POINTS DE FIGURES
#       - points de vitesse = SPEED_POINTS / temps (s) : 60 000 / 30 s = 2000 ;
#         plus on arrive vite, plus on en a ;
#       - points de figures : comptés par TrickScore.gd (figures, vrilles,
#         combos, validés à l'atterrissage) ;
#       - le meilleur score de chaque niveau est mémorisé dans user://pinpouin.cfg
#         (le record de TEMPS et son fantôme restent gérés comme avant) ;
#       - en multijoueur, le classement se fait au score.
# =============================================================================

signal race_finished(time: float, is_record: bool, previous_best: float)

const GHOST_DIR = "user://ghosts"
const CONFIG_PATH = "user://pinpouin.cfg"
const SAMPLE_INTERVAL = 1.0 / 30.0   # 30 échantillons par seconde
const GHOST_FORMAT_VERSION = 1
const SPEED_POINTS = 60000.0         # [SCORE 1.5] points de vitesse = SPEED_POINTS / temps (s)

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

# [MULTI] course en réseau
var _remotes := {}                  # peer_id -> nœud RemotePenguin
var _state_timer: float = 0.0       # cadence d'envoi de l'état local (20/s)
var _countdown: float = -1.0        # > 0 : compte à rebours en cours (s restantes)
var _waiting_go: bool = false       # pingouin figé, en attente du "GO" de l'hôte

# [SCORE 1.5]
var trick_score = null              # nœud TrickScore de la course en cours
var last_score := {}                # détail du dernier score : speed, tricks, score
var _best_scores := {}              # niveau -> meilleur score (chargé depuis la config)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE   # le chrono s'arrête pendant la pause
	DirAccess.make_dir_recursive_absolute(GHOST_DIR)
	_load_config()
	# On repère l'arrivée d'une nouvelle scène de niveau AVANT que ses enfants
	# (les générateurs de terrain) ne fassent leur _ready().
	get_tree().node_added.connect(_on_node_added)
	# [MULTI] le compte à rebours est lancé par l'hôte (NetSession). On se
	# connecte en différé : NetSession est déclaré APRÈS RaceManager.
	_connect_net.call_deferred()


func _connect_net() -> void:
	NetSession.countdown_started.connect(_on_countdown_started)
	NetSession.race_results_changed.connect(func():
		if _hud != null and is_instance_valid(_hud):
			_hud.set_ranking(NetSession.ranking())
			# déjà arrivé : on met à jour le bandeau ("En attente des autres…" disparaît)
			if NetSession.my_rank() > 0:
				_hud.show_multi_result(NetSession.players[NetSession.my_id()].time,
					NetSession.my_rank(), NetSession.players.size(), last_score))


# --- 1. Seed de course --------------------------------------------------------
func _on_node_added(node: Node) -> void:
	if node.get_parent() != get_tree().root:
		return
	var path := node.scene_file_path
	# [AIDE 1.7] un nœud ajouté à la racine par code (ex. la pause lecture,
	# ReadingPause) n'est pas une nouvelle scène : on l'ignore
	if path == "":
		return
	if path.begins_with("res://src/levels/"):
		_prepare_level(path)
	else:
		_reset_race()
		level_path = ""   # menus : pas de course


func _prepare_level(path: String) -> void:
	_reset_race()
	level_path = path
	_ghost_data = load_best_ghost(path) if ghost_enabled else null
	# [MULTI] en course réseau : seed imposé par l'hôte, pas de fantôme
	if NetSession.in_race:
		_ghost_data = null
		race_seed = NetSession.race_seed
	# Même terrain que le fantôme, sinon un nouveau seed (terrain aléatoire comme avant)
	elif _ghost_data != null:
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
	_remotes.clear()          # [MULTI] les nœuds sont libérés avec l'ancienne scène
	_state_timer = 0.0
	_countdown = -1.0
	_waiting_go = false
	trick_score = null        # [SCORE 1.5] libéré avec l'ancienne scène


# --- 2. Chrono + enregistrement ----------------------------------------------
func _physics_process(delta: float) -> void:
	if level_path == "":
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player != null:
			_start_race()
		return
	# [MULTI] compte à rebours puis envoi de l'état local (même après l'arrivée,
	# pour que les autres nous voient continuer à glisser)
	if NetSession.in_race:
		_update_countdown(delta)
		_state_timer -= delta
		if _state_timer <= 0.0 and not _waiting_go:
			_state_timer += NetSession.STATE_INTERVAL
			_send_state()
	if not racing:
		return
	race_time += delta
	_sample_timer -= delta
	if _sample_timer <= 0.0:
		_sample_timer += SAMPLE_INTERVAL
		_record_sample()


func _start_race() -> void:
	has_finish = not get_tree().get_nodes_in_group("finish_gate").is_empty()
	_show_start_help()   # [AIDE 1.7] carte d'aide (jeu en pause) si l'option est active
	if not has_finish and not NetSession.in_race:
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
	# [SCORE 1.5] juge des figures : il observe le pingouin et prévient le HUD
	trick_score = preload("res://src/ui/race/TrickScore.gd").new()
	trick_score.setup(_player)
	scene.add_child(trick_score)
	trick_score.points_banked.connect(func(_pts, total, label):
		if is_instance_valid(_hud):
			_hud.set_trick_points(total)
			_hud.show_trick_popup(label, Color(1, 0.94, 0.4)))
	trick_score.points_lost.connect(func(reason):
		if is_instance_valid(_hud):
			_hud.show_trick_popup(reason, Color(1, 0.5, 0.45)))
	trick_score.pending_changed.connect(func(text):
		if is_instance_valid(_hud):
			_hud.set_pending(text))
	if _ghost_data != null:
		_ghost_node = preload("res://src/ui/race/GhostPenguin.gd").new()
		_ghost_node.setup(_ghost_data, _player)
		scene.add_child(_ghost_node)
	# [MULTI] on fige le pingouin et on prévient l'hôte qu'on est prêt.
	# Le chrono ne part qu'au "GO" (cf. _on_countdown_started).
	if NetSession.in_race:
		racing = false
		_waiting_go = true
		_player.process_mode = Node.PROCESS_MODE_DISABLED
		_hud.set_best(-2.0)   # -2 = "en attente des autres joueurs"
		_hud.set_ranking(NetSession.ranking())
		NetSession.notify_loaded()


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
	# [SCORE 1.5] une figure en cours en passant la ligne compte (avant de couper le chrono)
	if trick_score != null and is_instance_valid(trick_score):
		trick_score.bank()
	racing = false
	_record_sample()  # dernière position exacte
	var previous_best := get_best_time(level_path)
	var is_record := previous_best < 0.0 or race_time < previous_best
	if is_record:
		_rec.time = race_time
		_save_ghost(_rec)
	# [SCORE 1.5] calcul du score
	var tricks: int = trick_score.total if trick_score != null and is_instance_valid(trick_score) else 0
	var speed := speed_points(race_time)
	var previous_best_score := get_best_score(level_path)
	last_score = {"speed": speed, "tricks": tricks, "score": speed + tricks,
		"best_score": previous_best_score, "is_best_score": speed + tricks > previous_best_score}
	if last_score.is_best_score:
		_save_best_score(level_path, speed + tricks)
	print("[COURSE] arrivée en ", format_time(race_time), " | record : ", is_record, " | score ", last_score)
	if NetSession.in_race:
		# [MULTI] annonce l'arrivée à tous (appel local immédiat + envoi aux
		# autres), puis on affiche la PLACE plutôt que le record.
		NetSession.report_finish(race_time, last_score.score)
		if _hud != null and is_instance_valid(_hud):
			_hud.show_multi_result(race_time, NetSession.my_rank(), NetSession.players.size(), last_score)
	elif _hud != null and is_instance_valid(_hud):
		_hud.show_result(race_time, is_record, previous_best, last_score)
	emit_signal("race_finished", race_time, is_record, previous_best)
	return is_record


# --- [AIDE 1.7] Carte d'aide en début de niveau ------------------------------------
const START_HELP_TEXT = "Avancer : {move_right}    Reculer : {move_left}\nSauter : {jump}    PUMP : {pump}  (dans les descentes)\nGrappin : {hook}    Tirer : {pull}\nFigure : {trix}    Rotation : {rotate_trigo} / {rotate_horaire}"
const START_HELP_SCORE = "\n\nSCORE = points de vitesse + points de figures\nFigures et vrilles comptent si tu atterris bien !"

func _show_start_help() -> void:
	# Pas dans le tuto (ses panneaux expliquent déjà tout), pas en multijoueur
	if not Settings.help_on_start or NetSession.in_race or level_path.ends_with("LevelBateau.tscn"):
		return
	var text := TutorialSign.resolve_text(START_HELP_TEXT + (START_HELP_SCORE if has_finish else ""))
	ReadingPause.open(get_tree(), "C'EST PARTI !" if has_finish else "GLISSE TRANQUILLE", text)


# --- 4. [MULTI] Course en réseau ----------------------------------------------
func _on_countdown_started(seconds: float) -> void:
	_countdown = seconds


func _update_countdown(delta: float) -> void:
	if _countdown < 0.0:
		return
	_countdown -= delta
	if _hud != null and is_instance_valid(_hud):
		_hud.show_countdown(_countdown)
	if _countdown <= 0.0:
		_countdown = -1.0
		# GO ! on libère le pingouin, le chrono part de zéro
		_waiting_go = false
		racing = true
		race_time = 0.0
		_sample_timer = 0.0
		if _player != null and is_instance_valid(_player):
			_player.process_mode = Node.PROCESS_MODE_INHERIT


# État envoyé : même format que les échantillons du fantôme (10 nombres :
# t, x, y, rotation, -, image, retourné, accroché, crochet x, crochet y),
# le nom de l'animation voyageant à part.
func _send_state() -> void:
	var spr = _player.animated_sprite
	var tip: Vector2 = _player.chain.tip
	var hooked: bool = _player.chain.hooked or _player.chain.flying
	NetSession.send_state(PackedFloat32Array([race_time, _player.global_position.x, _player.global_position.y,
		_player.rotation + spr.rotation, 0.0, spr.frame, 1.0 if spr.flip_h else 0.0,
		1.0 if hooked else 0.0, tip.x, tip.y]), str(spr.animation))


## Appelé par NetSession à chaque état reçu d'un autre joueur.
func on_remote_state(id: int, state: PackedFloat32Array, anim: String) -> void:
	if level_path == "" or _player == null or not is_instance_valid(_player) or state.size() < 10:
		return  # niveau pas encore prêt : on ignore (le suivant arrivera 50 ms après)
	var node = _remotes.get(id)
	if node == null or not is_instance_valid(node):
		node = preload("res://src/ui/race/RemotePenguin.gd").new()
		var p_name: String = NetSession.players[id].name if NetSession.players.has(id) else "?"
		node.setup(_player, p_name, id)
		get_tree().current_scene.add_child(node)
		_remotes[id] = node
	node.push_state(state, anim)


## Appelé par NetSession quand un joueur se déconnecte.
func remove_remote(id: int) -> void:
	var node = _remotes.get(id)
	if node != null and is_instance_valid(node):
		node.queue_free()
	_remotes.erase(id)
	if _hud != null and is_instance_valid(_hud) and NetSession.in_race:
		_hud.set_ranking(NetSession.ranking())


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


# --- [PARTAGE 1.7] Fantômes en texte (copier-coller, PC ET téléphone) ---------------
# Sur téléphone, on ne peut pas ouvrir le dossier des fantômes. On transforme
# donc un fantôme en TEXTE (compressé puis encodé en base64) : on le copie, on
# l'envoie par message (WhatsApp, SMS, Discord…) et l'ami le colle dans son
# jeu (écran Options). ~10 à 25 Ko de texte pour une course de 30 s.
const GHOST_TEXT_PREFIX = "PINPOUIN-FANTOME:1:"

## Texte à partager pour le meilleur fantôme d'un niveau ("" s'il n'y en a pas).
func export_ghost_text(path: String) -> String:
	var data = load_best_ghost(path)
	if data == null:
		return ""
	var raw := var_to_bytes(data)
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	# ":FIN" marque la fin : on peut coller le fantôme au milieu d'un message
	return GHOST_TEXT_PREFIX + str(raw.size()) + ":" + Marshalls.raw_to_base64(packed) + ":FIN"


## Importe un fantôme collé. Renvoie un message à afficher au joueur.
func import_ghost_text(text: String) -> String:
	text = text.strip_edges()
	var start := text.find(GHOST_TEXT_PREFIX)
	if start < 0:
		return "Ce texte n'est pas un fantôme Pinpouin."
	var rest := text.substr(start + GHOST_TEXT_PREFIX.length())
	var end := rest.find(":FIN")
	if end < 0:
		return "Fantôme incomplet : le texte a été coupé (il doit finir par :FIN)."
	rest = rest.substr(0, end)
	# certaines messageries ajoutent des retours à la ligne : on les enlève
	for ws in [" ", "\n", "\r", "\t"]:
		rest = rest.replace(ws, "")
	var sep := rest.find(":")
	if sep < 0:
		return "Fantôme incomplet (texte coupé ?)."
	var size := int(rest.substr(0, sep))
	var b64 := rest.substr(sep + 1)
	var b64_check := RegEx.create_from_string("^[A-Za-z0-9+/]+=*$")
	if b64_check.search(b64) == null:
		return "Fantôme abîmé (caractères en trop ?)."
	var packed := Marshalls.base64_to_raw(b64)
	if size <= 0 or size > 8_000_000 or packed.is_empty():
		return "Fantôme incomplet (texte coupé ?)."
	var raw := packed.decompress(size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != size:
		return "Fantôme abîmé (texte coupé ?)."
	# bytes_to_var refuse les objets par défaut : un texte piégé ne peut pas
	# exécuter de code, au pire il donne une donnée invalide (vérifiée ci-dessous)
	var data = bytes_to_var(raw)
	if typeof(data) != TYPE_DICTIONARY or not data.has("samples") or not data.has("level") \
			or int(data.get("version", 0)) != GHOST_FORMAT_VERSION or typeof(data.samples) != TYPE_PACKED_FLOAT32_ARRAY:
		return "Fantôme d'une autre version du jeu, ou abîmé."
	var level: String = str(data.level)
	if not level.begins_with("res://src/levels/") or not ResourceLoader.exists(level):
		return "Ce fantôme est pour un niveau inconnu."
	var file := GHOST_DIR.path_join("%s_ami_%d.ghost" % [level.get_file().get_basename(), Time.get_unix_time_from_system()])
	var f := FileAccess.open_compressed(file, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return "Impossible d'enregistrer le fantôme."
	f.store_var(data)
	f.close()
	_best_cache.erase(level)
	return "Fantôme ajouté : %s en %s.\nS'il est plus rapide que le tien, c'est lui qui courra contre toi." % [level.get_file().get_basename().replace("Level", ""), format_time(float(data.time))]


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


# --- 5. [SCORE 1.5] Score ---------------------------------------------------------
## Points de vitesse pour un temps donné (arrondis à la dizaine).
static func speed_points(time: float) -> int:
	return int(round(SPEED_POINTS / maxf(time, 1.0) / 10.0)) * 10


## Meilleur score connu pour un niveau, -1 s'il n'y en a pas.
func get_best_score(path: String) -> int:
	return int(_best_scores.get(path.get_file().get_basename(), -1))


func _save_best_score(path: String, score: int) -> void:
	var key := path.get_file().get_basename()
	_best_scores[key] = score
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("scores", key, score)
	cfg.save(CONFIG_PATH)


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
		if cfg.has_section("scores"):   # [SCORE 1.5]
			for key in cfg.get_section_keys("scores"):
				_best_scores[key] = int(cfg.get_value("scores", key, -1))
