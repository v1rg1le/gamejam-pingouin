extends Node2D

const UNIT_SIZE = 64 #Taille du joeur
const map_width = UNIT_SIZE*300 #Largeur des ilots
const max_height = UNIT_SIZE*3 #Hauteur des bosses

var sol_res = preload("res://src/levels/GroundGenerator/sol.tscn")
var player_res = preload("res://src/actors/Player.tscn")
var half_pipe_res = preload("res://src/levels/GroundGenerator/HalfPipe.tscn")
var tremplin_res = preload("res://src/levels/GroundGenerator/Tremplin.tscn")
var block_res= preload("res://src/levels/parts/StaticBody2DFish.tscn")

export var slope_length = UNIT_SIZE*40
export var ramp_length = UNIT_SIZE*15

#var max_gap = UNIT_SIZE * 10
export var gap = UNIT_SIZE * 5 #Gap horizontale entre chaque ilot
#export var gap = [1000, UNIT_SIZE * 5,UNIT_SIZE * 5,UNIT_SIZE * 5] #Gap horizontale entre chaque ilot
export var gap_offset = 7 #Gap verticale = gap_offset*UNIT_SIZE
export(int) var number_map = 4 # 2 #Nombre d'ilot sans trou généré sur la map

export var height_ground = [200, 260, 280, 400]
export var space_btw_grd_roof = [1300, 1100, 800, 600]


export(float) var slope_angle = 0
export(float) var coeff_pente = tan(deg2rad(slope_angle))

export(bool) var random_seed = false  # if true: overwrite world_seed and use a random one
export(String) var world_seed = "LEOOOOOO"
export(int) var noise_octaves = 1 #Number of OpenSimplex noise layers that are sampled to get the fractal noise. Higher values result in more detailed noise but take more time to generate.
export(int) var noise_period = 1000*0.7 #Period of the base octave. A lower period results in a higher-frequency noise (more value changes across the same distance).
export(float) var noise_persistence = 0.1 #Contribution factor of the different octaves. A persistence value of 1 means all the octaves have the same contribution, a value of 0.5 means each octave contributes half as much as the previous one.
export(float) var noise_lacunarity = 3 # Difference in period between octaves.

export(bool) var is_boost = false
export var boost_treshold = -0.6 #if simplex_noise.get_noise_2d(x,0)<boost_treshold:
export(bool) var is_igloo = true
export var igloo_treshold = 0.01 #ATTENTION -igloo_treshold<...<igloo_treshold


func _ready():
	var next_pos = Vector2(0,0)
	add_tremplin(Vector2(-slope_length-ramp_length-gap*4,-tan(deg2rad(32))*slope_length))
	# set position pinpouin dans add_tremplin()
	
	var all_end_pos = []
### GENERATION DES ILOTS
#	for i in range(number_map):
	var i = 0
	var is_final_map = (i == number_map -1)


		# au lieu de rajouter qu'un sol
		# spam plusieurs spaghettis en arc de cercle :
		#o    |
		#    /
		# __
		
		# avec differentes pentes 
	for sp in range(3):  # for X spaghettis
		var extra_start = Vector2(200, 0)
		
#				if sp == 0:
#					extra_start = Vector2(200, 0)
		if sp == 1:
			extra_start = Vector2(0, 300)
		elif sp == 2:
			extra_start = Vector2(-500, 500)
		
		coeff_pente = sp * 0.05
		
		var position_deb = next_pos + i*gap*Vector2(1,0) + i*(map_width+UNIT_SIZE)*Vector2(1,0)+i*map_width*coeff_pente*Vector2(0,0) + i*gap_offset*UNIT_SIZE*Vector2(0,1)
		all_end_pos.append(add_sol(position_deb+extra_start, i, is_final_map))
	
	print(all_end_pos)
	var iter_index = 0
	for ep in all_end_pos:
		
		print(ep)
		for sp in range(3):  # for X spaghettis
			var extra_start = Vector2(200, 0)
			
#				if sp == 0:
#					extra_start = Vector2(200, 0)
			if sp == 1:
				extra_start = Vector2(0, 300)
			elif sp == 2:
				extra_start = Vector2(-500, 500)
			
			coeff_pente = sp * 0.1 + .2 * iter_index
			
#			all_end_pos.append(add_sol(ep+extra_start, 1, false))
			var _popo = add_sol(ep+extra_start, 1, false)
#			if sp == 0:  # toit seulement pour spaghetti du haut
#				var _nocare = add_sol(ep + Vector2(0, -space_btw_grd_roof[1]), 1, false)
		iter_index += 1
	breakpoint
	print('faire une arrivee jolie + un mur/tobogan pour pas la depasser')

### FIN GENERATION DES ILOTS

	add_half_pipe(next_pos + number_map*gap*Vector2(1,0) + number_map*(map_width+UNIT_SIZE)*Vector2(1,0)
			+number_map*map_width*coeff_pente*Vector2(0,1) + (number_map+1)*gap_offset*UNIT_SIZE*Vector2(0,1))
				
				
func add_sol(position:Vector2, i, is_final_map:bool):
	# i = numero de lilot
	var sol = sol_res.instance()
	var next_pos = Vector2.ZERO
	sol.set_collision_layer(2)
	
	sol.coeff_pente = coeff_pente
	
	sol.noise_octaves = noise_octaves
	sol.noise_period = noise_period
	sol.noise_persistence = noise_persistence
	sol.noise_lacunarity = noise_lacunarity
	
	sol.world_seed = world_seed
	if random_seed:
		var new_seed = str(rand_seed(randi()%200)[1])
		print('Random seed: ', new_seed)
		sol.world_seed = new_seed
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
#	return next_pos
	# return end position car the next spaghettis
	var end_pos = position + Vector2(map_width, coeff_pente*map_width)
	return end_pos
	

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
	get_parent()._set_spawn_position(position+Vector2(300,-100))
	print('position player set by GroundGenerator when tremplin called')

#	add_child(player)  # faire un script sur LevelRandom.gd pour instancier joueur
#	get_parent().call_deferred("add_child", player)  # faire un script sur LevelRandom.gd pour instancier joueur


func add_block(position: Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var block = block_res.instance()
	print('Add block to: ',position)
	block.position = position
	add_child(block)
