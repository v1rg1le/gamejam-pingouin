extends Control

@onready var pic1 = get_node("TextureRectAnim")
@onready var pic2 = get_node("TextureRectAnim2")
@onready var pic3 = get_node("TextureRectAnim3")

# [ACCUEIL 1.9] Retour de l'équipe : « sur mobile, la disposition de l'écran
# d'accueil est cassée, le bouton se retrouve dans Pinpouin ».
# Cause : toutes les images de l'écran sont des carrés de 256 × 256 px (même
# canevas, superposés), mais elles n'étaient pas agrandies de la même façon :
#  - le titre et le pingouin animé en mode « couvrir l'écran » (stretch 6) :
#    sur un écran large de téléphone (20/9), ils sont fortement agrandis et
#    rognés en haut et en bas ;
#  - le bouton « appuie pour jouer » en mode « tenir dans l'écran » (stretch 5) :
#    plus petit et centré.
# Résultat : le bouton ne tombait plus sous le titre mais en plein dessus.
# Correction : on place NOUS-MÊMES les 5 images au même endroit et à la même
# taille, calculées pour que la zone utile du dessin (lignes 60 à 235 du
# canevas : pingouin, titre et bouton) tienne toujours dans l'écran, centrée,
# quel que soit son format (PC 1024 × 720, téléphone 20/9, tablette 4/3…).
const CANVAS = 256.0                       # taille des images de l'écran titre
const USEFUL_TOP = 60.0                    # 1re ligne utile du dessin
const USEFUL_BOTTOM = 235.0                # dernière ligne utile (bas du bouton)


func _ready():
	_layout()
	# [DÉMARRAGE 1.15] intro « Pinpouin prêt au départ » au lancement du jeu
	# ([1.24] réduite à un fondu depuis la couleur nuit : voir SHOW_INTRO_IMAGE)
	# (une seule fois), juste après l'écran de démarrage « logo nuit »
	load("res://src/screens/SplashIntro.gd").play_once(self)
	get_viewport().size_changed.connect(_layout)


func _layout() -> void:
	var view: Vector2 = get_viewport_rect().size
	var useful_h := USEFUL_BOTTOM - USEFUL_TOP
	# la plus grande échelle qui fait tenir la zone utile en hauteur ET le
	# canevas en largeur (petite marge de 4 %)
	var s := minf(view.x / CANVAS, view.y / useful_h) * 0.96
	var size := Vector2(CANVAS, CANVAS) * s
	var center_row := (USEFUL_TOP + USEFUL_BOTTOM) * 0.5
	var pos := Vector2((view.x - size.x) * 0.5, view.y * 0.5 - center_row * s)
	for node in [pic1, pic2, pic3, $TextureRect, $TextureButton]:
		node.set_anchors_preset(Control.PRESET_TOP_LEFT)
		node.position = pos
		node.size = size
		if node is TextureRect:
			node.stretch_mode = TextureRect.STRETCH_SCALE
		else:
			node.stretch_mode = TextureButton.STRETCH_SCALE

func _unhandled_input(event: InputEvent) -> void:
	# [MOBILE] un toucher d'écran compte aussi comme "appuyer sur une touche"
	# [ENTRÉES 1.14] tri commun dans Settings.is_continue_press : sur téléphone
	# seul un toucher (ou une manette) compte, plus les boutons de volume.
	if Settings.is_continue_press(event):
		if true:  # (bloc conservé tel quel : même indentation qu'avant)
			var error = get_tree().change_scene_to_file("res://src/screens/LevelSelectionScreen.tscn")
			if error != 0:
					print("ERROR: ", error)


func _on_TextureButton_button_up():
	var error = get_tree().change_scene_to_file("res://src/screens/LevelSelectionScreen.tscn")
	if error != 0:
		print("ERROR: ", error)


func do_fucking_animation_pinpouin():
	# de l'importance de faire les dessins dans la meme resolution
	# @Lory-Ann Lehmann
	if pic1.visible:
		pic1.visible = false
		pic2.visible = true
	elif pic2.visible:
		pic2.visible = false
		pic3.visible = true
	elif pic3.visible:
		pic3.visible = false
		pic1.visible = true

func _on_AnimationTimer_timeout():
	do_fucking_animation_pinpouin()
