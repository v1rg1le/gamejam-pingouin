extends Node2D

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
	player.global_position = spawn_position
	print(spawn_position)
	add_child(player)  # faire un script sur LevelRandom.gd pour instancier joueur
#	get_parent().call_deferred("add_child", player)  # faire un script sur LevelRandom.gd pour instancier joueur
