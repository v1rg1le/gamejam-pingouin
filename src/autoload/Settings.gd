extends Node
# =============================================================================
#  Settings.gd — autoload : schéma de contrôle actif
# -----------------------------------------------------------------------------
#  [MIGRATION GODOT 4.7] setget -> `: set = set_controls`
#
#  [MOBILE] (nouveau)
#   - Nouveau schéma TOUCH (écran tactile), ajouté EN FIN d'enum pour que
#     KBD_MOUSE (0) et GAMEPAD (1) gardent leurs valeurs.
#   - Détection de la plateforme au démarrage : `is_mobile_device` est vrai
#     sur Android / iOS (ou navigateur mobile si un jour export Web). On
#     démarre alors directement en TOUCH.
#   - Détection en cours de jeu (utile pour les PC/tablettes tactiles) :
#       * toucher l'écran           -> TOUCH
#       * manette                   -> GAMEPAD
#       * clavier / vraie souris    -> KBD_MOUSE
#     Les clics souris "émulés" par Godot à partir d'un toucher sont ignorés
#     (device == DEVICE_ID_EMULATION), sinon chaque toucher repasserait en
#     KBD_MOUSE.
#   - En mode TOUCH, les clics souris sont retirés des actions "hook" et
#     "pull" : sinon chaque toucher (même sur le bouton SAUT) lancerait le
#     grappin via le clic émulé. Ils sont remis dès qu'on revient au PC.
#   - `touch_aim` : direction de visée du grappin fournie par les contrôles
#     tactiles (Vector2.ZERO = visée par défaut, vers l'avant et le haut).
# =============================================================================

signal controls_changed(new_scheme)

enum {KBD_MOUSE, GAMEPAD, TOUCH}
var controls: = KBD_MOUSE: set = set_controls

## [MOBILE] true si le jeu tourne sur un appareil mobile (Android / iOS).
var is_mobile_device: bool = false
## [MOBILE] visée du grappin en mode tactile (mise à jour par TouchControls).
var touch_aim: Vector2 = Vector2.ZERO

# [MOBILE] actions dont on retire les clics souris en mode tactile
const MOUSE_ACTIONS_DISABLED_IN_TOUCH = ["hook", "pull"]
var _removed_mouse_events := {}   # action -> Array[InputEvent] retirés


func _ready() -> void:
	# [MOBILE] détection de la plateforme au lancement
	is_mobile_device = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	print("[MOBILE] appareil mobile : ", is_mobile_device, " | écran tactile dispo : ", DisplayServer.is_touchscreen_available())
	if is_mobile_device:
		self.controls = TOUCH
		# [MOBILE] les téléphones en paysage sont plus larges que 1024x720 :
		# en mode "expand" l'image remplit tout l'écran (pas de bandes noires
		# sur les côtés) ; on voit simplement un peu plus de niveau en largeur.
		# Sur PC on garde le réglage du projet (keep_width).
		get_tree().root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		self.controls = TOUCH
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		# petite zone morte : un stick qui "dérive" ne doit pas voler le contrôle
		if event is InputEventJoypadMotion and abs(event.axis_value) < 0.3:
			return
		self.controls = GAMEPAD
	elif event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return  # [MOBILE] clic/mouvement souris généré par un toucher : on ignore
	elif event is InputEventKey or event is InputEventMouseButton:
		self.controls = KBD_MOUSE
	elif event is InputEventMouseMotion and not is_mobile_device and event.relative.length() > 4.0:
		# vraie souris qui bouge franchement (pas un simple tremblement)
		self.controls = KBD_MOUSE


func set_controls(value:int) -> void:
	if value == controls:
		return  # [MOBILE] pas de signal inutile à chaque événement
	controls = value
	_update_mouse_bindings()
	emit_signal("controls_changed", controls)


# [MOBILE] retire / remet les clics souris des actions du grappin
func _update_mouse_bindings() -> void:
	if controls == TOUCH:
		for action in MOUSE_ACTIONS_DISABLED_IN_TOUCH:
			if _removed_mouse_events.has(action) or not InputMap.has_action(action):
				continue
			var removed := []
			for ev in InputMap.action_get_events(action):
				if ev is InputEventMouseButton:
					removed.append(ev)
					InputMap.action_erase_event(action, ev)
			_removed_mouse_events[action] = removed
	else:
		for action in _removed_mouse_events:
			for ev in _removed_mouse_events[action]:
				InputMap.action_add_event(action, ev)
		_removed_mouse_events.clear()
		touch_aim = Vector2.ZERO
