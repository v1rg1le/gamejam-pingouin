extends RefCounted
class_name PipeBend
# =============================================================================
#  PipeBend.gd — [VIRAGES 1.66] Morceau de pipe qui REDIRIGE Pinpouin.
# -----------------------------------------------------------------------------
#  Demande de l'équipe (croquis du quart de pipe, 23/11) : « des bouts de
#  terrain qui redirigent selon un angle : un quarter pipe pour 90°, 1/8 de
#  half-pipe pour 45°, d'autres fractions pour un angle donné de 0 à 180°,
#  quitte à mettre comme dans Trackmania des boosts au sol pour garder
#  Pinpouin collé contre la paroi ». Choix de l'équipe : une seule pièce
#  réglable (angle, rayon) avec des boosts le long de la courbe, forts quand
#  ça monte, aucun quand ça descend (couleur = force).
#
#  CONVENTIONS (coordonnées de Godot : y vers le BAS)
#   - un CAP (« heading ») est un angle en degrés : 0 = vers la droite,
#     +90 = vers le bas, -90 = vers le haut ;
#   - un VIRAGE `turn` signé : négatif = on tourne vers le HAUT (sens inverse
#     des aiguilles d'une montre à l'écran : quarter pipe classique, le sol est
#     à l'extérieur du virage, Pinpouin est plaqué dessus) ; positif = vers le
#     BAS (le sol est à l'intérieur : c'est un bord arrondi, on décolle).
#   - un virage est un ARC DE CERCLE : son centre est du côté où l'on tourne.
#
#  Fonctions statiques (pas de nœud) : les générateurs de niveaux (Gruyère,
#  cavernes) s'en servent pour fabriquer sols, rampes, quarter pipes et
#  tremplins, et pour placer les boosts.
# =============================================================================

## Force des boosts posés dans une montée (BoostArea : 0..1) : de quoi garder
## de la vitesse en montant ; plus la paroi est raide, plus la flèche est forte.
## Sur la pente θ, la gravité retire g·sin θ (≈ 800·sin θ px/s²) : la force
## 0,25 (450 px/s², jaune) tient sur ~30°, 0,5 (900, orange) jusqu'à la
## verticale ; on prend un peu de marge.
static func boost_strength_for_slope(climb_deg: float) -> float:
	if climb_deg <= 3.0:
		return 0.0
	var need := 800.0 * sin(deg_to_rad(minf(climb_deg, 90.0))) + 150.0
	return clampf(need / 1800.0, 0.2, 1.0)


## Points d'un arc : départ `p0`, cap de départ `heading` (degrés), virage
## `turn` (degrés, signé, voir l'en-tête), rayon `radius`. `step_deg` = finesse.
static func arc(p0: Vector2, heading: float, turn: float, radius: float, step_deg := 4.0) -> PackedVector2Array:
	var out := PackedVector2Array([p0])
	if absf(turn) < 0.01:
		return out
	var side := signf(turn)                                    # -1 : vers le haut
	var center := p0 + Vector2.from_angle(deg_to_rad(heading + side * 90.0)) * radius
	var a0 := heading - side * 90.0                            # angle de p0 vu du centre
	var n := maxi(2, int(ceil(absf(turn) / step_deg)))
	for i in range(1, n + 1):
		var a := a0 + turn * float(i) / n
		out.append(center + Vector2.from_angle(deg_to_rad(a)) * radius)
	return out


## Cap à la fin d'un arc.
static func end_heading(heading: float, turn: float) -> float:
	return heading + turn


## Segment droit depuis `p0` au cap `heading`, de longueur `length`.
static func straight(p0: Vector2, heading: float, length: float) -> PackedVector2Array:
	return PackedVector2Array([p0, p0 + Vector2.from_angle(deg_to_rad(heading)) * length])


## Concatène des morceaux (sans doubler les points communs).
static func join(parts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for part in parts:
		for i in part.size():
			if out.size() > 0 and out[out.size() - 1].distance_to(part[i]) < 1.0:
				continue
			out.append(part[i])
	return out


## Inverse l'ordre d'une ligne.
static func reversed(line: PackedVector2Array) -> PackedVector2Array:
	var out := line.duplicate()
	out.reverse()
	return out


## Boosts à poser le long d'une ligne de sol parcourue dans l'ordre de ses
## points : tous les `spacing` px, là où la ligne MONTE (cap < -3°), une flèche
## dans le sens du parcours, de force adaptée à la pente.
## Retourne des {pos, rot, strength, scale, air} (même format que
## CaveGenerator.boosts) ; la flèche est tournée selon le cap.
static func boosts_along(line: PackedVector2Array, spacing := 420.0, arrow_scale := 2.0, first_offset := 120.0) -> Array:
	var out: Array = []
	var dist := 0.0
	var next := first_offset
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var seg := a.distance_to(b)
		while next <= dist + seg and seg > 0.0:
			var t := (next - dist) / seg
			var p := a.lerp(b, t)
			var heading := rad_to_deg((b - a).angle())
			# on monte quand le cap est vers le haut (angle < 0), à droite
			# comme à gauche : la montée vaut -sin(cap)
			var climb := rad_to_deg(asin(clampf(-(b - a).normalized().y, -1.0, 1.0)))
			var s := boost_strength_for_slope(climb)
			if s > 0.0:
				out.append({"pos": p, "rot": heading, "strength": s, "scale": arrow_scale, "air": false})
			next += spacing
		dist += seg
	return out
