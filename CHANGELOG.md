# Changelog

All notable changes to GideonRaid are documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/); this project
uses semantic-ish versioning driven by git tags (`vX.Y.Z`).

## [0.8.0] - 2026-09-23

Four corrections requested by the raid lead after the **fourth** in-game test:
labels ran over the main panel frame, the intermission panel drew its big state on
top of the `SIMULATION` banner, the ping simulation was a guided sequence nobody
asked for, and the rehearsal closed by itself after a delay.

### Added
- **`Core/Layout.lua`** (pure logic, no WoW API, no event, no clock, no random):
  computes the geometry of every panel as an **ordered list of blocks anchored one
  under the other** (`top = previous.bottom - gap`), grows the frame to the widest
  label, wraps the body, and reports **two blocks sharing a Y band, a block running
  over the frame, a label whose longest word does not fit its button and a block
  drawn under the close cross**. `UI.ApplyLayout` applies the blocks as is and hides
  **and empties** every element the layout does not mention (no stale text).
- `Layout.MAIN_PANEL_ORDER` (the frozen button order) and
  `Layout.MAIN_PANEL_UTILITY_GAP` (the LOCK/UNLOCK utility is visually separated).
- `Core/Simulation.newRun`/`closeRun`/`forRehearsal` (single-cycle rehearsal) and
  `Core/Simulation.pingHelpView(bindKey)`: the **ping help** content (binding path,
  self-ping reminder, resolved keys, group reminder, "cannot detect a ping"), the
  binding key being injected by the rendering layer.
- `tests/spec/layout_spec.lua` (16 tests): pure geometry, verified in **both
  languages**.
- `/gr pinghelp`: an alias of `/gr sim ping`, listed in the `/gr` help.

### Changed
- **Main panel**: the frame is ≈360 px wide (it was 300) and every label is short
  (`PLACE INTERMISSION PANEL`, `SIM: PING YOURSELF`, `SIM: INTERMISSION GROUP`, `LOCK
  PANEL` / `PLACER LE PANNEAU`, `SIMULATION : TE PINGER`, `SIMULATION : GROUPE INTER`,
  `VERROUILLER`): **no label touches or leaves the frame in either language**, the
  body wraps and the frame grows with it instead of overflowing.
- **Main panel button order** (top to bottom, both languages): PLACE INTERMISSION
  PANEL, SIM: PING YOURSELF, SIM: INTERMISSION GROUP, then the LOCK/UNLOCK utility,
  separated by a bigger gap. This order is a `Core/` constant asserted by a test, so
  a future change cannot silently reorder the evening flow.
- **Intermission panel**: the big state, the `SIMULATION` banner, the headline, the
  `PING` line, the role line and the action line are now anchored in **one single
  stack**: nothing overlaps any more (a test asserts that the state is always drawn
  **below** the banner) in English **and** in French; the composition row is not part
  of the layout any more after a click (the three buttons are hidden and emptied, so
  they can never be drawn on top of the banner).
- **`/gr sim inter` (rehearsal)**: the panel opens **IMMEDIATELY** (no more 3 s
  delay), there is **one single cycle** and it is the **player** who closes it (close
  cross or Close button) - no automatic closing, no relaunch, no ticker at all. The
  chat reports the closing honestly and `/gr sim stop` still works.
- **`/gr sim ping`**: the guided sequence is gone (countdown, `PING PLACED` button,
  Avertissement → En route → Aide progression, announced-ping counter). It now opens
  a **short information window** - draggable, position persisted, closable - that
  explains **how to bind one key per ping** (`Options > Keybindings > Ping`) and the
  operational rule: **during the boss, when the panel says `PING: YES`, hover YOUR OWN
  character frame and press your key - you ping yourself**. It still states that a
  ping only shows **in a group or a raid** and that **the addon cannot detect a
  ping**.
- The rehearsal banner carries **two lines** (`SIMULATION - NO BOSS, NO RAID` +
  `SINGLE REHEARSAL - YOU CLOSE THE PANEL YOURSELF`) so it can never be mistaken for
  a fight, and the combat countdown line is replaced by a rehearsal headline (without
  a boss there is no orb to read and no clock).
- `docs/INTERMISSION-COACH.md` (new §2.4 and §2.6), `docs/TESTPLAN.md` (new steps 1d
  and 1e, refreshed loading protocol and §3.5b points 19/20) and `README.md` updated
  in English; `busted` goes from 212 to **219 tests**.

### Removed
- `cycles=N` on `/gr sim inter`: a trailing option is now **refused** with a message
  (one single rehearsal, closed by the player).
- The guided ping-training sequence and its frame (`PING PLACED`, `QUIT TRAINING`, the
  countdown and the announced-ping counter).

## [0.7.0] - 2026-09-22

Four corrections requested by the raid lead after the **third** in-game test: the
main panel could not be moved, the rehearsal ran three cycles instead of one, the
composition buttons stayed on screen after the click, and the ping test had to
teach the **real ANCHOR gesture** (pinging yourself).

### Added
- **`/gr lock` / `/gr unlock` / `/gr resetposition`** (and the **LOCK PANEL /
  UNLOCK PANEL** button on the main panel): freeze the panels where they are, let
  them be dragged again (persisted in `GideonRaidDB.lockPanel`), or bring the main
  panel, the intermission panel and the ping training frame back to the center.
  Dragging a locked panel prints a hint instead of doing nothing silently.
- **Persisted panel positions**: `GideonRaidDB.panelPosition` (main panel) and
  `GideonRaidDB.pingPanelPosition` (ping training frame), saved on every drag stop
  and restored at `ADDON_LOADED` / at the next opening, alongside the intermission
  panel position that already existed (`intermission.position`). Each block is a
  `{ point, relativePoint, x, y }` read back through a **pure, total** resolver.
- `tests/spec/load_spec.lua`: the drag is really allowed, the position is
  persisted, restored, locked, unlocked and reset; the three composition buttons
  disappear after a click (in a real intermission **and** in a rehearsal); the ping
  training shows the self-ping gesture with the bound key. `intermission_spec.lua`
  covers the new panel preferences (`Config.PANEL_SCHEMA`, the one-time migration,
  the total lock/position resolvers, no alias between accounts).
- Locale keys `panel.lockButton` / `panel.unlockButton` / `panel.lockedHint`,
  `cmd.panelLocked` / `cmd.panelUnlocked` / `cmd.positionReset`,
  `ui.noSavedVariables` and the ping-training step lines, in **English and
  French**.

### Changed
- **The main panel is draggable by default** (third in-game feedback: it could not
  be moved at all). `Core/Config.lua` set `lockPanel = true` as the default and
  `UI/Panel.lua` refused the drag accordingly; the default is now `false`, and the
  earlier behaviour is still one command away (`/gr lock`). A SavedVariables file
  written by an older version (no `panelSchema`, hence a `lockPanel = true` no
  player could ever change) is **softly migrated ONCE** in `Config.ensureDB`:
  `lockPanel` is forced to `false` and the schema stamped, so the player's own
  later choice is respected. A non-boolean `lockPanel` counts as "not locked": the
  resolver is total and never locks the player out.
- **A composition click now hides the three choice buttons**: `Core/Intermission.lua`
  serves `showButtons = false` once the state is declared, while `showRedo` stays
  true for the whole session — only the result (state, role, `PING: YES/NO`, the
  action line) and **CORRECT** remain, and CORRECT brings the three choices back
  with an empty state. A second accidental click is impossible.
- **The rehearsal runs ONE cycle by default** (`Simulation.DEFAULT_CYCLES` 3 → 1;
  in-game feedback: "just keep it on 1 test intermission"). The bounds are
  untouched (1–9) and a long rehearsal stays available with
  `/gr sim inter cycles=N`; the chat, the panel counter and the closing summary
  follow.
- **The ping test became a PING TRAINING for the ANCHOR gesture.** Measured in
  game: the ping lands **where the mouse is**, so hovering **your own character
  frame** pings **you**. The frame now shows the gesture step by step in large type
  — `1. Hover YOUR OWN character frame (the one with your health bar).` then
  `2. Press <key> (<Warning>) -> you ping yourself` — with the **really bound key**
  when the injected resolver knows it and **`your ping key`** otherwise (never an
  invented shortcut), plus the reminder that a ping only shows **while grouped**
  and that **the addon cannot detect a ping**. `Simulation.SCHEMA_VERSION` 1 → 2
  (the semantics of the sequence changed).
- **The ANCHOR action line states the real gesture** (`Core/Intermission.lua`, EN
  and FR): "PING: YES - hover YOUR OWN character frame then press your ping key
  (Warning), stay put and jump on the spot" instead of the vague "STAY WHERE YOU
  ARE - ping yourself (Warning)". The MIDDLE and CHASER lines are unchanged, the
  `none` policy still says "STAY WHERE YOU ARE".
- `/gr sim` parses its **whole argument** (mode + optional `cycles=N`) through a
  pure resolver; a sub-command or an option that is not understood is **refused
  with a message**, never guessed.
- **The ping sequence is named "training" everywhere it is displayed**:
  `sim.ping.title`, `sim.ping.quit` (`QUIT TRAINING`), `sim.ping.finished`
  (`PING TRAINING OVER`) and the chat reports (`Ping training over: …`,
  `Ping training left after …`, `err.nothingToConfirm`), EN and FR.
- `README.md`, `docs/INTERMISSION-COACH.md` and `docs/TESTPLAN.md` document the
  movable panels, the single default cycle, the hidden buttons and the self-ping
  gesture (including the in-game rows to replay them, and the open question: does
  the ping placed on oneself show **above the character for the other players**).

## [0.6.0] - 2026-09-22

Two requests from the raid lead after the first real in-game test: a **close
cross** on both panels, and a **SIMULATION MODE** to rehearse alone — no boss, no
raid.

### Added
- **Close cross ("X", top right) on the main panel AND on the intermission
  panel.** The label (`ui.closeCross` = "X") and the short tooltip
  (`ui.closeTooltip` = "Close" / "Fermer") live in `Core/Locale.lua`; a single
  shared rendering helper (`UI.AttachCloseCross`, in `UI/Panel.lua`, which loads
  first) builds the button for both frames, and the tooltip is skipped safely
  when `GameTooltip` does not exist. On the intermission panel the cross
  **cancels the placement** while in placement mode (same effect as the existing
  Close button), **leaves the rehearsal** during a simulation, and otherwise
  **only hides the panel**: the intermission clock keeps running, the panel still
  closes by itself at the end of the intermission and opens again at the next one
  — nothing is armed or disarmed and the validated in-game behaviour is
  untouched.
- **SIMULATION MODE, two entries reachable from the main panel (two buttons) and
  from the chat** (`/gr sim inter` | `sim group` | `sim groupe`, `/gr sim ping`,
  `/gr sim stop`), driven by the new **pure** module `Core/Simulation.lua`:
  - **"Intermission group"** (`/gr sim inter`): the intermission panel opens by
    itself **3 s** after the command (and after each closing), the player clicks
    their composition, sees the state / role / `PING: YES/NO` / the action line,
    corrects it with **REDO**, the panel closes by itself after **~20 s**, and the
    cycle repeats **3 times**. No boss, no raid, no `ENCOUNTER_START`, no combat
    event ever read.
  - **"Native ping test"** (`/gr sim ping`): the three native pings are announced
    one after the other in an **explicit order (Warning → OnMyWay → Assist)** on a
    dedicated frame — "PRESS: Warning (Q)" when the key is really bound (read by
    the rendering layer and injected into `Core/`), "PRESS: Warning" alone
    otherwise — with a **visible countdown**, a `PING PLACED` button to move to
    the next ping, a `QUIT TEST` button and the close cross to leave at any time.
    The frame states as is that **the addon cannot detect a ping** (no API reports
    one, so it never claims it did) and that **pings only show on screen while in
    a group or a raid**.
  - **A "SIMULATION - NO BOSS, NO RAID" banner** is displayed on every simulation
    surface (intermission panel and ping-test frame), with the cycle counter — a
    rehearsal can never be mistaken for a real fight.
  - `Core/Simulation.lua` is **isolated by construction**: bounded numeric options
    (cycles 1–9, opening delay 0–30 s, cycle duration = visibility+1–120 s, step
    1–120 s, gap 0–30 s), **unknown values REFUSED** (non-numeric option, unknown
    ping, empty sequence, unknown sub-command), **at most one transition per call**
    (a huge `dt` never skips a cycle nor a ping), and **no reference at all to the
    pre-computed `ENCOUNTER_START` timeline** (`tests/spec/guard_spec.lua` fails if
    `Core/Simulation.lua` ever mentions `ENCOUNTER_START`, `Intermission.newRun`,
    `advanceRun`, `resetRun` or `RegisterEvent`). A simulation publishes **no
    decision** in the SavedVariables (the diagnostic kit must never read a
    rehearsal as a real choice), is **refused while the real flow is running**
    (live intermission or armed timeline) and is **stopped the moment a real
    encounter starts**.
- `tests/spec/simulation_spec.lua`: 23 out-of-game tests of the two sequences
  (bounds, refusals, explicit order, one-transition-per-call, countdowns, honest
  ping wording, all the new locale keys present in EN and FR); `load_spec.lua`
  covers the two crosses and the two simulations end to end (real loading, tick
  by tick), and `guard_spec.lua` gained the simulation-isolation guard.

### Changed
- `GideonRaid.toc` lists `Core\Simulation.lua` **after** `Core\Intermission.lua`
  (it reuses the canonical states, the ping labels and the binding candidates) and
  before the `UI\` files: `check_toc` now reports **8 files**.
- `cmd.help` (EN and FR) announces the simulation commands, and `tests/support/`
  (API stub + core loader) follows the new `.toc` order.
- The intermission panel layout was shifted down a few pixels so the simulation
  banner can sit under the title (the content and the wording are unchanged).

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

[0.8.0]: https://github.com/BathmanTv/Gideon/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/BathmanTv/Gideon/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/BathmanTv/Gideon/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/BathmanTv/Gideon/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/BathmanTv/Gideon/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/BathmanTv/Gideon/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/BathmanTv/Gideon/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/BathmanTv/Gideon/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/BathmanTv/Gideon/releases/tag/v0.2.0
