ThreatHelper Forever tells a tank, before it happens, that a mob is about to slip away. Built for every tank on WoW Forever (warrior, paladin, druid in bear form...), with a UI that looks like the game's own.

**Features**

- **Your hold on every mob**: next to the nameplate of each mob in combat with you, one colour per state. On your target a percentage: 100 % = the aggro is yours and nobody is close; it falls as someone closes in; 0 % = lost. On other mobs Forever hides the figures: their plate shows the live state ("OK", "!" about to go, "0%" lost), or their last real percentage, dimmed, if you targeted them in the last 6 seconds. Tab through the pack to refresh them.
- **Threat frame**: a bar drawn like Forever's nameplates, with the player closest to taking your target.
- **Mob list**: every mob in combat with you, sorted by danger, your target outlined.
- **Alerts** in the middle of the screen with a sound, up to "AGGRO LOST to Bob: TAUNT!" (it names the new holder, even outside your group).
- **Settings window** from the minimap button or `/aggro`: lock/unlock, what to show, alerts, sounds, thresholds, a colour per state, a test, reset.

**Usage**

1. Show enemy nameplates (V).
2. Click the minimap button and untick "Lock the frames" to place the frame and the list, then lock them.
3. Tank. "Test" in the settings shows every alert without a fight.

**Slash commands**

`/aggro` opens the settings; `/aggro help` lists the others (lock, unlock, plate, list, test, reset...).

**Compatibility**

WoW Forever (Interface 16001), tested on build 1.60.1.70790. English and French.

**Good to know**

- On bosses the game may hide some threat values; the addon then falls back on threat states. Not yet measured on a boss.
- A unit outside your group (escort NPC, another player) is estimated from the game's percentage of lead and shown as "not in group".
- A row of the mob list cannot target its mob: Forever forbids addons to target through a nameplate. Click the nameplate.

Source and issues: https://github.com/Renaud-Sto/ThreatHelperForever
