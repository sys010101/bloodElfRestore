-- ============================================================
--  BElfRestore - Config.lua
--  User-editable policy layer
--
--  This file is loaded before `BElfRestore.lua`.
--  The goal is simple:
--  - keep raw sound/music datasets in `SoundData.lua`
--  - keep runtime logic in `BElfRestore.lua`
--  - keep safe tuning knobs, routing, exclusions, and heuristics here
--
--  Editing rules:
--  - Change one section at a time, then test in-game.
--  - Keep text keys lowercase when matching zone/subzone/name text.
--  - Do not rename top-level tables unless the runtime code was also
--    updated to read the new names.
--  - When unsure, comment out one line instead of deleting a whole block.
--
--  Region keys currently used by the music system:
--  - `silvermoon`
--  - `eversong`
--  - `sunstrider`
--  - `eversong_south`
--  - `deatholme`
--  - `amani`
--
--  Voice role values currently supported:
--  - `military`
--  - `noble`
--  - `standard`
-- ============================================================

BElfVR_Config = {
    voice = {
        -- ========================================================
        --  Voice Behavior
        --  Safe runtime timing/probability knobs for injected VO.
        -- ========================================================
        behavior = {
            -- How many rapid repeated clicks on the same target are
            -- required before the addon switches to a "pissed" line.
            pissedClickThreshold = 3,

            -- Seconds allowed between repeated clicks before the pissed
            -- counter resets.
            pissedClickWindowSeconds = 4,

            -- Maximum age of the last greet for normal bye playback.
            byeGracePeriodSeconds = 60,

            -- Minimum hold time before target-loss bye is allowed.
            -- This prevents greet + instant target-clear overlap.
            targetLossByeDelaySeconds = 1.6,

            -- Maximum age for target-loss bye after the original greet.
            -- Keep this fairly short: target-loss bye is meant to feel
            -- like a quick disengage, not a voice line from an NPC you
            -- flew away from several seconds ago.
            targetLossByeMaxAgeSeconds = 4.0,

            -- Minimum gap between injected TBC voice lines.
            minPlaybackGapSeconds = 1.25,

            -- Time window for temporary native dialog suppression.
            dialogSuppressionWindowSeconds = 0.4,

            -- Fake distance falloff probabilities for left-click greet.
            -- These are behavior-only probabilities, not real 3D volume.
            rangeTierNearChance = 0.65,
            rangeTierFarChance = 0.25,

            -- Prevents double-firing target-select greet on very fast
            -- duplicate target-change bursts.
            targetSelectDedupeWindowSeconds = 0.35,
        },

        -- ========================================================
        --  Voice Scope
        --  Keeps TBC voice replacement inside supported Quel'Thalas
        --  areas instead of letting it bleed into unrelated regions.
        -- ========================================================
        scope = {
            -- Exact lowercase zone or subzone text accepted for TBC
            -- voice replacement.
            fallbackZones = {
                "silvermoon city",
                "eversong woods",
                "sunstrider isle",
                "ghostlands",
                "sanctum of light",
                "the bazaar",
            },

            -- Normalized map/area tokens accepted for TBC voice
            -- replacement. These use alphanumeric-only normalized text
            -- from area names.
            scopeTokens = {
                "silvermooncity",
                "eversongwoods",
                "ghostlands",
                "sunstriderisle",
                "sanctumoflight",
            },

            -- Areas that must always keep Blizzard's native voices even
            -- if a parent zone or map token would otherwise qualify.
            nativeOnlyTokens = {
                "harandar",
            },
        },

        -- ========================================================
        --  Voice Classification
        --  Tokens used by tooltip/name heuristics.
        -- ========================================================
        classification = {
            -- If any tooltip line contains one of these tokens, the NPC
            -- is treated as explicitly Blood Elf.
            tooltipBloodElfRaceTokens = {
                "blood elf",
                "sin'dorei",
            },

            -- If any tooltip line contains one of these tokens, the NPC
            -- is treated as a child and should keep native audio.
            tooltipChildTokens = {
                "child",
            },

            -- Name tokens that should keep native child audio even when
            -- Blizzard hides tooltip race metadata.
            childNameTokens = {
                "child",
                "orphan",
            },

            -- Hidden-race fallback on plain target selection is limited
            -- to names that strongly suggest a Blood Elf NPC. These are
            -- normalized to lowercase alphanumeric tokens at runtime.
            hiddenRaceNameTokens = {
                "silvermoon",
                "sindorei",
                "farstrider",
                "magister",
                "spellbreaker",
                "blood knight",
            },

            -- If tooltip race text explicitly contains one of these,
            -- humanoid fallback must not pretend the NPC is Blood Elf.
            knownNonBloodElfRaceTokens = {
                "human",
                "orc",
                "dwarf",
                "night elf",
                "gnome",
                "troll",
                "tauren",
                "undead",
                "forsaken",
                "draenei",
                "worgen",
                "goblin",
                "pandaren",
                "tortollan",
                "grummle",
                "zandalari troll",
                "kul tiran",
                "dark iron dwarf",
                "mag'har orc",
                "void elf",
                "lightforged draenei",
                "nightborne",
                "highmountain tauren",
                "vulpera",
                "mechagnome",
                "dracthyr",
                "earthen",
            },
        },

        -- ========================================================
        --  Voice Role Heuristics
        --  Name fragments used when no exact override/profile exists.
        -- ========================================================
        roleHeuristics = {
            militaryNameTokens = {
                "guard",
                "ranger",
                "captain",
                "blood knight",
                "champion",
            },

            nobleNameTokens = {
                "lord",
                "lady",
                "noble",
            },
        },

        -- ========================================================
        --  Built-In Overrides
        --  Exact NPC-ID metadata fixes. Keys may be string or number.
        -- ========================================================
        overrides = {
            genderByNPCID = {
                -- ["123456"] = "female",
            },

            roleByNPCID = {
                -- ["123456"] = "military",
            },
        },

        -- ========================================================
        --  Built-In Name Profiles
        --  Used for repeated names that hide useful metadata.
        --
        --  Supported fields:
        --  - `role = "military" | "noble" | "standard"`
        --  - `vendor = true`
        --  - `exclude = true`
        --
        --  Example:
        --  ["example vendor"] = {
        --      role = "standard",
        --      vendor = true,
        --  }
        -- ========================================================
        profiles = {
            byName = {
                ["lyrendal"] = {
                    role = "standard",
                    vendor = true,
                },
                ["mahra treebender"] = {
                    exclude = true,
                },
                ["silvermoon resident"] = {
                    role = "standard",
                },
                ["doomsayer"] = {
                    role = "standard",
                },
                ["household attendant"] = {
                    role = "standard",
                },

                -- Player mount service vendors should never inherit the
                -- Blood Elf fallback classifier.
                ["cousin slowhands"] = {
                    exclude = true,
                },
                ["mystic birdhat"] = {
                    exclude = true,
                },
                ["collector unta"] = {
                    exclude = true,
                },
                ["merchant maku"] = {
                    exclude = true,
                },
                ["killia"] = {
                    exclude = true,
                },
                ["melanie morten"] = {
                    exclude = true,
                },

                -- Children currently keep native Midnight child audio
                -- because the addon does not ship a dedicated TBC child
                -- voice pool.
                ["sin'dorei child"] = {
                    exclude = true,
                },
                ["sin'dorei children"] = {
                    exclude = true,
                },
                ["sindorei child"] = {
                    exclude = true,
                },
                ["blood elf child"] = {
                    exclude = true,
                },
                ["silvermoon child"] = {
                    exclude = true,
                },
                ["sin'dorei orphan"] = {
                    exclude = true,
                },
            },
        },
    },

    music = {
        -- ========================================================
        --  Music Timing
        --  Safe runtime timing knobs for injected music playback.
        -- ========================================================
        timing = {
            updateIntervalSeconds = 1.0,
            trackRotateSeconds = 85,
            repeatCooldownSeconds = 180,
            transitionFadeMS = 900,
            endGraceSeconds = 0.5,
        },

        -- ========================================================
        --  Music Playback
        --  Lower-level playback control knobs.
        -- ========================================================
        playback = {
            forceStopNativeBeforeReplacement = true,
            nativeGuardIntervalSeconds = 0.25,

            -- WoW sound channel used for injected TBC music.
            -- `Master` keeps injected replacement music audible while
            -- the addon hard-suppresses Blizzard's native music channel.
            playbackChannel = "Master",

            -- Keep this enabled while replacement music uses a non-Music
            -- channel so native Midnight music cannot bleed underneath.
            suppressNativeWithVolume = true,
            nativeSuppressVolume = 0,

            -- Regions where ambient-channel suppression is allowed as a
            -- last-resort overlap guard.
            regionsWithAmbienceSuppression = {
                "deatholme",
            },

            -- Startup purge delay used to flush lingering pre-reload
            -- injected music before the new Lua instance resumes.
            startupPurgeDelaySeconds = 0.35,
        },

        -- ========================================================
        --  Music Day/Night Split
        -- ========================================================
        dayNightHours = {
            dayStartHour = 6,
            nightStartHour = 18,
        },

        -- ========================================================
        --  Music Scope
        --  Determines where the addon is even allowed to own music.
        -- ========================================================
        scope = {
            supportedZones = {
                "silvermoon city",
                "eversong woods",
                "sanctum of light",
            },

            supportedSubZones = {
                "the bazaar",
            },

            -- Areas that must always stay native even if the parent zone
            -- looks supported.
            nativeOnlyTokens = {
                "harandar",
            },

            -- Normalized map/area tokens that mark Midnight Quel'Thalas.
            scopeTokens = {
                "quelthalas",
                "silvermooncity",
                "eversongwoods",
                "ghostlands",
                "sunstriderisle",
                "sanctumoflight",
            },
        },

        -- ========================================================
        --  Music Routing
        --  Maps specific subzones into broader TBC region families.
        -- ========================================================
        routing = {
            -- Broad zone text -> region key.
            byZone = {
                ["silvermoon city"] = "silvermoon",
                ["sanctum of light"] = "silvermoon",
                ["eversong woods"] = "eversong",
            },

            -- Exact lowercase subzone text -> region key.
            bySubZone = {
                ["amani pass"] = "amani",
                ["daggerspine landing"] = "eversong_south",
                ["daggerspine point"] = "eversong_south",
                ["farstrider enclave"] = "eversong_south",
                ["goldenmist village"] = "eversong_south",
                ["ruins of deatholme"] = "deatholme",
                ["tranquillien"] = "eversong_south",
                ["sanctum of the moon"] = "eversong_south",
                ["sunstrider isle"] = "sunstrider",
                ["suncrown village"] = "eversong_south",
                ["thalassian pass"] = "eversong_south",
                ["thalassian range"] = "eversong_south",
                ["windrunner spire"] = "eversong_south",
                ["windrunner village"] = "eversong_south",
                ["zeb'nowa"] = "amani",
                ["zeb'tela ruins"] = "amani",
            },

            -- Narrow token fallback when exact subzone names drift.
            bySubZoneToken = {
                ["deatholme"] = "deatholme",
            },

            -- Normalized subzone tokens -> region key.
            -- These are matched after punctuation/spacing normalization.
            byNormalizedSubZoneToken = {
                ["amani"] = "amani",
                ["zeb"] = "amani",
            },

            -- If a supported subzone is known-good but does not define an
            -- explicit region, it falls back here.
            defaultSupportedSubZoneRegion = "silvermoon",
        },

        -- ========================================================
        --  Intro Cooldown Rules
        --
        --  Matching rules:
        --  - `defaultSeconds` always applies
        --  - more specific buckets layer on top
        --  - if ANY matching bucket is still on cooldown, the intro is
        --    skipped and the addon falls back to normal day/night music
        --
        --  Most precise user-facing location key currently available:
        --  - `zone||subzone`
        --
        --  Example keys:
        --  - `byRegion.silvermoon = 1800`
        --  - `byZone["silvermoon city"] = 1800`
        --  - `bySubZone["the bazaar"] = 2400`
        --  - `byArea["silvermoon city||the bazaar"] = 2400`
        --  - `byPool["silvermoon:intro"] = 1800`
        --  - `byTrackID[53473] = 1800`
        -- ========================================================
        introCooldowns = {
            defaultSeconds = 600,

            byRegion = {
                -- ["eversong"] = 1200,
            },

            byZone = {
                -- ["silvermoon city"] = 1800,
            },

            bySubZone = {
                -- ["the bazaar"] = 2400,
            },

            byArea = {
                -- ["silvermoon city||the bazaar"] = 2400,
            },

            -- Runtime pool key format: `region:pool`
            byPool = {
                ["silvermoon:intro"] = 1800,
            },

            byTrackID = {
                -- [53515] = 900,
            },
        },

        -- ========================================================
        --  Music Debug / Trace
        -- ========================================================
        debug = {
            traceMaxEntries = 1200,
        },
    },

    ui = {
        -- ========================================================
        --  UI Art
        -- ========================================================
        art = {
            texturePath = "Interface\\AddOns\\bloodElfRestore\\assets\\tbc_art",
            fallbackTexturePath = "Interface\\AddOns\\bloodElfRestore\\assets\\tbc_art.jpg",
            aspectRatio = 16 / 10,
            alpha = 0.10,

            -- 0.0 = contain, 1.0 = cover
            fitBlend = 1.0,
            scaleX = 1.0,
            scaleY = 1.0,

            margins = {
                left = 12,
                right = 12,
                top = 50,
                bottom = 12,
            },
        },

        -- ========================================================
        --  UI Layout
        -- ========================================================
        layout = {
            windowWidth = 550,
            windowHeight = 750,
            contentWidth = 446,
            tabButtonWidth = 92,
            tabButtonHeight = 22,
            tabButtonGap = 6,
        },
    },
}
