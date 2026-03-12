# Blood Elf Restore

Version: `0.6.4-alpha`

## Disclaimer

This project has been heavily vibe-coded.

My personal coding experience is limited, and I am doing what I can to build, test, and improve it as I go.

This addon is still in a very early stage of development. It is not really intended yet as a polished daily-use addon, and it still needs more logic work, design refinement, testing, and general cleanup before it can be considered stable.

If that is not your thing, please abstain from low-value or useless comments.

Blood Elf Restore is a World of Warcraft addon for Midnight-era Quel'Thalas that suppresses selected new Blood Elf NPC voice lines and injects original TBC-era Blood Elf voice sets during NPC interaction events.

It also includes a scoped Midnight Quel'Thalas music layer that mutes tracked supported-zone music FileDataIDs and injects old TBC regional music on `Master` while temporarily forcing native `Sound_MusicVolume=0` in supported zones.

## What The Addon Does

- Mutes tracked Midnight Blood Elf NPC voice FileDataIDs listed in `SoundData.lua`
- Plays original TBC voice lines for supported Blood Elf NPCs
- Supports greet playback on left-click target selection
- Supports greet playback on gossip open
- Supports bye playback on gossip close
- Supports bye playback when you click away from a recently greeted target
- Supports pissed playback after repeated clicks on the same NPC
- Mutes tracked supported-zone music FileDataIDs listed in `SoundData.lua`
- Injects region-aware TBC intro/day/night music while you remain in supported Midnight Quel'Thalas music areas
- Uses shuffle-with-cooldown logic so the same TBC music track is strongly discouraged from repeating too soon
- Can record music routing traces into SavedVariables for later analysis
- Exposes an in-game settings and test UI via `/belr`

## What Currently Works

- Addon loads correctly as `bloodElfRestore`
- Midnight Blood Elf voice muting can be enabled, disabled, and re-applied
- Left-click greet playback works on recognized nearby targets
- Hidden-race target-select fallback now works only for positive Blood Elf name/profile hints, so generic humanoids no longer get guessed into TBC VO
- Right-click gossip greet playback works
- Gossip close bye playback works
- Target-loss bye playback works after a short post-greet delay and is skipped if the disengage happens too late to sound believable
- Male and female TBC voice selection works with the current default reversed `UnitSex` mapping
- GUID-based and name-based manual overrides work
- Role-based voice pools work for `noble`, `standard`, and `military`
- Test playback buttons cover male and female voice sets for all three roles
- Rapid retargeting overlap is reduced by stop-handle logic, playback throttling, and target-loss bye delay/max-age rules
- Far-distance left-click targeting uses fake distance falloff buckets instead of always playing
- If WoW sound output is disabled (including the usual sound-effects toggle such as `Ctrl+S`), the addon does not inject replacement voices
- Verbose logging now includes the NPC name in key trigger lines to make troubleshooting easier
- Voice replacement is now scoped to supported Quel'Thalas areas, with native-only exclusions such as `Harandar`
- Music replacement is now scoped to Midnight Quel'Thalas map lineage instead of broad zone text alone
- Music logic currently recognizes:
  - `Silvermoon City`
  - `Eversong Woods`
  - `Sanctum of Light`
  - selected supported subzones such as `The Bazaar`, `Sunstrider Isle`, `Tranquillien`, `Sanctum of the Moon`, and `Wayfarer's Rest`
- Native-only guards keep unsupported or intentionally excluded areas on Blizzard music:
  - `Harandar`
  - unrelated Midnight zones outside Quel'Thalas scope
  - non-Midnight world zones
- Region routing now distinguishes:
  - `silvermoon`
  - `silvermoon_interior`
  - `eversong`
  - `sunstrider`
  - `eversong_south`
  - `deatholme`
  - `amani`
- `Ruins of Deatholme` now routes to the dedicated `deatholme` pool again, including a token fallback for small subzone naming shifts
- Amani-style troll subzones now route to dedicated troll music logic:
  - explicit overrides for `Amani Pass`, `Zeb'Nowa`, and `Zeb'tela Ruins`
  - name-pattern fallback for subzones containing `amani` or `zeb'`
- Midnight music muting is now applied only while you are actually in a supported music region; it is no longer globally applied on login
- Supported interiors can now mute both Midnight `mus_120_*` music and Blizzard generic tavern / inn zonemusic to prevent overlap in supported interior subzones
- Silvermoon City interiors detected via `IsIndoors()` or explicit subzone overrides such as `Wayfarer's Rest` now route to a dedicated `silvermoon_interior` pool with calm scenic music instead of the outdoor day/night cycle
- The generated Midnight catalog is loaded at runtime and currently provides the main music mute coverage, with Harandar families intentionally excluded
- Replacement music now uses `Master` while supported replacement ownership temporarily forces native `Sound_MusicVolume=0`, which is the current reliable fix for Silvermoon load-screen overlap
- Moving between supported music regions now forces an immediate TBC music handoff instead of waiting for the old injected region track to finish naturally
- Temporary CVar backups for music volume, ambience, and dialog are restored on area exit, `/reload`, and logout
- Ctrl+M and global sound-toggle changes now trigger immediate music re-evaluation (`CVAR_UPDATE`) without waiting for periodic ticks
- Non-NPC gossip objects with protected or nonstandard GUID values now fail closed instead of crashing the addon while it tries to inspect or log them
- The settings UI is now split into separate `Voice` and `Music` tabs
- Music-tab action buttons now anchor below the live status block so longer status text does not overlap the controls
- Music can optionally play an intro cue on fresh entry, then rotate through day or night pools
- Intro cooldown history is now persisted in SavedVariables, so `/reload` does not count as a fresh intro reset
- Intro cooldown policy is now user-editable in `Config.lua` by region, zone, subzone, area (`zone||subzone`), pool, and exact FileDataID
- Music trace recording can be enabled, walked through the city, and saved via `/reload` or logout for later tuning
- `/belr status` now reports music region, scope source, override source, catalog counts, and supplemental mute counts

## What Does Not Work Perfectly

- True 3D positional audio is not possible with this addon approach
- Per-yard volume falloff is not possible for injected `PlaySoundFile()` playback
- Fake distance falloff is behavioral only: sounds play less often at range, but not quieter
- Some Midnight NPCs still require manual overrides because Blizzard hides or misreports metadata
- Some NPCs still need explicit built-in profile exceptions (for example vendor-only or excluded non-Blood Elf false positives)
- Hidden-race target-select fallback before gossip is intentionally conservative: it only accepts supported-area NPCs with positive Blood Elf name/profile hints
- Mute coverage depends on the generated Midnight catalog plus the manual and supplemental FileDataIDs listed in `SoundData.lua`
- If Blizzard adds or swaps new Blood Elf VO assets, more mute IDs may be needed
- Music replacement is an addon-side approximation, not a true engine-level override of Blizzard's internal zone music resolver
- The addon cannot reliably read the exact native Midnight music FileDataID currently playing
- Music transitions are smoother than a hard stop, but they are still limited by what `PlaySoundFile()` and `StopSound()` allow on the addon side
- Music muting now depends on a generated Midnight catalog plus manually maintained supplemental IDs in `SoundData.lua`; anonymous `mus_1200_*` IDs or non-listfile SoundKit playback can still require manual follow-up
- Supported-zone continuity for interiors and enclave slices depends on the scope tokens, native-only tokens, and subzone overrides in `Config.lua`

## Core Design

The addon is built around two layers:

1. Suppression
   It calls `MuteSoundFile()` for known Midnight Blood Elf voice FileDataIDs.

2. Replacement
   It listens for target and gossip events, classifies the target as a Blood Elf NPC, resolves a role and voice sex, then plays a matching TBC FileDataID.

Because WoW does not let the addon attach those injected sounds to the NPC in 3D space, the addon uses approximation logic:

- fake distance falloff by distance buckets
- short playback throttling
- target-loss bye delay plus a short maximum believable disengage window
- brief dialog-channel suppression around injected playback

The music system uses a similar approximation model:

1. Build a tracked supported-zone mute set from generated Midnight `mus_120_*` families, manual non-catalog `mus_1200_*` seeds, and supplemental Blizzard zonemusic families used inside supported interiors.
2. Resolve whether the current area is actually inside Midnight Quel'Thalas using zone text, subzone text, and parent map lineage.
3. Keep native-only exclusions such as `Harandar` on Blizzard music even if the parent zone would otherwise qualify.
4. Watch zone, subzone, resting, and day/night changes.
5. Choose an intro/day/night TBC music track.
6. Avoid immediate repeats with a per-track cooldown.
7. Stop, fade, and re-evaluate the injected music when the context changes, including immediate supported-region handoff when the active injected track no longer matches the player's current region.
8. Restore any temporary audio-setting backups when the addon leaves music control or the client reloads.

The current music layer also:

- uses region-specific pools for broader Eversong, Sunstrider Isle, southern Eversong remastered areas, a dedicated Deatholme pocket, Amani routing, and a Silvermoon interior pool
- detects Silvermoon City interiors via `IsIndoors()` and routes them to calm scenic music instead of the outdoor day/night cycle
- loads a generated Midnight music catalog from wowdev/wow-listfile release `202603061837`
- excludes Harandar music families from addon muting so Harandar stays native
- supplements the Midnight catalog with Blizzard generic tavern / inn / rest-area zonemusic for supported interiors
- avoids replaying intro cues too often with a separate intro cooldown
- persists intro cooldown history across `/reload` and logout-safe SavedVariables flushes
- reads intro cooldown rules from `Config.lua` instead of one hardcoded runtime constant
- lets known tracks finish naturally instead of cutting them off with the old coarse timer
- keeps `/belr music stop` idle until a real resume trigger occurs
- temporarily forces native `Sound_MusicVolume=0` only while supported replacement music is active, then restores the previous value on exit, `/reload`, and logout

## Installation

Clone or download this repository into your WoW addons directory so the folder is named `bloodElfRestore`:

```
World of Warcraft\_retail_\Interface\AddOns\bloodElfRestore\
```

The folder name must match the TOC filename exactly or WoW will not load the addon.

## Addon Structure

```
bloodElfRestore/
├── bloodElfRestore.toc          Addon metadata and load order
├── Config.lua                   User-editable policy layer
├── Midnight_ID_catalog.lua      Generated Midnight music catalog (runtime)
├── SoundData.lua                Mute IDs, TBC voice/music pools
├── BElfRestore.lua              Main logic, UI, event handling
├── LICENSE                      MIT License
├── README.md                    This file
├── CHANGELOG.md                 Version history
├── DEV_NOTES.md                 Developer handoff notes
├── Midnight_ID_Index.md         Human-readable Midnight music index
├── TBC_ID_INDEX.md              Human-readable TBC zone-music index
├── TBC_ID_CATALOG.lua           TBC zone-music ID catalog (reference)
├── assets/
│   └── tbc_art.jpg              Optional UI background art
└── tools/
    ├── generate_midnight_catalog.ps1
    └── generate_tbc_catalog.ps1
```

Files are loaded by WoW in the order specified in `bloodElfRestore.toc`:
`Config.lua` → `Midnight_ID_catalog.lua` → `SoundData.lua` → `BElfRestore.lua`

## Main Files

- `Config.lua`
  User-editable policy layer for safe voice behavior, voice classification/scope rules, built-in name/ID overrides, music routing/scope/timing, intro cooldown rules, trace limits, and UI art/layout tuning.
- `BElfRestore.lua`
  Main logic, UI, event handling, classification, overrides, playback rules.
- `SoundData.lua`
  New Midnight mute IDs plus TBC male/female voice pools, manual Midnight music seed IDs, supplemental supported-zone music mute IDs, and TBC music pools.
- `Midnight_ID_catalog.lua`
  Machine-readable Midnight `mus_120_*` music catalog generated from wowdev/wow-listfile and loaded at runtime before `SoundData.lua`.
- `Midnight_ID_Index.md`
  Human-readable Midnight music family index generated from wowdev/wow-listfile, with notes about runtime exclusions and supplemental mutes.
- `TBC_ID_CATALOG.lua`
  Data-first TBC zone-music ID catalog (Quel'Thalas focus + Outland + key TBC instances) for future config authoring.
- `TBC_ID_INDEX.md`
  Human-readable summary/counts and full Quel'Thalas ID listing generated from wow-listfile.
- `assets/tbc_art.jpg`
  Optional UI background art used by the settings panel.
- `bloodElfRestore.toc`
  Addon metadata and load order.
- `DEV_NOTES.md`
  Ongoing developer handoff notes.

Catalog regeneration:
- `tools/generate_midnight_catalog.ps1 -ListfilePath <path-to-community-listfile.csv> -ReleaseTag <tag>`
- `tools/generate_tbc_catalog.ps1 -ListfilePath <path-to-community-listfile-withcapitals.csv> -ReleaseTag <tag>`

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
  Prints the addon's current settings, loaded counts, intro cooldown summary, and current music zone / subzone / region context in chat.

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
  Mutes the tracked supported-zone music IDs used by the music replacement layer.
- `/belr music mute off`
  Restores the tracked supported-zone music IDs.
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

Voice test playback:
- `/belr test male greet`
  Plays a random male greet line.
- `/belr test male bye`
  Plays a random male bye line.
- `/belr test male pissed`
  Plays a random male pissed line.
- `/belr test female greet`
  Plays a random female greet line.
- `/belr test female bye`
  Plays a random female bye line.
- `/belr test female pissed`
  Plays a random female pissed line.

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
- Mute tracked supported-zone music files
- Verbose music debug
- Record music trace to SavedVariables
- Play intro cue on fresh entry
- Music status block with region and ID counts
- Test buttons for intro/day/night music
- Re-apply music mutes
- Clear music trace
- Restore Midnight music
- Force music refresh
- Test playback buttons for male/female `noble`, `standard`, and `military`
- Re-apply mutes
- Restore Midnight VO

`Re-apply Mutes` also re-enables the mute option if it was previously turned off.

## Current Limitations

New bugs and regressions should be tracked in the repo issue tracker rather than maintained here as a running checklist.

- `Sound_EnableDialog` is briefly toggled during injected playback. This is intentional as a workaround, but it is a global client setting and not a per-NPC audio control.
- `UnitSex` appears inverted for current Midnight Blood Elf NPCs, so the addon treats it as reversed by default.
- Role classification still uses name heuristics for many NPCs.
- The role-pool slicing logic depends on the exact list order in `SoundData.lua`.
- Music replacement currently uses `Master` while native `Sound_MusicVolume` is forced to `0` in supported areas, so WoW's music slider does not directly control the injected track during replacement playback.
- The generated Midnight catalog covers `mus_120_*` families, but manual follow-up may still be needed for anonymous `mus_1200_*` IDs or non-listfile SoundKit playback.
- The music trace recorder does not create a standalone text file. It writes into SavedVariables, which WoW flushes to disk on `/reload` or logout.
- Large trace captures should be done in a single pass and then cleared; the recorder keeps a capped ring buffer, not an infinite log.
- `Config.lua` is a live code file, not a UI form. Keep its text keys lowercase and change one rule at a time.

## License

This project is released under the MIT License. See [LICENSE](LICENSE) for the full text.

## Future Work

1. Move additional tightly-coupled data-layout knobs into `Config.lua` only where doing so does not make the runtime easier to break.
2. Expand mute coverage for additional Midnight Blood Elf VO assets.
3. Add more exact built-in overrides for known problematic NPCs.
4. Add optional UI controls for tuning fake distance falloff probabilities.
5. Add a richer role model if more granular voice pools are needed.
6. Expand the Midnight Quel'Thalas scope and subzone allow-lists based on trace recordings.
7. Capture additional anonymous `mus_1200_*` or non-listfile native music leaks if Blizzard introduces them.
8. Replace placeholder TOC metadata such as author information with final release metadata.

## Exploratory Testing

This addon benefits more from free exploratory testing than from a rigid scripted pass.

1. Use it normally across supported and unsupported areas, including reloads, relogs, flight paths, fast movement, and abrupt target swaps.
2. Try destructive or awkward interaction patterns on purpose: rapid left-click retargeting, repeated gossip open and close, moving out of range mid-line, and toggling settings while audio is active.
3. If something sounds wrong, file it in the repo issue tracker with the NPC name, zone or subzone, what you expected, what actually happened, and any useful `/belr verbose` or `/belr music trace` output.
4. Use the in-game debug commands when needed, but as investigation tools, not as a required checklist for every tester.

