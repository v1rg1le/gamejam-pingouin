extends Button

@onready var menu_pause = get_parent().get_parent().get_parent()

func _on_ResumeButton_button_up():
#	get_tree().paused = false
	menu_pause.set_paused(false)

