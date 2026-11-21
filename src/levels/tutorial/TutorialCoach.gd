extends Node
class_name TutorialCoach
# =============================================================================
#  TutorialCoach.gd — [TUTO 1.41] le tuto par ATELIERS, mené par le maître
# -----------------------------------------------------------------------------
#  Demande de l'équipe (21/11) : « rajoute les nouveautés au tuto, fais-le
#  plus long, et fais refaire l'action en boucle jusqu'à ce qu'on la
#  réussisse ». Choix validés :
#   - 3 réussites pour les gestes de base, 1 ou 2 pour les gestes durs ;
#   - un bouton « Passer » après 5 échecs dans le même atelier ;
#   - les consignes données par le maître ninja, en bulles (MasterBubble) ;
#   - pour finir, une petite course chronométrée avec médaille.
#
#  Déroulé : la piste du tuto (BateauGenerator) est découpée en ATELIERS
#  posés les uns après les autres. Chaque atelier = un tronçon [x0, x1] de la
#  piste, un geste à réussir `need` fois, une consigne, des indices.
#   1. En entrant (x0) : le maître donne la consigne (jeu en pause le temps de
#      lire, si l'option des Options est active) ; le compteur « ○ ○ ○ »
#      apparaît au-dessus de Pinpouin (SuccessCounter).
#   2. Chaque réussite remplit un rond. Atelier réussi : clin d'œil du maître,
#      on continue tout droit vers l'atelier suivant.
#   3. ÉCHEC = arriver au bout (x1) sans assez de réussites, tomber dans le
#      trou, chuter sur le dos (hors atelier « chute »), ou rater une figure.
#      Au bout de l'atelier : retour au DÉBUT de l'atelier (la « boucle »),
#      avec l'élan qu'on avait en y entrant. Les réussites déjà faites restent. Chaque échec donne un indice plus
#      précis (le maître change de phrase).
#   4. Après 5 échecs dans le même atelier : bouton « Passer » (Tab, Back ou
#      toucher), qui emmène au début de l'atelier suivant.
#   5. Course finale : sur la ligne de départ, RaceManager remet le chrono à 0
#      (start_tutorial_final) ; arrivée = médaille comme les autres niveaux.
#  Déjà fini une fois ? Le bouton « Passer » est là dès le départ, et le
#  premier mène directement à la course finale.
#
#  Mode enfant : 1 réussite suffit partout, « Passer » après 2 échecs, et
#  l'atelier « chute » est sauté (en mode enfant on ne chute jamais).
#  Multijoueur : pas d'ateliers (les autres courent) ; le tuto reste une
#  course du départ à l'arrivée. Le coach se retire tout seul.
#
#  Comment on reconnaît chaque geste (aucune modification du pingouin) :
#   pump   : un appui sur PUMP au sol, tenu ≥ 0,25 s dans une descente
#            (ou chaque 0,7 s de PUMP tenu sans relâcher) ;
#   jump   : un saut (état JUMPING) suivi d'un atterrissage sans chute ;
#   feet   : atterrissage « sur les pattes » après ≥ 0,6 s en l'air
#            (signal Player.landed, LandingStyle 1.40) ;
#   nose   : atterrissage « nose » ;   crash : atterrissage « crash » ;
#   figure : un saut validé par TrickScore qui contient une figure ;
#   combo  : un saut validé avec au moins 2 éléments (figure, vrille, nose) ;
#   hook   : accroché ≥ 1 s au plafond, en tout (balancier ou en tirant) ;
#   swing  : de retour au sol de l'AUTRE côté du trou.
# =============================================================================

const FAILS_BEFORE_SKIP := 5          # échecs avant le bouton « Passer »
const KID_FAILS_BEFORE_SKIP := 2      # [MODE ENFANT]
const PUMP_STROKE_TIME := 0.25        # s de PUMP dans une descente = 1 coup réussi
const PUMP_LONG_STROKE := 0.7         # s de PUMP tenu sans relâcher = 1 coup aussi
const FEET_MIN_AIR := 0.6             # s en l'air pour qu'un atterrissage compte (tremplin)
const HOOK_MIN_TIME := 1.0            # s accroché au plafond
const PULL_MIN_TIME := 0.3            # (plus utilisé depuis la 1.41b : tirer n'est plus obligatoire)
const LOOP_SPEED_MIN := 700.0         # px/s : élan minimum après un retour au début
const LOOP_SPEED_MAX := 1300.0        # px/s : élan maximum
const WELCOME_DELAY := 0.4           # s avant l'accueil du maître (Pinpouin se pose)
const DONE_SECTION := "tutorial"      # user://pinpouin.cfg : tuto déjà fini une fois ?
const BRAVO := ["Bien joué !", "Parfait !", "Tu progresses vite !", "Très beau !", "Bravo, petit ninja !"]

var generator = null                  # BateauGenerator (piste, positions des ateliers)
var workshops: Array = []             # [{key, title, short, x0, x1, need, text, hints, ...}]
var final_x: float = 0.0              # ligne de départ de la course finale
var bubble: MasterBubble
var counter: SuccessCounter

var _player = null
var _trick = null                     # TrickScore de la course
var _index := -1                      # atelier en cours (-1 : accueil)
var _count := 0                       # réussites dans l'atelier en cours
var _fails := 0                       # échecs dans l'atelier en cours
var _completed := false               # atelier en cours réussi ?
var _entry_speed := 900.0             # élan en entrant dans l'atelier (px/s)
var _final_started := false
var _welcomed := false
var _done_before := false             # tuto déjà fini une fois (skip dès le départ)
var _prev_state = null
var _jumped := false                  # un saut est en cours (atelier « saut »)
var _stroke := 0.0                    # durée du coup de PUMP en cours (s)
var _hook_t := 0.0                    # temps accroché au plafond (s)
var _pull_t := 0.0                    # temps à tirer pendant ce temps (s)
var _hint_i := 0
var _final_hide_at := -1.0
var _welcome_wait := 0.0


func _init() -> void:
	add_to_group("tutorial")   # Player._pick_respawn_sample nous trouve par ce groupe


func setup(gen, list: Array, final_line_x: float) -> void:
	generator = gen
	workshops = list
	final_x = final_line_x


func _ready() -> void:
	if NetSession.in_race:
		# [MULTI] pas d'ateliers en course réseau : simple course jusqu'à l'arrivée
		remove_from_group("tutorial")
		queue_free()
		return
	var cfg := ConfigFile.new()
	cfg.load(RaceManager.CONFIG_PATH)
	_done_before = bool(cfg.get_value(DONE_SECTION, "done", false))
	if Settings.kid_mode:
		# [MODE ENFANT] une réussite suffit, et pas de chute en mode enfant
		for w in workshops:
			w.need = 1
		workshops = workshops.filter(func(w): return w.key != "crash")
	bubble = MasterBubble.new()
	add_child(bubble)
	bubble.skip_pressed.connect(_on_skip)
	counter = SuccessCounter.new()
	add_child(counter)


# -----------------------------------------------------------------------------
#  Boucle principale
# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
		counter.player = _player
		_player.landed.connect(_on_landed)
		_player.died.connect(_on_died)
		_prev_state = _player._states.current
	if _trick == null and RaceManager.trick_score != null and is_instance_valid(RaceManager.trick_score):
		_trick = RaceManager.trick_score
		_trick.points_banked.connect(_on_banked)
		_trick.points_lost.connect(_on_lost)
	# accueil du maître : on laisse d'abord Pinpouin se poser (dans les
	# toutes premières images, le grappin rangé est encore dessiné jusqu'au
	# point (0, 0) du niveau : une corde verticale se voyait derrière la bulle)
	if not _welcomed:
		_welcome_wait += delta
		if _welcome_wait >= WELCOME_DELAY:
			_welcomed = true
			_welcome()
	if _final_hide_at > 0.0 and RaceManager.race_time >= _final_hide_at:
		_final_hide_at = -1.0
		bubble.hide_bubble()

	var px: float = _player.global_position.x
	# limite de « chute infinie » : sous la piste à cet endroit (la piste
	# descend tout le long : la limite calculée au chargement, sous le point
	# le plus bas du niveau, ferait tomber très longtemps dans le trou)
	_player.fall_death_y = generator.ground_y_near(px) + 1400.0
	if _player._respawning:
		_prev_state = _player._states.current
		return

	# 1. Course finale
	if not _final_started and px >= final_x:
		_start_final()
	if _final_started:
		return

	# 2. Bout de l'atelier sans assez de réussites : on recommence (la boucle)
	if _index >= 0 and not _completed and px >= workshops[_index].x1:
		_fail("loop")
		_loop_back()
		return

	# 3. Entrée dans l'atelier suivant (le DERNIER dont le début est passé :
	# normalement le suivant ; plusieurs d'un coup seulement si le pingouin a
	# été déplacé plus loin, ex. outil de test)
	var target := _index
	while target + 1 < workshops.size() and px >= workshops[target + 1].x0:
		target += 1
	if target > _index and (_index < 0 or _completed):
		_enter(target)

	# 4. Gestes suivis image par image
	if _index >= 0 and not _completed:
		_watch(delta)
	_prev_state = _player._states.current


# Gestes qui se reconnaissent en regardant le pingouin à chaque image.
func _watch(delta: float) -> void:
	var sm = _player._states
	var st = sm.current
	var w: Dictionary = workshops[_index]
	match w.key:
		"pump":
			# un coup de PUMP = appui tenu au sol dans une descente, puis relâché
			# (la piste du tuto descend presque partout : un joueur peut garder
			# PUMP enfoncé longtemps ; chaque PUMP_LONG_STROKE s tenue compte
			# aussi pour un coup, sinon il resterait bloqué dans l'atelier)
			if st.sub_state_name == "PUMPING" and _player.is_on_ground:
				if _player._velocity.y > 10.0:
					_stroke += delta
					if _stroke >= PUMP_LONG_STROKE:
						_success()
						_stroke = 0.0
			elif _stroke > 0.0:
				if _stroke >= PUMP_STROKE_TIME:
					_success()
				_stroke = 0.0
		"jump":
			if st == sm.jumping and _prev_state != sm.jumping:
				_jumped = true
		"hook":
			# accroché au PLAFOND (pointe du grappin au-dessus du pingouin).
			# [TUTO 1.41b] Retour de l'équipe (vidéo) : « je me balance pourtant
			# ça ne marche pas ». Deux erreurs : 1) il fallait la pointe à plus
			# de 100 px au-dessus — or en se hissant ({pull}), Pinpouin arrive
			# juste sous le plafond et le chrono de l'atelier repartait à zéro ;
			# 2) tirer était obligatoire. Maintenant : 1 s accroché au plafond
			# (en se balançant OU en tirant), même en plusieurs fois.
			if _player.chain.hooked and _player.chain.tip.y < _player.global_position.y + 10.0:
				_hook_t += delta
				if _hook_t >= HOOK_MIN_TIME:
					_success()
					_hook_t = 0.0
		"swing":
			# passé de l'autre côté du trou (au sol, ou encore en l'air AU-DESSUS
			# de l'autre bord). Attention : en tombant dans le trou, le pingouin
			# peut dériver SOUS l'autre bord : ça, ce n'est pas une réussite
			# (bug vu au bot : réussite comptée pendant la chute).
			var sx: float = _player.global_position.x
			if sx > generator.hole_end() + 60.0 and _player.global_position.y < generator.surface_y(sx) + 30.0:
				_success()


# -----------------------------------------------------------------------------
#  Signaux du pingouin et du juge des figures
# -----------------------------------------------------------------------------
func _on_landed(style: String) -> void:
	if _index < 0 or _completed or _final_started:
		return
	var key: String = workshops[_index].key
	if style == "crash" and key != "crash":
		_fail("crash")
		_jumped = false
		return
	match key:
		"jump":
			if _jumped:
				_success()
		"feet":
			if style == "feet" and _player.landing._air_time >= FEET_MIN_AIR:
				_success()
		"nose":
			if style == "nose":
				_success()
		"crash":
			if style == "crash":
				_success()
	_jumped = false


func _on_banked(_points: int, _total: int, _label: String) -> void:
	if _index < 0 or _completed or _final_started:
		return
	var items: Array = _trick.last_bank_items
	match workshops[_index].key:
		"figure":
			for it in items:
				if it != "Nose" and it != "Vrille":
					_success()
					return
		"combo":
			if items.size() >= 2:
				_success()


func _on_lost(label: String) -> void:
	# figure pas finie avant le sol (« Raté ! ») ; les chutes passent par _on_landed
	if label == "Raté !" and _index >= 0 and not _completed and not _final_started:
		_fail("trick")


func _on_died() -> void:
	if _index >= 0 and not _completed and not _final_started:
		_fail("fall")


## Point de réapparition après une chute dans le vide (Player._pick_respawn_sample) :
## début de l'atelier en cours ; pendant la course finale, un peu avant le
## petit trou raté (jamais AVANT la ligne de départ : la règle habituelle,
## « 2 s en arrière », pouvait renvoyer au-dessus du grand trou du balancier).
func respawn_sample(x: float):
	if _final_started:
		var g = generator.final_gap()
		var rx: float = final_x + 200.0
		if g != null and x > g.x - 200.0:
			rx = g.x - 1200.0
		return {"pos": Vector2(rx, generator.surface_y(rx) - 40.0), "vel": Vector2(1100.0, 0.0)}
	if _index < 0:
		return null
	return {"pos": _start_point(workshops[_index]), "vel": _loop_velocity()}


# -----------------------------------------------------------------------------
#  Étapes du tuto
# -----------------------------------------------------------------------------
func _welcome() -> void:
	var text := "Bienvenue, petit Pinpouin ! Je vais t'apprendre la glisse ninja.\nAvance avec {move_right}. Un atelier raté ? On le recommence !"
	if _done_before:
		text += "\nTu connais déjà ? Passe directement à la course."
	bubble.say("LE MAÎTRE NINJA", text, true)
	counter.set_goal("", 0)
	_update_skip()


func _enter(i: int) -> void:
	_index = i
	_count = 0
	_fails = 0
	_completed = false
	_hint_i = 0
	_jumped = false
	_stroke = 0.0
	_hook_t = 0.0
	_pull_t = 0.0
	_entry_speed = clampf(_player._velocity.length(), LOOP_SPEED_MIN, LOOP_SPEED_MAX)
	var w: Dictionary = workshops[i]
	var text: String = w.text
	if w.need > 1:
		text += "  (%d fois)" % w.need
	bubble.say("ATELIER %d / %d · %s" % [i + 1, workshops.size(), w.title], text, true)
	counter.set_goal(w.short, w.need)
	_update_skip()
	print("[TUTO] atelier ", i + 1, " : ", w.key)


func _success() -> void:
	if _completed:
		return
	_count += 1
	counter.set_count(_count)
	Sfx.play("figure_ok", -4.0)
	var w: Dictionary = workshops[_index]
	print("[TUTO] réussite ", _count, "/", w.need, " (", w.key, ")")
	if _count >= w.need:
		_completed = true
		bubble.cheer()
		counter.flash("RÉUSSI !", Color(0.5, 1, 0.55))
		var msg: String = w.get("done_text", "")
		if msg == "":
			msg = BRAVO[_index % BRAVO.size()] + " Continue tout droit."
		bubble.say("ATELIER %d / %d · %s" % [_index + 1, workshops.size(), w.title], msg)
		_update_skip()
		get_tree().create_timer(1.6).timeout.connect(func():
			if _completed and is_instance_valid(counter):
				counter.set_goal("", 0))
	else:
		counter.flash("+1 !", Color(1, 0.94, 0.4))


func _fail(reason: String) -> void:
	_fails += 1
	var w: Dictionary = workshops[_index]
	var hints: Array = w.hints
	var hint: String = hints[_hint_i % hints.size()]
	_hint_i += 1
	var head: String = {"loop": "On recommence !", "crash": "Aïe, sur le dos !", "trick": "Figure pas finie !", "fall": "Plouf !"}.get(reason, "Encore !")
	bubble.say("ATELIER %d / %d · %s" % [_index + 1, workshops.size(), w.title], head + "  " + hint)
	counter.flash("Encore !", Color(1, 0.6, 0.3))
	_update_skip()
	print("[TUTO] échec ", _fails, " (", reason, ") atelier ", w.key)


# Bout de l'atelier : retour au début, avec l'élan qu'on avait en entrant.
# Les réussites déjà faites sont GARDÉES : la boucle redonne de la place pour
# finir, elle ne punit pas (3 réussites au total, pas forcément d'affilée).
func _loop_back() -> void:
	_jumped = false
	_stroke = 0.0
	_player.teleport_to(_start_point(workshops[_index]), _loop_velocity())


func _start_point(w: Dictionary) -> Vector2:
	var x: float = w.x0 + 150.0
	return Vector2(x, generator.surface_y(x) - 40.0)


func _loop_velocity() -> Vector2:
	return Vector2(_entry_speed, 0.0)


# Bouton « Passer » : visible après assez d'échecs (ou si le tuto est déjà connu).
func _update_skip() -> void:
	var limit: int = KID_FAILS_BEFORE_SKIP if Settings.kid_mode else FAILS_BEFORE_SKIP
	var on := false
	if _index < 0:
		on = _done_before
	elif not _completed:
		on = _done_before or _fails >= limit
	bubble.set_skip_visible(on, _index < 0)


func _on_skip() -> void:
	if _final_started or _player == null or _player._respawning:
		return
	var target: Vector2
	if _index < 0 and _done_before:
		# tuto déjà connu : directement juste avant la course finale
		target = Vector2(final_x - 500.0, generator.surface_y(final_x - 500.0) - 40.0)
		_index = workshops.size() - 1
		_completed = true
	elif _index + 1 < workshops.size():
		var nx: float = workshops[_index + 1].x0 + 40.0
		target = Vector2(nx, generator.surface_y(nx) - 40.0)
		_completed = true   # pas de boucle sur l'atelier passé
	else:
		target = Vector2(final_x - 500.0, generator.surface_y(final_x - 500.0) - 40.0)
		_completed = true
	print("[TUTO] atelier passé")
	counter.set_goal("", 0)
	bubble.set_skip_visible(false)
	_player.teleport_to(target, Vector2(maxf(_entry_speed, 900.0), 0.0))


func _start_final() -> void:
	_final_started = true
	counter.set_goal("", 0)
	RaceManager.start_tutorial_final()
	# on retient que le tuto a été fait (les ateliers deviennent « passables »)
	var cfg := ConfigFile.new()
	cfg.load(RaceManager.CONFIG_PATH)
	cfg.set_value(DONE_SECTION, "done", true)
	cfg.save(RaceManager.CONFIG_PATH)
	var gold := RaceManager.format_time(RaceManager.gold_time) if not Settings.is_chill() else ""
	var text := "Le chrono est parti ! Pump, sauts, figures, NOSE…\nMontre-moi tout ce que tu as appris."
	if gold != "":
		text += "  Or : " + gold
	bubble.cheer()
	bubble.set_top(0.0 if Settings.is_chill() else 92.0)   # sous le chrono (sauf en Chill : pas de chrono)
	bubble.say("COURSE FINALE", text)
	bubble.set_skip_visible(false)
	# la bulle laisse la place au chrono au bout de quelques secondes
	_final_hide_at = 4.0
