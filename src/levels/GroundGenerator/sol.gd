extends StaticBody2D

const UNIT_SIZE = 64
const width_point = 10
export(int) var map_width = UNIT_SIZE*10
export(int) var map_height = UNIT_SIZE*5 #ATTENTION PAS TROP HAUT SINON CA PLANTE

var boost_res = preload("res://src/levels/boost/BoostArea.tscn")  # .instance()
var decoration_res = preload("res://sprites/levels/decoration/Igloo.tscn") # 
var warning_res = preload("res://sprites/levels/decoration/Warning.tscn")
var end_res = preload("res://src/levels/Arche.tscn")

export(int) var polygon_large = 6400

export(float) var coeff_pente = 0

onready var n_point = 0

export(bool) var coef_pente_animated = false
export(bool) var is_boost = false
export var boost_treshold = 0.4
export(bool) var is_igloo = false
export var igloo_treshold = 0.01 #ATTENTION -igloo_treshold<...<igloo_treshold
export(bool) var is_final_map = false

export(String) var world_seed = "LEO"
export(int) var noise_octaves = 1
export(int) var noise_period = 10000*0.7
export(float) var noise_persistence = 0.2
export(float) var noise_lacunarity = 3
#export(float) var noise_threshold = 0.5

var simplex_noise : OpenSimplexNoise = OpenSimplexNoise.new()

#Permet d'avoir la position de la fin (x,y) y=end_height x=map_width * NUMERO MAP + SOMME DES GAP
var end_y =coeff_pente*(map_width-UNIT_SIZE) + map_height*self.simplex_noise.get_noise_2d(map_width-UNIT_SIZE,0) 
var end_x

func _ready() -> void:
	randomize()
#	var curve = $Path2D.curve
	var curve = generate_curve()
#	var polygon = curve.get_baked_points()
#	print(polygon.size())

	$CollisionPolygon2D.polygon = curve
	$Polygon2D.polygon = curve
	$Line2D.points = curve
	
	end_x = curve[curve.size()-1].x
	print(end_x)
	
	
func generate_curve() -> PoolVector2Array:
#PAST
#	var key = 0
	var debut = 0
	var fin = self.map_width
	var curve 
	

# INITIALISE LE POOLVECTOR2ARRY ET CREER LA BASE A GAUCHE
	curve = PoolVector2Array (
		[
			Vector2(debut,
		map_height*self.simplex_noise.get_noise_2d(debut,0) + coeff_pente*debut + polygon_large), #+coeff_pente*debut effet tobogan
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
#		n_point += 1
#		if coef_pente_animated:
#			coeff_pente = get_coef_pente(n_point)
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
		map_height*self.simplex_noise.get_noise_2d(fin,0) + coeff_pente*fin + polygon_large)) 
		
	# DEUX FOR POUR FAIRE LES INSTANCES L'UN APRES L'AUTRE
	
##		INSTANCE BOOST
	if is_boost:
		for x in range(debut ,fin,UNIT_SIZE):
			var point 
			
			point=Vector2(x,
			map_height* self.simplex_noise.get_noise_2d(x,0)
			 + coeff_pente*x)
			
			if simplex_noise.get_noise_2d(x,0)<boost_treshold: #-1+1.4=0.4
				add_boost(point)
##		INSTANCE BOOST FIN
		
##=		INSTANCE IGLOO
	if is_igloo:
		for x in range(debut ,fin,UNIT_SIZE):
			var point 
			
			point=Vector2(x,
			map_height* self.simplex_noise.get_noise_2d(x,0)
			 + coeff_pente*x)
			

			if simplex_noise.get_noise_2d(x,0)>-igloo_treshold && simplex_noise.get_noise_2d(x,0)<igloo_treshold: # 1-1.5=-0.5
	#			print(point_after)
				add_decoration(point)
				
##=		INSTANCE IGLOO FIN

##		INSTANCE WARNING
	var soon_end = map_width*0.85
	add_warning(
		Vector2(soon_end,
			map_height* self.simplex_noise.get_noise_2d(soon_end,0)
			 + coeff_pente*soon_end)
	)
##		INSTANCE WARNING FIN

##		INSTANCE END
	if is_final_map:
		var end = map_width*0.99
		add_end(
			Vector2(end,
				map_height* self.simplex_noise.get_noise_2d(end,0)
				 + coeff_pente*end)
		)
##		INSTANCE END FIN
	#+ coeff_pente*fin effet tobogan
#	print("Curve à la fin")
#	print(curve)
		
#	print(n_point)
	return curve

func add_boost(position :Vector2):
	var boost = boost_res.instance()
	boost.impulse_mode = true
	boost.global_position = position 
	add_child(boost)


func add_decoration(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var deco = decoration_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	deco.global_position = position
	add_child(deco)
#	return deco

func add_warning(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var warning = warning_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	warning.global_position = position
	add_child(warning)
#	return deco

func add_end(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var end = end_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	end.global_position = position
	add_child(end)
#	return deco

