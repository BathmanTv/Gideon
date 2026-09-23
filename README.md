# GideonRaid

![GIDEON](assets/gideon-hero.png)

*The guild's raid coach, and the GIDEON orchestrator — World of Warcraft: Midnight (12.1).*

Guild addon (World of Warcraft: Midnight, `## Interface: 120100`) that helps with
the mechanic of **pairing players carrying complementary debuffs** during a raid
intermission, with the **GIDEON** Discord bot as the assignment source, and that
embeds a second module: the **Intermission Coach** for the *Entombed Sentinels*
boss (mythic) — see [`docs/INTERMISSION-COACH.md`](docs/INTERMISSION-COACH.md).

---

## 1. Why the architecture is "weird" (and why it is mandatory)

In 12.x, an addon **can no longer** do what a raid addon used to do:

| Before 12.0 | Since 12.0 |
|---|---|
| Read other players' auras (`UnitAura`) and decide | The value may be **secret**: `if aura > 0` = **immediate Lua error** |
| Listen to `COMBAT_LOG_EVENT` | **Registering the event raises an error** |
| Exchange addon→addon messages in an instance | **No channel any more** |
| Work around the restrictions | Forbidden by Blizzard, breaks on every patch |

So the pairing **cannot** be computed in the client during combat. It is computed
**out of game by GIDEON**, written into the SavedVariables, and the addon only
**reads and displays** it:

```
GIDEON (VPS, out of game)
  Discord roster  →  lua5.1 tools/pairing_cli.lua  →  pairs
                                |
                                v
  WTF/Account/<ACCOUNT>/SavedVariables/GideonRaid.lua   (strings, never secret)
                                |
                          player /reload
                                v
                     GideonRaid displays the pairs
```

Sources: [Secret Values](https://warcraft.wiki.gg/wiki/Secret_Values) ·
[API changes 12.0.0](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes) ·
[Patch 12.1.0](https://warcraft.wiki.gg/wiki/Patch_12.1.0).

---

## 2. The pairing engine is shared

`Core/Pairing.lua` is **pure Lua 5.1**: the very same file runs inside the WoW
client and on the VPS. That is what guarantees that GIDEON and the addon always
compute *exactly* the same thing.

```bash
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

**Deterministic** result (alphabetical sort): the same roster always gives the
same result, so it can be compared with `diff`.

---

## 3. Intermission Coach — *Entombed Sentinels* (mythic)

During that intermission every player sees a **number** above their head, but
**the number does not determine the colors**: only "**2**" is unambiguous
(always 2 green + 2 red); "**1**" and "**3**" can be either 3 green + 1 red, or
1 green + 3 red — it is the **color of the orbs** that decides. There are
therefore only **three real states** (`3V1R`, `2V2R`, `1V3R`) and the survival
rule is a **color addition**: the sum of the two players must make
**4 green + 4 red** (`3V1R+1V3R` or `2V2R+2V2R`). Any other combination kills;
`3V1R + 2V2R` = **5 green** = the "5g". After **3 s** the room goes dark:
everyone then sees only their own orbs.

The addon can read **neither the other players' indicators nor its own** (secret
values) and **cannot send a ping** — measured in game: `C_Ping.SendMacroPing`
is refused by the client ("this action can only be used by the Blizzard UI"),
from a macro as well as from an addon. The module therefore does what is still
possible:

| Screen | Content | Data source |
|---|---|---|
| Main panel (`/gr`) | partner, role, position, pairs, then the buttons **in this order**: **PLACE INTERMISSION PANEL** -> **SIM: PING YOURSELF** -> **SIM: INTERMISSION GROUP** -> the LOCK/UNLOCK utility (frozen by a test: an evening flow, then a separated utility); the panel is **draggable** and reopens where you left it, and its frame is **as wide as its longest label in both languages** | `assignment` block prepared out of game by GIDEON |
| Placement mode (before the pull) | the panel is dragged where you want it, then **OK** saves the position and closes (the body says it explicitly: *place the panel where you want it to appear, then press OK: during the fight it opens by itself*); the close cross (`X`) and **Close** cancel instead of validating | the player's drag (persisted) |
| Intermission panel (opens by itself 2 s before the intermission, or `/gr inter`) | very large reminder, 3 s countdown, 3 buttons named after the visible composition (`1 vert + 3 rouges` / `2 verts + 2 rouges` / `3 verts + 1 rouge`, number as a hint) | the player's click |
| After the click | **the state in very large type**, the **role** (`ROLE: ANCHOR`), **`PING: OUI/NON`** (colored), and **ONE action line** — plus the **REDO** button; **the three composition buttons disappear** (REDO brings them back, empty state) | convention frozen in `Core/Intermission.lua` |
| Ping | **which ping to use** (`PING: Warning`) and, if you bound one, **which key to press** (`PING: Warning - press Q`) — the addon **never pings** | the player's keybinds, read with `GetBindingKey` |
| Assignment sound | **one soundboard per composition**, played **once** the moment you declare yours (real flow *and* rehearsal), on the Master channel; `/gr sound on\|off` mutes it, `/gr sound test 1v3r\|2v2r\|3v1r` plays one on request | `Core/Sound.lua` (pure table) + three Ogg files in `Sound/` |
| Close cross (`X`, top right) | closes the panel — on **both** the main panel, the intermission panel and the ping help window | `Core/Locale.lua` (`ui.closeCross`, `ui.closeTooltip`) |
| SIMULATION mode (no boss, no raid) | **Intermission group** (`/gr sim inter`): the panel opens **RIGHT AWAY** with **its three composition buttons** (`1V3R` / `2V2R` / `3V1R`, sized on their own labels), you click your composition, get the state + role + `PING: YES/NO` + the action line, correct it with REDO and **you close it yourself** (X or Close) - ONE single cycle, nothing closes it and nothing relaunches it; **Ping help** (`/gr sim ping` = `/gr pinghelp`): a **short information window** (draggable, closable) telling you **how to bind one key per ping** (`Options > Keybindings > Ping`) and the operational reminder - **during the boss, when the panel says `PING: YES`, hover YOUR OWN character frame and press your key: you ping yourself** - plus the two limits: pings only show **while grouped** and **the addon cannot detect a ping** | pure logic in `Core/Simulation.lua` + the pure layout in `Core/Layout.lua` (+ the close cross and the main-panel buttons) |

The panel shows the essential only (state, role, `PING: OUI/NON`, one action
line); the explanations and the way each decision is justified live in
[`docs/INTERMISSION-COACH.md`](docs/INTERMISSION-COACH.md), never on screen.

### 3.1 Ping roles by STATE (instead of one duty per number)

A state carries a **role**, and the role decides what the player does:

| State | Role | Does it ping? (default policy) | The ONE action line |
|---|---|---|---|
| `1V3R` | **ANCHOR** | **YES** — pings itself with the native ping keybind, or is pinged by another player | "PING: YES - hover YOUR OWN character frame (your health bar) then press your ping key (Warning): you ping yourself, stay put and jump on the spot" |
| `2V2R` | **MIDDLE** | no | "DO NOT PING - go to the middle / under the boss" |
| `3V1R` | **CHASER** | no | "DO NOT PING - run to a ping (a 1V3R)" |

**Why the ANCHOR line names the mouse gesture — CONFIRMED IN GAME.** The ping goes
where the **mouse** is: hovering **your own character frame** (the unit frame with
your health bar) and pressing the ping key **displays the ping on yourself**. The
raid lead validated the gesture in game (fifth in-game test: *"the ping on the
health bar works fine to show it on myself"*), so the action line spells it out
instead of a vague "ping yourself" and it is no longer on the "to be confirmed"
list. What is still **to be observed in a real raid**: how long that self-ping
stays visible on the other players' screens **after the room darkens**, and
whether it shows on their raid frames (see `docs/TESTPLAN.md`, row 14b).

**Why:** every state pinging used to flood the channel with ~20 pings; with one
ping per anchor (4 per side) the raid sends **at most ~8 pings**, which stays
readable — the client also rate-limits pings per player, and that limit is a
**measured fact** (3 pings in a row, then ~5 s of wait, then 3 again), not an
assumption (see `docs/TESTPLAN.md`, row 13). An ANCHOR may also simply **be
pinged by another player** of the raid: only one signal per anchor is needed, and
since patch **12.1 pings are visible on the raid frames**, so a chaser finds the
anchor without any addon-to-addon communication.

The policy is **configurable** (`/gr ping`, persisted in
`GideonRaidDB.intermission.pingMode`):

| Policy | Who pings |
|---|---|
| `anchors` (**default**, raid-lead decision) | only the `1V3R` ANCHORS |
| `color` (raidstrats variant) | every state, with its own color: `1V3R` red/Warning, `2V2R` blue/OnMyWay, `3V1R` green/Assist |
| `none` | nobody: the raid plays on positions only |

The addon **never sends a ping and no longer generates any macro** (that route is
refused by the client): it says **which ping to use** and, when it can read it,
**which key to press**. Pressing it is the player's job — Blizzard's own UI then
sends the ping. If no key is bound, the panel displays no key and points to
*Options > Keybindings > ping system*, never a shortcut that does not exist.

**Nothing is automatic.** The interface states it explicitly: *who declared what
is UNKNOWN* (no addon→addon channel in an instance, the UI is local to the
client); **the ping is the only signal visible to the other players** — and the
player is the one who places it.

### 3.2 Evening flow

1. before the pull, `/gr` → **PLACE INTERMISSION PANEL** (or `/gr inter place`):
   drag the panel where it must appear, prepare your ping keybind in
   *Options > Keybindings*, press **OK** (the position is saved);
2. pull the boss: `ENCOUNTER_START` starts the **pre-computed schedule**
   (46.3 s, then 148.9 / 251.5 / 353.2 s) — its arguments are never read;
3. **1–2 s before each intermission the panel opens by itself** with the three
   choices;
4. click your composition: state, role, `PING: OUI/NON` and one action line — the
   **three buttons disappear** (so no accidental second click) and **REDO** brings
   them back as many times as needed;
5. at the end of the intermission the panel **closes by itself**; the next one
   reopens it automatically.

**The panels are movable** (third in-game test): the main panel used to be frozen
(`lockPanel` was hard-coded to `true`). It is now **draggable by default**, and so
is the ping help window; each one **keeps its position** (saved in
`GideonRaidDB`, restored on `/reload`). Three new commands:

```bash
/gr lock           # freeze the panels where they are (persisted)
/gr unlock         # let them be dragged again (also the UNLOCK PANEL button)
/gr resetposition  # bring the main panel, the intermission panel and the ping help window back to the center
```

An existing `SavedVariables` file (all of them carried the old `lockPanel = true`)
is **unlocked once** on the first load after the update, then your own choice is
respected.

**Close cross (`X`, top right)** — on the main panel and on the intermission
panel: it closes the panel (during the placement it **cancels**, exactly like the
Close button, and during a simulation it **leaves the rehearsal**). Hiding the
intermission panel never touches the clock: it still closes by itself at the end
and opens again at the next intermission.

**Rehearse alone — SIMULATION mode** (no boss, no raid), from the main panel
(`SIMULATION` buttons) or from the chat:

```bash
/gr sim inter   # "Intermission group": the panel opens RIGHT AWAY, click your composition,
                # correct it with REDO, then close it YOURSELF (X or Close). One single cycle.
/gr sim ping    # PING HELP (= /gr pinghelp): how to bind one key per ping, and how to ping yourself
/gr sim stop    # close the rehearsal or the help window (= the Close button, = the cross)
```

The simulation is **isolated from the real flow**: it never arms/disarms the
`ENCOUNTER_START` timeline, publishes no decision, is refused while a real
intermission runs and is stopped the moment a real encounter starts. During a
rehearsal the panel displays a two-line
`SIMULATION - NO BOSS, NO RAID` / `SINGLE REHEARSAL - YOU CLOSE THE PANEL YOURSELF`
banner so it can never be mistaken for a fight, and the headline replaces the combat
countdown (there is no boss, hence no orb to read). The ping help window states as is
that **the addon cannot detect a ping** (no API reports one), that it **never sends a
ping**, and that **pings only show while in a group or a raid**.

```bash
make inter    # convention + action lines, out of game
make plan     # pre-pull view from the contract fixture
```

### 3.3 Assignment soundboards (one sound per composition)

Requested by the raid lead: the moment you **declare** your orb composition — a
click on one of the three buttons, in the real flow **as in the `/gr sim inter`
rehearsal** — the soundboard of **that** state is played, **once**.

| State | File | Client path |
|---|---|---|
| `1V3R` | `Sound/assign-1v3r.ogg` | `Interface\AddOns\GideonRaid\Sound\assign-1v3r.ogg` |
| `2V2R` | `Sound/assign-2v2r.ogg` | `Interface\AddOns\GideonRaid\Sound\assign-2v2r.ogg` |
| `3V1R` | `Sound/assign-3v1r.ogg` | `Interface\AddOns\GideonRaid\Sound\assign-3v1r.ogg` |

```bash
/gr sound                  # is the sound enabled? (and how to change it)
/gr sound on | off         # enable/disable it (persisted; an unknown value is refused)
/gr sound test 1v3r        # hear one soundboard now, without waiting for a fight
/gr sound test 2v2r        # (also: 3v1r)
```

Rules, all covered out of game by `tests/spec/sound_spec.lua`:

- **No sound without a declaration**: nothing is played until you click your
  composition (a state that is not `1V3R` / `2V2R` / `3V1R` is refused, nothing is
  guessed);
- **Once**: a repeated declaration of the same composition, a panel tick or a
  re-render cannot double the sound. **CORRECT** re-arms it: the next click plays
  the sound of the composition it declares, even when it is the same one. A new
  intermission (and a new rehearsal) re-arms it too;
- **Silent on failure**: a missing file, a refused call or an absent
  `PlaySoundFile` leaves the addon silent, **without a Lua error** and without
  interrupting the panel — the declaration and the rendering carry on;
- **`PlaySoundFile` is called from `UI/` only, under `pcall`, on the `Master`
  channel** (your master volume applies). `tests/spec/guard_spec.lua` fails if it
  ever appears in `Core/`, outside `UI/`, or unguarded;
- the choice of the file per state is a **pure table in `Core/Sound.lua`**
  (`Sound.FILES_BY_STATE`), testable without the client;
- the preference lives in `GideonRaidDB.intermission.soundEnabled` (`true` by
  default). It is resolved **totally**: only an exact `false` mutes the sound, so
  an older SavedVariables (no field) or a hand-edited value falls back to the
  default — the migration of the existing saves is a no-op.

#### Replacing the three sounds (when the real recordings are ready)

The three shipped files are **silent placeholders** (0.2 s of silence, Ogg
Vorbis), so nothing is broken in the meantime. Replacing them is a **file drop,
with no code change**:

1. record/convert each soundboard as **Ogg Vorbis** (`.ogg`; a `.wav` or `.mp3`
   file is **not** what the `.toc` lists). Speech or a short musical sting both
   work; keep them short (a few seconds at most) — the intermission lasts about
   20 s and the sound plays on the composition click;
2. name them **exactly**: `assign-1v3r.ogg`, `assign-2v2r.ogg`, `assign-3v1r.ogg`
   (lower case, no accent, no space) and drop them into the addon's `Sound/`
   folder, **overwriting** the placeholders:
   `World of Warcraft/_retail_/Interface/AddOns/GideonRaid/Sound/`;
3. do **not** rename, move or delete anything else: the three names are already
   listed in `GideonRaid.toc` and packaged by `.pkgmeta` (a test fails if a listed
   sound is missing from the repository);
4. in game, `/reload`, then `/gr sound test 1v3r` (then `2v2r`, `3v1r`): the chat
   names the file it played — that is how you confirm **which** file you heard.
   The sound is muted if the preference is off (`/gr sound off` then
   `/gr sound test` says so): `/gr sound on` first.

`ffmpeg` one-liner used for the placeholders (adaptive to any source file):

```bash
ffmpeg -i mysound.wav -c:a libvorbis -q:a 5 Sound/assign-1v3r.ogg
```

Full detail (convention, ping keybinds, `plan` contract, configuration, "to be
confirmed in game" items):
[`docs/INTERMISSION-COACH.md`](docs/INTERMISSION-COACH.md).

---

## 4. In-game language — English by default, French on a frFR client

The addon is **bilingual in game**, with **English as the official/default
language**:

- `Core/Locale.lua` (pure logic) holds every displayed string as
  `Locale.STRINGS[key] = { en = "...", fr = "..." }` plus two pure functions:
  - `Locale.resolve(requested, detected)` → `"en"` or `"fr"`: `"fr"` if the
    requested preference is `"fr"`, `"en"` if it is `"en"`, and in `"auto"`/nil
    mode `"fr"` when the detected client locale starts with `"fr"`, otherwise
    `"en"` (any unknown value falls back to `"en"`);
  - `Locale.t(key, lang)` → the translated string, with a safe fallback chain:
    requested language, then the other language, then the key itself — it never
    raises. `Locale.format(key, ...)` is the same with `string.format`
    placeholders.
- The **wiring layer** (`GideonRaid.lua`, the only layer allowed to call client
  APIs — [API:GetLocale](https://warcraft.wiki.gg/wiki/API:GetLocale)) detects
  the client language, reads the persisted preference `GideonRaidDB.locale`
  (`"auto"` by default, `"en"`, `"fr"`) and publishes the effective language to
  the rest of the code.
- In game: `/gr lang` shows the detected language, the effective one and the
  preference; `/gr lang auto`, `/gr lang en` and `/gr lang fr` rule on it and
  persist it. An unknown value is refused (nothing is guessed, nothing is
  written).
- Spell, orb and color **names are identical in both languages** (`3V1R`,
  `2V2R`, `1V3R`, `Warning`, `OnMyWay`, `Assist`).
- The `.toc` carries both descriptions: `## Notes:` (English) and
  `## Notes-frFR:` (French).

**To be confirmed in game:** the `GetLocale()` detection has to be validated
once on a **frFR** client (French displayed without any preference) and once on
an **enUS** client (English displayed).

---

## 5. Structure

```
GideonRaid/            <- REPOSITORY ROOT = ADDON ROOT (mandatory)
├── GideonRaid.toc
├── GideonRaid.lua     <- wiring: ADDON_LOADED, PLAYER_LOGIN, ENCOUNTER_*, /gr, /gr lang
├── Bindings.xml       <- intermission panel binding (loaded automatically,
│                         NEVER listed in the .toc)
├── Core/              <- PURE LOGIC (zero WoW API, testable)
│   ├── Locale.lua     <- in-game strings (en/fr) + language resolution
│   ├── Sound.lua      <- ASSIGNMENT SOUNDBOARDS: pure table state -> .ogg file,
│   │                     one-playback-per-assignment gate, bounded /gr sound preference
│   ├── Config.lua
│   ├── Pairing.lua
│   ├── Intermission.lua
│   ├── Layout.lua     <- PURE panel GEOMETRY: blocks anchored one under the other,
│   │                     overflow/overlap checks (the layout is computed, then applied)
│   └── Simulation.lua <- SIMULATION mode: rehearsal + ping help (no guided sequence)
├── UI/                <- RENDERING (zero computation: it APPLIES Core/Layout as is)
│   ├── Panel.lua      <- main panel + the shared layout applier (+ the close cross)
│   └── Intermission.lua <- intermission panel + the ping help window (close cross, banner,
│                           and the ONLY audio call of the addon: PlaySoundFile, under pcall)
├── Sound/             <- the three assignment soundboards, LISTED in the .toc
│   ├── assign-1v3r.ogg  (1V3R)   <- silent placeholders until the raid lead
│   ├── assign-2v2r.ogg  (2V2R)   delivers the real recordings: same names,
│   └── assign-3v1r.ogg  (3V1R)   same folder, no code change (README §3.3)
├── libs/              <- embedded libraries (externals)
├── tests/             <- busted + fixtures (excluded from the zip)
├── tools/             <- CLI + .toc validator (excluded from the zip)
├── docs/              <- CONVENTIONS.md, TESTPLAN.md, INTERMISSION-COACH.md (excluded from the zip)
└── .pkgmeta .luacheckrc .busted stylua.toml Makefile .github/
```

---

## 6. Commands (single exit gate: `make check`)

```bash
make check    # stylua --check + luacheck + check_toc + busted   <- MANDATORY
make syntax   # Lua 5.1 syntax check (the client runtime)
make test     # out-of-game unit tests (busted)
make toc      # .toc consistency
make cli      # pairing of the sample roster
make inter    # Intermission Coach: convention + action lines (out of game)
make plan     # pre-pull view from the assignment fixture
make fmt      # automatic reformatting
```

Reference result (after the Intermission Coach redesign, the close cross + SIMULATION
mode, the fourth in-game pass (no ping macro, minimal panel, REDO, full evening
flow with the pre-computed schedule, panels laid out by `Core/Layout.lua`, rehearsal
opened right away and closed by the player, ping help window instead of a guided
sequence), the fifth in-game pass (validated self-ping, OK button of the
placement mode, composition buttons restored in the rehearsal, every button sized on
its own label) and the assignment soundboards):

```
$ make check
stylua --check .
luacheck .
Total: 0 warnings / 0 errors in 24 files        # luacheck
python3 tools/check_toc.py GideonRaid.toc
OK GideonRaid.toc                              # check_toc (13 files listed: 10 lua + 3 sounds)
busted
260 successes / 0 failures / 0 errors / 0 pending : 1.514132 seconds
```

The 260 tests are spread over `intermission_spec.lua` (84),
`load_spec.lua` (49 — real loading, `.toc` order, evening flow, movable panels,
close cross, simulations, button order, placement OK button, rehearsal composition
buttons), `sound_spec.lua` (31 — assignment soundboards: pure table state -> file,
paths listed in the `.toc` and present on disk, bounded `/gr sound` preference, one
playback per assignment, survival to a failing/absent `PlaySoundFile`),
`locale_spec.lua` (21),
`pingpolicy_spec.lua` (20 — ping roles and policies), `layout_spec.lua` (22 — pure
panel geometry: no overlap, no overflow, every button sized on its label with its
inner margin, in both languages),
`simulation_spec.lua` (14 — pure rehearsal + ping help), `pairing_spec.lua` (11) and
`guard_spec.lua` (8 — anti-forbidden-API guard, audio call restricted to `UI/` under
`pcall`, simulation isolation).

### Tooling (installed and verified on the VPS on 22/09/2026, Debian 13)

```bash
apt-get install -y lua5.1 lua5.4 luajit luarocks lua-check jq
luarocks install busted        # busted 2.3.0
luarocks install luaunit       # alternative
npm i -g @johnnymorganz/stylua-bin   # stylua 2.5.2
```

Verified versions: `Lua 5.1.5`, `Lua 5.4.7`, `LuaJIT 2.1`, `luarocks 3.8.0`,
`Luacheck 1.2.0` (runs on PUC-Rio Lua 5.1 = the client runtime), `busted 2.3.0`,
`stylua 2.5.2`.

---

## 7. Distribution (guild of ~25 players) — recommendation

### What was chosen: private repository + GitHub release + GIDEON relay

```
tag v1.0.0  →  GitHub Actions (BigWigsMods/packager@v2)  →  GideonRaid-1.0.0.zip
                                       |
                            GIDEON downloads the asset (GitHub API, token)
                                       |
                     Discord message in #addons: zip as an attachment
                                       |
                players: drag and drop into Interface/AddOns/
```

**Why this choice:**

| Option | Verdict |
|---|---|
| **Private Git repository + zip posted by GIDEON on Discord** | **CHOSEN.** Zero account for the players, zero third-party service, one action = one attachment. GIDEON can already post and download. The zip is auto-generated, never built by hand. |
| Shared addon folder + addon manager | Rejected: requires a CurseForge/Wago project, an author account for Jean, and CurseForge does **not** offer guild-restricted distribution. |
| "Private" CurseForge | Does not really exist for that use case: either it is public, or nobody can install/auto-update it. |
| Public Git repository + `git pull` by the players | Rejected: requires Git skills from the players, and no automatic update. To reconsider **if** the addon is published publicly later (Wago/CurseForge, auto-update through WoWUp). |
| Wago Addons | Good candidate *if* published publicly. API key `WAGO_API_TOKEN`, already wired in `.github/workflows/release.yml`. |

The release workflow is **already written and functional locally**: the BigWigs
packager's `release.sh` produces a correct zip (verified, see §5). The only
remaining step is to create the GitHub repository and push a tag.

### Updates

- On every fix: `git tag v1.0.1 && git push origin v1.0.1` → GIDEON announces
  the new version with the zip.
- **On every game patch**: bump `## Interface:` in `GideonRaid.toc` **and**
  `MIN_INTERFACE` in `tools/check_toc.py` (otherwise the CI stays green while
  the client flags the addon as outdated). The `check_toc` test deliberately
  fails when the number has not been updated.

---

## 8. Documentation

- [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md) — **mandatory** code rules for the
  agents (structure, naming, comments citing the API source, prohibition on
  depending on a secret value, separation between logic and rendering).
- [`docs/TESTPLAN.md`](docs/TESTPLAN.md) — 4-step test plan, data sets and
  expected results.
- [`docs/INTERMISSION-COACH.md`](docs/INTERMISSION-COACH.md) — *Entombed
  Sentinels* module: mechanic, ping roles and **native ping keybinds**, `plan`
  contract, configuration and the list of items **to be confirmed in game**.
- [`docs/AGENT-RULES.md`](docs/AGENT-RULES.md) — what every code agent
  (Claude Code, Codex, OpenCode) must read before touching this repository.
  *(Named like that because the environment blocks the creation of an
  `AGENTS.md`: create a root `AGENTS.md` once, by hand, containing
  `See docs/AGENT-RULES.md` so that the agent CLIs load it automatically.)*
