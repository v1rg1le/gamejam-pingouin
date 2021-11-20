extends GroundGeneratorPart

export(int) var map_height = UNIT_SIZE * 50  #ATTENTION PAS TROP HAUT SINON CA PLANTE
export(int) var rayon = UNIT_SIZE * 45  #ATTENTION rayon < map_height sinon ca plante
export(float,0,90) var out_angle = 45
var angle = 90-out_angle

export(int) var polygon_large = 640

#Permet d'avoir la position de la fin (x,y) y=end_height x=map_width * NUMERO MAP + SOMME DES GAP
var end_x = 0
var end_y = 0


func _ready() -> void:
	randomize()
	var curve = generate_curve()

	$CollisionPolygon2D.polygon = curve
	$Polygon2D.polygon = curve
	$Line2D.points = curve


func generate_curve() -> PoolVector2Array:
	var curve
	## QUARTER PIPE
	curve = PoolVector2Array(
		[
			Vector2(0, 0),
			Vector2(0, map_height / 4),
			Vector2(0, map_height / 2),
			Vector2(0, 3 * map_height / 4),
			Vector2(0, map_height),
			Vector2(map_height / 4, map_height),
			Vector2(map_height / 2, map_height),
			Vector2(3 * map_height / 4, map_height),
			Vector2(map_height, map_height),
		]
	)
	if angle != 0:
		curve.append(
			Vector2(cos(deg2rad(90 - angle)), 0) * rayon
			+ Vector2(map_height + map_height - rayon, map_height)
		)
		curve.append(
			Vector2(cos(deg2rad(90 - angle)), sin(deg2rad(90 - angle))) * rayon
			+ Vector2(map_height + map_height - rayon, 0)
		)

	for teta in range(90 - angle, 181, 1):
		var point
		point = Vector2(cos(deg2rad(teta)), sin(deg2rad(teta))) * rayon + Vector2(map_height, 0)
		curve.append(point)
	curve.append(Vector2(0, 0))
	return curve
