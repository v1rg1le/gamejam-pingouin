extends Node2D

const UNIT_SIZE = 64 #Taille du joeur

## A chercher dans ground_generator
var slope_length = UNIT_SIZE*40
var entering_slope_angle = -32.0
var entering_coeff_pente = tan(deg2rad(entering_slope_angle))
var exiting_slope_angle = 20.0
var exiting_coeff_pente = tan(deg2rad(exiting_slope_angle))
export var ramp_length = UNIT_SIZE*12
var gap = UNIT_SIZE * 5

var player_res = preload("res://src/actors/Player.tscn")
var spawn_position = Vector2.ZERO

func _ready():
	# ajout player
	add_player()

func _set_spawn_position(position: Vector2):
	if spawn_position == Vector2.ZERO:
		spawn_position = position

func add_player():
	var player = player_res.instance()
	_set_spawn_position(UNIT_SIZE*Vector2(3,-5)
		-Vector2(1,0)*(slope_length+ramp_length+gap)
			+Vector2(0,1)*slope_length*entering_coeff_pente
	)
	player.global_position = spawn_position
#	print(spawn_position)
	add_child(player)  # faire un script sur LevelRandom.gd pour instancier joueur
#	get_parent().call_deferred("add_child", player)  # faire un script sur LevelRandom.gd pour instancier joueur
