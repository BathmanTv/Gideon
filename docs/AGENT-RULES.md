# Instructions for code agents (Claude Code / Codex / OpenCode)

> **Read this before any change to the repository.** This document is normative.
> The long version is in [`CONVENTIONS.md`](CONVENTIONS.md).
>
> *Note: this file is called `AGENT-RULES.md` because the environment blocks the
> creation of a file named `AGENTS.md` (protected agent instruction file). So
> that the agent CLIs load it automatically, create a root `AGENTS.md` once, by
> hand, containing the line `See docs/AGENT-RULES.md`.*

## The project in one sentence

WoW Midnight 12.1.0 addon (`## Interface: 120100`): it **displays** the pairs of
players with complementary debuffs computed **out of game by the GIDEON Discord
bot**, never computed inside the client.

## The 8 rules that make a PR fail

1. **No combat API in `Core/`.** `Core/` must be pure Lua 5.1, runnable by
   `lua5.1` without the client. One WoW symbol in `Core/` = rejected.
2. **No logic depending on a secret value.** In 12.x, comparing or doing
   arithmetic on a `UnitAura`/`UnitHealth`/`UnitPower` can raise an immediate Lua
   error.
   → <https://warcraft.wiki.gg/wiki/Secret_Values>
3. **Never `COMBAT_LOG_EVENT`** (nor `_UNFILTERED`): registering it raises an
   error. → <https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes>
4. **Every restricted API is commented with its source URL.** No invented URL;
   if it has not been verified, write `-- TO BE VERIFIED:` and do not code the
   call.
5. **No computation in `UI/`.** Rendering receives already computed values.
6. **No in-game literal in the code.** Every displayed string lives in
   `Core/Locale.lua` (`Locale.STRINGS[key] = { en = ..., fr = ... }`), with
   **English as the official/default language** and French served automatically
   on a frFR client. Use `ns.Locale.t(...)` / `ns.Locale.format(...)`; add new
   strings in both languages. `Core/` never calls `GetLocale()` — that call
   belongs to `GideonRaid.lua`, under `pcall`. See `docs/CONVENTIONS.md` §11.
7. **`make check` must exit with 0.** stylua + luacheck (0 warning) + check_toc
   + busted (all green).
8. **Nothing is declared "automatic" if it depends on the player.** The
   *Intermission Coach* module only displays what the player declares (click) or
   what was prepared out of game; `Bindings.xml` is **never** listed in the
   `.toc` (the client loads it on its own). See `docs/CONVENTIONS.md` §10.

## Enforced work loop

```bash
make check          # BEFORE committing, and it must be green
```

Work order for a new feature:

1. write the test in `tests/spec/` **first**, run it, **check that it fails**
   (red);
2. implement in `Core/` (logic), then `UI/` (rendering), then `GideonRaid.lua`
   (wiring);
3. `make check` → green;
4. if a file must be loaded, add it to `GideonRaid.toc` **with `\`** (dependency
   order: `Core/Locale.lua` first among the `Core/` modules);
5. if `.toc` or `.pkgmeta` changed: `bash release.sh -t .` and check that the
   zip builds.

## Structure to respect to the letter

- **The repository root IS the addon root** (`GideonRaid.toc` at the root).
  Never create a sub-folder containing the `.toc`: the BigWigs packager looks
  for `*.toc` in `$topdir` (verified, `release.sh` line 1389).
- `tests/`, `tools/`, `docs/` are excluded from the zip through `ignore:` in
  `.pkgmeta`. Any new non-addon folder must be added there, otherwise it pollutes
  the package.
- A new external library **must** be declared in `.pkgmeta` (`externals`), never
  copied by hand into `libs/`.

## Explicit prohibitions

- Pushing a `v*` tag (it triggers the release).
- Editing `.release/`.
- Adding a dependency or a workflow requiring an unconfigured secret.
- "Normalizing" a malformed identifier (`## Interface:`, CurseForge ID, addon
  name): stop and report.
- Using `pairs()` in a path that influences a computed result
  (non-deterministic): sort explicitly.
- Hard-coding an in-game string instead of going through `Core/Locale.lua`
  (English official, French on frFR).

## Where to look at what

| Need | File |
|---|---|
| Full code rules | `docs/CONVENTIONS.md` |
| Language layer (bilingual, English default) | `Core/Locale.lua`, `docs/CONVENTIONS.md` §11 |
| Test plan, data sets, expected results | `docs/TESTPLAN.md` |
| Entombed Sentinels module (convention, macro, "to be confirmed in game") | `docs/INTERMISSION-COACH.md` |
| 12.x context and distribution | `README.md` |
| Out-of-game loader (tests) | `tests/support/wowenv.lua` |
| Minimal API stub | `tests/support/wowapi_stub.lua` |
| Pairing engine | `Core/Pairing.lua` |
| Intermission Coach (pure logic) | `Core/Intermission.lua` |
| Intermission panel (rendering) | `UI/Intermission.lua` |
| Reference assignment block (contract) | `tests/fixtures/assignment_sample.lua` |
| `.toc` validator | `tools/check_toc.py` |
