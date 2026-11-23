# Pinpouin Le Ninja — Migration Godot 3.4 → Godot 4.7 + corrections

Branche git : `godot4-migration` (le premier commit, « Baseline », contient votre état local d'avant, modifications non commitées comprises).
Lancement : ouvrir le projet dans **Godot 4.7** puis F5 (la scène principale est maintenant `src/screens/MainScreen.tscn`).

Toutes les modifications dans le code sont repérées par des balises en commentaire :
`[MIGRATION GODOT 4.7]`, `[FIX VITESSE -> 0]`, `[GRAPPIN]`, `[MORT / RESPAWN]`, `[ARRIVÉE]`, `[NOUVEAU]`, `[PATCH PINPOUIN]`.
Aucun nom de variable existant n'a été changé, aucun visuel ni aucune ressource n'a été supprimé.

---

## 1. Migration Godot 4.7

- Conversion automatique (`godot --convert-3to4`) puis relecture et corrections à la main de tous les scripts du jeu.
- `KinematicBody2D` → `CharacterBody2D`. **Point important** : en Godot 4, `move_and_slide()` ne modifie plus la vitesse après une collision. Le comportement de Godot 3 est reproduit à la main dans `Player._apply_godot3_slide()` (mode `FLOATING`, `wall_min_slide_angle = 0`), sinon le pingouin accumulait de la gravité dans le sol ou s'arrêtait net contre les pentes.
- `OpenSimplexNoise` → `FastNoiseLite` (période → fréquence, persistence → gain…). ⚠️ L'algorithme de bruit n'est plus le même : un même `world_seed` donne un relief de forme différente. **Calibrage (13/11)** : mesuré contre le bruit de Godot 3.4 recompilé à l'identique, FastNoiseLite donnait un relief ~1,5x plus haut avec des bosses ~2x plus serrées (25 % des montées > 25°, contre 0 % en 3.4). `sol.gd` applique maintenant fréquence x 0,5 et amplitude x 0,668 : pentes, bosses et amplitude identiques à la 3.4 à quelques % près, avec les mêmes réglages de niveau. En simulation, la vitesse moyenne est 1,5 à 2,7 fois plus élevée qu'avec le bruit brut. Interrupteur `g3_terrain_calibration` sur `sol.gd` pour comparer.
- `Vector2.angle_to_point()` a changé de sens en Godot 4 : corrigé dans `Chain.gd` (rotation de la chaîne) et `sol.gd` (rotation des décorations).
- Zoom caméra inversé en Godot 4 (le mode debug « zoom 10 » devient « zoom 0.1 »).
- Capsules de collision : en Godot 4, `height` inclut les demi-cercles → tailles recalculées pour garder les mêmes dimensions (pingouin et crochet).
- La répétition des textures n'est plus une option d'import mais une propriété des nœuds : activée sur les sols, la chaîne du grappin, les fonds et les niveaux SmartShape (sinon textures étirées).
- Thème : l'ancien bloc `ToolButton` (fusionné dans `Button` en Godot 4) écrasait le style des boutons → retiré ; police Roboto rebranchée.
- Écrans : `expand` → `expand_mode` / `ignore_texture_size`, `_get_configuration_warnings()` renvoie une liste, `export(String, FILE)` → `@export_file`.
- Manettes : les numéros de boutons/axes ont été remappés automatiquement vers la nomenclature Godot 4.
- **SmartShape2D** : remplacé par la version 3.3.2 (portage officiel Godot 4). Un petit correctif de plantage est appliqué dans `addons/rmsmartshape/shapes/shape.gd` (texture `null` dans les matériaux `Ice*.tres`).
- Outils Godot 3 incompatibles (addon GUT + ses tests, démo `godot-git-plugin`, scripts de tests, ancien SmartShape2D, `SoundController` inutilisé dont les sons n'existent pas) : **déplacés** dans `_archive_godot3/` (ignoré par Godot via `.gdignore`), rien n'est supprimé.
- `breakpoint` qui figeaient le jeu (Spaghetti, GroundGeneratorBlock) retirés.
- Les fichiers `.tscn` sont encore au format texte Godot 3 (Godot 4.7 les lit sans souci) ; ils passeront au format 4 la première fois que vous les enregistrerez dans l'éditeur.

## 2. Bug « vitesse → 0 » (prioritaire)

Plusieurs causes, toutes traitées :

1. **Collisions fantômes** (cause principale) : le sol généré est un grand polygone concave que le moteur découpe en morceaux convexes ; les arêtes internes renvoyaient parfois une normale presque horizontale et `velocity.slide()` annulait toute la vitesse en une frame. → Les sols générés (`sol`, `HalfPipe`, `Tremplin`) utilisent maintenant des collisions en **segments** (contour seul), plus un filtre dans `Player.gd` qui remplace une normale « aberrante » aux pieds par celle mesurée par les raycasts.
2. **Atterrissage contre une pente** (fond de vallée) : la projection de Godot 3 effaçait toute la vitesse « écrasée » contre le sol (900 → 60 px/s observé en test). → 50 % de cette vitesse est rendue le long de la pente (`landing_speed_keep`, réglable ; 0 = comportement d'origine).
3. **Touche Shift partagée entre `pull` et `trix`** : tirer sur le grappin en l'air lançait une figure, et toucher le sol en figure = état STAGGERED = vitesse forcée à 0 pendant 2 s. → Pas de figure pendant le grappin.
4. **État IDLE trop agressif** : il freinait fort dès que la vitesse *horizontale* passait sous 100 px/s (donc dans les pentes raides). → On regarde la vitesse totale.
5. **NaN** possibles dans le swing du grappin → calcul réécrit + garde anti-NaN.

Un diagnostic reste actif : si la vitesse s'effondre encore, la console affiche `[SPEED DROP] …` avec l'état et la collision en cause (désactivable : `debug_speed_drop` sur le Player). Lors des tests, les seuls cas restants étaient des chocs réels (pingouin tiré par le grappin contre un plafond).

## 3. Grappin stabilisé (les modes de traction sont conservés)

- La direction de traction était calculée dans le repère d'un nœud qui **tourne avec le pingouin** : penché à 90°, la traction partait sur le côté. → Calcul en coordonnées globales.
- Le choix « pull » (crochet en dessous) / « swing » (crochet au-dessus) changeait à chaque frame autour de la hauteur du crochet → hystérésis de 48 px.
- `pull_factor` restait bloqué à 2 après un premier appui sur « pull ».
- `Vector2 < Vector2` (comparaison lexicographique) remplacé par une vraie comparaison composante par composante.
- Sorties d'état propres ; si le grappin se décroche tout seul, on sort proprement de l'état grappin.
- Le crochet ne déclenche plus les zones (ligne d'arrivée, boosts) et une accroche collée au joueur (< 40 px) est ignorée.

## 4. Parallax vertical (`src/levels/parallax/VerticalParallax.gd`)

L'horizontal reste géré par Godot exactement comme avant. Le vertical est piloté par script : chaque plan se décale d'une fraction du déplacement de la caméra proportionnelle à sa profondeur (perspective conservée), avec une saturation douce (`tanh`) et un garde-fou qui empêche de voir le vide sous le décor. Les fonds ignorent le zoom de la caméra. Réglages dans l'inspecteur du nœud `ParallaxBackground` de chaque niveau (`vertical_strength`, `max_vertical_shift`, `reference_camera_y`).

## 5. Mort et arrivée

- **Chute** : sous le point le plus bas du décor (+ `fall_death_margin`), ou après `max_fall_time` s de chute rapide, le pingouin réapparaît là où il glissait ~2 s avant, **avec l'élan qu'il avait** (on peut retenter le saut) ; chaque mort successive rembobine un peu plus loin. `respawn_on_death = false` → game over (rechargement du niveau).
- **Arrivée** (`FinishGate.gd`) : la zone n'est plus un carré de 128 px mais une **bande verticale de 6000 px** (franchir la ligne à n'importe quelle altitude compte), avec une sécurité anti-traversée à grande vitesse, un faisceau lumineux pulsant + le texte « ARRIVÉE » visibles de loin, et un petit ralenti de victoire.

## 6. Caméra adaptative (`src/actors/AdaptiveCamera.gd`)

Toutes les 0,2 s, la trajectoire du pingouin est prédite (vitesse + gravité) et le point d'atterrissage cherché par raycasts. La caméra dézoome juste assez pour voir ce point, ou au maximum s'il n'y a rien en vue. Anti-nausée : 4 paliers fixes (1 / 0,8 / 0,65 / 0,5), dézoom rapide mais re-zoom lent et retardé d'1 s, rien ne bouge pendant le grappin. En test : environ un changement de palier toutes les 6 à 9 s, et 70-80 % du temps au zoom normal. Tout est réglable sur le nœud `Camera2D` du Player.

## 7. LevelRandomSpaghetti

Ajouté au menu (le bouton « Spaghetti » existait déjà mais n'avait pas de scène). Le `breakpoint` qui bloquait le niveau est retiré et une ligne d'arrivée couvrant la hauteur de tous les spaghettis est placée à leur extrémité.

## À vérifier manette en main

Les tests ont été faits en simulation (sans écran, entrées scriptées) + captures d'écran : les sensations de glisse, l'intensité de l'amorti d'atterrissage et le rythme du zoom méritent d'être validés en jouant. Remarques :
- Sur les niveaux générés, l'arche décorative au bout de la dernière île (`Arche.tscn`) n'est **pas** une arrivée : la vraie arrivée est dans le half-pipe qui suit. Si les joueurs la confondent, il suffit de remplacer `end_res` par `FinishGate.tscn` dans `sol.gd`.
- Les niveaux Chill (704 / 917) n'ont pas d'arrivée (comme avant).
- `LevelTest2` affiche des erreurs SmartShape « collision_polygon_node_path » : ces chemins étaient déjà faux en Godot 3 (les collisions déjà calculées dans la scène fonctionnent).

---

## 8. Version mobile : boutons tactiles + détection PC / mobile

**Détection** (`src/autoload/Settings.gd`) :
- Au lancement : `Settings.is_mobile_device` est vrai sur Android / iOS ; le jeu démarre alors directement en mode tactile, en plein écran sans bandes noires (aspect `expand`) et en paysage.
- En cours de jeu, le mode suit le dernier périphérique utilisé : toucher l'écran → **TOUCH**, manette → **GAMEPAD**, clavier / vraie souris → **KBD_MOUSE**. Un PC ou une tablette tactile passe donc d'un mode à l'autre automatiquement.
- En mode tactile, les clics souris « émulés » par Godot à partir d'un toucher sont retirés des actions `hook` et `pull` (sinon chaque toucher lançait le grappin) ; ils reviennent dès qu'on retouche clavier/souris.

**Boutons** (`src/ui/touch/TouchControls.gd`, chargé en autoload, donc présent dans tous les niveaux sans modifier les scènes) :
- Gauche : ◀ ▶ (on peut glisser le doigt de l'un à l'autre) et ↺ ↻ pour la rotation en l'air.
- Droite : SAUT, GRAPPIN, TIRER, PUMP, FIGURE ; pause en haut à droite.
- **GRAPPIN = mini-joystick** : un tap tire vers l'avant-haut (visée par défaut) ; appuyer puis glisser tire dans la direction du glissé (une flèche jaune l'affiche). Maintenir le doigt = rester accroché.
- Multi-touch (on peut avancer, sauter et grappiner en même temps). Les boutons restent collés aux bords sur les écrans plus larges que 1024x720.
- Visibles uniquement en mode tactile, dans un niveau, hors pause. Aucun nouvel asset : tout est dessiné en code.
- La caméra décale légèrement la vue (vers le haut et vers l'avant) en mode tactile pour que le pingouin ne passe pas sous les boutons (`touch_view_shift` sur la Camera2D).
- Les écrans titre / fin acceptent aussi un toucher pour continuer.

**Corrigé au passage** : le menu pause (Échap) appelait `SceneTree.set_input_as_handled()`, qui n'existe plus en Godot 4 (erreur à chaque pause).

**Export Android** : preset « Android » ajouté (`export_presets.cfg`) — APK sans Gradle, ARM 32 + 64 bits, Android 7.0 minimum (API 24), paquet `com.pinpouin.leninja`, plein écran immersif, rendu « Compatibility » (OpenGL ES, le plus compatible pour un jeu 2D) et compression de textures ETC2/ASTC activée. L'APK est signé avec une clé de publication dédiée (`pinpouin-release.keystore`, alias `pinpouin`), fournie à part et **jamais commitée** (`*.keystore` dans `.gitignore`). Gardez-la précieusement : toutes les mises à jour de l'appli devront être signées avec la même clé. Pour ré-exporter depuis l'éditeur : Éditeur → Paramètres de l'éditeur → Export → Android (chemin du SDK Android + JDK), puis Projet → Exporter → Android, en renseignant la clé dans la section Keystore → Release du preset.

## 9. Map « bateau » : niveau d'apprentissage (`src/levels/LevelBateau.tscn`)

Premier bouton du menu : **« Tuto : Bateau »**. Il a son propre petit générateur (`src/levels/tutorial/BateauGenerator.gd`) qui réutilise `sol.tscn` et la ligne d'arrivée :
- **une seule piste continue, sans aucun trou**, en légère descente (3,4°), relief doux, sol épais ;
- **graine choisie par calcul** parmi 400 : le départ ne fait que descendre et la pire montée de la piste ne dépasse pas ~3° ;
- **mur invisible au départ** (on ne peut pas tomber en reculant) ;
- **plafond d'entraînement au grappin** au milieu, visible à l'écran mais hors de portée d'un simple saut ;
- **8 panneaux** (avancer, sauter, pump, rotation, grappin, tirer, figure, arrivée) qui affichent les **vraies touches** lues dans les réglages du projet, adaptées au mode (clavier / manette / tactile) et mises à jour en direct. Quand le pingouin passe un panneau, son texte reste **6 s en haut de l'écran** ;
- **ligne d'arrivée** posée sur la piste.

Tests en simulation : sans rien toucher, le pingouin glisse jusqu'à l'arrivée (~32 s) ; avec seulement la flèche droite : 44 s ; avec le pump : 29 s ; 0 mort, et le grappin s'accroche bien au plafond. Tous les réglages (longueur, pente, relief, plafond, arrivée, textes) sont exportés dans `BateauGenerator.gd`.

⚠️ La **figure** (`trix`) n'a **aucun bouton manette** dans les réglages du projet (le panneau l'indique). À choisir.

## 10. Boutons mobiles v2 (13/11)

- **Disposition** (proposition de l'équipe) : **PUMP dans le coin bas-droit** (le plus gros bouton, le plus accessible au pouce), **SAUT juste au-dessus**, GRAPPIN à gauche du PUMP, FIGURE un peu plus loin. À gauche : ◀ ▶ et ↺ ↻ (inchangé).
- **TIRER n'est plus un bouton séparé.** Avant, il fallait maintenir GRAPPIN et appuyer sur TIRER en même temps, deux doigts sur la même zone : impossible en pratique. Maintenant, une fois accroché, on **glisse le doigt loin du bouton GRAPPIN** (plus de 90 px) pour tirer sur la corde. Un cercle pointillé montre la distance à franchir, puis « TIRE ! » et une flèche orange s'affichent pendant qu'on tire. On revient sous 70 px pour arrêter. Un petit glissé de visée ne tire jamais par erreur.
- Positions et seuils regroupés en haut de `src/ui/touch/TouchControls.gd` (`_buttons`, `PULL_DISTANCE`, `PULL_RELEASE`).

## 11. Finition visuelle et menus (13/11, version 1.2)

- **Pixel-art net retrouvé** : en Godot 3, 88 images étaient importées « sans lissage ». Ce réglage d'import n'existe plus en Godot 4, et le lissage par défaut rendait tout le jeu légèrement flou depuis la migration. Le projet utilise maintenant le filtrage « Nearest » par défaut (`rendering/textures/canvas_textures/default_texture_filter`).
- **Caméra** : le dézoom maximal passe de ×0,5 à ×0,7 sur PC et ×0,8 sur mobile (`zoom_levels` / `zoom_levels_mobile`). À ×0,5, le pingouin devenait minuscule.
- **Menu de sélection des niveaux refait** :
  - titre en haut, panneau « COURSES » (tuto en premier, mis en avant) et panneau « CHILL » (étiquette d'origine, dans le bon sens) ;
  - Spaghetti rangé dans les courses, puisqu'il a désormais une arrivée ;
  - bouton Retour et numéro de version ;
  - navigation complète au clavier et à la manette, avec un cadre jaune sur le bouton sélectionné.
  - Le bouton « todo bolo » (sans niveau) est masqué, pas supprimé. L'ancienne scène est archivée dans `_archive_godot3/LevelSelectionScreen_v1_godot4.tscn`.
- **Menu pause** : fond assombri, titre « PAUSE », boutons plus grands en français (Reprendre / Recommencer / Choisir un niveau / Quitter le jeu), focus clavier/manette. « Choisir un niveau » ramène à la sélection des niveaux (avant : écran titre). L'interface passe au-dessus du bandeau du tuto.
- **Touche « retour » Android** : avant, elle fermait l'appli même en pleine partie. Maintenant : pause en jeu, retour au menu précédent dans la sélection des niveaux, et sortie seulement depuis l'écran titre (`application/config/quit_on_go_back = false` + gestion dans `Settings.gd`).
- **Version** affichée dans le menu, lue dans `application/config/version` (1.2).

## 12. Seed de course, chrono, records et fantômes (13/11, version 1.3)

Première brique du multijoueur (étape 5 de la feuille de route). Un nouvel autoload, `src/autoload/RaceManager.gd`, gère :
- **Seed de course** : à chaque chargement de niveau, un seed est choisi, et tout le hasard qui change le terrain en dépend (graines des îles `random_seed` des 3 générateurs, choix des décorations). Même seed = exactement le même terrain (vérifié : mêmes graines d'îles à chaque rejeu).
- **Chrono** en haut à gauche, avec le record du niveau, sur les niveaux avec arrivée seulement. Il s'arrête pendant la pause.
- **Record** : à l'arrivée, un bandeau affiche « NOUVEAU RECORD ! » (avec l'écart) ou « Temps / Record ». Le record s'affiche aussi sur le bouton du niveau dans le menu.
- **Fantôme** : chaque record est enregistré (30 fois par seconde : position, rotation, animation, grappin) dans `user://ghosts/<niveau>.ghost`, environ 16 Ko compressé pour 30 s de course. À la course suivante, un pingouin bleu translucide (« record ») rejoue cette course, sans aucune collision. Testé : avec les mêmes entrées, le fantôme suit le joueur à une image près et le temps est identique au centième.
- **Niveaux à terrain aléatoire** (SlightOffset, Spaghetti) : si un fantôme existe, on court sur SON terrain. Pour un nouveau terrain aléatoire, désactiver « Fantôme » dans le menu.
- **Partage** : sur PC, le bouton « Dossier des fantômes » ouvre le dossier. On y copie le `.ghost` d'un ami (renommé, par ex. `LevelBateau_leo.ghost`) : le plus rapide des fantômes du dossier pour un niveau est celui qui court, sur son terrain.
- **Menu** : interrupteur « Fantôme » (mémorisé dans `user://pinpouin.cfg`), records sur les boutons de course.

## 13. Multijoueur en réseau local (13/11, version 1.4)

Étape 6 de la feuille de route : des courses à plusieurs, en temps réel, sur le même Wi-Fi (jusqu'à 8 joueurs). Pas de serveur à héberger : un des joueurs crée la partie.

- **Menu** : nouveau bouton « Multijoueur » en bas de la sélection des niveaux → **salon** (`src/screens/MultiplayerLobby.tscn`).
  - Champ « Ton nom », mémorisé.
  - « Créer la partie » : le panneau devient le SALON, avec l'adresse IP de l'hôte, la liste des joueurs (★ = hôte), le choix de la course et « Lancer la course ».
  - « Rejoindre » : les parties du même Wi-Fi apparaissent toutes seules (un bouton par partie). On peut aussi taper l'adresse IP de l'hôte (utile si le réseau bloque la découverte).
- **Course** :
  - Tout le monde charge le même niveau avec **le même seed**, donc le même terrain.
  - Les pingouins sont figés jusqu'à ce que tous soient prêts, puis un **compte à rebours 3-2-1-GO** démarre pour tous en même temps.
  - Chacun voit **les autres pingouins en direct**, colorés, avec leur nom et leur grappin. Ils se traversent : pas de collision entre joueurs.
  - Le **classement** s'affiche en haut à droite et se remplit à chaque arrivée.
  - À l'arrivée, un bandeau affiche la **place** (« 1re place ! ») et le temps.
  - Quand tout le monde est arrivé (ou 45 s après le premier), tous reviennent au salon. Le classement de la course y reste affiché et on peut relancer.
- **Pause en multijoueur** : le jeu ne s'arrête pas (les autres continuent). « Recommencer » est masqué, puisque la chute fait déjà réapparaître le pingouin. « Choisir un niveau » devient « Quitter la course ».
- **Déconnexions** :
  - Si un invité part, la course continue sans lui.
  - Si l'hôte part, les invités reviennent au salon avec le message « L'hôte a quitté la partie ».
  - Une partie refuse un joueur qui a une autre version du jeu, ou qui arrive pendant une course.
- **Technique** :
  - Nouvel autoload `src/autoload/NetSession.gd` : ENet sur le port 47230, annonces UDP sur le port 47231 une fois par seconde.
  - Chaque appareil simule son propre pingouin, donc **aucune latence sur ses commandes**. Il envoie son état 20 fois par seconde.
  - Les autres sont affichés avec 100 ms de retard volontaire, interpolés, pour rester fluides (`src/ui/race/RemotePenguin.gd`).
  - `RaceManager` impose le seed de l'hôte, désactive le fantôme et gère le compte à rebours.
  - `RaceHud` affiche le décompte et le classement.
- **Android** : permissions réseau ajoutées à l'export (internet, état du réseau / Wi-Fi, multidiffusion Wi-Fi).
- **Testé** avec deux jeux qui se connectent l'un à l'autre :
  - découverte automatique, puis connexion par IP ;
  - départ synchronisé et même terrain (même seed des deux côtés) ;
  - pingouins distants visibles et fidèles ;
  - classement identique des deux côtés, retour au salon, deux courses d'affilée ;
  - départ d'un invité et de l'hôte en pleine course.
- **Limites connues** :
  - Les records battus en multijoueur sont aussi enregistrés comme records solo, avec leur fantôme.
  - Certains Wi-Fi (entreprise, école, réseau invité) isolent les appareils : ni découverte ni connexion possible. Un partage de connexion depuis un téléphone marche en général.
  - Sur certains Android, la découverte automatique peut ne rien trouver. Taper l'IP fonctionne quand même.
  - Deux jeux sur le même PC : seul le premier voit les annonces, l'autre peut rejoindre via `127.0.0.1`.

## 14. Score (temps + figures) et caméra qui regarde devant (14/11, version 1.5)

**Score** : `SCORE = points de vitesse + points de figures`.
- **Points de vitesse** : 60 000 ÷ le temps en secondes (30 s → 2000 points). Plus on arrive vite, plus on en a. Constante `SPEED_POINTS` dans `RaceManager.gd`.
- **Points de figures**, comptés par `src/ui/race/TrickScore.gd`, qui observe la machine à états du pingouin sans la modifier :
  - **figure réussie** (son animation va jusqu'au bout) : +100 (Toupie, Boule, Étoile ninja, Carpe) ;
  - **vrille** (un tour complet en l'air avec les touches de rotation, hors grappin) : +150 par tour ;
  - **combo** : plusieurs éléments dans le même saut multiplient le total du saut (×2, ×3… jusqu'à ×5) ;
  - les points d'un saut sont **en jeu** pendant le vol. On les gagne à l'atterrissage, ou en passant l'arrivée en l'air. On les perd si on touche le sol en pleine figure (« Raté ! ») ou si on tombe dans le vide (« Chute… »).
  - Le barème est regroupé dans les constantes `TRICK_POINTS`, `SPIN_POINTS` et `MAX_COMBO`.
- **À l'écran** :
  - sous le chrono, le total des figures ;
  - en bas au centre, les figures en jeu (« Boule + Vrille ×2 »), puis « +500 COMBO ×2 » en jaune ou « Raté ! » en rouge ;
  - à l'arrivée, « Vitesse … + Figures … / SCORE … » et le meilleur score du niveau.
- Le **meilleur score** de chaque niveau est mémorisé dans `user://pinpouin.cfg` et affiché sur les boutons de course. Le record de **temps** et son fantôme ne changent pas.
- **Multijoueur** : le classement se fait au score (à égalité, au temps). Le temps reste affiché entre parenthèses. Une version 1.4 et une version 1.5 ne peuvent pas jouer ensemble.
- **Tuto Bateau** : un panneau « SCORE = vitesse + figures » au départ. Le panneau des rotations explique la vrille, celui des figures leurs points et le risque de les perdre, et un nouveau panneau explique les combos.
- **Testé en simulation** :
  - figures validées (+100 chacune) ;
  - figure non finie à l'atterrissage : points perdus ;
  - vrilles et combo ×2 (+600) sur « Hook, you fool ! » ;
  - points perdus en tombant ;
  - score envoyé et classé en multijoueur.
- ⚠️ **Sur le tuto, les sauts sont courts** (moins d'une seconde) : une figure passe, mais une vrille complète ou un combo demande un grand saut. Les panneaux le précisent.

**Caméra** (`AdaptiveCamera.gd`, nouveaux réglages dans l'inspecteur, groupes « Regard vers l'avant » et « Dézoom au-dessus des trous ») :
- **Regard vers l'avant** : plus le pingouin va vite, plus la vue avance. À pleine vitesse, il est à environ 25 % du bord gauche de l'écran (mesuré : 25-27 % à 1000 px/s). Avant, c'était l'inverse : le lissage de position de Godot faisait traîner la caméra, et le pingouin se retrouvait à droite. Le lissage intégré est maintenant coupé à l'horizontale, et c'est le décalage d'avance qui est lissé, avec une courbe douce et sans à-coup aux demi-tours. En chute, la vue descend un peu.
- **Au-dessus d'un trou** (aucun atterrissage prévu sur la trajectoire) :
  - la caméra lance 32 rayons autour du pingouin, à la portée du grappin (1200 px, `distance_max` de `Chain.gd`) ;
  - elle se recentre et dézoome pour montrer toutes les prises trouvées, jusqu'à un palier spécial ×0,55 (×0,65 sur mobile), utilisé uniquement dans ce cas ;
  - le pingouin reste toujours à l'écran, et le zoom garde les règles anti-nausée (paliers, re-zoom lent et retardé, rien ne bouge pendant le grappin).
- **Correction au passage** : le décalage tactile passait par `position`, qui tournait avec le pingouin pendant les vrilles. Il passe maintenant par `offset`, qui ne tourne pas. Le petit décalage de ±20 px de `Player._process` est remplacé par le regard vers l'avant (l'ancien code est conservé si `look_ahead_enabled = false`).

## 15. Multijoueur par Internet, sans serveur : code de partie (14/11, version 1.6)

Choix de l'équipe : pas de serveur à payer ou à gérer. C'est l'hôte qui ouvre la porte de sa box.

- **Côté hôte** :
  - dans le salon, après « Créer la partie », un bouton **« Ouvrir sur Internet »** ;
  - le jeu demande alors à la box d'ouvrir le port UDP 47230 vers cet appareil (protocole **UPnP**, classe `UPNP` de Godot) et récupère l'adresse Internet de la box ;
  - un **code de partie** de 8 signes s'affiche (ex. `KKEA-DAHQ`), avec un bouton « Copier ». Il suffit de l'envoyer aux amis par message.
- **Côté invités** : on tape le code dans le champ de « Rejoindre », qui accepte un code ou une adresse IP. Ensuite, tout est identique au Wi-Fi : salon, compte à rebours, pingouins en direct, score, classement.
- **Le code** contient l'adresse Internet de la box de l'hôte.
  - Il n'utilise que des signes sans ambiguïté (ni I/1 ni O/0) et ignore les majuscules et minuscules.
  - Un signe de contrôle détecte toute faute de frappe sur un signe : testé sur 5000 fautes, toutes détectées.
  - Fonctions `ip_to_code()` et `code_to_ip()` dans `NetSession.gd`.
- **En quittant**, le port est refermé sur la box.
- **Sans blocage** : la discussion avec la box (1 à 5 s) se fait en tâche de fond, le jeu ne se fige pas.
- **Messages clairs en cas d'échec** :
  - box sans UPnP, ou UPnP désactivé ;
  - connexion 4G ou adresse partagée (« CGNAT ») ;
  - port refusé ;
  - côté invité : code invalide, ou connexion impossible (« vérifie le code et que l'hôte a bien ouvert la partie »).
- **Par Internet**, les autres pingouins sont affichés avec 150 ms de marge au lieu de 100 ms, pour rester fluides malgré une connexion moins régulière.
- **Testé ici** :
  - codes : 20 000 adresses converties aller-retour sans erreur ;
  - connexion par code entre deux jeux (code de 127.0.0.1), avec une course complète ;
  - échec UPnP : message affiché, et la partie en Wi-Fi continue normalement ;
  - non-régression du multijoueur en Wi-Fi.
- ⚠️ **À tester en vrai** : il n'y a pas de box dans l'environnement de test. L'ouverture du port n'a donc pas pu être essayée sur une vraie box.
- **Limites** :
  - l'**hôte** doit être sur une box qui accepte l'UPnP. C'est souvent activé par défaut, sinon il faut l'activer dans l'interface de la box ;
  - l'hôte ne peut pas être en 4G ni derrière un CGNAT ;
  - les **invités** peuvent être n'importe où, 4G comprise.
  - Si personne ne peut héberger, il faudra un relais (noray ou GD-Sync, notés dans la feuille de route).
- **Si l'UPnP ne marche pas** mais que l'hôte ouvre lui-même le port UDP 47230 dans sa box, les invités peuvent taper directement son adresse IP publique à la place du code.

## 16. Aide, options, tremplins et partage de fantômes (14/11, version 1.7)

- **Pause pour lire dans le tuto** (demande de l'équipe) :
  - quand le pingouin arrive à un panneau, le jeu se met en pause et le texte s'affiche en grand au centre ;
  - on repart avec n'importe quelle touche, bouton de manette, clic ou toucher. Les appuis des 0,4 premières secondes sont ignorés pour éviter de fermer par erreur, et les touches maintenues (avancer) restent maintenues ;
  - le chrono s'arrête pendant la lecture : lire ne coûte pas de temps ;
  - à la reprise, le texte reste 6 s en haut de l'écran, comme avant ;
  - c'est `src/ui/ReadingPause.gd`. Il n'y a jamais de pause en multijoueur.
- **Aide en début de niveau** :
  - au départ de chaque niveau, une carte « C'EST PARTI ! » rappelle les commandes, avec les vraies touches du périphérique utilisé, et le principe du score, jeu en pause ;
  - pas sur le tuto, dont les panneaux expliquent déjà tout ;
  - désactivable : « Aide en début de niveau » dans les Options.
- **Écran Options** (bouton « Options » dans la sélection des niveaux, `src/screens/OptionsScreen.tscn`) :
  - aide en début de niveau, pause de lecture du tuto, course contre son fantôme, volume de la musique ;
  - tout est mémorisé dans `user://pinpouin.cfg` (`Settings.set_option`).
- **Échanger des fantômes, téléphone compris** :
  - « Copier » transforme son record en texte (environ 19 Ko pour 25 s) à coller dans un message (WhatsApp, SMS, Discord…) ;
  - l'ami copie le message en entier et clique sur « Coller le fantôme d'un ami » : le fantôme est vérifié puis ajouté (`RaceManager.export_ghost_text` / `import_ghost_text`) ;
  - un texte coupé, abîmé ou d'une autre version est refusé avec un message clair ;
  - le texte collé ne peut contenir que des données, jamais de code.
- **Tuto : 2 tremplins d'entraînement** après le plafond du grappin :
  - ils donnent environ 2 s de vol, assez pour une vrille ou un combo ; le sol continue dessous, donc aucun risque ;
  - un panneau les annonce et explique les combos ;
  - en simulation : une vrille validée à chaque saut (+150).
- **Bouton manette pour la figure** : croix directionnelle haut. Les panneaux et l'aide l'affichent tout seuls.
- **Corrigé au passage** : un nœud ajouté par code à la racine de l'arbre était pris pour un changement de scène par `RaceManager`, ce qui coupait le chrono. Seules les vraies scènes comptent maintenant.

## 17. Fond infini qui suit le niveau (14/11, version 1.8)

Demande de l'équipe : plus de coupure nette du fond, une boucle infinie qui suit les pentes et s'adapte à la forme du niveau. Tout est dans `src/levels/parallax/VerticalParallax.gd`, aucune image n'est modifiée.

- **Boucle horizontale infinie** : chaque plan se répète tous les 3200 px (largeur de l'image × échelle du sprite, `motion_mirroring`). Avant, les plans s'arrêtaient au bout de leur région de 70 000 px.
- **Plus de bords nets** :
  - le bas du ciel était coupé en ligne droite par la région du sprite (ligne 180 de l'image, alors que le dessin descend jusqu'à 200 avec un bord ondulé). La région est maintenant rallongée jusqu'au bord naturel du dessin, sans rien déplacer ;
  - le ciel est prolongé vers le haut avec sa couleur dominante ;
  - le glacier, qui est le plan le plus au fond (`z_index` -126), est prolongé vers le haut (brume) et vers le bas (sa dernière ligne étirée : les falaises continuent).
  - Ces prolongements sont des `Sprite2D` enfants, dessinés derrière l'image d'origine (`show_behind_parent`).
  - Les plans de devant ne sont pas prolongés vers le bas : ils cacheraient le glacier.
- **Le fond suit les pentes** :
  - la composition est fixe à l'écran : ciel et montagnes en haut, glacier en bas, avec le bas du glacier calé sur le bas de l'écran (`anchor_offset` pour la décaler) ;
  - la hauteur de référence suit la caméra en douceur (`follow_time` = 3 s) : sur une longue descente, le fond accompagne le niveau au lieu de rester en butée ;
  - les mouvements rapides (sauts, chutes, grappin) font toujours bouger les plans selon leur profondeur ;
  - l'ancien garde-fou « anti-vide », qui recalait le décor par à-coups, n'est plus nécessaire quand les images sont prolongées. Il reste actif si `extend_vertically` est coupé.
- **Réglages** (inspecteur du nœud `ParallaxBackground` de chaque niveau) : `infinite_horizontal`, `extend_vertically`, `follow_time`, `anchor_offset`, `extension_rows`, en plus des anciens.
- **Vérifié** sur Spaghetti, Nice Slope et le tuto, en courant tout le niveau : composition cohérente partout, aucun vide (couleur de fond de la fenêtre) détecté à l'écran.
- **Note** : l'ordre d'affichage des plans dépend de leur `z_index` dans les scènes (glacier -126 au fond, nuages -123, montagnes -120 devant), pas de leur ordre dans l'arbre.

## 18. Corrections après les tests de la 1.8 (14/11, version 1.9)

- **Menu pause absent dans Chill 917** : le niveau n'avait pas l'interface (`UserInterface.tscn`). Elle est ajoutée ; Échap, la manette et le bouton pause tactile fonctionnent.
- **Niveaux Chill vraiment infinis** (`src/levels/ChillLoop.gd`, nœud « BoucleInfinie » dans 704 et 917) :
  - au bout du terrain, Pinpouin tombait dans le vide ; la réapparition le relançait au même endroit, avec son élan, et il retombait en boucle ;
  - maintenant, le terrain (sols + boosts) est recopié bout à bout, la fin de chaque copie raccordée au début de la suivante. Deux copies sont toujours prêtes devant le pingouin, et celles laissées derrière sont supprimées ;
  - la limite de « chute infinie » suit le terrain qui descend ;
  - testé : passage du raccord sans choc ni mort, sur 704 et 917.
- **Pinpouin qui s'enfonce dans le sol (Chill 704)** :
  - les sols générés n'ont qu'un contour de collision (correction du bug vitesse → 0), donc un intérieur creux ;
  - un sol fait ~40 px d'épaisseur et le pingouin 20 px de haut. Dans 704, il apparaissait 20 px sous la surface et glissait sur le bord intérieur, dans la glace ;
  - `Player._unstick_from_ground()` le remonte maintenant sur la surface s'il se retrouve à l'intérieur d'un sol. Sur 5 niveaux testés, le cas ne se produit qu'au départ de 704 ;
  - au passage, la bordure texturée des sols retournés (pistes du haut de 704) dépassait de ~60 px au-dessus de la vraie surface : corrigé dans `sol.gd`.
- **Écran d'accueil sur mobile** :
  - les 5 images de l'écran (carrés de 256 px superposés) n'étaient pas agrandies de la même façon : le titre « couvrait » l'écran, le bouton « tenait » dans l'écran. Sur un téléphone, le bouton tombait sur le titre ;
  - `MainScreen.gd` les place maintenant toutes au même endroit, à la même taille, pour que pingouin, titre et bouton tiennent toujours dans l'écran ;
  - vérifié en 1024 × 720, 1280 × 720, 2400 × 1080 (téléphone 20/9) et 2048 × 1536 (tablette).
- **Fond « veines grises qui bougent à peine »** (régression de la 1.8) :
  - les prolongements des images étiraient une ligne de pixels : cela faisait de longues traînées. Ce sont maintenant des aplats unis de la couleur du bord ;
  - **échelle uniforme** : les images étaient agrandies ×10 en largeur et ×5 en hauteur, ce qui écrasait le pixel-art en traînées horizontales. Elles sont maintenant agrandies ×5 dans les deux sens : vrais sommets de montagnes, falaises du glacier lisibles ;
  - **vitesses de défilement par profondeur** : glacier au fond 0,2, nuages 0,35, montagnes devant 0,5, au lieu de 0,7 à 0,9 où les fonds défilaient presque aussi vite que la piste. L'effet vertical est un peu renforcé ;
  - réglages `readable_parallax`, `parallax_speeds` et `readable_vertical_strength` sur le `ParallaxBackground` de chaque niveau. `readable_parallax = false` remet l'ancienne échelle.

## 19. Physique : pump, vitesses max, panneau de réglage (14/11, version 1.10)

**Ce que les mesures ont montré** (pingouin lancé à 1500 px/s sur le tuto, 3 s) :

| Touches | 1.9 | 1.10 |
|---|---|---|
| rien | 1500 → 1600 | identique |
| avancer | 1500 → **700** | 1500 → 1600 |
| pump (après un atterrissage rapide) | 1500 → **980 d'un coup** | ~1480, entretenu |
| pump depuis 600 | plafonne à 980 | 1450 en 1,5 s |

- **« Avancer » freinait.** `CanMoveState` ramenait toujours la vitesse vers `running_speed` (500), au sol comme en l'air. Maintenant, avancer accélère jusqu'à 500 mais ne freine jamais un pingouin plus rapide dans le même sens. Appuyer dans le sens opposé freine toujours.
- **Le pump plafonnait à 980 px/s** (`max_speed × 1,4`, dans `PumpState`), d'où la perte de vitesse après un saut. Le nouveau pump (l'ancien calcul est gardé en commentaire) :
  - il accélère le long du mouvement : `pump_accel` (450 px/s²) sur le plat, plus `gravité × pente × pump_slope_bonus` en descente, et seulement `pump_uphill_factor` (35 %) en montée ;
  - il s'arrête d'accélérer à `pump_max_speed` (1450), mais ne fait jamais perdre de vitesse ;
  - chaque nouvel appui donne une impulsion de `pump_impulse` (+90 px/s) : c'est la sensation de boost.
- **Vitesses max « douces »** : au-delà de `ground_max_speed` (1450) au sol et de `air_max_speed` (1750) en l'air, on perd chaque seconde une part de l'excédent (`over_speed_drag`). Il n'y a plus de coupure brutale. Le grappin garde son propre plafond (`MAX_SPEED_HOOKED`).
- **Sensation de vitesse** : une traînée blanche apparaît derrière le pingouin au-delà de 1200 px/s (`speed_trail_from`, 0 = jamais).
- **Résultat sur un parcours type** (avancer + pump 1 s sur 2 + sauts, 20 s) :

| Niveau | Vitesse moyenne 1.9 | Vitesse moyenne 1.10 |
|---|---|---|
| Tuto | 759 px/s | 1233 px/s |
| Nice Slope | 925 px/s | 1504 px/s |
| Spaghetti | 821 px/s | 1227 px/s |

  Les réglages ont été choisis parmi 4 jeux d'essai, pour aller environ 1,6 fois plus vite sans dépasser ~2000 px/s. Graphique : `vitesse_avant_apres_1.10.png`.
- **Panneau de réglage** (`src/autoload/PhysicsTuner.gd`) :
  - **F2** en jeu ; en tactile, le bouton ⚙ s'active dans Options (« Panneau de réglage physique ») ;
  - 12 curseurs appliqués tout de suite et mémorisés (`user://pinpouin.cfg`, section « physique ») ;
  - courbe de vitesse des 10 dernières secondes ;
  - « Par défaut » remet les valeurs d'origine, « Copier » met tous les réglages en texte, à partager avec l'équipe pour les mettre par défaut dans le jeu.
- **Non-régression** : 7 niveaux × 2 modes de jeu automatiques, aucune chute brutale de vitesse et aucune mort inattendue. Le multijoueur est OK.
- ⚠️ **Équilibrage à vérifier** : sur « Hook, you fool ! », la simulation qui ne fait qu'avancer passe maintenant les trous sans grappin (avant : 3 morts au premier trou). Si ce niveau doit obliger à utiliser le grappin, il faudra élargir les trous ou baisser les vitesses max.
- Les records et fantômes faits avec l'ancienne physique restent rejouables, mais ils seront faciles à battre.

## 20. Grappin tactile : toucher l'écran = viser là (14/11, version 1.11)

- **Problème** (retour de test de la 1.8) : sur mobile, un appui sur le bouton GRAPPIN tirait toujours à 45° vers l'avant. On pouvait viser en glissant depuis le bouton, mais c'était peu pratique et peu compris.
- **Maintenant** (`src/ui/touch/TouchControls.gd`) :
  - **toucher n'importe où dans la zone de jeu**, hors boutons, lance le grappin **vers le point touché**. La direction est calculée dans le monde, en tenant compte du zoom et du décalage de la caméra ;
  - **maintenir le doigt** : rester accroché ; **relever** : se décrocher ;
  - une fois accroché, **glisser ce doigt loin** du point touché (au-delà de 90 px) fait **tirer** sur la corde, comme avec le bouton ;
  - une petite cible jaune marque le point touché, avec le cercle « glisse loin = TIRER » autour ;
  - le bouton GRAPPIN marche toujours comme avant (tap = avant-haut, glissé = direction) ;
  - un toucher sur le panneau de réglage physique (⚙) ne lance pas le grappin ;
  - `free_aim_enabled = false` remet le comportement de la 1.10.
- **Textes en tactile** : les panneaux du tuto et la carte d'aide disent maintenant « le doigt sur l'endroit visé » pour le grappin et « le doigt et glisse-le loin » pour tirer.
- **Testé** en simulant des doigts :
  - visée à 20°, 60°, 70°, 100° et 110° : le grappin part dans la bonne direction, à quelques degrés près (le pingouin avance pendant le tir) ;
  - sous le plafond du tuto, il s'accroche ; doigt relevé, il se décroche.
- **À tester sur un vrai téléphone** : le confort du geste, et vérifier qu'on ne lance pas le grappin par erreur en visant mal un bouton. Les boutons gardent une zone de toucher un peu plus large que leur dessin.

## 21. « Hook, you fool ! » : prises d'accroche centrées sur les trous (14/11, version 1.12)

- **Demande** : avoir les endroits où utiliser le grappin au centre des trous ; le premier était beaucoup trop à gauche.
- **Mesure sur la 1.11** :

| Trou | Bords | Centre | Prise(s) 1.11 | Prise(s) 1.12 |
|---|---|---|---|---|
| 1 | 19136 → 20264 | 19700 | 19214 (au bord) | **19700** |
| 2 | 39400 → 41628 | 40514 | 40328 | **40514** |
| 3 | 60764 → 63492 | 62128 | 62192 | **62128** |
| 4 | 82628 → 85356 | 83992 | 83356 et 84356 | **83537 et 84447** (aux tiers) |
| 5 (avant le half-pipe) | 104492 → 106620 | 105556 | 105620 et 106620 (sur le bord du half-pipe) | **105201 et 105911** (aux tiers) |

- **Cause** (`GroundGeneratorBlock.gd`) : la position des prises était calculée avec `gap[i]`, alors que le trou réellement creusé avant l'île i vaut `gap[i-1] + 64` (`sum_gap(i)` n'additionne que les trous 0 à i-1).
- **Correction** :
  - les îles ne bougent pas, donc même niveau et fantômes toujours valables ;
  - les prises sont maintenant réparties sur la largeur réelle de chaque trou, de la fin de l'île précédente au début de la suivante. Le nombre de prises par trou ne change pas.
- **Effet de bord voulu** : la simulation qui ne fait qu'avancer, sans grappin, retombe maintenant dans le premier trou. Le niveau redemande donc le grappin, ce qui répond aussi à la remarque de la 1.10 (« on passe les trous sans grappin »).

## 22. Équilibrage des scores + arrivée du half-pipe (14/11, version 1.13)

- **Mesure sur la 1.12** (bots `vitesse` = avancer + pump, `mixte` = + un saut/figure toutes les 3 s) : avec l'ancien barème `60 000 / temps`, la vitesse valait 3140 pts sur le Bateau (19 s) mais seulement ~900 pts sur les niveaux longs (66 s) ; les figures (100 à 150 pts) écrasaient tout sur les longs niveaux, même en arrivant 30 s plus tard.
- **Nouveau barème** (`RaceManager.speed_points(time, reference)`) :
  - temps de référence = distance départ → arrivée ÷ `REF_SPEED` (1250 px/s, vitesse moyenne mesurée) ;
  - points de vitesse = `SPEED_BASE` (3000) au temps de référence, ± `SPEED_PER_SECOND` (100) par seconde d'avance / de retard, jamais négatif ;
  - figures inchangées → règle simple : **1 seconde = 100 points = 1 figure**.
- **Meilleurs scores** : nouvelle section de config `scores_v2` (l'ancienne `scores` est ignorée, pas supprimée) ; les records de temps sont conservés.
- **Textes** : panneau SCORE du tuto, aide de début de niveau, écran de résultat (affiche le temps de référence).
- **Résultats 1.13** :

  | Niveau | vitesse | mixte |
  |---|---|---|
  | Bateau | 19.08 s → 3020 | 21.77 s → 2750 + 600 = 3350 |
  | Flat | 65.80 s → 3210 | 68.97 s → 2890 + 1900 = 4790 |
  | Corridor | 67.05 s → 3010 | 94.93 s → 230 + 2100 = 2330 |
  | Spaghetti | 32.60 s → 3060 | — |
  | Nice Slope | 53.53 s → 4370 | — |

  Des figures qui ne coûtent presque pas de temps rapportent gros ; des figures qui font perdre 28 s font perdre la course.
- **Bug trouvé au passage (Nice Slope)** : sans grappin, le pingouin pouvait rester collé en haut du mur vertical du half-pipe final, à 274 px de l'arche posée sur le deck. `FinishGate.trigger_offset_x` (nouveau, 0 par défaut) permet de décaler la ligne de détection : `HalfPipe` la descend au milieu de la courbe de droite et allonge la bande vers le bas. L'arche ne bouge pas.

## 23. Écran titre, multijoueur et interface responsive (14/11, version 1.14)

- **Écran titre « appuie pour jouer »** : sur téléphone, les boutons de volume le faisaient passer (Android les envoie comme des touches). Nouveau tri commun `Settings.is_continue_press()` : sur téléphone, seul un toucher (ou un bouton de manette) compte ; sur PC, toute touche sauf volume / média. Utilisé par l'écran titre, l'écran de fin et la pause de lecture du tuto. Au passage, une touche de volume en pleine course faisait passer en mode « clavier » et **cachait les boutons tactiles** : corrigé (`Settings.is_system_key`).
- **Attente avant le décompte** (multi) : Pinpouin était figé en l'air au départ, la corde du grappin plantée dans le sol (le grappin ne se cache que dans son propre `_process`, qui ne tournait pas). Il est maintenant posé sur la piste, incliné comme la pente, grappin caché (`RaceManager._freeze_player_for_start`), et un panneau « En attente des autres joueurs — 1 / 2 prêts — on attend Léo » s'affiche. L'hôte renvoie la liste à chaque joueur prêt.
- **Flèches vers les autres joueurs** (`src/ui/race/PlayerArrows.gd`) : chaque joueur hors écran a une flèche à sa couleur sur le bord gauche ou droit, à sa hauteur, avec son nom et l'écart en mètres (+ devant, − derrière). Le joueur juste devant et celui juste derrière ont une flèche plus grosse. `only_neighbours = true` n'affiche que ces deux-là. En tactile, les flèches restent dans la moitié haute (au-dessus des boutons).
- **Interface responsive** :
  - plus de bandes noires sur PC : l'écran s'étend dans les deux sens (`aspect = expand`, comme sur téléphone) ;
  - taille de l'interface automatique selon la hauteur physique de l'écran (`Settings.auto_ui_scale` : ×1 sur PC et tablette, jusqu'à ×1,4 sur un petit téléphone), multipliée par le nouveau réglage **« Taille de l'interface »** des Options (80 à 150 %) ;
  - menus : agrandis autant que possible sans que rien ne déborde (calcul sur la taille minimale du contenu, revérifié 2 fois par seconde : le salon grandit avec les joueurs). Le grand titre de la sélection des niveaux se réduit si l'écran est peu haut ;
  - en jeu : HUD, menu pause et pause de lecture agrandis via `src/ui/UiScaler.gd` (les ancrages restent justes). La vue du jeu elle-même ne change pas.
- **Vérifié** en captures : PC 1024 × 720, fenêtre large 1900 × 700, fenêtre haute 900 × 1100, téléphone 2400 × 1080 (menus, salon, attente, flèches, pause). Course réseau à 2 et course solo inchangées.

## 24. Écran de démarrage Pinpouin (14/11, version 1.15)

- **Demande** : remplacer le logo Godot du lancement par une image de Pinpouin qui se prépare. Sur 4 propositions, l'équipe a gardé la n° 4 et la n° 1, **affichées à la suite** :
  1. **pendant le chargement** (écran de démarrage du moteur, réglages `application/boot_splash/*`) : logo « Pinpouin le ninja » et Pinpouin sur fond bleu nuit (`sprites/screens/splash_boot_nuit.png`, 1920 × 1080). Fond uni de la même couleur que la bordure : il tient sur tous les formats d'écran. Filtre coupé (pixel-art net) ;
  2. **puis l'intro** (`src/screens/SplashIntro.gd`, lancée par `MainScreen.gd`) : fondu depuis la même couleur nuit vers « Pinpouin prêt au départ » — debout sur la banquise, sa corde et son grappin à ses pieds, igloo et glaçons (`sprites/screens/splash_intro_banquise.png`) — 1,5 s, puis fondu vers l'écran titre. Un appui la passe ; jouée une seule fois par lancement.
- Les deux images sont des **montages des sprites existants** (logo, Pinpouin, igloo, glaçons, grappin, fond) ; seuls la corde enroulée et le sol de glace sont dessinés en pixels. Aucun asset d'origine n'est modifié.
- L'image d'intro fait 432 × 180 pixels (plus large que le 16/9) et s'affiche en « remplir l'écran » : sur un téléphone allongé (20/9), ni bandes ni logo coupé.
- La scène principale reste `MainScreen.tscn`.

## 25. Choix des flèches en multi (14/11, version 1.16)

- **Options → « Flèches des joueurs (multi) »** : *Toutes* (défaut), *Devant et derrière seulement* ou *Aucune*. Mémorisé dans `user://pinpouin.cfg` (`Settings.player_arrows`).
- **Mode « devant et derrière »** : seul le joueur le plus proche devant et le plus proche derrière ont une flèche. Cas des bords : le 1er de la course n'a personne devant, il ne voit que la flèche de son poursuivant ; le dernier ne voit que celle du joueur qui le précède. Vérifié en captures (milieu de peloton, en tête, mode Aucune).
- Décisions de l'équipe : disposition actuelle des boutons tactiles validée par Léo ; point « banquise » clos.

## 26. Version navigateur pour itch.io + jeu plus léger (14/11, version 1.17)

- **Export Web** (preset « Web » ajouté, sans threads : marche sur itch.io sans réglage spécial). Dans le navigateur (`Settings.is_web`) : bouton Multijoueur masqué (ENet / UDP indisponibles), boutons « Dossier des fantômes » et « Quitter le jeu » masqués. Les fantômes et options sont gardés par le navigateur. Testé dans Chrome : démarrage, menus, course complète.
- **Symboles ★ ◀ ▶ ⚙ ↺ ↻** : dans le navigateur, ils s'affichaient en petits rectangles (pas de police système). Ajout de la police libre **DejaVu Sans** (`assets/font/`, licence à côté) comme police de secours de Roboto et de la police par défaut (`Settings._add_symbol_font_fallback`).
- **Jeu bien plus léger** : les 2 musiques WAV (58 Mo) sont maintenant compressées à l'import en **QOA** (réglage `compress/mode` de leur `.import`, fichiers d'origine intacts) → 11,7 Mo, qualité quasi identique. Les fichiers d'éditeur de l'extension SmartShape (thème d'interface 7,7 Mo, documentation) ne sont plus exportés dans le jeu. Données du jeu : 67 Mo → 13,7 Mo.
- **Kit itch.io** : captures, GIF de gameplay, image de couverture 630 × 500, texte de la page (doc projet `claude/page-itch-io.md`).

## 27. Arrivée sur l'arche, vrilles plus tolérantes (15/11, version 1.18)

- **Arrivée sur l'arche** (retour de l'équipe : « le niveau finit dans le half-pipe et pas dans la petite arche prévue à cet effet ») : la ligne d'arrivée est maintenant posée sur l'arche du bout de la dernière île (`sol.gd`, `_add_finish_at_arch`) — une FinishGate invisible au même endroit, avec son faisceau « ARRIVÉE » ; l'arche d'origine reste le visuel. Le half-pipe ne pose plus sa propre arrivée quand celle-ci existe (il reste en fin de niveau). Concerne Flat and fun, Corridor, Nice Slope, Hook you fool !, SlightOffset ; Tuto et Spaghetti inchangés. Le temps de référence du score se recalcule tout seul (distance plus courte). Testé : arrivée franchie sur Flat (62 s), Nice Slope (52 s), Corridor (62 s).
- **Vrilles** : un tour complet compte à partir de 320° (tolérance `SPIN_TOLERANCE_DEG = 40` dans `TrickScore.gd`), pour les saltos un peu courts, surtout au départ d'une pente montante.
- **Meilleurs scores** : ils sont bien sauvegardés d'une version à l'autre. Ils avaient été remis à zéro une seule fois, volontairement, en 1.13 (changement de barème, section `scores_v2`). Pas de nouvelle remise à zéro en 1.18 : les anciens meilleurs scores restent affichés, même si l'arrivée plus proche rend les nouveaux temps plus courts.

## 28. Le maître ninja fait un clin d'œil + tolérance des vrilles à 20° (15/11, version 1.19)

- **Vrilles** : tolérance ramenée à 20° (un tour compte à partir de 340°), valeur validée par l'équipe (40° était trop généreux).
- **Clin d'œil du maître ninja** (`src/ui/race/MasterWink.gd`) : à chaque figure ou vrille réussie (points validés à l'atterrissage), le maître passe la tête par le bord droit de l'écran, bandeau au vent, fait un clin d'œil et repart (~1,2 s). Désactivable dans **Options → « Clin d'œil du maître ninja »** (`Settings.master_wink`, activé par défaut).
  - Le code d'une ancienne version n'a pas été retrouvé dans l'historique git (aucune branche du dépôt ne le contient). Le dessin du maître, lui, existait : `sprites/screens/bad_penguin_1/2/3.png` (64 × 64, bandeau animé), utilisé par l'écran titre des toutes premières versions puis abandonné. Il est réutilisé tel quel.
  - Une image **ajoutée** : `bad_penguin_wink.png`, copie de `bad_penguin_1` avec un œil fermé.
- **Captures itch.io supplémentaires** : colisée, podium d'arrivée, pump, grappin, figure en l'air, clin d'œil du maître.

## 29. Figures bonus dans le half-pipe d'arrivée (15/11, version 1.20)

- **Demande** : à l'arrivée, avoir encore ~30 s pour faire des figures dans le half-pipe de fin, et que ces points comptent dans le score final.
- **Déroulé** (`RaceManager.finish_race` / `_complete_race`, constante `BONUS_TIME = 30`) :
  1. passer l'arche arrête le chrono : temps, record et fantôme sont fixés tout de suite ;
  2. un bandeau « ARRIVÉE ! 1:02.43 — BONUS HALF-PIPE : 30 s, tes figures comptent encore ! » affiche le compte à rebours ; `TrickScore` continue de compter ;
  3. à 0 s, une figure encore en l'air est validée, puis le score final (vitesse + toutes les figures) est calculé, enregistré et affiché ; retour au menu 4 s plus tard.
- Seulement sur les niveaux avec un half-pipe après l'arrivée (Flat, Corridor, Nice Slope, Hook you fool !, SlightOffset). Tuto et Spaghetti : comme avant. En multijoueur aussi : le score est annoncé aux autres à la fin du bonus (le classement au temps n'est pas touché).
- L'aide de début de niveau le signale (« Après l'arrivée : 30 s de figures BONUS dans le half-pipe ! »).
- **Deux sécurités ajoutées pour le bonus** :
  - un **mur invisible** au bout du deck de droite du half-pipe (`HalfPipe._add_end_wall`) : lancé à pleine vitesse, le pingouin sortait du half-pipe et tombait dans le vide au bout du niveau ;
  - pendant le bonus, une chute (par exemple dans le trou entre la dernière île et le half-pipe) fait **réapparaître sur le deck de gauche du half-pipe** (`RaceManager.bonus_respawn_point`), pas avant l'arrivée.

## 30. Panneau à l'envers dans Chill 704 (15/11, version 1.21)

- **Retour de l'équipe** : dans Chill 704, après la première boucle, un panneau « attention » apparaissait à l'envers sur la piste.
- **Cause** : les pistes du haut de 704 sont des sols retournés (`scale = (-1, -1)`). Leurs décors (panneau, igloo, glaçons…) sont posés sur la face d'origine, qui se retrouve dessous, tête en bas. Dans le niveau d'origine ces sols partent vers la gauche, hors de vue ; recopiés par la boucle infinie (`ChillLoop.gd`), ils arrivent devant le pingouin.
- **Correction** (`sol.gd`, `_is_flipped`) : un sol retourné ne pose plus ni décor ni panneau. Le tirage au hasard des décors est conservé (décor tiré puis libéré) pour que les autres sols gardent exactement les mêmes décors. Seul Chill 704 a des sols retournés ; aucun asset supprimé.

## 31. « Test enfant » : 4 bugs trouvés en jouant n'importe comment (16/11, version 1.22)

- **Demande** : tester le jeu « comme un enfant ».
- **Méthode** : un bot pose de vrais doigts virtuels sur un écran de téléphone simulé (2400 × 1080, paysage). Il tapote partout, garde le doigt collé, appuie sur les boutons au hasard, ne fait plus rien, martèle la pause… 2 profils (« petit » au hasard, « grand » qui a compris ▶) × 5 parties de 4 min sur les 6 courses + 2 parties sur Chill 704/917, soit 68 parties. Outil hors projet (`child_test.gd`).
- **Bugs trouvés et corrigés** :
  1. **L'appli se fermait toute seule** : en tapotant, l'enfant ouvrait le menu pause puis touchait « Quitter le jeu » dans plus d'une partie sur deux (37 parties sur 68). Désormais (`MenuPause.gd`) :
     - « Quitter le jeu » est masqué sur téléphone et tablette (on quitte avec le geste retour / accueil ; iOS interdit d'ailleurs aux applis de se fermer seules) ;
     - « Recommencer », « Choisir un niveau » / « Quitter la course » et « Quitter le jeu » (PC) demandent **deux touchers** : le 1er affiche « Sûr ? Touche encore » en orange pendant 3 s. Les scripts des boutons ne changent pas : leur signal est seulement rebranché derrière la confirmation. En multi, on ne quitte la session réseau qu'à la confirmation.
  2. **Erreur de script à chaque SAUT en l'air** (migration Godot 4) : en Godot 3, le `_ready()` de la classe parente était appelé automatiquement ; en Godot 4 non. `JumpingState`, `TrixState` et `HookingInAirState` n'appelaient pas `InAirState._ready()`, donc `coyote_timer` restait vide : appuyer sur SAUT dans ces états plantait la lecture des commandes de la frame (pump en l'air ignoré). Ajout de `super._ready()` comme dans les états au sol.
  3. **Doigt relevé pendant une pause ignoré** (`TouchControls.gd`) : un doigt posé (grappin lancé, ▶ tenu) au moment où une carte d'aide, un panneau du tuto ou le menu pause apparaît, puis relevé pendant la pause, n'était pas vu : à la reprise le grappin restait « tenu » tout seul. Un doigt connu est maintenant toujours relâché.
  4. **Centaines d'erreurs « slide »** (`TouchControls.gd`) : poser un doigt sur le bouton GRAPPIN pendant qu'un « grappin libre » (toucher dans le décor) était actif faisait planter le glissé de l'autre doigt. Le bouton reprend proprement la main, et relever l'ancien doigt ne décroche plus.
  - Bonus, PC tactile seulement (`Settings.gd`) : le tout premier toucher sur un PC à écran tactile pouvait laisser l'action « hook » appuyée pour toujours (clic souris émulé). L'action est relâchée quand le jeu passe en mode tactile.
- **Résultat après corrections** : 0 erreur de script, plus aucune fermeture d'appli, 116 fichiers OK.
- **Ce qu'un enfant arrive à faire** : ⚠️ le tableau publié avec la 1.22 était faux. L'outil de test ne voyait pas toujours que l'enfant avait quitté le niveau par le menu pause, et comptait alors l'arrivée d'un AUTRE niveau. Les bons chiffres (6 min par partie, même version) sont dans la section 32, colonnes « sans mode enfant ».

## 32. Mode enfant (16/11, version 1.23)

- **Demande** : un mode pour les enfants dans les paramètres, suite au « test enfant ».
- **Options → « Mode enfant (avance tout seul + aide) »** (`Settings.kid_mode`, coupé par défaut, mémorisé). Jamais actif en multijoueur. Tout est dans `src/ui/race/KidAssist.gd`, créé par `RaceManager` au début de chaque niveau solo :
  1. **Pinpouin avance tout seul** au sol, jusqu'à 650 px/s (◀▶ normal : 500). La poussée s'arrête si on appuie sur ◀, en l'air ou au grappin ; pentes, pump et grappin restent les seuls moyens d'aller plus vite.
  2. **Coup de pouce dans les creux** : coincé 4 s sans avancer, il reçoit une petite impulsion vers l'avant et le haut.
  3. **Pont magique** : après 2 chutes de suite dans le même trou, il réapparaît sur l'île suivante, avec le message « Coup de pouce ! ». Le trou est repéré par son bord (cherché au rayon depuis le dernier endroit sûr), et les prises de grappin « poisson » au-dessus des trous ne sont pas prises pour du sol.
  4. **Aide visuelle** : 6 s sans avancer, des cercles jaunes clignotent autour de ▶ et PUMP (tactile), ou un message rappelle les touches (clavier, manette).
  5. **Boutons tactiles plus faciles à toucher** : zone de toucher ×1,6 au lieu de ×1,25 (`TouchControls._button_at`).
  6. **Pause par appui long** : le bouton pause tactile doit être tenu 1 s, avec un anneau qui se remplit (`TouchControls.KID_PAUSE_HOLD`). La touche retour Android ouvre toujours la pause.
  7. **Carte d'aide courte** : « Pinpouin avance tout seul ! Sauter, Grappin, PUMP ».
- **Au passage** (menu pause) : sur téléphone, sans « Quitter le jeu », le bouton « Choisir un niveau » s'étirait sur deux hauteurs ; il garde maintenant la taille des autres.
- **Mesuré avec le bot enfant** (téléphone simulé, 6 min par partie, 5 parties par course et par profil) :

  | Course | Petit, sans mode | Petit, mode enfant | Grand, sans mode | Grand, mode enfant |
  |---|---|---|---|---|
  | Tuto Bateau | 4 / 5 | 5 / 5 | 5 / 5 | 5 / 5 |
  | Nice Slope | 1 / 5 | 5 / 5 | 2 / 5 | 4 / 5 |
  | Spaghetti | 1 / 5 | 5 / 5 | 1 / 5 | 5 / 5 |
  | Hook you fool ! | 0 / 5 | 3 / 5 | 0 / 5 | 2 / 5 |
  | Flat and fun | 0 / 5 | 5 / 5 | 0 / 5 | 4 / 5 |
  | Corridor | 0 / 5 | 5 / 5 | 0 / 5 | 4 / 5 |
  | **Total** | **6 / 30** | **28 / 30** | **8 / 30** | **24 / 30** |
  | Sorties du niveau par erreur (menu pause) | 24 | 0 | 21 | 4 |

  Sans le mode, l'enfant ouvre la pause en tapotant, et finit souvent par toucher deux fois « Choisir un niveau » ou « Recommencer » malgré la confirmation. Les 4 sorties restantes du profil « grand » viennent d'un doigt gardé plus d'1 s sur le bouton pause. Hook you fool ! reste le plus dur : le pont magique aide, mais l'enfant tombe encore souvent (le niveau est long).
- **À noter** : les records, temps et fantômes faits en mode enfant comptent comme les autres (le mode est pensé pour les petits, pas pour battre des records).

## 33. Retours de Léo, lot 1 (16/11, version 1.24)

- **Volume de la musique** (Options) : il ne faisait rien. Le lecteur de musique (`MusicController`) n'était branché sur aucun bus, donc sur « Master », alors que le curseur règle le bus « Music ». Il est maintenant branché sur « Music » (vérifié : curseur à 20 % = −14 dB sur ce bus).
- **« Vitesse gardée à l'atterrissage »** (`landing_speed_keep`, panneau F2) : 0,5 → **0,75** par défaut. Ce réglage date de la correction du bug vitesse → 0 (section 2) : à l'atterrissage contre une pente, Godot 3 effaçait toute la vitesse « écrasée » contre le sol. À 0,5, le pingouin en perdait encore la moitié à chaque bosse, d'où un petit « freeze » à répétition. Mesure (bot avance + pump, 30 s) : vitesse moyenne +3 à +12 % selon le niveau, aucune chute brutale. ⚠️ Un réglage déjà changé avec le panneau F2 reste prioritaire : bouton « Par défaut » du panneau pour prendre la nouvelle valeur.
- **Tutoriel** :
  - le bouton s'appelle « ★ Tutoriel ★ » (au lieu de « Tuto : Bateau ») ; même nom dans le salon multi et l'échange de fantômes. Le fichier du niveau ne change pas (`LevelBateau.tscn`) : records et fantômes conservés ;
  - nouvel ordre des panneaux : avancer → PUMP → SAUT → rotation en l'air → SCORE → grappin… (avant : avancer → SCORE → saut → pump → rotation). Les panneaux restent aux mêmes endroits, seuls les textes changent de place.
- **Un seul écran de démarrage** : le logo nuit (tête de Pinpouin masquée dans le rond du « i »). L'image « Pinpouin prêt au départ » n'est plus montrée ; il reste un fondu de 0,35 s de la couleur nuit vers l'écran titre. Image conservée, `SplashIntro.SHOW_INTRO_IMAGE = true` pour la remettre.

## 34. Deux modes de jeu : Chill et Score (16/11, version 1.25)

- **Demande** (retours de Léo, lot 2 + choix de Manu) : garder le jeu « compétition » tel qu'il est, avec des médailles, et ajouter le mode « relax » que préfère Léo (« Chill > score, Tricks > score »).
- **Choix du mode** : deux boutons **Chill / Score** sous « COURSES », dans la sélection des niveaux (`Settings.game_mode`, **Chill par défaut**, mémorisé). En multijoueur, l'hôte choisit le mode dans le salon (`NetSession.race_mode`, envoyé à tous avec le niveau et le seed). `Settings.is_chill()` donne le mode de la partie en cours.
- **Mode Chill** :
  - **arrivée d'origine, dans le half-pipe** : l'arrivée sur l'arche (1.18) n'est pas posée (`sol.gd`), c'est `HalfPipe.add_finish_gate` qui pose la sienne, comme avant la 1.18 ;
  - **pas de chrono, de record, de total de figures, de classement ni de fantôme** (rien n'est enregistré). Les figures réussies s'affichent quand même en jaune, et le maître fait son clin d'œil ;
  - **le niveau ne se ferme pas** à l'arrivée : bandeau « BRAVO ! Reste faire des figures autant que tu veux » et bouton **Menu** pour partir quand on veut (`RaceManager.free_ride`). Un toucher sur ce bouton ne lance pas le grappin (groupe `touch_block`, `TouchControls._blocked_by_ui`) ;
  - tuto (sans half-pipe) : « BRAVO ! » puis retour au menu au bout de 3,5 s, sans ralenti ;
  - en multi : pas de classement ; le bandeau indique combien sont arrivés, et tout le monde rentre au salon 60 s après la dernière arrivée (150 s au plus après la première), pour rider ensemble.
- **Mode Score** (le jeu de la 1.24, avec des médailles) :
  - arrivée sur l'arche, chrono, record, fantôme, **30 s de figures bonus** ;
  - **médailles mesurées par un bot** « bon joueur » (▶, PUMP dans les descentes, grappin au-dessus des trous ; hors projet, `medal_bot.gd`). Or = temps du bot arrondi à la demi-seconde au-dessus, argent = or + 25 %, bronze = or + 60 % :

    | Course | Bot | Or | Argent | Bronze |
    |---|---|---|---|---|
    | Tutoriel | 17,28 s | 17,5 s | 21,9 s | 28,0 s |
    | Flat and fun | 1:03,83 | 1:04,0 | 1:20,0 | 1:42,4 |
    | Corridor | 1:03,45 | 1:03,5 | 1:19,4 | 1:41,6 |
    | Nice Slope | 47,68 s | 48,0 s | 1:00,0 | 1:16,8 |
    | Spaghetti | 30,9 à 34,1 s (10 terrains) | 34,5 s | 43,1 s | 55,2 s |
    | Hook, you fool ! | estimé | 1:37,0 | 2:01,3 | 2:35,2 |

    Spaghetti : le terrain change à chaque partie, on garde le plus lent des 10 pour que l'or soit faisable partout. Hook you fool : le bot ne passe pas encore tous les trous au grappin (il reste suspendu ou tombe au 4e trou) ; temps extrapolé de ses meilleurs passages, à ajuster avec vos essais (`RaceManager.MEDAL_GOLD`).
  - **points de vitesse** (`RaceManager.speed_points`) : bronze 1000, argent 2000, or 3000, puis +100 par seconde gagnée sous l'or ; entre deux médailles les points évoluent en continu ; plus lent que le bronze : 0. Les figures s'ajoutent comme avant ;
  - **affichage** : pastille de la meilleure médaille au bout de chaque bouton de course (dessinée en code, `src/ui/MedalBadge.gd`) ; pendant la course, la prochaine médaille à décrocher à côté du record (« Or 1:04.00 ») ; à l'arrivée, « MÉDAILLE OR (nouvelle !) » ou le temps du bronze à battre ;
  - les meilleurs scores repartent à zéro (nouvelle section `scores_v3`, l'ancienne reste ignorée) ; records de temps et fantômes conservés ; médailles dans la section `medals` de `user://pinpouin.cfg`.
- **Durée du bonus** (question de Manu) : un bot « joueur correct » (avance dans le sens du mouvement, PUMP dans les descentes, une figure à chaque décollage) fait **environ 10 passages et 7 à 11 figures en 30 s** (700 à 1100 points), soit le tiers des points de l'or. **30 s est gardé** : assez pour s'amuser, sans que le bonus écrase le chrono. Constat au passage : un pingouin qui retombe à la verticale au fond du half-pipe s'y arrête net ; il faut appuyer sur ◀ ou ▶ pour repartir (le mode enfant le fait tout seul).
- **Plus de mur invisible** au bout du half-pipe (Léo), dans les deux modes : une chute après l'arrivée fait réapparaître sur le bord gauche du dernier half-pipe (`RaceManager.half_pipe_respawn_point`, utilisé par `Player._pick_respawn_sample`). Spaghetti a son half-pipe tout en bas, sous la fin des spaghettis : on y tombe après l'arrivée, comme avant.
- **Testé** :
  - bots en Score (Tutoriel, Flat, Nice Slope : or obtenu, bonus compté) ;
  - bots en Chill (Flat et Spaghetti : on reste 40 s dans le half-pipe, figures comptées ; tuto : retour au menu) ;
  - multi à 2 dans les deux modes (Score : classement et retour au salon ; Chill : pas de classement, retour au salon après la dernière arrivée) ;
  - bot enfant en Chill avec mode enfant ;
  - 0 erreur de script, 118 fichiers OK.

## 35. Fond « à la Alto's Odyssey » (16/11, version 1.26)

- **Retour de Léo** : sur les longues pentes, le fond « pète » encore ; proposition de Manu : garder nos images mais les afficher comme dans Alto's Odyssey.
- **Cause trouvée** (captures sur Nice Slope, Spaghetti et Corridor) : les 3 images glissaient en hauteur à des vitesses différentes. La grande bande sombre du bas de l'image des nuages apparaissait alors entre les montagnes et la brume (bande noire à bord droit). Et le cadrage calé sur le bas du glacier cachait presque toutes les montagnes.
- **Nouvelle mise en page** (`VerticalParallax.gd`, `alto_layout = true`) :
  - **composition fixe à l'écran** : le décor ne suit plus les pentes. Chaque image est placée à une hauteur choisie (`alto_rows`, en lignes de pixels de l'image) dans un écran de 180 lignes, centré verticalement ;
  - **nouvel ordre des plans** (z_index changés par le script, scènes intactes) : nuages au fond, glacier au milieu (sa brume passe au pied des montagnes), montagnes devant. La bande sombre des nuages reste toujours cachée ;
  - **échelle entière ×4** (`art_scale`, avant ×5) : 180 lignes d'image = 720 px. Pixels nets, et tout le dessin tient à l'écran : nuages, sommets, brume, falaises ;
  - **à peine de mouvement vertical** : léger décalage selon la profondeur pendant les sauts et les chutes, au plus 40 px, qui revient en 0,8 s (`alto_vertical_strength`, `alto_max_shift`, `alto_follow_time`) ;
  - **prolongements** : ciel vers le haut, falaises vers le bas, en aplats de couleur. Aucun vide, même sur un écran très haut (vérifié en 900 × 1100) ;
  - **légère brume de profondeur** sur les nuages, teintés à 12 % vers la couleur du ciel (`alto_haze`) ;
  - défilement horizontal inchangé : 0,2 / 0,35 / 0,5 selon la profondeur.
- **Vérifié** en captures toutes les 3 s sur toute la descente de Nice Slope et de Corridor : composition identique du haut en bas des pentes, plus de bande noire. Même rendu sur le Tutoriel, Chill 704, Chill 917, Flat, Hook you fool ! et Spaghetti.
- Aucune image modifiée ni supprimée. `alto_layout = false` (sur le `ParallaxBackground` d'un niveau) remet le fond de la 1.9.

## 36. PUMP en l'air = descendre plus vite (16/11, version 1.27)

- **Demande de Léo**, validée par Manu, **activée par défaut** : tant que PUMP est maintenu en l'air, la gravité est plus forte et Pinpouin redescend plus vite.
- `Player.air_pump_gravity` = **×2** (1 = désactivé) ; réglable en jeu dans le panneau F2 (« Gravité en pumpant en l'air », de ×1 à ×4).
- **Pas pendant le grappin** (il a sa propre physique) **ni en mode enfant** (les petits appuient sur PUMP au hasard). Le petit coup de pump en l'air d'origine (`InAirState`) est conservé.
- **Mesuré** sur un saut du Tutoriel lancé à ~850 px/s : 1,67 s en l'air et 935 px sans PUMP ; **0,92 s et 514 px** en gardant PUMP. Ça sert à écourter un saut trop long, à viser son atterrissage, et à « coller » à une descente pour garder l'élan. Revers : un saut écourté laisse moins de temps pour les figures.
- Temps des médailles inchangés : le bot de mesure ne pumpe qu'au sol.

## 37. Niveau Chill « Half-pipe » + figures visibles en Chill (16/11, version 1.28)

- **Demande de Léo** : « un level à mettre dans Chill avec juste un half-pipe ».
- **Niveau** : la scène `LevelHalfPipe.tscn` existait déjà dans le projet sans être au menu. Elle y est ajoutée : bouton « Half-pipe » dans le panneau CHILL, après 917.
  - Pas de ligne d'arrivée : nouvelle option `HalfPipe.with_finish = false`. On y fait des figures sans fin.
  - Menu pause ajouté (`UserInterface`), comme dans les autres niveaux.
  - Podium, décors et prises de grappin (blocs au-dessus) conservés.
  - Une chute par un bout fait réapparaître sur le bord gauche du half-pipe.
- **Figures visibles dans tous les niveaux Chill** (704, 917, Half-pipe) : avant, sans arrivée, il n'y avait aucun affichage. Maintenant, un HUD sans chrono ni score montre les figures réussies, et le maître fait son clin d'œil (`RaceManager._setup_tricks`, ride libre `free_ride`).
- **Testé** : bot qui fait des allers-retours avec une figure à chaque décollage : 60 s sans chute, figures comptées. 704 et 917 sans erreur. 118 fichiers OK.

## 38. Plafonds pour s'accrocher dans Chill 704 et 917 (16/11, version 1.29)

- **Retour de Léo** : « Les chill levels ont pas de plafond, donc c'est peu dynamique ».
- **Principe** (`ChillLoop.gd`, `_add_ceilings`) : au chargement, des plafonds de glace (des `sol` presque plats, comme celui du tutoriel) sont posés au-dessus de la piste.
  - Un plafond de 1600 px tous les 4200 px (`ceiling_length`, `ceiling_period`), pas dans les 1500 premiers / derniers px (`ceiling_margin`).
  - À 450 px au-dessus du point le plus haut de la piste sous lui (`ceiling_clearance`), comme le plafond du tutoriel : hors de portée d'un simple saut, à portée de grappin.
  - Incliné comme la piste en dessous.
  - Dans 704, pas de plafond là où une piste retournée sert déjà de plafond à portée de grappin (entre 150 et 1100 px au-dessus).
  - Ils sont dans « Plateforms » : la boucle infinie les recopie avec le reste.
  - `add_ceilings = false` sur le nœud `BoucleInfinie` pour les retirer.
- **Résultat** : 917 : 18 plafonds ; 704 : 21. Bot qui lance le grappin vers le haut toutes les 3 s pendant 60 s : 917 : 4 → 15 accroches ; 704 : 3 → 11 accroches ; aucune chute. 118 fichiers OK.
- **À vérifier en jouant** : les plafonds sont parfois juste au-dessus du haut de l'écran (on voit la corde partir hors champ). Si c'est gênant, baisser `ceiling_clearance` (ex. 380).

## 39. Boost de figure (16/11, version 1.30)

- **Demande de Manu** (après la vidéo d'Alto's Odyssey) : « un petit boost de vitesse quand on a réussi un trick », partout.
- **Principe** : quand les points d'un saut sont gagnés (atterrissage propre, `TrickScore.bank()`), le pingouin reçoit une poussée dans le sens de sa vitesse (`Player.trick_boost(combo)`).
  - +220 px/s pour une figure seule (`trick_boost_base`), +90 px/s par figure en plus du combo (`trick_boost_per_combo`) ; combo ×5 = +580 px/s.
  - Pendant 1,6 s (`trick_boost_time`), la vitesse max « douce » est relevée d'autant, puis redescend progressivement : sinon le frottement au-dessus de la vitesse max mangerait le boost.
  - Traînée rose, plus épaisse et plus longue, pendant le boost.
  - Réglable avec F2 (3 nouvelles lignes dans le panneau physique).
  - Partout : courses, Chill, half-pipe, mode enfant.
- **Médailles remesurées** : le bot « bon joueur » fait maintenant des figures pendant la course. Il simule sa trajectoire et ne tente une figure que si le vol dure plus de 1,1 s, et jamais au-dessus d'un trou (il lui faut le grappin). 0 figure ratée.

| Niveau | Or avant | Bot avec boost | Or 1.30 |
|---|---|---|---|
| Tutoriel | 17,5 s | 17,23 s | 17,5 s |
| Flat and fun | 64 s | 54,82 s | 55 s |
| Corridor | 63,5 s | 55,62 s | 56 s |
| Nice Slope | 48 s | 45,75 s | 46 s |
| Spaghetti | 34,5 s | 26,1 à 28,0 s | 28 s |
| Hook, you fool ! | 97 s (estimé) | non mesuré | 97 s |

- **À savoir** : une figure ratée (atterrissage pendant la figure) arrête net le pingouin 2 s (comportement d'origine, `StaggeredState`). Le boost rend donc les figures intéressantes mais risquées sur les petits sauts.
- **Testé** : 118 fichiers OK ; boost vérifié dans le half-pipe et dans les courses.

## 40. Gerbe de neige et de glace au sol (16/11, version 1.31)

- **Demande de Manu** : une traînée de neige ou de glace derrière Pinpouin, de plus en plus grosse avec la vitesse, au sol ; garder la traînée actuelle en l'air.
- **Au sol** (`Player._update_snow_spray`) : 3 gerbes de grains (`CPUParticles2D`, marche aussi dans la version navigateur) s'allument l'une après l'autre à 220, 650 et 1100 px/s (`snow_spray_speeds`).
  - 28, 56, puis 84 grains par gerbe (`snow_spray_amount`).
  - Grains carrés, pour coller au pixel art : blancs (neige) à bleus (éclats de glace).
  - Projetés vers l'arrière et vers le haut, en panache. Ils retombent avec la gravité et s'effacent.
  - Taille et vitesse de projection augmentent en continu avec la vitesse.
  - Roses pendant un boost de figure.
  - Seulement quand le pingouin glisse au sol : pas en l'air, pas accroché au grappin, pas sonné.
- **En l'air** : la traînée d'avant (blanche, rose pendant un boost) reste ; au sol elle s'efface.
- Aucun asset ajouté : le grain est une texture de 1 pixel créée en code.
- **Testé** : 118 fichiers OK ; captures à 500, 1370 et 1620 px/s ; temps du bot des médailles inchangé.

## 41. Niveau « Sans fin » (Chill) (16/11, version 1.32)

- **Idée de Manu** (vidéo d'Alto's Odyssey) : un niveau sans fin avec des trous qu'on passe d'abord en sautant, puis au grappin de façon normale, puis de façon plus subtile, avec des passages testés par des bots.
- **Niveau** : `src/levels/LevelEndless.tscn`, bouton « Sans fin » dans le panneau CHILL. Le terrain est fabriqué au fur et à mesure devant le pingouin par `src/levels/endless/EndlessGenerator.gd`, et libéré loin derrière (mémoire constante).
- **Un tronçon** = une île de glace (`sol`, longue de 3000 à 4600 px, en légère descente pour garder de la vitesse) suivie d'un trou :

| Trou | Largeur | Arrivée | Comment le passer |
|---|---|---|---|
| Saut | 450 à 800 px | 80 à 220 px plus bas | sauter au bord |
| Grand saut | 950 à 1450 px | 200 à 380 px plus bas | PUMP + sauter |
| Grappin | 2300 à 2700 px | 150 à 250 px plus haut | une prise au milieu |
| Grappin double | 4000 à 4500 px | même niveau | deux prises à enchaîner |
| Grappin montée | 1600 à 1900 px | 420 à 520 px plus haut | prise au-dessus de l'arrivée : lâcher dans la remontée |
| Plafond | 3800 à 4400 px | 100 à 200 px plus haut | s'accrocher au plafond, lâcher, se raccrocher plus loin |

- **Difficulté qui monte** (`_pick_type`) :
  - les 3 premiers trous sont des sauts ;
  - puis arrivent, dans l'ordre : grand saut (3e), grappin (5e), plafond (8e), grappin double (9e), grappin montée (12e) ;
  - les petits sauts deviennent plus rares ;
  - jamais deux fois de suite le même trou à grappin ;
  - les sauts s'allongent jusqu'à +15 %.
- **Chute** : réapparition au début de l'île d'avant le trou raté, avec un peu d'élan (`respawn_sample`, appelé par `Player._pick_respawn_sample`). Attention : en tombant, le pingouin dérive souvent sous l'île suivante ; on se sert donc de la dernière île où il a glissé, sinon on « sautait » le trou raté.
- **Carte d'aide** propre au niveau : sauter les petits trous, grappin sur les blocs de glace, lâcher quand Pinpouin remonte.
- **Ce que les bots ont appris sur le grappin** : avec une prise au-dessus, c'est un balancier rigide qui tire en plus vers la prise. La chaîne vole à 3000 px/s, donc à pleine vitesse il faut tirer environ 900 px avant la prise. Le bon moment pour lâcher : quand on remonte en avançant (vitesse verticale vers le haut > 45 % de la vitesse).
- **Validation par bots** (outil hors projet `endless_bot.gd`, 120 s par type de trou forcé) :

| Trou | Bot « saut seul » | Bot « saut + grappin » |
|---|---|---|
| Saut | 43/43 | 42/42 |
| Grand saut | 34/34 | 36/36 |
| Grappin | 0/19 | 17/21 |
| Grappin double | 0/19 | 15/15 |
| Grappin montée | 0/19 | 21/25 |
| Plafond | 0/20 | 11/11 |

  - Partie normale de 5 min avec le bot grappin : 41 îles, 8 chutes.
  - Mode enfant, bot qui ne saute jamais : 17 îles en 150 s grâce au pont magique, contre 1 sans le mode enfant.
- **Testé** : 120 fichiers OK ; captures de chaque type de trou ; panneau CHILL avec 4 boutons sur écran de téléphone.
- **Prochaine étape (1.33)** : mode Score du Sans fin (compteur de mètres, record, 3 vies en têtes de Pinpouin, médailles 1 / 3 / 5 km).

## 42. Sans fin en mode Score : mètres, 3 vies, médailles (16/11, version 1.33)

- **Choix de Manu** : 3 vies en têtes de Pinpouin ; médailles bronze 1 km, argent 3 km, or 5 km.
- **Où le trouver** :
  - bouton « ∞ Sans fin ∞ » dans les COURSES, qui suit le choix Chill / Score ;
  - le bouton « Sans fin » du panneau CHILL reste toujours en Chill (scène `LevelEndlessChill.tscn`, qui reprend `LevelEndless.tscn` avec `force_chill = true`).
- **En Score** (`src/levels/endless/EndlessScore.gd`, créé par le générateur) :
  - **Compteur** en haut au centre (en haut à droite, il y a le bouton pause tactile) : distance en mètres, record dessous, puis la médaille en cours et la suivante (« Argent à 3 km »).
  - **Distance** = point le plus loin atteint ; une chute ne fait pas reculer le compteur.
  - **1 m = 40 px**, à peu près la taille du pingouin (`PX_PER_METER`).
  - **3 vies** : 3 têtes de Pinpouin en haut à gauche, découpées dans le sprite du pingouin, sans image ajoutée. Chaque chute en grise une, et on réapparaît avant le trou. À la 3e chute : panneau « PLUS DE VIES ! » avec distance, record, médaille, et boutons Rejouer / Menu.
  - **Médailles** : « MÉDAILLE BRONZE ! » s'affiche en passant 1 km, de même pour 3 et 5 km. La meilleure médaille et le record (section `endless` du fichier d'options) s'affichent sur le bouton du menu en mode Score.
  - La carte d'aide du départ rappelle les 3 vies et les médailles.
- **Réglage de l'échelle aux bots** (parties complètes jusqu'à la 3e chute) :
  - bot « saut + grappin » : 3,4 à 8,9 km, l'or est atteint dans 4 parties sur 6 (comme les temps de l'or des courses, mesurés sur un bon joueur) ;
  - bot « saut seul » : 783 m, il s'arrête aux premiers trous à grappin, donc pas de bronze sans le grappin.
- **Testé** : 122 fichiers OK ; captures du compteur et de l'écran de fin ; menu sur écran de téléphone avec le 7e bouton ; le Sans fin du panneau CHILL reste sans vies même quand le mode Score est choisi.

## 43. Bruitages provisoires + médailles corrigées (16/11, version 1.34)

### Bruitages provisoires
- **Demande de Manu** : en attendant les vrais enregistrements de son ami, des bruitages générés par Claude d'après la liste « Pinpouin Le Ninja — Sons à enregistrer ».
- **Les sons** (`assets/sfx_provisoire/`) : entièrement calculés (bruit filtré, sinus, enveloppes), rien de récupéré ailleurs. Outil hors projet `gen_sfx.py`. 60 fichiers WAV mono 44,1 kHz, 5 Mo :
  - 25 sons, la plupart en 3 variantes, tirées au hasard et à une hauteur légèrement différente à chaque fois ;
  - 5 boucles : glisse, glisse rapide, vent en l'air, sifflement de vitesse, vent d'ambiance ;
  - les **voix** (hop, youhou, aïe, maître ninja), les applaudissements, la corde tendue et le freinage ne sont pas faits : des voix calculées sonneraient faux, c'est le travail de l'ami.
- **Lecteur** : autoload `Sfx` (`src/autoload/Sfx.gd`).
  - `Sfx.play("nom")` pour les sons courts ; `Sfx.loop("nom", volume)` pour les boucles, redemandées à chaque image et qui s'éteignent en douceur quand on ne les demande plus (pause, changement de niveau).
  - Bus audio « Sound », qui existait déjà sans être utilisé. Nouveau curseur **« Volume des effets »** dans les Options, sous la musique (`Settings.sfx_volume`), avec un « ding » d'essai.
  - Clic sur tous les boutons des menus, ajouté automatiquement.
- **Pour passer aux vrais sons** : déposer les WAV de l'ami dans `assets/sfx/` avec les noms de la liste (`saut_01.wav`, `saut_02.wav`… ou `glisse_boucle.wav`). Ils sont pris en priorité, sans toucher au code. Pour une boucle, régler *Loop Mode = Forward* dans l'import (fait pour les provisoires).
- **Où on les entend** :

| Moment | Son |
|---|---|
| Glisse au sol (plus fort avec la vitesse ; « rapide » au-delà de 1000 px/s) | `glisse_boucle`, `glisse_rapide_boucle` |
| En l'air (vent ; sifflement au-delà de 1300 px/s) | `vent_boucle`, `vitesse_boucle` |
| Fond sonore de tous les niveaux | `ambiance_vent` |
| Saut, atterrissage (plus fort si on tombait vite), appui sur PUMP au sol | `saut`, `atterrissage`, `pump` |
| Grappin : lancer, accroche, lâcher | `grappin_lancer`, `grappin_accroche`, `grappin_lacher` |
| Figure lancée, réussie, combo (de plus en plus aigu), vrille, figure ratée | `figure_whoosh`, `figure_ok`, `combo`, `vrille`, `figure_rate` |
| Chute dans le vide, réapparition | `chute`, `reapparition` |
| Décompte 3-2-1, GO (multi) | `decompte_bip`, `decompte_go` |
| Ligne d'arrivée, nouveau record, fin du bonus | `arrivee`, `record`, `bonus_fin` |
| Clin d'œil du maître | `maitre_clin` |
| Sans fin : médaille, plus de vies | `record`, `bonus_fin` |
| Boutons des menus | `ui_clic` |

- Testé : un bot sur Nice Slope déclenche glisse, glisse rapide, vent, sifflement, ambiance, atterrissage, pump, figures, figure ratée, clin d'œil et arrivée ; le temps du bot est identique avec et sans les sons.

### Médailles corrigées (important)
- En vérifiant les sons, le temps du bot était différent de celui mesuré en 1.30. Cause : le fichier d'options de la machine de test contenait d'anciens réglages du panneau F2, restés d'un essai précédent, qui rendaient le pingouin plus rapide. **Les temps de l'or de la 1.30 et l'échelle des mètres de la 1.33 avaient été mesurés avec cette physique-là**, pas avec celle des joueurs.
- Remesuré avec les réglages par défaut (fichier d'options effacé avant chaque partie, terrains au hasard pour Spaghetti). Or = meilleur temps du bot, avec ou sans figures, arrondi à la demi-seconde au-dessus :

| Niveau | Or 1.30 (faux) | Bot avec figures | Bot sans figures | Or 1.34 |
|---|---|---|---|---|
| Tutoriel | 17,5 s | 18,95 s | 19,12 s | 19 s |
| Flat and fun | 55 s | 63,60 s | 65,15 s | 64 s |
| Corridor | 56 s | 74,33 s | 66,40 s | 66,5 s |
| Nice Slope | 46 s | 49,07 s | 52,17 s | 49,5 s |
| Spaghetti | 28 s | 31,3 à 33,6 s | 32,55 s | 33,5 s |
| Hook, you fool ! | 97 s | — | — | 97 s (estimé) |

  - À noter : dans Corridor, faire des figures fait perdre du temps (atterrissages ratés) ; dans les autres niveaux, le boost fait gagner 1 à 3 s.
- **Sans fin** revalidé avec la vraie physique :
  - bot « saut seul » : 100 % des sauts, 0 % des trous à grappin ;
  - bot grappin : grappin 15/15, double 11/12, montée 17/17, plafond 8/8.
  - Échelle des mètres : le bot grappin faisait 6,9 à 10,9 km avant sa 3e chute. L'or serait atteint à chaque fois, donc **1 m = 55 px** au lieu de 40. Le bot fait alors 5,0 à 8,0 km (or 4 fois sur 5) ; le bot « saut seul » environ 670 m (pas de bronze sans grappin).
- **Leçon pour la suite** : avant chaque mesure aux bots, effacer `user://pinpouin.cfg` (réglages F2, records et fantômes) de la machine de test.

## 44. Ciel qui change de couleur (16/11, version 1.35)

- **Idée de Léo** (« un ciel qui change de couleur, dans l'esprit d'Alto »), lancée par Manu.
- **Sans fin** : le ciel suit la distance parcourue.
  - 0 m aube rosée, 1 km plein jour (couleurs d'origine), 3 km couchant orangé, 5 à 6,5 km nuit bleue avec étoiles et pleine lune, retour à l'aube à 8 km, et ainsi de suite.
  - Fondus doux. Le ciel suit le point le plus loin atteint : une chute ne fait pas revenir le jour.
  - La nuit, avec la lune et les étoiles, devient la récompense visuelle de ceux qui passent les 5 km (l'or).
- **Niveaux Chill** : ambiance fixe. 704 au petit matin, 917 au couchant, Half-pipe de nuit étoilée.
- **Comment** (`src/levels/parallax/SkyCycle.gd`, un nœud « Ciel » dans chaque niveau concerné ; `fixed_at` = ambiance fixe, en « mètres » du cycle) :
  - les 3 plans du fond sont teintés via leur `ParallaxLayer` (la teinte passe aussi à leurs prolongements) ;
  - le premier plan (îles, pingouin, décor) est teinté plus légèrement par un `CanvasModulate`, pour rester lisible ; au couchant, presque pas, pour que la glace reste bleue ;
  - la couleur du ciel derrière les images (couleur de fond du rendu) change aussi, et elle est remise d'origine en quittant le niveau ;
  - étoiles qui scintillent et lune dessinées en code (`SkyStars.gd`), entre les nuages et les montagnes ;
  - l'interface (HUD, boutons) n'est pas teintée.
- **Aucune image ajoutée ni modifiée.** Les autres niveaux (courses) gardent le ciel d'origine.
- Palette réglable en tête de `SkyCycle.gd` (`KEYS` : mètres, teinte du fond, teinte du premier plan, couleur du ciel, nuit).
- **Testé** : 125 fichiers OK ; captures des 4 moments du Sans fin et des 3 niveaux Chill.

## 45. Fantôme du Sans fin et défis entre amis (16/11, version 1.36)

- **Demande de Manu** : courir contre son meilleur essai dans le Sans fin, sur le même terrain, et pouvoir défier un ami.
- **Mode Score seulement** (comme les fantômes des courses ; rien ne change en Chill ni en multi).
- **Enregistrement** : la partie est enregistrée comme celle d'une course (30 positions par seconde, même `GhostPenguin.gd`). À la fin de la partie (plus de vies), elle devient le fantôme si elle est allée **plus loin** que tous les fantômes du niveau.
  - Le fichier garde la distance, rangée en `time = -mètres` : « le plus petit temps » de `load_best_ghost` est ainsi le fantôme allé le plus loin, sans toucher au code des courses.
  - Il garde aussi la **graine du terrain** : la partie suivante a le même terrain que le fantôme.
- **En jeu** :
  - le fantôme bleu glisse à côté, avec l'étiquette « fantôme 330 m » ;
  - sous le compteur, l'écart : « Fantôme : 34 m devant / derrière / à côté de toi ! » (le fantôme est vite hors de l'écran dans ce niveau) ;
  - carte d'aide : « Ton FANTÔME glisse avec toi : il est allé jusqu'à … m, même terrain ! ».
- **Écran de fin** : « Fantôme : 330 m (encore 258 m) » ou « C'est ton nouveau fantôme ! ». Trois boutons :
  - **Rejouer** : le même terrain que la partie qu'on vient de finir (avec le fantôme s'il a été fait sur ce terrain) ;
  - **Nouveau terrain** : terrain neuf, sans fantôme ;
  - **Menu**. En revenant par le menu, on retrouve le terrain du fantôme.
- **Défi entre amis** : l'échange de fantômes des Options marche aussi pour le Sans fin (ligne « Sans fin   330 m », bouton Copier). Coller le texte d'un ami : « Défi ajouté : Sans fin, 330 m ». S'il est allé plus loin que le sien, on glisse contre lui, sur son terrain.
- **Corrigé au passage** : la carte d'aide du Sans fin en mode Score avait le titre « GLISSE TRANQUILLE » (défaut de la 1.33) ; elle dit maintenant « C'EST PARTI ! ».
- **Fichiers** : `RaceManager.gd` (`_start_endless_ghost`, `save_endless_ghost`, `endless_ghost_meters`, `endless_new_terrain`, `endless_replay_seed`), `EndlessScore.gd` (écart, écran de fin), `OptionsScreen.gd` (`RACES` + affichage en mètres).
- **Testé** : 125 fichiers OK ; bot : partie 1 enregistre le fantôme, partie 2 le charge sur la même graine ; Nouveau terrain → graine neuve sans fantôme, Rejouer → même graine, menu → terrain du fantôme ; export puis import du texte (« Défi ajouté : Sans fin, 330 m »).

## 46. Un seul menu pour tous les niveaux (21/11, version 1.37)

- **Demande de Manu** : plus de panneau « CHILL » à droite ; tous les niveaux dans la liste COURSES, et le choix Chill / Score s'applique à chacun.
- **Nouvelle liste** (`LevelSelectionScreen.tscn`) : les 10 boutons sont dans une grille de deux colonnes (nœud `Grid`, un `GridContainer`), dans cet ordre : Tutoriel, Flat and fun, Corridor, Nice Slope, Hook you fool !, Spaghetti, 704, 917, Half-pipe, ∞ Sans fin ∞. Sur une seule colonne, la liste aurait été trop haute : l'écran aurait tout rétréci sur téléphone.
- **Les modes** :
  - les 6 courses avec arrivée et le Sans fin suivent le choix Chill / Score comme avant ;
  - 704, 917 et Half-pipe n'ont pas d'arrivée : ils restent en glisse libre dans les deux modes. En Score, leur bouton affiche « · glisse libre » et le texte sous les boutons le rappelle (`FREE_RIDE_LEVELS` dans `LevelSelectionScreen.gd`).
- **Ancien panneau CHILL** : masqué (`visible = false`), pas supprimé. Son étiquette CHILL d'origine et le bouton vers `LevelEndlessChill.tscn` (Sans fin toujours en Chill) y restent. Ce bouton faisait doublon avec « ∞ Sans fin ∞ » en mode Chill.
- Boutons élargis à 380 px et séparateurs « · » resserrés : en mode Score, la médaille au bout du bouton ne mord plus sur le texte.
- **Testé** : 125 fichiers OK ; captures en Chill et en Score (avec records, points et médailles sur tous les boutons) en 1280 × 720, 1024 × 720 et 2400 × 1080.

## 47. Bouton « Menu » retiré du bandeau d'arrivée Chill (21/11, version 1.38)

- **Retour de Manu** : en mode Chill, à l'arrivée, le bouton « Menu » du bandeau « BRAVO ! Reste faire des figures autant que tu veux » ne marchait pas, alors que le menu pause (Échap) permet déjà de partir.
- **Changement** (`RaceHud.show_chill_finish`) : le bouton est retiré ; le bandeau dit à la place « (pour partir : menu pause) ». En multi, le bandeau ne change pas (retour au salon ensemble).
- Pour partir : Échap, bouton pause tactile ou manette → « Choisir un niveau ».
- **Testé** : 125 fichiers OK ; capture du bandeau.

## 48. Boutons de fin de partie du Sans fin qui ne répondaient pas (21/11, version 1.39)

- **Retour de Manu** : à la fin d'une partie du Sans fin (« PLUS DE VIES ! »), les boutons Rejouer, Nouveau terrain et Menu ne marchaient pas. C'était aussi la cause du bouton « Menu » de l'arrivée Chill retiré en 1.38.
- **Cause** : le menu pause (`MenuPause`, calque 60) est un `Control` qui couvre tout l'écran. Même caché (seul son fond `PauseOverlay` est masqué), il attrapait la souris par défaut (`mouse_filter = STOP`) et passait au-dessus du HUD (calque 36). Il mangeait donc tous les clics destinés aux boutons du HUD. Trouvé en simulant un clic : le contrôle sous la souris était `MenuPause`, pas le bouton.
- **Correction** (`MenuPause.gd`) : `mouse_filter = IGNORE` sur ce nœud. Quand la pause est ouverte, c'est `PauseOverlay` (plein écran) qui reçoit les clics, comme avant.
- **Testé** (clics de souris simulés) : Rejouer (même terrain), Nouveau terrain (terrain neuf), Menu (sélection des niveaux), et « Reprendre » du menu pause ; 125 fichiers OK.

## 49. Atterrissages comme en skate : pattes, nose, chute (21/11, version 1.40)

- **Demande de Manu** : Pinpouin ne doit plus retomber toujours de la même façon. Glisser debout sur les pattes ; un « nose » comme en skate (atterrir le bec en avant, en restant allongé) ; une vraie chute s'il retombe sur le dos, avec une roulade et une petite explosion de neige pour cacher le passage dos → fesses.
- **Choix de Manu** (questions posées avant de lancer) :
  - pattes : il reste debout jusqu'au prochain saut, **juste visuel** (même vitesse) ;
  - nose : **« NOSE ! » + points + petit boost**, comme une figure réussie ;
  - chute : **roulade puis assis étourdi 1 s** ;
  - tolérance **généreuse** : chute seulement au-delà de 120° de travers par rapport à la pente.
- **Comment c'est mesuré** (`src/actors/LandingStyle.gd`, créé par `Player._ready`, appelé par `Player._physics_process` juste après le mouvement) :
  - à chaque image en l'air, on garde l'écart entre l'angle du pingouin et celui de la pente sous lui (rayon vertical, indépendant de sa rotation), **avant** que `InAirState` ne le redresse tout seul en approchant du sol ;
  - au contact, cet écart décide : plus de 120° → chute ; bec en avant de plus de 35° → nose ; sinon → pattes ;
  - les deux capteurs de sol tournent avec le pingouin : sur le dos, ils regardent le ciel. C'est donc le contact du corps (`move_and_slide`) qui détecte la chute ;
  - seul un **vrai sol** compte (surface tournée vers le haut). Bug trouvé en test et corrigé : à l'envers sous une île, les capteurs touchaient le dessous de l'île, et ça déclenchait une fausse chute en plein vol ;
  - pas de nose ni de chute pendant le grappin. Une figure pas finie à l'atterrissage reste la « figure ratée » d'avant (2 s sonné), sauf sur le dos, où c'est la chute.
- **Pattes** : nouvelle animation `glide_feet` avec le dessin de Pinpouin debout déjà dans le jeu (`Ninja-Chinstrap_idle.png`, aucune image ajoutée). Il se penche un peu en arrière quand il va vite, avec un léger rebond, et se tasse quand on tient PUMP. Les états au sol (glisse, course, pump) passent par `Player.play_ground_anim()`, qui choisit debout ou à plat ventre. Au départ d'un niveau, il est à plat ventre, comme avant.
- **Nose** : à plat ventre (la glisse d'origine). `TrickScore` ajoute « Nose » (`LandingStyle.NOSE_POINTS` = 50) aux figures du saut : il compte dans le combo, s'affiche « +… NOSE ! » et donne le boost de figure.
- **Chute** (`src/states/CrashState.gd`, nouvel état de la machine à états) :
  - explosion de neige au contact (gros paquets lents qui masquent le pingouin + éclats rapides), qui part avec l'élan du pingouin ;
  - roulade 0,5 s avec le dessin « boule » de la figure Boule, qui tourne sur lui-même ; le pingouin freine et se remet dans le sens de la pente ;
  - deuxième petit nuage au moment où il s'assoit, pour cacher le passage boule → assis ;
  - puis 1 s assis étourdi, avec les étoiles (`StaggeredState` accepte maintenant une durée et un dessin imposés : `next_time`, `next_anim`) ;
  - les points du saut en cours sont perdus (« Chute ! »).
- **Mode enfant** : pas de chute ; un atterrissage sur le dos remet Pinpouin sur ses pattes.
- **Testé** :
  - bot qui retombe exprès à 0° (pattes), 59° (nose) et 167 à 177° (chute) : bon classement, captures de chaque cas ;
  - temps du bot des médailles identiques à la 1.34 (Tutoriel 19,12 s, Nice Slope 52,17 s, Flat 1:05,15) : aucun nose involontaire ;
  - bot grappin du Sans fin : grappin 20/20, double 15/15, montée 25/25, plafond 11/11, aucune chute après un lâcher de grappin ;
  - 127 fichiers OK.
- **À régler en jouant** (en tête de `LandingStyle.gd`) : `CRASH_ANGLE_DEG` (120), `NOSE_ANGLE_DEG` (35), `NOSE_POINTS` (50) ; durées dans `CrashState.gd` (`ROLL_TIME` 0,5 s, `DIZZY_TIME` 1 s).

## 50. Tuto par ateliers, mené par le maître ninja (21/11, version 1.41)

- **Demande de l'équipe** : ajouter les nouveautés au tuto, le rendre plus long, et faire refaire chaque action en boucle jusqu'à ce qu'elle soit réussie.
- **Choix de l'équipe** (questions posées avant de lancer) :
  - **3 réussites** pour les gestes de base, **1 ou 2** pour les gestes durs ;
  - un bouton **« Passer » après 5 échecs** dans le même atelier ;
  - les consignes données par **le maître ninja, dans des bulles** ;
  - pour finir, une **petite course chronométrée avec médaille**.
- **Les 9 ateliers**, dans l'ordre (`workshop_specs`, en tête de `BateauGenerator.gd`) :

  | # | Atelier | À réussir | Comment c'est reconnu |
  |---|---|---|---|
  | 1 | PUMP | 3 | PUMP tenu au sol dans une descente ≥ 0,25 s (ou chaque 0,7 s sans relâcher) |
  | 2 | Saut | 3 | un saut suivi d'un atterrissage sans chute |
  | 3 | Sur les pattes (3 tremplins) | 3 | atterrissage « pattes » après ≥ 0,6 s en l'air |
  | 4 | Nose (2 tremplins) | 2 | atterrissage « nose » |
  | 5 | La chute (1 tremplin) | 1 | atterrissage sur le dos, fait exprès pour voir ce qui se passe |
  | 6 | Figures (2 tremplins) | 2 | un saut validé avec une figure |
  | 7 | Combo (1 tremplin) | 1 | un saut validé avec au moins 2 éléments (figure, vrille, nose) |
  | 8 | Grappin au plafond | 1 | accroché ≥ 1 s au plafond en tirant ≥ 0,3 s |
  | 9 | Balancier (grand trou + bloc de glace) | 1 | de l'autre côté du trou, au-dessus du sol |

- **Déroulé d'un atelier** (`src/levels/tutorial/TutorialCoach.gd`) :
  - en entrant, le maître donne **une** consigne avec les vraies touches du joueur. Le jeu se met en pause le temps de lire si l'option « Pause pour lire les panneaux du tuto » est active (comme avant) ;
  - un compteur à ronds s'affiche **sous Pinpouin** (`SuccessCounter.gd`) : là où le joueur regarde. Il était d'abord au-dessus, mais passait derrière la bulle quand la caméra met le pingouin en haut de l'écran ;
  - chaque réussite remplit un rond (« +1 ! ») ; atelier réussi → clin d'œil du maître, « RÉUSSI ! » ;
  - **échec** = arriver au bout de l'atelier sans assez de réussites, tomber dans le trou, chuter sur le dos (hors atelier « chute ») ou ne pas finir une figure. Le maître donne alors un **indice plus précis** (une phrase différente à chaque échec) ;
  - au bout de l'atelier : **retour au début** (la boucle), avec l'élan qu'on avait en entrant. Les réussites déjà faites sont **gardées** : la boucle redonne de la place pour finir, elle ne punit pas ;
  - après 5 échecs : bouton **« Passer cet atelier ▶▶ »** sous la bulle (Tab au clavier, Back à la manette, ou toucher). Il est testé avant les boutons tactiles, pour que toucher le bouton ne lance pas aussi le grappin.
- **Le maître ninja** (`src/levels/tutorial/MasterBubble.gd`) : le dessin déjà dans le jeu (`bad_penguin_1/2/3` + `bad_penguin_wink`, ceux du clin d'œil) en haut à gauche. Son bandeau flotte quand il parle, et il fait un clin d'œil à chaque atelier réussi. Bulle dessinée en code, aux couleurs du HUD : **aucune image ajoutée**. Pendant les ateliers, le chrono est caché, la place est libre.
- **Course finale** : sur la ligne de départ (panneau « COURSE FINALE, le chrono part ici »), départ lancé. `RaceManager.start_tutorial_final()` :
  - remet le chrono et les points de figures à zéro ;
  - lance l'enregistrement du fantôme et le fantôme lui-même ;
  - le maître descend sous le chrono, puis s'efface au bout de 4 s.
  
  Le parcours compte 3 tremplins et un petit trou à sauter. Or : **13,5 s** (bot : 13,28 à 13,55 s), argent 16,9 s, bronze 21,6 s. Une chute dans le petit trou fait réapparaître juste avant ce trou, jamais derrière la ligne de départ.
- **La piste** (`BateauGenerator.gd`) :
  - construite à partir de la liste des ateliers : changer la longueur d'un atelier recale tout le reste ;
  - elle n'est plus d'un seul morceau : elle est coupée par des trous (`gaps`), et `surface_y(x)` lit le bon morceau ;
  - le grand trou du balancier reprend les mesures du trou « GRAPPIN » du Sans fin (2400 px, autre bord 200 px plus haut, bloc de glace au milieu, 600 px au-dessus), réglé aux bots : un saut seul ne passe pas ;
  - les tremplins passent de 35° à **28°**. Lancé à pleine vitesse, un tremplin à 35° faisait voler ~3700 px et passer par-dessus le tremplin suivant. À 28°, on vole ~2 s, assez pour une figure suivie d'un nose ;
  - les anciens panneaux d'explication deviennent de simples panneaux d'entrée « ATELIER 3 · SUR LES PATTES » (`TutorialSign.announce = false` : ni pause ni bandeau).
- **Déjà fait une fois ?** Le tuto s'en souvient (`user://pinpouin.cfg`, section `tutorial`). Au retour, le bouton est là dès l'accueil (« Aller à la course ») et dans chaque atelier.
- **Mode enfant** : 1 réussite suffit partout, « Passer » après 2 échecs, pas d'atelier « chute » (on ne chute jamais en mode enfant).
- **Multijoueur** : pas d'ateliers ; le tuto reste une course du départ à l'arrivée.
- **Anciens records du tuto** : le chrono ne couvre plus le même parcours. La médaille et le meilleur score de l'ancien tuto sont effacés une seule fois (`migrations/tuto_141`). Les anciens fantômes sont ignorés : seuls ceux marqués `tuto = 2` sont lus.
- **Petits ajouts ailleurs** :
  - `Player.teleport_to()` : retour au début de l'atelier, avec un fondu ;
  - `Player._pick_respawn_sample()` : demande d'abord au tuto ;
  - `TrickScore.last_bank_items` : les noms des éléments du dernier saut validé ;
  - `RaceHud.set_tutorial_intro()`.
- **Testé** :
  - bot qui joue tout le tuto : 9/9 ateliers, ~83 s jusqu'à l'arrivée, médaille d'or ;
  - bot qui rate exprès un atelier (nose, grappin, balancier) : boucle ou réapparition, indices, « Passer » au 5e échec, puis la suite normalement ;
  - modes enfant, Chill et « déjà fait » : OK ;
  - captures de l'accueil, d'un atelier, des échecs avec « Passer », de la course finale ;
  - temps des autres niveaux au bot inchangés (Flat 1:05,15, Nice Slope 52,17 s) ;
  - 130 fichiers OK.
  
  Deux bugs trouvés par les bots et corrigés :
  - en tombant dans le trou, le pingouin pouvait dériver sous l'autre bord et l'atelier « balancier » se validait ;
  - le petit trou de la course finale était trop dur à passer sans sauter : il est maintenant plus court et plus bas.
- **À régler en jouant** :
  - longueurs, tremplins et textes dans `workshop_specs` ;
  - seuils en tête de `TutorialCoach.gd` (`FAILS_BEFORE_SKIP`, `PUMP_STROKE_TIME`, `FEET_MIN_AIR`, `HOOK_MIN_TIME`…) ;
  - course finale : `final_length`, `final_ramps`, `final_gap_*`.

## 51. Grappin du tuto qui ne validait pas + atterrissage sur le ventre (21/11, version 1.42)

- **Retour de l'équipe** (vidéo) : dans l'atelier GRAPPIN du tuto, « je me balance pourtant ça ne marche pas ».
  - **Cause** : la réussite demandait la pointe du grappin à plus de 100 px au-dessus du pingouin. Or en se hissant ({pull}), Pinpouin arrive juste sous le plafond : le compteur de temps repartait à zéro à chaque image. Il fallait aussi obligatoirement tirer : se balancer sans tirer ne comptait jamais.
  - **Correction** (`TutorialCoach.gd`) : réussite après **1 s accroché au plafond en tout**, en se balançant ou en tirant, même en plusieurs fois. Consigne et indices du maître réécrits (« tu peux te balancer ou tirer : les deux comptent »).
  - Le bot passait, lui, parce qu'il s'accrochait de loin et tirait toujours. Il est maintenant testé aussi sans tirer.
- **Atterrissages** (`LandingStyle.gd`), demande de l'équipe : « si on atterrit sur le ventre, on glisse sur le ventre comme avant ; on n'est debout que si l'on tombe sur les pattes ».

  | Angle avec la pente juste avant le sol | 1.40 / 1.41 | 1.42 |
  |---|---|---|
  | bec en avant > 35° | nose (ventre + points) | nose (inchangé) |
  | entre −30° et +35° (à plat) | debout | **sur le ventre** (glisse d'origine) |
  | bec relevé de 30° à 120° (pattes vers le sol) | debout | **debout** |
  | au-delà de 120° | chute | chute (inchangé) |

  - Nouveau style d'atterrissage `"belly"` (signal `Player.landed`) ; réglage `FEET_ANGLE_DEG` = 30.
  - Atelier « SUR LES PATTES » du tuto : il faut maintenant relever le bec avec {rotate_trigo} avant de toucher le sol (consigne et indices réécrits).
- **Testé** : bot du tuto complet, avec et sans tirer au grappin : 9/9 ateliers, or à la course finale ; captures d'un atterrissage à plat (ventre) et bec relevé (debout) ; temps de Nice Slope au bot inchangé (52,17 s) ; 130 fichiers OK.

## 52. Défi figures chronométré : 704, 917 et Half-pipe en mode Score (21/11, version 1.43)

- **Demande de l'équipe** : « Dans le 704 et le 917, lance un chrono en mode Score : le but est juste de faire le meilleur score en figures, chrono 4 minutes. Dans le Half-pipe pareil, un chrono de 3 minutes. »
- **En mode Score** (`src/ui/race/TrickAttack.gd`, créé par `RaceManager._start_race`) :
  - compte à rebours en haut au centre : **4:00** pour 704 et 917, **3:00** pour le Half-pipe (`TIME_LIMITS`). Il s'arrête pendant la pause et la carte d'aide ;
  - dessous : les points de figures, le record et la prochaine médaille à décrocher ;
  - 10 dernières secondes : chiffres rouges et un bip par seconde ;
  - à 0 : une figure encore en l'air compte, le pingouin s'arrête, panneau « TEMPS ÉCOULÉ ! » (points, record, médaille), boutons **Rejouer** et **Menu** ;
  - les points se marquent comme partout (figures, vrilles, nose, combos ; une chute fait perdre le saut en cours).
- **En mode Chill** : rien ne change, glisse libre sans chrono.
- **Médailles en points** (`MEDAL_POINTS_GOLD`) : or = points d'un bot « joueur correct » qui fait une figure dès que le vol dure plus de 1,1 s (outil hors projet `trick_bot.gd`) ; argent = 65 % de l'or ; bronze = 35 %.

  | Niveau | Durée | Bot figures seules | Bot figures + nose | Bronze | Argent | Or |
  |---|---|---|---|---|---|---|
  | 704 | 4 min | 3450 | 11 800 | 1200 | 2300 | 3500 |
  | 917 | 4 min | 7100 | 23 000 | 2500 | 4600 | 7000 |
  | Half-pipe | 3 min | 6500 | 10 000 | 2300 | 4200 | 6500 |

- **Menu** (mode Score) : « 704 · 4 min · 2350 pts » avec la pastille de la meilleure médaille ; le texte sous Chill / Score l'annonce.
- **Carte d'aide** : « DÉFI FIGURES : 4 minutes pour faire le plus de points ! ».
- **Meilleur score / médaille** : enregistrés comme ceux des courses (sections `scores_v3` et `medals`).
- **Testé** : bot sur les 3 niveaux jusqu'au bout du chrono ; captures de l'aide, du chrono, de la fin et du menu ; 131 fichiers OK.

### Icône de l'exe Windows (21/11, 1.43)
- L'exe Windows avait l'icône de Godot. Il prend maintenant le pingouin ninja de l'appli Android (`icon.png`, agrandi en pixels nets) : nouveau fichier `icon.ico` (16 à 256 px), preset « Windows Desktop » : `application/icon = res://icon.ico`, `modify_resources = true` (Godot 4.7 l'écrit dans l'exe sans outil externe). Vérifié en relisant l'icône dans l'exe.

## 53. Retours du questionnaire : grappin vers l'arrière, interface trop petite (21/11, version 1.44)

Réponses relues dans Google Forms. Léo et Manu ont tous les deux testé sur téléphone Android.

- **Léo : « des fois le grappin part vers l'arrière, mais je sais pas trop dans quels cas »** ; Léo et Manu : grappin lancé « parfois » en visant un bouton.
  - **Cause trouvée (tactile)** : toucher la zone de jeu lance le grappin vers le point touché (1.11). Un pouce qui rate de peu un bouton de GAUCHE (◀ ▶ ↺ ↻, ou l'espace entre eux) touchait la zone de jeu : le grappin partait vers ce point, donc **derrière et sous** Pinpouin.
  - **Correction** (`TouchControls.gd`) : tout le pavé de gauche (rectangle autour des 4 boutons, marge 70 px, jusqu'au bas de l'écran) appartient aux boutons. Un toucher dedans prend le bouton le plus proche et ne lance jamais le grappin. Ailleurs, la zone de toucher des boutons passe de ×1,25 à ×1,4 leur taille.
  - **Même problème au clavier** : Espace visait la souris, même posée et oubliée dans un coin (souvent à gauche, derrière le pingouin). Maintenant (`Player._get_aim_direction`) : clic, ou souris bougée depuis moins de 2 s → on vise la souris ; sinon (Espace, souris immobile) → visée par défaut, vers l'avant et le haut.
  - Testé : touchers simulés entre les boutons de gauche, au bord de l'écran, sous ◀ → bouton ; au-dessus du pavé et à droite → grappin. Clavier : souris immobile → avant-haut ; clic ou souris bougée → vers la souris.
- **Manu : « taille de l'interface par défaut : trop petite »** (textes lisibles 3/5).
  - Sur téléphone, l'interface est agrandie de 15 % de plus (`Settings.MOBILE_UI_BOOST`) : ×1,15 à ×1,5 selon la taille de l'écran (avant ×1,0 à ×1,4). Toujours réglable dans Options → Taille de l'interface.
  - Les cartes d'aide (`ReadingPause`) se réduisent toutes seules si elles ne tiennent plus à l'écran (la plus longue, celle du Sans fin, dépassait à ×1,6).
  - Vérifié en captures sur un écran de téléphone simulé (2400 × 1080) à ×1,5 : menus, tuto, carte d'aide, HUD de course, défi figures.
- **« Appli non sûre » à l'installation (Léo)** : message d'Android pour tout APK installé hors du Play Store, impossible à supprimer depuis le jeu. Texte d'explication FR/EN à mettre sous le téléchargement Android sur itch.io (feuille de route).
- **Au passage** : si la scène changeait pendant une pause de lecture du maître ninja, le niveau suivant démarrait en pause (`MasterBubble._exit_tree`).
- Testé : tuto complet au bot (or), 131 fichiers OK.

## 54. Créateur de niveau dessiné (1.45, prototype)

Demande de l'équipe (21/11) : dessiner un niveau, les plateformes et les petits blocs pour le grappin se forment tout seuls.

- **Fichiers** : `src/levels/drawn/DrawnLevel.gd` (classe `DrawnLevel` : données du dessin, nettoyage du trait, îlots, trous, blocs de grappin, sauvegarde) ; `src/levels/drawn/DrawnGenerator.gd` + `src/levels/LevelDrawn.tscn` (copie de `LevelBateau.tscn`, seul le générateur change) ; `src/screens/LevelEditor.gd` + `.tscn` (l'éditeur). Bouton « Créer un niveau » ajouté à la grille de `LevelSelectionScreen.tscn`.
- **Nettoyage du trait** : points qui avancent vers la droite seulement → Ramer-Douglas-Peucker (14 px) → 3 passes de Chaikin → un point tous les 32 px → pente limitée à 60°. Un trait par-dessus un sol existant est coupé ; deux traits à moins de 70 px se recollent.
- **Construction** : chaque îlot = trait + fond commun 450 px sous le point le plus bas ; même rendu que les tremplins du tuto (remplissage bleu de `sol.tscn`, bordure `tile_ice_up_long1.png`) ; collision `BUILD_SEGMENTS` (correctif « vitesse → 0 »). Blocs de grappin : le poisson de glace du tuto (`StaticBody2DFish.tscn`), auto au-dessus des trous > 420 px (un tous les ~950 px, 600 px au-dessus du bord) + posés à la main. Murs avant le départ et au bout de la piste de freinage (1 600 px). Arrivée `FinishGate` au bout du dernier trait, `next_scene_path` = l'éditeur. La mort par chute vient de `Player._compute_fall_death_y` (rien à ajouter).
- **RaceManager** : `DRAWN_LEVEL` / `_is_drawn_level()` : pas de fantôme, pas de carte d'aide, record / score / médaille affichés mais jamais enregistrés.
- **Interface** : deux barres (haut : actions ; bas : outils, infos, TESTER) ; échelle = celle du jeu, réduite pour tenir dans l'écran (`_ui_scale`, téléphone 20:9 ≈ 1024 × 460 px logiques) ; reconstruite quand la taille de l'écran change. Deux doigts : déplacer + zoomer (le trait commencé est annulé).
- **Tests** (outils hors projet) : `editor_input_test.gd` (dessin, trait refusé, grappin, gomme, annuler, tout effacer, molette, deux doigts, sauvegarde : tout OK) ; `medal_bot.gd` sur un dessin tremblé synthétique : arrivée en 13,57 s en passant le grand trou au grappin ; joueur « naïf » sans grappin : aucune mort sur ce dessin (le grand trou se saute sur la bosse d'avant, d'où l'avertissement orange « conseillé » et pas « impossible ») ; retour à l'éditeur après l'arrivée en Chill ; aucun fichier de record écrit. Non-régression : Flat 65,15 s et NiceSlope 52,17 s inchangés ; check_all 136 fichiers, 0 échec.

## 55. Mes niveaux : plusieurs niveaux dessinés, record, médaille, fantôme (1.46)

Étape 3 du créateur, demandée le 21/11.

- **Stockage** : un fichier par niveau, `user://niveaux/<id>.json` (nom, dessin, empreinte, dates). L'id est fixe ; renommer ne le change pas. Un niveau vide n'est pas écrit. Au premier lancement, l'ancien `user://niveau_dessine.json` de la 1.45 devient « Mon niveau 1 » (le fichier d'origine est laissé en place).
- **Records** : `RaceManager._prepare_level` remplace le chemin réel `LevelDrawn.tscn` par un chemin virtuel `res://src/levels/LevelDrawn_<id>_<empreinte>.tscn` (`DrawnLevel.race_path()`). Tout le reste (fantômes, record, score, médaille, HUD) marche sans autre changement, rangé sous ce chemin. L'empreinte (md5 du dessin arrondi au 1/10 de px) change dès qu'on modifie le dessin : l'ancien record ne compte plus. L'éditeur prévient une fois ; « Annuler » retrouve le record tant qu'on reste dans l'éditeur ; les fantômes des anciens dessins sont effacés en sortant (`prune_ghosts`). Médaille : temps de référence (distance ÷ `REF_SPEED`), comme un niveau absent de `MEDAL_GOLD`.
- **Écrans** : `src/screens/MyLevelsScreen.gd/.tscn` (Jouer / Modifier / Supprimer en deux touchers / + Nouveau niveau ; record et médaille sur chaque ligne). Le bouton de la sélection devient « Mes niveaux · créer ». Éditeur : bouton du nom (toucher = fenêtre « Nom du niveau »), record dans la ligne d'infos, « Retour » vers Mes niveaux. `DrawnLevel.return_scene` : après JOUER, l'arrivée ramène à la liste ; après TESTER, à l'éditeur.
- **UiScaler** : la connexion `size_changed` est retirée quand le calque quitte l'arbre (avant : « Lambda capture was freed » dans le journal, et une erreur sur un calque retiré mais pas encore libéré).
- **Tests** : `mylevels_test.gd` (reprise 1.45, 2e niveau, renommage, record dans l'éditeur, avertissement, Annuler, suppression en deux touchers : tout OK) ; deux courses au bot en Score sur le niveau repris : record + médaille argent à la 1re, fantôme chargé à la 2e, même empreinte d'un lancement à l'autre ; captures téléphone 2400 × 1080 ; `editor_input_test.gd` OK ; non-régression Flat 65,15 s, tuto complet (13,4 à 14,3 s selon les parties, même dispersion qu'avant), check_all 138 fichiers, 0 échec.

## 56. Partage des niveaux dessinés et Niveaux de la communauté (1.47)

Demande de l'équipe (21/11) : partager un niveau, et pouvoir l'exporter pour ajouter au jeu les niveaux qu'on trouve cool. Choix : section à part « Niveaux de la communauté », fantôme inclus au choix.

- **Code** (`DrawnLevel` partie 6) : `PINPOUIN-NIVEAU:1:<taille>:<base64>:FIN`, même principe que les fantômes en texte (`var_to_bytes` → zstd → base64). Il contient le nom, l'auteur, le dessin et, au choix, le meilleur fantôme. ~3,5 Ko sans fantôme, ~14 Ko avec pour un niveau de 15 000 px. On peut le coller au milieu d'un message, retours à la ligne compris.
- **Import** : `decode_code` vérifie tout (taille, version, `bytes_to_var` sans objets, nombres finis et bornés, 300 traits / 40 000 points max). `import_level` ajoute le niveau à « Mes niveaux » avec un nouvel id et garde son auteur. Un nom déjà pris devient « Nom (2) ». Un dessin déjà présent n'est pas dupliqué, seul son fantôme est ajouté. Le fantôme est rangé sous le chemin de record du niveau (`<chemin>_ami_<date>.ghost`).
- **Fichier** : `.pinpouin` = le code dans un fichier texte. Sur PC, il va dans `user://niveaux_exportes` (dossier ouvert) ; dans le navigateur, il est téléchargé (`JavaScriptBridge.download_buffer`). Sur téléphone, on passe par le code.
- **Auteur** : « Ton nom de créateur », demandé dans la fenêtre Partager et gardé dans `pinpouin.cfg` (`creator/author`). Un niveau reçu garde l'auteur d'origine.
- **Niveaux de la communauté** : fichiers JSON dans `res://src/levels/drawn/officiels/` (format d'un niveau + `order` + `gold_time`). Vérifié : ils sont bien dans le jeu exporté (pck) et listés par `DirAccess`. Écran `CommunityLevelsScreen.tscn` (même script que Mes niveaux, `community = true`) : seulement Jouer, avec l'auteur ; pas de bouton « Éditer » en course ; `save()` refuse d'écrire un niveau officiel. Records sous l'id `off-<fichier>`. L'or vient de `gold_time` (`RaceManager`, après `MEDAL_GOLD`).
- **Ajouter un niveau officiel** (outils hors projet) : `add_official.gd -- <fichier du code> <slug> [ordre] [nom] [auteur]`, puis `official_bot.sh <slug>` (bot avec et sans figures, or = meilleur temps arrondi à la demi-seconde au-dessus, écrit dans le fichier). Exemple livré : « Première glisse » par « Claude (exemple) », or 13,5 s (bot 13,42 / 13,57). Pour le retirer, effacer son fichier.
- **Tests** : `share_test.gd` entre deux dossiers de joueur (export, import, auteur, même empreinte, fantôme repris, doublon, message avec retours à la ligne, code coupé, texte quelconque, code de fantôme, nombres absurdes, nom en double) : tout OK. Captures PC et téléphone des fenêtres. Non-régression : `editor_input_test`, `mylevels_test`, Flat 65,15 s, check_all 139 fichiers, 0 échec.

## 57. Médailles de « Hook, you fool ! » mesurées pour de vrai (21/11, pour la 1.48)

- **Avant** : l'or (97 s) était **estimé**, parce que le bot « bon joueur » ne passait pas les trous de ce niveau. Il lançait le tremplin du départ droit dans le bord avant du plafond du couloir, et tombait (45 chutes en 400 s).
- **Nouveau bot** (`gap_bot.gd`, hors projet, copie de `medal_bot.gd`), réglé en essayant plusieurs façons de faire :
  - il accroche le poisson presque à la verticale (moins de 150 px devant) ; accroché trop tôt, il faisait un tour complet et perdait toute sa vitesse ;
  - il lâche quand la corde fait environ 25° de l'autre côté de la prise, en remontant (`REL = 0,4` × longueur de corde) ;
  - sans poisson à portée, il s'accroche au **plafond du couloir**, au point le plus loin devant (grand balancier). Il ignore le dessous des îles flottantes (vide en dessous) : un joueur ne ramperait pas dessous.
- **Fausse alerte au passage** : le bot semblait « coincé dans la glace ». En fait, les îles de ce niveau sont des bandes d'environ 300 px d'épaisseur avec du vide dessous, et il pendait SOUS une île en s'accrochant à son dessous. Ce n'est pas un bug du jeu, rien n'a été changé dans le pingouin.
- **Résultat** : course sans chute en **85,57 s** avec figures (89,3 à 95,6 s selon les réglages, 90,1 s sans figures). Le terrain est le même à chaque partie (les trous ne dépendent pas du seed).
- **Nouvelles médailles** (`RaceManager.MEDAL_GOLD["LevelRandomGap"]`) : or **86 s** (avant 97), argent 1:47,5, bronze 2:17,6. Une médaille déjà gagnée reste gagnée.

## 58. Enquête « ralentissements » et compteur de vitesse (21/11, pour la 1.48)

**Enquête** (aucun changement de physique, seulement des mesures). Outils hors projet : `speed_probe.gd` (relève la vitesse à chaque image et cherche la cause de chaque perte), branché sur les bots (`probe_endless.gd`, `probe_medal.gd`). Environ 40 min de jeu au bot (Sans fin normal / Chill / sans grappin, 9 niveaux de course).
- **Aucun ralentissement sans cause.** Les pertes viennent : du tremplin de départ (montée), des chocs contre le flanc d'une île (saut raté), des morts (réapparition à 450 px/s en Sans fin, `EndlessGenerator.respawn_sample`), du grappin, et du plafond de vitesse au sol.
- **Grappin** : à l'accroche, le pingouin perd en moyenne un tiers de sa vitesse en UNE image (75 accroches, 3 sur 4 au-dessus de 25 %). `HookingInAirState.swing()` retire toute la vitesse dans l'axe de la corde, même quand on fonce VERS le crochet (une vraie corde ne retient que si on s'éloigne). `pull_original()` borne aussi la vitesse horizontale à 1000 (`MAX_SPEED_HOOKED`).
- **Au sol** : pas de frottement caché (somme vitesse + hauteur constante, à quelques px/s près). 75 % de la vitesse perdue au sol vient du plafond doux `ground_max_speed = 1450` (`Player._apply_soft_speed_caps`, `over_speed_drag = 1.5`), plus bas que celui en l'air (1750) : après un gros saut, on perd jusqu'à 20 % en 1,5 s (1989 → 1566), même en descente. Petit à-coup de 3-4 % quand un plat rejoint une montée de ~15° (deux surfaces touchées à la fois, `_apply_godot3_slide`).
- Rien n'a été modifié : ce sont des choix de réglage à faire avec l'équipe (et les médailles seraient à remesurer).

**Compteur de vitesse** (demande de l'équipe) : Options → « Afficher la vitesse de Pinpouin » (`Settings.show_speed`, coupé par défaut), ou **F3** en jeu.
- `src/ui/race/SpeedMeter.gd` : en haut à droite, sous le bouton pause tactile : km/h (55 px = 1 m, même échelle que les distances du Sans fin), px/s et « au sol / en l'air / grappin », jauge 0 → 2200 px/s avec un trait blanc (plafond au sol) et un trait bleu (plafond en l'air). La jauge devient **orange** quand le frein doux agit.
- Créé par `RaceManager._start_race()` dans tous les niveaux, solo et multi (pingouin local). En multi, le classement de `RaceHud` passe sous le compteur quand il est affiché.
- **Tests** : check_all 140 fichiers, 0 échec ; captures PC (course + Sans fin) et téléphone (Options).

## 59. Physique réelle : résistance de l'air + frottement à la place des plafonds (21/11, pour la 1.49)

**Décision de l'équipe** après l'enquête de la section 58 : partir de principes physiques plutôt que de freiner le pingouin au-dessus de 1450 px/s au sol et 1750 en l'air.

- **Ce qui change** (`Player._apply_air_drag_and_friction`, appelée par `_apply_soft_speed_caps`) :
  - **Résistance de l'air** en k·v², la même au sol et en l'air : plus de changement de règle en touchant le sol. Avec la gravité, elle crée toute seule une vitesse limite qui dépend de la pente, v_lim = √(g·sin θ / k). Réglage `drag_terminal_speed` = vitesse limite sur 10° de pente (k en est déduit, avec la gravité du moment).
  - **Frottement de glisse** au sol (Coulomb), μ·g·cos θ, très faible sur la glace (`ground_friction` = 0,02, soit 16 px/s²). Il ne fait jamais changer de sens.
  - Rien pendant le grappin, comme avant. Le PUMP reste volontairement « non physique » (il ajoute de l'énergie).
  - Boost de figure préservé : pendant le boost, l'air ne freine que la vitesse au-delà de la part « boost » (qui décroît comme l'ancien plafond relevé).
  - `realistic_physics = 0` remet exactement l'ancien système. C'est le premier curseur du panneau F2, pour comparer en jouant.
- **Réglage aux bots** :
  - 1600 px/s sur 10° (premier essai) : le plat était trop freiné (Flat 73,95 s au lieu de 65,15) et le trou « grappin » du Sans fin ne passait plus (0/14).
  - Cause du trou raté : la vitesse d'APPROCHE. Avant, la gravité poussait au-delà de 1450 sur les îles en légère descente (le bot arrivait à 1550-1630). Maintenant, l'air le retient et le PUMP s'arrêtait à 1450.
  - **Retenu : `drag_terminal_speed` = 2000** (≈ 1790 px/s sur 8°, 2440 sur 15°, 2830 sur 20°) et **`pump_max_speed` 1450 → 1650**.
- **Validation** :
  - Sans fin par type de trou : saut 37/37, grand saut 30/31, grappin 22/23, double 15/15, montée 24/24, plafond 11/11.
  - Tuto complet 9/9 ateliers.
  - Toutes les courses terminées, Hook you fool sans chute.
  - Atterrissage rapide dans une descente : 1981 → 2027 px/s une seconde plus tard (avant : 1989 → 1566).
  - Vitesse max relevée : 2534 px/s (Nice Slope).
- **Médailles remesurées** (`RaceManager.MEDAL_GOLD`, `TrickAttack.MEDAL_POINTS_GOLD`) :

  | Niveau | Bot avec figures | Bot sans | Or 1.49 | Or 1.48 |
  |---|---|---|---|---|
  | Tutoriel (course finale) | — | 12,72 à 12,97 s | 13 s | 13,5 s |
  | Flat and fun | 61,55 s | 64,15 s | 62 s | 64 s |
  | Corridor | 62,00 s | 64,85 s | 62 s | 66,5 s |
  | Nice Slope | 36,88 s | 41,32 s | 37 s | 49,5 s |
  | Spaghetti (12 terrains) | 32,3 à 40,5 s | 32,9 à 38,4 s | 38,5 s | 33,5 s |
  | Hook, you fool ! | 89,03 s | chute | 89 s | 86 s |
  | Défi figures 704 / 917 / Half-pipe | 3600 / 7100 / 5300 pts | — | 3500 / 7000 / 5500 | 3500 / 7000 / 6500 |
  | Première glisse (communauté) | 13,08 s | 13,07 s | 13,5 s (inchangé) | 13,5 s |

  Spaghetti : terrain au hasard à chaque partie, l'or couvre 11 terrains sur 12 (un terrain difficile à 40,5 s). Half-pipe : l'air raccourcit un peu les sauts.
- **Sans fin** : échelle des mètres inchangée (55 px = 1 m, pour ne pas fausser les records). Le bot grappin fait maintenant 3,5 à 5,7 km avant sa 3e chute (avant : 5,0 à 8,0) : l'or (5 km) est un peu plus dur.
- **Records et fantômes** : ceux faits avant restent, mais la physique a changé ; sur Nice Slope en particulier, les anciens temps seront faciles à battre.
- **Compteur de vitesse** (`SpeedMeter.gd`), avec la nouvelle physique : un seul repère blanc = la vitesse limite de la pente sous Pinpouin ; orange = il perd de la vitesse ; pente affichée (« au sol · descente 11° »). Jauge jusqu'à 3000 px/s.

## 60. TAIL comme le NOSE, équilibre sur la tail, roulade pour les figures ratées (21/11, pour la 1.50)

Demande de l'équipe : le « tail » (atterrissage bec relevé, glisse debout) doit marcher comme le nose ; pendant la glisse debout, pouvoir basculer vers le ventre ou vers le dos (chute) ; et la roulade de la chute aussi pour une figure ratée, avec « 1 s pour tous » au lieu de 2 s.

- **TAIL !** (`LandingStyle.TAIL_POINTS` = 50, `TrickScore._on_landed`, style `"feet"` inchangé pour le tuto) : un atterrissage bec relevé ajoute « Tail » aux éléments du saut. Il compte dans le combo, s'affiche « +50 TAIL ! » et donne le boost de figure. L'atelier « Figures » du tuto ne le prend pas pour une figure (comme Nose et Vrille).
- **Équilibre sur la tail** (`LandingStyle._update_tail_balance`, choix de l'équipe : touches de rotation) : pendant la glisse debout, la touche « vers l'avant » (horaire en allant à droite) penche Pinpouin vers le ventre ; « vers l'arrière » (trigo) vers le dos. Le sens suit le sens de la glisse, comme pour le nose.
  - Penché de 35° vers l'avant (`TAIL_TO_BELLY_DEG`, ~0,25 s d'appui) : il se couche et glisse sur le ventre, avec un petit « flop » de neige. Rien à gagner (choix de l'équipe).
  - Penché de 70° vers l'arrière (`TAIL_FALL_DEG`, ~0,5 s d'appui) : chute, avec la même roulade que sur le dos. En relâchant avant, il se redresse tout seul (`TAIL_RETURN_SPEED_DEG`).
  - Seul le dessin penche (`tail_tilt`) : la physique de la glisse ne change pas. Mode enfant : jamais de chute.
- **Figure ratée** (`TrixState`) : toucher le sol en pleine figure fait maintenant la roulade (neige + 0,5 s de roulade + 1 s étourdi, `CrashState`) au lieu de rester sonné 2 s arrêté net. Les points du saut sont perdus tout de suite (« Raté ! »). Mode enfant : pas de roulade, étourdi 1 s.
- **1 s pour tous** : `StaggeredState.staggered_time` 2 → 1 s.
- **Bug évité au passage** : à chaque début de niveau, Pinpouin apparaît en l'air et retombait bec relevé sur le tremplin de départ. Il aurait gagné un « TAIL ! » gratuit (points + boost). Le premier contact après une apparition ne compte plus (`LandingStyle.fresh_spawn`, remis à vrai par une réapparition et par le retour au début d'un atelier du tuto).
- **Tuto** : consigne de l'atelier « Sur les pattes » complétée (TAIL, bascule vers le ventre, chute en arrière) + un indice.
- **Testé** :
  - bot qui atterrit bec relevé : « +50 TAIL ! », puis ventre en 0,25 s (scénario A), chute + roulade + étourdi 1 s + repart (scénario B) ; figure lancée juste avant le sol : roulade puis 1 s étourdi (scénario C) ;
  - plus de TAIL au départ ;
  - tuto complet 9/9 (normal et mode enfant) ;
  - Flat 61,55 s et Nice Slope 36,88 s inchangés ; Sans fin sans chute ;
  - défis figures : 917 = 7100 et Half-pipe = 5300 inchangés. 704 = 2600 au lieu de 3600 : ce n'est pas une régression, ce score du bot est très sensible (2800 à 3700 en changeant le frottement de 0,019 à 0,021) ; or 3500 gardé ;
  - check_all 140 fichiers, 0 échec.

## 61. Chute plus courte avant la réapparition (21/11, version 1.51)

Retour de l'équipe : « on chute pendant longtemps, raccourcir ce temps pour que ce soit moins frustrant d'attendre ».

- **Avant** (mesuré aux bots, du moment où Pinpouin quitte le sol jusqu'à la réapparition) : 3,0 s dans le Sans fin, 4,3 à 6,1 s dans les courses. Seules deux règles existaient : passer 1500 px sous le point le plus bas du niveau, ou 4 s de chute rapide.
- **Règle 3, « chute sans retour »** (`Player._is_doomed_fall`, réglages `doomed_fall_depth` = 600 px, `doomed_confirm_time` = 0,15 s). On réapparaît dès que tout est vrai à la fois :
  - en l'air, en train de descendre, sans grappin accroché ni lancé ;
  - au moins 600 px sous le dernier appui (sol ou grappin) : les prises de grappin, 600 px au-dessus du bord des trous, sont alors hors de portée (1200 px) ;
  - aucun sol sous lui jusqu'au fond du niveau (s'il y a une piste plus bas, comme dans Spaghetti, il atterrit dessus) ;
  - sa trajectoire ne touche rien pendant 1,2 s.
  `doomed_fall_depth = 0` désactive la règle.
- **Vérifiée « à blanc »** (outil hors projet `doom_check.gd`) : la règle est coupée, et on note chaque fois qu'elle aurait tué, puis ce qui se passe vraiment. Sur 129 cas (Sans fin sans grappin, sans saut, LevelRandom, SlightOffset, Hook you fool sans grappin), Pinpouin est mort à chaque fois : **0 fausse alerte**. Sur les parties où le bot passe ses trous (6 types du Sans fin, Spaghetti et ses pistes empilées), elle ne s'est jamais déclenchée par erreur.
- **Après** : 1,4 s dans les courses (avant 4,3 à 6,1 s), 2,25 s dans le Sans fin (avant 3,0 s ; Pinpouin y saute avant de tomber, il part donc de plus haut).
- **Sans fin** : on réapparaît à **1000 px/s** au lieu de 450 (`EndlessGenerator.RESPAWN_SPEED`), pour ne plus « ramer » après une chute. Le bot grappin fait maintenant 5,1 à 7,2 km avant sa 3e chute (3,5 à 5,7 en 1.49-1.50) ; le pont magique du mode enfant marche toujours.
- Non-régression : tuto complet, Flat 61,55 s, Nice Slope 36,88 s, Hook you fool 89,03 s, défis figures et niveau de la communauté inchangés ; check_all 140 fichiers, 0 échec.
- **Au passage** : les figures sont tirées au hasard à chaque saut (`TrixState`, `randomize()`). Le temps du bot qui fait des figures varie donc d'une partie à l'autre : une figure longue qui n'a pas le temps de finir donne une roulade. Exemple : Corridor 62,00 s ou 76,82 s.

## 62. Chute sans retour plus prudente : grappin à portée et longs sauts (21/11, version 1.52)

Retour de l'équipe sur la 1.51 : « la chute dans le vide apparaît trop rapidement des fois ; ne l'active que quand chaque plateforme aux alentours est trop loin pour être grappinée. Attention aux longs sauts, qu'ils ne soient pas pris pour une chute. »

- **Longs sauts** : la trajectoire est maintenant suivie jusqu'au fond du niveau (6 s max, `DOOMED_LOOKAHEAD`), plus seulement 1,2 s. Test sur un niveau dessiné (outil hors projet `longjump_setup.gd`) : tremplin, grand vide sans grappin, piste 3000 px plus bas et loin devant. En 1.51, Pinpouin réapparaissait en plein vol (à x = 6237) alors qu'il allait atterrir ; en 1.52, il atterrit. Si la piste est ratée (3500 px plus bas, à partir de x = 8500), la réapparition n'arrive qu'une fois la piste dépassée.
- **Prises à portée** (`Player._has_rescue_hook_in_reach`, 32 rayons tout autour, longueur du grappin 1200 px, masque du grappin) : pas de réapparition tant qu'une prise UTILE est à portée :
  - tout ce qui est à la hauteur du bord d'où il est parti, ou plus haut (blocs, plafonds, coin du bord) ;
  - le dessus d'une plateforme, même plus bas sur le côté.
  Ne comptent pas : le dessous d'une plateforme et les murs plus bas que ce bord. Premier essai avec les dessous : en tombant, Pinpouin dérive souvent sous l'île suivante, et la règle ne se déclenchait plus jamais dans le Sans fin (3 s, comme en 1.50).
- **Vérifié à blanc** (`doom_check.gd`) : 0 fausse alerte (Sans fin 6 types de trous, sans grappin, sans saut ; LevelRandom, SlightOffset, Hook you fool avec et sans grappin, Spaghetti).
- **Durée des chutes** (quitter le sol → réapparition) :

  | | 1.50 | 1.51 | 1.52 |
  |---|---|---|---|
  | Courses (LevelRandom, SlightOffset) | 4,3 à 6,1 s | 1,4 s | 1,7 à 1,9 s |
  | Sans fin | 3,0 s | 2,25 s | 2,25 s |

- Non-régression : tuto complet (or), Hook you fool 89,03 s sans chute, Sans fin (grappin 25/25, double 18/18, plafond 14/14…) ; check_all 140 fichiers, 0 échec.

## 63. Grappin (option d'essai), glisse lissée, médailles ajustées (21/11, version 1.53)

- **Coup de frein du grappin à l'accroche** (enquête 1.48 : un tiers de la vitesse perdue en une image) : essayé de trois façons, gardé **en option** (`Player.hook_keep_speed`, panneau F2 « Grappin : garder la vitesse à l'accroche », **0 par défaut** : comportement d'origine).
  1. « Corde molle » (ne retenir que quand la corde est tendue) : la petite traction élastique vers le crochet s'accumulait et aspirait Pinpouin vers la prise. Abandonné.
  2. Garder toute la vitesse à l'image de l'accroche (réorientée le long du balancier) : prise droit devant à la même hauteur → Pinpouin envoyé à la verticale à 1450 px/s. Dans le mode « traction », ne plus brider à 1000 px/s → il s'écrasait dans le bloc de glace et restait pendu dessous. Grappin double du Sans fin : 6-7 sur 17 au lieu de 18/19.
  3. Version gardée en option (`HookingInAirState.swing`, seulement à l'image de l'accroche) : réorientation progressive selon l'angle d'arrivée (toute la vitesse gardée si on arrive de biais, comportement d'origine si on fonce droit sur la prise). Encore 7 sur 16 au grappin double pour le bot : à essayer en jouant avant de décider. Le mode « traction » garde son plafond de 1000 px/s.
  Par défaut, rien ne change (vérifié : Hook you fool 89,03 s, grappin double 19/19, comme en 1.52).
- **Glisse lissée** (`Player._apply_godot3_slide`, `SMOOTH_KINK_MAX_DEG` = 25°, `was_grounded_before_move`) : au sol, sur une cassure de pente de moins de 25° (un plat qui rejoint une montée…), Pinpouin garde la vitesse qu'il avait le long de l'ancien sol au lieu de perdre 3-4 % en une image. Ne crée pas de vitesse (seule la vitesse le long de l'ancien sol est reprise), ne touche pas aux atterrissages ni aux chocs (grand angle). Mesuré : plus aucun à-coup de plus de 30 px/s en une image sur Flat, Corridor, Nice Slope, Spaghetti.
- **Non-régression** : Sans fin saut 46/46, grand saut 38/39, grappin 27/27, double 18/18, montée 29/30, plafond 14/14 ; tuto complet (normal et mode enfant) ; défis figures 704 2850 / 917 7900 / Half-pipe 5300 (or inchangés : 3500 / 7000 / 5500) ; Première glisse 12,90 s (or 13,5 inchangé) ; Sans fin Score 3,7 à 5,6 km.
- **Médailles ajustées** (courses un peu plus rapides avec la glisse lissée) : Corridor 62 → **61,5 s** (bot 61,13 s), Hook you fool 89 → **86,5 s** (bot 86,27 s), Tutoriel 13 → **13,5 s** (bot 12,38 à 13,27 s selon les figures tirées : 13 s était trop juste). Inchangés : Flat 62 s (bot 61,70), Nice Slope 37 s (bot 36,68), Spaghetti 38,5 s (bot 31,7 à 37,5 s sur 8 terrains).
- **Questionnaire Google** mis à jour pour la 1.53 : titre, version, figure ratée (roulade + 1 s), médailles remesurées, et 5 nouvelles questions (nouvelle glisse, TAIL et équilibre, durée des chutes, compteur de vitesse, option d'essai du grappin).

## 64. Pas de pump pour grimper un mur, sauf accroché au grappin (21/11, version 1.54)

- **Le problème** : sur un mur presque vertical (côtés du half-pipe), PUMP donnait quand même de la vitesse. Chaque nouvel appui ajoute `pump_impulse` (+90 px/s) et l'accélération continue s'y ajoute : en tapotant, on battait la gravité et on remontait le mur sans élan ni grappin.
- **Choix de l'équipe** :
  - « mur » = surface sous Pinpouin plus raide que **75°** (`Player.PUMP_WALL_DEG`) ;
  - bloqué **en montée seulement** : en redescendant le mur, le pump accélère comme avant (le geste normal du half-pipe) ;
  - **autorisé** si Pinpouin est bien accroché : grappin qui tient **et** crochet plus haut que lui.
- **Code** :
  - `Player.pump_blocked_on_wall()` décide ; `Player.apply_pump_accel(delta)` et `Player.apply_pump_impulse()` reprennent la formule de `PumpState` (1.10) **sans la changer**, sauf ce blocage.
  - `PumpState` appelle ces deux fonctions.
  - `HookingOnGroundState` n'avait aucun pump (accroché au sol, PUMP ne faisait rien) : il l'applique maintenant **uniquement** sur un mur avec le crochet au-dessus. Partout ailleurs, accroché au sol, rien ne change.
- **Mesuré** (`wallonly_test.gd` : posé au fond du half-pipe à 900 px/s, PUMP pressé seulement sur le mur) :

  | Hauteur atteinte | sans pump | pump tenu | pump tapoté |
  |---|---|---|---|
  | 1.53 | 489 px | 564 px | 689 px (sort du half-pipe) |
  | 1.54 | 489 px | 487 px | 487 px |
  | 1.54, grappin accroché au-dessus | 661 px | 692 px | 631 px |

- **Non-régression** (même résultat qu'en 1.53) : Nice Slope 41,17 s, Flat 63,02 s (bot sans figures), défi Half-pipe 11 500 points (11 650 en 1.53, figures tirées au hasard), tuto complet (or), Sans fin grappin 11/11, double 5/5, montée 7/7, plafond 2/2 ; check_all 140 fichiers, 0 échec.

## 65. Bandeaux d'arrivée qui s'effacent (21/11, pour la 1.55)

- **Demande de l'équipe** : le bandeau « BRAVO ! Reste faire des figures autant que tu veux » (Chill) prend trop de place pendant les figures dans le half-pipe ; pareil pour le panneau de résultat du mode Score.
- **Fait** (`RaceHud._show_then_fade`, réglages `FADE_DELAY` = 3 s, `FADE_TIME` = 0,8 s, `FADE_ALPHA` = 0,15) : le bandeau Chill et le panneau de résultat (solo et multi) restent bien lisibles 3 s, puis deviennent presque transparents par un fondu doux. Ils ne disparaissent pas complètement.
- Si le texte change (en multi : « 2 / 3 arrivés », classement), le bandeau redevient lisible 3 s. Même texte renvoyé : rien ne bouge (pas de clignotement).
- Pas touché : le compte à rebours « BONUS HALF-PIPE : N s » du mode Score (info qui change chaque seconde, sans fond).
- **Testé** (`fade_test.gd`) : opacité 1,00 à 2,9 s, 0,57 à 3,4 s, 0,15 à 4 s et après ; rappel avec le même texte : reste à 0,15 ; nouveau texte : revient à 1. check_all 140 fichiers, 0 échec.

## 66. Tuto : une seule réussite, pause au moment du geste, bulle qui s'efface, falaises (21/11, pour la 1.55)

Demande de l'équipe : ne plus redemander plusieurs fois le même geste ; mettre la pause AU MOMENT où il faut agir, en montrant le bouton selon l'appareil (PC, téléphone, manette) ; texte qui s'efface ; un atelier pour grimper une falaise avant la course finale. Choix de l'équipe : on repart en appuyant sur le bon bouton (l'action se fait tout de suite) ; pause à la 1re tentative seulement ; bulle effacée selon la longueur du texte ; falaise simple au grappin puis une plus difficile.

- **Une réussite par atelier** (`need` = 1 dans `BateauGenerator.workshop_specs`).
- **Invites « Appuie sur… »** (`src/levels/tutorial/ActionPrompt.gd`, nouveau) :
  - le jeu se fige (`Engine.time_scale = 0` : le pingouin ne bouge plus mais lit encore les touches, donc l'appui fait l'action tout de suite ; une vraie pause cachait les boutons tactiles) ;
  - le bouton affiché dépend de l'appareil : touche du clavier, bouton de manette, ou bouton tactile entouré d'un cercle jaune qui « respire » ;
  - modes : appuyer, relâcher (lâcher le grappin au bon moment) ;
  - le temps est toujours remis à 1 en sortant (changement de scène compris) ; option coupée (`Settings.tutorial_pause`, renommée « Tuto : figer le jeu sur les gestes ») : l'invite s'affiche sans figer ;
  - le panneau se place pour ne jamais cacher Pinpouin.
- **Moments des invites** (`prompts` de chaque atelier, `TutorialCoach._prompt_ready`) : au sol / dans une descente, au bord d'un tremplin, juste après le décollage, juste avant le sol (0,22 s : un appui maintenu ne peut pas dépasser ~80° de rotation, donc pas de chute), plus tôt pour l'atelier chute (0,45 s), sous le plafond, accroché, quand une prise est dans l'axe du grappin lancé sans viser (45°), quand lâcher le balancier fait retomber de l'autre côté du trou, au-dessus du bord d'une falaise. Seulement à la 1re tentative ; après un échec, seulement l'indice du maître.
- **Plus de pause en entrant dans un atelier** ; la bulle du maître reste lisible le temps de la lire (15 caractères par seconde, 3 à 10 s) puis devient presque transparente (`MasterBubble._show_then_fade`).
- **Deux ateliers falaise** avant la course finale (11 ateliers au lieu de 9) :
  - FALAISE : un mur de 500 px, une prise (boule de glace dessinée en code) au-dessus du bord ; grappin, tirer, lâcher au-dessus ;
  - GRANDE FALAISE : deux murs de 500 px en escalier avec une marche de 1000 px ; le même geste deux fois.
  - Bloqué au pied d'un mur 1,2 s = échec et retour au début de l'atelier.
  - La caméra garde la prise à grimper dans le cadre (`AdaptiveCamera.focus_point`).
  - Premiers essais ratés aux bots : gros blocs « poisson » (le grappin accrochait leur coin, Pinpouin restait pendu contre la paroi) ; un seul mur de 1000 px avec une prise basse devant (Pinpouin, projeté en tirant, restait posé sur la prise).
- **Grappin** (`HookingInAirState.swing`) : pendu presque à la verticale et presque immobile, « tirer » ne faisait rien (sortie anticipée du code d'origine). Corrigé seulement quand on tire. Vérifié : Hook you fool 86,27 s (comme en 1.53), Sans fin grappin 9/9, double 5/5 et 30/30, montée 7/7, plafond 4/4.
- **Manette** : « Avance avec {move_right} » affichait « (aucun bouton manette) » ; maintenant « Stick gauche ▶ » (`TutorialSign._binding_text`).
- **Testé** (`tuto_prompt_bot.gd`, élève qui ne fait QUE ce que disent les invites) : les 11 ateliers réussis du premier coup au clavier, à la manette, au tactile et en mode enfant ; captures PC et téléphone ; course finale inchangée (12,85 s, or 13,5) ; check_all 141 fichiers, 0 échec.
- **Retour de l'équipe sur la capture du tuto (même soir, 1.55b)** : la bulle et le panneau « Appuie sur… » au milieu de l'écran faisaient doublon, et le panneau cachait l'action.
  - L'invite passe **dans la bulle** (`MasterBubble.show_prompt`) : petit titre « APPUIE SUR » (« TOUCHE » sur téléphone), le bouton en gros, puis ce que ça fait. Le milieu de l'écran reste libre ; le voile léger (sous la bulle) et le cercle jaune autour du bouton tactile restent. Le panneau du milieu ne sert plus que si aucune bulle n'est donnée.
  - Après l'action, la bulle dit un **rappel court** du geste en cours (champ `after` de chaque invite, ex. « Tire… et lâche Espace une fois au-dessus du bord »), qui s'efface ensuite.
  - Choix de l'équipe : c'est **PINPOUIN** qui parle (titre de la bulle d'accueil, avant « LE MAÎTRE NINJA »), « Salut, c'est moi, Pinpouin ! ».
  - Re-testé : 11 ateliers sur 11 du premier coup au clavier, à la manette et au tactile, 10 sur 10 en mode enfant ; captures PC et téléphone.
- **Retour de l'équipe sur une vidéo du tuto (même soir, 1.55c)** : un igloo du décor au milieu de la falaise ; en bas de la descente, deux bouts de terrain l'un dans l'autre ; demande d'une falaise « plus montagne », moins verticale.
  - **Paroi rocheuse** (`BateauGenerator.FACE_PROFILE`) : sections à 78°, 90°, 100° (petit surplomb), 84°, 76°, puis un haut de paroi arrondi. Choix de l'équipe : 75° et plus, jusqu'à 90-100° par endroits. Sommet bombé (`SUMMIT_DOME` = 60 px) au lieu d'un plateau plat, épaulement presque plat entre les deux parois de la grande falaise. Bordure de glace sur les dessus seulement (une seule ligne du sommet jusqu'au bas de la descente).
  - **Un seul terrain** : la falaise est dessinée par-dessus la piste (`z_index` = 5) et son dessous suit la piste (`CLIFF_UNDER` = 90 px sous la surface) : on ne voit plus la bordure de la piste à travers la falaise, et la descente rejoint la piste en douceur.
  - **Décors cachés** sous la falaise (igloo, glaçons… de la piste : `visible = false`, rien n'est supprimé).
  - Prises placées après le HAUT de la paroi (`cliff_face_tops`) ; l'invite « lâche » s'y réfère.
  - Re-testé : 11 ateliers sur 11 du premier coup au clavier, à la manette et au tactile, 10 sur 10 en mode enfant ; captures des parois et des descentes.
- **Atelier CHEMINÉE (1.55d, demande de l'équipe)** : dernier atelier avant la course (12 ateliers). Un couloir de 600 px entre un rocher suspendu à gauche (on glisse dessous) et un grand massif à paroi droite à droite. On grimpe en zigzag : prise de droite, de gauche, de droite, de gauche, puis la prise au bord du sommet de droite (5 prises, choix de l'équipe), on se pose sur le replat et on redescend vers la course (`BateauGenerator._add_chimney`).
  - Les prises sont calculées de bas en haut : chacune est dans l'axe du grappin lancé sans viser (45°) depuis l'endroit où Pinpouin pend sous la précédente.
  - Invites : grappin, tirer, puis pour chaque prise « balance-toi vers la gauche / la droite » (sans figer : il faut voir le mouvement ; `freeze` = false) et « relance le grappin » quand la prise suivante est dans l'axe (`aim_swing`), enfin tirer et lâcher au-dessus du sommet.
  - Pendu immobile sous une prise, Pinpouin ne peut pas se retourner (il regarde du côté où il allait) : au moment de l'appui, le tuto le tourne vers la prise montrée (`ActionPrompt.face_dir`).
  - La caméra suit la prochaine prise au-dessus de Pinpouin.
- **Correction du gel (1.55d)** : pendant un gel, le pingouin n'est plus seulement « au ralenti zéro » mais arrêté (`process_mode` DISABLED). Avant, des forces du jeu qui ne dépendent pas du temps (traction du grappin au sol) s'accumulaient pendant le gel : jusqu'à 3000 px/s à la reprise, et grappin relancé du mauvais côté. À la reprise, l'appui sur le bon bouton est « rejoué » pour que le pingouin le voie comme un appui neuf, et l'action est relâchée quand le joueur relâche le vrai bouton.
- Re-testé : 12 ateliers sur 12 du premier coup au clavier, à la manette et au tactile, 11 sur 11 en mode enfant ; course finale 13,47 s (or 13,5 s) ; captures de la cheminée.

## 67. Tuto : plus de place pour les sauts, gestes anticipés, cheminée revue (22/11, version 1.57)

Retour de l'équipe sur une vidéo de la 1.56.

- **Plus de place après les tremplins** : un vol lancé fait 2000 à 3500 px ; l'atelier pouvait se terminer pendant le vol (« On recommence ! » en pleine figure). Ateliers allongés (pattes 17 500 px, nose et figures 12 000, chute et combo 6500 ; 5600 px entre deux tremplins), et l'atelier ne recommence plus tant que Pinpouin est en l'air.
- **Gestes faits en avance** (`TutorialCoach._already_done`) : si le joueur a déjà fait le geste attendu (sauté avant le bord, figure lancée, bec déjà relevé ou penché, déjà presque sur le dos, déjà accroché à la prise visée, PUMP déjà tenu), l'invite n'est pas affichée et on passe à la suivante. Avant, elle attendait le tremplin suivant et redemandait un geste déjà fait.
- **Cheminée** :
  - prises **encastrées** dans les parois (`CHIMNEY_EMBED` : centre 15 px dans le mur ; elles dépassent de ~40 px au lieu de 110) : on ne se coince plus entre une prise et la paroi d'en face ;
  - **galerie de sortie** : le rocher de gauche se prolonge en plafond au-dessus du haut du massif (1000 px, hauteur 380 px), ouverte seulement à droite ; une prise de sortie à droite (juste après le bord, dans l'axe depuis la dernière prise de gauche) et une à gauche (au-dessus du couloir) pour s'ajuster ; on se pose sur le sol de la galerie et on ressort à droite vers le replat et la descente.
- Corrigé au passage : juste après un « lâche ! », l'invite de grappin suivante était parfois sautée (le grappin tenait encore une image).
- Testé (`tuto_prompt_bot.gd`) : tous les ateliers réussis du premier coup, testés par morceaux au clavier, à la manette, au tactile et en mode enfant ; captures de la cheminée et de la galerie ; course finale 13,68 s (or 13,5 s, figures tirées au hasard) ; check_all 141 fichiers, 0 échec.

## 68. Grappin qui colle sous la prise, saut contre les murs, « Passer » dans le menu pause (22/11, version 1.58)

Retour de l'équipe sur une vidéo de la 1.57.

- **Bloqué sous le bloc de glace** (atelier BALANCIER, puis partout) : accroché au bloc, la petite traction élastique du balancier (`stretch`, `HookingInAirState.swing`) raccourcit la corde à chaque passage ; Pinpouin finissait à ~70 px du crochet, plaqué contre le flanc du bloc. Le calcul « corde rigide » effaçait alors aussi la gravité (elle tire dans l'axe de la corde) : il flottait immobile (mesuré : 13 px/s pendant plus de 5 s, outil hors projet `swing_stuck.gd`).
  - Corrigé (`HookingInAirState.ROPE_MIN_LENGTH` = 160 px) : sous cette longueur et sans tirer, on n'efface plus la vitesse qui l'éloigne du crochet et on ne fait plus la traction élastique ; il retombe au bout d'une corde de 160 px et peut se balancer. En tirant ({pull}), rien ne change (falaises, cheminée).
  - Filet de sécurité du tuto (`TutorialCoach`, `SWING_STILL_SPEED` 250 px/s, `SWING_STILL_TIME` 2,5 s) : au balancier, pendu sans élan 2,5 s = « Plus assez d'élan ! », retour au début de l'atelier.
- **Plus d'escalade en sautant** : collé à un mur, SAUT donnait toujours une vitesse vers le haut ; en tapotant, on grimpait (half-pipe : 489 px sans sauter, 662 à 668 px en tapotant). Choix de l'équipe, comme pour le PUMP (section 64) : sur un mur (> 75°, `PUMP_WALL_DEG`), sans grappin accroché au-dessus, SAUT **repousse du mur** : Pinpouin se décolle à l'horizontale (`Player.WALL_JUMP_PUSH` = 450 px/s) en gardant sa vitesse verticale, en montée comme en descente. Même règle pour le saut « coyote » (`_last_ground_normal`). Code : `Player.wall_jump_normal()`, `JumpingState.enter`. Mesuré : 480 px en tapotant (489 sans sauter).
- **« Passer cet atelier »** : le gros bouton sous la bulle prenait de la place et on cliquait dessus en visant le grappin. Choix de l'équipe : il passe dans le **menu pause** (ligne sous « Reprendre », visible quand « Passer » est permis : règle d'avant inchangée ; `MenuPause._add_tuto_skip_button`, `MasterBubble.skip_available / skip_label / request_skip`). Sous la bulle ne reste qu'un petit rappel non cliquable (« Passer : Tab ou menu pause »). Tab et Back passent toujours l'atelier.
- Testé : Hook you fool 86,27 s (inchangé), Sans fin grappin 25/26, double 19/19, montée 31/33, plafond 14/14 ; défi Half-pipe 11 050 points (11 500 en 1.57, figures au hasard) ; captures PC et téléphone de la bulle et du menu pause.

## 69. Nouveau niveau « Le Half-Pipe de l'œuf » (maquette) (22/11, version 1.59)

Niveau imaginé par l'équipe (croquis « Level_Egg_V2 »), plan v3 validé : un seul tour d'environ 3 minutes autour d'un grand œuf de glace, sans retour possible. Vue de côté.

- **Construit par le code** (`src/levels/egg/EggGenerator.gd`, scène `src/levels/LevelEgg.tscn`, copie de `LevelDrawn.tscn`) : le créateur de niveau ne fait ni parois verticales, ni boucle, ni surplomb. Toutes les formes viennent de quelques constantes en tête du fichier (taille de l'œuf, de la grotte, des trous, de la cheminée…). Aucun nouvel asset : remplissages et contours en couleur (bleu glace pour l'œuf et les tremplins, bleu plus sombre pour la grotte, pour bien lire les parois), bordure de glace existante sur les sols, prises = boules de glace du tuto, half-pipe = `HalfPipe.tscn` (sans sa propre arrivée), arrivée = `FinishGate.tscn` (bande d'arrivée réduite à 1500 px de haut).
- **Le tour** :
  1. départ sur une plateforme en pente douce ; mur derrière (jusqu'au plafond) ; la plateforme devient un **toboggan** qui rejoint l'épaule de l'œuf (la « paroi ajoutée » du plan v3 : le dessous est plein, aucun chemin vers le half-pipe) ;
  2. descente à droite : tremplins sur le toboggan et l'épaule de l'œuf ; Pinpouin est lancé vers la paroi, qu'il longe jusqu'au grand **bol** du bas ;
  3. le bas, **vers la gauche** : 3 trous sur le vide (saut avec tremplin, balancier sous une stalactite, grappin double sous deux stalactites) ;
  4. le bol de gauche (plus serré) fait remonter dans la **cheminée** entre la paroi et un pilier : 14 prises en zigzag, calculées de haut en bas avec la règle de l'atelier CHEMINÉE du tuto (prises encastrées), jusqu'à une galerie de sortie ouverte à droite ;
  5. un **pont** en pente douce, puis un **plafond suspendu** (2 prises) au-dessus du dos de l'œuf jusqu'au sommet ;
  6. **arrivée** au bord de la fente creusée dans le haut de l'œuf, puis chute dans le **half-pipe** (30 s de figures bonus en Score, glisse libre en Chill : règles de `RaceManager` inchangées).
- **Points de passage** (groupe `course_checkpoints`) : départ, bol droit, trou 2, trou 3, cheminée, pont. Une chute réapparaît au dernier point atteint (`Player._pick_respawn_sample` demande au niveau, comme pour le tuto et le Sans fin ; après l'arrivée, règle du half-pipe). Tomber sous le pont = réapparition au début du pont (sinon on redescendrait toute la cheminée).
- **Mode enfant** (groupe `course_direction`) : `KidAssist` demande au niveau le sens « vers l'avant » (gauche dans le bas, aucun dans la cheminée) et l'avancement le long du tour ; deux chutes depuis le même point = point suivant (« pont magique ») ; coincé 15 s (pied de la cheminée) = point suivant. Ailleurs, rien ne change (sens = droite, avancement = x).
- **Menu** : bouton « Le Half-Pipe de l'œuf » dans COURSES. **Médaille d'or provisoire** : 82 s (`RaceManager.MEDAL_GOLD`).
- **Testé** (outil hors projet `egg_bot.gd`, bot « bon joueur » qui vise les prises) : tour complet en 1:21,07 (1 chute au grappin double), arrivée en Score (bonus half-pipe) et en Chill (glisse libre) ; mode enfant depuis le bas et depuis la cheminée jusqu'à l'arrivée ; captures de chaque partie et du menu (PC, téléphone) ; check_all 143 fichiers, 0 échec.
- **Réglages en cours de route** : 1re cheminée inaccessible (le pilier descendait sous l'endroit où l'élan fait remonter Pinpouin : bol gauche resserré, `R_BL` = 2500) ; grappin double trop près du balancier (on volait dans les stalactites : trou 3 décalé à gauche) ; plateforme de départ plate (9 s à 460 px/s : pente de 450 px) ; pont plat (12 s : pente de 650 px).
- **Durée** : un tour au bot prend 1:21. Un joueur qui découvre le niveau mettra nettement plus (chutes, prises de la cheminée), mais sans doute moins de 3 minutes une fois le parcours connu : à régler avec l'équipe après les premiers essais (plus d'épreuves, œuf plus grand, ou cheminée plus longue).

## 70. « Le Half-Pipe de l'œuf » : zigzag, chemin de gauche, crevasse, habillage pixel art (22/11, version 1.60)

Retours de l'équipe sur la maquette 1.59 : raccourci possible par le dos de l'œuf, pas assez de dézoom en bas, remplacer la cheminée par des plateformes, ajouter un zigzag à droite, des panneaux, et habiller le niveau (œuf bleu glace en pixel art, grotte plus sombre).

- **Zigzag à droite** : 4 corniches de glace en pente de 10°, alternées œuf / paroi (la 1re part de l'œuf, dans le sens de l'élan). Sous le « ventre » de l'œuf, le bout libre d'une corniche dépasse son point le plus large (`_egg_reach_right`), sinon Pinpouin se coincerait en tombant. Les tremplins de l'épaule de l'œuf sont supprimés.
- **Chemin de gauche** (remplace cheminée, pilier et galerie) : une **marche** de 800 px avec une rampe arrondie (arc de 60°, l'élan du bas fait monter dessus), puis **12 plateformes-stalactites** alternées (côté paroi / côté œuf, 760 px plus haut à chaque fois), la 13e étant le **pont**. Chaque prise est 300 px au-dessus du niveau de la plateforme visée mais **dans la colonne d'en face**, à 60 px de son bord : au-dessus de la plateforme, le grappin se plantait dans son dessous (essai 1). On tire, on monte le long du bord, on lâche au-dessus et on se pose.
- **Crevasse** creusée dans le dos de l'œuf (x de -5800 à -1800, fond en V à y = -300) : plus de raccourci, il faut passer par le plafond (2 prises). Tomber dedans = retour au début du pont.
- **Points de passage** : départ, bol droit, trou 2, trou 3, marche, mi-hauteur (6e plateforme), pont, **crevasse franchie** (nouveau : sans lui, le mode enfant tombait sans fin dans la crevasse).
- **Caméra** : en bas, cadrage de la stalactite suivante (jusqu'à 4800 px devant) et dézoom jusqu'à 0,33 (`AdaptiveCamera.focus_min_zoom`, nouvelle variable, 0,5 par défaut : les autres niveaux ne changent pas) ; au-dessus de l'œuf et dans le zigzag, cadrage de la corniche suivante ; sur le chemin de gauche, de la prise suivante.
- **Habillage pixel art** : images générées par `tools/art/egg_art.py` (dossier ignoré par Godot) dans `sprites/levels/egg/`, palette des sprites du jeu. Œuf texturé sur sa vraie équation (1 pixel d'art = 6 px du monde, tramage aux transitions, éclats, fissures, neige au sommet) ; tuile de glace sur stalactites, corniches, plateformes, pont et tremplins ; rangées de glaçons sous les plateformes (décor, sans collision, jamais devant les prises) ; prises en boules de glace à anneau bleu ; **fond de roche sombre** derrière tout le niveau (cache le ciel et les montagnes) ; **14 panneaux flèches** à chaque changement de direction (style du panneau « attention »).
- **Médaille d'or provisoire** : 108 s. Bot « bon joueur » : tour complet en 1:46,33 sans chute (Score et Chill) ; mode enfant sans rien toucher : arrivée en 1:33,88 (5 chutes, « pont magique »). check_all 143 fichiers, 0 échec.

## 71. Menus : nouveau plan de la sélection des niveaux, fenêtres plus larges, tableau des scores du salon (22/11, version 1.61)

Demande de l'équipe (capture du salon et croquis du menu), choix validés : un écran à onglets derrière « Niveaux custom », fantômes dans Options, boutons en français, titre de la colonne de droite qui suit le mode. Le niveau de la 1.60 s'appelle maintenant **« L'Œuf »** (au lieu de « Le Half-Pipe de l'œuf », qui se confondait avec le niveau « Half-pipe »).

- **Largeur commune des menus** (`src/ui/MenuLayout.gd`, nouveau) : marge de 5 % de chaque côté (40 unités minimum), largeur utile plafonnée à 1400 unités (au-delà, la marge grandit) ; les panneaux d'une rangée se partagent toute la largeur. Appliqué à la sélection des niveaux, au salon multijoueur, aux Options et à Mes niveaux / Communauté.
- **Salon, « Dernière course »** (`MultiplayerLobby._fill_results`) : vrai tableau rang | nom | points | temps. Points et temps alignés à droite, chiffres de même largeur (`tnum`), points en gras, temps plus clair, ta ligne en jaune avec « (toi) », nom trop long coupé avec « … », tableau plafonné à 760 unités pour que le score reste près du nom. Le panneau prend la hauteur de son contenu (plus de grand vide en bas).
- **Sélection des niveaux** (plan de l'équipe) : en haut « MODE : ○ CHILL / ○ SCORE », chaque choix suivi d'une phrase ; trois colonnes :
  - « Autres modes » : Tutoriel, Sans fin, Niveaux custom ;
  - « Niveaux » (courses avec une arrivée) : Flat and fun, Corridor, Nice Slope, Hook you fool, Spaghetti, **L'Œuf** ;
  - « Défis figures » en Score / « Glisse libre » en Chill : 704, 917, Half-pipe.
  En Score, chaque bouton montre son record sur une 2e ligne (« pas encore de record » sinon) avec sa médaille. Logo Pinpouin en bas à droite, à côté de la version. Le bouton « Niveaux de la communauté », l'interrupteur et le dossier des fantômes restent dans la scène mais sont masqués (le fantôme se règle dans Options, où il était déjà).
- **Niveaux custom** : ouvre « Mes niveaux », qui a maintenant deux **onglets** en haut, MES NIVEAUX / COMMUNAUTÉ (`MyLevelsScreen._build`).
- **L'Œuf** ajouté aux courses du multijoueur et à l'échange de fantômes des Options.
- Testé : captures PC (1600×900, 1024×768) et téléphone (2340×1080) en Chill et en Score ; salon avec un faux classement (nom long, joueur pas arrivé) ; parcours des boutons (Niveaux custom → onglet Communauté → onglet Mes niveaux ; L'Œuf lance bien le niveau) ; check_all 144 fichiers, 0 échec.

## 72. Compteur de vitesse : repère de vitesse limite avec le frottement de glisse (22/11, pour la 1.62)

- **Équation du jeu** (`Player._apply_air_drag_and_friction`, par unité de masse, g = `gravity` = 800 px/s²) : dv/dt = g·sin θ − μ·g·cos θ − k·v². Air partout (k·v²), frottement de glisse au sol seulement (μ = `ground_friction` = 0,02). k = g·sin(10°) / `drag_terminal_speed`² : 2000 px/s est la vitesse limite **sur 10° avec l'air seul**, pas en chute libre (en chute libre : √(g/k) ≈ 4800 px/s).
- **Correction** : `Player.terminal_speed_on_slope` (repère du compteur F3) utilisait √(g·sin θ / k), sans le frottement, et affichait donc une limite un peu trop haute. Elle calcule maintenant v = √( g·(sin θ − μ·cos θ) / k ), et 0 quand la pente ne vainc pas le frottement (≤ ~1,15°).
- **La physique ne change pas** : seule cette fonction d'affichage est modifiée (aucune médaille à remesurer).
- Vérifié : 8° → 1658, 10° → 1883, 15° → 2349, 20° → 2729 px/s, identique à l'intégration numérique de l'équation (8° : 1658, 15° : 2349) ; check_all 144 fichiers, 0 échec.

## 73. « Le Gruyère de glace » : maquette de la partie 1 + balançoire au PUMP (22/11, pour la 1.62)

- **Niveau** `src/levels/LevelGruyere.tscn` + `src/levels/gruyere/GruyereGenerator.gd` (géométrie calculée, comme L'Œuf). Pas encore dans le menu (maquette).
- **Motif répété 3 fois**, de plus en plus dur : 3 piliers « vague » sur le vide (creux puis lèvre à 24°), **plafond-guide** en voûte au-dessus de chaque trou (filet de sécurité : rabat sur le pilier suivant si on saute trop haut), **grand bol** puis **tremplin à 45°**, **grand saut** avec **zone de dézoom** (caméra `focus_point`, zoom 0,4 au plus large). Motif 1 : on se pose sur une pente. Motifs 2 et 3 : la plateforme est plus haute que la fin du saut, il faut **grappiner l'œuf** (au-dessus de la plateforme, en retrait du bord, comme les ateliers FALAISE : on tire, on monte, on lâche au-dessus).
- La trajectoire du saut est **calculée** (gravité + air, mêmes lois que le joueur) depuis la vitesse de décollage mesurée au bot (`JUMP_SPEED`) ; l'arrivée ou l'œuf sont posés dessus.
- **Points de passage** : départ, début de chaque série de piliers, bol (réapparition sur le 3e pilier : Player limite la vitesse de réapparition à 1200 px/s, trop peu pour le grand saut si l'on repart dans le bol).
- **Arrivée provisoire** : un pilier, l'arche, le half-pipe (mur au bout). Les cavernes viendront s'intercaler ici.
- **Balançoire (nouvelle mécanique, `HookingInAirState.swing`)** : PUMP tenu près du bas du balancier (±45°) pousse le long de l'arc dans le sens du mouvement (700 px/s², jusqu'à 1250 px/s) ; presque arrêté, sens de la flèche tenue. Sans PUMP, rien ne change. Constantes `SWING_PUMP_*`.
- **Bot** (`tools` hors projet : `gruyere_bot.gd`, env FIRE_D, NOPUMP, NOSWINGPUMP, PULL, LOG, SHOTS ; `gruyere_view.gd` avec NOBG=1) : partie 1 en 42,9 s sans chute (grappin lancé à 800, 950 ou 1100 px de l'œuf : 0 chute) ; sans PUMP : 48 à 59 s, 0 ou 1 chute.
- Itérations notées dans le code : remontée du bol raccourcie (trop d'élan perdu), plafonds sur les 3 trous (survol des piliers à grande vitesse, atterrissage à plat au fond du bol), pilier long après l'œuf qui descend d'abord (sinon on n'en ressortait pas), départ en haut d'une pente (sans PUMP, 450 px/s au 1er trou).
- **Version 1.62 (code 65)** : le Gruyère de glace est dans le menu (colonne Niveaux, sous L'Œuf), dans le multijoueur et dans l'échange de fantômes ; or provisoire 44 s (`MEDAL_GOLD`). Vérifié : Chill 41,3 s ; mode enfant sans toucher à rien : arrivée en 60,9 s (3 chutes, « pont magique » compris) ; menus en Chill et en Score (PC 1600×900, 1024×768, téléphone 2340×1080) ; check_all 146 fichiers, 0 échec.

## 74. Cavernes générées (graine, N entrées / M sorties) et fin du Gruyère de glace (23/11, version 1.63)

- **Générateur** `src/levels/cave/CaveGenerator.gd` (`class_name CaveGenerator`, un nœud réutilisable) : `cave_seed`, `entry_lanes` / `exit_lanes` (étages des entrées et sorties), `entry_angles` θ / `exit_angles` φ, `columns`. Une graine donne toujours la même caverne.
  - **Plan** : colonnes (`COL_W` 2600) × étages (`LANE_GAP` 1250). Entre deux colonnes, chaque étage est un **couloir** (épreuve : glissade, trou, balancier, double prise ; plus dur en haut, plus sûr en bas) ou une **salle de croisement** de deux étages : rester en haut (balancier), se laisser tomber (descendre d'étage), rester en bas, monter au grappin (deux prises). Salle à 4 ouvertures = X ; nœud à 2 sorties = Y.
  - **Routes** tirées au hasard d'une entrée vers une sortie (on ne change d'étage que dans une salle) : la caverne est leur réunion, donc **aucun cul-de-sac par construction**. `check_plan()` revérifie sur les passages réels : tout nœud atteignable et menant à une sortie, chaque sortie atteinte, chaque entrée vers au moins 2 sorties, au moins un X et un Y ; sinon nouveau sous-tirage avec la même graine.
  - Contrôle sur 1 000 graines pour 4 réglages (2→3, 3→4, 4→2, 3→3), en 8 et 10 colonnes : 100 % conformes (`tools/cave_check.gd` hors projet). Planche des graines : `tools/cave_sketch.gd` + `tools/py/cave_planche.py`.
  - **Géométrie** : collisions en chaînes de segments ouvertes (les ouvertures entre couloirs ne sont pas des murs), roche dessinée en tranches (montagne moins les galeries), **voile de glace léger** dans les galeries (on voit le décor à travers), contour sombre et bordure de glace sur les sols. Dôme au-dessus des trous à prises (prise plus haute = vrai balancier). Pas de simple trou juste après un balancier (on en sort lancé très loin).
  - **Grappin** : la roche des cavernes est dans le groupe `no_hook` : le crochet n'y tient pas (`Chain.gd`), seules les prises comptent ; la « chute sans retour » ignore aussi cette roche (`Player._has_rescue_hook_in_reach`).
- **Gruyère de glace** : après la partie 1, 3 cavernes (graines 1440, 2302, 3303 ; 2→3, 3→4, 4→2 étages ; 10 colonnes) reliées par des **passages à l'air libre** (rebord de sortie, balcon d'entrée du même étage ; tomber entre les deux ramène sur le sol de l'étage le plus bas : pas de chute mortelle). Fin : la sortie du haut se laisse tomber dans le **half-pipe**, celle du bas y monte au grappin (deux prises). Arche sur le deck gauche.
  - **Points de passage** : chaque carrefour touché au sol ; un puits fait réapparaître au dernier carrefour. Mode enfant : « pont magique » = carrefour suivant.
  - **Œufs (partie 1)** : même place, mais la descente qui suit est 650 px plus bas : on attrape l'œuf par en dessous, balancier, on retombe dans la pente (demande de l'équipe).

## 75. Cavernes moins hautes, dézoom haut / bas, panneau des montées (23/11, version 1.64)

- Retour de l'équipe (1.63) : « cul-de-sac » en passant par le bas, cavernes trop hautes, dézoom souhaité sur les galeries du dessus et du dessous.
- Le « cul-de-sac » était une **montée obligatoire** (salle de croisement dont la galerie du bas n'a pas de suite : il faut monter au grappin) dont les prises étaient hors de l'écran. Désormais : **panneau flèche « haut »** au pied du rebord, et la caméra montre les prises.
- **Étages plus serrés** : `LANE_GAP` 1250 → 950, `TUNNEL_H` 720 → 620, `PIT_DEPTH` 300 → 220, dôme 860 ; prise 1 des montées à 700 px du sol. Un couloir à prises (balancier, double) n'est placé que si l'étage du dessus n'est pas creusé au même endroit (place pour le dôme) ; l'étage du haut garde donc la plupart des balanciers.
- **Caméra** (`AdaptiveCamera.focus_point2`, `GruyereGenerator._cave_focus`) : dans une caverne, le cadre englobe Pinpouin et les carrefours de la colonne suivante sur l'étage du dessus et celui du dessous (s'ils existent), zoom 0,4 au plus large ; il ne change qu'à chaque colonne.
- Contrôle 1 000 graines × 3 réglages : 100 %. Bot : route du haut 2:04 (la plus rapide), du bas 2:34, au hasard 2:43 à 3:16, mode enfant 3:01 ; or 125 s.

## 76. Boosts « Trackmania », plafonds accrochables, rampes, vide tout en bas (23/11, version 1.65)

- **Boost réparé** (`src/levels/boost/BoostArea.gd` / `.tscn`, flèches jaunes et rouges d'origine `Speed_arrow1/2.png`). Il n'avait jamais marché : aucun niveau ne l'activait, la scène gardait des noms Godot 3 (`frames`, `extents` : flèche invisible, zone minuscule) et l'effet (64 px/s) était mangé par la limite de vitesse. Scène réécrite au format Godot 4 (mêmes nœuds, mêmes images).
- **Mode turbo** (par défaut, `turbo_mode`) : tant que le pingouin est dans la zone, puis `boost_time` s après, **accélération** dans le sens de la flèche (au sol : le long de la pente). `boost_strength` de 0 à 1 = **spectre de couleur** proportionnel (blanc nul → jaune → orange → rouge), accélération = force × 1800 px/s². Le jaune (0,25 = 450 px/s²) suffit pour grimper une pente de 20°. `in_air` : boost en l'air (zone colorée flottante) ; `arrow_scale` : taille de la flèche. Couleur par shader (`boost_tint.gdshader`) : les PNG ne sont pas modifiés. Traînée du pingouin à la couleur du boost, son provisoire `boost.wav`. Anciens réglages `impulse_*` / `accel_*` conservés (utilisés seulement si `turbo_mode = false`). `Player.pad_boost()` / `_apply_pad_boost()`.
- **Cavernes** (`CaveGenerator`) :
  - **plafonds accrochables** (`hookable_ceilings`) sur toute la longueur : corps « Plafonds » hors du groupe `no_hook` ; habillage bandeau de glace + stalactites (`sprites/levels/cave/plafond_glace.png`, nouvelle image). Murs et reste de la roche : toujours non accrochables ;
  - **plus de trous mortels entre deux galeries** (`pits_only_bottom`) : aux étages du haut, les épreuves passent au-dessus d'une **cuvette** arrondie sans danger ; **tout en bas**, le trou traverse la montagne et donne sur le **vide** (boost en l'air au-dessus des trous simples) ;
  - **rampes** (`climb_style = "rampe"`) : une montée obligatoire devient une pente (~21°) jusqu'à la sortie haute, avec un boost orange au pied et deux rappels jaunes. `climb_style = "grappin"` remet les deux prises (levier de difficulté pour de futures cavernes) ;
  - petits **rappels** jaunes dans une glissade sur deux de la moitié basse.
- Contrôles : 1 500 graines (4 → 2 étages, 10 colonnes) : 100 % ; check_all 147 fichiers, 0 échec. Bot : bas 1:55 (le plus rapide), haut 2:07, hasard 2:07 à 2:16, Chill 1:51, sans PUMP 2:07, mode enfant 2:14 ; une rampe se monte seule depuis 300 px/s (≈ 1240 px/s en haut). Or 116 s.

## 77. Zones de vide, virages en morceau de pipe, 4e caverne, retours de test (23/11, version 1.66)

- **Retours de test 1.65** :
  - **caméra** : tout en bas d'une caverne, le cadre garde aussi le sol de sa propre galerie plus loin et 260 px dessous (`GruyereGenerator._cave_focus`) ;
  - **arrivée par le bas** : rampe à boosts (virages PipeBend : creux, montée à 28°, arrondi) qui arrive pile sur le deck du half-pipe ; plus de prises de grappin ;
  - **chute en pleine figure contre un plafond** : Pinpouin à l'envers « touchait le sol » sur le plafond (capteurs tournés vers le haut, normale de segment renvoyée vers le haut) ; la roulade le figeait 1 s en l'air (« mur blanc »). `LandingStyle.on_real_floor()` exige un contact SOUS Pinpouin ; `TrixState`, `CrashState`, `StaggeredState` et la détection d'atterrissage s'en servent ; en l'air, la roulade et l'étourdissement laissent agir la gravité. Vérifié avant / après (`ceil_trick.gd` hors projet).
- **Virages** (`src/levels/cave/PipeBend.gd`, nouveau, `class_name PipeBend`) : arc réglable (cap de départ, angle de virage signé de 0 à 180°, rayon), droites, raccords, et `boosts_along()` qui pose des boosts dans les montées (force selon la pente, couleur = force).
- **Angles θ / φ des cavernes** (`CaveGenerator.entry_angles` / `exit_angles`, de -90 à +90, rayons `entry_bend_radius` / `exit_bend_radius` ou par étage `entry_radii` / `exit_radii`) : les couloirs restent à 8° dans la montagne ; devant une entrée / après une sortie, un virage hors de la montagne : rampe d'accueil (θ > 8, on arrive en tombant), tube courbe avec plafond qui plaque et boosts en l'air (θ < 8, on arrive par en dessous), tremplin (φ < 8), plongeon en tube (φ > 8, plafond + 600 px tout droit, sinon on décollait). Toits en pente (on ne reste plus coincé contre le flanc). Bouts exposés : `exit_tips`, `entry_tips`.
- **Zones de vide** entre cavernes (croquis de l'équipe) : tremplins à -18° en sortie, rampes d'accueil à 55° en entrée ; les entrées sont un étage + 150 px plus bas que les sorties de même numéro, calculé avec la vraie physique : de 1000 à 2200 px/s on retombe en face, plus lent un étage plus bas, tout en bas le vide. **Échelle d'œufs** pour monter (un par sortie sauf la plus haute, deux à enchaîner pour monter de deux) + deux balançoires au-dessus. Zone 2 : la sortie du bas plonge (+70°) dans un **virage en U** à boosts qui remonte dans l'entrée du bas de la caverne 3 **par en dessous** (-55°). Caméra : cadre sur l'entrée en face et l'œuf de l'étage (zoom jusqu'à 0,33).
- **4 cavernes** (graines 1440, 2302, 3303, 4404).
- **Stalactites** : bandeau lisse + stalactites posées tous les 110 px là où un bruit (graine de la caverne) dépasse 0 ; 4 tailles selon sa valeur ; plafond lisse ailleurs (nouvelles images `plafond_glace_lisse.png`, `stalactite_1..4.png`).
- **Routes équivalentes** : rappels jaunes dans les glissades de tous les étages ; au-dessus des trous à prises (sans vide dessous), un boost en l'air au milieu ; un boost à l'arrivée de chaque trou. Bot : haut 2:14, bas 2:09 (rester sur son étage) ; changer d'étage (œufs, montées au grappin) coûte du temps : hasard 2:23 à 3:04 ; Chill 2:40 ; sans PUMP 2:30 ; mode enfant 2:32. Or 130 s.
- Contrôles : 1 000 graines (4 → 3 étages) : 100 % ; check_all 148 fichiers, 0 échec.

## 78. Œufs au milieu du vide, U plus doux, or à 2:00, Pinpouin collé aux plafonds (23/11, version 1.67)

- **Œufs** (retour de l'équipe : « pile entre les deux plateformes, sur la trajectoire mais un peu plus haut, pour appuyer le grappin ») : `LADDER_EGG` = 1250 px après le tremplin, 470 px plus haut. Au bot, en se balançant, Pinpouin butait sous la rampe d'accueil du dessus : rampes raccourcies (rayon 1400 -> 1000) et tremplins à -15° (au lieu de -18°). Recalculé : de 1300 à 2500 px/s on retombe en face, plus lent un étage plus bas ; la trajectoire la plus rapide passe ~250 px sous l'œuf ; le bout de la rampe du dessus est 570 px à droite et 200 px sous l'œuf. Bot : en lâchant à hauteur de l'œuf on monte d'un étage, et on peut enchaîner l'œuf du dessus.
- **Virage en U plus doux** : le plus grand rayon qui tient (750 au lieu de 500).
- **Pinpouin collé sous un plafond** (vu au bot, jusqu'à 28 s) : en longeant un plafond qui descend, la projection « à la Godot 3 » retirait aussi la gravité à chaque image. `Player._apply_godot3_slide` : contre un plafond, on n'enlève que la vitesse qui rentre dedans (sols et murs inchangés) ; `Player._ray_sees_floor` : un capteur tourné vers le haut ne compte plus comme sol. Hook you fool (gap_bot) : temps identique au centième avant / après ; L'Œuf 107 s (inchangé).
- **Or : 2:00** (demande de l'équipe ; Manu 2:07 avec des ratés). Bot : haut 2:10, bas 2:09, hasard 2:00,5 à 3:04, sans PUMP 2:06, Chill 2:23, mode enfant 2:50.

## 79. 100 % air + glace : plus de plafonds de vitesse, air au grappin, pump à puissance limitée (23/11, version 1.68)

Demande de l'équipe : « enlever tous les plafonds, laisser 100 % air + glace ».

- **`SUPER_MAX_SPEED`** (3000 px/s par axe) et **`MAX_SPEED_HOOKED`** (1000 px/s par axe, `HookingInAirState`) ne sont plus appliqués ; noms gardés. Nouvel interrupteur `Player.hard_speed_caps` (false) qui remet des plafonds sur la vitesse TOTALE : `HARD_CAP_SPEED` = 5000 (au-dessus de la chute libre √(g/k) ≈ 4800) et `HARD_CAP_SPEED_HOOKED` = 2600 (balancier à corde maximale ≈ 2530).
- **Résistance de l'air au grappin** : avant, rien ne freinait pendant qu'on était accroché (`_apply_soft_speed_caps` sortait tout de suite) ; maintenant air (et glace si l'on glisse accroché), comme partout.
- **PUMP** : comme un moteur, force limitée à basse vitesse, puissance limitée à haute vitesse. Sous `pump_max_speed` (1650) : le pump d'avant, inchangé. Au-dessus (avant : rien) : gain = P / v, avec P = (k·v² + μ·g)·v à 1650 sur le plat (≈ 182 500) : ≈ 110 px/s² à 1650, 60 à 3000 ; l'impulsion d'un appui suit la même loi (+22 px/s à 1650, +12 à 3000). `Player.pump_power()`. Essai abandonné : puissance pure partout (gain = P / v dès 400 px/s) -> pump trop faible entre 400 et 1650 (Flat 64,5 -> 86 s, Sans fin 0 saut sur 37, Hook you fool pas fini).
- **L'Œuf** : avec l'air au grappin, la 2e prise du plafond était hors de portée après le balancier sur la 1re (le bot tombait en boucle) : plafond abaissé de 100 px (`CEIL_UNDER` 750 -> 650).
- Compteur de vitesse : jauge jusqu'à 5000 (était 3000) ; F2 : « Pump : vitesse d'équilibre sur le plat ».
- **Avant / après aux bots** (mêmes terrains) : Flat 64,5 -> 62,2 s ; Corridor 62,4 -> 62,6 ; Nice Slope 41,2 -> 40,4 ; Spaghetti 32,8 -> 32,2 ; Hook you fool 86,3 -> 82,7 (**or 86,5 -> 83**) ; L'Œuf 107,0 -> 108,2 ; tuto (course finale) 15,6 -> 15,5 ; Gruyère bas 2:14 -> 2:10, haut 2:34 -> 2:16 ; Sans fin (trous passés) grappin 36/39 -> 41/43, double 29/31 -> 25/29, montée 50/50 -> 55/58, plafond 21/21 -> 21/21. Enlever les deux plafonds seuls : aucun effet mesuré ; l'air au grappin : +2 s sur Hook you fool (compensé par le pump au-delà de 1650). Aucune traversée de sol vue.
- Outils hors projet : `medal_bot.gd` / `gap_bot.gd` acceptent `SEED=<n>` (graine fixe, comparaisons avant / après).


## 80. Fond dans le bon ordre de profondeur, plus de ralentissements au sol (23/11, version 1.69)

Retours de l'équipe : « les montagnes, plus loin que le glacier, bougent plus vite que lui » et « des ralentissements au sol par moment, même lentement ; en sautant à ce moment on a un boost ; l'air n'a pas ce problème ».

- **Fond (`VerticalParallax.gd`, disposition Alto)** : la vitesse de chaque plan était donnée par son RANG d'affichage (`parallax_speeds` [0,2 ; 0,35 ; 0,5] dans l'ordre de `alto_z`), d'où montagnes 0,5 et glacier 0,35. Nouveau dictionnaire `alto_speeds` (nuages 0,2, montagnes 0,35, glacier 0,5) : le plan le plus proche défile le plus vite. Le glacier, passé devant, cachait les montagnes avec sa brume : rangée `alto_rows.glacier` -100 -> -70 (à -55, la bande sombre du bas des nuages réapparaît). Effet de bord : le pied des falaises du glacier est en grande partie sous l'écran.
- **Ralentissements au sol (`Player.gd`)** : mesurés avec une sonde (`ground_probe.gd`, hors projet : ▶ tenu, perte = vitesse prévue par la physique - vitesse réelle). Niveaux normaux propres (0 à 1 perte de 12 px/s) ; cavernes du Gruyère : pertes de 20 à 100 px/s en une image. Deux causes :
  1. au sommet d'une bosse, les deux rayons de sol touchent de part et d'autre et leur normale moyenne est fausse (jusqu'à 24°) ; le filtre « arête fantôme » remplaçait la vraie collision par cette normale -> vitesse tordue vers le bas (452 -> 352 px/s). Maintenant, si les deux capteurs diffèrent de plus de 10° (`GHOST_RAYS_AGREE_DEG`), le filtre ne s'applique pas ;
  2. aux jonctions de segments, 2 ou 3 contacts dans la même image, chacun retirant un peu de vitesse (≈ 6 %). Le lissage GLISSE LISSE (1.53) prend maintenant comme référence la normale du vrai contact au sol de l'image précédente (`_last_floor_n`, effacée dès qu'une image n'a pas de contact) au lieu de celle des capteurs, et lisse dès 0° (avant : au-delà de 0,5°). Physiquement, c'est une glisse sans frottement sur une courbe : la vitesse ne change pas en suivant le sol.
  - Sonde avant / après (30 s) : caverne 2, 9 pertes / 293 px/s -> 6 / 167 ; les pertes restantes sont toutes des **atterrissages** (vitesse verticale absorbée, 75 % rendue par `landing_speed_keep`), pas de la glisse. Niveaux normaux inchangés.
- **Bots avant / après** : Corridor 62,6 -> 62,5 s ; Nice Slope 40,4 -> 39,7 ; Spaghetti 32,2 -> 31,3 ; Flat 62,2 -> 63,3 ; Hook you fool 82,7 -> 88,4 ; L'Œuf 108,2 -> 106,6 ; Gruyère haut 2:16 -> 2:09, bas 2:10 -> 2:16 (2 chutes du bot dans la caverne 3), hasard 2:58 -> 3:27 (autres routes) ; Sans fin mitigé (deux types mieux, deux moins bien). Les trajectoires divergent dès 1 px/s d'écart (Hook you fool : écart de 1 px/s à 1,1 s, puis sauts et grappins différents) : ces écarts sont du chaos du bot, pas une perte de vitesse au sol (vitesse et pertes au sol mesurées identiques ou meilleures). Médailles non touchées.

## 81. Sols des cavernes lissés à la source, coins saillants sous la capsule (23/11, version 1.70)

Question de l'équipe : « les plateformes de Flat and fun et celles des cavernes sont différentes ? Encore des bugs dus au terrain dans les cavernes, plus sur Flat ». Mesure de la géométrie (outil `terrain_stats.gd`, hors projet) : Flat = une courbe de bruit, un point tous les 64 px, 0,4 % de cassures de plus de 10° ; cavernes = 448 morceaux (courbes de 8 à 12 points) raccordés bout à bout, 8 % de cassures de plus de 10° dont 146 de plus de 25°.

- **`CaveGenerator.gd`, `_smooth_collision_chains()`** (interrupteur `smooth_floors`, true) : juste avant de créer les collisions, les morceaux de sol qui se touchent bout à bout et continuent dans un sens voisin (< 60°) sont recollés en une seule chaîne ; les points à moins de 2 px sont fusionnés ; chaque coin « de sol » (pentes < 55° des deux côtés, `SMOOTH_SLOPE_MAX_DEG`) qui tourne de plus de 4° (`SMOOTH_MAX_TURN_DEG`) devient un petit arc de Bézier tangent aux deux segments (au plus 90 px de chaque côté, `SMOOTH_MAX_CUT`). Murs et plafonds accrochables inchangés. La bordure dessinée suit les chaînes lissées ; écart à la forme d'origine : quelques pixels. Résultat : cassures de sol de plus de 10° dans les cavernes 414 -> 0 (celles qui restent dans la zone sont des murs, des plafonds accrochables et le contour des œufs).
- **`Player.gd`, coins saillants** : la capsule de Pinpouin est couchée et ne tourne pas ; son dessous est plat (20 px). Sur une pente raide (rampes à 27° des cavernes, montée vers l'arrivée), un sommet du sol touchait ce dessous plat et le moteur renvoyait la normale (0, -1) : vitesse verticale effacée (1836 -> 1618 px/s en une image), sous le seuil du filtre « arête fantôme » (35°). Nouveau test dans `_is_ghost_collision` : si les deux capteurs voient la même pente et que le contact est sur ou au-dessus de la corde entre leurs points d'impact (coin saillant), le contact est fantôme dès 3° d'écart (`GHOST_VERTEX_MIN_DEG`, jusqu'à 50°) ; un contact sous la corde (vrai creux) n'est pas touché.
- **Sonde avant / après (30 s)** : caverne 4 + arrivée 1 366 -> 0 px/s perdus ; cavernes 1 à 3 : il ne reste que des atterrissages ; Flat, Nice Slope, Spaghetti : 0 perte.
- **Bots 1.69 -> 1.70** : Flat 63,3 -> 63,2 s ; Corridor 62,4 -> 63,8 ; Nice Slope 39,8 -> 40,2 ; Spaghetti 32,9 -> 32,8 ; Hook you fool 88,4 -> 85,9 ; L'Œuf 108,5 -> 106,2 ; Gruyère haut 2:09 -> 2:20, bas 2:16 -> 1:59, hasard 3:27 -> 2:32 (moyenne 2:38 -> 2:17) ; Sans fin : grappin 32/41 -> 45/45, double 30/30 -> 22/27, montée 41/49 -> 56/56, plafond 22/22 -> 22/22. Médailles non touchées.

## 82. Sols lissés partout : courbes C², au plus 1° d'un segment au suivant (23/11, version 1.71)

Demande de l'équipe : « réduire encore la pente entre les bouts de terrain… des courbes C^infini en vrai ». Réponse : un sol de collision reste une suite de segments ; 0,001° est impossible (il faudrait des segments de 0,01 px, plus fins que la précision des nombres du moteur, ~0,016 px vers x = 150 000) et inutile (à 1 500 px/s, Pinpouin avance de 25 px par image). Choix de l'équipe : **option 2** (courbes C², 1° par segment, tous les niveaux) ; **option 3** (glisse sur la courbe mathématique exacte) gardée pour plus tard dans la feuille de route.

- **`src/levels/SmoothCurve.gd`** (nouveau, `class_name SmoothCurve`, commun) : `smooth_open` (lignes) et `smooth_closed` (contours de polygones). Le contour est coupé aux **coins durs** (mur : pente > 55° ; vrai angle : > 30°, > 60° dans les cavernes), chaque tronçon est recoupé (points posés sur les segments d'origine, tous les 24 px, jusqu'à 48 px près d'un coin fort, 96 px dans les cavernes), puis remplacé par sa **B-spline cubique uniforme** (C² : tangente et courbure continues), serrée aux bouts (bouts et directions inchangés), découpée morceau par morceau en juste assez de pas pour ne jamais tourner de plus de 1° (`MAX_TURN_DEG`), sans pas plus court que 1,5 px (`MIN_STEP_PX`, précision des nombres) ; points alignés retirés.
- Appliqué aux **collisions** de : `sol.gd` (Flat, Corridor, Nice Slope, Hook you fool, Spaghetti, Sans fin, Chill 704 / 917), `Tremplin.gd`, `HalfPipe.gd`, `GruyereGenerator._add_body`, `EggGenerator._add_body` et `_chain_to_segments`, `BateauGenerator` (tuto), `CaveGenerator` (remplace les arcs de Bézier de la 1.70). **Le dessin garde ses points d'origine** (art inchangé) : écart dessin / collision mesuré < 1 px (Flat, Spaghetti, Gruyère, Chill), 1,5 px (tuto), 3,3 px au plus (L'Œuf). Point d'indice 0 et coins durs conservés (le coin du deck du half-pipe, `poly[1]`, lu par `RaceManager`, est vérifié inchangé). Non touchés : niveaux dessinés / communauté (forme choisie par leur auteur), œufs à grappin, plafonds accrochables des cavernes.
- **Cassures de plus de 1° (segments de sol)**, avant -> après : Flat 3 483 -> 62, Nice Slope 3 243 -> 62, Spaghetti 5 548 -> 69, Hook you fool 4 973 -> 220, Chill 704 9 784 -> 158, Chill 917 1 970 -> 38, tuto 773 -> 84, Gruyère 5 791 -> 983. Celles qui restent : coins durs voulus (bords, murs, lèvres de tremplin), virages très serrés (rayon < 86 px : pas de 1,5 px, jusqu'à ~2°), contour des œufs et plafonds accrochables. Courbes de plus de 5° : Flat 644 -> 42, Spaghetti 1 294 -> 49, Chill 704 3 267 -> 107.
- Chargement des niveaux : +0 à +0,2 s (essai abandonné : subdivision + nettoyage, +0,3 à +1,5 s ; remplacé par l'échantillonnage direct de la B-spline).
- **Sonde** : aucune perte au sol hors atterrissages (Flat, Nice Slope, Hook you fool, cavernes) ; Spaghetti : une perte de 15 px/s (creux serré).
- **Bots 1.70 -> 1.71** : Flat 63,2 -> 62,5 s ; Corridor 63,8 -> 61,5 ; Nice Slope 40,2 -> 39,6 ; Spaghetti 32,8 -> 31,7 ; Hook you fool 85,9 -> 85,6 ; L'Œuf 106,2 -> 108,2 ; tuto (élève des invites) course finale 15,8 s, 0 atelier passé ; Gruyère (bot avec `FIRE_D=1000` ; à 900, il reste pendu sous l'œuf 3 après une approche différente, limite du bot) haut 2:21 -> 2:25, bas 1:52 -> 2:04, hasard 2:25 -> 3:07 (autres routes tirées dans les cavernes) ; Sans fin : comparable (le terrain du Sans fin est tiré au hasard à chaque partie : grappin double 25/29 avec comme sans le lissage). Médailles non touchées.
- Outil hors projet : `terrain_stats.gd` (env `KMIN`, `DETAIL=1|2` : cassures par objet).

## 83. Options à onglets, plein écran, caméra douce, zoom libre, air et frottement à l'écran, figure fixée (23/11, version 1.72)

Demandes de l'équipe (23/11). Choix validés : zoom libre au stick droit (R3 tenu) et au pincement ; le zoom libre s'ajoute au zoom automatique ; onglet Développeur visible, en dernier.

- **Options rangées en onglets latéraux** (`OptionsScreen.gd`, `_build_tabs`) : JEU (mode enfant, aide au début, clin d'œil, tuto figé, fantôme), AFFICHAGE (plein écran, taille de l'interface, zoom libre, flèches multi), SON (musique, effets), FANTÔMES (échange, l'ancienne colonne de droite), DÉVELOPPEUR (panneau physique F2, vitesse F3, air et frottement, figure fixée). Les nœuds de la scène et leurs variables sont gardés, simplement déplacés dans les pages. Manette / clavier : haut / bas dans les onglets (arriver sur un onglet l'ouvre), droite pour entrer dans la page, gauche pour revenir. Dernier onglet ouvert retenu.
- **Plein écran** (`Settings.fullscreen`, `apply_fullscreen`) : case dans AFFICHAGE + touche **F11** partout ; mémorisé et rétabli au lancement (PC) ; dans le navigateur, seulement par la case ou F11 (le navigateur exige un geste du joueur) ; masqué sur téléphone (déjà plein écran).
- **Caméra douce** (`AdaptiveCamera.gd`, `smooth_follow_enabled`) : le zoom automatique, le regard vers l'avant et la hauteur de la vue passent par des **ressorts amortis** (« smooth damp ») : départ en douceur, vitesse continue, plus de saut de vitesse à chaque nouveau palier de zoom ; la marge « drag » verticale de Godot (vue figée puis qui repart d'un coup) est remplacée par un ressort court (`follow_y_time` 0,12 s ; saut direct au-delà de `snap_distance`, ex. réapparition). Mesure (accélération de la vue, px / image², 40 s de course au ▶ + PUMP + sauts) : à-coups de plus de 10 px / image² : Gruyère 25 -> 3 (horizontal) et 38 -> 2 (vertical), Spaghetti 16 -> 5 et 21 -> 3, L'Œuf 16 -> 10 et 21 -> 0. Les à-coups horizontaux qui restent viennent des chocs de Pinpouin lui-même (la vue le suit sans retard en x).
- **Zoom libre** (`Settings.free_zoom`, coupé par défaut ; `Settings.zoom_factor` de 0,5 à 1,8, non mémorisé) : molette (clic molette = zoom auto), manette : tenir R3 et pousser le stick droit (clic court sur R3 = zoom auto ; le stick droit vise aussi le grappin, sans gêne), téléphone : pincer à deux doigts dans la zone de jeu (`TouchControls._pinch_input` : le 1er doigt lance le grappin comme avant ; un 2e doigt posé moins de 0,3 s après transforme le geste en pincement et relâche le grappin). Le facteur multiplie le zoom automatique (lissé lui aussi).
- **Air et frottement sous la vitesse** (`Settings.show_coefs`, onglet Développeur ; `SpeedMeter._update_coefs`) : « Air k = 3,47·10⁻⁵ /px −N px/s² » et « Glace μ = 0,020 −N px/s² » (freinage de la dernière image, `Player.last_air_decel` / `last_friction_decel`), en **gras blanc** quand le jeu l'applique (frottement : au sol ; air : dès que Pinpouin bouge, grappin compris), gris pâle sinon (3 images de suite avant de changer : pas de clignotement). Le cadre s'affiche aussi sans le compteur de vitesse.
- **Figure fixée** (`Settings.fixed_trick`, onglet Développeur ; `TrixState.enter`) : « Au hasard (normal) » ou Toupie / Boule / Étoile ninja / Carpe (`Settings.TRICKS`, noms de `TrickScore.gd`).
- Physique inchangée : bots identiques à la 1.71 (Flat, Corridor, Nice Slope, Spaghetti, Hook you fool, L'Œuf ; Sans fin tiré au hasard) ; tuto (élève des invites) terminé.
