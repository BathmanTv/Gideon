# Intermission Coach — Entombed Sentinels (mythique)

Module « Intermission Coach » de GideonRaid : il rend la **coordination de
l'intermission des Entombed Sentinels** (raid *The Venomous Abyss*, Midnight
12.1.0) possible et rapide **avec une action minimale du joueur**, sans jamais
lire une API de combat.

Guide de référence :
<https://raidstrats.gg/guides/entombed-sentinels/mythic/phase/quick-overview>

---

## 1. La mécanique, telle qu'elle est implémentée

- Pendant l'intermission, **chaque joueur voit un NUMÉRO au-dessus de sa tête**,
  mais **le numéro ne détermine PAS les couleurs** :
  - « **2** » = **toujours 2 verts + 2 rouges** (`2V2R`) — le seul cas non ambigu ;
  - « **1** » ou « **3** » = soit **3 verts + 1 rouge** (`3V1R`), soit **1 vert +
    3 rouges** (`1V3R`) : c'est la **COULEUR des orbes** qui tranche, jamais le
    numéro.
  Il n'existe donc que **trois états réels** : `3V1R`, `2V2R`, `1V3R`.
- **Règle de survie = addition de couleurs** : la somme des deux joueurs doit
  faire **4 verts ET 4 rouges** (4V4R) :
  - `3V1R + 1V3R` = 4V4R → **sûr** ;
  - `2V2R + 2V2R` = 4V4R → **sûr** ;
  - toute autre combinaison tue ; `3V1R + 2V2R` = **5 verts** = le « **5g** » du
    guide ; `1V3R + 1V3R` = 2 verts + 6 rouges = mort aussi.
- Environ **3 s** après le début, le boss obscurcit la salle : chaque joueur ne
  voit plus que **ses propres orbes** (son numéro seul ne suffit pas).

> **Correction assumée.** Le modèle précédent liait `1 ↔ 1 vert + 3 rouges` et
> `3 ↔ 3 verts + 1 rouge`, avec une position et un ping déduits du numéro :
> c'était **faux** (les numéros 1 et 3 sont ambigus). Le module demande
> désormais **la composition réellement vue** ; une déclaration réduite à
> « 1 » ou « 3 » est **refusée** avec un message demandant la couleur dominante —
> le code ne devine jamais.

## 2. Les trois états (convention explicite et configurable)

Table `CONVENTION` de `Core/Intermission.lua` (source unique de vérité) :

| État | Composition | Numéro(s) possible(s) | Position | Ping | Couleur | Doit être rejoint par |
|---|---|---|---|---|---|---|
| `1V3R` | 1 vert + 3 rouges | **1 ou 3** (ambigu) | **SUR PLACE**, là où tu es | `Enum.PingSubjectType.Warning` | **ROUGE** | `3V1R` |
| `2V2R` | 2 verts + 2 rouges | **2** (non ambigu) | **MILIEU / sous le boss** | `Enum.PingSubjectType.OnMyWay` | **BLEU** | `2V2R` |
| `3V1R` | 3 verts + 1 rouge | **1 ou 3** (ambigu) | **va te coller à un `1V3R`** | `Enum.PingSubjectType.Assist` | **VERT** | `1V3R` |

Chaque état porte aussi : le libellé visuel (« 3 VERTS + 1 ROUGE »), le nombre de
verts et de rouges (base du calcul de survie), la consigne opérationnelle, le
texte du bouton (numéro en indice) et la règle de guilde rappelée pour ce numéro.

**Ping** : convention du guide raidstrats, **par couleur dominante** — 3 verts →
`Assist` (vert), 2-2 → `OnMyWay` (bleu), 3 rouges → `Warning` (rouge). Ces
couleurs sont vérifiées sur la galerie du wiki
(<https://warcraft.wiki.gg/wiki/Ping_System>) : `Warning` = panneau rouge,
`OnMyWay` = flèche bleue, `Assist` = drapeau vert.

**Positions** : les lignes **positionnelles** du guide raidstrats se
**contredisent** (elles donnent à la fois « 1 vert 3 rouges → gauche » et
« 3 rouges 1 vert → droite »). Notre convention est donc **explicite et
configurable**, et c'est la seule cohérente avec « la couleur tranche » : le
point **fixe** est l'état à majorité **rouge** (`1V3R`, ping ROUGE), le
**coureur** est l'état à majorité **verte** (`3V1R`, ping VERT), les `2V2R`
vont au milieu. Convention de guilde par défaut, rappelée à l'écran pour chaque
état : **« 2 » → milieu / sous le boss ; « 1 » → sur place + ping ; « 3 » →
rejoint un « 1 » de couleur complémentaire**. Si la guilde change de convention,
on modifie `CONVENTION` (et les tests) — jamais l'UI.

## 3. Ce que l'addon fait / ne peut PAS faire (à dire tel quel aux joueurs)

**Il peut :**

- afficher le plan préparé hors jeu (partenaire, rôle, position, paires) ;
- afficher un rappel en très gros de la convention au déclenchement ;
- afficher 3 boutons nommés par la **composition visible** — `1 vert + 3 rouges`,
  `2 verts + 2 rouges`, `3 verts + 1 rouge` — avec le **numéro en indice**
  (« 1 ou 3 », « 2 ») : le joueur clique la composition, et **la consigne
  correspondante apparaît immédiatement** (ce que tu as, ce que tu dois faire,
  quel état rejoindre, le ping, et le rappel que « 1 » ou « 3 » seul ne suffit
  pas) ;
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
        -- OPTIONNEL : plan préparé hors jeu (rôle / position par joueur).
        -- `role` = COMPOSITION D'ORBES (« 3V1R », « 2V2R », « 1V3R », « 3 verts »),
        -- jamais un numéro seul 1/3 (ambigu).
        plan = {
            { name = "Velna",   role = "2V2R", position = "MIDDLE" },
            { name = "Torgh",   role = "2V2R", position = "MIDDLE" },
            { name = "Bathman", role = "1V3R", position = "HOLD"   },
            { name = "Coren",   role = "3V1R", position = "PURSUE" },
        },
    },
}
```

- `plan` est **facultatif** : sans lui, l'addon affiche seulement le partenaire
  et la liste des paires.
- `role` accepte la **composition d'orbes** (`"1V3R"`, `"2V2R"`, `"3V1R"`, ou une
  forme tolérée comme `"3 verts"`) **ou** un rôle de raid libre (`"Tank"`,
  `"Heal"`) — dans ce dernier cas l'addon n'en déduit aucune rencontre. Un
  numéro seul `"1"` ou `"3"` est **ambigu** : l'addon l'écrit
  (`Rencontre non verifiable : numero 1 ambigu…`) au lieu de le deviner.
- Si les deux rôles d'une paire sont des compositions, l'addon affiche
  `Rencontre 2V2R+2V2R : OK (combinaison sure (4 verts + 4 rouges))` ou
  `Rencontre 3V1R+2V2R : MORT (5 verts = 5g : MORT)` : c'est un **contrôle du
  plan préparé**, pas une lecture en jeu.
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
/gr inter 3V1R            déclare ta COMPOSITION (aussi : 2V2R, 1V3R, « 3 verts »)
/gr inter 2               seul le « 2 » est accepté comme numéro (non ambigu)
/gr inter macro           affiche la macro de ping correspondante
/gr inter on | off        active/désactive le module
/gr inter status          état du module + timeline
```

`/gr inter 1` ou `/gr inter 3` sont **refusés** avec un message demandant la
couleur dominante : le module ne devine jamais la composition à partir du numéro.

Une **binding** `GIDEONRAID_INTERMISSION` (sans touche par défaut) est déclarée
dans `Bindings.xml` : à assigner dans *Options > Raccourcis > GideonRaid*.
Le corps de la binding est du Lua exécuté **insecurement** (voir
<https://warcraft.wiki.gg/wiki/Creating_key_bindings>) : il ouvre le panneau,
et ne peut pas — ne doit pas — envoyer de ping.

## 8. Tests hors jeu

```bash
busted                                    # 88 tests, dont 59 pour ce module
lua5.1 tools/intermission_cli.lua all     # les 3 états + macros
lua5.1 tools/intermission_cli.lua 3V1R    # un état
lua5.1 tools/intermission_cli.lua 1       # -> REFUS : numéro ambigu
lua5.1 tools/intermission_cli.lua pair 3V1R 2V2R    # -> MORT (5 verts)
lua5.1 tools/intermission_cli.lua plan Velna
```

Couvert par `tests/spec/intermission_spec.lua` :

- les trois états de couleur (libellé, verts/rouges, numéros possibles, ping,
  complément, consigne) et leur ordre déterministe ;
- la normalisation tolérante (`3V1R`, `2v2r`, `1 V 3 R`, `vert-vert-vert-rouge`,
  `vvrr`, `3 verts`, `1 vert 3 rouges`, « vert » = dominante), et le **refus
  explicite** de « 1 » ou « 3 » seuls (message « ambigu », jamais de devinette) ;
- les collisions par addition de couleurs : `3V1R+1V3R` sûr, `2V2R+2V2R` sûr,
  `3V1R+2V2R` interdit (5 verts), `1V3R+1V3R` et `3V1R+3V1R` interdits ;
- la génération de macro (par couleur dominante), l'absence de texte d'événement
  interdit, et le refus de fabriquer une macro sur un numéro ambigu ;
- la machine d'état : `IDLE → VISIBLE (3 s) → DARK → DONE`, déclaration avant
  démarrage / après la fin refusée, `reset`, `dt` négatif ignoré, déterminisme ;
- la timeline préparée (bornes, `durée > visibilité`) ;
- la vue pré-pull (partenaire, rôle, position, paires triées, plan malformé,
  rencontre sûre / mortelle / **non vérifiable** quand un rôle reste ambigu) ;
- la configuration (bornes, types incohérents, absence d'alias entre comptes).

Couvert par `tests/spec/load_spec.lua` (chargement réel, ordre du `.toc`) :
`ENCOUNTER_START` ouvre le panneau, les trois boutons portent la composition et
le numéro en indice, le clic sur un bouton affiche la consigne, le ticker bascule
en salle obscurcie après 3 s, `ENCOUNTER_END` ferme le panneau, la désactivation
est respectée, le panneau n'affiche aucune valeur dynamique.

Couvert par `tests/spec/guard_spec.lua` (garde anti-API-interdite) : aucun
fichier listé dans le `.toc` ne contient `COMBAT_LOG_EVENT`, `UnitAura`,
`UnitBuff`, `UnitDebuff`, `UnitGUID`, `SendChatMessage`, `GetRaidRosterInfo`,
`C_VoiceChat` hors commentaire ; `C_Ping` / `SendMacroPing` n'apparaissent
**jamais comme appel** (seulement dans le **texte** de la macro, qui est du code
sécurisé déclenché par le joueur) ; `Core/` reste sans `GetTime`,
`math.random`, `CreateFrame`, `UnitName` ni `GideonRaidDB`.

## 9. À confirmer en jeu (liste honnête)

1. Syntaxe exacte de la macro de ping (appel `C_Ping.SendMacroPing` depuis une
   macro, sémantique de `targetToken = "player"`, jeton de la variante `/ping`).
2. Apparition de la binding `GIDEONRAID_INTERMISSION` dans *Options > Raccourcis*
   (fichier XML non testable hors client) et comportement `header`.
3. Lisibilité réelle du panneau pendant l'obscurcissement (taille, position par
   défaut) — non vérifiable hors client.
4. Durée exacte de l'intermission : `durationSeconds` est un défaut **à ajuster**
   après les premiers pulls.
5. Convention de guilde définitive (position, ping vs `/say`) : le tableau du
   §2 et la table `CONVENTION` de `Core/Intermission.lua` sont la source unique ;
   s'ils changent, changer `CONVENTION` (et les tests) — jamais l'UI. Les lignes
   positionnelles du guide raidstrats se contredisant, notre choix (rouge =
   point fixe, vert = coureur, 2-2 = milieu) est explicite et révisable.
6. Lien entre le **numéro affiché** et la **marque** (Mark of Acid / Mark of
   Blood) : mesuré en jeu par le kit de diagnostic `GideonDiagAddon`
   (`/gdiagmark`), qui note désormais **numéro + composition** par intermission.
