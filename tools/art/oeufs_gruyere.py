# [ŒUFS 1.79] Œufs à grappiner du Gruyère de glace : 5 designs en pixel art,
# même palette que tools/art/egg_art.py. Forme EXACTE de la collision
# (GruyereGenerator._add_egg : x = RX cos t (1 + 0.12 sin t), y = RY sin t),
# 1 pixel d'image = 4 px de jeu (RX 130, RY 170).
# Usage (racine du dépôt) : python3 tools/art/oeufs_gruyere.py [--planche sortie.png]
from PIL import Image, ImageDraw
import math, random, sys
OUT=(0x2b,0x3a,0x59,255); DEEP=(0x44,0xa2,0xbe,255); MID=(0x66,0xb4,0xd2,255)
LIGHT=(0x82,0xbe,0xd8,255); SNOW=(0xdf,0xf3,0xfe,255); FILL=(0xb1,0xdc,0xf4,255)
FILL2=(0x90,0xc4,0xe2,255); INK=(0x17,0x19,0x2f,255); WHITE=(0xf6,0xfb,0xff,255)
RIM=(0x45,0x78,0xb3,255); ORANGE=(0xf0,0x9a,0x3a,255); PALE=(0xc9,0xe8,0xfa,255)
T=(0,0,0,0)
PX=4; RX=130/PX; RY=170/PX
W=int(math.ceil(2*RX*1.12))+4; H=int(math.ceil(2*RY))+4
CX=W/2; CY=H/2

def inside(x,y):
    # point (centre du pixel) dans la forme d'œuf ? (même formule que le jeu)
    yy=(y+0.5-CY)/RY
    if abs(yy)>1: return False
    s=yy; c=math.sqrt(max(0,1-s*s))
    half=RX*c*(1+0.12*s)
    return abs(x+0.5-CX)<=half

def base(fill_fn):
    im=Image.new('RGBA',(W,H),T); px=im.load()
    for y in range(H):
        for x in range(W):
            if inside(x,y): px[x,y]=fill_fn(x,y)
    return im

def outline(im,col=RIM):
    px=im.load(); src=im.copy().load()
    for y in range(H):
        for x in range(W):
            if src[x,y][3]>0:
                for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    X,Y=x+dx,y+dy
                    if not(0<=X<W and 0<=Y<H) or src[X,Y][3]==0:
                        px[x,y]=col; break
    return im

def shade(x,y,light=WHITE,mid=SNOW,dark=PALE,deep=FILL):
    # éclairage en haut à gauche, en bandes nettes (pixel art)
    u=(x+0.5-CX)/RX; v=(y+0.5-CY)/RY
    d=0.55*u+0.75*v
    if d< -0.55: return light
    if d< 0.25: return mid
    if d< 0.75: return dark
    return deep

def highlight(im,col=WHITE):
    # reflet en croissant en haut à gauche
    px=im.load()
    for y in range(H):
        for x in range(W):
            if px[x,y][3]==0: continue
            u=(x+0.5-CX)/RX; v=(y+0.5-CY)/RY
            r1=((u+0.38)/0.22)**2+((v+0.45)/0.32)**2
            r2=((u+0.30)/0.22)**2+((v+0.38)/0.32)**2
            if r1<1 and r2>1: px[x,y]=col
    return im

def egg_glace():
    # 1 — œuf de glace poli : dégradé glace, facettes, reflet
    def f(x,y):
        u=(x+0.5-CX)/RX; v=(y+0.5-CY)/RY
        d=0.55*u+0.75*v
        if d< -0.6: return SNOW
        if d< 0.0: return FILL
        if d< 0.55: return LIGHT
        return MID
    im=base(f); px=im.load()
    # fines facettes claires
    for (x0,y0,x1,y1) in ((0.1,-0.7,0.5,0.1),(-0.3,0.2,0.35,0.8),(0.5,0.1,0.15,0.9)):
        for k in range(60):
            t=k/59; x=int(CX+(x0+(x1-x0)*t)*RX); y=int(CY+(y0+(y1-y0)*t)*RY)
            if 0<=x<W and 0<=y<H and px[x,y][3]>0: px[x,y]=PALE
    return outline(highlight(im))

def egg_tachete():
    # 2 — œuf tacheté (œuf de manchot) : blanc, taches bleu pâle
    random.seed(7)
    im=base(lambda x,y: shade(x,y)); px=im.load()
    for _ in range(26):
        u=random.uniform(-0.8,0.8); v=random.uniform(-0.85,0.85)
        x=int(CX+u*RX); y=int(CY+v*RY); r=random.choice([1,1,1,2,2,3])
        col=random.choice([FILL2,LIGHT,FILL2])
        for dy in range(-r,r+1):
            for dx in range(-r,r+1):
                if dx*dx+dy*dy<=r*r+0.5 and 0<=x+dx<W and 0<=y+dy<H and px[x+dx,y+dy][3]>0:
                    px[x+dx,y+dy]=col
    return outline(highlight(im))

def egg_craquele():
    # 3 — œuf craquelé (« il va éclore ») : fissure en zigzag + éclats
    im=base(lambda x,y: shade(x,y)); px=im.load()
    yc=int(CY+0.05*RY); pts=[]
    x=2; up=True
    while x<W-2:
        pts.append((x,yc+(-3 if up else 3))); x+=5; up=not up
    for (a,b) in zip(pts,pts[1:]):
        n=max(abs(b[0]-a[0]),abs(b[1]-a[1]))
        for k in range(n+1):
            X=round(a[0]+(b[0]-a[0])*k/n); Y=round(a[1]+(b[1]-a[1])*k/n)
            if 0<=X<W and px[X,Y][3]>0: px[X,Y]=OUT
            if 0<=X<W and Y+1<H and px[X,Y+1][3]>0 and px[X,Y+1]!=OUT: px[X,Y+1]=FILL2
    # petite fissure verticale
    for k in range(9):
        X=int(CX+0.25*RX)+(k%2); Y=yc-3-k
        if px[X,Y][3]>0: px[X,Y]=OUT
    return outline(highlight(im))

def egg_neige():
    # 4 — bonnet de neige : calotte blanche à gouttes rondes, corps glace
    random.seed(3)
    def f(x,y):
        u=(x+0.5-CX)/RX; v=(y+0.5-CY)/RY
        d=0.55*u+0.75*v
        if d< -0.2: return FILL
        if d< 0.5: return LIGHT
        return MID
    im=base(f); px=im.load()
    # bord de la calotte : ligne ondulée à gouttes rondes
    edge={}
    for x in range(W):
        u=(x+0.5-CX)/RX
        # festons arrondis (demi-cercles) : la neige « coule » en boules
        k=(u+1.2)*4.0; fr=k-math.floor(k)
        e=-0.30+0.09*math.sqrt(max(0.0,1-(2*fr-1)**2))
        edge[x]=int(CY+e*RY)
    for x in range(W):
        for y in range(H):
            if px[x,y][3]>0 and y<=edge[x]:
                px[x,y]=SNOW
    # gouttes de neige arrondies sous la calotte
    for gx in (-0.55,-0.1,0.4,0.7):
        x=int(CX+gx*RX); y=edge[x]
        for dy in range(0,5):
            r=2 if dy<3 else 1
            for dx in range(-r,r+1):
                if 0<=x+dx<W and px[x+dx,y+dy][3]>0: px[x+dx,y+dy]=SNOW
    return outline(highlight(im))

def egg_bebe():
    # 5 — bébé Pinpouin endormi dans un œuf de glace translucide
    def f(x,y):
        u=(x+0.5-CX)/RX; v=(y+0.5-CY)/RY
        d=0.55*u+0.75*v
        if d< -0.5: return SNOW
        if d< 0.3: return FILL
        return FILL2
    im=base(f); px=im.load(); d=ImageDraw.Draw(im)
    # silhouette enroulée (un peu estompée par la glace : couleurs adoucies)
    body=(0x33,0x40,0x63,255); belly=(0xe8,0xf4,0xfc,255)
    cx,cy=CX+1,CY+6
    d.ellipse([cx-13,cy-12,cx+13,cy+14],fill=body)
    d.ellipse([cx-8,cy-4,cx+9,cy+13],fill=belly)
    d.ellipse([cx-10,cy-22,cx+8,cy-5],fill=body)       # tête
    d.ellipse([cx-6,cy-17,cx+4,cy-8],fill=belly)       # visage
    d.line([cx-4,cy-13,cx-1,cy-13],fill=INK)           # œil fermé
    d.polygon([(cx+3,cy-12),(cx+8,cy-11),(cx+3,cy-10)],fill=ORANGE)   # bec
    d.ellipse([cx-15,cy+2,cx-9,cy+12],fill=body)       # aileron
    d.polygon([(cx-5,cy+13),(cx-1,cy+16),(cx+3,cy+13)],fill=ORANGE)   # pattes
    # remettre la coquille par-dessus ce qui dépasse
    src=base(lambda x,y:(0,0,0,255)).load()
    for y in range(H):
        for x in range(W):
            if src[x,y][3]==0: px[x,y]=T
    return outline(highlight(im))

EGGS=[('glace',egg_glace),('tachete',egg_tachete),('craquele',egg_craquele),('neige',egg_neige),('bebe',egg_bebe)]
if __name__=='__main__':
    outs=[]
    for name,fn in EGGS:
        im=fn(); im.save(f'sprites/levels/gruyere/oeuf_{name}.png'); outs.append(im)
    if '--planche' in sys.argv:
        dst=sys.argv[sys.argv.index('--planche')+1]
        sc=5; pad=20
        bd=Image.new('RGBA',(len(outs)*(W*sc+pad)+pad,H*sc+2*pad),(52,64,92,255))
        for i,im in enumerate(outs): bd.paste(im.resize((W*sc,H*sc),Image.NEAREST),(pad+i*(W*sc+pad),pad),im.resize((W*sc,H*sc),Image.NEAREST))
        bd.save(dst)
    print(W,H)
