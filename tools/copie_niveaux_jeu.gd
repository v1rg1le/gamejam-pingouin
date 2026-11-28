extends SceneTree
# =============================================================================
#  tools/copie_niveaux_jeu.gd — [COPIES DU JEU 1.92] prépare les copies des
#  niveaux du jeu pour le créateur (« Copier pour modifier »).
# -----------------------------------------------------------------------------
#  Charge chaque niveau du jeu, attend que ses générateurs aient tout
#  construit, puis LevelCopier.capture() en fait un niveau du créateur, écrit
#  dans res://src/levels/drawn/jeu/<slug>.json (DrawnLevel.GAME_COPY_DIR).
#  À relancer quand un niveau du jeu change. Depuis le dossier du projet :
#    XDG_DATA_HOME=$(mktemp -d) godot --headless --path . -s tools/copie_niveaux_jeu.gd
#  (dossier de données neuf : pas de fantôme du joueur, donc la même graine
#  de terrain à chaque fois pour les niveaux au terrain tiré au hasard)
# =============================================================================

## [scène, slug, nom affiché, ordre, règles, ambiance]
const LEVELS := [
	["LevelRandomFlat", "flat-and-fun", "Flat and fun", 1, {}, {}],
	["LevelRandomCorridor", "corridor", "Corridor", 2, {}, {}],
	["LevelRandomNiceSlope", "nice-slope", "Nice Slope", 3, {}, {}],
	["LevelRandomGap", "hook-you-fool", "Hook, you fool !", 4, {}, {}],
	["LevelRandomSpaghetti", "spaghetti", "Spaghetti", 5, {}, {}],
	["LevelEgg", "l-oeuf", "L'Œuf", 6, {}, {}],
	["LevelGruyere", "gruyere", "Le Gruyère de glace", 7, {}, {}],
	["LevelChill704", "704", "704", 8, {"type": "tricks", "time": 240.0}, {"sky": "cycle"}],
	["LevelChill917", "917", "917", 9, {"type": "tricks", "time": 240.0}, {"sky": "cycle"}],
	["LevelHalfPipe", "half-pipe", "Half-pipe", 10, {"type": "tricks", "time": 180.0}, {"sky": "cycle"}],
	["LevelBateau", "tutoriel", "Tutoriel", 11, {}, {}],
]
const OUT_DIR := "res://src/levels/drawn/jeu"
## Temps laissé aux générateurs (s) ; le pingouin est figé dès la 2e image
const WAIT := 1.5

var i := -1
var t := 0.0
var frames := 0
var only := ""


func _process(d: float) -> bool:
	if i == -1:
		only = OS.get_environment("ONLY")   # (facultatif) un seul niveau
		root.get_node("Settings").game_mode = 1   # mode Score : la ligne d'arrivée est posée
		_next()
		return false
	frames += 1
	t += d
	if frames == 2:
		# on fige le pingouin à sa place de départ (sinon il glisse pendant l'attente)
		var p := current_scene.get_tree().get_first_node_in_group("player")
		if p != null:
			p.process_mode = Node.PROCESS_MODE_DISABLED
	if t < WAIT:
		return false
	var L: Array = LEVELS[i]
	var rules: Dictionary = (L[4] as Dictionary).duplicate()
	rules["runout"] = false   # le niveau a ses propres bouts (voir DrawnLevel.clean_rules)
	# (chargé à l'exécution : un script lancé avec -s ne connaît pas encore
	# les autoloads quand il est compilé)
	var data: Dictionary = load("res://src/levels/drawn/LevelCopier.gd").capture(current_scene, {"name": L[2], "order": L[3],
		"scene": "res://src/levels/%s.tscn" % L[0], "rules": rules, "ambiance": L[5]})
	var rep: Dictionary = data.report
	data.erase("report")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f := FileAccess.open(OUT_DIR.path_join(L[1] + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	print("COPIE %s : %d traits, %d morceaux, %d prises, %d cavernes, %d œufs, %d boosts, %d décors ; laissés : %s" % [
		L[1], rep.strokes, rep.pieces, rep.hooks, rep.caves, rep.eggs, rep.boosts, rep.decor, str(rep.skipped)])
	_next()
	return false


func _next() -> void:
	i += 1
	while i < LEVELS.size() and only != "" and LEVELS[i][1] != only:
		i += 1
	if i >= LEVELS.size():
		print("COPIES FAITES")
		quit()
		return
	t = 0.0
	frames = 0
	seed(1920 + i)   # graine fixe : même terrain à chaque passage de l'outil
	change_scene_to_file("res://src/levels/%s.tscn" % LEVELS[i][0])
