extends GroundGeneratorPart

export(float) var map_height = UNIT_SIZE * 7
export(int) var height_factor = 5

export(int) var polygon_large = 256

export(float) var deck_length = UNIT_SIZE * 8
export(float) var flat_bottom_length = UNIT_SIZE * 7
export(float) var length = UNIT_SIZE * 10
export(float) var deck_length_start = UNIT_SIZE * 2

#HALF PIPE 1
#var map_width = 2 * deck_length + 2 * length + flat_bottom_length
#HALF PIPE 2
var map_width = 2 * deck_length + 2 * map_height + flat_bottom_length

#Permet d'avoir la position de la fin (x,y) y=end_height x=map_width * NUMERO MAP + SOMME DES GAP
var end_x = 0
var end_y = 0

func _ready() -> void:
	randomize()
	var curve = generate_curve()

	$CollisionPolygon2D.polygon = curve
	$Polygon2D.polygon = curve
	$Line2D.points = curve

#	add_decoration("block", Vector2(deck_length + map_height + flat_bottom_length / 2, map_height))
	add_decoration("block", Vector2(deck_length + map_height, -map_height - UNIT_SIZE * 6))
	add_decoration("block", Vector2(deck_length + map_height + flat_bottom_length, -map_height - UNIT_SIZE * 6))
##HALF PIPE 1
## POSITION AU MILIEU
#	add_decoration("finish_podium", Vector2(deck_length+length+(flat_bottom_length/2),0))

### POSITION SUR LE DECK DE DROITE
#	add_decoration("finish_gate", Vector2(1.5*deck_length+2*length+flat_bottom_length,-map_height-7*UNIT_SIZE/8))
#	add_decoration("ice_small", Vector2(1.75*deck_length+2*length+flat_bottom_length,-map_height-UNIT_SIZE/4))
#	add_decoration("buisson", Vector2(1.15*deck_length+2*length+flat_bottom_length,-map_height-UNIT_SIZE/4))
#
### POSITION SUR LE DECK DE GAUCHE
#	add_decoration("finish_podium", Vector2(0.5*deck_length,-map_height-5*UNIT_SIZE/8))
#	add_decoration("ice_medium1", Vector2(0.85*deck_length,-map_height-UNIT_SIZE/4))
#	add_decoration("ice_medium2", Vector2(0.15*deck_length,-map_height-UNIT_SIZE/4))

## POSITION SUR LE DECK DE DROITE
	add_decoration("finish_gate", 
		Vector2(
			1.5 * deck_length + 2 * map_height + flat_bottom_length,
			-map_height - 7 * UNIT_SIZE / 8 - deck_length_start
		)
	)
	add_decoration("ice_small", 
		Vector2(
			1.75 * deck_length + 2 * map_height + flat_bottom_length,
			-map_height - UNIT_SIZE / 4 - deck_length_start
		)
	)
	add_decoration("buisson", 
		Vector2(
			1.15 * deck_length + 2 * map_height + flat_bottom_length,
			-map_height - UNIT_SIZE / 4 - deck_length_start
		)
	)

## POSITION SUR LE DECK DE GAUCHE
	add_decoration("finish_podium", Vector2(0.5 * deck_length, -map_height - 5 * UNIT_SIZE / 8 - deck_length_start))
	add_decoration("ice_medium1", Vector2(0.85 * deck_length, -map_height - UNIT_SIZE / 4 - deck_length_start))
	add_decoration("ice_medium2", Vector2(0.15 * deck_length, -map_height - UNIT_SIZE / 4 - deck_length_start))

	end_x = curve[curve.size() - 2].x
	end_y = curve[curve.size() - 2].y


#func f(x): #HALF_PIPE 1
#	var y
#	if x<=deck_length:
#		y=map_height #FIRST DECK
#	elif x>deck_length && x<=deck_length+length: #deck_length<...<deck_length+length FIRST RAMP
#		y = pow(b,x-deck_length)*map_height
#	elif x>deck_length+length && x<=deck_length+length+flat_bottom_length:
#		y=pow(b,length)*map_height
#	elif x>deck_length+length+flat_bottom_length && x<=deck_length+2*length+flat_bottom_length:
#		var offset = deck_length+2*length+flat_bottom_length
#		y= pow(b,-(x-offset))*map_height
#	else:
#		y=map_height
#	return y


func f(x, rayon):
	var y
	if x < deck_length:
		y = map_height + deck_length_start  #FIRST DECK
	elif x >= deck_length && x < deck_length + map_height:  #deck_length<...<deck_length+length FIRST RAMP
		y = -sqrt(pow(map_height, 2) - pow(x - deck_length - map_height, 2)) + map_height
	elif x >= deck_length + map_height && x < deck_length + map_height + flat_bottom_length:
		y = 0
	elif (
		x >= deck_length + map_height + flat_bottom_length
		&& x < deck_length + 2 * map_height + flat_bottom_length
	):
		var offset = flat_bottom_length
		y = -sqrt(pow(map_height, 2) - pow(x - (deck_length + map_height + flat_bottom_length), 2)) + map_height  #-sqrt(pow(map_height,2)-pow(x-deck_length-map_height-offset,2))
	else:
		y = map_height + deck_length_start
	return y


func generate_curve() -> PoolVector2Array:
	var debut = 0
	var fin = self.map_width
	var curve

	# INITIALISE LE POOLVECTOR2ARRY ET CREER LA BASE A GAUCHE
	curve = PoolVector2Array(
		[
			Vector2(debut, polygon_large),  #+coeff_pente*debut effet tobogan
		]
	)

	for x in range(debut, fin, UNIT_SIZE / 4):
		var point

	#HALF PIPE 1
	#	point=Vector2(x,-f(x)) # Le moins permets de retourner l'axe de y (Godot a des coordonn�es en y inverser par rapport � celle utiliser par les matheux)
	#HALF PIPE 2
		point = Vector2(x, -f(x, map_height))
		curve.append(point)

	curve.append(Vector2(fin - UNIT_SIZE / 4, polygon_large))
	var p = range(debut, fin - UNIT_SIZE / 4, map_width / 16)
	p.invert()
	print(p)
	for x in p:
		curve.append(Vector2(x, polygon_large))
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
##	print("Curve à la fin")
##	print(curve)
#
##	print(n_point)
#	return curve
