# Pixel art « Pinpouin » du niveau « Le Half-Pipe de l'œuf » (1.60) :
# œuf glacé, stalactites, plateformes-stalactites, prise d'accroche, panneaux
# flèches, tuiles de glace et de roche de la grotte. Palette reprise des
# sprites du jeu (warning.png, tile_ice_*).
#
# Usage (depuis la racine du dépôt) :  python3 tools/art/egg_art.py
# -> écrit les PNG dans sprites/levels/egg/ (puis lancer l'éditeur ou
#    `godot --headless --import` pour générer les .import).
# Dossier tools/ ignoré par Godot (.gdignore).
from PIL import Image
import math, random
OUT=(0x2b,0x3a,0x59,255); DEEP=(0x44,0xa2,0xbe,255); MID=(0x66,0xb4,0xd2,255)
LIGHT=(0x82,0xbe,0xd8,255); SNOW=(0xdf,0xf3,0xfe,255); FILL=(0xb1,0xdc,0xf4,255)
FILL2=(0x90,0xc4,0xe2,255); BLUE=(0x24,0x99,0xdd,255); INK=(0x17,0x19,0x2f,255)
T=(0,0,0,0)

def outline(im, col=OUT):
    w,h=im.size; px=im.load(); src=im.copy().load()
    for y in range(h):
        for x in range(w):
            if src[x,y][3]==0:
                for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    X,Y=x+dx,y+dy
                    if 0<=X<w and 0<=Y<h and src[X,Y][3]>0 and src[X,Y]!=col:
                        px[x,y]=col; break
    return im

# ---------------------------------------------------------------- stalactite
def icicle(w, h, seed=0, cap=True):
    random.seed(seed)
    im=Image.new('RGBA',(w+4,h+4),T); px=im.load()
    steps=[]
    for y in range(h):
        t=y/(h-1)
        half=(w/2)*(1-t)**0.85
        steps.append(max(0.5,half))
    cx=(w+4)/2
    for y,half in enumerate(steps):
        x0=int(round(cx-half)); x1=int(round(cx+half))
        for x in range(x0,max(x1,x0+1)):
            u=(x-x0)/max(1,(x1-x0))
            c=LIGHT if u<0.3 else (MID if u<0.68 else DEEP)
            if 0.12<u<0.24 and y>2 and y<h*0.8: c=SNOW      # reflet vertical
            px[x,y+2]=c
    if cap:   # neige sur le dessus
        for x in range(int(cx-w/2)-1,int(cx+w/2)+1):
            d=random.choice([2,2,3,3,4,5])
            for y in range(0,d): 
                if 0<=x<im.width: px[x,y+1]=SNOW
    return outline(im)

# ------------------------------------------------- plateforme-stalactite
def platform(w, seed=0):
    random.seed(seed)
    h=70
    im=Image.new('RGBA',(w+4,h+4),T); px=im.load()
    body=14
    for y in range(body):
        for x in range(2,w+2):
            c=FILL if y<4 else (LIGHT if y<body-4 else MID)
            if y>=body-2: c=DEEP
            if y>=4 and y<body-4 and (x*7+y*13)%29==0: c=FILL      # petits reflets
            px[x,y+4]=c
    for x in range(2,w+2):                     # neige
        d=random.choice([3,3,4,4,5])
        for y in range(0,d): px[x,y+1]=SNOW
    # glaçons qui pendent dessous
    x=4
    while x<w-4:
        iw=random.choice([6,8,10,12]); ih=random.choice([18,26,34,44,52])
        ic=icicle(iw,ih,seed=x+seed,cap=False)
        ic=Image.eval(ic,lambda v:v)
        im.alpha_composite(ic,(x-2,4+body-4))
        x+=iw+random.choice([2,4,6])
    return outline(im)

# ------------------------------------------------------- prise d'accroche
def hold():
    """Prise : boule de glace avec un anneau bleu vif (« on s'accroche ici »)."""
    im=Image.new('RGBA',(28,28),T); px=im.load()
    for y in range(28):
        for x in range(28):
            dx,dy=x-13.5,y-13.5; r=math.hypot(dx,dy)
            if r<11.5:
                l=(-dx-dy)/16
                c=FILL if l>0.5 else LIGHT if l>0.0 else MID if l>-0.5 else DEEP
                if 8.6<r<10.6: c=BLUE                      # anneau
                px[x,y]=c
    for (x,y) in [(9,8),(10,7),(8,9),(11,7),(9,9)]: px[x,y]=SNOW   # reflet
    return outline(im)

# ---------------------------------------------------------------- panneaux
ARROWS={'droite':(1,0),'gauche':(-1,0),'haut':(0,-1),'bas':(0,1),'haut-droite':(1,-1),'bas-gauche':(-1,1),'haut-gauche':(-1,-1),'bas-droite':(1,1)}
def sign(direction):
    """Panneau flèche dans le style du panneau « attention » du jeu :
    double bord sombre, face blanche, petit chapeau de neige, poteau fin,
    petit tas de neige au pied."""
    im=Image.new('RGBA',(64,64),T); px=im.load()
    random.seed(len(direction)*7)
    # poteau (comme warning.png : bord sombre, centre clair)
    for y in range(37,59):
        for x in range(30,34): px[x,y]=INK if x in (30,33) else SNOW
    # tas de neige irrégulier au pied
    for x in range(23,42):
        top=59-int(3*math.sin(math.pi*(x-23)/19))-random.choice([0,0,1])
        for y in range(top,62): px[x,y]=SNOW
        if random.random()<0.3: px[x,61]=LIGHT
    # panneau : rectangle arrondi, bord sombre + liseré intérieur
    x0,y0,x1,y1=14,15,50,38
    R=4
    def inside(x,y,m):
        cx=min(max(x,x0+R),x1-1-R); cy=min(max(y,y0+R),y1-1-R)
        return math.hypot(x-cx,y-cy)<=R-m+0.3
    for y in range(y0,y1):
        for x in range(x0,x1):
            if inside(x,y,0):
                px[x,y]=INK
                if inside(x,y,2): px[x,y]=SNOW
                if inside(x,y,3) and not inside(x,y,4): px[x,y]=INK   # liseré intérieur
                if inside(x,y,4): px[x,y]=SNOW
    # flèche
    dx,dy=ARROWS[direction]; L=math.hypot(dx,dy); dx/=L; dy/=L
    cx,cy=32,26.5
    for y in range(y0+4,y1-4):
        for x in range(x0+4,x1-4):
            rx,ry=x+0.5-cx,y+0.5-cy
            a=rx*dx+ry*dy; b=-rx*dy+ry*dx
            shaft = -8<=a<=1 and abs(b)<=1.6
            head = 0<=a<=7.5 and abs(b)<=(7.5-a)*0.95
            if shaft or head: px[x,y]=INK
    # chapeau de neige irrégulier, avec quelques pixels bleus
    for x in range(x0+1,x1-1):
        u=(x-x0)/(x1-x0)
        d=int(1+3*math.sin(math.pi*u)**0.7+random.choice([0,0,1,2]))
        for y in range(y0-d,y0+1): px[x,y]=SNOW
        if random.random()<0.25: px[x,y0-d]=LIGHT
    return outline(im)

# ---------------------------------------------------------------- l'œuf
def egg(W=300, H=120, seed=3):
    random.seed(seed)
    im=Image.new('RGBA',(W+8,H+40),T); px=im.load()
    A=W/2; B=H/2; cx=A+4; cy=B+6; K=0.13
    def inside(x,y):
        Y=(cy-y)/B
        if abs(Y)>1: return False
        X=(x-cx)/(A*(1-K*Y)) if True else 0
        return X*X+Y*Y<=1
    # éclats de glace : lignes droites brisées (facettes), un ton plus sombre
    shard=set()
    for _ in range(22):
        x=random.uniform(cx-A*0.85,cx+A*0.85); y=random.uniform(cy-B*0.75,cy+B*0.8)
        for seg in range(random.randint(2,4)):
            ang=random.choice([0.35,0.6,2.5,2.8,1.2,-0.3])+random.uniform(-0.15,0.15)
            ln=random.randint(6,16)
            for k in range(ln):
                shard.add((int(x),int(y))); x+=math.cos(ang); y+=math.sin(ang)*0.6
    def facet(x,y): return (x,y) in shard
    cracks=set()
    for _ in range(9):    # fissures dans la glace
        x=random.uniform(cx-A*0.7,cx+A*0.7); y=random.uniform(cy-B*0.5,cy+B*0.6)
        ang=random.uniform(0,math.pi)
        for k in range(random.randint(8,20)):
            cracks.add((int(x),int(y)))
            ang+=random.uniform(-0.6,0.6); x+=math.cos(ang); y+=math.sin(ang)*0.7
    for y in range(im.height):
        for x in range(im.width):
            if not inside(x+0.5,y+0.5): continue
            Y=(cy-y)/B; X=(x-cx)/(A*(1-K*Y))
            r2=min(1.0,X*X+Y*Y); Z=math.sqrt(1-r2)          # dôme : vraie normale
            l=-0.45*X+0.55*Y+0.70*Z                          # lumière en haut à gauche, de face
            c=SNOW if l>0.975 else FILL if l>0.74 else LIGHT if l>0.50 else MID if l>0.22 else DEEP
            if r2>0.93 and c not in (SNOW,): c=DEEP if c in (MID,LIGHT) else c   # bord plus sombre
            # strates de glace qui suivent la courbe de l'œuf
            ring=math.sqrt(r2)
            # facettes de glace : quelques taches irrégulières un ton plus sombre
            if c in (FILL,LIGHT,MID) and facet(x,y): c=FILL2 if c==FILL else (MID if c==LIGHT else DEEP)
            if (x,y) in cracks and c!=SNOW: c=DEEP if c in (FILL,LIGHT,FILL2) else OUT
            px[x,y]=c
    # reflets
    for (x0,y0,n) in [(cx-A*0.45,cy-B*0.55,9),(cx-A*0.38,cy-B*0.42,5),(cx+A*0.2,cy-B*0.75,6)]:
        for k in range(n):
            X,Y=int(x0+k),int(y0-k*0.5)
            if px[X,Y][3]: px[X,Y]=SNOW
    # neige sur le sommet
    for x in range(im.width):
        for y in range(im.height):
            if px[x,y][3] and not px[x,max(0,y-1)][3]:
                Y=(cy-y)/B
                if Y>0.5:
                    d=random.choice([2,3,3,4,4,5]) + int(6*(Y-0.5))
                    if random.random()<0.12: d+=random.choice([3,5])   # coulures de neige
                    for k in range(d):
                        if y+k<im.height and px[x,y+k][3]: px[x,y+k]=SNOW
                break
    # petits glaçons sous l'œuf
    xs=list(range(int(cx-A*0.75),int(cx+A*0.75),random.choice([5,6,7])))
    for x in xs:
        if random.random()<0.35: continue
        ybot=max(y for y in range(im.height) if px[x,y][3])
        ln=random.choice([4,6,8,11,15])
        for k in range(ln):
            w=max(0,int((1-k/ln)*2))
            for dx in range(-w,w+1):
                X=x+dx; Y=ybot+k
                if Y<im.height: px[X,Y]=MID if dx>=0 else LIGHT
    return outline(im)

# ------------------------------------------------- texture de l'œuf EN JEU
def egg_texture(A_world=10000.0, B_world=3400.0, K=0.13, S=6, seed=11):
    """L'œuf du niveau à l'échelle : 1 pixel d'art = S pixels du monde.
    Même équation que EggGenerator._egg_point : x = A cos t (1 - K sin t),
    y = -B sin t. Le centre de l'œuf est au pixel (PAD + A/S, PAD + B/S) :
    EggGenerator règle texture_offset en conséquence. La fente du half-pipe
    et la crevasse sont découpées par le polygone en jeu (pas ici)."""
    random.seed(seed)
    PAD=4
    A=A_world/S; B=B_world/S
    W=int(2*A+2*PAD); H=int(2*B+2*PAD)
    cx=PAD+A; cy=PAD+B
    im=Image.new('RGBA',(W,H),T); px=im.load()
    # éclats (facettes) et fissures, en nombre proportionnel à la surface
    shard=set(); cracks=set()
    for _ in range(int(A*B/420)):
        x=random.uniform(cx-A*0.9,cx+A*0.9); y=random.uniform(cy-B*0.8,cy+B*0.85)
        for seg in range(random.randint(2,4)):
            ang=random.choice([0.35,0.6,2.5,2.8,1.2,-0.3])+random.uniform(-0.15,0.15)
            for k in range(random.randint(8,26)):
                shard.add((int(x),int(y))); x+=math.cos(ang); y+=math.sin(ang)*0.6
    for _ in range(int(A*B/1500)):
        x=random.uniform(cx-A*0.8,cx+A*0.8); y=random.uniform(cy-B*0.6,cy+B*0.7)
        ang=random.uniform(0,math.pi)
        for k in range(random.randint(10,40)):
            cracks.add((int(x),int(y)))
            ang+=random.uniform(-0.6,0.6); x+=math.cos(ang); y+=math.sin(ang)*0.7
    for y in range(H):
        Y=(cy-(y+0.5))/B
        if abs(Y)>1: continue
        for x in range(W):
            X=((x+0.5)-cx)/(A*(1-K*Y))
            r2=X*X+Y*Y
            if r2>1.0: continue
            Z=math.sqrt(1-r2)
            l=-0.45*X+0.55*Y+0.70*Z
            # tramage ordonné (Bayer 4x4) aux frontières des teintes : style pixel art
            l+=(BAYER[y%4][x%4]/16.0-0.47)*0.05
            c=SNOW if l>0.975 else FILL if l>0.74 else LIGHT if l>0.50 else MID if l>0.22 else DEEP
            if r2>0.985 and c!=SNOW: c=DEEP if c in (MID,LIGHT) else c
            if c in (FILL,LIGHT,MID) and (x,y) in shard: c=FILL2 if c==FILL else (MID if c==LIGHT else DEEP)
            if (x,y) in cracks and c!=SNOW: c=DEEP if c in (FILL,LIGHT,FILL2) else OUT
            px[x,y]=c
    # reflets (traits obliques clairs, en haut à gauche)
    for (fx,fy,n) in [(-0.45,-0.55,60),(-0.38,-0.42,34),(0.2,-0.75,40),(-0.6,-0.2,22)]:
        for k in range(n):
            for w in range(3):
                X,Y=int(cx+A*fx+k),int(cy+B*fy-k*0.5)+w
                if 0<=X<W and 0<=Y<H and px[X,Y][3]: px[X,Y]=SNOW
    # neige sur le sommet (avec coulures)
    for x in range(W):
        for y in range(H):
            if px[x,y][3]:
                Y=(cy-y)/B
                if Y>0.4:
                    d=random.choice([3,4,4,5,6]) + int(14*(Y-0.4))
                    if random.random()<0.08: d+=random.choice([6,10,14])
                    for k in range(d):
                        if y+k<H and px[x,y+k][3]: px[x,y+k]=SNOW
                    if y+d<H and px[x,y+d][3] and random.random()<0.5: px[x,y+d]=LIGHT
                break
    return im


BAYER=[[0,8,2,10],[12,4,14,6],[3,11,1,9],[15,7,13,5]]


def tile_ice(N=48, seed=5):
    """Tuile de glace (stalactites, corniches, plateformes, pont) : stries
    verticales et facettes, raccord sans couture (motif périodique)."""
    random.seed(seed)
    im=Image.new('RGBA',(N,N),FILL); px=im.load()
    # bandes verticales de 2 à 6 pixels (pas de rayures d'1 pixel : trop bruité)
    cols=[]
    while len(cols)<N:
        cols+= [random.choice([FILL,FILL,LIGHT,LIGHT,MID,FILL2])]*random.randint(2,6)
    cols=cols[:N]; cols[-1]=cols[0]
    for x in range(N):
        for y in range(N):
            px[x,y]=cols[x]
    for _ in range(18):                    # éclats obliques (enroulés : sans couture)
        x=random.randrange(N); y=random.randrange(N); ang=random.choice([0.4,2.7,1.3])
        for k in range(random.randint(4,10)):
            X=int(x)%N; Y=int(y)%N
            c=px[X,Y]; px[X,Y]=DEEP if c in (MID,) else MID if c==LIGHT else LIGHT
            x+=math.cos(ang); y+=math.sin(ang)
    for _ in range(10):
        X=random.randrange(N); Y=random.randrange(N); px[X,Y]=SNOW; px[(X+1)%N,Y]=SNOW
    return im


def tile_rock(N=64, seed=9):
    """Tuile de roche sombre pour le fond de la grotte (plus sombre que le
    ciel : on « sent » qu'on est sous terre). Taches + veines + quelques
    cristaux bleus. Périodique (sans couture)."""
    random.seed(seed)
    R0=(0x1d,0x22,0x3d,255); R1=(0x23,0x2c,0x4b,255); R2=(0x2b,0x3a,0x59,255)
    im=Image.new('RGBA',(N,N),R1); px=im.load()
    # bruit périodique : somme de sinus entiers sur la tuile
    ph=[random.uniform(0,6.28) for _ in range(6)]
    for y in range(N):
        for x in range(N):
            u=2*math.pi*x/N; v=2*math.pi*y/N
            n=(math.sin(u+ph[0])+math.sin(v+ph[1])+0.7*math.sin(2*u+v+ph[2])
               +0.6*math.sin(3*v-u+ph[3])+0.5*math.sin(4*u+2*v+ph[4]))
            px[x,y]=R0 if n<-0.9 else R2 if n>1.3 else R1
    for _ in range(5):                     # veines claires
        x=random.randrange(N); y=random.randrange(N); ang=random.uniform(0,6.28)
        for k in range(random.randint(8,18)):
            px[int(x)%N,int(y)%N]=R2
            ang+=random.uniform(-0.5,0.5); x+=math.cos(ang); y+=math.sin(ang)
    for _ in range(4):                     # petits cristaux
        X=random.randrange(N); Y=random.randrange(N)
        px[X,Y]=DEEP; px[X,(Y+1)%N]=OUT
    return im


def up(im,s): return im.resize((im.width*s,im.height*s),Image.NEAREST)

if __name__=='__main__':
    import os
    D=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..','sprites','levels','egg')
    os.makedirs(D,exist_ok=True)
    egg_texture().save(os.path.join(D,'oeuf_glace.png'))
    egg().save(os.path.join(D,'oeuf_apercu.png'))           # petite version (aperçu, icône)
    for i,(w,h) in enumerate([(14,60),(20,96),(26,130),(10,40)]):
        icicle(w,h,seed=i).save(os.path.join(D,'stalactite_%d.png'%i))
    for i,w in enumerate((96,128)):
        platform(w,seed=w).save(os.path.join(D,'plateforme_%d.png'%i))
    hold().save(os.path.join(D,'prise.png'))
    for d in ARROWS:
        sign(d).save(os.path.join(D,'panneau_%s.png'%d))
    tile_ice().save(os.path.join(D,'tuile_glace.png'))
    tile_rock().save(os.path.join(D,'tuile_roche.png'))
