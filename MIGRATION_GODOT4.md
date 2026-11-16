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
