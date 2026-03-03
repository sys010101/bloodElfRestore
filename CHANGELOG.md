# Changelog

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
