extends Control

const tracks = [
	"res://assets/musics/2020-03-22_-_8_Bit_Surf_-_FesliyanStudios.com_-_David_Renda.wav"
]

const main_theme = "res://assets/musics/2020-03-22_-_A_Bit_Of_Hope_-_David_Fesliyan.wav"

# Load the music player node
@onready var _music_player = $AudioStreamPlayer
var track
var track_path
var play_stopped = false

var music_on = true # false #  true

func _ready():
	# non, pour l'instant musique se lance avec WelcomeScreen
	# a decommenter pour que la musique se lance avec le jeu
	play(main_theme)
#	pass

# Calling this function will load the given track, and play it
func play(track_url : String = ""):
	if track_url.is_empty(): # si musique non precisee  [MIGRATION] test explicite de chaîne vide
		# selectionne une chanson au hasard dans le dossier
		var rand_nb = randi() % tracks.size()
		track_url = tracks[rand_nb]

	track_path = track_url
	track = load(track_url)
	_music_player.stream = track
	_music_player.play()
	play_stopped = false

# Calling this function will stop the music
func stop():
	_music_player.stop()
	play_stopped = true

func music_onoff():
	_music_player.playing = !_music_player.playing
	play_stopped = !play_stopped
	if music_on:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), -80)
		music_on = false
	else:
		# [OPTIONS 1.7] on revient au volume choisi dans les Options (au lieu de -6 dB fixe)
		Settings.apply_music_volume()
		music_on = true

func is_playing_main_theme():
	if _music_player.playing == true and track_path == main_theme:
		return true
	else:
		return false

func _on_AudioStreamPlayer_finished():
	# quand son finit, lance une chanson au hasard 	
	if !play_stopped: # hormis si son arrete manuelement
		play()
