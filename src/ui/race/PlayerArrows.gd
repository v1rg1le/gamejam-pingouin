extends Control
# =============================================================================
#  PlayerArrows.gd — [FLÈCHES 1.14] où sont les autres joueurs ?
# -----------------------------------------------------------------------------
#  Demande de l'équipe : en multijoueur, indiquer la position des autres
#  joueurs par des flèches (« soit tous, soit celui d'avant et d'après »).
#  Choix retenu : les deux à la fois.
#   - Chaque joueur HORS de l'écran a une flèche à sa couleur, collée au bord
#     de l'écran dans sa direction, avec son nom et son écart en mètres
#     (+ = devant toi, − = derrière toi).
#   - Le joueur JUSTE DEVANT toi et celui JUSTE DERRIÈRE ont une flèche plus
#     grosse et bien opaque ; les autres sont plus petites et transparentes.
#     Avec 2 ou 3 joueurs, toutes les flèches sont donc « grosses ».
#   - Un joueur visible à l'écran n'a pas de flèche (son nom flotte déjà
#     au-dessus de lui, cf. RemotePenguin.gd).
#  Réglage : `only_neighbours = true` n'affiche QUE les voisins (devant /
#  derrière), si l'équipe préfère moins d'informations à l'écran.
#  Créé par RaceHud en course multijoueur ; tout est dessiné en code (aucun
#  nouvel asset). Les positions viennent de RaceManager._remotes.
# =============================================================================

## N'afficher que le joueur juste devant et celui juste derrière.
## [FLÈCHES 1.16] forcé par le réglage « Flèches des joueurs » des Options
## (Settings.player_arrows) : Toutes / Devant et derrière / Aucune.
@export var only_neighbours: bool = false
## Distance (px) entre la flèche et le bord de l'écran.
@export var edge_margin: float = 34.0
## Marge du haut, pour ne pas passer sur le chrono et le classement.
@export var top_margin: float = 140.0
## Pixels du monde par « mètre » affiché (le pingouin fait ~64 px).
@export var px_per_meter: float = 64.0

var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()


func _process(_delta: float) -> void:
	# [RESPONSIVE 1.14] toujours la taille du HUD (racine agrandie ou écran)
	var parent_size: Vector2 = get_parent().size if get_parent() is Control else get_viewport_rect().size
	position = Vector2.ZERO
	size = parent_size
	queue_redraw()   # on redessine à chaque image (les joueurs bougent)


func _draw() -> void:
	# [FLÈCHES 1.16] réglage des Options. En mode « devant et derrière », le
	# 1er de la course n'a personne devant : il ne voit QUE la flèche de celui
	# qui le suit ; le dernier ne voit que celle de celui qui le précède (géré
	# par ahead_id / behind_id = -1 ci-dessous).
	if Settings.player_arrows == Settings.ARROWS_NONE:
		return
	var neighbours_only: bool = only_neighbours or Settings.player_arrows == Settings.ARROWS_NEIGHBOURS
	var me = RaceManager._player
	if me == null or not is_instance_valid(me):
		return
	var remotes: Dictionary = RaceManager._remotes
	if remotes.is_empty():
		return
	var my_x: float = me.global_position.x
	# 1. qui est juste devant / juste derrière moi (en x, le sens de la course)
	var ahead_id := -1
	var behind_id := -1
	var ahead_dx := INF
	var behind_dx := -INF
	for id in remotes:
		var node = remotes[id]
		if not is_instance_valid(node) or not node.visible:
			continue
		var dx: float = node.global_position.x - my_x
		if dx >= 0.0 and dx < ahead_dx:
			ahead_dx = dx; ahead_id = id
		elif dx < 0.0 and dx > behind_dx:
			behind_dx = dx; behind_id = id
	# 2. une flèche par joueur hors écran
	# [RESPONSIVE 1.14] le HUD peut être agrandi (UiScaler) : on travaille
	# dans les unités de CE nœud (taille = size), et on convertit le monde
	# -> écran -> unités du nœud.
	var view := size
	var to_local: Transform2D = get_global_transform_with_canvas().affine_inverse()
	# en tactile, les boutons occupent le bas de l'écran : les flèches restent
	# dans la moitié haute (au-dessus de SAUT et des rotations)
	var bottom: float = view.y * 0.5 if Settings.controls == Settings.TOUCH else view.y - edge_margin - 40.0
	var inner := Rect2(Vector2(edge_margin, top_margin), Vector2(view.x - edge_margin * 2.0, maxf(bottom - top_margin, 40.0)))
	var center := inner.get_center()   # les flèches partent du centre de leur zone
	var used: Array = []   # positions déjà prises (pour décaler les flèches qui se chevauchent)
	for id in remotes:
		var node = remotes[id]
		if not is_instance_valid(node) or not node.visible:
			continue
		var neighbour: bool = id == ahead_id or id == behind_id
		if neighbours_only and not neighbour:
			continue
		# position du pingouin à l'écran (coordonnées de la fenêtre), puis dans
		# les unités de ce nœud
		var screen_pos: Vector2 = to_local * node.get_global_transform_with_canvas().origin
		if Rect2(Vector2.ZERO, view).grow(-8.0).has_point(screen_pos):
			continue   # visible à l'écran : pas besoin de flèche
		# point du bord de `inner` dans la direction du joueur (depuis le centre)
		var dir: Vector2 = (screen_pos - center).normalized()
		# La course va de gauche à droite : un joueur hors champ à gauche ou à
		# droite a sa flèche sur le bord gauche / droit, à SA hauteur (bornée à
		# la zone) ; un joueur juste au-dessus / en dessous de l'écran l'a sur
		# le bord haut / bas de la zone.
		var pos: Vector2
		if screen_pos.x < 0.0 or screen_pos.x > view.x:
			pos = Vector2(inner.end.x if screen_pos.x > view.x else inner.position.x,
				clampf(screen_pos.y, inner.position.y, inner.end.y))
		else:
			pos = _edge_point(center, dir, inner)
		dir = (screen_pos - pos).normalized()   # la flèche vise le joueur
		for p in used:   # deux flèches au même endroit : on décale vers le bas
			if absf(pos.x - p.x) < 140.0 and absf(pos.y - p.y) < 56.0:
				# en dessous s'il reste de la place, sinon au-dessus
				pos.y = p.y + 56.0 if p.y + 56.0 <= inner.end.y else p.y - 56.0
		used.append(pos)
		var color: Color = node.COLORS[node.peer_id % node.COLORS.size()]
		var big: bool = neighbour
		_draw_arrow(pos, dir, color, 1.0 if big else 0.7, 1.0 if big else 0.55)
		# nom + écart en mètres, juste sous la flèche (dans l'écran)
		var meters := int(round((node.global_position.x - my_x) / px_per_meter))
		var txt := "%s  %s%d m" % [node._label.text, "+" if meters >= 0 else "−", absi(meters)]
		var fs := 18 if big else 14
		var tw: float = _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tpos := pos + Vector2(-tw * 0.5, 22.0 + fs)
		tpos.x = clampf(tpos.x, 6.0, view.x - tw - 6.0)
		var a := 1.0 if big else 0.6
		draw_string_outline(_font, tpos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.08, 0.12, 0.24, 0.9 * a))
		draw_string(_font, tpos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(color, a))


## Point où la demi-droite (center, dir) sort du rectangle `r`.
func _edge_point(center: Vector2, dir: Vector2, r: Rect2) -> Vector2:
	var t := INF
	if dir.x > 0.001: t = minf(t, (r.end.x - center.x) / dir.x)
	if dir.x < -0.001: t = minf(t, (r.position.x - center.x) / dir.x)
	if dir.y > 0.001: t = minf(t, (r.end.y - center.y) / dir.y)
	if dir.y < -0.001: t = minf(t, (r.position.y - center.y) / dir.y)
	if t == INF:
		return center
	return center + dir * t


## Triangle pointant vers `dir`, contour sombre pour rester lisible sur la neige.
func _draw_arrow(pos: Vector2, dir: Vector2, color: Color, scale_f: float, alpha: float) -> void:
	var side := Vector2(-dir.y, dir.x)
	var tip := pos + dir * 18.0 * scale_f
	var base := pos - dir * 12.0 * scale_f
	var pts := PackedVector2Array([tip, base + side * 15.0 * scale_f, base - side * 15.0 * scale_f])
	draw_colored_polygon(pts, Color(color, alpha))
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(0.08, 0.12, 0.24, alpha), 3.0, true)
