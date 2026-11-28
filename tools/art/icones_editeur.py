# [ICÔNES 1.82] Icônes du créateur de niveau, en pixel art, dans la palette
# du jeu (mêmes couleurs que tools/art/oeufs_gruyere.py et les panneaux de
# L'Œuf). Chaque icône est dessinée sur une grille de 16 x 16 pixels, reçoit
# un contour sombre automatique (comme les panneaux), puis est agrandie x2
# (32 x 32, sans lissage : taille d'affichage exacte dans les barres, pas de flou) dans sprites/ui/editor/<nom>.png.
# Les vignettes des formes de terrain et des gros blocs (palette de l'outil
# Objets, éléments à venir) sont dessinées de la même façon sur 24 x 24 (x2).
# Usage (racine du dépôt) : python3 tools/art/icones_editeur.py [--planche sortie.png]
# Aucun visuel existant n'est modifié : ce script n'écrit que de nouveaux fichiers.
from PIL import Image, ImageDraw
import os, sys

# --- Palette (reprise des œufs du Gruyère et des panneaux) -------------------
INK = (0x17, 0x19, 0x2f, 255)     # contour sombre
WHITE = (0xf6, 0xfb, 0xff, 255)
SNOW = (0xdf, 0xf3, 0xfe, 255)
ICE = (0xb1, 0xdc, 0xf4, 255)     # glace claire (remplissage des sols)
MID = (0x66, 0xb4, 0xd2, 255)
DEEP = (0x45, 0x78, 0xb3, 255)
YEL = (0xff, 0xd2, 0x3f, 255)     # jaune des drapeaux / de la sélection
ORANGE = (0xf0, 0x9a, 0x3a, 255)
RED = (0xe8, 0x4a, 0x3a, 255)
GREEN = (0x5c, 0xcf, 0x6a, 255)
PINK = (0xf2, 0x9b, 0xb8, 255)
GREY = (0x9e, 0xa8, 0xb8, 255)
VIOLET = (0xa8, 0x7c, 0xf0, 255)
T = (0, 0, 0, 0)

OUT_DIR = "sprites/ui/editor"


def new(n=16):
    im = Image.new("RGBA", (n, n), T)
    return im, ImageDraw.Draw(im)


def outline(im, col=INK):
    """Contour d'un pixel autour de tout ce qui est dessiné (dehors)."""
    w, h = im.size
    src = im.copy().load()
    px = im.load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    X, Y = x + dx, y + dy
                    if 0 <= X < w and 0 <= Y < h and src[X, Y][3] > 0 and src[X, Y] != INK:
                        px[x, y] = col
                        break
    return im


# --- Icônes des boutons (16 x 16) -------------------------------------------
def i_retour():
    im, d = new()
    d.polygon([(2, 8), (7, 3), (7, 6), (13, 6), (13, 10), (7, 10), (7, 13)], fill=WHITE)
    return im


def i_annuler():
    im, d = new()
    d.arc([3, 4, 13, 14], 200, 450, fill=WHITE, width=2)   # demi-cercle
    d.polygon([(1, 6), (6, 2), (6, 9)], fill=WHITE)          # pointe à gauche
    return im


def i_refaire():
    return i_annuler().transpose(Image.FLIP_LEFT_RIGHT)


def i_effacer():
    # poubelle
    im, d = new()
    d.rectangle([3, 4, 12, 5], fill=WHITE)
    d.rectangle([6, 2, 9, 3], fill=WHITE)
    d.rectangle([4, 6, 11, 14], fill=ICE)
    for x in (6, 9):
        d.line([(x, 8), (x, 12)], fill=DEEP)
    return im


def i_grappins():
    # bloc de grappin (ellipse grise) avec un éclair jaune « auto »
    im, d = new()
    d.ellipse([1, 6, 12, 12], fill=GREY)
    d.line([(3, 8), (9, 8)], fill=WHITE)
    d.polygon([(12, 1), (9, 6), (11, 6), (10, 10), (14, 4), (12, 4)], fill=YEL)
    return im


def i_simple():
    # un gros bouton rond (mode Simple : gros boutons)
    im, d = new()
    d.ellipse([2, 2, 13, 13], fill=GREEN)
    d.ellipse([5, 4, 8, 7], fill=WHITE)
    return im


def i_expert():
    # trois curseurs de réglage (mode Expert : tous les réglages)
    im, d = new()
    for i, (y, k) in enumerate(((3, 10), (8, 4), (13, 8))):
        d.line([(1, y), (14, y)], fill=SNOW)
        d.rectangle([k - 1, y - 2, k + 1, y + 2], fill=YEL)
    return im


def i_aimant():
    im, d = new()
    d.arc([2, 2, 13, 13], 180, 360, fill=RED, width=4)
    d.rectangle([2, 7, 5, 11], fill=RED)
    d.rectangle([10, 7, 13, 11], fill=RED)
    d.rectangle([2, 11, 5, 13], fill=WHITE)
    d.rectangle([10, 11, 13, 13], fill=WHITE)
    return im


def i_survol():
    # œil
    im, d = new()
    d.polygon([(1, 8), (4, 4), (8, 3), (12, 4), (15, 8), (12, 12), (8, 13), (4, 12)], fill=WHITE)
    d.ellipse([5, 5, 10, 10], fill=MID)
    d.ellipse([7, 7, 8, 8], fill=INK)
    return im


def i_zoom(plus):
    im, d = new()
    d.ellipse([1, 1, 10, 10], fill=ICE)
    d.line([(9, 9), (14, 14)], fill=WHITE, width=3)
    d.line([(3, 5), (8, 5)], fill=INK, width=2)
    if plus:
        d.line([(5, 3), (5, 8)], fill=INK, width=2)
    return im


def i_tout_voir():
    # quatre coins de cadrage + une petite colline
    im, d = new()
    for (x, y, sx, sy) in ((1, 1, 1, 1), (14, 1, -1, 1), (1, 14, 1, -1), (14, 14, -1, -1)):
        d.line([(x, y), (x + 3 * sx, y)], fill=YEL, width=2)
        d.line([(x, y), (x, y + 3 * sy)], fill=YEL, width=2)
    d.polygon([(4, 11), (7, 7), (9, 9), (11, 8), (12, 11)], fill=ICE)
    return im


def i_dessiner():
    # crayon en diagonale + trait de sol
    im, d = new()
    d.line([(1, 14), (8, 12), (14, 13)], fill=MID, width=2)
    d.polygon([(4, 10), (12, 2), (14, 4), (6, 12)], fill=YEL)
    d.polygon([(12, 2), (13, 1), (15, 3), (14, 4)], fill=PINK)
    d.polygon([(4, 10), (6, 12), (3, 13)], fill=SNOW)
    return im


def i_objets():
    # un œuf et un petit bloc de grappin (la palette d'objets)
    im, d = new()
    d.ellipse([1, 2, 9, 13], fill=ICE)
    d.point([(3, 5), (5, 8), (4, 10)], fill=WHITE)
    d.ellipse([8, 9, 15, 14], fill=GREY)
    return im


def i_selection():
    # flèche de curseur
    im, d = new()
    d.polygon([(3, 1), (3, 13), (6, 10), (9, 15), (11, 14), (8, 9), (12, 9)], fill=WHITE)
    return im


def i_gomme():
    im, d = new()
    d.polygon([(2, 10), (9, 3), (14, 8), (7, 15)], fill=PINK)
    d.polygon([(2, 10), (5, 7), (10, 12), (7, 15)], fill=WHITE)
    return im


def i_deplacer():
    # croix de quatre flèches
    im, d = new()
    # (pointes étroites, sinon les quatre flèches se touchent et forment un losange)
    d.rectangle([7, 2, 8, 13], fill=WHITE)
    d.rectangle([2, 7, 13, 8], fill=WHITE)
    for p in ([(7, 0), (8, 0), (10, 3), (5, 3)], [(7, 15), (8, 15), (10, 12), (5, 12)],
              [(0, 7), (0, 8), (3, 10), (3, 5)], [(15, 7), (15, 8), (12, 10), (12, 5)]):
        d.polygon(p, fill=WHITE)
    return im


def i_valider():
    # médaille d'or avec une coche
    im, d = new()
    d.polygon([(4, 0), (7, 5), (5, 6), (2, 1)], fill=RED)
    d.polygon([(11, 0), (8, 5), (10, 6), (13, 1)], fill=DEEP)
    d.ellipse([2, 4, 13, 15], fill=YEL)
    d.line([(5, 9), (7, 12), (11, 7)], fill=WHITE, width=2)
    return im


def i_dici():
    # triangle « lecture » + repère (point de départ choisi)
    im, d = new()
    d.polygon([(5, 2), (14, 8), (5, 14)], fill=GREEN)
    d.ellipse([0, 10, 5, 15], fill=YEL)
    return im


def i_tester():
    im, d = new()
    d.polygon([(3, 1), (14, 8), (3, 15)], fill=GREEN)
    d.line([(5, 4), (5, 12)], fill=WHITE)
    return im


def i_nom():
    # crayon seul (renommer)
    im, d = new()
    d.polygon([(2, 11), (11, 2), (14, 5), (5, 14)], fill=YEL)
    d.polygon([(11, 2), (12, 1), (15, 4), (14, 5)], fill=PINK)
    d.polygon([(2, 11), (5, 14), (1, 15)], fill=SNOW)
    return im


ICONS = {
    "retour": i_retour, "annuler": i_annuler, "refaire": i_refaire, "effacer": i_effacer,
    "grappins": i_grappins, "simple": i_simple, "expert": i_expert, "aimant": i_aimant,
    "survol": i_survol, "zoom_moins": lambda: i_zoom(False), "zoom_plus": lambda: i_zoom(True),
    "tout_voir": i_tout_voir, "dessiner": i_dessiner, "objets": i_objets,
    "selection": i_selection, "gomme": i_gomme, "deplacer": i_deplacer,
    "valider": i_valider, "dici": i_dici, "tester": i_tester, "nom": i_nom,
}


# --- [ICÔNES PARTOUT 1.87] Plus aucun texte sur les boutons du créateur --------
# Demande de l'équipe (28/11) : « enlever le texte des boutons dans tout cet
# éditeur, juste une bulle info au survol ». Choix : une icône pour CHAQUE
# bouton, même les choix (formes de bloc, tailles, largeurs…).

def i_dupliquer():
    im, d = new()
    d.rectangle([1, 1, 9, 9], fill=ICE)
    d.rectangle([6, 6, 14, 14], fill=WHITE)
    d.line([(10, 8), (10, 12)], fill=GREEN, width=2)
    d.line([(8, 10), (12, 10)], fill=GREEN, width=2)
    return im


def i_supprimer():
    im, d = new()
    d.rectangle([2, 4, 13, 13], fill=ICE)
    d.line([(3, 3), (13, 13)], fill=RED, width=3)
    d.line([(13, 3), (3, 13)], fill=RED, width=3)
    return im


def i_taille(k):
    # petit / moyen / grand : un carré de glace de 3 tailles, posé au sol
    im, d = new()
    s = (4, 8, 13)[k]
    d.rectangle([8 - s // 2, 14 - s, 8 - s // 2 + s - 1, 14], fill=ICE)
    d.line([(8 - s // 2, 14 - s), (8 - s // 2 + s - 1, 14 - s)], fill=SNOW, width=2)
    d.line([(0, 15), (15, 15)], fill=MID)
    return im


def i_bloc(kind):
    im, d = new()
    if kind == "rect":
        d.rounded_rectangle([1, 3, 14, 13], radius=2, fill=DEEP)
    elif kind == "oeuf":
        d.ellipse([3, 1, 12, 14], fill=DEEP)
    elif kind == "rond":
        d.ellipse([1, 1, 14, 14], fill=DEEP)
    elif kind == "montagne":
        d.polygon([(0, 14), (3, 7), (6, 3), (9, 2), (12, 5), (15, 14)], fill=DEEP)
    else:   # forme libre : contour en pointillés + crayon
        for x, y in ((2, 4), (5, 2), (9, 3), (12, 6), (13, 10), (10, 13), (5, 13), (2, 10)):
            d.rectangle([x, y, x + 1, y + 1], fill=DEEP)
        d.polygon([(8, 9), (13, 4), (15, 6), (10, 11)], fill=YEL)
    return im


def i_tracer():
    # galerie claire qui serpente dans la roche, crayon au bout
    im, d = new()
    d.rectangle([0, 1, 15, 14], fill=DEEP)
    d.line([(0, 9), (4, 6), (8, 9), (11, 7)], fill=SNOW, width=3)
    d.polygon([(10, 7), (14, 2), (16, 4), (12, 9)], fill=YEL)
    return im


def i_pioche():
    im, d = new()
    d.line([(4, 14), (11, 5)], fill=ORANGE, width=2)
    d.arc([2, 0, 15, 10], 200, 340, fill=GREY, width=2)
    return im


def i_truelle():
    im, d = new()
    d.polygon([(2, 13), (8, 5), (12, 9)], fill=GREY)
    d.line([(10, 7), (14, 3)], fill=ORANGE, width=2)
    d.rectangle([1, 14, 8, 15], fill=DEEP)
    return im


def i_galerie(k):
    # étroite / normale / large : bande claire de 3 épaisseurs dans la roche
    im, d = new()
    d.rectangle([0, 1, 15, 14], fill=DEEP)
    h = (2, 4, 7)[k]
    d.rectangle([0, 8 - h // 2 - h % 2, 15, 8 + h // 2], fill=SNOW)
    return im


def i_fini():
    # main ouverte : on arrête de tailler (le doigt déplace le bloc)
    im, d = new()
    d.rectangle([4, 7, 12, 14], fill=PINK)
    for x in (4, 6, 8, 10):
        d.rectangle([x, 2 + (x % 4), x + 1, 7], fill=PINK)
    d.polygon([(12, 9), (15, 6), (15, 8), (12, 12)], fill=PINK)
    return im


def i_reboucher():
    # bloc plein + flèche ronde (tout revient comme au début)
    im, d = new()
    d.rectangle([1, 5, 11, 14], fill=DEEP)
    d.arc([6, 0, 15, 9], 180, 450, fill=YEL, width=2)
    d.polygon([(5, 4), (9, 4), (7, 7)], fill=YEL)
    return im


def i_de():
    im, d = new()
    d.rounded_rectangle([2, 2, 13, 13], radius=2, fill=WHITE)
    for x, y in ((5, 5), (10, 10), (7, 7), (5, 10), (10, 5)):
        d.rectangle([x - 1 + (x > 7), y - 1 + (y > 7), x + (x > 7), y + (y > 7)], fill=INK)
    return im


def i_detacher():
    # prise de grappin qui sort d'une falaise (flèche)
    im, d = new()
    d.polygon([(0, 15), (2, 4), (5, 2), (6, 15)], fill=DEEP)
    d.ellipse([7, 3, 15, 8], fill=GREY)
    d.polygon([(8, 10), (12, 10), (12, 8), (15, 12), (12, 15), (12, 13), (8, 13)], fill=YEL)
    return im


def i_serie():
    # escalier de plateformes alternées
    im, d = new()
    for k, (x, y) in enumerate(((1, 13), (8, 9), (1, 5), (8, 1))):
        d.rectangle([x, y, x + 6, y + 1], fill=SNOW)
        d.point([(x + 2, y + 2), (x + 4, y + 2)], fill=ICE)
    return im


def i_remplir():
    # bloc qui s'étire aux quatre coins (tout le niveau)
    im, d = new()
    d.rectangle([4, 4, 11, 11], fill=DEEP)
    for (x, y, dx, dy) in ((0, 0, 1, 1), (15, 0, -1, 1), (0, 15, 1, -1), (15, 15, -1, -1)):
        d.line([(x, y), (x + 3 * dx, y + 3 * dy)], fill=YEL, width=2)
        d.line([(x, y), (x + 3 * dx, y)], fill=YEL)
        d.line([(x, y), (x, y + 3 * dy)], fill=YEL)
    return im


def i_ok():
    im, d = new()
    d.line([(2, 8), (6, 12), (14, 3)], fill=GREEN, width=3)
    return im


def i_non():
    im, d = new()
    d.line([(3, 3), (12, 12)], fill=RED, width=3)
    d.line([(12, 3), (3, 12)], fill=RED, width=3)
    return im


def i_accrochable():
    # plafond à stalactites + crochet
    im, d = new()
    d.rectangle([0, 1, 15, 4], fill=ICE)
    for x in (2, 7, 12):
        d.polygon([(x - 1, 5), (x + 2, 5), (x, 8)], fill=ICE)
    d.line([(6, 14), (9, 9)], fill=GREY, width=2)
    d.arc([7, 8, 13, 14], 270, 90, fill=GREY, width=2)
    return im


def i_en_l_air():
    # flèches de boost au-dessus d'un trou
    im, d = new()
    for x in (2, 7):
        d.polygon([(x, 2), (x + 4, 6), (x, 10), (x + 2, 10), (x + 6, 6), (x + 2, 2)], fill=YEL)
    d.rectangle([0, 13, 3, 15], fill=ICE)
    d.rectangle([12, 13, 15, 15], fill=ICE)
    return im


def i_prise_auto():
    # falaise + prise + éclair « auto »
    im, d = new()
    d.polygon([(0, 15), (2, 6), (5, 3), (8, 15)], fill=DEEP)
    d.ellipse([7, 4, 13, 8], fill=GREY)
    d.polygon([(13, 9), (11, 12), (12, 12), (11, 15), (15, 11), (13, 11)], fill=YEL)
    return im


def i_onglet(k):
    im, d = new()
    if k == 0:   # objets : drapeau
        d.rectangle([4, 1, 5, 15], fill=DEEP)
        d.polygon([(6, 1), (14, 4), (6, 7)], fill=YEL)
    elif k == 1:   # terrain : tremplin
        d.polygon([(0, 15), (0, 13), (8, 12), (13, 7), (15, 4), (15, 15)], fill=ICE)
        d.line([(0, 13), (8, 12), (13, 7), (15, 4)], fill=SNOW, width=2)
    elif k == 2:   # décor : sapin enneigé
        d.polygon([(8, 1), (13, 8), (10, 8), (14, 13), (2, 13), (6, 8), (3, 8)], fill=GREEN)
        d.rectangle([7, 13, 8, 15], fill=ORANGE)
        d.point([(8, 1), (7, 4), (10, 9)], fill=WHITE)
    else:   # gros blocs : caverne
        d.rectangle([0, 1, 15, 14], fill=DEEP)
        d.rectangle([2, 4, 13, 6], fill=T)
        d.rectangle([2, 9, 13, 11], fill=T)
    return im


def i_aide():
    # [UX 1.88] bulle de dialogue avec un point d'interrogation (visite)
    im, d = new()
    d.rounded_rectangle([1, 1, 14, 11], radius=3, fill=WHITE)
    d.polygon([(4, 11), (8, 11), (4, 15)], fill=WHITE)
    d.arc([5, 2, 10, 7], 180, 30, fill=DEEP, width=2)
    d.line([(8, 6), (7, 8)], fill=DEEP, width=2)
    d.point([(7, 10)], fill=DEEP)
    return im


def i_etapes():
    # [UX 1.88] liste cochée (étapes du niveau)
    im, d = new()
    for k, y in enumerate((2, 7, 12)):
        d.rectangle([1, y, 3, y + 2], fill=GREEN if k < 2 else WHITE)
        d.line([(6, y + 1), (14, y + 1)], fill=WHITE, width=2)
    return im


ICONS.update({"aide": i_aide, "etapes": i_etapes})


ICONS.update({
    "dupliquer": i_dupliquer, "supprimer": i_supprimer,
    "taille_petit": lambda: i_taille(0), "taille_moyen": lambda: i_taille(1), "taille_grand": lambda: i_taille(2),
    "bloc_rect": lambda: i_bloc("rect"), "bloc_oeuf": lambda: i_bloc("oeuf"), "bloc_rond": lambda: i_bloc("rond"),
    "bloc_montagne": lambda: i_bloc("montagne"), "bloc_libre": lambda: i_bloc("libre"),
    "tracer": i_tracer, "pioche": i_pioche, "truelle": i_truelle,
    "galerie_etroite": lambda: i_galerie(0), "galerie_normale": lambda: i_galerie(1), "galerie_large": lambda: i_galerie(2),
    "fini": i_fini, "reboucher": i_reboucher, "de": i_de, "detacher": i_detacher, "serie": i_serie,
    "remplir": i_remplir, "ok": i_ok, "non": i_non, "accrochable": i_accrochable, "en_l_air": i_en_l_air,
    "prise_auto": i_prise_auto,
    "onglet_objets": lambda: i_onglet(0), "onglet_terrain": lambda: i_onglet(1),
    "onglet_decor": lambda: i_onglet(2), "onglet_gros": lambda: i_onglet(3),
})


# --- [RÈGLES 1.90] Fenêtre « Niveau » : type, ciel, musique ; pont magique ------
def i_niveau():
    # petit paysage (montagne + soleil) dans un cadre : les réglages du niveau
    im, d = new()
    d.rectangle([1, 2, 14, 13], fill=MID)
    d.ellipse([9, 3, 12, 6], fill=YEL)
    d.polygon([(1, 13), (6, 6), (9, 10), (11, 8), (14, 12), (14, 13)], fill=SNOW)
    return im


def i_type(k):
    im, d = new()
    if k == 0:   # course : drapeau à damier
        d.rectangle([2, 1, 3, 15], fill=GREY)
        for y in range(2, 9, 2):
            for x in range(4, 14, 2):
                d.rectangle([x, y, x, y], fill=WHITE if (x + y) % 4 == 0 else INK)
                d.rectangle([x + 1, y, x + 1, y], fill=INK if (x + y) % 4 == 0 else WHITE)
                d.rectangle([x, y + 1, x, y + 1], fill=INK if (x + y) % 4 == 0 else WHITE)
                d.rectangle([x + 1, y + 1, x + 1, y + 1], fill=WHITE if (x + y) % 4 == 0 else INK)
    elif k == 1:   # glisse libre : vague de neige sans fin
        d.line([(0, 10), (3, 7), (6, 9), (9, 6), (12, 8), (15, 5)], fill=SNOW, width=3)
        d.polygon([(0, 15), (0, 12), (3, 9), (6, 11), (9, 8), (12, 10), (15, 7), (15, 15)], fill=ICE)
    else:   # défi figures : étoile qui tourne
        d.polygon([(8, 1), (10, 6), (15, 6), (11, 9), (13, 14), (8, 11), (3, 14), (5, 9), (1, 6), (6, 6)], fill=YEL)
        d.arc([0, 0, 15, 15], 200, 320, fill=WHITE, width=1)
    return im


def i_ciel(k):
    im, d = new()
    cols = {"jour": (0x66, 0xa8, 0xe0, 255), "aube": (0xee, 0xb0, 0xbc, 255), "couchant": (0xf2, 0x84, 0x52, 255),
            "nuit": (0x1a, 0x22, 0x55, 255)}
    if k == "cycle":
        # quatre quarts : le temps passe
        d.pieslice([1, 1, 14, 14], 180, 270, fill=cols["aube"])
        d.pieslice([1, 1, 14, 14], 270, 360, fill=cols["jour"])
        d.pieslice([1, 1, 14, 14], 0, 90, fill=cols["couchant"])
        d.pieslice([1, 1, 14, 14], 90, 180, fill=cols["nuit"])
        d.line([(8, 8), (8, 3)], fill=WHITE)
        d.line([(8, 8), (11, 9)], fill=WHITE)
        return im
    d.rectangle([1, 1, 14, 14], fill=cols[k])
    if k == "nuit":
        d.ellipse([8, 3, 12, 7], fill=WHITE)
        d.ellipse([9, 2, 12, 6], fill=cols["nuit"])
        d.point([(3, 4), (5, 9), (11, 11), (4, 12)], fill=WHITE)
    else:
        y = {"jour": 3, "aube": 9, "couchant": 9}[k]
        d.ellipse([5, y, 10, y + 5], fill=YEL if k != "couchant" else (0xff, 0xe0, 0x80, 255))
    d.rectangle([1, 12, 14, 14], fill=SNOW)
    return im


def i_musique(k):
    im, d = new()
    col = YEL if k == 0 else PINK if k == 1 else GREY
    d.line([(6, 3), (6, 12)], fill=col, width=2)
    d.line([(12, 1), (12, 10)], fill=col, width=2)
    d.polygon([(6, 3), (13, 1), (13, 3), (6, 5)], fill=col)
    d.ellipse([2, 10, 6, 14], fill=col)
    d.ellipse([8, 8, 12, 12], fill=col)
    if k == 2:
        d.line([(1, 14), (14, 1)], fill=RED, width=2)
    return im


ICONS.update({
    "niveau": i_niveau,
    "type_course": lambda: i_type(0), "type_libre": lambda: i_type(1), "type_figures": lambda: i_type(2),
    "ciel_jour": lambda: i_ciel("jour"), "ciel_aube": lambda: i_ciel("aube"), "ciel_couchant": lambda: i_ciel("couchant"),
    "ciel_nuit": lambda: i_ciel("nuit"), "ciel_cycle": lambda: i_ciel("cycle"),
    "musique_glisse": lambda: i_musique(0), "musique_espoir": lambda: i_musique(1), "musique_aucune": lambda: i_musique(2),
})


# --- Vignettes de la palette (24 x 24) ----------------------------------------
# Glace + neige du jeu : remplissage ICE, dessus SNOW, contour sombre.
def ground(d, pts, bottom=22):
    """Sol : polygone de glace sous la ligne `pts`, neige sur le dessus."""
    poly = list(pts) + [(pts[-1][0], bottom), (pts[0][0], bottom)]
    d.polygon(poly, fill=ICE)
    d.line(pts, fill=SNOW, width=2)


def v_new():
    return new(24)


def v_draw():
    im, d = v_new()
    ground(d, [(1, 14), (6, 12), (11, 15), (17, 11), (22, 13)])
    d.polygon([(10, 9), (18, 1), (21, 4), (13, 12)], fill=YEL)
    return im


def v_ramp():
    im, d = v_new()
    ground(d, [(1, 19), (8, 19), (14, 16), (19, 11), (22, 8)])
    return im


def v_halfpipe():
    im, d = v_new()
    pts = [(1, 4)] + [(x, int(19 - 15 * (1 - ((x - 11.5) / 10.5) ** 2) ** 0.5 * 0 + 0)) for x in []]
    # U : deux murs arrondis et un fond plat
    pts = [(1, 3), (2, 10), (4, 15), (7, 18), (11, 19), (13, 19), (17, 18), (20, 15), (22, 10), (23, 3)]
    ground(d, pts)
    return im


def v_bowl():
    im, d = v_new()
    pts = [(1, 9), (4, 13), (8, 16), (12, 17), (16, 16), (20, 13), (23, 9)]
    ground(d, pts)
    return im


def v_slope():
    # rampe à boosts : pente + chevrons
    im, d = v_new()
    ground(d, [(1, 20), (23, 6)])
    for k in range(3):
        x = 6 + k * 5
        y = int(20 - (x - 1) * 14 / 22) - 4
        d.polygon([(x, y - 2), (x + 3, y), (x, y + 2)], fill=RED)
    return im


def v_bend():
    # virage en pipe (quart de cercle)
    im, d = v_new()
    d.pieslice([-12, -12, 22, 22], 0, 90, fill=ICE)
    d.pieslice([-4, -4, 14, 14], 0, 90, fill=T)
    d.arc([-12, -12, 22, 22], 0, 90, fill=SNOW, width=2)
    return im


def v_upipe():
    im, d = v_new()
    d.pieslice([2, -8, 22, 20], 0, 180, fill=ICE)
    d.pieslice([7, -3, 17, 15], 0, 180, fill=T)
    d.arc([2, -8, 22, 20], 0, 180, fill=SNOW, width=2)
    return im


def v_ceiling():
    im, d = v_new()
    d.rectangle([1, 2, 22, 6], fill=ICE)
    for x in range(3, 22, 4):
        d.polygon([(x - 1, 7), (x + 2, 7), (x + 0.5, 11)], fill=SNOW)
    ground(d, [(1, 19), (22, 19)])
    return im


def v_floating():
    im, d = v_new()
    d.polygon([(3, 10), (20, 10), (17, 15), (6, 15)], fill=ICE)
    d.line([(3, 10), (20, 10)], fill=SNOW, width=2)
    return im


def v_wall():
    im, d = v_new()
    d.rectangle([12, 2, 18, 22], fill=ICE)
    d.line([(12, 2), (12, 22)], fill=SNOW, width=2)
    ground(d, [(1, 20), (11, 20)])
    return im


def v_pillar():
    im, d = v_new()
    d.rectangle([8, 6, 15, 22], fill=ICE)
    d.rectangle([7, 5, 16, 6], fill=SNOW)
    return im


def v_balcony():
    im, d = v_new()
    d.rectangle([0, 2, 6, 22], fill=DEEP)
    d.polygon([(6, 9), (21, 9), (20, 12), (6, 14)], fill=ICE)
    d.line([(6, 9), (21, 9)], fill=SNOW, width=2)
    for x, l in ((9, 4), (13, 3), (17, 2)):
        d.ellipse([x - 1, 12, x + 1, 12 + l], fill=ICE)
    return im


def v_stal():
    im, d = v_new()
    d.polygon([(4, 8), (20, 8), (12, 21)], fill=ICE)
    d.line([(4, 8), (20, 8)], fill=SNOW, width=2)
    return im


def v_cliff():
    im, d = v_new()
    d.polygon([(2, 22), (6, 6), (10, 3), (15, 4), (19, 9), (22, 22)], fill=GREY)
    d.polygon([(6, 6), (10, 3), (15, 4), (12, 7), (8, 8)], fill=SNOW)
    return im


def v_cave():
    im, d = v_new()
    d.rectangle([1, 2, 22, 21], fill=DEEP)
    d.rectangle([3, 6, 20, 9], fill=T)
    d.rectangle([3, 14, 20, 17], fill=T)
    d.line([(3, 9), (20, 9)], fill=SNOW)
    d.line([(3, 17), (20, 17)], fill=SNOW)
    return im


def v_carved():
    # [CAVERNE 1.85] bloc de glace creusé à la main : galerie sinueuse + pioche
    im, d = v_new()
    d.rectangle([1, 4, 22, 21], fill=DEEP)
    d.line([(1, 9), (6, 13), (11, 10), (16, 15), (22, 12)], fill=T, width=4)
    d.line([(14, 1), (20, 7)], fill=ORANGE, width=2)
    d.arc([10, 0, 22, 8], 200, 340, fill=GREY, width=2)
    return im


def v_void():
    im, d = v_new()
    ground(d, [(1, 10), (6, 11)], bottom=22)
    ground(d, [(17, 15), (22, 14)], bottom=22)
    for y in (5, 11):
        d.ellipse([10, y, 13, y + 4], fill=ICE)
    return im


def v_pillars():
    im, d = v_new()
    for x in (2, 10, 18):
        d.rectangle([x, 9 + (x % 3), x + 3, 22], fill=ICE)
        d.line([(x, 9 + (x % 3)), (x + 3, 9 + (x % 3))], fill=SNOW)
    return im


def v_bigegg():
    im, d = v_new()
    d.ellipse([4, 1, 19, 22], fill=ICE)
    d.line([(8, 6), (11, 10), (9, 14)], fill=WHITE)
    return im


def v_endless():
    im, d = v_new()
    ground(d, [(1, 12), (7, 14)], bottom=22)
    ground(d, [(11, 15), (16, 13)], bottom=22)
    d.polygon([(19, 10), (23, 13), (19, 16)], fill=YEL)
    return im


def v_camera():
    # zone de caméra : cadre violet en pointillés + petite caméra
    im, d = v_new()
    for x in range(1, 23, 3):
        d.point([(x, 1), (x, 22)], fill=VIOLET)
        d.point([(x + 1, 1), (x + 1, 22)], fill=VIOLET)
    for y in range(1, 23, 3):
        d.point([(1, y), (22, y)], fill=VIOLET)
        d.point([(1, y + 1), (22, y + 1)], fill=VIOLET)
    d.rectangle([6, 9, 15, 15], fill=GREY)
    d.polygon([(15, 11), (19, 9), (19, 15), (15, 13)], fill=GREY)
    d.ellipse([9, 10, 12, 13], fill=INK)
    return im


def v_checkpoint():
    im, d = v_new()
    d.rectangle([7, 3, 8, 21], fill=DEEP)
    d.polygon([(9, 3), (19, 6), (9, 10)], fill=YEL)
    return im


def v_hook():
    im, d = v_new()
    d.ellipse([2, 8, 21, 16], fill=GREY)
    d.line([(5, 11), (14, 11)], fill=WHITE)
    return im



def v_bridge():
    # [RÈGLES 1.90] pont magique : arc-en-ciel au-dessus d'un trou, étoile
    im, d = v_new()
    ground(d, [(0, 17), (5, 17)], bottom=22)
    ground(d, [(18, 17), (23, 17)], bottom=22)
    for k, col in enumerate((RED, ORANGE, YEL, GREEN, MID)):
        d.arc([3 + k, 5 + k, 20 - k, 26 - k], 180, 360, fill=col, width=1)
    d.polygon([(11, 1), (12, 3), (14, 3), (12, 4), (13, 6), (11, 5), (9, 6), (10, 4), (8, 3), (10, 3)], fill=WHITE)
    return im


THUMBS = {
    "draw": v_draw, "ramp": v_ramp, "halfpipe": v_halfpipe, "bowl": v_bowl, "slope": v_slope,
    "bend": v_bend, "upipe": v_upipe, "ceiling": v_ceiling, "floating": v_floating, "wall": v_wall,
    "pillar": v_pillar, "balcony": v_balcony, "stal": v_stal, "cliff": v_cliff,
    "cave": v_cave, "carved": v_carved, "void": v_void, "pillars": v_pillars, "bigegg": v_bigegg, "endless": v_endless,
    "camera": v_camera, "checkpoint": v_checkpoint, "hook": v_hook,
    "bridge": v_bridge,   # [RÈGLES 1.90]
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    made = []
    for name, fn in ICONS.items():
        im = outline(fn()).resize((32, 32), Image.NEAREST)
        im.save(os.path.join(OUT_DIR, name + ".png"))
        made.append(im)
    thumbs = []
    for name, fn in THUMBS.items():
        im = outline(fn()).resize((48, 48), Image.NEAREST)
        im.save(os.path.join(OUT_DIR, "palette_" + name + ".png"))
        thumbs.append(im)
    if "--planche" in sys.argv:
        out = sys.argv[sys.argv.index("--planche") + 1]
        all_ims = made + thumbs
        cols = 11
        rows = (len(all_ims) + cols - 1) // cols
        sheet = Image.new("RGBA", (cols * 64, rows * 64), (0x1b, 0x27, 0x45, 255))
        for k, im in enumerate(all_ims):
            sheet.paste(im, ((k % cols) * 64 + (64 - im.width) // 2, (k // cols) * 64 + (64 - im.height) // 2), im)
        sheet = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
        sheet.save(out)
    print(len(made), "icônes,", len(thumbs), "vignettes ->", OUT_DIR)


if __name__ == "__main__":
    main()
