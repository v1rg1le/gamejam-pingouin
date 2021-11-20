extends Node2D

var block_res= preload("res://src/levels/parts/Block.tscn")
var boost_res = preload("res://src/levels/boost/BoostArea.tscn")
var quarter_res = preload("res://src/levels/GroundGenerator/QuarterPipe.tscn")
var half_pipe_res = preload("res://src/levels/GroundGenerator/HalfPipe.tscn")

# Ground Generator
# const map_width = UNIT_SIZE*60 #Largeur des ilots
# const max_height = UNIT_SIZE*2
# export var gap = UNIT_SIZE * 7 #Gap horizontale entre chaque ilot
# export var gap_offset = 10 #Gap verticale = gap_offset*UNIT_SIZE
# export(int) var number_map = 5 #Nombre d'ilot sans trou généré sur la map
# export(int) var number_stage = 5
# export(float) var max_height = UNIT_SIZE*7 

const UNIT_SIZE = 64
export(float) var map_height = UNIT_SIZE*50 #ATTENTION PAS TROP HAUT SINON CA PLANTE
export(float) var rayon = UNIT_SIZE*45
export(float,0,90) var out_angle = 45


# Called when the node enters the scene tree for the first time.
func _ready():
	var offset = UNIT_SIZE*Vector2(-5,5)
	add_res(Vector2(10000,2790)+offset,"quarter")
	#QUELQUES TRUC A HOOK
	for i in range(4):
		add_res(Vector2(11900, 1100)+UNIT_SIZE*Vector2(10*i,0),"block")
		
	for j in range(8):
		if j!=1:
			add_res(Vector2(11900, 1100)+UNIT_SIZE*Vector2(30,j*5),"block")
		add_res(Vector2(11900, 1100)+UNIT_SIZE*Vector2(40,j*5),"block")

	add_res(Vector2(11900, 1100)+UNIT_SIZE*Vector2(30,50),"half_pipe")
	pass # Replace with function body.

func add_res(position :Vector2,res_name:String):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var res
	match res_name:
		"block":
			res = block_res.instance()
			res.global_position = position
		"boost":
			res = boost_res.instance()
			res.impulse_mode = true
			res.global_position = position
		"quarter":
			res = quarter_res.instance()
#			res.taille = taille
			res.map_height = UNIT_SIZE*20
			res.rayon = UNIT_SIZE*15
#			res.rayon = rayon
			res.out_angle = 0
			res.rotation = deg2rad(-40)
			res.global_position = position
		"half_pipe":
			res = half_pipe_res.instance()
			res.global_position = position
	add_child(res)
# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
