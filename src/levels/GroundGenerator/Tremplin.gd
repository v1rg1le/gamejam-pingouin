extends GroundGeneratorPart

export(int) var map_height = UNIT_SIZE * 5  #ATTENTION PAS TROP HAUT SINON CA PLANTE

export(int) var polygon_large = 3200

export var slope_length = UNIT_SIZE * 40
export(float) var entering_slope_angle = -32
var entering_coeff_pente = tan(deg2rad(entering_slope_angle))
export(float) var exiting_slope_angle = 20
var exiting_coeff_pente = tan(deg2rad(exiting_slope_angle))
export var ramp_length = UNIT_SIZE * 12

var map_width = slope_length + ramp_length

#Permet d'avoir la position de la fin (x,y) y=end_height x=map_width * NUMERO MAP + SOMME DES GAP
var end_x = 0
var end_y = 0


func _ready() -> void:
	randomize()
	var curve = generate_curve()

	$CollisionPolygon2D.polygon = curve
	$Polygon2D.polygon = curve
	$Line2D.points = curve

## POSITION AU MILLIEU
#	add_decoration("finish_podium", Vector2(deck_length+length+(flat_bottom_length/2),0))

### POSITION SUR LE DECK DE DROITE
#	add_decoration("finish_gate", Vector2(1.5*deck_length+2*length+flat_bottom_length,-height-7*UNIT_SIZE/8))
#	add_decoration("ice_small", Vector2(1.75*deck_length+2*length+flat_bottom_length,-height-UNIT_SIZE/4))
#	add_decoration("buisson", Vector2(1.15*deck_length+2*length+flat_bottom_length,-height-UNIT_SIZE/4))
#
### POSITION SUR LE DECK DE GAUCHE
#	add_decoration("finish_podium", Vector2(0.5*deck_length,-height-5*UNIT_SIZE/8))
#	add_decoration("ice_medium1", Vector2(0.85*deck_length,-height-UNIT_SIZE/4))
#	add_decoration("ice_medium2", Vector2(0.15*deck_length,-height-UNIT_SIZE/4))

	end_x = curve[curve.size() - 2].x
	end_y = curve[curve.size() - 2].y


#func f(x): #Tremplin 1
#	var y
#	if x<=slope_length:
#		y = -tan(deg2rad(32))*x
#	else:
#		y = -tan(deg2rad(32))*x + pow((x-slope_length)/(UNIT_SIZE/2),2)
#		print(pow(x-slope_length,2))
#	return y


func linear_interpolation(x, a, b):
	return (1 - x) * a + x * b


func f(x):  #Tremplin 2
	var y
	var coeff
	if x <= slope_length:
		y = entering_coeff_pente * x
	else:
		coeff = linear_interpolation(
			(float(x - slope_length)) / float(ramp_length),
			entering_coeff_pente,
			exiting_coeff_pente
		)
		y = coeff * (x - slope_length) + entering_coeff_pente * slope_length
	return y


func generate_curve() -> PoolVector2Array:
#PAST
#	var key = 0
	var debut = 0
	var fin = self.map_width
	var curve

# INITIALISE LE POOLVECTOR2ARRY ET CREER LA BASE A GAUCHE
	curve = PoolVector2Array(
		[
			Vector2(debut, polygon_large),  #+coeff_pente*debut effet tobogan
		]
	)

	for x in range(debut, fin, UNIT_SIZE):
		var point
#		if x<deck_length:
#			point=Vector2(x,height)
#		else:
#			point=Vector2(x,-f(x - deck_length)) # Le moins permets de retourner l'axe de y (Godot a des coordonn�es en y inverser par rapport � celle utiliser par les matheux)
		point = Vector2(x, -f(x))
		curve.append(point)

	curve.append(Vector2(fin - UNIT_SIZE, polygon_large))

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
#				add_decoration("boost", point)
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
#				add_decoration("igloo", point)
#
###=		INSTANCE IGLOO FIN
#
###		INSTANCE WARNING
#	var soon_end = map_width*0.85
#	add_decoration("warning", 
#		Vector2(soon_end,
#			map_height* self.simplex_noise.get_noise_2d(soon_end,0)
#			 + coeff_pente*soon_end)
#	)
###		INSTANCE WARNING FIN
#
###		INSTANCE END
#	if is_final_map:
#		var end = map_width*0.99
#		add_decoration("end", 
#			Vector2(end,
#				map_height* self.simplex_noise.get_noise_2d(end,0)
#				 + coeff_pente*end)
#		)
###		INSTANCE END FIN
#	curve.append(
#		Vector2(fin,
#		map_height*self.simplex_noise.get_noise_2d(fin,0) + coeff_pente*fin + polygon_large)) #+ coeff_pente*fin effet tobogan
##	print("Curve a la fin")
##	print(curve)
#
##	print(n_point)
#	return curve
