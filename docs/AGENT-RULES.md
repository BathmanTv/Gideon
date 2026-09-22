# Instructions pour les agents de code (Claude Code / Codex / OpenCode)

> **À lire avant toute modification du dépôt.** Ce document est normatif.
> La version longue est dans [`CONVENTIONS.md`](CONVENTIONS.md).
>
> *Note : ce fichier s'appelle `AGENT-RULES.md` parce que l'environnement
> bloque la création d'un fichier nommé `AGENTS.md` (fichier d'instructions
> d'agent protégé). Pour que les CLI d'agents le chargent automatiquement,
> créer une fois, à la main, un `AGENTS.md` à la racine contenant la ligne
> `Voir docs/AGENT-RULES.md`.*

## Le projet en une phrase

Addon WoW Midnight 12.1.0 (`## Interface: 120100`) : il **affiche** les paires de
joueurs aux debuffs complémentaires calculées **hors jeu par le bot Discord
GIDEON**, jamais calculées dans le client.

## Les 6 règles qui font échouer une PR

1. **Aucune API de combat dans `Core/`.** `Core/` doit être du Lua 5.1 pur,
   exécutable par `lua5.1` sans le client. Un symbole WoW dans `Core/` = refus.
2. **Aucune logique dépendant d'une valeur secrète.** En 12.x, comparer ou
   faire de l'arithmétique sur un `UnitAura`/`UnitHealth`/`UnitPower` peut lever
   une erreur Lua immédiate.
   → <https://warcraft.wiki.gg/wiki/Secret_Values>
3. **Jamais `COMBAT_LOG_EVENT`** (ni `_UNFILTERED`) : l'enregistrer lève une
   erreur. → <https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes>
4. **Toute API restreinte est commentée avec son URL de source.** Pas d'URL
   inventée ; si elle n'est pas vérifiée, écrire `-- A VERIFIER:` et ne pas
   coder l'appel.
5. **Aucun calcul dans `UI/`.** Le rendu reçoit des valeurs déjà calculées.
6. **`make check` doit sortir en 0.** stylua + luacheck (0 warning) + check_toc
   + busted (tous verts).

## Boucle de travail imposée

```bash
make check          # AVANT de commiter, et il doit être vert
```

Ordre de travail pour une nouvelle fonctionnalité :

1. écrire le test dans `tests/spec/` **d'abord**, le lancer, **vérifier qu'il
   échoue** (rouge) ;
2. implémenter dans `Core/` (logique), puis `UI/` (rendu), puis `GideonRaid.lua`
   (câblage) ;
3. `make check` → vert ;
4. si un fichier doit être chargé, l'ajouter à `GideonRaid.toc` **avec `\`** ;
5. si `.toc` ou `.pkgmeta` a changé : `bash release.sh -t .` et vérifier que le
   zip se construit.

## Structure à respecter à la lettre

- **La racine du dépôt EST la racine de l'addon** (`GideonRaid.toc` à la racine).
  Ne jamais créer de sous-dossier contenant le `.toc` : le BigWigs packager
  cherche `*.toc` dans `$topdir` (vérifié, `release.sh` ligne 1389).
- `tests/`, `tools/`, `docs/` sont exclus du zip via `ignore:` dans `.pkgmeta`.
  Tout nouveau dossier non-addon doit y être ajouté, sinon il pollue le paquet.
- Une nouvelle lib externe **doit** être déclarée dans `.pkgmeta` (`externals`),
  jamais copiée à la main dans `libs/`.

## Interdits explicites

- Pousser un tag `v*` (déclenche la release).
- Éditer `.release/`.
- Ajouter une dépendance ou un workflow nécessitant un secret non configuré.
- « Normaliser » un identifiant mal formé (`## Interface:`, ID CurseForge, nom
  d'addon) : s'arrêter et signaler.
- Utiliser `pairs()` dans un chemin qui influence un résultat calculé
  (non déterministe) : trier explicitement.

## Où regarder quoi

| Besoin | Fichier |
|---|---|
| Règles de code complètes | `docs/CONVENTIONS.md` |
| Plan de test, jeux de données, résultats attendus | `docs/TESTPLAN.md` |
| Contexte 12.x et distribution | `README.md` |
| Chargeur hors jeu (tests) | `tests/support/wowenv.lua` |
| Stub API minimal | `tests/support/wowapi_stub.lua` |
| Moteur d'appariement | `Core/Pairing.lua` |
| Validateur de `.toc` | `tools/check_toc.py` |
