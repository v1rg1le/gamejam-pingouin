class_name MenuLayout
extends RefCounted
# =============================================================================
#  MenuLayout.gd — [MENUS 1.61] une seule règle de largeur pour les menus
# -----------------------------------------------------------------------------
#  Demande de l'équipe (capture du salon multijoueur) : les fenêtres des menus
#  étaient trop étroites (panneaux de 430-440 px au milieu d'un écran large),
#  il faut qu'elles prennent plus de place en largeur « en gardant une marge ».
#
#  Règle commune (choix validé avec l'équipe) :
#   - marge de chaque côté = 5 % de la largeur de l'écran, jamais moins de
#     MIN_MARGIN (40 unités) ;
#   - largeur utile plafonnée à MAX_CONTENT_WIDTH : sur un écran très large
#     (21:9), les lignes deviendraient trop longues à lire, la marge grandit
#     alors au lieu du contenu ;
#   - les panneaux (PanelContainer) d'une rangée se partagent toute la largeur
#     restante (size_flags EXPAND_FILL) au lieu de garder leur largeur fixe.
#
#  Utilisation, dans le _ready() d'un écran de menu :
#      MenuLayout.fit($Margin)                 # marges gauche / droite
#      MenuLayout.widen_panels($Margin/VBox/Columns)
#  La marge est recalculée quand l'écran change de taille (rotation, fenêtre
#  PC redimensionnée, agrandissement des menus par Settings.menu_scale).
# =============================================================================

const MARGIN_RATIO := 0.05        # 5 % de la largeur de chaque côté
const MIN_MARGIN := 40.0          # unités : jamais collé au bord
const MAX_CONTENT_WIDTH := 1400.0 # unités : au-delà, la marge grandit


## Marge gauche / droite pour un écran de `width` unités de large.
static func side_margin(width: float) -> float:
	return maxf(maxf(MIN_MARGIN, width * MARGIN_RATIO), (width - MAX_CONTENT_WIDTH) * 0.5)


## Applique la marge à un MarginContainer plein écran, maintenant et à chaque
## changement de taille de l'écran. La connexion est retirée quand le
## conteneur quitte l'arbre (même précaution que UiScaler, voir 1.46).
static func fit(margin: MarginContainer) -> void:
	if margin == null or not margin.is_inside_tree():
		return
	var vp := margin.get_viewport()
	var update := func():
		if is_instance_valid(margin) and margin.is_inside_tree():
			var w: float = margin.get_viewport().get_visible_rect().size.x
			var m := int(round(side_margin(w)))
			margin.add_theme_constant_override("margin_left", m)
			margin.add_theme_constant_override("margin_right", m)
	update.call()
	vp.size_changed.connect(update)
	margin.tree_exiting.connect(func():
		if is_instance_valid(vp) and vp.size_changed.is_connected(update):
			vp.size_changed.disconnect(update), CONNECT_ONE_SHOT)


## Les panneaux d'une rangée (HBoxContainer « Columns ») prennent toute la
## largeur disponible, à parts égales. Leur largeur minimale de la scène
## reste un minimum (le texte ne s'écrase jamais).
static func widen_panels(row: Container) -> void:
	if row == null:
		return
	for c in row.get_children():
		if c is PanelContainer:
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.size_flags_stretch_ratio = 1.0
