extends Node2D
# =============================================================================
#  RemotePenguin.gd — [MULTI] pingouin d'un autre joueur, en direct
# -----------------------------------------------------------------------------
#  Étape 6 (multijoueur en réseau local). Cousin de GhostPenguin.gd :
#  - aucune physique, aucune collision : les joueurs se traversent (c'est une
#    course, pas un jeu de contact ; et ça évite toute triche par la latence) ;
#  - son image est une copie du sprite du vrai pingouin (aucun nouvel asset),
#    teintée d'une couleur propre à chaque joueur, avec son nom au-dessus ;
#  - les états arrivent 20 fois par seconde (NetSession -> RaceManager ->
#    push_state). Pour un mouvement fluide malgré les paquets irréguliers, on
#    affiche le joueur avec un léger retard (INTERP_DELAY = 100 ms) en
#    interpolant entre les deux états qui encadrent cet instant.
#    (Méthode classique "interpolation d'entités" des jeux en réseau.)
# =============================================================================

const INTERP_DELAY = 0.1       # s de retard volontaire (2 paquets de marge)
const BUFFER_MAX = 40          # on garde 2 s d'états au maximum
const TELEPORT_DIST = 400.0    # au-delà : respawn, pas d'interpolation

# Couleurs des adversaires (le bleu est réservé au fantôme record)
const COLORS = [Color(1.0, 0.55, 0.55), Color(0.6, 1.0, 0.6), Color(1.0, 0.85, 0.4),
	Color(0.9, 0.6, 1.0), Color(0.5, 1.0, 1.0), Color(1.0, 0.7, 0.35), Color(0.85, 0.85, 0.85)]

var peer_id: int = 0
var _buffer: Array = []        # [[heure locale de réception, état, animation], ...]
var _sprite: AnimatedSprite2D
var _rope: Line2D
var _label: Label


func setup(player: Node, p_name: String, id: int) -> void:
	peer_id = id
	var color: Color = COLORS[id % COLORS.size()]
	_sprite = player.animated_sprite.duplicate(0)
	_sprite.modulate = Color(color, 0.85)
	_sprite.stop()   # on pilote l'image nous-mêmes
	_rope = Line2D.new()
	_rope.width = 3.0
	_rope.default_color = Color(color, 0.6)
	_rope.top_level = true
	_label = Label.new()
	_label.text = p_name
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", color)
	_label.add_theme_color_override("font_outline_color", Color(0.1, 0.14, 0.26, 0.95))
	_label.add_theme_constant_override("outline_size", 6)
	_label.top_level = true   # le nom ne tourne pas avec le pingouin
	visible = false           # visible dès le premier état reçu


func _ready() -> void:
	z_index = -1   # derrière le pingouin local
	add_child(_rope)
	add_child(_sprite)
	add_child(_label)


func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


## Nouvel état reçu (même format que les échantillons du fantôme).
func push_state(state: PackedFloat32Array, anim: String) -> void:
	_buffer.append([_now(), state, anim])
	if _buffer.size() > BUFFER_MAX:
		_buffer.pop_front()
	visible = true


func _process(_delta: float) -> void:
	if _buffer.is_empty():
		return
	var t := _now() - INTERP_DELAY
	# on jette les états trop vieux (on garde celui juste avant t)
	while _buffer.size() > 2 and _buffer[1][0] <= t:
		_buffer.pop_front()
	var a = _buffer[0]
	var b = _buffer[1] if _buffer.size() > 1 else a
	var k := 0.0 if b[0] <= a[0] else clampf((t - a[0]) / (b[0] - a[0]), 0.0, 1.0)
	var sa: PackedFloat32Array = a[1]
	var sb: PackedFloat32Array = b[1]
	var pa := Vector2(sa[1], sa[2])
	var pb := Vector2(sb[1], sb[2])
	var pos := pa if pa.distance_to(pb) > TELEPORT_DIST else pa.lerp(pb, k)
	global_position = pos
	rotation = lerp_angle(sa[3], sb[3], k)
	_label.global_position = pos + Vector2(-_label.size.x * 0.5, -66)
	var anim_name := StringName(a[2])
	if _sprite.sprite_frames.has_animation(anim_name) and _sprite.animation != anim_name:
		_sprite.animation = anim_name
	_sprite.frame = int(sa[5])
	_sprite.flip_h = sa[6] > 0.5
	if sa[7] > 0.5:
		_rope.points = PackedVector2Array([pos, Vector2(sa[8], sa[9])])
	else:
		_rope.points = PackedVector2Array()
