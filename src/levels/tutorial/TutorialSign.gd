extends Node2D
class_name TutorialSign
# =============================================================================
#  TutorialSign.gd — [MAP BATEAU] panneau d'explication posé dans le niveau
# -----------------------------------------------------------------------------
#  - Le texte peut contenir des marqueurs {action} (ex. "{jump}") remplacés par
#    la touche RÉELLE de l'action, lue dans l'InputMap du projet : si quelqu'un
#    change une touche dans les réglages du projet, le panneau suit tout seul.
#  - Le texte s'adapte au mode de contrôle actif (Settings.controls) :
#      clavier/souris -> noms des touches (ex. "Z ou Flèche haut")
#      manette        -> noms des boutons (ex. "A", "LB")
#      tactile        -> noms des boutons à l'écran (ex. "SAUT")
#    et se met à jour en direct si le joueur change de périphérique.
#  - Aucun nouvel asset : panneau = PanelContainer + Label, dessinés en code.
#  - Rappel à l'écran : le pingouin passe vite devant les panneaux ; quand il
#    franchit un panneau, son texte est aussi affiché en haut de l'écran
#    pendant hud_duration secondes (bandeau partagé, un seul à la fois).
#  [AIDE 1.7] Pause lecture : si l'option "Pause pour lire les panneaux du
#  tuto" est active (Settings.tutorial_pause, activée par défaut), le jeu se
#  met EN PAUSE quand le pingouin arrive au panneau, et le texte s'affiche en
#  grand au centre (ReadingPause.gd) jusqu'à ce que le joueur appuie sur une
#  touche. Pas de pause en multijoueur.
#  resolve_text() est maintenant "static" : RaceManager s'en sert pour la
#  carte d'aide de début de niveau (mêmes noms de touches que les panneaux).
# =============================================================================

## Texte du panneau, avec des marqueurs {action} (jump, hook, pump...).
@export_multiline var sign_text: String = ""

## Durée (s) d'affichage du rappel en haut de l'écran.
@export var hud_duration: float = 6.0

var _label: Label
var _shown_on_hud := false
static var _hud_label: Label = null   # bandeau partagé par tous les panneaux
static var _hud_tween: Tween = null

# Noms des boutons de manette (disposition Xbox, index Godot 4)
const JOY_BUTTON_NAMES = {0: "A", 1: "B", 2: "X", 3: "Y", 4: "Back", 6: "Start", 9: "LB", 10: "RB",
	11: "Croix haut", 12: "Croix bas", 13: "Croix gauche", 14: "Croix droite"}
const JOY_AXIS_NAMES = {4: "LT", 5: "RT"}
# Noms des boutons tactiles (cf. TouchControls.gd)
const TOUCH_NAMES = {"move_right": "▶", "move_left": "◀", "jump": "SAUT", "pump": "PUMP",
	"hook": "GRAPPIN", "pull": "GRAPPIN en glissant le doigt loin", "trix": "FIGURE", "rotate_trigo": "↺", "rotate_horaire": "↻"}


func _ready() -> void:
	z_index = 40  # au-dessus du décor
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.1, 0.22, 0.78)
	style.border_color = Color(1, 1, 1, 0.85)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(_label)
	add_child(panel)
	_refresh()
	# centre le panneau sur le point du niveau une fois sa taille connue
	panel.resized.connect(func(): panel.position = Vector2(-panel.size.x * 0.5, -panel.size.y))
	Settings.controls_changed.connect(func(_s): _refresh())


func _process(_delta: float) -> void:
	if _shown_on_hud:
		return
	var player = get_tree().get_first_node_in_group("player")
	if player != null and player.global_position.x >= global_position.x - 250.0:
		_shown_on_hud = true
		# [AIDE 1.7] pause pour lire (désactivable dans les Options) : le texte
		# s'affiche en grand au centre, jeu en pause ; le rappel en haut de
		# l'écran n'apparaît qu'à la reprise (sinon le texte serait en double).
		var reading = ReadingPause.open(get_tree(), "", _label.text) if Settings.tutorial_pause else null
		if reading != null:
			modulate.a = 0.0   # le panneau du décor disparaît tout de suite (le jeu est en pause)
			if _hud_label != null and is_instance_valid(_hud_label):
				_hud_label.get_parent().modulate.a = 0.0   # l'ancien rappel aussi
			var txt := _label.text
			reading.closed.connect(func(): _show_on_hud(txt))
			return
		_show_on_hud(_label.text)
		# le texte est maintenant en haut de l'écran : on efface le panneau du
		# décor pour ne pas afficher deux fois la même chose
		create_tween().tween_property(self, "modulate:a", 0.0, 0.4)


# Affiche le texte dans un bandeau en haut de l'écran (créé à la demande).
func _show_on_hud(text: String) -> void:
	if _hud_label == null or not is_instance_valid(_hud_label):
		var layer := CanvasLayer.new()
		layer.layer = 40
		get_tree().current_scene.add_child(layer)
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.1, 0.22, 0.85)
		style.border_color = Color(1, 0.95, 0.4, 0.9)
		style.set_border_width_all(3)
		style.set_corner_radius_all(12)
		style.set_content_margin_all(12)
		panel.add_theme_stylebox_override("panel", style)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud_label = Label.new()
		_hud_label.add_theme_font_size_override("font_size", 24)
		_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(_hud_label)
		layer.add_child(panel)
		# centré en haut de l'écran, quelle que soit sa taille
		panel.resized.connect(func():
			var vw := panel.get_viewport_rect().size.x
			panel.position = Vector2((vw - panel.size.x) * 0.5, 70))
	var hud_panel: Control = _hud_label.get_parent()
	_hud_label.text = text
	_hud_label.reset_size()
	hud_panel.reset_size()  # le bandeau reprend la taille du nouveau texte (plus grand OU plus petit)
	hud_panel.modulate.a = 1.0
	if _hud_tween != null and _hud_tween.is_valid():
		_hud_tween.kill()
	_hud_tween = hud_panel.create_tween()
	_hud_tween.tween_interval(hud_duration)
	_hud_tween.tween_property(hud_panel, "modulate:a", 0.0, 0.6)


func _refresh() -> void:
	var txt := resolve_text(sign_text)
	_label.text = txt
	# le bandeau suit aussi un changement de périphérique
	if _shown_on_hud and _hud_label != null and is_instance_valid(_hud_label) and _hud_label.get_parent().modulate.a > 0.0:
		_hud_label.text = txt


## [AIDE 1.7] Remplace les marqueurs {action} par les vraies touches (static :
## utilisable sans panneau, ex. TutorialSign.resolve_text("Sauter : {jump}")).
static func resolve_text(text: String) -> String:
	var txt := text
	var regex := RegEx.new()
	regex.compile("\\{([a-z_]+)\\}")
	for m in regex.search_all(text):
		txt = txt.replace(m.get_string(), _binding_text(m.get_string(1)))
	return txt


# Texte de la (ou des) touche(s) associée(s) à une action, selon le mode actif.
static func _binding_text(action: String) -> String:
	if Settings.controls == Settings.TOUCH:
		return TOUCH_NAMES.get(action, action)
	if not InputMap.has_action(action):
		return action
	var names := []
	for ev in InputMap.action_get_events(action):
		if Settings.controls == Settings.GAMEPAD:
			if ev is InputEventJoypadButton and JOY_BUTTON_NAMES.has(ev.button_index):
				names.append(JOY_BUTTON_NAMES[ev.button_index])
			elif ev is InputEventJoypadMotion and JOY_AXIS_NAMES.has(ev.axis):
				names.append(JOY_AXIS_NAMES[ev.axis])
		else:
			if ev is InputEventKey:
				var code: int = ev.keycode if ev.keycode != 0 else ev.physical_keycode
				names.append(_key_name(code))
			elif ev is InputEventMouseButton:
				names.append({MOUSE_BUTTON_LEFT: "Clic gauche", MOUSE_BUTTON_RIGHT: "Clic droit"}.get(ev.button_index, "Souris"))
	if names.is_empty():
		# action sans touche pour ce périphérique (ex. "trix" n'a pas de bouton manette)
		return "(aucun bouton manette)" if Settings.controls == Settings.GAMEPAD else "(aucune touche)"
	# au plus 2 propositions pour garder le panneau lisible
	return " ou ".join(PackedStringArray(names.slice(0, 2)))


static func _key_name(code: int) -> String:
	match code:
		KEY_UP: return "Flèche haut"
		KEY_DOWN: return "Flèche bas"
		KEY_LEFT: return "Flèche gauche"
		KEY_RIGHT: return "Flèche droite"
		KEY_SPACE: return "Espace"
		KEY_SHIFT: return "Maj"
	return OS.get_keycode_string(code)
