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
| `1V3R` | `ANCHOR` | **pings** (default policy) | "PING: YES - hover YOUR OWN character frame then press your ping key (Warning), stay put and jump on the spot" |
| `2V2R` | `MIDDLE` | does not ping | "DO NOT PING - go to the middle / under the boss" |
| `3V1R` | `CHASER` | does not ping | "DO NOT PING - run to a ping (a 1V3R)" |

(French: "PING : OUI - survole TON propre cadre de personnage puis appuie sur ta
touche de ping (Avertissement), reste sur place et saute sur place" / "NE PING PAS
- va au milieu / sous le boss" / "NE PING PAS - fonce sur un ping (un 1V3R)".)

**The ANCHOR line now states the REAL gesture, not a vague order.** Measured in
game by the raid lead (third in-game test): **the ping lands where the MOUSE is**,
and pinging your **own character frame** (the unit frame with your health bar)
**pings yourself**. The action line therefore says exactly what to do — hover YOUR
OWN frame, press the ping key — instead of the former "ping yourself", which never
told *how*.

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
| d | clicks the composition seen above their head | state in very large type, role, `PING: YES/NO`, one action line. **The three composition buttons then disappear** — only the result and the **REDO** button stay, so a second click by accident is impossible; REDO brings the three choices back (empty state), as many times as needed |
| e | — | at the end of the intermission the panel **closes by itself** |
| f | next intermission | same cycle, **automatically** (schedule: 46.3 s, then 148.9 / 251.5 / 353.2 s after the pull) |

The schedule lives in `GideonRaidDB.intermission.scheduleSeconds` (sorted,
bounded, 12 entries max) and can be replaced out of game. The state machine is
pure and time is **injected**: `Intermission.tick(state, dt)` and
`Intermission.advanceRun(run, dt)` never read the client clock.

### 2.4 SIMULATION mode (rehearse ALONE: no boss, no raid)

The raid lead must be able to rehearse the intermission **without a boss and
without a raid** (to learn the flow, to check the panel, to test the ping keys).
Two entries, both reachable **from the main panel (the two SIMULATION buttons) and
from the chat**, driven by the pure module `Core/Simulation.lua`:

| Entry | Command (aliases) | What happens |
|---|---|---|
| **Intermission group** | `/gr sim inter` (`sim group`, `sim groupe`) | the intermission panel **opens RIGHT AWAY** (fourth in-game feedback: the former 3 s delay is gone), the player clicks the composition they see, reads the state / role / `PING: YES/NO` / the action line, corrects it with **REDO**, and **closes the panel themselves** (close cross or Close button). **ONE single cycle**: nothing closes it automatically, nothing relaunches it, and the chat reports it when it closes; `/gr sim stop` does the same |
| **Ping help** | `/gr sim ping` (= `/gr pinghelp`) | a **short information window** (draggable, position persisted, closable with its Close button or the cross) that explains **how to bind one key per ping** (`Options > Keybindings > Ping`) and the **operational reminder** - `PING: YES = PING YOURSELF`: hover YOUR OWN character frame, press your key, and you ping yourself. There is **no guided sequence any more** (fourth in-game feedback): no countdown, no `PING PLACED` button, no `Avertissement -> En route -> Aide` progression, no announced-ping counter |
| Leave | `/gr sim stop`, the **Close** button or the close cross | closes the rehearsal or the help window and gives an honest report |

**What the rehearsal banner says.** A rehearsal is a **single cycle the player
closes**, so the panel carries a **two-line** banner:

```
SIMULATION - NO BOSS, NO RAID
SINGLE REHEARSAL - YOU CLOSE THE PANEL YOURSELF
```

The banner therefore announces exactly what the rehearsal does, and it can never be
mistaken for a real fight. The **combat headline is replaced** during a rehearsal
(`SIMULATION: NO ORB TO READ - CLICK THE COMPOSITION YOU SEE ABOVE YOUR HEAD`):
without a boss there is **no orb to read and no clock**, so the countdown
(`LOOK AT THE ORB COLOR ABOVE THE HEADS: 0 s`) is gone instead of contradicting
what the player sees - the note below it explains that in a real fight this line
counts the seconds.

**The ping help teaches the SELF-PING gesture and how to bind the keys.** Measured
in game by the raid lead: the ping lands **where the mouse is**, so hovering **your
own character frame** pings **you**. The window therefore states, in both
languages:

- `1. Bind one key per ping: Options > Keybindings > Ping (Ping, Warning, On My
  Way, Assist)` - the **real client path**, in the player's own language
  (`Options > Raccourcis > Ping` in French);
- `2. During the boss, when this panel says PING: YES, hover YOUR OWN character
  frame (the one with your health bar) then press your key: you ping yourself,
  where you stand.`
- the headline `PING: YES = PING YOURSELF` (`PING : OUI = PINGE-TOI TOI-MEME`), so
  the rule is readable at a glance;
- `Keys found for your pings:` followed by one line per ping
  (`Warning = Q` / `On My Way = no key bound (Options > Keybindings > Ping)`): the
  key the player **really bound**, read with `GetBindingKey` under `pcall` by the
  rendering layer and injected into `Core/` - a ping with no key says so honestly,
  never an invented shortcut.

**What the ping help does NOT claim.** The addon **cannot detect a ping** - no game
API reports one (see §4) - and it **never sends one**. The window states it as is:

- `This is exactly the ANCHOR (1V3R) gesture during the intermission: ping
  yourself where you stand.`
- `REMINDER: pings only show on screen while you are in a GROUP or a RAID.
  Alone, nothing appears.`
- `The addon CANNOT detect a ping: no game API reports one. Only you can check
  your screen.`

Only the player can check their own screen: the window **counts nothing** and
**times nothing** (it owns no state and starts no clock).

**Isolation (enforced by `tests/spec/guard_spec.lua`).** A simulation owns its own
run and state and:

- never arms, disarms or advances the pre-computed `ENCOUNTER_START` timeline
  (`Core/Simulation.lua` must not reference `ENCOUNTER_START`,
  `Intermission.newRun`, `advanceRun`, `resetRun` or `RegisterEvent`);
- never publishes a decision in the SavedVariables — the diagnostic kit must never
  read a rehearsal as a real choice;
- is **refused while the real flow is running** (intermission in progress or
  timeline armed), and **stopped the moment a real encounter starts**;
- takes **no option at all** (the former `cycles=N` is gone: one single cycle, the
  player closes it) and refuses anything else: a trailing token
  (`/gr sim inter cycles=3`), an unknown sub-command (`/gr sim bidon`) or a
  non-table argument are **rejected with a message**, never guessed;
- the rehearsal **arms no clock at all**: it owns no ticker, so nothing in it can
  advance, close or relaunch the panel on its own.

**The close cross ("X").** Both panels (main and intermission) have a close cross
in the top right corner (label and tooltip from `Core/Locale.lua`:
`ui.closeCross` = `X`, `ui.closeTooltip` = `Close` / `Fermer`). On the intermission
panel it **cancels the placement** during placement mode (same effect as the Close
button), **closes the rehearsal** during a simulation (same as the Close button),
closes the ping help window, and otherwise **only hides the panel**: the
intermission clock keeps running, the panel still closes by itself at the end of
the intermission and **opens again at the next one**. The cross is a **real button
in the layout** (`Core/Layout.lua` reserves its corner): no line may be drawn under
it in either language.

### 2.5 Movable panels (persisted position + Lock/Unlock)

In-game feedback: **the main panel could not be moved at all**, because
`GideonRaidDB.lockPanel` was hard-coded to `true` and the drag handler refused
every `StartMoving`. Three panels are now **draggable by default** and each one
remembers where the player left it:

| Panel | SavedVariables key | Restored |
|---|---|---|
| main panel (`/gr`) | `GideonRaidDB.panelPosition` | at `ADDON_LOADED` and every time the panel is shown |
| intermission panel | `GideonRaidDB.intermission.position` | on placement, opening and `/gr show` |
| ping help window | `GideonRaidDB.pingPanelPosition` | before each opening |

Each position is a `{ point, relativePoint, x, y }` block, saved on **drag stop**
(no confirmation needed) and read back through the **pure, total**
`ns.Config.resolvePosition`, which only ever returns a known anchor point
(`Config.POSITION_POINTS`): a hand-edited SavedVariables holding `point = "BANANA"`
falls back to `CENTER` instead of raising inside `SetPoint`.

**Lock / unlock.** `/gr lock` and `/gr unlock` (same effect as the **LOCK PANEL /
UNLOCK PANEL** button of the main panel) freeze or free every panel; the choice is
persisted in `GideonRaidDB.lockPanel` and survives a `/reload`. `/gr resetposition`
brings the three panels back to the center of the screen. Dragging a locked panel
prints a hint instead of doing nothing silently.

**Soft migration (one time).** Every SavedVariables written by an earlier version
carries `lockPanel = true` — the **old hard-coded default**, which no player could
change (no command existed) — and no schema marker. On the first load after the
update, `Config.ensureDB` sees `panelSchema ~= Config.PANEL_SCHEMA`, forces
`lockPanel = false` **once**, and stamps the schema. From then on the player's own
choice (`/gr lock`) is respected, and a **non-boolean** value (hand-edited file)
counts as "not locked": the resolver is total, it never raises and never locks the
player out.

### 2.6 Readable panels - the layout is COMPUTED in `Core/` and applied as is

The fourth in-game test showed two layout bugs: **the main panel text ran over the
frame** (French labels are longer than English ones) and **the intermission panel
drew its big state on top of the SIMULATION banner** (fixed pixel offsets that could
collide). The fix is structural: the geometry of every panel is now **computed by a
pure module** (`Core/Layout.lua`) and simply **copied** by the rendering layer.

```
Core/Layout.lua   -> an ORDERED list of blocks, anchored one under the other
UI/Panel.lua      -> UI.ApplyLayout(target, layout, elements): clears everything,
                     then copies point/size/label block by block
```

Rules enforced by `tests/spec/layout_spec.lua` (16 tests) **in both languages**:

- **stacking**: every block is anchored **below** the previous one
  (`top = previous.bottom - gap`), never at an absolute offset that could collide -
  the exact bug of the fourth test (the state drawn over the banner);
- **alignment**: the buttons of the main panel are all the **same width** (the widest
  label of the current language) and regularly spaced; the three flow buttons come
  first, the LOCK/UNLOCK utility is **separated by a bigger gap**;
- **order**: the main panel builds its buttons from the constant
  `Layout.MAIN_PANEL_ORDER = { "place", "simPing", "simInter", "lock" }`, and a test
  asserts that order, so a future change cannot silently reorder the evening flow;
- **no overflow**: a block never runs over the frame, and a label never runs over its
  button (the other cause of the text leaving the frame are labels whose **longest
  word** does not fit the button);
- **no stale text**: an element that is not part of the current layout is hidden
  **and emptied**, so a CORRECT cannot leave the previous `1V3R` on screen;
- **the close cross** reserves its own top-right corner: no line may be drawn under
  it;
- **the frame follows the content**: the width is the widest of the blocks (the main
  panel is ≈360 px so the French labels fit, the intermission panel ≈560 px), the
  height is computed from the stacked blocks, and the wrapped body grows the frame
  instead of overflowing it.

`UI/` therefore computes **nothing**: it iterates the blocks, copies the point
(`TOPLEFT` + offsets, computed in `Core/`), the size and the label. The pure geometry
is what makes "no overlap in either language" testable **out of game**, with a
stubbed API, on every commit.

## 3. What the addon does / can NOT do (to be told to the players as is)

**It can:**

- display the plan prepared out of game (partner, role, position, pairs);
- **place** the intermission panel where the player wants it (position persisted),
  **drag the main panel** (movable by default, position persisted, `/gr lock` to
  freeze it, `/gr resetposition` to recenter everything) and do the same with the
  ping help window;
- display the **three composition buttons** named after the **visible
  composition** — `1 green + 3 red`, `2 green + 2 red`, `3 green + 1 red` — with
  the **number as a hint** ("1 or 3", "2"); once a composition is clicked the three
  buttons **disappear** (only the result stays, with REDO);
- display, once a composition is clicked, **the state in very large type, the
  role, the `PING: YES/NO` banner (colored with the ping color of the state) and
  ONE action line** — the ANCHOR line spelling out the **real gesture**
  (hover YOUR OWN character frame, press your ping key);
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
| `position` | `CENTER` | intermission panel position, saved on drag and drop (placement mode) |

Outside `intermission`, the top level of the SavedVariables holds the **language
preference** and the **panel preferences** (positions + lock):

| Key | Default | Effect |
|---|---|---|
| `locale` | `"auto"` | in-game language: `"auto"` (follow the client), `"en"`, `"fr"` — see `/gr lang` |
| `lockPanel` | `false` | `true` freezes every panel (`/gr lock`), `false` lets the player drag them (`/gr unlock`, the UNLOCK PANEL button). Only a real boolean can lock: anything else counts as "not locked" |
| `panelSchema` | `1` | schema marker of the panel preferences: an older SavedVariables (no marker) is **unlocked once** and stamped — see §2.5 |
| `panelPosition` | `{ CENTER, CENTER, 0, 0 }` | **main panel** position, saved on every drag stop, restored at `ADDON_LOADED` |
| `pingPanelPosition` | `{ CENTER, CENTER, 0, 0 }` | **ping help window** position, saved on every drag stop, restored at the next opening |

## 7. Commands and keybinding

```
/gr                       main panel (plan + PLACE INTERMISSION PANEL button
                          + the two SIMULATION buttons)
/gr plan                  detailed plan in the chat
/gr lang                  detected language, effective language, how to change
/gr lang auto|en|fr       rules on the language and persists it in the SavedVariables
/gr ping                  current ping policy and what it means for the roles
/gr ping anchors|color|none   rules on the PING POLICY and persists it (default anchors)
/gr inter                 shows/hides the intermission panel (close cross too)
/gr inter start|stop      starts/stops ONE intermission manually
/gr inter place           placement mode: drag the panel, prepare the ping, press OK
/gr inter ping            which ping to use, which key, and the binding names tried
/gr inter 3V1R            declares your COMPOSITION (also: 2V2R, 1V3R, "3 verts")
/gr inter 2               only "2" is accepted as a number (unambiguous)
/gr inter on | off        enables/disables the module
/gr inter status          module state + timeline + schedule
/gr sim                   simulation help (what it does, how to leave)
/gr sim inter             SIMULATION: the panel opens RIGHT AWAY, no boss (aliases: group, groupe)
                          -> ONE rehearsal, YOU close it (X or Close)
/gr sim ping              PING HELP (= /gr pinghelp): bind one key per ping, then ping YOURSELF
/gr sim stop              closes the rehearsal or the ping help window
/gr lock                  freezes the panels where they are (persisted)
/gr unlock                lets them be dragged again (persisted, also a panel button)
/gr resetposition         brings the main panel, the intermission panel and the ping help window to the center
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
busted                                    # 219 tests: 84 for this module, 46 for the real loading
                                          # (panels, close cross, simulations, button order),
                                          # 21 for the language, 20 for the ping policy,
                                          # 16 for the pure panel geometry (EN + FR),
                                          # 14 for the rehearsal + ping help (pure),
                                          # 11 for the pairing, 7 for the anti-API guard
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

Covered by `tests/spec/intermission_spec.lua` (84 tests):

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
  (with the ping color), one action line, at most three short lines, the
  **disappearance of the three choice buttons as soon as one is clicked**
  (`showButtons` false, `showRedo` true, CORRECT bringing them back), and the
  **disappearance** of the old verbose lines (ROLE ORDER / PING POLICY / STATE
  THAT JOINS YOU / caveats);
- the **placement view** (drag, ping keybinding reminder, lead, plan or
  "no plan");
- the pre-pull view (partner, role, position, sorted pairs, malformed plan, safe
  / deadly / **unverifiable** meeting when a role stays ambiguous, ping to use
  deduced from the prepared composition);
- the configuration (bounds incl. `leadSeconds`, inconsistent types, normalized
  schedule, no alias between accounts, no `macroTargetToken` any more) and the
  **panel preferences**: a fresh position block per account, a **total** lock
  resolver (only a real boolean locks), a **total** position resolver (only a
  known `Config.POSITION_POINTS` anchor survives, so a hand-edited `point` can
  never reach `SetPoint`), and the **one-time migration** that unlocks a legacy
  `lockPanel = true` once before respecting the player's own choice.

Covered by `tests/spec/pingpolicy_spec.lua` (20 tests): the role of each state
(ANCHOR/MIDDLE/CHASER, never deduced from the number), the default policy where
**only `1V3R` pings**, `color` where the three states ping their own ping,
`none` where nobody pings, the wording of each action line, an unknown policy
resolved to `anchors`, the refusal to name a ping for a role that must not ping,
the persistence of `/gr ping`, the refusal of an unknown value, and the fact
that **the policy is no longer displayed permanently** on the panel.

Covered by `tests/spec/load_spec.lua` (46 tests, real loading, `.toc` order)
— plus the close cross and the two simulations, detailed after the guard below:
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

Covered by `tests/spec/simulation_spec.lua` (14 tests, **pure logic**, no client):
`Core/Simulation.lua` must not reference `ENCOUNTER_START`, `Intermission.newRun`,
`advanceRun`, `resetRun` or `RegisterEvent`; the **rehearsal** is a **single cycle**
(`newRun` takes no option at all), never writes anything to the SavedVariables, and
`forRehearsal` replaces the combat countdown by a useful line (the headline contains
no `%` and no ` s`), appends the explanatory note, keeps the state / the ping banner
/ the composition buttons and **does not modify** the snapshot it is given; the
**ping help view** lists the four pings to bind, carries the gesture (`hover YOUR
OWN character frame`), the group reminder and the explicit "**CANNOT detect a
ping**" line, carries the bound key when the injected resolver knows it and `no key
bound` otherwise, and stays sane when the resolver is missing, raises or returns
nonsense; the `/gr sim` argument parser accepts `inter` with its aliases (`group`,
`groupe`), `ping` and `stop`, and **refuses any trailing option** (the former
`/gr sim inter cycles=N`); all the simulation locale keys are present in **both**
languages.

Covered by `tests/spec/layout_spec.lua` (16 tests, pure geometry, no client): the
engine stacks every block **one under the other** (never two blocks sharing a Y
band, an extra `gapBefore` only where a utility button is meant to be separated),
reports a real overlap, a real overflow and an unbreakable word wider than its
block, measures text and wraps it, and grows the frame to the longest label; the
**main panel** keeps its button order **PLACE -> SIM: PING -> SIM: INTER -> LOCK**
(the order is a constant asserted by a test, the lock separated by a bigger gap, all
four buttons the same width), and the **intermission panel** is checked in **both
languages** in every phase (rehearsal with the two-line banner, dark room with the
big state, placement mode): the big state is always **below** the banner, the
headline below that, then the ping banner, the body and the action row, and nothing
ever runs over the frame or under the close cross.

Covered by `tests/spec/guard_spec.lua` (7 tests, anti-forbidden-API guard): no
file listed in the `.toc` contains `COMBAT_LOG_EVENT`, `UnitAura`, `UnitBuff`,
`UnitDebuff`, `UnitGUID`, `SendChatMessage`, `GetRaidRosterInfo`, `C_VoiceChat`
outside a comment; **no ping API at all** (`C_Ping`, `SendMacroPing`,
`PingSubjectType`) even inside a string; `buildMacro` is gone; `Core/` stays free
of `GetTime`, `math.random`, `CreateFrame`, `UnitName`, `GideonRaidDB` **and of
the binding lookup**; a simulation stays free of the real timeline; and the binding
lookup, when present, is **only in `UI/` and only under `pcall`**.

Covered by `tests/spec/load_spec.lua` (46 tests): the real loading in `.toc` order
(9 files), the evening flow (arming, automatic opening, closing, reopening,
`ENCOUNTER_END`, placement mode and its saved position), the **main panel made
movable by default** (the drag is really allowed, the position is persisted on drag
stop, restored when the panel is shown again, `/gr lock` freezes it, `/gr unlock`
frees it, `/gr resetposition` recenters the three panels, the LOCK/UNLOCK button
does the same as the command), the **button order of the main panel** (PLACE, SIM:
PING, SIM: INTER, then the LOCK utility), the fact that **the three composition
buttons disappear once one is clicked** (CORRECT brings them back, in a real
intermission and in a rehearsal, and the composition row is not even part of the
applied layout any more), the **close cross on all three surfaces** (label, short
tooltip, translated tooltip, closing the main panel, hiding the intermission panel
without touching the clock, cancelling the placement) and the **two simulations**
(the rehearsal **opens right away** with no ticker at all, the two-line banner, the
click, REDO, **the player closes it** - nothing closes or relaunches it by itself -
the layout that keeps the big state below the banner in **both languages**, the ping
help window with its bound-key lines and its honest "no detection" wording, opened
by `/gr sim ping` **and** `/gr pinghelp`, closed by its button, its cross or
`/gr sim stop`, the **refusals** (a trailing option, an unknown sub-command) and the
`ENCOUNTER_START` isolation).

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
10. **Close cross ("X") in the client** — the button is built and tested out of
    game (label, short tooltip, click handlers), but its **hover** and its
    position in the top right corner are only verifiable in the client: check the
    tooltip reads `Close` in English / `Fermer` in French, and that the cross on
    the intermission panel **cancels** the placement mode and **does not** stop
    the automatic reopening at the next intermission.
11. **SIMULATION mode in the client** (`/gr sim inter`, `/gr sim ping`): the
    out-of-game tests drive both with a stubbed API, so what remains to be seen in
    game is the *real* rendering. Check that the panel opens **immediately** after
    the command (no more 3 s delay), that it **stays open until YOU close it** (X or
    Close) and that nothing relaunches it, that the two-line
    `SIMULATION - NO BOSS, NO RAID` banner is impossible to confuse with a real
    fight, that the big state is drawn **below** the banner (and not on top of it),
    and that a boss pull during a rehearsal **stops** it (the encounter then arms
    the normal schedule exactly once).
12. **The keys listed in the ping help window** (`/gr sim ping` or `/gr pinghelp`)
    depend on the binding names of item 1: as long as the real command names are
    unknown, a line honestly reads `no key bound`. Verify the ping really shows on
    screen **while grouped** (alone, nothing appears — that is expected and stated
    by the window).
13. **THE SELF-PING GESTURE — the open question of the third in-game test.**
    Measured by the raid lead: the ping goes **where the mouse is**, and pinging
    his **own character frame** pings **himself**. What is still to be confirmed
    **in a real raid**: does the ping placed on oneself appear **above the
    character** for the **other** players (and for how long)? That is the
    assumption the whole ANCHOR convention rests on — the action line now says
    *hover YOUR OWN frame and press your key*, and a CHASER must be able to run to
    the ping the anchor placed. Check it with a second player (or on the raid
    frames since patch 12.1) before the guild relies on it, and note how long the
    ping stays visible after the room darkens.
14. **Dragging the panels in the client.** The drag, the persistence on drag stop
    and the LOCK/UNLOCK button are covered out of game with a stubbed frame; what
    remains to be seen is the *real* feeling: the main panel really moves with the
    left button, the position survives a `/reload`, `/gr lock` freezes it,
    `/gr resetposition` recenters the three panels, and the ping help window
    reopens where it was dragged.
15. **The NEW layout in the client, in French AND in English** (`/gr lang fr`, then
    `/gr lang en`): no label touches or leaves the frame on the main panel (the
    frame is ≈360 px wide) and the ping help window fits as well; on the
    intermission panel the big state, the SIMULATION banner, the `PING: OUI/NON`
    line, the ROLE line and the action line are **all separated** (the fourth test
    showed `2V2R` drawn on the banner). Out of game this is proven block by block;
    what is checked here is the **font metrics of the real client** (the widths are
    measured with an approximation of the client's fonts, so a small visual margin
    must remain on screen).
