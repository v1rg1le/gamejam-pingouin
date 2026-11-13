extends Node2D
# =============================================================================
#  GhostPenguin.gd — [FANTÔMES] pingouin transparent qui rejoue une course
# -----------------------------------------------------------------------------
#  - Aucune physique, aucune collision : il ne gêne jamais le joueur.
#  - Son image est une copie du sprite du vrai pingouin (mêmes animations,
#    aucun nouvel asset), teintée en bleu et semi-transparente.
#  - Il suit le chrono de RaceManager : à l'instant t, il est là où était le
#    joueur enregistré à l'instant t (interpolation entre deux échantillons).
#  - Le grappin du fantôme est dessiné par une simple ligne.
#  - Il s'efface en douceur à la fin de sa course.
# =============================================================================

const FIELDS = 10   # nombre de valeurs par échantillon (cf. RaceManager._record_sample)

var _samples: PackedFloat32Array
var _anims: Array = []
var _count: int = 0
var _i: int = 0             # échantillon courant (on avance au fil du temps)
var _sprite: AnimatedSprite2D
var _rope: Line2D
var _label: Label


func setup(data: Dictionary, player: Node) -> void:
	_samples = data.samples
	_anims = data.anims
	_count = _samples.size() / FIELDS
	# Copie du sprite du joueur (sans script ni enfants inutiles)
	_sprite = player.animated_sprite.duplicate(0)
	_sprite.modulate = Color(0.35, 0.7, 1.0, 0.62)   # bleu nettement visible sur la glace
	_sprite.stop()   # on pilote l'image nous-mêmes
	_rope = Line2D.new()
	_rope.width = 3.0
	_rope.default_color = Color(0.7, 0.9, 1.0, 0.45)
	_rope.top_level = true   # coordonnées monde
	_label = Label.new()
	_label.text = "record"
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(1, 0.94, 0.4, 0.9))
	_label.add_theme_color_override("font_outline_color", Color(0.1, 0.14, 0.26, 0.9))
	_label.add_theme_constant_override("outline_size", 6)
	_label.top_level = true   # le texte ne tourne pas avec le pingouin


func _ready() -> void:
	z_index = -1          # derrière le vrai pingouin
	add_child(_rope)
	add_child(_sprite)
	add_child(_label)
	visible = _count > 0


func _v(i: int, f: int) -> float:
	return _samples[i * FIELDS + f]


func _process(_delta: float) -> void:
	if _count == 0:
		return
	var t: float = RaceManager.race_time
	# avance jusqu'au bon intervalle [i, i+1]
	while _i < _count - 2 and _v(_i + 1, 0) <= t:
		_i += 1
	var i := _i
	var j := mini(i + 1, _count - 1)
	var t0 := _v(i, 0)
	var t1 := _v(j, 0)
	var k := 0.0 if t1 <= t0 else clampf((t - t0) / (t1 - t0), 0.0, 1.0)

	var pos := Vector2(lerpf(_v(i, 1), _v(j, 1), k), lerpf(_v(i, 2), _v(j, 2), k))
	# saut de plus de 400 px entre deux échantillons = téléportation (respawn) : pas d'interpolation
	if Vector2(_v(i, 1), _v(i, 2)).distance_to(Vector2(_v(j, 1), _v(j, 2))) > 400.0:
		pos = Vector2(_v(i, 1), _v(i, 2))
	global_position = pos
	rotation = lerp_angle(_v(i, 3), _v(j, 3), k)   # rotation du corps (+ figure) autour du pingouin
	_label.global_position = pos + Vector2(-24, -62)
	var anim_idx := int(_v(i, 4))
	if anim_idx >= 0 and anim_idx < _anims.size():
		var anim_name: StringName = _anims[anim_idx]
		if _sprite.sprite_frames.has_animation(anim_name) and _sprite.animation != anim_name:
			_sprite.animation = anim_name
	_sprite.frame = int(_v(i, 5))
	_sprite.flip_h = _v(i, 6) > 0.5

	# grappin du fantôme
	if _v(i, 7) > 0.5:
		_rope.points = PackedVector2Array([pos, Vector2(_v(i, 8), _v(i, 9))])
	else:
		_rope.points = PackedVector2Array()

	# fin de la course enregistrée : on s'efface
	if t > _v(_count - 1, 0) + 0.3:
		modulate.a = maxf(0.0, modulate.a - _delta * 2.0)
