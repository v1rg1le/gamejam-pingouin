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
