# GideonRaid — conventions de code (OBLIGATOIRES pour tout agent de code)

Ce fichier est normatif. Claude Code / Codex / OpenCode doivent le respecter
sans exception. Toute PR qui l'enfreint est refusée par `make check`.

---

## 1. Contexte technique à ne jamais perdre de vue (patch 12.1.0, live)

Sources vérifiées :

- `## Interface: 120100` — patch 12.1.0 « Curse of Ula'tek », sorti le 11/08/2026,
  Interface `.toc` = `120100` → <https://warcraft.wiki.gg/wiki/Patch_12.1.0>
- `## Interface: 120007` pour 12.0.7 — <https://warcraft.wiki.gg/wiki/Patch_12.0.7>
- Secret Values — <https://warcraft.wiki.gg/wiki/Secret_Values>
- API changes 12.0.0 — <https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes>

### 1.1 Les valeurs secrètes (Secret Values)

> « Combat API functions may now return secret values when called […] Tainted
> code is not allowed to perform arithmetic on secret values. Tainted code is
> not allowed to compare or perform boolean tests on secret values. »

Conséquences opérationnelles, à appliquer mécaniquement :

1. **INTERDIT** : lire une valeur d'unité et la tester/compter/calculer.
   `UnitHealth`, `UnitPower`, `UnitAura`, `UnitCastingInfo`, `GetTime` de combat,
   les `auraInstanceID`, l'état des cooldowns… peuvent renvoyer un secret.
   Un `if secretValue > 0 then` est une **erreur Lua immédiate**.
2. **AUTORISÉ** : stocker un secret dans une variable ou un champ de table, le
   passer à une fonction Lua, le concaténer dans une chaîne, le passer à un
   widget marqué comme acceptant les secrets (ex. `StatusBar:SetValue`).
3. Si le code doit savoir *si* une valeur est secrète, il utilise
   `issecretvalue(v)` / `canaccessvalue(v)` — il ne fait jamais semblant que
   non.

### 1.2 Interdictions supplémentaires

- **`COMBAT_LOG_EVENT` et `COMBAT_LOG_EVENT_UNFILTERED` sont interdits à
  l'enregistrement** : `frame:RegisterEvent("COMBAT_LOG_EVENT")` lève une
  erreur immédiate en 12.x. Aucun fichier de ce dépôt ne doit contenir ces
  chaînes.
- **Aucune communication addon → addon en instance** (messages vers un autre
  addon). Le canal d'échange avec GIDEON est hors instance / hors combat.
- **Aucun contournement** (« workaround » pour dé-secréter une valeur) : c'est
  interdit par Blizzard et c'est la cause n°1 de casse d'addon en 12.x.

### 1.3 Le canal officiel avec GIDEON

Le bot GIDEON n'est pas dans le client. Le seul canal fiable est :

```
GIDEON (hors jeu)  --écrit-->  WTF/Account/<COMPTE>/SavedVariables/GideonRaid.lua
                                    |
                              joueur /reload ou relance le client
                                    |
                              l'addon LIT GideonRaidDB.assignment
```

Ces données sont **des chaînes de caractères écrites hors jeu : jamais des
valeurs secrètes.** C'est ce qui rend tout le projet faisable.

---

## 2. Architecture : deux couches, une frontière infranchissable

```
Core/      LOGIQUE PURE. Zéro API WoW. 100 % testable avec busted, hors jeu.
UI/        RENDU. Peut appeler l'API WoW. Zéro calcul métier.
GideonRaid.lua  Câblage : événements, slash commands. Dépend des deux.
```

### Règles

1. Un fichier de `Core/` **ne doit jamais** référencer un symbole de l'API WoW
   (`CreateFrame`, `UnitName`, `C_*`, `_G.GideonRaidDB`, `DEFAULT_CHAT_FRAME`…).
   Corollaire direct : il n'y a rien à mocker pour le tester.
2. Un fichier de `UI/` **ne contient aucun calcul**. Il reçoit des valeurs déjà
   calculées par `ns.Pairing` / `ns.Config` et les affiche.
3. Toute donnée qui vient du client (nom de joueur, roster) entre dans `Core/`
   **déjà convertie en chaîne ou en nombre** par le câblage.
4. Si un besoin semble obliger `Core/` à appeler l'API : le besoin est mal
   découpé. Extraire le calcul et passer le résultat en paramètre.

---

## 3. Structure du dépôt (imposée)

```
GideonRaid/                      <- RACINE DU DEPOT = RACINE DE L'ADDON
├── GideonRaid.toc               <- nom du fichier == dossier d'install == package-as
├── GideonRaid.lua               <- point d'entrée (événements, slash)
├── Bindings.xml                 <- binding(s) du panneau d'intermission. Chargé
│                                   AUTOMATIQUEMENT par le client : JAMAIS listé
│                                   dans le .toc (voir §10)
├── Core/
│   ├── Config.lua               <- defaults + SavedVariables
│   ├── Pairing.lua              <- moteur d'appariement (PUR)
│   └── Intermission.lua         <- Intermission Coach (PUR)
├── UI/
│   ├── Panel.lua                <- rendu
│   └── Intermission.lua         <- rendu du panneau d'intermission
├── libs/                        <- libs embarquées (externals), jamais éditées
├── tests/
│   ├── spec/*_spec.lua          <- busted
│   ├── fixtures/                <- blocs SavedVariables de référence (contrat)
│   └── support/                 <- harnais (wowenv, stub API)
├── tools/                       <- scripts hors addon (exclus du zip)
├── docs/
├── .pkgmeta  .luacheckrc  .busted  stylua.toml  Makefile
└── .github/workflows/{ci,release}.yml
```

**Le client WoW exige que la racine du dépôt soit la racine de l'addon** : c'est
aussi ce qu'exige le BigWigs packager (`release.sh` cherche `*.toc` dans
`$topdir`, ligne 1389 de release.sh). Ne jamais réintroduire un sous-dossier
contenant le `.toc`.

Chaque fichier `.lua` doit être listé dans le `.toc`, dans l'ordre de
dépendance. Le séparateur est `\` (backslash), **jamais** `/`.

---

## 4. Conventions de nommage

| Élément | Convention | Exemple |
|---|---|---|
| Dossier / TOC / package | PascalCase, identique partout | `GideonRaid` |
| Fichier Lua | PascalCase pour les modules | `Core/Pairing.lua` |
| Specs | `snake_case` + `_spec.lua` | `pairing_spec.lua` |
| Table de module | Même nom que le fichier | `local Pairing = {}` |
| Exposée dans le namespace | `ns.Pairing` | `ns.UI.Refresh()` |
| Fonction publique | `camelCase` | `Pairing.buildPairs` |
| Fonction locale | `camelCase` en `local function` | `local function sortedCopy` |
| Constante | `UPPER_SNAKE` | `Pairing.SCHEMA_VERSION` |
| Variables `Sav..` | `<Addon>DB`, `<Addon>CharDB` | `GideonRaidDB` |
| Fichier global créé | préfixé | `GideonRaidPanel` |

En-tête de fichier **obligatoire** (voir les modèles existants) :

```lua
local _, ns = ...
```

- `local _, ns = ...` quand le nom de l'addon n'est pas utilisé (`_` n'est pas
  signalé par luacheck ; `local addonName, ns = ...` l'est → warning 212).
- **Jamais** de variable globale implicite. Toute globale doit être déclarée
  dans `.luacheckrc` *et* justifiée en commentaire.

---

## 5. Commentaires obligatoires quand une API est restreinte

Dès qu'une ligne touche une API contrainte en 12.x, elle est précédée d'un
commentaire citant **la source**, au format :

```lua
-- Ref API 12.1.0 : <https://warcraft.wiki.gg/wiki/...>
-- Contrainte : <ce qui est interdit et pourquoi>
-- <la ligne de code>
```

Exemple réel (dans `Core/Pairing.lua`) :

```lua
-- Ref API 12.x : https://warcraft.wiki.gg/wiki/Secret_Values
-- Source contrainte : "Tainted code is not allowed to compare or perform
-- boolean tests on secret values."
-- => on ne traite QUE des chaînes fournies par le joueur ou par GIDEON.
```

Règles associées :

- Un commentaire qui cite une API **doit** contenir l'URL de la page wiki
  correspondante. Pas d'URL inventée : si elle n'a pas été vérifiée, écrire
  `-- A VERIFIER:` et ne pas coder l'appel.
- **Jamais de logique métier dépendante d'une valeur secrète.** Si un
  comportement de l'addon change selon une valeur potentiellement secrète, il
  est refusé en review. La donnée doit venir de `GideonRaidDB` ou d'une saisie
  du joueur.
- Au moindre doute : `-- SECRET?` en tête de fonction, et la fonction est
  interdite d'accès depuis `UI/Refresh`.

---

## 6. Style : automatisé, pas négociable

- `stylua.toml` : 4 espaces, 140 colonnes, guillemets doubles.
  **`stylua --check .` doit passer.** Ne jamais formatter à la main.
- `luacheck .` doit afficher `0 warnings / 0 errors`.
- `std = "lua51"` : le client WoW tourne sur **PUC-Rio Lua 5.1**. Donc :
  - pas de `goto`, pas d'opérateur `//`, pas d'entiers natifs, pas de `\u{}` ;
  - `table.unpack` n'existe pas → `unpack` ;
  - `#` sur une table à trous est interdit (`#` n'est défini que pour les
    séquences sans trou).
- Commentaires et identifiants en **ASCII** pour le code Lua (les fichiers
  `.md` peuvent être accentués).

---

## 7. Déterminisme (règle de test, pas de style)

- Aucun tri par ordre d'entrée : toujours trier **par nom** ou par clé
  explicite. Le même roster doit produire le même résultat quel que soit
  l'ordre reçu de GIDEON. (Voir le test « est insensible a l'ordre d'entree ».)
- Aucun `pairs()` dans un chemin qui influence le résultat : `pairs()` n'a pas
  d'ordre garanti. Utiliser une liste triée.
- Aucun `math.random`, aucune dépendance à l'heure, aucun `GetTime()` dans
  `Core/`.

---

## 8. Définition de « terminé » pour une tâche

Une tâche n'est terminée que si, **et seulement si** :

1. `make check` sort en code 0 (stylua + luacheck + toc + busted) ;
2. un test de `tests/spec/` couvre le nouveau comportement (et échoue avant le
   correctif — vérifier réellement le rouge puis le vert) ;
3. le nouveau fichier est listé dans `GideonRaid.toc` s'il doit être chargé ;
4. aucune chaîne `COMBAT_LOG_EVENT`, aucun appel à une API de combat sans
   commentaire de source, aucune logique sur une valeur secrète ;
5. `bash release.sh -t .` produit un zip sans erreur (à lancer si `.pkgmeta`
   ou le `.toc` a changé).

---

## 9. Ce qu'un agent ne doit JAMAIS faire

- Ajouter une dépendance externe (lib, package Lua) sans le déclarer dans
  `.pkgmeta` (`externals`) — sinon le zip packagé est cassé.
- Modifier `libs/` à la main.
- Pousser un tag `v*` : le tag déclenche la release (workflow `Release`).
- Introduire un workflow qui a besoin d'un secret non configuré.
- Éditer `.release/` (artefact, gitignoré).
- « Réparer » un token malformé (nom d'addon, numéro d'Interface, ID de projet
  CurseForge) : si une valeur ne respecte pas le format attendu, s'arrêter et
  demander.

---

## 10. Règles spécifiques au module « Intermission Coach »

1. **Aucun automatisme revendiqué.** Tout ce que l'addon affiche vient soit d'un
   clic du joueur, soit d'un bloc préparé hors jeu. Interdiction d'écrire dans
   l'UI, la doc ou un message de commit qu'une action est « automatique »
   lorsqu'elle dépend d'une déclaration du joueur.
2. **Aucun ping envoyé par l'addon.** `C_Ping.SendMacroPing` est `#protected` —
   <https://warcraft.wiki.gg/wiki/API:C_Ping.SendMacroPing> : l'addon **génère le
   texte d'une macro**, le joueur la déclenche. Le corps d'une `Bindings.xml` est
   exécuté *insecurely* (<https://warcraft.wiki.gg/wiki/Creating_key_bindings>) :
   il ne peut pas non plus appeler cette fonction.
3. **`Bindings.xml` n'est JAMAIS listé dans le `.toc`** : le client le charge
   automatiquement. `tools/check_toc.py` continue de ne vérifier que les `.lua`
   du `.toc`.
4. **Aucune valeur d'API de combat dans le module** : ni aura, ni santé, ni
   ressource, ni cible. Seuls entrent le nom de sa propre unité
   (`UnitName("player")`) et les chaînes de `GideonRaidDB`.
5. **Le temps est injecté.** `Core/Intermission.tick(state, dt)` reçoit un pas de
   temps constant fourni par le câblage : aucun `GetTime()` dans `Core/`.
6. **L'UI dit ce qui est impossible.** Le panneau affiche explicitement que
   « qui a déclaré quoi » est inconnu et que le ping est le seul signal visible
   par les autres joueurs.
