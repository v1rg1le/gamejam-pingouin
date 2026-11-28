extends Control
# =============================================================================
#  MultiplayerLobby.gd — [MULTI] salon multijoueur en réseau local (étape 6)
# -----------------------------------------------------------------------------
#  Deux colonnes, comme l'écran des niveaux :
#   - à gauche "CRÉER UNE PARTIE" : bouton pour devenir l'hôte. Une fois la
#     partie créée, ce panneau devient le SALON : adresse IP à donner aux
#     autres, liste des joueurs, choix de la course et bouton "Lancer"
#     (l'hôte seulement ; les invités voient "En attente de l'hôte…") ;
#   - à droite "REJOINDRE" : les parties trouvées automatiquement sur le Wi-Fi
#     (un bouton par partie) et un champ pour taper l'adresse IP à la main
#     (utile si le réseau bloque la diffusion, ex. Wi-Fi d'entreprise).
#  En bas : Retour (quitte la partie et revient au choix des niveaux),
#  "Quitter la partie" (reste dans le salon), numéro de version.
#  [INTERNET 1.6] Dans le salon, l'hôte peut cliquer "Ouvrir sur Internet" :
#  un CODE DE PARTIE de 8 signes s'affiche (bouton "Copier"), à envoyer aux
#  amis qui ne sont pas sur le même Wi-Fi. Ils le tapent dans le champ de
#  "Rejoindre" (qui accepte un code OU une adresse IP).
#  Après une course, on revient ici, toujours connectés, avec le classement
#  de la dernière course affiché dans le salon.
#  Toute la logique réseau est dans l'autoload NetSession.
# =============================================================================

# Courses proposées en multijoueur (les niveaux avec arrivée ; les niveaux
# Chill n'ont pas de fin, donc pas de classement).
const RACES = [
	["Tutoriel", "res://src/levels/LevelBateau.tscn"],   # [1.24] « Tuto : Bateau » -> « Tutoriel » (Léo)
	["Flat and fun", "res://src/levels/LevelRandomFlat.tscn"],
	["Corridor", "res://src/levels/LevelRandomCorridor.tscn"],
	["Nice Slope", "res://src/levels/LevelRandomNiceSlope.tscn"],
	["Hook, you fool !", "res://src/levels/LevelRandomGap.tscn"],
	["Spaghetti", "res://src/levels/LevelRandomSpaghetti.tscn"],
	["L'Œuf", "res://src/levels/LevelEgg.tscn"],   # [MENUS 1.61] nouveau niveau, ajouté ici aussi
	["Le Gruyère de glace", "res://src/levels/LevelGruyere.tscn"],   # [GRUYÈRE 1.62] maquette de la partie 1, à tester
]

@onready var name_edit: LineEdit = $Margin/VBox/NameRow/NameEdit
@onready var host_header: Label = $Margin/VBox/Columns/HostPanel/VBox/HostHeader
@onready var host_button: Button = $Margin/VBox/Columns/HostPanel/VBox/HostButton
@onready var ip_label: Label = $Margin/VBox/Columns/HostPanel/VBox/IpLabel
@onready var internet_button: Button = $Margin/VBox/Columns/HostPanel/VBox/InternetButton
@onready var copy_button: Button = $Margin/VBox/Columns/HostPanel/VBox/InternetRow/CopyButton
@onready var internet_label: Label = $Margin/VBox/Columns/HostPanel/VBox/InternetRow/InternetLabel
@onready var players_label: Label = $Margin/VBox/Columns/HostPanel/VBox/PlayersLabel
@onready var level_option: OptionButton = $Margin/VBox/Columns/HostPanel/VBox/LevelOption
@onready var start_button: Button = $Margin/VBox/Columns/HostPanel/VBox/StartButton
@onready var join_panel: PanelContainer = $Margin/VBox/Columns/JoinPanel
@onready var search_label: Label = $Margin/VBox/Columns/JoinPanel/VBox/SearchLabel
@onready var hosts_list: VBoxContainer = $Margin/VBox/Columns/JoinPanel/VBox/HostsList
@onready var ip_edit: LineEdit = $Margin/VBox/Columns/JoinPanel/VBox/IpRow/IpEdit
@onready var join_button: Button = $Margin/VBox/Columns/JoinPanel/VBox/IpRow/JoinButton
@onready var status_label: Label = $Margin/VBox/StatusLabel
@onready var back_button: Button = $Margin/VBox/Bottom/BackButton
@onready var leave_button: Button = $Margin/VBox/Bottom/LeaveButton
@onready var version_label: Label = $Margin/VBox/Bottom/VersionLabel

var _connecting: bool = false   # invité : connexion en cours (pas encore dans la liste)
var mode_option: OptionButton    # [MODES 1.25] choix Chill / Score (hôte)
var _choices: Array = []         # [MULTI CRÉATEUR 1.91] ce que lance chaque ligne de la liste


## [MULTI CRÉATEUR 1.91] « Lancer » : une course du jeu, ou un niveau du
## créateur envoyé à tous les joueurs
func _on_start_pressed() -> void:
	var c: Dictionary = _choices[level_option.selected] if level_option.selected >= 0 and level_option.selected < _choices.size() else {"kind": "sep"}
	match str(c.kind):
		"race":
			NetSession.start_race(c.ref, mode_option.selected)   # [MODES 1.25]
		"mine", "off":
			NetSession.start_drawn_race(c.kind, c.ref, mode_option.selected)
		_:
			status_label.text = "Choisis une course dans la liste."


func _ready() -> void:
	# [MENUS 1.61] largeur commune des menus (marge de 5 %) : les panneaux
	# « Créer » / « Rejoindre » (puis le SALON seul) prennent toute la largeur
	MenuLayout.fit($Margin)
	MenuLayout.widen_panels($Margin/VBox/Columns)
	# le panneau prend la hauteur de son contenu (plus de grand vide en bas)
	for panel in [$Margin/VBox/Columns/HostPanel, join_panel]:
		panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_build_results_table()
	version_label.text = "v" + str(ProjectSettings.get_setting("application/config/version", "?"))
	name_edit.text = NetSession.player_name
	name_edit.text_changed.connect(NetSession.set_player_name)
	# [MULTI CRÉATEUR 1.91] après les courses du jeu : mes niveaux (validés ou
	# en glisse libre) et ceux de la Communauté (choix de l'équipe). Chaque
	# ligne garde ce qu'il faut lancer dans _choices (même ordre que la liste).
	DrawnLevel.end_net_level()   # (sécurité : on revient toujours ici avec son propre niveau)
	_choices.clear()
	for race in RACES:
		level_option.add_item(race[0])
		_choices.append({"kind": "race", "ref": race[1]})
	var mine: Array = []
	var off: Array = []
	for e in DrawnLevel.multi_levels():
		(mine if e.kind == "mine" else off).append(e)
	for group in [["Mes niveaux", mine], ["Communauté", off]]:
		if (group[1] as Array).is_empty():
			continue
		level_option.add_separator("— %s —" % group[0])
		_choices.append({"kind": "sep"})
		for e in group[1]:
			var label: String = str(e.name)
			if e.type == "free":
				label += "  (glisse libre : 3 min de figures)"
			elif e.type == "tricks":
				label += "  (défi figures)"
			level_option.add_item(label)
			_choices.append(e)
	var start_i := clampi(NetSession.last_level_index, 0, _choices.size() - 1)
	if _choices[start_i].kind == "sep":
		start_i = 0
	level_option.selected = start_i
	level_option.item_selected.connect(func(i): NetSession.last_level_index = i)
	# [MODES 1.25] l'hôte choisit le mode de jeu pour tout le monde : copie
	# du menu des niveaux (même style), juste en dessous
	mode_option = level_option.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
	mode_option.name = "ModeOption"
	mode_option.clear()
	mode_option.add_item("Mode Chill (tranquille, sans chrono)")
	mode_option.add_item("Mode Score (chrono, médailles, classement)")
	level_option.get_parent().add_child(mode_option)
	level_option.get_parent().move_child(mode_option, level_option.get_index() + 1)
	if NetSession.last_mode < 0:
		NetSession.last_mode = Settings.game_mode
	mode_option.selected = NetSession.last_mode
	mode_option.item_selected.connect(func(i): NetSession.last_mode = i)

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(func(): _join(ip_edit.text))
	ip_edit.text_submitted.connect(_join)
	start_button.pressed.connect(_on_start_pressed)
	leave_button.pressed.connect(func():
		NetSession.leave()
		status_label.text = "Tu as quitté la partie.")
	back_button.pressed.connect(_go_back)
	# [INTERNET 1.6]
	internet_button.pressed.connect(func():
		internet_label.text = "Ouverture du port de ta box…"
		NetSession.open_internet()
		_refresh())
	copy_button.pressed.connect(func():
		DisplayServer.clipboard_set(NetSession.internet_code)
		status_label.text = "Code copié : envoie-le à tes amis !")
	NetSession.internet_opened.connect(func(_code): _refresh())
	NetSession.internet_failed.connect(func(reason):
		internet_label.text = ""
		status_label.text = reason + "\nSolutions : active l'UPnP dans les réglages de ta box, ou demande à un ami de créer la partie."
		_refresh())

	NetSession.players_changed.connect(_refresh)
	NetSession.hosts_changed.connect(_refresh_hosts)
	NetSession.session_ended.connect(func(reason):
		_connecting = false
		status_label.text = reason
		NetSession.pending_message = ""   # déjà affiché ici
		_refresh())
	NetSession.start_discovery()
	# message laissé par NetSession avant le changement de scène (ex. l'hôte
	# a quitté pendant la course) : on l'affiche une fois
	status_label.text = NetSession.pending_message
	NetSession.pending_message = ""
	_refresh()
	_refresh_hosts()
	if Settings.controls != Settings.TOUCH:
		(start_button if NetSession.is_host() else host_button).grab_focus()


func _exit_tree() -> void:
	NetSession.stop_discovery()


func _unhandled_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		_go_back()


func _go_back() -> void:
	NetSession.leave()
	get_tree().change_scene_to_file("res://src/screens/LevelSelectionScreen.tscn")


func _on_host_pressed() -> void:
	var err := NetSession.host()
	if err != OK:
		status_label.text = "Impossible de créer la partie (erreur %d). Le port %d est peut-être déjà utilisé." % [err, NetSession.GAME_PORT]
	else:
		status_label.text = ""
	_refresh()


func _join(ip: String) -> void:
	ip = ip.strip_edges()
	if not ip.is_valid_ip_address():
		# [INTERNET 1.6] pas une adresse IP : c'est peut-être un code de partie
		var from_code := NetSession.code_to_ip(ip)
		if from_code == "":
			status_label.text = "Code invalide : vérifie les 8 signes (ex. K7QM-2XPA), ou tape une adresse comme 192.168.1.12"
			return
		ip = from_code
	if NetSession.join(ip) != OK:
		status_label.text = "Connexion impossible."
		return
	_connecting = true
	status_label.text = "Connexion à %s…" % ip
	_refresh()


# --- Mise à jour de l'affichage ---------------------------------------------------
func _refresh() -> void:
	var in_session := NetSession.is_active()
	# hors partie, on écoute les annonces (l'hôte arrête d'écouter en créant)
	if not in_session and not NetSession.is_discovering():
		NetSession.start_discovery()
	var joined := in_session and NetSession.players.has(NetSession.my_id())
	if joined:
		_connecting = false
		if status_label.text.begins_with("Connexion"):
			status_label.text = ""
	join_panel.visible = not in_session
	leave_button.visible = in_session
	host_button.visible = not in_session
	host_header.text = "SALON" if in_session else "CRÉER UNE PARTIE"
	name_edit.editable = not in_session   # le nom est envoyé à la connexion

	if NetSession.is_host():
		var ips: Array = NetSession.local_ips()
		ip_label.text = "Partie ouverte ! Sur le même Wi-Fi, les autres la verront dans « Rejoindre ».\nAdresse : " + (", ".join(ips) if not ips.is_empty() else "inconnue")
		if NetSession.internet_code != "":   # [INTERNET 1.6]
			ip_label.text += "\nAmis ailleurs : envoie-leur ce code."
	elif joined:
		ip_label.text = "Connecté ! L'hôte choisit la course et la lance."
	elif _connecting:
		ip_label.text = "Connexion…"
	else:
		ip_label.text = "Les autres joueurs te trouveront automatiquement s'ils sont sur le même Wi-Fi."

	# Joueurs + classement de la dernière course
	var lines := PackedStringArray()
	if joined:
		lines.append("Joueurs (%d) :" % NetSession.players.size())
		for id in NetSession.players:
			var mark := "  ★ " if id == 1 else "  • "   # ★ = l'hôte
			lines.append(mark + str(NetSession.players[id].name) + ("  (toi)" if id == NetSession.my_id() else ""))
	# [MENUS 1.61] « Dernière course » : vrai tableau à colonnes (voir
	# _fill_results), plus dans ce texte
	players_label.text = "\n".join(lines)
	players_label.visible = not lines.is_empty()
	_fill_results(joined)

	# [INTERNET 1.6] ouverture sur Internet (hôte seulement)
	internet_button.visible = NetSession.is_host() and NetSession.internet_code == ""
	internet_button.disabled = NetSession.internet_busy
	copy_button.visible = NetSession.is_host() and NetSession.internet_code != ""
	if NetSession.is_host() and NetSession.internet_code != "":
		internet_label.text = "Code :  " + NetSession.internet_code
	elif not NetSession.internet_busy:
		internet_label.text = ""
	internet_label.get_parent().visible = internet_label.text != ""

	level_option.visible = NetSession.is_host()
	if mode_option != null:
		mode_option.visible = NetSession.is_host()   # [MODES 1.25]
	start_button.visible = NetSession.is_host()
	start_button.disabled = NetSession.players.size() < 1


func _refresh_hosts() -> void:
	for c in hosts_list.get_children():
		c.queue_free()
	var n := 0
	for ip in NetSession.found_hosts:
		var h: Dictionary = NetSession.found_hosts[ip]
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 46)
		b.text = "%s   (%d joueur%s)" % [h.name, h.players, "s" if h.players > 1 else ""]
		b.pressed.connect(_join.bind(ip))
		hosts_list.add_child(b)
		n += 1
	search_label.text = "Recherche des parties sur le Wi-Fi…" if n == 0 else "Parties trouvées :"


# --- [MENUS 1.61] Tableau « Dernière course » -----------------------------------
# Demande de l'équipe (capture du salon) : points et temps alignés à droite.
# Avant, chaque ligne était un texte « 1. Nom   9990 pts  (1:16.07) » : les
# chiffres suivaient la longueur des noms et ne tombaient jamais les uns sous
# les autres. Maintenant : rang | nom | points | temps, en colonnes.
#  - points et temps alignés à droite, chiffres à largeur fixe (ils tombent
#    pile les uns sous les autres) ; points en gras (ils font le classement en
#    Score), temps en plus clair ;
#  - nom coupé avec « … » s'il est trop long (il ne pousse plus les colonnes) ;
#  - ta ligne en jaune, comme le « (toi) » de la liste des joueurs ;
#  - le tableau (décalé de 20 px, comme la liste des joueurs) ne s'étire pas au-delà de RESULTS_MAX_WIDTH : sur un écran
#    large, le nom et son score resteraient sinon trop loin l'un de l'autre.
const RESULTS_MAX_WIDTH := 760.0
var _results_box: VBoxContainer     # titre + tableau (masqué sans résultats)
var _results_grid: GridContainer


func _build_results_table() -> void:
	_results_box = VBoxContainer.new()
	_results_box.name = "ResultsBox"
	_results_box.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = "Dernière course :"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color.WHITE)
	_results_box.add_child(title)
	# le tableau, aligné à gauche (comme la liste des joueurs au-dessus) et
	# plafonné en largeur
	var center := HBoxContainer.new()
	_results_box.add_child(center)
	_results_grid = GridContainer.new()
	_results_grid.columns = 4
	_results_grid.add_theme_constant_override("h_separation", 26)
	_results_grid.add_theme_constant_override("v_separation", 6)
	center.add_child(_results_grid)
	_results_grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	center.add_theme_constant_override("separation", 0)
	var indent := Control.new()
	indent.custom_minimum_size.x = 12
	center.add_child(indent)
	center.move_child(indent, 0)
	center.resized.connect(func():
		_results_grid.custom_minimum_size.x = minf(center.size.x - 12.0, RESULTS_MAX_WIDTH))
	var parent := players_label.get_parent()
	parent.add_child(_results_box)
	parent.move_child(_results_box, players_label.get_index() + 1)


func _fill_results(joined: bool) -> void:
	for c in _results_grid.get_children():
		c.queue_free()
	_results_box.visible = joined and not NetSession.last_results.is_empty()
	if not _results_box.visible:
		return
	var me: String = ""
	if NetSession.players.has(NetSession.my_id()):
		me = str(NetSession.players[NetSession.my_id()].name)
	var rank := 1
	for entry in NetSession.last_results:
		var mine: bool = str(entry[0]) == me
		var color := Color(1, 0.94, 0.4) if mine else Color.WHITE
		var arrived: bool = entry[1] >= 0.0
		# rang
		_cell("%d." % rank if arrived else "–", color, HORIZONTAL_ALIGNMENT_RIGHT, false)
		# nom : prend toute la place qui reste, coupé avec « … » si trop long
		var name_cell := _cell(str(entry[0]) + ("  (toi)" if mine else ""), color, HORIZONTAL_ALIGNMENT_LEFT, false)
		name_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_cell.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_cell.clip_text = true
		name_cell.custom_minimum_size.x = 120
		if arrived:
			# [SCORE 1.5] classement au score ; le temps ensuite, plus clair
			_cell("%d pts" % entry[2], color, HORIZONTAL_ALIGNMENT_RIGHT, true)
			_cell(RaceManager.format_time(entry[1]), Color(color, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, false)
			rank += 1
		else:
			_cell("", color, HORIZONTAL_ALIGNMENT_RIGHT, false)
			_cell("pas arrivé", Color(color, 0.7), HORIZONTAL_ALIGNMENT_RIGHT, false)


## Une case du tableau des résultats (chiffres à largeur fixe : ils s'alignent).
func _cell(text: String, color: Color, align: HorizontalAlignment, bold: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", color)
	# chiffres de même largeur (tnum) : 9990 et 7620 tombent pile l'un sous l'autre
	var f := FontVariation.new()
	f.base_font = l.get_theme_font("font")
	f.opentype_features = {"tnum": 1}
	if bold:
		f.variation_embolden = 0.6
	l.add_theme_font_override("font", f)
	_results_grid.add_child(l)
	return l
