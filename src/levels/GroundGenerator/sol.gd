extends StaticBody2D

const UNIT_SIZE = 64
const width_point = 10
export(int) var map_width = UNIT_SIZE*400
export(int) var map_height = UNIT_SIZE*5 #ATTENTION PAS TROP HAUT SINON CA PLANTE

export(float) var coeff_pente = 0.5

onready var n_point = 0
export(bool) var coef_pente_animated = false

export(String) var world_seed = "LEOOOO"
export(int) var noise_octaves = 1
export(int) var noise_period = 10000*0.7
export(float) var noise_persistence = 0.2
export(float) var noise_lacunarity = 3
#export(float) var noise_threshold = 0.5

var simplex_noise : OpenSimplexNoise = OpenSimplexNoise.new()

func _ready() -> void:
	randomize()
#	var curve = $Path2D.curve
	var curve = generate_curve()
#	var polygon = curve.get_baked_points()
#	print(polygon.size())

	$CollisionPolygon2D.polygon = curve
	$Polygon2D.polygon = curve
	$Line2D.points = curve
	
func generate_curve() -> PoolVector2Array:
#PAST
#	var key = 0
	var debut = -self.map_width /2
	var fin = self.map_width /2
	var curve 
	

# INITIALISE LE POOLVECTOR2ARRY ET CREER LA BASE A GAUCHE
	curve = PoolVector2Array (
		[
			Vector2(debut,
		map_height*self.simplex_noise.get_noise_2d(debut,0) + coeff_pente*debut + 6400), #+coeff_pente*debut effet tobogan
		]
	)
#	print("Curve Init")
#	print(curve)
	

#CREER LA BASE DU POLYGON
#	curve.append(
#		Vector2(debut,
#		self.simplex_noise.get_noise_2d(debut,0) + 6400)
#	)
#	curve.append(
#		Vector2(fin,
#		self.simplex_noise.get_noise_2d(fin,0) + 6400)
#	)
#	print(curve)

	#random
#	self.simplex_noise.seed = randi()
#	static
	self.simplex_noise.seed = self.world_seed.hash()
	self.simplex_noise.octaves = self.noise_octaves
	self.simplex_noise.period = self.noise_period
	self.simplex_noise.persistence = self.noise_persistence
	self.simplex_noise.lacunarity = self.noise_lacunarity

#PAST
#	mySS2D = get_node("/root/LevelGenerated/mySS2D_Open")
#PAST
#	for x in range(-self.map_width /2 ,self.map_width /2):
#		for y in range(-self.map_height /2 ,self.map_height /2):
#			if self.simplex_noise.get_noise_2d(x,y) < self.noise_threshold: #ICI
#				self._set_autofile(x,y) #ICI
#		self.tile_map.update_dirty_quadrants()
	for x in range(debut ,fin,UNIT_SIZE):
		n_point += 1
		if coef_pente_animated:
			coeff_pente = get_coef_pente(n_point)
		var point
#		point=Vector2(x,
#		map_height* lerp(self.simplex_noise.get_noise_2d(x,0),self.simplex_noise.get_noise_2d(x+UNIT_SIZE,0),0.1)
#		 + coeff_pente*x) #+coeff_pente*x effet tobogan

		point=Vector2(x,
		map_height* self.simplex_noise.get_noise_2d(x,0)
		 + coeff_pente*x) #+coeff_pente*x effet tobogan
#		print(point)
		curve.append(point)
	curve.append(
		Vector2(fin,
		map_height*self.simplex_noise.get_noise_2d(fin,0) + coeff_pente*fin + 6400)) #+ coeff_pente*fin effet tobogan
#	print("Curve à la fin")
#	print(curve)
		
#	print(n_point)
	return curve

func get_coef_pente(n_point):
#	pass
#	print(n_point)
	var pente = [-0.3,0,0.3,0.4]
	# pourcentage davancement
#	var percent = 400 - n_point /400
	var percent = floor(n_point / (1200/2))+1
#	print(percent)
#	print("")
	return pente[percent]
