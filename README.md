# Arcanum

Le HUD du mage Arcanes pour World of Warcraft: Forever : tes procs, tes charges et le moment du burst, autour de ton personnage.

Arcanum place chaque information d'un côté de ton personnage, pour que tu la lises sans quitter le combat des yeux :

![Aperçu du HUD d'Arcanum](docs/apercu.png)

*Aperçu composé avec les textures de l'addon (le personnage est une silhouette, les icônes de sorts sont remplacées par des aplats, les zones sont plus rapprochées qu'en jeu). De gauche à droite : en combat avec deux procs, hors combat avec deux rappels, et le moment du burst. En jeu : `/arc demo`.*

- **À gauche : les Idées claires. À droite : le Barrage de projectiles.** Une grande icône (celle du sort que le proc améliore : Déflagration des Arcanes, Projectiles des Arcanes), cerclée de la couleur du proc, bleu clair ou rose, avec le temps restant en chiffres et un voile qui grandit à mesure que le proc s'épuise. Pas de proc : le côté reste vide.
- **En haut : les charges de Déflagration des Arcanes.** Un cristal par charge visée (deux par défaut, réglable à 3 ou 4), qui s'éclaircit quand la cible est atteinte ; un cristal de plus apparaît quand le jeu t'offre une charge. Dessous, une barre se vide pendant les 18 secondes de la fenêtre des charges, avec les secondes restantes ; elle rougit quand la fenêtre va se fermer.
- **Au-dessus des charges, seulement au bon moment : le burst.** Voir plus bas.
- **En bas, hors combat : les rappels.** L'icône de ce qu'il manque avant d'engager : Intelligence des Arcanes, armure, eau, nourriture. L'eau et la nourriture sont rappelées quand tes sacs n'en ont plus (invoquées ou achetées). Rien ne manque : rien ne s'affiche. Au repos en ville, les rappels attendent que tu sortes ou que tu cibles un ennemi.

Le HUD est centré sur l'écran, là où se tient ton personnage. Le réglage « Écartement » (ou `/arc ecart 150`) éloigne ou rapproche les quatre zones ; `/arc verrou` permet de déplacer l'ensemble.

**Le moment du burst.** Pour ne pas oublier tes gros temps de recharge, Arcanum te dit quand les claquer : au bon moment (charges visées atteintes, Courroux prêt, aucun proc à dépenser d'abord), l'icône du sort à lancer apparaît au-dessus des charges, cerclée d'or, avec une onde dorée et un son. C'est le Pouvoir des Arcanes dès qu'il est prêt, puis le Courroux des Arcanes : la macro de burst (`/arc macro`) lance Eurêka et la Présence spirituelle avec lui. Sans la macro (réglage « Macro de burst » coupé), l'icône déroule Eurêka, puis la Présence spirituelle, puis le Courroux. Si le signal reste allumé 6 secondes sans que tu lances un de ces sorts, l'onde et le son sont redonnés une fois (réglage « Rappel du burst », de 2 à 12 secondes, ou « non »). Le réglage « Signaler le moment du burst » coupe le tout.

**Les sons.** Un son à l'arrivée d'un proc, un autre quand c'est le moment du burst. Ce sont des sons du jeu : le ping de la mini-carte pour un Barrage de projectiles, la notification Battle.net pour des Idées claires, la Témérité du guerrier pour le burst. `/arc sons` les fait entendre.

Tu peux en choisir d'autres dans les réglages (`/arc`) : chaque signal a sa ligne, avec le nom du son entre deux flèches. Une flèche passe au son suivant et le fait entendre ; un clic sur le nom le rejoue. La liste propose une quinzaine de sons du jeu (alerte de raid, appel de préparation, montée de niveau, quête terminée, réveil…) et la **voix du jeu**, qui dit « Burst », « Barrage » ou « Idées claires » avec la synthèse vocale de WoW, si une voix est installée sur ton ordinateur. Un son que ton client ne joue pas est sauté.

Pour un son hors liste : `/arc son 888` fait entendre le son de cet identifiant, `/arc son burst 888` le choisit pour le moment du burst (`clear` et `barrage` pour les procs), `/arc son burst` revient au son par défaut. Les identifiants se trouvent dans la base de sons de Wowhead (le nombre dans l'adresse de la page). Tu peux aussi déposer tes propres fichiers `.ogg` dans `Arcanum\Sounds` (voir le LISEZMOI du dossier).

**Ce qu'Arcanum ne fait plus.** Jusqu'à la version 0.12, Arcanum était un cercle qui conseillait le prochain sort. Depuis la 1.0 il ne conseille plus le cycle : il montre tes procs, tes charges, le moment du burst et tes rappels, et te laisse jouer.

## Installation

1. Télécharge `Arcanum-x.y.z-forever.zip` sur la dernière release du dépôt, ou récupère le dossier `Arcanum`.
2. Place le dossier `Arcanum` dans `World of Warcraft\_forever_\Interface\AddOns`.
3. Lance le jeu. Si Arcanum est marqué « périmé » dans la liste des addons, coche **Charger les addons périmés**.

Il ne se réveille que sur un mage. Après une mise à jour qui ajoute des textures, quitte et relance le jeu : un `/reload` ne les voit pas.

## Commandes

| Commande | Effet |
|---|---|
| `/arc` | Réglages (ce qui s'affiche, taille, écartement, sons, burst, charges visées) |
| `/arc demo` | Le HUD joue un cycle complet, sans combattre (marche sur toute classe) |
| `/arc verrou` | Déplacer le HUD, puis le fixer |
| `/arc taille 120` | Taille du HUD, en pourcentage (de 60 à 180) |
| `/arc ecart 150` | Distance entre le personnage et les zones (de 80 à 320) |
| `/arc sons` | Fait entendre les trois sons (Idées claires, Barrage, moment du burst) |
| `/arc son 3071` | Fait entendre un son du jeu ; `/arc son burst 3071` le choisit pour un signal (`clear`, `barrage` ou `burst`), `/arc son burst voix` le fait dire par la voix du jeu |
| `/arc macro` | Crée la macro de burst (Eureka + Présence spirituelle + Courroux) avec les noms exacts que le jeu donne aux sorts |
| `/arc diag` | Rapport à copier : sorts reconnus, signaux lus, derniers changements d'état |

**Comment il voit les procs en combat.** Forever cache les auras aux addons pendant le combat. Arcanum s'appuie sur ce qui reste lisible : tes propres sorts lancés (chaque Déflagration ajoute une charge, pendant les 18 s que dure la fenêtre ouverte par la première), le coût en mana annoncé par le jeu (Projectiles gratuits = Barrage, tout gratuit = Idées claires, et le coût de la Déflagration, +100 % par charge, donne le nombre exact de charges), la surbrillance des boutons, et les icônes du Gestionnaire de temps de recharge de Blizzard si tu y suis ces buffs (Options > Améliorations de jeu). Hors combat il relit les vraies auras et apprend les durées et les coûts réels. Il affiche, il ne lance rien.

## Développement

- `python tools/test/run_tests.py` lance un mage simulé avec les règles de Forever : auras cachées et valeurs secrètes en combat, coût des sorts et sorts lancés lisibles. Il compte aussi les appels au jeu et les opérations d'affichage, pour que l'addon reste sobre. Il faut le module `lupa` (`pip install lupa`).
- `python tools/make_media.py` régénère les textures, `python tools/preview.py` l'aperçu `docs/apercu.png`.
- Publier une version : ajoute une section `## X.Y.Z` dans `CHANGELOG.md`, puis `python tools/release.py X.Y.Z`. Le script met le numéro à jour, lance les tests, crée l'étiquette `vX.Y.Z` et pousse ; GitHub Actions publie la release (`Arcanum-X.Y.Z-forever.zip` et `release.json` pour WowUp).
