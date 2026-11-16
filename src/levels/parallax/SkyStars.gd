extends Node2D
# =============================================================================
#  SkyStars.gd — [CIEL 1.35] étoiles et lune de la nuit (dessinées en code)
# =============================================================================
#  Posé dans le ParallaxBackground (calque du fond) par SkyCycle : il ne défile
#  pas avec le niveau, comme un vrai ciel très lointain. Les étoiles sont de
#  petits carrés (pixel art) dans la moitié haute de l'écran, qui scintillent ;
#  la lune est un disque clair avec un croissant d'ombre. Tout est invisible
#  le jour (night = 0) et apparaît en fondu avec la nuit (night = 1).
# =============================================================================

var night := 0.0:
	set(v):
		night = v
		visible = night > 0.01
		queue_redraw()

const STAR_COUNT := 90
var _stars: Array = []           # [position relative (0..1), taille, phase]
var _time := 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 917                # toujours le même ciel
	for i in STAR_COUNT:
		_stars.append([Vector2(rng.randf(), pow(rng.randf(), 1.4) * 0.55),
			2.0 if rng.randf() < 0.8 else 4.0, rng.randf() * TAU])
	visible = false


func _process(delta: float) -> void:
	if visible:
		_time += delta
		queue_redraw()


func _draw() -> void:
	var size := get_viewport().get_visible_rect().size
	for s in _stars:
		var twinkle := 0.6 + 0.4 * sin(_time * 2.3 + s[2])
		var p: Vector2 = (s[0] as Vector2) * size
		draw_rect(Rect2(p.floor(), Vector2(s[1], s[1])), Color(1, 1, 0.92, night * twinkle))
	# pleine lune en haut à droite, avec deux halos doux
	var c := Vector2(size.x * 0.82, size.y * 0.16)
	var r := minf(size.x, size.y) * 0.045
	draw_circle(c, r * 2.2, Color(1, 1, 0.9, 0.05 * night))
	draw_circle(c, r * 1.5, Color(1, 1, 0.9, 0.10 * night))
	draw_circle(c, r, Color(0.98, 0.97, 0.88, night))
	draw_circle(c + Vector2(-r * 0.3, r * 0.15), r * 0.22, Color(0.85, 0.85, 0.78, night))   # petites taches
	draw_circle(c + Vector2(r * 0.35, -r * 0.25), r * 0.15, Color(0.85, 0.85, 0.78, night))
