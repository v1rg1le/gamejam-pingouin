"""[GLACE 1.77] Bordure « dessus de la glace » des plateformes : couche de neige.

Demandes de l'équipe (27/11) :
  1. changer la ligne bleue (cristaux de tile_ice_up_long1.png) pour un vrai
     « dessus de glace », léger, lisible à haute vitesse ;
  2. « l'impression d'une plus grosse couche de neige sur la glace, pour faire
     sens avec la traînée que Pinpouin laisse derrière lui quand il va vite ».
L'image d'origine n'est pas modifiée : on écrit une nouvelle image,
sprites/levels/tiles/ice_surface.png.

Géométrie : la bordure est un Line2D de 96 px de large, CENTRÉ sur la surface
du sol, posé seulement sur les morceaux de contour tournés vers le haut
(IceStyle.gd). L'image fait 24 lignes de haut : une ligne d'image = 4 px en jeu
(même gros pixel que le fond, affiché x4). La surface (là où glisse Pinpouin)
tombe entre les lignes 11 et 12 :
  lignes 9-10 : contour bleu au-dessus des bosses de neige
  lignes 10-11: bosses de neige (4 px, parfois 8 px : congères) au-dessus de
                la surface, ou contour bleu entre les bosses
  lignes 12-18: la couche de neige (blanc, ombrée vers le bas), 20 à 28 px
                d'épaisseur selon l'endroit (bas de la couche irrégulier)
  ensuite     : limite neige / glace un peu plus sombre, puis glace claire
                qui s'efface
Les bosses ne dépassent que de 4 à 8 px : le pingouin glisse « dans » la neige
fraîche sans avoir l'air de s'enfoncer dans le sol (bug corrigé en 1.9).
Le motif fait 128 pixels d'image de long (512 px en jeu) : on ne voit pas la
répétition à vitesse normale.

Usage (depuis la racine du dépôt) : python3 tools/art/ice_style.py
"""
import random
from PIL import Image

W, H = 128, 24
SURF = 12   # 1re ligne sous la surface
rng = random.Random(1777)

EDGE = (76, 128, 186)        # contour (lisible sur le fond clair)
SNOW_TOP = (248, 253, 255)   # dessus de la neige, éclairé
SNOW = (235, 245, 254)       # neige
SNOW_SHADE = (214, 231, 249) # neige à l'ombre, vers le bas de la couche
SNOW_ICE = (170, 208, 238)   # limite neige / glace
BAND = (206, 238, 252)       # glace claire sous la neige
BAND_ALPHA = [0.55, 0.22]

im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
px = im.load()


def runs(total, wmin, wmax):
    """Découpe la largeur en morceaux de wmin..wmax pixels."""
    out, x = [], 0
    while x < total:
        w = min(rng.randint(wmin, wmax), total - x)
        out.append((x, w))
        x += w
    return out


# bosses de neige au-dessus de la surface : un morceau sur deux environ
# (hauteur 1 ligne, parfois 2 = congère), jamais au bord de l'image (raccord
# propre quand le motif se répète)
bump = [0] * W
for x0, w in runs(W, 3, 10):
    if rng.random() < 0.5 and x0 > 0 and x0 + w < W:
        hgt = 2 if (rng.random() < 0.3 and w >= 5) else 1
        for x in range(x0, x0 + w):
            # une congère est plus haute au milieu qu'aux bords
            edge_x = x in (x0, x0 + w - 1)
            bump[x] = 1 if (hgt == 2 and edge_x) else hgt
# épaisseur de la couche : 5 à 7 lignes sous la surface, par morceaux
depth = [6] * W
for x0, w in runs(W, 4, 12):
    d = rng.choice([5, 6, 6, 7])
    for x in range(x0, x0 + w):
        depth[x] = d

for x in range(W):
    b = bump[x]
    # contour au-dessus de la neige, puis bosses
    px[x, SURF - 1 - b] = EDGE + (255,)
    for k in range(b):
        px[x, SURF - 1 - k] = (SNOW_TOP if k == b - 1 else SNOW) + (255,)
    # couche de neige sous la surface
    d = depth[x]
    for k in range(d):
        if k == 0 and b == 0:
            c = SNOW_TOP
        elif k >= d - 1:
            c = SNOW_SHADE
        else:
            c = SNOW
        px[x, SURF + k] = c + (255,)
    # limite neige / glace juste sous la couche, puis glace claire
    y = SURF + d
    px[x, y] = SNOW_ICE + (230,)
    for k, a in enumerate(BAND_ALPHA):
        if y + 1 + k < H:
            px[x, y + 1 + k] = BAND + (int(255 * a),)

im.save('sprites/levels/tiles/ice_surface.png')
print('écrit sprites/levels/tiles/ice_surface.png', im.size)
