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
| 2 | Addon loading (wiring, .toc, events) | busted + API stub | on every commit | CI + local |
| 3 | Rendering and ergonomics in game | test client | before every patch | WoW client |
| 4 | End-to-end GIDEON integration | Lua CLI + Discord | before every raid | VPS + Discord |

Single exit gate: **`make check`** (stylua + luacheck + toc + busted).

---

## Step 1 — Out-of-game unit tests of the pairing logic

**Goal**: the `ns.Pairing` engine is pure Lua 5.1, without any call to the WoW
API. It is therefore runnable by `lua5.1` and by `busted`, installed on the VPS
and on the GitHub runner.

**File**: `tests/spec/pairing_spec.lua` (11 tests; the repository total is
**111 tests**, spread over `intermission_spec.lua` (60), `load_spec.lua` (16),
`locale_spec.lua` (20) and `guard_spec.lua` (4)).

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

**File**: `tests/spec/intermission_spec.lua` (60 tests).

**What is verified:**

| Family | Cases |
|---|---|
| Color states | the three states `1V3R` / `2V2R` / `3V1R` (label, green AND red counts, possible numbers, ping, complement, instruction), "2" alone unambiguous, "1"/"3" ambiguous, deterministic order, non-mutable copy, **the French variant served explicitly when the active language is `fr`** |
| Normalization | `3V1R`, `2v2r`, `1 V 3 R`, `vert-vert-vert-rouge`, `vvrr`, `3 verts`, `1 vert 3 rouges`, dominant color alone ("vert", "majorité verte"), "2" accepted, **"1"/"3" alone refused with an "ambiguous" message**, empty/unknown/unusable input refused |
| Collisions | `3V1R+1V3R` OK both ways, `2V2R+2V2R` OK, `3V1R+2V2R` = 5 green = dead, `1V3R+1V3R` and `3V1R+3V1R` refused, comparison on an ambiguous number refused |
| Macro | `C_Ping.SendMacroPing` call per state (dominant color), target token, `/ping` variant, "to be confirmed" note, **absence of forbidden event text**, no macro on an ambiguous number |
| Timeline | default values (3 s), prepared values, bounds (1–10 s, 3–120 s), `duration > visibility` |
| State machine | `IDLE → VISIBLE (3 s) → DARK → DONE`, countdown 3/2/1/0, declaration during VISIBLE and DARK, refusal before start, on an ambiguous number and after the end, `reset`, negative/non-numeric `dt` ignored, determinism (same inputs ⇒ same report) |
| Pre-pull view | partner, role (composition), position, meeting `2V2R+2V2R` OK / `3V1R+2V2R` DEAD / `1V3R+3V1R` OK / **unverifiable when the role stays ambiguous**, pairs sorted by name and insensitive to input order, plan absent, malformed plan, player absent, invalid assignment |
| Configuration | fresh defaults (no alias between accounts), scale and duration bounds, inconsistent types ignored |

**Out-of-game preview** (verifiable by hand, without a client — the developer CLI
keeps printing French):

```
$ lua5.1 tools/intermission_cli.lua all            # les 3 états + macros
$ lua5.1 tools/intermission_cli.lua 1              # -> REFUS : numéro ambigu
$ lua5.1 tools/intermission_cli.lua pair 3V1R 2V2R # -> 3V1R+2V2R : MORT (5 verts = 5g)
$ lua5.1 tools/intermission_cli.lua plan Velna
```

---

## Step 1c — Out-of-game tests of the language layer

**Goal**: prove that the addon is bilingual with English as the official
language, that French is served automatically on a frFR client, and that no
string can ever raise.

**File**: `tests/spec/locale_spec.lua` (20 tests), in three blocks:

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

1. the 7 files of the `.toc` are loaded in order (`Core/Locale.lua` second,
   before the other `Core/` modules), and the 6 layers (`ns.Locale`,
   `ns.Pairing`, `ns.Config`, `ns.Intermission`, `ns.UI`, `ns.GR`) are exposed;
2. `ADDON_LOADED` on `GideonRaid` initializes `GideonRaidDB` with the defaults
   (including `intermission` and `locale`);
3. `ADDON_LOADED` on **another** addon does not touch the SavedVariables;
4. `PLAYER_LOGIN` without an assignment does not raise;
5. `PLAYER_LOGIN` **with** an assignment displays the plan (partner, role,
   position, `2V2R+2V2R` meeting) in the panel;
6. the slash handler (`/gr show`, `/gr status`, `/gr plan`, `/gr inter status`,
   unknown command) answers without raising;
7. `ENCOUNTER_START` (with its instance arguments) opens the intermission panel
   without any argument being read;
8. the three buttons carry the visible composition (number as a hint) and a click
   on a button displays the full instruction and the ping macro;
9. the ticker switches the display to "room darkened" 3 s after the start
   (35 ticks of 0.1 s);
10. `ENCOUNTER_END` closes the panel;
11. disabling (`/gr inter off`) is honoured;
12. the panel displays no dynamic value (no combat API call).

**`.toc` verification** (`tools/check_toc.py`, in CI):

```
$ python3 tools/check_toc.py GideonRaid.toc
OK GideonRaid.toc
  Interface  : 120100
  Version    : @project-version@
  SavedVar   : GideonRaidDB
  Fichiers   : 7
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

**Pass criterion**: step 1 + 1b + 1c + step 2 green, `luacheck .` = 0 warning.

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
9. Move the panel (drag), `/reload`, check the position is kept.
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

| # | Action | Expected |
|---|---|---|
| 1 | `/gr` out of instance | "Your partner: …" + list of pairs (`assignment` block prepared by GIDEON) |
| 2 | `/gr plan` | the detailed plan in the chat (role, position, meeting) |
| 3 | `bindings`: Options > Keybindings > GideonRaid, assign a key | the binding shows up; the key opens/closes the panel |
| 4 | Enter *Entombed Sentinels*, pull the boss | the panel opens on its own on `ENCOUNTER_START` (points 1 and 2: **to be confirmed**) |
| 5 | During the 3 s of visibility | the reminder displays "LOOK AT THE ORB COLOR ABOVE THE HEADS: 3" then 2, 1 (French on a frFR client) |
| 6 | Count your orbs, click `1` / `2` / `3` composition button | the instruction (position + ping color) and the macro appear |
| 7 | Paste the macro into a game macro (60 s before the pull) | the ping goes out with the right color — **syntax to be confirmed, this is item 1 of the list in `docs/INTERMISSION-COACH.md` §9** |
| 8 | Check after 3 s | "ROOM DARKENED": the panel stays readable, no dynamic text |
| 9 | End of combat | `ENCOUNTER_END` closes the panel |
| 10 | `/console scriptErrors 1` over 10 min of raid | **no** Lua error (typically `attempt to compare a secret value` = blocking regression) |
| 11 | `/gr lang` on a frFR client and on an enUS client | detected language correct, text in the right language; TBD item 3 of `docs/INTERMISSION-COACH.md` §9 |

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
| 1 | Discord command `!g roster assign` on the real roster | GIDEON answers with the list of pairs |
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
| Orb convention / wrong collisions | 1b | 60 tests (states 3V1R/2V2R/1V3R, `3V1R+1V3R` and `2V2R+2V2R` safe, `3V1R+2V2R` = 5 green, ambiguous number refused) |
| Wrong language served (English/French) | 1c | 20 tests (`resolve`, `t`/`format` fallbacks, `GetLocale` stubbed `frFR`/`enUS`/`deDE`, `/gr lang`, missing key) |
| Hard-coded in-game string | 1c + 2 | all displayed text comes from `Core/Locale.lua`; the guard scans the loaded files |
| Countdown / switch to the darkened room wrong | 1b + 2 | deterministic state machine + tested ticker |
| Ping macro unusable or badly targeted | 1b + 3 | generated text + protocol §3.5 point 7 ("to be confirmed in game") |
| Declaring one thing and displaying another | 1b + 2 | instruction coming from the same table as the macro |
| File forgotten in the `.toc` | 2 | `wowenv.loadAddon()` + `check_toc.py` |
| Lua 5.1 syntax error | 2 | `make syntax` |
| Crash at login / wrong event | 2 | `load_spec.lua` |
| Unreadable panel in a raid | 3 | manual protocol §3.2 and §3.5 |
| Secret value error in combat | 3 | §3.0 + code review (conventions §1 and §10) |
| GIDEON format drift (pairs **and** `plan`) | 4 | contract test + round-trip |
| Outdated Interface version | 2 | `check_toc.py` (threshold 120100) |
