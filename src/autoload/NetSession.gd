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
# =============================================================================

signal players_changed
signal hosts_changed
signal session_ended(reason: String)
signal countdown_started(seconds: float)
signal race_results_changed

const GAME_PORT = 47230
const DISCOVERY_PORT = 47231
const MAX_PLAYERS = 8
const STATE_INTERVAL = 1.0 / 20.0      # 20 envois d'état par seconde
const FINISH_TIMEOUT = 45.0            # s après la 1re arrivée avant retour au salon
const LOBBY_SCENE = "res://src/screens/MultiplayerLobby.tscn"

var player_name: String = ""
var players := {}            # peer_id -> {"name": String, "loaded": bool, "time": float (-1 = pas arrivé)}
var found_hosts := {}        # ip -> {"name": String, "players": int, "seen": float}
var in_race: bool = false    # une course multijoueur est en cours
var race_seed: int = 0
var race_level: String = ""
var last_results: Array = [] # [[nom, temps], ...] de la dernière course
var last_level_index: int = 0   # dernière course choisie par l'hôte (salon)
var pending_message: String = ""  # message à afficher en arrivant au salon (ex. "L'hôte a quitté")
var _listen_warned: bool = false

const CONFIG_PATH = "user://pinpouin.cfg"   # même fichier que RaceManager

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
	players = {1: {"name": player_name, "loaded": false, "time": -1.0}}
	stop_discovery()   # l'hôte n'a pas besoin d'écouter les annonces (et libère le port)
	_start_announce()
	emit_signal("players_changed")
	return OK


func join(ip: String) -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip.strip_edges(), GAME_PORT)
	if err != OK:
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	return OK


func leave() -> void:
	_stop_announce()
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
	if is_host() and in_race and _first_finish_time > 0.0 and now - _first_finish_time > FINISH_TIMEOUT:
		_end_race()


func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "?"))


# --- Connexions -----------------------------------------------------------------
func _on_connected_to_server() -> void:
	# l'invité se présente (nom + version) à l'hôte
	_rpc_register.rpc_id(1, player_name, _version())


func _on_connection_failed() -> void:
	leave()
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
	players[id] = {"name": p_name.substr(0, 20), "loaded": false, "time": -1.0}
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
func start_race(level_path: String) -> void:
	if not is_host():
		return
	_rpc_start.rpc(level_path, randi())


@rpc("authority", "call_local", "reliable")
func _rpc_start(level_path: String, seed_value: int) -> void:
	in_race = true
	_race_id += 1
	race_level = level_path
	race_seed = seed_value
	_first_finish_time = -1.0
	for id in players:
		players[id].loaded = false
		players[id].time = -1.0
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
func report_finish(time: float) -> void:
	_rpc_finished.rpc(time)


@rpc("any_peer", "call_local", "reliable")
func _rpc_finished(time: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if players.has(id) and players[id].time < 0.0:
		players[id].time = time
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
	await get_tree().create_timer(4.0).timeout   # le temps d'admirer le classement
	if id == _race_id:
		_end_race()


func _end_race() -> void:
	if is_host() and in_race:
		_rpc_back_to_lobby.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_back_to_lobby() -> void:
	last_results = ranking()
	in_race = false
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().change_scene_to_file(LOBBY_SCENE)


## Place du joueur local parmi les arrivés (1 = premier), 0 s'il n'est pas arrivé.
func my_rank() -> int:
	var me = players.get(my_id())
	if me == null or me.time < 0.0:
		return 0
	var rank := 1
	for id in players:
		if id != my_id() and players[id].time >= 0.0 and players[id].time < me.time:
			rank += 1
	return rank


## Classement : [[nom, temps], ...] trié (les non-arrivés à la fin, temps -1).
func ranking() -> Array:
	var arr := []
	for id in players:
		arr.append([players[id].name, players[id].time])
	arr.sort_custom(func(a, b):
		if a[1] < 0.0: return false
		if b[1] < 0.0: return true
		return a[1] < b[1])
	return arr
