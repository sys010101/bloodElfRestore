# Changelog

## 0.4.0-alpha

- Expanded music routing from a basic Silvermoon-only layer into broader region families:
  - `silvermoon`
  - `eversong`
  - `sunstrider`
  - `ghostlands`
- Added region-specific TBC music pools for broader Eversong travel, Sunstrider Isle, and ghostlands-style southern / haunted areas.
- Added a much larger set of tracked Midnight Quel'Thalas music mute IDs to reduce double-music bleed-through in subzones and boundary pockets.
- Added subzone region overrides for areas such as `Sunstrider Isle`, `Tranquillien`, `Sanctum of the Moon`, `Windrunner Village`, and other southern remastered subzones.
- Added approximate music duration data so known replacement tracks are allowed to finish naturally instead of being cut off by the old coarse rotation timer.
- Added intro cooldown handling so intro cues do not replay too often on quick re-entry to the same region.
- Fixed long dead gaps after a track finished by clearing stale playback state as soon as the expected track lifetime expires.
- Fixed excessive music restart churn by routing playback from a stable region/day-night key instead of refreshing on every tiny subzone or resting-state change.
- Fixed startup double-play on login by moving initial music startup to `PLAYER_ENTERING_WORLD` only.
- Added live handling for WoW's global music toggle (`Ctrl+M`), including clean resume behavior when music is re-enabled.
- Fixed scheduler behavior while WoW music output is disabled so it no longer burns shuffle state selecting tracks that cannot play.
- Added a real manual-stop hold state for `/belvr music stop`, so it no longer immediately auto-resumes on the next periodic tick.
- Fixed slash-command music test playback so it now uses the same region-aware pool selection as the live music system.
- Improved slash-command feedback for `/belvr music on` so it reports when the music system is only armed because the master addon switch is still off.
- Reworked the settings UI into separate `Voice` and `Music` tabs instead of one long stacked control panel.
- Adjusted tab layout spacing to avoid overlap between the tab buttons and the first controls in each section.
- Kept the known limitation that `Ctrl+M` fade-out still depends on Blizzard's own music channel behavior and may remain abrupt.
- Updated TOC metadata and docs to `0.4.0-alpha`.

## 0.3.0-alpha

- Added first-pass Silvermoon / Eversong music replacement support alongside the existing voice system.
- Added tracked Midnight music mute IDs and TBC Silvermoon intro/day/night music pools in `SoundData.lua`.
- Added music settings in SavedVariables, including separate enable, mute, verbose, intro, and trace-recorder toggles.
- Added a separate music controller that watches zone, subzone, resting-state, and day/night transitions.
- Added addon-side music routing for `Silvermoon City` and `Eversong Woods`.
- Added support for enclave-style Silvermoon routing such as `Sanctum of Light` and supported subzones like `The Bazaar`.
- Added a shuffle-with-cooldown music picker so recently played TBC tracks are strongly discouraged from repeating too soon.
- Added periodic music rotation for long stays in the same supported area.
- Added fade-based stop handling for injected music transitions to reduce hard cuts.
- Added music test buttons, status text, and runtime controls to the in-game UI.
- Added slash commands for music control, music testing, manual refresh, and stopping injected music.
- Added separate verbose music logs that report the addon's current music context and selected replacement track.
- Added a music trace recorder that stores route and playback logs in SavedVariables for later inspection after `/reload` or logout.
- Updated TOC metadata and docs to `0.3.0-alpha`.

## 0.2.1-alpha

- Fixed addon load detection by aligning TOC and addon name with the folder name.
- Added `/belvr` UI with runtime toggles, status display, and test playback controls.
- Added left-click greet playback on `PLAYER_TARGET_CHANGED`.
- Added greet dedupe so right-click gossip does not immediately double-play after target-select.
- Added target-loss bye playback when switching away from a recently greeted target.
- Added pissed playback after repeated clicks on the same NPC.
- Added hidden-tooltip race scanning and humanoid fallback classification for Midnight NPCs with hidden metadata.
- Switched manual force and role overrides to GUID-based targeting because Blizzard reuses `npcID` values.
- Added name-based override commands for repeated NPC names.
- Split TBC greet pools into role-based sub-pools so standard NPCs do not play vendor-only lines.
- Added built-in handling for current reversed `UnitSex` behavior, with a UI toggle to invert if needed.
- Reduced overlapping playback with sound-handle stopping, playback throttling, and target-loss bye delay.
- Added temporary dialog-channel suppression and `Master` playback for injected lines to reduce untracked Midnight VO overlap.
- Added fake distance falloff for left-click greet using distance buckets and probabilistic playback.
- Expanded role heuristics for names like `blood knight` and `champion`.
- Added one-time saved-variable schema migration for legacy NPC-ID override tables.
- Added slash commands and status output for the invert-sex setting.
- Removed the hardcoded female gender profile for `Silvermoon Resident`.
- Added an optional toggle and slash commands for native dialog suppression.
- Fixed `Re-apply Mutes` so it re-enables the mute option instead of only re-running active mutes.
- Added explicit `verbose on` and `verbose off` slash commands.
- Added plain-English hover tooltips for UI checkboxes.
- Event-driven playback now applies the suppression window before rate-limit checks, improving coverage for stubborn mixed-voice NPCs.
- Added a sound-state check so replacement VO respects WoW sound disable states, including the usual `Ctrl+S` sound-effects toggle.
- Added a built-in vendor profile for `Lyrendal` so he uses vendor greetings.
- Added a built-in exclusion profile for `Mahra Treebender` to avoid hidden-race fallback false positives.
- Added NPC names to key verbose trigger logs for easier troubleshooting.
- Restricted the hidden-race humanoid fallback to Blood Elf zones to prevent false positives like Zul'Aman trolls.

## Notes For Next Iteration

- Expand the Silvermoon music allow-list using trace recordings from more interiors and subzones.
- Validate whether additional Midnight music FileDataIDs still need muting.
- Consider exposing music timing values in the UI once the zone map stabilizes.
- Consider one-time migration cleanup for legacy saved variables instead of clearing them every load.
- Replace placeholder TOC metadata before any public release.
