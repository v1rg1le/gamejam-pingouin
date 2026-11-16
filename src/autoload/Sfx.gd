extends Node
# =============================================================================
#  Sfx.gd — [BRUITAGES 1.34] lecteur de bruitages (autoload « Sfx »)
# =============================================================================
#  Le jeu n'avait aucun bruitage. En attendant les vrais enregistrements (liste
#  « Pinpouin Le Ninja — Sons à enregistrer »), des sons PROVISOIRES calculés
#  par Claude sont dans res://assets/sfx_provisoire/ (même noms de fichiers que
#  la liste). Pour passer aux vrais sons : déposer les WAV de l'ami dans
#  res://assets/sfx/ avec les mêmes noms (nom_01.wav, nom_02.wav… ou nom.wav
#  pour les boucles) : ils sont pris EN PRIORITÉ, sans toucher au code.
#
#  Utilisation :
#    Sfx.play("saut")                 -> une variante au hasard, hauteur variée
#    Sfx.play("figure_ok", -3.0, 1.2) -> volume (dB) et hauteur imposés
#    Sfx.loop("glisse_boucle", vol)   -> boucle continue, volume réglé à chaque image
#
#  Tout passe par le bus audio « Sound », réglé par le curseur
#  « Volume des effets » des Options (Settings.sfx_volume).
#  Les clics des boutons des menus sont ajoutés automatiquement.
# =============================================================================

const DIRS := ["res://assets/sfx/", "res://assets/sfx_provisoire/"]
const BUS := "Sound"
const VOICES := 10                       # sons courts joués en même temps au maximum

var _cache := {}                         # nom -> Array[AudioStream] (variantes)
var _players: Array = []                 # AudioStreamPlayer pour les sons courts
var _next := 0
var _loops := {}                         # nom -> AudioStreamPlayer (boucles)
var _loop_targets := {}                  # nom -> volume voulu cette image (linéaire)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS      # les clics marchent aussi en pause
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		add_child(p)
		_players.append(p)
	# clic sur tous les boutons des menus, créés maintenant ou plus tard
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta("sfx_wired"):
		n.set_meta("sfx_wired", true)
		n.pressed.connect(func(): play("ui_clic", -6.0))


## Toutes les variantes d'un son (nom_01, nom_02… ou nom), vrais sons d'abord.
func _streams(name: String) -> Array:
	if _cache.has(name):
		return _cache[name]
	var found: Array = []
	for dir in DIRS:
		for i in range(1, 10):
			var path := "%s%s_%02d.wav" % [dir, name, i]
			if ResourceLoader.exists(path):
				found.append(load(path))
		if found.is_empty() and ResourceLoader.exists(dir + name + ".wav"):
			found.append(load(dir + name + ".wav"))
		if not found.is_empty():
			break                       # les vrais sons (assets/sfx) masquent les provisoires
	_cache[name] = found
	return found


## Joue un son court. pitch < 0 : hauteur un peu au hasard (évite la répétition).
func play(name: String, volume_db: float = 0.0, pitch: float = -1.0) -> void:
	var list := _streams(name)
	if list.is_empty():
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = list[randi() % list.size()]
	p.volume_db = volume_db
	p.pitch_scale = pitch if pitch > 0.0 else randf_range(0.93, 1.07)
	p.play()


## Boucle : à appeler à CHAQUE image avec le volume voulu (0 à 1). Une boucle
## qui n'est plus demandée s'éteint en douceur (voir _process).
func loop(name: String, volume: float, pitch: float = 1.0) -> void:
	_loop_targets[name] = clampf(volume, 0.0, 1.0)
	if not _loops.has(name):
		var list := _streams(name)
		if list.is_empty():
			return
		var p := AudioStreamPlayer.new()
		p.bus = BUS
		p.stream = list[0]
		p.volume_db = -60.0
		add_child(p)
		p.play()
		_loops[name] = p
	_loops[name].pitch_scale = pitch


func _process(delta: float) -> void:
	for name in _loops.keys():
		var p: AudioStreamPlayer = _loops[name]
		var target: float = _loop_targets.get(name, 0.0)
		# volume lissé (pas de saut brusque), en linéaire
		var cur := db_to_linear(p.volume_db)
		cur = move_toward(cur, target, delta * 3.0)
		p.volume_db = linear_to_db(maxf(cur, 0.0001))
		if not p.playing and cur > 0.001:
			p.play()                    # (au cas où la boucle aurait été coupée)
		if cur <= 0.0001 and target <= 0.0:
			p.stop()
			p.queue_free()
			_loops.erase(name)
	_loop_targets.clear()               # chaque image, les boucles doivent être redemandées


## Coupe toutes les boucles tout de suite (changement de scène).
func stop_loops() -> void:
	for name in _loops.keys():
		_loops[name].queue_free()
	_loops.clear()
	_loop_targets.clear()
