extends PlayerState
class_name CrashState
# =============================================================================
#  CrashState.gd — [ATTERRISSAGES 1.40] chute : Pinpouin atterrit sur le dos
# -----------------------------------------------------------------------------
#  Demande de Manu : « Quand il tombe sur le dos je veux qu'il tombe comme
#  s'il faisait une chute avec une roulade », avec « une petite explosion de
#  neige » pour cacher le passage dos → fesses.
#  Choix de Manu : roulade, puis assis étourdi 1 s (comme une figure ratée,
#  mais plus court).
#
#  Déroulé (déclenché par LandingStyle.gd quand le pingouin touche le sol à
#  plus de 120° de la pente ; [1.50] aussi par TrixState, figure pas finie
#  avant le sol, et par LandingStyle en tail trop penché vers l'arrière) :
#    1. explosion de neige (LandingStyle.snow_burst) au point de contact ;
#    2. roulade ROLL_TIME s : le dessin « boule » (figure Boule, déjà dans le
#       jeu) tourne sur lui-même, le pingouin se remet dans le sens de la
#       pente et perd peu à peu sa vitesse ;
#    3. puis état STAGGERED (assis, étoiles au-dessus de la tête) pendant
#       DIZZY_TIME s, avant de repartir (vitesse nulle, comme une figure ratée).
#  Les points du saut en cours sont perdus (TrickScore, « Chute ! »).
# =============================================================================

var super_state_name := "CRASH"
var sub_state_name := "CRASHING"

## Durée de la roulade (s), cachée en partie par l'explosion de neige.
const ROLL_TIME := 0.5
## Durée « assis étourdi » après la roulade (s). [ROULADE 1.50] utilisée
## aussi pour les figures ratées (qui avaient 2 s « sonné » avant).
const DIZZY_TIME := 1.0
## Vitesse de rotation du dessin pendant la roulade (radians / s).
const ROLL_SPIN := 18.0

var _t := 0.0


func _handle_input(player: CharacterBody2D, delta: float) -> void:
	_t += delta
	# le dessin roule sur lui-même dans le sens de la glisse
	player.animated_sprite.rotation += ROLL_SPIN * player.facing * delta
	# le corps se remet dans le sens de la pente (caché par la neige)
	player.rotation = lerp_angle(player.rotation, player.landing.last_slope_rotation, 0.25)
	# la roulade freine : il reste ~20 % de la vitesse à la fin
	player._velocity *= clampf(1.0 - 3.2 * delta, 0.0, 1.0)
	if _t >= ROLL_TIME:
		# 2e petit nuage de neige : cache le passage boule → assis
		player.landing.snow_burst(player.global_position, player._velocity, 0.8)
		# assis étourdi, avec les étoiles (StaggeredState, durée et dessin imposés)
		player._states.staggered.next_time = DIZZY_TIME
		player._states.staggered.next_anim = "staggered"
		player._states.go_to_state(player, "staggered")


func enter(player: CharacterBody2D, _previous_state: PlayerState) -> void:
	_t = 0.0
	player.anim_player.play("crash_roll")
	Sfx.play("atterrissage", 3.0, 0.8)   # [BRUITAGES 1.34] gros « pouf » grave


func exit(player: CharacterBody2D) -> void:
	player.animated_sprite.rotation = 0.0   # le dessin se remet droit
	player.rotation = player.landing.last_slope_rotation
