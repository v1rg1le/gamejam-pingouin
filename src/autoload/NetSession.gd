extends Node
# =============================================================================
#  NetSession.gd — [MULTI] autoload : partie multijoueur en réseau local
# -----------------------------------------------------------------------------
#  Étape 6 de la feuille de route (multijoueur temps réel, d'abord même Wi-Fi).
#
#  Principe (choisi pour un jeu de course SANS contact entre joueurs) :
#   - chaque appareil simule SON pingouin comme en solo (aucune physique en
#     réseau, donc aucune latence sur ses propres commandes) ;
#   - il envoie 20 fois par seconde son état (position, rotation, animation,
#     grappin) aux autres, qui l'affichent comme un "pingouin distant" ;
#   - tout le monde court sur le MÊME terrain grâce au seed de course choisi
#     par l'hôte (cf. RaceManager).
#
#  Rôles :
#   - HÔTE : crée la partie (serveur ENet, port GAME_PORT), s'annonce sur le
#     Wi-Fi (diffusion UDP, port DISCOVERY_PORT), choisit le niveau, lance la
#     course, renvoie tout le monde au salon à la fin.
#   - INVITÉ : trouve les parties annoncées sur le Wi-Fi (ou tape l'IP de
#     l'hôte) et s'y connecte.
#
#  Déroulé d'une course :
#   hôte start_race() -> tous chargent le niveau avec le même seed
#   -> chacun signale "chargé" -> l'hôte lance le compte à rebours (3 s)
#   -> course -> chaque arrivée est annoncée à tous (classement en direct)
#   -> quand tout le monde est arrivé (ou 45 s après le 1er), retour au salon.
#
#  [INTERNET 1.6] Jouer par Internet SANS serveur (choix de l'équipe, 14/11) :
#   - l'hôte clique "Ouvrir sur Internet" : le jeu demande à sa box d'ouvrir
#     le port GAME_PORT (protocole UPnP, géré par la classe UPNP de Godot),
#     et récupère l'adresse publique de la box ;
#   - cette adresse est transformée en CODE DE PARTIE de 8 caractères
#     (ex. "K7QM-2XPA") à envoyer aux amis : ip_to_code() / code_to_ip() ;
#   - les amis tapent le code dans "Rejoindre" : c'est exactement la même
#     connexion qu'en Wi-Fi, vers l'adresse publique de la box de l'hôte.
#   - En quittant, le port est refermé sur la box.
#   Limites : l'hôte doit être sur une box qui accepte l'UPnP (pas en 4G, pas
#   derrière une adresse partagée "CGNAT"). Les invités, eux, peuvent être
#   n'importe où (4G comprise). Le jeu explique quoi faire si ça échoue.
# =============================================================================

signal players_changed
signal hosts_changed
signal session_ended(reason: String)
signal countdown_started(seconds: float)
signal race_results_changed
signal internet_opened(code: String)       # [INTERNET 1.6] port ouvert, code prêt
signal internet_failed(reason: String)     # [INTERNET 1.6] la box a refusé

const GAME_PORT = 47230
const DISCOVERY_PORT = 47231
const MAX_PLAYERS = 8
const STATE_INTERVAL = 1.0 / 20.0      # 20 envois d'état par seconde
const FINISH_TIMEOUT = 45.0            # s après la 1re arrivée avant retour au salon
const LOBBY_SCENE = "res://src/screens/MultiplayerLobby.tscn"

var player_name: String = ""
var players := {}            # peer_id -> {"name": String, "loaded": bool, "time": float (-1 = pas arrivé), "score": int}
var found_hosts := {}        # ip -> {"name": String, "players": int, "seen": float}
var in_race: bool = false    # une course multijoueur est en cours
var race_seed: int = 0
# [MODES 1.25] mode de la course réseau (Settings.MODE_CHILL / MODE_SCORE),
# choisi par l'hôte dans le salon et envoyé à tous avec le niveau et le seed.
var race_mode: int = 0
var last_mode: int = -1                  # dernier mode choisi dans le salon (-1 = celui des Options)
# [MODES 1.25] en Chill, on ne rentre pas au salon 4 s après la dernière
# arrivée : on laisse le temps de faire des figures ensemble dans le half-pipe.
const CHILL_STAY_TIME = 60.0             # s après la dernière arrivée (Chill)
const CHILL_FINISH_TIMEOUT = 150.0       # s après la 1re arrivée (Chill)
var race_level: String = ""
var last_results: Array = [] # [[nom, temps], ...] de la dernière course
var last_level_index: int = 0   # dernière course choisie par l'hôte (salon)
var pending_message: String = ""  # message à afficher en arrivant au salon (ex. "L'hôte a quitté")
var _listen_warned: bool = false

const CONFIG_PATH = "user://pinpouin.cfg"   # même fichier que RaceManager

# [INTERNET 1.6] codes de partie : 32 signes sans les confusions I/1, O/0
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
var internet_code: String = ""     # code de la partie ouverte sur Internet ("" = non)
var internet_busy: bool = false    # ouverture du port en cours (prend 1 à 3 s)
var is_online_game: bool = false   # connecté à un hôte hors du réseau local
var _upnp: UPNP = null             # gardé pour refermer le port en quittant

var _peer: ENetMultiplayerPeer = null
var _udp_announce: PacketPeerUDP = null
var _udp_listen: PacketPeerUDP = null
var _announce_timer: float = 0.0
var _first_finish_time: float = -1.0
var _race_id: int = 0         # n° de course (évite qu'un vieux délai ne termine la suivante)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # le réseau continue même en pause
	# Nom du joueur : mémorisé entre les parties (sinon "Pingouin 123")
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	player_name = cfg.get_value("net", "player_name", "Pingouin %d" % (randi() % 900 + 100))
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Change et mémorise le nom du joueur (champ "Ton nom" du salon).
func set_player_name(value: String) -> void:
	value = value.strip_edges().substr(0, 20)
	if value == "":
		return
	player_name = value
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)   # on garde les autres réglages (fantôme…)
	cfg.set_value("net", "player_name", value)
	cfg.save(CONFIG_PATH)


func is_discovering() -> bool:
	return _udp_listen != null


func is_active() -> bool:
	return _peer != null and _peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func is_host() -> bool:
	return is_active() and multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if is_active() else 0


# --- Créer / rejoindre / quitter ---------------------------------------------
func host() -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(GAME_PORT, MAX_PLAYERS - 1)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	players = {1: {"name": player_name, "loaded": false, "time": -1.0, "score": 0}}
	stop_discovery()   # l'hôte n'a pas besoin d'écouter les annonces (et libère le port)
	_start_announce()
	emit_signal("players_changed")
	return OK


func join(ip: String) -> Error:
	leave()
	# [INTERNET 1.6] hôte hors réseau local (code de partie / IP publique) :
	# on affichera les autres avec un peu plus de marge (connexion moins régulière)
	is_online_game = not _is_private_ip(ip.strip_edges())
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip.strip_edges(), GAME_PORT)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	return OK


func leave() -> void:
	_stop_announce()
	_close_internet()   # [INTERNET 1.6] referme le port de la box s'il était ouvert
	is_online_game = false
	if _peer != null:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	players.clear()
	in_race = false
	emit_signal("players_changed")


# Adresse(s) IPv4 de cet appareil sur le réseau local (à donner aux invités).
func local_ips() -> Array:
	var out := []
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or (ip.begins_with("172.") and int(ip.split(".")[1]) in range(16, 32)):
			out.append(ip)
	return out


# --- [INTERNET 1.6] Ouverture sur Internet + codes de partie --------------------
## Hôte : ouvre la partie sur Internet. Résultat par les signaux
## internet_opened(code) ou internet_failed(raison). Ne bloque pas le jeu :
## la discussion avec la box se fait dans un fil d'exécution à part.
func open_internet() -> void:
	if not is_host() or internet_busy or internet_code != "":
		return
	internet_busy = true
	WorkerThreadPool.add_task(_upnp_task)


# Exécuté hors du fil principal : on n'y touche à AUCUN nœud, on renvoie le
# résultat avec call_deferred (exécuté ensuite dans le fil principal).
func _upnp_task() -> void:
	var upnp := UPNP.new()
	var err := upnp.discover(2500, 2)
	if err != UPNP.UPNP_RESULT_SUCCESS or upnp.get_gateway() == null or not upnp.get_gateway().is_valid_gateway():
		_upnp_done.call_deferred(null, "", "Ta box n'a pas répondu (UPnP désactivé ou absent).")
		return
	var public_ip := upnp.query_external_address()
	if public_ip == "" or not public_ip.is_valid_ip_address() or public_ip.contains(":"):
		_upnp_done.call_deferred(null, "", "Impossible de connaître l'adresse Internet de ta box.")
		return
	if _is_private_ip(public_ip) or public_ip.begins_with("100."):
		_upnp_done.call_deferred(null, "", "Ta connexion partage son adresse Internet avec d'autres abonnés (4G ou « CGNAT ») : impossible d'héberger d'ici.")
		return
	# ENet utilise l'UDP ; durée 0 = jusqu'à ce qu'on le referme
	err = upnp.add_port_mapping(GAME_PORT, GAME_PORT, "Pinpouin Le Ninja", "UDP", 0)
	if err != UPNP.UPNP_RESULT_SUCCESS:
		_upnp_done.call_deferred(null, "", "Ta box a refusé d'ouvrir le port (erreur UPnP %d)." % err)
		return
	_upnp_done.call_deferred(upnp, public_ip, "")


func _upnp_done(upnp, public_ip: String, error_text: String) -> void:
	internet_busy = false
	if error_text != "" or not is_host():
		# échec, ou l'hôte a quitté entre-temps : on referme si besoin
		if upnp != null:
			upnp.delete_port_mapping(GAME_PORT, "UDP")
		if error_text != "":
			# si le salon n'est plus affiché (course lancée entre-temps), le
			# message sera montré au retour au salon
			if get_tree().current_scene == null or get_tree().current_scene.scene_file_path != LOBBY_SCENE:
				pending_message = error_text
			emit_signal("internet_failed", error_text)
		return
	_upnp = upnp
	is_online_game = true   # des joueurs vont arriver par Internet
	internet_code = ip_to_code(public_ip)
	print("[INTERNET] partie ouverte : ", public_ip, " -> code ", internet_code)
	emit_signal("internet_opened", internet_code)


func _close_internet() -> void:
	if _upnp != null:
		var upnp := _upnp
		_upnp = null
		# refermer le port peut prendre un instant : hors du fil principal
		WorkerThreadPool.add_task(func(): upnp.delete_port_mapping(GAME_PORT, "UDP"))
	internet_code = ""


## Adresse IPv4 -> code de 8 signes "XXXX-XXXX" (7 signes pour les 32 bits de
## l'adresse + 1 signe de contrôle qui détecte les fautes de frappe).
static func ip_to_code(ip: String) -> String:
	var parts := ip.split(".")
	var n := 0
	for p in parts:
		n = (n << 8) | (int(p) & 255)
	# 7 signes = 35 bits : les 3 bits en trop reçoivent une valeur au hasard
	# (sinon tous les codes commenceraient par A, B, C ou D)
	n |= (randi() % 8) << 32
	var chars := ""
	var checksum := 0
	for i in 7:
		var v := (n >> (5 * (6 - i))) & 31
		checksum += v * (2 * i + 1)   # poids impairs : toute faute sur 1 signe est détectée
		chars += CODE_ALPHABET[v]
	chars += CODE_ALPHABET[checksum % 32]
	return chars.substr(0, 4) + "-" + chars.substr(4, 4)


## Code de partie -> adresse IPv4, ou "" si le code est invalide.
static func code_to_ip(code: String) -> String:
	var clean := code.to_upper().replace("-", "").replace(" ", "")
	if clean.length() != 8:
		return ""
	var n := 0
	var checksum := 0
	for i in 7:
		var v := CODE_ALPHABET.find(clean[i])
		if v < 0:
			return ""
		checksum += v * (2 * i + 1)   # poids impairs : toute faute sur 1 signe est détectée
		n = (n << 5) | v
	if CODE_ALPHABET.find(clean[7]) != checksum % 32:
		return ""
	n &= 0xFFFFFFFF   # on ignore les 3 bits "au hasard"
	return "%d.%d.%d.%d" % [(n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255]


static func _is_private_ip(ip: String) -> bool:
	if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("127."):
		return true
	if ip.begins_with("172."):
		var b := int(ip.split(".")[1])
		return b >= 16 and b < 32
	return false


# --- Découverte sur le Wi-Fi (diffusion UDP) ------------------------------------
func _start_announce() -> void:
	_udp_announce = PacketPeerUDP.new()
	_udp_announce.set_broadcast_enabled(true)
	_udp_announce.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_announce_timer = 0.0


func _stop_announce() -> void:
	if _udp_announce != null:
		_udp_announce.close()
	_udp_announce = null


## À appeler quand l'écran "Rejoindre" est ouvert.
func start_discovery() -> void:
	stop_discovery()
	_udp_listen = PacketPeerUDP.new()
	if _udp_listen.bind(DISCOVERY_PORT) != OK:
		# arrive surtout avec 2 jeux sur le même PC : le 2e ne peut pas écouter
		# (rejoindre par l'IP 127.0.0.1 reste possible). On ne prévient qu'une fois.
		if not _listen_warned:
			push_warning("[MULTI] impossible d'écouter les annonces (port %d occupé ?)" % DISCOVERY_PORT)
			_listen_warned = true
		_udp_listen = null
	found_hosts.clear()


func stop_discovery() -> void:
	if _udp_listen != null:
		_udp_listen.close()
	_udp_listen = null


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	# Hôte : annonce "PINPOUIN|version|nom|nb joueurs" toutes les secondes
	if _udp_announce != null and not in_race:
		_announce_timer -= delta
		if _announce_timer <= 0.0:
			_announce_timer = 1.0
			var msg := "PINPOUIN|%s|%s|%d" % [_version(), player_name, players.size()]
			_udp_announce.put_packet(msg.to_utf8_buffer())
	# Invité : écoute les annonces
	if _udp_listen != null:
		var changed := false
		while _udp_listen.get_available_packet_count() > 0:
			var pkt := _udp_listen.get_packet().get_string_from_utf8()
			var ip := _udp_listen.get_packet_ip()
			var parts := pkt.split("|")
			if parts.size() >= 4 and parts[0] == "PINPOUIN" and parts[1] == _version():
				found_hosts[ip] = {"name": parts[2], "players": int(parts[3]), "seen": now}
				changed = true
		for ip in found_hosts.keys():   # oublie les parties muettes depuis 4 s
			if now - found_hosts[ip].seen > 4.0:
				found_hosts.erase(ip)
				changed = true
		if changed:
			emit_signal("hosts_changed")
	# Fin de course : délai max après la 1re arrivée (hôte)
	if is_host() and in_race and _first_finish_time > 0.0 and now - _first_finish_time > (CHILL_FINISH_TIMEOUT if race_mode == Settings.MODE_CHILL else FINISH_TIMEOUT):
		_end_race()


func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "?"))


# --- Connexions -----------------------------------------------------------------
func _on_connected_to_server() -> void:
	# l'invité se présente (nom + version) à l'hôte
	_rpc_register.rpc_id(1, player_name, _version())


func _on_connection_failed() -> void:
	var online := is_online_game
	leave()
	if online:
		# [INTERNET 1.6] cas le plus fréquent : code mal recopié, ou l'hôte n'a
		# pas (encore) ouvert sa partie sur Internet
		emit_signal("session_ended", "Connexion impossible : vérifie le code, et que l'hôte a bien cliqué « Ouvrir sur Internet ».")
	else:
		emit_signal("session_ended", "Connexion impossible à cette partie.")


func _on_server_disconnected() -> void:
	var was_racing := in_race
	leave()
	pending_message = "L'hôte a quitté la partie."
	emit_signal("session_ended", pending_message)
	if was_racing:
		get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_peer_connected(_id: int) -> void:
	pass  # on attend que l'invité se présente (_rpc_register)


func _on_peer_disconnected(id: int) -> void:
	if players.has(id):
		players.erase(id)
		RaceManager.remove_remote(id)
		if is_host():
			_rpc_players.rpc(players)
			_check_all_loaded()
			_check_all_finished()
		emit_signal("players_changed")


@rpc("any_peer", "reliable")
func _rpc_register(p_name: String, version: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if version != _version() or in_race:
		# version différente ou course déjà lancée : on refuse poliment
		_rpc_refused.rpc_id(id, "Version différente (hôte : %s)." % _version() if version != _version() else "Course déjà en cours, réessaie après.")
		await get_tree().create_timer(0.3).timeout
		_peer.disconnect_peer(id)
		return
	players[id] = {"name": p_name.substr(0, 20), "loaded": false, "time": -1.0, "score": 0}
	_rpc_players.rpc(players)
	emit_signal("players_changed")


@rpc("authority", "reliable")
func _rpc_refused(reason: String) -> void:
	pending_message = reason
	emit_signal("session_ended", reason)


@rpc("authority", "call_local", "reliable")
func _rpc_players(p: Dictionary) -> void:
	players = p
	emit_signal("players_changed")


# --- Course ----------------------------------------------------------------------
## Hôte : lance une course sur un niveau pour tous les joueurs.
func start_race(level_path: String, mode: int = 0) -> void:
	if not is_host():
		return
	_rpc_start.rpc(level_path, randi(), mode)   # [MODES 1.25] + le mode de jeu


@rpc("authority", "call_local", "reliable")
func _rpc_start(level_path: String, seed_value: int, mode: int = 0) -> void:
	in_race = true
	_race_id += 1
	race_level = level_path
	race_seed = seed_value
	race_mode = mode   # [MODES 1.25]
	_first_finish_time = -1.0
	for id in players:
		players[id].loaded = false
		players[id].time = -1.0
		players[id].score = 0
	get_tree().paused = false
	get_tree().change_scene_to_file(level_path)


## Appelé par RaceManager quand le niveau est chargé et le pingouin prêt.
func notify_loaded() -> void:
	_rpc_loaded.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func _rpc_loaded() -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.has(id):
		players[id].loaded = true
		# [ATTENTE 1.14] on renvoie la liste à tous : chacun peut afficher
		# « 2/3 prêts — on attend Léo » pendant l'attente avant le décompte
		_rpc_players.rpc(players)
	_check_all_loaded()


func _check_all_loaded() -> void:
	if not in_race:
		return
	for id in players:
		if not players[id].loaded:
			return
	_rpc_go.rpc(3.0)


@rpc("authority", "call_local", "reliable")
func _rpc_go(seconds: float) -> void:
	emit_signal("countdown_started", seconds)


## Envoi de l'état du pingouin local (appelé par RaceManager, 20 fois/s).
func send_state(state: PackedFloat32Array, anim: String) -> void:
	if is_active():
		_rpc_state.rpc(state, anim)


@rpc("any_peer", "unreliable_ordered")
func _rpc_state(state: PackedFloat32Array, anim: String) -> void:
	RaceManager.on_remote_state(multiplayer.get_remote_sender_id(), state, anim)


## Appelé par RaceManager à l'arrivée du joueur local.
## [SCORE 1.5] on envoie aussi le score (vitesse + figures) : le classement se fait au score.
func report_finish(time: float, score: int) -> void:
	_rpc_finished.rpc(time, score)


@rpc("any_peer", "call_local", "reliable")
func _rpc_finished(time: float, score: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if players.has(id) and players[id].time < 0.0:
		players[id].time = time
		players[id].score = score
		if _first_finish_time < 0.0:
			_first_finish_time = Time.get_ticks_msec() / 1000.0
	emit_signal("race_results_changed")
	if is_host():
		_check_all_finished()


func _check_all_finished() -> void:
	if not in_race:
		return
	for id in players:
		if players[id].time < 0.0:
			return
	var id := _race_id
	# le temps d'admirer le classement (Score) ; en Chill : de rider ensemble
	await get_tree().create_timer(CHILL_STAY_TIME if race_mode == Settings.MODE_CHILL else 4.0).timeout
	if id == _race_id:
		_end_race()


func _end_race() -> void:
	if is_host() and in_race:
		_rpc_back_to_lobby.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_back_to_lobby() -> void:
	# [MODES 1.25] pas de classement à afficher au salon après une course Chill
	last_results = [] if race_mode == Settings.MODE_CHILL else ranking()
	in_race = false
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().change_scene_to_file(LOBBY_SCENE)


## Place du joueur local parmi les arrivés (1 = premier), 0 s'il n'est pas arrivé.
## [SCORE 1.5] au score (à score égal : au temps). Attention : un joueur encore
## en course peut encore nous dépasser, la place affichée est provisoire.
func my_rank() -> int:
	var me = players.get(my_id())
	if me == null or me.time < 0.0:
		return 0
	var rank := 1
	for id in players:
		var o = players[id]
		if id != my_id() and o.time >= 0.0 and (o.score > me.score or (o.score == me.score and o.time < me.time)):
			rank += 1
	return rank


## Classement : [[nom, temps, score], ...] trié au score (les non-arrivés à la fin, temps -1).
func ranking() -> Array:
	var arr := []
	for id in players:
		arr.append([players[id].name, players[id].time, int(players[id].get("score", 0))])
	arr.sort_custom(func(a, b):
		if a[1] < 0.0: return false
		if b[1] < 0.0: return true
		if a[2] != b[2]: return a[2] > b[2]
		return a[1] < b[1])
	return arr
