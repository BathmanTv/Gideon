# Intermission Coach — Entombed Sentinels (mythic)

"Intermission Coach" module of GideonRaid: it makes the **coordination of the
Entombed Sentinels intermission** (raid *The Venomous Abyss*, Midnight 12.1.0)
possible and fast **with minimal player action**, without ever reading a combat
API.

Reference guide:
<https://raidstrats.gg/guides/entombed-sentinels/mythic/phase/quick-overview>

> **Design rule after the first real in-game test (raid lead, live raid):** the
> intermission panel shows **the essential only** — the state, the role,
> `PING: YES/NO` and **one** action line. The long explanations live here, in
> this document, **never on screen**.

---

## 1. The mechanic, as implemented

- During the intermission, **every player sees a NUMBER above their head**, but
  **the number does NOT determine the colors**:
  - "**2**" = **always 2 green + 2 red** (`2V2R`) — the only unambiguous case;
  - "**1**" or "**3**" = either **3 green + 1 red** (`3V1R`), or **1 green +
    3 red** (`1V3R`): it is the **COLOR of the orbs** that decides, never the
    number.
  There are therefore only **three real states**: `3V1R`, `2V2R`, `1V3R`.
- **Survival rule = color addition**: the sum of the two players must make
  **4 green AND 4 red** (4V4R):
  - `3V1R + 1V3R` = 4V4R → **safe**;
  - `2V2R + 2V2R` = 4V4R → **safe**;
  - any other combination kills; `3V1R + 2V2R` = **5 green** = the guide's
    "**5g**"; `1V3R + 1V3R` = 2 green + 6 red = dead as well.
- About **3 s** after the start, the boss darkens the room: each player then
  sees only **their own orbs** (their number alone is not enough).

## 2. The three states (explicit and configurable convention)

`CONVENTION` table of `Core/Intermission.lua` (single source of truth):

| State | Composition | Possible number(s) | Role | Position | Ping to use | Must be joined by |
|---|---|---|---|---|---|---|
| `1V3R` | 1 green + 3 red | **1 or 3** (ambiguous) | **ANCHOR** | **HOLD**, where you are | `Warning` (red) | `3V1R` |
| `2V2R` | 2 green + 2 red | **2** (unambiguous) | **MIDDLE** | **MIDDLE / under the boss** | `OnMyWay` (blue) | `2V2R` |
| `3V1R` | 3 green + 1 red | **1 or 3** (ambiguous) | **CHASER** | **run to a ping, any `1V3R`** | `Assist` (green) | `1V3R` |

Each state also carries: the visual label ("3 GREEN + 1 RED", "3 VERTS +
1 ROUGE" in French), the number of green and red orbs (basis of the survival
computation), the **ONE action line** (two variants: with ping / without ping,
selected by the policy) and the button text (number as a hint). **Every displayed
field of a `CONVENTION` record is a locale key** (`state.actionPing.3V1R`, …)
resolved by `copyRecord` through `ns.Locale.t`, so `/gr lang` applies without a
reload.

**Ping naming**: raidstrats guide convention, **by dominant color** — 3 green →
`Assist` (green), 2-2 → `OnMyWay` (blue), 3 red → `Warning` (red). Those colors
are verified on the wiki gallery
(<https://warcraft.wiki.gg/wiki/Ping_System>): `Warning` = red panel,
`OnMyWay` = blue arrow, `Assist` = green flag. **Which state actually pings is
decided by the ping policy, not by the color alone** — see §2.2.

**Positions**: the **positional** lines of the raidstrats guide **contradict each
other** (they give both "1 green 3 red → left" and "3 red 1 green → right"). Our
convention is therefore **explicit and configurable**, and it is the only one
consistent with "the color decides": the **fixed** point is the **red**-majority
state (`1V3R`, `Warning` ping), the **runner** is the **green**-majority state
(`3V1R`, `Assist` ping), the `2V2R` go to the middle. If the guild changes the
convention, change `CONVENTION` (and the tests) — never the UI.

### 2.1 Ping roles by STATE (raid-lead decision)

The duty comes from the **state** (the orb composition), never from the number
displayed above the head: 1 and 3 are ambiguous, and a role deduced from them
would be wrong half of the time. Every canonical state therefore carries an
explicit **`role`** and **one** action line in `CONVENTION`:

| State | `role` | Verdict | Action line (EN) |
|---|---|---|---|
| `1V3R` | `ANCHOR` | **pings** (default policy) | "STAY WHERE YOU ARE - ping yourself (Warning) and jump on the spot" |
| `2V2R` | `MIDDLE` | does not ping | "DO NOT PING - go to the middle / under the boss" |
| `3V1R` | `CHASER` | does not ping | "DO NOT PING - run to a ping (a 1V3R)" |

(French: "RESTE SUR PLACE - ping-toi (Warning) et saute sur place" / "NE PING PAS
- va au milieu / sous le boss" / "NE PING PAS - fonce sur un ping (un 1V3R)".)

**Why this rule (the "8 pings instead of 20" argument):** if every state pings
its own ping, a 20-player raid produces ~**20 pings** in a few seconds and the
channel becomes unreadable. Restricting the ping to the anchors gives **one ping
per anchor, 4 per side → at most ~8 pings in the whole raid**, and every ping is
meaningful (an anchor is a landmark a chaser can run to).

**The client's per-player ping limit is a MEASURED fact, not an assumption:
3 pings in a row, then about 5 seconds of wait, then 3 again (measured in game
by the raid lead, 2026-09-22).** Two consequences, both already enforced by the
design:

1. **The addon must never ask for a burst.** An instruction such as "ping
   yourself, then ping your anchor, then ping the middle" would be swallowed by
   the client from the 4th ping on. The one action line per state contains **one
   single ping**, which is the whole point of having reduced the panel to the
   essential (§2.3).
2. **With the `anchors` policy, each concerned player sends exactly ONE ping per
   intermission** — one every ~100 s over the fight, where the client allows 3
   per 5 s. The raid is therefore **very far from the limit**, which is what
   validates the anchor-only choice: the ping budget is never the failure mode.

Three points make this rule playable:

1. **An ANCHOR can be pinged by somebody else.** The keybind is only a
   convenience: any other player of the raid (a chaser passing by, a player who
   still sees the anchor during the 3 s window) can ping the anchor. What
   matters is that the anchor does not move and that **one** ping locates it.
2. **Pings are visible on the raid frames since patch 12.1**, so a chaser can
   locate an anchored player from the frames even after the room darkens — still
   with no addon → addon communication (which does not exist in instances).
3. **The addon never pings and never prepares a macro.** See §4.

### 2.2 Ping policies (configurable: `/gr ping`)

The policy is persisted in `GideonRaidDB.intermission.pingMode` and resolved by
the pure, total `ns.Config.resolvePingMode` (an unknown value — absent, typo,
hand-edited SavedVariables — falls back to `anchors`, never an error):

| Policy | Who pings | Ping |
|---|---|---|
| `anchors` (**default**) | only the `1V3R` ANCHORS | `Warning` |
| `color` (raidstrats variant) | every state | `1V3R` `Warning`, `2V2R` `OnMyWay`, `3V1R` `Assist` |
| `none` | nobody (positions only) | — |

The role never changes with the policy (a `3V1R` is always the `CHASER`): only
the ping decision and **the wording of the action line** adapt, so a role never
receives a contradictory instruction. In `color` mode the `CHASER`/`MIDDLE` keep
their movement order and simply ping their own ping on the way.

The policy **decides who must ping** but is **no longer displayed permanently on
the panel**: it stays available on demand (`/gr ping`, `/gr inter status`).

### 2.3 Evening flow (implemented end to end)

| # | Player action | What the addon does |
|---|---|---|
| a | before the pull, types `/gr` | the main panel opens; its button **PLACE INTERMISSION PANEL** switches to **placement mode**: the intermission frame is shown, dragged where the player wants it and its **position is saved in the SavedVariables** |
| b | prepares the ping keybind (Options > Keybindings), then presses **OK** | the placement panel is validated and **closes**; `/gr inter place` reopens it at will |
| c | pulls the boss | `ENCOUNTER_START` is the **starting gun of the pre-computed schedule** (its arguments are never read). 1–2 s (**lead = 2 s by default**) before each intermission the panel **opens by itself** with the three choices |
| d | clicks the composition seen above their head | state in very large type, role, `PING: YES/NO`, one action line; the **REDO** button brings the three choices back, as many times as needed |
| e | — | at the end of the intermission the panel **closes by itself** |
| f | next intermission | same cycle, **automatically** (schedule: 46.3 s, then 148.9 / 251.5 / 353.2 s after the pull) |

The schedule lives in `GideonRaidDB.intermission.scheduleSeconds` (sorted,
bounded, 12 entries max) and can be replaced out of game. The state machine is
pure and time is **injected**: `Intermission.tick(state, dt)` and
`Intermission.advanceRun(run, dt)` never read the client clock.

## 3. What the addon does / can NOT do (to be told to the players as is)

**It can:**

- display the plan prepared out of game (partner, role, position, pairs);
- **place** the intermission panel where the player wants it (position persisted);
- display the **three composition buttons** named after the **visible
  composition** — `1 green + 3 red`, `2 green + 2 red`, `3 green + 1 red` — with
  the **number as a hint** ("1 or 3", "2");
- display, once a composition is clicked, **the state in very large type, the
  role, the `PING: YES/NO` banner (colored with the ping color of the state) and
  ONE action line**;
- display **which ping to use** (`PING: Warning`) and, when the player bound a
  key, **which key to press** (`PING: Warning - press Q`) — the key is read with
  `GetBindingKey`, under `pcall`;
- display the **2 s lead**, the **3 s visibility countdown**, then report that the
  room went dark, then close itself at the end;
- offer **REDO**: a mistaken click is corrected in one click, as many times as
  needed;
- publish the player's decision (timestamped) into the SavedVariables: that is
  what the `GideonDiagAddon` diagnostic kit reads back, with no chat input and no
  inter-addon communication.

**It can NOT (12.x constraints, to be assumed):**

- read another player's auras / indicators (secret values) —
  <https://warcraft.wiki.gg/wiki/Secret_Values>;
- read **its own** in a usable way: it is the player who declares;
- **send a ping**, and this is now a measured in-game fact, not a documentation
  guess: an addon ping is refused by the client ("action usable only by the
  Blizzard UI"), **including from a macro** and from a binding. So the addon
  **generates no macro any more** and **never pings**: the player pings with
  their **native** ping keybind;
- **know who declared what**: no addon→addon channel in an instance, and an
  addon's UI is local to its client;
- display a text visible to the other players: **the ping is the only signal**
  the others see.

In other words: **nothing is automatic in this addon**. Everything displayed
comes from a player click or from a file prepared out of game.

Everything above is displayed in the **effective language** (English by default,
French on a frFR client — see `README.md` §4 and `docs/CONVENTIONS.md` §11). Only
the **org names** (`3V1R`, `2V2R`, `1V3R`, `Warning`, `OnMyWay`, `Assist`) are
identical in both languages.

## 4. Ping: native Blizzard keybinds (no macro — status of the API)

**Measured in game (raid lead, live raid):**

```
/run C_Ping.SendMacroPing({type = Enum.PingSubjectType.Warning, targetToken = "player"})
-> error: "this action can only be used by the Blizzard UI" (forbidden action)
```

So the macro route is **dead**, by design of the client: the ping API is
restricted to Blizzard's own UI, from a macro as well as from an addon. What is
left, and what is now implemented:

- since Dragonflight 10.1.7 the player can bind **one key per ping**
  (Options > Keybindings > **ping system**), without opening the ping wheel;
- the addon **tells which ping to use** and reads the player's keybinds with
  `GetBindingKey` (<https://warcraft.wiki.gg/wiki/API_GetBindingKey>), **under
  `pcall`**, to display `PING: Warning - press Q`;
- if the lookup finds nothing (no key bound, or the binding command name is not
  the expected one), the panel shows **no key at all** and says
  `PING: Warning - set a keybind in Options > Keybindings`. It never shows a
  shortcut that does not exist;
- the **native ping keybinds DO exist, separately**, and were **MEASURED IN GAME
  by the raid lead (2026-09-22)** on a French client, under these labels
  (Options > Raccourcis):

| Raid label (what we say) | Ping system (EN client) | Ping system (FR client) |
|---|---|---|
| `Warning` — the ANCHOR ping (default policy) | Warning | **Avertissement** |
| `OnMyWay` | On My Way | **En route** |
| `Assist` | Assist | **Aide** |
| — (not used) | Ping / Standard, Attack / Help | Ping, Attaque, Aide |
| — | ping targeting | Activer le ciblage de ping |

  The **label displayed in game follows the language of the client** (`ping.name.*`
  in `Core/Locale.lua`): `PING: Warning` in English, `PING : Avertissement` in
  French. The **canonical identifier** (`Warning`, `OnMyWay`, `Assist`) never
  changes: it is what configuration, tests and binding candidates use. FR labels
  measured in game; EN labels from the ping system page
  (<https://warcraft.wiki.gg/wiki/Ping_System>).

- the **command names** of those keybinds, they, are **TO BE CONFIRMED IN GAME**:
  the client showed the labels, not the binding commands. So the candidates live
  in `Core/Intermission.lua` → `PING_BINDINGS` and are tried in order:

| State | Ping | Candidates tried, in order |
|---|---|---|
| `1V3R` | `Warning` | `PING_WARNING`, `PINGTYPE_WARNING`, `PINGSUBJECTTYPE_WARNING`, `BINDING_PING_WARNING` |
| `2V2R` | `OnMyWay` | `PING_ONMYWAY`, `PING_ON_MY_WAY`, `PINGTYPE_ONMYWAY`, `BINDING_PING_ONMYWAY` |
| `3V1R` | `Assist` | `PING_ASSIST`, `PING_HELP`, `PINGTYPE_ASSIST`, `BINDING_PING_ASSIST` |

  The lists stay **semantically pure**: a state never borrows the key of another
  ping (`PING_ATTACK` is deliberately absent — showing the Attack key for a
  `Warning` instruction would be a lie), even though « Attaque » and « Aide »
  exist as separate native keybinds.

`/gr inter ping` prints the chosen line **and the names that were tried**, which
is exactly what the in-game confirmation has to check (see §9).

## 5. Data contract (GIDEON → addon)

`GideonRaidDB.assignment` (written out of game, read by the addon):

```lua
GideonRaidDB = {
    schema = 1,
    assignment = {
        schema = 1,
        pairs = {
            { a = "Velna",  b = "Torgh" },
            { a = "Bathman", b = "Coren" },
        },
        -- OPTIONAL: plan prepared out of game (role / position per player).
        -- `role` = ORB COMPOSITION ("3V1R", "2V2R", "1V3R", "3 verts"),
        -- never a bare number 1/3 (ambiguous).
        plan = {
            { name = "Velna",   role = "2V2R", position = "MIDDLE" },
            { name = "Torgh",   role = "2V2R", position = "MIDDLE" },
            { name = "Bathman", role = "1V3R", position = "HOLD"   },
            { name = "Coren",   role = "3V1R", position = "PURSUE" },
        },
    },
}
```

- `plan` is **optional**: without it — and without any `assignment` at all — the
  addon only says, discreetly, `No out-of-game plan loaded (optional).` It never
  points the player to a chat command: the out-of-game plan is prepared by the
  GIDEON side, not by a command typed in game.
- `role` accepts the **orb composition** (`"1V3R"`, `"2V2R"`, `"3V1R"`, or a
  tolerated form such as `"3 verts"`) **or** a free raid role (`"Tank"`,
  `"Heal"`) — in the latter case the addon deduces no meeting from it. A bare
  number `"1"` or `"3"` is **ambiguous**: the addon writes it out
  (`Meeting cannot be verified: number 1 is ambiguous…`) instead of guessing.
- If both roles of a pair are compositions, the addon displays
  `Meeting 2V2R+2V2R: OK (safe combination (4 green + 4 red))` or
  `Meeting 3V1R+2V2R: DEAD (5 green = 5g: DEAD)`: that is a **check of the
  prepared plan**, not an in-game read.
- A malformed `plan` entry is ignored and counted ("Plan: 1 ignored entry(ies)."),
  never a crash.
- Contract fixture: `tests/fixtures/assignment_sample.lua`.

## 6. Configuration

In `GideonRaidDB.intermission` (values resolved and clamped by
`ns.Config.resolveIntermission`):

| Key | Default | Effect |
|---|---|---|
| `enabled` | `true` | enables/disables the whole module (`/gr inter on|off`) |
| `startOnEncounterStart` | `true` | arms the pre-computed schedule on `ENCOUNTER_START` |
| `autoShowPanel` | `true` | opens the panel when an intermission starts |
| `scale` | `1.0` | panel scale (clamped 0.5 – 3.0) |
| `leadSeconds` | `2` | the panel opens this many seconds BEFORE each intermission (clamped 0 – 10) |
| `visibilitySeconds` | `3` | visibility window (clamped 1 – 10) |
| `durationSeconds` | `20` | intermission duration, after which the panel closes itself (clamped, > visibility) |
| `scheduleSeconds` | `{46.3, 148.9, 251.5, 353.2}` | **pre-computed intermission times**, in seconds since the pull (positive numbers only, sorted, 12 entries max) |
| `pingMode` | `"anchors"` | **ping policy**: `anchors` (only the `1V3R` anchors ping), `color` (every state pings its own ping), `none` (nobody pings) — see `/gr ping`; an unknown value falls back to `"anchors"` |
| `position` | `CENTER` | panel position, saved on drag and drop (placement mode) |

Outside `intermission`, the top level of the SavedVariables holds the **language
preference**:

| Key | Default | Effect |
|---|---|---|
| `locale` | `"auto"` | in-game language: `"auto"` (follow the client), `"en"`, `"fr"` — see `/gr lang` |

## 7. Commands and keybinding

```
/gr                       main panel (plan + PLACE INTERMISSION PANEL button)
/gr plan                  detailed plan in the chat
/gr lang                  detected language, effective language, how to change
/gr lang auto|en|fr       rules on the language and persists it in the SavedVariables
/gr ping                  current ping policy and what it means for the roles
/gr ping anchors|color|none   rules on the PING POLICY and persists it (default anchors)
/gr inter                 shows/hides the intermission panel
/gr inter start|stop      starts/stops ONE intermission manually
/gr inter place           placement mode: drag the panel, prepare the ping, press OK
/gr inter ping            which ping to use, which key, and the binding names tried
/gr inter 3V1R            declares your COMPOSITION (also: 2V2R, 1V3R, "3 verts")
/gr inter 2               only "2" is accepted as a number (unambiguous)
/gr inter on | off        enables/disables the module
/gr inter status          module state + timeline + schedule
```

`/gr inter 1` or `/gr inter 3` are **refused** with a message asking for the
dominant color: the module never guesses the composition from the number.
`/gr ping` with an unknown value is refused the same way (nothing is persisted).
`/gr inter macro` **no longer exists**: the macro route is dead (see §4).

A **binding** `GIDEONRAID_INTERMISSION` (no default key) is declared in
`Bindings.xml`: assign it in *Options > Keybindings > GideonRaid*. It only opens
the panel; the ping keybinds are the client's own (ping system).

## 8. Out-of-game tests

```bash
busted                                    # 160 tests, 78 for this module + 20 for the ping policy
lua5.1 tools/intermission_cli.lua all     # the 3 states + action lines
lua5.1 tools/intermission_cli.lua roles   # the 3 states under the 3 ping policies
lua5.1 tools/intermission_cli.lua 3V1R    # one state
lua5.1 tools/intermission_cli.lua 3V1R color Q   # one state, explicit policy and simulated key
lua5.1 tools/intermission_cli.lua 1       # -> REFUS : numéro ambigu
lua5.1 tools/intermission_cli.lua run     # replay of the pre-computed schedule
lua5.1 tools/intermission_cli.lua pair 3V1R 2V2R    # -> MORT (5 verts)
lua5.1 tools/intermission_cli.lua plan Velna [fixture] [anchors|color|none]
```

(The CLI is a developer tool and keeps printing French; only the in-game text is
translated. The key it prints is SIMULATED — the real key is read in game with
`GetBindingKey`.)

Covered by `tests/spec/intermission_spec.lua` (78 tests):

- the three color states (label, green/red counts, possible numbers, ping,
  complement, role, button label, the **ONE action line**) and their
  deterministic order — in the default language (English) **and** in the explicit
  French variant;
- tolerant normalization (`3V1R`, `2v2r`, `1 V 3 R`, `vert-vert-vert-rouge`,
  `vvrr`, `3 verts`, `1 vert 3 rouges`, "vert" = dominant), and the **explicit
  refusal** of "1" or "3" alone (message "ambiguous", never a guess);
- the collisions by color addition: `3V1R+1V3R` safe, `2V2R+2V2R` safe,
  `3V1R+2V2R` forbidden (5 green), `1V3R+1V3R` and `3V1R+3V1R` forbidden;
- **the ping**: the candidate binding names per state, `pingHint` with a key
  (`PING: Warning - press Q`), without a key and with an empty/absurd key
  (`set a keybind in Options > Keybindings`), the refusal for a state that must
  not ping or on an ambiguous number, the **injected resolver** (the key is never
  read by Core/), a resolver that raises or returns a non-string, and the
  disappearance of the macro generation (`buildMacro` == nil);
- **the pre-computed schedule**: the raid lead's values, normalization of a
  persisted schedule (sorted, positive, capped), the opening time
  (`intermission - lead`), "nothing opens before", "one opening per
  intermission", **no skip even with a huge dt**, reset and determinism;
- the state machine: `IDLE → PENDING (lead) → VISIBLE (3 s) → DARK → DONE`,
  the countdown, the declaration during PENDING/VISIBLE/DARK, the refusal before
  the start / on an ambiguous number / after the end, **REDO**
  (`clearDeclaration`, idempotent, refused when nothing is declared), `reset`,
  negative `dt` ignored, determinism;
- the **minimal content of the panel**: state, role line, `PING: YES/NO` banner
  (with the ping color), one action line, at most three short lines, and the
  **disappearance** of the old verbose lines (ROLE ORDER / PING POLICY / STATE
  THAT JOINS YOU / caveats);
- the **placement view** (drag, ping keybinding reminder, lead, plan or
  "no plan");
- the pre-pull view (partner, role, position, sorted pairs, malformed plan, safe
  / deadly / **unverifiable** meeting when a role stays ambiguous, ping to use
  deduced from the prepared composition);
- the configuration (bounds incl. `leadSeconds`, inconsistent types, normalized
  schedule, no alias between accounts, no `macroTargetToken` any more).

Covered by `tests/spec/pingpolicy_spec.lua` (20 tests): the role of each state
(ANCHOR/MIDDLE/CHASER, never deduced from the number), the default policy where
**only `1V3R` pings**, `color` where the three states ping their own ping,
`none` where nobody pings, the wording of each action line, an unknown policy
resolved to `anchors`, the refusal to name a ping for a role that must not ping,
the persistence of `/gr ping`, the refusal of an unknown value, and the fact
that **the policy is no longer displayed permanently** on the panel.

Covered by `tests/spec/load_spec.lua` (24 tests, real loading, `.toc` order):
`ADDON_LOADED` creates the SavedVariables (schedule and lead included),
`PLAYER_LOGIN` renders the plan, the main panel shows the discreet
"no out-of-game plan" line and **never** a non-existent command, the **placement
mode** (button + OK + saved position), `ENCOUNTER_START` **arms** the schedule
without opening the panel, the panel **opens by itself** before the first
intermission, the click displays the essential, **REDO** corrects it several
times, the ping key is displayed when bound (and the fallback line when not, or
when `GetBindingKey` raises), the panel **closes by itself** at the end,
**reopens** at the next intermission, `ENCOUNTER_END` disarms everything,
disabling is honoured and the panel never displays a dynamic value.

Covered by `tests/spec/guard_spec.lua` (6 tests, anti-forbidden-API guard): no
file listed in the `.toc` contains `COMBAT_LOG_EVENT`, `UnitAura`, `UnitBuff`,
`UnitDebuff`, `UnitGUID`, `SendChatMessage`, `GetRaidRosterInfo`, `C_VoiceChat`
outside a comment; **no ping API at all** (`C_Ping`, `SendMacroPing`,
`PingSubjectType`) even inside a string; `buildMacro` is gone; `Core/` stays free
of `GetTime`, `math.random`, `CreateFrame`, `UnitName`, `GideonRaidDB` **and of
the binding lookup**; and the binding lookup, when present, is **only in `UI/`
and only under `pcall`**.

Covered by `tests/spec/locale_spec.lua` (21 tests): default English, every key
served in **both** languages, `GetLocale()` returning `"frFR"` → French,
`"enUS"`/`"deDE"` → English, explicit override beating detection, unknown value →
English, the auto-preference following the client, `/gr lang` printing the
detected / effective / preferred language, `/gr lang fr|en|auto` persisted in the
SavedVariables, refusal of an unknown value, missing key → the key itself, no
exception.

## 9. To be confirmed in game (honest list)

1. **Exact binding command names of the ping keybinds** — THE priority item
   (the keybinds themselves ARE confirmed to exist: §4). Bind each ping in
   *Options > Keybindings > ping system*, then run `/gr inter ping` after
   declaring an `1V3R`/`2V2R`/`3V1R`: the line shows the key only if one of the
   candidates of §4 is the real command name. If no key is displayed, dump the
   real names (`/dump GetBindingKey("PING_WARNING")`, `GetBindingName`,
   `/dump C_KeyBindings` or the frame XML of the ping system) and replace
   `PING_BINDINGS` in `Core/Intermission.lua` (plus the tests and §4 here).
2. ~~Number of pings per player~~ — **MEASURED in game by the raid lead
   (2026-09-22): 3 pings in a row, then about 5 s of wait, then 3 again.** No
   longer to be confirmed (see §2.1 for the design argument it validates). Still
   open, on the other hand: the **display duration of a ping on the raid frames
   since patch 12.1** — does a ping stay visible on the frame long enough for a
   CHASER to run to it *after* the room darkens? See `docs/TESTPLAN.md` §3.5.
3. **Exact intermission timings measured from `ENCOUNTER_START`**: the schedule
   (46.3 s then 148.9 / 251.5 / 353.2 s) and the `leadSeconds = 2` are the raid
   lead's measurements; the diagnostic kit (`GideonDiagAddon`) records the
   decision timestamps, which is what validates or corrects them.
4. **Real duration of an intermission** (`durationSeconds`, default 20 s): it
   decides when the panel closes by itself.
5. The binding `GIDEONRAID_INTERMISSION` showing up in *Options > Keybindings*
   (an XML file cannot be tested outside the client) and the `header` behaviour.
6. **Client language detection**: validate `GetLocale()`
   (<https://warcraft.wiki.gg/wiki/API:GetLocale>) **once on a frFR client**
   (French must be served with the `auto` preference) **and once on an enUS
   client** (English must be served). The out-of-game tests cover the two cases
   with a stubbed `GetLocale`, but only an in-client run proves the real return
   value.
7. Real readability of the stripped-down panel during the darkening (type size,
   default position) — not verifiable outside the client.
8. Final guild convention (position, ping vs `/say`): the table of §2 and the
   `CONVENTION` table of `Core/Intermission.lua` are the single source; if they
   change, change `CONVENTION` (and the tests) — never the UI.
9. Link between the **displayed number** and the **mark** (Mark of Acid / Mark of
   Blood): measured in game by the `GideonDiagAddon` diagnostic kit
   (`/gdiagmark`), which records **number + composition** per intermission.
