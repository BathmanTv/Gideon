# Changelog

All notable changes to GideonRaid are documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/); this project
uses semantic-ish versioning driven by git tags (`vX.Y.Z`).

## [0.5.0] - 2026-09-22

Redesign of the Intermission Coach after the **first real in-game test** (raid
lead, live raid): the ping macro route is dead by design of the client, the panel
was too verbose, and a wrong click could not be corrected.

### Removed
- **The ping macro, entirely.** Measured in game:
  `C_Ping.SendMacroPing({type = Enum.PingSubjectType.Warning, targetToken = "player"})`
  is refused by the client (*"this action can only be used by the Blizzard UI"*),
  from a macro as well as from an addon. Gone with it:
  `Intermission.buildMacro` (and its record fields `macroPrimary` / `macroFallback`
  / `macroTargetToken` / `pingToken`), the *MACRO / FALLBACK* block of the panel,
  the `/gr inter macro` command, the `macroTargetToken` SavedVariables key and the
  tests that covered them. The anti-forbidden-API guard now fails if `C_Ping`,
  `SendMacroPing` or `PingSubjectType` appears **anywhere**, even inside a string.
- The vestigial out-of-game messages: the main panel no longer shows
  *"No GIDEON assignment"* / *"Ask GIDEON: !g roster assign"* — **that command
  does not exist**. Replaced by a single discreet line,
  `No out-of-game plan loaded (optional).`, and no in-game text ever points to a
  chat command again.
- The verbose panel lines (role order, "PING POLICY", "STATE THAT JOINS YOU",
  caveats, long paragraphs). The technical justification stays in `docs/`, not on
  a panel read during the darkening.

### Added
- **Native ping keybinds instead of a macro.** The panel says WHICH ping to use
  (`PING: Warning`) and, when the player bound one, **which key to press**
  (`PING: Warning - press Q`). The key is read with `GetBindingKey`, **under
  `pcall`, in the rendering layer only**; `Core/` receives it as an injected
  resolver and never calls the API. If no candidate binding responds, the panel
  shows **no key at all** and asks for a keybind in *Options > Keybindings* —
  never a shortcut that does not exist. The candidates live in
  `Intermission.PING_BINDINGS` and are still to be confirmed in game.
- **Bilingual ping labels**: the label displayed follows the client's language —
  EN `Warning` / `On My Way` / `Assist`, FR **`Avertissement` / `En route` /
  `Aide`** (measured in game by the raid lead, 2026-09-22, Options > Raccourcis) —
  while the canonical identifier used by the configuration, the tests and the
  binding candidates never changes.
- **`REDO` button** on the intermission panel: a wrong click is corrected in one
  click, as many times as needed, and it returns to the three composition
  choices cleanly (`Intermission.clearDeclaration`, idempotent).
- **Placement mode** (before the pull): `/gr` → *PLACE INTERMISSION PANEL* (or
  `/gr inter place`) shows the intermission frame where the player wants it, lets
  them prepare their ping keybind, and **OK** validates, saves the position in the
  SavedVariables and closes the panel.
- **The whole evening flow, automatic where it can be**: `ENCOUNTER_START` is the
  starting gun of the **pre-computed schedule** (its arguments are never read),
  the panel **opens by itself** `leadSeconds` (2 s) before each intermission
  (≈46.3 s, then 148.9 / 251.5 / 353.2 s), **closes by itself** at the end of the
  intermission and **reopens** at the next one. New pure machine
  (`Intermission.newRun` / `advanceRun` / `runOpenAt` / `runRemaining` /
  `runFinished` / `resetRun`) with an injected time step; `PENDING` phase while the
  panel waits for the intermission.
- `/gr inter ping`: which ping, which key, and the binding names tried.
- `/gr inter place` (alias `/gr inter setup`) for the placement mode.
- The **one action line** per state, selected by the policy (`state.actionPing.*`
  / `state.actionNoPing.*` in both languages), so the essential fits on screen.

### Changed
- The intermission panel now shows **the essential only**: the state in very large
  type, `ROLE: ANCHOR|MIDDLE|CHASER`, a colored **`PING: YES/NO`** banner and
  **ONE** action line (`1V3R` = "STAY WHERE YOU ARE - ping yourself (Warning) and
  jump on the spot", `2V2R` = "DO NOT PING - go to the middle / under the boss",
  `3V1R` = "DO NOT PING - run to a ping (a 1V3R)"), plus `REDO`. Maximum three
  short lines, checked by the tests.
- `Config.DEFAULTS` is now a **function** returning a fresh table (no shared
  table between two characters or two `/reload`), and
  `Config.resolveIntermission` clamps the new `leadSeconds` and the
  `scheduleSeconds` list (sorted, positive, 12 entries max).
- The ping policy (`anchors` by default, `color`, `none`) is **kept and still
  decides who must ping**, but is no longer displayed permanently: it stays
  available on demand (`/gr ping`, `/gr inter status`).
- The measured **per-player ping limit** is now documented as a fact: **3 pings
  in a row, then about 5 s of wait, then 3 again** (measured in game by the raid
  lead, 2026-09-22). With the `anchors` policy each concerned player sends exactly
  **one** ping per intermission, so the raid stays far from the limit — the design
  argument that validates the anchor-only choice.
- `docs/INTERMISSION-COACH.md`, `docs/TESTPLAN.md`, `docs/CONVENTIONS.md` (§10) and
  `README.md` rewritten around the new flow, the native keybinds and the honest
  "to be confirmed in game" list.
- Offline test suite: **162 tests** (80 in `intermission_spec.lua`, 24 in
  `load_spec.lua`, 21 in `locale_spec.lua`, 20 in `pingpolicy_spec.lua`, 11 in
  `pairing_spec.lua`, 6 in `guard_spec.lua`), zero luacheck warning.

## [0.4.0] - 2026-09-22

### Added
- **Ping roles by STATE** in the Intermission Coach (raid-lead decision): the
  state no longer gives a duty per number but a ROLE — `1V3R` = **ANCHOR**
  (stands still, pings itself with the macro or is pinged by another player,
  does not move), `2V2R` = **MIDDLE** (does not ping, goes to the middle and
  pairs up with another 2V2R), `3V1R` = **CHASER** (does not ping, runs to a
  ping, any 1V3R anchor works).
- **Configurable ping policy**, persisted in `GideonRaidDB.intermission.pingMode`
  and changeable in game with the new `/gr ping anchors|color|none`:
  - `anchors` (default): only the ANCHOR states ping, one ping per anchor —
    about **8 pings per raid instead of ~20**, which keeps the ping channel
    readable (the client also rate-limits pings per player);
  - `color`: raidstrats variant, every state pings with its own color
    (1V3R red/Warning, 2V2R blue/OnMyWay, 3V1R green/Assist);
  - `none`: nobody pings, the raid plays on positions only.
  An unknown value is refused (nothing is persisted, nothing is guessed).
- The intermission panel now shows a **"PING: YES/NO" banner** (colored with the
  role's ping color), the **role order** ("ROLE ORDER: …"), the current ping
  policy, and the **ping macro ONLY for a role that must ping** — a
  CHASER/MIDDLE under `anchors` sees why no macro is proposed instead.
- The pre-pull plan (`/gr plan`, main panel) now deduces the **ping role, the
  role order and, when relevant, the ping macro** from the composition prepared
  by GIDEON, under the configured policy.
- `/gr ping` (no argument) prints the current policy and what it means.

### Changed
- `Intermission.getDeclaration`, `Intermission.snapshot` and
  `Intermission.buildPlan` accept the ping policy as an explicit, injected
  argument: `Core/` stays pure (no SavedVariables read, no API, no clock) and an
  unknown policy always resolves to `anchors`.
- `Intermission.buildMacro` now REFUSES to build a ping macro for a state that
  must not ping under the given policy.
- The state action texts no longer prescribe a ping unconditionally (the ping
  decision comes from the role + the policy), and the "state to join" line is
  adapted for the ANCHOR ("STATE THAT JOINS YOU: …").
- The keybinding label follows the effective language (`/gr lang`) instead of
  being a hard-coded French literal.

### Notes
- Offline test suite: **138 tests**, zero luacheck warnings (19 new tests in
  `tests/spec/pingpolicy_spec.lua`).
- Still 12.x compliant: no combat API, no aura read, no combat log, no
  addon-to-addon messaging, and the addon still only GENERATES the ping macro
  text (the player triggers it: `C_Ping.SendMacroPing` is `#protected`).

## [0.3.0] - 2026-09-22

### Added
- Bilingual in-game text. **English is the official language of the addon**;
  French is served automatically on a `frFR` client.
- New command `/gr lang` (and `/gr lang auto|en|fr`) to inspect the detected and
  effective language and to force one; the preference is persisted in
  `GideonRaidDB.locale`.
- New pure-logic module `Core/Locale.lua` (`Locale.STRINGS`, `Locale.resolve`,
  `Locale.t` / `Locale.format`) with a safe fallback chain that never raises.

### Changed
- All public documentation (README and `docs/`) rewritten in English.
- CI moved to Node 24 actions (`actions/checkout@v5`), runner pinned to
  `ubuntu-24.04`.
- CurseForge publishing is handled by CurseForge itself (packaging on tagged
  commits), so no CurseForge token is needed in the workflow.

### Notes
- Offline test suite: 111 tests, zero luacheck warnings.
- No combat API is used anywhere in the addon (Midnight 12.x compliant: no aura
  reading, no combat log, no addon-to-addon messaging in instances).

## [0.2.2] - 2026-09-22

### Changed
- Workflow maintenance: Node 24 actions, pinned runner, CurseForge publishing
  moved to the CurseForge side.

## [0.2.1] - 2026-09-22

### Added
- GIDEON artwork at the top of the README.

### Fixed
- The release workflow could not create the GitHub Release (missing
  `permissions: contents: write`).

## [0.2.0] - 2026-09-22

### Added
- First published version of **GideonRaid**: Intermission Coach for the Mythic
  *Entombed Sentinels* intermission (orb composition in, position and ping macro
  out), pre-pull pairing plan view, and the offline pairing engine
  (`Core/Pairing.lua`) shared with the GIDEON Discord bot.
- CI and release workflows (BigWigs packager), offline test suite with busted.

[0.5.0]: https://github.com/BathmanTv/Gideon/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/BathmanTv/Gideon/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/BathmanTv/Gideon/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/BathmanTv/Gideon/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/BathmanTv/Gideon/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/BathmanTv/Gideon/releases/tag/v0.2.0
