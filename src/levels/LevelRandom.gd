extends Node2D

var player_res = preload("res://src/actors/Player.tscn")
var spawn_position = Vector2.ZERO

func _ready():
	# ajout player
	add_only_one_player()

func _set_spawn_position(position: Vector2):
	if spawn_position == Vector2.ZERO:
		spawn_position = position

func add_player():
	var player = player_res.instance()
	player.global_position = spawn_position
	print(spawn_position)
	get_parent().call_deferred("add_child", player)

func add_only_one_player():
	var player = player_res.instance()
	player.global_position = spawn_position
	if !get_parent().has_node("Player"):
		print("No player yet")
		get_parent().call_deferred("add_child", player)  # faire un script sur LevelRandom.gd pour instancier joueur
	else:
		print("Already has a player !")
