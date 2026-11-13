# Historique d'Arcanum

## 1.1.0 — 13 novembre 2026

- Rappels d'eau et de nourriture : seuls les objets invoqués comptent (une eau achetée ne dispense plus d'en invoquer). Les objets de tous les rangs d'Invocation d'eau et de nourriture de Forever sont reconnus.
- Le rappel de la gemme de mana revient : il s'affiche quand la meilleure gemme que tu sais invoquer n'est pas dans tes sacs.
- Les charges ne s'affichent que quand tu en as : sans charge, plus de cristaux vides.
- Les procs montrent leur propre icône (Idées claires, Barrage de projectiles) au lieu de celle du sort à lancer.
- Le signal de burst est retiré (icône, son, rappel, réglages). À sa place, au-dessus des charges : l'icône de la Présence spirituelle, tant qu'elle est active.
- Les réglages tiennent de nouveau sur une colonne.

## 1.0.0 — 13 novembre 2026

Arcanum repart sur de nouvelles bases : le cercle laisse la place à quatre zones autour du personnage.

- À gauche du personnage, les Idées claires ; à droite, le Barrage de projectiles : une grande icône avec le temps restant, seulement quand le proc est actif.
- En haut, les charges de Déflagration des Arcanes : un cristal par charge visée, et dessous la barre des 18 secondes de leur fenêtre, avec les secondes.
- Au-dessus des charges, au moment du burst seulement : l'icône du sort à lancer, en or (Pouvoir des Arcanes, puis le Courroux de la macro de burst). Le son, l'onde et le rappel après 6 secondes sont conservés.
- En bas, hors combat : les rappels de ce qui manque. Intelligence des Arcanes et armure, comme avant, plus l'eau et la nourriture quand les sacs n'en ont plus. Le rappel de gemme de mana est retiré. Au repos en ville, les rappels ne s'affichent pas.
- Nouveau réglage « Écartement » (`/arc ecart 150`) : la distance entre le personnage et les zones. Le HUD est recentré sur l'écran à la mise à jour.
- Retirés : le cercle, le conseil du prochain sort (et `/arc conseil`, `/arc aoe`), les gemmes de temps de recharge, la barre de mana, et les réglages qui allaient avec.

## 0.12.2 — 12 novembre 2026

- Mode suivi seul : avec la macro de burst (réglage « Burst en une icône », actif par défaut), l'icône du centre montre directement le Courroux des Arcanes au lieu d'Eurêka puis de la Présence spirituelle : une seule touche fait tout. Le Pouvoir des Arcanes, qui n'est pas dans la macro, garde son icône.

## 0.12.1 — 12 novembre 2026

- Mode suivi seul : au moment du burst, l'icône du sort à lancer s'affiche au centre du cercle, cerclée d'or. Le centre restait vide. Elle suit l'ordre du burst (Pouvoir des Arcanes, puis Eurêka, puis Présence spirituelle, puis le Courroux qui en profite) et s'efface si un proc s'y affiche.

## 0.12.0 — 12 novembre 2026

- Gemme « bientôt prête » : dix secondes avant la fin d'une recharge, la gemme reprend ses couleurs, prend un bord doré et compte les secondes. Réglage « Recharge bientôt finie » (de 5 à 30 secondes, ou « non »).
- Rappel du burst : si le signal reste allumé 6 secondes sans que tu lances un gros temps de recharge, l'onde dorée et le son sont redonnés une fois. Lancer l'un d'eux relance le délai pour les suivants. Réglage « Rappel du burst » (de 2 à 12 secondes, ou « non »). En mode suivi seul.
- Les sons se choisissent par leur nom dans les réglages : une ligne par signal (Idées claires, Barrage, Burst), deux flèches pour passer d'un son à l'autre en l'écoutant. Une quinzaine de sons du jeu, plus la voix du jeu, qui dit le mot (« Burst ») si une voix de synthèse est installée. `/arc son burst voix` fait la même chose.
- La fenêtre des réglages passe sur deux colonnes : elle devenait trop haute.

## 0.11.0 — 12 novembre 2026

- Un son quand c'est le moment du burst (la Témérité du guerrier, par défaut). Il retentit une fois quand le moment arrive, en mode suivi seul comme en mode conseil, et n'est pas rejoué si le signal s'éteint et revient dans les 8 secondes.
- Les sons se choisissent : `/arc son 888` fait entendre un son du jeu, `/arc son burst 888` le choisit pour le moment du burst (`clear` ou `barrage` pour les procs), `/arc son burst` revient au son d'origine. Un identifiant que le jeu ne joue pas n'est pas retenu.
- `/arc sons` fait entendre les trois sons et dit lesquels sont joués.

## 0.10.0 — 12 novembre 2026

- Mode suivi seul : Arcanum signale le moment du burst. Quand les charges visées sont atteintes, que la Colère est prête et qu'aucun proc n'est à dépenser d'abord, les gemmes des temps de recharge prêts (Eurêka, Présence spirituelle…) grossissent et battent en or, l'anneau passe à l'or et une onde dorée part du cercle. Le réglage « Signaler le moment du burst » (ancien « Conseiller les gros temps de recharge ») le coupe.
- Charges visées atteintes : les cristaux et l'arc passent au violet très clair au lieu du rose, trop proche de celui du Barrage de projectiles. Ils ne pulsent plus en continu : ce qui bat est réservé à ce qui demande une action (procs, burst).
- L'arc de la fenêtre des charges se lit mieux : l'anneau s'efface en piste sombre dessous tant qu'il y a des charges.

## 0.9.2 — 12 novembre 2026

- La démonstration (`/arc demo`) joue maintenant dans le mode choisi. En mode suivi seul, elle montre les charges qui montent, les procs au centre (un, puis deux côte à côte) et les temps de recharge, sans conseil. Elle montrait jusqu'ici toujours le mode conseil.

## 0.9.1 — 12 novembre 2026

- Mode suivi seul : les procs actifs s'affichent en grandes icônes au centre du cercle, à la place du conseil. L'icône est celle du sort que le proc améliore (Projectiles pour le Barrage, Déflagration pour les Idées claires), cerclée de la couleur du proc, avec le temps restant. Un proc : une icône centrée ; deux : côte à côte. Les orbes du bas ne servent plus qu'en mode conseil.

## 0.9.0 — 12 novembre 2026

- Mode « suivi seul » : le réglage « Prochain sort conseillé » (ou `/arc conseil`) masque l'icône centrale. Le cercle ne montre alors que les charges, leur fenêtre, les procs et les gros temps de recharge, sans rien conseiller.

## 0.8.3 — 12 novembre 2026

- Réglage « Anticiper » : pendant un Éclair de givre ou une Boule de feu, Arcanum annonçait encore une Déflagration gratuite alors que le sort en cours allait dépenser les Idées claires. L'anticipation en tient compte.

- Diagnostic : le journal garde 120 changements au lieu de 60, et les salves d'une canalisation tiennent sur une ligne (« sort missiles x6 ») au lieu de le remplir. Il note aussi le délai entre Présence spirituelle et la Colère qui suit, pour savoir si la macro de burst les lance au même appui.

## 0.8.2 — 12 novembre 2026

- Macro de burst : le Courroux ne partait pas au même appui qu'Eureka et Présence spirituelle. `/arc macro` sépare maintenant les sorts par `/stopcasting`, la forme classique de cette macro. Relance `/arc macro` pour mettre la tienne à jour. Attention : appuyée pendant une incantation, la macro l'interrompt.

## 0.8.1 — 12 novembre 2026

D'après un rapport de combat (`/arc diag`).

- Mana : le jeu le cache en combat, ce qui rendait la règle « gemme puis Évocation sous 15 % de mana » inopérante. Arcanum l'estime maintenant avec ce que le jeu dit encore : si un sort qui coûte moins de 15 % de ton mana maximum devient impayable, tu es sous 15 %.
- Présence spirituelle lancée avant le combat restait notée « active » pendant tout le combat, ce qui pouvait faire conseiller le Courroux à tort. Le premier sort à incantation la termine.

## 0.8.0 — 12 novembre 2026

Review design : chaque élément a dû justifier sa place.

- Cristaux : un par charge visée seulement (deux par défaut), au-dessus du cercle et un peu plus grands. Un cristal de plus apparaît quand le jeu offre une charge. Fini les cristaux éteints en permanence, et l'arc de la fenêtre n'est plus brouillé par eux.
- Procs : des orbes de couleur sans icône, pour ne plus les confondre avec les temps de recharge.
- Icône centrale agrandie (64 au lieu de 56).
- Ondes plus petites, et plus aucune quand les charges visées sont atteintes (les cristaux bondissent déjà).
- Retirés : le halo derrière le cercle, les runes gravées et leur réglage.

Des textures ont changé : quitte et relance le jeu après la mise à jour.

## 0.7.2 — 12 novembre 2026

- Idées claires pendant une incantation : si le proc arrive pendant un Éclair de givre ou une Boule de feu, c'est ce sort bon marché qui le dépenserait. Arcanum conseille alors d'interrompre : l'icône passe à la Déflagration, en bleu clair, avec un bord blanc qui bat vite. Rien ne change pour un Barrage de projectiles (il attend la fin du sort), ni quand il reste moins d'une demi-seconde d'incantation. Réglable.

## 0.7.1 — 12 novembre 2026

Passe de performance, de nettoyage et de relecture du cycle. Rien ne change à l'écran.

- Beaucoup moins d'appels au jeu : sur le jeu simulé, 42 par seconde en combat au lieu de 530, et 13 au lieu de 114 quand le HUD est masqué. Les auras, les coûts, les temps de recharge, la cible et l'incantation en cours ne sont relus que lorsque le jeu signale un changement ; en combat, les auras que le jeu classe secrètes ne sont plus demandées du tout.
- Affichage : plus aucune table créée à chaque image, les cristaux au repos ne sont plus redessinés, et un HUD masqué ne fait presque plus rien.
- Addon plus léger : quatre textures inutilisées retirées, trois autres réduites (350 Ko de textures au lieu de 600).
- Cycle : quand la fenêtre des charges est presque finie (moins de 4 secondes), Arcanum ne conseille plus de monter une charge de plus ; il fait profiter des charges en place.
- Code mort retiré ; le banc de test vérifie maintenant le nombre d'appels au jeu et l'absence de variable globale parasite.

## 0.7.0 — 12 novembre 2026

- Mode multi-cibles : il s'active quand tu lances un sort de zone (ou avec `/arc aoe` avant le pull) et conseille Choc de flammes, Eureka, Présence spirituelle, puis Explosion des Arcanes. Le cercle passe à l'orange.
- Rang du remplissage : l'Éclair de givre est conseillé au rang 1 par défaut, avec un « 1 » sur l'icône ; réglage « max » pour le dernier rang.
- Burst en une icône : avec la macro ArcBurst, Arcanum montre directement le Courroux pendant Eureka et Présence spirituelle (réglable).
- L'icône rougit quand la cible est hors de portée.
- Rappels avant le combat, sous le cercle : Intelligence des Arcanes, armure, gemme de mana manquante.
- Diagnostic : nouvelle section « Vérifications en jeu » (mana lisible ou non en combat, Présence spirituelle conservée ou non après des Projectiles, rangs de l'Éclair de givre).

## 0.6.2 — 12 novembre 2026

Première version du dépôt.

- Cercle runique : le prochain sort au centre, les charges de Déflagration en haut de l'anneau, l'arc de leur fenêtre de 18 secondes, les gros temps de recharge sur les côtés, une gemme par proc en bas.
- Conseil du prochain sort : Projectiles sur un Barrage, Déflagration gratuite sur des Idées claires, Courroux en ouverture puis à charges visées atteintes (2 par défaut) avec Eureka et Présence spirituelle, Éclair de givre en remplissage, gemme de mana et Évocation quand le mana manque.
- Suivi en combat malgré les auras cachées : sorts lancés, coût des sorts annoncé par le jeu, surbrillance des boutons, icônes du Gestionnaire de temps de recharge.
- `/arc macro` crée la macro de burst avec les noms exacts des sorts ; `/arc diag` produit un rapport à copier.
