extends Node2D
class_name StateMachine

onready var in_air: InAirState = $"InAirState"
onready var on_ground: OnGroundState = $"OnGroundState"

onready var idling: IdleState = $"IdleState"
onready var sliding: SlidingState = $"SlidingState"
onready var jumping: JumpingState = $"JumpingState"
onready var running: RunningState = $"RunningState"
onready var staggered: StaggeredState = $"StaggeredState"
onready var hooking_air_state: HookingInAirState = $"HookingInAirState"
onready var hooking_on_ground: HookingOnGroundState = $"HookingOnGroundState"
onready var trixing: TrixState = $"TrixState"
onready var pumping: PumpState = $"PumpState"

onready var super_state_label: Label = $"SuperState"
onready var sub_state_label: Label = $"SubState"
onready var label3: Label = $"Label3"

onready var current: PlayerState = on_ground

onready var player = get_parent()

func _ready():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass

func go_to_state(_player: KinematicBody2D, state_name: String) -> void:
	current._exit(_player)
	current = get(state_name)
	current._enter(_player)

func _on_AnimationPlayer_animation_finished(anim_name):
#	if anim_name == "trick":
	if "trick" in anim_name:
		player._states.current = player._states.in_air
		player._states.current._enter(player)
