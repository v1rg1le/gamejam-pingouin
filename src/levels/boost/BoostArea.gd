extends Area2D
# =============================================================================
#  BoostArea.gd — zone de boost (flèches jaunes et rouges).
# -----------------------------------------------------------------------------
#  HISTOIRE
#   Créée par l'équipe sous Godot 3.4 (modes « impulse » et « accel ») mais elle
#   n'a jamais vraiment marché. Raisons trouvées en 1.65 :
#    1. aucun niveau ne l'activait (is_boost restait à false partout) ;
#    2. la scène gardait des noms de réglages de Godot 3 (`frames`, `extents`) :
#       sous Godot 4, la flèche ne s'affichait pas et la zone était minuscule ;
#    3. l'effet était quasi nul (impulsion de 64 px/s ≈ 4 km/h) et la
#       limite de vitesse du pingouin le « mangeait » aussitôt.
#
#  [BOOST 1.65] MODE « TURBO » (façon Trackmania, demande de l'équipe)
#   - Tant que le pingouin est DANS la zone, puis pendant `boost_time` secondes
#     après, il reçoit une ACCÉLÉRATION dans le sens de la flèche (au sol :
#     le long de la pente). Plus la zone est longue, plus le boost dure.
#   - `boost_strength` (0 à 1) règle la force sur tout un SPECTRE, et la
#     couleur de la flèche suit la force, proportionnellement :
#         0    blanc   : nul
#         0.25 jaune   : faible, mais suffit pour grimper une pente de 20°
#         0.6  orange
#         1    rouge   : maximum
#   - au sol (in_air = false) : flèches posées sur le sol, le boost suit la
#     pente ; en l'air (in_air = true) : grande flèche qui flotte dans une zone
#     colorée bien lisible, le boost suit la flèche (on peut la tourner).
#   - `arrow_scale` : taille de la flèche (et de la zone). On va parfois très
#     vite : une grande flèche se lit mieux à ces moments-là.
#  Les anciens réglages (impulse_*, accel_*) sont gardés tels quels (consigne :
#  ne pas renommer les variables). Ils ne servent que si turbo_mode = false.
# =============================================================================

@export var impulse_factor = 64  # Vector2(300, 0) # 300
@export var accel_factor = Vector2(1.2, 0) #acceleration >1 decelaration 0<...<1
## Direction de la flèche, dans le repère du nœud ((1, 0) = vers la droite,
## puis on tourne le nœud avec `rotation`). Sert aussi au mode turbo.
@export var impulse_dir = Vector2(1,0)
@export var impulse_mode = false
@export var accel_mode = false
#export(String, FILE) var collision_shape_path

# --- [BOOST 1.65] mode turbo --------------------------------------------------
## Turbo façon Trackmania (nouveau, par défaut). false = anciens modes.
@export var turbo_mode: bool = true
## Force du boost, de 0 (blanc, nul) à 1 (rouge, maximum).
@export_range(0.0, 1.0, 0.01) var boost_strength: float = 0.35
## Boost en l'air (zone flottante) plutôt qu'au sol.
@export var in_air: bool = false
## Taille de la flèche (1 = 64 px de dessin ; 2 = 128 px...).
@export var arrow_scale: float = 2.0
## Durée du boost APRÈS la sortie de la zone (s).
@export var boost_time: float = 0.8

## Accélération du boost rouge (force 1), en px/s². Le jaune (0,25) donne
## 450 px/s² : sur 20° de pente, la gravité et le frottement retirent
## 800·(sin 20° + 0,02·cos 20°) ≈ 290 px/s², l'air ~30 de plus à 1000 px/s :
## il reste de quoi accélérer en montée.
const BOOST_MAX_ACCEL := 1800.0
## Couleurs du spectre (force -> couleur), interpolées entre ces points.
const SPECTRUM := [
	[0.0, Color(1.0, 1.0, 1.0)],     # blanc : nul
	[0.25, Color(1.0, 0.88, 0.12)],  # jaune
	[0.6, Color(1.0, 0.5, 0.05)],    # orange
	[1.0, Color(0.95, 0.08, 0.05)],  # rouge
]
## Partie visible du dessin des flèches dans le PNG 64×64 (mesurée) : de x=4
## à 62 et de y=27 à 52. Son centre est 7,5 px sous le centre de l'image.
const ARROW_W := 58.0
const ARROW_H := 25.0
const ARROW_DY := 7.5

const TINT_SHADER := preload("res://src/levels/boost/boost_tint.gdshader")

var _zone: Polygon2D = null    # [1.65] fond coloré de la zone (lisibilité)
var _t := 0.0


## Couleur d'une force donnée (0..1), le long du spectre blanc -> rouge.
static func color_for(strength: float) -> Color:
	var s := clampf(strength, 0.0, 1.0)
	for i in range(1, SPECTRUM.size()):
		if s <= SPECTRUM[i][0]:
			var a = SPECTRUM[i - 1]
			var b = SPECTRUM[i]
			return (a[1] as Color).lerp(b[1], (s - a[0]) / (b[0] - a[0]))
	return SPECTRUM[SPECTRUM.size() - 1][1]


func _ready():
	# [MIGRATION GODOT 4.7] la propriété `playing` n'existe plus : on appelle play()
	$AnimatedSprite2D.play()
	if turbo_mode:
		_setup_turbo_look()


## [BOOST 1.65] Taille de la zone, couleur des flèches, fond lisible.
func _setup_turbo_look() -> void:
	var col := color_for(boost_strength)
	var spr: AnimatedSprite2D = $AnimatedSprite2D
	# la flèche est dessinée dans le sens de impulse_dir (par défaut vers la droite)
	spr.rotation = impulse_dir.angle()
	spr.scale = Vector2.ONE * arrow_scale
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # pixel art net
	# plus le boost est fort, plus les chevrons défilent vite
	spr.speed_scale = 1.0 + 3.0 * boost_strength
	var mat := ShaderMaterial.new()
	mat.shader = TINT_SHADER
	mat.set_shader_parameter("tint", col)
	spr.material = mat
	# zone de détection : un rectangle autour du dessin (au sol, un peu plus
	# haut que la flèche pour attraper le pingouin même s'il saute un peu)
	var w := ARROW_W * arrow_scale
	var h := ARROW_H * arrow_scale
	var size := Vector2(w, h)
	var center := Vector2.ZERO
	if not in_air:
		# le nœud est posé SUR le sol : la flèche repose dessus, la zone monte
		# jusqu'à 140 px au-dessus (hauteur d'un petit saut)
		size = Vector2(w, maxf(h, 140.0))
		center = Vector2(0, -size.y * 0.5)
		spr.position = Vector2(0, -h * 0.5 - 4.0) - Vector2(0, ARROW_DY * arrow_scale).rotated(spr.rotation)
	else:
		size = Vector2(w, h) + Vector2(60, 60)
		spr.position = -Vector2(0, ARROW_DY * arrow_scale).rotated(spr.rotation)
	var rect := RectangleShape2D.new()
	rect.size = size
	$CollisionShape2D.shape = rect
	$CollisionShape2D.position = center
	# fond coloré (léger) : on voit tout de suite où agit le boost
	_zone = Polygon2D.new()
	var hs := size * 0.5
	_zone.polygon = PackedVector2Array([center + Vector2(-hs.x, -hs.y), center + Vector2(hs.x, -hs.y),
		center + Vector2(hs.x, hs.y), center + Vector2(-hs.x, hs.y)])
	_zone.color = Color(col.r, col.g, col.b, 0.22 if in_air else 0.12)
	_zone.show_behind_parent = true
	add_child(_zone)
	move_child(_zone, 0)


func _process(delta: float) -> void:
	# [BOOST 1.65] la zone « respire » doucement (attire l'œil sans clignoter)
	if _zone != null:
		_t += delta
		var base := 0.22 if in_air else 0.12
		_zone.color.a = base * (0.75 + 0.25 * sin(_t * 4.0))


## [BOOST 1.65] Direction du boost dans le monde (flèche tournée avec le nœud).
func boost_direction() -> Vector2:
	return global_transform.basis_xform(impulse_dir).normalized()


func _physics_process(_delta: float) -> void:
	# [BOOST 1.65] tant que le pingouin est dans la zone, on (re)donne le turbo
	if not turbo_mode or boost_strength <= 0.0:
		return
	for body in get_overlapping_bodies():
		if body.has_method("pad_boost"):
			body.pad_boost(boost_direction(), boost_strength * BOOST_MAX_ACCEL, boost_time,
				color_for(boost_strength), not in_air)


func _on_BoostArea_body_entered(body):
	# [BOOST 1.65] mode turbo : le son au moment où l'on entre dans la zone
	if turbo_mode:
		if body.has_method("pad_boost") and boost_strength > 0.0:
			Sfx.play("boost", -4.0, 0.8 + 0.5 * boost_strength)
		return
	if body.name == "Player":
#		print('player')
#		print(body._velocity)
#Boost dans une direction ici Vector2(1,0) = down
		if impulse_mode:
			body._velocity += impulse_factor*impulse_dir.normalized()

##Accélération #ATTENTION UN PEU BUGUE MAIS CA MARCHE INCH
		if accel_mode:
			body._velocity *= accel_factor
#		print(body._velocity)
