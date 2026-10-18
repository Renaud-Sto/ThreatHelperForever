# Changelog

All notable changes to ThreatHelper Forever. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versions: [SemVer](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-10-18

First public release, tested on WoW Forever beta build 1.60.1.70450 (Interface 16001).

### Added
- Your hold on every mob in combat with you, as a percentage next to its nameplate
  (all mobs, target only, or none), coloured by state.
- Threat frame drawn like Forever's nameplate bars: state, closest player, hold.
- Mob list sorted by danger, current target outlined.
- Centre-screen alerts with sounds for warning, danger and aggro lost (names the new holder,
  even a player outside the group).
- Settings window and minimap button: lock/unlock, display choices, alerts, sounds,
  thresholds, colour per state, test, reset. Also in the addon compartment.
- `/aggro` commands, English and French.
- Optional fight journal and diagnostics written to SavedVariables (off by default).

### Known limitations
- Not yet measured on a boss, where the game may hide threat values; the addon then falls back
  on threat states.
- Clicking a row of the mob list cannot target the mob: Forever forbids addons to target
  through a nameplate.

[Unreleased]: https://github.com/Renaud-Sto/ThreatHelperForever/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Renaud-Sto/ThreatHelperForever/releases/tag/v1.0.0
