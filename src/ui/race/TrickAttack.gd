extends CanvasLayer
class_name TrickAttack
# =============================================================================
#  TrickAttack.gd — [DÉFI FIGURES 1.43] 704, 917 et Half-pipe en mode Score
# -----------------------------------------------------------------------------
#  Demande de l'équipe (21/11) : « Dans le 704 et le 917, lance un chrono en
#  mode Score : le but est juste de faire le meilleur score en figures,
#  chrono 4 minutes. Dans le Half-pipe pareil, un chrono de 3 minutes. »
#
#  Déroulé (créé par RaceManager._start_race, mode Score seulement, jamais en
#  multijoueur ; en Chill ces niveaux restent en glisse libre comme avant) :
#   - compte à rebours en haut au centre (4:00 ou 3:00, TIME_LIMITS) ; il
#     s'arrête pendant la pause (le calque suit la pause du jeu) ;
#   - gros total des points de figures dessous, record et prochaine médaille ;
#   - les 10 dernières secondes : chiffres rouges et un « bip » par seconde ;
#   - à 0 : une figure encore en l'air est validée (comme sur la ligne
#     d'arrivée), le pingouin s'arrête, panneau « TEMPS ÉCOULÉ ! » avec le
#     score, le record, la médaille, et les boutons Rejouer / Menu ;
#   - meilleur score et meilleure médaille enregistrés comme pour les
#     courses (RaceManager._save_best_score / _save_best_medal) : ils
#     s'affichent sur le bouton du niveau dans le menu.
#  Les figures sont comptées par le juge habituel (TrickScore) : rien ne
#  change dans la façon de marquer (figures, vrilles, nose, combos).
#  Médailles : en POINTS (plus c'est haut, mieux c'est), MEDAL_POINTS_GOLD,
#  argent = or × SILVER_SHARE, bronze = or × BRONZE_SHARE.
# =============================================================================

## Durée du défi par niveau (s).
const TIME_LIMITS := {
	"LevelChill704": 240.0,
	"LevelChill917": 240.0,
	"LevelHalfPipe": 180.0,
}
## Points de l'or par niveau. Mesurés au bot « défi figures » (trick_bot.gd,
## hors projet) : il lance une figure dès que le vol prévu dépasse 1,1 s.
##   704 : 3450 pts   917 : 7100 pts   Half-pipe : 6500 pts  (figures seules)
## Avec en plus un NOSE à chaque atterrissage (combos ×2), le même bot fait
## 11 800 / 23 000 / 10 000 pts : l'or est donc à portée d'un joueur qui
## enchaîne figures et nose, sans être parfait.
## [PHYSIQUE RÉELLE 1.49] remesuré avec la résistance de l'air (bot figures
## seules) : 704 = 3600 pts, 917 = 7100, Half-pipe = 5300 (6500 avant : l'air
## raccourcit un peu les sauts du half-pipe). Arrondi au 500 le plus proche.
const MEDAL_POINTS_GOLD := {
	"LevelChill704": 3500,
	"LevelChill917": 7000,
	"LevelHalfPipe": 5500,   # 1.48 : 6500
}
const SILVER_SHARE := 0.65
const BRONZE_SHARE := 0.35
const MEDAL_NAMES := ["", "BRONZE", "ARGENT", "OR"]
const MEDAL_COLORS := [Color.WHITE, Color(0.85, 0.55, 0.3), Color(0.82, 0.86, 0.92), Color(1, 0.84, 0.25)]

var player = null
var level_key := ""             # ex. "LevelChill704"
var time_left := 0.0
var over := false
var best := -1                  # meilleur score avant cette partie
var _ui_root: Control = null
var _time_label: Label
var _points_label: Label
var _best_label: Label
var _last_beep := -1


## Le niveau a-t-il un défi figures ? (chemin de scène)
static func has_challenge(path: String) -> bool:
	# [RÈGLES 1.90] niveau du créateur de type « Défi figures »
	if _is_drawn(path.get_file().get_basename()):
		return DrawnLevel.level_type() == "tricks"
	return TIME_LIMITS.has(path.get_file().get_basename())


## [RÈGLES 1.90] Niveau du créateur ? (chemin réel LevelDrawn ou virtuel LevelDrawn_<id>_<empreinte>)
static func _is_drawn(key: String) -> bool:
	return key.begins_with("LevelDrawn")


## Points minimum pour chaque médaille : [bronze, argent, or].
static func medal_points(key: String) -> Array:
	var gold: int = int(MEDAL_POINTS_GOLD.get(key, 4000))
	if _is_drawn(key):
		# [RÈGLES 1.90] or = points du créateur (« ✔ Valider ») ; pas encore
		# validé : pas de médailles (liste vide)
		gold = int(DrawnLevel.current_gold)
		if gold <= 0:
			return []
	return [int(round(gold * BRONZE_SHARE / 100.0)) * 100, int(round(gold * SILVER_SHARE / 100.0)) * 100, gold]


static func medal_for(key: String, points: int) -> int:
	var t := medal_points(key)
	if t.is_empty():
		return 0   # [RÈGLES 1.90] niveau du créateur pas encore validé
	var m := 0
	for i in 3:
		if points >= t[i]:
			m = i + 1
	return m


func setup(p, path: String) -> void:
	player = p
	level_key = path.get_file().get_basename()
	time_left = float(TIME_LIMITS.get(level_key, 240.0))
	if _is_drawn(level_key):
		time_left = DrawnLevel.tricks_time()   # [RÈGLES 1.90] durée choisie par le créateur


func _ready() -> void:
	layer = 36                      # comme le HUD, sous le menu pause (60)
	best = RaceManager.get_best_score(RaceManager.level_path)
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -260
	top.offset_right = 260
	top.offset_top = 6
	top.add_theme_constant_override("separation", -4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	_time_label = _make_label(40, Color.WHITE)
	_points_label = _make_label(26, Color(1, 0.94, 0.4))
	_best_label = _make_label(16, Color(0.75, 0.95, 1.0))
	for l in [_time_label, _points_label, _best_label]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		top.add_child(l)
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


func _points() -> int:
	var ts = RaceManager.trick_score
	return ts.total if ts != null and is_instance_valid(ts) else 0


func _physics_process(delta: float) -> void:
	if over:
		return
	time_left = maxf(0.0, time_left - delta)
	# 10 dernières secondes : un bip par seconde
	var sec := int(ceil(time_left))
	if sec <= 10 and sec > 0 and sec != _last_beep:
		_last_beep = sec
		Sfx.play("decompte_bip", -6.0)
	_update_labels()
	if time_left <= 0.0:
		_finish()


func _update_labels() -> void:
	var t := int(ceil(time_left))
	_time_label.text = "%d:%02d" % [t / 60, t % 60]
	_time_label.add_theme_color_override("font_color", Color(1, 0.45, 0.35) if time_left <= 10.0 else Color.WHITE)
	var pts := _points()
	_points_label.text = "%d pts" % pts
	var text := ("Record  %d pts" % best) if best >= 0 else "Premier essai !"
	# prochaine médaille à décrocher
	var have := medal_for(level_key, pts)
	if medal_points(level_key).is_empty():
		# [RÈGLES 1.90] défi du créateur pas encore validé
		text += "   ·   Validation : tes points deviendront l'or" if DrawnLevel.validating else ""
	elif have < 3:
		text += "   ·   %s à %d pts" % [MEDAL_NAMES[have + 1].capitalize(), medal_points(level_key)[have]]
	else:
		text += "   ·   OR !"
	_best_label.text = text


func _finish() -> void:
	over = true
	# une figure encore en l'air compte (comme en passant une ligne d'arrivée)
	var ts = RaceManager.trick_score
	if ts != null and is_instance_valid(ts):
		ts.bank()
	var pts := _points()
	var medal := medal_for(level_key, pts)
	# [RÈGLES 1.90] défi d'un niveau du créateur : la course « ✔ Valider »
	# fixe l'or (les points du créateur) ; « Tester d'ici » (chemin réel
	# LevelDrawn) n'enregistre rien
	var counts: bool = level_key != "LevelDrawn"
	if _is_drawn(level_key) and DrawnLevel.validating and counts and pts > 0:
		DrawnLevel.record_validation(float(pts))
		medal = medal_for(level_key, pts)
	var record := pts > best and counts
	if record:
		RaceManager._save_best_score(RaceManager.level_path, pts)
	if medal > RaceManager.get_best_medal(RaceManager.level_path) and counts:
		RaceManager._save_best_medal(RaceManager.level_path, medal)
	# plus de figures comptées : le juge ne regarde que si l'on « ride »
	RaceManager.free_ride = false
	RaceManager.last_score = {"speed": 0, "tricks": pts, "score": pts, "medal": medal, "is_best_score": record}
	Sfx.play("bonus_fin")
	if record and pts > 0:
		get_tree().create_timer(0.7).timeout.connect(func(): Sfx.play("record"))
	if is_instance_valid(player):
		player.process_mode = Node.PROCESS_MODE_DISABLED   # le pingouin s'arrête
	_update_labels()
	_show_over_panel(pts, medal, record)
	print("[DÉFI FIGURES] fin : %d pts, médaille %d, record %s" % [pts, medal, record])
	RaceManager.emit_signal("race_completed")


func _show_over_panel(pts: int, medal: int, record: bool) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.1, 0.22, 0.9)
	style.border_color = MEDAL_COLORS[medal] if medal > 0 else Color(1, 0.94, 0.4)
	style.set_border_width_all(4)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := _make_label(34, Color(1, 0.94, 0.4))
	title.text = "TEMPS ÉCOULÉ !"
	var text := _make_label(26, Color.WHITE)
	text.text = "Figures : %d pts" % pts
	if record and pts > 0:
		text.text += "\nNOUVEAU RECORD !"
	elif best >= 0:
		text.text += "\nRecord : %d pts" % best
	if medal > 0:
		text.text += "\nMédaille %s" % MEDAL_NAMES[medal]
	elif not medal_points(level_key).is_empty():
		text.text += "\nBronze à %d pts" % medal_points(level_key)[0]
	for l in [title, text]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	box.add_child(buttons)
	for b in [["Rejouer", func(): get_tree().reload_current_scene()],
			["Menu", func(): get_tree().change_scene_to_file(DrawnLevel.return_scene if _is_drawn(level_key) else "res://src/screens/LevelSelectionScreen.tscn")]]:
		var btn := Button.new()
		btn.theme = load("res://src/theme_main.tres")   # même style que les menus
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(170, 52)
		btn.add_theme_font_size_override("font_size", 22)
		btn.add_to_group("touch_block")                  # un toucher ici ne lance pas le grappin
		var action: Callable = b[1]
		btn.pressed.connect(func():
			get_tree().paused = false
			action.call())
		buttons.add_child(btn)
	_ui_root.add_child(panel)
	panel.reset_size()
	panel.position = (_ui_root.size - panel.size) * 0.5
