extends Node

# Load the music player node
onready var _sound_player = $SoundStreamPlayer
onready var _sound_player_2 = $SoundStreamPlayer2
onready var _ui_sound_player = $UISoundStreamPlayer
var sound
var play_stopped = false

var sound_on = true
#var sounds_call = [[],[]]
#var sounds_thanks = [[],[]]
#var sounds_grab = []
#var sounds_launched = []

var sounds_call = [[preload("res://assets/sounds/call_casquette/casquette_01.ogg"),
					preload("res://assets/sounds/call_casquette/casquette_02.ogg"),
					preload("res://assets/sounds/call_casquette/casquette_03.ogg"),
					preload("res://assets/sounds/call_casquette/casquette_04.ogg"),
					preload("res://assets/sounds/call_casquette/casquette_joder_damela_01.ogg"),
					preload("res://assets/sounds/call_casquette/casquette_maintenant_01.ogg"),
					preload("res://assets/sounds/call_casquette/casquette_plus_vite.ogg"),
					preload("res://assets/sounds/call_casquette/casquette_urgent_01.ogg"),
					preload("res://assets/sounds/call_casquette/casquette_urgent_02.ogg")
					],\
					[preload("res://assets/sounds/call_poncho/poncho_01.ogg"),
					preload("res://assets/sounds/call_poncho/poncho_2.ogg"),
					preload("res://assets/sounds/call_poncho/poncho_03.ogg"),
					preload("res://assets/sounds/call_poncho/poncho_04.ogg"),
					preload("res://assets/sounds/call_poncho/poncho_05.ogg"),
					preload("res://assets/sounds/call_poncho/poncho_ahah_01.ogg"),
					preload("res://assets/sounds/call_poncho/poncho_gentil_01.ogg"),
					preload("res://assets/sounds/call_poncho/poncho_grosse_voie_01.ogg"),
					preload("res://assets/sounds/call_poncho/poncho_popopo.ogg"),
					preload("res://assets/sounds/call_poncho/poncho_pour_moi_01.ogg")
					]]

var sounds_thanks = [[preload("res://assets/sounds/thanks_casquette/gracias_01.ogg"),
						preload("res://assets/sounds/thanks_casquette/merci_01.ogg"),
						preload("res://assets/sounds/thanks_casquette/merci_beaucoup_01.ogg"),
						preload("res://assets/sounds/thanks_casquette/ohoh_01.ogg"),
						preload("res://assets/sounds/thanks_casquette/youhou_01.ogg")
					],
					[preload("res://assets/sounds/thanks_poncho/gracias_01.ogg"),
					preload("res://assets/sounds/thanks_poncho/merci_01.ogg"),
					preload("res://assets/sounds/thanks_poncho/merci_beaucoup_01.ogg"),
					preload("res://assets/sounds/thanks_poncho/merci_poncho_01.ogg"),
					preload("res://assets/sounds/thanks_poncho/ohoh_01.ogg"),
					preload("res://assets/sounds/thanks_poncho/youhou_01.ogg")
					]]

var sounds_grab = [preload("res://assets/sounds/grab/grab_meh_01.ogg"),
					preload("res://assets/sounds/grab/grab_ohohoh_01.ogg"),
					preload("res://assets/sounds/grab/grab_oh_01.ogg")
					]


var sounds_launched = [preload("res://assets/sounds/launched/launched_01.ogg")]

func _ready():
	# coupe les sons (car ca casse les couilles)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Sound"), 0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("UI"), -6)
#	pass
#	_load_all_sounds()


func _load_all_sounds():
	var files = get_files("res://assets/sounds/call_casquette/")
	for current_sound in files:
		sounds_call[0].append(load(current_sound))
#		sounds_call[0].append(current_sound)
		
	files = get_files("res://assets/sounds/call_poncho/")
	for current_sound in files:
		sounds_call[1].append(load(current_sound))
		
	files = get_files("res://assets/sounds/thanks_casquette/")
	for current_sound in files:
		sounds_thanks[0].append(load(current_sound))
		
	files = get_files("res://assets/sounds/thanks_poncho/")
	for current_sound in files:
		sounds_thanks[1].append(load(current_sound))

	files = get_files("res://assets/sounds/grab/")
	for current_sound in files:
		sounds_grab.append(load(current_sound))
		
	files = get_files("res://assets/sounds/launched/")
	for current_sound in files:
		sounds_launched.append(load(current_sound))
		
#	files = get_files("res://assets/sounds/grab_poncho/")
#	for sound in files:
#		sounds_grab.append(load(sound))





func get_files(path):
	var files = []
	var dir = Directory.new()
	dir.open(path)
	dir.list_dir_begin()
	
	print("NE marche pas avec export des .ogg")
#	print("Get files at: ", path)

	while true:
		var file = dir.get_next()
#		print("file: ", file)
		if file == "":
#			pass
			break
		# a remettre pour jouer DANS GODOT 
		elif file.ends_with(".import"):  
			continue
#			files.append(path+file)
#			print("> IMPORT: file added: ", path + file)
		elif not file.begins_with("."):
#			continue
			files.append(path+file)
###			sounds.append(preload(path+file))
			print("file added: ", path + file)

	dir.list_dir_end()

	return files

func sound_play(sound_url):
	sound = load(sound_url)
	_sound_player.stream = sound
	_sound_player.play()

func sound_random(value:int, dico:String):
	# play random sound
#	sounds.shuffle()
#	_sound_player.stream = sounds.front()
	
	var sound_player 
	if _sound_player.playing:  # si 1er entrain de jouer un son, on prend le 2eme
		sound_player = _sound_player_2
	else:  # par default le 1er
		sound_player = _sound_player
	
	# value = 1: casquette, 2 = poncho
	# dico = want to buy, after buy, grab
	if dico == "want_to_buy":
		sounds_call[value-1].shuffle()
		sound_player.stream = sounds_call[value-1].front()
#		sound_player.stream = call_casquette[0]
		sound_player.play()
	elif dico == "after_buy":
		sounds_thanks[value-1].shuffle()
		sound_player.stream = sounds_thanks[value-1].front()
		sound_player.play()
	elif dico == "grab":
		sounds_grab.shuffle()
		sound_player.stream = sounds_grab.front()
		sound_player.play()
	elif dico == "launched":
		sounds_launched.shuffle()
		sound_player.stream = sounds_launched.front()
		sound_player.play()

#	print(sound_player.stream)

func ui_play(sound_url):
	sound = load(sound_url)
#	sound = load(call_casquette[0])
	_ui_sound_player.stream = sound
	_ui_sound_player.play()
#	play_stopped = false
	


func ui_stop():
	_ui_sound_player.stop()
	play_stopped = true

func sound_onoff():
	# pas beacoup de sens car les sons s'arretent apres etre jouer une fois
	# il faudra reduire le son à -100 dB pour off et remonter à -6dB pour on 
	_sound_player.playing = !_sound_player.playing
	_sound_player_2.playing = !_sound_player_2.playing
	_ui_sound_player.playing = !_ui_sound_player.playing
	if sound_on:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Sound"), -80)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("UI"), -80)
		sound_on = false
		_ui_sound_player.stream = null  # delete dernier son pour pas repeter lors de lallumage

	else:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Sound"), -6)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("UI"), -6)
		sound_on = true

func _on_UISoundStreamPlayer_finished():
#	if !play_stopped: # hormis si son arrete manuelement
#	ui_stop()
#	_ui_sound_player.stop()
	_ui_sound_player.stream = null


func _on_SoundStreamPlayer_finished():
	_sound_player.stream = null
#	_sound_player.stop()


func _on_SoundStreamPlayer2_finished():
	_sound_player_2.stream = null
