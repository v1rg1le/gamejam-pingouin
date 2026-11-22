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
#  [TUTO 1.55] Changements (demande de l'équipe, 21/11) :
#   - UNE réussite par atelier (need = 1 dans BateauGenerator) ;
#   - plus de pause de lecture en ENTRANT dans un atelier : la bulle donne la
#     consigne sans figer le jeu, et s'efface toute seule (MasterBubble) ;
#   - à la place, à la 1re tentative de chaque atelier, le jeu se fige AU
#     MOMENT du geste et montre le bouton à utiliser selon l'appareil
#     (ActionPrompt). Les invites de l'atelier (`prompts` de
#     BateauGenerator.workshop_specs) passent dans l'ordre ; chacune attend
#     son moment (_prompt_ready). Après un échec, plus d'invites dans cet
#     atelier : seulement l'indice du maître ;
#   - deux ateliers FALAISE avant la course finale (geste « cliff » : arriver
#     sur le dessus de la falaise). Bloqué au pied du mur = échec + boucle.
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
#   swing  : de retour au sol de l'AUTRE côté du trou ;
#   cliff, cliff2 : [TUTO 1.55] posé au sol SUR le dessus de la falaise
#            (grande falaise : deux murs en escalier, voir BateauGenerator).
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
# [TUTO 1.55] invites « Appuie sur… » au moment du geste
const PROMPT_LAND_SOON := 0.22        # s avant de toucher le sol : invite NOSE / pattes
const PROMPT_AIM_TOL := 45.0          # px : tolérance de « la prise est dans l'axe (45°) »
const CLIFF_STUCK_TIME := 1.2         # s arrêté au pied de la falaise = échec
const SWING_STILL_SPEED := 250.0      # [TUTO 1.58] px/s : « pendu sans élan » au balancier
const SWING_STILL_TIME := 2.5         # [TUTO 1.58] s pendu sans élan = échec, on recommence
var prompt: ActionPrompt
var _prompts_on := false              # invites encore actives dans cet atelier (1re tentative)
var _prompt_i := 0                    # prochaine invite de l'atelier
var _air_t := 0.0                     # s depuis que Pinpouin a quitté le sol
var _hooked_t := 0.0                  # s accroché (invite « tire ! »)
var _stuck_t := 0.0                   # s bloqué au pied de la falaise
var _start_prompt_done := false       # invite « avance » de l'accueil


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
	prompt = ActionPrompt.new()   # [TUTO 1.55]
	prompt.bubble = bubble        # [TUTO 1.55b] l'invite s'affiche dans la bulle
	add_child(prompt)
	prompt.done.connect(_on_prompt_done)


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

	# [TUTO 1.55] jeu figé par une invite : rien à suivre (delta vaut 0)
	# (_prev_state n'est PAS mis à jour : un saut commencé pendant le gel doit
	# être vu comme un nouveau saut à la reprise, atelier « saut »)
	if prompt.is_active():
		return
	# temps en l'air / accroché (pour les moments des invites)
	_air_t = 0.0 if _player.is_on_ground else _air_t + delta
	_hooked_t = _hooked_t + delta if _player.chain.hooked else 0.0

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
	# [TUTO 1.56b] seulement une fois posé : avant, l'atelier recommençait EN
	# PLEIN VOL (« On recommence ! » pendant qu'on faisait la figure, vu dans
	# la vidéo de l'équipe), alors que le saut pouvait encore réussir
	if _index >= 0 and not _completed and px >= workshops[_index].x1 and _player.is_on_ground:
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
	# 5. [TUTO 1.55] invite « Appuie sur… » si c'est le moment
	_update_prompts()
	_update_camera_focus()
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
		"cliff", "cliff2", "chimney":
			# [TUTO 1.55] réussi : posé SUR le dessus de la falaise (dernier mur)
			var ppos: Vector2 = _player.global_position
			var last_face: float = w.cliff_faces[w.cliff_faces.size() - 1]
			if _player.is_on_ground and ppos.x > last_face and ppos.y < w.cliff_top_y + 120.0:
				_success()
				return
			# bloqué au pied d'un mur (au sol, presque arrêté, pas accroché) :
			# échec + boucle, sinon on ne pourrait jamais atteindre le bout
			var stuck := false
			if _player.is_on_ground and absf(_player._velocity.x) < 80.0 and not _player.chain.hooked:
				for i in w.cliff_faces.size():
					if ppos.x > w.cliff_faces[i] - 250.0 and ppos.x < w.cliff_faces[i] + 10.0 \
							and ppos.y > w.cliff_tops[i] + 150.0:
						stuck = true
			if stuck:
				_stuck_t += delta
				if _stuck_t >= CLIFF_STUCK_TIME:
					_stuck_t = 0.0
					_fail("wall")
					_loop_back()
			else:
				_stuck_t = 0.0
		"swing":
			# passé de l'autre côté du trou (au sol, ou encore en l'air AU-DESSUS
			# de l'autre bord). Attention : en tombant dans le trou, le pingouin
			# peut dériver SOUS l'autre bord : ça, ce n'est pas une réussite
			# (bug vu au bot : réussite comptée pendant la chute).
			var sx: float = _player.global_position.x
			if sx > generator.hole_end() + 60.0 and _player.global_position.y < generator.surface_y(sx) + 30.0:
				_success()
				return
			# [TUTO 1.58] filet de sécurité (vidéo 1.57) : accroché au bloc mais
			# pendu presque immobile (pas assez d'élan pour repartir), on ne
			# laisse pas le joueur se balancer dans le vide : retour au début
			# de l'atelier, avec un indice. Pas pendant une invite figée.
			if _player.chain.hooked and _player._velocity.length() < SWING_STILL_SPEED \
					and not prompt.is_active():
				_stuck_t += delta
				if _stuck_t >= SWING_STILL_TIME:
					_stuck_t = 0.0
					_fail("still")
					_loop_back()
			else:
				_stuck_t = 0.0


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
				if it != "Nose" and it != "Vrille" and it != "Tail":   # [TAIL 1.50] atterrissage, pas une figure
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
	# [TUTO 1.55b] choix de l'équipe : c'est PINPOUIN qui parle au joueur
	# (avant : « LE MAÎTRE NINJA »)
	var text := "Salut, c'est moi, Pinpouin ! Viens, je t'apprends la glisse ninja.\nAvance avec {move_right}. Un atelier raté ? On le recommence !"
	if _done_before:
		text += "\nTu connais déjà ? Passe directement à la course."
	bubble.say("PINPOUIN", text)   # [TUTO 1.55] plus de pause de lecture ici
	counter.set_goal("", 0)
	_update_skip()
	# [TUTO 1.55] première invite : avancer (Pinpouin est arrêté au départ)
	if not _start_prompt_done and not Input.is_action_pressed("move_right"):
		_start_prompt_done = true
		prompt.show_prompt("move_right", "Pour avancer. Garde-le enfoncé !")


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
	_prompts_on = true     # [TUTO 1.55] 1re tentative : invites au moment du geste
	_prompt_i = 0
	_stuck_t = 0.0
	prompt.cancel()
	_entry_speed = clampf(_player._velocity.length(), LOOP_SPEED_MIN, LOOP_SPEED_MAX)
	var w: Dictionary = workshops[i]
	var text: String = w.text
	if w.need > 1:
		text += "  (%d fois)" % w.need
	# [TUTO 1.55] plus de pause en entrant : on fige plutôt au moment du geste
	bubble.say("ATELIER %d / %d · %s" % [i + 1, workshops.size(), w.title], text)
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
		prompt.cancel()   # [TUTO 1.55]
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
	# [TUTO 1.55] choix de l'équipe : invites seulement à la 1re tentative
	_prompts_on = false
	prompt.cancel()
	var w: Dictionary = workshops[_index]
	var hints: Array = w.hints
	var hint: String = hints[_hint_i % hints.size()]
	_hint_i += 1
	var head: String = {"loop": "On recommence !", "crash": "Aïe, sur le dos !", "trick": "Figure pas finie !", "fall": "Plouf !", "wall": "Bloqué au pied du mur !", "still": "Plus assez d'élan !"}.get(reason, "Encore !")
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
	prompt.cancel()   # [TUTO 1.55]
	counter.set_goal("", 0)
	bubble.set_skip_visible(false)
	_player.teleport_to(target, Vector2(maxf(_entry_speed, 900.0), 0.0))


func _start_final() -> void:
	_final_started = true
	if _player != null and "focus_point" in _player.camera:
		_player.camera.focus_point = null   # [TUTO 1.55]
	prompt.cancel()   # [TUTO 1.55]
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


# =============================================================================
#  [TUTO 1.55] Invites « Appuie sur… » au moment du geste (ActionPrompt)
# -----------------------------------------------------------------------------
#  À chaque image (jeu non figé), on regarde si la prochaine invite de
#  l'atelier a trouvé son moment (_prompt_ready). Si oui, ActionPrompt fige
#  le jeu et montre le bouton ; quand le joueur appuie, `done` arrive et on
#  passe à l'invite suivante. Une invite dont le bouton est DÉJÀ tenu (le
#  joueur fait déjà le geste) est sautée sans figer.
# =============================================================================
func _update_prompts() -> void:
	if _final_started or _index < 0 or _completed or not _prompts_on:
		return
	if _player._respawning or get_tree().paused:
		return
	var list: Array = workshops[_index].get("prompts", [])
	if _prompt_i >= list.size():
		return
	var p: Dictionary = list[_prompt_i]
	# [TUTO 1.56b] geste déjà fait en avance : on ne le redemande pas
	if _already_done(p):
		print("[TUTO] invite sautée (déjà fait) : ", p.action, " (", p.when, ")")
		_prompt_i += 1
		return
	if not _prompt_ready(String(p.when), workshops[_index]):
		return
	var mode: String = p.get("mode", "press")
	if mode == "press" and Input.is_action_pressed(p.action):
		_prompt_i += 1   # il le fait déjà : pas besoin de figer
		return
	if mode == "release" and not Input.is_action_pressed(p.action):
		_prompt_i += 1   # déjà relâché
		return
	print("[TUTO] invite ", p.action, " (", p.when, ")")
	# [1.55d] cheminée : tourner Pinpouin vers la prise montrée (ActionPrompt.face_dir)
	prompt.face_dir = 0
	if String(p.when).begins_with("aim_swing:"):
		var tt = _target(workshops[_index], String(p.when).substr(10))
		if tt != null:
			prompt.face_dir = 1 if tt.x > _player.global_position.x else -1
	prompt.show_prompt(p.action, p.text, mode, p.get("freeze", true))


# [TUTO 1.55] Falaises : la caméra garde dans le cadre la prise du mur à
# grimper (AdaptiveCamera.focus_point), depuis un peu avant le mur jusqu'à ce
# que Pinpouin soit passé au-dessus. Partout ailleurs : rien (null).
func _update_camera_focus() -> void:
	var cam = _player.camera
	if cam == null or not "focus_point" in cam:
		return
	var focus = null
	if not _final_started and _index >= 0 and workshops[_index].has("chimney_left"):
		# [TUTO 1.55d] cheminée : la prochaine prise au-dessus de Pinpouin
		var wc: Dictionary = workshops[_index]
		var py: float = _player.global_position.y
		if _player.global_position.x > wc.chimney_left - 1600.0:
			for k in range(1, 6):
				var t = wc.targets.get("c%d" % k, null)
				if t == null:
					continue
				if _player.chain.hooked and _player.chain.tip.distance_to(t) < 150.0:
					continue   # celle où il est accroché : on regarde la suivante
				if t.y < py - 60.0:
					focus = t
					break
		cam.focus_point = focus
		return
	if not _final_started and _index >= 0 and workshops[_index].has("cliff_faces"):
		var w: Dictionary = workshops[_index]
		var px: float = _player.global_position.x
		if _player.chain.hooked:
			# accroché : on garde dans le cadre la prise où tient le grappin
			var best := INF
			for key in w.targets:
				var dd: float = w.targets[key].distance_to(_player.chain.tip)
				if dd < best and dd < 300.0:
					best = dd
					focus = w.targets[key]
			cam.focus_point = focus
			return
		for i in w.cliff_faces.size():
			var face: float = w.cliff_faces[i]
			# déjà monté sur ce mur (posé sur la marche ou le dessus : la
			# marche descend un peu, d'où la marge de 80 px) -> mur suivant
			var passed: bool = px > face + 40.0 and _player.global_position.y < w.cliff_tops[i] + 80.0
			if px > face - 1600.0 and not passed:
				focus = w.targets.get("hold%d" % (i + 1), null)
				break
	cam.focus_point = focus


# =============================================================================
#  [TUTO 1.56b] Le joueur a déjà fait le geste, en avance
# -----------------------------------------------------------------------------
#  Retour de l'équipe : « des fois le jeu redemande de faire l'action parce
#  que le joueur l'a faite de manière anticipée ». Exemple : il saute AVANT le
#  bord du tremplin ; l'invite « saute au bord ! » attendait le bord… du
#  tremplin suivant, et redemandait un saut déjà fait. Maintenant, si le
#  geste de l'invite en attente est déjà fait (ou en train d'être fait), on la
#  saute sans rien afficher, et on passe à la suivante (celle du même saut).
# =============================================================================
func _already_done(p: Dictionary) -> bool:
	var when := String(p.when)
	var st = _player._states.current
	var ground: bool = _player.is_on_ground
	# rotation « vers l'avant » positive, quel que soit le sens de la glisse
	var tilt: float = _player.rotation * float(_player.facing)
	match String(p.action):
		"jump":
			# déjà en l'air après un saut (ou lancé par le tremplin)
			if when == "lip":
				return not ground and _air_t > 0.1                   # parti du tremplin
			return _jumped or st == _player._states.jumping         # atelier saut : déjà sauté
		"trix":
			return st == _player._states.trixing
		"rotate_trigo":
			if when == "land_crash":
				return absf(_player.rotation) > deg_to_rad(90.0)   # déjà presque sur le dos
			return not ground and tilt < -deg_to_rad(25.0)          # bec déjà relevé
		"rotate_horaire":
			return not ground and tilt > deg_to_rad(25.0)           # bec déjà en avant
		"hook":
			if String(p.get("mode", "press")) != "press":
				return false
			# déjà accroché À LA PRISE visée (ou au plafond de l'atelier
			# grappin) : pas la peine de le redemander. (Pas « accroché tout
			# court » : juste après un « lâche ! », le grappin tient encore une
			# image, et l'invite suivante était sautée à tort.)
			if not _player.chain.hooked:
				return false
			if when.begins_with("aim:"):
				var t = _target(workshops[_index], when.substr(4))
				return t != null and _player.chain.tip.distance_to(t) < 200.0
			return when == "under_roof"
		"pump":
			return st.sub_state_name == "PUMPING"
	return false


func _on_prompt_done() -> void:
	# [TUTO 1.55b] choix de l'équipe : après l'action, la bulle redit le
	# geste en cours en UNE phrase courte (`after` de l'invite), qui
	# s'efface ensuite comme les autres textes
	var title := "PINPOUIN"
	var after := ""
	if _index >= 0 and not _final_started:
		var w: Dictionary = workshops[_index]
		var list: Array = w.get("prompts", [])
		if _prompt_i < list.size():
			after = list[_prompt_i].get("after", "")
		title = "ATELIER %d / %d · %s" % [_index + 1, workshops.size(), w.title]
	elif _index < 0:
		after = "Garde {move_right} enfoncé : on y va !"   # invite « avance » de l'accueil
	if after != "" and not _completed:
		bubble.say(title, after)
	_prompt_i += 1


# Le moment de l'invite est-il venu ? (voir la liste dans BateauGenerator)
func _prompt_ready(when: String, w: Dictionary) -> bool:
	var pos: Vector2 = _player.global_position
	var vel: Vector2 = _player._velocity
	var ground: bool = _player.is_on_ground
	var st = _player._states.current
	var trixing: bool = st == _player._states.trixing
	if when.begins_with("aim:"):
		# prise devant, sur la ligne à 45° du grappin « par défaut »
		var t = _target(w, when.substr(4))
		return t != null and not _player.chain.hooked and not _player.chain.flying and _on_aim_line(pos, t)
	if when.begins_with("aim_swing:"):
		# [TUTO 1.55d] cheminée : accroché à une prise (ou en l'air), en train
		# d'aller VERS la prise suivante (le grappin relancé part du côté où
		# Pinpouin regarde), et cette prise est dans l'axe à 45°
		var t4 = _target(w, when.substr(10))
		if t4 == null or _player.chain.flying:
			return false
		if _player.chain.hooked and _player.chain.tip.distance_to(t4) < 150.0:
			return false   # déjà accroché à celle-là
		# en train d'aller vers la prise, ou presque immobile (pendu) : le
		# tuto tournera Pinpouin vers elle au moment de l'appui (face_dir)
		var side := signf(t4.x - pos.x)
		return (vel.x * side > 30.0 or vel.length() < 80.0) and _on_aim_line(pos, t4, side)
	if when.begins_with("turn:"):
		# [TUTO 1.55d] cheminée : accroché, il faut partir de l'autre côté
		# (vers la prise suivante) et Pinpouin n'y va pas encore
		var t5 = _target(w, when.substr(5))
		if t5 == null or not _player.chain.hooked or _player.chain.tip.distance_to(t5) < 150.0:
			return false
		return _hooked_t > 0.4 and vel.x * signf(t5.x - pos.x) < 60.0
	if when.begins_with("over:"):
		# accroché, et au-dessus du n-ième mur de la falaise (on peut lâcher)
		var n := int(when.substr(5)) - 1
		if not w.has("cliff_faces") or n >= w.cliff_faces.size():
			return false
		var top_x: float = w.get("cliff_face_tops", w.cliff_faces)[n]   # [1.55c] haut de la paroi
		return _player.chain.hooked and pos.x > top_x + 40.0 and pos.y < w.cliff_tops[n] - 30.0
	match when:
		"start":
			return true
		"ground":
			return ground and pos.x > w.x0 + 400.0
		"ground_descent":
			return ground and pos.x > w.x0 + 400.0 and vel.y > 20.0
		"lip":
			# au sol, juste avant le bord d'un tremplin de l'atelier
			if not ground:
				return false
			for lip in generator.ramp_lips(w.x0, w.x1):
				if pos.x < lip and lip - pos.x < 160.0:
					return true
			return false
		"takeoff":
			return not ground and _air_t > 0.1 and vel.y < 0.0 and not _player.chain.hooked
		"land_crash":
			# atelier « chute » : assez tôt pour tourner jusque sur le dos
			# (~370°/s en tenant la rotation : 0,45 s ≈ 165°)
			if ground or vel.y <= 0.0 or _air_t < 0.3:
				return false
			return _time_to_ground() < 0.45
		"land_soon":
			# en l'air, en train de redescendre, sol tout proche (et la figure
			# finie : on ne penche pas pendant une figure)
			if ground or vel.y <= 0.0 or trixing or _air_t < 0.3:
				return false
			return _time_to_ground() < PROMPT_LAND_SOON
		"under_roof":
			return ground and pos.x > generator.roof_start + 300.0
		"hooked":
			return _player.chain.hooked and _hooked_t > 0.25
		"swing_release":
			# accroché au bloc du balancier, passé dessous, et on remonte
			# ET, lâché maintenant, il retomberait bien de l'autre côté du trou
			# (trajectoire simple : gravité seule)
			var t3 = generator.targets.get("swing", null)
			return t3 != null and _player.chain.hooked and pos.x > t3.x + 150.0 and vel.y < -50.0 \
					and _clears_far_edge()
	return false


# Prise `name` de l'atelier (falaises) ou du niveau (balancier).
func _target(w: Dictionary, name: String):
	var t = w.get("targets", {}).get(name, null)
	if t == null:
		t = generator.targets.get(name, null)
	return t


# La prise `t` est-elle devant Pinpouin, sur la ligne à 45° vers le haut
# (direction du grappin lancé sans viser : Espace, bouton manette, bouton
# tactile GRAPPIN), et à portée (Chain.distance_max = 1200 px) ?
func _on_aim_line(pos: Vector2, t: Vector2, side := 0.0) -> bool:
	# side : côté du tir (0 = celui où Pinpouin regarde)
	var dx: float = (t.x - pos.x) * (side if side != 0.0 else float(_player.facing))
	var dy: float = pos.y - t.y
	return dx > 0.0 and dy > 0.0 and absf(dx - dy) < PROMPT_AIM_TOL and dx * 1.414 < 1150.0


# [TUTO 1.55] Lâché maintenant, Pinpouin passerait-il AU-DESSUS du bord
# d'arrivée du balancier ? (trajectoire simple, gravité seule, avec une
# marge : le bord d'arrivée est 200 px plus haut que le départ, et l'air
# freine un peu). Sert à dire « lâche ! » au bon moment.
func _clears_far_edge() -> bool:
	var p: Vector2 = _player.global_position
	var v: Vector2 = _player._velocity
	var edge_x: float = generator.hole_end() + 60.0
	var edge_y: float = generator.surface_y(generator.hole_end() + 60.0)
	var step := 0.02
	for k in range(200):
		v.y += _player.gravity * step
		p += v * step * 0.97
		if p.x >= edge_x:
			return p.y < edge_y - 70.0
		if v.y > 0.0 and p.y > edge_y + 300.0:
			return false
	return false


# Temps avant de toucher le sol (trajectoire simple : gravité seule), en s ;
# 9 s si rien en dessous dans les 1,5 s.
func _time_to_ground() -> float:
	var space = _player.get_world_2d().direct_space_state
	var p: Vector2 = _player.global_position
	var v: Vector2 = _player._velocity
	var step := 0.03
	for k in range(50):
		var nv := v + Vector2(0, _player.gravity * step)
		var np := p + nv * step
		var q := PhysicsRayQueryParameters2D.create(p, np + Vector2(0, 30), 2, [_player.get_rid()])
		if not space.intersect_ray(q).is_empty():
			return k * step
		p = np
		v = nv
	return 9.0
