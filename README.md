# Blood Elf Voice Restore

Version: `0.3.0-alpha`

## Disclaimer

This project has been heavily vibe-coded.

My personal coding experience is limited, and I am doing what I can to build, test, and improve it as I go.

If that is not your thing, please abstain from low-value or useless comments.

Blood Elf Voice Restore is a World of Warcraft addon for Midnight-era Silvermoon that suppresses selected new Blood Elf NPC voice lines and injects original TBC-era Blood Elf voice sets during NPC interaction events.

It now also includes a first-pass Silvermoon / Eversong music layer that mutes tracked Midnight music FileDataIDs and injects old TBC Silvermoon music on the music channel.

## What The Addon Does

- Mutes tracked Midnight Blood Elf NPC voice FileDataIDs listed in `SoundData.lua`
- Plays original TBC voice lines for supported Blood Elf NPCs
- Supports greet playback on left-click target selection
- Supports greet playback on gossip open
- Supports bye playback on gossip close
- Supports bye playback when you click away from a recently greeted target
- Supports pissed playback after repeated clicks on the same NPC
- Mutes tracked Midnight Silvermoon / Eversong music FileDataIDs listed in `SoundData.lua`
- Injects TBC Silvermoon intro/day/night music while you remain in supported Blood Elf music areas
- Uses shuffle-with-cooldown logic so the same TBC music track is strongly discouraged from repeating too soon
- Can record music routing traces into SavedVariables for later analysis
- Exposes an in-game settings and test UI via `/belvr`

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
- Supported-zone continuity for interiors and enclave slices depends on the allow-lists in `BElfVoiceRestore.lua`

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

## Main Files

- `BElfVoiceRestore.lua`
  Main logic, UI, event handling, classification, overrides, playback rules.
- `SoundData.lua`
  New Midnight mute IDs plus TBC male/female voice pools, tracked Midnight music IDs, and TBC music pools.
- `bloodElfRestore.toc`
  Addon metadata and load order.
- `DEV_NOTES.md`
  Ongoing developer handoff notes.

## Commands

- `/belvr`
  Open the UI.
- `/belvr on`
- `/belvr off`
- `/belvr mute on`
- `/belvr mute off`
- `/belvr verbose`
- `/belvr verbose on`
- `/belvr verbose off`
- `/belvr fallback on`
- `/belvr fallback off`
- `/belvr target on`
- `/belvr target off`
- `/belvr invert`
- `/belvr invert on`
- `/belvr invert off`
- `/belvr suppress`
- `/belvr suppress on`
- `/belvr suppress off`
- `/belvr force male`
- `/belvr force female`
- `/belvr force clear`
- `/belvr force-name male`
- `/belvr force-name female`
- `/belvr force-name clear`
- `/belvr role military`
- `/belvr role noble`
- `/belvr role standard`
- `/belvr role clear`
- `/belvr role-name military`
- `/belvr role-name noble`
- `/belvr role-name standard`
- `/belvr role-name clear`
- `/belvr status`
- `/belvr music on`
- `/belvr music off`
- `/belvr music mute on`
- `/belvr music mute off`
- `/belvr music verbose`
- `/belvr music verbose on`
- `/belvr music verbose off`
- `/belvr music trace on`
- `/belvr music trace off`
- `/belvr music trace clear`
- `/belvr music intro on`
- `/belvr music intro off`
- `/belvr music now`
- `/belvr music stop`
- `/belvr test music intro`
- `/belvr test music day`
- `/belvr test music night`

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
5. Test `/belvr force ...` and `/belvr force-name ...` on known problematic NPCs.
6. Test with verbose logging enabled when adding new mute IDs or overrides.
7. Test `/belvr music verbose on` while walking between Silvermoon subzones and interiors.
8. Test `/belvr music trace on`, then `/reload`, and inspect the SavedVariables trace for unexpected zone names or missing allow-list entries.
