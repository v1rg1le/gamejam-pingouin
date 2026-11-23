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
#       - [SCORE 1.13] points de vitesse = SPEED_BASE au TEMPS DE RÉFÉRENCE du
#         niveau, puis ± SPEED_PER_SECOND par seconde d'avance / de retard
#         (jamais négatif). Temps de référence = distance départ -> arrivée
#         ÷ REF_SPEED (1250 px/s, la vitesse moyenne mesurée d'un joueur qui
#         avance en pumpant, sur tous les niveaux). Règle à retenir :
#         « 1 seconde = 100 points = 1 figure ».
#         (1.5 à 1.12 : 60 000 / temps -> sur un niveau long (66 s) la vitesse
#         ne valait que 900 points et les figures écrasaient tout ; sur un
#         niveau court (19 s), c'était l'inverse.)
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
const SPEED_POINTS = 60000.0         # [SCORE 1.5] ancien barème (60 000 / temps), plus utilisé depuis la 1.13
const SPEED_BASE = 3000              # [SCORE 1.13] points de vitesse au temps de référence
const SPEED_PER_SECOND = 100         # [SCORE 1.13] points par seconde d'avance / de retard
const REF_SPEED = 1250.0             # [SCORE 1.13] px/s : sert à calculer le temps de référence
const SCORES_SECTION = "scores_v3"   # [MODES 1.25] barème à médailles (avant : "scores_v2", gardée mais ignorée)

# --- [MODES 1.25] Médailles du mode Score ---------------------------------------
# Demande de l'équipe : remplacer le « temps de référence » calculé par des
# temps de médailles mesurés avec des bots. OR = temps d'un bon joueur (bot
# « ▶ + PUMP dans les descentes + grappin au-dessus des trous », hors projet :
# medal_bot.gd), arrondi à la demi-seconde au-dessus ; ARGENT = or + 25 % ;
# BRONZE = or + 60 %.
#  - Spaghetti (terrain différent à chaque partie) : mesuré sur 10 terrains,
#    on garde le PLUS LENT (30,9 à 34,1 s) pour que l'or soit faisable partout.
#  - « Hook, you fool ! » : jusqu'à la 1.47, temps ESTIMÉ (97 s), le bot ne
#    passant pas tous les trous au grappin. [MÉDAILLES 1.48] mesuré pour de
#    vrai avec un bot qui sait s'y prendre (gap_bot.gd, hors projet) :
#    accroche le poisson presque à la verticale (pas trop tôt, sinon il fait
#    un tour complet et perd sa vitesse), lâche quand la corde fait ~25° de
#    l'autre côté en remontant, et s'accroche au PLAFOND du couloir quand il
#    n'y a pas de poisson. Meilleure course sans chute : 85,57 s avec
#    figures (89,3 à 95,6 s selon les réglages, 90,1 s sans figures).
#    Le terrain est le même à chaque partie (les trous ne dépendent pas du seed).
# Un niveau absent de la liste utilise l'ancien temps de référence
# (distance ÷ REF_SPEED) comme temps d'or.
# [MÉDAILLES 1.34] temps remesurés avec les réglages physiques PAR DÉFAUT (les
# mesures de la 1.30 avaient été faites avec d'anciens réglages F2 restés sur la
# machine de test : trop rapides). Or = meilleur temps du bot « bon joueur »,
# avec ou sans figures, arrondi à la demi-seconde au-dessus.
const MEDAL_GOLD := {
	# [TUTO 1.41] le chrono du tuto ne couvre plus que la COURSE FINALE (après
	# les ateliers) : temps remesuré au bot sur ce seul tronçon.
	# [PHYSIQUE RÉELLE 1.49] tout remesuré avec la résistance de l'air (bot
	# « bon joueur », dossier joueur neuf). Valeurs 1.48 en fin de ligne.
	"LevelBateau": 13.5,          # [1.53] bot 12,38 à 13,27 s selon les figures tirées (1.49 : 13, trop juste ; 1.48 : 13,5)
	"LevelRandomFlat": 62.0,      # bot 61,55 s avec figures, 64,15 sans (1.48 : 64)
	"LevelRandomCorridor": 61.5,  # [1.53] bot 61,13 s avec figures (glisse lissée) ; 1.49 : 62 (bot 62,00) ; 1.48 : 66,5
	"LevelRandomNiceSlope": 37.0, # bot 36,88 s avec figures, 41,32 sans : grandes descentes plus rapides (1.48 : 49,5)
	"LevelRandomSpaghetti": 38.5, # bot 32,3 à 38,4 s selon le terrain (40,5 sur un terrain difficile) (1.48 : 33,5)
	"LevelRandomGap": 86.5,       # [1.53] gap_bot 86,27 s avec figures, sans chute ; 1.49 : 89 ; 1.48 : 86
	"LevelEgg": 108.0,            # [ŒUF 1.60] zigzag + chemin de gauche + crevasse : egg_bot 106,33 s (0 chute, sans figures)
	"LevelGruyere": 170.0,        # [GRUYÈRE 1.63] partie 1 + 3 cavernes + half-pipe : gruyere_bot 167 à 186 s selon la route (0 à 1 chute, sans figures)
}
const SILVER_FACTOR := 1.25       # argent = or × 1,25
const BRONZE_FACTOR := 1.6        # bronze = or × 1,6
const MEDAL_POINTS := [0, 1000, 2000, 3000]   # aucune / bronze / argent / or
const MEDAL_NAMES := ["", "BRONZE", "ARGENT", "OR"]
const MEDALS_SECTION = "medals"   # meilleure médaille par niveau (1..3)
var gold_time: float = 0.0        # temps de l'or du niveau en cours (s)
var _best_medals := {}            # niveau -> meilleure médaille (1..3)

# --- [MODES 1.25] Mode Chill ----------------------------------------------------
# Vrai une fois l'arrivée passée en mode Chill quand le niveau a un half-pipe :
# le niveau ne se ferme pas, on y reste faire des figures (TrickScore compte
# toujours pour les messages à l'écran) et une chute fait réapparaître sur le
# bord du half-pipe.
var free_ride := false

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
var endless_new_terrain := false    # [FANTÔME SANS FIN 1.36] prochain Sans fin : terrain neuf
var endless_replay_seed := -1       # [FANTÔME SANS FIN 1.36] « Rejouer » : même terrain que la partie finie
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
var ref_time: float = 0.0           # [SCORE 1.13] temps de référence du niveau en cours (s)

# --- [TUTO 1.41] Tuto par ateliers -------------------------------------------
# Le tuto (LevelBateau) commence par des ATELIERS (TutorialCoach.gd) puis finit
# par une petite COURSE chronométrée avec médaille. Pendant les ateliers :
#   - racing reste vrai (le juge des figures, TrickScore, ne compte que si l'on
#     « court » : il faut ses points pour valider les ateliers de figures) ;
#   - mais le chrono est caché, rien n'est enregistré pour le fantôme, et le
#     fantôme n'est créé qu'au départ de la course finale.
# start_tutorial_final() remet chrono, points et enregistrement à zéro quand
# Pinpouin franchit la ligne de départ de la course finale.
const TUTO_LEVEL := "LevelBateau"
const TUTO_GHOST_VERSION := 2       # fantômes du tuto 1.41 (les anciens couvraient tout le niveau)
var tutorial_intro := false         # vrai pendant les ateliers du tuto

# --- [CRÉATEUR 1.45] Niveau dessiné dans l'éditeur ---------------------------------
# LevelDrawn.tscn change à chaque dessin. 1.45 : rien n'y était enregistré.
# [MES NIVEAUX 1.46] chaque niveau dessiné a maintenant un chemin VIRTUEL
# (DrawnLevel.race_path() : res://src/levels/LevelDrawn_<id>_<empreinte>.tscn),
# remplacé dans _prepare_level : record, fantôme, score et médaille sont
# rangés sous ce chemin comme pour un vrai niveau ; l'empreinte change quand
# on modifie le dessin, donc un ancien record ne compte plus.
# Seul cas sans rien d'enregistré : le chemin réel LevelDrawn.tscn (niveau
# ouvert sans passer par l'éditeur, ex. depuis l'éditeur Godot).
# Pas de carte d'aide au départ dans un niveau dessiné (on enchaîne vite
# dessin -> test -> dessin).
const DRAWN_LEVEL := "LevelDrawn"


## Vrai dans tous les niveaux dessinés
func _is_any_drawn_level() -> bool:
	return level_path.get_file().get_basename().begins_with(DRAWN_LEVEL)


## Vrai seulement si le niveau dessiné n'a pas de chemin virtuel : rien n'est enregistré
func _is_drawn_level() -> bool:
	return level_path.get_file().get_basename() == DRAWN_LEVEL


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
			if Settings.is_chill():
				# [MODES 1.25] pas de classement en Chill : juste qui est arrivé
				if free_ride or not racing:
					_hud.show_chill_finish(free_ride)
				return
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
	# [MES NIVEAUX 1.46] niveau dessiné : chemin virtuel propre au dessin
	if path.ends_with(DRAWN_LEVEL + ".tscn") and not NetSession.in_race:
		DrawnLevel.load_once()
		path = DrawnLevel.race_path()
	level_path = path
	_ghost_data = load_best_ghost(path) if ghost_enabled else null
	# [FANTÔME SANS FIN 1.36] bouton « Nouveau terrain » : pas de fantôme, terrain neuf
	if path.ends_with("LevelEndless.tscn") and endless_new_terrain:
		_ghost_data = null
	endless_new_terrain = false
	if Settings.is_chill():
		_ghost_data = null   # [MODES 1.25] pas de fantôme en mode Chill
	if _is_drawn_level():
		_ghost_data = null   # [CRÉATEUR 1.45] pas de fantôme sur un niveau dessiné sans chemin virtuel
	# [MULTI] en course réseau : seed imposé par l'hôte, pas de fantôme
	if NetSession.in_race:
		_ghost_data = null
		race_seed = NetSession.race_seed
	# Même terrain que le fantôme, sinon un nouveau seed (terrain aléatoire comme avant)
	elif _ghost_data != null:
		race_seed = int(_ghost_data.seed)
	else:
		race_seed = randi()
	# [FANTÔME SANS FIN 1.36] « Rejouer » relance le terrain de la partie qu'on
	# vient de finir ; le fantôme ne vient que s'il a été fait sur ce terrain
	if endless_replay_seed >= 0 and path.ends_with("LevelEndless.tscn") and not NetSession.in_race:
		race_seed = endless_replay_seed
		if _ghost_data != null and int(_ghost_data.seed) != race_seed:
			_ghost_data = null
	endless_replay_seed = -1
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
	bonus_active = false      # [BONUS 1.20] pas de bonus en cours dans une nouvelle scène
	free_ride = false         # [MODES 1.25]
	tutorial_intro = false    # [TUTO 1.41]
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
	# [BONUS 1.20] compte à rebours des figures bonus (chrono déjà arrêté)
	if bonus_active:
		bonus_left -= delta
		if _hud != null and is_instance_valid(_hud):
			_hud.set_bonus_left(bonus_left)
		if bonus_left <= 0.0:
			Sfx.play("bonus_fin")   # [BRUITAGES 1.34] coup de sifflet
			_complete_race()
		return
	if not racing:
		return
	race_time += delta
	if Settings.is_chill():
		return   # [MODES 1.25] pas d'enregistrement de fantôme en Chill
	if tutorial_intro:
		return   # [TUTO 1.41] ateliers : rien à enregistrer avant la course finale
	_sample_timer -= delta
	if _sample_timer <= 0.0:
		_sample_timer += SAMPLE_INTERVAL
		_record_sample()


func _start_race() -> void:
	has_finish = not get_tree().get_nodes_in_group("finish_gate").is_empty()
	_show_start_help()   # [AIDE 1.7] carte d'aide (jeu en pause) si l'option est active
	# [MODE ENFANT 1.23] aide de jeu pour les petits (poussée auto, coup de
	# pouce, cercles sur ▶ / PUMP). Toujours créée en solo, y compris dans les
	# niveaux Chill : elle ne fait rien tant que l'option est coupée, et on
	# peut donc l'activer/désactiver depuis les Options sans relancer.
	if not NetSession.in_race:
		var kid = preload("res://src/ui/race/KidAssist.gd").new()
		kid.setup(_player)
		get_tree().current_scene.add_child(kid)
	# [VITESSE 1.48] compteur de vitesse du pingouin local (option « Afficher la
	# vitesse de Pinpouin »). Créé dans TOUS les niveaux, solo comme multi ; il
	# reste caché tant que l'option est coupée (F3 l'allume en pleine partie).
	var meter = preload("res://src/ui/race/SpeedMeter.gd").new()
	meter.setup(_player)
	get_tree().current_scene.add_child(meter)
	if not has_finish and not NetSession.in_race:
		# niveau "Chill" (704, 917, half-pipe) : pas de chrono.
		# [CHILL 1.28] mais les figures s'affichent (et le maître fait son clin
		# d'œil) : HUD sans chrono ni score + juge des figures, en « ride libre ».
		free_ride = true
		_hud = preload("res://src/ui/race/RaceHud.gd").new()
		_hud.chill_mode = true
		get_tree().current_scene.add_child(_hud)
		_setup_tricks(get_tree().current_scene)
		_start_endless_ghost()   # [FANTÔME SANS FIN 1.36] (Sans fin en mode Score seulement)
		# [DÉFI FIGURES 1.43] 704, 917, Half-pipe en mode Score : chrono de
		# 4 / 3 min pour faire le meilleur score de figures (TrickAttack.gd)
		if not Settings.is_chill() and TrickAttack.has_challenge(level_path):
			var attack = preload("res://src/ui/race/TrickAttack.gd").new()
			attack.setup(_player, level_path)
			get_tree().current_scene.add_child(attack)
		return
	racing = true
	race_time = 0.0
	_sample_timer = 0.0
	# [SCORE 1.13] temps de référence = distance départ -> arrivée / REF_SPEED
	var gate = get_tree().get_first_node_in_group("finish_gate")
	if gate != null and _player != null:
		ref_time = maxf(10.0, absf(gate.global_position.x - _player.global_position.x) / REF_SPEED)
	# [MODES 1.25] temps de l'or (mesuré par les bots), sinon le temps de référence
	gold_time = float(MEDAL_GOLD.get(level_path.get_file().get_basename(), ref_time))
	# [PARTAGE 1.47] niveau de la communauté : temps de l'or mesuré au bot (dans son fichier)
	if _is_any_drawn_level() and DrawnLevel.current_gold > 0.0:
		gold_time = DrawnLevel.current_gold
	_rec = {"version": GHOST_FORMAT_VERSION, "level": level_path, "seed": race_seed,
		"anims": [], "samples": PackedFloat32Array(), "time": 0.0}
	var scene := get_tree().current_scene
	_hud = preload("res://src/ui/race/RaceHud.gd").new()
	_hud.chill_mode = Settings.is_chill()   # [MODES 1.25] pas de chrono ni de score à l'écran
	scene.add_child(_hud)
	_hud.set_best(get_best_time(level_path))
	_setup_tricks(scene)
	# [TUTO 1.41] ateliers du tuto : chrono caché, pas de fantôme pour l'instant
	# (pas en multijoueur : là, le tuto est une simple course du départ à l'arrivée)
	tutorial_intro = level_path.get_file().get_basename() == TUTO_LEVEL and not NetSession.in_race
	if tutorial_intro:
		_hud.set_tutorial_intro(true)
	if _ghost_data != null and not tutorial_intro:
		_ghost_node = preload("res://src/ui/race/GhostPenguin.gd").new()
		_ghost_node.setup(_ghost_data, _player)
		scene.add_child(_ghost_node)
	# [MULTI] on fige le pingouin et on prévient l'hôte qu'on est prêt.
	# Le chrono ne part qu'au "GO" (cf. _on_countdown_started).
	if NetSession.in_race:
		racing = false
		_waiting_go = true
		_freeze_player_for_start()   # [ATTENTE 1.14] posé au sol, grappin rangé
		_player.process_mode = Node.PROCESS_MODE_DISABLED
		_hud.set_best(-2.0)   # -2 = "en attente des autres joueurs"
		_hud.show_waiting(true)   # [ATTENTE 1.14] grand panneau « En attente… »
		_hud.set_ranking(NetSession.ranking())
		NetSession.notify_loaded()


## [SCORE 1.5] juge des figures : il observe le pingouin et prévient le HUD.
## ([CHILL 1.28] sorti de _start_race pour servir aussi aux niveaux Chill.)
func _setup_tricks(scene: Node) -> void:
	trick_score = preload("res://src/ui/race/TrickScore.gd").new()
	trick_score.setup(_player)
	scene.add_child(trick_score)
	trick_score.points_banked.connect(func(_pts, total, label):
		if is_instance_valid(_hud):
			_hud.set_trick_points(total)
			_hud.show_trick_popup(label, Color(1, 0.94, 0.4))
			# [MAÎTRE 1.19] le maître ninja passe la tête et fait un clin d'œil
			if Settings.master_wink:
				_hud.show_master_wink())
	trick_score.points_lost.connect(func(reason):
		if is_instance_valid(_hud):
			_hud.show_trick_popup(reason, Color(1, 0.5, 0.45)))
	trick_score.pending_changed.connect(func(text):
		if is_instance_valid(_hud):
			_hud.set_pending(text))


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
	Sfx.play("arrivee")   # [BRUITAGES 1.34] passage de la ligne d'arrivée
	if Settings.is_chill():
		return _finish_chill()   # [MODES 1.25]
	racing = false
	_record_sample()  # dernière position exacte
	var previous_best := get_best_time(level_path)
	var is_record := previous_best < 0.0 or race_time < previous_best
	if _is_drawn_level():   # [CRÉATEUR 1.45] rien d'enregistré (voir DRAWN_LEVEL)
		previous_best = -1.0
		is_record = false
	if is_record:
		_rec.time = race_time
		_save_ghost(_rec)
	_finish_record = {"is_record": is_record, "previous_best": previous_best}
	if is_record:   # [BRUITAGES 1.34] petites notes montantes, juste après l'arrivée
		get_tree().create_timer(0.7).timeout.connect(func(): Sfx.play("record"))
	# [BONUS 1.20] le chrono est arrêté (temps, record et fantôme ci-dessus ne
	# changent plus), mais s'il y a un half-pipe après l'arrivée, on laisse
	# BONUS_TIME secondes pour y faire des figures qui comptent encore.
	if _has_bonus_half_pipe():
		bonus_active = true
		bonus_left = BONUS_TIME
		print("[COURSE] arrivée en ", format_time(race_time), " | figures à l'arrivée ", trick_score.total if trick_score != null else 0, " | bonus half-pipe ", BONUS_TIME, " s")
		if _hud != null and is_instance_valid(_hud):
			_hud.show_bonus(race_time, is_record, previous_best, bonus_left)
		return is_record
	_complete_race()
	return is_record


# --- [BONUS 1.20] Figures bonus dans le half-pipe d'arrivée ---------------------
# Demande de l'équipe : « à l'arrivée, avoir encore 30 s pour faire des tricks
# dans le half-pipe à la fin du niveau, et que ces points comptent encore pour
# le score final ».
# Déroulé :
#  1. la ligne d'arrivée (l'arche) arrête le chrono : temps, record et fantôme
#     sont fixés tout de suite (finish_race ci-dessus) ;
#  2. pendant BONUS_TIME secondes, TrickScore continue de compter (il regarde
#     `bonus_active`) ; un bandeau en haut de l'écran affiche le compte à
#     rebours ;
#  3. à la fin, une figure encore en l'air est validée comme sur la ligne
#     d'arrivée, puis on calcule le score (vitesse + TOUTES les figures), on
#     l'enregistre et on l'affiche (_complete_race) ;
#  4. FinishGate attend le signal race_completed pour revenir au menu.
# Seulement sur les niveaux qui ont un half-pipe (niveaux générés) : le tuto
# et Spaghetti se terminent comme avant. En multijoueur aussi : l'arrivée et
# le score sont annoncés aux autres à la fin du bonus.
const BONUS_TIME = 30.0           # s de figures bonus après l'arrivée
signal race_completed             # émis quand le score final est connu
var bonus_active := false         # vrai pendant le bonus (chrono arrêté, figures comptées)
var bonus_left := 0.0             # s restantes de bonus
var _finish_record := {}          # {is_record, previous_best} mémorisés à l'arrivée


## Vrai si le niveau a un half-pipe (zone de figures) APRÈS la ligne d'arrivée.
func _has_bonus_half_pipe() -> bool:
	var gate = get_tree().get_first_node_in_group("finish_gate")
	if gate == null:
		return false
	for hp in get_tree().get_nodes_in_group("half_pipe"):
		if hp.global_position.x > gate.global_position.x - 200.0:
			return true
	return false


## [BONUS 1.20] Point de réapparition pendant le bonus : sur le deck de gauche
## du half-pipe d'arrivée (un quart de sa longueur, à côté du podium).
## [MODES 1.25] devenu un simple relais vers half_pipe_respawn_point().
func bonus_respawn_point():
	return half_pipe_respawn_point()


func _old_bonus_respawn_point():   # (ancienne version, gardée pour mémoire)
	var gate = get_tree().get_first_node_in_group("finish_gate")
	for hp in get_tree().get_nodes_in_group("half_pipe"):
		if gate == null or hp.global_position.x > gate.global_position.x - 200.0:
			var poly: PackedVector2Array = hp.get_node("CollisionPolygon2D").polygon
			if poly.size() > 1:
				# poly[1] = coin haut-gauche du deck de gauche
				return hp.to_global(poly[1]) + Vector2(hp.deck_length * 0.25, -20.0)
	return null


## [MODES 1.25] Arrivée en mode Chill : rien n'est enregistré (ni temps, ni
## record, ni fantôme, ni score). S'il y a un half-pipe, on y reste aussi
## longtemps qu'on veut (free_ride) ; sinon (tuto, Spaghetti) FinishGate
## ramène au menu comme avant, après un « Bravo ! ».
func _finish_chill() -> bool:
	racing = false
	free_ride = _has_half_pipe()
	print("[COURSE] arrivée (Chill) | half-pipe libre : ", free_ride)
	if NetSession.in_race:
		NetSession.report_finish(race_time, 0)   # pour savoir qui est arrivé (pas de classement)
	if _hud != null and is_instance_valid(_hud):
		_hud.show_chill_finish(free_ride)
	emit_signal("race_finished", race_time, false, -1.0)
	emit_signal("race_completed")
	return false


## [MODES 1.25] Vrai si le niveau a un half-pipe (n'importe où).
func _has_half_pipe() -> bool:
	return not get_tree().get_nodes_in_group("half_pipe").is_empty()


## [MODES 1.25] Point de réapparition sur le bord gauche (deck) du DERNIER
## half-pipe du niveau : utilisé pendant le bonus (Score) et après l'arrivée
## (Chill). Remplace l'ancien mur invisible au bout du half-pipe.
func half_pipe_respawn_point():
	var last = null
	for hp in get_tree().get_nodes_in_group("half_pipe"):
		if last == null or hp.global_position.x > last.global_position.x:
			last = hp
	if last == null:
		return null
	var poly: PackedVector2Array = last.get_node("CollisionPolygon2D").polygon
	if poly.size() > 1:
		# poly[1] = coin haut-gauche du deck de gauche
		return last.to_global(poly[1]) + Vector2(last.deck_length * 0.25, -20.0)
	return null


## Fin du bonus (ou arrivée sans bonus) : score final, sauvegarde, affichage.
func _complete_race() -> void:
	bonus_active = false
	if trick_score != null and is_instance_valid(trick_score):
		trick_score.bank()   # une figure en l'air à la fin du bonus compte
	var is_record: bool = _finish_record.get("is_record", false)
	var previous_best: float = _finish_record.get("previous_best", -1.0)
	# [SCORE 1.5] calcul du score
	var tricks: int = trick_score.total if trick_score != null and is_instance_valid(trick_score) else 0
	# [MODES 1.25] points de vitesse selon les médailles (voir speed_points)
	var speed := speed_points(race_time, gold_time)
	var medal := medal_for(race_time, gold_time)
	var previous_best_score := get_best_score(level_path)
	var previous_medal := get_best_medal(level_path)
	last_score = {"speed": speed, "tricks": tricks, "score": speed + tricks, "gold_time": gold_time,
		"medal": medal, "new_medal": medal > previous_medal,
		"best_score": previous_best_score, "is_best_score": speed + tricks > previous_best_score}
	if _is_drawn_level():   # [CRÉATEUR 1.45] score affiché mais pas enregistré
		last_score.new_medal = false
		last_score.is_best_score = false
	if last_score.is_best_score:
		_save_best_score(level_path, speed + tricks)
	if medal > previous_medal and not _is_drawn_level():
		_save_best_medal(level_path, medal)
	print("[COURSE] arrivée en ", format_time(race_time), " | record : ", is_record, " | score ", last_score)
	if NetSession.in_race:
		# [MULTI] annonce l'arrivée à tous (appel local immédiat + envoi aux
		# autres), puis on affiche la PLACE plutôt que le record.
		NetSession.report_finish(race_time, last_score.score)
		if _hud != null and is_instance_valid(_hud):
			_hud.show_bonus_end()
			_hud.show_multi_result(race_time, NetSession.my_rank(), NetSession.players.size(), last_score)
	elif _hud != null and is_instance_valid(_hud):
		_hud.show_bonus_end()
		_hud.show_result(race_time, is_record, previous_best, last_score)
	emit_signal("race_finished", race_time, is_record, previous_best)
	emit_signal("race_completed")


# --- [TUTO 1.41] Départ de la course finale du tuto ---------------------------------
## Appelé par TutorialCoach quand Pinpouin franchit la ligne de départ de la
## course finale : départ « lancé » (il glisse déjà), le chrono part de 0.
func start_tutorial_final() -> void:
	if not tutorial_intro:
		return
	tutorial_intro = false
	race_time = 0.0
	_sample_timer = 0.0
	# enregistrement du fantôme à partir d'ici seulement (marqué « tuto 2 »)
	_rec = {"version": GHOST_FORMAT_VERSION, "level": level_path, "seed": race_seed,
		"anims": [], "samples": PackedFloat32Array(), "time": 0.0, "tuto": TUTO_GHOST_VERSION}
	# temps de référence : distance ligne de départ -> arrivée
	var gate = get_tree().get_first_node_in_group("finish_gate")
	if gate != null and _player != null:
		ref_time = maxf(10.0, absf(gate.global_position.x - _player.global_position.x) / REF_SPEED)
	gold_time = float(MEDAL_GOLD[TUTO_LEVEL])
	# les points de figures des ateliers ne comptent pas dans le score
	if trick_score != null and is_instance_valid(trick_score):
		trick_score.total = 0
		trick_score._pending.clear()
	if _hud != null and is_instance_valid(_hud):
		_hud.set_tutorial_intro(false)
		_hud.set_trick_points(0)
		_hud.set_best(get_best_time(level_path))
	# le fantôme part en même temps que le chrono
	if _ghost_data != null and not Settings.is_chill() and _player != null:
		_ghost_node = preload("res://src/ui/race/GhostPenguin.gd").new()
		_ghost_node.setup(_ghost_data, _player)
		get_tree().current_scene.add_child(_ghost_node)
	print("[TUTO] départ de la course finale")


# --- [AIDE 1.7] Carte d'aide en début de niveau ------------------------------------
const START_HELP_TEXT = "Avancer : {move_right}    Reculer : {move_left}\nSauter : {jump}    PUMP : {pump}  (dans les descentes)\nGrappin : {hook}    Tirer : {pull}\nFigure : {trix}    Rotation : {rotate_trigo} / {rotate_horaire}"
# [SCORE 1.13] aide de départ : rappel de la règle « 1 s = 100 pts = 1 figure »
const START_HELP_SCORE = "\n\nSCORE = vitesse + figures  (1 seconde gagnée = 100 pts = 1 figure)\nFigures et vrilles comptent si tu atterris bien !"

# [MODE ENFANT 1.23] aide de départ très courte (la poussée automatique fait avancer)
const KID_HELP_TEXT = "Pinpouin avance tout seul !\nSauter : {jump}    Grappin : {hook}\nPUMP : {pump} pour aller plus vite"

func _show_start_help() -> void:
	# Pas dans le tuto (ses panneaux expliquent déjà tout), pas en multijoueur
	# [CRÉATEUR 1.45] ni dans un niveau dessiné (on y revient à chaque essai)
	if not Settings.help_on_start or NetSession.in_race or level_path.ends_with("LevelBateau.tscn") or _is_any_drawn_level():
		return
	var text := TutorialSign.resolve_text(START_HELP_TEXT + (START_HELP_SCORE if has_finish and not Settings.is_chill() else ""))
	# [MODES 1.25] en Chill : pas de score, on reste dans le half-pipe d'arrivée
	if Settings.is_chill() and has_finish and _has_half_pipe():
		text += "\n\nMode Chill : pas de chrono. Après l'arrivée,\nreste dans le half-pipe faire des figures autant que tu veux !"
	# [SANS FIN 1.32] le niveau Sans fin explique ses trous
	if level_path.contains("LevelEndless"):
		if not Settings.is_chill() and not level_path.ends_with("LevelEndlessChill.tscn"):
			text += "\n\n3 VIES (têtes de Pinpouin) · médailles à 1 / 3 / 5 km"
		text += "\n\nSANS FIN : va le plus loin possible !\nPetits trous : saute.  Grands trous : grappin sur les blocs de glace,\npuis lâche quand Pinpouin remonte pour être projeté."
	# [MODE ENFANT 1.23] carte courte : un enfant ne lit pas un long texte
	if Settings.kid_mode:
		text = TutorialSign.resolve_text(KID_HELP_TEXT)
	# [BONUS 1.20] on prévient qu'il y a des figures bonus après l'arrivée
	if has_finish and _has_bonus_half_pipe() and not Settings.is_chill():
		text += "\nAprès l'arrivée : %d s de figures BONUS dans le half-pipe !" % int(BONUS_TIME)
	# [DÉFI FIGURES 1.43] 704, 917, Half-pipe en mode Score
	var trick_attack: bool = not Settings.is_chill() and TrickAttack.has_challenge(level_path)
	if trick_attack:
		var secs: int = int(TrickAttack.TIME_LIMITS[level_path.get_file().get_basename()])
		text += "\n\nDÉFI FIGURES : %d minutes pour faire le plus de points !\nFigures, vrilles, nose et combos. Évite les chutes : le saut est perdu." % (secs / 60)
	# [FANTÔME SANS FIN 1.36] le Sans fin en mode Score n'est pas une « glisse tranquille »
	var endless_score: bool = level_path.ends_with("LevelEndless.tscn") and not Settings.is_chill()
	if endless_score and endless_ghost_meters() > 0:
		text += "\nTon FANTÔME glisse avec toi : il est allé jusqu'à %d m, même terrain !" % endless_ghost_meters()
	ReadingPause.open(get_tree(), "C'EST PARTI !" if has_finish or endless_score or trick_attack else "GLISSE TRANQUILLE", text)


# --- 4. [MULTI] Course en réseau ----------------------------------------------
func _on_countdown_started(seconds: float) -> void:
	_countdown = seconds
	# [ATTENTE 1.14] tout le monde est prêt : on retire le panneau d'attente
	if _hud != null and is_instance_valid(_hud):
		_hud.show_waiting(false)


# [ATTENTE 1.14] Retour de test : pendant l'attente des autres joueurs, on
# voyait Pinpouin figé EN L'AIR au point de départ, avec la corde du grappin
# plantée dans le sol. Raisons :
#  - le pingouin est figé dès sa 1re image (process_mode DISABLED), avant même
#    d'être tombé sur la piste ;
#  - le grappin (Chain.gd) ne se cache que dans son propre _process(), qui
#    n'a jamais tourné : il restait visible, tendu vers le bas.
# Correction : avant de le figer, on POSE le pingouin sur la piste juste en
# dessous (un rayon vers le bas), incliné comme la pente, vitesse nulle, et
# on cache le grappin. Tous les joueurs ayant le même terrain (même seed),
# tout le monde part exactement du même endroit.
func _freeze_player_for_start() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if "chain" in _player and _player.chain != null:
		_player.chain.visible = false
	var space: PhysicsDirectSpaceState2D = _player.get_world_2d().direct_space_state
	var from: Vector2 = _player.global_position
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, 4000), _player.collision_mask, [_player.get_rid()])
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty() or hit.normal.y > -0.5:
		return   # pas de sol raisonnable dessous : on laisse tel quel
	# le bas de la capsule (20 px de haut, centrée sur l'origine) touche le sol
	_player.global_position = hit.position + hit.normal * 11.0
	_player.rotation = hit.normal.angle() + PI / 2.0
	_player.velocity = Vector2.ZERO
	if "_velocity" in _player:
		_player._velocity = Vector2.ZERO


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
		# [TUTO 1.41] tuto : seuls les fantômes de la course finale (nouvelle version)
		if data != null and path.get_file().get_basename() == TUTO_LEVEL and int(data.get("tuto", 0)) != TUTO_GHOST_VERSION:
			continue
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
	if level.ends_with("LevelEndless.tscn"):   # [FANTÔME SANS FIN 1.36] distance, pas un temps
		return "Défi ajouté : Sans fin, %d m.\nS'il est allé plus loin que toi, tu glisseras contre lui (mode Score), sur le même terrain." % -int(float(data.time))
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
## [SCORE 1.13] SPEED_BASE au temps de référence, ± SPEED_PER_SECOND par
## seconde d'avance ou de retard, arrondi à la dizaine, jamais négatif.
## [MODES 1.25] Points de vitesse avec les médailles (reference = temps de l'or) :
##   temps <= or      : 3000 + 100 par seconde gagnée sous l'or
##   or -> argent     : de 3000 à 2000, en continu (chaque seconde compte)
##   argent -> bronze : de 2000 à 1000, en continu
##   plus lent que le bronze : 0 (pas de médaille)
## (1.13 à 1.24 : 3000 au temps de référence ± 100 par seconde.)
static func speed_points(time: float, reference: float) -> int:
	var gold := reference
	var silver := gold * SILVER_FACTOR
	var bronze := gold * BRONZE_FACTOR
	var pts: float
	if time <= gold:
		pts = MEDAL_POINTS[3] + (gold - time) * SPEED_PER_SECOND
	elif time <= silver:
		pts = lerpf(MEDAL_POINTS[3], MEDAL_POINTS[2], (time - gold) / (silver - gold))
	elif time <= bronze:
		pts = lerpf(MEDAL_POINTS[2], MEDAL_POINTS[1], (time - silver) / (bronze - silver))
	else:
		pts = 0.0
	return maxi(0, int(round(pts / 10.0)) * 10)


## [MODES 1.25] Médaille obtenue : 3 = or, 2 = argent, 1 = bronze, 0 = aucune.
static func medal_for(time: float, gold: float) -> int:
	if time <= gold:
		return 3
	if time <= gold * SILVER_FACTOR:
		return 2
	if time <= gold * BRONZE_FACTOR:
		return 1
	return 0


## [MODES 1.25] Temps à battre pour chaque médaille du niveau en cours.
func medal_times() -> Array:
	return [gold_time * BRONZE_FACTOR, gold_time * SILVER_FACTOR, gold_time]


## [MODES 1.25] Meilleure médaille obtenue sur un niveau (0 = aucune).
func get_best_medal(path: String) -> int:
	return int(_best_medals.get(path.get_file().get_basename(), 0))


func _save_best_medal(path: String, medal: int) -> void:
	var key := path.get_file().get_basename()
	_best_medals[key] = medal
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(MEDALS_SECTION, key, medal)
	cfg.save(CONFIG_PATH)


## Meilleur score connu pour un niveau, -1 s'il n'y en a pas.
func get_best_score(path: String) -> int:
	return int(_best_scores.get(path.get_file().get_basename(), -1))


func _save_best_score(path: String, score: int) -> void:
	var key := path.get_file().get_basename()
	_best_scores[key] = score
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(SCORES_SECTION, key, score)
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
		# [SCORE 1.13] nouvelle section : les meilleurs scores de l'ancien
		# barème ne sont plus comparables (ils restent dans "scores", ignorés)
		if cfg.has_section(SCORES_SECTION):
			for key in cfg.get_section_keys(SCORES_SECTION):
				_best_scores[key] = int(cfg.get_value(SCORES_SECTION, key, -1))
		# [MODES 1.25] meilleures médailles
		# [TUTO 1.41] le tuto a changé (le chrono ne couvre plus que la course
		# finale) : médaille et score de l'ancien tuto effacés UNE fois
		if not cfg.get_value("migrations", "tuto_141", false):
			for section in [MEDALS_SECTION, SCORES_SECTION]:
				if cfg.has_section_key(section, TUTO_LEVEL):
					cfg.erase_section_key(section, TUTO_LEVEL)
			cfg.set_value("migrations", "tuto_141", true)
			cfg.save(CONFIG_PATH)
		if cfg.has_section(MEDALS_SECTION):
			for key in cfg.get_section_keys(MEDALS_SECTION):
				_best_medals[key] = int(cfg.get_value(MEDALS_SECTION, key, 0))



# =============================================================================
#  [FANTÔME SANS FIN 1.36] Fantôme du niveau Sans fin (mode Score)
# =============================================================================
#  Le Sans fin n'a pas d'arrivée : on « court » quand même (racing = true,
#  sans chrono à l'écran) pour enregistrer la partie avec le système des
#  fantômes des courses (mêmes échantillons, même GhostPenguin).
#  - Le fantôme garde la DISTANCE, pas un temps : on range time = -mètres pour
#    que « le plus petit time » (load_best_ghost) soit le fantôme allé le plus loin.
#  - Il garde aussi la graine du terrain : la partie suivante a le même terrain
#    que le fantôme (sauf bouton « Nouveau terrain » de l'écran de fin).
#  - Défi entre amis : l'échange de fantômes des Options (copier-coller) marche
#    tel quel ; le fantôme d'un ami allé plus loin devient la cible.
func _start_endless_ghost() -> void:
	if not level_path.ends_with("LevelEndless.tscn") or Settings.is_chill() or NetSession.in_race:
		return
	racing = true
	race_time = 0.0
	_sample_timer = 0.0
	_rec = {"version": GHOST_FORMAT_VERSION, "level": level_path, "seed": race_seed,
		"anims": [], "samples": PackedFloat32Array(), "time": 0.0}
	if _ghost_data != null:
		_ghost_node = preload("res://src/ui/race/GhostPenguin.gd").new()
		_ghost_node.setup(_ghost_data, _player)
		get_tree().current_scene.add_child(_ghost_node)
		_ghost_node._label.text = "fantôme " + str(-int(float(_ghost_data.time))) + " m"
	print("[SANS FIN] fantôme : ", _ghost_data != null, " | seed ", race_seed)


## Mètres du fantôme chargé pour cette partie (0 s'il n'y en a pas).
func endless_ghost_meters() -> int:
	return -int(float(_ghost_data.time)) if _ghost_data != null else 0


## Fin de partie du Sans fin (plus de vies) : on garde la partie comme fantôme
## si elle est allée plus loin que tous les fantômes de ce niveau.
func save_endless_ghost(meters: int) -> bool:
	if not racing or _rec.is_empty():
		return false
	racing = false
	_record_sample()
	var best = load_best_ghost(level_path)
	if best != null and -float(best.time) >= meters:
		return false
	_rec.time = -float(meters)
	_rec["meters"] = meters
	_save_ghost(_rec)
	return true
