extends Node2D

const UNIT_SIZE = 64
const map_width = UNIT_SIZE*300
const max_height = UNIT_SIZE*3

var sol_res = preload("res://src/levels/GroundGenerator/sol.tscn")
export var gap = UNIT_SIZE * 5
export var gap_offset = 7
export(int) var number_map = 5

export(float) var coeff_pente = 0.2

export(int) var noise_octaves = 1
export(int) var noise_period = 1000*0.7
export(float) var noise_persistence = 0.2
export(float) var noise_lacunarity = 3

export(bool) var is_boost = true
export var boost_treshold = -0.5
export(bool) var is_igloo = true
export var igloo_treshold = 0.01 #ATTENTION -igloo_treshold<...<igloo_treshold

func _ready():
	var next_pos = Vector2(0,0)
	for i in range(number_map):
		if i == 0:
			next_pos = add_sol(next_pos)
		else:
			next_pos = add_sol(
				next_pos + i*gap*Vector2(1,0) + i*(map_width+UNIT_SIZE)*Vector2(1,0)
				+i*map_width*coeff_pente*Vector2(0,1) + i*gap_offset*UNIT_SIZE*Vector2(0,1)
				)

func add_sol(position :Vector2):
	var sol = sol_res.instance()
	var next_pos = Vector2.ZERO
	sol.set_collision_layer(2)
	
	sol.coeff_pente = coeff_pente
	
	sol.noise_octaves = noise_octaves
	sol.noise_period = noise_period
	sol.noise_persistence = noise_persistence
	sol.noise_lacunarity = noise_lacunarity
	
	sol.is_boost = is_boost
	sol.boost_treshold = boost_treshold	
	sol.is_igloo = is_igloo
	sol.igloo_treshold = igloo_treshold
	
	sol.map_width = map_width
	sol.map_height = max_height
	sol.position = position
#	print(sol.noise_period) 
	add_child(sol)
	next_pos = Vector2(0,0)
#	print(next_pos)
	return next_pos
