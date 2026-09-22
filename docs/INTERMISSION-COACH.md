# Intermission Coach — Entombed Sentinels (mythic)

"Intermission Coach" module of GideonRaid: it makes the **coordination of the
Entombed Sentinels intermission** (raid *The Venomous Abyss*, Midnight 12.1.0)
possible and fast **with minimal player action**, without ever reading a combat
API.

Reference guide:
<https://raidstrats.gg/guides/entombed-sentinels/mythic/phase/quick-overview>

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

> **Assumed correction.** The previous model bound `1 ↔ 1 green + 3 red` and
> `3 ↔ 3 green + 1 red`, with a position and a ping deduced from the number:
> that was **wrong** (numbers 1 and 3 are ambiguous). The module now asks for
> **the composition actually seen**; a declaration reduced to "1" or "3" is
> **refused** with a message asking for the dominant color — the code never
> guesses.

## 2. The three states (explicit and configurable convention)

`CONVENTION` table of `Core/Intermission.lua` (single source of truth):

| State | Composition | Possible number(s) | Role | Position | Ping | Color | Must be joined by |
|---|---|---|---|---|---|---|---|
| `1V3R` | 1 green + 3 red | **1 or 3** (ambiguous) | **ANCHOR** | **HOLD**, where you are | `Enum.PingSubjectType.Warning` | **RED** | `3V1R` |
| `2V2R` | 2 green + 2 red | **2** (unambiguous) | **MID** | **MIDDLE / under the boss** | `Enum.PingSubjectType.OnMyWay` | **BLUE** | `2V2R` |
| `3V1R` | 3 green + 1 red | **1 or 3** (ambiguous) | **CHASER** | **go and stick to a `1V3R`** | `Enum.PingSubjectType.Assist` | **GREEN** | `1V3R` |

Each state also carries: the visual label ("3 GREEN + 1 RED", "3 VERTS +
1 ROUGE" in French), the number of green and red orbs (basis of the survival
computation), the operational instruction, the button text (number as a hint)
and the guild rule recalled for that number. **Every displayed field of a
`CONVENTION` record is a locale key** (`state.action.3V1R`, …) resolved by
`copyRecord` through `ns.Locale.t`, so `/gr lang` applies without a reload.
The ping role adds three more per-state fields (`role`, `orderPing`,
`orderNoPing` + the `pingYes`/`pingNo` lines), resolved the same way.

**Ping**: raidstrats guide convention, **by dominant color** — 3 green →
`Assist` (green), 2-2 → `OnMyWay` (blue), 3 red → `Warning` (red). Those colors
are verified on the wiki gallery
(<https://warcraft.wiki.gg/wiki/Ping_System>): `Warning` = red panel,
`OnMyWay` = blue arrow, `Assist` = green flag. **Which state actually pings is
decided by the ping policy, not by the color alone** — see §2.1.

**Positions**: the **positional** lines of the raidstrats guide **contradict each
other** (they give both "1 green 3 red → left" and "3 red 1 green → right"). Our
convention is therefore **explicit and configurable**, and it is the only one
consistent with "the color decides": the **fixed** point is the **red**-majority
state (`1V3R`, RED ping), the **runner** is the **green**-majority state
(`3V1R`, GREEN ping), the `2V2R` go to the middle. Default guild convention,
recalled on screen for every state: **"2" → middle / under the boss; "1" → hold +
ping; "3" → joins a "1" with the complementary color**. If the guild changes the
convention, change `CONVENTION` (and the tests) — never the UI.

### 2.1 Ping roles by STATE (raid-lead decision)

The duty comes from the **state** (the orb composition), never from the number
displayed above the head: 1 and 3 are ambiguous, and a role deduced from them
would be wrong half of the time. Every canonical state therefore carries an
explicit **`role`** in `CONVENTION`:

| State | `role` | Verdict | Operational order (EN / FR) |
|---|---|---|---|
| `1V3R` | `ANCHOR` | **pings** (default policy) | "STAY WHERE YOU ARE, place a ping on yourself (macro) or get pinged by another player, DO NOT MOVE." / "RESTE SUR PLACE, place un ping sur toi (macro) ou fais-toi pinger par un autre joueur, NE BOUGE PAS." |
| `2V2R` | `MID` | does not ping | "Do NOT ping: go to the MIDDLE / under the boss and pair up with another 2V2R." / "Ne ping PAS : va au MILIEU / sous le boss et apparie-toi avec un autre 2V2R." |
| `3V1R` | `CHASER` | does not ping | "Do NOT ping: spot a ping and run to it (any 1V3R works)." / "Ne ping PAS : repere un ping et fonce dessus (n'importe quel 1V3R fait l'affaire)." |

**Why this rule (the "8 pings instead of 20" argument):** if every state pings
its own color, a 20-player raid produces ~**20 pings** in a few seconds — the
channel becomes unreadable and the client's own **per-player ping limit** (a
burst of about 3 pings; exact value **to be confirmed in game**, see
`docs/TESTPLAN.md`) swallows part of them. Restricting the ping to the anchors
gives **one ping per anchor, 4 per side → at most ~8 pings in the whole raid**,
and every ping is meaningful (an anchor is a landmark a chaser can run to).

Three points make this rule playable:

1. **An ANCHOR can be pinged by somebody else.** The macro is only a
   convenience: any other player of the raid (a chaser passing by, a player who
   still sees the anchor during the 3 s window) can ping the anchor. What
   matters is that the anchor does not move and that **one** ping locates it.
2. **Pings are visible on the raid frames since patch 12.1**, so a chaser can
   locate an anchored player from the frames even after the room darkens — still
   with no addon → addon communication (which does not exist in instances).
3. **The addon never pings.** `C_Ping.SendMacroPing` is `#protected`: the addon
   only GENERATES the macro text, and it generates it **only for a role that has
   to ping** under the current policy. A `MID` or a `CHASER` under `anchors` has
   no macro area at all: the panel shows why ("No ping for this role under the
   current policy").

### 2.2 Ping policies (configurable: `/gr ping`)

The policy is persisted in `GideonRaidDB.intermission.pingMode` and resolved by
the pure, total `ns.Config.resolvePingMode` (an unknown value — absent, typo,
hand-edited SavedVariables — falls back to `anchors`, never an error):

| Policy | Who pings | Ping color |
|---|---|---|
| `anchors` (**default**) | only the `1V3R` ANCHORS | red (`Warning`) |
| `color` (raidstrats variant) | every state | `1V3R` red/`Warning`, `2V2R` blue/`OnMyWay`, `3V1R` green/`Assist` |
| `none` | nobody (positions only) | — |

The role never changes with the policy (a `3V1R` is always the `CHASER`): only
the ping decision and **the wording of the role order** adapt, so a role never
receives a contradictory instruction. In `color` mode the `CHASER`/`MID` keep
their movement order and simply ping their own color on the way.

## 3. What the addon does / can NOT do (to be told to the players as is)

**It can:**

- display the plan prepared out of game (partner, role, position, pairs);
- display a very large reminder of the convention on trigger;
- display 3 buttons named after the **visible composition** — `1 green + 3 red`,
  `2 green + 2 red`, `3 green + 1 red` — with the **number as a hint** ("1 or 3",
  "2"): the player clicks the composition, and **the matching instruction appears
  immediately** (what you have, what you must do, which state to join, the ping,
  and the reminder that "1" or "3" alone is not enough);
- display the **3 s countdown** (visibility window) then report that the room went
  dark;
- display the **ping role** of the declared state, the "**PING: YES/NO**" banner
  (colored with the ping color of the state) and the **role order** — under the
  default `anchors` policy that reads: ANCHOR "stay where you are, ping yourself
  (macro) or get pinged, do not move", MIDDLE and CHASER "do not ping";
- **generate the ping macro** ready to paste, **only for a role that must ping**
  under the configured policy. The other roles see the reason instead of a macro
  they must not use.

**It can NOT (12.x constraints, to be assumed):**

- read another player's auras / indicators (secret values) —
  <https://warcraft.wiki.gg/wiki/Secret_Values>;
- read **its own** in a usable way: it is the player who declares;
- send a ping itself: `C_Ping.SendMacroPing` is **#protected** ("This can only be
  called from secure code") —
  <https://warcraft.wiki.gg/wiki/API:C_Ping.SendMacroPing>;
- **know who declared what**: no addon→addon channel in an instance, and an
  addon's UI is local to its client. The UI says it in so many words
  (French: "INCONNU : personne ne peut lire ton numero ni te dire qui a declare
  quoi" / English: "UNKNOWN: nobody can read your number or tell you who
  declared what");
- display a text visible to the other players: **the ping is the only signal**
  the others see.

In other words: **nothing is automatic in this addon**. Everything displayed
comes from a player click or from a file prepared out of game.

Everything above is displayed in the **effective language** (English by default,
French on a frFR client — see `README.md` §4 and `docs/CONVENTIONS.md` §11). Only
the **spell, orb and color names** are identical in both languages.

## 4. Ping macro (status: **to be confirmed in game**)

The addon generates and displays the exact text to paste into a macro:

```
/run C_Ping.SendMacroPing({type = Enum.PingSubjectType.Warning, targetToken = "player"})
```

- `C_Ping.SendMacroPing(macroInfo)` in 12.1.0 takes a **structure** (`type`,
  `targetToken`, `spellID`, `itemID`) —
  <https://warcraft.wiki.gg/wiki/API:C_Ping.SendMacroPing>; the values of
  `Enum.PingSubjectType` (0 Attack, 1 Warning, 2 Assist, 3 OnMyWay, …) are
  verified on <https://warcraft.wiki.gg/wiki/Enum.PingSubjectType>.
- Generated fallback variant: `/ping Warning` (existing macro command, seen in
  real usage; **the wiki has no `MACRO ping` page**, so the exact case and token
  are to be confirmed).
- The macro text itself is language-independent: only the "to be confirmed" note
  around it is translated.
- **To be confirmed in game:** (1) the call from a macro is indeed allowed,
  (2) `targetToken = "player"` indeed produces a ping on yourself (icon above the
  head / raid frame), (3) the token of the `/ping` variant.

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

- `plan` is **optional**: without it, the addon only displays the partner and the
  list of pairs.
- `role` accepts the **orb composition** (`"1V3R"`, `"2V2R"`, `"3V1R"`, or a
  tolerated form such as `"3 verts"`) **or** a free raid role (`"Tank"`,
  `"Heal"`) — in the latter case the addon deduces no meeting from it. A bare
  number `"1"` or `"3"` is **ambiguous**: the addon writes it out (French:
  `Rencontre non verifiable : numero 1 ambigu…` / English: `Meeting cannot be
  verified: number 1 is ambiguous…`) instead of guessing.
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
| `startOnEncounterStart` | `true` | starts the timeline on `ENCOUNTER_START` |
| `autoShowPanel` | `true` | opens the panel on trigger |
| `scale` | `1.0` | panel scale (clamped 0.5 – 3.0) |
| `visibilitySeconds` | `3` | visibility window (clamped 1 – 10) |
| `durationSeconds` | `20` | total intermission duration (clamped, > visibility) |
| `macroTargetToken` | `"player"` | target token of the ping macro |
| `pingMode` | `"anchors"` | **ping policy**: `"anchors"` (only the `1V3R` anchors ping, default), `"color"` (every state pings its own color), `"none"` (nobody pings) — see `/gr ping`; an unknown value falls back to `"anchors"` (never an error) |
| `position` | `CENTER` | panel position, saved on drag and drop |

Outside `intermission`, the top level of the SavedVariables holds the **language
preference**:

| Key | Default | Effect |
|---|---|---|
| `locale` | `"auto"` | in-game language: `"auto"` (follow the client), `"en"`, `"fr"` — see `/gr lang` |

## 7. Commands and keybinding

```
/gr                       main panel (plan prepared out of game)
/gr plan                  detailed plan in the chat
/gr lang                  detected language, effective language, how to change
/gr lang auto|en|fr       rules on the language and persists it in the SavedVariables
/gr ping                  current ping policy and what it means for the roles
/gr ping anchors|color|none   rules on the PING POLICY and persists it (default anchors)
/gr inter                 shows/hides the intermission panel
/gr inter start|stop      starts/stops the pre-computed timeline
/gr inter 3V1R            declares your COMPOSITION (also: 2V2R, 1V3R, "3 verts")
/gr inter 2               only "2" is accepted as a number (unambiguous)
/gr inter macro           displays the matching ping macro
/gr inter on | off        enables/disables the module
/gr inter status          module state + timeline
```

`/gr inter 1` or `/gr inter 3` are **refused** with a message asking for the
dominant color: the module never guesses the composition from the number.
`/gr ping` with an unknown value is refused the same way (nothing is persisted).

A **binding** `GIDEONRAID_INTERMISSION` (no default key) is declared in
`Bindings.xml`: assign it in *Options > Keybindings > GideonRaid*. The body of
the binding is Lua executed **insecurely** (see
<https://warcraft.wiki.gg/wiki/Creating_key_bindings>): it opens the panel, and
cannot — must not — send a ping.

## 8. Out-of-game tests

```bash
busted                                    # 138 tests, 65 for this module + 19 for the ping policy
lua5.1 tools/intermission_cli.lua all     # the 3 states + macros (default policy)
lua5.1 tools/intermission_cli.lua roles   # the 3 states under the 3 ping policies
lua5.1 tools/intermission_cli.lua 3V1R    # one state
lua5.1 tools/intermission_cli.lua 3V1R color   # one state, explicit policy
lua5.1 tools/intermission_cli.lua 1       # -> REFUS : numéro ambigu
lua5.1 tools/intermission_cli.lua pair 3V1R 2V2R    # -> MORT (5 verts)
lua5.1 tools/intermission_cli.lua plan Velna [fixture] [anchors|color|none]
```

(The CLI is a developer tool and keeps printing French; only the in-game text is
translated.)

Covered by `tests/spec/intermission_spec.lua`:

- the three color states (label, green/red counts, possible numbers, ping,
  complement, instruction) and their deterministic order — in the default
  language (English) **and** in the explicit French variant;
- tolerant normalization (`3V1R`, `2v2r`, `1 V 3 R`, `vert-vert-vert-rouge`,
  `vvrr`, `3 verts`, `1 vert 3 rouges`, "vert" = dominant), and the **explicit
  refusal** of "1" or "3" alone (message "ambiguous", never a guess);
- the collisions by color addition: `3V1R+1V3R` safe, `2V2R+2V2R` safe,
  `3V1R+2V2R` forbidden (5 green), `1V3R+1V3R` and `3V1R+3V1R` forbidden;
- the macro generation (by dominant color), the absence of forbidden event text,
  and the refusal to build a macro on an ambiguous number;
- the state machine: `IDLE → VISIBLE (3 s) → DARK → DONE`, declaration before
  start / after the end refused, `reset`, negative `dt` ignored, determinism;
- the prepared timeline (bounds, `duration > visibility`);
- the **ping roles and policies** (`tests/spec/pingpolicy_spec.lua`, 19 tests):
  the role of each state (ANCHOR/MID/CHASER, never deduced from the number), the
  default policy where **only `1V3R` pings**, `color` where the three states ping
  with their own color (red/Warning, blue/OnMyWay, green/Assist), `none` where
  nobody pings, the wording of each role order (anchor "do not move", chaser "run
  to a ping", middle "another 2V2R"), an unknown policy resolved to `anchors`,
  the refusal to build a macro for a role that must not ping, the persistence of
  `/gr ping` and the refusal of an unknown value;
- the pre-pull view (partner, role, position, sorted pairs, malformed plan, safe
  / deadly / **unverifiable** meeting when a role stays ambiguous);
- the configuration (bounds, inconsistent types, no alias between accounts).

Covered by `tests/spec/load_spec.lua` (real loading, `.toc` order):
`ENCOUNTER_START` opens the panel, the three buttons carry the composition and
the number as a hint, clicking a button displays the instruction, the ticker
switches to the darkened room after 3 s, `ENCOUNTER_END` closes the panel,
disabling is honoured, the panel displays no dynamic value.

Covered by `tests/spec/guard_spec.lua` (anti-forbidden-API guard): no file listed
in the `.toc` contains `COMBAT_LOG_EVENT`, `UnitAura`, `UnitBuff`, `UnitDebuff`,
`UnitGUID`, `SendChatMessage`, `GetRaidRosterInfo`, `C_VoiceChat` outside a
comment; `C_Ping` / `SendMacroPing` **never appear as a call** (only inside the
macro **text**, which is secure code triggered by the player); `Core/` stays free
of `GetTime`, `math.random`, `CreateFrame`, `UnitName` and `GideonRaidDB`.

Covered by `tests/spec/locale_spec.lua` (language layer): default English,
`GetLocale()` returning `"frFR"` → French, `"enUS"`/`"deDE"` → English, explicit
override beating detection, unknown value → English, the auto-preference
following the client, `/gr lang` printing the detected / effective / preferred
language, `/gr lang fr|en|auto` persisted in the SavedVariables, refusal of an
unknown value, missing key → the key itself, no exception.

## 9. To be confirmed in game (honest list)

1. Exact syntax of the ping macro (calling `C_Ping.SendMacroPing` from a macro,
   semantics of `targetToken = "player"`, token of the `/ping` variant).
2. The binding `GIDEONRAID_INTERMISSION` showing up in *Options > Keybindings*
   (an XML file cannot be tested outside the client) and the `header` behaviour.
3. **Client language detection**: validate `GetLocale()`
   (<https://warcraft.wiki.gg/wiki/API:GetLocale>) **once on a frFR client**
   (French must be served with the `auto` preference) **and once on an enUS
   client** (English must be served). The out-of-game tests cover the two cases
   with a stubbed `GetLocale`, but only an in-client run proves the real return
   value.
4. Real readability of the panel during the darkening (size, default position) —
   not verifiable outside the client.
5. Exact intermission duration: `durationSeconds` is a default **to be tuned**
   after the first pulls.
6. Final guild convention (position, ping vs `/say`): the table of §2 and the
   `CONVENTION` table of `Core/Intermission.lua` are the single source; if they
   change, change `CONVENTION` (and the tests) — never the UI. The positional
   lines of the raidstrats guide contradicting each other, our choice (red =
   fixed point, green = runner, 2-2 = middle) is explicit and revisable.
7. Link between the **displayed number** and the **mark** (Mark of Acid / Mark of
   Blood): measured in game by the `GideonDiagAddon` diagnostic kit
   (`/gdiagmark`), which now records **number + composition** per intermission.
8. **Ping behaviour** (the "anchors" policy rests on it): the **exact number of
   pings a single player may send in a row** (a burst of about 3 is the current
   assumption), what the client does beyond that limit, and the **display of
   pings on the raid frames since patch 12.1** (does a ping stay visible on the
   frame long enough for a CHASER to run to it after the room darkens?). Those
   three points are also listed in `docs/TESTPLAN.md` §3.5 (in-game protocol).
