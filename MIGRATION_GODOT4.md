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
