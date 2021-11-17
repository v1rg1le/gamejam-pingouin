extends StaticBody2D

const UNIT_SIZE = 64
const width_point = 10
export(int) var map_height = UNIT_SIZE*5 #ATTENTION PAS TROP HAUT SINON CA PLANTE

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



export(int) var polygon_large = 6400

#export(float) var height = UNIT_SIZE*7
#export(float) var deck_length = UNIT_SIZE*8
#export(float) var flat_bottom_length = UNIT_SIZE*4
#export(float) var length = UNIT_SIZE*10

export var slope_length = UNIT_SIZE*40
export var ramp_length = UNIT_SIZE*15

var map_width = slope_length+ramp_length 

#var b = 0.9977


export(bool) var coef_pente_animated = false
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
#	var curve = $Path2D.curve
	var curve = generate_curve()
#	var polygon = curve.get_baked_points()
#	print(polygon.size())

	$CollisionPolygon2D.polygon = curve
	$Polygon2D.polygon = curve
	$Line2D.points = curve
	

## POSITION AU MILLIEU
#	add_finish_podium(Vector2(deck_length+length+(flat_bottom_length/2),0))

### POSITION SUR LE DECK DE DROITE
#	add_finish_gate(Vector2(1.5*deck_length+2*length+flat_bottom_length,-height-7*UNIT_SIZE/8))
#	add_ice_small(Vector2(1.75*deck_length+2*length+flat_bottom_length,-height-UNIT_SIZE/4))
#	add_buisson(Vector2(1.15*deck_length+2*length+flat_bottom_length,-height-UNIT_SIZE/4))
#
### POSITION SUR LE DECK DE GAUCHE
#	add_finish_podium(Vector2(0.5*deck_length,-height-5*UNIT_SIZE/8))
#	add_ice_medium1(Vector2(0.85*deck_length,-height-UNIT_SIZE/4))
#	add_ice_medium2(Vector2(0.15*deck_length,-height-UNIT_SIZE/4))
	
	end_x = curve[curve.size()-2].x
	end_y = curve[curve.size()-2].y
	
func f(x): #Tremplin
	var y
	if x<=slope_length:
		y = -tan(deg2rad(32))*x
	else:
		y = -tan(deg2rad(32))*x + pow((x-slope_length)/(UNIT_SIZE/2),2)
		print(pow(x-slope_length,2))
	return y

	
	
func generate_curve() -> PoolVector2Array:
#PAST
#	var key = 0
	var debut = 0
	var fin = self.map_width
	var curve 
	

# INITIALISE LE POOLVECTOR2ARRY ET CREER LA BASE A GAUCHE
	curve = PoolVector2Array (
		[
			Vector2(debut, polygon_large), #+coeff_pente*debut effet tobogan
		]
	)

	for x in range(debut ,fin,UNIT_SIZE):

		var point
#		if x<deck_length:
#			point=Vector2(x,height)
#		else:
#			point=Vector2(x,-f(x - deck_length)) # Le moins permets de retourner l'axe de y (Godot a des coordonnées en y inverser par rapport à celle utiliser par les matheux)
		point=Vector2(x,-f(x))
		curve.append(point)
	
		
	curve.append(Vector2(fin-UNIT_SIZE,polygon_large))
	
	return curve
		
	# DEUX FOR POUR FAIRE LES INSTANCES L'UN APRES L'AUTRE
	
###		INSTANCE BOOST
#	if is_boost:
#		for x in range(debut ,fin,UNIT_SIZE):
#			var point 
#
#			point=Vector2(x,
#			map_height* self.simplex_noise.get_noise_2d(x,0)
#			 + coeff_pente*x)
#
#			if simplex_noise.get_noise_2d(x,0)<boost_treshold: #-1+1.4=0.4
#				add_boost(point)
###		INSTANCE BOOST FIN
#
###=		INSTANCE IGLOO
#	if is_igloo:
#		for x in range(debut ,fin,UNIT_SIZE):
#			var point 
#
#			point=Vector2(x,
#			map_height* self.simplex_noise.get_noise_2d(x,0)
#			 + coeff_pente*x)
#
#
#			if simplex_noise.get_noise_2d(x,0)>-igloo_treshold && simplex_noise.get_noise_2d(x,0)<igloo_treshold: # 1-1.5=-0.5
#	#			print(point_after)
#				add_decoration(point)
#
###=		INSTANCE IGLOO FIN
#
###		INSTANCE WARNING
#	var soon_end = map_width*0.85
#	add_warning(
#		Vector2(soon_end,
#			map_height* self.simplex_noise.get_noise_2d(soon_end,0)
#			 + coeff_pente*soon_end)
#	)
###		INSTANCE WARNING FIN
#
###		INSTANCE END
#	if is_final_map:
#		var end = map_width*0.99
#		add_end(
#			Vector2(end,
#				map_height* self.simplex_noise.get_noise_2d(end,0)
#				 + coeff_pente*end)
#		)
###		INSTANCE END FIN
#	curve.append(
#		Vector2(fin,
#		map_height*self.simplex_noise.get_noise_2d(fin,0) + coeff_pente*fin + polygon_large)) #+ coeff_pente*fin effet tobogan
##	print("Curve à la fin")
##	print(curve)
#
##	print(n_point)
#	return curve

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

