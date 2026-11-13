extends Node2D

const UNIT_SIZE = 64 #Taille du joeur
const map_width = UNIT_SIZE*300 #Largeur des ilots
const max_height = UNIT_SIZE*3 #Hauteur des bosses

var sol_res = preload("res://src/levels/GroundGenerator/sol.tscn")
var player_res = preload("res://src/actors/Player.tscn")
var half_pipe_res = preload("res://src/levels/GroundGenerator/HalfPipe.tscn")
var tremplin_res = preload("res://src/levels/GroundGenerator/Tremplin.tscn")
var block_res= preload("res://src/levels/parts/StaticBody2DFish.tscn")

@export var slope_length = UNIT_SIZE*40
@export var ramp_length = UNIT_SIZE*15

#var max_gap = UNIT_SIZE * 10
@export var gap = UNIT_SIZE * 5 #Gap horizontale entre chaque ilot
#export var gap = [1000, UNIT_SIZE * 5,UNIT_SIZE * 5,UNIT_SIZE * 5] #Gap horizontale entre chaque ilot
@export var gap_offset = 7 #Gap verticale = gap_offset*UNIT_SIZE
@export var number_map: int = 4 # 2 #Nombre d'ilot sans trou généré sur la map

@export var height_ground = [200, 260, 280, 400]
@export var space_btw_grd_roof = [1300, 1100, 800, 600]


@export var slope_angle: float = 0
@export var coeff_pente: float = tan(deg_to_rad(slope_angle))

@export var random_seed: bool = false  # if true: overwrite world_seed and use a random one
@export var world_seed: String = "LEOOOOOO"
@export var noise_octaves: int = 1 #Number of OpenSimplex noise layers that are sampled to get the fractal noise. Higher values result in more detailed noise but take more time to generate.
@export var noise_period: int = 1000*0.7 #Period of the base octave. A lower period results in a higher-frequency noise (more value changes across the same distance).
@export var noise_persistence: float = 0.1 #Contribution factor of the different fractal_octaves. A persistence value of 1 means all the fractal_octaves have the same contribution, a value of 0.5 means each octave contributes half as much as the previous one.
@export var noise_lacunarity: float = 3 # Difference in period between fractal_octaves.

@export var is_boost: bool = false
@export var boost_treshold = -0.6 #if simplex_noise.get_noise_2d(x,0)<boost_treshold:
@export var is_igloo: bool = true
@export var igloo_treshold = 0.01 #ATTENTION -igloo_treshold<...<igloo_treshold


#func sum_gap(index):
#	# return sum of all gaps
#	var ss = 0
#	for idx in range(index):
#		ss += gap[idx]
#	return ss

func _ready():
	var next_pos = Vector2(0,0)
	
#	add_tremplin(Vector2(tan(deg2rad(32))*slope_length,-slope_length-ramp_length))
	add_tremplin(Vector2(-slope_length-ramp_length-gap,-tan(deg_to_rad(32))*slope_length))
	# set position pinpouin dans add_tremplin()
	
### GENERATION DES ILOTS
	for i in range(number_map):
		var is_final_map = (i == number_map -1)
#		print(is_final_map)
		if i == 0:
#			add_player(next_pos + UNIT_SIZE*Vector2(3,-5)
#			  +Vector2(-slope_length-ramp_length-gap,-tan(deg2rad(32))*slope_length)
#			)
			# send spawn position to LevelRandom
#			get_parent()._set_spawn_position(next_pos + UNIT_SIZE*Vector2(3,-5))
#			get_parent()._set_spawn_position(next_pos)
#			add_player(next_pos + UNIT_SIZE*Vector2(3,-5))
			next_pos = add_sol(next_pos, i, false)
			var _nocare = add_sol(next_pos + Vector2(0, -space_btw_grd_roof[i]), i, false)  # add roof to grab on
		else:
			var fuck_position = next_pos + i*gap*Vector2(1,0) + i*(map_width+UNIT_SIZE)*Vector2(1,0)+i*map_width*coeff_pente*Vector2(0,1) + i*gap_offset*UNIT_SIZE*Vector2(0,1)
#			var fuck_position = next_pos + sum_gap(i)*Vector2(1,0) + i*(map_width+UNIT_SIZE)*Vector2(1,0)+i*map_width*coeff_pente*Vector2(0,1) + i*gap_offset*UNIT_SIZE*Vector2(0,1)
			next_pos = add_sol(fuck_position, i, is_final_map)
			var _nocare = add_sol(fuck_position + Vector2(0, -space_btw_grd_roof[i]), i, is_final_map)
			
#			if gap[i] >= max_gap:  # max_gap
#				# genere des blocs pour hook
#				var end_of_previous = fuck_position.x - gap[i]
#				# determine number of block to put
#				var space_btw_block = 600
#				# -1 car trop facile sinon
#				var n_block = floor(gap[i] / space_btw_block) -1  
#				# split empty space to put them
#				print('Gap: ', gap[i])
#				print('Number of blocks: ', n_block)
#				for nb in range(1,n_block+1):
#					add_block(Vector2(end_of_previous,0) + Vector2(nb*gap[i]/(n_block+1), fuck_position.y-500))
			
### FIN GENERATION DES ILOTS
	if gap_offset == 0:
		add_half_pipe(next_pos + number_map*gap*Vector2(1,0) + number_map*(map_width+UNIT_SIZE)*Vector2(1,0)
				+number_map*map_width*coeff_pente*Vector2(0,1) + (number_map+1)*2*UNIT_SIZE*Vector2(0,1))
#		add_half_pipe(next_pos + Vector2(sum_gap(number_map)-gap[0],0)*Vector2(1,0) + number_map*(map_width+UNIT_SIZE)*Vector2(1,0)
#				+number_map*map_width*coeff_pente*Vector2(0,1) + (number_map+1)*2*UNIT_SIZE*Vector2(0,1))
#		breakpoint
	else:
		add_half_pipe(next_pos + number_map*gap*Vector2(1,0) + number_map*(map_width+UNIT_SIZE)*Vector2(1,0)
				+number_map*map_width*coeff_pente*Vector2(0,1) + (number_map+1)*gap_offset*UNIT_SIZE*Vector2(0,1))
#		add_half_pipe(next_pos + Vector2(sum_gap(number_map)-gap[0],0)*Vector2(1,0) + number_map*(map_width+UNIT_SIZE)*Vector2(1,0)
#				+number_map*map_width*coeff_pente*Vector2(0,1) + (number_map+1)*gap_offset*UNIT_SIZE*Vector2(0,1))
				
				
func add_sol(position:Vector2, i, is_final_map:bool):
	# i = numero de lilot
	var sol = sol_res.instantiate()
	var next_pos = Vector2.ZERO
	sol.set_collision_layer(2)
	
	sol.coeff_pente = coeff_pente
	
	sol.noise_octaves = noise_octaves
	sol.noise_period = noise_period
	sol.noise_persistence = noise_persistence
	sol.noise_lacunarity = noise_lacunarity
	
	sol.world_seed = world_seed
	if random_seed:
		# [FANTÔMES] graine tirée du seed de course (avant : randi()) -> terrain rejouable à l'identique
		var new_seed = str(rand_from_seed(RaceManager.next_seed_index())[1])
		print('Random seed: ', new_seed)
		sol.world_seed = new_seed
#		breakpoint
	sol.is_boost = is_boost
	sol.boost_treshold = boost_treshold
	sol.is_igloo = is_igloo
	sol.igloo_treshold = igloo_treshold
	sol.is_final_map = is_final_map
	
	sol.map_width = map_width
	sol.map_height = max_height
	sol.position = position
	sol.h = height_ground[i]
#	print(sol.noise_period) 
	add_child(sol)
	next_pos = Vector2(0,0)
#	print(next_pos)
	return next_pos

func add_player(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var player = player_res.instantiate()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	player.global_position = position
	add_child(player)
	
func add_half_pipe(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var half_pipe = half_pipe_res.instantiate()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	half_pipe.global_position = position
	add_child(half_pipe)
	
func add_tremplin(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var tremplin = tremplin_res.instantiate()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	tremplin.global_position = position
	add_child(tremplin)
	get_parent()._set_spawn_position(position+Vector2(300,-100))
	print('position player set by GroundGenerator when tremplin called')

#	add_child(player)  # faire un script sur LevelRandom.gd pour instancier joueur
#	get_parent().call_deferred("add_child", player)  # faire un script sur LevelRandom.gd pour instancier joueur


func add_block(position: Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var block = block_res.instantiate()
	print('Add block to: ',position)
	block.position = position
	add_child(block)
