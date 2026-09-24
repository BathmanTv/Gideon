# Changelog

All notable changes to GideonRaid are documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/); this project
uses semantic-ish versioning driven by git tags (`vX.Y.Z`).

## [0.13.1] - 2026-09-24

**The placement panel is the illustration alone, the intermission panel has no
title any more, the word is much bigger, and the buttons are thin-bordered cards.**
Four requests from the raid lead after the first evening with the picture panel.

### Changed

- **The placement panel shows ONLY the illustration.** During `/gr inter place`
  (and the **PLACE INTERMISSION PANEL** button) the panel used to show the three
  composition pictures plus an **OK** button; it now shows the raid lead's Gideon
  illustration (`Texture/placement.tga`) and **nothing else** — no button, no
  label, no composition. It is the **visual reference** of the window being placed:
  you see the size and the spot it will take during the fight. The panel stays
  **draggable** (position saved), the close cross **cancels**, and the placement is
  validated by the new **`/gr inter ok`** command, which saves the position exactly
  like the former button did.
- **No title, anywhere.** The intermission panel's title (`ui.panelTitle`, rendered
  by an old content builder) and the whole pre-pull text block are **deleted** —
  the builder (`Intermission.setupView`), its strings (`ui.setup.*`, `ui.ok`) and
  the placement **OK** button are gone from the source, not merely hidden. The
  panel now carries nothing but: the three picture cards, the close cross, and the
  one word + **CORRECT** after the click. The **SIMULATION** banner stays (it is
  what tells a rehearsal from a real fight) and no other title is allowed.
- **The word after the click is five notches bigger.** `Ping` and `Chasseur` are
  now drawn at **44 px** and `BOSS` at **64 px** (the biggest text of the window),
  with an **explicit font file and size** (`Layout.WORD_FONT_FILE`,
  `Layout.WORD_SIZE`, `Layout.WORD_SIZE_BIG`) applied through
  `FontString:SetFont(file, size, "")` on a FontString the addon creates — never a
  Blizzard font object, whose real size an addon cannot read out of game. The frame
  **widens itself** until the word fits whole (`nowrap`), so `Chasseur` and `BOSS`
  are **never truncated nor pushed out of the frame**, in French as in English.
- **The buttons are simple cards.** Each composition picture is now drawn inside a
  **thin border with a discreet dark background** (`Layout.BUTTON_STYLES.card`),
  with **no text** and **one single feedback**: the border lights up under the mouse
  and while pressed. Nothing else moves. The **style is a parameter**
  (`Layout.BUTTON_STYLES` + `Layout.CHOICE_STYLE`): the richer picker the raid lead
  is still choosing will be a new entry in that table, and `UI.ApplyCardStyle` reads
  whatever Core names.

### Added

- **`Texture/placement.tga`**: the Gideon illustration delivered by the raid lead,
  converted to **uncompressed 32-bit TGA** with the same reproducible tool
  (`tools/make_textures.py`), fitted in a **384 px box** with the aspect ratio kept,
  listed in `GideonRaid.toc` and kept outside `assets/`. Note that this delivery is
  **opaque** (the PNG has no alpha channel), unlike the three orb screenshots.
- **`/gr inter ok`** (alias `/gr inter confirm`): validates the placement and closes
  the panel; it replaces the OK button on a panel that must show no button at all.
- **`Core/Textures.lua`** now exposes the placement file, its size, its client path
  and a shared aspect-preserving fit; **`Core/Layout.lua`** gained the card styles,
  the explicit word size/font constants, `Layout.placementPanel()`, the per-panel
  text allow-lists and the card rules of `violations()`.
- **Tests**: the placement panel builds **one** block (the illustration) and it is
  the only one — no button, no text, nothing under the cross; the placement TGA
  exists, is 32-bit uncompressed, is listed in the `.toc`, is fitted in a ~384 px
  box and is **not** an orb state; the old title/placement strings
  (`ui.panelTitle`, `ui.ok`, `ui.setup.*`) **can not come back** and the layout
  rules **refuse** any text a panel is not allowed to write; the word's font size is
  asserted per composition **in FR and EN** (>= 44 px, >= 64 px for `BOSS`) with no
  truncation and no overflow; cards carry a border and a discreet background, size =
  picture + the padding of the style, with the border lighting up on hover/press and
  **no sound** outside a click; the placement panel stays **draggable** (position
  saved and restored) and `/gr inter ok` saves that position and closes.

### Fixed

- A fitting bug in `Core/Textures.lua`: `Textures.placementDisplaySize` handed the
  box to `fitInBox` as the **height** (a Lua multi-value call in the middle of an
  argument list), which sized the placement illustration at the default box instead
  of 384 px. The aspect-ratio rule of `Layout.violations()` is what caught it.

## [0.13.0] - 2026-09-24

**The intermission panel is now three pictures and one word.** Every line of text
was removed — the raid lead asked for the simplest possible panel — and the addon
no longer plays **any** sound by itself: the soundboards fire on the click only.

### Changed

- **The panel content is three pictures.** It used to show a headline, a state, a
  role and an action line; it now shows **three vertically stacked image buttons**
  (fixed order: 3 green + 1 red, 2 green + 2 red, 1 green + 3 red), and **nothing
  else** before the click. The close cross and the dragging (saved position) stay.
- **One single word after the click** (`Core/Locale.lua`, FR / EN): `1V3R` →
  **PING** (green), `2V2R` → **BOSS** (largest font of the window), `3V1R` →
  **CHASER** (green). The colour and the font come from the shared theme
  (`Core/Layout.lua`) instead of scattered literals. **CORRECT** stays, discreet.
- **Sounds fire on the click only.** The soundboard of the declared composition is
  played **once per click** and nowhere else; nothing plays at the auto-open, in
  `/gr sim inter`, on a re-render or on closing.
- **The panel always closes.** A bounded close guard (`Core/Intermission.newCloseGuard`
  / `arm` / `tick` / `disarm`, pure, no clock) plus `Config.autoCloseSeconds`
  (default 30 s = the real 2 + 3 + 20 s window + 5 s margin, bounded 5..300) makes
  the window disappear at the end of the intermission even if the state machine
  stalls.

### Added

- **`Texture/`** (new): the raid lead's three in-game screenshots converted to
  **uncompressed 32-bit TGA** (alpha kept, 256 px box, aspect preserved), listed in
  `GideonRaid.toc` and kept **outside** `assets/` (which the packager excludes).
- **`Core/Textures.lua`** (pure): the single mapping from a state to its texture
  file, its size and its client path; **`tools/make_textures.py`** makes the
  conversion reproducible.
- **`tests/spec/texture_spec.lua`**: TGA header read byte by byte, declared
  dimensions, transparent background, `.toc` listing, state → screenshot mapping.
- Tests for the new panel: pinned vertical order, no leftover text before the
  click, exact word + colour + size per composition in FR **and** EN, one click =
  one sound and **no sound otherwise** (auto-open, simulation, re-render, closing),
  and the bounded close filet (`Core` + `UI`).

### Removed

- **The automatic intermission start sound.** `Sound/intermission-start.ogg` stays
  in the package and can still be heard on demand (`/gr sound test start`), but it
  is never triggered by the addon any more.

## [0.12.0] - 2026-09-24

**The target boss is now DELIVERED with the addon** — no player has to type a
command for the intermission panel to open on *Entombed Sentinels* — and a new
**read-only health report** validates the four sound files **in game** without ever
making a noise in a raid.

### Added

- **The default target, shipped with the addon** (`Core/Config.lua`,
  `Config.DEFAULT_BOSS_IDS` / `Config.DEFAULT_BOSS_NAMES`). The encounter id
  **`3445`** is the one **MEASURED IN GAME** by the raid lead on **2026-09-24**
  (heroic pull, 20 players, `/gr idlog on`):
  `encounter seen: id=3445 name=Sentinelles inhumées difficulty=15 group=20`. The
  **id stays the primary criterion** (an integer, identical on every client
  whatever the language) and the two names are shipped as a **secondary** safety
  net: the official `Entombed Sentinels` **and** `Sentinelles inhumées`, the French
  string of the raid lead's client, accent included (the file is UTF-8 and the
  string is compared as-is, case-insensitively, never re-accented). **Every
  difficulty** of that boss opens the panel (14 Normal / 15 Heroic / 16 Mythic / 17
  LFR, documented in `Config.BOSS_DIFFICULTIES`): the difficulty is **deliberately
  not filtered**, it is logged by the idlog and never takes part in the decision.
- **`BossFilter.resolveTarget`** (`Core/BossFilter.lua`, pure): the *effective*
  target = the player's own entries **plus** the delivered default. Two states are
  now distinct and can never be confused:
  - **never configured** (fresh install, empty SavedVariables) → the delivered
    default applies (`bossTargetSource = "default"`), so the panel opens with no
    command typed and **no warning is printed at login**;
  - **cleared on purpose** (`/gr boss clear` → `bossTargetCleared = true`, an exact
    `true` only) → the delivered default is **dropped too**: nothing opens by itself
    any more until `/gr boss <id>` names a target again — an explicit choice is
    never silently undone, and a lost configuration is never mistaken for a choice;
  - **player addition** (`/gr boss 2594`) → added to the delivered default, never
    replacing it; `/gr boss 3445` is idempotent.
- **`/gr diag`** — the health report, in one read-only command: the **effective
  auto-open target and where it comes from**, the delivered default, the idlog
  state, the ping policy, and a **verdict per sound file** (the four of them).
  The verdict comes from the **boolean returned by `PlaySoundFile`** (`true` = the
  client **will** play the file, `false`/`nil` = missing file, file added after the
  client started, or refused playback). That call **is** a playback, so it runs
  behind a **silence gate** (`Core/Diag.probeGate`): the probe is only made when the
  Master channel is **enabled** (a disabled channel answers "nothing will play" even
  for a file that is there — the verdict would be a lie) **and** its volume is **0**
  (mathematically inaudible). With the sound on, `/gr diag` plays **nothing** and
  says so, with the procedure to get a verdict (`/console Sound_MasterVolume 0` →
  `/gr diag` → restore) and the reminder that a file added after the client started
  needs a **restart**, and that a file unlisted in `GideonRaid.toc` is never loaded.
  A client that refuses to answer reads **UNKNOWN**, never a fake KO.
- **`Core/Diag.lua`** (new PURE module: no client call at all — the rendering layer
  injects the two CVars and the answers), and the guard test that keeps it that way.
- `/gr boss` and `/gr boss list` now print the **source** of the effective target
  and label every entry with its **provenance** (*addon default* / *added by you*);
  the delivery is announced in the chat so the target is never a mystery.

### Changed

- The refusal message at an encounter that opens nothing **distinguishes the two
  cases**: an explicitly cleared target (`/gr boss clear`, short message naming
  `/gr boss 3445`) vs no target at all (the full procedure). The login warning is
  only printed when **nothing** can open (it is silent on a fresh install now).
- `/gr boss name <text>` still adds a name to the player's own list; the name
  criterion is no longer empty by default (the two delivered names).
- Test suite: **302 → 331 tests** (new `tests/spec/diag_spec.lua`, 19 tests; the
  delivered-target states covered in `bossfilter_spec.lua` and
  `intermission_spec.lua`); `.toc` entries **15 → 16** (12 Lua files + 4 sounds).
  `make check` stays green (stylua + luacheck on **28** files + check_toc + busted).

### Not in this release

- **No tag, no packaging**: this entry is staged under `[Unreleased]`.

## [0.11.0] - 2026-09-24

**Critical bug fixed** — *"the window opens by itself during ANY boss fight! It
must be limited to the boss we want."*: the intermission panel used to open on
**every** `ENCOUNTER_START` of every raid. The auto-open is now filtered by a
**persisted allow-list of encounter ids**, with a **safe default: an empty list
opens nothing**. Plus the raid lead's **intermission start sound**
(`Sound/intermission-start.ogg`), played **once** at the beginning of every
intermission.

### Fixed

- **The panel only opens on the target boss** (`Core/BossFilter.lua`, new PURE
  module: no WoW API, no clock). The decision is
  `BossFilter.evaluate(observation, configuration) -> { shouldOpen, reason, id, name }`,
  in this order: the **manual override** (`/gr inter on`), then an **empty
  allow-list = REFUSAL** (safe default, `noTarget`), then the **encounter id**
  (`ENCOUNTER_START` arg1, an integer, identical in every client language),
  then the optional **name** criterion (case-insensitive), otherwise `noMatch`
  (or `unreadable` when a value could not be read). A schedule left over by a
  previous fight is disarmed too, so the panel can never open on the wrong boss.
- **Every `ENCOUNTER_START` argument is read under `pcall`, and only to compare**:
  in 12.x an argument may be a **secret** value, whose smallest operation raises.
  The reader is **injected** by the wiring layer (Core/ never touches an event), a
  value that fails to read is reported as `unreadable` and is **never a match**,
  and the decision itself is called through `pcall` (`UI.BossDecision`): the worst
  case is a panel that does not open, **never** a Lua error and **never** an
  automatic opening on an unknown boss.
- A stale `ENCOUNTER_START` schedule is **disarmed** when an encounter is not the
  target, and `/gr inter off` clears the manual override, so nothing can fire
  later on.

### Added

- **`/gr boss`** — which boss may open the panel by itself:
  - `/gr boss` prints the auto-open target, the idlog state and, when the list is
    empty, the **safe-default warning** with the exact procedure;
  - `/gr boss <id>` **adds an encounter id** to the persisted allow-list (the
    **primary** criterion). Anything that is not a **positive integer** (`abc`,
    `0`, `-3`, `12.5`, `1e3`) is **REFUSED without persisting anything** (same
    mechanics as `/gr lang`, `/gr ping` and `/gr sound`) — the id of the target
    boss is **measured**, never guessed;
  - `/gr boss name <text>` adds the **secondary** criterion: the exact encounter
    NAME. It depends on the **client language** (the raid lead plays on a French
    client), so the list is **EMPTY by default** and no translated name is ever
    written for the player;
  - `/gr boss list` shows both lists, the manual override and the encounters
    memorized by the idlog; `/gr boss clear` empties both lists (back to the safe
    default).
- **`/gr idlog on|off`** (persisted) — the **measurement** mechanism requested by
  the raid lead: at **every** `ENCOUNTER_START` the chat prints
  `encounter seen: id=… name=… difficulty=… group=…` (each value read under
  `pcall`; an unreadable value prints `unreadable` instead of a fake number) and
  the **last 10** observations are memorized in the SavedVariables
  (`GideonRaidDB.intermission.seenEncounters`, newest first). This is how the real
  id of *Entombed Sentinels* is captured in game: `/gr idlog on`, pull the boss,
  `/gr boss list` (or the chat line), then `/gr boss <id>`. Nothing is sent
  anywhere.
- **The safe default is announced**: with no target configured, the chat says so
  **once at login** and again at every encounter that opens nothing — the panel is
  not silently broken, it tells the player how to configure the right boss. A
  panel that does not open is better than a panel on the wrong boss.
- **`/gr inter on` is the MANUAL OVERRIDE** (and stays the enable command): it
  arms the panel for the **NEXT** encounter, whatever the boss, and that arm is
  **consumed at the end of that encounter** (`/gr inter off` clears it) — the only
  way to open the panel on a boss that is not the configured target.
- **The intermission START sound** (`Sound/intermission-start.ogg`, the raid
  lead's own recording, already in the repository and **listed in
  `GideonRaid.toc`** — an unlisted sound is not loaded by the client). It is
  played **once at the very beginning of every intermission** — the moment the
  panel opens by itself, 2 s before the intermission — and **once per
  `/gr sim inter` rehearsal`. The rule is an **identity** carried by the caller
  (`Sound.newStartGate` / `Sound.takeIntermissionStart`: the wiring hands a token
  naming the intermission), so the same intermission can **never** sound twice
  while the next one always sounds, with no explicit re-arm. Same channel
  (`Master`), same preference (`/gr sound on|off`) and same `pcall` protection as
  the soundboards.
- **`/gr sound test start`** plays that file on request and names it in the chat,
  without waiting for a pull.
- `tests/spec/bossfilter_spec.lua` (40 tests): the pure decision (good id, wrong
  id, **unreadable** id via an injected reader that raises, empty list, empty
  name, difficulty which **never decides**, override), the strict resolvers and
  the total ones (a hand-edited SavedVariables can never open the panel), the
  idlog ring (bounded, newest first, empty observations dropped), and the wiring
  (`/gr boss`, `/gr boss name`, `/gr boss list`, `/gr boss clear`, refusals
  without persisting, `/gr idlog`, the login warning, the manual override consumed
  at the end of the encounter, and a Core decision that raises staying a refusal).
- The intermission start sound is covered end to end: its pure gate (one playback
  per intermission, a new token plays again, `/gr sound off` silences it), the real
  flow (**two intermissions = two sounds**), the rehearsal (one per cycle), the
  `.toc` entry and the file on disk (real Ogg Vorbis).

### Changed

- `GideonRaid.lua`: the event handler now passes the `ENCOUNTER_START` arguments
  to `ns.BossFilter.observeEncounter` (they were ignored before) — still no combat
  API, no combat log event, no ping, no macro.
- `GideonRaid.toc`: `Core/BossFilter.lua` (loaded **before** `Core/Config.lua`)
  and `Sound/intermission-start.ogg` are listed.
- `Core/Config.lua` resolves the new persisted fields (`bossIds`, `bossNames`,
  `idlog`, `seenEncounters`, `overrideEncounter`) and publishes one observation
  into the idlog ring; `Core/Sound.lua` owns the start sound (one playback per
  intermission); `UI/Intermission.lua` owns the playback and the warning messages.
- Docs: `README.md` (§3.2 flow, §3.3 start sound, §3.4 `/gr boss` + the ID capture
  procedure, §5 structure, §6 reference `make check` output), `docs/INTERMISSION-COACH.md`
  (§2.7 start sound, §2.8 the auto-open filter, §6 configuration, §7 commands,
  §8 test counts, §9 items 19-20), `docs/TESTPLAN.md` (§1g, Step 2 items 28-29,
  protocols §3.5d/§3.5e, coverage matrix).
- Test suite: **260 → 302 tests**; `.toc` entries **13 → 15** (11 Lua files + 4
  sounds). `make check` stays green (stylua + luacheck on 26 files + check_toc +
  busted).

## [0.10.0] - 2026-09-23

**Assignment soundboards** requested by the raid lead: the moment a player
declares their orb composition — a click on one of the three buttons, in the
**real flow as in the `/gr sim inter` rehearsal** — the soundboard of **that**
state is played, **once**. One file per canonical state, three **silent
placeholders** shipped now (the real recordings are a plain file drop later, no
code change), one **new persisted preference** (`/gr sound on|off`) and one
**test entry** that does not need a fight (`/gr sound test 1v3r|2v2r|3v1r`).

### Added

- **Assignment soundboards** — `Core/Sound.lua`, PURE (no WoW API, testable out
  of game): `1V3R` → `Sound/assign-1v3r.ogg`, `2V2R` →
  `Sound/assign-2v2r.ogg`, `3V1R` → `Sound/assign-3v1r.ogg`, referenced through
  `Interface\AddOns\GideonRaid\Sound\<file>`. The sound of the **declared** state
  is played the moment the declaration is accepted, **once**: nothing is played
  before a declaration, and a repeated declaration of the same composition, a
  panel tick or a re-render can never double it. **CORRECT** re-arms the gate — a
  new click plays the sound of the composition it declares, even when it is the
  same one (natural behaviour, documented) — and so does every new intermission
  and every new rehearsal.
- **`PlaySoundFile` — the only audio call of the addon** — lives in
  `UI/Intermission.lua`, on the **`Master`** channel, behind a `type()` guard and
  a `pcall`: a missing file, a refused call or an absent API leaves the addon
  **silent, without a Lua error and without interrupting the rendering**
  (`tests/spec/sound_spec.lua` proves the declaration and the panel keep working
  when the call raises or when the API is gone; `tests/spec/guard_spec.lua` now
  fails if `PlaySoundFile` ever appears in `Core/`, outside `UI/`, or on a line
  that is not guarded).
- **`/gr sound`** (is the sound enabled, and how to change it), **`/gr sound
  on|off`** (a value that is not `on` or `off` is **REFUSED without persisting
  anything** — same mechanics as `/gr lang` and `/gr ping`) and **`/gr sound test
  <1v3r|2v2r|3v1r>`**: plays one soundboard on request, so the three files can be
  heard **without waiting for a fight**, and names the file it played. An unknown
  state is refused and nothing is played; a muted sound stays silent and says so
  (the test never contradicts the setting). `/gr inter status` now reports the
  setting, and the `/gr` help lists the new commands in both languages.
- **`Sound/assign-1v3r.ogg`, `Sound/assign-2v2r.ogg`, `Sound/assign-3v1r.ogg`**:
  **silent placeholders** (0.2 s of silence, Ogg Vorbis, mono 44.1 kHz) that keep
  the addon complete — and silent — until the raid lead delivers the real
  recordings. They are **listed in `GideonRaid.toc`** (the client does not load a
  sound that is not listed) and therefore packaged. `README.md` documents the
  replacement procedure (section *Replacing the three sounds*): same names, same
  folder, same format, **no code change**; a test also checks that `.pkgmeta`
  never excludes `Sound/`.
- **`GideonRaidDB.intermission.soundEnabled`**, `true` by default and resolved
  TOTAL (only an exact `false` mutes the sound: an absent field — an older
  SavedVariables — or a hand-edited value falls back to the default, so the soft
  migration of the existing saves is a no-op).

### Changed

- Tests: **228 → 260** (`sound_spec.lua`: 31 new; `guard_spec.lua`: 7 → 8;
  `load_spec.lua`: 49, `.toc` order and the new layer included), luacheck
  **22 → 24 files**, `.toc` **9 → 13 entries** (10 Lua files + the 3 sounds),
  and the test harness lists the whole `.toc` again
  (`wowenv.tocEntries`; `wowenv.tocFiles` keeps returning the Lua files only).
- Documents updated: `README.md` (soundboards section + replacement procedure +
  command list + real `make check` output), `docs/INTERMISSION-COACH.md`
  (configuration, commands, tests, in-game status) and `docs/TESTPLAN.md` (new
  §1f, step 2 items and a new §3.5d in-game protocol: right sound on the click,
  in EN and FR, no sound when the preference is off).

## [0.9.0] - 2026-09-23

Three corrections and one confirmed measurement from the raid lead's **fifth**
in-game test: the placement mode had **no way to validate the chosen position**
(no OK button, and the panel said "press OK" without one), the **rehearsal panel had
lost its three composition buttons** — its whole point — and the **button labels ran
out of their frames** (`SIMULATION : GROUPE INTER` came out of its button). The
self-ping gesture that the whole ANCHOR convention rests on was **confirmed in the
client** during the same pass.

### Added
- **`OK` button in placement mode** (new locale key `ui.ok`): it **saves the current
  panel position and closes the window** — the close cross and the **Close** button
  keep their meaning (they *cancel* the placement and save nothing). The panel's
  explanatory text now says exactly what to do, in both languages
  (`ui.setup.ready`): *"Place the panel where you want it to appear, then press OK:
  during the fight it opens by itself N s before each intermission and closes at the
  end."* / *"Place le panneau la ou tu veux qu'il apparaisse, puis appuie sur OK :
  pendant le combat il s'ouvre tout seul N s avant chaque intermission et se ferme a
  la fin."*
- **Button sizing in `Core/Layout.lua`**: `Layout.buttonSize(label, style, minWidth,
  minHeight)` measures a button from its **own label** (widest explicit line + inner
  margin `Layout.BUTTON_PADDING_X` for the width, number of lines of the font +
  vertical margin for the height, floored by a minimum clickable size), with
  `Layout.buttonNeeds` as the single source used by every button of the addon
  (composition buttons, `REDO`, `OK`, `Close`, and the four buttons of the main
  panel — which keep **one common size** so the row stays aligned). A new
  violation is reported: **a label wider than its button**.

### Fixed
- **The three composition buttons are back in the rehearsal** (`/gr sim inter`):
  they are part of the pure layout (`showChoices`) as long as no composition is
  declared, they are **clickable** (click -> state + ROLE + `PING: YES/NO` + ONE
  action line, then the three disappear and **CORRECT** brings them back), exactly
  like the real intermission flow.
- **Root cause of both disappearances: an element drawn without an anchor point.**
  Row buttons built by `Core/Layout.lua` could come out of the engine **without a
  `point`**, and `Frame:SetPoint(nil, ...)` **raises** in the client: `UI.ApplyLayout`
  stopped right there and **everything placed after that element was never applied**
  — which is how the composition buttons and the OK button ended up missing (the
  layout was computed, the panel just never drew them). The engine now **anchors
  every block and every row button**, `UI/Panel.lua` has a safety net on a missing
  anchor, and the test stub **refuses a non-string anchor like the client does**, so
  the regression can never pass CI again (removing the anchor in `Core/Layout.lua`
  makes the suite fail).
- **No button label touches or leaves its frame** any more, in English **and** in
  French, on **all five surfaces** (main panel, placement with `OK`, rehearsal with
  the three compositions, post-click with `REDO`, ping help): asserted label by
  label, plus the envelope of every button.

### Changed
- **Self-ping: CONFIRMED IN GAME (fifth in-game test, 2026-09-23)** — hovering **your
  own character frame / your health bar** and pressing the ping key **displays the
  ping on yourself** (raid lead: *"the ping on the health bar works fine to show it
  on myself"*). It was the last open assumption of the ANCHOR convention; it is no
  longer on the "to be confirmed" list (`README.md`, `docs/INTERMISSION-COACH.md`
  §9, `docs/TESTPLAN.md`, where only the **other players' view** and the **ping
  duration** stay to be watched with a second player).
- **The ANCHOR action line** spells the gesture out and stops being a slogan
  (`state.actionLine.1V3R`, both languages): *"PING: YES - hover YOUR OWN character
  frame (your health bar) then press your ping key (Warning): you ping yourself,
  stay put and jump on the spot."* The ping help window (`/gr sim ping`) uses the
  same wording.
- Tests: **219 -> 228** (`layout_spec.lua` 16 -> 22, `load_spec.lua` 46 -> 49),
  documents and their counts updated (`README.md`, `docs/INTERMISSION-COACH.md`,
  `docs/TESTPLAN.md`, including a new §3.5c in-game protocol for the fifth pass).

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

[0.13.0]: https://github.com/BathmanTv/Gideon/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/BathmanTv/Gideon/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/BathmanTv/Gideon/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/BathmanTv/Gideon/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/BathmanTv/Gideon/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/BathmanTv/Gideon/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/BathmanTv/Gideon/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/BathmanTv/Gideon/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/BathmanTv/Gideon/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/BathmanTv/Gideon/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/BathmanTv/Gideon/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/BathmanTv/Gideon/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/BathmanTv/Gideon/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/BathmanTv/Gideon/releases/tag/v0.2.0
