extends CanvasLayer
# =============================================================================
#  TouchControls.gd — [MOBILE] boutons tactiles à l'écran (autoload)
# -----------------------------------------------------------------------------
#  - Chargé en autoload : présent dans TOUS les niveaux sans toucher aux scènes.
#  - Visible seulement si : schéma de contrôle = TOUCH (cf. Settings.gd), un
#    pingouin est présent (on est dans un niveau, pas dans un menu) et le jeu
#    n'est pas en pause.
#  - Multi-touch : chaque doigt est suivi par son index, on peut glisser à
#    droite tout en sautant / grappinant.
#  - Les boutons "appuient" directement sur les actions existantes de
#    l'InputMap (move_left, jump, hook...) via Input.action_press(), donc
#    TOUT le code du joueur et des états reste inchangé.
#  - Aucun nouvel asset : les boutons sont dessinés en code (_draw).
#
#  Disposition (écran de référence 1024 x 720, paysage) :
#    gauche : ◀ ▶ (avancer / reculer), au-dessus ↺ ↻ (rotation en l'air)
#    droite : SAUT (gros), GRAPPIN, TIRER, PUMP, FIGURE ; pause en haut à droite
#
#  GRAPPIN = mini-joystick :
#    - simple tap / appui  -> tir dans la direction par défaut (avant-haut)
#    - appui + glissé      -> tir dans la direction du glissé
#    Pour laisser le temps de glisser, le tir part quand le doigt a glissé de
#    AIM_DEADZONE px, ou au plus tard après AIM_DELAY secondes.
#    Maintenir le doigt = rester accroché (comme la touche Espace).
# =============================================================================

const AIM_DEADZONE = 28.0   # px de glissé avant de considérer qu'on vise
const AIM_DELAY = 0.12      # s : délai max avant de tirer sans visée
const BUTTON_ALPHA = 0.45   # transparence des boutons au repos

# Description des boutons : position (repère 1024x720), rayon, action, libellé.
# "slide" = on peut glisser le doigt d'un bouton de ce groupe à l'autre (◀ ▶).
var _buttons := [
	{"id": "left",   "pos": Vector2(100, 610), "r": 62, "action": "move_left",      "label": "",        "icon": "left",  "slide": true},
	{"id": "right",  "pos": Vector2(250, 610), "r": 62, "action": "move_right",     "label": "",        "icon": "right", "slide": true},
	{"id": "rot_l",  "pos": Vector2(100, 465), "r": 46, "action": "rotate_trigo",   "label": "",        "icon": "rot_l", "slide": true},
	{"id": "rot_r",  "pos": Vector2(250, 465), "r": 46, "action": "rotate_horaire", "label": "",        "icon": "rot_r", "slide": true},
	{"id": "jump",   "pos": Vector2(925, 610), "r": 72, "action": "jump",           "label": "SAUT",    "icon": "",      "slide": false},
	{"id": "hook",   "pos": Vector2(770, 640), "r": 62, "action": "hook",           "label": "GRAPPIN", "icon": "",      "slide": false},
	{"id": "pull",   "pos": Vector2(780, 505), "r": 48, "action": "pull",           "label": "TIRER",   "icon": "",      "slide": false},
	{"id": "pump",   "pos": Vector2(925, 455), "r": 52, "action": "pump",           "label": "PUMP",    "icon": "",      "slide": false},
	{"id": "trix",   "pos": Vector2(635, 655), "r": 42, "action": "trix",           "label": "FIGURE",  "icon": "",      "slide": false},
	{"id": "pause",  "pos": Vector2(980, 44),  "r": 30, "action": "ui_cancel",      "label": "II",      "icon": "",      "slide": false},
]

var _fingers := {}          # index du doigt -> id du bouton tenu
var _pressed_count := {}    # id du bouton -> nb de doigts dessus
var _hook_finger := -1      # doigt qui tient le bouton GRAPPIN
var _hook_origin := Vector2.ZERO
var _hook_time := 0.0
var _hook_fired := false
var _aim_vec := Vector2.ZERO  # pour dessiner la flèche de visée
var _canvas: Control          # nœud qui dessine tous les boutons
var _font: Font


func _ready() -> void:
	layer = 50                                  # au-dessus du jeu et de l'UI
	process_mode = Node.PROCESS_MODE_ALWAYS      # pour se cacher pendant la pause
	_font = ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE  # ne bloque jamais les menus
	_canvas.draw.connect(_draw_buttons)
	add_child(_canvas)
	Settings.controls_changed.connect(func(_s): _release_all())
	visible = false


# --- Visibilité ---------------------------------------------------------------
func _should_show() -> bool:
	return Settings.controls == Settings.TOUCH \
		and not get_tree().paused \
		and get_tree().get_first_node_in_group("player") != null


func _process(delta: float) -> void:
	var show := _should_show()
	if show != visible:
		visible = show
		if not show:
			_release_all()  # on ne laisse jamais une action "coincée"
	if not visible:
		return

	# GRAPPIN : tir différé si le doigt n'a pas (encore) glissé
	if _hook_finger != -1 and not _hook_fired:
		_hook_time += delta
		if _hook_time >= AIM_DELAY:
			_fire_hook(Vector2.ZERO)
	_canvas.queue_redraw()


# --- Entrées tactiles ---------------------------------------------------------
func _input(event: InputEvent) -> void:
	# Le tout premier toucher doit déjà fonctionner : Godot appelle _input()
	# des autoloads du DERNIER au premier, donc on reçoit l'événement AVANT
	# Settings -> on bascule nous-mêmes en mode TOUCH, puis on teste
	# _should_show() (et pas `visible`, mis à jour seulement dans _process).
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		Settings.controls = Settings.TOUCH
	if not _should_show():
		return
	if event is InputEventScreenTouch:
		var pos := _to_reference(event.position)
		if event.pressed:
			var b = _button_at(pos)
			if b != null:
				_finger_down(event.index, b, pos)
				get_viewport().set_input_as_handled()
		elif _fingers.has(event.index):
			_finger_up(event.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _fingers.has(event.index):
		var pos := _to_reference(event.position)
		var held = _get_button(_fingers[event.index])
		if event.index == _hook_finger:
			_update_hook_aim(pos)
		elif held.slide:
			# glisser d'un bouton à l'autre (ex. de ◀ à ▶) sans relever le doigt
			var b = _button_at(pos)
			if b != null and b.slide and b.id != held.id:
				_finger_up(event.index)
				_finger_down(event.index, b, pos)
		get_viewport().set_input_as_handled()


func _finger_down(index: int, b: Dictionary, pos: Vector2) -> void:
	_fingers[index] = b.id
	_pressed_count[b.id] = _pressed_count.get(b.id, 0) + 1
	if b.id == "pause":
		# Le menu pause écoute "ui_cancel" : on simule l'appui sur Échap.
		var ev := InputEventAction.new()
		ev.action = "ui_cancel"
		ev.pressed = true
		Input.parse_input_event(ev)
	elif b.id == "hook":
		_hook_finger = index
		_hook_origin = pos
		_hook_time = 0.0
		_hook_fired = false
		_aim_vec = Vector2.ZERO
	else:
		Input.action_press(b.action)


func _finger_up(index: int) -> void:
	var id = _fingers[index]
	_fingers.erase(index)
	_pressed_count[id] = max(0, _pressed_count.get(id, 1) - 1)
	var b = _get_button(id)
	if id == "hook":
		if not _hook_fired:
			_fire_hook(Vector2.ZERO)  # tap très court : on tire quand même
		_hook_finger = -1
		_aim_vec = Vector2.ZERO
		# relâché à la frame suivante, pour que "just_pressed" ait été vu
		_release_hook_deferred()
	elif id != "pause" and _pressed_count[id] == 0:
		Input.action_release(b.action)


func _release_hook_deferred() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if _hook_finger == -1:
		Input.action_release("hook")
		Settings.touch_aim = Vector2.ZERO


func _update_hook_aim(pos: Vector2) -> void:
	var d := pos - _hook_origin
	_aim_vec = d
	if d.length() >= AIM_DEADZONE:
		# Visée : la direction du glissé est transmise au joueur
		# (Player._get_aim_direction() lit Settings.touch_aim en mode TOUCH).
		Settings.touch_aim = d.normalized()
		if not _hook_fired:
			_fire_hook(d.normalized())


func _fire_hook(aim: Vector2) -> void:
	_hook_fired = true
	Settings.touch_aim = aim
	Input.action_press("hook")


func _release_all() -> void:
	for b in _buttons:
		if b.id != "pause" and InputMap.has_action(b.action):
			Input.action_release(b.action)
	_fingers.clear()
	_pressed_count.clear()
	_hook_finger = -1
	_aim_vec = Vector2.ZERO
	Settings.touch_aim = Vector2.ZERO


# --- Outils -------------------------------------------------------------------
# Position du doigt dans le repère 1024x720 du jeu.
# NB : en Godot 4, le Viewport convertit DÉJÀ les positions des événements
# tactiles dans ce repère (stretch "canvas_items") avant _input() : quelle que
# soit la résolution du téléphone, on n'a donc rien à recalculer ici.
func _to_reference(screen_pos: Vector2) -> Vector2:
	return screen_pos


# Position réelle d'un bouton à l'écran : les positions de _buttons sont
# données pour un écran 1024x720 ; sur un écran plus large / plus haut
# (téléphone 20:9...), les boutons de droite restent collés au bord droit et
# ceux du bas au bord bas.
func _pos(b: Dictionary) -> Vector2:
	var vis: Vector2 = get_viewport().get_visible_rect().size
	var p: Vector2 = b.pos
	if p.x > 512.0:
		p.x += vis.x - 1024.0
	if p.y > 360.0:
		p.y += vis.y - 720.0
	return p


func _button_at(pos: Vector2):
	var best = null
	var best_d := INF
	for b in _buttons:
		var d: float = pos.distance_to(_pos(b))
		if d <= b.r * 1.25 and d < best_d:  # zone de toucher un peu plus large que le dessin
			best = b
			best_d = d
	return best


func _get_button(id: String) -> Dictionary:
	for b in _buttons:
		if b.id == id:
			return b
	return {}


# --- Dessin -------------------------------------------------------------------
func _draw_buttons() -> void:
	for b in _buttons:
		var pressed: bool = _pressed_count.get(b.id, 0) > 0
		var a := 0.85 if pressed else BUTTON_ALPHA
		var fill := Color(0.08, 0.13, 0.28, a * 0.7)
		var line := Color(1, 1, 1, a)
		var c := _pos(b)
		_canvas.draw_circle(c, b.r, fill)
		_canvas.draw_arc(c, b.r, 0, TAU, 48, line, 3.0, true)
		match b.icon:
			"left":
				_draw_triangle(c, -1, b.r * 0.42, line)
			"right":
				_draw_triangle(c, 1, b.r * 0.42, line)
			"rot_l":
				_draw_rotation(c, b.r * 0.45, -1, line)
			"rot_r":
				_draw_rotation(c, b.r * 0.45, 1, line)
			_:
				var size := 30 if b.id == "pause" else (22 if b.r >= 60 else 17)
				var w := _font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
				_canvas.draw_string(_font, c + Vector2(-w * 0.5, size * 0.35), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, line)
	# flèche de visée du grappin pendant le glissé
	if _hook_finger != -1 and _aim_vec.length() >= AIM_DEADZONE:
		var hook_pos: Vector2 = _pos(_get_button("hook"))
		var tip := hook_pos + _aim_vec.normalized() * 110.0
		_canvas.draw_line(hook_pos, tip, Color(1, 0.95, 0.4, 0.9), 5.0, true)
		_canvas.draw_circle(tip, 9.0, Color(1, 0.95, 0.4, 0.9))


func _draw_triangle(c: Vector2, dir: int, s: float, col: Color) -> void:
	_canvas.draw_colored_polygon(PackedVector2Array([
		c + Vector2(dir * s, 0), c + Vector2(-dir * s * 0.6, -s), c + Vector2(-dir * s * 0.6, s)]), col)


func _draw_rotation(c: Vector2, r: float, dir: int, col: Color) -> void:
	# arc de cercle + pointe de flèche (sens horaire ou trigo)
	var start := -PI * 0.75
	var end := PI * 0.75
	_canvas.draw_arc(c, r, start, end, 24, col, 4.0, true)
	var ang := end if dir > 0 else start
	var p := c + Vector2(cos(ang), sin(ang)) * r
	var tangent := Vector2(-sin(ang), cos(ang)) * dir
	var n := Vector2(cos(ang), sin(ang))
	_canvas.draw_colored_polygon(PackedVector2Array([p + tangent * 12, p + n * 8 - tangent * 4, p - n * 8 - tangent * 4]), col)
