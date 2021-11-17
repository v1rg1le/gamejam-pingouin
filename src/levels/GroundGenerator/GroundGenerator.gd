extends Node2D

const UNIT_SIZE = 64 #Taille du joeur
const map_width = UNIT_SIZE*300 #Largeur des ilots
const max_height = UNIT_SIZE*3 #Hauteur des bosses

var sol_res = preload("res://src/levels/GroundGenerator/sol.tscn")
var player_res = preload("res://src/actors/Player.tscn")
var half_pipe_res = preload("res://src/levels/GroundGenerator/HalfPipe.tscn")
var tremplin_res = preload("res://src/levels/GroundGenerator/Tremplin.tscn")

export var slope_length = UNIT_SIZE*40
export var ramp_length = UNIT_SIZE*15

export var gap = UNIT_SIZE * 5 #Gap horizontale entre chaque ilot
export var gap_offset = 7 #Gap verticale = gap_offset*UNIT_SIZE
export(int) var number_map = 2 #Nombre d'ilot sans trou généré sur la map

export(float) var slope_angle = 0
export(float) var coeff_pente = tan(deg2rad(slope_angle))

export(String) var world_seed = "LEOOOOOO"
export(int) var noise_octaves = 1 #Number of OpenSimplex noise layers that are sampled to get the fractal noise. Higher values result in more detailed noise but take more time to generate.
export(int) var noise_period = 1000*0.7 #Period of the base octave. A lower period results in a higher-frequency noise (more value changes across the same distance).
export(float) var noise_persistence = 0.1 #Contribution factor of the different octaves. A persistence value of 1 means all the octaves have the same contribution, a value of 0.5 means each octave contributes half as much as the previous one.
export(float) var noise_lacunarity = 3 # Difference in period between octaves.

export(bool) var is_boost = true
export var boost_treshold = -0.6 #if simplex_noise.get_noise_2d(x,0)<boost_treshold:
export(bool) var is_igloo = true
export var igloo_treshold = 0.01 #ATTENTION -igloo_treshold<...<igloo_treshold

func _ready():
	var next_pos = Vector2(0,0)
	
#	add_tremplin(Vector2(tan(deg2rad(32))*slope_length,-slope_length-ramp_length))
	add_tremplin(Vector2(-slope_length-ramp_length-gap,-tan(deg2rad(32))*slope_length))
	
### GENERATION DES ILOTS
	for i in range(number_map):
		var is_final_map = (i == number_map -1)
		print(is_final_map)
		if i == 0:
			add_player(next_pos + UNIT_SIZE*Vector2(3,-5)
			+Vector2(-slope_length-ramp_length-gap,-tan(deg2rad(32))*slope_length) 
			)
			next_pos = add_sol(next_pos,false)
		else:
			next_pos = add_sol(
				next_pos + i*gap*Vector2(1,0) + i*(map_width+UNIT_SIZE)*Vector2(1,0)
				+i*map_width*coeff_pente*Vector2(0,1) + i*gap_offset*UNIT_SIZE*Vector2(0,1)
				,is_final_map)
### FIN GENERATION DES ILOTS
	add_half_pipe(next_pos + number_map*gap*Vector2(1,0) + number_map*(map_width+UNIT_SIZE)*Vector2(1,0)
				+number_map*map_width*coeff_pente*Vector2(0,1) + (number_map+1)*gap_offset*UNIT_SIZE*Vector2(0,1))

func add_sol(position :Vector2,is_final_map:bool):
	var sol = sol_res.instance()
	var next_pos = Vector2.ZERO
	sol.set_collision_layer(2)
	
	sol.coeff_pente = coeff_pente
	
	sol.noise_octaves = noise_octaves
	sol.noise_period = noise_period
	sol.noise_persistence = noise_persistence
	sol.noise_lacunarity = noise_lacunarity
	
	sol.world_seed = world_seed
	sol.is_boost = is_boost
	sol.boost_treshold = boost_treshold	
	sol.is_igloo = is_igloo
	sol.igloo_treshold = igloo_treshold
	sol.is_final_map = is_final_map
	
	sol.map_width = map_width
	sol.map_height = max_height
	sol.position = position
#	print(sol.noise_period) 
	add_child(sol)
	next_pos = Vector2(0,0)
#	print(next_pos)
	return next_pos
	
func add_player(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var player = player_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	player.global_position = position
	add_child(player)
	
func add_half_pipe(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var half_pipe = half_pipe_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	half_pipe.global_position = position
	add_child(half_pipe)
	
func add_tremplin(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var tremplin = tremplin_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	tremplin.global_position = position
	add_child(tremplin)

