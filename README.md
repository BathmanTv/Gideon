# GideonRaid

Addon de guilde (World of Warcraft : Midnight, `## Interface: 120100`) qui aide à
la mécanique d'**appariement de joueurs portant des debuffs complémentaires**
pendant une intermission de raid, avec le bot Discord **GIDEON** comme source
d'assignation.

---

## 1. Pourquoi l'architecture est « bizarre » (et pourquoi elle est obligatoire)

En 12.x, un addon **ne peut plus** faire ce qu'un addon de raid faisait avant :

| Avant 12.0 | Depuis 12.0 |
|---|---|
| Lire l'aura des autres (`UnitAura`) et décider | La valeur peut être **secrète** : `if aura > 0` = **erreur Lua immédiate** |
| Écouter `COMBAT_LOG_EVENT` | **Enregistrer l'événement lève une erreur** |
| S'échanger des messages addon→addon en instance | **Plus de canal** |
| Contourner les restrictions | Interdit par Blizzard, casse à chaque patch |

Donc l'appariement **ne peut pas** être calculé dans le client en combat. Il est
calculé **hors jeu par GIDEON**, écrit dans les SavedVariables, et l'addon se
contente de **lire et d'afficher** :

```
GIDEON (VPS, hors jeu)
  roster Discord  →  lua5.1 tools/pairing_cli.lua  →  paires
                                |
                                v
  WTF/Account/<COMPTE>/SavedVariables/GideonRaid.lua   (chaînes, jamais secrètes)
                                |
                          joueur /reload
                                v
                     GideonRaid affiche les paires
```

Sources : [Secret Values](https://warcraft.wiki.gg/wiki/Secret_Values) ·
[API changes 12.0.0](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes) ·
[Patch 12.1.0](https://warcraft.wiki.gg/wiki/Patch_12.1.0).

---

## 2. Le moteur d'appariement est partagé

`Core/Pairing.lua` est du **Lua 5.1 pur** : le même fichier tourne dans le client
WoW et sur le VPS. C'est ce qui garantit que GIDEON et l'addon calculent
*toujours* la même chose.

```bash
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

Résultat **déterministe** (tri alphabétique) : le même roster donne toujours le
même résultat, donc comparable par `diff`.

---

## 3. Structure

```
GideonRaid/            <- RACINE DU DEPOT = RACINE DE L'ADDON (obligatoire)
├── GideonRaid.toc
├── GideonRaid.lua     <- câblage : ADDON_LOADED, PLAYER_LOGIN, /gr
├── Core/              <- LOGIQUE PURE (zéro API WoW, testable)
│   ├── Config.lua
│   └── Pairing.lua
├── UI/                <- RENDU (zéro calcul)
│   └── Panel.lua
├── libs/              <- libs embarquées (externals)
├── tests/             <- busted (exclu du zip)
├── tools/             <- CLI + validateur .toc (exclu du zip)
├── docs/              <- CONVENTIONS.md, TESTPLAN.md (exclu du zip)
└── .pkgmeta .luacheckrc .busted stylua.toml Makefile .github/
```

---

## 4. Commandes (porte de sortie unique : `make check`)

```bash
make check    # stylua --check + luacheck + check_toc + busted   <- OBLIGATOIRE
make syntax   # vérification syntaxique Lua 5.1 (runtime du client)
make test     # tests unitaires hors jeu (busted)
make toc      # cohérence du .toc
make cli      # appariement du roster d'exemple
make fmt      # reformatage automatique
```

Résultat de référence sur le squelette :

```
$ make check
Total: 0 warnings / 0 errors in 9 files        # luacheck
OK GideonRaid.toc                              # check_toc
  17 successes / 0 failures / 0 errors         # busted
```

### Outillage (installé et vérifié sur le VPS le 22/09/2026, Debian 13)

```bash
apt-get install -y lua5.1 lua5.4 luajit luarocks lua-check jq
luarocks install busted        # busted 2.3.0
luarocks install luaunit       # alternative
npm i -g @johnnymorganz/stylua-bin   # stylua 2.5.2
```

Versions vérifiées : `Lua 5.1.5`, `Lua 5.4.7`, `LuaJIT 2.1`, `luarocks 3.8.0`,
`Luacheck 1.2.0` (tourne sous PUC-Rio Lua 5.1 = runtime du client), `busted 2.3.0`,
`stylua 2.5.2`.

---

## 5. Distribution (guilde de ~25 joueurs) — recommandation

### Ce qui est retenu : dépôt privé + release GitHub + relais par GIDEON

```
tag v1.0.0  →  GitHub Actions (BigWigsMods/packager@v2)  →  GideonRaid-1.0.0.zip
                                       |
                            GIDEON télécharge l'asset (API GitHub, token)
                                       |
                     message Discord dans #addons : zip en pièce jointe
                                       |
                joueurs : glisser-déposer dans Interface/AddOns/
```

**Pourquoi ce choix :**

| Option | Verdict |
|---|---|
| **Dépôt Git privé + zip posté par GIDEON sur Discord** | **RETENU.** Zéro compte pour les joueurs, zéro service tiers, une action = une pièce jointe. GIDEON sait déjà poster et télécharger. Le zip est auto-généré, jamais fabriqué à la main. |
| Dossier d'addon partagé + gestionnaire d'addons | Rejeté : nécessite un projet CurseForge/Wago, un compte auteur pour Jean, et CurseForge **ne propose pas** de distribution restreinte à une guilde. |
| CurseForge « privé » | N'existe pas réellement pour ce cas d'usage : soit c'est public, soit personne ne peut l'installer/auto-updater. |
| Dépôt Git public + `git pull` par les joueurs | Rejeté : demande Git aux joueurs, et pas de mise à jour automatique. À reconsidérer **si** on publie l'addon publiquement plus tard (Wago/CurseForge, auto-update via WoWUp). |
| Wago Addons | Bon candidat *si* publication publique. Clé API `WAGO_API_TOKEN`, déjà câblée dans `.github/workflows/release.yml`. |

Le workflow de release est **déjà écrit et fonctionnel en local** : `release.sh`
du BigWigs packager produit un zip correct (vérifié, voir §4). Il ne reste qu'à
créer le dépôt GitHub et pousser un tag.

### Mises à jour

- À chaque correctif : `git tag v1.0.1 && git push origin v1.0.1` → GIDEON
  annonce la nouvelle version avec le zip.
- **À chaque patch de jeu** : bumper `## Interface:` dans `GideonRaid.toc`
  **et** `MIN_INTERFACE` dans `tools/check_toc.py` (sinon la CI reste verte alors
  que le client marque l'addon obsolète). Le test `check_toc` échouera
  volontairement si le numéro n'a pas été mis à jour.

---

## 6. Documentation

- [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md) — règles de code **obligatoires**
  pour les agents (structure, nommage, commentaires citant la source API,
  interdiction de dépendre d'une valeur secrète, séparation logique/rendu).
- [`docs/TESTPLAN.md`](docs/TESTPLAN.md) — plan de test en 4 étapes, jeux de
  données et résultats attendus.
- [`docs/AGENT-RULES.md`](docs/AGENT-RULES.md) — ce que tout agent de code
  (Claude Code, Codex, OpenCode) doit lire avant de toucher à ce dépôt.
  *(Nommé ainsi car l'environnement bloque la création d'un `AGENTS.md` : créer
  une fois un `AGENTS.md` racine contenant `Voir docs/AGENT-RULES.md` pour que
  les CLI d'agents le chargent automatiquement.)*
