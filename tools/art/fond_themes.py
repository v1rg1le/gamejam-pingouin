"""[FOND 1.75] Thèmes de fond de Pinpouin : suite du glacier vers le bas et
ciel lointain au-dessus des nuages (demande de l'équipe du 27/11).

Tout est généré en pixel art dans la palette des images d'origine
(Background_glacier / mountains / clouds, 320 x 308, affichées x4 en jeu).
Les images d'origine ne sont PAS modifiées : on écrit de nouvelles images.

Usage (depuis la racine du dépôt) :  python3 tools/art/fond_themes.py
  -> sprites/levels/fonds/Fond_bas_*.png et Fond_ciel_*.png
  (puis `godot --headless --import` pour générer les .import)
  python3 tools/art/fond_themes.py --planches  -> planches de présentation
  dans /tmp/fond_planches/
Graines fixes : relancer le script redonne exactement les mêmes images.
"""
import random
from PIL import Image, ImageDraw, ImageFont

W = 320
# Palette d'origine
SNOW = (203, 219, 252)   # neige / fissures claires du glacier
ICE = (104, 130, 182)    # glace de la falaise
DARK = (57, 76, 98)      # crevasses sombres
HI = (223, 243, 254)     # reflets clairs
SKY0 = (102, 124, 149)   # haut de l'image des nuages
NIGHT1 = (34, 32, 52)
NIGHT2 = (12, 10, 27)
MOUNT = (69, 80, 101)

import os, sys
SRC = 'sprites/levels/'
glacier = Image.open(SRC + 'Background_glacier.png').convert('RGBA')
mount = Image.open(SRC + 'Background_mountains.png').convert('RGBA')
clouds = Image.open(SRC + 'Background_clouds.png').convert('RGBA')

CODE = {SNOW: '.', ICE: 'o', DARK: '#', HI: 'w'}
COL = {v: k for k, v in CODE.items()}


def last_row():
    row = []
    for x in range(W):
        p = glacier.getpixel((x, 307))
        row.append(CODE.get(p[:3], 'o') if p[3] else 'o')
    return row


def runs_of(row):
    """Découpe la ligne en morceaux [couleur, longueur, tendance] (en boucle)."""
    # on démarre sur une frontière pour que la ligne boucle proprement
    start = 0
    for i in range(W):
        if row[i] != row[i - 1]:
            start = i
            break
    rot = row[start:] + row[:start]
    out = []
    for c in rot:
        if out and out[-1][0] == c:
            out[-1][1] += 1
        else:
            out.append([c, 1, 0])
    return out, start


def evolve(rows_needed, rng, spawn=1.0, wedge_bias=-0.35):
    """Prolonge la falaise ligne par ligne. Chaque bande (crevasse sombre,
    reflet clair, fissure) est un « objet » qui grandit jusqu'à sa largeur,
    tient un moment, puis s'amincit en pointe : mêmes formes longues et lisses
    que le dessin d'origine. Les bords ne bougent qu'une ligne sur trois ou
    quatre, pour garder des pans de glace droits."""
    row = last_row()
    runs, start = runs_of(row)
    # [couleur, largeur, cible, durée de maintien]
    feats = []
    for c, n, _ in runs:
        if c == '#':
            feats.append([c, n, n, rng.randint(4, 30)])
        elif c == 'w':
            feats.append([c, n, n, rng.randint(6, 40)])
        elif c == '.':
            feats.append([c, n, n, rng.randint(10, 60)])
        else:
            feats.append([c, n, n, 999])
    out = []
    MAXW = {'#': 14, 'w': 18, '.': 2}
    for _ in range(rows_needed):
        for f in feats:
            c = f[0]
            if c == 'o':
                continue
            f[3] -= 1
            if f[3] > 0:          # croissance vers la cible, puis maintien
                if f[1] < f[2] and rng.random() < 0.45:
                    f[1] += 1
            elif rng.random() < (0.3 if c == '#' else 0.4):
                f[1] -= 1         # pointe vers le bas
        # dérive lente (pans de glace presque droits)
        for i, f in enumerate(feats):
            if f[0] != 'o' and rng.random() < 0.09:
                L, R = feats[i - 1], feats[(i + 1) % len(feats)]
                if L[0] == 'o' and R[0] == 'o':
                    if rng.random() < 0.5 and L[1] > 2:
                        L[1] -= 1; R[1] += 1
                    elif R[1] > 2:
                        R[1] -= 1; L[1] += 1
        feats = [f for f in feats if f[1] > 0]
        born = []
        for f in feats:
            if f[0] == 'o' and f[1] > 26 and rng.random() < 0.03 * spawn:
                kind = rng.choices(['#', 'w', '.'], [0.35, 0.45, 0.2])[0]
                a = rng.randint(8, f[1] - 12)
                tgt = {'#': rng.randint(5, 12), 'w': rng.randint(5, 16), '.': rng.randint(1, 2)}[kind]
                hold = {'#': rng.randint(20, 60), 'w': rng.randint(14, 45), '.': rng.randint(20, 70)}[kind]
                born += [['o', a, 0, 999], [kind, 1, tgt, hold], ['o', f[1] - a - 1, 0, 999]]
            else:
                born.append(f)
        feats = []
        for f in born:
            if feats and feats[-1][0] == f[0] == 'o':
                feats[-1][1] += f[1]
            else:
                feats.append(f)
        tot = sum(f[1] for f in feats)
        while tot != W:
            i = max(range(len(feats)), key=lambda k: feats[k][1] if feats[k][0] == 'o' else -1)
            feats[i][1] += 1 if tot < W else -1
            tot += 1 if tot < W else -1
        line = []
        for f in feats:
            line += [f[0]] * f[1]
        line = line[W - start:] + line[:W - start]
        out.append(line)
    return out


def darken_map(depth_t):
    """Plus on descend, plus la glace s'enfonce dans l'ombre (palette du jeu)."""
    steps = [
        {'.': SNOW, 'o': ICE, '#': DARK, 'w': HI},
        {'.': ICE, 'o': (84, 106, 150), '#': (45, 58, 80), 'w': SNOW},
        {'.': (84, 106, 150), 'o': DARK, '#': NIGHT1, 'w': ICE},
        {'.': DARK, 'o': (40, 48, 70), '#': NIGHT2, 'w': (84, 106, 150)},
        {'.': NIGHT1, 'o': NIGHT1, '#': NIGHT2, 'w': DARK},
    ]
    return steps, depth_t


import math
def wave(x, seed=0.0):
    """Bord ondulé et qui boucle sur 320 px (comme le bas des nuages)."""
    t = x / W * 6.283
    return 3.0 * math.sin(t * 2 + seed) + 2.0 * math.sin(t * 5 + seed * 1.7) + 1.0 * math.sin(t * 11 + seed * 0.3)


def dither_pick(steps, f, x, y):
    """Passage d'une teinte à la suivante en damier (comme le fondu des nuages)."""
    f = max(0.0, min(len(steps) - 1 - 1e-6, f))
    i = int(f)
    frac = f - i
    # bandes plates, avec seulement quelques lignes de damier entre deux
    # teintes (comme les bords tramés des nuages d'origine)
    if frac < 0.75:
        return steps[i]
    if frac < 0.88:
        return steps[i + 1] if (x + y) % 2 == 0 and y % 2 == 0 else steps[i]
    return steps[i + 1] if (x + y) % 2 == 0 else steps[i]


def render(lines, palette_fn):
    im = Image.new('RGBA', (W, len(lines)))
    px = im.load()
    for y, line in enumerate(lines):
        for x, c in enumerate(line):
            px[x, y] = palette_fn(x, y, c) + (255,)
    return im


# --------------------------------------------------------------- GLACIER A
def glacier_A(seed=7, H=260):
    rng = random.Random(seed)
    lines = evolve(H, rng)
    steps, _ = darken_map(0)

    def pal(x, y, c):
        f = max(0.0, (y + wave(x, 1.3) - 40) / (H - 40)) * 4.2
        return dither_pick(steps, f, x, y)[c]
    return render(lines, pal)


# --------------------------------------------------------------- GLACIER B
def glacier_B(seed=11, H=260):
    """Strates : la glace ancienne se lit en couches, avec des grottes bleues."""
    rng = random.Random(seed)
    lines = evolve(H, rng, spawn=1.4)
    strata = [58, 120, 176, 226]
    # lignes de strate ondulées (2 px clairs + 1 px sombre dessous)
    for s in strata:
        ph = rng.random() * 6.28
        amp = rng.randint(2, 4)
        fq = rng.choice([1, 1, 2])
        for x in range(W):
            import math
            y = s + int(round(amp * math.sin(x / 320 * 6.283 * fq + ph)))
            if 0 <= y < H - 2:
                lines[y][x] = '.'
                lines[y + 1][x] = '#'
    # grottes : arches sombres avec un cœur bleu clair
    caves = []
    for _ in range(5):
        cx, cy = rng.randint(10, 310), rng.randint(70, 215)
        caves.append((cx, cy, rng.randint(7, 13), rng.randint(9, 15)))
    for cx, cy, rw, rh in caves:
        for y in range(cy - rh, cy + 2):
            for dx in range(-rw, rw + 1):
                x = (cx + dx) % W
                yy = (y - cy) / rh
                if (dx / rw) ** 2 + yy ** 2 <= 1.0 and 0 <= y < H:
                    inner = (dx / (rw - 3)) ** 2 + ((y - cy) / (rh - 3)) ** 2 <= 1.0 if rw > 3 else False
                    lines[y][x] = 'w' if inner and y > cy - rh + 5 else '#'
    steps, _ = darken_map(0)

    def pal(x, y, c):
        f = max(0.0, (y + wave(x, 2.1) - 50) / (H - 50)) * 3.6
        p = dither_pick(steps, f, x, y)[c]
        return p
    im = render(lines, pal)
    # lueur bleue dans les grottes (une teinte un peu plus vive)
    px = im.load()
    for cx, cy, rw, rh in caves:
        for y in range(cy - rh + 5, cy + 1):
            for dx in range(-rw + 3, rw - 2):
                x = (cx + dx) % W
                if 0 <= y < H and lines[y][x] == 'w':
                    px[x, y] = (150, 200, 240, 255) if (x + y) % 3 else (203, 235, 252, 255)
    return im


# --------------------------------------------------------------- GLACIER C
def glacier_C(seed=5, H=260, cliff=120):
    """Le pied du glacier : la falaise s'arrête sur une mer glacée."""
    import math
    rng = random.Random(seed)
    lines = evolve(cliff + 6, rng)
    steps, _ = darken_map(0)
    im = Image.new('RGBA', (W, H))
    px = im.load()
    # bas de falaise irrégulier (blocs tombés, pointes)
    edge = []
    e = cliff
    for x in range(W):
        if rng.random() < 0.2:
            e += rng.choice([-2, -1, 1, 2])
        e = max(cliff - 8, min(cliff + 4, e))
        edge.append(e)
    water_top = cliff + 6
    for y in range(H):
        for x in range(W):
            if y < edge[x]:
                f = max(0.0, (y + wave(x, 0.4) - 30) / cliff) * 1.6
                px[x, y] = dither_pick(steps, f, x, y)[lines[y][x]] + (255,)
            elif y < water_top:
                px[x, y] = DARK + (255,)  # ombre au pied
            else:
                d = (y - water_top) / (H - water_top)
                base = dither_pick([DARK, (45, 58, 80), NIGHT1, NIGHT2], d * 3.2, x, y)
                px[x, y] = base + (255,)
    # reflet de la falaise : lignes cassées, plus sombres
    for y in range(water_top, min(H, water_top + 70)):
        src = water_top - (y - water_top) - 2
        if src < 0:
            break
        if (y - water_top) % 3 == 2:
            continue
        shift = int(round(2 * math.sin(y * 0.9)))
        for x in range(W):
            if (y - water_top) > 8 and ((x // 3 + y) % max(2, 9 - (y - water_top) // 8)) == 0:
                continue
            c = lines[src][(x + shift) % W]
            col = {'.': (84, 106, 150), 'o': (66, 86, 120), '#': NIGHT1, 'w': ICE}[c]
            px[x, y] = col + (255,)
    # vaguelettes claires
    for _ in range(70):
        x = rng.randint(0, W - 1); y = rng.randint(water_top + 2, H - 4)
        n = rng.randint(2, 7)
        for k in range(n):
            px[(x + k) % W, y] = (SNOW if y < water_top + 50 else ICE) + (255,)
    # petits icebergs
    for _ in range(4):
        bx, by = rng.randint(0, W - 1), rng.randint(water_top + 10, H - 30)
        bw = rng.randint(8, 18)
        bh = rng.randint(4, 8)
        for y in range(by - bh, by):
            ww = bw - (by - y) // 2
            for dx in range(-ww // 2, ww // 2):
                c = HI if dx < 0 else SNOW
                if y == by - bh:
                    c = HI
                px[(bx + dx) % W, y] = c + (255,)
        for y in range(by, by + bh // 2):  # reflet
            ww = bw - (y - by) * 2
            for dx in range(-ww // 2, ww // 2):
                if (y + dx) % 2 == 0:
                    px[(bx + dx) % W, y] = ICE + (255,)
    return im


# --------------------------------------------------------------- CIELS
def sky_base(H, rng, top=NIGHT2):
    """Dégradé en bandes, du haut des nuages vers le ciel profond."""
    steps = [SKY0, (82, 100, 128), DARK, (45, 52, 76), NIGHT1, (22, 20, 40), top]
    im = Image.new('RGBA', (W, H))
    px = im.load()
    for y in range(H):
        for x in range(W):
            # [1.75] le ciel fonce VITE au-dessus des nuages : en jeu, on n'en
            # voit que le bas (dézoom), il faut que les étoiles y soient déjà.
            # Les 26 dernières lignes restent de la couleur du haut des nuages
            # (cachées derrière eux, elles servent de raccord).
            u = max(0.0, (H - 1 - y + wave(x, 0.9) - 26) / (H - 26))
            f = (u ** 0.5) * (len(steps) - 1) * 1.05
            px[x, y] = dither_pick(steps, f, x, y) + (255,)
    return im


def stars(im, rng, n, ymax_frac=0.8, big=0.06):
    px = im.load()
    H = im.size[1]
    for _ in range(n):
        x = rng.randint(0, W - 1)
        # [1.75] étoiles réparties jusqu'au ras des nuages (sauf le raccord)
        y = int(rng.random() * (H - 36))
        r = rng.random()
        if r < big:  # étoile en croix, comme les petits nuages pixel
            for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                px[(x + dx) % W, max(0, min(H - 1, y + dy))] = (SNOW if (dx or dy) else HI) + (255,)
        elif r < 0.35:
            px[x, y] = HI + (255,)
        else:
            px[x, y] = (SNOW if rng.random() < 0.6 else (131, 142, 163)) + (255,)


def sky_1(H=240, seed=3):
    rng = random.Random(seed)
    im = sky_base(H, rng)
    stars(im, rng, 230)
    return im


def sky_2(H=240, seed=4):
    """Aurore boréale : rideaux verticaux qui pendent d'une ligne ondulée."""
    import math
    rng = random.Random(seed)
    im = sky_base(H, rng)
    stars(im, rng, 170)
    px = im.load()
    A1, A2, A3 = (63, 120, 128), (94, 168, 170), (170, 230, 214)
    for band in range(2):
        ph = rng.random() * 6.28
        base = 120 + band * 40   # [1.75] plus bas : visible au-dessus des nuages
        for x in range(W):
            top = base + 14 * math.sin(x / W * 6.283 * 2 + ph) + 6 * math.sin(x / W * 6.283 * 5 + ph * 2)
            ln = 22 + 14 * (0.5 + 0.5 * math.sin(x / W * 6.283 * 3 + ph * 3)) + rng.randint(-3, 3)
            if band == 1:
                ln *= 0.7
            for k in range(int(ln)):
                y = int(top) + k
                if not (0 <= y < H):
                    continue
                t = k / ln
                # lumineux en haut du rideau, puis s'efface en damier
                if t < 0.12:
                    c = A3
                elif t < 0.45:
                    c = A2
                else:
                    c = A1
                    if (x + y) % 2 and t > 0.7:
                        continue
                if x % 7 == 0 and t > 0.3:
                    continue  # rayures verticales du rideau
                px[x, y] = c + (255,)
    return im


def sky_3(H=240, seed=9):
    """Voie lactée en diagonale + étoile filante + planète lointaine."""
    import math
    rng = random.Random(seed)
    im = sky_base(H, rng)
    px = im.load()
    # nébuleuse : nuages de pixels sombres-bleus le long d'une diagonale
    for _ in range(5200):
        u = rng.random()
        x = int(u * W)
        yc = 95 + u * 100 + 14 * math.sin(u * 9)   # [1.75] plus bas
        y = int(rng.gauss(yc, 13))
        if 0 <= y < H - 34:
            d = abs(y - yc) / 13
            c = (45, 52, 76) if d > 1.1 else ((57, 76, 98) if d > 0.5 else (82, 100, 128))
            px[x % W, y] = c + (255,)
    stars(im, rng, 140)
    # étoiles denses dans la voie lactée
    for _ in range(260):
        u = rng.random(); x = int(u * W)
        y = int(rng.gauss(95 + u * 100 + 14 * math.sin(u * 9), 8))
        if 0 <= y < H:
            px[x % W, y] = (HI if rng.random() < 0.4 else SNOW) + (255,)
    # étoile filante
    x0, y0 = 250, 120
    for k in range(26):
        x, y = x0 - k, y0 + k // 2
        c = HI if k < 3 else (SNOW if k < 12 else (131, 142, 163))
        if k > 18 and k % 2:
            continue
        px[x, y] = c + (255,)
    # petite planète à anneau, très loin
    cx, cy, r = 62, 150, 9
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                lit = (x - cx) + (y - cy) < -2
                px[x, y] = ((131, 142, 163) if lit else (69, 80, 101)) + (255,)
    for x in range(cx - 16, cx + 17):
        y = cy + int(round((x - cx) * 0.25))
        if (x - cx) ** 2 + (y - cy) ** 2 > (r - 1) ** 2 or (x - cx) < 0:
            px[x, y] = SNOW + (255,)
    return im


# --------------------------------------------------------------- PLANCHES
try:
    FONT = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 30)
    FONT_S = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 22)
except OSError:
    FONT = FONT_S = ImageFont.load_default()

S = 3  # zoom des planches


def column(sky=None, ext=None, show_new=True):
    """Pile complète du fond : ciel lointain, nuages, montagnes, glacier, suite."""
    hs = sky.size[1] if sky else 0
    he = ext.size[1] if ext else 0
    im = Image.new('RGBA', (W, hs + 308 + he), ICE + (255,))
    if sky:
        im.alpha_composite(sky, (0, 0))
    for l in (clouds, mount, glacier):
        im.alpha_composite(l, (0, hs))
    if ext:
        im.alpha_composite(ext, (0, hs + 308))
    return im, hs, he


def board(title, sub, img, marks):
    big = img.resize((img.size[0] * S, img.size[1] * S), Image.NEAREST)
    pad = 90
    out = Image.new('RGB', (big.size[0] + 220, big.size[1] + pad), (24, 26, 38))
    out.paste(big, (0, pad))
    d = ImageDraw.Draw(out)
    d.text((16, 12), title, font=FONT, fill=(230, 240, 255))
    d.text((16, 52), sub, font=FONT_S, fill=(170, 185, 210))
    for y0, y1, label, new in marks:
        col = (255, 200, 80) if new else (140, 150, 170)
        x = big.size[0] + 12
        d.line([(x, pad + y0 * S), (x, pad + y1 * S)], fill=col, width=4)
        d.text((x + 12, pad + (y0 + y1) * S // 2 - 12), label, font=FONT_S, fill=col)
    return out


# Noms des fichiers dans le jeu (Settings.BG_GLACIER_THEMES / BG_SKY_THEMES)
FILES = {
    'Fond_bas_falaise.png': glacier_A, 'Fond_bas_strates.png': glacier_B, 'Fond_bas_mer.png': glacier_C,
    'Fond_ciel_etoiles.png': sky_1, 'Fond_ciel_aurore.png': sky_2, 'Fond_ciel_voie_lactee.png': sky_3,
}

if __name__ == '__main__' and '--planches' not in sys.argv:
    os.makedirs('sprites/levels/fonds', exist_ok=True)
    for name, fn in FILES.items():
        fn().save('sprites/levels/fonds/' + name)
        print('écrit', name)

if __name__ == '__main__' and '--planches' in sys.argv:
    os.makedirs('/tmp/fond_planches/out', exist_ok=True)
    os.chdir('/tmp/fond_planches')
    gl = {'A': (glacier_A(), 'Glacier A — « Falaise sans fond »',
                'La falaise continue, les crevasses dérivent, puis tout s\'enfonce dans l\'ombre'),
          'B': (glacier_B(), 'Glacier B — « Strates et grottes bleues »',
                'Couches de glace ancienne + petites grottes qui brillent, puis l\'ombre'),
          'C': (glacier_C(), 'Glacier C — « Pied du glacier sur la mer »',
                'La falaise s\'arrête sur une eau glacée : reflet cassé, icebergs')}
    for k, (ext, t, s) in gl.items():
        ext.save(f'out/glacier_{k}_brut.png')
        col, hs, he = column(None, ext)
        crop = col.crop((0, 140, W, col.size[1]))
        img = board(t, s, crop, [(236 - 140, 308 - 140, 'glacier actuel', False),
                                 (308 - 140, 308 - 140 + he, 'NOUVEAU', True)])
        img.save(f'out/proposition-glacier-{k}.png')
    sk = {'1': (sky_1(), 'Ciel 1 — « Nuit étoilée »',
                'Dégradé en bandes tramées (comme les nuages) + étoiles pixel et en croix'),
          '2': (sky_2(), 'Ciel 2 — « Aurore boréale »',
                'Étoiles + deux rideaux d\'aurore (3 teintes vert-bleu en plus de la palette)'),
          '3': (sky_3(), 'Ciel 3 — « Voie lactée »',
                'Voie lactée en diagonale, étoile filante, petite planète à anneau')}
    for k, (sky, t, s) in sk.items():
        sky.save(f'out/ciel_{k}_brut.png')
        col, hs, he = column(sky, None)
        crop = col.crop((0, 0, W, hs + 200))
        img = board(t, s, crop, [(0, hs, 'NOUVEAU', True), (hs, hs + 200, 'nuages actuels', False)])
        img.save(f'out/proposition-ciel-{k}.png')
