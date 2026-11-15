extends Node2D
# =============================================================================
#  FinishGate.gd — ligne d'arrivée
# -----------------------------------------------------------------------------
#  [MIGRATION GODOT 4.7] change_scene() -> change_scene_to_file()
#
#  [ARRIVÉE PLUS ÉVIDENTE / IMPOSSIBLE À RATER]  (nouveau)
#   Avant : une zone de 128 x 128 px autour de l'arche. Le pingouin étant
#   presque toujours en l'air, il passait au-dessus sans la toucher.
#   Maintenant :
#   1. La zone de détection est une BANDE VERTICALE très haute
#      (finish_band_height) : franchir la ligne à n'importe quelle altitude
#      au-dessus de l'arche compte.
#   2. Sécurité anti-"traversée" : si le pingouin passe de la gauche à la
#      droite de la ligne entre deux frames (vitesse énorme, respawn...),
#      l'arrivée est validée quand même.
#   3. Seul le pingouin déclenche l'arrivée (avant : n'importe quel corps,
#      y compris le crochet du grappin).
#   4. Repère visuel : un faisceau lumineux pulsant + le texte "ARRIVÉE"
#      au-dessus de l'arche, visibles de loin (surtout avec le dézoom).
#   5. Petit ralenti de victoire avant de revenir à la sélection des niveaux.
#  Les sprites de l'arche d'origine sont conservés tels quels.
# =============================================================================

## Hauteur (px) de la zone d'arrivée au-dessus de l'arche.
@export var finish_band_height: float = 6000.0
## Profondeur (px) de la zone sous l'arche (pour les arrivées un peu basses).
@export var finish_band_below: float = 400.0
## [ARRIVÉE 1.13] Décalage horizontal (px) de la LIGNE de détection par
## rapport à l'arche (négatif = plus tôt). Utilisé par le half-pipe final :
## l'arche reste posée sur le deck, mais la ligne est descendue dans la
## courbe de droite, pour qu'un pingouin qui n'a pas assez d'élan pour
## sortir du half-pipe (il reste collé en haut du mur vertical) arrive quand
## même. Valeur 0 = comportement d'avant.
@export var trigger_offset_x: float = 0.0
## Largeur (px) de la zone d'arrivée.
@export var finish_band_width: float = 200.0
## Affiche le faisceau + le texte "ARRIVÉE".
@export var show_beacon: bool = true
## Scène chargée après l'arrivée.
@export_file("*.tscn") var next_scene_path: String = "res://src/screens/LevelSelectionScreen.tscn"

var _finished := false
var _player_prev_x = null
var _beacon: Polygon2D
var _time := 0.0


func _ready() -> void:
	add_to_group("finish_gate")  # [FANTÔMES] RaceManager sait ainsi que le niveau a une arrivée
	# 1. Bande verticale de détection (remplace le carré de 128 px)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(finish_band_width, finish_band_height + finish_band_below)
	$Area2D/CollisionShape2D.shape = shape
	$Area2D/CollisionShape2D.position = Vector2(trigger_offset_x, (finish_band_below - finish_band_height) * 0.5)
	$Area2D.collision_mask = 1  # calque 1 = "player"
	# 4. Repère visuel
	if show_beacon:
		_build_beacon()


func _build_beacon() -> void:
	# Faisceau : un simple polygone semi-transparent, dégradé via vertex colors
	# (aucun nouvel asset graphique nécessaire).
	_beacon = Polygon2D.new()
	var w := finish_band_width * 0.35
	var h := 2200.0
	_beacon.polygon = PackedVector2Array([Vector2(-w, -60), Vector2(w, -60), Vector2(w * 0.6, -h), Vector2(-w * 0.6, -h)])
	_beacon.vertex_colors = PackedColorArray([Color(1, 0.95, 0.4, 0.55), Color(1, 0.95, 0.4, 0.55), Color(1, 0.95, 0.4, 0.0), Color(1, 0.95, 0.4, 0.0)])
	_beacon.z_index = -59  # entre l'arrière et l'avant de l'arche
	add_child(_beacon)

	var label := Label.new()
	label.text = "ARRIVÉE"
	label.add_theme_font_size_override("font_size", 64)
	label.add_theme_color_override("font_color", Color(1, 0.95, 0.4))
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.15, 0.3))
	label.add_theme_constant_override("outline_size", 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(400, 90)
	label.position = Vector2(-200, -330)
	label.z_index = 30
	add_child(label)


func _process(delta: float) -> void:
	if _beacon:
		_time += delta
		_beacon.modulate.a = 0.65 + 0.35 * sin(_time * 4.0)  # pulsation douce


func _physics_process(_delta: float) -> void:
	# 2. Sécurité anti-traversée (le pingouin a "sauté" la bande entre 2 frames)
	if _finished:
		return
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var x: float = player.global_position.x
	var line_x: float = global_position.x + trigger_offset_x  # [ARRIVÉE 1.13] ligne éventuellement décalée
	var in_height: bool = player.global_position.y < global_position.y + finish_band_below \
		and player.global_position.y > global_position.y - finish_band_height
	if _player_prev_x != null and _player_prev_x < line_x and x >= line_x and in_height:
		_finish()
	_player_prev_x = x


func _on_Area2D_body_entered(body):
	# 3. Seul le pingouin compte
	if body.is_in_group("player"):
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("yay")
	RaceManager.finish_race()  # [FANTÔMES] arrête le chrono, sauve le record + le fantôme
	# [BONUS 1.20] figures bonus dans le half-pipe : pas de ralenti, on laisse
	# jouer ; on attend le score final, on le laisse lire, puis retour au menu.
	if RaceManager.bonus_active:
		await RaceManager.race_completed
		if NetSession.in_race:
			return
		await get_tree().create_timer(4.0, true, false, true).timeout
		if is_inside_tree():
			get_tree().change_scene_to_file(next_scene_path)
		return
	# 5. Petit ralenti de victoire (le timer ignore le ralenti : 4e argument)
	Engine.time_scale = 0.3
	# [FANTÔMES] un peu plus long pour lire le temps / le record
	await get_tree().create_timer(1.8, true, false, true).timeout
	Engine.time_scale = 1.0
	# [MULTI] en course réseau, on reste dans le niveau (on voit arriver les
	# autres, classement en haut à droite) : c'est l'hôte qui renverra tout le
	# monde au salon quand tous seront arrivés (cf. NetSession).
	if NetSession.in_race:
		return
	var error = get_tree().change_scene_to_file(next_scene_path)
	if error != 0:
		print("ERROR: ", error)
