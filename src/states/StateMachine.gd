extends Node2D
class_name StateMachine

onready var in_air: InAirState = $"InAirState"
onready var on_ground: OnGroundState = $"OnGroundState"

onready var idling: IdleState = $"IdleState"
onready var sliding: SlidingState = $"SlidingState"
onready var jumping: JumpingState = $"JumpingState"
onready var running: RunningState = $"RunningState"
onready var staggered: StaggeredState = $"StaggeredState"
onready var hooking: HookingState = $"HookingState"
onready var trixing: TrixState = $"TrixState"

onready var super_state_label: Label = $"SuperState"
onready var sub_state_label: Label = $"SubState"
onready var label3: Label = $"Label3"

onready var current: PlayerState = on_ground

# Called when the node enters the scene tree for the first time.
func _ready():
#	current_state = idling
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
