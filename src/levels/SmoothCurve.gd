class_name SmoothCurve
extends RefCounted
## =============================================================================
## [LISSAGE C² 1.71] Lissage des sols de collision, commun à tous les niveaux
## =============================================================================
## Demande de l'équipe (après la 1.70) : « réduire encore la cassure entre les
## bouts de terrain… des courbes C^infini en vrai ». Un sol de collision est
## forcément une suite de segments droits ; on vise donc :
##   1. une courbe LIMITE de classe C² (tangente ET courbure continues, plus
##      d'à-coup de courbure aux raccords entre deux morceaux de courbe) ;
##   2. une ligne brisée qui la suit, avec au plus MAX_TURN_DEG (1°) de
##      rotation d'un segment au suivant (Flat d'avant : jusqu'à 10°).
##
## Méthode (pour chaque « tronçon de sol » entre deux coins durs) :
##   a. on recoupe les segments trop longs (RESAMPLE_PX) : les points ajoutés
##      sont SUR les segments d'origine, la forme ne bouge pas ; ça garde
##      l'arrondi local (quelques pixels autour de chaque coin) ;
##   b. on calcule la B-spline cubique uniforme de ce contour (courbe C² :
##      tangente et courbure continues), « serrée » aux bouts (bouts fixes,
##      même direction qu'avant), et on la découpe morceau par morceau en
##      juste assez de pas pour ne jamais tourner de plus de MAX_TURN_DEG
##      (1 pas sur les lignes droites, plus dans les virages) ;
##   c. on retire les points alignés (lignes droites).
##
## Coins DURS (jamais arrondis) : un mur (segment de plus de HARD_SLOPE_DEG de
## pente) ou un vrai angle (plus de HARD_TURN_DEG) : un mur doit rester un mur,
## le bord d'un trou reste net. Écart à la forme d'origine : ~1 à 3 px au plus
## près des anciens coins, rien ailleurs.
##
## On ne lisse que les COLLISIONS : le dessin (Polygon2D, bordures) garde
## ses points d'origine (art inchangé, écart de 1 à 3 px invisible).
## Option 3 de l'équipe (pour plus tard, feuille de route) : glisse sur la
## courbe mathématique exacte (C∞ là où le sol l'est), sans segments.

const MAX_TURN_DEG := 1.0       # rotation max d'un segment au suivant
const HARD_SLOPE_DEG := 55.0    # au-delà : mur, coins nets
## Au-delà : vrai angle, coin net. 30° par défaut : les niveaux dont le
## dessin garde ses points d'origine (Flat…, tuto, L'Œuf, Gruyère partie 1)
## gardent ainsi le dessin et la collision à moins de ~3 px l'un de l'autre
## (un coin de 45° arrondi déplaçait le sol de 8 à 10 px sous le dessin).
## Les cavernes passent 60° (leur bordure est dessinée sur la collision
## lissée : aucun écart visible).
const HARD_TURN_DEG := 30.0
const RESAMPLE_PX := 24.0       # recoupe des segments (taille de l'arrondi d'un petit coin)
const RESAMPLE_MAX_PX := 48.0   # recoupe la plus large (coins forts)
const RESAMPLE_MAX_WIDE_PX := 96.0  # idem, cavernes (arrondi plus large permis)
const MIN_STEP_PX := 1.5        # segment le plus court produit
const DECIMATE_MAX_LEN := 96.0  # segment le plus long en fusionnant des points alignés
const MERGE_PX := 2.0           # points plus proches : fusionnés


## Lisse une ligne de sol ouverte (bouts fixes).
## `hard_turn` : angle au-delà duquel un coin reste net ; `wide` : arrondi des
## coins forts plus large (cavernes, où le dessin suit la collision).
static func smooth_open(pts: PackedVector2Array, max_turn := MAX_TURN_DEG, hard_turn := HARD_TURN_DEG, wide := false) -> PackedVector2Array:
	var p := dedupe(pts)
	if p.size() < 3:
		return p
	var hard := _hard_indices(p, false, hard_turn)
	var out := PackedVector2Array([p[0]])
	for k in hard.size() - 1:
		var run := p.slice(hard[k], hard[k + 1] + 1)
		var sm := _smooth_run(run, max_turn, wide)
		for j in range(1, sm.size()):
			out.append(sm[j])
	return out


## Lisse un polygone fermé (contour de sol, CollisionPolygon2D). Le polygone
## est parcouru à partir d'un coin dur, pour que le point d'indice 0 (et les
## coins durs) restent les mêmes ; un polygone sans coin dur est rendu tel quel.
static func smooth_closed(pts: PackedVector2Array, max_turn := MAX_TURN_DEG, hard_turn := HARD_TURN_DEG, wide := false) -> PackedVector2Array:
	var p := dedupe(pts)
	if p.size() > 2 and p[0].distance_to(p[p.size() - 1]) < MERGE_PX:
		p.remove_at(p.size() - 1)
	if p.size() < 4:
		return p
	var n := p.size()
	var hard := _hard_indices(p, true, hard_turn)
	if hard.is_empty():
		return p
	# on démarre au premier coin dur (en général l'indice 0 : coin bas-gauche)
	var start: int = hard[0]
	var ring := PackedVector2Array()
	for k in n + 1:
		ring.append(p[(start + k) % n])
	var ring_hard: Array = []
	for h in hard:
		ring_hard.append((h - start + n) % n)
	ring_hard.append(n)
	var out := PackedVector2Array([ring[0]])
	for k in ring_hard.size() - 1:
		var run := ring.slice(ring_hard[k], ring_hard[k + 1] + 1)
		var sm := _smooth_run(run, max_turn, wide)
		for j in range(1, sm.size()):
			out.append(sm[j])
	out.remove_at(out.size() - 1)    # dernier point = premier (anneau)
	# on remet l'ordre d'origine (le point d'indice 0 reste p[0])
	if start != 0:
		var idx := -1
		for k in out.size():
			if out[k].distance_to(p[0]) < 0.01:
				idx = k
				break
		if idx > 0:
			out = out.slice(idx) + out.slice(0, idx)
	return out


## Rotation maximale (degrés) entre deux segments voisins « de sol » :
## pour les mesures et les contrôles.
static func max_turn_deg(p: PackedVector2Array) -> float:
	var m := 0.0
	for i in range(1, p.size() - 1):
		var d1 := p[i] - p[i - 1]
		var d2 := p[i + 1] - p[i]
		if d1.length() < 0.01 or d2.length() < 0.01:
			continue
		if _slope_deg(d1) > HARD_SLOPE_DEG or _slope_deg(d2) > HARD_SLOPE_DEG:
			continue
		m = maxf(m, absf(rad_to_deg(d1.angle_to(d2))))
	return m


## Comme dedupe, avec une distance au choix.
static func dedupe_px(ch: PackedVector2Array, px: float) -> PackedVector2Array:
	if ch.size() < 2:
		return ch
	var out := PackedVector2Array([ch[0]])
	for k in range(1, ch.size() - 1):
		if ch[k].distance_to(out[out.size() - 1]) >= px:
			out.append(ch[k])
	var last: Vector2 = ch[ch.size() - 1]
	if out.size() > 1 and last.distance_to(out[out.size() - 1]) < px:
		out[out.size() - 1] = last
	else:
		out.append(last)
	return out


## Retire les points à moins de MERGE_PX du précédent (raccords entre deux
## courbes) : un segment de 0,5 px a une direction au hasard.
static func dedupe(ch: PackedVector2Array) -> PackedVector2Array:
	if ch.size() < 2:
		return ch
	var out := PackedVector2Array([ch[0]])
	for k in range(1, ch.size() - 1):
		if ch[k].distance_to(out[out.size() - 1]) >= MERGE_PX:
			out.append(ch[k])
	var last: Vector2 = ch[ch.size() - 1]
	if out.size() > 1 and last.distance_to(out[out.size() - 1]) < MERGE_PX:
		out[out.size() - 1] = last
	else:
		out.append(last)
	return out


# ----------------------------------------------------------------------------
# Détails
# ----------------------------------------------------------------------------

static func _slope_deg(d: Vector2) -> float:
	return rad_to_deg(atan2(absf(d.y), absf(d.x)))


## Coin dur en i : un des deux segments est un mur, ou l'angle est trop fort.
static func _is_hard(prev: Vector2, cur: Vector2, nxt: Vector2, hard_turn: float) -> bool:
	var d1 := cur - prev
	var d2 := nxt - cur
	if d1.length() < 0.01 or d2.length() < 0.01:
		return true
	if _slope_deg(d1) > HARD_SLOPE_DEG or _slope_deg(d2) > HARD_SLOPE_DEG:
		return true
	return absf(rad_to_deg(d1.angle_to(d2))) > hard_turn


## Indices des coins durs ; pour une ligne ouverte, les deux bouts en font
## toujours partie.
static func _hard_indices(p: PackedVector2Array, closed: bool, hard_turn: float) -> Array:
	var n := p.size()
	var hard: Array = []
	if closed:
		for i in n:
			if _is_hard(p[(i - 1 + n) % n], p[i], p[(i + 1) % n], hard_turn):
				hard.append(i)
	else:
		hard.append(0)
		for i in range(1, n - 1):
			if _is_hard(p[i - 1], p[i], p[i + 1], hard_turn):
				hard.append(i)
		hard.append(n - 1)
	return hard


## Un tronçon sans coin dur à l'intérieur : recoupe, puis échantillonne la
## B-spline cubique (C²) de ce contour, juste assez finement pour ne jamais
## tourner de plus de max_turn d'un segment au suivant.
static func _smooth_run(run: PackedVector2Array, max_turn: float, wide := false) -> PackedVector2Array:
	if run.size() < 3:
		return run    # un seul segment (mur, bord) : rien à arrondir
	if max_turn_deg(run) <= max_turn:
		return run    # déjà assez doux : on ne touche à rien
	# a. recoupe : points ajoutés SUR les segments d'origine (la forme ne
	# bouge pas) ; RESAMPLE_PX fixe la taille de l'arrondi autour d'un coin
	# Un coin fort a besoin d'un arrondi plus large (sinon la rotation se
	# concentre sur quelques pixels et il faudrait des segments trop courts
	# pour les nombres du moteur) : pas de recoupe = RESAMPLE_PX, ou le
	# triple (cavernes) ou 1,5 fois l'angle du coin voisin (en px), au plus
	# RESAMPLE_MAX_WIDE_PX / RESAMPLE_MAX_PX.
	var turns := PackedFloat32Array()
	turns.resize(run.size())
	for i in range(1, run.size() - 1):
		var e1: Vector2 = run[i] - run[i - 1]
		var e2: Vector2 = run[i + 1] - run[i]
		if e1.length() > 0.01 and e2.length() > 0.01:
			turns[i] = absf(rad_to_deg(e1.angle_to(e2)))
	var c := PackedVector2Array([run[0]])
	for i in range(1, run.size()):
		var a: Vector2 = run[i - 1]
		var b: Vector2 = run[i]
		var step: float = clampf((3.0 if wide else 1.5) * maxf(turns[i - 1], turns[i]), RESAMPLE_PX, RESAMPLE_MAX_WIDE_PX if wide else RESAMPLE_MAX_PX)
		var k := int(ceil(a.distance_to(b) / step))
		for j in range(1, k + 1):
			c.append(a.lerp(b, float(j) / k))
	# b. B-spline cubique uniforme « serrée » aux bouts (premier et dernier
	# points triplés) : elle part exactement du 1er point dans la direction du
	# 1er segment et finit au dernier point dans la direction du dernier
	# segment. Courbe C² (courbure continue) partout ailleurs.
	var ctl := PackedVector2Array([c[0], c[0]])
	ctl.append_array(c)
	ctl.append(c[c.size() - 1])
	ctl.append(c[c.size() - 1])
	var out := PackedVector2Array([c[0]])
	for i in range(1, ctl.size() - 2):
		var p0: Vector2 = ctl[i - 1]
		var p1: Vector2 = ctl[i]
		var p2: Vector2 = ctl[i + 1]
		var p3: Vector2 = ctl[i + 2]
		# rotation de la tangente sur ce morceau (début, milieu, fin)
		var d0 := (p2 - p0) * 0.5
		var dm := (p3 + p2 * 5.0 - p1 * 5.0 - p0) / 8.0
		var d1 := (p3 - p1) * 0.5
		var turn := 0.0
		if d0.length() > 1e-6 and dm.length() > 1e-6:
			turn += absf(d0.angle_to(dm))
		if dm.length() > 1e-6 and d1.length() > 1e-6:
			turn += absf(dm.angle_to(d1))
		# nombre de pas : 1 sur une ligne droite, plus dans les virages (marge
		# de 25 % : la rotation d'une corde suit celle de la tangente)
		var n := maxi(1, int(ceil(rad_to_deg(turn) / (max_turn * 0.75))))
		# la rotation n'est pas régulière le long du morceau (plus forte près
		# d'un ancien coin) : si un pas tourne encore trop, on double le
		# nombre de pas (vérification jusqu'au raccord avec le morceau d'avant)
		# pas jamais plus courts que MIN_STEP_PX : sous ~1 px, les nombres du
		# moteur (précision ~0,016 px vers x = 150 000) rendent la direction
		# d'un segment imprécise
		var n_max := maxi(1, int(p1.distance_to(p2) / MIN_STEP_PX))
		n = mini(n, n_max)
		var pts := PackedVector2Array()
		for _try in 8:
			pts = PackedVector2Array()
			for k in range(1, n + 1):
				pts.append(_bspline(p0, p1, p2, p3, float(k) / n))
			if n >= n_max or _span_ok(out, pts, max_turn):
				break
			n = mini(n * 2, n_max)
		out.append_array(pts)
	# c. on retire les points alignés (lignes droites) : rien ne change
	return _drop_collinear(dedupe_px(out, 1.0))


## Vrai si les nouveaux points `pts`, ajoutés au bout de `out`, ne font
## tourner aucun coin de plus de max_turn (y compris le raccord).
static func _span_ok(out: PackedVector2Array, pts: PackedVector2Array, max_turn: float) -> bool:
	var a: Vector2 = out[out.size() - 2] if out.size() > 1 else Vector2.INF
	var b: Vector2 = out[out.size() - 1]
	for q in pts:
		if q.distance_to(b) < 1e-4:
			continue
		if a != Vector2.INF:
			if absf(rad_to_deg((b - a).angle_to(q - b))) > max_turn:
				return false
		a = b
		b = q
	return true


## Point de paramètre t (0..1) d'un morceau de B-spline cubique uniforme.
static func _bspline(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	var u := 1.0 - t
	return (p0 * (u * u * u) + p1 * (3.0 * t3 - 6.0 * t2 + 4.0) + p2 * (-3.0 * t3 + 3.0 * t2 + 3.0 * t + 1.0) + p3 * t3) / 6.0


## Retire les points où la ligne ne tourne quasiment pas (< 0,01°), tant que
## le segment obtenu reste plus court que DECIMATE_MAX_LEN, et les points
## à moins de 0,05 px du précédent.
static func _drop_collinear(c: PackedVector2Array) -> PackedVector2Array:
	if c.size() < 3:
		return c
	var out := PackedVector2Array([c[0]])
	for i in range(1, c.size() - 1):
		var prev: Vector2 = out[out.size() - 1]
		if c[i].distance_to(prev) < 0.05:
			continue
		var d1: Vector2 = c[i] - prev
		var d2: Vector2 = c[i + 1] - c[i]
		if d2.length() > 1e-6 and absf(rad_to_deg(d1.angle_to(d2))) < 0.01 and prev.distance_to(c[i + 1]) <= DECIMATE_MAX_LEN:
			continue
		out.append(c[i])
	out.append(c[c.size() - 1])
	return out
