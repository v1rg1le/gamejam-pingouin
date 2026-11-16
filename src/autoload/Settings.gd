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
# [WEB 1.17] version jouable dans le navigateur (page itch.io). Le navigateur
# n'a ni réseau ENet (multijoueur), ni dossiers ouvrables, ni « quitter ».
var is_web: bool = OS.has_feature("web")
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
var physics_panel: bool = false   # [PHYSIQUE 1.10] bouton ⚙ du panneau de réglage en tactile
var master_wink: bool = true      # [MAÎTRE 1.19] clin d'œil du maître ninja à chaque figure réussie
# [MODE ENFANT 1.23] Options → « Mode enfant » : poussée automatique au sol,
# coup de pouce dans les creux, aide visuelle quand on n'avance plus, boutons
# tactiles plus faciles à toucher, carte d'aide simplifiée (voir KidAssist.gd).
# Désactivé par défaut ; jamais actif en multijoueur.
var kid_mode: bool = false
# [MODES 1.25] Deux façons de jouer (retours de Léo : « Chill > score,
# Tricks > score ») :
#  - MODE_CHILL (par défaut) : pas de chrono ni de score à l'écran, pas de
#    fantôme, l'arrivée est celle d'origine (dans le half-pipe) et le niveau
#    ne se ferme pas : on reste faire des figures autant qu'on veut ;
#  - MODE_SCORE : le jeu « compétition » (arrivée à l'arche, chrono, record,
#    fantôme, médailles bronze / argent / or, 30 s de figures bonus).
# Choisi en haut de la sélection des niveaux ; en multijoueur, c'est l'hôte
# qui choisit pour tout le monde (NetSession.race_mode).
enum { MODE_CHILL, MODE_SCORE }
var game_mode: int = MODE_CHILL
var ui_size: float = 1.0          # [RESPONSIVE 1.14] réglage « Taille de l'interface » (0,8 à 1,5)
# [FLÈCHES 1.16] flèches vers les autres joueurs en multi (choix dans Options)
enum { ARROWS_ALL, ARROWS_NEIGHBOURS, ARROWS_NONE }
var player_arrows: int = ARROWS_ALL


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
	# [RESPONSIVE 1.14] … et maintenant sur PC aussi : une fenêtre plus large
	# ou plus haute que 1024 × 720 montre simplement plus de jeu, au lieu
	# d'ajouter des bandes noires. Les menus se recentrent tout seuls
	# (ancrages), le HUD reste collé aux bords.
	get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_load_options()   # [OPTIONS 1.7]
	_add_symbol_font_fallback()   # [WEB 1.17]
	# [RESPONSIVE 1.14] _process doit tourner même en pause (changement de
	# scène depuis le menu pause) ; une fenêtre redimensionnée recalcule
	# l'échelle des menus.
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.size_changed.connect(func(): _last_scene_path = "?")


# --- [OPTIONS 1.7] -------------------------------------------------------------
func _load_options() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(OPTIONS_PATH) == OK:
		help_on_start = cfg.get_value("options", "help_on_start", true)
		tutorial_pause = cfg.get_value("options", "tutorial_pause", true)
		music_volume = clampf(float(cfg.get_value("options", "music_volume", 0.8)), 0.0, 1.0)
		physics_panel = cfg.get_value("options", "physics_panel", false)
		master_wink = cfg.get_value("options", "master_wink", true)
		kid_mode = cfg.get_value("options", "kid_mode", false)   # [MODE ENFANT 1.23]
		game_mode = clampi(int(cfg.get_value("options", "game_mode", MODE_CHILL)), MODE_CHILL, MODE_SCORE)   # [MODES 1.25]
		ui_size = clampf(float(cfg.get_value("options", "ui_size", 1.0)), 0.8, 1.5)
		player_arrows = clampi(int(cfg.get_value("options", "player_arrows", ARROWS_ALL)), ARROWS_ALL, ARROWS_NONE)
	apply_music_volume()


## [MODES 1.25] Vrai si la partie en cours (ou à lancer) est en mode Chill.
## En multijoueur, c'est le mode choisi par l'hôte qui compte.
func is_chill() -> bool:
	if NetSession.in_race:
		return NetSession.race_mode == MODE_CHILL
	return game_mode == MODE_CHILL


## Change un réglage, l'applique et le mémorise.
func set_option(key: String, value) -> void:
	set(key, value)
	if key == "music_volume":
		apply_music_volume()
	if key == "ui_size":   # [RESPONSIVE 1.14] appliqué tout de suite aux menus
		_last_scene_path = ""
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


# --- [RESPONSIVE 1.14] Taille de l'interface ---------------------------------
# L'écran du jeu fait toujours au moins 1024 × 720 « unités », quelle que soit
# la machine. Sur un PC, 720 unités font ~25 cm de haut ; sur un téléphone en
# paysage, ~6 à 7 cm : tout le texte est 4 fois plus petit. On agrandit donc
# l'interface selon la hauteur PHYSIQUE de l'écran (pouces = pixels ÷ dpi) :
#   écran de 5 pouces de haut ou plus (tablette, PC) -> × 1
#   téléphone (~2,7 pouces)                           -> × 1,4 (maximum)
# multiplié par le réglage « Taille de l'interface » des Options.

## Échelle automatique (1 sur PC, jusqu'à 1,4 sur un petit téléphone).
func auto_ui_scale() -> float:
	if not is_mobile_device:
		return 1.0
	var screen := DisplayServer.screen_get_size()
	var dpi := float(DisplayServer.screen_get_dpi())
	if dpi <= 0.0:
		return 1.25
	var inches := float(mini(screen.x, screen.y)) / dpi
	return clampf(1.0 + (5.0 - inches) * 0.17, 1.0, 1.4)


## Échelle du HUD et des menus EN JEU (calques agrandis par UiScaler).
func hud_scale() -> float:
	return clampf(auto_ui_scale() * ui_size, 0.7, 2.0)


## Échelle des écrans de MENU (titre, sélection, salon, options…) : on
## agrandit autant que hud_scale() le demande, mais jamais au point que le
## contenu de l'écran (taille minimale de ses conteneurs) ne tienne plus.
func menu_scale(scene: Node) -> float:
	var root := get_tree().root
	# taille de l'écran en unités, SANS agrandissement
	var view: Vector2 = root.get_visible_rect().size * root.content_scale_factor
	var need := Vector2(320, 240)
	for c in scene.get_children():
		if c is Container and c.visible:
			var m: Vector2 = c.get_combined_minimum_size()
			need = Vector2(maxf(need.x, m.x), maxf(need.y, m.y))
	var fit: float = minf(view.x / (need.x + 8.0), view.y / (need.y + 8.0))
	return clampf(hud_scale(), 0.7, maxf(fit, 0.7))


# Les écrans de menu utilisent l'agrandissement global de la fenêtre
# (content_scale_factor) ; dans les niveaux il reste à 1 pour ne pas changer
# la vue du jeu (le HUD, lui, est agrandi par UiScaler). On surveille donc la
# scène courante.
var _last_scene_path := "?"
var _menu_check_timer := 0.0

func _process(delta: float) -> void:
	var scene = get_tree().current_scene
	var path: String = scene.scene_file_path if scene != null else ""
	var is_menu: bool = path.begins_with("res://src/screens/")
	if path == _last_scene_path:
		# un menu peut grandir (salon : liste des joueurs, parties trouvées…) :
		# on revérifie 2 fois par seconde que tout tient encore à l'écran
		if not is_menu:
			return
		_menu_check_timer -= delta
		if _menu_check_timer > 0.0:
			return
	_menu_check_timer = 0.5
	_last_scene_path = path
	var factor := 1.0
	if is_menu:
		factor = menu_scale(scene)
	var root := get_tree().root
	if absf(root.content_scale_factor - factor) < 0.02:
		return
	root.content_scale_factor = factor
	# Godot ne recale pas toujours les Control « plein écran » quand
	# l'agrandissement change : on le fait à la main, une image plus tard
	# (le temps que la nouvelle taille de l'écran soit prise en compte).
	await get_tree().process_frame
	if is_instance_valid(scene) and scene is Control and scene.anchor_right == 1.0 and scene.anchor_bottom == 1.0:
		scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scene.size = root.get_visible_rect().size
		if scene.has_method("_layout"):
			scene._layout()


# --- [ENTRÉES 1.14] « Appuie pour continuer » --------------------------------
# Retour de test : sur téléphone, l'écran titre « appuie sur une touche »
# partait aussi avec les boutons de VOLUME (Android les envoie au jeu comme des
# touches de clavier). Ces deux fonctions servent à tous les écrans
# « appuie pour continuer » (titre, fin, pause de lecture du tuto).

## Touches « système » que le joueur n'utilise jamais pour jouer : volume,
## muet, touches média, touche retour Android (gérée à part, cf. plus haut).
const SYSTEM_KEYS = [KEY_VOLUMEUP, KEY_VOLUMEDOWN, KEY_VOLUMEMUTE,
	KEY_MEDIAPLAY, KEY_MEDIASTOP, KEY_MEDIANEXT,
	KEY_MEDIAPREVIOUS, KEY_BACK]

func is_system_key(event: InputEvent) -> bool:
	return event is InputEventKey and (event.keycode in SYSTEM_KEYS or event.physical_keycode in SYSTEM_KEYS)

## Vrai si `event` est un appui qui doit faire « continuer ».
## - Sur TÉLÉPHONE / TABLETTE : uniquement un toucher de l'écran, ou un bouton
##   de manette si une manette est branchée (geste toujours volontaire).
##   Les touches (volume…) et les clics souris « émulés » sont ignorés.
## - Sur PC : touche du clavier (sauf touches système), clic, bouton de
##   manette ou toucher (écran tactile de PC).
func is_continue_press(event: InputEvent) -> bool:
	if not event.is_pressed() or event.is_echo():
		return false
	if is_mobile_device:
		return event is InputEventScreenTouch or event is InputEventJoypadButton
	if event is InputEventKey:
		return not is_system_key(event)
	if event is InputEventMouseButton:
		return event.device != InputEvent.DEVICE_ID_EMULATION or not DisplayServer.is_touchscreen_available()
	return event is InputEventJoypadButton or event is InputEventScreenTouch


func _input(event: InputEvent) -> void:
	# [ENTRÉES 1.14] une touche de volume ne doit pas faire passer en mode
	# « clavier » (ce qui cachait les boutons tactiles en pleine course !)
	if is_system_key(event):
		return
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
			# [TEST ENFANT 1.22] BUG trouvé par le bot « enfant » : sur un PC
			# tactile (ou une tablette Windows), le tout premier toucher génère
			# aussi un clic souris « émulé ». Ce clic appuie sur "hook" AVANT
			# qu'on retire les clics souris de l'action… et le relâchement du
			# clic n'est plus reconnu ensuite => "hook" restait appuyé pour
			# toujours et le grappin ne pouvait plus jamais s'accrocher.
			# On relâche donc l'action au moment où on lui retire la souris.
			Input.action_release(action)
	else:
		for action in _removed_mouse_events:
			for ev in _removed_mouse_events[action]:
				InputMap.action_add_event(action, ev)
		_removed_mouse_events.clear()
		touch_aim = Vector2.ZERO



# --- [WEB 1.17] Symboles ★ ◀ ▶ ⚙ ↺ ↻ … ------------------------------------------
# Les polices du jeu (Roboto, et la police par défaut de Godot) n'ont pas ces
# symboles. Sur PC, le système fournit une police de secours ; dans le
# NAVIGATEUR (version itch.io) il n'y en a aucune : ils s'affichaient en
# petits rectangles. On ajoute donc DejaVu Sans (police libre, licence dans
# assets/font/DejaVuSans_LICENCE.txt) comme police de secours partout.
const SYMBOL_FONT = "res://assets/font/DejaVuSans.ttf"
const GAME_FONTS = ["res://assets/font/Roboto-Medium.ttf"]

# On GARDE une référence aux polices modifiées : sinon Godot les libère dès la
# fin de la fonction, et le prochain chargement repart sans police de secours.
var _patched_fonts: Array = []

func _add_symbol_font_fallback() -> void:
	if not ResourceLoader.exists(SYMBOL_FONT):
		return
	var symbols: Font = load(SYMBOL_FONT)
	var fonts: Array = [ThemeDB.fallback_font]
	for path in GAME_FONTS:
		if ResourceLoader.exists(path):
			fonts.append(load(path))
	for f in fonts:
		if f == null or f == symbols or not ("fallbacks" in f):
			continue
		# on reconstruit un tableau typé neuf (modifier la copie renvoyée par
		# la propriété ne suffit pas)
		var fb: Array[Font] = []
		for old in f.fallbacks:
			fb.append(old)
		if not fb.has(symbols):
			fb.append(symbols)
		f.set("fallbacks", fb)
		_patched_fonts.append(f)
