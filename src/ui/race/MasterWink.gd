extends Control
# =============================================================================
#  MasterWink.gd — [MAÎTRE 1.19] le maître ninja qui fait un clin d'œil
# -----------------------------------------------------------------------------
#  Demande de l'équipe : « le Pinpouin ninja, le maître, qui était censé
#  poper d'un coin de l'écran et faire un clin d'œil, à chaque figure ;
#  activable / désactivable dans les Options ».
#  Le code d'origine n'a pas été retrouvé dans l'historique git (aucune
#  branche ne le contient). On a en revanche retrouvé le dessin du maître :
#  sprites/screens/bad_penguin_1/2/3.png (64 × 64, le bandeau flotte au vent),
#  qui servait à l'écran titre des toutes premières versions et n'était plus
#  utilisé. Il est réutilisé tel quel. Une seule image a été AJOUTÉE :
#  bad_penguin_wink.png, copie de bad_penguin_1 avec l'œil droit fermé.
#
#  Déroulé (≈ 1,2 s) :
#   1. le maître glisse depuis le bord droit de l'écran, un peu penché ;
#   2. son bandeau flotte (les 3 images en boucle) ;
#   3. clin d'œil (image « wink ») ;
#   4. il repart vers le bord.
#  Une nouvelle figure pendant l'animation la relance (pas d'empilement).
#  Déclenché par RaceHud.show_master_wink(), appelé par RaceManager quand
#  TrickScore valide des points (atterrissage propre après une figure ou une
#  vrille). Réglage : Settings.master_wink (Options → « Clin d'œil du maître »).
# =============================================================================

const FRAMES = [
	"res://sprites/screens/bad_penguin_1.png",
	"res://sprites/screens/bad_penguin_2.png",
	"res://sprites/screens/bad_penguin_3.png",
]
const WINK = "res://sprites/screens/bad_penguin_wink.png"
const SIZE := 160.0          # taille affichée (unités du HUD) : 64 px × 2,5
const SLIDE_TIME := 0.22     # s : entrée et sortie
const STAY_TIME := 0.75      # s : présence à l'écran
const WINK_AT := 0.3         # s après l'entrée : début du clin d'œil
const WINK_TIME := 0.3       # s : durée du clin d'œil
const FRAME_TIME := 0.12     # s : bandeau au vent (une image toutes les 0,12 s)

var _pic: TextureRect
var _textures: Array = []
var _wink_tex: Texture2D
var _tween: Tween
var _t := 0.0                # temps depuis l'entrée
var _active := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for path in FRAMES:
		_textures.append(load(path))
	_wink_tex = load(WINK)
	_pic = TextureRect.new()
	_pic.texture = _textures[0]
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # pixel-art net
	_pic.size = Vector2(SIZE, SIZE)
	_pic.pivot_offset = Vector2(SIZE, SIZE)   # pivote depuis son coin bas-droit
	_pic.rotation_degrees = -12.0
	_pic.flip_h = true                        # il regarde vers l'intérieur de l'écran
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pic.visible = false
	add_child(_pic)


## Lance (ou relance) l'apparition du maître.
func play() -> void:
	var view: Vector2 = size
	# bord droit, un peu au-dessus du milieu : loin du chrono (haut gauche),
	# du classement (haut droite) et des boutons tactiles (bas de l'écran)
	var y: float = view.y * 0.30
	var hidden_x: float = view.x + 10.0
	var shown_x: float = view.x - SIZE * 0.85   # il dépasse à moitié, comme s'il passait la tête
	_t = 0.0
	_active = true
	_pic.visible = true
	_pic.position = Vector2(hidden_x, y)
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_pic, "position:x", shown_x, SLIDE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(STAY_TIME)
	_tween.tween_property(_pic, "position:x", hidden_x, SLIDE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func():
		_active = false
		_pic.visible = false)


func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	var winking: bool = _t >= SLIDE_TIME + WINK_AT and _t < SLIDE_TIME + WINK_AT + WINK_TIME
	if winking:
		_pic.texture = _wink_tex
	else:
		_pic.texture = _textures[int(_t / FRAME_TIME) % _textures.size()]
