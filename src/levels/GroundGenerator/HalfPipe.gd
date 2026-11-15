extends StaticBody2D

const UNIT_SIZE = 64
const width_point = 10
@export var map_height: int = UNIT_SIZE*5 #ATTENTION PAS TROP HAUT SINON CA PLANTE

var boost_res = preload("res://src/levels/boost/BoostArea.tscn")  # super.instantiate()

var decoration_res = preload("res://src/levels/decoration/Igloo.tscn") #Igloo
var warning_res = preload("res://src/levels/decoration/Warning.tscn")
var end_res = preload("res://src/levels/Arche.tscn")
var finish_podium_res= preload("res://src/levels/decoration/FinishPodium.tscn")
var finish_gate_res= preload("res://src/levels/FinishGate.tscn")
var ice_medium1_res= preload("res://src/levels/decoration/IceMedium1.tscn")
var ice_medium2_res= preload("res://src/levels/decoration/IceMedium2.tscn")
var ice_small_res= preload("res://src/levels/decoration/IceSmall.tscn")
var buisson_res= preload("res://src/levels/decoration/Buisson.tscn")
#var block_res= preload("res://src/levels/parts/Block.tscn")
var block_res= preload("res://src/levels/parts/StaticBody2DFish.tscn")



@export var polygon_large: int = 640

@export var height: float = UNIT_SIZE*7
@export var deck_length: float = UNIT_SIZE*8
@export var flat_bottom_length: float = UNIT_SIZE*7
@export var length: float = UNIT_SIZE*10
@export var deck_length_start: float = UNIT_SIZE

#HALF PIPE 1
#var map_width = 2*deck_length+2*length+flat_bottom_length
#HALF PIPE 2
var map_width = 2*deck_length+2*height+flat_bottom_length

var b = pow(0.01,1/length)
#var b = 0.9977


@export var coef_pente_animated: bool = false
@export var is_boost: bool = false
@export var boost_treshold = 0.4
@export var is_igloo: bool = false
@export var igloo_treshold = 0.01 #ATTENTION -igloo_treshold<...<igloo_treshold
@export var is_final_map: bool = false


#Permet d'avoir la position de la fin (x,y) y=end_height x=map_width * NUMERO MAP + SOMME DES GAP
var end_x = 0
var end_y = 0

func _ready() -> void:
#	print("b=")
#	print(b)
	randomize()
#	var curve = $Path2D.curve
	var curve = generate_curve()
#	var polygon = curve.get_baked_points()
#	print(polygon.size())

	# [FIX VITESSE -> 0] collision en segments (contour) : plus d'arêtes internes
	# issues du découpage convexe, qui créaient des "collisions fantômes".
	$CollisionPolygon2D.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
	$CollisionPolygon2D.polygon = curve
	$Polygon2D.polygon = curve
	$Line2D.points = curve
	

#	add_block(Vector2(deck_length+height+flat_bottom_length/2,height))
	add_block(Vector2(deck_length+height,-height-UNIT_SIZE*6))
	add_block(Vector2(deck_length+height+flat_bottom_length,-height-UNIT_SIZE*6))
##HALF PIPE 1
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
	
## POSITION SUR LE DECK DE DROITE
	add_finish_gate(Vector2(1.5*deck_length+2*height+flat_bottom_length,-height-7*UNIT_SIZE/8.0-deck_length_start))
	add_ice_small(Vector2(1.75*deck_length+2*height+flat_bottom_length,-height-UNIT_SIZE/4.0-deck_length_start))
	add_buisson(Vector2(1.15*deck_length+2*height+flat_bottom_length,-height-UNIT_SIZE/4.0-deck_length_start))

## POSITION SUR LE DECK DE GAUCHE
	add_finish_podium(Vector2(0.5*deck_length,-height-5*UNIT_SIZE/8.0-deck_length_start))
	add_ice_medium1(Vector2(0.85*deck_length,-height-UNIT_SIZE/4.0-deck_length_start))
	add_ice_medium2(Vector2(0.15*deck_length,-height-UNIT_SIZE/4.0-deck_length_start))
	
	end_x = curve[curve.size()-2].x
	end_y = curve[curve.size()-2].y
	
#func f(x): #HALF_PIPE 1
#	var y
#	if x<=deck_length:
#		y=height #FIRST DECK
#	elif x>deck_length && x<=deck_length+length: #deck_length<...<deck_length+length FIRST RAMP
#		y = pow(b,x-deck_length)*height
#	elif x>deck_length+length && x<=deck_length+length+flat_bottom_length:
#		y=pow(b,length)*height
#	elif x>deck_length+length+flat_bottom_length && x<=deck_length+2*length+flat_bottom_length:
#		var offset = deck_length+2*length+flat_bottom_length
#		y= pow(b,-(x-offset))*height
#	else:
#		y=height
#	return y

func f(x, _rayon):
	var y
	if x<deck_length:
		y=height+deck_length_start #FIRST DECK
	elif x>=deck_length && x<deck_length+height: #deck_length<...<deck_length+length FIRST RAMP
		y = -sqrt(pow(height,2)-pow(x-deck_length-height,2))+height 
	elif x>=deck_length+height && x<deck_length+height+flat_bottom_length:
		y=0
	elif x>=deck_length+height+flat_bottom_length && x<deck_length+2*height+flat_bottom_length:
		var _offset = flat_bottom_length
		y = -sqrt(pow(height,2)-pow(x-(deck_length+height+flat_bottom_length),2))+height  #-sqrt(pow(height,2)-pow(x-deck_length-height-offset,2)) 
	else:
		y=height+deck_length_start
	return y 
	
	
func generate_curve() -> PackedVector2Array:
#PAST
#	var key = 0
	var debut = 0
	var fin = self.map_width
	var curve 
	

# INITIALISE LE POOLVECTOR2ARRY ET CREER LA BASE A GAUCHE
	curve = PackedVector2Array (
		[
			Vector2(debut, polygon_large), #+coeff_pente*debut effet tobogan
		]
	)

	for x in range(debut ,fin,UNIT_SIZE/32.0):

		var point

#HALF PIPE 1
#		point=Vector2(x,-f(x)) # Le moins permets de retourner l'axe de y (Godot a des coordonnées en y inverser par rapport à celle utiliser par les matheux)
#HALF PIPE 2
		point=Vector2(x,-f(x,height)) 
		curve.append(point)
	
		
	curve.append(Vector2(fin-UNIT_SIZE/32.0,polygon_large))
	
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

func add_block(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var block = block_res.instantiate()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	block.position = position
	add_child(block)
#	return deco

func add_buisson(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var buisson = buisson_res.instantiate()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	buisson.position = position
	add_child(buisson)
#	return deco

func add_ice_medium1(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var ice_medium1 = ice_medium1_res.instantiate()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	ice_medium1.position = position
	add_child(ice_medium1)
#	return deco

func add_ice_medium2(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var ice_medium2 = ice_medium2_res.instantiate()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	ice_medium2.position = position
	add_child(ice_medium2)
#	return deco

func add_ice_small(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var ice_small = ice_small_res.instantiate()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	ice_small.position = position
	add_child(ice_small)
#	return deco

func add_finish_podium(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var finish_podium = finish_podium_res.instantiate()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	finish_podium.position = position
	add_child(finish_podium)
#	return deco

func add_finish_gate(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	# [ARRIVÉE 1.18] l'arrivée est désormais sur l'arche de la dernière île
	# (voir sol.gd, _add_finish_at_arch) : pas de 2e arrivée dans le half-pipe.
	# (Un half-pipe utilisé seul, sans île avant, garde la sienne.)
	if is_inside_tree() and not get_tree().get_nodes_in_group("finish_gate").is_empty():
		return
	var finish_gate = finish_gate_res.instantiate()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	finish_gate.position = position
	# [ARRIVÉE 1.13] Le mur de droite du half-pipe finit à la verticale : sans
	# grappin ni saut, on monte, on retombe, et le pingouin pouvait rester
	# bloqué contre le haut du mur à quelques px du deck où est l'arche (mesuré
	# sur Nice Slope : bloqué à 274 px de la ligne). On descend donc la ligne
	# d'arrivée au milieu de la courbe de droite (l'arche ne bouge pas) et on
	# allonge la bande vers le bas jusqu'au fond du half-pipe.
	finish_gate.trigger_offset_x = -(0.5 * deck_length + 0.5 * height)
	finish_gate.finish_band_below = height + 3 * UNIT_SIZE
	add_child(finish_gate)
#	return deco

func add_boost(position :Vector2):
	var boost = boost_res.instantiate()
	boost.impulse_mode = true
	boost.global_position = position 
	add_child(boost)


func add_decoration(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var deco = decoration_res.instantiate()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	deco.global_position = position
	add_child(deco)
#	return deco

func add_warning(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var warning = warning_res.instantiate()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	warning.global_position = position
	add_child(warning)
#	return deco

func add_end(position :Vector2):#, rotation_degrees): #point_a:Vector2,point_b:Vector2):
	var end = end_res.instantiate()
#	var dvec = (point_b - point_a).normalized()
#	var normal = Vector2(dvec.y, -dvec.x)
	end.global_position = position
	add_child(end)
#	return deco

