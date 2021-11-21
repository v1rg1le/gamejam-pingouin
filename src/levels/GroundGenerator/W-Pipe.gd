extends GroundGeneratorPart

export(int) var map_height = UNIT_SIZE * 90  #ATTENTION PAS TROP HAUT SINON CA PLANTE
export(int) var rayon = UNIT_SIZE * 15  #ATTENTION rayon < map_height sinon ca plante
export(float,0,90) var out_angle = 45
var angle = 0

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
#			Vector2(0, map_height / 2),
#			Vector2(0, 3 * map_height / 4),
#			Vector2(0, map_height),
#			Vector2(map_height / 4, map_height),
#			Vector2(map_height / 2, map_height),
#			Vector2(3 * map_height / 4, map_height),
			Vector2(map_height, map_height/4),
#			Vector2(map_height,map_height / 4),
#			Vector2(map_height,map_height / 2),
#			Vector2(map_height,3 * map_height / 4),
			Vector2(map_height, 0)
		]
	)
	for teta in range(0, 120, 1):
		var point
		point = Vector2(cos(deg2rad(teta)), sin(deg2rad(teta))) * rayon + Vector2(map_height -5/2*rayon, 0)
		curve.append(point)
	for teta in range(60, 120, 1):
		var point
		point = Vector2(cos(deg2rad(teta)), sin(deg2rad(teta))) * rayon + Vector2(map_height -7/2*rayon, 0)
		curve.append(point)
	var p = range(60, 181, 1)
	for teta in p:
		var point
		point = Vector2(cos(deg2rad(teta)), sin(deg2rad(teta))) * rayon + Vector2(map_height -9/2*rayon, 0)
		curve.append(point)
	curve.append(Vector2(0, 0))
	return curve
