extends CanvasLayer
# =============================================================================
#  SpeedMeter.gd — [VITESSE 1.48] compteur de vitesse de Pinpouin
# -----------------------------------------------------------------------------
#  Demande de l'équipe : « une option pour afficher la vitesse de Pinpouin »
#  (suite à l'enquête sur les ralentissements en glisse, voir
#  MIGRATION_GODOT4.md, section 58).
#
#  Ce qu'on voit (en haut à droite, sous le bouton pause tactile) :
#    ┌───────────────────────┐
#    │        95 km/h        │  <- grande valeur, facile à lire en jouant
#    │   1450 px/s · au sol  │  <- valeur « moteur » + sol / en l'air / grappin
#    │ ▓▓▓▓▓▓▓▓▓▓▓▓▓░░|░░|░░ │  <- jauge 0 → 3000 px/s (2200 avant la 1.49)
#    └───────────────────────┘
#  Sur la jauge (ancienne physique, realistic_physics = 0), deux traits :
#    - trait BLANC  = plafond au sol   (Player.ground_max_speed, 1450 px/s)
#    - trait BLEU   = plafond en l'air (Player.air_max_speed,    1750 px/s)
#  Quand Pinpouin va plus vite que le plafond de là où il est (sol ou air),
#  la jauge devient ORANGE : c'est le « frein doux » de
#  Player._apply_soft_speed_caps() qui est en train de le ralentir.
#  Pratique pour comprendre les ralentissements après un gros saut.
#
#  Unités : le jeu compte 55 px par mètre (EndlessScore.PX_PER_METER, réglé
#  pour les distances du mode Sans fin). On réutilise la même échelle pour
#  que « km/h » et « mètres parcourus » restent cohérents entre eux :
#      km/h = px/s ÷ 55 × 3,6      (1450 px/s ≈ 95 km/h)
#
#  Création : par RaceManager._start_race(), une fois par niveau, pour le
#  pingouin LOCAL (en multi aussi). Le compteur existe toujours mais reste
#  caché tant que l'option est coupée : on peut donc l'allumer / l'éteindre
#  en pleine partie avec la touche F3 (clavier), sans relancer le niveau.
#
#  Aucun nouvel asset : tout est dessiné en code (comme RaceHud.gd).
#
#  [PHYSIQUE RÉELLE 1.49] Avec la nouvelle physique (résistance de l'air +
#  frottement, Player.realistic_physics = 1, réglage par défaut), il n'y a
#  plus de plafonds fixes. La jauge change donc de sens :
#    - un seul repère BLANC = la VITESSE LIMITE de la pente sous Pinpouin
#      (Player.terminal_speed_on_slope) : au-dessus, l'air le ralentit plus
#      que la pente ne le pousse ; en dessous, il accélère encore. Pas de
#      repère en l'air, sur le plat ni en montée (pas de vitesse limite) ;
#    - ORANGE = Pinpouin est en train de PERDRE de la vitesse (accélération
#      lissée < -150 px/s²), BLEU = il garde ou prend de la vitesse ;
#    - la ligne du dessous indique aussi la pente : « au sol · descente 8° ».
#  Avec l'ancienne physique (realistic_physics = 0), l'affichage d'avant
#  (deux plafonds, orange = frein doux) est conservé tel quel.
# =============================================================================

## Même échelle que les distances du mode Sans fin (EndlessScore.PX_PER_METER).
## Copiée ici (et pas lue dans EndlessScore) pour ne pas dépendre d'un script
## de niveau : le compteur doit marcher dans TOUS les niveaux.
const PX_PER_METER := 55.0
## Vitesse correspondant à une jauge pleine (un peu au-dessus du plafond en
## l'air pour qu'on voie le dépassement après un pump ou une figure boostée).
const GAUGE_MAX := 5000.0   # [1.68] plus de plafond à 3000 : la jauge va jusqu'à ~la chute libre (4800 px/s) ; [1.49] 3000 = ancien SUPER_MAX_SPEED
## Touche pour allumer / éteindre le compteur en jeu (F2 = panneau physique).
const TOGGLE_KEY := KEY_F3

var player = null                 # le pingouin local (Player.gd), donné par setup()
var _panel: PanelContainer        # le cadre semi-transparent
var _kmh_label: Label             # « 95 km/h »
var _detail_label: Label          # « 1450 px/s · au sol »
var _gauge: Control               # la jauge dessinée en code (_draw_gauge)
var _speed := 0.0                 # vitesse affichée (px/s), un peu lissée
var _over_cap := false            # vrai = jauge orange (frein doux / perte de vitesse)
var _accel := 0.0                 # [1.49] accélération lissée (px/s²), pour l'orange
var _last_raw := -1.0             # [1.49] vitesse brute de l'image précédente
var _limit_mark := 0.0            # [1.49] vitesse limite de la pente (0 = pas de repère)


## Appelé par RaceManager avant add_child().
func setup(p) -> void:
	player = p


func _ready() -> void:
	layer = 35   # même étage que RaceHud : au-dessus du jeu, sous la pause (60)
	process_mode = Node.PROCESS_MODE_PAUSABLE   # figé pendant la pause, comme le jeu

	# --- le cadre (même style sombre et arrondi que le bandeau de RaceHud)
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.1, 0.22, 0.6)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ancré en haut à droite ; 84 px du haut = sous le bouton pause tactile
	# (TouchControls, « pause » en (980, 44) rayon 30), même hauteur que le
	# classement multi de RaceHud (qui se décale alors en dessous, cf. RaceHud)
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN   # grandit vers la gauche
	_panel.offset_right = -18
	_panel.offset_top = 84
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)

	_kmh_label = _make_label(26, Color(1, 1, 1))
	_detail_label = _make_label(14, Color(0.75, 0.95, 1.0))
	box.add_child(_kmh_label)
	box.add_child(_detail_label)

	# --- la jauge : un simple Control qui se dessine lui-même
	_gauge = Control.new()
	_gauge.custom_minimum_size = Vector2(190, 12)
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge.draw.connect(_draw_gauge)
	box.add_child(_gauge)

	# [RESPONSIVE 1.14] agrandi sur téléphone comme le reste du HUD
	UiScaler.apply(self)
	_refresh_visibility()


# Étiquette avec contour, comme RaceHud._make_label (lisible sur la neige).
func _make_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.14, 0.26))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# Le compteur n'est visible que si l'option est active ET qu'il y a un pingouin.
func _refresh_visibility() -> void:
	visible = Settings.show_speed and player != null and is_instance_valid(player)


func _unhandled_input(event: InputEvent) -> void:
	# F3 : raccourci clavier pour allumer / éteindre (mémorisé dans les
	# Options, exactement comme la case « Afficher la vitesse »)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == TOGGLE_KEY:
		Settings.set_option("show_speed", not Settings.show_speed)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_refresh_visibility()
	if not visible:
		return
	# Vitesse réelle du moteur physique du pingouin (Player._velocity, px/s).
	var raw: float = player._velocity.length()
	# Lissage très léger (~0,05 s) : sans lui, le chiffre « tremble » d'une
	# unité à chaque image au sol. Assez court pour voir les vraies chutes
	# brusques (grappin, choc) d'une image à l'autre.
	_speed = lerpf(_speed, raw, clampf(delta * 20.0, 0.0, 1.0))

	# Où est Pinpouin ? (même logique que Player._apply_soft_speed_caps)
	var hooking: bool = player.chain.hooked
	var on_ground: bool = player.is_on_ground
	var where := "grappin" if hooking else ("au sol" if on_ground else "en l'air")

	# [PHYSIQUE RÉELLE 1.49] nouvel affichage (voir l'en-tête)
	if player.realistic_physics >= 0.5:
		_show_realistic(raw, delta, hooking, on_ground, where)
		return
	_limit_mark = 0.0
	# Plafond qui s'applique là où il est. Pendant le grappin, il n'y a pas
	# de frein doux (HookingInAirState a son propre réglage) : pas d'orange.
	var cap: float = player.ground_max_speed if on_ground else player.air_max_speed
	cap += _boost_extra()
	_over_cap = not hooking and raw > cap + 1.0

	var kmh: float = _speed / PX_PER_METER * 3.6
	_kmh_label.text = "%d km/h" % roundi(kmh)
	_detail_label.text = "%d px/s · %s" % [roundi(_speed), where]
	_gauge.queue_redraw()


# [PHYSIQUE RÉELLE 1.49] Affichage avec la résistance de l'air : repère =
# vitesse limite de la pente actuelle, orange = Pinpouin ralentit.
func _show_realistic(raw: float, delta: float, hooking: bool, on_ground: bool, where: String) -> void:
	# accélération mesurée d'une image à l'autre, lissée (~0,25 s) pour que
	# la couleur ne clignote pas sur chaque petite bosse
	if _last_raw >= 0.0 and delta > 0.0:
		_accel = lerpf(_accel, (raw - _last_raw) / delta, clampf(delta * 4.0, 0.0, 1.0))
	_last_raw = raw
	_over_cap = _accel < -150.0

	# pente sous Pinpouin, en degrés (+ = descente dans le sens où il va) :
	# angle de la normale du sol, retourné si on glisse vers la gauche
	_limit_mark = 0.0
	var slope_text := ""
	if on_ground and not hooking:
		var n: Vector2 = player._get_ground_normal()
		if n != Vector2.ZERO:
			var slope := rad_to_deg(atan2(n.x, -n.y)) * signf(player._velocity.x if absf(player._velocity.x) > 1.0 else 1.0)
			_limit_mark = player.terminal_speed_on_slope(slope)
			if slope > 1.0:
				slope_text = " · descente %d°" % roundi(slope)
			elif slope < -1.0:
				slope_text = " · montée %d°" % roundi(-slope)
			else:
				slope_text = " · plat"

	_kmh_label.text = "%d km/h" % roundi(_speed / PX_PER_METER * 3.6)
	_detail_label.text = "%d px/s · %s%s" % [roundi(_speed), where, slope_text]
	_gauge.queue_redraw()


# Plafond relevé pendant le boost d'une figure réussie ([BOOST FIGURE 1.30]
# dans Player._apply_soft_speed_caps) : même calcul, en lecture seule.
func _boost_extra() -> float:
	if player._trick_boost_left <= 0.0 or player.trick_boost_time <= 0.0:
		return 0.0
	return player._trick_boost_extra * clampf(player._trick_boost_left / player.trick_boost_time, 0.0, 1.0)


# Jauge : fond sombre, remplissage bleu (orange si frein doux), et les deux
# repères des plafonds (blanc = sol, bleu clair = air).
func _draw_gauge() -> void:
	var w: float = _gauge.size.x
	var h: float = _gauge.size.y
	_gauge.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.45))
	var f: float = clampf(_speed / GAUGE_MAX, 0.0, 1.0)
	var fill := Color(1.0, 0.6, 0.15) if _over_cap else Color(0.45, 0.8, 1.0)
	_gauge.draw_rect(Rect2(0, 0, w * f, h), fill)
	if player == null or not is_instance_valid(player):
		return
	# [PHYSIQUE RÉELLE 1.49] un seul repère : la vitesse limite de la pente
	if player.realistic_physics >= 0.5:
		if _limit_mark > 0.0:
			var xl: float = w * clampf(_limit_mark / GAUGE_MAX, 0.0, 1.0)
			_gauge.draw_line(Vector2(xl, -2), Vector2(xl, h + 2), Color(1, 1, 1), 2.0)
		return
	for mark in [[player.ground_max_speed, Color(1, 1, 1)], [player.air_max_speed, Color(0.55, 0.85, 1.0)]]:
		var x: float = w * clampf(mark[0] / GAUGE_MAX, 0.0, 1.0)
		_gauge.draw_line(Vector2(x, -2), Vector2(x, h + 2), mark[1], 2.0)
