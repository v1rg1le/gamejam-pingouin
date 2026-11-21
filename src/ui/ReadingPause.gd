extends CanvasLayer
class_name ReadingPause
# =============================================================================
#  ReadingPause.gd — [AIDE 1.7] « pause lecture » : un texte au centre de
#  l'écran, le jeu en pause, on repart en appuyant sur n'importe quelle touche
# -----------------------------------------------------------------------------
#  Demande de l'équipe (14/11) : dans le tuto, mettre le jeu en pause pour que
#  le joueur ait le temps de lire ; et une aide en début de niveau, que l'on
#  peut désactiver (écran Options).
#  Utilisé par :
#   - TutorialSign.gd : à chaque panneau du tuto (si Settings.tutorial_pause) ;
#   - RaceManager.gd  : carte d'aide au départ d'un niveau (si Settings.help_on_start).
#  Usage : ReadingPause.open(get_tree(), "titre", "texte")
#  - met le jeu en pause (le chrono s'arrête aussi : ça ne coûte pas de temps) ;
#  - reprise : touche clavier, bouton manette, clic ou toucher. Les 0,4 s
#    suivant l'ouverture sont ignorées, pour ne pas fermer le texte par
#    accident avec une touche déjà enfoncée ;
#  - les touches maintenues (ex. avancer) restent maintenues à la reprise ;
#  - jamais en multijoueur (les autres continuent de courir).
#  Aucun nouvel asset : panneau dessiné en code, mêmes couleurs que le HUD.
# =============================================================================

signal closed

const MIN_DISPLAY_TIME = 0.4   # s pendant lesquelles on ignore les appuis

static var _current = null     # une seule pause lecture à la fois

var _opened_at: float = 0.0
var _was_paused: bool = false


## Ouvre une pause lecture (ou remplace le texte de celle déjà ouverte).
## Renvoie le nœud (signal `closed` à la fermeture), ou null en multijoueur.
static func open(tree: SceneTree, title: String, text: String):
	if NetSession.in_race:
		return null
	if _current != null and is_instance_valid(_current):
		_current._set_text(title, text)
		return _current
	var node = load("res://src/ui/ReadingPause.gd").new()
	tree.root.add_child(node)
	node._set_text(title, text)
	_current = node
	return node


static func is_open() -> bool:
	return _current != null and is_instance_valid(_current)


var _title: Label
var _text: Label
var _hint: Label
var _panel: PanelContainer      # [INTERFACE 1.44] pour vérifier qu'il tient à l'écran


func _init() -> void:
	layer = 70                              # au-dessus du HUD et du menu pause
	process_mode = Node.PROCESS_MODE_ALWAYS # doit vivre pendant la pause
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.15, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	_panel = panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.1, 0.22, 0.94)
	style.border_color = Color(1, 0.94, 0.4)
	style.set_border_width_all(4)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	_title = _label(30, Color(1, 0.94, 0.4))
	_text = _label(25, Color(1, 1, 1))
	_hint = _label(17, Color(1, 1, 1, 0.7))
	box.add_child(_title)
	box.add_child(_text)
	box.add_child(_hint)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _ready() -> void:
	UiScaler.apply(self)   # [RESPONSIVE 1.14] texte plus gros sur téléphone
	_fit_to_screen()
	_was_paused = get_tree().paused
	get_tree().paused = true
	_opened_at = Time.get_ticks_msec() / 1000.0


## [INTERFACE 1.44] L'interface est plus grande sur téléphone (×1,15) : une
## carte d'aide longue (Sans fin, mode Score…) pourrait dépasser de l'écran.
## On garde l'agrandissement voulu, mais jamais plus que ce qui tient (94 %).
func _fit_to_screen() -> void:
	if _panel == null or not is_inside_tree():
		return
	var need: Vector2 = _panel.get_combined_minimum_size()
	var avail: Vector2 = get_viewport().get_visible_rect().size * 0.94
	if need.x <= 0.0 or need.y <= 0.0:
		return
	var s: float = minf(Settings.hud_scale(), minf(avail.x / need.x, avail.y / need.y))
	UiScaler.apply(self, maxf(s, 0.5))


func _set_text(title: String, text: String) -> void:
	_title.text = title
	_title.visible = title != ""
	_text.text = text
	var how := "Touche l'écran" if Settings.controls == Settings.TOUCH else ("Appuie sur un bouton" if Settings.controls == Settings.GAMEPAD else "Appuie sur une touche")
	_hint.text = how + " pour continuer   ·   aide désactivable dans Options"
	_opened_at = Time.get_ticks_msec() / 1000.0
	_fit_to_screen()


func _input(event: InputEvent) -> void:
	# [ENTRÉES 1.14] tri commun (Settings.is_continue_press) : les touches de
	# volume ne ferment plus la pause de lecture, et sur téléphone seul un
	# toucher compte. On laisse passer les autres événements (ex. volume).
	var is_press: bool = Settings.is_continue_press(event)
	if not is_press:
		return
	# on « mange » l'appui : il ne doit ni ouvrir le menu pause (Échap), ni
	# déclencher un saut ou le grappin à la reprise
	get_viewport().set_input_as_handled()
	if Time.get_ticks_msec() / 1000.0 - _opened_at < MIN_DISPLAY_TIME:
		return
	close()


func close() -> void:
	get_tree().paused = _was_paused
	_current = null
	emit_signal("closed")
	queue_free()
