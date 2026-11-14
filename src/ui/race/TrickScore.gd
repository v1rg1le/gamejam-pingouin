extends Node
# =============================================================================
#  TrickScore.gd — [SCORE 1.5] points de figures pendant une course
# -----------------------------------------------------------------------------
#  Demande de l'équipe (14/11) : un score qui compte À LA FOIS le temps du
#  parcours ET des bonus pour les figures. Ce nœud s'occupe des figures ; le
#  score final est calculé par RaceManager à l'arrivée :
#
#      SCORE = points de vitesse + points de figures
#      points de vitesse = SPEED_POINTS / temps en secondes (RaceManager)
#
#  Barème des figures (tout est regroupé dans les constantes ci-dessous) :
#   - FIGURE réussie (l'animation de figure va jusqu'au bout) : TRICK_POINTS
#   - VRILLE (un tour complet du pingouin en l'air, touches de rotation) :
#     SPIN_POINTS par tour
#   - COMBO : plusieurs éléments dans le MÊME saut => le total du saut est
#     multiplié par le nombre d'éléments (×2, ×3… jusqu'à MAX_COMBO).
#   - Les points d'un saut sont « en jeu » tant qu'on est en l'air : ils sont
#     gagnés à l'ATTERRISSAGE propre (ou en passant la ligne d'arrivée).
#     Atterrir pendant une figure (pingouin sonné) ou tomber dans le vide :
#     les points du saut sont perdus.
#
#  Aucune modification des états du pingouin : on se contente d'OBSERVER la
#  machine à états (player._states) à chaque image, comme le ferait un juge.
#  Créé par RaceManager au début d'une course (niveaux avec arrivée).
# =============================================================================

signal points_banked(points: int, total: int, label: String)
signal points_lost(label: String)
signal pending_changed(text: String)

const TRICK_POINTS = 100
const SPIN_POINTS = 150
const MAX_COMBO = 5

# Noms affichés des 4 animations de figure existantes (Player.tscn)
const TRICK_NAMES = {
	"trick_spin": "Toupie",
	"trick_boule": "Boule",
	"trick_etoile_ninja": "Étoile ninja",
	"trick_carpe": "Carpe",
}

var player = null
var total: int = 0                 # points de figures gagnés dans cette course
var tricks_done: int = 0           # nombre de figures + vrilles validées (stats)

var _pending: Array = []           # éléments du saut en cours : [[nom, points], ...]
var _prev_state = null             # état de la machine à états à l'image précédente
var _current_trick: String = ""    # nom de la figure en cours
var _spin_accum: float = 0.0       # rotation cumulée (rad) depuis le décollage
var _spins_counted: int = 0        # tours complets déjà comptés dans ce saut
var _prev_rotation: float = 0.0
var _last_deaths: int = 0


func setup(p) -> void:
	player = p
	_prev_state = p._states.current
	_prev_rotation = p.rotation
	_last_deaths = p.death_count


func _physics_process(_delta: float) -> void:
	if player == null or not is_instance_valid(player) or not RaceManager.racing:
		return
	var sm = player._states
	var st = sm.current

	# 1. Chute dans le vide (respawn) : le saut en cours est perdu
	if player.death_count != _last_deaths:
		_last_deaths = player.death_count
		_lose("Chute…")
		_reset_spin()

	# 2. Début de figure : on note laquelle (l'animation vient d'être choisie)
	if st == sm.trixing and _prev_state != sm.trixing:
		_current_trick = TRICK_NAMES.get(str(player.anim_player.current_animation), "Figure")

	# 3. Figure terminée en l'air (TrixState -> InAirState, cf. StateMachine)
	if _prev_state == sm.trixing and st == sm.in_air:
		_add(_current_trick, TRICK_POINTS)

	# 4. Atterrissage pendant une figure : pingouin sonné, points perdus
	if st == sm.staggered and _prev_state != sm.staggered:
		_lose("Raté !")
		_reset_spin()

	# 5. Vrilles : rotation cumulée en l'air (hors grappin, qui fait tourner
	#    le pingouin tout seul)
	var rot: float = player.rotation
	if st.super_state_name == "IN AIR" and st.sub_state_name != "HOOKING":
		_spin_accum += angle_difference(_prev_rotation, rot)
		var turns := int(absf(_spin_accum) / TAU)
		while _spins_counted < turns:
			_spins_counted += 1
			_add("Vrille", SPIN_POINTS)
	_prev_rotation = rot

	# 6. Atterrissage propre : les points du saut sont gagnés
	if st.super_state_name == "ON_GROUND" and _prev_state != null and _prev_state.super_state_name != "ON_GROUND":
		bank()
		_reset_spin()

	_prev_state = st


## Valide les points en jeu (atterrissage, ou ligne d'arrivée franchie en l'air).
func bank() -> void:
	if _pending.is_empty():
		return
	var sum := 0
	for item in _pending:
		sum += item[1]
	var combo := mini(_pending.size(), MAX_COMBO)
	var points := sum * combo
	total += points
	tricks_done += _pending.size()
	var label := "+%d" % points
	if combo > 1:
		label += "  COMBO ×%d" % combo
	_pending.clear()
	emit_signal("pending_changed", "")
	emit_signal("points_banked", points, total, label)


func _add(trick_name: String, points: int) -> void:
	_pending.append([trick_name, points])
	var names := PackedStringArray()
	for item in _pending:
		names.append(item[0])
	var text := " + ".join(names)
	if _pending.size() > 1:
		text += "  ×%d" % mini(_pending.size(), MAX_COMBO)
	emit_signal("pending_changed", text)


func _lose(reason: String) -> void:
	if _pending.is_empty():
		return
	_pending.clear()
	emit_signal("pending_changed", "")
	emit_signal("points_lost", reason)


func _reset_spin() -> void:
	_spin_accum = 0.0
	_spins_counted = 0
