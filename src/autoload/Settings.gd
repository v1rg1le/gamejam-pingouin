extends Node
# =============================================================================
#  Settings.gd — autoload : schéma de contrôle actif
# -----------------------------------------------------------------------------
#  [MIGRATION GODOT 4.7] setget -> `: set = set_controls`
#
#  [MOBILE] (nouveau)
#   - Nouveau schéma TOUCH (écran tactile), ajouté EN FIN d'enum pour que
#     KBD_MOUSE (0) et GAMEPAD (1) gardent leurs valeurs.
#   - Détection de la plateforme au démarrage : `is_mobile_device` est vrai
#     sur Android / iOS (ou navigateur mobile si un jour export Web). On
#     démarre alors directement en TOUCH.
#   - Détection en cours de jeu (utile pour les PC/tablettes tactiles) :
#       * toucher l'écran           -> TOUCH
#       * manette                   -> GAMEPAD
#       * clavier / vraie souris    -> KBD_MOUSE
#     Les clics souris "émulés" par Godot à partir d'un toucher sont ignorés
#     (device == DEVICE_ID_EMULATION), sinon chaque toucher repasserait en
#     KBD_MOUSE.
#   - En mode TOUCH, les clics souris sont retirés des actions "hook" et
#     "pull" : sinon chaque toucher (même sur le bouton SAUT) lancerait le
#     grappin via le clic émulé. Ils sont remis dès qu'on revient au PC.
#   - `touch_aim` : direction de visée du grappin fournie par les contrôles
#     tactiles (Vector2.ZERO = visée par défaut, vers l'avant et le haut).
#
#  [OPTIONS 1.7] Réglages du joueur (écran Options), mémorisés dans
#  user://pinpouin.cfg (section "options") :
#   - help_on_start  : carte d'aide (commandes + score) en début de niveau,
#                      jeu en pause jusqu'à ce qu'on appuie sur une touche ;
#   - tutorial_pause : dans le tuto, le jeu se met en pause à chaque panneau
#                      pour laisser le temps de lire ;
#   - music_volume   : volume de la musique (0 à 1, bus audio "Music").
# =============================================================================

signal controls_changed(new_scheme)

enum {KBD_MOUSE, GAMEPAD, TOUCH}
var controls: = KBD_MOUSE: set = set_controls

## [MOBILE] true si le jeu tourne sur un appareil mobile (Android / iOS).
var is_mobile_device: bool = false
## [MOBILE] visée du grappin en mode tactile (mise à jour par TouchControls).
var touch_aim: Vector2 = Vector2.ZERO

# [MOBILE] actions dont on retire les clics souris en mode tactile
const MOUSE_ACTIONS_DISABLED_IN_TOUCH = ["hook", "pull"]
var _removed_mouse_events := {}   # action -> Array[InputEvent] retirés

# [OPTIONS 1.7]
signal options_changed
const OPTIONS_PATH = "user://pinpouin.cfg"   # même fichier que les records / fantômes
var help_on_start: bool = true
var tutorial_pause: bool = true
var music_volume: float = 0.8


func _ready() -> void:
	# [MOBILE] détection de la plateforme au lancement
	is_mobile_device = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	print("[MOBILE] appareil mobile : ", is_mobile_device, " | écran tactile dispo : ", DisplayServer.is_touchscreen_available())
	if is_mobile_device:
		self.controls = TOUCH
		# [MOBILE] les téléphones en paysage sont plus larges que 1024x720 :
		# en mode "expand" l'image remplit tout l'écran (pas de bandes noires
		# sur les côtés) ; on voit simplement un peu plus de niveau en largeur.
		# Sur PC on garde le réglage du projet (keep_width).
		get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_load_options()   # [OPTIONS 1.7]


# --- [OPTIONS 1.7] -------------------------------------------------------------
func _load_options() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(OPTIONS_PATH) == OK:
		help_on_start = cfg.get_value("options", "help_on_start", true)
		tutorial_pause = cfg.get_value("options", "tutorial_pause", true)
		music_volume = clampf(float(cfg.get_value("options", "music_volume", 0.8)), 0.0, 1.0)
	apply_music_volume()


## Change un réglage, l'applique et le mémorise.
func set_option(key: String, value) -> void:
	set(key, value)
	if key == "music_volume":
		apply_music_volume()
	var cfg := ConfigFile.new()
	cfg.load(OPTIONS_PATH)   # on garde les autres sections (records, fantôme, nom…)
	cfg.set_value("options", key, value)
	cfg.save(OPTIONS_PATH)
	emit_signal("options_changed")


## Volume de la musique : bus "Music" (cf. default_bus_layout.tres).
func apply_music_volume() -> void:
	var bus := AudioServer.get_bus_index("Music")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(music_volume, 0.0001)))


# [FINITION 13/11] Touche "retour" d'Android : par défaut Godot FERME l'appli
# (même en pleine partie). On la désactive dans les réglages du projet
# (application/config/quit_on_go_back = false) et on la traduit ici :
#  - écran titre      -> on quitte le jeu (comportement attendu sur Android)
#  - partout ailleurs -> équivalent de Échap (pause en jeu, retour au menu
#    précédent dans la sélection des niveaux)
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		var scene = get_tree().current_scene
		if scene != null and scene.scene_file_path == "res://src/screens/MainScreen.tscn":
			get_tree().quit()
		else:
			var ev := InputEventAction.new()
			ev.action = "ui_cancel"
			ev.pressed = true
			Input.parse_input_event(ev)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		self.controls = TOUCH
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		# petite zone morte : un stick qui "dérive" ne doit pas voler le contrôle
		if event is InputEventJoypadMotion and abs(event.axis_value) < 0.3:
			return
		self.controls = GAMEPAD
	elif event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return  # [MOBILE] clic/mouvement souris généré par un toucher : on ignore
	elif event is InputEventKey or event is InputEventMouseButton:
		self.controls = KBD_MOUSE
	elif event is InputEventMouseMotion and not is_mobile_device and event.relative.length() > 4.0:
		# vraie souris qui bouge franchement (pas un simple tremblement)
		self.controls = KBD_MOUSE


func set_controls(value:int) -> void:
	if value == controls:
		return  # [MOBILE] pas de signal inutile à chaque événement
	controls = value
	_update_mouse_bindings()
	emit_signal("controls_changed", controls)


# [MOBILE] retire / remet les clics souris des actions du grappin
func _update_mouse_bindings() -> void:
	if controls == TOUCH:
		for action in MOUSE_ACTIONS_DISABLED_IN_TOUCH:
			if _removed_mouse_events.has(action) or not InputMap.has_action(action):
				continue
			var removed := []
			for ev in InputMap.action_get_events(action):
				if ev is InputEventMouseButton:
					removed.append(ev)
					InputMap.action_erase_event(action, ev)
			_removed_mouse_events[action] = removed
	else:
		for action in _removed_mouse_events:
			for ev in _removed_mouse_events[action]:
				InputMap.action_add_event(action, ev)
		_removed_mouse_events.clear()
		touch_aim = Vector2.ZERO
