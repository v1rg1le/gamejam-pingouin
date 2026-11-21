extends Node2D
class_name StateMachine

@onready var in_air: InAirState = $"InAirState"
@onready var on_ground: OnGroundState = $"OnGroundState"

@onready var idling: IdleState = $"IdleState"
@onready var sliding: SlidingState = $"SlidingState"
@onready var jumping: JumpingState = $"JumpingState"
@onready var running: RunningState = $"RunningState"
@onready var staggered: StaggeredState = $"StaggeredState"
@onready var trixing: TrixState = $"TrixState"
@onready var pumping: PumpState = $"PumpState"
@onready var crashing = $"CrashState"   # [ATTERRISSAGES 1.40] chute sur le dos : roulade dans la neige

@onready var hooking_in_air: HookingInAirState = $"HookingInAirState"
@onready var hooking_on_ground: HookingOnGroundState = $"HookingOnGroundState"

@onready var super_state_label: Label = $"SuperState"
@onready var sub_state_label: Label = $"SubState"
@onready var label3: Label = $"Label3"

@onready var current: PlayerState = idling

@onready var player = get_parent()

func _ready():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func go_to_state(_player: CharacterBody2D, state_name: String) -> void:
	current._exit(_player)
	current = get(state_name)
	current._enter(_player)

func _on_AnimationPlayer_animation_finished(anim_name):
#	if anim_name == "trick":
#	var player = get_parent()
	# [MIGRATION GODOT 4.7] anim_name est un StringName : conversion en String pour `in`.
	# [FIX] on ne repasse "en l'air" que si on est TOUJOURS en figure (sinon, une fin
	# d'animation tardive pouvait écraser l'état sol/staggered), et via go_to_state
	# pour que TrixState.exit() remette bien la rotation du sprite à 0.
	if "trick" in str(anim_name) and player._states.current == player._states.trixing:
		player._states.go_to_state(player, "in_air")
