extends CanvasLayer
# =============================================================================
#  EndlessScore.gd — [SANS FIN 1.33] mode Score du niveau Sans fin
# =============================================================================
#  Demande de Manu : en Score, le but est d'aller le plus loin possible.
#   - compteur de MÈTRES en haut au centre (comme Alto's Odyssey), record dessous ;
#   - 3 VIES, affichées en têtes de Pinpouin en haut à gauche : chaque chute
#     en coûte une (on réapparaît avant le trou raté), à la 3e c'est fini ;
#   - MÉDAILLES à la distance : bronze 1 km, argent 3 km, or 5 km
#     (meilleure médaille et record gardés, affichés au menu).
#  Créé par EndlessGenerator quand le mode Score est choisi.
#  Les figures restent affichées par le HUD habituel (RaceHud, sans chrono).
# =============================================================================

const LIVES := 3
## Pixels par mètre : réglé aux bots pour que l'or (5 km) corresponde à une
## bonne partie d'un « bon joueur » (bot qui saute et utilise bien le grappin).
const PX_PER_METER := 40.0   # ~ la taille du pingouin : 1 Pinpouin = 1 m
## Distances des médailles (mètres) : bronze, argent, or.
const MEDAL_METERS := [1000, 3000, 5000]
const MEDAL_NAMES := ["", "BRONZE", "ARGENT", "OR"]
const MEDAL_COLORS := [Color.WHITE, Color(0.85, 0.55, 0.3), Color(0.82, 0.86, 0.92), Color(1, 0.84, 0.25)]
const LEVEL_KEY := "res://src/levels/LevelEndless.tscn"   # clé du record / de la médaille
const SAVE_SECTION := "endless"

var player = null
var lives := LIVES
var meters := 0
var best := 0              # record (mètres) avant cette partie
var over := false          # partie terminée
var _start_x := 0.0
var _max_x := 0.0
var _ui_root: Control = null
var _dist_label: Label
var _best_label: Label
var _next_label: Label
var _heads: Array = []
var _over_panel: PanelContainer = null


func setup(p) -> void:
	player = p
	_start_x = p.global_position.x
	_max_x = _start_x
	p.died.connect(_on_died)


func _ready() -> void:
	layer = 36                      # au-dessus du jeu, sous le menu pause (60)
	best = get_best_meters()
	# --- distance : en haut au centre
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -220
	top.offset_right = 220
	top.offset_top = 8
	top.add_theme_constant_override("separation", -4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_dist_label = _make_label(40, Color.WHITE)
	_best_label = _make_label(18, Color(1, 0.94, 0.4))
	_next_label = _make_label(16, Color(0.75, 0.95, 1.0))
	for l in [_dist_label, _best_label, _next_label]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		top.add_child(l)
	_best_label.text = "Record  " + format_meters(best) if best > 0 else "Premier essai !"
	# --- vies : 3 têtes de Pinpouin en haut à gauche (découpées dans le sprite
	# du pingouin, aucune image ajoutée)
	var lives_box := HBoxContainer.new()
	lives_box.position = Vector2(18, 14)
	lives_box.add_theme_constant_override("separation", 6)
	lives_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lives_box)
	var head := AtlasTexture.new()
	head.atlas = load("res://sprites/pingouin/Ninja-Chinstrap_idle.png")
	head.region = Rect2(25, 5, 26, 24)          # la tête avec le bandeau ninja
	for i in LIVES:
		var tr := TextureRect.new()
		tr.texture = head
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # pixel art net
		tr.custom_minimum_size = Vector2(52, 48)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lives_box.add_child(tr)
		_heads.append(tr)
	_ui_root = UiScaler.apply(self)   # [RESPONSIVE] agrandi sur téléphone
	_update_labels()


func _make_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.14, 0.26))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _physics_process(_delta: float) -> void:
	if over or player == null or not is_instance_valid(player):
		return
	# distance = point le plus loin atteint (une chute ne fait pas reculer le compteur)
	_max_x = maxf(_max_x, player.global_position.x)
	var m := int((_max_x - _start_x) / PX_PER_METER)
	if m != meters:
		var before := medal_for(meters)
		meters = m
		_update_labels()
		var now := medal_for(meters)
		if now > before:
			_flash_medal(now)


func _update_labels() -> void:
	_dist_label.text = format_meters(meters)
	var next := ""
	for i in MEDAL_METERS.size():
		if meters < MEDAL_METERS[i]:
			next = "%s à %s" % [MEDAL_NAMES[i + 1].capitalize(), format_meters(MEDAL_METERS[i])]
			break
	var got := medal_for(meters)
	_next_label.text = ("Médaille : %s" % MEDAL_NAMES[got].capitalize() if got > 0 else "") \
		+ ("   ·   " if got > 0 and next != "" else "") + next
	if meters > best and best > 0:
		_best_label.text = "NOUVEAU RECORD !"
	for i in _heads.size():
		_heads[i].modulate = Color.WHITE if i < lives else Color(0.25, 0.3, 0.4, 0.45)


# --- vies --------------------------------------------------------------------
func _on_died() -> void:
	if over:
		return
	lives -= 1
	_update_labels()
	# petite secousse de la tête perdue
	if lives >= 0 and lives < _heads.size():
		var t := create_tween()
		t.tween_property(_heads[lives], "scale", Vector2(1.4, 1.4), 0.12)
		t.tween_property(_heads[lives], "scale", Vector2.ONE, 0.2)
	if lives <= 0:
		_game_over()


func _game_over() -> void:
	over = true
	var medal := medal_for(meters)
	var record := meters > best
	if record:
		_save_best_meters(meters)
	if medal > RaceManager.get_best_medal(LEVEL_KEY):
		RaceManager._save_best_medal(LEVEL_KEY, medal)
	# le pingouin s'arrête après son fondu de chute
	get_tree().create_timer(0.3).timeout.connect(func():
		if is_instance_valid(player):
			player.process_mode = Node.PROCESS_MODE_DISABLED)
	_show_over_panel(medal, record)


func _show_over_panel(medal: int, record: bool) -> void:
	_over_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.1, 0.22, 0.9)
	style.border_color = MEDAL_COLORS[medal] if medal > 0 else Color(1, 0.94, 0.4)
	style.set_border_width_all(4)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(22)
	_over_panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	_over_panel.add_child(box)
	var title := _make_label(34, Color(1, 0.94, 0.4))
	title.text = "PLUS DE VIES !"
	var text := _make_label(26, Color.WHITE)
	text.text = "Distance : %s" % format_meters(meters)
	if record:
		text.text += "\nNOUVEAU RECORD !"
	elif best > 0:
		text.text += "\nRecord : %s" % format_meters(best)
	if medal > 0:
		text.text += "\nMédaille %s" % MEDAL_NAMES[medal]
	for l in [title, text]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	for b in [["Rejouer", func(): get_tree().reload_current_scene()],
			["Menu", func(): get_tree().change_scene_to_file("res://src/screens/LevelSelectionScreen.tscn")]]:
		var btn := Button.new()
		btn.theme = load("res://src/theme_main.tres")   # même style que les menus du jeu
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(170, 52)
		btn.add_theme_font_size_override("font_size", 22)
		btn.add_to_group("touch_block")                  # un toucher ici ne lance pas le grappin
		var action: Callable = b[1]
		btn.pressed.connect(func():
			get_tree().paused = false
			action.call())
		buttons.add_child(btn)
	(_ui_root if _ui_root != null else self).add_child(_over_panel)
	_over_panel.reset_size()
	var view: Vector2 = _ui_root.size if _ui_root != null else get_viewport().get_visible_rect().size
	_over_panel.position = (view - _over_panel.size) * 0.5


# --- médailles -----------------------------------------------------------------
static func medal_for(m: int) -> int:
	var medal := 0
	for i in MEDAL_METERS.size():
		if m >= MEDAL_METERS[i]:
			medal = i + 1
	return medal


func _flash_medal(medal: int) -> void:
	var l := _make_label(44, MEDAL_COLORS[medal])
	l.text = "MÉDAILLE %s !" % MEDAL_NAMES[medal]
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.offset_left = -300
	l.offset_right = 300
	l.offset_top = -140
	l.offset_bottom = -80
	(_ui_root if _ui_root != null else self).add_child(l)
	var t := create_tween()
	t.tween_interval(1.4)
	t.tween_property(l, "modulate:a", 0.0, 0.6)
	t.tween_callback(l.queue_free)


static func format_meters(m: int) -> String:
	if m < 1000:
		return "%d m" % m
	if m % 1000 == 0:
		return "%d km" % (m / 1000)          # « 1 km », pas « 1,00 km »
	return ("%.2f km" % (m / 1000.0)).replace(".", ",")


# --- record (fichier d'options de RaceManager) --------------------------------
static func get_best_meters() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(RaceManager.CONFIG_PATH) != OK:
		return 0
	return int(cfg.get_value(SAVE_SECTION, "best_meters", 0))


func _save_best_meters(m: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(RaceManager.CONFIG_PATH)
	cfg.set_value(SAVE_SECTION, "best_meters", m)
	cfg.save(RaceManager.CONFIG_PATH)
