extends StaticBody2D

const UNIT_SIZE = 64
export(int) var map_width = UNIT_SIZE * 10
export(int) var map_height = UNIT_SIZE * 5  #ATTENTION PAS TROP HAUT SINON CA PLANTE

var boost_res = preload("res://src/levels/boost/BoostArea.tscn")  # .instance()
var decoration_res = preload("res://sprites/levels/decoration/Igloo.tscn")  #
var warning_res = preload("res://sprites/levels/decoration/Warning.tscn")
var end_res = preload("res://src/levels/Arche.tscn")

export(int) var polygon_large = 320

export(float) var coeff_pente = 0

onready var n_point = 0

export(bool) var coef_pente_animated = false
export(bool) var is_boost = false
export var boost_treshold = 0.4
export(bool) var is_igloo = false
export var igloo_treshold = 0.01  #ATTENTION -igloo_treshold<...<igloo_treshold
export(bool) var is_final_map = false

export(String) var world_seed = "LEO"
export(int) var noise_octaves = 1
export(int) var noise_period = 10000 * 0.7
export(float) var noise_persistence = 0.2
export(float) var noise_lacunarity = 3
#export(float) var noise_threshold = 0.5

var simplex_noise: OpenSimplexNoise = OpenSimplexNoise.new()

#Permet d'avoir la position de la fin (x,y) y=end_height x=map_width * NUMERO MAP + SOMME DES GAP
var end_y = (
	coeff_pente * (map_width - UNIT_SIZE)
	+ map_height * self.simplex_noise.get_noise_2d(map_width - UNIT_SIZE, 0)
)
var end_x

func _ready() -> void:
	randomize()
	var curve = generate_curve()

	$CollisionPolygon2D.polygon = curve
	$Polygon2D.polygon = curve
	$Line2D.points = curve

	end_x = curve[curve.size() - 1].x
	print(end_x)

func get_offset_y(x: float) -> float:
	return map_height * self.simplex_noise.get_noise_2d(x, 0) + coeff_pente * x


func generate_curve() -> PoolVector2Array:
	var debut = 0
	var fin = self.map_width
	var curve

# INITIALISE LE POOLVECTOR2ARRY ET CREER LA BASE A GAUCHE
	curve = PoolVector2Array(
		[
			Vector2(debut, get_offset_y(debut) + polygon_large),  #+coeff_pente*debut effet tobogan
		]
	)

	self.simplex_noise.seed = self.world_seed.hash()
	self.simplex_noise.octaves = self.noise_octaves
	self.simplex_noise.period = self.noise_period
	self.simplex_noise.persistence = self.noise_persistence
	self.simplex_noise.lacunarity = self.noise_lacunarity

#POINT DU DESSUS
	for x in range(debut, fin, 1.2 * UNIT_SIZE):
		var  = Vector2(x, get_offset_y(x))
		curve.append(point)

#PAST
#	curve.append( Vector2( fin, get_offset_y(fin) + polygon_large ))

#POINT DU DESSOUS
#	var p = range(debut, fin, map_width/32)
	var p = range(debut, fin, 1.2 * UNIT_SIZE)
	p.invert()
	print(p)
	for x in p:
		curve.append(Vector2(x, get_offset_y(x) + polygon_large))

	# DEUX FOR POUR FAIRE LES INSTANCES L'UN APRES L'AUTRE

##		INSTANCE BOOST
	if is_boost:
		for x in range(debut, fin, UNIT_SIZE):
			var  = Vector2(x, get_offset_y(x))

			if simplex_noise.get_noise_2d(x, 0) < boost_treshold:  #-1+1.4=0.4
				add_boost(point)
##		INSTANCE BOOST FIN

##=		INSTANCE IGLOO
	if is_igloo:
		for x in range(debut, fin, UNIT_SIZE):
			var point = Vector2(x, get_offset_y(x))

			if (
				simplex_noise.get_noise_2d(x, 0) > -igloo_treshold
				&& simplex_noise.get_noise_2d(x, 0) < igloo_treshold
			):  # 1-1.5=-0.5
				add_decoration(point)

##=		INSTANCE IGLOO FIN

##		INSTANCE WARNING
	var soon_end = map_width * 0.85
	add_warning(Vector2(soon_end, get_offset_y(soon_end)))
##		INSTANCE WARNING FIN

##		INSTANCE END
	if is_final_map:
		var end = map_width * 0.99
		add_end(Vector2(end, get_offset_y(end) - 7 * UNIT_SIZE / 8))
##		INSTANCE END FIN
	return curve

func add_boost(position: Vector2):
	var boost = boost_res.instance()
	boost.impulse_mode = true
	boost.global_position = position
	add_child(boost)

func add_decoration(position: Vector2):  #, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var deco = decoration_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	deco.global_position = position
	add_child(deco)
#	return deco

func add_warning(position: Vector2):  #, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var warning = warning_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	warning.global_position = position
	add_child(warning)
#	return deco

func add_end(position: Vector2):  #, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var end = end_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	end.global_position = position
	add_child(end)
#	return deco
