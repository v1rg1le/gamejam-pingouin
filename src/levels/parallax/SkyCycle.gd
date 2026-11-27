extends Node
# =============================================================================
#  SkyCycle.gd — [CIEL 1.35] le ciel change de couleur (façon Alto's Odyssey)
# =============================================================================
#  Idée de Léo, demandée par Manu : dans le niveau Sans fin, le ciel passe
#  de l'AUBE au JOUR, puis au COUCHANT, puis à une NUIT ÉTOILÉE au fil des
#  kilomètres, puis recommence. Dans les niveaux Chill, une ambiance FIXE.
#
#  Aucune image ajoutée ni modifiée : on TEINTE ce qui existe.
#   - les 3 plans du fond (nuages, glacier, montagnes) : couleur de leur
#     ParallaxLayer (la teinte passe à leurs prolongements) ;
#   - le premier plan (îles, pingouin, décor) : un CanvasModulate plus léger,
#     pour garder le jeu lisible ;
#   - la couleur du ciel derrière les images (couleur de fond du rendu) ;
#   - la nuit : des étoiles qui scintillent et une lune, dessinées en code.
#  L'interface (HUD, boutons) n'est pas teintée (autres calques).
#
#  Repères de la palette (en mètres du Sans fin, 1 m = EndlessScore.PX_PER_METER) :
#    0 m aube · 1 km jour · 3 km couchant · 5 km nuit · 8 km aube (et on recommence)
# =============================================================================

## Ambiance fixe pour les niveaux Chill (en « mètres » du cycle, voir KEYS),
## ou -1 = suit la distance parcourue (niveau Sans fin).
@export var fixed_at: float = -1.0
## Longueur d'un cycle complet aube -> aube (m).
@export var cycle_length: float = 8000.0

# palette : [mètres, teinte du fond, teinte du premier plan, couleur du ciel, nuit 0..1]
const KEYS := [
	[0.0,    Color(1.00, 0.84, 0.88), Color(1.00, 0.95, 0.96), Color(0.93, 0.70, 0.74), 0.0],  # aube rose
	[1000.0, Color(1.00, 1.00, 1.00), Color(1.00, 1.00, 1.00), Color(0.40, 0.49, 0.58), 0.0],  # jour (couleurs d'origine)
	[3000.0, Color(1.00, 0.66, 0.48), Color(1.00, 0.93, 0.88), Color(0.95, 0.52, 0.34), 0.0],  # couchant orangé (premier plan à peine teinté : la glace reste bleue)
	[5000.0, Color(0.36, 0.42, 0.78), Color(0.62, 0.68, 0.92), Color(0.07, 0.09, 0.22), 1.0],  # nuit bleue
	[6500.0, Color(0.36, 0.42, 0.78), Color(0.62, 0.68, 0.92), Color(0.07, 0.09, 0.22), 1.0],  # (la nuit dure)
	[8000.0, Color(1.00, 0.84, 0.88), Color(1.00, 0.95, 0.96), Color(0.93, 0.70, 0.74), 0.0],  # retour à l'aube
]

var _layers: Array = []          # ParallaxLayer du fond
var _bg: Node = null             # [FOND 1.74] ParallaxBackground (voir _process)
var _world_tint: CanvasModulate = null
var _stars: Node2D = null
var _player = null
var _start_x := 0.0
var _old_clear := Color()
var _current := 0.0              # position lissée dans le cycle (m)


func _ready() -> void:
	_old_clear = RenderingServer.get_default_clear_color()
	var level := get_parent()
	var bg := level.get_node_or_null("ParallaxBackground")
	_bg = bg
	if bg != null:
		for c in bg.get_children():
			if c is ParallaxLayer:
				_layers.append(c)
		_stars = preload("res://src/levels/parallax/SkyStars.gd").new()
		_stars.z_index = -125      # devant les nuages (-126), derrière glacier et montagnes
		bg.add_child(_stars)
	_world_tint = CanvasModulate.new()
	level.add_child.call_deferred(_world_tint)
	_current = maxf(fixed_at, 0.0)
	_apply(_current)


func _exit_tree() -> void:
	RenderingServer.set_default_clear_color(_old_clear)   # les autres niveaux gardent leur ciel


func _process(delta: float) -> void:
	var target := fixed_at
	if fixed_at < 0.0:
		if _player == null or not is_instance_valid(_player):
			_player = get_tree().get_first_node_in_group("player")
			if _player != null:
				_start_x = _player.global_position.x
			return
		var px_per_m: float = preload("res://src/levels/endless/EndlessScore.gd").PX_PER_METER
		# point le plus loin atteint : une chute ne fait pas revenir le jour
		target = maxf(_current, (_player.global_position.x - _start_x) / px_per_m)
	# changement doux (pas de saut de couleur à la réapparition)
	_current = move_toward(_current, target, maxf(30.0, absf(target - _current) * 2.0) * delta)
	_apply(_current)


func _apply(m: float) -> void:
	var c := fposmod(m, cycle_length) if fixed_at < 0.0 or m >= cycle_length else m
	var a = KEYS[0]
	var b = KEYS[-1]
	for i in KEYS.size() - 1:
		if c >= KEYS[i][0] and c <= KEYS[i + 1][0]:
			a = KEYS[i]
			b = KEYS[i + 1]
			break
	var t := 0.0 if b[0] == a[0] else clampf((c - a[0]) / (b[0] - a[0]), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)                # fondu adouci
	var bg_tint: Color = a[1].lerp(b[1], t)
	var fg_tint: Color = a[2].lerp(b[2], t)
	var sky: Color = a[3].lerp(b[3], t)
	var night: float = lerpf(a[4], b[4], t)
	for l in _layers:
		if is_instance_valid(l):
			l.modulate = bg_tint
	# [FOND 1.74] depuis le fond « Thalès », les images des plans sont portées
	# par le nœud « DollyPlans » (VerticalParallax) et non plus par leurs
	# ParallaxLayer : on lui donne la même teinte
	if is_instance_valid(_bg):
		var dp := _bg.get_node_or_null("DollyPlans")
		if dp != null:
			dp.modulate = bg_tint
	if is_instance_valid(_world_tint):
		_world_tint.color = fg_tint
	RenderingServer.set_default_clear_color(sky)
	if is_instance_valid(_stars):
		_stars.night = night
