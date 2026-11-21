extends CanvasLayer
class_name MasterBubble
# =============================================================================
#  MasterBubble.gd — [TUTO 1.41] le maître ninja parle dans une bulle
# -----------------------------------------------------------------------------
#  Demande de l'équipe (21/11) : un tuto plus long et plus immersif. Choix
#  retenu : « le maître ninja en bulles ». Le maître (le dessin déjà dans le
#  jeu : sprites/screens/bad_penguin_1/2/3.png + bad_penguin_wink.png, ceux
#  de MasterWink.gd) passe la tête en haut à gauche de l'écran et donne UNE
#  consigne courte par atelier, avec les vraies touches du joueur (mêmes
#  marqueurs {action} que les panneaux : TutorialSign.resolve_text).
#  Aucun nouvel asset : bulle dessinée en code, mêmes couleurs que le HUD.
#
#  Ce que sait faire la bulle (appelée par TutorialCoach.gd) :
#   - say(titre, texte)      : nouvelle consigne (le maître « parle » : son
#                              bandeau flotte et la bulle rebondit) ;
#   - say(..., pause=true)   : la même, mais le jeu se met EN PAUSE jusqu'à
#                              un appui (si l'option « Pause pour lire les
#                              panneaux du tuto » est active, comme avant) ;
#   - cheer()                : clin d'œil du maître (réussite) ;
#   - set_skip_visible(on)   : bouton « Passer » (après 5 échecs) ;
#     Tab au clavier, Back à la manette, ou toucher / clic sur le bouton.
#  Signaux : `closed` (fin de la pause de lecture), `skip_pressed`.
# =============================================================================

signal closed
signal skip_pressed

const FRAMES = [
	"res://sprites/screens/bad_penguin_1.png",
	"res://sprites/screens/bad_penguin_2.png",
	"res://sprites/screens/bad_penguin_3.png",
]
const WINK = "res://sprites/screens/bad_penguin_wink.png"
const MASTER_SIZE := 104.0     # taille du maître à l'écran (64 px × ~1,6, pixel-art net)
const BUBBLE_X := 128.0        # la bulle commence à droite du maître
const BUBBLE_MAX_W := 560.0    # largeur max du texte (au-delà : retour à la ligne)
const FRAME_TIME := 0.12       # s : bandeau au vent
const TALK_TIME := 1.2         # s : le bandeau flotte quand il parle
const WINK_TIME := 0.45        # s : clin d'œil
const MIN_PAUSE_TIME := 0.4    # s pendant lesquelles on ignore les appuis (comme ReadingPause)
const SKIP_KEY := KEY_TAB      # touche « Passer » au clavier
const SKIP_JOY := JOY_BUTTON_BACK   # bouton « Passer » à la manette (Back / Select)

var _root: Control             # racine agrandie (UiScaler)
var _dim: ColorRect            # voile sombre pendant la pause de lecture
var _master: TextureRect
var _bubble: PanelContainer
var _tail: Control             # petite pointe de la bulle, vers le maître
var _title: Label
var _text: Label
var _hint: Label               # « Appuie sur une touche… » (pause seulement)
var _skip: Button
var _textures: Array = []
var _wink_tex: Texture2D
var _talk_left := 0.0          # s pendant lesquelles le bandeau flotte encore
var _wink_left := 0.0
var _anim_t := 0.0
var _pausing := false          # pause de lecture en cours
var _opened_at := 0.0
var _was_paused := false
var _raw_title := ""           # textes AVANT remplacement des touches (pour
var _raw_text := ""            # suivre un changement de manette / clavier)
var _skip_to_race := false     # texte du bouton : « Aller à la course »


func _init() -> void:
	layer = 45                              # au-dessus du HUD (35) et des panneaux (40), sous les boutons tactiles (50)
	process_mode = Node.PROCESS_MODE_ALWAYS # doit répondre pendant la pause de lecture


func _ready() -> void:
	for path in FRAMES:
		_textures.append(load(path))
	_wink_tex = load(WINK)

	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.05, 0.15, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.visible = false
	add_child(_dim)

	# --- le maître (haut gauche ; le chrono y est caché pendant les ateliers)
	_master = TextureRect.new()
	_master.texture = _textures[0]
	_master.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_master.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_master.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_master.size = Vector2(MASTER_SIZE, MASTER_SIZE)
	_master.position = Vector2(12, 10)
	_master.pivot_offset = Vector2(MASTER_SIZE * 0.5, MASTER_SIZE)
	_master.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_master)

	# --- la bulle
	_tail = Control.new()
	_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tail.position = Vector2(BUBBLE_X - 16, 40)
	_tail.size = Vector2(20, 24)
	_tail.draw.connect(func():
		# triangle blanc (bordure) puis bleu nuit (fond), pointe vers le maître
		_tail.draw_colored_polygon(PackedVector2Array([Vector2(0, 12), Vector2(20, 0), Vector2(20, 24)]), Color(1, 0.94, 0.4))
		_tail.draw_colored_polygon(PackedVector2Array([Vector2(5, 12), Vector2(20, 4), Vector2(20, 20)]), Color(0.06, 0.1, 0.22, 0.94)))
	add_child(_tail)

	_bubble = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.1, 0.22, 0.94)
	style.border_color = Color(1, 0.94, 0.4)
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(14)
	_bubble.add_theme_stylebox_override("panel", style)
	_bubble.position = Vector2(BUBBLE_X, 14)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bubble)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(box)
	_title = _label(19, Color(1, 0.94, 0.4))
	_text = _label(23, Color(1, 1, 1))
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 0
	_hint = _label(15, Color(1, 1, 1, 0.7))
	box.add_child(_title)
	box.add_child(_text)
	box.add_child(_hint)

	# --- bouton « Passer » (sous la bulle), caché au départ
	_skip = Button.new()
	_skip.add_theme_font_size_override("font_size", 20)
	_skip.focus_mode = Control.FOCUS_NONE   # pas de focus : Espace / Entrée restent au jeu
	# même style que la bulle, bordure jaune : il doit se voir sans gêner
	for st_name in ["normal", "hover", "pressed"]:
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color(0.06, 0.1, 0.22, 0.94) if st_name != "pressed" else Color(0.25, 0.3, 0.5, 0.95)
		bs.border_color = Color(1, 0.94, 0.4)
		bs.set_border_width_all(3 if st_name == "normal" else 4)
		bs.set_corner_radius_all(12)
		bs.set_content_margin_all(10)
		_skip.add_theme_stylebox_override(st_name, bs)
	_skip.add_theme_color_override("font_color", Color(1, 0.94, 0.4))
	_skip.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	_skip.visible = false
	_skip.pressed.connect(func(): emit_signal("skip_pressed"))
	add_child(_skip)

	_root = UiScaler.apply(self)   # [RESPONSIVE 1.14] plus gros sur téléphone
	Settings.controls_changed.connect(func(_s): _refresh_text())
	visible = false


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Nouvelle consigne du maître. `pause` : on fige le jeu le temps de lire
## (seulement si l'option des Options est active, et jamais en multijoueur).
func say(title: String, text: String, pause := false) -> void:
	_raw_title = title
	_raw_text = text
	visible = true
	_refresh_text()
	_talk_left = TALK_TIME
	# petit rebond de la bulle : on voit tout de suite que le texte a changé
	_bubble.pivot_offset = Vector2(0, _bubble.size.y * 0.5)
	_bubble.scale = Vector2(0.85, 0.85)
	create_tween().set_ignore_time_scale(true).tween_property(_bubble, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if pause and Settings.tutorial_pause and not NetSession.in_race:
		_start_pause()
	else:
		_hint.visible = false
	_show_then_fade()   # [TUTO 1.55] lisible le temps de lire, puis presque transparente


# =============================================================================
#  [TUTO 1.55] La bulle s'efface toute seule, selon la longueur du texte
# -----------------------------------------------------------------------------
#  Demande de l'équipe (21/11) : comme le bandeau « BRAVO ! », la bulle du
#  maître prend de la place pendant qu'on joue. Choix de l'équipe : elle
#  reste lisible le temps de la lire (« selon la longueur du texte »), puis
#  devient presque transparente. Elle redevient bien visible à chaque
#  nouvelle consigne ou nouvel indice (say()).
#  Durée : READ_CHARS_PER_S caractères par seconde (lecture tranquille), au
#  moins READ_MIN_TIME s, au plus READ_MAX_TIME s. Le bouton « Passer »
#  n'est PAS estompé (il doit rester trouvable).
#  Le Tween ignore Engine.time_scale : la bulle continue son compte même
#  pendant un gel du jeu par une invite « Appuie sur… » (ActionPrompt).
# =============================================================================
const READ_CHARS_PER_S := 15.0   # vitesse de lecture prise en compte
const READ_MIN_TIME := 3.0       # s : même durée que les bandeaux d'arrivée
const READ_MAX_TIME := 10.0      # s
const FADE_TIME := 0.8           # s de fondu
const FADE_ALPHA := 0.15         # opacité finale : « à peine visible »
var _fade_tween: Tween = null

func _show_then_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	for n in [_master, _tail, _bubble]:
		n.modulate.a = 1.0
	if _pausing:
		return   # pause de lecture (ancienne option) : pas de fondu pendant la pause
	var chars := float((_title.text + _text.text).length())
	var wait := clampf(chars / READ_CHARS_PER_S, READ_MIN_TIME, READ_MAX_TIME)
	_fade_tween = create_tween().set_ignore_time_scale(true).set_parallel(true)
	for n in [_master, _tail, _bubble]:
		_fade_tween.tween_property(n, "modulate:a", FADE_ALPHA, FADE_TIME).set_delay(wait) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Descend le maître et sa bulle de `dy` (course finale : le chrono, le record
## et les points de figures réapparaissent en haut à gauche, juste au-dessus).
func set_top(dy: float) -> void:
	_master.position.y = 10.0 + dy
	_tail.position.y = 40.0 + dy
	_bubble.position.y = 14.0 + dy
	_fit.call_deferred()


## Cache la bulle et le maître (course finale : le chrono reprend sa place).
func hide_bubble() -> void:
	visible = false


## Clin d'œil du maître : une étape réussie.
func cheer() -> void:
	_wink_left = WINK_TIME
	_master.scale = Vector2(1.15, 1.15)
	create_tween().tween_property(_master, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## `to_race` : le bouton mène directement à la course finale (tuto déjà fait).
func set_skip_visible(on: bool, to_race := false) -> void:
	_skip.visible = on
	_skip_to_race = to_race
	_refresh_text()


func is_pausing() -> bool:
	return _pausing


func _refresh_text() -> void:
	if _title == null:
		return
	_title.text = TutorialSign.resolve_text(_raw_title)
	_title.visible = _raw_title != ""
	_text.text = TutorialSign.resolve_text(_raw_text)
	# largeur : celle du texte, sans dépasser BUBBLE_MAX_W (ni l'écran)
	var avail: float = (_root.size.x if _root != null else 1024.0) - BUBBLE_X - 20.0
	var font := _text.get_theme_font("font")
	var widest := 0.0
	for line in _text.text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 23).x)
	_text.custom_minimum_size.x = minf(minf(widest + 4.0, BUBBLE_MAX_W), avail - 28.0)
	var how := "Touche l'écran" if Settings.controls == Settings.TOUCH else ("Appuie sur un bouton" if Settings.controls == Settings.GAMEPAD else "Appuie sur une touche")
	_hint.text = how + " pour continuer"
	var skip_key := "Back" if Settings.controls == Settings.GAMEPAD else ("" if Settings.controls == Settings.TOUCH else "Tab")
	var what := "Aller à la course" if _skip_to_race else "Passer cet atelier"
	_skip.text = what + "  ▶▶" + ("   (%s)" % skip_key if skip_key != "" else "")
	_bubble.reset_size()
	_skip.reset_size()
	# le texte à la ligne automatique ne connaît sa vraie hauteur qu'après une
	# mise en page : on reprend la taille de la bulle à l'image suivante (sinon
	# elle pouvait rester haute comme l'écran, vu au premier test)
	_fit.call_deferred()


func _fit() -> void:
	_bubble.reset_size()
	# le bouton « Passer » se place sous la bulle, une fois la bulle mesurée
	_skip.position = Vector2(BUBBLE_X, _bubble.position.y + _bubble.size.y + 8.0)


func _start_pause() -> void:
	_pausing = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_opened_at = Time.get_ticks_msec() / 1000.0
	_dim.visible = true
	_hint.visible = true
	_refresh_text()


# [TUTO 1.44] Si la scène change pendant une pause de lecture (bouton retour
# Android, outil de test…), on rend la main : sinon le niveau suivant
# démarrerait encore en pause.
func _exit_tree() -> void:
	if _pausing:
		_pausing = false
		get_tree().paused = _was_paused


func _end_pause() -> void:
	_pausing = false
	get_tree().paused = _was_paused
	_dim.visible = false
	_hint.visible = false
	_refresh_text()
	_show_then_fade()   # [TUTO 1.55] le compte de lecture démarre à la fin de la pause
	emit_signal("closed")


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# --- « Passer » : Tab, Back, ou toucher / clic sur le bouton. On le teste
	# ICI (avant les boutons tactiles) : sinon toucher le bouton lancerait
	# aussi le grappin vers cet endroit de l'écran.
	# (aussi pendant la pause de lecture : on ferme la pause ET on passe)
	if _skip.visible and event.is_pressed() and not event.is_echo():
		var hit := false
		if event is InputEventKey and event.keycode == SKIP_KEY:
			hit = true
		elif event is InputEventJoypadButton and event.button_index == SKIP_JOY:
			hit = true
		elif event is InputEventScreenTouch or event is InputEventMouseButton:
			hit = _skip.get_global_rect().has_point(_to_root(event.position))
		if hit:
			get_viewport().set_input_as_handled()
			if _pausing:
				_end_pause()
			emit_signal("skip_pressed")
			return
	# --- pause de lecture : un appui (tri commun de Settings) la ferme
	if _pausing and Settings.is_continue_press(event):
		get_viewport().set_input_as_handled()
		if Time.get_ticks_msec() / 1000.0 - _opened_at >= MIN_PAUSE_TIME:
			_end_pause()


# Position écran -> repère du bouton (le calque est agrandi par UiScaler).
func _to_root(screen_pos: Vector2) -> Vector2:
	return screen_pos / scale.x


func _process(delta: float) -> void:
	if not visible:
		return
	_anim_t += delta
	_talk_left = maxf(0.0, _talk_left - delta)
	_wink_left = maxf(0.0, _wink_left - delta)
	if _wink_left > 0.0:
		_master.texture = _wink_tex
	elif _talk_left > 0.0 or _pausing:
		_master.texture = _textures[int(_anim_t / FRAME_TIME) % _textures.size()]   # le bandeau flotte : il parle
	else:
		_master.texture = _textures[0]
