# Changelog

All notable changes to ThreatHelper Forever. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versions: [SemVer](https://semver.org/).

## [Unreleased]

## [1.0.3] - 2026-11-05

### Fixed
- In a group, the player closest to taking your target was often shown as "not in group"
  (two samples in three in a dungeon journal), and a caster's share was overstated. The
  estimate from the percentage of lead now gives way to the group member it matches, melee or
  ranged; "not in group" is kept for a gap no member explains (escort NPC, outside player).

### Changed
- Dimmed percentages come from your target only: hovering a mob gives no threat value on
  Forever (measured), so the mouseover is no longer read.

## [1.0.2] - 2026-11-05

### Changed
- Every nameplate of a mob in combat with you shows something again, for multi-aggro: the live
  state ("OK" held, "!" about to go, "0%" lost) and, for a mob you targeted, hovered or focused
  in the last 6 seconds, its last real percentage, dimmed. Tab through the pack to refresh them.
  The mob list uses the same labels. (1.0.1 left the plates of other mobs empty.)
- The fight journal also samples the mouseover and focus mobs.

## [1.0.1] - 2026-11-05

Tested on WoW Forever 1.60.1.70790 (launch build, Interface 16001).

### Fixed
- The nameplate and the mob list disagreed with the threat frame on the same mob (100 % on the
  plate, 51 % on the frame) and jumped from 100 % to lost with nothing in between. Forever hides
  threat values read through a nameplate (measured): the target's plate and row now take the
  frame's figure, and other held mobs show their state colour without a made-up 100 %.
- A unit outside the group taking threat (an escort NPC, a player not in your group) is now
  counted even when group members are on the threat list, and is labelled "not in group"
  instead of "someone".

### Changed
- The fight journal also reads the target through its nameplate and keeps member names.

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

[Unreleased]: https://github.com/Renaud-Sto/ThreatHelperForever/compare/v1.0.3...HEAD
[1.0.3]: https://github.com/Renaud-Sto/ThreatHelperForever/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/Renaud-Sto/ThreatHelperForever/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/Renaud-Sto/ThreatHelperForever/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/Renaud-Sto/ThreatHelperForever/releases/tag/v1.0.0
