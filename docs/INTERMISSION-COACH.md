# Intermission Coach — Entombed Sentinels (mythique)

Module « Intermission Coach » de GideonRaid : il rend la **coordination de
l'intermission des Entombed Sentinels** (raid *The Venomous Abyss*, Midnight
12.1.0) possible et rapide **avec une action minimale du joueur**, sans jamais
lire une API de combat.

Guide de référence :
<https://raidstrats.gg/guides/entombed-sentinels/mythic/phase/quick-overview>

---

## 1. La mécanique, telle qu'elle est implémentée

- Pendant l'intermission, **chaque joueur reçoit au hasard une combinaison
  d'orbes affichée au-dessus de sa tête** :
  - `1 vert + 3 rouges` → déclarée « **1** »
  - `2 verts + 2 rouges` → déclarée « **2** »
  - `3 verts + 1 rouge` → déclarée « **3** »
- **Combinaisons qui sauvent : 2+2 et 1+3.** Toute autre collision tue ;
  `2+3` = 5 verts = « **5g** ».
- Environ **3 s** après le début, le boss obscurcit la salle : **chaque joueur ne
  voit plus que SON propre numéro**.
- Stratégies de guilde : ping, orientation spatiale (gauche / milieu-sous le boss
  / droite), ou `/say 1-2-3`.

## 2. Convention implémentée (configurable dans le code, pas dans l'UI)

| Déclaration | Orbes | Position | Ping | Couleur | Consigne |
|---|---|---|---|---|---|
| « 1 » | 1 vert + 3 rouges | **GAUCHE** du boss | `Enum.PingSubjectType.Warning` | **ROUGE** | saute sur place, ping rouge, rejoint un 3 |
| « 2 » | 2 verts + 2 rouges | **MILIEU / sous le boss** | `Enum.PingSubjectType.OnMyWay` | **BLEU** | cours sous le boss, ping bleu, rejoint un autre 2 |
| « 3 » | 3 verts + 1 rouge | **DROITE** du boss | `Enum.PingSubjectType.Assist` | **VERT** | fonce sur un 1, ping vert |

Les **couleurs** sont vérifiées sur la galerie du wiki
(<https://warcraft.wiki.gg/wiki/Ping_System>) : `Warning` = panneau rouge,
`OnMyWay` = flèche bleue, `Assist` = drapeau vert — ce qui correspond à la
convention de guilde « vert = 3, bleu = 2, rouge = 1 ».

## 3. Ce que l'addon fait / ne peut PAS faire (à dire tel quel aux joueurs)

**Il peut :**

- afficher le plan préparé hors jeu (partenaire, rôle, position, paires) ;
- afficher un rappel en très gros de la convention au déclenchement ;
- afficher 3 boutons `1 / 2 / 3` : le joueur clique ce qu'il voit au-dessus de sa
  tête, et **la consigne correspondante apparaît immédiatement** ;
- afficher un **compte à rebours de 3 s** (fenêtre de visibilité) puis signaler
  la salle obscurcie ;
- **générer la macro de ping** prête à coller, adaptée à la déclaration.

**Il ne peut PAS (contraintes 12.x, à assumer) :**

- lire les auras / indicateurs d'un autre joueur (valeurs secrètes) —
  <https://warcraft.wiki.gg/wiki/Secret_Values> ;
- lire **les siens** de façon exploitable : c'est le joueur qui déclare ;
- envoyer un ping lui-même : `C_Ping.SendMacroPing` est **#protected**
  (« This can only be called from secure code ») —
  <https://warcraft.wiki.gg/wiki/API:C_Ping.SendMacroPing> ;
- **savoir qui a déclaré quoi** : aucun canal addon→addon en instance, et l'UI
  d'un addon est locale à son client. L'UI l'écrit noir sur blanc
  (« INCONNU : personne ne peut lire ton numero ni te dire qui a declare quoi ») ;
- afficher un texte visible par les autres joueurs : **le ping est le seul
  signal** que les autres voient.

Autrement dit : **rien n'est automatique dans cet addon**. Tout ce qui s'affiche
vient d'un clic du joueur ou d'un fichier préparé hors jeu.

## 4. Macro de ping (statut : **à confirmer en jeu**)

L'addon génère et affiche le texte exact à coller dans une macro :

```
/run C_Ping.SendMacroPing({type = Enum.PingSubjectType.Warning, targetToken = "player"})
```

- `C_Ping.SendMacroPing(macroInfo)` en 12.1.0 prend une **structure**
  (`type`, `targetToken`, `spellID`, `itemID`) —
  <https://warcraft.wiki.gg/wiki/API:C_Ping.SendMacroPing> ; les valeurs de
  `Enum.PingSubjectType` (0 Attack, 1 Warning, 2 Assist, 3 OnMyWay, …) sont
  vérifiées sur <https://warcraft.wiki.gg/wiki/Enum.PingSubjectType>.
- Variante de secours générée : `/ping Warning` (commande de macro existante,
  vue en usage réel ; **le wiki n'a pas de page `MACRO ping`**, donc la casse et
  le jeton exact sont à confirmer).
- **À confirmer en jeu :** (1) l'appel depuis une macro est bien autorisé,
  (2) `targetToken = "player"` produit bien un ping sur soi (icône au-dessus de
  la tête / cadre de raid), (3) le jeton de la variante `/ping`.

## 5. Contrat de données (GIDEON → addon)

`GideonRaidDB.assignment` (écrit hors jeu, lu par l'addon) :

```lua
GideonRaidDB = {
    schema = 1,
    assignment = {
        schema = 1,
        pairs = {
            { a = "Velna",  b = "Torgh" },
            { a = "Bathman", b = "Coren" },
        },
        -- OPTIONNEL : plan préparé hors jeu (rôle / position par joueur)
        plan = {
            { name = "Velna",   role = "2", position = "MIDDLE" },
            { name = "Torgh",   role = "2", position = "MIDDLE" },
            { name = "Bathman", role = "1", position = "LEFT"   },
            { name = "Coren",   role = "3", position = "RIGHT"  },
        },
    },
}
```

- `plan` est **facultatif** : sans lui, l'addon affiche seulement le partenaire
  et la liste des paires.
- `role` accepte la déclaration préparée (`"1"`, `"2"`, `"3"`) **ou** un rôle de
  raid libre (`"Tank"`, `"Heal"`) — dans ce dernier cas l'addon n'en déduit
  aucune rencontre.
- Si les deux rôles d'une paire sont des déclarations, l'addon affiche
  `Rencontre 2+2 : OK` ou `Rencontre 2+3 : MORT (5 verts = 5g)` : c'est un
  **contrôle du plan préparé**, pas une lecture en jeu.
- Une entrée de `plan` malformée est ignorée et comptée (« Plan : 1 entrée
  ignorée »), jamais un crash.
- Fixture de contrat : `tests/fixtures/assignment_sample.lua`.

## 6. Configuration

Dans `GideonRaidDB.intermission` (valeurs résolues et bornées par
`ns.Config.resolveIntermission`) :

| Clé | Défaut | Effet |
|---|---|---|
| `enabled` | `true` | active/désactive tout le module (`/gr inter on|off`) |
| `startOnEncounterStart` | `true` | lance la timeline sur `ENCOUNTER_START` |
| `autoShowPanel` | `true` | ouvre le panneau au déclenchement |
| `scale` | `1.0` | échelle du panneau (bornée 0.5 – 3.0) |
| `visibilitySeconds` | `3` | fenêtre de visibilité (bornée 1 – 10) |
| `durationSeconds` | `20` | durée totale de l'intermission (bornée, > visibilité) |
| `macroTargetToken` | `"player"` | jeton de cible de la macro de ping |
| `position` | `CENTER` | position du panneau, sauvegardée au glisser-déposer |

## 7. Commandes et touche

```
/gr                       panneau principal (plan préparé hors jeu)
/gr plan                  plan détaillé dans le chat
/gr inter                 affiche/masque le panneau d'intermission
/gr inter start|stop      lance/arrête la timeline pré-calculée
/gr inter 1 | 2 | 3       déclare ce que tu vois (raccourci clavier utile)
/gr inter macro           affiche la macro de ping correspondante
/gr inter on | off        active/désactive le module
/gr inter status          état du module + timeline
```

Une **binding** `GIDEONRAID_INTERMISSION` (sans touche par défaut) est déclarée
dans `Bindings.xml` : à assigner dans *Options > Raccourcis > GideonRaid*.
Le corps de la binding est du Lua exécuté **insecurement** (voir
<https://warcraft.wiki.gg/wiki/Creating_key_bindings>) : il ouvre le panneau,
et ne peut pas — ne doit pas — envoyer de ping.

## 8. Tests hors jeu

```bash
busted                                    # 71 tests, dont 47 pour ce module
lua5.1 tools/intermission_cli.lua all     # convention + macros
lua5.1 tools/intermission_cli.lua pair 2 3
lua5.1 tools/intermission_cli.lua plan Velna
```

Couvert par `tests/spec/intermission_spec.lua` :

- la convention (orbes, positions, pings, consignes) et son déterminisme ;
- les collisions (`2+2`, `1+3` OK ; `2+3` = 5 verts ; `1+1`, `3+3`) ;
- la génération de macro, y compris l'absence de texte d'événement interdit ;
- la machine d'état : `IDLE → VISIBLE (3 s) → DARK → DONE`, déclaration avant
  démarrage / après la fin refusée, `reset`, `dt` négatif ignoré, déterminisme ;
- la timeline préparée (bornes, `durée > visibilité`) ;
- la vue pré-pull (partenaire, rôle, position, paires triées, plan malformé) ;
- la configuration (bornes, types incohérents, absence d'alias entre comptes).

Couvert par `tests/spec/load_spec.lua` (chargement réel, ordre du `.toc`) :
`ENCOUNTER_START` ouvre le panneau, le clic sur un bouton affiche la consigne,
le ticker bascule en salle obscurcie après 3 s, `ENCOUNTER_END` ferme le
panneau, la désactivation est respectée, le panneau n'affiche aucune valeur
dynamique.

## 9. À confirmer en jeu (liste honnête)

1. Syntaxe exacte de la macro de ping (appel `C_Ping.SendMacroPing` depuis une
   macro, sémantique de `targetToken = "player"`, jeton de la variante `/ping`).
2. Apparition de la binding `GIDEONRAID_INTERMISSION` dans *Options > Raccourcis*
   (fichier XML non testable hors client) et comportement `header`.
3. Lisibilité réelle du panneau pendant l'obscurcissement (taille, position par
   défaut) — non vérifiable hors client.
4. Durée exacte de l'intermission : `durationSeconds` est un défaut **à ajuster**
   après les premiers pulls.
5. Convention de guilde définitive (ping vs `/say` vs position) : le tableau du
   §2 est celui implémenté ; s'il change, changer `CONVENTION` dans
   `Core/Intermission.lua` (et les tests) — jamais l'UI.
