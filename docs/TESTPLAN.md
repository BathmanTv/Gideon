# Plan de test — GideonRaid (4 étapes)

Principe directeur : **on teste hors jeu tout ce qui peut l'être**, parce qu'en
12.x, en combat, l'addon ne *peut pas* lire les valeurs qui l'intéressent (Secret
Values) et ne peut pas s'échanger de messages en instance. Ce qui reste
vérifiable en jeu est réduit au rendu et au câblage. Le plan est construit pour
que 90 % du risque soit éliminé avant d'ouvrir le client.

| Étape | Objet | Outil | Fréquence | Où |
|---|---|---|---|---|
| 1 | Logique d'appariement (pure) | busted + lua5.1 | à chaque commit | CI + local |
| 2 | Chargement de l'addon (câblage, .toc) | busted + stub API | à chaque commit | CI + local |
| 3 | Rendu et ergonomie en jeu | client de test | avant chaque patch | client WoW |
| 4 | Intégration GIDEON bout en bout | CLI Lua + Discord | avant chaque raid | VPS + Discord |

Porte de sortie unique : **`make check`** (stylua + luacheck + toc + busted).

---

## Étape 1 — Tests unitaires hors jeu de la logique d'appariement

**Objectif** : le moteur `ns.Pairing` est du Lua 5.1 pur, sans aucun appel à
l'API WoW. Il est donc exécutable par `lua5.1` et par `busted`, installés sur le
VPS et sur le runner GitHub.

**Fichier** : `tests/spec/pairing_spec.lua` (17 assertions = 17 tests au total
avec `load_spec.lua`).

**Lancement** :

```bash
cd GideonRaid && busted
```

### Jeu de données de référence (« fixtures »)

Roster de 20 joueurs, 10 `ember` / 10 `frost`, fourni par GIDEON :

```
Velna,ember      Bathman,frost    Kaela,ember     Ordan,frost     Sylvia,ember
Torgh,frost      Mira,ember      Nyx,frost       Rukh,ember      Dorian,frost
Ilya,ember       Pax,frost       Zerun,ember     Halda,frost     Coren,ember
Aster,frost      Bren,ember      Lumen,frost     Serka,ember     Vaelen,frost
```

Fichier : `tools/sample_roster.csv`.

### Résultat attendu (vérifié, sortie réelle)

```
$ lua5.1 tools/pairing_cli.lua < tools/sample_roster.csv
Bren|Aster
Coren|Bathman
Ilya|Dorian
Kaela|Halda
Mira|Lumen
Rukh|Nyx
Serka|Ordan
Sylvia|Pax
Velna|Torgh
Zerun|Vaelen
```

10 paires, 0 non-apparié, exit code 0. L'appariement est **alphabétique**
(Alice-Bob, puis Yann-Zoe…) : c'est ce qui garantit que le même roster produit
exactement le même résultat, sur le client comme dans GIDEON.

### Cas de test obligatoires (tous présents dans `pairing_spec.lua`)

| Cas | Entrée | Attendu |
|---|---|---|
| nominal 3+3 | Tank1/Tank2/Dps1 ember, Heal1/Heal2/Dps2 frost | 3 paires alignées par nom |
| déterminisme | même roster, ordre inversé | résultats identiques |
| normalisation | `"  Ember "`, `"FROST"` | appariés |
| surnuméraires | 3 ember, 1 frost | 1 paire + 2 `unpaired` `no_partner:frost` |
| debuff manquant | joueur sans `debuff` | `unpaired` `missing_debuff` |
| debuff inconnu | `poison` | `unpaired` `unknown_debuff:poison` |
| entrée invalide | `"pas une table"` | `nil, err` (pas de crash) |
| doublon | deux joueurs `A` | `nil, err` |
| `findPartner` | bilatéral + inconnu | `"B"`, `"A"`, `nil` |
| `validateAssignment` | bloc GIDEON valide / malformé | filtré / rejeté |

**Critère de passage** : `17 successes / 0 failures / 0 errors`.

---

## Étape 2 — Tests de chargement de l'addon

**Objectif** : prouver que l'addon se charge dans l'ordre du `.toc`, que les
événements ne lèvent pas, et que le rendu lit bien `GideonRaidDB`. On ne mocke
**que** les frames (`tests/support/wowapi_stub.lua`, ~60 lignes) : aucune API de
combat n'est mockée, car aucun fichier n'en appelle.

**Fichier** : `tests/spec/load_spec.lua`.

Ce qui est vérifié :

1. les 4 couches (`ns.Pairing`, `ns.Config`, `ns.UI`, `ns.GR`) sont exposées ;
2. `ADDON_LOADED` sur `GideonRaid` initialise `GideonRaidDB` avec les defaults ;
3. `ADDON_LOADED` sur un **autre** addon ne touche pas aux SavedVariables ;
4. `PLAYER_LOGIN` sans assignation ne lève pas ;
5. `PLAYER_LOGIN` **avec** assignation affiche le bon partenaire dans le panneau ;
6. le slash handler (`/gr show`, `/gr status`, commande inconnue) répond sans
   lever.

**Vérification du `.toc`** (`tools/check_toc.py`, en CI) :

```
$ python3 tools/check_toc.py GideonRaid.toc
OK GideonRaid.toc
  Interface  : 120100
  Version    : @project-version@
  SavedVar   : GideonRaidDB
  Fichiers   : 4
```

Il vérifie : nom du `.toc` == `package-as`, `## Interface:` numérique et
≥ 120100, présence de `Title/Notes/Version`, et **existence sur disque de chaque
fichier listé** (c'est le bug n°1 des addons : un fichier listé mais absent, ou
un `/` au lieu d'un `\`).

**Vérification syntaxique Lua 5.1** (le runtime réel du client) :

```
$ make syntax
OK ./GideonRaid.lua
OK ./UI/Panel.lua
OK ./Core/Config.lua
OK ./Core/Pairing.lua
OK ./tests/support/wowapi_stub.lua
OK ./tests/support/wowenv.lua
OK ./tests/spec/load_spec.lua
OK ./tests/spec/pairing_spec.lua
OK ./tools/pairing_cli.lua
```

**Critère de passage** : étape 1 + étape 2 vertes, `luacheck .` = 0 warning.

### Tests de chargement en profondeur (optionnel, si besoin plus tard)

Deux harnais existent et sont réels (vérifiés le 22/09/2026) :

| Harnais | Nature | Usage | Contrainte VPS |
|---|---|---|---|
| [Osso/wow-ui-sim](https://github.com/Osso/wow-ui-sim) | Simulateur d'UI WoW, headless, tags jusqu'à `12.0.5` | `run-tests` d'un addon, screenshots de frame-tree, assertions `assertTableEquals`, tests async via `C_Timer.After` | Nécessite **docker**, dont le démon n'est **pas démarré** sur ce VPS → à utiliser **en GitHub Actions** (`uses: osso/wow-ui-sim@12.0.5`) |
| [wowless/wowless](https://github.com/wowless/wowless) | Interpréteur Lua + FrameXML headless | Chargement du vrai code client | **Pre-alpha** (« les erreurs sont presque sûrement dans Wowless, pas dans votre addon »), build CMake/vcpkg lourd → non retenu |

Décision : `wow-ui-sim` est le bon candidat pour automatiser l'étape 3 **quand**
le besoin se présentera (par ex. vérifier que le panneau s'affiche). Il n'est pas
activé dans la CI par défaut pour ne pas dépendre d'un composant GPL-3 qui
change vite en pleine transition 12.x.

---

## Étape 3 — Tests manuels en jeu (protocole)

**Prérequis** : client Midnight 12.1.0 (Interface `120100`), addon installé dans
`Interface/AddOns/GideonRaid/`, `GideonRaidDB.assignment` peuplé par GIDEON.

### 3.0 Pré-vol : aucune valeur secrète

- Cocher « Afficher les erreurs Lua » et **jouer 10 minutes de raid réel**.
  Aucune erreur `attempt to compare a secret value`, aucune erreur
  `COMBAT_LOG_EVENT` (cette seconde erreur signifie qu'un événement interdit est
  enregistré → régression bloquante).
- Commande console : `/console scriptErrors 1`.

### 3.1 Hors combat, hors instance — chargement (2 min)

1. Écrire à la main `WTF/Account/<COMPTE>/SavedVariables/GideonRaid.lua` avec un
   bloc `assignment` de test (2 paires dont une contenant le personnage).
2. `/reload` → `/gr` → vérifier : « Ton partenaire : <Nom> » + la liste des
   paires.
3. `/gr status` → « assignation OK, 2 paires ».
4. `/gr reset` → puis `/reload` → le panneau affiche « Aucune assignation
   GIDEON. » sans erreur.

### 3.2 Hors combat, dans l'instance — lecture en raid

5. Sur un boss de raid **avant le pull** : `/gr` doit afficher exactement les
   mêmes paires qu'hors instance. *Test critique* : c'est là que l'on prouve que
   l'addon ne dépend d'aucun canal interdit en instance.
6. Pendant l'intermission : vérifier que le panneau reste lisible et **n'affiche
   aucune valeur dynamique** (santé, aura). S'il en affiche une, c'est une
   régression de conception → étape 1 échouée.

### 3.3 Robustesse

7. Roster volontairement incomplet (un partenaire a `quit`) : la paire doit
   apparaître telle quelle **sans** décalage — l'addon n'a pas à recalculer.
8. `/gr` tapé 20 fois : aucune frame dupliquée, aucun ralentissement.
9. Déplacer le panneau (drag), `/reload`, vérifier la position conservée.
10. Tester avec un second personnage (autre `SavedVariablesPerCharacter`) : pas
    de fuite de données entre personnages.

### 3.4 Ce qui n'est PAS testable en jeu (à documenter dans le rapport)

- On ne teste pas l'*affichage correct de l'aura* de l'autre joueur : le client
  ne nous la donne pas.
- On ne teste pas la synchronisation « en direct » : aucun canal addon→addon en
  instance. La synchronisation est asynchrone **par conception** (GIDEON →
  file → `/reload`).

### 3.5 Environnement de test recommandé

Un seul joueur « cobaye » suffit : l'essentiel (lecture de `GideonRaidDB`,
rendu) ne dépend d'aucun autre joueur. Les tests à 2+ joueurs seraient
nécessaires seulement pour un canal de communication, qui n'existe pas. **C'est
un argument fort pour ne pas investir dans un client de test lourd.**

---

## Étape 4 — Tests d'intégration avec GIDEON

**Objectif** : garantir que le contrat de données GIDEON ↔ addon ne dérive pas.

### 4.1 Contrat de données (schéma figé, versionné)

`GideonRaidDB.assignment` (écrit par GIDEON, lu par l'addon) :

```lua
GideonRaidDB = {
    schema = 1,
    assignment = {
        schema = 1,
        pairs = {
            { a = "Velna",  b = "Torgh" },
            { a = "Bathman", b = "Coren" },
            -- ...
        },
    },
}
```

- `schema` est **obligatoire** : si GIDEON passe à 2 et que l'addon est en 1,
  l'addon doit refuser le bloc (aujourd'hui `validateAssignment` l'accepte et le
  normalise → à durcir quand le schéma changera).
- L'ordre des paires est alphabétique. C'est ce qui rend le contrat comparable
  par diff (`diff` des deux sorties).

### 4.2 Non-régression du contrat (test automatique, hors jeu)

GIDEON génère le fichier via le moteur Lua **partagé** :

```bash
# GIDEON : produit les paires à partir du roster
lua5.1 tools/pairing_cli.lua < /tmp/roster_du_soir.csv
# -> Velna|Torgh .... exit 0
```

Test à ajouter quand GIDEON est branché : un test de `tests/spec/` qui prend un
exemple de fichier `SavedVariables` de référence (fixture) et vérifie que
`Pairing.validateAssignment` accepte **exactement** ce que GIDEON écrit. C'est
un test de contrat, pas un test d'implémentation : il doit casser *si et
seulement si* le format change.

### 4.3 Round-trip manuel (10 min, avant le premier raid)

| # | Action | Attendu |
|---|---|---|
| 1 | Commande Discord `!g roster assign` sur le roster réel | GIDEON répond avec la liste des paires |
| 2 | Vérifier `WTF/.../SavedVariables/GideonRaid.lua` sur le VPS de test | `pairs` identiques à la réponse Discord, `schema = 1` |
| 3 | `/reload` en jeu | panneau identique à la réponse Discord |
| 4 | Couper GIDEON, `/reload` | l'addon fonctionne toujours (données déjà en cache) |
| 5 | Roster avec un seul `frost` et 3 `ember` | GIDEON alerte (`NON-APPARIE: ... no_partner:frost` sur stderr) **et** l'addon affiche la même chose |

### 4.4 Test de dégradation

GIDEON écrit un bloc malformé (`pairs = {{a=1,b="B"}}`) : l'addon doit afficher
« Aucune assignation GIDEON. (paire #1 invalide) » et **ne rien planter**. C'est
déjà couvert à l'étape 1 et 2.

---

## Matrice de couverture (ce qui prouve quoi)

| Risque | Étape qui le couvre | Preuve |
|---|---|---|
| Mauvais appariement | 1 | 17 tests, dataset de 20 joueurs |
| Résultat non déterministe | 1 | test « insensible à l'ordre d'entrée » |
| Fichier oublié dans le `.toc` | 2 | `check_toc.py` |
| Erreur de syntaxe Lua 5.1 | 2 | `make syntax` |
| Crash au login / mauvais événement | 2 | `load_spec.lua` |
| Panneau illisible en raid | 3 | protocole manuel §3.2 |
| Erreur secret value en combat | 3 | §3.0 + revue de code (conventions §1) |
| Dérive du format GIDEON | 4 | test de contrat + round-trip |
| Version d'Interface obsolète | 2 | `check_toc.py` (seuil 120100) |
