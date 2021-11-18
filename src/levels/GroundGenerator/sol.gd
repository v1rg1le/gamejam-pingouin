extends GroundGeneratorPart

export(int) var map_width = UNIT_SIZE * 10
export(int) var map_height = UNIT_SIZE * 3  #ATTENTION PAS TROP HAUT SINON CA PLANTE

export(int) var polygon_large = 320

export(float) var coeff_pente = 0

onready var n_point = 0

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

	var p = range(debut, fin, 1.2 * UNIT_SIZE)
	for x in p:
		var point
		point = Vector2(x, get_offset_y(x))
		curve.append(point)

	curve.append(Vector2(fin, get_offset_y(fin) + polygon_large))

	p.invert()
	for x in p:
		curve.append(Vector2(x, get_offset_y(x) + polygon_large))

	# DEUX FOR POUR FAIRE LES INSTANCES L'UN APRES L'AUTRE

##		INSTANCE BOOST
	if is_boost:
		for x in range(debut, fin, UNIT_SIZE):
			var point

			point = Vector2(x, get_offset_y(x))

			if simplex_noise.get_noise_2d(x, 0) < boost_treshold:  #-1+1.4=0.4
				add_decoration("boost", point)
##		INSTANCE BOOST FIN

##=		INSTANCE IGLOO
	if is_igloo:
		for x in range(debut, fin, UNIT_SIZE):
			var point = Vector2(x, get_offset_y(x))

			if (
				simplex_noise.get_noise_2d(x, 0) > -igloo_treshold
				&& simplex_noise.get_noise_2d(x, 0) < igloo_treshold
			):  # 1-1.5=-0.5
				add_decoration("igloo", point)

##=		INSTANCE IGLOO FIN

##		INSTANCE WARNING
	var soon_end = map_width * 0.85
	add_decoration("warning", Vector2(soon_end, get_offset_y(soon_end)))
##		INSTANCE WARNING FIN

##		INSTANCE END
	if is_final_map:
		var end = map_width * 0.99
		add_decoration("end", Vector2(end, get_offset_y(end)))
##		INSTANCE END FIN
	return curve
