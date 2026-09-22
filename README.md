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
values) and **cannot send a ping** (`C_Ping.SendMacroPing` is `#protected`:
macros only). The module therefore does what is still possible:

| Screen | Content | Data source |
|---|---|---|
| Main panel (`/gr`) | partner, role, position, pairs | `assignment` block prepared out of game by GIDEON |
| Intermission panel (`/gr inter` or the keybinding) | very large reminder, 3 s countdown, **three buttons named after the visible composition** (`1 vert + 3 rouges` / `2 verts + 2 rouges` / `3 verts + 1 rouge`, number as a hint) | the player's click |
| After the click | instruction (what you have, what you must do, state to join, ping color/token) + **ping macro ready to copy** | convention frozen in `Core/Intermission.lua` |

**Nothing is automatic.** The interface states it explicitly: *who declared what
is UNKNOWN* (no addon→addon channel in an instance, the UI is local to the
client); **the ping is the only signal visible to the other players** — and the
player is the one who places it: the addon only prepares the macro and says which
ping to use, because the ping API is `#protected` (an addon cannot ping for you).

```bash
make inter    # convention + macros, out of game
make plan     # pre-pull view from the contract fixture
```

Full detail (convention, `plan` contract, configuration, "to be confirmed in
game" items): [`docs/INTERMISSION-COACH.md`](docs/INTERMISSION-COACH.md).

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
│   ├── Config.lua
│   ├── Pairing.lua
│   └── Intermission.lua
├── UI/                <- RENDERING (zero computation)
│   ├── Panel.lua
│   └── Intermission.lua
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
make inter    # Intermission Coach convention + macros (out of game)
make plan     # pre-pull view from the assignment fixture
make fmt      # automatic reformatting
```

Reference result (after the color-model fix and the bilingual language layer):

```
$ make check
Total: 0 warnings / 0 errors in 17 files        # luacheck
OK GideonRaid.toc                              # check_toc (7 files listed)
111 successes / 0 failures / 0 errors           # busted
```

The 111 tests are spread over `pairing_spec.lua` (11),
`intermission_spec.lua` (60), `load_spec.lua` (16), `guard_spec.lua` (4) and
`locale_spec.lua` (20).

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
  Sentinels* module: mechanic, ping convention, macro, `plan` contract,
  configuration and the list of items **to be confirmed in game**.
- [`docs/AGENT-RULES.md`](docs/AGENT-RULES.md) — what every code agent
  (Claude Code, Codex, OpenCode) must read before touching this repository.
  *(Named like that because the environment blocks the creation of an
  `AGENTS.md`: create a root `AGENTS.md` once, by hand, containing
  `See docs/AGENT-RULES.md` so that the agent CLIs load it automatically.)*
