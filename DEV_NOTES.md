# Blood Elf Restore - Dev Notes

## Current Purpose

Current working version:
- `0.7.0-alpha`

This addon restores old TBC-era Blood Elf NPC voice lines in Midnight-era Quel'Thalas while muting the newer Midnight replacement voice set.

It also now includes a scoped Midnight Quel'Thalas music replacement layer for `Silvermoon City`, `Eversong Woods`, `Sunstrider Isle`, southern Eversong remastered subzones, `Ruins of Deatholme`, and selected interiors. That layer mutes tracked supported-zone music FileDataIDs, injects old TBC music on `Master`, temporarily forces native `Sound_MusicVolume=0` while replacement music owns a supported region, and intentionally leaves unrelated zones native.

Main behavior:
- Mutes tracked Midnight Blood Elf voice FileDataIDs from `SoundData.lua`
- Plays TBC greet lines on left-click target selection
- Plays TBC greet lines on gossip open when a target-select greet did not just fire
- Plays TBC bye lines on gossip close
- Plays TBC bye lines when you click away from a previously greeted target
- Plays TBC pissed lines after repeated clicks on the same NPC
- Mutes tracked supported-zone music FileDataIDs from `SoundData.lua` plus generated Midnight catalog data
- Injects region-aware TBC intro/day/night music while you remain in supported Midnight Quel'Thalas zones
- Uses a shuffle-with-cooldown music picker so the same TBC music track is strongly discouraged from repeating immediately

## Core Files

- `Config.lua`
  - User-editable policy layer
  - Owns safe voice/music/UI policy knobs with commented examples and safety warnings
  - Covers behavior timing, fallback scope/classification, built-in name/ID overrides, music routing/scope/timing, intro cooldowns, trace limits, and UI tuning
- `SoundData.lua`
  - Holds all mute IDs for new Midnight voices
  - Holds all old TBC male/female voice FileDataIDs
  - Holds manual Midnight music seed IDs
  - Holds supplemental supported-zone music mute IDs for non-Midnight Blizzard zonemusic
  - Holds TBC Silvermoon intro/day/night music FileDataIDs
- `Debug.lua`
  - DebugChatFrame integration + global `c()` / `cp()` logging shortcuts
  - 2000-line ring-buffer log capture in `BElfVRDB.debugLog`
  - Pre-init buffer for lines logged before `BElfVRDB` exists
  - Copyable dump frame via `BElfVR_ShowLogDump()`
  - Falls back to `print()` when [DebugChatFrame](https://github.com/kapresoft/wow-addon-debug-chat-frame) is not installed
- `BElfRestore.lua`
  - Main addon logic
  - UI
  - Target/gossip event handling
  - Zone/music event handling
  - NPC classification
  - Role and gender overrides
- `bloodElfRestore.toc`
  - Correct TOC name matching the addon folder
  - Loads `Midnight_ID_catalog.lua` before `SoundData.lua`
  - Loads `Debug.lua` before `BElfRestore.lua`
- `Midnight_ID_catalog.lua`
  - Generated Midnight `mus_120_*` music catalog used at runtime
  - Source-of-truth dataset for bulk Midnight music muting
- `Midnight_ID_Index.md`
  - Human-readable Midnight music family index generated from wowdev/wow-listfile
  - Documents runtime exclusions and supplemental supported-zone notes
- `TBC_ID_CATALOG.lua`
  - Generated TBC zone-music ID database for config/data authoring
  - Includes Quel'Thalas focus (`Eversong`, `Ghostlands`, `Zulaman`, `Sunwell`)
  - Includes Outland and key TBC instance music folders
- `TBC_ID_INDEX.md`
  - Human-readable index and zone counts for the generated catalog

## Major Fixes Already Applied

### Addon Detection / Load

- Renamed the TOC to `bloodElfRestore.toc`
- Aligned `ADDON_NAME` with the folder/TOC name (`bloodElfRestore`)
- This fixed WoW not listing the addon at all

### UI Added

The addon now has an in-game UI window opened with:
- `/belr`
- Legacy alias: `/belvr` still maps to the same handler.

Current UI includes:
- `Voice` and `Music` tabs instead of one long control stack
- Enable addon toggle
- Mute new Midnight VO toggle
- Verbose debug toggle
- Fallback classifier toggle
- Left-click greet toggle
- Invert NPC sex mapping toggle
- Status text
- Test buttons for male/female noble, standard, and military greet/bye/pissed
- Re-apply mutes
- Restore Midnight VO
- Music enable toggle
- Music mute toggle
- Music verbose debug toggle
- Music trace recorder toggle
- Music intro-on-entry toggle
- Music test buttons for intro/day/night
- Re-apply music mutes
- Clear music trace
- Restore Midnight music
- Force music refresh
- Optional semi-transparent panel background art (`assets/tbc_art.jpg`) with tunable margins and manual X/Y art scaling

Behavior note:
- `Re-apply mutes` now also turns the mute option back on if it had been disabled
- Hovering checkboxes now shows plain-English help text for non-technical users
- Verbose logs now include NPC names in key trigger messages
- Music trace logs are stored in SavedVariables, not in a standalone text file, and are written to disk on `/reload` or logout
- Music-tab action rows are anchored below the live music status text so status growth does not overlap the buttons

### NPC Detection Fixes

Original issue:
- `UnitRace("target")` was not usable for these Midnight NPCs

Fixes added:
- Hidden tooltip scan for `"Blood Elf"` text
- Humanoid fallback classifier when race text is hidden
- Hidden-race humanoid fallback on target selection is limited to positive Blood Elf name/profile hints instead of generic humanoids
- The hidden-race humanoid fallback is now limited to Blood Elf zones so unrelated humanoids elsewhere do not get Blood Elf VO
- Built-in name profile fallback for repeated NPC names that hide useful metadata

### Left-Click / Right-Click Behavior

Added:
- `PLAYER_TARGET_CHANGED` handling so greet can fire on normal left-click target selection
- Left-click target-select greet uses fake distance falloff buckets:
  - close: always plays
  - near: usually plays
  - far: rarely plays
  - out of range: never plays
- Dedupe window so right-click gossip does not immediately double-fire another greet
- Bye playback when target is cleared/switched away from a previously greeted NPC
- Target-loss bye now has both a minimum delay and a maximum believable age so late fly-away disengages do not still play point-blank farewell audio

### Gender / Role Overrides

Added:
- Saved per-NPC gender overrides
- Saved per-NPC role overrides
- Built-in default name-based profiles

Current built-in defaults (defined in `Config.lua` `voice.profiles.byName`):
- `Lyrendal`
  - role: `standard`, vendor greet category
- `Mahra Treebender`
  - excluded from Blood Elf fallback classification
- `Silvermoon Resident`
  - role: `standard`
- `Doomsayer`
  - role: `standard`
- `Household Attendant`
  - role: `standard`
- `Cousin Slowhands`, `Mystic Birdhat`, `Collector Unta`, `Merchant Maku`, `Killia`, `Melanie Morten`
  - excluded (mount service vendors, not Blood Elf NPCs)
- `Sin'dorei Child`, `Sin'dorei Children`, `Sindorei Child`, `Blood Elf Child`, `Silvermoon Child`, `Sin'dorei Orphan`
  - excluded (no TBC child voice pool)

Manual override commands still exist:
- `/belr force male`
- `/belr force female`
- `/belr force clear`
- `/belr role military`
- `/belr role noble`
- `/belr role standard`
- `/belr role clear`

Important:
- `/belr force ...` and `/belr role ...` now apply to the current target's full unit `GUID`
- This is intentional because Midnight can reuse the same `npc=...` ID across different actual NPCs
- Legacy saved `npc=...` overrides are migrated once into `BElfVRDB.legacyOverrideBackup`, then cleared so old bad mappings do not keep applying

New name-wide override commands also exist:
- `/belr force-name male`
- `/belr force-name female`
- `/belr force-name clear`
- `/belr invert`
- `/belr invert on`
- `/belr invert off`
- `/belr suppress`
- `/belr suppress on`
- `/belr suppress off`
- `/belr role-name military`
- `/belr role-name noble`
- `/belr role-name standard`
- `/belr role-name clear`
- `/belr verbose on`
- `/belr verbose off`

These apply to every NPC that shares the current target's displayed name, which helps when
Blizzard uses multiple `npc=...` IDs for visually identical Midnight NPCs.

### Replacement Playback Rule

- TBC replacement playback now runs only when `Mute new Midnight VO` is enabled
- If muting is disabled, the addon stops injecting TBC lines so you do not hear both TBC and Midnight VO layered together
- Before playing a new injected TBC line, the addon stops the previous injected TBC sound handle to prevent overlap on rapid retargeting/clicks
- Injected TBC lines are also rate-limited with a short minimum gap, so rapid greet/bye/greet chains are suppressed instead of stacking
- Target-loss bye playback now waits for a short post-greet delay, so instant click-off does not overlap the greet but normal click-away still gets a bye
- Injected TBC playback can briefly suppress the native dialog channel and plays on `Master` to block unknown/untracked Midnight VO from stacking
- Native dialog suppression is now user-toggleable for compatibility testing
- Event-driven playback applies the suppression window before the TBC rate-limit check, so even skipped replacement lines can still block a leaking native Midnight line
- Injected TBC playback now respects WoW sound disable states, including the usual `Ctrl+S` sound-effects toggle

### Music Replacement Rule

- TBC replacement music runs only when `Enable addon logic`, `Enable replacement music logic`, and `Mute tracked supported-zone music files` are all enabled
- If tracked music muting is disabled, the addon stops injecting TBC music so native and TBC music do not stack
- Music ownership is now scoped to Midnight Quel'Thalas map lineage, not only broad zone text:
  - zone name
  - subzone name
  - parent map lineage tokens
- Native-only guards now explicitly keep some areas on Blizzard music even if the parent zone would otherwise qualify:
  - `Harandar`
- Supported broad music routing currently includes:
  - `Silvermoon City`
  - `Sanctum of Light`
  - `Eversong Woods`
- Region routing now groups playback into:
  - `silvermoon`
  - `silvermoon_interior`
  - `eversong`
  - `sunstrider`
  - `eversong_south`
  - `deatholme`
  - `amani`
- Supported subzone fallback and override routing now includes:
  - `The Bazaar`
  - `Wayfarer's Rest` mapped into the dedicated `silvermoon_interior` family
  - `Sunstrider Isle`
  - `Tranquillien`
  - `Sanctum of the Moon`
  - several southern remastered subzones mapped into the `eversong_south` family
  - `Ruins of Deatholme` mapped into the dedicated `deatholme` family
  - narrow token fallback for subzones containing `deatholme`
  - `Amani Pass`, `Zeb'Nowa`, and `Zeb'tela Ruins` mapped into the dedicated `amani` family
  - dynamic pattern fallback for troll-style subzone names containing `amani` or `zeb'`
- The runtime mute set is now composed from three layers:
  - generated Midnight `mus_120_*` family coverage from `Midnight_ID_catalog.lua`
  - manual non-catalog Midnight seed IDs in `BElfVR_NewMusicIDs` (for `mus_1200_*` and similar gaps)
  - supplemental Blizzard zonemusic IDs in `BElfVR_SupplementalMusicMuteIDs` for supported interiors such as inns / taverns
- Runtime Midnight catalog exclusions now intentionally preserve Harandar families:
  - `harandar_1`
  - `harandar_2`
  - `harandar_3`
  - `lightbloom_harandar`
- The music system checks:
  - zone changes
  - indoor-like subzone changes
  - resting state changes
  - in-game day/night phase
  - relevant `CVAR_UPDATE` changes
- An intro cue can optionally play on entry into supported zones before the day/night rotation
- Intro cues use a 10-minute cooldown persisted in SavedVariables so they do not spam on quick re-entry, including across relogs and game restarts
- Intro cooldown history is persisted in `BElfVRDB.musicIntroHistory`, so `/reload` does not reset the intro timer
- Intro cooldown policy is read from `Config.lua` and can be scoped by region, zone, subzone, area (`zone||subzone`), pool, and exact FileDataID
- Known-duration tracks are now allowed to finish naturally instead of being cut off by the old coarse rotation timer
- Long stays in the same supported area still have fallback periodic rotation for unknown-duration cases
- The music shuffle system keeps recently played TBC tracks on a cooldown so the same track does not immediately repeat
- Playback routing now keys off a stable region + day/night signature instead of tiny subzone churn, which greatly reduces constant restarts while moving around Silvermoon
- Loading-screen arrivals into supported music space now arm a short world-entry settle window before addon playback is allowed to start
- Active injected-music ownership is now tracked separately from the player's current area context, so supported-region swaps can force an immediate handoff instead of waiting for the stale track to finish
- Injected replacement music currently plays on `Master`, not `Music`, so the addon can hard-suppress Blizzard's native music channel without cutting its own replacement track
- The steady-state `Sound_MusicVolume=0` suppression path was reinstated for supported replacement ownership after some Silvermoon load-screen arrivals kept native Midnight music alive through tracked muting and repeated `StopMusic()` guards
- Temporary audio-setting backups are persisted in `BElfVRDB.pendingCVarRestores` and restored on area exit, addon load, `/reload`, and `PLAYER_LOGOUT`
- `Sound_EnableAmbience` suppression remains a narrow Deatholme-specific fallback path, with the same persisted-restore safety
- Ctrl+M and global music toggles now trigger immediate re-evaluation through `CVAR_UPDATE` handling
- Intro cues are now queued only on true fresh supported-entry, not on every internal region swap
- Music debug output now indicates:
  - support source
  - scope source
  - override source
  - native-only state
- GUID parsing and debug logging now fail closed on protected or nonstandard gossip-object GUID values instead of assuming every interactable target is a normal creature GUID
- `/belr music stop` now creates a real manual stop state and stays idle until a meaningful resume trigger occurs
- Slash music test commands now use the same region-aware pool selection as the live music system
- `/belr status` now reports:
  - current music zone
  - current subzone
  - current region
  - catalog counts
  - supplemental counts
- `/belr music note <text>` adds a one-line manual marker into `musicTraceLog` with current zone/subzone/region context (useful during high-speed flight mapping)
- Music trace recording can capture:
  - context changes
  - support source (zone vs subzone)
  - scope source
  - override source
  - selected pool
  - selected track
  - skip reasons
  - unsupported-region exits

### Voice Pool Logic

Original issue:
- Greet lines were mixed with vendor lines, so guards/residents could say vendor-only barks like "I have one of a kind items"

Fix applied:
- The TBC `greet` tables are now split internally into:
  - `vendor`
  - `greet`
- Standard greet playback now uses only the non-vendor `greet` sub-pool
- This is split by role:
  - `military`
  - `noble`
  - `standard`

Important:
- This split depends on the current ordering in `SoundData.lua`
- If the TBC sound lists are reordered, the layout offsets in `BElfRestore.lua` must also be updated

## Community Configuration Notes

### Where To Add New Midnight Mute IDs

Add them to:
- `BElfVR_NewVoiceIDs` in `SoundData.lua`
- `BElfVR_NewMusicIDs` in `SoundData.lua` for manual music-specific non-catalog IDs such as `mus_1200_*`
- `BElfVR_SupplementalMusicMuteIDs` in `SoundData.lua` for non-Midnight Blizzard zonemusic that still appears inside supported Midnight Quel'Thalas interiors

Preferred workflow for Midnight music coverage:
- regenerate `Midnight_ID_catalog.lua` and `Midnight_ID_Index.md`
- keep broad family coverage in the generated catalog
- keep only true exceptions or non-catalog gaps in `SoundData.lua`

### Where To Add New Old TBC Sound IDs

Add them to:
- `BElfVR_TBCVoices_Male`
- `BElfVR_TBCVoices_Female`
- `BElfVR_TBCMusic.intro`
- `BElfVR_TBCMusic.day`
- `BElfVR_TBCMusic.night`
- `BElfVR_TBCMusicRegions.<region>.intro`
- `BElfVR_TBCMusicRegions.<region>.day`
- `BElfVR_TBCMusicRegions.<region>.night`

### TBC Catalog Data Source

- `TBC_ID_CATALOG.lua` and `TBC_ID_INDEX.md` are generated from wowdev/wow-listfile release `202603051942`.
- Scope is TBC-era zone-music families (not every possible TBC-era asset path in the client).
- Use this catalog as the source-of-truth dataset for future `config.lua` routing work.
- Regeneration command:
  - `tools/generate_tbc_catalog.ps1 -ListfilePath <community-listfile-withcapitals.csv> -ReleaseTag <release-tag>`

### Midnight Catalog Data Source

- `Midnight_ID_catalog.lua` and `Midnight_ID_Index.md` are generated from wowdev/wow-listfile release `202603061837`.
- Scope is Midnight music families under `sound/music/midnight/mus_120_*.mp3`.
- The generated catalog is now loaded at runtime before `SoundData.lua`.
- Runtime muting intentionally excludes Harandar families through `MIDNIGHT_CATALOG_MUTE_FAMILY_EXCLUSIONS`.
- Runtime muting also supplements the catalog with manual `mus_1200_*` seeds and Blizzard tavern / inn zonemusic IDs for supported interiors.
- Regeneration command:
  - `tools/generate_midnight_catalog.ps1 -ListfilePath <community-listfile.csv> -ReleaseTag <release-tag>`

Keep the current grouping/order:
- noble block first
- standard block second
- military block third

Inside each role block:
- keep vendor lines together
- keep greeting lines together

If that ordering changes, update the role layout tables in:
- `BElfRestore.lua`

### Where To Add Built-In Automatic Fixes

In `Config.lua` (read by `BElfRestore.lua` at startup):

- `voice.overrides.genderByNPCID` → builds `DEFAULT_GENDER_OVERRIDES`
  - For known NPC IDs with wrong client-reported gender
- `voice.overrides.roleByNPCID` → builds `DEFAULT_ROLE_OVERRIDES`
  - For known NPC IDs with wrong role classification
- `voice.profiles.byName` → builds `DEFAULT_NAME_PROFILES`
  - For repeated NPC names that need fallback handling without exact IDs
  - Supports `role`, optional `vendor=true`, and optional `exclude=true`
- `BElfVRDB.guidGenderOverrides`
  - User-saved gender overrides by full target GUID (best for exact individual NPCs)
- `BElfVRDB.guidRoleOverrides`
  - User-saved role overrides by full target GUID (best for exact individual NPCs)
- `BElfVRDB.nameGenderOverrides`
  - User-saved gender overrides by lowercase NPC name
- `BElfVRDB.nameRoleOverrides`
  - User-saved role overrides by lowercase NPC name
- `BLOOD_ELF_MUSIC_ZONES`
  - Lowercase zone names that should keep TBC music active
- `BLOOD_ELF_MUSIC_SUBZONES`
  - Lowercase subzone names that should keep TBC music active even when Blizzard reports a different top-level zone
- `BLOOD_ELF_MUSIC_SCOPE_TOKENS`
  - Normalized map-lineage / zone tokens that allow the music system to take control
- `BLOOD_ELF_MUSIC_NATIVE_ONLY_TOKENS`
  - Normalized area tokens that must stay native even inside a broader supported parent zone
- `MUSIC_SUBZONE_REGION_OVERRIDES`
  - Exact lowercase subzone names that should route into a different TBC region family
- `MUSIC_SUBZONE_REGION_TOKEN_OVERRIDES`
  - Narrow token fallbacks for subzones whose exact names may drift slightly
- `MIDNIGHT_CATALOG_MUTE_FAMILY_EXCLUSIONS`
  - Midnight catalog families that should stay native even though they exist in the generated dataset
- `BElfVR_SupplementalMusicMuteIDs`
  - Non-Midnight Blizzard zonemusic IDs still worth muting inside supported interiors
- `BElfVRDB.musicTraceLog`
  - User-captured music route trace buffer stored in SavedVariables
- `BElfVRDB.pendingCVarRestores`
  - Persisted temporary audio-setting backups for recovery after `/reload` or logout
- `BElfVRDB.musicIntroHistory`
  - Persisted intro cooldown timestamps keyed by config bucket (`default`, `region:...`, `pool:...`, `track:...`, etc.)

## Known Heuristics / Limitations

- Some Midnight NPCs hide race text entirely
- Some NPCs may report the wrong sex from the client (`UnitSex`)
- Current behavior treats Midnight Blood Elf `UnitSex` as reversed by default
- The UI includes an `Invert NPC sex mapping` toggle to flip back if Blizzard data is correct for a given case
- Hidden-race fallback is intentionally zone-limited and should not be trusted as a global classifier
- Name-based role heuristics are simple:
  - names containing `guard`, `ranger`, `captain`, `blood knight`, `champion` -> `military`
  - names containing `lord`, `lady`, `noble` -> `noble`
  - otherwise -> `standard`
- Music replacement is a first-pass addon-side injector, not a true engine-level replacement of Blizzard's internal zone-music resolver
- The addon can log area context changes for music, but it cannot reliably read the exact native Midnight music FileDataID that Blizzard's engine picked at runtime
- The generated Midnight catalog covers `mus_120_*` families only; anonymous `mus_1200_*` IDs and non-listfile SoundKit playback still need manual discovery
- Track rotation currently uses a configurable approximate timer, because addon Lua does not get a clean "this injected FileDataID finished" callback for this playback path
- The music trace recorder is a capped ring buffer and intentionally trims old entries; it is meant for focused capture sessions, not permanent long-term logging

## Suggested Next Improvements

1. Add a richer role model if needed:
   - vendor
   - questgiver
   - trainer
   - civilian
2. Add more built-in Midnight Silvermoon NPC overrides by exact `npc=...` IDs
3. Add more comments near role layout offsets if more community editing is expected
4. Consider deprecating the old `genderOverrides` / `roleOverrides` saved-variable fields entirely in a cleanup pass
5. Expand the Midnight Quel'Thalas scope tokens, native-only tokens, and subzone allow-lists from recorded trace sessions
6. Use recorded trace sessions to identify additional anonymous `mus_1200_*` or non-listfile music playback that still leaks through

## Session Update (2026-03-18 - DebugChatFrame Integration, Log Dump, and Intro Music Fix)

This session added full DebugChatFrame integration, a persistent debug log system, and fixed the long-standing intro music bug.

### DebugChatFrame integration

- Added `Debug.lua` as a new file loaded before `BElfRestore.lua`
- Integrates with the optional [DebugChatFrame](https://github.com/kapresoft/wow-addon-debug-chat-frame) addon for a dedicated `BElfVR` chat tab
- Provides global `c(...)` for standard logging and `cp(moduleName, ...)` for module-prefixed logging
- Falls back to `print()` when DebugChatFrame is not installed
- All `c()` / `cp()` output is also captured to a 2000-line ring buffer in `BElfVRDB.debugLog`
- Pre-init buffer holds lines logged before `ADDON_LOADED` and flushes them once `BElfVR_InitDebug()` runs
- Includes programmatic `LoadAddOn("DebugChatFrame")` fallback for both modern (`C_AddOns`) and legacy API paths
- `BElfVR_InitDebug()` is called from the `ADDON_LOADED` block in `BElfRestore.lua`

### Debug log dump

- Added `/belr dumplog` (also `/belr dump`) — opens a draggable, scrollable EditBox frame with the full ring-buffer contents
- Users can `Ctrl+A` then `Ctrl+C` to copy the entire log
- Added `/belr log clear` to wipe the buffer
- The raw log is also available at `WTF/Account/<ACCOUNT>/SavedVariables/bloodElfRestore.lua` after logout

### Structured debug logging

- Added `c()` calls at all major event handlers in `BElfRestore.lua`:
  - `ADDON_LOADED`, `PLAYER_LOGIN`, `PLAYER_ENTERING_WORLD`, `PLAYER_TARGET_CHANGED`
  - `GOSSIP_SHOW`, `GOSSIP_CLOSED`, zone changes, `CVAR_UPDATE`, `PLAYER_LOGOUT`
- Bridged existing `Log()` → `c("Voice", ...)` and `LogMusic()` → `c("Music", ...)` so all existing verbose output also routes to DebugChatFrame
- Added entry logging to `PlayRandomTBC()`, `ApplyMutes()`, and `EvaluateMusicState()`
- Filtered `CVAR_UPDATE` logging to `Sound_*` CVars only (camera, perks, splash screen CVars are ignored)
- Suppressed `EvaluateMusicState: periodic` heartbeat logging (~1s interval) to prevent log flooding

### Intro music fix

Root cause: loading-screen arrivals (login, reload, zone portals) always set `musicSkipIntroOnWorldEntry = true`, which unconditionally bypassed the cooldown system. The intro could never play on any entry that came through a loading screen — which is every login and most zone transitions.

Fix:
- Removed the unconditional intro skip for loading-screen arrivals
- All supported-zone entries now queue the intro via `ShouldQueueMusicIntro()` and defer to `ShouldPlayMusicIntro()` for cooldown enforcement
- The existing 10-minute SavedVariables-persisted cooldown (`MUSIC_INTRO_REPEAT_COOLDOWN = 600`) prevents spam across rapid relogs
- The world-entry settle window no longer clears `musicIntroPending`, so the intro survives the brief startup purge delay

Result: first login of the day → intro plays. Quick relog → cooldown blocks it, plays day/night track. Come back after 10+ minutes → intro plays again.

### Misc

- Added `.luarc.json` with WoW API global declarations for Lua language server (gitignored)
- Updated `.gitignore` with `.luarc.json`

## Session Update (2026-03-12 - Silvermoon Interior Music and Documentation Pass)

This session added dedicated Silvermoon City interior music support and resolved several README-to-code discrepancies found during a full cross-reference review.

What changed:

- Added `silvermoon_interior` music region with GL_ScenicWalk TBC tracks (`53513`, `53514`, `53515`) in `SoundData.lua`
- Added `IsIndoors()` detection in `GetMusicContext()`:
  - When the player is inside Silvermoon City and `IsIndoors()` returns true, the region swaps from `silvermoon` to `silvermoon_interior`
  - Explicit subzone overrides still win over the `IsIndoors()` fallback
  - Walking back outside returns to the normal `silvermoon` outdoor day/night cycle
  - The `ZONE_CHANGED_INDOORS` event (already registered) triggers re-evaluation automatically
- Added `Wayfarer's Rest` as an explicit supported subzone in `Config.lua` with `silvermoon_interior` routing
- Added fallback in `GetMusicTrackPool()` so empty `silvermoon_interior` categories (like intro) fall back to the regular Silvermoon outdoor chain, then to the legacy `BElfVR_TBCMusic` global pool
- Added `MUSIC_REGION_SILVERMOON_INTERIOR` constant in `BElfRestore.lua`

Documentation fixes from the cross-reference review:

- Fixed `README.md` LICENSE link from an absolute Windows path to a relative `[LICENSE](LICENSE)` link
- Fixed `README.md` scope config attribution from `BElfRestore.lua` to `Config.lua` (line 103)
- Added all six voice test slash commands to `README.md` Commands section
- Added Installation and Addon Structure sections to `README.md` with a folder tree and TOC load order
- Updated interior and region routing descriptions across `README.md` and `DEV_NOTES.md`

Known limitation:

- `IsIndoors()` returns nil for large indoor spaces where WoW allows mounting, so some Silvermoon interiors may not trigger the swap
- Interiors that change native Midnight music without any zone/subzone text change or `IsIndoors()` flag cannot be detected by addon Lua
- Additional interior subzones can be added to `Config.lua` `bySubZone` routing as they are discovered during testing

## Session Update (2026-03-08 - Region Handoff and Protected GUID Hardening)

This follow-up came after the Silvermoon world-entry overlap fix, when two more regressions showed up during live retesting:

- moving between supported Quel'Thalas music regions could keep the old injected TBC track playing until its natural end instead of handing off immediately
- interacting with a non-NPC dungeon gossip object (`Light-Starved Blossom`) triggered a taint/secret-string error path while the addon tried to parse and log the target GUID like a normal creature

What changed:

- Split music state into two responsibilities:
  - current player context (`musicCurrentAreaKey`, `musicCurrentRegionKey`)
  - currently playing injected track ownership (`musicPlaybackAreaKey`, `musicPlaybackRegionKey`)
- Supported-region swaps now compare the active injected track's ownership against the live player context and force an immediate music handoff when they diverge
- Added explicit verbose tracing for playback/context mismatch swaps so future region-handoff bugs are easier to spot in `music verbose`
- Hardened `GetNPCIDFromGUID()` with protected-call parsing so nonstandard or protected GUID values fail closed instead of exploding on `strsplit`
- Added guarded debug-string formatting so logging protected GUID-like values no longer taints or crashes gossip/object interactions

Practical outcome:

- traveling from `Silvermoon City` to `Sunstrider Isle` and similar supported-region swaps now changes TBC music immediately
- gossip objects and non-creature interactables no longer crash the addon just because `UnitGUID()` returned a protected or non-creature value

## Session Update (2026-03-08 - Silvermoon World-Entry Music Overlap Fix)

This follow-up was specifically for the stubborn Silvermoon double-music bug that still happened on reload, hearth, teleport, and other loading-screen arrivals after the broader 0.6.1-alpha hotfix pass.

Observed failure mode:

- Native Midnight Silvermoon music could survive:
  - tracked music FileDataID muting
  - startup music purge ordering
  - repeated `StopMusic()` guards
  - delayed world-entry settle windows
- The overlap was easiest to reproduce on `ZONE_CHANGED_NEW_AREA` arrivals into `Silvermoon City`, where Blizzard's native track would keep playing underneath injected TBC day music.

What changed:

- Added explicit world-entry settle handling for supported music arrivals:
  - pending world-entry tracking across loading screens
  - intro suppression for loading-screen arrivals
  - short post-arrival settle window before replacement playback is allowed
  - repeated native `StopMusic()` guard pulses during the settle window
  - direct `ZONE_CHANGED_NEW_AREA` arming so the fix does not depend on Blizzard event ordering
- Reverted supported-zone replacement playback back to `Master`
- Re-enabled supported-zone steady-state native suppression through `Sound_MusicVolume=0`
- Kept persisted restore safety for temporary audio CVars so the player's previous values still recover on exit, reload, addon load, and logout

Practical outcome:

- Silvermoon reload, teleport, and hearth arrivals no longer stack Midnight native music with old TBC replacement music
- The earlier "play on `Music` and avoid slider hijacking" model is no longer the active runtime design

Tradeoff:

- While supported replacement music is active, the user's music slider no longer directly controls the injected TBC track because playback is back on `Master`

## Session Update (2026-03-07 - Music Hardening, Catalog Refactor, and Documentation Pass)

This session was the large cleanup after repeated music-overlap regressions in Deatholme, Harandar, and Silvermoon interiors.
It also included a post-refactor load recovery after the new `Config.lua` policy extraction briefly pushed `BElfRestore.lua` over WoW's chunk-local limit and introduced a few ordering/syntax regressions.

What changed:

- Tightened music ownership to Midnight Quel'Thalas only:
  - added map-lineage scope gating
  - added native-only exclusion tokens
  - kept Harandar native
- Fixed Deatholme routing regressions:
  - restored exact `Ruins of Deatholme` routing
  - added `deatholme` token fallback for small subzone-name shifts
  - re-darkened the dedicated TBC `deatholme` day pool
- Reworked tracked music muting from a partial hand-maintained list into a generated-catalog model:
  - added `Midnight_ID_catalog.lua`
  - added `Midnight_ID_Index.md`
  - added `tools/generate_midnight_catalog.ps1`
  - updated `bloodElfRestore.toc` to load the generated catalog before `SoundData.lua`
- Converted runtime Midnight muting to broad family coverage with explicit exclusions instead of hand-adding one family at a time:
  - Harandar families are now excluded at the family level
  - non-catalog `mus_1200_*` gaps still live in `BElfVR_NewMusicIDs`
- Fixed Silvermoon inn overlap:
  - added `BElfVR_SupplementalMusicMuteIDs`
  - currently includes Blizzard tavern / inn / rest-area zonemusic IDs `53737`-`53778`
  - these supplemental IDs are only applied while the addon owns a supported music region
- Removed global login-time music muting:
  - old `ApplyMutes` / `RemoveMutes` music behavior was too broad
  - all music muting now flows through `SetTrackedMusicMutesActive`
  - muting is now strictly region-scoped
- Reworked mute-list building:
  - added helper logic to build one deduped base mute set
  - base set now includes catalog-backed Midnight data plus supplemental supported-zone data
  - optional region-specific extra mutes can still be layered on top
- Fixed music slider and temporary-audio-setting safety:
  - replacement music now plays on `Music`, not `Master`
  - steady-state slider hijacking is disabled
  - persisted restore values were added for `Sound_MusicVolume`
  - persisted restore values were added for `Sound_EnableAmbience`
  - persisted restore values were added for `Sound_EnableDialog`
  - recovery runs on addon load and `PLAYER_LOGOUT`
  - this `Music`-channel model was later reverted on `2026-03-08` after Silvermoon load-screen arrivals still produced native+TBC overlap
- Expanded the real user-editable config surface:
  - created `Config.lua`
  - moved safe voice/music/UI policy tables out of hardcoded runtime blocks
  - moved intro cooldown matching out of transient runtime-only state
  - persisted intro cooldown history in `BElfVRDB.musicIntroHistory`
  - intro cooldown rules can now be scoped by region, zone, subzone, area, pool, and exact FileDataID
  - role heuristics, scope tokens, supported zones/subzones, region routing, built-in name profiles, trace limits, and UI art/layout settings are now config-backed
- Expanded live debugging and status output:
  - context lines now include `scope`, `scopeSource`, `overrideSource`, and `nativeOnly`
  - `/belr status` now reports catalog counts and supplemental mute counts
  - UI text now refers to tracked supported-zone music instead of tracked Midnight Silvermoon music

Removed or superseded behavior:

- Removed the assumption that music problems were only Silvermoon / Eversong problems
- Removed the old "mute everything globally and hope it is fine" music path
- Removed the old documentation assumption that replacement music intentionally used `Master` with `Sound_MusicVolume=0` in steady-state
  - this was accurate for the 2026-03-07 runtime, but was later reversed by the 2026-03-08 Silvermoon world-entry fix

Current practical debugging rule:

- If a leak is inside supported Midnight Quel'Thalas and `Music muted IDs` looks correct in `/belr status`, the next suspect is usually:
  - anonymous `mus_1200_*`
  - non-listfile Blizzard zonemusic
  - SoundKit-style playback not visible in the Midnight catalog

## Session Update (2026-03-05)

Low-risk cleanup pass applied in `BElfRestore.lua` after review triage:

- Removed unused `local addon = {}` declaration near the top of the file.
- Removed dead fallback-zone entry `["zul'aman"] = false` from `BLOOD_ELF_FALLBACK_ZONES`.
- Added an early `OnUpdate` short-circuit:
  - `if not IsMusicReplacementActive() then return end`
  - This avoids periodic music evaluation work while replacement music is disabled/unmuted.

Notes:
- No behavior-changing refactors were done in this pass.
- Potential larger refactors (voice pool structural enforcement, trace-buffer internals) remain optional and were intentionally deferred.

## Session Update (2026-03-05 - Southern Routing Stabilization)

Implemented a focused music-routing and trace tooling pass:

- Replaced active southern routing semantics from `ghostlands` to `eversong_south`.
- Added dedicated `deatholme` routing for `Ruins of Deatholme` with a narrow dark pool.
- Added compatibility handling so legacy `BElfVR_TBCMusicRegions.ghostlands` data is still consumed as `eversong_south`.
- Added `/belr music note <text>` to write manual markers into the SavedVariables music trace with current zone/subzone/region context.
- Added `amani` regional routing for Amani/Zeb-style subzones and mapped it to verified Zul'Aman ambient IDs (`53825`-`53830`) in `SoundData.lua`.
- Updated docs and in-game help text for the new routing names and command.

Data note:
- No speculative Midnight mute IDs were added in this pass. Native leak spots are still expected to require additional verified IDs from future focused trace/datamine passes.

