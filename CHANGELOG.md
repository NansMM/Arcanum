# Historique d'Arcanum

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
