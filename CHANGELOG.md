# Changelog

All notable changes to GideonRaid are documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/); this project
uses semantic-ish versioning driven by git tags (`vX.Y.Z`).

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

[0.3.0]: https://github.com/BathmanTv/Gideon/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/BathmanTv/Gideon/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/BathmanTv/Gideon/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/BathmanTv/Gideon/releases/tag/v0.2.0
