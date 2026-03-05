# Blood Elf Voice Restore - Dev Notes

## Current Purpose

Current working version:
- `0.4.0-alpha`

This addon restores old TBC-era Blood Elf NPC voice lines in Midnight-era Silvermoon while muting the newer Midnight replacement voice set.

It also now includes a broader first-pass music replacement layer for `Silvermoon City`, `Eversong Woods`, `Sunstrider Isle`, and ghostlands-style southern remastered subzones that can mute tracked Midnight music FileDataIDs and inject old TBC music on the music channel.

Main behavior:
- Mutes tracked Midnight Blood Elf voice FileDataIDs from `SoundData.lua`
- Plays TBC greet lines on left-click target selection
- Plays TBC greet lines on gossip open when a target-select greet did not just fire
- Plays TBC bye lines on gossip close
- Plays TBC bye lines when you click away from a previously greeted target
- Plays TBC pissed lines after repeated clicks on the same NPC
- Mutes tracked Midnight Silvermoon / Eversong music FileDataIDs from `SoundData.lua`
- Injects region-aware TBC intro/day/night music while you remain in supported Blood Elf zones
- Uses a shuffle-with-cooldown music picker so the same TBC music track is strongly discouraged from repeating immediately

## Core Files

- `SoundData.lua`
  - Holds all mute IDs for new Midnight voices
  - Holds all old TBC male/female voice FileDataIDs
  - Holds tracked Midnight music mute IDs
  - Holds TBC Silvermoon intro/day/night music FileDataIDs
- `BElfVoiceRestore.lua`
  - Main addon logic
  - UI
  - Target/gossip event handling
  - Zone/music event handling
  - NPC classification
  - Role and gender overrides
- `bloodElfRestore.toc`
  - Correct TOC name matching the addon folder

## Major Fixes Already Applied

### Addon Detection / Load

- Renamed the TOC to `bloodElfRestore.toc`
- Aligned `ADDON_NAME` with the folder/TOC name (`bloodElfRestore`)
- This fixed WoW not listing the addon at all

### UI Added

The addon now has an in-game UI window opened with:
- `/belvr`

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

Behavior note:
- `Re-apply mutes` now also turns the mute option back on if it had been disabled
- Hovering checkboxes now shows plain-English help text for non-technical users
- Verbose logs now include NPC names in key trigger messages
- Music trace logs are stored in SavedVariables, not in a standalone text file, and are written to disk on `/reload` or logout

### NPC Detection Fixes

Original issue:
- `UnitRace("target")` was not usable for these Midnight NPCs

Fixes added:
- Hidden tooltip scan for `"Blood Elf"` text
- Humanoid fallback classifier when race text is hidden
- Left-click target selection can use the hidden-race humanoid fallback before gossip opens
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

### Gender / Role Overrides

Added:
- Saved per-NPC gender overrides
- Saved per-NPC role overrides
- Built-in default name-based profiles

Current built-in defaults:
- `Lyrendal`
  - role: `standard`
  - vendor greet category
- `Mahra Treebender`
  - excluded from Blood Elf fallback classification
- `Silvermoon Resident`
  - role: `standard`

Manual override commands still exist:
- `/belvr force male`
- `/belvr force female`
- `/belvr force clear`
- `/belvr role military`
- `/belvr role noble`
- `/belvr role standard`
- `/belvr role clear`

Important:
- `/belvr force ...` and `/belvr role ...` now apply to the current target's full unit `GUID`
- This is intentional because Midnight can reuse the same `npc=...` ID across different actual NPCs
- Legacy saved `npc=...` overrides are migrated once into `BElfVRDB.legacyOverrideBackup`, then cleared so old bad mappings do not keep applying

New name-wide override commands also exist:
- `/belvr force-name male`
- `/belvr force-name female`
- `/belvr force-name clear`
- `/belvr invert`
- `/belvr invert on`
- `/belvr invert off`
- `/belvr suppress`
- `/belvr suppress on`
- `/belvr suppress off`
- `/belvr role-name military`
- `/belvr role-name noble`
- `/belvr role-name standard`
- `/belvr role-name clear`
- `/belvr verbose on`
- `/belvr verbose off`

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

- TBC replacement music runs only when `Enable addon logic`, `Enable replacement music logic`, and `Mute tracked Midnight Silvermoon music files` are all enabled
- If tracked music muting is disabled, the addon stops injecting TBC music so Midnight and TBC music do not stack
- Supported broad music routing currently includes:
  - `Silvermoon City`
  - `Sanctum of Light`
  - `Eversong Woods`
- Region routing now groups playback into:
  - `silvermoon`
  - `eversong`
  - `sunstrider`
  - `ghostlands`
- Supported subzone fallback and override routing now includes:
  - `The Bazaar`
  - `Sunstrider Isle`
  - `Tranquillien`
  - `Sanctum of the Moon`
  - several southern / haunted remastered subzones mapped into the `ghostlands` family
- The music system checks:
  - zone changes
  - indoor-like subzone changes
  - resting state changes
  - in-game day/night phase
- A first-entry intro cue can optionally play before the day/night rotation
- Intro cues now have a separate cooldown so they do not spam on quick re-entry
- Known-duration tracks are now allowed to finish naturally instead of being cut off by the old coarse rotation timer
- Long stays in the same supported area still have fallback periodic rotation for unknown-duration cases
- The music shuffle system keeps recently played TBC tracks on a cooldown so the same track does not immediately repeat
- Playback routing now keys off a stable region + day/night signature instead of tiny subzone churn, which greatly reduces constant restarts while moving around Silvermoon
- Music stop transitions currently use a longer fade than the first pass to reduce abrupt cutoffs when area routing changes
- Music debug output now indicates whether the current area was matched by zone name or by subzone allow-list
- `/belvr music stop` now creates a real manual stop state and stays idle until a meaningful resume trigger occurs
- Slash music test commands now use the same region-aware pool selection as the live music system
- Music trace recording can capture:
  - context changes
  - support source (zone vs subzone)
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
- If the TBC sound lists are reordered, the layout offsets in `BElfVoiceRestore.lua` must also be updated

## Community Configuration Notes

### Where To Add New Midnight Mute IDs

Add them to:
- `BElfVR_NewVoiceIDs` in `SoundData.lua`
- `BElfVR_NewMusicIDs` in `SoundData.lua` for music-specific mute IDs

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

Keep the current grouping/order:
- noble block first
- standard block second
- military block third

Inside each role block:
- keep vendor lines together
- keep greeting lines together

If that ordering changes, update the role layout tables in:
- `BElfVoiceRestore.lua`

### Where To Add Built-In Automatic Fixes

In `BElfVoiceRestore.lua`:

- `DEFAULT_GENDER_OVERRIDES`
  - For known NPC IDs with wrong client-reported gender
- `DEFAULT_ROLE_OVERRIDES`
  - For known NPC IDs with wrong role classification
- `DEFAULT_NAME_PROFILES`
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
- `BElfVRDB.musicTraceLog`
  - User-captured music route trace buffer stored in SavedVariables

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
- Track rotation currently uses a configurable approximate timer, because addon Lua does not get a clean "this injected FileDataID finished" callback for this playback path
- The music trace recorder is a capped ring buffer and intentionally trims old entries; it is meant for focused capture sessions, not permanent long-term logging

## Suggested Next Improvements

1. Move community-editable defaults into a separate `Config.lua`
2. Add a richer role model if needed:
   - vendor
   - questgiver
   - trainer
   - civilian
3. Add more built-in Midnight Silvermoon NPC overrides by exact `npc=...` IDs
4. Add more comments near role layout offsets if more community editing is expected
5. Consider deprecating the old `genderOverrides` / `roleOverrides` saved-variable fields entirely in a cleanup pass
6. Expand the Silvermoon music zone/subzone allow-lists from recorded trace sessions
7. Use recorded trace sessions to identify additional Midnight music FileDataIDs that still leak through and add them to `BElfVR_NewMusicIDs`

## Session Update (2026-03-05)

Low-risk cleanup pass applied in `BElfVoiceRestore.lua` after review triage:

- Removed unused `local addon = {}` declaration near the top of the file.
- Removed dead fallback-zone entry `["zul'aman"] = false` from `BLOOD_ELF_FALLBACK_ZONES`.
- Added an early `OnUpdate` short-circuit:
  - `if not IsMusicReplacementActive() then return end`
  - This avoids periodic music evaluation work while replacement music is disabled/unmuted.

Notes:
- No behavior-changing refactors were done in this pass.
- Potential larger refactors (voice pool structural enforcement, trace-buffer internals) remain optional and were intentionally deferred.
