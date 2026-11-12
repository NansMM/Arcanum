# Arcanum

Le HUD du mage Arcanes pour World of Warcraft: Forever : un cercle qui dit quel sort lancer ensuite.

Arcanum affiche sous ton personnage un cercle, avec au centre le prochain sort à lancer :

![Aperçu du HUD d'Arcanum](docs/apercu.png)

*Aperçu composé avec les textures de l'addon (les icônes de sorts sont remplacées par des aplats). À gauche le cycle normal, à droite un Barrage de projectiles. En jeu : `/arc demo`.*

- **Au centre** : le sort à lancer ensuite. Sa couleur, reprise par l'anneau, dit pourquoi : violet pour le cycle normal, rose pour un Barrage de projectiles, bleu clair pour des Idées claires, or pour les gros dégâts (Eureka, Présence spirituelle, Courroux instantané), bleu pour le mana (gemme, Évocation, sort moins cher, baguette), orange en multi-cibles. Pendant une incantation il ne change pas : un voile se retire à mesure que le sort part, puis il passe au suivant (une option permet au contraire d'anticiper).
- **Au-dessus du cercle, les cristaux** : un par charge de Déflagration des Arcanes visée (deux par défaut). Ils pulsent quand la cible est atteinte ; un cristal de plus apparaît quand le jeu t'offre une charge.
- **L'arc lumineux autour de l'anneau** : les 18 secondes de la fenêtre des charges, qui se vide.
- **À gauche et à droite, sertis dans l'anneau** : tes gros temps de recharge, avec leur icône (Présence spirituelle, Eureka du gnome, Pouvoir des Arcanes, Berserker ou Fureur sanguinaire, selon ce que ton personnage connaît).
- **En bas de l'anneau** : un orbe de couleur par proc actif, rose pour le Barrage de projectiles, bleu clair pour les Idées claires, avec un voile qui grandit à mesure que le proc s'épuise.
- **Sous le cercle, hors combat** : ce qu'il manque avant d'engager (Intelligence des Arcanes, armure, gemme de mana).
- **L'icône rougit** quand la cible est hors de portée du sort conseillé.
- En option : une barre de mana.

L'ordre conseillé part du guide Method (patch 1.60.1), adapté à ce qui se mesure en jeu : chaque charge double le coût de la Déflagration suivante, et rien ne les consomme pendant leurs 18 secondes. Arcanum vise donc un nombre de charges (**2 par défaut**, réglable à 3 ou 4 dans `/arc`), puis en profite avec des sorts qui ne coûtent pas plus cher :

1. Pouvoir des Arcanes dès qu'il est prêt.
2. Projectiles des Arcanes sur un Barrage de projectiles : ils sont gratuits, et un nouveau proc serait perdu tant que celui-ci n'est pas dépensé.
3. Déflagration sur des Idées claires : c'est le sort le plus cher, elle devient gratuite et la charge en plus aussi. (Le Courroux dépenserait le proc pour deux fois moins de mana économisé.) Si le proc arrive pendant l'incantation d'un Éclair de givre ou d'une Boule de feu, c'est ce sort qui le dépenserait : un bord blanc bat alors vite autour de l'icône pour te dire d'interrompre (réglable).
4. Hors combat, sans charge : Courroux en ouverture. Le premier sort ne coûte pas de temps de combat, autant y mettre la plus longue incantation (réglable).
5. Charges visées atteintes, Courroux prêt : Eureka, puis Présence spirituelle, puis Courroux des Arcanes. Avec la macro de burst (`/arc macro`), une seule touche fait les trois : Arcanum montre alors directement le Courroux, en or (réglable).
6. Gemme de mana, puis Évocation, sous 15 % de mana.
7. Sous les charges visées : Déflagration, sauf si la fenêtre des charges se ferme dans moins de 4 secondes (une charge de plus ne servirait à rien).
8. Charges visées atteintes : Éclair de givre ou Boule de feu (le moins cher), qui profitent des charges et peuvent déclencher un Barrage. Au rang 1 par défaut, signalé par un « 1 » sur l'icône : deux fois plus de lancers, donc de chances de Barrage, pour moins de la moitié du mana et environ 17 % de dégâts en moins. Le réglage « max » conseille le dernier rang.
9. Si le mana ne suit plus : Courroux, gemme de mana, Évocation, le sort le moins cher, la baguette.

Un réglage retire les gros temps de recharge du conseil (Pouvoir des Arcanes, Eureka, Présence spirituelle), pour les garder sous la main.

**Plusieurs ennemis.** Le mode multi-cibles s'active tout seul quand tu lances un sort de zone, et retombe quand tu relances un sort mono-cible, après 8 secondes sans sort de zone, ou à la fin du combat ; `/arc aoe` le force avant le pull. Le cercle passe à l'orange et conseille : Choc de flammes en ouverture, Eureka, Présence spirituelle pour un Choc de flammes instantané, puis Explosion des Arcanes en boucle. Pas de montée de charges : l'Explosion ne reçoit que 14 % des dégâts des sorts, les charges ne se remboursent pas.

La variante Feu ajoute l'Explosion pyrotechnique sur 3 charges d'Échauffement et le Trait de feu, si tu as ces sorts.

## Installation

1. Télécharge `Arcanum-x.y.z-forever.zip` sur la dernière release du dépôt, ou récupère le dossier `Arcanum`.
2. Place le dossier `Arcanum` dans `World of Warcraft\_forever_\Interface\AddOns`.
3. Lance le jeu. Si Arcanum est marqué « périmé » dans la liste des addons, coche **Charger les addons périmés**.

Il ne se réveille que sur un mage. Après une mise à jour qui ajoute des textures, quitte et relance le jeu : un `/reload` ne les voit pas.

## Commandes

| Commande | Effet |
|---|---|
| `/arc` | Réglages (taille, ce qui s'affiche, sons, charges visées, rang du remplissage, gros temps de recharge) |
| `/arc demo` | Le HUD conseille un cycle complet, sans combattre (marche sur toute classe) |
| `/arc verrou` | Déplacer le HUD, puis le fixer |
| `/arc aoe` | Mode multi-cibles, jusqu'à la fin du combat |
| `/arc macro` | Crée la macro de burst (Eureka + Présence spirituelle + Courroux) avec les noms exacts que le jeu donne aux sorts |
| `/arc diag` | Rapport à copier : sorts reconnus, signaux lus, derniers conseils et changements d'état |

**Comment il voit les procs en combat.** Forever cache les auras aux addons pendant le combat. Arcanum s'appuie sur ce qui reste lisible : tes propres sorts lancés (chaque Déflagration ajoute une charge, pendant les 18 s que dure la fenêtre ouverte par la première), le coût en mana annoncé par le jeu (Projectiles gratuits = Barrage, tout gratuit = Idées claires, et le coût de la Déflagration, +100 % par charge, donne le nombre exact de charges), la surbrillance des boutons, et les icônes du Gestionnaire de temps de recharge de Blizzard si tu y suis ces buffs (Options > Améliorations de jeu). Hors combat il relit les vraies auras et apprend les durées et les coûts réels. Il conseille, il ne lance rien.

## Développement

- `python tools/test/run_tests.py` lance un mage simulé avec les règles de Forever : auras cachées et valeurs secrètes en combat, coût des sorts et sorts lancés lisibles. Il compte aussi les appels au jeu et les opérations d'affichage, pour que l'addon reste sobre. Il faut le module `lupa` (`pip install lupa`).
- `python tools/make_media.py` régénère les textures, `python tools/preview.py` l'aperçu `docs/apercu.png`.
- Publier une version : ajoute une section `## X.Y.Z` dans `CHANGELOG.md`, puis `python tools/release.py X.Y.Z`. Le script met le numéro à jour, lance les tests, crée l'étiquette `vX.Y.Z` et pousse ; GitHub Actions publie la release (`Arcanum-X.Y.Z-forever.zip` et `release.json` pour WowUp).
