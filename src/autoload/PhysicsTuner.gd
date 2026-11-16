extends CanvasLayer
# =============================================================================
#  PhysicsTuner.gd — [PHYSIQUE 1.10] panneau de réglage de la glisse, en jeu
# -----------------------------------------------------------------------------
#  Demande de l'équipe : pouvoir recalibrer les vitesses (sol, air, pump) en
#  jouant. Autoload (présent partout), invisible par défaut.
#   - Ouvrir / fermer : touche F2, ou bouton ⚙ en haut à gauche en mode
#     tactile (à activer dans Options : « Panneau de réglage physique ») ;
#   - un curseur par réglage : appliqué TOUT DE SUITE au pingouin, et
#     mémorisé dans user://pinpouin.cfg (section "physique") pour les
#     prochaines parties ;
#   - courbe de vitesse des 10 dernières secondes, avec les repères « max
#     pump » (orange) et « max sol » (rouge) ;
#   - « Par défaut » remet les valeurs d'origine (celles de Player.gd) ;
#   - « Copier » met tous les réglages en texte dans le presse-papiers : à
#     coller dans un message pour partager les bonnes valeurs avec l'équipe
#     (ou avec Claude, pour les mettre par défaut dans le jeu).
#  Le pingouin lit ces réglages à son apparition (Player._ready -> apply_to).
#  NB : les fantômes enregistrés avec d'autres réglages restent rejouables
#  (ils rejouent des positions), mais ne sont plus comparables en temps.
# =============================================================================

const CONFIG_PATH = "user://pinpouin.cfg"
const SECTION = "physique"

# [nom de la variable de Player.gd, libellé, min, max, pas]
const PARAMS = [
	["running_speed", "Vitesse en courant (avancer)", 200.0, 1200.0, 10.0],
	["pump_accel", "Pump : accélération (plat)", 0.0, 2000.0, 10.0],
	["pump_slope_bonus", "Pump : bonus en descente", 0.0, 4.0, 0.05],
	["pump_uphill_factor", "Pump : efficacité en montée", 0.0, 1.0, 0.05],
	["pump_impulse", "Pump : impulsion à l'appui", 0.0, 400.0, 5.0],
	["pump_max_speed", "Vitesse max du pump", 500.0, 3000.0, 25.0],
	["ground_max_speed", "Vitesse max au sol", 800.0, 3000.0, 25.0],
	["air_max_speed", "Vitesse max en l'air", 800.0, 3000.0, 25.0],
	["over_speed_drag", "Frottement au-dessus du max", 0.0, 3.0, 0.05],
	["landing_speed_keep", "Vitesse gardée à l'atterrissage", 0.0, 1.0, 0.05],
	["air_pump_gravity", "Gravité en pumpant en l'air (×)", 1.0, 4.0, 0.1],   # [PUMP EN L'AIR 1.27]
	["gravity", "Gravité", 300.0, 2000.0, 10.0],
	["speed_trail_from", "Traînée de vitesse à partir de", 0.0, 3000.0, 50.0],
]

var values := {}        # réglages modifiés par le joueur (nom -> valeur)
var _defaults := {}     # valeurs d'origine lues sur le premier pingouin
var _panel: PanelContainer
var _sliders := {}
var _value_labels := {}
var _speed_label: Label
var _graph: Line2D
var _graph_box: Control
var _ref_lines := {}
var _history: PackedFloat32Array = PackedFloat32Array()
var _gear: Button
const GRAPH_SIZE = Vector2(300, 90)
const GRAPH_MAX = 3000.0
const HISTORY_LEN = 600   # 10 s à 60 images/s


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK and cfg.has_section(SECTION):
		for key in cfg.get_section_keys(SECTION):
			values[key] = float(cfg.get_value(SECTION, key))
	_build()
	_panel.visible = false


## Appelé par Player._ready() : applique les réglages mémorisés.
func apply_to(player: Node) -> void:
	if _defaults.is_empty():
		for p in PARAMS:
			_defaults[p[0]] = float(player.get(p[0]))
	for key in values:
		player.set(key, values[key])
	_refresh_sliders(player)


## [GRAPPIN TACTILE 1.11] Vrai si ce point de l'écran est sur le panneau ou
## sur le bouton ⚙ : un toucher à cet endroit ne doit pas lancer le grappin.
func covers(screen_pos: Vector2) -> bool:
	return (_panel.visible and _panel.get_global_rect().has_point(screen_pos)) \
		or (_gear.visible and _gear.get_global_rect().has_point(screen_pos))


func _player():
	return get_tree().get_first_node_in_group("player")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		toggle()


func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_refresh_sliders(_player())


func _process(_delta: float) -> void:
	var player = _player()
	var in_level: bool = player != null and is_instance_valid(player)
	_gear.visible = in_level and Settings.controls == Settings.TOUCH and Settings.get("physics_panel") == true
	if not in_level:
		if _panel.visible:
			_panel.visible = false
		return
	if not _panel.visible:
		return
	# à droite de l'écran : le pingouin, lui, est à gauche quand il va vite
	# (caméra « regard vers l'avant »)
	_panel.position = Vector2(get_viewport().get_visible_rect().size.x - _panel.size.x - 12, 60)
	var speed: float = player._velocity.length()
	_history.append(speed)
	if _history.size() > HISTORY_LEN:
		_history = _history.slice(_history.size() - HISTORY_LEN)
	_speed_label.text = "Vitesse : %d px/s   (%s)" % [speed, "au sol" if player.is_on_ground else "en l'air"]
	var pts := PackedVector2Array()
	for i in _history.size():
		pts.append(Vector2(GRAPH_SIZE.x * i / float(HISTORY_LEN), GRAPH_SIZE.y * (1.0 - minf(_history[i], GRAPH_MAX) / GRAPH_MAX)))
	_graph.points = pts
	for key in _ref_lines:
		var y: float = GRAPH_SIZE.y * (1.0 - minf(float(player.get(key)), GRAPH_MAX) / GRAPH_MAX)
		_ref_lines[key].points = PackedVector2Array([Vector2(0, y), Vector2(GRAPH_SIZE.x, y)])


func _on_slider(value: float, key: String) -> void:
	values[key] = value
	_value_labels[key].text = _fmt(value)
	var player = _player()
	if player != null and is_instance_valid(player):
		player.set(key, value)
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value(SECTION, key, value)
	cfg.save(CONFIG_PATH)


func _reset_defaults() -> void:
	values.clear()
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	if cfg.has_section(SECTION):
		cfg.erase_section(SECTION)
	cfg.save(CONFIG_PATH)
	var player = _player()
	if player != null and is_instance_valid(player):
		for key in _defaults:
			player.set(key, _defaults[key])
	_refresh_sliders(player)


func _copy() -> void:
	var player = _player()
	var lines := PackedStringArray(["Réglages physique Pinpouin v%s :" % ProjectSettings.get_setting("application/config/version", "?")])
	for p in PARAMS:
		var v = player.get(p[0]) if player != null and is_instance_valid(player) else values.get(p[0], _defaults.get(p[0], 0.0))
		lines.append("%s = %s" % [p[0], _fmt(float(v))])
	DisplayServer.clipboard_set("\n".join(lines))
	_speed_label.text = "Réglages copiés dans le presse-papiers !"


func _refresh_sliders(player) -> void:
	for p in PARAMS:
		var key: String = p[0]
		var v: float = values.get(key, _defaults.get(key, p[2]))
		if player != null and is_instance_valid(player):
			v = float(player.get(key))
		_sliders[key].set_value_no_signal(v)
		_value_labels[key].text = _fmt(v)


func _fmt(v: float) -> String:
	return str(int(v)) if absf(v) >= 10.0 else "%.2f" % v


# --- Construction de l'interface (en code, aucun asset) ---------------------------
func _build() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.18, 0.78)
	style.border_color = Color(1, 0.94, 0.4)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position = Vector2(12, 60)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_panel.add_child(box)
	var title := _label("RÉGLAGES PHYSIQUE  (F2 pour fermer)", 17, Color(1, 0.94, 0.4))
	box.add_child(title)
	for p in PARAMS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_label := _label(p[1], 13, Color(1, 1, 1))
		name_label.custom_minimum_size = Vector2(200, 0)
		var slider := HSlider.new()
		slider.min_value = p[2]
		slider.max_value = p[3]
		slider.step = p[4]
		slider.custom_minimum_size = Vector2(150, 22)
		slider.focus_mode = Control.FOCUS_NONE   # les flèches restent au pingouin
		slider.value_changed.connect(_on_slider.bind(p[0]))
		var value_label := _label("", 13, Color(0.75, 0.95, 1))
		value_label.custom_minimum_size = Vector2(46, 0)
		row.add_child(name_label)
		row.add_child(slider)
		row.add_child(value_label)
		box.add_child(row)
		_sliders[p[0]] = slider
		_value_labels[p[0]] = value_label
	_speed_label = _label("", 14, Color(1, 1, 1))
	box.add_child(_speed_label)
	_graph_box = Control.new()
	_graph_box.custom_minimum_size = GRAPH_SIZE
	box.add_child(_graph_box)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.35)
	bg.size = GRAPH_SIZE
	_graph_box.add_child(bg)
	for pair in [["pump_max_speed", Color(1, 0.6, 0.2, 0.8)], ["ground_max_speed", Color(1, 0.3, 0.3, 0.8)]]:
		var l := Line2D.new()
		l.width = 1.0
		l.default_color = pair[1]
		_graph_box.add_child(l)
		_ref_lines[pair[0]] = l
	_graph = Line2D.new()
	_graph.width = 2.0
	_graph.default_color = Color(0.6, 1, 0.6)
	_graph_box.add_child(_graph)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	for b in [["Par défaut", _reset_defaults], ["Copier", _copy], ["Fermer", toggle]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(b[1])
		buttons.add_child(btn)
	# bouton ⚙ pour le tactile (pas de touche F2 sur téléphone)
	_gear = Button.new()
	_gear.text = "⚙"
	_gear.add_theme_font_size_override("font_size", 26)
	_gear.position = Vector2(12, 120)
	_gear.custom_minimum_size = Vector2(52, 52)
	_gear.focus_mode = Control.FOCUS_NONE
	_gear.pressed.connect(toggle)
	_gear.visible = false
	add_child(_gear)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
