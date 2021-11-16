extends StaticBody2D

const UNIT_SIZE = 64
const width_point = 10
export(int) var map_height = UNIT_SIZE*5 #ATTENTION PAS TROP HAUT SINON CA PLANTE

var boost_res = preload("res://src/levels/boost/BoostArea.tscn")  # .instance()
var decoration_res = preload("res://sprites/levels/decoration/Igloo.tscn") # 
var warning_res = preload("res://sprites/levels/decoration/Warning.tscn")
var end_res = preload("res://src/levels/Arche.tscn")

export(int) var polygon_large = 640



export(float) var height = UNIT_SIZE*7
export(float) var deck_length = UNIT_SIZE*5
export(float) var flat_bottom_length = UNIT_SIZE*4
export(float) var length = UNIT_SIZE*10

var map_width = 2*deck_length+2*length+flat_bottom_length

var b = pow(0.01,1/length)
#var b = 0.9977


onready var n_point = 0

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
	print("b=")
	print(b)
	randomize()
#	var curve = $Path2D.curve
	var curve = generate_curve()
#	var polygon = curve.get_baked_points()
#	print(polygon.size())

	$CollisionPolygon2D.polygon = curve
	$Polygon2D.polygon = curve
	$Line2D.points = curve
	
	end_x = curve[curve.size()-2].x
	end_y = curve[curve.size()-2].y
	
func f(x): #HALF_PIPE
	var y
	if x<=deck_length:
		y=height #FIRST DECK
	elif x>deck_length && x<=deck_length+length: #deck_length<...<deck_length+length FIRST RAMP
		y = pow(b,x-deck_length)*height
	elif x>deck_length+length && x<=deck_length+length+flat_bottom_length:
		y=pow(b,length)*height
	elif x>deck_length+length+flat_bottom_length && x<=deck_length+2*length+flat_bottom_length:
		var offset = deck_length+2*length+flat_bottom_length
		y= pow(b,-(x-offset))*height
	else:
		y=height
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

