# Blood Elf Restore

Version: `0.4.0-alpha`

## Disclaimer

This project has been heavily vibe-coded.

My personal coding experience is limited, and I am doing what I can to build, test, and improve it as I go.

This addon is still in a very early stage of development. It is not really intended yet as a polished daily-use addon, and it still needs more logic work, design refinement, testing, and general cleanup before it can be considered stable.

If that is not your thing, please abstain from low-value or useless comments.

Blood Elf Restore is a World of Warcraft addon for Midnight-era Silvermoon that suppresses selected new Blood Elf NPC voice lines and injects original TBC-era Blood Elf voice sets during NPC interaction events.

It now also includes a broader first-pass Quel'Thalas music layer that mutes tracked Midnight music FileDataIDs and injects old TBC regional music on the music channel.

## What The Addon Does

- Mutes tracked Midnight Blood Elf NPC voice FileDataIDs listed in `SoundData.lua`
- Plays original TBC voice lines for supported Blood Elf NPCs
- Supports greet playback on left-click target selection
- Supports greet playback on gossip open
- Supports bye playback on gossip close
- Supports bye playback when you click away from a recently greeted target
- Supports pissed playback after repeated clicks on the same NPC
- Mutes tracked Midnight Silvermoon / Eversong music FileDataIDs listed in `SoundData.lua`
- Injects region-aware TBC intro/day/night music while you remain in supported Blood Elf music areas
- Uses shuffle-with-cooldown logic so the same TBC music track is strongly discouraged from repeating too soon
- Can record music routing traces into SavedVariables for later analysis
- Exposes an in-game settings and test UI via `/belr`

## What Currently Works

- Addon loads correctly as `bloodElfRestore`
- Midnight Blood Elf voice muting can be enabled, disabled, and re-applied
- Left-click greet playback works on recognized nearby targets
- Right-click gossip greet playback works
- Gossip close bye playback works
- Target-loss bye playback works after a short post-greet delay
- Male and female TBC voice selection works with the current default reversed `UnitSex` mapping
- GUID-based and name-based manual overrides work
- Role-based voice pools work for `noble`, `standard`, and `military`
- Test playback buttons cover male and female voice sets for all three roles
- Rapid retargeting overlap is reduced by stop-handle logic, playback throttling, and target-loss delay rules
- Far-distance left-click targeting uses fake distance falloff buckets instead of always playing
- If WoW sound output is disabled (including the usual sound-effects toggle such as `Ctrl+S`), the addon does not inject replacement voices
- Verbose logging now includes the NPC name in key trigger lines to make troubleshooting easier
- First-pass music replacement works in supported Silvermoon / Eversong areas
- Music logic currently recognizes:
  - `Silvermoon City`
  - `Eversong Woods`
  - `Sanctum of Light`
  - selected supported subzones such as `The Bazaar`
- Region routing now distinguishes:
  - `silvermoon`
  - `eversong`
  - `sunstrider`
  - `eversong_south`
  - `deatholme`
- The settings UI is now split into separate `Voice` and `Music` tabs
- Music can optionally play an intro cue on fresh entry, then rotate through day or night pools
- Music trace recording can be enabled, walked through the city, and saved via `/reload` or logout for later tuning

## What Does Not Work Perfectly

- True 3D positional audio is not possible with this addon approach
- Per-yard volume falloff is not possible for injected `PlaySoundFile()` playback
- Fake distance falloff is behavioral only: sounds play less often at range, but not quieter
- Some Midnight NPCs still require manual overrides because Blizzard hides or misreports metadata
- Some NPCs still need explicit built-in profile exceptions (for example vendor-only or excluded non-Blood Elf false positives)
- The hidden-race humanoid fallback is intentionally constrained to Blood Elf zones so unrelated humanoids elsewhere do not get Blood Elf VO
- Mute coverage depends entirely on the FileDataIDs listed in `SoundData.lua`
- If Blizzard adds or swaps new Blood Elf VO assets, more mute IDs may be needed
- Music replacement is an addon-side approximation, not a true engine-level override of Blizzard's internal zone music resolver
- The addon cannot reliably read the exact native Midnight music FileDataID currently playing
- Music transitions are smoother than a hard stop, but they are still limited by what `PlaySoundFile()` and `StopSound()` allow on the addon side
- Supported-zone continuity for interiors and enclave slices depends on the allow-lists in `BElfRestore.lua`

## Core Design

The addon is built around two layers:

1. Suppression
   It calls `MuteSoundFile()` for known Midnight Blood Elf voice FileDataIDs.

2. Replacement
   It listens for target and gossip events, classifies the target as a Blood Elf NPC, resolves a role and voice sex, then plays a matching TBC FileDataID.

Because WoW does not let the addon attach those injected sounds to the NPC in 3D space, the addon uses approximation logic:

- fake distance falloff by distance buckets
- short playback throttling
- target-loss bye delay
- brief dialog-channel suppression around injected playback

The music system uses a similar approximation model:

1. Mute known Midnight music FileDataIDs with `MuteSoundFile()`.
2. Watch zone, subzone, resting, and day/night changes.
3. Choose an intro/day/night TBC music track.
4. Avoid immediate repeats with a per-track cooldown.
5. Stop and restart the injected music with a short fade when the context changes.

In `0.4.0-alpha`, the music layer also:

- uses region-specific pools for broader Eversong, Sunstrider Isle, southern Eversong remastered areas, and a dedicated Deatholme pocket
- avoids replaying intro cues too often with a separate intro cooldown
- lets known tracks finish naturally instead of cutting them off with the old coarse timer
- keeps `/belr music stop` idle until a real resume trigger occurs

## Main Files

- `BElfRestore.lua`
  Main logic, UI, event handling, classification, overrides, playback rules.
- `SoundData.lua`
  New Midnight mute IDs plus TBC male/female voice pools, tracked Midnight music IDs, and TBC music pools.
- `bloodElfRestore.toc`
  Addon metadata and load order.
- `DEV_NOTES.md`
  Ongoing developer handoff notes.

## Commands

- `/belr`
  Open the UI.
- Legacy alias:
  - `/belvr` runs the same command set for backward compatibility.

General addon power:
- `/belr on`
  Turns the addon on.
- `/belr off`
  Turns the addon off and stops its replacement behavior.
- `/belr status`
  Prints the addon's current settings and loaded counts in chat.

Voice muting and voice debug:
- `/belr mute on`
  Turns on muting for the tracked new Midnight Blood Elf voice lines.
- `/belr mute off`
  Restores the tracked new Midnight Blood Elf voice lines.
- `/belr verbose`
  Toggles detailed voice debug messages in chat.
- `/belr verbose on`
  Forces detailed voice debug messages on.
- `/belr verbose off`
  Forces detailed voice debug messages off.

Voice detection and behavior:
- `/belr fallback on`
  Allows the addon to use its backup humanoid check when Blizzard hides NPC race data.
- `/belr fallback off`
  Disables that backup humanoid check.
- `/belr target on`
  Plays a greet when you left-click and target a supported NPC.
- `/belr target off`
  Disables left-click target greet playback.
- `/belr invert`
  Toggles the male/female voice swap used when Blizzard reports NPC sex backwards.
- `/belr invert on`
  Forces the male/female voice swap on.
- `/belr invert off`
  Forces the male/female voice swap off.
- `/belr suppress`
  Toggles temporary native dialog suppression during injected voice playback.
- `/belr suppress on`
  Forces native dialog suppression on.
- `/belr suppress off`
  Forces native dialog suppression off.

Manual voice fixes for the NPC you are targeting:
- `/belr force male`
  Forces the current target to use male voice playback.
- `/belr force female`
  Forces the current target to use female voice playback.
- `/belr force clear`
  Clears the exact-target gender override.
- `/belr role military`
  Forces the current target into the military voice pool.
- `/belr role noble`
  Forces the current target into the noble voice pool.
- `/belr role standard`
  Forces the current target into the standard voice pool.
- `/belr role clear`
  Clears the exact-target role override.

Manual voice fixes for every NPC with the same visible name:
- `/belr force-name male`
  Forces all NPCs with the current target's name to use male voice playback.
- `/belr force-name female`
  Forces all NPCs with the current target's name to use female voice playback.
- `/belr force-name clear`
  Clears the name-wide gender override.
- `/belr role-name military`
  Forces all NPCs with the current target's name into the military voice pool.
- `/belr role-name noble`
  Forces all NPCs with the current target's name into the noble voice pool.
- `/belr role-name standard`
  Forces all NPCs with the current target's name into the standard voice pool.
- `/belr role-name clear`
  Clears the name-wide role override.

Music controls:
- `/belr music on`
  Turns the music replacement system on.
- `/belr music off`
  Turns the music replacement system off.
- `/belr music mute on`
  Mutes the tracked Midnight music IDs used by the music replacement layer.
- `/belr music mute off`
  Restores the tracked Midnight music IDs.
- `/belr music verbose`
  Toggles detailed music routing messages in chat.
- `/belr music verbose on`
  Forces detailed music routing messages on.
- `/belr music verbose off`
  Forces detailed music routing messages off.
- `/belr music intro on`
  Makes the addon play the intro music cue when entering the supported music region.
- `/belr music intro off`
  Disables that intro-on-entry cue.
- `/belr music now`
  Forces the addon to re-check your current area and refresh music logic immediately.
- `/belr music stop`
  Stops the currently injected addon music and clears the music state.

Music trace recording:
- `/belr music trace on`
  Starts recording music routing and playback lines into SavedVariables for later review.
- `/belr music trace off`
  Stops recording the music trace.
- `/belr music trace clear`
  Clears the saved music trace buffer.
- `/belr music note <text>`
  Adds a manual trace marker line with your note plus current zone/subzone/region context.

Music test playback:
- `/belr test music intro`
  Plays the configured intro music track for testing.
- `/belr test music day`
  Plays one of the configured daytime music tracks for testing.
- `/belr test music night`
  Plays one of the configured nighttime music tracks for testing.

## UI Controls

- Hovering a checkbox shows a plain-English explanation of what it does.
- Enable addon logic
- Mute new Midnight Blood Elf voice files
- Verbose chat debug
- Fallback humanoid classifier
- Left-click greet toggle
- Invert NPC sex mapping toggle
- Suppress native dialog during injected playback toggle
- Enable replacement music logic
- Mute tracked Midnight Silvermoon music files
- Verbose music debug
- Record music trace to SavedVariables
- Play intro cue on fresh entry
- Music status block
- Test buttons for intro/day/night music
- Re-apply music mutes
- Clear music trace
- Restore Midnight music
- Force music refresh
- Test playback buttons for male/female `noble`, `standard`, and `military`
- Re-apply mutes
- Restore Midnight VO

`Re-apply Mutes` also re-enables the mute option if it was previously turned off.

## Known Issues

- `Sound_EnableDialog` is briefly toggled during injected playback. This is intentional as a workaround, but it is a global client setting and not a per-NPC audio control.
- Native dialog suppression is now optional and can be disabled for compatibility testing.
- `Suppress` is the main fallback for stubborn NPCs that still leak a native Midnight line alongside the addon's replacement voice.
- `UnitSex` appears inverted for current Midnight Blood Elf NPCs, so the addon treats it as reversed by default.
- Role classification still uses name heuristics for many NPCs.
- The role-pool slicing logic depends on the exact list order in `SoundData.lua`.
- Legacy `genderOverrides` and `roleOverrides` are migrated once into a backup field, then reset in favor of GUID-based overrides.
- To reduce stubborn double-music leaks from unknown Midnight IDs, replacement playback now calls `StopMusic()` first; this can make some transitions feel more abrupt.
- The music trace recorder does not create a standalone text file. It writes into SavedVariables, which WoW flushes to disk on `/reload` or logout.
- Large trace captures should be done in a single pass and then cleared; the recorder keeps a capped ring buffer, not an infinite log.

## License

This project is released under the MIT License. See [LICENSE](C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\bloodElfRestore\LICENSE) for the full text.

## Future Work

1. Move editable defaults and heuristics into a separate `Config.lua`.
2. Expand mute coverage for additional Midnight Blood Elf VO assets.
3. Add more exact built-in overrides for known problematic NPCs.
4. Add optional UI controls for tuning fake distance falloff probabilities.
5. Add a richer role model if more granular voice pools are needed.
6. Expand the Silvermoon subzone allow-list based on trace recordings.
7. Replace placeholder TOC metadata such as author information with final release metadata.

## Recommended Testing Pass

1. Test left-click greet on nearby, mid-range, and far-range targets.
2. Test right-click greet and gossip close bye.
3. Test target-loss bye after a short delay.
4. Test male and female NPCs after `/reload`.
5. Test `/belr force ...` and `/belr force-name ...` on known problematic NPCs.
6. Test with verbose logging enabled when adding new mute IDs or overrides.
7. Test `/belr music verbose on` while walking between Silvermoon subzones and interiors.
8. Test `/belr music trace on`, run southern Eversong routes, then `/reload`, and inspect the SavedVariables trace for unexpected zone names or missing allow-list entries.
9. During fast flying passes, use `/belr music note <text>` at the exact moment you hear a leak so the trace has a searchable marker.

