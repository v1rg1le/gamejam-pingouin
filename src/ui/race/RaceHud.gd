extends CanvasLayer
# =============================================================================
#  RaceHud.gd — [FANTÔMES] chrono à l'écran + résultat à l'arrivée
# -----------------------------------------------------------------------------
#  Créé par RaceManager au début d'une course (niveaux avec arrivée seulement).
#  - En haut à gauche : temps en cours et record du niveau.
#  - À l'arrivée : grand bandeau "NOUVEAU RECORD !" ou "Temps : ... (record ...)".
#  Tout est dessiné en code (aucun nouvel asset).
#  [MULTI] (étape 6) en course réseau :
#   - grand compte à rebours "3, 2, 1, GO !" au centre (show_countdown) ;
#   - en haut à droite, le classement en direct (set_ranking) : les arrivés
#     avec leur temps, puis ceux encore en course.
#  [SCORE 1.5] :
#   - sous le chrono : total des points de figures de la course ;
#   - en bas au centre : la figure / le combo EN JEU pendant le saut, puis
#     "+300 COMBO ×2" (gagné, en jaune) ou "Raté !" (perdu, en rouge) ;
#   - à l'arrivée : temps, points de vitesse + points de figures = SCORE.
# =============================================================================

var _time_label: Label
var _best_label: Label
var _result_panel: PanelContainer
var _result_label: Label
var _countdown_label: Label     # [MULTI] 3-2-1-GO
var _ranking_label: Label       # [MULTI] classement en direct
var _go_timer: float = 0.0      # [MULTI] durée d'affichage du "GO !"
var _tricks_label: Label        # [SCORE 1.5] points de figures
var _pending_label: Label       # [SCORE 1.5] figures en jeu pendant le saut
var _popup_label: Label         # [SCORE 1.5] points gagnés / perdus
var _popup_timer: float = 0.0


func _ready() -> void:
	layer = 35  # au-dessus du jeu, sous le menu pause (60) et les boutons tactiles (50)
	var box := VBoxContainer.new()
	box.position = Vector2(18, 12)
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_time_label = _make_label(30, Color(1, 1, 1))
	_best_label = _make_label(17, Color(1, 0.94, 0.4))
	box.add_child(_time_label)
	box.add_child(_best_label)
	_tricks_label = _make_label(17, Color(0.75, 0.95, 1.0))   # [SCORE 1.5]
	_tricks_label.text = "Figures  0 pt"
	box.add_child(_tricks_label)

	# [SCORE 1.5] figures en jeu + points gagnés : en bas au centre (au-dessus
	# des boutons tactiles, sous le pingouin)
	_pending_label = _make_label(24, Color(1, 1, 1))
	_popup_label = _make_label(30, Color(1, 0.94, 0.4))
	for l in [_pending_label, _popup_label]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		l.offset_left = -300
		l.offset_right = 300
		add_child(l)
	_pending_label.offset_top = -205
	_pending_label.offset_bottom = -170
	_popup_label.offset_top = -170
	_popup_label.offset_bottom = -128

	_result_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.1, 0.22, 0.88)
	style.border_color = Color(1, 0.94, 0.4)
	style.set_border_width_all(4)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(22)
	_result_panel.add_theme_stylebox_override("panel", style)
	_result_panel.visible = false
	_result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_label = _make_label(36, Color(1, 1, 1))
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_panel.add_child(_result_label)
	add_child(_result_panel)
	_result_panel.resized.connect(_center_result)

	# [MULTI] compte à rebours : très gros chiffres au centre de l'écran
	_countdown_label = _make_label(120, Color(1, 0.94, 0.4))
	_countdown_label.add_theme_constant_override("outline_size", 18)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown_label.offset_bottom = -260   # dans le haut de l'écran, pas sur le pingouin
	_countdown_label.visible = false
	add_child(_countdown_label)
	# [MULTI] classement : en haut à droite, sous le bouton pause tactile
	_ranking_label = _make_label(17, Color(1, 1, 1))
	_ranking_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ranking_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_ranking_label.offset_left = -320
	_ranking_label.offset_right = -18
	_ranking_label.offset_top = 84
	_ranking_label.visible = false
	add_child(_ranking_label)
	# [FLÈCHES 1.14] flèches vers les autres joueurs hors écran (multi seulement)
	if NetSession.in_race:
		add_child(preload("res://src/ui/race/PlayerArrows.gd").new())
	# [RESPONSIVE 1.14] tout le HUD est agrandi sur les petits écrans
	# (téléphone) : voir UiScaler.gd. Les nœuds créés plus tard vont dans
	# _ui_root, et les positions se calculent sur _ui_root.size.
	_ui_root = UiScaler.apply(self)


func _make_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.14, 0.26))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(_delta: float) -> void:
	_time_label.text = RaceManager.format_time(RaceManager.race_time)
	_update_waiting(_delta)   # [ATTENTE 1.14]
	# [MULTI] le "GO !" reste affiché 0,8 s puis disparaît
	if _go_timer > 0.0:
		_go_timer -= _delta
		if _go_timer <= 0.0:
			_countdown_label.visible = false
	# [SCORE 1.5] le message de points s'efface au bout de 1,6 s
	if _popup_timer > 0.0:
		_popup_timer -= _delta
		_popup_label.modulate.a = clampf(_popup_timer / 0.4, 0.0, 1.0)


# --- [ATTENTE 1.14] Panneau « En attente des autres joueurs » -----------------
# Retour de test : avant le décompte, seule une petite ligne jaune sous le
# chrono disait qu'on attendait. On affiche maintenant un panneau au centre
# avec le nombre de joueurs prêts et le nom de ceux qu'on attend (liste mise
# à jour par l'hôte à chaque joueur prêt, cf. NetSession._rpc_loaded).
var _waiting_panel: PanelContainer = null
var _ui_root: Control = null   # [RESPONSIVE 1.14] racine agrandie du HUD (UiScaler)
var _waiting_label: Label = null
var _waiting_dots := 0.0

func show_waiting(on: bool) -> void:
	if on and _waiting_panel == null:
		_waiting_panel = PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.1, 0.2, 0.75)
		sb.set_corner_radius_all(16)
		sb.content_margin_left = 40; sb.content_margin_right = 40
		sb.content_margin_top = 22; sb.content_margin_bottom = 22
		_waiting_panel.add_theme_stylebox_override("panel", sb)
		_waiting_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_waiting_label = _make_label(34, Color(1, 0.94, 0.4))
		_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_waiting_panel.add_child(_waiting_label)
		_ui_root.add_child(_waiting_panel)   # [RESPONSIVE 1.14] dans la racine agrandie
		_update_waiting(0.0)
	elif not on and _waiting_panel != null:
		_waiting_panel.queue_free()
		_waiting_panel = null
		_waiting_label = null


func _update_waiting(delta: float) -> void:
	if _waiting_panel == null:
		return
	_waiting_dots = fmod(_waiting_dots + delta * 2.0, 4.0)
	var ready := 0
	var missing := PackedStringArray()
	for id in NetSession.players:
		if NetSession.players[id].loaded:
			ready += 1
		else:
			missing.append(NetSession.players[id].name)
	var text := "En attente des autres joueurs" + ".".repeat(int(_waiting_dots))
	text += "\n%d / %d prêts" % [ready, NetSession.players.size()]
	if missing.size() > 0 and missing.size() <= 3:
		text += "  —  on attend " + ", ".join(missing)
	_waiting_label.text = text
	# centré, un peu au-dessus du milieu (le pingouin est au centre)
	var view: Vector2 = _ui_root.size   # [RESPONSIVE 1.14] taille en unités du HUD
	_waiting_panel.reset_size()
	_waiting_panel.position = Vector2((view.x - _waiting_panel.size.x) * 0.5, view.y * 0.22)


# [MAÎTRE 1.19] clin d'œil du maître ninja (voir MasterWink.gd). Créé à la
# première figure réussie, puis réutilisé.
var _master: Control = null

func show_master_wink() -> void:
	if _master == null or not is_instance_valid(_master):
		_master = preload("res://src/ui/race/MasterWink.gd").new()
		(_ui_root if _ui_root != null else self).add_child(_master)
	_master.play()


func set_best(best: float) -> void:
	if best == -2.0:   # [MULTI] code spécial envoyé par RaceManager avant le départ
		_best_label.text = "En attente des autres joueurs…"
		return
	_best_label.text = ("Record  " + RaceManager.format_time(best)) if best >= 0.0 else "Pas encore de record"


## [MULTI] Affiche le compte à rebours (secondes restantes ; <= 0 -> "GO !").
func show_countdown(remaining: float) -> void:
	_countdown_label.visible = true
	if remaining > 0.0:
		_countdown_label.text = str(ceili(remaining))
		_best_label.text = "Prêt ?"
	elif _go_timer <= 0.0:
		_countdown_label.text = "GO !"
		_go_timer = 0.8
		set_best(RaceManager.get_best_time(RaceManager.level_path))


## [MULTI] Classement en direct : liste [[nom, temps, score], ...] (temps -1 = en course).
## [SCORE 1.5] classé au score ; le temps reste affiché.
func set_ranking(ranking: Array) -> void:
	var lines := PackedStringArray()
	var rank := 1
	for entry in ranking:
		if entry[1] >= 0.0:
			lines.append("%d. %s   %d pts  (%s)" % [rank, entry[0], entry[2], RaceManager.format_time(entry[1])])
			rank += 1
		else:
			lines.append("%s   …" % entry[0])
	_ranking_label.text = "\n".join(lines)
	_ranking_label.visible = ranking.size() > 0


func show_result(time: float, is_record: bool, previous_best: float, score := {}) -> void:
	if is_record:
		_result_label.text = "NOUVEAU RECORD !\n" + RaceManager.format_time(time)
		if previous_best >= 0.0:
			_result_label.text += "  (-%.2f s)" % (previous_best - time)
		set_best(time)
	else:
		_result_label.text = "Temps : " + RaceManager.format_time(time) + "\nRecord : " + RaceManager.format_time(previous_best)
	_result_label.text += _score_text(score)   # [SCORE 1.5]
	_result_panel.visible = true
	_result_panel.reset_size()
	_center_result()


## [SCORE 1.5] Détail du score sous le temps : vitesse + figures = SCORE.
func _score_text(score: Dictionary) -> String:
	if score.is_empty():
		return ""
	var t := "\n\nVitesse %d  +  Figures %d\nSCORE  %d" % [score.speed, score.tricks, score.score]
	# [SCORE 1.13] rappel du temps de référence (3000 points de vitesse à ce temps)
	if score.has("ref_time") and score.ref_time > 0.0:
		t += "\n(temps de référence %s)" % RaceManager.format_time(score.ref_time)
	if score.is_best_score and score.best_score >= 0:
		t += "\nMeilleur score !"   # (pas affiché la toute 1re fois)
	elif not score.is_best_score and score.best_score >= 0:
		t += "\n(meilleur : %d)" % score.best_score
	return t


## [SCORE 1.5] Total des points de figures (en haut à gauche).
func set_trick_points(total: int) -> void:
	_tricks_label.text = "Figures  %d pts" % total


## [SCORE 1.5] Figures en jeu pendant le saut ("" = rien en jeu).
func set_pending(text: String) -> void:
	_pending_label.text = text


## [SCORE 1.5] Message bref : points gagnés (jaune) ou perdus (rouge).
func show_trick_popup(text: String, color: Color) -> void:
	_popup_label.text = text
	_popup_label.add_theme_color_override("font_color", color)
	_popup_label.modulate.a = 1.0
	_popup_timer = 1.6


## [MULTI] Résultat d'une course en réseau : la place avant tout.
func show_multi_result(time: float, rank: int, total: int, score := {}) -> void:
	var place := "1re place !" if rank == 1 else "%de place" % rank
	_result_label.text = place + "\n" + RaceManager.format_time(time) + _score_text(score)
	# d'autres joueurs encore en course ? (le classement se complète en haut à droite)
	var finished := 0
	for entry in NetSession.ranking():
		if entry[1] >= 0.0:
			finished += 1
	if finished < total:
		_result_label.text += "\nEn attente des autres…"
	_result_panel.visible = true
	_result_panel.reset_size()
	_center_result()


func _center_result() -> void:
	var vs: Vector2 = _ui_root.size if _ui_root != null else _result_panel.get_viewport_rect().size   # [RESPONSIVE 1.14]
	_result_panel.position = (vs - _result_panel.size) * 0.5 - Vector2(0, 80)
