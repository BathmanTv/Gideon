# GideonRaid — code conventions (MANDATORY for every code agent)

This file is normative. Claude Code / Codex / OpenCode must follow it without
exception. Any PR that breaks it is rejected by `make check`.

---

## 1. Technical context never to lose sight of (patch 12.1.0, live)

Verified sources:

- `## Interface: 120100` — patch 12.1.0 "Curse of Ula'tek", released on
  11/08/2026, `.toc` Interface = `120100` → <https://warcraft.wiki.gg/wiki/Patch_12.1.0>
- `## Interface: 120007` for 12.0.7 — <https://warcraft.wiki.gg/wiki/Patch_12.0.7>
- Secret Values — <https://warcraft.wiki.gg/wiki/Secret_Values>
- API changes 12.0.0 — <https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes>

### 1.1 Secret Values

> "Combat API functions may now return secret values when called […] Tainted
> code is not allowed to perform arithmetic on secret values. Tainted code is
> not allowed to compare or perform boolean tests on secret values."

Operational consequences, to be applied mechanically:

1. **FORBIDDEN**: reading a unit value and testing / counting / computing on it.
   `UnitHealth`, `UnitPower`, `UnitAura`, `UnitCastingInfo`, combat `GetTime`,
   `auraInstanceID`s, cooldown states… can return a secret. An
   `if secretValue > 0 then` is an **immediate Lua error**.
2. **ALLOWED**: storing a secret in a variable or a table field, passing it to a
   Lua function, concatenating it into a string, passing it to a widget flagged
   as accepting secrets (e.g. `StatusBar:SetValue`).
3. If the code must know *whether* a value is secret, it uses
   `issecretvalue(v)` / `canaccessvalue(v)` — it never pretends otherwise.

### 1.2 Further prohibitions

- **`COMBAT_LOG_EVENT` and `COMBAT_LOG_EVENT_UNFILTERED` may not be
  registered**: `frame:RegisterEvent("COMBAT_LOG_EVENT")` raises an immediate
  error in 12.x. No file of this repository may contain those strings.
- **No addon → addon communication in an instance** (messages to another addon).
  The exchange channel with GIDEON is out of instance / out of combat.
- **No workaround** ("un-secreting" a value): it is forbidden by Blizzard and it
  is the number one cause of addon breakage in 12.x.

### 1.3 The official channel with GIDEON

The GIDEON bot is not inside the client. The only reliable channel is:

```
GIDEON (out of game)  --writes-->  WTF/Account/<ACCOUNT>/SavedVariables/GideonRaid.lua
                                    |
                              player /reload or client restart
                                    |
                              the addon READS GideonRaidDB.assignment
```

That data is **text strings written out of game: never secret values.** That is
what makes the whole project feasible.

---

## 2. Architecture: two layers, one uncrossable border

```
Core/      PURE LOGIC. Zero WoW API. 100% testable with busted, out of game.
UI/        RENDERING. May call the WoW API. Zero business computation.
GideonRaid.lua  Wiring: events, slash commands. Depends on both.
```

### Rules

1. A file in `Core/` **must never** reference a WoW API symbol (`CreateFrame`,
   `UnitName`, `C_*`, `_G.GideonRaidDB`, `DEFAULT_CHAT_FRAME`…). Direct
   corollary: there is nothing to mock in order to test it.
2. A file in `UI/` **contains no computation**. It receives values already
   computed by `ns.Pairing` / `ns.Config` / `ns.Intermission` and displays them.
3. Any data coming from the client (player name, roster, locale) enters `Core/`
   **already converted into a string or a number** by the wiring.
4. If a need seems to force `Core/` to call the API: the need is badly split.
   Extract the computation and pass the result as a parameter.

---

## 3. Repository structure (enforced)

```
GideonRaid/                      <- REPOSITORY ROOT = ADDON ROOT
├── GideonRaid.toc               <- file name == install folder == package-as
├── GideonRaid.lua               <- entry point (events, slash, language wiring)
├── Bindings.xml                 <- intermission panel binding(s). Loaded
│                                   AUTOMATICALLY by the client: NEVER listed
│                                   in the .toc (see §10)
├── Core/
│   ├── Locale.lua               <- in-game strings (en/fr) + language resolution
│   ├── Config.lua               <- defaults + SavedVariables
│   ├── Pairing.lua              <- pairing engine (PURE)
│   └── Intermission.lua         <- Intermission Coach (PURE)
├── UI/
│   ├── Panel.lua                <- rendering
│   └── Intermission.lua         <- intermission panel rendering
├── libs/                        <- embedded libraries (externals), never edited
├── tests/
│   ├── spec/*_spec.lua          <- busted
│   ├── fixtures/                <- reference SavedVariables blocks (contract)
│   └── support/                 <- harness (wowenv, API stub)
├── tools/                       <- out-of-addon scripts (excluded from the zip)
├── docs/
├── .pkgmeta  .luacheckrc  .busted  stylua.toml  Makefile
└── .github/workflows/{ci,release}.yml
```

**The WoW client requires the repository root to be the addon root**: that is
also what the BigWigs packager requires (`release.sh` looks for `*.toc` in
`$topdir`, line 1389 of release.sh). Never reintroduce a sub-folder containing
the `.toc`.

Every `.lua` file must be listed in the `.toc`, in dependency order —
`Core/Locale.lua` **first** among the `Core/` modules, since Config,
Intermission, Panel and UI depend on it. The separator is `\` (backslash),
**never** `/`.

---

## 4. Naming conventions

| Element | Convention | Example |
|---|---|---|
| Folder / TOC / package | PascalCase, identical everywhere | `GideonRaid` |
| Lua file | PascalCase for modules | `Core/Pairing.lua` |
| Specs | `snake_case` + `_spec.lua` | `pairing_spec.lua` |
| Module table | Same name as the file | `local Pairing = {}` |
| Exposed in the namespace | `ns.Pairing` | `ns.UI.Refresh()` |
| Public function | `camelCase` | `Pairing.buildPairs` |
| Local function | `camelCase` in `local function` | `local function sortedCopy` |
| Constant | `UPPER_SNAKE` | `Pairing.SCHEMA_VERSION` |
| `Sav..` variables | `<Addon>DB`, `<Addon>CharDB` | `GideonRaidDB` |
| Created global | prefixed | `GideonRaidPanel` |

**Mandatory** file header (see the existing templates):

```lua
local _, ns = ...
```

- `local _, ns = ...` when the addon name is not used (`_` is not reported by
  luacheck; `local addonName, ns = ...` is → warning 212).
- **Never** an implicit global. Every global must be declared in `.luacheckrc`
  *and* justified in a comment.

---

## 5. Mandatory comments when an API is restricted

As soon as a line touches an API restricted in 12.x, it is preceded by a comment
citing **the source**, in this format:

```lua
-- API ref 12.1.0: <https://warcraft.wiki.gg/wiki/...>
-- Constraint: <what is forbidden and why>
-- <the line of code>
```

Real example (in `Core/Pairing.lua`):

```lua
-- API ref 12.x: https://warcraft.wiki.gg/wiki/Secret_Values
-- Constrained source: "Tainted code is not allowed to compare or perform
-- boolean tests on secret values."
-- => only strings provided by the player or by GIDEON are handled.
```

Related rules:

- A comment citing an API **must** contain the URL of the matching wiki page. No
  invented URL: if it has not been verified, write `-- TO BE VERIFIED:` and do
  not code the call.
- **Never any business logic depending on a secret value.** If an addon
  behaviour changes according to a potentially secret value, it is rejected in
  review. The data must come from `GideonRaidDB` or from player input.
- At the slightest doubt: `-- SECRET?` at the top of the function, and the
  function may not be called from `UI/Refresh`.

---

## 6. Style: automated, non-negotiable

- `stylua.toml`: 4 spaces, 140 columns, double quotes.
  **`stylua --check .` must pass.** Never format by hand.
- `luacheck .` must print `0 warnings / 0 errors`.
- `std = "lua51"`: the WoW client runs on **PUC-Rio Lua 5.1**. Therefore:
  - no `goto`, no `//` operator, no native integers, no `\u{}`;
  - `table.unpack` does not exist → `unpack`;
  - `#` on a table with holes is forbidden (`#` is only defined for hole-free
    sequences).
- Comments and identifiers in **ASCII** for Lua code (`.md` files may use
  accents).
- **No in-game literal in the code**: every displayed string goes through
  `ns.Locale` (§11).

---

## 7. Determinism (a testing rule, not a style rule)

- No sort by input order: always sort **by name** or by an explicit key. The
  same roster must produce the same result whatever the order received from
  GIDEON. (See the test "est insensible a l'ordre d'entree".)
- No `pairs()` in a path that influences the result: `pairs()` has no guaranteed
  order. Use a sorted list.
- No `math.random`, no dependency on the clock, no `GetTime()` in `Core/`.

---

## 8. Definition of "done" for a task

A task is finished if, **and only if**:

1. `make check` exits with code 0 (stylua + luacheck + toc + busted);
2. a test in `tests/spec/` covers the new behaviour (and fails before the fix —
   actually verify red then green);
3. the new file is listed in `GideonRaid.toc` if it must be loaded;
4. no `COMBAT_LOG_EVENT` string, no call to a combat API without a source
   comment, no logic on a secret value;
5. `bash release.sh -t .` produces a zip without error (to be run when
   `.pkgmeta` or the `.toc` changed).

---

## 9. What an agent must NEVER do

- Add an external dependency (library, Lua package) without declaring it in
  `.pkgmeta` (`externals`) — otherwise the packaged zip is broken.
- Edit `libs/` by hand.
- Push a `v*` tag: the tag triggers the release (workflow `Release`).
- Introduce a workflow that needs an unconfigured secret.
- Edit `.release/` (artifact, gitignored).
- "Repair" a malformed token (addon name, Interface number, CurseForge project
  ID): if a value does not match the expected format, stop and ask.

---

## 10. Rules specific to the "Intermission Coach" module

1. **No claimed automation.** Everything the addon displays comes either from a
   player click or from a block prepared out of game. Forbidden to write in the
   UI, in the docs or in a commit message that an action is "automatic" when it
   depends on a player declaration.
2. **No ping sent by the addon, no macro preparing one.**
   `C_Ping.SendMacroPing` is `#protected` and the client **refuses the call even
   from a macro or a binding** — measured in game on a live raid: *"this action
   can only be used by the Blizzard UI"*. The module therefore **generates no
   macro any more** and only tells the player **which ping to use**; the player
   triggers it with the **native** ping keybind
   (Options > Keybindings > ping system, since 10.1.7). Forbidden to write, in the
   UI, in the docs or in a commit message, that the addon pings or prepares a
   ping. The anti-forbidden-API guard (`tests/spec/guard_spec.lua`) fails if
   `C_Ping`, `SendMacroPing` or `PingSubjectType` appears anywhere in a file
   listed in the `.toc`, **comments excluded** — and `buildMacro` must not come
   back.
2bis. **The ping keybind is READ, never bound.** The only allowed call is
   `GetBindingKey(<candidate>)`
   (<https://warcraft.wiki.gg/wiki/API_GetBindingKey>), **in `UI/` only**, **under
   `pcall`**, for display. `Core/` never calls it: the rendering layer injects a
   `resolveBinding(refName)` function, and `Core/Intermission.pingHint` only
   formats what it receives. If the lookup returns nothing (no key bound, unknown
   binding name), the panel must show **no key at all** and point to
   *Options > Keybindings* — never invent a shortcut. The candidate names are
   data (`PING_BINDINGS` in `Core/Intermission.lua`) and stay **to be confirmed in
   game**.
3. **`Bindings.xml` is NEVER listed in the `.toc`**: the client loads it
   automatically. `tools/check_toc.py` keeps checking only the `.lua` files
   listed in the `.toc`.
4. **No combat API value in the module**: no aura, no health, no resource, no
   target. Only the name of our own unit (`UnitName("player")`) and the strings
   from `GideonRaidDB` enter it. The **arguments of `ENCOUNTER_START` are never
   read** (they are secret values): the event is only the starting gun of the
   pre-computed schedule.
5. **Time is injected.** `Core/Intermission.tick(state, dt)` and
   `Core/Intermission.advanceRun(run, dt)` receive a constant time step provided
   by the wiring: no `GetTime()` in `Core/`.
6. **The UI says what is impossible.** The panel explicitly states that "who
   declared what" is unknown and that the ping is the only signal visible to the
   other players.
7. **The panel shows the ESSENTIAL only** (raid-lead decision after the first real
   in-game test): the state, the role, `PING: YES/NO` and **one** action line.
   Forbidden on screen: role orders, ping policies, caveats, long paragraphs —
   the justification belongs to `docs/`, not to a panel read during the
   darkening. Same rule for the vestigial messages: **never** point the player to
   a command that does not exist (the absent out-of-game plan is reported by a
   single discreet line, or not at all).

---

## 11. Language layer (bilingual, English by default)

1. **English is the official language** of the addon; French is served
   automatically on a frFR client. No in-game string may be written as a literal
   in the modules: it lives in `Core/Locale.lua` as
   `Locale.STRINGS[key] = { en = "...", fr = "..." }` and is served through
   `ns.Locale.t(key)` / `ns.Locale.format(key, ...)`.
2. `Core/Locale.lua` is **pure**: no `GetLocale()`, no API. Detection belongs to
   the wiring layer, which calls `GetLocale()`
   (<https://warcraft.wiki.gg/wiki/API:GetLocale>) under `pcall` and hands the
   raw value to `Locale.resolve(preference, detected)`.
3. `Locale.t` **never raises**: it serves the requested language, then the other
   language, then the key itself. `Locale.format` uses `pcall(string.format)`.
4. Keys are stable identifiers (`state.action.3V1R`, `ui.close`). Spell, orb and
   color names (`3V1R`, `Warning`, `OnMyWay`, `Assist`) are identical in both
   languages and are therefore never translated.
5. The persisted preference is `GideonRaidDB.locale` (`"auto"` by default,
   `"en"`, `"fr"`), normalized by `Config.resolveLocale`: any unexpected value
   falls back to `"auto"`.
6. Every new displayed string **must** be added in both languages, and covered
   by `tests/spec/locale_spec.lua` (default = English, `"frFR"` = French,
   explicit override wins, unknown value = English, missing key = the key).
7. The `.toc` keeps `## Notes:` in English and `## Notes-frFR:` in French.
