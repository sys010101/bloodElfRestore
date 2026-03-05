-- ============================================================
--  BElfVoiceRestore - BElfVoiceRestore.lua
--  Main addon logic
--
--  What this addon does:
--    1. Mutes new Midnight Blood Elf NPC voice lines
--    2. Plays original TBC-era voices during Blood Elf NPC interactions
--       - GOSSIP_SHOW -> random greet line
--       - GOSSIP_CLOSED -> random bye line
--       - Repeated clicks on same NPC -> random pissed line
-- ============================================================

local ADDON_NAME = "bloodElfRestore"
local DB_SCHEMA_VERSION = 3

-- How many clicks on the same NPC before triggering a pissed line
local PISSED_CLICK_THRESHOLD = 3
-- Time window (seconds) in which clicks count toward pissed threshold
local PISSED_CLICK_WINDOW = 4
-- How long (seconds) after last greet to still play a bye line
local BYE_GRACE_PERIOD = 60
-- Minimum time after a greet before a target-loss bye is allowed
local TARGET_LOSS_BYE_DELAY = 1.6
-- Minimum spacing between injected TBC lines to prevent rapid overlap
local MIN_PLAYBACK_GAP = 1.25
-- Briefly suppress native dialog around injected playback to prevent unknown Midnight VO from stacking
local DIALOG_SUPPRESSION_WINDOW = 0.4
-- Fake distance falloff for non-3D injected VO.
-- Since PlaySoundFile cannot attach to the NPC in world space, we approximate falloff by
-- reducing how often target-select VO plays as the target gets farther away.
local RANGE_TIER_NEAR_CHANCE = 0.65
local RANGE_TIER_FAR_CHANCE = 0.25
local BLOOD_ELF_FALLBACK_ZONES = {
    ["silvermoon city"] = true,
    ["eversong woods"] = true,
    ["sunstrider isle"] = true,
    ["ghostlands"] = true,
}

-- ============================================================
--  MUSIC CONSTANTS
--  This block is safe for end users to tune carefully.
--
--  SAFE TO CHANGE:
--  - `MUSIC_TRACK_ROTATE_SECONDS`: approximate time before the
--    addon rotates to another TBC music track if you stay in the
--    same supported area for a long time.
--  - `MUSIC_REPEAT_COOLDOWN`: minimum time before the same track
--    is allowed to be picked again by the shuffle logic.
--  - `MUSIC_DAY_START_HOUR` and `MUSIC_NIGHT_START_HOUR`: the
--    day/night split used for selecting the replacement pool.
--
--  CHANGE WITH CARE:
--  - `BLOOD_ELF_MUSIC_ZONES` should only contain lowercase zone
--    names that you explicitly want to receive replacement music.
--  - Removing both supported zones effectively disables the
--    region routing logic.
-- ============================================================
local MUSIC_UPDATE_INTERVAL = 1.0
local MUSIC_TRACK_ROTATE_SECONDS = 85
local MUSIC_REPEAT_COOLDOWN = 180
local MUSIC_INTRO_REPEAT_COOLDOWN = 600
local MUSIC_TRANSITION_FADE_MS = 900
local MUSIC_END_GRACE_SECONDS = 0.5
local MUSIC_DAY_START_HOUR = 6
local MUSIC_NIGHT_START_HOUR = 18
local BLOOD_ELF_MUSIC_ZONES = {
    ["silvermoon city"] = true,
    ["eversong woods"] = true,
    ["sanctum of light"] = true,
}

-- Some Midnight interiors and enclave slices report a different
-- top-level zone name while still being logically inside the same
-- Silvermoon music space. Add lowercase subzone names here as you
-- discover them in verbose mode.
--
-- SAFE TO CHANGE:
-- - Add more lowercase subzone names as you test.
--
-- CHANGE WITH CARE:
-- - These are broad allow-list matches. Adding unrelated names can
--   make TBC music bleed into places you do not want.
local BLOOD_ELF_MUSIC_SUBZONES = {
    ["the bazaar"] = true,
}

-- Broad music families. These are what the actual playback logic
-- should react to. Fine-grained subzones are still logged for
-- mapping, but they should not constantly restart the same track
-- while you move around inside one logical music region.
local MUSIC_REGION_SILVERMOON = "silvermoon"
local MUSIC_REGION_EVERSONG = "eversong"
local MUSIC_REGION_SUNSTRIDER = "sunstrider"
local MUSIC_REGION_GHOSTLANDS = "ghostlands"

-- Some Midnight-era subzones still logically belong to a different
-- music family than the broad top-level zone name suggests.
-- This lets the addon route them into a different regional pool.
--
-- SAFE TO CHANGE:
-- - Add lowercase subzone names here as you confirm they should
--   borrow a different regional music family.
local MUSIC_SUBZONE_REGION_OVERRIDES = {
    ["amani pass"] = MUSIC_REGION_GHOSTLANDS,
    ["daggerspine landing"] = MUSIC_REGION_GHOSTLANDS,
    ["daggerspine point"] = MUSIC_REGION_GHOSTLANDS,
    ["farstrider enclave"] = MUSIC_REGION_GHOSTLANDS,
    ["goldenmist village"] = MUSIC_REGION_GHOSTLANDS,
    ["ruins of deatholme"] = MUSIC_REGION_GHOSTLANDS,
    ["tranquillien"] = MUSIC_REGION_GHOSTLANDS,
    ["sanctum of the moon"] = MUSIC_REGION_GHOSTLANDS,
    ["sunstrider isle"] = MUSIC_REGION_SUNSTRIDER,
    ["suncrown village"] = MUSIC_REGION_GHOSTLANDS,
    ["thalassian pass"] = MUSIC_REGION_GHOSTLANDS,
    ["windrunner spire"] = MUSIC_REGION_GHOSTLANDS,
    ["windrunner village"] = MUSIC_REGION_GHOSTLANDS,
    ["zeb'nowa"] = MUSIC_REGION_GHOSTLANDS,
    ["zeb'tela ruins"] = MUSIC_REGION_GHOSTLANDS,
}


-- ============================================================
--  SAVED VARIABLES DEFAULTS
-- ============================================================
local DB_DEFAULTS = {
    schemaVersion = DB_SCHEMA_VERSION,
    enabled = true,
    muteNew = true,
    verbose = false,
    fallbackHumanoid = true,
    playOnTarget = true,
    invertSex = false,
    suppressNativeDialog = true,
    musicEnabled = true,
    muteNewMusic = true,
    musicVerbose = false,
    musicUseIntro = true,
    musicTraceEnabled = false,
    musicTraceLog = {},
    guidGenderOverrides = {},
    guidRoleOverrides = {},
    genderOverrides = {},
    roleOverrides = {},
    nameGenderOverrides = {},
    nameRoleOverrides = {},
}


-- ============================================================
--  STATE
-- ============================================================
local state = {
    lastTargetGUID = nil,    -- GUID of the last NPC we greeted
    lastTargetName = nil,
    lastGreetTime = 0,       -- timestamp of last greet
    clickCount = 0,          -- how many times we've clicked the current NPC
    lastClickTime = 0,       -- timestamp of last click (for window reset)
    lastNPCGender = nil,     -- "male", "female", or nil for last gossiped NPC
    lastNPCRole = nil,
    lastNPCGreetCategory = nil,
    lastTargetChangeGUID = nil,
    lastTargetChangeTime = 0,
    lastSoundHandle = nil,
    lastPlaybackTime = 0,
    dialogSuppressToken = 0,
    dialogPrevEnabled = nil,
    lastTargetRangeTier = nil,
    musicHandle = nil,
    musicCurrentTrackID = nil,
    musicCurrentPool = nil,
    musicCurrentAreaKey = nil,
    musicCurrentRegionKey = nil,
    musicLastTrackStartedAt = 0,
    musicExpectedEndTime = 0,
    musicLastGlobalMusicEnabled = nil,
    musicLastContextSignature = nil,
    musicLastZoneName = nil,
    musicLastSubZoneName = nil,
    musicLastResting = nil,
    musicLastIndoor = nil,
    musicLastNight = nil,
    musicWasInSupportedZone = false,
    musicTrackCooldowns = {},
    musicIntroCooldowns = {},
    musicUpdateAccumulator = 0,
    musicIntroPending = false,
    musicManualStop = false,
}

local ui = {
    panel = nil,
    voiceTabButton = nil,
    musicTabButton = nil,
    voiceSection = nil,
    musicSection = nil,
    activeTab = "voice",
    statusText = nil,
    enabledCheckbox = nil,
    muteCheckbox = nil,
    verboseCheckbox = nil,
    fallbackCheckbox = nil,
    targetCheckbox = nil,
    invertSexCheckbox = nil,
    suppressDialogCheckbox = nil,
    musicEnabledCheckbox = nil,
    musicMuteCheckbox = nil,
    musicVerboseCheckbox = nil,
    musicIntroCheckbox = nil,
    musicTraceCheckbox = nil,
    musicStatusText = nil,
}

local raceTooltip = CreateFrame("GameTooltip", ADDON_NAME .. "RaceTooltip", nil, "GameTooltipTemplate")
raceTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

-- Built-in NPC-ID fixes for Midnight records that report bad metadata.
-- Add more entries here as you discover them:
-- ["123456"] = "female"
local DEFAULT_GENDER_OVERRIDES = {}

-- Built-in role defaults by NPC ID.
-- Valid roles: "military", "noble", "standard"
local DEFAULT_ROLE_OVERRIDES = {}

-- Built-in name fallbacks for NPCs that do not expose race/gossip data cleanly.
-- This is useful for repeated ambient NPC names where Blizzard hides useful metadata.
local DEFAULT_NAME_PROFILES = {
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
}


-- ============================================================
--  HELPERS
-- ============================================================

-- Print a debug message if verbose mode is on
local function Log(msg)
    if BElfVRDB and BElfVRDB.verbose then
        print("|cffFFD700[BElfVR]|r " .. tostring(msg))
    end
end

-- Separate music logging keeps zone/music spam out of the normal
-- voice debug stream unless the user explicitly asks for it.
local function LogMusic(msg)
    if BElfVRDB and BElfVRDB.musicVerbose then
        print("|cff7FD4FF[BElfVR Music]|r " .. tostring(msg))
    end
end

-- WoW addons cannot write arbitrary text files directly.
-- This recorder writes into SavedVariables instead, which WoW
-- flushes to disk on /reload or logout.
--
-- SAFE TO CHANGE:
-- - `maxEntries` can be increased if you want longer traces.
--
-- DO NOT REMOVE THE RING-BUFFER TRIM:
-- - Unbounded growth will bloat the SavedVariables file and can
--   become annoying to load and inspect.
local function RecordMusicTrace(msg)
    if not (BElfVRDB and BElfVRDB.musicTraceEnabled) then
        return
    end

    BElfVRDB.musicTraceLog = BElfVRDB.musicTraceLog or {}

    local hour = date("%H:%M:%S")
    local line = "[" .. tostring(hour or "??:??:??") .. "] " .. tostring(msg)
    local log = BElfVRDB.musicTraceLog
    local maxEntries = 1200

    log[#log + 1] = line

    local overflow = #log - maxEntries
    if overflow > 0 then
        for i = 1, overflow do
            tremove(log, 1)
        end
    end
end

local function ShowHelpTooltip(self, title, text)
    if not title and not text then
        return
    end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if title then
        GameTooltip:SetText(title, 1, 0.82, 0)
    end
    if text then
        GameTooltip:AddLine(text, 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function HideHelpTooltip()
    GameTooltip:Hide()
end

local function CountEntries(list)
    return list and #list or 0
end

-- Returns whether the user currently allows the music channel.
-- This mirrors the voice code respecting WoW's sound toggles.
local function IsGlobalMusicEnabled()
    if GetCVar("Sound_EnableAllSound") == "0" then
        return false
    end
    if GetCVar("Sound_EnableMusic") == "0" then
        return false
    end
    return true
end

local function SliceList(list, startIndex, count)
    local result = {}
    if not list then
        return result
    end

    local lastIndex = startIndex + count - 1
    for i = startIndex, lastIndex do
        if list[i] then
            result[#result + 1] = list[i]
        end
    end

    return result
end

local function GetNPCIDFromGUID(guid)
    if not guid then return nil end

    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if unitType ~= "Creature" and unitType ~= "Vehicle" then
        return nil
    end

    return npcID
end

local function IsLikelyBloodElfFallback(unit, allowWithoutGossip)
    if not UnitExists(unit) or UnitIsPlayer(unit) then
        return false
    end

    local creatureType = UnitCreatureType(unit)
    local sex = UnitSex(unit)
    local canGossip = GossipFrame and GossipFrame:IsShown()

    if BElfVRDB and BElfVRDB.verbose then
        Log("Fallback check: creatureType=" .. tostring(creatureType or "?") ..
            " sex=" .. tostring(sex or "?") ..
            " gossipShown=" .. tostring(canGossip))
    end

    local zoneName = string.lower(GetRealZoneText() or GetZoneText() or "")
    local subZoneName = string.lower(GetSubZoneText() or "")
    local zoneAllowed = BLOOD_ELF_FALLBACK_ZONES[zoneName]
    if zoneAllowed == nil and subZoneName ~= "" then
        zoneAllowed = BLOOD_ELF_FALLBACK_ZONES[subZoneName]
    end

    if zoneAllowed ~= true then
        if BElfVRDB and BElfVRDB.verbose then
            Log("Fallback blocked outside Blood Elf zones: zone=" ..
                tostring(zoneName ~= "" and zoneName or "?") ..
                " subzone=" .. tostring(subZoneName ~= "" and subZoneName or "?"))
        end
        return false
    end

    if creatureType == "Humanoid" and (sex == 2 or sex == 3) and (canGossip or allowWithoutGossip) then
        return true
    end

    return false
end

local function GetVoiceStats()
    local newCount = CountEntries(BElfVR_NewVoiceIDs)
    local maleGreet = BElfVR_TBCVoices_Male and CountEntries(BElfVR_TBCVoices_Male.greet) or 0
    local maleBye = BElfVR_TBCVoices_Male and CountEntries(BElfVR_TBCVoices_Male.bye) or 0
    local malePissed = BElfVR_TBCVoices_Male and CountEntries(BElfVR_TBCVoices_Male.pissed) or 0
    local femaleGreet = BElfVR_TBCVoices_Female and CountEntries(BElfVR_TBCVoices_Female.greet) or 0
    local femaleBye = BElfVR_TBCVoices_Female and CountEntries(BElfVR_TBCVoices_Female.bye) or 0
    local femalePissed = BElfVR_TBCVoices_Female and CountEntries(BElfVR_TBCVoices_Female.pissed) or 0

    return {
        newCount = newCount,
        maleGreet = maleGreet,
        maleBye = maleBye,
        malePissed = malePissed,
        femaleGreet = femaleGreet,
        femaleBye = femaleBye,
        femalePissed = femalePissed,
    }
end

-- ============================================================
--  MUSIC HELPERS
--  This entire section is intentionally isolated from the voice
--  interaction code so future music tuning stays local.
-- ============================================================

local function GetMusicStats()
    local introCount = BElfVR_TBCMusic and CountEntries(BElfVR_TBCMusic.intro) or 0
    local dayCount = BElfVR_TBCMusic and CountEntries(BElfVR_TBCMusic.day) or 0
    local nightCount = BElfVR_TBCMusic and CountEntries(BElfVR_TBCMusic.night) or 0
    local mutedCount = CountEntries(BElfVR_NewMusicIDs)
    local regionalCount = 0

    if BElfVR_TBCMusicRegions then
        for _, regionData in pairs(BElfVR_TBCMusicRegions) do
            regionalCount = regionalCount +
                CountEntries(regionData and regionData.intro) +
                CountEntries(regionData and regionData.day) +
                CountEntries(regionData and regionData.night)
        end
    end

    return {
        introCount = introCount,
        dayCount = dayCount,
        nightCount = nightCount,
        mutedCount = mutedCount,
        regionalCount = regionalCount,
    }
end

local function IsMusicReplacementActive()
    return BElfVRDB and BElfVRDB.enabled and BElfVRDB.musicEnabled and BElfVRDB.muteNewMusic
end

local function GetCurrentGameHour()
    local hour = 12
    if GetGameTime then
        local gameHour = GetGameTime()
        if type(gameHour) == "number" then
            hour = gameHour
        end
    end
    return hour
end

local function IsNightTimeForMusic()
    local hour = GetCurrentGameHour()
    return hour < MUSIC_DAY_START_HOUR or hour >= MUSIC_NIGHT_START_HOUR
end

-- Region-aware pool lookup.
-- The addon first tries the explicit per-region override table, then
-- falls back to the legacy global Silvermoon table so empty buckets
-- still behave sensibly while mapping is in progress.
local function GetMusicTrackPool(regionKey, poolName)
    local regionData = BElfVR_TBCMusicRegions and regionKey and BElfVR_TBCMusicRegions[regionKey]
    local regionPool = regionData and regionData[poolName]
    if regionPool and #regionPool > 0 then
        return regionPool, regionKey
    end

    local legacyPool = BElfVR_TBCMusic and BElfVR_TBCMusic[poolName]
    if legacyPool and #legacyPool > 0 then
        return legacyPool, MUSIC_REGION_SILVERMOON
    end

    return nil, nil
end

local function ShouldQueueMusicIntro(regionKey)
    if not (BElfVRDB and BElfVRDB.musicUseIntro and regionKey) then
        return false
    end

    local now = GetTime()
    local lastIntroAt = state.musicIntroCooldowns and state.musicIntroCooldowns[regionKey]
    if lastIntroAt and (now - lastIntroAt) < MUSIC_INTRO_REPEAT_COOLDOWN then
        local remaining = math.ceil(MUSIC_INTRO_REPEAT_COOLDOWN - (now - lastIntroAt))
        LogMusic("Skipping intro for region " .. regionKey .. " because intro cooldown is still active (" .. remaining .. "s left).")
        RecordMusicTrace("Skipped intro for region=" .. regionKey .. " cooldownRemaining=" .. tostring(remaining))
        return false
    end

    return true
end

-- Builds a compact context snapshot from the player's current
-- position. This is what the addon can reliably inspect through
-- addon Lua. Blizzard's internal music resolver still has more
-- data than addons do, so this is intentionally conservative.
local function GetMusicContext()
    local zoneName = GetRealZoneText() or GetZoneText() or ""
    local subZoneName = GetSubZoneText() or ""
    local zoneKey = string.lower(zoneName)
    local subZoneKey = string.lower(subZoneName)
    local supportedByZone = BLOOD_ELF_MUSIC_ZONES[zoneKey] == true
    local supportedBySubZone = BLOOD_ELF_MUSIC_SUBZONES[subZoneKey] == true
    local supported = supportedByZone or supportedBySubZone
    local isResting = IsResting() and true or false
    local isNight = IsNightTimeForMusic()
    local isIndoor = (subZoneKey ~= "" and subZoneKey ~= zoneKey)
    local regionKey = MUSIC_SUBZONE_REGION_OVERRIDES[subZoneKey]

    if regionKey then
        -- Explicit subzone override wins.
    elseif zoneKey == "eversong woods" then
        regionKey = MUSIC_REGION_EVERSONG
    elseif zoneKey == "silvermoon city" or zoneKey == "sanctum of light" then
        regionKey = MUSIC_REGION_SILVERMOON
    elseif supportedBySubZone then
        regionKey = MUSIC_REGION_SILVERMOON
    elseif supported and supportedByZone then
        regionKey = zoneKey
    end

    return {
        zoneName = zoneName,
        subZoneName = subZoneName,
        zoneKey = zoneKey,
        subZoneKey = subZoneKey,
        supported = supported,
        supportedByZone = supportedByZone,
        supportedBySubZone = supportedBySubZone,
        isResting = isResting,
        isNight = isNight,
        isIndoor = isIndoor,
        regionKey = regionKey,
        -- This is the stable playback routing key.
        -- DO NOT casually replace this with subzone or resting-state
        -- data again, or the addon will start hard-restarting music
        -- every few steps across tiny Silvermoon boundaries.
        areaKey = tostring(regionKey or zoneKey) .. "||" .. (isNight and "night" or "day"),
    }
end

local function StopInjectedMusic(fadeOutMS)
    if state.musicHandle then
        StopSound(state.musicHandle, fadeOutMS or 0)
        state.musicHandle = nil
    end
    state.musicCurrentTrackID = nil
    state.musicCurrentPool = nil
    state.musicLastTrackStartedAt = 0
    state.musicExpectedEndTime = 0
end

local function ResetMusicState(stopPlayback)
    if stopPlayback then
        StopInjectedMusic(MUSIC_TRANSITION_FADE_MS)
    end

    state.musicCurrentAreaKey = nil
    state.musicCurrentRegionKey = nil
    state.musicLastContextSignature = nil
    state.musicLastZoneName = nil
    state.musicLastSubZoneName = nil
    state.musicLastResting = nil
    state.musicLastIndoor = nil
    state.musicLastNight = nil
    state.musicWasInSupportedZone = false
    state.musicTrackCooldowns = {}
    state.musicUpdateAccumulator = 0
    state.musicIntroPending = false
    state.musicLastGlobalMusicEnabled = nil
end

-- If the track should already be over based on its known duration,
-- clear the stale handle state so the scheduler can queue the next
-- song immediately instead of waiting for the coarse rotation timer.
local function RefreshMusicPlaybackLifetime()
    if not state.musicHandle or state.musicExpectedEndTime <= 0 then
        return
    end

    local now = GetTime()
    if now < (state.musicExpectedEndTime + MUSIC_END_GRACE_SECONDS) then
        return
    end

    LogMusic("Current music track appears finished; clearing stale playback state so the next track can start.")
    RecordMusicTrace("Detected completed track; clearing stale playback state.")

    state.musicHandle = nil
    state.musicCurrentTrackID = nil
    state.musicCurrentPool = nil
    state.musicLastTrackStartedAt = 0
    state.musicExpectedEndTime = 0
end

-- Detects live changes to WoW's own music toggle (for example Ctrl+M)
-- so the addon behaves like native music: fade out when disabled,
-- resume with a fresh track when re-enabled.
local function HandleGlobalMusicToggle()
    if not BElfVRDB then
        return false
    end

    local isEnabled = IsGlobalMusicEnabled()
    if state.musicLastGlobalMusicEnabled == nil then
        state.musicLastGlobalMusicEnabled = isEnabled
        return false
    end

    if isEnabled == state.musicLastGlobalMusicEnabled then
        return false
    end

    state.musicLastGlobalMusicEnabled = isEnabled

    if not isEnabled then
        if state.musicHandle then
            LogMusic("WoW music output was disabled; fading out injected music.")
            RecordMusicTrace("Detected global music disable; fading out injected music.")
            StopInjectedMusic(MUSIC_TRANSITION_FADE_MS)
        end
        return true
    end

    LogMusic("WoW music output was re-enabled; the addon will resume with a fresh track.")
    RecordMusicTrace("Detected global music enable; scheduling fresh music playback.")
    return true
end

-- Picks a track from the provided pool while strongly avoiding
-- immediate repeats. The same ID is kept on cooldown for a few
-- minutes before it is considered again.
--
-- SAFE TO CHANGE:
-- - The cooldown duration is controlled by
--   `MUSIC_REPEAT_COOLDOWN` near the top of the file.
--
-- DO NOT CHANGE LIGHTLY:
-- - The fallback order here is what prevents tiny pools from
--   getting stuck with "no valid track" edge cases.
local function ChooseMusicTrack(poolName, tracks)
    if not tracks or #tracks == 0 then
        return nil
    end

    local now = GetTime()
    local eligible = {}

    for _, fileDataID in ipairs(tracks) do
        local lastPlayedAt = state.musicTrackCooldowns[fileDataID]
        local cooledDown = (not lastPlayedAt) or ((now - lastPlayedAt) >= MUSIC_REPEAT_COOLDOWN)

        if cooledDown and fileDataID ~= state.musicCurrentTrackID then
            eligible[#eligible + 1] = fileDataID
        end
    end

    if #eligible == 0 and #tracks > 1 then
        for _, fileDataID in ipairs(tracks) do
            if fileDataID ~= state.musicCurrentTrackID then
                eligible[#eligible + 1] = fileDataID
            end
        end
    end

    if #eligible == 0 then
        for _, fileDataID in ipairs(tracks) do
            eligible[#eligible + 1] = fileDataID
        end
    end

    local chosen = eligible[math.random(#eligible)]
    state.musicTrackCooldowns[chosen] = now
    LogMusic("Selected " .. tostring(poolName or "?") .. " track ID " .. chosen .. " from " .. #eligible .. " eligible candidate(s).")
    RecordMusicTrace("Selected pool=" .. tostring(poolName or "?") .. " track=" .. tostring(chosen) ..
        " eligible=" .. tostring(#eligible))
    return chosen
end

local function PlayMusicTrack(fileDataID, poolName, reason)
    if not fileDataID then
        return
    end
    if not IsGlobalMusicEnabled() then
        LogMusic("Skipping replacement music because WoW music output is disabled.")
        RecordMusicTrace("Skipped playback because WoW music output is disabled.")
        return
    end

    StopInjectedMusic(MUSIC_TRANSITION_FADE_MS)

    local willPlay, soundHandle = PlaySoundFile(fileDataID, "Music")
    if not willPlay then
        LogMusic("PlaySoundFile failed for music track ID " .. fileDataID)
        RecordMusicTrace("PlaySoundFile failed for track=" .. tostring(fileDataID))
        return
    end

    state.musicHandle = soundHandle
    state.musicCurrentTrackID = fileDataID
    state.musicCurrentPool = poolName
    state.musicLastTrackStartedAt = GetTime()
    state.musicExpectedEndTime = state.musicLastTrackStartedAt + ((BElfVR_TBCMusicDurations and BElfVR_TBCMusicDurations[fileDataID]) or MUSIC_TRACK_ROTATE_SECONDS)

    LogMusic("Playing " .. tostring(poolName or "?") .. " music track ID " .. fileDataID ..
        " (" .. tostring(reason or "unspecified") .. ")")
    RecordMusicTrace("Playing pool=" .. tostring(poolName or "?") .. " track=" .. tostring(fileDataID) ..
        " reason=" .. tostring(reason or "unspecified"))
end

local function EvaluateMusicState(reason, forceTrackRefresh)
    if not BElfVRDB then
        return
    end

    local globalMusicToggleChanged = HandleGlobalMusicToggle()
    RefreshMusicPlaybackLifetime()

    local context = GetMusicContext()
    local contextSignature = context.areaKey

    if not IsGlobalMusicEnabled() then
        state.musicCurrentAreaKey = context.areaKey
        state.musicCurrentRegionKey = context.regionKey
        state.musicLastContextSignature = contextSignature
        return
    end

    if context.zoneName ~= state.musicLastZoneName or
       context.subZoneName ~= state.musicLastSubZoneName or
       context.isResting ~= state.musicLastResting or
       context.isIndoor ~= state.musicLastIndoor or
       context.isNight ~= state.musicLastNight then
        LogMusic("Context change [" .. tostring(reason or "update") .. "]: zone=" ..
            tostring(context.zoneName ~= "" and context.zoneName or "<none>") ..
            " subzone=" .. tostring(context.subZoneName ~= "" and context.subZoneName or "<none>") ..
            " region=" .. tostring(context.regionKey or "<none>") ..
            " supported(zone)=" .. tostring(context.supportedByZone) ..
            " supported(subzone)=" .. tostring(context.supportedBySubZone) ..
            " resting=" .. tostring(context.isResting) ..
            " indoorLike=" .. tostring(context.isIndoor) ..
            " phase=" .. (context.isNight and "night" or "day"))
        RecordMusicTrace("Context reason=" .. tostring(reason or "update") ..
            " zone=" .. tostring(context.zoneName ~= "" and context.zoneName or "<none>") ..
            " subzone=" .. tostring(context.subZoneName ~= "" and context.subZoneName or "<none>") ..
            " region=" .. tostring(context.regionKey or "<none>") ..
            " supportedZone=" .. tostring(context.supportedByZone) ..
            " supportedSubZone=" .. tostring(context.supportedBySubZone) ..
            " resting=" .. tostring(context.isResting) ..
            " indoorLike=" .. tostring(context.isIndoor) ..
            " phase=" .. (context.isNight and "night" or "day"))
    end

    state.musicLastZoneName = context.zoneName
    state.musicLastSubZoneName = context.subZoneName
    state.musicLastResting = context.isResting
    state.musicLastIndoor = context.isIndoor
    state.musicLastNight = context.isNight

    if not context.supported then
        if state.musicWasInSupportedZone then
            LogMusic("Leaving supported music region; stopping injected music.")
            RecordMusicTrace("Leaving supported music region; stopping injected music.")
        end
        state.musicWasInSupportedZone = false
        state.musicCurrentAreaKey = nil
        state.musicCurrentRegionKey = nil
        state.musicLastContextSignature = contextSignature
        state.musicIntroPending = false
        if state.musicHandle then
            StopInjectedMusic(MUSIC_TRANSITION_FADE_MS)
        end
        return
    end

    state.musicWasInSupportedZone = true

    if not IsMusicReplacementActive() then
        if state.musicHandle then
            LogMusic("Music replacement is disabled or unmuted; stopping injected music to avoid overlap.")
            RecordMusicTrace("Music replacement inactive; stopping injected music.")
            StopInjectedMusic(MUSIC_TRANSITION_FADE_MS)
        end
        state.musicCurrentAreaKey = context.areaKey
        state.musicCurrentRegionKey = context.regionKey
        state.musicLastContextSignature = contextSignature
        state.musicIntroPending = false
        return
    end

    local enteringSupportedZone = (state.musicLastContextSignature ~= nil and state.musicCurrentAreaKey == nil)
        or (not state.musicCurrentAreaKey)
    local areaChanged = state.musicCurrentAreaKey ~= context.areaKey
    local regionChanged = state.musicCurrentRegionKey ~= context.regionKey
    -- Fallback-only rotation:
    -- If a track has a known duration, let it finish naturally.
    -- The old fixed timer caused long songs (especially intros) to be
    -- cut off abruptly before their natural end.
    local timeToRotate = state.musicLastTrackStartedAt > 0 and
        state.musicExpectedEndTime <= 0 and
        ((GetTime() - state.musicLastTrackStartedAt) >= MUSIC_TRACK_ROTATE_SECONDS)

    if enteringSupportedZone or regionChanged then
        state.musicIntroPending = ShouldQueueMusicIntro(context.regionKey)
    end

    if state.musicManualStop then
        if forceTrackRefresh or globalMusicToggleChanged or areaChanged then
            state.musicManualStop = false
        else
            state.musicCurrentAreaKey = context.areaKey
            state.musicCurrentRegionKey = context.regionKey
            state.musicLastContextSignature = contextSignature
            return
        end
    end

    if not (forceTrackRefresh or globalMusicToggleChanged or areaChanged or timeToRotate or not state.musicHandle) then
        state.musicLastContextSignature = contextSignature
        return
    end

    local poolName
    local trackPool
    local resolvedRegionKey = context.regionKey

    if state.musicIntroPending then
        poolName = "intro"
        trackPool, resolvedRegionKey = GetMusicTrackPool(context.regionKey, "intro")
        state.musicIntroPending = false
        if trackPool and context.regionKey then
            state.musicIntroCooldowns[context.regionKey] = GetTime()
        end
    else
        poolName = context.isNight and "night" or "day"
        trackPool, resolvedRegionKey = GetMusicTrackPool(context.regionKey, poolName)
    end

    local nextTrack = ChooseMusicTrack(poolName, trackPool)
    if nextTrack then
        local resolvedPoolName = poolName
        if resolvedRegionKey and resolvedRegionKey ~= context.regionKey then
            resolvedPoolName = tostring(context.regionKey or "?") .. "->" .. tostring(resolvedRegionKey) .. ":" .. poolName
        elseif resolvedRegionKey then
            resolvedPoolName = tostring(resolvedRegionKey) .. ":" .. poolName
        end
        PlayMusicTrack(nextTrack, resolvedPoolName, reason or (areaChanged and "area change" or "rotation"))
    else
        LogMusic("No replacement music tracks are configured for pool " .. tostring(poolName or "?"))
        RecordMusicTrace("No tracks configured for pool=" .. tostring(poolName or "?"))
    end

    state.musicCurrentAreaKey = context.areaKey
    state.musicCurrentRegionKey = context.regionKey
    state.musicLastContextSignature = contextSignature
end

local function MigrateSavedVariables()
    if not BElfVRDB then
        return
    end

    local currentVersion = tonumber(BElfVRDB.schemaVersion) or 0
    if currentVersion >= DB_SCHEMA_VERSION then
        return
    end

    if currentVersion < 2 then
        local hadGenderOverrides = BElfVRDB.genderOverrides and next(BElfVRDB.genderOverrides) ~= nil
        local hadRoleOverrides = BElfVRDB.roleOverrides and next(BElfVRDB.roleOverrides) ~= nil

        if hadGenderOverrides or hadRoleOverrides then
            BElfVRDB.legacyOverrideBackup = BElfVRDB.legacyOverrideBackup or {
                genderOverrides = BElfVRDB.genderOverrides,
                roleOverrides = BElfVRDB.roleOverrides,
            }
        end

        BElfVRDB.genderOverrides = {}
        BElfVRDB.roleOverrides = {}
    end

    BElfVRDB.schemaVersion = DB_SCHEMA_VERSION
end

local function GetUnitVORangeTier(unit)
    if not UnitExists(unit) then
        return nil
    end

    -- 3 is the tightest built-in check, 2 is slightly looser, 1/4 are the broad nearby checks.
    if CheckInteractDistance(unit, 3) then
        return "close"
    end
    if CheckInteractDistance(unit, 2) then
        return "near"
    end
    if CheckInteractDistance(unit, 1) or CheckInteractDistance(unit, 4) then
        return "far"
    end

    return nil
end

local function ShouldPlayForRangeTier(rangeTier)
    if rangeTier == "close" then
        return true
    end

    if rangeTier == "near" then
        local roll = math.random()
        Log("Range tier=near roll=" .. string.format("%.2f", roll) .. " threshold=" .. tostring(RANGE_TIER_NEAR_CHANCE))
        return roll <= RANGE_TIER_NEAR_CHANCE
    end

    if rangeTier == "far" then
        local roll = math.random()
        Log("Range tier=far roll=" .. string.format("%.2f", roll) .. " threshold=" .. tostring(RANGE_TIER_FAR_CHANCE))
        return roll <= RANGE_TIER_FAR_CHANCE
    end

    return false
end

local function ApplyDialogSuppressionWindow()
    if not (BElfVRDB and BElfVRDB.suppressNativeDialog) then
        return
    end

    state.dialogSuppressToken = state.dialogSuppressToken + 1
    local suppressToken = state.dialogSuppressToken
    state.dialogPrevEnabled = GetCVar("Sound_EnableDialog")
    if state.dialogPrevEnabled ~= "0" then
        SetCVar("Sound_EnableDialog", "0")
    end

    C_Timer.After(DIALOG_SUPPRESSION_WINDOW, function()
        if state.dialogSuppressToken ~= suppressToken then
            return
        end

        local restoreValue = state.dialogPrevEnabled or "1"
        if GetCVar("Sound_EnableDialog") ~= restoreValue then
            SetCVar("Sound_EnableDialog", restoreValue)
        end
    end)
end

local function IsGlobalSoundEnabled()
    if GetCVar("Sound_EnableAllSound") == "0" then
        return false
    end

    if GetCVar("Sound_EnableSFX") == "0" then
        return false
    end

    return true
end

local function GetConfiguredGenderOverride(npcID)
    if not npcID then
        return nil
    end

    local key = tostring(npcID)
    local value = DEFAULT_GENDER_OVERRIDES[key]

    if value == "male" or value == "female" then
        return value
    end

    return nil
end

local function GetConfiguredGUIDGenderOverride(guid)
    if not guid then
        return nil
    end

    local value = BElfVRDB and BElfVRDB.guidGenderOverrides and BElfVRDB.guidGenderOverrides[guid]
    if value == "male" or value == "female" then
        return value
    end

    return nil
end

local function GetDefaultNameProfile(unit)
    local name = UnitName(unit)
    if not name then
        return nil
    end

    return DEFAULT_NAME_PROFILES[string.lower(name)]
end

local function GetConfiguredNameGenderOverride(unit)
    local name = UnitName(unit)
    if not name then
        return nil
    end

    local key = string.lower(name)
    local value = BElfVRDB and BElfVRDB.nameGenderOverrides and BElfVRDB.nameGenderOverrides[key]
    if value == "male" or value == "female" then
        return value
    end

    return nil
end

local function GetConfiguredNameRoleOverride(unit)
    local name = UnitName(unit)
    if not name then
        return nil
    end

    local key = string.lower(name)
    local value = BElfVRDB and BElfVRDB.nameRoleOverrides and BElfVRDB.nameRoleOverrides[key]
    if value == "military" or value == "noble" or value == "standard" then
        return value
    end

    return nil
end

local function IsExcludedByNameProfile(unit)
    local profile = GetDefaultNameProfile(unit)
    return profile and profile.exclude and true or false
end

local function GetGreetingCategory(unit)
    local profile = GetDefaultNameProfile(unit)
    if profile and profile.vendor then
        return "vendor"
    end

    if MerchantFrame and MerchantFrame:IsShown() then
        return "vendor"
    end

    return "greet"
end

local function GetConfiguredRoleOverride(npcID)
    if not npcID then
        return nil
    end

    local key = tostring(npcID)
    local value = DEFAULT_ROLE_OVERRIDES[key]

    if value == "military" or value == "noble" or value == "standard" then
        return value
    end

    return nil
end

local function GetConfiguredGUIDRoleOverride(guid)
    if not guid then
        return nil
    end

    local value = BElfVRDB and BElfVRDB.guidRoleOverrides and BElfVRDB.guidRoleOverrides[guid]
    if value == "military" or value == "noble" or value == "standard" then
        return value
    end

    return nil
end

-- This layout splits each master list in SoundData.lua into sub-pools.
-- Keep the ordering in SoundData.lua stable (noble block, then standard, then military)
-- or update these offsets if you insert/remove entries.
local function BuildRolePools(source, layout)
    if not source then
        return nil
    end

    return {
        noble = {
            greet = SliceList(source.greet, layout.greet.nobleGreetStart, layout.greet.nobleGreetCount),
            vendor = SliceList(source.greet, layout.greet.nobleVendorStart, layout.greet.nobleVendorCount),
            bye = SliceList(source.bye, layout.bye.nobleStart, layout.bye.nobleCount),
            pissed = SliceList(source.pissed, layout.pissed.nobleStart, layout.pissed.nobleCount),
        },
        standard = {
            greet = SliceList(source.greet, layout.greet.standardGreetStart, layout.greet.standardGreetCount),
            vendor = SliceList(source.greet, layout.greet.standardVendorStart, layout.greet.standardVendorCount),
            bye = SliceList(source.bye, layout.bye.standardStart, layout.bye.standardCount),
            pissed = SliceList(source.pissed, layout.pissed.standardStart, layout.pissed.standardCount),
        },
        military = {
            greet = SliceList(source.greet, layout.greet.militaryGreetStart, layout.greet.militaryGreetCount),
            vendor = SliceList(source.greet, layout.greet.militaryVendorStart, layout.greet.militaryVendorCount),
            bye = SliceList(source.bye, layout.bye.militaryStart, layout.bye.militaryCount),
            pissed = SliceList(source.pissed, layout.pissed.militaryStart, layout.pissed.militaryCount),
        },
    }
end

local MALE_ROLE_LAYOUT = {
    greet = {
        nobleVendorStart = 1, nobleVendorCount = 6, nobleGreetStart = 7, nobleGreetCount = 7,
        standardVendorStart = 14, standardVendorCount = 6, standardGreetStart = 20, standardGreetCount = 6,
        militaryVendorStart = 26, militaryVendorCount = 6, militaryGreetStart = 32, militaryGreetCount = 6,
    },
    bye = { nobleStart = 1, nobleCount = 6, standardStart = 7, standardCount = 6, militaryStart = 13, militaryCount = 6 },
    pissed = { nobleStart = 1, nobleCount = 5, standardStart = 6, standardCount = 5, militaryStart = 11, militaryCount = 5 },
}

local FEMALE_ROLE_LAYOUT = {
    greet = {
        nobleVendorStart = 1, nobleVendorCount = 6, nobleGreetStart = 7, nobleGreetCount = 6,
        standardVendorStart = 13, standardVendorCount = 6, standardGreetStart = 19, standardGreetCount = 6,
        militaryVendorStart = 32, militaryVendorCount = 6, militaryGreetStart = 25, militaryGreetCount = 7,
    },
    bye = { nobleStart = 1, nobleCount = 6, standardStart = 7, standardCount = 6, militaryStart = 13, militaryCount = 6 },
    pissed = { nobleStart = 1, nobleCount = 5, standardStart = 6, standardCount = 6, militaryStart = 12, militaryCount = 4 },
}

local ROLE_POOLS_MALE = BuildRolePools(BElfVR_TBCVoices_Male, MALE_ROLE_LAYOUT)
local ROLE_POOLS_FEMALE = BuildRolePools(BElfVR_TBCVoices_Female, FEMALE_ROLE_LAYOUT)

local function GetVoiceRole(unit)
    local guid = UnitGUID(unit)
    local guidOverride = GetConfiguredGUIDRoleOverride(guid)
    if guidOverride then
        Log("Using configured role override for guid=" .. tostring(guid) .. ": " .. guidOverride)
        return guidOverride
    end

    local npcID = GetNPCIDFromGUID(guid)
    local override = GetConfiguredRoleOverride(npcID)
    if override then
        Log("Using configured role override for npc=" .. tostring(npcID) .. ": " .. override)
        return override
    end

    local nameOverride = GetConfiguredNameRoleOverride(unit)
    if nameOverride then
        Log("Using configured name role override for " .. tostring(UnitName(unit)) .. ": " .. nameOverride)
        return nameOverride
    end

    local profile = GetDefaultNameProfile(unit)
    if profile and (profile.role == "military" or profile.role == "noble" or profile.role == "standard") then
        Log("Using built-in name role for " .. tostring(UnitName(unit)) .. ": " .. profile.role)
        return profile.role
    end

    local name = string.lower(UnitName(unit) or "")
    if string.find(name, "guard", 1, true) or
       string.find(name, "ranger", 1, true) or
       string.find(name, "captain", 1, true) or
       string.find(name, "blood knight", 1, true) or
       string.find(name, "champion", 1, true) then
        return "military"
    end
    if string.find(name, "lord", 1, true) or string.find(name, "lady", 1, true) or string.find(name, "noble", 1, true) then
        return "noble"
    end

    return "standard"
end

-- Play a random sound from a given TBC voice category for the given gender
-- gender: "male" or "female"
-- category: "greet", "bye", or "pissed"
local function PlayRandomTBC(gender, category, role, suppressNative)
    if not IsGlobalSoundEnabled() then
        Log("Skipping TBC " .. (category or "?") .. " because WoW sound output is disabled.")
        return
    end

    if suppressNative then
        ApplyDialogSuppressionWindow()
    end

    local now = GetTime()
    if (now - state.lastPlaybackTime) < MIN_PLAYBACK_GAP then
        Log("Skipping TBC " .. (category or "?") .. " because playback is rate-limited.")
        return
    end

    local rolePools = (gender == "female") and ROLE_POOLS_FEMALE or ROLE_POOLS_MALE
    local pool = rolePools and role and rolePools[role]
    local sounds = pool and pool[category]

    if not sounds or #sounds == 0 then
        local mixedPool = (gender == "female") and BElfVR_TBCVoices_Female or BElfVR_TBCVoices_Male
        sounds = mixedPool and mixedPool[category]
    end

    if not sounds or #sounds == 0 then
        Log("No sounds loaded for: " .. (gender or "?") .. " / " .. (category or "?"))
        return
    end

    local fileDataID = sounds[math.random(#sounds)]
    if state.lastSoundHandle then
        StopSound(state.lastSoundHandle, 0)
        state.lastSoundHandle = nil
    end

    local willPlay, soundHandle = PlaySoundFile(fileDataID, "Master")
    if willPlay and soundHandle then
        state.lastSoundHandle = soundHandle
    end
    state.lastPlaybackTime = now

    Log("Playing TBC " .. gender .. " " .. (role or "mixed") .. " " .. category .. " (ID: " .. fileDataID .. ")")
end

local function IsReplacementPlaybackActive()
    return BElfVRDB and BElfVRDB.enabled and BElfVRDB.muteNew
end

local function ResetInteractionState()
    state.lastTargetGUID = nil
    state.lastTargetName = nil
    state.lastGreetTime = 0
    state.clickCount = 0
    state.lastClickTime = 0
    state.lastNPCGender = nil
    state.lastNPCRole = nil
    state.lastNPCGreetCategory = nil
    state.lastTargetChangeGUID = nil
    state.lastTargetChangeTime = 0
    state.lastTargetRangeTier = nil
    if state.lastSoundHandle then
        StopSound(state.lastSoundHandle, 0)
        state.lastSoundHandle = nil
    end
    if state.dialogPrevEnabled and GetCVar("Sound_EnableDialog") ~= state.dialogPrevEnabled then
        SetCVar("Sound_EnableDialog", state.dialogPrevEnabled)
    end
    state.lastPlaybackTime = 0
end

local function IsBloodElfNPC(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) then
        return false
    end

    if BElfVRDB and BElfVRDB.verbose then
        Log("Scanning tooltip for race data on target: " .. (UnitName(unit) or "<unknown>"))
    end

    raceTooltip:ClearLines()
    raceTooltip:SetUnit(unit)

    for i = 2, raceTooltip:NumLines() do
        local fontString = _G[raceTooltip:GetName() .. "TextLeft" .. i]
        local text = fontString and fontString:GetText()
        if text and BElfVRDB and BElfVRDB.verbose then
            Log("Tooltip line " .. i .. ": " .. text)
        end
        if text and string.find(string.lower(text), "blood elf", 1, true) then
            raceTooltip:Hide()
            raceTooltip:ClearLines()
            return true
        end
    end

    raceTooltip:Hide()
    raceTooltip:ClearLines()
    return false
end

-- Returns "male", "female", or nil if the unit is not a Blood Elf NPC
local function GetBloodElfNPCGender(unit, allowHiddenRaceFallbackWithoutGossip)
    if not UnitExists(unit) then return nil end

    -- We only want NPCs, not player characters
    if UnitIsPlayer(unit) then return nil end

    if IsExcludedByNameProfile(unit) then
        Log("Target is excluded by built-in name profile: " .. tostring(UnitName(unit)))
        return nil
    end

    local guid = UnitGUID(unit)
    local guidOverride = GetConfiguredGUIDGenderOverride(guid)
    if guidOverride then
        Log("Using configured gender override for guid=" .. tostring(guid) .. ": " .. guidOverride)
        return guidOverride
    end

    local npcID = GetNPCIDFromGUID(guid)
    local override = GetConfiguredGenderOverride(npcID)
    if override then
        Log("Using configured gender override for npc=" .. tostring(npcID) .. ": " .. override)
        return override
    end

    local nameOverride = GetConfiguredNameGenderOverride(unit)
    if nameOverride then
        Log("Using configured name gender override for " .. tostring(UnitName(unit)) .. ": " .. nameOverride)
        return nameOverride
    end

    local profile = GetDefaultNameProfile(unit)
    if profile and (profile.gender == "male" or profile.gender == "female") then
        Log("Using built-in name profile for " .. tostring(UnitName(unit)) .. ": " .. profile.gender)
        return profile.gender
    end

    if not IsBloodElfNPC(unit) then
        if BElfVRDB and BElfVRDB.fallbackHumanoid and IsLikelyBloodElfFallback(unit, allowHiddenRaceFallbackWithoutGossip) then
            Log("Target race is hidden; using humanoid fallback classifier.")
        else
            Log("Target is not recognized as a Blood Elf NPC.")
            return nil
        end
    end

    -- Midnight Blood Elf NPCs appear to report UnitSex inverted relative to the voice sets.
    -- Treat 2/3 as reversed by default, and let the UI toggle flip back if needed.
    local sex = UnitSex(unit)
    if sex == 3 then
        return (BElfVRDB and BElfVRDB.invertSex) and "male" or "female"
    elseif sex == 2 then
        return (BElfVRDB and BElfVRDB.invertSex) and "female" or "male"
    end

    return nil
end


-- ============================================================
--  MUTE / UNMUTE
-- ============================================================

local function ApplyMutes()
    if not BElfVRDB or not BElfVRDB.enabled then
        return
    end

    if BElfVRDB.muteNew and BElfVR_NewVoiceIDs then
        local voiceCount = 0
        for _, id in ipairs(BElfVR_NewVoiceIDs) do
            MuteSoundFile(id)
            voiceCount = voiceCount + 1
        end
        Log("Muted " .. voiceCount .. " new voice file(s).")
    end

    if BElfVRDB.musicEnabled and BElfVRDB.muteNewMusic and BElfVR_NewMusicIDs then
        local musicCount = 0
        for _, id in ipairs(BElfVR_NewMusicIDs) do
            MuteSoundFile(id)
            musicCount = musicCount + 1
        end
        LogMusic("Muted " .. musicCount .. " tracked Midnight music file(s).")
    end
end

local function RemoveMutes()
    if BElfVR_NewVoiceIDs then
        for _, id in ipairs(BElfVR_NewVoiceIDs) do
            UnmuteSoundFile(id)
        end
        Log("Unmuted all new voice files.")
    end

    if BElfVR_NewMusicIDs then
        for _, id in ipairs(BElfVR_NewMusicIDs) do
            UnmuteSoundFile(id)
        end
        LogMusic("Unmuted all tracked Midnight music files.")
    end
end


-- ============================================================
--  SETTINGS / UI
-- ============================================================

local function RefreshUI()
    if not ui.panel or not BElfVRDB then return end

    if ui.enabledCheckbox then
        ui.enabledCheckbox:SetChecked(BElfVRDB.enabled)
    end
    if ui.muteCheckbox then
        ui.muteCheckbox:SetChecked(BElfVRDB.muteNew)
    end
    if ui.verboseCheckbox then
        ui.verboseCheckbox:SetChecked(BElfVRDB.verbose)
    end
    if ui.fallbackCheckbox then
        ui.fallbackCheckbox:SetChecked(BElfVRDB.fallbackHumanoid)
    end
    if ui.targetCheckbox then
        ui.targetCheckbox:SetChecked(BElfVRDB.playOnTarget)
    end
    if ui.invertSexCheckbox then
        ui.invertSexCheckbox:SetChecked(BElfVRDB.invertSex)
    end
    if ui.suppressDialogCheckbox then
        ui.suppressDialogCheckbox:SetChecked(BElfVRDB.suppressNativeDialog)
    end
    if ui.musicEnabledCheckbox then
        ui.musicEnabledCheckbox:SetChecked(BElfVRDB.musicEnabled)
    end
    if ui.musicMuteCheckbox then
        ui.musicMuteCheckbox:SetChecked(BElfVRDB.muteNewMusic)
    end
    if ui.musicVerboseCheckbox then
        ui.musicVerboseCheckbox:SetChecked(BElfVRDB.musicVerbose)
    end
    if ui.musicIntroCheckbox then
        ui.musicIntroCheckbox:SetChecked(BElfVRDB.musicUseIntro)
    end
    if ui.musicTraceCheckbox then
        ui.musicTraceCheckbox:SetChecked(BElfVRDB.musicTraceEnabled)
    end

    if ui.statusText then
        local stats = GetVoiceStats()
        local muteState = (BElfVRDB.enabled and BElfVRDB.muteNew) and "ACTIVE" or "INACTIVE"
        local fallbackState = BElfVRDB.fallbackHumanoid and "ON" or "OFF"
        local targetState = BElfVRDB.playOnTarget and "ON" or "OFF"
        local invertState = BElfVRDB.invertSex and "ON" or "OFF"
        local suppressState = BElfVRDB.suppressNativeDialog and "ON" or "OFF"

        ui.statusText:SetText(
            "Mode: " .. (BElfVRDB.enabled and "Enabled" or "Disabled") ..
            "    Mute New Midnight VO: " .. muteState ..
            "\nFallback classifier: " .. fallbackState ..
            "    Left-click greet: " .. targetState ..
            "\nInvert sex mapping: " .. invertState ..
            "    Suppress native dialog: " .. suppressState ..
            "\nMuted new IDs: " .. stats.newCount ..
            "\nMale TBC pool: " .. stats.maleGreet .. " greet / " .. stats.maleBye .. " bye / " .. stats.malePissed .. " pissed" ..
            "\nFemale TBC pool: " .. stats.femaleGreet .. " greet / " .. stats.femaleBye .. " bye / " .. stats.femalePissed .. " pissed" ..
            "\nBehavior: replacement playback runs only while Midnight VO muting is active."
        )
    end

    if ui.musicStatusText then
        local musicStats = GetMusicStats()
        local musicMuteState = (BElfVRDB.enabled and BElfVRDB.musicEnabled and BElfVRDB.muteNewMusic) and "ACTIVE" or "INACTIVE"
        local musicVerboseState = BElfVRDB.musicVerbose and "ON" or "OFF"
        local introState = BElfVRDB.musicUseIntro and "ON" or "OFF"
        local traceState = BElfVRDB.musicTraceEnabled and "ON" or "OFF"
        local currentTrack = state.musicCurrentTrackID and tostring(state.musicCurrentTrackID) or "none"
        local currentPool = state.musicCurrentPool or "none"
        local traceCount = BElfVRDB.musicTraceLog and #BElfVRDB.musicTraceLog or 0

        ui.musicStatusText:SetText(
            "Music mode: " .. (BElfVRDB.musicEnabled and "Enabled" or "Disabled") ..
            "    Mute tracked Midnight music: " .. musicMuteState ..
            "\nMusic verbose: " .. musicVerboseState ..
            "    Use intro on fresh entry: " .. introState ..
            "\nMusic trace recorder: " .. traceState ..
            "    Trace lines stored: " .. traceCount ..
            "\nMuted Midnight music IDs: " .. musicStats.mutedCount ..
            "\nTBC music pools: " .. musicStats.introCount .. " intro / " .. musicStats.dayCount .. " day / " .. musicStats.nightCount .. " night" ..
            "\nRegional override IDs loaded: " .. musicStats.regionalCount ..
            "\nCurrent injected track: " .. currentTrack .. " (" .. currentPool .. ")" ..
            "\nBehavior: replacement music runs only while tracked Midnight music muting is active."
        )
    end
end

local function SetAddonEnabled(enabled)
    BElfVRDB.enabled = enabled and true or false

    if BElfVRDB.enabled then
        ApplyMutes()
        EvaluateMusicState("addon enabled", true)
    else
        RemoveMutes()
        ResetInteractionState()
        ResetMusicState(true)
    end

    RefreshUI()
end

local function SetMuteEnabled(enabled)
    BElfVRDB.muteNew = enabled and true or false

    if BElfVRDB.enabled and BElfVRDB.muteNew then
        if BElfVR_NewVoiceIDs then
            for _, id in ipairs(BElfVR_NewVoiceIDs) do
                MuteSoundFile(id)
            end
        end
    else
        if BElfVR_NewVoiceIDs then
            for _, id in ipairs(BElfVR_NewVoiceIDs) do
                UnmuteSoundFile(id)
            end
        end
        ResetInteractionState()
    end

    RefreshUI()
end

local function SetVerboseEnabled(enabled)
    BElfVRDB.verbose = enabled and true or false
    RefreshUI()
end

local function SetMusicEnabled(enabled)
    BElfVRDB.musicEnabled = enabled and true or false

    if BElfVRDB.enabled and BElfVRDB.musicEnabled then
        if BElfVRDB.muteNewMusic and BElfVR_NewMusicIDs then
            for _, id in ipairs(BElfVR_NewMusicIDs) do
                MuteSoundFile(id)
            end
        end
        EvaluateMusicState("music enabled", true)
    else
        if BElfVR_NewMusicIDs then
            for _, id in ipairs(BElfVR_NewMusicIDs) do
                UnmuteSoundFile(id)
            end
        end
        ResetMusicState(true)
    end

    RefreshUI()
end

local function SetMusicMuteEnabled(enabled)
    BElfVRDB.muteNewMusic = enabled and true or false

    if BElfVRDB.enabled and BElfVRDB.musicEnabled and BElfVRDB.muteNewMusic and BElfVR_NewMusicIDs then
        for _, id in ipairs(BElfVR_NewMusicIDs) do
            MuteSoundFile(id)
        end
        EvaluateMusicState("music mute enabled", true)
    else
        if BElfVR_NewMusicIDs then
            for _, id in ipairs(BElfVR_NewMusicIDs) do
                UnmuteSoundFile(id)
            end
        end
        ResetMusicState(true)
    end

    RefreshUI()
end

local function SetMusicVerboseEnabled(enabled)
    BElfVRDB.musicVerbose = enabled and true or false
    RefreshUI()
end

local function SetMusicTraceEnabled(enabled)
    BElfVRDB.musicTraceEnabled = enabled and true or false
    if BElfVRDB.musicTraceEnabled then
        RecordMusicTrace("Trace recording enabled.")
    end
    RefreshUI()
end

local function SetMusicUseIntroEnabled(enabled)
    BElfVRDB.musicUseIntro = enabled and true or false
    if BElfVRDB.musicUseIntro and state.musicWasInSupportedZone and not state.musicHandle then
        state.musicIntroPending = true
    end
    RefreshUI()
end

local function SetFallbackEnabled(enabled)
    BElfVRDB.fallbackHumanoid = enabled and true or false
    RefreshUI()
end

local function SetPlayOnTargetEnabled(enabled)
    BElfVRDB.playOnTarget = enabled and true or false
    RefreshUI()
end

local function SetInvertSexEnabled(enabled)
    BElfVRDB.invertSex = enabled and true or false
    RefreshUI()
end

local function SetSuppressNativeDialogEnabled(enabled)
    BElfVRDB.suppressNativeDialog = enabled and true or false

    if not BElfVRDB.suppressNativeDialog and state.dialogPrevEnabled and GetCVar("Sound_EnableDialog") ~= state.dialogPrevEnabled then
        SetCVar("Sound_EnableDialog", state.dialogPrevEnabled)
    end

    RefreshUI()
end

local function SetCurrentTargetGenderOverride(value)
    local guid = UnitGUID("target")
    if not guid then
        print("|cffFFD700[BElfVR]|r No valid NPC target selected.")
        return
    end

    BElfVRDB.guidGenderOverrides = BElfVRDB.guidGenderOverrides or {}

    if value == "male" or value == "female" then
        BElfVRDB.guidGenderOverrides[guid] = value
        print("|cffFFD700[BElfVR]|r guid=" .. guid .. " forced to |cffFFFFFF" .. value .. "|r voices.")
    else
        BElfVRDB.guidGenderOverrides[guid] = nil
        print("|cffFFD700[BElfVR]|r Cleared gender override for guid=" .. guid .. ".")
    end

    RefreshUI()
end

local function SetCurrentTargetRoleOverride(value)
    local guid = UnitGUID("target")
    if not guid then
        print("|cffFFD700[BElfVR]|r No valid NPC target selected.")
        return
    end

    BElfVRDB.guidRoleOverrides = BElfVRDB.guidRoleOverrides or {}

    if value == "military" or value == "noble" or value == "standard" then
        BElfVRDB.guidRoleOverrides[guid] = value
        print("|cffFFD700[BElfVR]|r guid=" .. guid .. " forced to |cffFFFFFF" .. value .. "|r role voices.")
    else
        BElfVRDB.guidRoleOverrides[guid] = nil
        print("|cffFFD700[BElfVR]|r Cleared role override for guid=" .. guid .. ".")
    end

    RefreshUI()
end

local function SetCurrentTargetNameGenderOverride(value)
    local name = UnitName("target")
    if not name then
        print("|cffFFD700[BElfVR]|r No valid NPC target selected.")
        return
    end

    local key = string.lower(name)
    BElfVRDB.nameGenderOverrides = BElfVRDB.nameGenderOverrides or {}

    if value == "male" or value == "female" then
        BElfVRDB.nameGenderOverrides[key] = value
        print("|cffFFD700[BElfVR]|r name=\"" .. name .. "\" forced to |cffFFFFFF" .. value .. "|r voices.")
    else
        BElfVRDB.nameGenderOverrides[key] = nil
        print("|cffFFD700[BElfVR]|r Cleared name gender override for \"" .. name .. "\".")
    end

    RefreshUI()
end

local function SetCurrentTargetNameRoleOverride(value)
    local name = UnitName("target")
    if not name then
        print("|cffFFD700[BElfVR]|r No valid NPC target selected.")
        return
    end

    local key = string.lower(name)
    BElfVRDB.nameRoleOverrides = BElfVRDB.nameRoleOverrides or {}

    if value == "military" or value == "noble" or value == "standard" then
        BElfVRDB.nameRoleOverrides[key] = value
        print("|cffFFD700[BElfVR]|r name=\"" .. name .. "\" forced to |cffFFFFFF" .. value .. "|r role voices.")
    else
        BElfVRDB.nameRoleOverrides[key] = nil
        print("|cffFFD700[BElfVR]|r Cleared name role override for \"" .. name .. "\".")
    end

    RefreshUI()
end

local function CreateCheckbox(parent, xOffset, yOffset, labelText, helpText, onClick)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    checkbox:SetScript("OnClick", onClick)
    checkbox:SetScript("OnEnter", function(self)
        ShowHelpTooltip(self, labelText, helpText)
    end)
    checkbox:SetScript("OnLeave", HideHelpTooltip)

    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", checkbox, "RIGHT", 4, 1)
    label:SetText(labelText)
    label:EnableMouse(true)
    label:SetScript("OnEnter", function()
        ShowHelpTooltip(checkbox, labelText, helpText)
    end)
    label:SetScript("OnLeave", HideHelpTooltip)

    return checkbox
end

local function CreateActionButton(parent, width, height, label, xOffset, yOffset, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    return button
end

local function CreateSectionFrame(parent)
    local section = CreateFrame("Frame", nil, parent)
    section:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -96)
    section:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 12)
    return section
end

local function SetSettingsTab(tabKey)
    if not ui.panel then
        return
    end

    ui.activeTab = tabKey

    if ui.voiceSection then
        ui.voiceSection:SetShown(tabKey == "voice")
    end
    if ui.musicSection then
        ui.musicSection:SetShown(tabKey == "music")
    end

    if ui.voiceTabButton then
        ui.voiceTabButton:SetEnabled(tabKey ~= "voice")
    end
    if ui.musicTabButton then
        ui.musicTabButton:SetEnabled(tabKey ~= "music")
    end
end

local function CreateSettingsUI()
    if ui.panel then
        return ui.panel
    end

    local panel = CreateFrame("Frame", "BElfVoiceRestoreUI", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(470, 760)
    panel:SetPoint("CENTER")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:Hide()
    tinsert(UISpecialFrames, panel:GetName())

    panel.TitleText:SetText("Blood Elf Voice Restore")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", 16, -34)
    subtitle:SetWidth(430)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Controls for restoring TBC Blood Elf voices and first-pass Silvermoon / Eversong music replacement.")

    ui.voiceTabButton = CreateActionButton(panel, 92, 22, "Voice", 16, -60, function()
        SetSettingsTab("voice")
    end)
    ui.musicTabButton = CreateActionButton(panel, 92, 22, "Music", 114, -60, function()
        SetSettingsTab("music")
    end)

    local voiceSection = CreateSectionFrame(panel)
    local musicSection = CreateSectionFrame(panel)
    ui.voiceSection = voiceSection
    ui.musicSection = musicSection

    ui.enabledCheckbox = CreateCheckbox(voiceSection, 2, -8, "Enable addon logic",
        "Turns the addon on or off. If this is off, the addon will not replace NPC voices or apply mutes.",
        function(self)
        SetAddonEnabled(self:GetChecked())
    end)

    ui.muteCheckbox = CreateCheckbox(voiceSection, 2, -36, "Mute new Midnight Blood Elf voice files",
        "Silences the tracked new Midnight Blood Elf voices so you hear the addon's replacement voices instead.",
        function(self)
        SetMuteEnabled(self:GetChecked())
    end)

    ui.verboseCheckbox = CreateCheckbox(voiceSection, 2, -64, "Verbose chat debug",
        "Shows detailed debug lines in chat. Turn this off for normal play.",
        function(self)
        SetVerboseEnabled(self:GetChecked())
    end)

    ui.fallbackCheckbox = CreateCheckbox(voiceSection, 2, -92, "Fallback: allow humanoid gossip NPCs if race is hidden",
        "If the game hides an NPC's race, the addon can still treat nearby humanoid NPCs as valid Blood Elf candidates.",
        function(self)
        SetFallbackEnabled(self:GetChecked())
    end)

    ui.targetCheckbox = CreateCheckbox(voiceSection, 2, -120, "Play greet on left-click target selection",
        "Plays a greeting when you left-click and target a supported NPC, even before opening gossip.",
        function(self)
        SetPlayOnTargetEnabled(self:GetChecked())
    end)

    ui.invertSexCheckbox = CreateCheckbox(voiceSection, 2, -148, "Invert NPC sex mapping (swap male/female VO)",
        "Swaps male and female voice selection. Use this if the game reports an NPC's sex backwards.",
        function(self)
        SetInvertSexEnabled(self:GetChecked())
    end)

    ui.suppressDialogCheckbox = CreateCheckbox(voiceSection, 2, -176, "Suppress native dialog during injected playback",
        "Temporarily blocks the game's normal NPC dialog for a moment while the addon plays a replacement line. This can stop double-talk on stubborn NPCs.",
        function(self)
        SetSuppressNativeDialogEnabled(self:GetChecked())
    end)

    local statusTitle = voiceSection:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    statusTitle:SetPoint("TOPLEFT", 6, -214)
    statusTitle:SetText("Status")

    ui.statusText = voiceSection:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ui.statusText:SetPoint("TOPLEFT", statusTitle, "BOTTOMLEFT", 0, -10)
    ui.statusText:SetWidth(430)
    ui.statusText:SetJustifyH("LEFT")
    ui.statusText:SetJustifyV("TOP")

    local testTitle = voiceSection:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    testTitle:SetPoint("TOPLEFT", 6, -336)
    testTitle:SetText("Test Playback")

    CreateActionButton(voiceSection, 140, 24, "M Noble Greet", 6, -360, function()
        PlayRandomTBC("male", "greet", "noble")
    end)
    CreateActionButton(voiceSection, 140, 24, "M Noble Bye", 152, -360, function()
        PlayRandomTBC("male", "bye", "noble")
    end)
    CreateActionButton(voiceSection, 140, 24, "M Noble Pissed", 298, -360, function()
        PlayRandomTBC("male", "pissed", "noble")
    end)
    CreateActionButton(voiceSection, 140, 24, "M Standard Greet", 6, -392, function()
        PlayRandomTBC("male", "greet", "standard")
    end)
    CreateActionButton(voiceSection, 140, 24, "M Standard Bye", 152, -392, function()
        PlayRandomTBC("male", "bye", "standard")
    end)
    CreateActionButton(voiceSection, 140, 24, "M Standard Pissed", 298, -392, function()
        PlayRandomTBC("male", "pissed", "standard")
    end)
    CreateActionButton(voiceSection, 140, 24, "M Military Greet", 6, -424, function()
        PlayRandomTBC("male", "greet", "military")
    end)
    CreateActionButton(voiceSection, 140, 24, "M Military Bye", 152, -424, function()
        PlayRandomTBC("male", "bye", "military")
    end)
    CreateActionButton(voiceSection, 140, 24, "M Military Pissed", 298, -424, function()
        PlayRandomTBC("male", "pissed", "military")
    end)
    CreateActionButton(voiceSection, 140, 24, "F Noble Greet", 6, -456, function()
        PlayRandomTBC("female", "greet", "noble")
    end)
    CreateActionButton(voiceSection, 140, 24, "F Noble Bye", 152, -456, function()
        PlayRandomTBC("female", "bye", "noble")
    end)
    CreateActionButton(voiceSection, 140, 24, "F Noble Pissed", 298, -456, function()
        PlayRandomTBC("female", "pissed", "noble")
    end)
    CreateActionButton(voiceSection, 140, 24, "F Standard Greet", 6, -488, function()
        PlayRandomTBC("female", "greet", "standard")
    end)
    CreateActionButton(voiceSection, 140, 24, "F Standard Bye", 152, -488, function()
        PlayRandomTBC("female", "bye", "standard")
    end)
    CreateActionButton(voiceSection, 140, 24, "F Standard Pissed", 298, -488, function()
        PlayRandomTBC("female", "pissed", "standard")
    end)
    CreateActionButton(voiceSection, 140, 24, "F Military Greet", 6, -520, function()
        PlayRandomTBC("female", "greet", "military")
    end)
    CreateActionButton(voiceSection, 140, 24, "F Military Bye", 152, -520, function()
        PlayRandomTBC("female", "bye", "military")
    end)
    CreateActionButton(voiceSection, 140, 24, "F Military Pissed", 298, -520, function()
        PlayRandomTBC("female", "pissed", "military")
    end)
    CreateActionButton(voiceSection, 212, 24, "Re-apply Mutes", 6, -560, function()
        SetMuteEnabled(true)
        if BElfVRDB.enabled then
            print("|cffFFD700[BElfVR]|r Mute option enabled and mutes applied.")
        else
            print("|cffFFD700[BElfVR]|r Mute option enabled. Mutes will apply when the addon is enabled.")
        end
    end)
    CreateActionButton(voiceSection, 212, 24, "Restore Midnight VO", 224, -560, function()
        SetMuteEnabled(false)
        print("|cffFFD700[BElfVR]|r Unmuted all tracked new voice IDs.")
    end)

    local musicTitle = musicSection:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    musicTitle:SetPoint("TOPLEFT", 6, -8)
    musicTitle:SetText("Music")

    ui.musicEnabledCheckbox = CreateCheckbox(musicSection, 2, -32, "Enable replacement music logic",
        "Turns the addon's music system on or off. This does not affect the voice system.",
        function(self)
        SetMusicEnabled(self:GetChecked())
    end)

    ui.musicMuteCheckbox = CreateCheckbox(musicSection, 2, -60, "Mute tracked Midnight Silvermoon music files",
        "Silences the currently tracked Midnight Silvermoon / Eversong music IDs so the addon's TBC music can replace them.",
        function(self)
        SetMusicMuteEnabled(self:GetChecked())
    end)

    ui.musicVerboseCheckbox = CreateCheckbox(musicSection, 2, -88, "Verbose music debug",
        "Shows zone, subzone, resting, and day/night routing in chat so you can map where Blizzard swaps music.",
        function(self)
        SetMusicVerboseEnabled(self:GetChecked())
    end)

    ui.musicTraceCheckbox = CreateCheckbox(musicSection, 2, -116, "Record music trace to SavedVariables",
        "Records music context and playback lines into the addon's SavedVariables data. Use /reload or log out before reading the saved file from disk.",
        function(self)
        SetMusicTraceEnabled(self:GetChecked())
    end)

    ui.musicIntroCheckbox = CreateCheckbox(musicSection, 2, -144, "Play intro cue on fresh entry",
        "When you enter Silvermoon City or Eversong Woods from outside the supported region, the addon can play the intro music before rotating into day or night tracks.",
        function(self)
        SetMusicUseIntroEnabled(self:GetChecked())
    end)

    local musicStatusTitle = musicSection:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    musicStatusTitle:SetPoint("TOPLEFT", 6, -182)
    musicStatusTitle:SetText("Music Status")

    ui.musicStatusText = musicSection:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ui.musicStatusText:SetPoint("TOPLEFT", musicStatusTitle, "BOTTOMLEFT", 0, -10)
    ui.musicStatusText:SetWidth(430)
    ui.musicStatusText:SetJustifyH("LEFT")
    ui.musicStatusText:SetJustifyV("TOP")

    CreateActionButton(musicSection, 140, 24, "Test Intro", 6, -300, function()
        local introPool = GetMusicTrackPool(MUSIC_REGION_SILVERMOON, "intro")
        local trackID = introPool and introPool[1]
        if trackID then
            PlayMusicTrack(trackID, "intro", "manual test")
            RefreshUI()
        end
    end)
    CreateActionButton(musicSection, 140, 24, "Test Day", 152, -300, function()
        local pool = GetMusicTrackPool(MUSIC_REGION_SILVERMOON, "day")
        local trackID = ChooseMusicTrack("day", pool)
        if trackID then
            PlayMusicTrack(trackID, "day", "manual test")
            RefreshUI()
        end
    end)
    CreateActionButton(musicSection, 140, 24, "Test Night", 298, -300, function()
        local pool = GetMusicTrackPool(MUSIC_REGION_SILVERMOON, "night")
        local trackID = ChooseMusicTrack("night", pool)
        if trackID then
            PlayMusicTrack(trackID, "night", "manual test")
            RefreshUI()
        end
    end)
    CreateActionButton(musicSection, 212, 24, "Re-apply Music Mutes", 6, -332, function()
        SetMusicMuteEnabled(true)
        if BElfVRDB.enabled and BElfVRDB.musicEnabled then
            print("|cff7FD4FF[BElfVR Music]|r Music mutes enabled and reapplied.")
        else
            print("|cff7FD4FF[BElfVR Music]|r Music mute option enabled. Mutes will apply when music logic is active.")
        end
    end)
    CreateActionButton(musicSection, 212, 24, "Clear Music Trace", 224, -332, function()
        BElfVRDB.musicTraceLog = {}
        if BElfVRDB.musicTraceEnabled then
            RecordMusicTrace("Trace log cleared.")
        end
        RefreshUI()
        print("|cff7FD4FF[BElfVR Music]|r Cleared the recorded music trace buffer.")
    end)
    CreateActionButton(musicSection, 212, 24, "Restore Midnight Music", 6, -364, function()
        SetMusicMuteEnabled(false)
        print("|cff7FD4FF[BElfVR Music]|r Unmuted all tracked Midnight music IDs.")
    end)
    CreateActionButton(musicSection, 212, 24, "Force Music Refresh", 224, -364, function()
        EvaluateMusicState("manual ui refresh", true)
        RefreshUI()
        print("|cff7FD4FF[BElfVR Music]|r Forced a music re-evaluation.")
    end)

    ui.panel = panel
    SetSettingsTab("voice")
    RefreshUI()

    return panel
end

local function ShowSettingsUI()
    local panel = CreateSettingsUI()
    RefreshUI()
    panel:Show()
    panel:Raise()
end


-- ============================================================
--  INTERACTION LOGIC
-- ============================================================

local function OnGossipShow()
    if not IsReplacementPlaybackActive() then return end

    local targetName = UnitName("target") or "<unknown>"
    local guid = UnitGUID("target")
    local npcID = GetNPCIDFromGUID(guid)
    local sex = UnitSex("target")

    Log("GOSSIP_SHOW target=" .. targetName ..
        " npc=" .. tostring(npcID or "?") ..
        " sex=" .. tostring(sex or "?") ..
        " guid=" .. tostring(guid or "?"))

    local gender = GetBloodElfNPCGender("target")
    if not gender then
        Log("Skipping playback because target did not resolve as a Blood Elf NPC with a usable sex.")
        state.lastNPCGender = nil
        state.lastNPCRole = nil
        return
    end

    local role = GetVoiceRole("target")
    local greetCategory = GetGreetingCategory("target")
    state.lastNPCGender = gender
    state.lastNPCRole = role
    state.lastNPCGreetCategory = greetCategory
    state.lastTargetName = targetName
    state.lastTargetRangeTier = "close"
    local now = GetTime()

    if guid == state.lastTargetChangeGUID and (now - state.lastTargetChangeTime) < 0.5 then
        Log("Skipping gossip greet because target-select greet already fired for npc=" .. tostring(npcID or "?"))
        state.lastClickTime = now
        return
    end

    local sameNPC = (guid == state.lastTargetGUID)
    local withinWindow = (now - state.lastClickTime) <= PISSED_CLICK_WINDOW

    if sameNPC and withinWindow then
        state.clickCount = state.clickCount + 1
        Log("Click count for this NPC: " .. state.clickCount)

        if state.clickCount >= PISSED_CLICK_THRESHOLD then
            Log("Triggering pissed line for target=" .. targetName .. " npc=" .. tostring(npcID or "?"))
            PlayRandomTBC(gender, "pissed", role, true)
            state.clickCount = 0
        end
    else
        state.clickCount = 1
        state.lastTargetGUID = guid
        state.lastGreetTime = now
        Log("Triggering " .. greetCategory .. " line for target=" .. targetName .. " npc=" .. tostring(npcID or "?"))
        PlayRandomTBC(gender, greetCategory, role, true)
    end

    state.lastClickTime = now
end

local function OnGossipClosed()
    if not IsReplacementPlaybackActive() then return end
    if not state.lastNPCGender then return end

    local timeSinceGreet = GetTime() - state.lastGreetTime
    if timeSinceGreet <= BYE_GRACE_PERIOD then
        Log("Triggering bye line for previous gossip target=" .. tostring(state.lastTargetName or "<unknown>") ..
            " npc=" .. tostring(GetNPCIDFromGUID(state.lastTargetGUID) or "?"))
        PlayRandomTBC(state.lastNPCGender, "bye", state.lastNPCRole, true)
    end

    state.lastTargetGUID = nil
    state.lastTargetName = nil
    state.lastNPCGender = nil
    state.lastNPCRole = nil
    state.lastNPCGreetCategory = nil
    state.lastTargetRangeTier = nil
end

local function OnTargetChanged()
    local newGUID = UnitGUID("target")

    if state.lastNPCGender and state.lastTargetGUID and newGUID ~= state.lastTargetGUID and not (GossipFrame and GossipFrame:IsShown()) then
        local elapsed = GetTime() - state.lastGreetTime
        if elapsed <= BYE_GRACE_PERIOD and elapsed >= TARGET_LOSS_BYE_DELAY then
            Log("Triggering target-loss bye for target=" .. tostring(state.lastTargetName or "<unknown>") ..
                " npc=" .. tostring(GetNPCIDFromGUID(state.lastTargetGUID) or "?"))
            PlayRandomTBC(state.lastNPCGender, "bye", state.lastNPCRole, true)
        elseif elapsed < TARGET_LOSS_BYE_DELAY then
            Log("Skipping target-loss bye for target=" .. tostring(state.lastTargetName or "<unknown>") ..
                " because target was not held long enough.")
        end
        state.lastNPCGender = nil
        state.lastNPCRole = nil
        state.lastNPCGreetCategory = nil
        state.lastTargetGUID = nil
        state.lastTargetName = nil
        state.lastTargetRangeTier = nil
        state.clickCount = 0
    end

    if not IsReplacementPlaybackActive() or not BElfVRDB.playOnTarget then
        return
    end

    local guid = newGUID
    if not guid then
        return
    end

    local rangeTier = GetUnitVORangeTier("target")
    if not rangeTier then
        Log("Skipping target-select greet because target is out of VO range.")
        return
    end

    if not ShouldPlayForRangeTier(rangeTier) then
        Log("Skipping target-select greet because range tier " .. rangeTier .. " did not pass the playback roll.")
        return
    end

    local now = GetTime()
    if guid == state.lastTargetChangeGUID and (now - state.lastTargetChangeTime) < 0.35 then
        return
    end

    local gender = GetBloodElfNPCGender("target", true)
    if not gender then
        return
    end

    local role = GetVoiceRole("target")
    local greetCategory = GetGreetingCategory("target")
    local npcID = GetNPCIDFromGUID(guid)
    local targetName = UnitName("target") or "<unknown>"
    state.lastNPCGender = gender
    state.lastNPCRole = role
    state.lastNPCGreetCategory = greetCategory
    state.lastTargetGUID = guid
    state.lastTargetName = targetName
    state.lastTargetRangeTier = rangeTier
    state.lastGreetTime = now
    state.lastClickTime = now
    state.clickCount = 1
    state.lastTargetChangeGUID = guid
    state.lastTargetChangeTime = now

    Log("Triggering target-select " .. greetCategory .. " for target=" .. targetName ..
        " npc=" .. tostring(npcID or "?"))
    PlayRandomTBC(gender, greetCategory, role, true)
end


-- ============================================================
--  EVENT FRAME
-- ============================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("GOSSIP_SHOW")
frame:RegisterEvent("GOSSIP_CLOSED")
frame:RegisterEvent("ZONE_CHANGED")
frame:RegisterEvent("ZONE_CHANGED_INDOORS")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("PLAYER_UPDATE_RESTING")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end

        BElfVRDB = BElfVRDB or {}
        for key, value in pairs(DB_DEFAULTS) do
            if BElfVRDB[key] == nil then
                BElfVRDB[key] = value
            end
        end
        MigrateSavedVariables()

    elseif event == "PLAYER_LOGIN" then
        CreateSettingsUI()
        ApplyMutes()
        RefreshUI()
        print("|cffFFD700[BElfVoiceRestore]|r Loaded. Type |cffFFFFFF/belvr|r to open the UI.")

    elseif event == "PLAYER_ENTERING_WORLD" then
        EvaluateMusicState("entering world", true)
        RefreshUI()

    elseif event == "PLAYER_TARGET_CHANGED" then
        OnTargetChanged()

    elseif event == "GOSSIP_SHOW" then
        OnGossipShow()

    elseif event == "GOSSIP_CLOSED" then
        OnGossipClosed()

    elseif event == "ZONE_CHANGED" or
           event == "ZONE_CHANGED_INDOORS" or
           event == "ZONE_CHANGED_NEW_AREA" or
           event == "PLAYER_UPDATE_RESTING" then
        -- Let the music logic decide whether a real playback refresh
        -- is warranted. These events still update trace logs, but we
        -- should not hard-refresh the track on every tiny subzone or
        -- resting flag flip.
        EvaluateMusicState(event, false)
        RefreshUI()
    end
end)

frame:SetScript("OnUpdate", function(self, elapsed)
    if not BElfVRDB then
        return
    end
    if not IsMusicReplacementActive() then
        return
    end

    state.musicUpdateAccumulator = (state.musicUpdateAccumulator or 0) + elapsed
    if state.musicUpdateAccumulator < MUSIC_UPDATE_INTERVAL then
        return
    end

    state.musicUpdateAccumulator = 0
    EvaluateMusicState("periodic", false)
    if ui.panel and ui.panel:IsShown() then
        RefreshUI()
    end
end)


-- ============================================================
--  SLASH COMMANDS
-- ============================================================

SLASH_BELVR1 = "/belvr"

SlashCmdList["BELVR"] = function(input)
    local cmd = strtrim((input or ""):lower())

    if cmd == "" or cmd == "ui" or cmd == "config" or cmd == "options" or cmd == "show" then
        ShowSettingsUI()

    elseif cmd == "on" then
        SetAddonEnabled(true)
        print("|cffFFD700[BElfVR]|r |cff00FF00Enabled.|r")

    elseif cmd == "off" then
        SetAddonEnabled(false)
        print("|cffFFD700[BElfVR]|r |cffFF4444Disabled.|r Mutes removed.")

    elseif cmd == "mute on" then
        SetMuteEnabled(true)
        print("|cffFFD700[BElfVR]|r New voice muting: |cff00FF00ON|r")

    elseif cmd == "mute off" then
        SetMuteEnabled(false)
        print("|cffFFD700[BElfVR]|r New voice muting: |cffFF4444OFF|r")

    elseif cmd == "verbose on" then
        SetVerboseEnabled(true)
        print("|cffFFD700[BElfVR]|r Verbose mode: |cff00FF00ON|r")

    elseif cmd == "verbose off" then
        SetVerboseEnabled(false)
        print("|cffFFD700[BElfVR]|r Verbose mode: |cffFF4444OFF|r")

    elseif cmd == "verbose" then
        SetVerboseEnabled(not BElfVRDB.verbose)
        print("|cffFFD700[BElfVR]|r Verbose mode: " ..
            (BElfVRDB.verbose and "|cff00FF00ON|r" or "|cffFF4444OFF|r"))

    elseif cmd == "music on" then
        SetMusicEnabled(true)
        if BElfVRDB.enabled then
            print("|cff7FD4FF[BElfVR Music]|r |cff00FF00Enabled.|r")
        else
            print("|cff7FD4FF[BElfVR Music]|r |cff00FF00Armed.|r The music system will stay idle until the main addon is enabled.")
        end

    elseif cmd == "music off" then
        SetMusicEnabled(false)
        print("|cff7FD4FF[BElfVR Music]|r |cffFF4444Disabled.|r")

    elseif cmd == "music mute on" then
        SetMusicMuteEnabled(true)
        print("|cff7FD4FF[BElfVR Music]|r Tracked Midnight music muting: |cff00FF00ON|r")

    elseif cmd == "music mute off" then
        SetMusicMuteEnabled(false)
        print("|cff7FD4FF[BElfVR Music]|r Tracked Midnight music muting: |cffFF4444OFF|r")

    elseif cmd == "music verbose on" then
        SetMusicVerboseEnabled(true)
        print("|cff7FD4FF[BElfVR Music]|r Verbose music debug: |cff00FF00ON|r")

    elseif cmd == "music verbose off" then
        SetMusicVerboseEnabled(false)
        print("|cff7FD4FF[BElfVR Music]|r Verbose music debug: |cffFF4444OFF|r")

    elseif cmd == "music verbose" then
        SetMusicVerboseEnabled(not BElfVRDB.musicVerbose)
        print("|cff7FD4FF[BElfVR Music]|r Verbose music debug: " ..
            (BElfVRDB.musicVerbose and "|cff00FF00ON|r" or "|cffFF4444OFF|r"))

    elseif cmd == "music trace on" then
        SetMusicTraceEnabled(true)
        print("|cff7FD4FF[BElfVR Music]|r Music trace recording: |cff00FF00ON|r")
        print("|cff7FD4FF[BElfVR Music]|r The trace is saved to SavedVariables on |cffFFFFFF/reload|r or logout.")

    elseif cmd == "music trace off" then
        SetMusicTraceEnabled(false)
        print("|cff7FD4FF[BElfVR Music]|r Music trace recording: |cffFF4444OFF|r")

    elseif cmd == "music trace clear" then
        BElfVRDB.musicTraceLog = {}
        if BElfVRDB.musicTraceEnabled then
            RecordMusicTrace("Trace log cleared.")
        end
        RefreshUI()
        print("|cff7FD4FF[BElfVR Music]|r Cleared the recorded music trace buffer.")

    elseif cmd == "music intro on" then
        SetMusicUseIntroEnabled(true)
        print("|cff7FD4FF[BElfVR Music]|r Intro-on-entry: |cff00FF00ON|r")

    elseif cmd == "music intro off" then
        SetMusicUseIntroEnabled(false)
        print("|cff7FD4FF[BElfVR Music]|r Intro-on-entry: |cffFF4444OFF|r")

    elseif cmd == "music now" then
        EvaluateMusicState("manual refresh", true)
        RefreshUI()
        print("|cff7FD4FF[BElfVR Music]|r Forced a music re-evaluation.")

    elseif cmd == "fallback on" then
        SetFallbackEnabled(true)
        print("|cffFFD700[BElfVR]|r Fallback classifier: |cff00FF00ON|r")

    elseif cmd == "fallback off" then
        SetFallbackEnabled(false)
        print("|cffFFD700[BElfVR]|r Fallback classifier: |cffFF4444OFF|r")

    elseif cmd == "target on" then
        SetPlayOnTargetEnabled(true)
        print("|cffFFD700[BElfVR]|r Left-click greet: |cff00FF00ON|r")

    elseif cmd == "target off" then
        SetPlayOnTargetEnabled(false)
        print("|cffFFD700[BElfVR]|r Left-click greet: |cffFF4444OFF|r")

    elseif cmd == "invert on" then
        SetInvertSexEnabled(true)
        print("|cffFFD700[BElfVR]|r Invert NPC sex mapping: |cff00FF00ON|r")

    elseif cmd == "invert off" then
        SetInvertSexEnabled(false)
        print("|cffFFD700[BElfVR]|r Invert NPC sex mapping: |cffFF4444OFF|r")

    elseif cmd == "invert" then
        SetInvertSexEnabled(not BElfVRDB.invertSex)
        print("|cffFFD700[BElfVR]|r Invert NPC sex mapping: " ..
            (BElfVRDB.invertSex and "|cff00FF00ON|r" or "|cffFF4444OFF|r"))

    elseif cmd == "suppress on" then
        SetSuppressNativeDialogEnabled(true)
        print("|cffFFD700[BElfVR]|r Native dialog suppression: |cff00FF00ON|r")

    elseif cmd == "suppress off" then
        SetSuppressNativeDialogEnabled(false)
        print("|cffFFD700[BElfVR]|r Native dialog suppression: |cffFF4444OFF|r")

    elseif cmd == "suppress" then
        SetSuppressNativeDialogEnabled(not BElfVRDB.suppressNativeDialog)
        print("|cffFFD700[BElfVR]|r Native dialog suppression: " ..
            (BElfVRDB.suppressNativeDialog and "|cff00FF00ON|r" or "|cffFF4444OFF|r"))

    elseif cmd == "force male" then
        SetCurrentTargetGenderOverride("male")

    elseif cmd == "force female" then
        SetCurrentTargetGenderOverride("female")

    elseif cmd == "force clear" then
        SetCurrentTargetGenderOverride(nil)

    elseif cmd == "force-name male" then
        SetCurrentTargetNameGenderOverride("male")

    elseif cmd == "force-name female" then
        SetCurrentTargetNameGenderOverride("female")

    elseif cmd == "force-name clear" then
        SetCurrentTargetNameGenderOverride(nil)

    elseif cmd == "role military" then
        SetCurrentTargetRoleOverride("military")

    elseif cmd == "role noble" then
        SetCurrentTargetRoleOverride("noble")

    elseif cmd == "role standard" then
        SetCurrentTargetRoleOverride("standard")

    elseif cmd == "role clear" then
        SetCurrentTargetRoleOverride(nil)

    elseif cmd == "role-name military" then
        SetCurrentTargetNameRoleOverride("military")

    elseif cmd == "role-name noble" then
        SetCurrentTargetNameRoleOverride("noble")

    elseif cmd == "role-name standard" then
        SetCurrentTargetNameRoleOverride("standard")

    elseif cmd == "role-name clear" then
        SetCurrentTargetNameRoleOverride(nil)

    elseif cmd == "status" then
        local stats = GetVoiceStats()
        local musicStats = GetMusicStats()
        print("|cffFFD700[BElfVR]|r --- Status ---")
        print("  Addon enabled    : " .. tostring(BElfVRDB.enabled))
        print("  Muting new VO    : " .. tostring(BElfVRDB.muteNew))
        print("  Verbose mode     : " .. tostring(BElfVRDB.verbose))
        print("  Fallback mode    : " .. tostring(BElfVRDB.fallbackHumanoid))
        print("  Left-click greet : " .. tostring(BElfVRDB.playOnTarget))
        print("  Invert sex map   : " .. tostring(BElfVRDB.invertSex))
        print("  Suppress dialog  : " .. tostring(BElfVRDB.suppressNativeDialog))
        print("  DB schema        : " .. tostring(BElfVRDB.schemaVersion))
        print("  New IDs loaded   : " .. stats.newCount)
        print("  TBC male   : " .. stats.maleGreet .. " greet / " .. stats.maleBye .. " bye / " .. stats.malePissed .. " pissed")
        print("  TBC female : " .. stats.femaleGreet .. " greet / " .. stats.femaleBye .. " bye / " .. stats.femalePissed .. " pissed")
        print("  Music enabled    : " .. tostring(BElfVRDB.musicEnabled))
        print("  Muting new music : " .. tostring(BElfVRDB.muteNewMusic))
        print("  Music verbose    : " .. tostring(BElfVRDB.musicVerbose))
        print("  Music intro      : " .. tostring(BElfVRDB.musicUseIntro))
        print("  Music muted IDs  : " .. musicStats.mutedCount)
        print("  TBC music  : " .. musicStats.introCount .. " intro / " .. musicStats.dayCount .. " day / " .. musicStats.nightCount .. " night")
        print("  Current music    : " .. tostring(state.musicCurrentTrackID or "none") .. " (" .. tostring(state.musicCurrentPool or "none") .. ")")
        print("  Music trace on   : " .. tostring(BElfVRDB.musicTraceEnabled))
        print("  Trace lines      : " .. tostring(BElfVRDB.musicTraceLog and #BElfVRDB.musicTraceLog or 0))

    elseif cmd == "test male greet" then
        PlayRandomTBC("male", "greet")
    elseif cmd == "test male bye" then
        PlayRandomTBC("male", "bye")
    elseif cmd == "test male pissed" then
        PlayRandomTBC("male", "pissed")
    elseif cmd == "test female greet" then
        PlayRandomTBC("female", "greet")
    elseif cmd == "test female bye" then
        PlayRandomTBC("female", "bye")
    elseif cmd == "test female pissed" then
        PlayRandomTBC("female", "pissed")
    elseif cmd == "test music intro" then
        local context = GetMusicContext()
        local pool = GetMusicTrackPool(context.regionKey or MUSIC_REGION_SILVERMOON, "intro")
        local trackID = pool and pool[1]
        if trackID then
            PlayMusicTrack(trackID, "intro", "manual slash test")
            RefreshUI()
        end
    elseif cmd == "test music day" then
        local context = GetMusicContext()
        local pool = GetMusicTrackPool(context.regionKey or MUSIC_REGION_SILVERMOON, "day")
        local trackID = ChooseMusicTrack("day", pool)
        if trackID then
            PlayMusicTrack(trackID, "day", "manual slash test")
            RefreshUI()
        end
    elseif cmd == "test music night" then
        local context = GetMusicContext()
        local pool = GetMusicTrackPool(context.regionKey or MUSIC_REGION_SILVERMOON, "night")
        local trackID = ChooseMusicTrack("night", pool)
        if trackID then
            PlayMusicTrack(trackID, "night", "manual slash test")
            RefreshUI()
        end
    elseif cmd == "music stop" then
        ResetMusicState(true)
        state.musicManualStop = true
        RefreshUI()
        print("|cff7FD4FF[BElfVR Music]|r Stopped injected music. Playback will stay idle until you move to a new area, re-enable WoW music, or force a refresh.")

    else
        print("|cffFFD700[BElfVR]|r Commands:")
        print("  |cffFFFFFF/belvr|r                                 open the UI")
        print("  |cffFFFFFF/belvr on|r / |cffFFFFFF/belvr off|r    enable or disable the addon")
        print("  |cffFFFFFF/belvr mute on|r / |cffFFFFFF/belvr mute off|r")
        print("                                              toggle muting of new voices")
        print("  |cffFFFFFF/belvr verbose|r / |cffFFFFFF/belvr verbose on|r / |cffFFFFFF/belvr verbose off|r")
        print("                                              toggle or set debug output in chat")
        print("  |cffFFFFFF/belvr music on|r / |cffFFFFFF/belvr music off|r")
        print("                                              enable or disable the music replacement system")
        print("  |cffFFFFFF/belvr music mute on|r / |cffFFFFFF/belvr music mute off|r")
        print("                                              toggle muting of tracked Midnight music IDs")
        print("  |cffFFFFFF/belvr music verbose|r / |cffFFFFFF/belvr music verbose on|r / |cffFFFFFF/belvr music verbose off|r")
        print("                                              toggle or set music routing debug output in chat")
        print("  |cffFFFFFF/belvr music trace on|r / |cffFFFFFF/belvr music trace off|r / |cffFFFFFF/belvr music trace clear|r")
        print("                                              record music routing lines into SavedVariables for later review")
        print("  |cffFFFFFF/belvr music intro on|r / |cffFFFFFF/belvr music intro off|r")
        print("                                              toggle the intro cue when entering the supported region")
        print("  |cffFFFFFF/belvr music now|r / |cffFFFFFF/belvr music stop|r")
        print("                                              force a music re-check or stop injected music")
        print("  |cffFFFFFF/belvr fallback on|r / |cffFFFFFF/belvr fallback off|r")
        print("                                              allow humanoid NPC fallback when race is hidden")
        print("  |cffFFFFFF/belvr target on|r / |cffFFFFFF/belvr target off|r")
        print("                                              toggle greet playback on left-click target")
        print("  |cffFFFFFF/belvr invert|r / |cffFFFFFF/belvr invert on|r / |cffFFFFFF/belvr invert off|r")
        print("                                              toggle or set the reversed NPC sex mapping")
        print("  |cffFFFFFF/belvr suppress|r / |cffFFFFFF/belvr suppress on|r / |cffFFFFFF/belvr suppress off|r")
        print("                                              toggle or set native dialog suppression during injected playback")
        print("  |cffFFFFFF/belvr force male|r / |cffFFFFFF/belvr force female|r / |cffFFFFFF/belvr force clear|r")
        print("                                              override only the current target's exact NPC GUID")
        print("  |cffFFFFFF/belvr force-name male|r / |cffFFFFFF/belvr force-name female|r / |cffFFFFFF/belvr force-name clear|r")
        print("                                              override all matching NPCs by the current target's name")
        print("  |cffFFFFFF/belvr role military|r / |cffFFFFFF/belvr role noble|r / |cffFFFFFF/belvr role standard|r / |cffFFFFFF/belvr role clear|r")
        print("                                              override only the current target's exact NPC GUID")
        print("  |cffFFFFFF/belvr role-name military|r / |cffFFFFFF/belvr role-name noble|r / |cffFFFFFF/belvr role-name standard|r / |cffFFFFFF/belvr role-name clear|r")
        print("                                              override all matching NPCs by the current target's name")
        print("  |cffFFFFFF/belvr status|r                          show current state and loaded sound counts")
        print("  |cffFFFFFF/belvr test male greet|r / |cffFFFFFF/belvr test male bye|r / |cffFFFFFF/belvr test male pissed|r")
        print("  |cffFFFFFF/belvr test female greet|r / |cffFFFFFF/belvr test female bye|r / |cffFFFFFF/belvr test female pissed|r")
        print("  |cffFFFFFF/belvr test music intro|r / |cffFFFFFF/belvr test music day|r / |cffFFFFFF/belvr test music night|r")
    end
end
