# ThreatHelper Forever : à vérifier en jeu

Ce que les tests hors jeu ne peuvent pas voir. Noter la version du client à chaque passage.
Avant : `/console scriptErrors 1`.

## Chargement
- [ ] L'addon apparaît dans la liste des addons, aucune erreur Lua au chargement.
- [ ] Rien n'est écrit dans le chat à la connexion.

## Sonde (`/aggro probe`, cible un monstre en combat)
- [ ] `UnitThreatSituation` renvoie un nombre (attendu : 3 quand tu tiens la cible).
- [ ] `UnitThreatLeadSituation` existe et renvoie un nombre 0 à 3.
- [ ] `UnitDetailedThreatSituation` renvoie des nombres sur un monstre normal.
- [ ] Même chose sur un boss : noter si des valeurs sortent en `<SECRET>`.

## Cadre
- [ ] `/aggro unlock` : le cadre apparaît sous le centre de l'écran et se déplace à la souris.
- [ ] `/aggro lock` puis `/reload` : il garde sa place, caché hors combat.
- [ ] En combat avec une cible : barre et texte d'état visibles, lisibles, sans débordement.

## Alertes
- [ ] `/aggro test` : trois messages au centre (jaune, orange, rouge) et un son à chacun.
- [ ] En groupe, un DPS qui monte fait passer Attention puis Danger avec son nom.
- [ ] Laisser un membre prendre la cible : « AGGRO PERDUE sur <nom> : PROVOCATION ! ».
- [ ] Aucune fenêtre « ThreatHelper Forever a été bloqué » pendant tout ça.

## Liste des monstres (0.9.0)
- [ ] En combat contre 2 ou 3 monstres : une ligne par monstre, sans trou, le plus menacé en haut.
- [ ] La ligne de la cible a la bordure jaune ; la liste disparaît hors combat.
- [ ] `/aggro unlock` : la liste se déplace ; `/aggro lock`.

## Réglages et minicarte (1.0.0)
- [ ] Bouton sur la minicarte (icône Posture défensive), info-bulle à trois lignes, se déplace autour.
- [ ] Clic gauche : fenêtre de réglages (panneau Blizzard), Échap la ferme ; clic droit : verrou.
- [ ] Chaque case agit tout de suite ; les boutons Tous / Cible / Aucun restent surlignés sur le choix.
- [ ] Seuils - / + par pas de 5 ; une pastille de couleur change la barre et les pourcentages.
- [ ] « Tout réinitialiser » remet tout par défaut ; aucune fenêtre « bloqué ».
