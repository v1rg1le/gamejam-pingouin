extends Control
# =============================================================================
#  SplashIntro.gd — [DÉMARRAGE 1.15] Pinpouin se prépare (choix de l'équipe)
# -----------------------------------------------------------------------------
#  Demande : remplacer l'écran Godot du lancement par une image de Pinpouin.
#  L'équipe a retenu DEUX propositions, affichées à la suite :
#   1. Écran de démarrage du moteur (réglages application/boot_splash/* du
#      projet) : « logo sur fond nuit » (sprites/screens/splash_boot_nuit.png).
#      Il s'affiche pendant le chargement, sur tous les formats d'écran grâce
#      à son fond uni (même couleur que la bordure).
#   2. Puis CETTE intro, en fondu depuis la même couleur nuit : « Pinpouin prêt
#      au départ » (sprites/screens/splash_intro_banquise.png), ~1,5 s, avant
#      que l'écran titre n'apparaisse.
#  Les deux images sont des montages des sprites existants du jeu (logo,
#  Pinpouin, igloo, glaçons, grappin) : aucun asset d'origine n'est modifié.
#  L'image d'intro fait 432 × 180 pixels (plus large que 16/9) : affichée en
#  « remplir l'écran », elle couvre aussi les téléphones allongés (20/9) sans
#  bandes ni rognage du logo.
#  Un appui (toucher, touche, clic, manette ; pas les touches de volume) passe
#  l'intro. Elle n'est jouée qu'une fois par lancement du jeu.
#  Ajoutée par MainScreen.gd (la scène principale ne change pas).
# =============================================================================

const NIGHT := Color(18 / 255.0, 22 / 255.0, 46 / 255.0)   # = fond du splash de démarrage
const FADE_IN := 0.45      # s : apparition de l'image depuis le fond nuit
const HOLD := 1.5          # s : image affichée
const FADE_OUT := 0.5      # s : disparition, on découvre l'écran titre

static var already_shown := false   # une seule fois par lancement

var _tween: Tween
var _leaving := false


## Ajoute l'intro par-dessus `parent` si elle n'a pas encore été jouée.
static func play_once(parent: Control) -> void:
	if already_shown:
		return
	already_shown = true
	var intro = load("res://src/screens/SplashIntro.gd").new()
	parent.add_child(intro)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # le bouton de l'écran titre ne reçoit rien pendant l'intro
	z_index = 100
	var back := ColorRect.new()
	back.color = NIGHT
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	var pic := TextureRect.new()
	pic.texture = load("res://sprites/screens/splash_intro_banquise.png")
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # pixel-art net
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.modulate.a = 0.0
	add_child(pic)
	_tween = create_tween()
	_tween.tween_property(pic, "modulate:a", 1.0, FADE_IN)
	_tween.tween_interval(HOLD)
	_tween.tween_callback(_leave)


func _input(event: InputEvent) -> void:
	# on « mange » tous les appuis : l'écran titre ne doit pas partir en même temps
	if Settings.is_continue_press(event):
		get_viewport().set_input_as_handled()
		_leave()
	elif event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey:
		get_viewport().set_input_as_handled()


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	if _tween:
		_tween.kill()
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, FADE_OUT)
	t.tween_callback(queue_free)
