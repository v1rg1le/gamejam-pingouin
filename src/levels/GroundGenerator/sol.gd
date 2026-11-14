extends StaticBody2D
# =============================================================================
#  sol.gd — génération procédurale d'un "îlot" / spaghetti de glace
#  [MIGRATION GODOT 4.7]
#   - OpenSimplexNoise n'existe plus -> FastNoiseLite (type SIMPLEX).
#     Correspondance des réglages : period -> frequency = 1/period,
#     octaves -> fractal_octaves, persistence -> fractal_gain,
#     lacunarity -> fractal_lacunarity. NB : l'algorithme de bruit est
#     différent, donc un même "world_seed" ne donne plus EXACTEMENT le même
#     relief qu'en Godot 3 (mêmes amplitudes / fréquences, formes différentes).
#   - angle_to_point() a changé de sens en Godot 4 -> calcul explicite.
#  [RELIEF 3.4] (calibrage du 13/11/2026)
#   Mesuré sur TOUS les sols des niveaux (bruit Godot 3.4 recompilé à
#   l'identique vs FastNoiseLite) : à réglages égaux, FastNoiseLite donnait
#   un relief ~1,5x plus haut et des bosses ~2x plus serrées (25 % des
#   montées > 25°, contre 0 % en 3.4). Deux facteurs corrigent cela :
#     fréquence x NOISE_FREQUENCY_G3 (0.5) et valeur x NOISE_AMPLITUDE_G3 (0.668)
#   -> pentes et bosses identiques à la 3.4 à ~1 % près, avec les MÊMES
#   réglages de niveau (noise_period, map_height...). Les formes exactes
#   d'un seed restent différentes (algorithme différent), pas leur "ressenti".
#   Toutes les lectures du bruit passent par _noise(x) (seuils boost / igloo
#   compris, qui gardent donc la même fréquence d'apparition qu'en 3.4).
#  [FIX VITESSE -> 0]
#   - La collision est construite en SEGMENTS (contour seul) et non plus en
#     morceaux convexes : les arêtes internes du découpage provoquaient des
#     "collisions fantômes" qui stoppaient net le pingouin.
# =============================================================================

const UNIT_SIZE = 64
const width_point = 10
@export var map_width: int = UNIT_SIZE*10
@export var map_height: int = UNIT_SIZE*5 #ATTENTION PAS TROP HAUT SINON CA PLANTE

var boost_res = preload("res://src/levels/boost/BoostArea.tscn")
var igloo = preload("res://src/levels/decoration/Igloo.tscn")
var buisson = preload("res://src/levels/decoration/Buisson.tscn")
var colisee = preload("res://src/levels/decoration/Colisee.tscn")
var icemed1 = preload("res://src/levels/decoration/IceMedium1.tscn")
var icemed2 = preload("res://src/levels/decoration/IceMedium2.tscn")
var icesmall = preload("res://src/levels/decoration/IceSmall.tscn")



#var decorations = [igloo, buisson, colisee, icemed1, icemed2, icesmall]
var decorations_common = [icemed1, icemed2, icesmall]
var decorations_rare = [igloo, buisson]
var decorations_wow = [colisee]

var decoration_res = igloo

var warning_res = preload("res://src/levels/decoration/Warning.tscn")
var end_res = preload("res://src/levels/Arche.tscn")

@export var h: int = 40
@export var polygon_large: int = h+20 #60  # 400# 6400


@export var coeff_pente: float = 0

@onready var n_point = 0

@export var coef_pente_animated: bool = false
@export var is_boost: bool = false
@export var boost_treshold = 0.4
@export var is_igloo: bool = false
@export var igloo_treshold = 0.01 #ATTENTION -igloo_treshold<...<igloo_treshold
@export var is_final_map: bool = false

@export var world_seed: String = "LEO"
@export var noise_octaves: int = 1
@export var noise_period: int = 10000*0.7
@export var noise_persistence: float = 0.2
@export var noise_lacunarity: float = 3
#export(float) var noise_threshold = 0.5

# [RELIEF 3.4] facteurs de calibrage FastNoiseLite -> OpenSimplexNoise de Godot 3.4
const NOISE_FREQUENCY_G3 = 0.5     # fréquence = 0.5 / noise_period
const NOISE_AMPLITUDE_G3 = 0.668   # valeur du bruit x 0.668
## [RELIEF 3.4] true = relief calibré comme en 3.4 ; false = FastNoiseLite brut
## (relief plus raide, celui des premières versions 4.7) — utile pour comparer.
@export var g3_terrain_calibration: bool = true

var point_t1  # pour conserver le point precedent, pour pente + normal pour decoration

var simplex_noise : FastNoiseLite = FastNoiseLite.new()

#Permet d'avoir la position de la fin (x,y) y=end_height x=map_width * NUMERO MAP + SOMME DES GAP
var end_y = 0.0  # [RELIEF 3.4] calculé dans _ready() une fois le bruit configuré (avant : bruit pas encore réglé)
var end_x

func _ready() -> void:
	randomize()
#	var curve = $Path2D.curve
	var curve = generate_curve()
#	var polygon = curve.get_baked_points()
#	print(polygon.size())

	# [FIX VITESSE -> 0] contour en segments = plus d'arêtes internes fantômes
	$CollisionPolygon2D.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
	$CollisionPolygon2D.polygon = curve
	$Polygon2D.polygon = curve
	$Line2D.points = curve
	# [SOL 1.9] Sols retournés (scale = (-1, -1), ex. les pistes du haut de
	# Chill 704) : la bordure texturée est décalée de +28 px « vers l'intérieur »
	# du sol dans sol.tscn. Une fois le sol retourné, ce décalage partait vers le
	# HAUT, hors du sol : la bordure dépassait de ~60 px au-dessus de la vraie
	# surface et le pingouin semblait s'enfoncer dans la glace. On inverse donc
	# le décalage pour qu'il reste toujours à l'intérieur du sol.
	if scale.y < 0.0 and $Line2D.position.y > 0.0:
		$Line2D.position.y = -$Line2D.position.y
	
	end_x = curve[curve.size()-1].x
	end_y = coeff_pente*(map_width-UNIT_SIZE) + map_height*_noise(map_width-UNIT_SIZE)  # [RELIEF 3.4]
#	print(end_x)
	
	
func generate_curve() -> PackedVector2Array:
#PAST
#	var key = 0
	var debut = 0
	var fin = self.map_width
	var curve 
	

	#random
#	self.simplex_noise.seed = randi()
#	static
	# [RELIEF 3.4] le bruit est maintenant configuré AVANT le tout premier point
	# (avant, le coin bas-gauche du polygone lisait un bruit encore "par défaut").
	self.simplex_noise.seed = self.world_seed.hash()
	# [MIGRATION GODOT 4.7] équivalents FastNoiseLite des réglages OpenSimplexNoise
	self.simplex_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	self.simplex_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	self.simplex_noise.fractal_octaves = self.noise_octaves
	var freq_factor = NOISE_FREQUENCY_G3 if g3_terrain_calibration else 1.0  # [RELIEF 3.4]
	self.simplex_noise.frequency = freq_factor / max(1.0, float(self.noise_period))  # period -> frequency
	self.simplex_noise.fractal_gain = self.noise_persistence                 # persistence -> gain
	self.simplex_noise.fractal_lacunarity = self.noise_lacunarity

# INITIALISE LE POOLVECTOR2ARRY ET CREER LA BASE A GAUCHE
	curve = PackedVector2Array (
		[
			Vector2(debut,
		map_height*_noise(debut) + coeff_pente*debut + h+20), #+coeff_pente*debut effet tobogan
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


#PAST
#	mySS2D = get_node("/root/LevelGenerated/mySS2D_Open")
#PAST
#	for x in range(-self.map_width /2 ,self.map_width /2):
#		for y in range(-self.map_height /2 ,self.map_height /2):
#			if self.simplex_noise.get_noise_2d(x,y) < self.noise_threshold: #ICI
#				self._set_autofile(x,y) #ICI
#		self.tile_map.update_dirty_quadrants()
	for x in range(debut, fin, UNIT_SIZE):
#		n_point += 1
#		if coef_pente_animated:
#			coeff_pente = get_coef_pente(n_point)
		var point
#		point=Vector2(x,
#		map_height* lerp(self.simplex_noise.get_noise_2d(x,0),self.simplex_noise.get_noise_2d(x+UNIT_SIZE,0),0.1)
#		 + coeff_pente*x) #+coeff_pente*x effet tobogan

		point=Vector2(x,
		map_height* _noise(x)
		 + coeff_pente*x) #+coeff_pente*x effet tobogan
#		print(point)
		curve.append(point)
	
	# la veille fin polygone de manu
#	curve.append(
#		Vector2(fin,
#		map_height*self.simplex_noise.get_noise_2d(fin,0) + coeff_pente*fin + polygon_large)) 
	
	# la fin style:
	#on fait un joli retour de la courbe avec une epaisseur plus fine pour pouvoir rider dessus ?
	
	#	h = max(curve) - min(curve) + petite marge
	# on ajoute le meme nombre de point sur le retour 
	var length_1way = len(curve)
#	var h = 40
	
	for np in range(1, length_1way):
		var point = curve[length_1way-np]
		curve.append(Vector2(point[0], point[1] + h))

	
	# DEUX FOR POUR FAIRE LES INSTANCES L'UN APRES L'AUTRE
	
##		INSTANCE BOOST
	if is_boost:
		for x in range(debut ,fin,UNIT_SIZE):
			var point 
			
			point=Vector2(x,
			map_height* _noise(x)
			 + coeff_pente*x)
			
			if _noise(x)<boost_treshold: #-1+1.4=0.4
				add_boost(point)
##		INSTANCE BOOST FIN
		
##=		INSTANCE IGLOO
	if is_igloo:
		for x in range(debut+2*UNIT_SIZE, fin, UNIT_SIZE):
			var point 
			
			point=Vector2(x,
			map_height* _noise(x)
			 + coeff_pente*x)
			

			if _noise(x)>-igloo_treshold && _noise(x)<igloo_treshold: # 1-1.5=-0.5
				if point_t1 == null: point_t1 = point
				var angrad = (point - point_t1).angle()  # [MIGRATION] == point.angle_to_point(point_t1) de Godot 3
				add_decoration(point, rad_to_deg(angrad))
				
			point_t1 = point
##=		INSTANCE IGLOO FIN

##		INSTANCE WARNING
	var soon_end = map_width*0.94
	add_warning(
		Vector2(soon_end,
			map_height* _noise(soon_end)
			 + coeff_pente*soon_end)
	)
##		INSTANCE WARNING FIN

##		INSTANCE END
	if is_final_map:
		var end = map_width*0.99
		add_end(
			Vector2(end,
				map_height* _noise(end)
				 + coeff_pente*end)
		)
##		INSTANCE END FIN
	#+ coeff_pente*fin effet tobogan
#	print("Curve à la fin")
#	print(curve)
	

#	print(n_point)
	return curve

# [RELIEF 3.4] Lecture du bruit le long de la ligne y = 0, calibrée pour
# reproduire l'échelle de l'OpenSimplexNoise de Godot 3.4.
func _noise(x: float) -> float:
	var v := simplex_noise.get_noise_2d(x, 0)
	return v * NOISE_AMPLITUDE_G3 if g3_terrain_calibration else v


func add_boost(position :Vector2):
	var boost = boost_res.instantiate()
	boost.impulse_mode = true
	boost.global_position = position 
	add_child(boost)


func add_decoration(position:Vector2, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	# decoration aleatoire
#	randomize()
#	decoration_res = decorations[randi() % 6]
#	var deco = decoration_res.instance()
	var deco = get_random_decoration_instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	deco.global_position = position
	deco.rotation_degrees = rotation_degrees
	add_child(deco)
#	return deco

func add_warning(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var warning = warning_res.instantiate()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	warning.global_position = position
	add_child(warning)
#	return deco

func add_end(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var end = end_res.instantiate()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	end.global_position = position
	add_child(end)
#	return deco

func get_random_decoration_instance():
	# [FANTÔMES] hasard tiré du seed de course : mêmes décorations à chaque rejeu
	var random_float = RaceManager.deco_rng.randf()

	if random_float < 0.6:  # common
		return decorations_common[RaceManager.deco_rng.randi() % len(decorations_common)].instantiate()
	elif random_float < 0.8:  # Uncommon
		return decorations_rare[RaceManager.deco_rng.randi() % len(decorations_rare)].instantiate()
	else:  # Rare
		return decorations_wow[RaceManager.deco_rng.randi() % len(decorations_wow)].instantiate()
		 

