# Changelog

## 0.6.1-alpha - 2026-03-08

- Applied voice-area gating to all TBC replacement playback so out-of-scope NPCs no longer inherit Blood Elf voices just because their tooltip exposes Blood Elf race text.
- Added voice-side native-only exclusions so areas such as `Harandar` stay on Blizzard voice just like they already do on the music side.
- Narrowed hidden-race target-select fallback from generic humanoids to positive Blood Elf name/profile hints, preventing false positives on unrelated nearby humanoids.
- Blocked target-select TBC playback for dead and hostile or attackable units.
- Restored hidden-race target-select recognition for `Doomsayer` and `Household Attendant` via exact built-in Blood Elf name profiles.
- Fixed the Lua reload crash caused by a forward-referenced hidden-race fallback helper.
- Tightened startup music purge ordering so tracked music mutes are armed before music is re-enabled, reducing Silvermoon intro overlap on login and `/reload`.
- Reworked the README testing guidance around exploratory issue-tracker-driven testing and trimmed the README limitations list to durable user-facing constraints.

## 0.6.0-alpha - 2026-03-07

- Tightened music ownership to Midnight Quel'Thalas only by adding scope checks from zone text, subzone text, and parent map lineage.
- Added native-only music exclusions so areas such as `Harandar` stay on Blizzard music even when their parent zone would otherwise qualify.
- Fixed Deatholme routing regressions by restoring dedicated `Ruins of Deatholme` routing, adding a narrow `deatholme` token fallback, and re-darkening the TBC `deatholme` pool.
- Reworked tracked music muting from a partial hand-maintained list into a generated Midnight catalog model based on wowdev/wow-listfile release `202603061837`.
- Added `Midnight_ID_catalog.lua`, `Midnight_ID_Index.md`, and `tools/generate_midnight_catalog.ps1`.
- Updated `bloodElfRestore.toc` so the generated Midnight catalog loads before `SoundData.lua`.
- Added runtime Midnight catalog exclusions for `harandar_1`, `harandar_2`, `harandar_3`, and `lightbloom_harandar` so Harandar remains native.
- Added `BElfVR_SupplementalMusicMuteIDs` for non-Midnight Blizzard zonemusic used inside supported interiors, currently covering tavern / inn / rest-area IDs `53737`-`53778`.
- Refactored music mute building so all music muting now flows through the same region-scoped tracked-mute path instead of global login-time muting.
- Removed the old steady-state `Sound_MusicVolume=0` suppression model from active use and switched replacement music playback to the real `Music` channel.
- Added persisted restore safety for temporary `Sound_MusicVolume`, `Sound_EnableAmbience`, and `Sound_EnableDialog` changes, including recovery on addon load and `PLAYER_LOGOUT`.
- Added `Config.lua` as a user-editable policy layer and moved intro cooldown rules there with commented examples.
- Expanded `Config.lua` into the main safe policy surface for voice behavior, voice classification/scope rules, built-in overrides/profiles, music routing/scope/timing, trace limits, and UI art/layout tuning.
- Persisted intro cooldown history in `BElfVRDB.musicIntroHistory` so `/reload` no longer resets intro timing.
- Added layered intro cooldown matching by region, zone, subzone, area (`zone||subzone`), pool, and exact FileDataID, with day/night fallback when an intro is blocked.
- Expanded music debug and status output with `scope`, `scopeSource`, `overrideSource`, `nativeOnly`, catalog counts, and supplemental mute counts.
- Updated UI and slash-command wording from tracked Midnight Silvermoon music to tracked supported-zone music where appropriate.
- Refreshed `README.md`, `DEV_NOTES.md`, and generated Midnight catalog documentation to match the current runtime model and data flow.
- Added `targetLossByeMaxAgeSeconds` so delayed target-loss bye playback is skipped once the disengage is too old to sound believable.
- Anchored music-tab action buttons under the live status block so longer status text no longer overlaps the test and utility controls.
- Fixed post-refactor load regressions by reducing top-level local pressure in `BElfRestore.lua` and cleaning up helper/symbol initialization ordering.

## 0.5.0-alpha

- Bumped working addon/docs metadata version from `0.4.0-alpha` to `0.5.0-alpha`.
- Rebranded visible addon naming from `Blood Elf Voice Restore` to `Blood Elf Restore`.
- Renamed main addon script from `BElfVoiceRestore.lua` to `BElfRestore.lua` and updated TOC load order.
- Switched primary slash command docs/UI prompts to `/belr` while keeping `/belvr` as a legacy alias.
- Renamed the legacy southern music routing label from `ghostlands` to `eversong_south` to match Midnight-era zone reality.
- Added a dedicated `deatholme` music region so `Ruins of Deatholme` no longer shares the full southern random pool.
- Added legacy compatibility so custom `SoundData.lua` packs that still define `ghostlands` are treated as `eversong_south`.
- Added `/belr music note <text>` to write manual zone/subzone/region marker lines into the trace buffer.
- Added a `StopMusic()` pre-playback reset before replacement music starts to reduce native Midnight overlap in leak-prone pockets.
- Added native-music suppression by temporarily forcing `Sound_MusicVolume=0` while replacement music is active in supported areas, then restoring the prior value when leaving control.
- Switched injected replacement music playback to the `Master` channel so native `Music` channel suppression does not cut the injected track.
- Added immediate `CVAR_UPDATE` handling for `Sound_EnableMusic` and `Sound_EnableAllSound` so Ctrl+M and sound toggles react without waiting for periodic ticks.
- Fixed intro routing so intro cues are queued only on true fresh entry into supported music space, not on every internal region swap.
- Rebalanced southern pools so `deatholme` no longer uses `53513`, and Deatholme now uses a darker dedicated intro/day/night selection.
- Added scalable/clipped UI background-art support (`assets/tbc_art.jpg`) with configurable margins and independent X/Y art scaling.
- Added a dedicated `amani` music region (Amani Pass / Zeb ruins routing) with verified old TBC Zul'Aman ambient FileDataIDs (`53825`-`53830`) so troll subzones no longer default to elf music.
- Added dynamic Amani routing fallback for subzone names containing `amani` or `zeb'`.
- Added `thalassian range` regional override to keep southern corridor routing stable.
- Added fail-safe playback fallback for `amani`: if a selected Zul'Aman path cannot be played in the current client build, routing falls back to southern-Eversong pool selection.
- Added `TBC_ID_CATALOG.lua` and `TBC_ID_INDEX.md` generated from wowdev/wow-listfile (`202603051942`) to provide a full TBC zone-music ID database for future config-driven routing.
- Added `tools/generate_tbc_catalog.ps1` to regenerate the TBC catalog/index from a listfile dump.

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
- Added a real manual-stop hold state for `/belr music stop`, so it no longer immediately auto-resumes on the next periodic tick.
- Fixed slash-command music test playback so it now uses the same region-aware pool selection as the live music system.
- Improved slash-command feedback for `/belr music on` so it reports when the music system is only armed because the master addon switch is still off.
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
- Added `/belr` UI with runtime toggles, status display, and test playback controls.
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

