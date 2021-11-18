extends StaticBody2D

const UNIT_SIZE = 64
export(int) var taille = UNIT_SIZE*20 #ATTENTION PAS TROP HAUT SINON CA PLANTE
export(int) var rayon = UNIT_SIZE*15

var boost_res = preload("res://src/levels/boost/BoostArea.tscn")  # .instance()

var decoration_res = preload("res://sprites/levels/decoration/Igloo.tscn") #Igloo
var warning_res = preload("res://sprites/levels/decoration/Warning.tscn")
var end_res = preload("res://src/levels/Arche.tscn")
var finish_podium_res= preload("res://src/levels/decoration/FinishPodium.tscn")
var finish_gate_res= preload("res://src/levels/FinishGate.tscn")
var ice_medium1_res= preload("res://src/levels/decoration/IceMedium1.tscn")
var ice_medium2_res= preload("res://src/levels/decoration/IceMedium2.tscn")
var ice_small_res= preload("res://src/levels/decoration/IceSmall.tscn")
var buisson_res= preload("res://src/levels/decoration/Buisson.tscn")
var block_res= preload("res://src/levels/parts/Block.tscn")

export(int) var polygon_large = 640

export(bool) var is_boost = false
export var boost_treshold = 0.4
export(bool) var is_igloo = false
export var igloo_treshold = 0.01 #ATTENTION -igloo_treshold<...<igloo_treshold
export(bool) var is_final_map = false


#Permet d'avoir la position de la fin (x,y) y=end_height x=map_width * NUMERO MAP + SOMME DES GAP
var end_x = 0
var end_y = 0

func _ready() -> void:
	randomize()
	var curve = generate_curve()

	$CollisionPolygon2D.polygon = curve
	$Polygon2D.polygon = curve
	$Line2D.points = curve

func generate_curve() -> PoolVector2Array:
	var curve 
## QUARTER PIPE
	curve = PoolVector2Array (
		[
			Vector2(0, 0),
			Vector2(0, taille/4),
			Vector2(0, taille/2),
			Vector2(0, 3*taille/4),
			Vector2(0, taille),
			Vector2(taille/4, taille),
			Vector2(taille/2, taille),
			Vector2(3*taille/4, taille),
			Vector2(taille, taille), 

		]
	)
	for teta in range(90 ,181,2):
		var point
		point=Vector2(cos(deg2rad(teta)), sin(deg2rad(teta))) *rayon + Vector2(taille, 0)
		curve.append(point)
	curve.append(Vector2(0, 0))

	return curve
		

func add_block(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var block = block_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	block.position = position
	add_child(block)
#	return deco

func add_buisson(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var buisson = buisson_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	buisson.position = position
	add_child(buisson)
#	return deco

func add_ice_medium1(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var ice_medium1 = ice_medium1_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	ice_medium1.position = position
	add_child(ice_medium1)
#	return deco

func add_ice_medium2(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var ice_medium2 = ice_medium2_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	ice_medium2.position = position
	add_child(ice_medium2)
#	return deco

func add_ice_small(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var ice_small = ice_small_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	ice_small.position = position
	add_child(ice_small)
#	return deco

func add_finish_podium(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var finish_podium = finish_podium_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	finish_podium.position = position
	add_child(finish_podium)
#	return deco

func add_finish_gate(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var finish_gate = finish_gate_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	finish_gate.position = position
	add_child(finish_gate)
#	return deco

func add_boost(position :Vector2):
	var boost = boost_res.instance()
	boost.impulse_mode = true
	boost.global_position = position 
	add_child(boost)


func add_decoration(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var deco = decoration_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	deco.global_position = position
	add_child(deco)
#	return deco

func add_warning(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var warning = warning_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	warning.global_position = position
	add_child(warning)
#	return deco

func add_end(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var end = end_res.instance()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	end.global_position = position
	add_child(end)
#	return deco
