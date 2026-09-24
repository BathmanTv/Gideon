# Test plan — GideonRaid (4 steps)

Guiding principle: **everything that can be tested out of game is tested out of
game**, because in 12.x, during combat, the addon *cannot* read the values it is
interested in (Secret Values) and cannot exchange messages in an instance. What
remains verifiable in game is reduced to rendering and wiring. The plan is built
so that 90 % of the risk is eliminated before opening the client.

| Step | Subject | Tool | Frequency | Where |
|---|---|---|---|---|
| 1 | Pairing logic (pure) | busted + lua5.1 | on every commit | CI + local |
| 1b | Intermission Coach: orb convention + state machine (pure) | busted + lua5.1 | on every commit | CI + local |
| 1c | Language layer: strings, resolution, `/gr lang` | busted + lua5.1 | on every commit | CI + local |
| 1d | Simulation mode: rehearsal + ping help (pure) | busted + lua5.1 | on every commit | CI + local |
| 1e | Panel layout: stacking, overlap, overflow, button order (pure) | busted + lua5.1 | on every commit | CI + local |
| 1f | Soundboards: state → file table, one playback per assignment, one playback per intermission for the START sound, `/gr sound` preference (pure) | busted + lua5.1 | on every commit | CI + local |
| 1g | Which boss may OPEN the panel: pure allow-list of encounter ids (`/gr boss`), the DELIVERED default target (id 3445 + the two names), explicit clear vs never configured, name criterion, idlog ring, manual override (pure) | busted + lua5.1 | on every commit | CI + local |
| 1h | `/gr diag` health report: sound file list, SILENCE GATE of the audio probe, verdict per file, report lines (pure) | busted + lua5.1 | on every commit | CI + local |
| 2 | Addon loading (wiring, .toc, events, close cross, simulations) | busted + API stub | on every commit | CI + local |
| 3 | Rendering and ergonomics in game | test client | before every patch | WoW client |
| 4 | End-to-end GIDEON integration | Lua CLI + Discord | before every raid | VPS + Discord |

Single exit gate: **`make check`** (stylua + luacheck + toc + busted).

---

## Step 1 — Out-of-game unit tests of the pairing logic

**Goal**: the `ns.Pairing` engine is pure Lua 5.1, without any call to the WoW
API. It is therefore runnable by `lua5.1` and by `busted`, installed on the VPS
and on the GitHub runner.

**File**: `tests/spec/pairing_spec.lua` (11 tests; the repository total is
**331 tests**, spread over `intermission_spec.lua` (88 — including the resolution of
the DELIVERED target: never configured vs explicit `/gr boss clear` vs player
addition), `load_spec.lua` (49),
`bossfilter_spec.lua` (45 — which boss may open the panel: the delivered default
target, pure decision + wiring of `/gr boss` and `/gr idlog`), `sound_spec.lua`
(31 — soundboards and the intermission start sound), `layout_spec.lua` (22 — pure
panel geometry and button sizing), `locale_spec.lua` (21), `pingpolicy_spec.lua`
(20), `diag_spec.lua` (19 — `/gr diag`: silence gate, verdict per sound file,
report lines, and the proof that **no sound is ever played when the client is
audible**), `simulation_spec.lua` (14), `pairing_spec.lua` (11) and
`guard_spec.lua` (11)).

**How to run**:

```bash
busted
```

### Reference data set ("fixtures")

Roster of 20 players, 10 `ember` / 10 `frost`, provided by GIDEON:

```
Velna,ember      Bathman,frost    Kaela,ember     Ordan,frost     Sylvia,ember
Torgh,frost      Mira,ember      Nyx,frost       Rukh,ember      Dorian,frost
Ilya,ember       Pax,frost       Zerun,ember     Halda,frost     Coren,ember
Aster,frost      Bren,ember      Lumen,frost     Serka,ember     Vaelen,frost
```

File: `tools/sample_roster.csv`.

### Expected result (verified, real output)

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

10 pairs, 0 unpaired, exit code 0. The pairing is **alphabetical**
(Alice-Bob, then Yann-Zoe…): that is what guarantees that the same roster
produces exactly the same result, in the client as well as in GIDEON.

### Mandatory test cases (all present in `pairing_spec.lua`)

| Case | Input | Expected |
|---|---|---|
| nominal 3+3 | Tank1/Tank2/Dps1 ember, Heal1/Heal2/Dps2 frost | 3 pairs aligned by name |
| determinism | same roster, reversed order | identical results |
| normalization | `"  Ember "`, `"FROST"` | paired |
| extras | 3 ember, 1 frost | 1 pair + 2 `unpaired` `no_partner:frost` |
| missing debuff | player without `debuff` | `unpaired` `missing_debuff` |
| unknown debuff | `poison` | `unpaired` `unknown_debuff:poison` |
| invalid input | `"pas une table"` | `nil, err` (no crash) |
| duplicate | two players `A` | `nil, err` |
| `findPartner` | both ways + unknown | `"B"`, `"A"`, `nil` |
| `validateAssignment` | valid / malformed GIDEON block | filtered / rejected |

**Pass criterion**: step 1 green (`11 successes / 0 failures / 0 errors`).

---

## Step 1b — Out-of-game tests of the Intermission Coach (pure logic)

**Goal**: everything that depends on a business rule (color states, collisions,
intermission state machine, pre-pull view, configuration bounds) is tested
**outside the client**, because in game there is nothing to observe: the addon
reads no combat API.

**File**: `tests/spec/intermission_spec.lua` (84 tests) +
`tests/spec/pingpolicy_spec.lua` (20 tests, ping roles and policies).

**What is verified:**

| Family | Cases |
|---|---|
| Color states | the three states `1V3R` / `2V2R` / `3V1R` (label, green AND red counts, possible numbers, role, ping, complement, **the ONE action line**), "2" alone unambiguous, "1"/"3" ambiguous, deterministic order, non-mutable copy, **the French variant served explicitly when the active language is `fr`** |
| Normalization | `3V1R`, `2v2r`, `1 V 3 R`, `vert-vert-vert-rouge`, `vvrr`, `3 verts`, `1 vert 3 rouges`, dominant color alone ("vert", "majorité verte"), "2" accepted, **"1"/"3" alone refused with an "ambiguous" message**, empty/unknown/unusable input refused |
| Collisions | `3V1R+1V3R` OK both ways, `2V2R+2V2R` OK, `3V1R+2V2R` = 5 green = dead, `1V3R+1V3R` and `3V1R+3V1R` refused, comparison on an ambiguous number refused |
| Ping roles | `1V3R` = ANCHOR (pings; the action line spells out the **real gesture**: "hover YOUR OWN character frame then press your ping key (Warning), stay put and jump on the spot"; can be pinged by another player), `2V2R` = MIDDLE ("go to the middle / under the boss"), `3V1R` = CHASER ("run to a ping (a 1V3R)"), role independent of the number and of the policy |
| Ping policies | `anchors` (default): **only `1V3R` pings**; `color`: the three states ping with their own color (red/Warning, blue/OnMyWay, green/Assist); `none`: nobody pings; unknown value → `anchors`; the "PING: YES/NO" line and the wording of the action line follow the policy in EN and FR |
| **Ping keybind (no macro)** | candidate binding names per state (`PING_WARNING` / `PING_ONMYWAY` / `PING_HELP` / the `BINDING_` variants), **no candidate borrows another ping's key** (`PING_ATTACK` absent), `pingHint` with a key (`PING: Warning - press Q`), **without a key** and with an empty/absurd key (`set a keybind in Options > Keybindings`), refusal for a state that must not ping and on an ambiguous number, **injected resolver** (Core/ never reads the key), resolver raising / returning a non-string, and `buildMacro` == nil (**the macro generation has disappeared**) |
| **Ping labels (bilingual)** | `pingLabel` serving the client's own label in the active language — EN `Warning` / `On My Way` / `Assist`, **FR `Avertissement` / `En route` / `Aide`** (measured in game by the raid lead, 2026-09-22) — the **canonical identifier never changes**, an unknown/empty identifier returns a clean string (never `nil`), and the `color` policy line names the pings in the player's language only |
| Timeline | default values, **prepared values (46.3 / 148.9 / 251.5 / 353.2 s)**, bounds (visibility 1–10 s, duration > visibility, lead 0–10 s), `duration > visibility` |
| **Schedule (pre-computed)** | the raid lead's four values, normalization of a persisted schedule (sorted, positive only, 12 entries max), opening time `intermission − lead`, **nothing opens before the hour**, **one opening per intermission**, **no skip even with a huge `dt`**, reset, determinism |
| State machine | `IDLE → PENDING (lead) → VISIBLE (3 s) → DARK → DONE`, countdown 3/2/1/0, declaration during PENDING/VISIBLE/DARK, refusal before start, on an ambiguous number and after the end, **REDO (`clearDeclaration`) usable several times and idempotent**, `reset`, negative/non-numeric `dt` ignored, determinism |
| Pre-pull view | partner, role (composition), position, **ping to use deduced from the prepared composition and the policy**, meeting `2V2R+2V2R` OK / `3V1R+2V2R` DEAD / `1V3R+3V1R` OK / **unverifiable when the role stays ambiguous**, pairs sorted by name and insensitive to input order, plan absent, malformed plan, player absent, invalid assignment |
| **Minimal panel content** | state, role line, `PING: YES/NO` banner (ping color), **one** action line, **at most three short lines**, **the three choice buttons disappearing as soon as one is clicked** (`showButtons` false / `showRedo` true, CORRECT bringing them back, empty state), and the **absence** of the old verbose lines (ROLE ORDER / PING POLICY / STATE THAT JOINS YOU / caveats) |
| **Placement view** | headline, drag instructions, ping keybind reminder, lead reminder, plan or "no plan" line |
| Configuration | fresh defaults (no alias between accounts — **panel positions included**), scale/visibility/duration/**lead** bounds, inconsistent types ignored, `pingMode` default `anchors` and any unknown value falling back to `anchors`, **no `macroTargetToken` any more** |
| **Panel preferences** | `/gr lock` / `/gr unlock` persisted (`lockPanel`), **`lockPanel` false by default** (the main panel is draggable), a **total lock resolver** (only a real boolean locks, anything else unlocks) and a **total position resolver** (only a known `Config.POSITION_POINTS` anchor survives; a hand-edited `point` falls back to `CENTER`), and the **one-time migration** that unlocks a legacy `lockPanel = true` once (no schema marker) before respecting the player's own choice |
| Command `/gr ping` | `ping` prints the policy and its meaning, `ping color|none` persists it and changes the panel (the action line and the ping to use), unknown value refused **without writing anything**, value reloaded after a `/reload` simulation |

**Out-of-game preview** (verifiable by hand, without a client — the developer CLI
keeps printing French):

```
$ lua5.1 tools/intermission_cli.lua all            # les 3 états + ligne d'action
$ lua5.1 tools/intermission_cli.lua roles          # les 3 états × les 3 politiques
$ lua5.1 tools/intermission_cli.lua run            # rejeu du planning pré-calculé
$ lua5.1 tools/intermission_cli.lua 1              # -> REFUS : numéro ambigu
$ lua5.1 tools/intermission_cli.lua 3V1R color Q   # politique explicite + touche simulée
$ lua5.1 tools/intermission_cli.lua pair 3V1R 2V2R # -> 3V1R+2V2R : MORT (5 verts = 5g)
$ lua5.1 tools/intermission_cli.lua plan Velna none
```

---

## Step 1c — Out-of-game tests of the language layer

**Goal**: prove that the addon is bilingual with English as the official
language, that French is served automatically on a frFR client, and that no
string can ever raise.

**File**: `tests/spec/locale_spec.lua` (21 tests), in three blocks:

1. `Locale.resolve` (pure): default English, `auto`/`nil` following the client
   (`frFR` → French, `enUS`/`deDE` → English), an explicit preference beating the
   detection, any unknown value falling back to English;
2. `Locale.t` / `Locale.format`: the English variant by default and the French
   one on demand (including a full `frFR` code), a key present in one language
   only still served, a missing key returning the key itself **without raising**,
   `format` total even without arguments, `setActive` falling back to English,
   determinism;
3. the wiring end to end (with the API stub): English by default, `GetLocale()`
   returning `"frFR"` serving French (panel headline and buttons included),
   `"enUS"`/`"deDE"`/`"esES"` serving English, a **missing `GetLocale`** not
   raising, `/gr lang` printing the detected + effective + preferred language and
   the rule, `/gr lang fr|en|auto` persisted in `GideonRaidDB.locale` and applied
   immediately, an unknown value refused and persisting nothing, a hand-edited
   (`"Klingon"`) preference falling back to `auto`.

**Pass criterion**: `locale_spec.lua` green + `intermission_spec.lua` green in the
default (English) language.

---

## Step 1d — Out-of-game tests of the SIMULATION mode (pure logic)

**Goal**: prove that the two simulation entries (a **rehearsal** of the intermissions
and the **ping help** window, fourth in-game feedback) are **pure logic**, **with no
clock of their own**, and **isolated from the real flow**: a rehearsal must never
arm, disarm or advance the `ENCOUNTER_START` timeline, and must never publish a
decision the diagnostic kit could read as a real one.

**File**: `tests/spec/simulation_spec.lua` (14 tests) + the isolation guard in
`tests/spec/guard_spec.lua`.

**What is proven out of game:**

- `Core/Simulation.lua` contains **none** of `ENCOUNTER_START`,
  `Intermission.newRun`, `advanceRun`, `resetRun`, `RegisterEvent` (guard test), nor
  `GetTime` / `math.random` / any WoW API (the `Core/` purity guard covers it);
- the **rehearsal** is a **single cycle the player closes**: `newRun` takes **no
  option at all** (the former `cycles=N` is gone), it opens **right away** (no
  3 s delay, no countdown line), it is closed by the player (`closeRun`), it is
  **idempotent**, and it never writes anything to the SavedVariables;
- `forRehearsal` produces the rehearsal view: a **two-line** banner
  (`SIMULATION - NO BOSS, NO RAID` + `SINGLE REHEARSAL - YOU CLOSE THE PANEL
  YOURSELF`), a headline that **replaces the combat countdown** (asserted to contain
  no `%` and no ` s`, because there is no boss and therefore no orb to read), the
  explanatory note, and it **does not modify** the snapshot it receives (state, ping
  banner, composition buttons and REDO stay what the real module computed);
- the **ping help view**: the four pings to bind (`Ping, Warning, On My Way,
  Assist`), the gesture (`hover YOUR OWN character frame`, `you ping yourself`), the
  group reminder and the explicit **"the addon CANNOT detect a ping"** line; the
  bound key is carried by the **injected resolver** and the line honestly reads
  `no key bound` when the resolver is absent, raises or returns nonsense (never an
  invented shortcut); the view is **stateless** (it counts nothing and times
  nothing);
- the **whole `/gr sim` argument** parsed by `parseCommand`: `inter` with its aliases
  (`group`, `groupe`), `ping`, `stop`, and the **refusal of any trailing option**
  (`/gr sim inter cycles=3`), of an unknown sub-command and of an invalid argument —
  the refusal always comes with a **message**;
- every simulation string exists in **both** languages (`locale.t` pairs), and the
  rehearsal banner is the two-line one in both languages (no leftover cycle counter).

**How to run**:

```bash
busted tests/spec/simulation_spec.lua
busted tests/spec/guard_spec.lua
```

**Pass criterion**: both green, `make check` green (331 tests).

---

## Step 1e — Out-of-game tests of the PANEL LAYOUT (pure geometry and button sizing)

**Goal**: prove, **out of game and in both languages**, that no panel can draw one
element on top of another or run text over its frame — the two bugs of the fourth
in-game test (the French labels leaving the main panel, the big state drawn over the
SIMULATION banner) — and that **no button label ever comes out of its button** and
that **no element is drawn without an anchor point** — the two bugs of the fifth
in-game test (the text leaving the buttons, the composition buttons and the OK
button missing from the panel).

**File**: `tests/spec/layout_spec.lua` (22 tests). The geometry is computed by
`Core/Layout.lua` (pure Lua 5.1, no WoW API) and **applied as is** by `UI/Panel.lua`
(`UI.ApplyLayout`).

**What is proven out of game:**

- the engine **stacks** blocks one under the other (`top = previous.bottom - gap`),
  never at an absolute offset, so two blocks can never share a Y band; an extra
  `gapBefore` is available for a utility button that must be visually separated;
- **every block and every row button carries its anchor point** (`point`), and
  `tests/support/wowapi_stub.lua` **refuses a non-string point like the client
  does**: a nil point raises in game and the applier stops right there, which is
  exactly how the three composition buttons and the OK button disappeared (fifth
  in-game test). Removing the anchor from `Core/Layout.lua` makes the suite fail;
- **button sizing**: `Layout.buttonSize` measures **every** button from its label
  (widest explicit line + inner margin for the width, number of lines + vertical
  margin for the height, floored by a minimum size), and the tests check, in
  English **and** in French, the five surfaces of the addon (main panel, placement
  with the `OK` button, rehearsal with the three compositions, post-click with
  `REDO`, ping help) — for every button: the label fits **with its margin** both
  ways;
- the **violation report** really fires: a hand-built overlapping layout is reported
  (`overlap`), a block running over the frame is reported (`border`), a block whose
  **longest word** does not fit is reported (`wider than its block`), a block drawn
  under the close cross is reported too, and so are a **missing anchor** and a
  **label wider than its button**;
- the **frame follows the content**: width ≥ the longest label + padding, height
  computed from the stacked blocks, and a longer body **grows** the frame instead of
  overflowing it;
- the **main panel**: the button order is the constant
  `Layout.MAIN_PANEL_ORDER = { "place", "simPing", "simInter", "lock" }` (asserted, so
  a future change cannot silently reorder the evening flow), the three flow buttons
  share **one width** and a **regular spacing**, and the LOCK/UNLOCK utility is
  separated by a **bigger gap**;
- **no label touches or leaves the frame** in English **and** in French, on the
  locked and unlocked variants, and with a long body (the out-of-game plan);
- the **intermission panel** is checked in **both languages** in every phase
  (rehearsal with the two-line banner, dark room with the big state, placement mode):
  the big state is always **below** the banner, then the headline, then the ping
  banner, then the body, then the action row — the exact fourth-test bug;
- the **placement mode** carries the `OK` button (measured, anchored, next to
  `Close`, never overlapping it) — the fifth-test request;
- the **rehearsal** carries the **three composition buttons** (their Core labels, one
  measured size for the row, anchors, minimum size) as long as nothing is clicked,
  and when the layout does not contain them (after a click) they are **not part of
  the layout at all**: `UI.ApplyLayout` hides and empties every element the layout
  does not mention, so nothing can be drawn on top of the banner and no stale `1V3R`
  can survive a CORRECT;
- the frame width is **wider than the old 300 px** (main panel ≈360 px, intermission
  panel ≈650 px) precisely so the French labels fit — in the frame **and** in the
  buttons.

**How to run**:

```bash
busted tests/spec/layout_spec.lua
```

**Pass criterion**: green, `make check` green (331 tests).

---

## Step 2 — Addon loading tests

**Goal**: prove that the addon loads in the `.toc` order, that the events do not
raise, and that the rendering really reads `GideonRaidDB`. Only the frames are
mocked (`tests/support/wowapi_stub.lua`): no combat API is mocked, because no
file calls one. The stub does define `GetLocale` (the real client always has it)
so that the language wiring is exercised.

**File**: `tests/spec/load_spec.lua`.

Loading goes through `wowenv.loadAddon()`, which **reads the `.toc`** and loads
its files in order: a forgotten, renamed or badly ordered file makes the test
fail (that is the number one addon bug).

What is verified:

1. the 11 Lua files of the `.toc` are loaded in order (`Core/Locale.lua` second,
   `Core/Sound.lua` third, `Core/BossFilter.lua` fourth and **before
   `Core/Config.lua`** — it resolves the auto-open allow-list —, `Core/Layout.lua`
   before the `UI/` layer, before the other `Core/` modules), and the 10 layers
   (`ns.Locale`, `ns.Sound`, `ns.BossFilter`, `ns.Pairing`, `ns.Config`,
   `ns.Intermission`, `ns.Simulation`, `ns.Layout`, `ns.UI`, `ns.GR`) are exposed —
   the four sound files listed in the `.toc` are checked separately
   (`sound_spec.lua`: `.toc` entries, files on disk, packaging);
2. `ADDON_LOADED` on `GideonRaid` initializes `GideonRaidDB` with the defaults
   (including `intermission` and `locale`);
3. `ADDON_LOADED` on **another** addon does not touch the SavedVariables;
4. `PLAYER_LOGIN` without an assignment does not raise;
5. `PLAYER_LOGIN` **with** an assignment displays the plan (partner, role,
   position, `2V2R+2V2R` meeting) in the panel;
6. the slash handler (`/gr show`, `/gr status`, `/gr plan`, `/gr inter status`,
   unknown command) answers without raising;
7. `ENCOUNTER_START` (with its instance arguments) **arms the schedule without
   opening the panel** — and it does so **only for the configured target boss**:
   with no target configured (the default) an encounter arms **nothing**, and the
   chat explains the safe default (`/gr boss <id>`, `/gr inter on`). The four
   arguments are handed to `Core/BossFilter.observeEncounter`, which reads them
   **under `pcall`** and only to compare the encounter id (and the optional name);
   a `watch` test makes `evaluate` itself raise and proves the panel then stays
   closed instead of propagating the error;
8. the panel **opens by itself** before the first intermission (444 ticks of
   0.1 s ⇒ 44.3 s), shows the 3 s countdown, then "room darkened", then
   **closes by itself** at the end of the intermission;
9. the three buttons carry the visible composition (number as a hint) and a click
   displays the state, the role, `PING: YES/NO` and **one** action line;
10. **REDO** brings the three choices back and can be used several times, in a row
    and after a new click;
11. the **ping key** is displayed when the player bound one (`PING: Warning -
    press Q`), and the "set a keybind" line otherwise, **including when
    `GetBindingKey` raises**;
12. the panel **reopens** at the next intermission of the schedule;
13. `ENCOUNTER_END` closes the panel, disarms the schedule and no opening happens
    afterwards;
14. the **placement mode** (button of the main panel or `/gr inter place`) shows
    the panel, saves the position on **OK** and closes; **Close** cancels;
15. the main panel shows the discreet "no out-of-game plan" line and **never** a
    non-existent command;
16. disabling (`/gr inter off`) is honoured, placement included;
17. the panel displays no dynamic value (no combat API call);
18. the **button order of the main panel** is the one a test freezes (PLACE
    INTERMISSION PANEL, SIM: PING YOURSELF, SIM: INTERMISSION GROUP, then the
    LOCK/UNLOCK utility, separated by a bigger gap) **in both languages**;
19. the rehearsal **opens right away** (no ticker is even created: the panel cannot
    close by itself) and it is the **player** who closes it (Close button or cross),
    with an honest chat report; the two-line `SIMULATION` banner is on screen and the
    combat countdown line is gone;
20. the **applied layout** keeps the big state **below** the banner in English and in
    French (the recorded anchors are compared), and an element that is not part of the
    current layout is **hidden and emptied** (no stale text after CORRECT);
21. the ping help window (`/gr sim ping` **and** `/gr pinghelp`) carries the binding
    path, the self-ping reminder, the bound keys (or `no key bound`) and the explicit
    "cannot detect a ping" line, and it closes through its button, its cross or
    `/gr sim stop`;
22. the **placement text** says exactly what to do (fifth in-game feedback): *place
    the panel where you want it to appear, then press OK: during the fight it opens
    by itself* — checked in English **and** on a `frFR` client — and the **OK** button
    really saves the position and closes;
23. the **rehearsal** shows the **three composition buttons** (fifth in-game feedback:
    the panel had lost them) and each one **works**: `1V3R` → state + `ROLE: ANCHOR` +
    `PING: YES` + the ANCHOR action line, `2V2R` → `ROLE: MIDDLE` + `PING: NO` +
    "go to the middle", `3V1R` → `ROLE: CHASER` + `PING: NO` + "run to a ping"; the
    three disappear on the click and **CORRIGER brings them back**; each button is
    **anchored** (`TOPLEFT`) and **sized on its label**;
24. the **stub refuses a non-string anchor** exactly like the client
    (`tests/support/wowapi_stub.lua`): the whole panel flow is exercised with that
    strictness, so an element without an anchor point (the fifth-test bug) can never
    pass CI again;
25. **the assignment soundboard** (Step 1f, `sound_spec.lua`): the sound of the
    **declared** composition is played **once**, on the `Master` channel, with the
    file path of that state; **nothing** is played before a declaration, a repeated
    declaration of the same composition does not replay it, **CORRECT** re-arms it,
    a new intermission and a new rehearsal re-arm it, and `/gr sound off` silences
    it while the panel keeps rendering;
26. **`PlaySoundFile` is called from `UI/` only, under `pcall`** — a call that
    raises or an absent API leaves the addon silent **without a Lua error** and
    without interrupting the rendering (`guard_spec.lua` fails if the identifier
    appears in `Core/`, outside `UI/`, or unguarded);
27. **the four sound files ship with the addon**: they are listed in
    `GideonRaid.toc` (the client does not load an unlisted sound), present on disk
    (real Ogg Vorbis), and never excluded by `.pkgmeta` — a test fails if one of
    them disappears;
28. **the AUTO-OPEN BOSS FILTER** (Step 1g, `bossfilter_spec.lua` +
    `intermission_spec.lua`): the **target ships with the addon** — a client that
    **never configured anything** (empty SavedVariables) opens the panel on the
    **delivered** id `3445` and on the two delivered names (the English official one
    and the French one measured in game), **on every difficulty**, with no command
    typed and **no warning at login**; an id added by a player **adds itself** to the
    delivered one and `/gr boss list` labels each entry (*addon default* / *added by
    you*); `/gr boss 3445` is idempotent; `/gr boss clear` is an **explicit** state
    (`bossTargetCleared`, an exact `true` only) that **drops the delivered default**
    too, so **nothing opens** any more until an id is given again — and a
    hand-edited `bossTargetCleared = "oui"` does **not** drop it; `/gr boss` refuses
    a value that is not a positive integer **without persisting anything**; a boss
    that is not the target is refused (`noMatch`); `/gr idlog on` prints the
    `encounter seen: id=…` line and memorizes it (10 max); `/gr inter on` arms the
    manual override for the next encounter **whatever the boss** and it is consumed
    at the end of it; and a decision that raises (a secret value) stays a **refusal**
    with no Lua error;
29. **the intermission START sound** (Step 1f): `/gr sound test start` names and
    plays `intermission-start.ogg`, an intermission plays it **once** (the same
    intermission can never sound twice) and the **next** one plays it again, a
    rehearsal plays it once per cycle, and `/gr sound off` silences it too;
30. **the `/gr diag` health report** (Step 1h, `diag_spec.lua`): the four sound files
    are listed in the canonical order of `Core/Sound.lua` with the path the addon
    really plays; the **silence gate** only allows the audio probe when the Master
    channel is **enabled** (a disabled channel would answer "nothing will play" for a
    present file — a lie) **and** its volume is **0** (mathematically inaudible), and
    it is TOTAL (out of game, an unreadable CVar, a volume that cannot be parsed, a
    raising or absent `PlaySoundFile` → **no probe, no lie, no Lua error**); the
    report prints the effective target, its source, the delivered default, the idlog
    state and the ping policy; each file gets a verdict line (*playable* / *not
    playable* / *not tested* / *unknown*) and the negative case names the cause and
    the fix (**restart the client**, list the file in the `.toc`); and in the wiring,
    `/gr diag` calls `PlaySoundFile` **zero** times when the client is audible or
    silent, and exactly four times (the four paths, channel `Master`) when the volume
    is 0 — while writing **nothing** to the SavedVariables.

**`.toc` verification** (`tools/check_toc.py`, in CI):

```
$ python3 tools/check_toc.py GideonRaid.toc
OK GideonRaid.toc
  Interface  : 120100
  Version    : @project-version@
  SavedVar   : GideonRaidDB
  Fichiers   : 16
```

It checks: `.toc` name == `package-as`, `## Interface:` numeric and ≥ 120100,
presence of `Title/Notes/Version`, and **the existence on disk of every listed
file** (that is the number one addon bug: a listed file that is missing, or a `/`
instead of a `\`).

**Lua 5.1 syntax verification** (the real client runtime):

```
$ make syntax
OK ./GideonRaid.lua
OK ./UI/Panel.lua
OK ./Core/Locale.lua
OK ./Core/Config.lua
OK ./Core/Pairing.lua
OK ./tests/support/wowapi_stub.lua
OK ./tests/support/wowenv.lua
OK ./tests/spec/load_spec.lua
OK ./tests/spec/pairing_spec.lua
OK ./tools/pairing_cli.lua
```

**Pass criterion**: step 1 + 1b + 1c + 1d + 1e + 1f + 1g + 1h + step 2 green (331 tests), `luacheck .` = 0 warning.

### Deeper loading tests (optional, if needed later)

Two harnesses exist and are real (verified on 22/09/2026):

| Harness | Nature | Usage | VPS constraint |
|---|---|---|---|
| [Osso/wow-ui-sim](https://github.com/Osso/wow-ui-sim) | Headless WoW UI simulator, tags up to `12.0.5` | an addon's `run-tests`, frame-tree screenshots, `assertTableEquals` assertions, async tests through `C_Timer.After` | Requires **docker**, whose daemon is **not started** on this VPS → use it **in GitHub Actions** (`uses: osso/wow-ui-sim@12.0.5`) |
| [wowless/wowless](https://github.com/wowless/wowless) | Headless Lua + FrameXML interpreter | Loading the real client code | **Pre-alpha** ("errors are almost certainly in Wowless, not in your addon"), heavy CMake/vcpkg build → not retained |

Decision: `wow-ui-sim` is the right candidate to automate step 3 **when** the need
arises (for example to check that the panel shows up). It is not enabled in the CI
by default, to avoid depending on a GPL-3 component that changes fast in the
middle of the 12.x transition.

---

## Step 3 — Manual in-game tests (protocol)

**Prerequisites**: Midnight 12.1.0 client (Interface `120100`), addon installed in
`Interface/AddOns/GideonRaid/`, `GideonRaidDB.assignment` populated by GIDEON.

### 3.0 Pre-flight: no secret value

- Tick "Display Lua errors" and **play 10 minutes of a real raid**. No
  `attempt to compare a secret value` error, no `COMBAT_LOG_EVENT` error (that
  second error means a forbidden event is registered → blocking regression).
- Console command: `/console scriptErrors 1`.

### 3.1 Out of combat, out of instance — loading (2 min)

1. Hand-write `WTF/Account/<ACCOUNT>/SavedVariables/GideonRaid.lua` with a test
   `assignment` block (2 pairs, one of them containing the character).
2. `/reload` → `/gr` → check: "Your partner: <Name>" + the list of pairs.
3. `/gr status` → "assignment OK, 2 pairs".
4. `/gr reset` → then `/reload` → the panel shows "No GIDEON assignment."
   without error.

### 3.2 Out of combat, inside the instance — reading in a raid

5. On a raid boss **before the pull**: `/gr` must display exactly the same pairs
   as outside the instance. *Critical test*: this is where we prove that the
   addon does not depend on any forbidden channel in an instance.
6. During the intermission: check that the panel stays readable and **displays no
   dynamic value** (health, aura). If it displays one, it is a design regression
   → step 1 failed.

### 3.3 Robustness

7. Deliberately incomplete roster (a partner has `quit`): the pair must appear
   as-is **without** shifting — the addon has nothing to recompute.
8. `/gr` typed 20 times: no duplicated frame, no slowdown.
9. Move the panel (drag), `/reload`, check the position is kept; then `/gr lock`
   (the panel must refuse to move and say so), `/gr unlock` (it moves again) and
   `/gr resetposition` (everything comes back to the center).
10. Test with a second character (another `SavedVariablesPerCharacter`): no data
    leak between characters.

### 3.4 What is NOT testable in game (to be documented in the report)

- We do not test the *correct display of the other player's aura*: the client
  does not give it to us.
- We do not test "live" synchronization: no addon→addon channel in an instance.
  Synchronization is asynchronous **by design** (GIDEON → file → `/reload`).
- For the *Entombed Sentinels* intermission: we do **not** test that the addon
  "knows" the other players' orbs — it does not and never will (secret values).
  The only possible test is that **what the player sees on their screen** matches
  what they declared.

### 3.5 In-game protocol — Intermission Coach (to be done before the first pull)

**Reference facts (established in game before this protocol):** the native ping
keybinds DO exist, separately, under « Ping / Attaque / Avertissement / En route /
Aide » (+ « Activer le ciblage de ping ») — measured in game by the raid lead,
2026-09-22 — and an addon ping or a ping macro is **refused** by the client
("this action can only be used by the Blizzard UI"). The per-player ping limit is
**3 pings in a row, then about 5 s of wait, then 3 again** (same measurement).

| # | Action | Expected |
|---|---|---|
| 1 | `/gr` out of instance | "Your partner: …" + list of pairs (`assignment` block prepared by GIDEON); with no plan: `No out-of-game plan loaded (optional).` and **no** mention of a Discord command |
| 2 | `/gr plan` | the detailed plan in the chat (role, position, meeting) |
| 3 | `bindings`: Options > Keybindings > GideonRaid, assign a key | the binding shows up; the key opens/closes the panel |
| 3b | **Before the pull**: `/gr` → **PLACE INTERMISSION PANEL** (or `/gr inter place`) | the intermission panel appears, can be **dragged** where the player wants it; the body recalls the ping keybind and the lead **and says exactly what to do** (fifth in-game feedback): *place the panel where you want it to appear, then press OK: during the fight it opens by itself*; the **OK** button is on screen (right of the frame, next to **Close**), **saves the position and closes** the panel. **Close** and the **X** cancel instead. Re-doable, and usable several times |
| 3c | Bind each ping: Options > Keybindings > **ping system** (or Raccourcis) | one key per ping exists (Avertissement / En route / Aide) — **already measured**; `/gr inter ping` then shows `PING: Avertissement - press <key>` if the binding command name matches a candidate (TBD item 1 of `docs/INTERMISSION-COACH.md` §9) |
| 4 | **Name the target first**: `/gr boss <id>` with the id captured per §3.5e (until then, nothing opens by itself). Then enter *Entombed Sentinels* and pull the boss | `ENCOUNTER_START` **arms the schedule** (the panel does **not** open at the pull) and the chat confirms the number of planned intermissions and the 2 s lead. Only the configured target arms anything; the four arguments are read **once, under `pcall`**, and only to compare the encounter id / name (§3.5e) |
| 4b | Wait for the first intermission | **1–2 s before** it, the panel opens **by itself** with \"GET READY: 2 s\" then the 3 s countdown, and the **intermission start sound plays once** (§3.5d 8b–8e) — the timing (≈46.3 s, then 148.9 / 251.5 / 353.2 s) is TBD item 3 of §9 |
| 5 | During the 3 s of visibility | the reminder displays "LOOK AT THE ORB COLOR ABOVE THE HEADS: 3" then 2, 1 (French on a frFR client) |
| 6 | Count your orbs, click `1` / `2` / `3` composition button | the panel shows **the essential only**: the state in very large type, **ROLE** (ANCHOR / MIDDLE / CHASER), **"PING: YES/NO"** (colored) and **ONE** action line — no role order, no policy line, no caveat, no paragraph — and **the three buttons disappear at once** (only the result and CORRECT stay) |
| 7 | Press the **native ping key** of the instructed ping (once) — for a `1V3R` ANCHOR: **hover YOUR OWN character frame first** | the ping goes out (the addon does not ping, and never with a macro); **never ask for a burst** (3 pings in a row max per player). The action line states the gesture: `PING: YES - hover YOUR OWN character frame (your health bar) then press your ping key (Warning): you ping yourself, stay put and jump on the spot` |
| 7b | Click a wrong composition, then **REDO**, then the right one (twice) | the three buttons come back, the panel returns to the choice state, the correction is unlimited and never leaves a stale state |
| 8 | Check after 3 s | "ROOM DARKENED": the panel stays readable, no dynamic text |
| 8b | End of the intermission | the panel **closes by itself** (`durationSeconds`, 20 s by default), even with no click |
| 8c | Next intermission | the panel **reopens by itself**, choice state reset — same cycle as §4b/6/7b/8b |
| 9 | End of combat | `ENCOUNTER_END` closes the panel and disarms the schedule: no further opening |
| 10 | `/console scriptErrors 1` over 10 min of raid | **no** Lua error (typically `attempt to compare a secret value` = blocking regression), and **no** "action usable only by the Blizzard UI" error (that one means a forbidden ping call came back) |
| 11 | `/gr lang` on a frFR client and on an enUS client | detected language correct, text in the right language, and the **ping label follows it** (`PING : Avertissement` in French); TBD item 6 of `docs/INTERMISSION-COACH.md` §9 |
| 12 | `/gr ping` then `/gr ping anchors|color|none`, then re-open the intermission panel | the header banner switches between **PING: YES** and **PING: NO** and the action line follows the policy (never a contradictory order for the same role) — the policy itself stays **out** of the panel |
| 13 | Send a burst of pings yourself (3 in a row, then a 4th) | **CONFIRMED MEASUREMENT, 2026-09-22**: 3 in a row are accepted, then the client waits about 5 s before accepting 3 again. No longer to be confirmed — it is the reference for the ping budget (§2.1 of `docs/INTERMISSION-COACH.md`) |
| 14 | With `anchors`: one anchor pings, several CHASERS run to it | the ping stays visible **long enough** after the room darkens, and it shows on the **raid frame** of the anchored player (raid frame pings since patch 12.1) — the remaining thing to watch in game (with the self-ping already confirmed, row 14b) |
| 14b | **SELF-PING — CONFIRMED IN GAME (fifth in-game test, 2026-09-23).** The ANCHOR hovers **their own character frame**, presses the ping key and self-pings | **the ping is displayed ON YOURSELF** — the raid lead's words: *"the ping on the health bar works fine to show it on myself"*. No longer to be confirmed. What is left **to watch with a second player**: does that self-ping show for the **others**, **above the character** (which is what a CHASER runs to), and **how long** does it stay visible after the room darkens (world frame, raid frames)? The addon cannot detect a ping, so only the players can answer that part |
| 14c | Move the **main panel** (or ask the other players to move theirs) during the raid, then `/reload` between two intermissions | the panel is draggable (it was frozen before), the position is kept after the `/reload`, and `/gr lock` keeps it in place if it hides something |
| 15 | Count the pings in the raid with the `anchors` policy (expected ~8) versus `color` (expected ~20) | the `anchors` policy keeps the channel readable: at most one ping per anchor, 4 per side, **one ping per player per intermission** — far from the 3-per-5-s client limit |

### 3.5b In-game protocol — close cross and SIMULATION mode (5 min, ALONE)

**Goal**: validate the two additions requested by the raid lead (close cross on both
panels, simulation mode) **without a boss, without a raid and without pulling
anything**. Everything else about the simulation is already proven out of game
(Step 1d): what is verified here is the **rendering** and the **real timer cadence**.
Keep `/console scriptErrors 1` on: no Lua error is allowed here either.

| # | Action | Expected |
|---|---|---|
| 1 | `/gr`, then hover the **X** in the top right corner | a short tooltip reads `Close` (English) / `Fermer` (French on a frFR client); the X itself is the label from `Core/Locale.lua` |
| 2 | Click that **X** | the main panel closes; `/gr` brings it back (the plan and the buttons are unchanged) |
| 3 | `/gr inter place`, then click the **X** of the intermission panel | the placement is **cancelled** exactly like the Close button: the panel closes and **no** position is saved; `/gr inter place` works again |
| 4 | `/gr inter start` (or wait for a real intermission), then click the **X** | the panel hides; the intermission clock keeps running, the panel **closes by itself** at the end and **opens again at the next intermission** (nothing was disarmed) |
| 5 | `/gr sim inter` (same as the **SIMULATION** button of the main panel) | the chat states `SIMULATION (no boss, no raid): the intermission panel opens RIGHT AWAY. Click your composition, then close it yourself (X or Close button). The ENCOUNTER_START timeline is NOT armed.`; the panel opens **IMMEDIATELY** (no delay) with the **two-line** banner `SIMULATION - NO BOSS, NO RAID` / `SINGLE REHEARSAL - YOU CLOSE THE PANEL YOURSELF` **and the three composition buttons** |
| 6 | Click a composition | state in very large type **below the banner**, `ROLE`, `PING: YES/NO` and ONE action line, exactly like a real intermission; **the three buttons disappear** (they are not drawn anywhere, in particular not on the banner); **CORRECT** brings them back with an **empty state** (no stale `1V3R` left on screen) |
| 7 | Wait without clicking | the panel **stays open**: nothing closes it, nothing relaunches it. It is **you** who closes it (X or Close) - the chat then reports `Simulation closed (no boss, no raid, nothing was published).` |
| 7b | Watch the whole rehearsal | no line contradicts the situation: no countdown (`... : 0 s`), no `SIMULATED INTERMISSION 1/1`, and the banner, the state, the role and the action lines are **all separated** (nothing drawn over the banner, in French as well: `/gr lang fr`) |
| 8 | After the rehearsal, `/gr inter status` | the **real** module is untouched: phase `IDLE`, schedule **not armed**, no decision published (the diagnostic kit must see nothing) |
| 9 | `/gr sim ping` (or `/gr pinghelp`) | the **help window** opens at once (draggable, position kept) with `PING: YES = PING YOURSELF`, the binding path (`1. Bind one key per ping: Options > Keybindings > Ping (Ping, Warning, On My Way, Assist)`), the operational reminder (`2. During the boss, ... hover YOUR OWN character frame ... then press your key: you ping yourself, where you stand.`), the `Keys found for your pings:` list (`Warning = Q`, or `no key bound` while the binding command name is still unknown — TBD item 1 of `docs/INTERMISSION-COACH.md` §9), the group reminder and the explicit **"the addon CANNOT detect a ping"** line. **No countdown, no `PING PLACED`, no step progression** |
| 10 | Hover **your own character frame** with the mouse and press the real ping key while **grouped** | a ping appears **on you** (you pinged yourself) — **CONFIRMED IN GAME (fifth in-game test): "the ping on the health bar works fine to show it on myself"**. The window claims nothing else: the addon **counts nothing** and detects nothing — only your screen tells you |
| 10b | Redo the gesture **alone** (not grouped, no raid) | **nothing** appears on screen and the addon does not claim otherwise: this is expected and stated on the frame |
| 11 | Move the mouse **away from your character frame** (over the world, or over another player's frame) and press the same key | the ping lands where the **mouse** is (world position, or on the other player) instead of on you — that is the measurement that made the gesture explicit: **the ping follows the mouse, so the ANCHOR must hover their own frame** |
| 12 | Start a rehearsal, then close it with `/gr sim stop` (or the **Close** button, or the **X**, or the close button of the ping help window) | it closes at once with an honest report (`Simulation closed (no boss, no raid, nothing was published).`); `/gr sim stop` again answers `No simulation running.` |
| 13 | Start a simulation, then **pull a boss** (or `/gr inter start`) | the simulation is **stopped at once** by `ENCOUNTER_START` and the normal schedule is armed **exactly once** (no double state, no panel left open) |
| 14 | `/gr sim`, then `/gr sim bidon`, then `/gr sim inter cycles=3` | the help lists the three commands and `/gr pinghelp`; an unknown sub-command **and a trailing option** are **refused** with a message (never guessed, and no panel opens) |
| 15 | Drag the **main panel** (`/gr`), then `/reload`, then `/gr` again | the panel moves with the left button (it was **frozen** before: `lockPanel` hard-coded to `true`), the position survives the `/reload` and the panel reopens **where it was left** |
| 16 | `/gr lock`, then try to drag it; `/gr unlock`, then drag it again | locked: the panel does not move and the chat explains it (the LOCK PANEL button shows UNLOCK PANEL); unlocked: the drag works again and the choice survives a `/reload` |
| 17 | Drag the **ping help window** (`/gr sim ping`), close it, open it again | the window is draggable and **reopens where it was dragged** (position persisted like the main panel) |
| 18 | `/gr resetposition` | the main panel, the intermission panel and the ping help window all come back to the **center** of the screen |
| 19 | Open the main panel in French, then in English (`/gr lang fr` / `/gr lang en`) | **no label touches or leaves the frame** in either language and the four buttons keep the order **PLACE LE PANNEAU -> SIMULATION: TE PINGER -> SIMULATION: GROUPE INTER -> VERROUILLER** (the utility separated by a small space, all the same width) |
| 20 | Switch to French during a rehearsal, then look at the panel | the big state, the SIMULATION banner, the `PING : OUI` line, the ROLE line and the action line stay **separated** (French labels are longer: that is the case that used to overlap) |

### 3.5c In-game protocol — the fifth pass (buttons and layout, 5 min, ALONE)

**Goal**: check the four points of the fifth in-game feedback (OK button, composition
buttons of the rehearsal, button labels, and the now-confirmed self-ping) **without a
boss and without a raid**. Keep `/console scriptErrors 1`: a Lua error here is a
blocking regression (the applier stops on the first faulty element and the panel loses
everything placed after it — that is exactly how the composition buttons and the OK
button had disappeared).

| # | Action | Expected |
|---|---|---|
| 1 | `/gr inter place` | the panel shows the placement text **including** *Place the panel where you want it to appear, then press OK: during the fight it opens by itself*; the **OK** button is **on screen**, at the bottom right next to **Close** (not clipped, not overlapping it) |
| 2 | Drag the panel where you want it, then click **OK** | the panel closes, the chat confirms `Placement saved. Pull when you want: the panel opens by itself before each intermission.`; `/gr inter place` shows the panel **at the new position** |
| 3 | `/gr inter place`, then click the **X** (or **Close**) | the placement is **cancelled**: nothing is saved (that is the difference with OK) |
| 4 | `/gr sim inter` | the panel opens right away with the banner **and the three composition buttons** (`1 vert + 3 rouges` / `2 verts + 2 rouges` / `3 verts + 1 rouge`, French labels in game), each with its **three lines of label fully inside its button** — no character out of the frame, no label touching the border |
| 5 | Click each of the three buttons | `1V3R` → `ROLE : ANCRE` + `PING : OUI` + the ANCHOR action line; `2V2R` → `ROLE : MILIEU` + `PING : NON`; `3V1R` → `ROLE : CHASSEUR` + `PING : NON` — and **the three buttons disappear** each time; **CORRIGER** brings them back |
| 6 | Look at every button of both panels in **French then English** (`/gr lang fr`, `/gr lang en`) | no label touches nor leaves its button (`PLACER LE PANNEAU`, `SIMULATION : TE PINGER`, `SIMULATION : GROUPE INTER`, `VERROUILLER`, `CORRIGER`, `Fermer`, `OK`, and the composition labels) — if a label still looks tight, raise `Layout.BUTTON_PADDING_X` / `Layout.FONTS.button.charWidth` in `Core/Layout.lua` (the tests measure through the same module) |
| 7 | Look at the width of the intermission panel | it is now **≈650 px** (as wide as its three composition labels require). Nothing to fix technically; if it feels too wide at your UI scale, lower the panel `scale` |
| 8 | Grouped, hover **your own character frame / health bar** and press the ping key | the ping is displayed **on yourself** — this is the fifth-pass confirmation; it is written in the doc and is **no longer on the "to be confirmed" list** |

### 3.5d In-game protocol — assignment soundboards (5 min, ALONE)

**Goal**: validate what the out-of-game tests cannot hear: the **real playback** by
the client. The three shipped files are **silent placeholders**, so this protocol
checks the **plumbing** (which file is requested, when, once) and the preference;
the real sounds only exist once the raid lead has dropped his recordings in `Sound/`
(`README.md` §3.3 — same names, Ogg Vorbis, no code change, only a `/reload`).
Keep `/console scriptErrors 1`: a Lua error here is a blocking regression (the
playback is wrapped in `pcall`, so a refused call must stay silent and never break
the panel).

| # | Action | Expected |
|---|---|---|
| 1 | `/gr sound` | the chat answers `Assignment sound: enabled - one soundboard per composition (1V3R / 2V2R / 3V1R), played once when you click your composition. /gr sound on\|off to change it, /gr sound test 1v3r\|2v2r\|3v1r to hear one now.` (`actif`/`desactive` in French) |
| 2 | `/gr sound test 1v3r`, then `2v2r`, then `3v1r` | each command **names its own file** in the chat: `Sound test: 1V3R (assign-1v3r.ogg)…`, `Sound test: 2V2R (assign-2v2r.ogg)…`, `Sound test: 3V1R (assign-3v1r.ogg)…` — with the **placeholders** you hear nothing (the files are silence, by design) but the plumbing is proven; **once the raid lead's recordings are in place**, each command plays its own soundboard: `1v3r` must play the **1V3R** sound, not the `3v1r` one — hear the three in a row to tell them apart |
| 3 | `/gr sound test bidon` | refused: `Unknown sound 'bidon': accepted values are 1v3r, 2v2r, 3v1r, start.` and **nothing** is played |
| 4 | `/gr sound yes` (or any value that is not `on`/`off`) | refused: `Unknown value 'yes': accepted values are on, off.`; `/gr sound` still reports the **previous** state (nothing was persisted) |
| 5 | `/gr sim inter` (or a real intermission), then click a composition | the soundboard of **that** state plays **exactly once**, **at the click** — the state, the role, `PING: YES/NO` and the action line appear as usual, in the same instant |
| 6 | Click the same composition again (`/gr inter 3V1R` twice, or force a click) | **no second sound**: one playback per assignment |
| 7 | Click **CORRIGER**, then click a composition (the same one or another) | the sound of the newly clicked composition plays: a correction is a new decision |
| 8 | Let the intermission end, wait for the **next** one, click the same composition as before | the sound plays again (a new intermission re-arms the playback) |
| 8b | **The intermission START sound**: `/gr sound test start` | the chat answers `Intermission start sound: intermission-start.ogg should have played (once at the beginning of every intermission)…` and the raid lead's recording is heard (**this file is NOT a placeholder**) |
| 8c | Then, on the target boss, let an intermission open **by itself** | the start sound plays **exactly once**, at the moment the panel opens (2 s before the intermission) — not twice, and **again at every new intermission** |
| 8d | `/gr sim inter` (then a second `/gr sim inter` after closing it) | the start sound plays **once per rehearsal**, like a real intermission |
| 8e | `/gr sound off`, then `/gr sim inter` | **nothing plays** (neither the start sound nor a soundboard) and the panel is unchanged; `/gr sound on` restores both |
| 9 | `/gr sound off`, then click a composition | **nothing plays**, and the panel is **unchanged**: state, role, `PING` banner and action line are all there (no Lua error, no frozen panel). `/gr inter status` reports `assignment sound: disabled` |
| 10 | `/gr sound on`, then `/gr sound test 3v1r` | the sound plays again |
| 11 | Switch the language (`/gr lang fr`, then `/gr lang en`) and redo points 1, 2 and 4 | the same messages in French (`/gr sound` = état, `/gr sound test` = « Test du son : … »), and an unknown value is still refused: the messages follow the active language like the rest of the addon |
| 12 | `/reload`, then `/gr sound` | the preference survived (a `/gr sound off` before the reload is still off) — it lives in `GideonRaidDB.intermission.soundEnabled` |
| 13 | Replace the three files in `Sound/` with the raid lead's recordings, `/reload`, then redo point 2 | the three **real** sounds play, one per composition, and nothing else had to be rebuilt |

**Failure reading**: if a sound never plays while the chat says `Sound test: …`, the
file is not where the `.toc` says it is (`Sound/`, lower case names) or the client
did not load the addon: `PlaySoundFile` fails silently by design, and the addon stays
silent too — check the **file names** first, then that the addon folder really is
`Interface/AddOns/GideonRaid/`.

### 3.5e In-game protocol — which boss may open the panel (10 min)

**Goal**: the reported bug (*"the window opens by itself during ANY boss fight"*) is
fixed by an allow-list of encounter ids, and that allow-list now **ships with the
addon**: **the measurement is DONE** (raid lead, 2026-09-24, heroic pull with 20
players: `encounter seen: id=3445 name=Sentinelles inhumées difficulty=15 group=20`).
What is checked here is what only a real client can say: that a fresh install opens
on the delivered target **with no command typed**, that another boss still does not,
and that the two distinct states (*never configured* / *cleared on purpose*) read
clearly. Everything else is proven out of game (`bossfilter_spec.lua`,
`intermission_spec.lua`). Keep `/console scriptErrors 1` on.

**A. The DELIVERED target (no command at all) — the new check**

| # | Action | Expected |
|---|---|---|
| 1 | Fresh install (or a client whose SavedVariables were never touched): `/reload` and watch the chat | **no warning**: a target is delivered, so the panel will open by itself. `/gr boss` reports `Auto-open target boss: ids 3445, names entombed sentinels, sentinelles inhumées` **and** the two lines that say where it comes from (`Target source: the default DELIVERED with the addon` + `Default delivered with the addon (it needs NO command and NO SavedVariables): id 3445, names Entombed Sentinels, Sentinelles inhumées.`) |
| 2 | `/gr boss list` | each id is labelled with its provenance: `Auto-open target ids: 3445 (addon default)` |
| 3 | Pull **Entombed Sentinels** (heroic, the difficulty that was measured) | the panel opens **by itself 2 s before each intermission**, four intermissions, closes at the end of each, and the start sound plays once per intermission (§3.5d 8b–8e) |
| 4 | Pull it again on **Mythic (16)** | **it opens too**: the difficulty is deliberately **not** filtered (14/15/16/17 are documented in `Config.BOSS_DIFFICULTIES`; the id log prints the difficulty but never decides). Nothing to change if it works |
| 5 | Pull a **different** boss | the panel **never opens**: `Encounter <id> is NOT the configured target …` — **this is the bug that was reported** |
| 6 | `/gr boss clear`, then pull **Entombed Sentinels** | **nothing opens** and the chat says the target was cleared **on purpose**: `Auto-open target is cleared on purpose (/gr boss clear) … /gr boss 3445 puts the target of the addon back` — the delivered default must **not** come back by itself |
| 7 | `/gr boss 3445` (the id typed back) | `Target encounter id 3445 added…` and the panel opens on the next pull; `/gr boss list` now reads `3445 (added by you)` with `Target source: ONLY the entries added by a player` |
| 8 | `/gr boss 3445` a **second time** | idempotent: no duplicate in `/gr boss list`, the target does not change |

**B. The filter in a raid evening**

| # | Action | Expected |
|---|---|---|
| 9 | Pull **a boss that is not the target**, with the delivered target in place | the panel **never opens** (no ticker, no schedule armed) and the chat prints the refusal, which names `/gr boss <id>` — an explanation, not a bug report |
| 10 | `/gr boss abc`, `/gr boss 0`, `/gr boss -3`, `/gr boss 12.5` | each is refused (`Unknown encounter id '…': a POSITIVE INTEGER is expected …`) and `/gr boss` still shows the **previous** target: nothing was written |
| 11 | `/gr idlog peut-etre` | refused (`Unknown value 'peut-etre': accepted values are on, off.`) and `/gr idlog` still reports the **previous** state |
| 12 | `/gr lang fr`, then `/gr boss` and `/gr boss list` | the same messages in French (`Boss cible de l'ouverture auto : …`, `Origine de la cible : le defaut LIVRE avec l'addon …`): every new string follows the active language like the rest of the addon |
| 13 | `/gr inter on`, then pull **any** boss | the panel opens on that encounter (`Encounter started: the MANUAL OVERRIDE (/gr inter on) opens the panel for it, whatever the boss…`), and at the end of that encounter the chat says the override is **consumed**: the next boss does **not** open it |
| 14 | `/console scriptErrors 1` over a whole evening, with the idlog on | **no** Lua error — in particular no `attempt to compare a secret value`: a secret argument must be reported as `unreadable`, never compared, and must never open the panel |
| 15 | `/gr lang fr`, then `/gr boss` and `/gr idlog` | the same messages in French (`Boss cible de l'ouverture auto : …`, `Journal des ids d'encounter : …`) |

**C. Measuring the id of ANOTHER boss (the procedure that produced 3445)**

| # | Action | Expected |
|---|---|---|
| 16 | `/gr idlog on`, then pull the boss | one line per `ENCOUNTER_START`: `encounter seen: id=<ID> name=<NAME> difficulty=<d> group=<n>` — **write down the `id=` value**; a value the client hides prints `unreadable`, never a fake number |
| 17 | `/gr boss list` | `Encounters memorized by the idlog (1, newest first):` then the line indented: the id is readable **after** the fight, no screenshot needed |
| 18 | `/gr boss <THE_ID>` | `Target encounter id <ID> added…` and that boss opens the panel **too** (it is added to the delivered one, it never replaces it). `/gr idlog off` when finished |
| 19 | `/gr boss name <the exact name your client displays>` | the name is added (secondary criterion) and `/gr boss list` shows it labelled `added by you`. **Language-dependent: paste only what the idlog printed on YOUR client; no translation is ever written for you** |

**Failure reading**: if the panel opens on a boss that is not the target, look at
`/gr boss list` — either that id is in the list (remove it with `/gr boss clear`
then re-add the right ones) or `overrideEncounter` is armed (`/gr inter off` then
`/gr inter on` clears it). If `/gr boss <id>` is refused, the value is not a
**positive integer**: an encounter id is a plain integer, never a decimal, never a
name. If a client that **never** configured anything does **not** open on the
delivered target, check `/gr boss`: if it reads `cleared ON PURPOSE`, a
`/gr boss clear` was played (the SavedVariables keep `bossTargetCleared = true`) —
that is the intended behaviour, and `/gr boss 3445` restores it.

### 3.5f In-game protocol — `/gr diag`, the health report (5 min, ALONE)

**Goal**: confirm in a real client the two things the tests cannot prove: the
**meaning of the boolean returned by `PlaySoundFile`** (the documented trick: the
call returns `true` when the client **will** play the file, `nil`/`false` when it
will not — missing file, file added after the client started, refused playback) and
the promise that **the diagnostic never makes a noise**.

| # | Action | Expected |
|---|---|---|
| 1 | `/gr diag` with the game sound **ON** (the normal raid case) | a read-only report: the target (`auto-open target: ids 3445 …`), its source, the delivered default, `encounter id log: …`, `intermission ping policy: anchors - …`, and the four sound files listed as **`NOT TESTED`** — and **absolutely no sound is played** (this is the promise: no noise in a raid). The report ends with the two ways to get a verdict |
| 2 | `/console Sound_MasterVolume 0` (master volume 0, channel still enabled), then `/gr diag` | the four files are now probed for real: four **`present and playable [OK]`**, with `the check DID run for real … NOTHING was audible`. This is the **confirmation that a volume of 0 does not make the client answer "nothing will play"**; if instead **all four** read `NOT playable [KO]`, the report's own caveat fires (`ALL FOUR files came back as not playable`) and the gate has to be revisited (`Core/Diag.probeGate` is the single place). Then `/console Sound_MasterVolume 1` |
| 3 | Ctrl+S (or Options > Sound) to **disable the sound**, then `/gr diag` | four `NOT TESTED` + `the sound is OFF (or unreadable) in this client, and a DISABLED channel answers 'nothing will play' even for a file that is really there - the verdict would be a lie`: **nothing is played**. Turn the sound back on |
| 4 | **Negative case**: rename `Sound/assign-3v1r.ogg` to `assign-3v1r.ogg.bak` (or replace its content with a non-audio file), **restart the client** (a `/reload` is NOT enough for sound files), set the master volume to 0, `/gr diag` | that line alone reads `Sound/assign-3v1r.ogg: NOT playable [KO]` while the other three read `[OK]`. Restore the file and restart again. This is the only way to validate a real KO |
| 5 | `/gr diag` twice in a row | idempotent and read-only: nothing is written in `GideonRaidDB` (`/gr boss`, `/gr boss list` and `/gr idlog` are unchanged afterwards), the panel does not open, and the four sounds are not played twice |
| 6 | `/gr lang fr`, then `/gr diag` | the whole report in French (`--- DIAGNOSTIC (lecture seule …)`, `cible de l'ouverture auto : …`, `NON jouable [KO]`): every line goes through `Core/Locale.lua` like the rest of the addon |

**Failure reading**: `NOT TESTED` is a **refusal to guess**, not a failure — read the
reason line right under it (sound on → mute the master volume and rerun; sound off →
turn it on; CVar unreadable → the client refused the read, `/gr sound test
1v3r|2v2r|3v1r|start` still plays a file on request). A `KO` on **one** file means
that file is missing from `Sound/`, not listed in `GideonRaid.toc` (an unlisted file
is **never** loaded), or was added **after** the client started (**restart**, a
`/reload` is not enough). A `KO` on **all four** is almost always a channel that
refuses every playback: put the master volume back above 0 and hear one file with
`/gr sound test 1v3r`.

### 3.6 Recommended test environment

A single "guinea pig" player is enough: the essential part (reading
`GideonRaidDB`, rendering) does not depend on any other player. Tests with 2+
players would only be needed for a communication channel, which does not exist.
**That is a strong argument for not investing in a heavy test client.**

---

## Step 4 — Integration tests with GIDEON

**Goal**: guarantee that the GIDEON ↔ addon data contract does not drift.

### 4.1 Data contract (frozen, versioned schema)

`GideonRaidDB.assignment` (written by GIDEON, read by the addon):

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
        -- OPTIONAL: plan prepared out of game (role / position per player).
        -- `role` accepts the composition "1V3R" / "2V2R" / "3V1R" or a free role.
        plan = {
            { name = "Velna",   role = "2V2R", position = "MIDDLE" },
            { name = "Torgh",   role = "2V2R", position = "MIDDLE" },
            { name = "Bathman", role = "1V3R", position = "HOLD"   },
            { name = "Coren",   role = "3V1R", position = "PURSUE" },
        },
    },
}
```

Runnable contract fixture: `tests/fixtures/assignment_sample.lua` (used by
`tests/spec/intermission_spec.lua` and by
`lua5.1 tools/intermission_cli.lua plan <Name>`).

- `schema` is **mandatory**: if GIDEON moves to 2 while the addon is on 1, the
  addon must refuse the block (today `validateAssignment` accepts and normalizes
  it → to be hardened when the schema changes).
- The pair order is alphabetical. That is what makes the contract comparable with
  a diff (`diff` of both outputs).

### 4.2 Contract non-regression (automatic test, out of game)

GIDEON generates the file through the **shared** Lua engine:

```bash
# GIDEON: produces the pairs from the roster
lua5.1 tools/pairing_cli.lua < /tmp/roster_of_the_evening.csv
# -> Velna|Torgh .... exit 0
```

Test to add once GIDEON is plugged in: a test in `tests/spec/` that takes a
sample reference `SavedVariables` file (fixture) and checks that
`Pairing.validateAssignment` accepts **exactly** what GIDEON writes. That is a
contract test, not an implementation test: it must break *if and only if* the
format changes.

### 4.3 Manual round-trip (10 min, before the first raid)

| # | Action | Expected |
|---|---|---|
| 1 | The GIDEON side publishes the assignment (the exact Discord command belongs to the bot repository, **not** to this addon: no in-game message points to a command any more) | GIDEON answers with the list of pairs |
| 2 | Check `WTF/.../SavedVariables/GideonRaid.lua` on the test VPS | `pairs` identical to the Discord answer, `schema = 1` |
| 3 | `/reload` in game | panel identical to the Discord answer |
| 4 | Stop GIDEON, `/reload` | the addon still works (data already cached) |
| 5 | Roster with a single `frost` and 3 `ember` | GIDEON alerts (`NON-APPARIE: ... no_partner:frost` on stderr) **and** the addon displays the same thing |

### 4.4 Degradation test

GIDEON writes a malformed block (`pairs = {{a=1,b="B"}}`): the addon must display
"No GIDEON assignment. (paire #1 invalide)" and **not crash**. That is already
covered in steps 1 and 2.

---

## Coverage matrix (what proves what)

| Risk | Step covering it | Evidence |
|---|---|---|
| Wrong pairing | 1 | 11 tests, 20-player data set |
| Non-deterministic result | 1 | "insensitive to input order" test |
| Orb convention / wrong collisions | 1b | 80 tests (states 3V1R/2V2R/1V3R, `3V1R+1V3R` and `2V2R+2V2R` safe, `3V1R+2V2R` = 5 green, ambiguous number refused) |
| Wrong language served (English/French) | 1c | 21 tests (`resolve`, `t`/`format` fallbacks, `GetLocale` stubbed `frFR`/`enUS`/`deDE`, `/gr lang`, missing key) |
| Hard-coded in-game string | 1c + 2 | all displayed text comes from `Core/Locale.lua`; the guard scans the loaded files |
| Countdown / switch to the darkened room wrong | 1b + 2 | deterministic state machine + tested ticker |
| ~~Ping macro unusable~~ (macro route dead: the client refuses it) | 1b + 3 | the macro generation has been **removed**; `guard_spec.lua` fails if `C_Ping` / `SendMacroPing` / `buildMacro` comes back; the addon only displays which ping and which key |
| Ping keybind not found (wrong candidate name) | 1b + 3 | the panel shows **no key** and asks for a keybind in Options > Keybindings; `/gr inter ping` prints the candidates tried (TBD item 1 of §9) |
| Wrong ping role (a duty deduced from the ambiguous number) | 1b | 20 tests (`pingpolicy_spec.lua`): role carried by the state, never by the number |
| **Ping flood** (~20 pings, unreadable channel, client ping limit) | 1b + 3 | `anchors` policy: only the anchors ping, **one ping per player per intermission** vs a measured client limit of **3 per 5 s** (3 in a row + ~5 s wait, measured in game 2026-09-22): the budget is never the failure mode. Protocol §3.5 point 15 |
| Unknown ping policy silently accepted | 1b + 2 | pure resolver (unknown → `anchors`), `/gr ping` refuses an unknown value and writes nothing |
| Declaring one thing and displaying another | 1b + 2 | instruction and ping decision coming from the same record (`CONVENTION` + `pingsInMode`) |
| Panel unreadable during the darkening (too much text) | 1b + 2 | **max 3 short lines** + the state in very large type, tested (`intermission_spec.lua`); banned lines (ROLE ORDER / PING POLICY / caveats) checked by the tests |
| Player stuck on a wrong click | 1b + 2 | **REDO** button (`clearDeclaration`), unlimited and idempotent, tested in `intermission_spec.lua` and `load_spec.lua` |
| Panel does not open (or opens too late) at the intermission | 1b + 2 | schedule machine tested out of game (opening at `intermission − lead`, no skip even with a huge `dt`) + protocol §3.5 points 4b/8c |
| File forgotten in the `.toc` | 2 | `wowenv.loadAddon()` + `check_toc.py` |
| **Sound file forgotten in the `.toc`** (the client does not load an unlisted sound) or deleted from the repository | 1f + 2 | `sound_spec.lua`: the **four** client paths (the three soundboards **and** `intermission-start.ogg`) are entries of the `.toc`, the four files exist on disk (real Ogg Vorbis) and `.pkgmeta` never excludes `Sound/`; `check_toc.py` also fails if a listed file is missing |
| **Wrong sound for a composition** (file swapped between two states) | 1f + 3 | pure table `state -> file` tested state by state (three distinct names, no sharing) + protocol §3.5d point 2 (hear the three in a row) |
| **Sound played twice / played without a declaration** | 1f + 2 | `Sound.takeAssignSound` refuses a repeat of the same assignment ("already") and an unknown state ("unknown") — asserted in `sound_spec.lua`; protocol §3.5d points 5/6/8 |
| **Sound still playing when the player muted it** | 1f + 2 + 3 | total resolver (only an exact `false` mutes), `/gr sound off` then a click asserts **zero** `PlaySoundFile` call while the panel still renders; protocol §3.5d points 9/10 |
| **A failing/absent sound call breaks the panel** | 2 | `PlaySoundFile` under `pcall` + `type()` guard, `guard_spec.lua` restricts it to `UI/`, `sound_spec.lua` runs the whole declaration flow with a raising and with an absent API |
| **THE PANEL OPENS ON THE WRONG BOSS** (the reported bug: every `ENCOUNTER_START` opened it) | 1g + 2 + 3 | pure decision on the allow-list in `Core/BossFilter.lua`: the delivered default (id **3445**) opens (`matchId`), any other id is refused (`noMatch`) — asserted by `bossfilter_spec.lua` (45 tests) and driven end to end in `load_spec.lua`; protocol §3.5e A/B |
| **THE PANEL DOES NOT OPEN ON THE RIGHT BOSS because nobody typed a command** | 1g + 2 + 3 | the target is **DELIVERED** (`Config.DEFAULT_BOSS_IDS = { 3445 }` + the EN/FR names, measured in game on 2026-09-24): a SavedVariables that was **never configured** resolves to the delivered default (`bossTargetSource = "default"`), so a fresh install works with no command — asserted in `intermission_spec.lua` (never configured vs explicit clear vs player addition) and driven in `bossfilter_spec.lua` (heroic 15 + FR name, mythic 16 + EN name); no warning is printed at login any more; protocol §3.5e A rows 1–4 |
| **A deliberate `/gr boss clear` is silently undone by the delivered default** (or the reverse: a lost configuration mistaken for a choice) | 1g + 2 | `bossTargetCleared` (an **exact `true`** only) is distinct from an empty list: after a clear the delivered default is **dropped** (`bossTargetSource = "cleared"`, nothing opens) until `/gr boss <id>` adds one; `/gr boss`, `/gr boss list` and `/gr diag` all say **where** the target comes from, and `/gr boss list` labels every entry *addon default* / *added by you*; protocol §3.5e A rows 6–8 |
| **`/gr diag` makes a noise in a raid** (an in-game health check must never play a sound) | 1h + 2 + 3 | the audio probe is behind the **silence gate** `Core/Diag.probeGate`: it runs only with the Master channel **enabled** (otherwise a disabled channel answers "nothing will play" even for a present file — a lie) **and** its volume at **0** (so the playback is inaudible). `diag_spec.lua` asserts that `/gr diag` calls `PlaySoundFile` **zero** times when the sound is on or off, and exactly 4 times (channel `Master`, the right paths) when the volume is 0; `guard_spec.lua` asserts the gate is what the rendering layer obeys; protocol §3.5f rows 1–3 |
| **A missing / not-loaded sound file goes unnoticed** (an unlisted file fails silently) | 1f + 1h + 3 | `diag_spec.lua` drives the four verdicts (OK / KO / not tested / unknown) and the report lines; protocol §3.5f row 4 renames a real file and **restarts** the client to see a true KO |
| **A *secret* / unreadable `ENCOUNTER_START` argument opens the panel or raises a Lua error** | 1g + 2 + 3 | every argument is read **under `pcall`** and an unreadable value is **never compared** (`REASON.UNREADABLE`, no match); the decision itself is called under `pcall` in `UI.BossDecision`, proven by a test that makes `evaluate` raise (panel stays closed, no error propagates); protocol §3.5e row 16 (`scriptErrors 1` over a whole evening) |
| **The target boss id is invented / wrong** (the id used to be unknown) | 1g + 2 + 3 | nothing is guessed: the delivered id **3445** is the one **MEASURED IN GAME** (raid lead, 2026-09-24, `/gr idlog on`, heroic 20-player pull: `encounter seen: id=3445 name=Sentinelles inhumées difficulty=15 group=20`), `/gr boss` refuses anything that is not a **positive integer without persisting it**, and the id of any other boss comes only from **`/gr idlog on` in game** (§3.5e C: the chat prints `id=…` and `/gr boss list` keeps the last 10 encounters) |
| **Start sound played twice for one intermission, or never again** | 1f + 2 + 3 | one playback per **intermission token** (the same token is refused with `REASON.ALREADY`, a new token always plays: the next intermission and the next rehearsal re-arm it) — asserted by `sound_spec.lua` on the pure gate and on the real flow (two intermissions = two sounds, one rehearsal = one sound); protocol §3.5d rows 8b–8e |
| Lua 5.1 syntax error | 2 | `make syntax` |
| Crash at login / wrong event | 2 | `load_spec.lua` |
| **A rehearsal corrupts a real fight** (timeline armed/disarmed, decision published, double state) | 1d + 2 + 3 | guard: `Core/Simulation.lua` must not reference `ENCOUNTER_START` / `Intermission.newRun` / `advanceRun` / `resetRun` / `RegisterEvent`; the two crosses, the two simulations and the refusals are driven tick by tick in `load_spec.lua`; no decision ever published; protocol §3.5b points 8/13 |
| **Simulation mistaken for a real intermission** | 1d + 2 + 3 | the two-line `SIMULATION - NO BOSS, NO RAID` / `SINGLE REHEARSAL - YOU CLOSE THE PANEL YOURSELF` banner on the panel (asserted in the tests) + protocol §3.5b point 5 |
| **A layout regression makes a panel unreadable** (text over the frame, one line on top of another, French longer than English) | 1e + 2 + 3 | pure geometry in `Core/Layout.lua` (ordered, anchored blocks + overlap/border/cross violations) asserted block by block **in both languages** by `layout_spec.lua`, applied as is by `UI.ApplyLayout` (an element outside the layout is hidden **and emptied**); protocol §3.5b points 19/20 check the real font metrics |
| **Addon pretending to detect a ping** (no API can) | 1d + 2 | the "announced" counter only, the explicit `CANNOT detect a ping` line and the group reminder, asserted in both languages; protocol §3.5b points 10/11 |
| **Panels impossible to close** | 2 + 3 | close cross on both panels: label + short tooltip from `Core/Locale.lua`, click handlers covered in `load_spec.lua`, tooltip without `GameTooltip` does not raise; protocol §3.5b points 1–4 |
| Unreadable panel in a raid | 3 | manual protocol §3.2 and §3.5 |
| Secret value error in combat | 3 | §3.0 + code review (conventions §1 and §10) |
| GIDEON format drift (pairs **and** `plan`) | 4 | contract test + round-trip |
| Outdated Interface version | 2 | `check_toc.py` (threshold 120100) |
