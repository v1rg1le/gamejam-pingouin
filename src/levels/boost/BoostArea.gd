extends Area2D

export var impulse_factor = 150  # Vector2(300, 0) # 300
export var accel_factor = Vector2(1.2, 0) #acceleration >1 decelaration 0<...<1
export var impulse_dir = Vector2(1,0)
export var impulse_mode = false
export var accel_mode = false
#export(String, FILE) var collision_shape_path 

func _ready():
	$AnimatedSprite.playing = true
	

func _on_BoostArea_body_entered(body):
	if body.name == "Player":
#		print('player')
#		print(body._velocity)
#Boost dans une direction ici Vector2(1,0) = down
		if impulse_mode:
			body._velocity += impulse_factor*impulse_dir.normalized()

##Accélération #ATTENTION UN PEU BUGUE MAIS CA MARCHE INCH
		if accel_mode:
			body._velocity *= accel_factor
#		print(body._velocity)
