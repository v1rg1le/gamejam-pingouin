extends StaticBody2D
class_name GroundGeneratorPart

const UNIT_SIZE = 64

var boost_res = preload("res://src/levels/boost/BoostArea.tscn")  # .instance()
var igloo_res = preload("res://sprites/levels/decoration/Igloo.tscn")  #Igloo
var warning_res = preload("res://sprites/levels/decoration/Warning.tscn")
var end_res = preload("res://src/levels/Arche.tscn")
var finish_podium_res = preload("res://src/levels/decoration/FinishPodium.tscn")
var finish_gate_res = preload("res://src/levels/FinishGate.tscn")
var ice_medium1_res = preload("res://src/levels/decoration/IceMedium1.tscn")
var ice_medium2_res = preload("res://src/levels/decoration/IceMedium2.tscn")
var ice_small_res = preload("res://src/levels/decoration/IceSmall.tscn")
var buisson_res = preload("res://src/levels/decoration/Buisson.tscn")
var block_res = preload("res://src/levels/parts/Block.tscn")

export(bool) var coef_pente_animated = false
export(bool) var is_boost = false
export var boost_treshold = 0.4
export(bool) var is_igloo = false
export var igloo_treshold = 0.01  #ATTENTION -igloo_treshold<...<igloo_treshold
export(bool) var is_final_map = false

func add_decoration(deco_name: String, position: Vector2, global_position: bool = false):
	var deco
	match deco_name:
		"block":
			deco = block_res.instance()
			deco.global_position = position
		"boost":
			deco = boost_res.instance()
			deco.impulse_mode = true
			deco.global_position = position
		"buisson":
			deco = buisson_res.instance()
			deco.position = position
		"end":
			deco = end_res.instance()
			deco.global_position = position
		"finish_podium":
			deco = finish_podium_res.instance()
			deco.position = position
		"finish_gate":
			deco = finish_gate_res.instance()
			deco.position = position
		"ice_medium1":
			deco = ice_medium1_res.instance()
			deco.position = position
		"ice_medium2":
			deco = ice_medium2_res.instance()
			deco.position = position
		"ice_small":
			deco = ice_small_res.instance()
			deco.position = position
		"igloo":
			deco = igloo_res.instance()
			deco.position = position
		"warning":
			deco = warning_res.instance()
			deco.global_position = position
	add_child(deco)
