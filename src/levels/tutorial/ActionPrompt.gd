extends CanvasLayer
class_name ActionPrompt
# =============================================================================
#  ActionPrompt.gd — [TUTO 1.55] « Appuie sur… » AU MOMENT de l'action
# -----------------------------------------------------------------------------
#  Demande de l'équipe (21/11) : la pause du tuto ne doit plus arriver en
#  entrant dans un atelier (on lisait la consigne avant d'en avoir besoin),
#  mais AU MOMENT où il faut faire le geste : au bord du tremplin pour
#  sauter, juste avant de toucher le sol pour le NOSE, quand la prise est
#  dans l'axe pour le grappin… Le jeu se fige et montre LE bouton à
#  utiliser, selon l'appareil :
#   - PC : la touche (« Espace », « Flèche haut »…) ;
#   - manette : le bouton (« A », « RB »…) ;
#   - téléphone : le nom du bouton tactile ET un cercle jaune qui « respire »
#     autour de ce bouton à l'écran.
#  Choix de l'équipe :
#   - on repart en appuyant sur LE bon bouton, et l'action se fait tout de
#     suite (le pingouin, figé, voit l'appui : il saute, lance le grappin…) ;
#   - seulement à la 1re tentative de chaque atelier (TutorialCoach décide).
#
#  Comment on fige le jeu : Engine.time_scale = 0. Le jeu continue de
#  tourner, mais le temps ne passe plus (delta = 0) : Pinpouin ne bouge plus,
#  et pourtant il LIT les touches. C'est ce qui permet que l'appui sur le bon
#  bouton fasse l'action immédiatement. (Une vraie pause de l'arbre, comme
#  l'ancienne pause de lecture, cachait les boutons tactiles et faisait
#  perdre l'appui.) Le temps est TOUJOURS remis à 1 en sortant (fin de
#  l'invite, changement de scène, menu « Choisir un niveau »…).
#  Comme delta vaut 0, toutes les animations de ce fichier utilisent l'heure
#  réelle (Time.get_ticks_msec), et les Tween ignorent le time_scale.
#
#  Si l'option « Pause du tuto » est coupée (Settings.tutorial_pause), le jeu
#  ne se fige pas : l'invite s'affiche quand même, et s'en va quand le geste
#  est fait (ou au bout de UNFROZEN_TIMEOUT s).
#
#  Modes d'attente (`mode`) :
#   - "press"   : un appui sur l'action (cas normal) ;
#   - "release" : relâcher l'action (ex. lâcher le grappin au bon moment) ;
#   - "repress" : relâcher puis réappuyer (ex. relancer le grappin vers la
#                 prise suivante de la falaise).
#  Signal `done` quand le joueur a fait le geste demandé.
# =============================================================================

signal done

const UNFROZEN_TIMEOUT := 4.0   # s : invite sans gel (option coupée)
const MIN_SHOW_TIME := 0.15     # s réelles avant d'accepter le geste (évite un appui « déjà en route »)

# Bouton tactile (TouchControls._buttons[].id) de chaque action
const TOUCH_BUTTON := {"move_right": "right", "move_left": "left", "jump": "jump", "pump": "pump",
	"hook": "hook", "pull": "hook", "trix": "trix", "rotate_trigo": "rot_l", "rotate_horaire": "rot_r"}

# Sur téléphone, le nom du bouton tactile à toucher (TutorialSign donne une
# phrase pour le grappin, « le doigt sur l'endroit visé », qui se lisait mal
# après « TOUCHE » : vu en capture)
const TOUCH_KEY := {"hook": "GRAPPIN", "pull": "GLISSE-LE LOIN"}
const TOUCH_HEAD := {"pull": "GARDE LE DOIGT SUR GRAPPIN ET"}
const TOUCH_EXTRA := {"hook": "(ou touche directement l'endroit visé)"}

var action := ""                # action de l'InputMap attendue
var mode := "press"
var _text := ""                 # phrase sous la touche ({action} remplacés)
var _active := false
var _frozen := false
var _started_ms := 0
var _released_once := false     # mode "repress" : relâché au moins une fois

var _root: Control              # calque agrandi (UiScaler) : le panneau
var _veil: ColorRect            # voile léger : « le jeu est figé »
var _panel: PanelContainer
var _head: Label                # « APPUIE SUR » / « RELÂCHE » …
var _key: Label                 # LE bouton, en gros
var _sub: Label                 # ce que ça fait
var _ring_layer: CanvasLayer    # cercles autour des boutons tactiles (non agrandi)
var _ring: Control


func _init() -> void:
	layer = 47                               # au-dessus de la bulle du maître (45)
	process_mode = Node.PROCESS_MODE_ALWAYS  # suit le menu pause (voir _process)


func _ready() -> void:
	_veil = ColorRect.new()
	_veil.color = Color(0.02, 0.05, 0.15, 0.28)
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE   # ne bloque jamais les doigts
	add_child(_veil)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.1, 0.22, 0.92)
	style.border_color = Color(1, 0.94, 0.4)
	style.set_border_width_all(4)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)
	_head = _label(22, Color(1, 1, 1, 0.85))
	_key = _label(44, Color(1, 0.94, 0.4))
	_sub = _label(21, Color(1, 1, 1))
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for l in [_head, _key, _sub]:
		box.add_child(l)

	_root = UiScaler.apply(self)   # [RESPONSIVE 1.14] plus gros sur téléphone

	# Les cercles tactiles se dessinent dans le repère des boutons tactiles
	# (TouchControls n'est pas agrandi) : calque à part, au-dessus d'eux (50).
	_ring_layer = CanvasLayer.new()
	_ring_layer.layer = 51
	add_child(_ring_layer)
	_ring = Control.new()
	_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	_ring_layer.add_child(_ring)

	Settings.controls_changed.connect(func(_s): _refresh())
	_set_shown(false)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.14, 0.26))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Montre l'invite pour `p_action` (ex. "jump") et fige le jeu (si l'option
## est active). `p_text` : la phrase d'explication ({action} acceptés).
func show_prompt(p_action: String, p_text: String, p_mode := "press") -> void:
	action = p_action
	mode = p_mode
	_text = p_text
	_active = true
	_released_once = not Input.is_action_pressed(action)
	_started_ms = Time.get_ticks_msec()
	_frozen = Settings.tutorial_pause and not NetSession.in_race
	if _frozen:
		Engine.time_scale = 0.0
	_refresh()
	_set_shown(true)
	# petit « pop » du panneau (en temps réel : le jeu est figé)
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.8, 0.8)
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("maitre_clin", -6.0)


## Retire l'invite et rend le temps (sans émettre `done`) : atelier passé,
## chute, course finale…
func cancel() -> void:
	if not _active:
		return
	_active = false
	_unfreeze()
	_set_shown(false)


func is_active() -> bool:
	return _active


func _unfreeze() -> void:
	if _frozen:
		_frozen = false
		Engine.time_scale = 1.0


# Changement de scène pendant une invite : on rend TOUJOURS le temps.
func _exit_tree() -> void:
	if _frozen:
		Engine.time_scale = 1.0
		_frozen = false


func _set_shown(on: bool) -> void:
	_veil.visible = on and _frozen
	_panel.visible = on
	_ring.visible = on and Settings.controls == Settings.TOUCH


# Textes selon l'appareil (une manette branchée en cours de route change tout).
func _refresh() -> void:
	if _head == null:
		return
	var touch: bool = Settings.controls == Settings.TOUCH
	match mode:
		"release":
			_head.text = "RELÂCHE" if not touch else "LÈVE LE DOIGT DE"
		"repress":
			_head.text = "RELÂCHE PUIS RÉAPPUIE SUR" if not touch else "LÈVE LE DOIGT PUIS TOUCHE À NOUVEAU"
		_:
			_head.text = "APPUIE SUR" if not touch else TOUCH_HEAD.get(action, "TOUCHE")
	_key.text = TutorialSign.resolve_text("{%s}" % action)
	_sub.text = TutorialSign.resolve_text(_text)
	if touch:
		_key.text = TOUCH_KEY.get(action, _key.text)
		if mode == "press" and TOUCH_EXTRA.has(action):
			_sub.text += "\n" + TOUCH_EXTRA[action]
	_sub.visible = _sub.text != ""
	_sub.custom_minimum_size.x = 0.0
	_panel.reset_size()
	# largeur du texte d'explication : celle du panneau, sans dépasser 560 px
	var font := _sub.get_theme_font("font")
	var widest := 0.0
	for line in _sub.text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 21).x)
	_sub.custom_minimum_size.x = minf(widest + 4.0, 560.0)
	_place.call_deferred()


# Panneau au centre, sous la bulle du maître (vu en capture : à 17 % de la
# hauteur, il cachait la fin de la consigne) : Pinpouin reste visible (la
# caméra le garde vers le milieu) et les boutons tactiles (en bas) aussi.
# Si Pinpouin est à cet endroit de l'écran (en l'air, la caméra le place
# souvent haut), le panneau passe SOUS lui, ou au-dessus s'il n'y a pas la
# place : on doit toujours voir le pingouin pendant le gel.
func _place() -> void:
	if _panel == null:
		return
	_panel.reset_size()
	var vs: Vector2 = _root.size if _root != null else get_viewport().get_visible_rect().size
	var h: float = _panel.size.y
	var y := maxf(vs.y * 0.29, 200.0)
	var player = get_tree().get_first_node_in_group("player")
	if player != null:
		# position du pingouin à l'écran, dans le repère agrandi du panneau
		var sp: Vector2 = player.get_global_transform_with_canvas().origin / maxf(scale.x, 0.01)
		if y < sp.y + 50.0 and y + h > sp.y - 70.0:
			if sp.y + 80.0 + h < vs.y - 10.0:
				y = sp.y + 80.0          # sous Pinpouin
			else:
				y = maxf(10.0, sp.y - 90.0 - h)   # au-dessus de Pinpouin
	_panel.position = Vector2((vs.x - _panel.size.x) * 0.5, y)
	_panel.pivot_offset = _panel.size * 0.5


func _process(_delta: float) -> void:
	if not _active:
		return
	# Menu pause ouvert par-dessus : on le laisse faire (rien à vérifier)
	if get_tree().paused:
		return
	var t := (Time.get_ticks_msec() - _started_ms) / 1000.0
	# le gros bouton « respire » (heure réelle : delta vaut 0 quand c'est figé)
	var pulse := 0.5 + 0.5 * sin(t * 6.0)
	_key.modulate = Color(1, 1, 1, 0.75 + 0.25 * pulse)
	if _ring.visible:
		_ring.queue_redraw()
	if t < MIN_SHOW_TIME:
		if not Input.is_action_pressed(action):
			_released_once = true
		return
	var ok := false
	var pressed := Input.is_action_pressed(action)
	match mode:
		"release":
			ok = not pressed
		"repress":
			if not pressed:
				_released_once = true
			ok = _released_once and pressed
		_:
			# un nouvel appui (ou une touche qu'on vient d'enfoncer)
			ok = Input.is_action_just_pressed(action) or (pressed and _released_once)
			if not pressed:
				_released_once = true
	if not ok and not _frozen and t >= UNFROZEN_TIMEOUT:
		cancel()   # option coupée : l'invite ne reste pas indéfiniment
		return
	if ok:
		_active = false
		_unfreeze()
		_set_shown(false)
		emit_signal("done")


# Cercle jaune qui « respire » autour du bouton tactile à utiliser (positions
# réelles lues dans TouchControls, comme les cercles d'aide du mode enfant).
func _draw_ring() -> void:
	var tc = get_node_or_null("/root/TouchControls")
	if tc == null or not TOUCH_BUTTON.has(action):
		return
	var b: Dictionary = tc._get_button(TOUCH_BUTTON[action])
	if b.is_empty():
		return
	var t := (Time.get_ticks_msec() - _started_ms) / 1000.0
	var pulse := 0.5 + 0.5 * sin(t * 6.0)
	var col := Color(1, 0.94, 0.4, 0.5 + 0.5 * pulse)
	var c: Vector2 = tc._pos(b)
	var r: float = b.r + 10.0 + 14.0 * pulse
	_ring.draw_arc(c, r, 0.0, TAU, 48, col, 7.0, true)
	_ring.draw_arc(c, r + 16.0, 0.0, TAU, 48, Color(col, col.a * 0.4), 4.0, true)
