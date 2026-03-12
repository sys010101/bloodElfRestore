-- ============================================================
--  BElfRestore - BElfRestore.lua
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
local DB_SCHEMA_VERSION = 4

local LogMusic
local RecordMusicTrace
local RestoreInterruptedTemporaryCVars
local RegionalMusicMuteIDs = (_G and rawget(_G, "BElfVR_RegionalMusicMuteIDs")) or {}

-- ============================================================
--  CONFIG HELPERS
--  `Config.lua` is the user-editable policy layer. The runtime keeps
--  defensive fallbacks so one bad edit does not instantly brick the
--  addon.
-- ============================================================
function GetUserConfigRoot()
    return type(BElfVR_Config) == "table" and BElfVR_Config or nil
end

function GetConfigValue(...)
    local node = GetUserConfigRoot()
    for i = 1, select("#", ...) do
        if type(node) ~= "table" then
            return nil
        end
        node = node[select(i, ...)]
    end
    return node
end

function NormalizeUserConfigKey(value)
    if type(value) ~= "string" then
        return nil
    end

    local normalized = strtrim(string.lower(value))
    if normalized == "" then
        return nil
    end

    return normalized
end

function GetConfigBoolean(defaultValue, ...)
    local value = GetConfigValue(...)
    if type(value) == "boolean" then
        return value
    end
    return defaultValue
end

function GetConfigNumber(defaultValue, ...)
    local value = tonumber(GetConfigValue(...))
    if value == nil then
        return defaultValue
    end
    return value
end

function GetConfigInteger(defaultValue, ...)
    local value = tonumber(GetConfigValue(...))
    if value == nil then
        return defaultValue
    end
    return math.floor(value + 0.5)
end

function GetConfigString(defaultValue, ...)
    local value = GetConfigValue(...)
    if type(value) == "string" and value ~= "" then
        return value
    end
    return defaultValue
end

function BuildNormalizedStringSet(source)
    local set = {}
    if type(source) ~= "table" then
        return set
    end

    for key, value in pairs(source) do
        local normalized = nil
        if type(key) == "number" then
            normalized = NormalizeUserConfigKey(value)
        elseif value == true then
            normalized = NormalizeUserConfigKey(key)
        end

        if normalized then
            set[normalized] = true
        end
    end

    return set
end

function BuildNormalizedStringList(source)
    local list = {}
    local seen = {}
    if type(source) ~= "table" then
        return list
    end

    local function remember(value)
        local normalized = NormalizeUserConfigKey(value)
        if normalized and not seen[normalized] then
            seen[normalized] = true
            list[#list + 1] = normalized
        end
    end

    for key, value in pairs(source) do
        if type(key) == "number" then
            remember(value)
        elseif value == true then
            remember(key)
        end
    end

    return list
end

function BuildNormalizedStringMap(source, valueNormalizer)
    local map = {}
    if type(source) ~= "table" then
        return map
    end

    for key, value in pairs(source) do
        local normalizedKey = NormalizeUserConfigKey(key)
        local normalizedValue = valueNormalizer and valueNormalizer(value) or NormalizeUserConfigKey(value)
        if normalizedKey and normalizedValue then
            map[normalizedKey] = normalizedValue
        end
    end

    return map
end

function BuildNormalizedNPCOverrideMap(source, allowedValues)
    local map = {}
    if type(source) ~= "table" then
        return map
    end

    for key, value in pairs(source) do
        local npcID = nil
        if type(key) == "number" then
            npcID = tostring(math.floor(key + 0.5))
        elseif type(key) == "string" and key ~= "" then
            npcID = tostring(key)
        end

        if npcID and allowedValues[value] then
            map[npcID] = value
        end
    end

    return map
end

function BuildNormalizedNameProfileMap(source)
    local map = {}
    if type(source) ~= "table" then
        return map
    end

    for key, value in pairs(source) do
        local normalizedName = NormalizeUserConfigKey(key)
        if normalizedName and type(value) == "table" then
            local profile = {}
            if value.role == "military" or value.role == "noble" or value.role == "standard" then
                profile.role = value.role
            end
            if value.vendor == true then
                profile.vendor = true
            end
            if value.exclude == true then
                profile.exclude = true
            end

            if next(profile) ~= nil then
                map[normalizedName] = profile
            end
        end
    end

    return map
end

-- ============================================================
--  EFFECTIVE CONFIGURED POLICY
--  These locals are the runtime-facing values after Config.lua was
--  parsed and sanitized.
-- ============================================================
PISSED_CLICK_THRESHOLD = GetConfigInteger(3, "voice", "behavior", "pissedClickThreshold")
PISSED_CLICK_WINDOW = GetConfigNumber(4, "voice", "behavior", "pissedClickWindowSeconds")
BYE_GRACE_PERIOD = GetConfigNumber(60, "voice", "behavior", "byeGracePeriodSeconds")
TARGET_LOSS_BYE_DELAY = GetConfigNumber(1.6, "voice", "behavior", "targetLossByeDelaySeconds")
TARGET_LOSS_BYE_MAX_AGE = math.max(
    TARGET_LOSS_BYE_DELAY,
    GetConfigNumber(4.0, "voice", "behavior", "targetLossByeMaxAgeSeconds")
)
MIN_PLAYBACK_GAP = GetConfigNumber(1.25, "voice", "behavior", "minPlaybackGapSeconds")
DIALOG_SUPPRESSION_WINDOW = GetConfigNumber(0.4, "voice", "behavior", "dialogSuppressionWindowSeconds")
RANGE_TIER_NEAR_CHANCE = GetConfigNumber(0.65, "voice", "behavior", "rangeTierNearChance")
RANGE_TIER_FAR_CHANCE = GetConfigNumber(0.25, "voice", "behavior", "rangeTierFarChance")
TARGET_SELECT_DEDUPE_WINDOW = GetConfigNumber(0.35, "voice", "behavior", "targetSelectDedupeWindowSeconds")

BLOOD_ELF_FALLBACK_ZONES = BuildNormalizedStringSet(
    GetConfigValue("voice", "scope", "fallbackZones") or {
        "silvermoon city",
        "eversong woods",
        "sunstrider isle",
        "ghostlands",
        "sanctum of light",
        "the bazaar",
    }
)

BLOOD_ELF_VOICE_SCOPE_TOKENS = BuildNormalizedStringSet(
    GetConfigValue("voice", "scope", "scopeTokens") or {
        "silvermooncity",
        "eversongwoods",
        "ghostlands",
        "sunstriderisle",
        "sanctumoflight",
    }
)

BLOOD_ELF_VOICE_NATIVE_ONLY_TOKENS = BuildNormalizedStringList(
    GetConfigValue("voice", "scope", "nativeOnlyTokens") or {
        "harandar",
    }
)

BLOOD_ELF_TOOLTIP_RACE_TOKENS = BuildNormalizedStringList(
    GetConfigValue("voice", "classification", "tooltipBloodElfRaceTokens") or {
        "blood elf",
        "sin'dorei",
    }
)

BLOOD_ELF_TOOLTIP_CHILD_TOKENS = BuildNormalizedStringList(
    GetConfigValue("voice", "classification", "tooltipChildTokens") or {
        "child",
    }
)

CHILD_NAME_TOKENS = BuildNormalizedStringList(
    GetConfigValue("voice", "classification", "childNameTokens") or {
        "child",
        "orphan",
    }
)

BLOOD_ELF_HIDDEN_RACE_NAME_TOKENS = BuildNormalizedStringList(
    GetConfigValue("voice", "classification", "hiddenRaceNameTokens") or {
        "silvermoon",
        "sindorei",
        "farstrider",
        "magister",
        "spellbreaker",
        "bloodknight",
    }
)

KNOWN_NON_BLOOD_ELF_RACE_TOKENS = BuildNormalizedStringList(
    GetConfigValue("voice", "classification", "knownNonBloodElfRaceTokens") or {
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
    }
)

MILITARY_ROLE_NAME_TOKENS = BuildNormalizedStringList(
    GetConfigValue("voice", "roleHeuristics", "militaryNameTokens") or {
        "guard",
        "ranger",
        "captain",
        "blood knight",
        "champion",
    }
)

NOBLE_ROLE_NAME_TOKENS = BuildNormalizedStringList(
    GetConfigValue("voice", "roleHeuristics", "nobleNameTokens") or {
        "lord",
        "lady",
        "noble",
    }
)

MUSIC_UPDATE_INTERVAL = GetConfigNumber(1.0, "music", "timing", "updateIntervalSeconds")
MUSIC_TRACK_ROTATE_SECONDS = GetConfigNumber(85, "music", "timing", "trackRotateSeconds")
MUSIC_REPEAT_COOLDOWN = GetConfigNumber(180, "music", "timing", "repeatCooldownSeconds")
MUSIC_INTRO_REPEAT_COOLDOWN = 600
MUSIC_TRANSITION_FADE_MS = GetConfigInteger(900, "music", "timing", "transitionFadeMS")
MUSIC_FORCE_STOP_NATIVE_BEFORE_REPLACEMENT = GetConfigBoolean(true, "music", "playback", "forceStopNativeBeforeReplacement")
MUSIC_NATIVE_GUARD_INTERVAL = GetConfigNumber(0.25, "music", "playback", "nativeGuardIntervalSeconds")
MUSIC_PLAYBACK_CHANNEL = GetConfigString("Music", "music", "playback", "playbackChannel")
MUSIC_SUPPRESS_NATIVE_WITH_VOLUME = GetConfigBoolean(false, "music", "playback", "suppressNativeWithVolume")
MUSIC_NATIVE_SUPPRESS_VOLUME = GetConfigNumber(0, "music", "playback", "nativeSuppressVolume")
MUSIC_END_GRACE_SECONDS = GetConfigNumber(0.5, "music", "timing", "endGraceSeconds")
MUSIC_DAY_START_HOUR = GetConfigInteger(6, "music", "dayNightHours", "dayStartHour")
MUSIC_NIGHT_START_HOUR = GetConfigInteger(18, "music", "dayNightHours", "nightStartHour")
MUSIC_STARTUP_PURGE_DELAY_SECONDS = GetConfigNumber(0.35, "music", "playback", "startupPurgeDelaySeconds")
MUSIC_WORLD_ENTRY_SETTLE_SECONDS = GetConfigNumber(0.85, "music", "playback", "worldEntrySettleSeconds")
MUSIC_TRACE_MAX_ENTRIES = GetConfigInteger(1200, "music", "debug", "traceMaxEntries")

BLOOD_ELF_MUSIC_ZONES = BuildNormalizedStringSet(
    GetConfigValue("music", "scope", "supportedZones") or {
        "silvermoon city",
        "eversong woods",
        "sanctum of light",
    }
)

BLOOD_ELF_MUSIC_SUBZONES = BuildNormalizedStringSet(
    GetConfigValue("music", "scope", "supportedSubZones") or {
        "the bazaar",
    }
)

BLOOD_ELF_MUSIC_NATIVE_ONLY_TOKENS = BuildNormalizedStringList(
    GetConfigValue("music", "scope", "nativeOnlyTokens") or {
        "harandar",
    }
)

BLOOD_ELF_MUSIC_SCOPE_TOKENS = BuildNormalizedStringSet(
    GetConfigValue("music", "scope", "scopeTokens") or {
        "quelthalas",
        "silvermooncity",
        "eversongwoods",
        "ghostlands",
        "sunstriderisle",
        "sanctumoflight",
    }
)

UI_ART_PATH = GetConfigString("Interface\\AddOns\\bloodElfRestore\\assets\\tbc_art", "ui", "art", "texturePath")
UI_ART_PATH_WITH_EXT = GetConfigString("Interface\\AddOns\\bloodElfRestore\\assets\\tbc_art.jpg", "ui", "art", "fallbackTexturePath")
UI_ART_ASPECT_RATIO = GetConfigNumber(16 / 10, "ui", "art", "aspectRatio")
UI_ART_ALPHA = GetConfigNumber(0.10, "ui", "art", "alpha")
UI_ART_FIT_BLEND = GetConfigNumber(1.0, "ui", "art", "fitBlend")
UI_ART_SCALE_X = GetConfigNumber(1.0, "ui", "art", "scaleX")
UI_ART_SCALE_Y = GetConfigNumber(1.0, "ui", "art", "scaleY")
UI_ART_MARGIN_LEFT = GetConfigInteger(12, "ui", "art", "margins", "left")
UI_ART_MARGIN_RIGHT = GetConfigInteger(12, "ui", "art", "margins", "right")
UI_ART_MARGIN_TOP = GetConfigInteger(50, "ui", "art", "margins", "top")
UI_ART_MARGIN_BOTTOM = GetConfigInteger(12, "ui", "art", "margins", "bottom")
SETTINGS_UI_WIDTH = GetConfigInteger(550, "ui", "layout", "windowWidth")
SETTINGS_UI_HEIGHT = GetConfigInteger(750, "ui", "layout", "windowHeight")
SETTINGS_CONTENT_WIDTH = GetConfigInteger(446, "ui", "layout", "contentWidth")
SETTINGS_CONTENT_SIDE_MARGIN = math.floor((SETTINGS_UI_WIDTH - SETTINGS_CONTENT_WIDTH) * 0.5)
SETTINGS_TAB_BUTTON_WIDTH = GetConfigInteger(92, "ui", "layout", "tabButtonWidth")
SETTINGS_TAB_BUTTON_HEIGHT = GetConfigInteger(22, "ui", "layout", "tabButtonHeight")
SETTINGS_TAB_BUTTON_GAP = GetConfigInteger(6, "ui", "layout", "tabButtonGap")
SETTINGS_TAB_GROUP_WIDTH = (SETTINGS_TAB_BUTTON_WIDTH * 2) + SETTINGS_TAB_BUTTON_GAP
SETTINGS_TAB_START_X = math.floor((SETTINGS_UI_WIDTH - SETTINGS_TAB_GROUP_WIDTH) * 0.5)

-- Broad music families. These are what the actual playback logic
-- should react to. Fine-grained subzones are still logged for
-- mapping, but they should not constantly restart the same track
-- while you move around inside one logical music region.
MUSIC_REGION_SILVERMOON = "silvermoon"
MUSIC_REGION_SILVERMOON_INTERIOR = "silvermoon_interior"
MUSIC_REGION_EVERSONG = "eversong"
MUSIC_REGION_SUNSTRIDER = "sunstrider"
MUSIC_REGION_EVERSONG_SOUTH = "eversong_south"
MUSIC_REGION_DEATHOLME = "deatholme"
MUSIC_REGION_AMANI = "amani"
MUSIC_REGION_LEGACY_GHOSTLANDS = "ghostlands"
RAW_DEFAULT_SUPPORTED_SUBZONE_REGION = NormalizeUserConfigKey(
    GetConfigValue("music", "routing", "defaultSupportedSubZoneRegion")
)
DEFAULT_SUPPORTED_SUBZONE_REGION = nil
MUSIC_ZONE_REGION_OVERRIDES = nil
MUSIC_SUBZONE_REGION_OVERRIDES = nil
MUSIC_SUBZONE_REGION_TOKEN_OVERRIDES = nil
MUSIC_NORMALIZED_SUBZONE_PATTERN_REGION_OVERRIDES = nil
MUSIC_NATIVE_AMBIENCE_SUPPRESS_REGIONS = BuildNormalizedStringSet(
    GetConfigValue("music", "playback", "regionsWithAmbienceSuppression") or {
        MUSIC_REGION_DEATHOLME,
    }
)

function NormalizeMusicRegionKey(regionKey)
    if regionKey == MUSIC_REGION_LEGACY_GHOSTLANDS then
        return MUSIC_REGION_EVERSONG_SOUTH
    end
    return regionKey
end

DEFAULT_SUPPORTED_SUBZONE_REGION = NormalizeMusicRegionKey(RAW_DEFAULT_SUPPORTED_SUBZONE_REGION)
    or MUSIC_REGION_SILVERMOON

MUSIC_ZONE_REGION_OVERRIDES = BuildNormalizedStringMap(
    GetConfigValue("music", "routing", "byZone") or {},
    function(value)
        return NormalizeMusicRegionKey(NormalizeUserConfigKey(value))
    end
)

MUSIC_SUBZONE_REGION_OVERRIDES = BuildNormalizedStringMap(
    GetConfigValue("music", "routing", "bySubZone") or {},
    function(value)
        return NormalizeMusicRegionKey(NormalizeUserConfigKey(value))
    end
)

MUSIC_SUBZONE_REGION_TOKEN_OVERRIDES = BuildNormalizedStringMap(
    GetConfigValue("music", "routing", "bySubZoneToken") or {},
    function(value)
        return NormalizeMusicRegionKey(NormalizeUserConfigKey(value))
    end
)

MUSIC_NORMALIZED_SUBZONE_PATTERN_REGION_OVERRIDES = BuildNormalizedStringMap(
    GetConfigValue("music", "routing", "byNormalizedSubZoneToken") or {},
    function(value)
        return NormalizeMusicRegionKey(NormalizeUserConfigKey(value))
    end
)

function NormalizeAreaMatchToken(text)
    local normalized = string.lower(tostring(text or ""))
    normalized = normalized:gsub("[^%w]+", "")
    return normalized
end

local function AreaMatchesTokenList(text, tokenList)
    local normalized = NormalizeAreaMatchToken(text)
    if normalized == "" or not tokenList then
        return false
    end

    for _, token in ipairs(tokenList) do
        if strfind(normalized, token, 1, true) ~= nil then
            return true
        end
    end

    return false
end

function AreaHasVoiceNativeOnly(text)
    return AreaMatchesTokenList(text, BLOOD_ELF_VOICE_NATIVE_ONLY_TOKENS)
end

function AreaHasNativeOnlyMusic(text)
    return AreaMatchesTokenList(text, BLOOD_ELF_MUSIC_NATIVE_ONLY_TOKENS)
end

function GetCurrentMapLineageTokens()
    local tokens = {}
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then
        return tokens
    end

    local mapID = C_Map.GetBestMapForUnit("player")
    local seen = {}

    while mapID and not seen[mapID] do
        seen[mapID] = true

        local mapInfo = C_Map.GetMapInfo(mapID)
        if not mapInfo then
            break
        end

        local token = NormalizeAreaMatchToken(mapInfo.name)
        if token ~= "" then
            tokens[token] = true
        end

        local parentMapID = tonumber(mapInfo.parentMapID) or 0
        if parentMapID <= 0 then
            break
        end

        mapID = parentMapID
    end

    return tokens
end

function ResolveBloodElfMusicScope(zoneName, subZoneName, hasDirectSubZoneSupport)
    local zoneToken = NormalizeAreaMatchToken(zoneName)
    if zoneToken ~= "" and BLOOD_ELF_MUSIC_SCOPE_TOKENS[zoneToken] then
        return true, "zone"
    end

    local subZoneToken = NormalizeAreaMatchToken(subZoneName)
    if subZoneToken ~= "" and BLOOD_ELF_MUSIC_SCOPE_TOKENS[subZoneToken] then
        return true, "subzone"
    end

    local mapTokens = GetCurrentMapLineageTokens()
    for token in pairs(mapTokens) do
        if BLOOD_ELF_MUSIC_SCOPE_TOKENS[token] then
            return true, "map"
        end
    end

    if hasDirectSubZoneSupport then
        return true, "direct-subzone"
    end

    return false, "none"
end

function ResolveMusicSubZoneRegionOverride(subZoneName, subZoneKey)
    local exactRegionKey = NormalizeMusicRegionKey(MUSIC_SUBZONE_REGION_OVERRIDES[subZoneKey])
    if exactRegionKey then
        return exactRegionKey, "exact"
    end

    local subZoneToken = NormalizeAreaMatchToken(subZoneName)
    if subZoneToken == "" then
        return nil, "none"
    end

    for token, regionKey in pairs(MUSIC_SUBZONE_REGION_TOKEN_OVERRIDES) do
        if strfind(subZoneToken, token, 1, true) ~= nil then
            return NormalizeMusicRegionKey(regionKey), "token"
        end
    end

    return nil, "none"
end

-- ============================================================
--  INTRO COOLDOWN HELPERS
--  These stay separate from the general config access layer because
--  they also manage SavedVariables-backed runtime history.
-- ============================================================
function GetUserMusicIntroCooldownConfig()
    local introConfig = GetConfigValue("music", "introCooldowns")
    return type(introConfig) == "table" and introConfig or nil
end

function NormalizeConfiguredCooldownSeconds(value)
    local seconds = tonumber(value)
    if not seconds or seconds <= 0 then
        return nil
    end

    return math.floor(seconds + 0.5)
end

-- Persisted intro cooldowns must survive `/reload`, so they need a
-- stable wall-clock time source rather than `GetTime()`, which resets
-- with every Lua instance.
function GetStableTimestampSeconds()
    if type(GetServerTime) == "function" then
        local serverNow = tonumber(GetServerTime())
        if serverNow and serverNow > 0 then
            return serverNow
        end
    end

    if type(time) == "function" then
        local localNow = tonumber(time())
        if localNow and localNow > 0 then
            return localNow
        end
    end

    return math.floor(GetTime())
end

function BuildMusicLocationRuleKey(zoneKey, subZoneKey)
    local normalizedZoneKey = NormalizeUserConfigKey(zoneKey)
    local normalizedSubZoneKey = NormalizeUserConfigKey(subZoneKey)

    if not normalizedZoneKey or not normalizedSubZoneKey or normalizedSubZoneKey == normalizedZoneKey then
        return nil
    end

    return normalizedZoneKey .. "||" .. normalizedSubZoneKey
end

function BuildMusicPoolRuleKey(regionKey, poolName)
    local normalizedRegionKey = NormalizeMusicRegionKey(regionKey)
    local normalizedPoolName = NormalizeUserConfigKey(poolName)

    if not normalizedRegionKey or not normalizedPoolName then
        return nil
    end

    return normalizedRegionKey .. ":" .. normalizedPoolName
end

function GetMusicIntroHistoryStore()
    if not BElfVRDB then
        return nil
    end

    if type(BElfVRDB.musicIntroHistory) ~= "table" then
        BElfVRDB.musicIntroHistory = {}
    end

    return BElfVRDB.musicIntroHistory
end

function AddMusicIntroCooldownBucket(bucketList, seenBuckets, historyKey, label, seconds)
    if not historyKey or not label then
        return
    end

    local normalizedSeconds = NormalizeConfiguredCooldownSeconds(seconds)
    if not normalizedSeconds or seenBuckets[historyKey] then
        return
    end

    seenBuckets[historyKey] = true
    bucketList[#bucketList + 1] = {
        historyKey = historyKey,
        label = label,
        seconds = normalizedSeconds,
    }
end

-- Build every cooldown bucket that applies to one intro candidate.
-- All matching buckets are enforced together so:
-- - broad defaults still work
-- - precise overrides can be added without removing safety nets
-- - the strictest matching rule wins naturally
function BuildMusicIntroCooldownBuckets(context, regionKey, poolName, fileDataID)
    local introConfig = GetUserMusicIntroCooldownConfig()
    local buckets = {}
    local seenBuckets = {}
    local resolvedRegionKey = NormalizeMusicRegionKey(regionKey or (context and context.regionKey))
    local defaultSeconds = introConfig and introConfig.defaultSeconds or MUSIC_INTRO_REPEAT_COOLDOWN

    AddMusicIntroCooldownBucket(buckets, seenBuckets, "default", "default", defaultSeconds)

    if introConfig and type(introConfig.byRegion) == "table" and resolvedRegionKey then
        AddMusicIntroCooldownBucket(
            buckets,
            seenBuckets,
            "region:" .. resolvedRegionKey,
            "region " .. resolvedRegionKey,
            introConfig.byRegion[resolvedRegionKey]
        )
    end

    if introConfig and type(introConfig.byZone) == "table" and context and context.zoneKey ~= "" then
        AddMusicIntroCooldownBucket(
            buckets,
            seenBuckets,
            "zone:" .. context.zoneKey,
            "zone " .. context.zoneKey,
            introConfig.byZone[context.zoneKey]
        )
    end

    if introConfig and type(introConfig.bySubZone) == "table" and context and context.subZoneKey ~= "" then
        AddMusicIntroCooldownBucket(
            buckets,
            seenBuckets,
            "subzone:" .. context.subZoneKey,
            "subzone " .. context.subZoneKey,
            introConfig.bySubZone[context.subZoneKey]
        )
    end

    if introConfig and type(introConfig.byArea) == "table" and context then
        local locationRuleKey = BuildMusicLocationRuleKey(context.zoneKey, context.subZoneKey)
        if locationRuleKey then
            AddMusicIntroCooldownBucket(
                buckets,
                seenBuckets,
                "area:" .. locationRuleKey,
                "area " .. locationRuleKey,
                introConfig.byArea[locationRuleKey]
            )
        end
    end

    if introConfig and type(introConfig.byPool) == "table" then
        local poolRuleKey = BuildMusicPoolRuleKey(resolvedRegionKey, poolName)
        if poolRuleKey then
            AddMusicIntroCooldownBucket(
                buckets,
                seenBuckets,
                "pool:" .. poolRuleKey,
                "pool " .. poolRuleKey,
                introConfig.byPool[poolRuleKey]
            )
        end
    end

    if introConfig and type(introConfig.byTrackID) == "table" and fileDataID then
        AddMusicIntroCooldownBucket(
            buckets,
            seenBuckets,
            "track:" .. tostring(fileDataID),
            "track " .. tostring(fileDataID),
            introConfig.byTrackID[fileDataID]
        )
    end

    return buckets
end

function ShouldPlayMusicIntro(context, regionKey, poolName, fileDataID)
    if not (BElfVRDB and BElfVRDB.musicUseIntro and fileDataID) then
        return false
    end

    local introHistory = GetMusicIntroHistoryStore()
    if not introHistory then
        return true
    end

    local now = GetStableTimestampSeconds()
    local strongestBlock = nil

    for _, bucket in ipairs(BuildMusicIntroCooldownBuckets(context, regionKey, poolName, fileDataID)) do
        local lastPlayedAt = tonumber(introHistory[bucket.historyKey])
        if lastPlayedAt then
            local elapsed = now - lastPlayedAt
            if elapsed < bucket.seconds then
                local remaining = math.ceil(bucket.seconds - elapsed)
                if not strongestBlock or remaining > strongestBlock.remaining then
                    strongestBlock = {
                        label = bucket.label,
                        remaining = remaining,
                    }
                end
            end
        end
    end

    if strongestBlock then
        LogMusic("Skipping intro because cooldown is still active for " ..
            strongestBlock.label .. " (" .. tostring(strongestBlock.remaining) .. "s left).")
        RecordMusicTrace("Skipped intro cooldown=" .. tostring(strongestBlock.label) ..
            " remaining=" .. tostring(strongestBlock.remaining))
        return false
    end

    return true
end

function RememberMusicIntroPlayback(context, regionKey, poolName, fileDataID)
    local introHistory = GetMusicIntroHistoryStore()
    if not introHistory then
        return
    end

    local now = GetStableTimestampSeconds()
    for _, bucket in ipairs(BuildMusicIntroCooldownBuckets(context, regionKey, poolName, fileDataID)) do
        introHistory[bucket.historyKey] = now
    end
end

function GetConfiguredMusicIntroDefaultCooldown()
    local introConfig = GetUserMusicIntroCooldownConfig()
    return NormalizeConfiguredCooldownSeconds(introConfig and introConfig.defaultSeconds) or MUSIC_INTRO_REPEAT_COOLDOWN
end


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
    musicIntroHistory = {},
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
    musicPlaybackAreaKey = nil,
    musicPlaybackRegionKey = nil,
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
    musicUpdateAccumulator = 0,
    musicIntroPending = false,
    musicManualStop = false,
    musicLastNativeStopAt = 0,
    musicNativeVolumeForced = false,
    musicNativeVolumeBackup = nil,
    musicAmbienceForced = false,
    musicAmbienceEnabledBackup = nil,
    -- `nil` means "unknown yet"; first context evaluation will force-sync.
    musicTrackedMutesApplied = nil,
    musicTrackedMuteSignature = nil,
    musicTrackedMutedIDs = nil,
    musicStartupPurgeInProgress = false,
    musicStartupPurgeIgnoreNextCVar = false,
    musicStartupPurgeReason = nil,
    musicPendingWorldEntry = false,
    musicSkipIntroOnWorldEntry = false,
    musicWorldEntrySuppressUntil = 0,
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

DEFAULT_GENDER_OVERRIDES = BuildNormalizedNPCOverrideMap(
    GetConfigValue("voice", "overrides", "genderByNPCID") or {},
    {
        male = true,
        female = true,
    }
)

DEFAULT_ROLE_OVERRIDES = BuildNormalizedNPCOverrideMap(
    GetConfigValue("voice", "overrides", "roleByNPCID") or {},
    {
        military = true,
        noble = true,
        standard = true,
    }
)

DEFAULT_NAME_PROFILES = BuildNormalizedNameProfileMap(
    GetConfigValue("voice", "profiles", "byName") or {}
)


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
LogMusic = function(msg)
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
local function AppendMusicTraceLine(msg)
    if not BElfVRDB then
        return false
    end

    BElfVRDB.musicTraceLog = BElfVRDB.musicTraceLog or {}

    local hour = date("%H:%M:%S")
    local line = "[" .. tostring(hour or "??:??:??") .. "] " .. tostring(msg)
    local log = BElfVRDB.musicTraceLog
    local maxEntries = MUSIC_TRACE_MAX_ENTRIES

    log[#log + 1] = line

    local overflow = #log - maxEntries
    if overflow > 0 then
        for i = 1, overflow do
            tremove(log, 1)
        end
    end

    return true
end

RecordMusicTrace = function(msg)
    if not (BElfVRDB and BElfVRDB.musicTraceEnabled) then
        return
    end

    AppendMusicTraceLine(msg)
end

local function GetPendingCVarRestore(cvarName)
    if not (BElfVRDB and type(BElfVRDB.pendingCVarRestores) == "table") then
        return nil
    end

    local restoreValue = BElfVRDB.pendingCVarRestores[cvarName]
    if restoreValue == nil then
        return nil
    end

    return tostring(restoreValue)
end

local function RememberPendingCVarRestore(cvarName, restoreValue)
    if not (BElfVRDB and cvarName and restoreValue ~= nil) then
        return
    end

    if type(BElfVRDB.pendingCVarRestores) ~= "table" then
        BElfVRDB.pendingCVarRestores = {}
    end

    if BElfVRDB.pendingCVarRestores[cvarName] == nil then
        BElfVRDB.pendingCVarRestores[cvarName] = tostring(restoreValue)
    end
end

local function ClearPendingCVarRestore(cvarName)
    if not (BElfVRDB and type(BElfVRDB.pendingCVarRestores) == "table") then
        return
    end

    BElfVRDB.pendingCVarRestores[cvarName] = nil
    if next(BElfVRDB.pendingCVarRestores) == nil then
        BElfVRDB.pendingCVarRestores = nil
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

local function CountKeys(map)
    if not map then
        return 0
    end

    local count = 0
    for _ in pairs(map) do
        count = count + 1
    end
    return count
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

    local ok, unitType, _, _, _, _, npcID = pcall(strsplit, "-", guid)
    if not ok then
        return nil
    end
    if unitType ~= "Creature" and unitType ~= "Vehicle" then
        return nil
    end

    return npcID
end

local function FormatDebugValue(value, fallbackText)
    if value == nil then
        return fallbackText or "?"
    end

    local ok, text = pcall(tostring, value)
    if not ok then
        return fallbackText or "<protected>"
    end

    return text
end

local function IsInBloodElfVoiceArea()
    local zoneName = GetRealZoneText() or GetZoneText() or ""
    local subZoneName = GetSubZoneText() or ""
    local zoneKey = string.lower(zoneName)
    local subZoneKey = string.lower(subZoneName)
    local mapTokens = GetCurrentMapLineageTokens()

    if AreaHasVoiceNativeOnly(zoneName) or AreaHasVoiceNativeOnly(subZoneName) then
        return false, "native-only", zoneName, subZoneName
    end

    for _, token in ipairs(BLOOD_ELF_VOICE_NATIVE_ONLY_TOKENS) do
        if mapTokens[token] then
            return false, "native-only-map", zoneName, subZoneName
        end
    end

    if BLOOD_ELF_FALLBACK_ZONES[zoneKey] == true then
        return true, "zone", zoneName, subZoneName
    end

    if subZoneKey ~= "" and BLOOD_ELF_FALLBACK_ZONES[subZoneKey] == true then
        return true, "subzone", zoneName, subZoneName
    end

    local zoneToken = NormalizeAreaMatchToken(zoneName)
    if zoneToken ~= "" and BLOOD_ELF_VOICE_SCOPE_TOKENS[zoneToken] then
        return true, "zone-token", zoneName, subZoneName
    end

    local subZoneToken = NormalizeAreaMatchToken(subZoneName)
    if subZoneToken ~= "" and BLOOD_ELF_VOICE_SCOPE_TOKENS[subZoneToken] then
        return true, "subzone-token", zoneName, subZoneName
    end

    for token in pairs(mapTokens) do
        if BLOOD_ELF_VOICE_SCOPE_TOKENS[token] then
            return true, "map", zoneName, subZoneName
        end
    end

    return false, "none", zoneName, subZoneName
end

local function GetUnitTooltipIdentity(unit)
    local info = {
        hasBloodElfRace = false,
        hasExplicitNonBloodElfRace = false,
        explicitRaceToken = nil,
        hasChildMarker = false,
    }

    if not UnitExists(unit) or UnitIsPlayer(unit) then
        return info
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

        if text then
            local normalized = string.lower(text)

            for _, raceToken in ipairs(BLOOD_ELF_TOOLTIP_RACE_TOKENS) do
                if strfind(normalized, raceToken, 1, true) ~= nil then
                    info.hasBloodElfRace = true
                    break
                end
            end

            if not info.hasChildMarker then
                for _, childToken in ipairs(BLOOD_ELF_TOOLTIP_CHILD_TOKENS) do
                    if strfind(normalized, childToken, 1, true) ~= nil then
                        info.hasChildMarker = true
                        break
                    end
                end
            end

            if not info.hasBloodElfRace and not info.hasExplicitNonBloodElfRace then
                for _, raceToken in ipairs(KNOWN_NON_BLOOD_ELF_RACE_TOKENS) do
                    if strfind(normalized, raceToken, 1, true) ~= nil then
                        info.hasExplicitNonBloodElfRace = true
                        info.explicitRaceToken = raceToken
                        break
                    end
                end
            end
        end
    end

    raceTooltip:Hide()
    raceTooltip:ClearLines()

    if info.hasBloodElfRace then
        info.hasExplicitNonBloodElfRace = false
        info.explicitRaceToken = nil
    end

    return info
end

local function IsUnitDeadForVoice(unit)
    return UnitExists(unit) and UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
end

local NameLooksLikeBloodElfHiddenRaceFallback

local function IsLikelyBloodElfFallback(unit, allowWithoutGossip)
    if not UnitExists(unit) or UnitIsPlayer(unit) then
        return false
    end

    if IsUnitDeadForVoice(unit) then
        if BElfVRDB and BElfVRDB.verbose then
            Log("Fallback blocked because target is dead.")
        end
        return false
    end

    local creatureType = UnitCreatureType(unit)
    local sex = UnitSex(unit)
    local canGossip = GossipFrame and GossipFrame:IsShown()
    local attackable = UnitCanAttack and UnitCanAttack("player", unit)

    if BElfVRDB and BElfVRDB.verbose then
        Log("Fallback check: creatureType=" .. tostring(creatureType or "?") ..
            " sex=" .. tostring(sex or "?") ..
            " gossipShown=" .. tostring(canGossip) ..
            " attackable=" .. tostring(attackable))
    end

    if attackable then
        if BElfVRDB and BElfVRDB.verbose then
            Log("Fallback blocked because target is hostile/attackable.")
        end
        return false
    end

    local zoneAllowed, scopeSource, zoneName, subZoneName = IsInBloodElfVoiceArea()
    if not zoneAllowed then
        if BElfVRDB and BElfVRDB.verbose then
            Log("Fallback blocked outside supported Blood Elf voice scope (" .. tostring(scopeSource) .. "): zone=" ..
                tostring(zoneName ~= "" and string.lower(zoneName) or "?") ..
                " subzone=" .. tostring(subZoneName ~= "" and string.lower(subZoneName) or "?"))
        end
        return false
    end

    if BElfVRDB and BElfVRDB.verbose then
        Log("Fallback zone scope accepted via " .. tostring(scopeSource))
    end

    if creatureType == "Humanoid" and (sex == 2 or sex == 3) then
        if canGossip then
            return true
        end

        if allowWithoutGossip and NameLooksLikeBloodElfHiddenRaceFallback(unit) then
            if BElfVRDB and BElfVRDB.verbose then
                Log("Fallback accepted before gossip because target name/profile matches Blood Elf hints.")
            end
            return true
        end
    end

    if BElfVRDB and BElfVRDB.verbose and allowWithoutGossip and not canGossip then
        Log("Fallback blocked before gossip because target name/profile lacks Blood Elf hints.")
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

local function AppendUniqueMusicIDs(targetList, seen, sourceList)
    if not sourceList then
        return
    end

    for _, id in ipairs(sourceList) do
        if not seen[id] then
            seen[id] = true
            targetList[#targetList + 1] = id
        end
    end
end

local function BuildBaseTrackedMusicMuteList()
    local ids = {}
    local seen = {}

    AppendUniqueMusicIDs(ids, seen, BElfVR_NewMusicIDs)
    AppendUniqueMusicIDs(ids, seen, BElfVR_SupplementalMusicMuteIDs)

    return ids
end

local function GetMusicStats()
    local introCount = BElfVR_TBCMusic and CountEntries(BElfVR_TBCMusic.intro) or 0
    local dayCount = BElfVR_TBCMusic and CountEntries(BElfVR_TBCMusic.day) or 0
    local nightCount = BElfVR_TBCMusic and CountEntries(BElfVR_TBCMusic.night) or 0
    local mutedCount = CountEntries(BuildBaseTrackedMusicMuteList())
    local catalogCount = CountEntries(BElfVR_MidnightAllMusicIDs)
    local catalogFamilyCount = CountKeys(BElfVR_MidnightMusicFamilyIDs)
    local supplementalCount = CountEntries(BElfVR_SupplementalMusicMuteIDs)
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
        catalogCount = catalogCount,
        catalogFamilyCount = catalogFamilyCount,
        supplementalCount = supplementalCount,
        regionalCount = regionalCount,
    }
end

local function IsMusicReplacementActive()
    return BElfVRDB and BElfVRDB.enabled and BElfVRDB.musicEnabled and BElfVRDB.muteNewMusic
end

local function BuildTrackedMusicMuteList(regionKey)
    local ids = BuildBaseTrackedMusicMuteList()
    local seen = {}

    for _, id in ipairs(ids) do
        seen[id] = true
    end

    if RegionalMusicMuteIDs and regionKey then
        AppendUniqueMusicIDs(ids, seen, RegionalMusicMuteIDs[regionKey])
    end

    return ids
end

-- Keep tracked native music file muting scoped to supported Blood Elf music
-- regions so unrelated zones are never muted by this addon.
local function SetTrackedMusicMutesActive(shouldMute, regionKey, reason)
    local wantsMute = shouldMute and true or false
    local desiredSignature = wantsMute and tostring(regionKey or "base") or "off"
    if state.musicTrackedMuteSignature == desiredSignature then
        return
    end

    if state.musicTrackedMutedIDs then
        for _, id in ipairs(state.musicTrackedMutedIDs) do
            UnmuteSoundFile(id)
        end
        state.musicTrackedMutedIDs = nil
    end

    if not wantsMute then
        state.musicTrackedMutesApplied = false
        state.musicTrackedMuteSignature = "off"
        return
    end

    local activeMuteIDs = BuildTrackedMusicMuteList(regionKey)
    if #activeMuteIDs == 0 then
        state.musicTrackedMutesApplied = false
        state.musicTrackedMuteSignature = "off"
        return
    end

    for _, id in ipairs(activeMuteIDs) do
        MuteSoundFile(id)
    end

    state.musicTrackedMutesApplied = true
    state.musicTrackedMuteSignature = desiredSignature
    state.musicTrackedMutedIDs = activeMuteIDs
    LogMusic("Muted " .. #activeMuteIDs .. " tracked music file(s) for region " .. tostring(regionKey or "base") .. ".")
    RecordMusicTrace("Applied tracked music mutes reason=" .. tostring(reason or "update") ..
        " region=" .. tostring(regionKey or "base") ..
        " count=" .. tostring(#activeMuteIDs))
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
    local canonicalRegionKey = NormalizeMusicRegionKey(regionKey)
    local regionData = BElfVR_TBCMusicRegions and canonicalRegionKey and BElfVR_TBCMusicRegions[canonicalRegionKey]
    local regionPool = regionData and regionData[poolName]
    if regionPool and #regionPool > 0 then
        return regionPool, canonicalRegionKey
    end

    -- If a Silvermoon interior pool is empty for this category, fall back
    -- to the regular Silvermoon outdoor chain so playback still works.
    if canonicalRegionKey == MUSIC_REGION_SILVERMOON_INTERIOR and BElfVR_TBCMusicRegions then
        local smRegionData = BElfVR_TBCMusicRegions[MUSIC_REGION_SILVERMOON]
        local smRegionPool = smRegionData and smRegionData[poolName]
        if smRegionPool and #smRegionPool > 0 then
            return smRegionPool, MUSIC_REGION_SILVERMOON
        end
    end

    -- If an explicit Amani bucket is missing in a custom pack, fall back to
    -- broader southern-Eversong routing so playback still works.
    if canonicalRegionKey == MUSIC_REGION_AMANI and BElfVR_TBCMusicRegions then
        local southRegionData = BElfVR_TBCMusicRegions[MUSIC_REGION_EVERSONG_SOUTH]
        local southRegionPool = southRegionData and southRegionData[poolName]
        if southRegionPool and #southRegionPool > 0 then
            return southRegionPool, MUSIC_REGION_EVERSONG_SOUTH
        end
    end

    -- If a custom pack has not added dedicated Deatholme buckets yet,
    -- fall back to the broader southern-Eversong family first.
    if canonicalRegionKey == MUSIC_REGION_DEATHOLME and BElfVR_TBCMusicRegions then
        local southRegionData = BElfVR_TBCMusicRegions[MUSIC_REGION_EVERSONG_SOUTH]
        local southRegionPool = southRegionData and southRegionData[poolName]
        if southRegionPool and #southRegionPool > 0 then
            return southRegionPool, MUSIC_REGION_EVERSONG_SOUTH
        end
    end

    -- Backward compatibility: if custom/community data still uses the
    -- legacy `ghostlands` bucket, treat it as `eversong_south`.
    if canonicalRegionKey == MUSIC_REGION_EVERSONG_SOUTH and BElfVR_TBCMusicRegions then
        local legacyRegionData = BElfVR_TBCMusicRegions[MUSIC_REGION_LEGACY_GHOSTLANDS]
        local legacyRegionPool = legacyRegionData and legacyRegionData[poolName]
        if legacyRegionPool and #legacyRegionPool > 0 then
            return legacyRegionPool, canonicalRegionKey
        end
    end

    local legacyPool = BElfVR_TBCMusic and BElfVR_TBCMusic[poolName]
    if legacyPool and #legacyPool > 0 then
        return legacyPool, MUSIC_REGION_SILVERMOON
    end

    return nil, canonicalRegionKey
end

local function ShouldQueueMusicIntro(regionKey)
    return BElfVRDB and BElfVRDB.musicUseIntro and regionKey and true or false
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
    local overrideRegionKey, overrideMatchSource = ResolveMusicSubZoneRegionOverride(subZoneName, subZoneKey)
    local hasDirectSubZoneSupport = BLOOD_ELF_MUSIC_SUBZONES[subZoneKey] == true
        or overrideRegionKey ~= nil
    local inMusicScope, musicScopeSource = ResolveBloodElfMusicScope(zoneName, subZoneName, hasDirectSubZoneSupport)
    local nativeOnlyZone = AreaHasNativeOnlyMusic(zoneName)
    local nativeOnlySubZone = AreaHasNativeOnlyMusic(subZoneName)
    local nativeOnly = nativeOnlyZone or nativeOnlySubZone
    local supportedByZone = BLOOD_ELF_MUSIC_ZONES[zoneKey] == true and inMusicScope and not nativeOnly
    local supportedBySubZone = hasDirectSubZoneSupport and inMusicScope and not nativeOnly
    local supported = supportedByZone or supportedBySubZone
    local isResting = IsResting() and true or false
    local isNight = IsNightTimeForMusic()
    local isIndoor = (subZoneKey ~= "" and subZoneKey ~= zoneKey)
    local regionKey = nil
    local normalizedSubZoneToken = NormalizeAreaMatchToken(subZoneName)
    local patternRegionKey = nil

    if normalizedSubZoneToken ~= "" then
        for token, configuredRegionKey in pairs(MUSIC_NORMALIZED_SUBZONE_PATTERN_REGION_OVERRIDES) do
            if strfind(normalizedSubZoneToken, token, 1, true) ~= nil then
                patternRegionKey = configuredRegionKey
                break
            end
        end
    end

    if inMusicScope and not nativeOnly then
        regionKey = overrideRegionKey
        if regionKey then
            -- Explicit subzone override wins.
        elseif patternRegionKey then
            regionKey = patternRegionKey
        elseif MUSIC_ZONE_REGION_OVERRIDES[zoneKey] then
            regionKey = MUSIC_ZONE_REGION_OVERRIDES[zoneKey]
        elseif supportedBySubZone then
            regionKey = DEFAULT_SUPPORTED_SUBZONE_REGION
        elseif supported and supportedByZone then
            regionKey = NormalizeMusicRegionKey(zoneKey)
        end
    end

    -- If the player is indoors inside Silvermoon City and no explicit
    -- subzone override already routed to a different region, swap to
    -- the dedicated interior pool so buildings get calm scenic music
    -- instead of the louder outdoor day/night cycle.
    -- IsIndoors() returns 1 when the WoW client considers the player
    -- inside a roofed building; it returns nil for open-air areas and
    -- large indoor spaces where mounting is allowed.
    local wowIndoors = IsIndoors and IsIndoors()
    if regionKey == MUSIC_REGION_SILVERMOON and wowIndoors then
        regionKey = MUSIC_REGION_SILVERMOON_INTERIOR
    end

    return {
        zoneName = zoneName,
        subZoneName = subZoneName,
        zoneKey = zoneKey,
        subZoneKey = subZoneKey,
        supported = supported,
        supportedByZone = supportedByZone,
        supportedBySubZone = supportedBySubZone,
        inMusicScope = inMusicScope,
        musicScopeSource = musicScopeSource,
        overrideMatchSource = overrideMatchSource,
        nativeOnly = nativeOnly,
        nativeOnlyZone = nativeOnlyZone,
        nativeOnlySubZone = nativeOnlySubZone,
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
    state.musicPlaybackAreaKey = nil
    state.musicPlaybackRegionKey = nil
    state.musicLastTrackStartedAt = 0
    state.musicExpectedEndTime = 0
end

local function RestoreNativeMusicVolume(reason)
    if not (SetCVar and GetCVar) then
        return
    end

    local restoreValue = state.musicNativeVolumeBackup or GetPendingCVarRestore("Sound_MusicVolume")
    if restoreValue == nil then
        return
    end

    state.musicNativeVolumeForced = false
    state.musicNativeVolumeBackup = nil

    if GetCVar("Sound_MusicVolume") ~= tostring(restoreValue) then
        SetCVar("Sound_MusicVolume", tostring(restoreValue))
    end

    ClearPendingCVarRestore("Sound_MusicVolume")
    LogMusic("Restored native music volume after leaving replacement-music control.")
    RecordMusicTrace("Restored Sound_MusicVolume reason=" .. tostring(reason or "update"))
end

local function RestoreGlobalMusicEnabledSetting(reason)
    if not (SetCVar and GetCVar) then
        return
    end

    local restoreValue = GetPendingCVarRestore("Sound_EnableMusic")
    if restoreValue == nil then
        return
    end

    if GetCVar("Sound_EnableMusic") ~= tostring(restoreValue) then
        SetCVar("Sound_EnableMusic", tostring(restoreValue))
    end

    ClearPendingCVarRestore("Sound_EnableMusic")
    LogMusic("Restored global music enable state after " .. tostring(reason or "update") .. ".")
    RecordMusicTrace("Restored Sound_EnableMusic reason=" .. tostring(reason or "update"))
end

local function RestoreNativeAmbienceSetting(reason)
    if not (SetCVar and GetCVar) then
        return
    end

    local restoreValue = state.musicAmbienceEnabledBackup or GetPendingCVarRestore("Sound_EnableAmbience")
    if restoreValue == nil then
        return
    end

    state.musicAmbienceForced = false
    state.musicAmbienceEnabledBackup = nil

    if GetCVar("Sound_EnableAmbience") ~= tostring(restoreValue) then
        SetCVar("Sound_EnableAmbience", tostring(restoreValue))
    end

    ClearPendingCVarRestore("Sound_EnableAmbience")
    LogMusic("Restored ambient channel after leaving replacement-music control.")
    RecordMusicTrace("Restored Sound_EnableAmbience reason=" .. tostring(reason or "update"))
end

local function SetNativeMusicVolumeSuppressed(shouldSuppress, reason)
    if not (SetCVar and GetCVar) then
        return
    end

    if not MUSIC_SUPPRESS_NATIVE_WITH_VOLUME then
        RestoreNativeMusicVolume(reason or "volume suppression disabled")
        return
    end

    local currentVolume = GetCVar("Sound_MusicVolume")
    if shouldSuppress then
        if not state.musicNativeVolumeForced then
            state.musicNativeVolumeBackup = currentVolume
            state.musicNativeVolumeForced = true
            RememberPendingCVarRestore("Sound_MusicVolume", currentVolume)
            LogMusic("Temporarily forcing native music volume to 0 while replacement music is active.")
            RecordMusicTrace("Forced Sound_MusicVolume=0 reason=" .. tostring(reason or "update"))
        end

        if tonumber(currentVolume or "") ~= MUSIC_NATIVE_SUPPRESS_VOLUME then
            SetCVar("Sound_MusicVolume", tostring(MUSIC_NATIVE_SUPPRESS_VOLUME))
        end
        return
    end

    RestoreNativeMusicVolume(reason)
end

local function SetNativeAmbienceSuppressed(shouldSuppress, reason)
    if not (SetCVar and GetCVar) then
        return
    end

    if shouldSuppress then
        if not state.musicAmbienceForced then
            local currentEnabled = GetCVar("Sound_EnableAmbience")
            state.musicAmbienceEnabledBackup = currentEnabled
            state.musicAmbienceForced = true
            RememberPendingCVarRestore("Sound_EnableAmbience", currentEnabled)
            LogMusic("Temporarily disabling ambient channel to block overlapping native Deatholme audio.")
            RecordMusicTrace("Forced Sound_EnableAmbience=0 reason=" .. tostring(reason or "update"))
        end

        if GetCVar("Sound_EnableAmbience") ~= "0" then
            SetCVar("Sound_EnableAmbience", "0")
        end
        return
    end

    RestoreNativeAmbienceSetting(reason)
end

-- Some Midnight tracks can restart underneath injected playback even
-- after one-time muting/stop calls. While replacement music is active,
-- issue periodic native-channel stops. Injected music is played on
-- `MUSIC_PLAYBACK_CHANNEL` so this native guard does not cut our own track.
local function EnforceNativeMusicSuppression(reason, forceNow)
    if not (MUSIC_FORCE_STOP_NATIVE_BEFORE_REPLACEMENT and StopMusic) then
        return
    end

    local now = GetTime()
    if not forceNow then
        local elapsed = now - (state.musicLastNativeStopAt or 0)
        if elapsed < MUSIC_NATIVE_GUARD_INTERVAL then
            return
        end
    end

    StopMusic()
    state.musicLastNativeStopAt = now

    if forceNow then
        LogMusic("Issued StopMusic() native guard [" .. tostring(reason or "update") .. "].")
        RecordMusicTrace("Issued StopMusic native guard reason=" .. tostring(reason or "update"))
    elseif reason ~= "heartbeat" then
        LogMusic("Issued periodic StopMusic() native guard pulse.")
    end
end

local function ArmWorldEntryMusicSettle(reason)
    if not (C_Timer and C_Timer.After) then
        return false
    end

    local settleReason = tostring(reason or "world entry")
    local armedUntil = GetTime() + MUSIC_WORLD_ENTRY_SETTLE_SECONDS
    state.musicWorldEntrySuppressUntil = armedUntil

    LogMusic("Armed world-entry music settle window for " ..
        tostring(MUSIC_WORLD_ENTRY_SETTLE_SECONDS) .. "s [" .. settleReason .. "].")
    RecordMusicTrace("Armed world-entry settle reason=" .. settleReason ..
        " seconds=" .. tostring(MUSIC_WORLD_ENTRY_SETTLE_SECONDS))

    C_Timer.After(MUSIC_WORLD_ENTRY_SETTLE_SECONDS, function()
        if state.musicWorldEntrySuppressUntil ~= armedUntil then
            return
        end

        state.musicWorldEntrySuppressUntil = 0
    end)

    return true
end

local function ResetMusicState(stopPlayback)
    if stopPlayback then
        StopInjectedMusic(MUSIC_TRANSITION_FADE_MS)
    end

    state.musicCurrentAreaKey = nil
    state.musicCurrentRegionKey = nil
    state.musicPlaybackAreaKey = nil
    state.musicPlaybackRegionKey = nil
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
    state.musicPendingWorldEntry = false
    state.musicSkipIntroOnWorldEntry = false
    state.musicWorldEntrySuppressUntil = 0
    state.musicLastNativeStopAt = 0
    SetNativeMusicVolumeSuppressed(false, "reset")
    SetNativeAmbienceSuppressed(false, "reset")
end

local function ShutdownMusicState(reason)
    if state.musicHandle or state.musicCurrentTrackID then
        LogMusic("Shutting down injected music for " .. tostring(reason or "shutdown") .. ".")
        RecordMusicTrace("Shutdown music reason=" .. tostring(reason or "shutdown"))
    end

    StopInjectedMusic(0)

    if StopMusic then
        StopMusic()
        state.musicLastNativeStopAt = GetTime()
    end

    SetTrackedMusicMutesActive(false, nil, tostring(reason or "shutdown"))
    state.musicCurrentAreaKey = nil
    state.musicCurrentRegionKey = nil
    state.musicPlaybackAreaKey = nil
    state.musicPlaybackRegionKey = nil
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
    state.musicPendingWorldEntry = false
    state.musicSkipIntroOnWorldEntry = false
    state.musicWorldEntrySuppressUntil = 0

    RestoreInterruptedTemporaryCVars(tostring(reason or "shutdown"))
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
    LogMusic("Selected " .. tostring(poolName or "?") .. " track ID " .. chosen .. " from " .. #eligible .. " eligible candidate(s).")
    RecordMusicTrace("Selected pool=" .. tostring(poolName or "?") .. " track=" .. tostring(chosen) ..
        " eligible=" .. tostring(#eligible))
    return chosen
end

local function PlayMusicTrack(fileDataID, poolName, reason, playbackAreaKey, playbackRegionKey)
    if not fileDataID then
        return false
    end
    if not IsGlobalMusicEnabled() then
        LogMusic("Skipping replacement music because WoW music output is disabled.")
        RecordMusicTrace("Skipped playback because WoW music output is disabled.")
        return false
    end

    EnforceNativeMusicSuppression("before replacement playback", true)

    StopInjectedMusic(MUSIC_TRANSITION_FADE_MS)

    local willPlay, soundHandle = PlaySoundFile(fileDataID, MUSIC_PLAYBACK_CHANNEL)
    if not willPlay then
        LogMusic("PlaySoundFile failed for music track ID " .. fileDataID)
        RecordMusicTrace("PlaySoundFile failed for track=" .. tostring(fileDataID))
        return false
    end

    state.musicHandle = soundHandle
    state.musicCurrentTrackID = fileDataID
    state.musicCurrentPool = poolName
    state.musicPlaybackAreaKey = playbackAreaKey
    state.musicPlaybackRegionKey = playbackRegionKey
    state.musicLastTrackStartedAt = GetTime()
    state.musicExpectedEndTime = state.musicLastTrackStartedAt + ((BElfVR_TBCMusicDurations and BElfVR_TBCMusicDurations[fileDataID]) or MUSIC_TRACK_ROTATE_SECONDS)
    state.musicTrackCooldowns[fileDataID] = state.musicLastTrackStartedAt

    LogMusic("Playing " .. tostring(poolName or "?") .. " music track ID " .. fileDataID ..
        " (" .. tostring(reason or "unspecified") .. ")")
    RecordMusicTrace("Playing pool=" .. tostring(poolName or "?") .. " track=" .. tostring(fileDataID) ..
        " reason=" .. tostring(reason or "unspecified"))
    return true
end

local function EvaluateMusicState(reason, forceTrackRefresh)
    if not BElfVRDB then
        return
    end

    local globalMusicToggleChanged = HandleGlobalMusicToggle()
    RefreshMusicPlaybackLifetime()

    local context = GetMusicContext()
    local contextSignature = context.areaKey
    local shouldMuteTrackedMusic = context.supported and BElfVRDB.enabled and BElfVRDB.musicEnabled and BElfVRDB.muteNewMusic
    SetTrackedMusicMutesActive(shouldMuteTrackedMusic, context.regionKey, reason)
    local shouldSuppressNativeVolume = context.supported and IsMusicReplacementActive() and IsGlobalMusicEnabled()
    SetNativeMusicVolumeSuppressed(shouldSuppressNativeVolume, reason)
    local shouldSuppressNativeAmbience = context.supported
        and IsMusicReplacementActive()
        and IsGlobalMusicEnabled()
        and context.regionKey ~= nil
        and MUSIC_NATIVE_AMBIENCE_SUPPRESS_REGIONS[context.regionKey] == true
    SetNativeAmbienceSuppressed(shouldSuppressNativeAmbience, reason)

    if not IsGlobalMusicEnabled() then
        state.musicPendingWorldEntry = false
        state.musicCurrentAreaKey = context.areaKey
        state.musicCurrentRegionKey = context.regionKey
        state.musicLastContextSignature = contextSignature
        return
    end

    local locationChanged = context.zoneName ~= state.musicLastZoneName or
        context.subZoneName ~= state.musicLastSubZoneName or
        context.isResting ~= state.musicLastResting or
        context.isIndoor ~= state.musicLastIndoor or
        context.isNight ~= state.musicLastNight

    if locationChanged then
        LogMusic("Context change [" .. tostring(reason or "update") .. "]: zone=" ..
            tostring(context.zoneName ~= "" and context.zoneName or "<none>") ..
            " subzone=" .. tostring(context.subZoneName ~= "" and context.subZoneName or "<none>") ..
            " region=" .. tostring(context.regionKey or "<none>") ..
            " scope=" .. tostring(context.inMusicScope) ..
            " scopeSource=" .. tostring(context.musicScopeSource or "none") ..
            " overrideSource=" .. tostring(context.overrideMatchSource or "none") ..
            " supported(zone)=" .. tostring(context.supportedByZone) ..
            " supported(subzone)=" .. tostring(context.supportedBySubZone) ..
            " nativeOnly=" .. tostring(context.nativeOnly) ..
            " resting=" .. tostring(context.isResting) ..
            " indoorLike=" .. tostring(context.isIndoor) ..
            " phase=" .. (context.isNight and "night" or "day"))
        RecordMusicTrace("Context reason=" .. tostring(reason or "update") ..
            " zone=" .. tostring(context.zoneName ~= "" and context.zoneName or "<none>") ..
            " subzone=" .. tostring(context.subZoneName ~= "" and context.subZoneName or "<none>") ..
            " region=" .. tostring(context.regionKey or "<none>") ..
            " scope=" .. tostring(context.inMusicScope) ..
            " scopeSource=" .. tostring(context.musicScopeSource or "none") ..
            " overrideSource=" .. tostring(context.overrideMatchSource or "none") ..
            " supportedZone=" .. tostring(context.supportedByZone) ..
            " supportedSubZone=" .. tostring(context.supportedBySubZone) ..
            " nativeOnly=" .. tostring(context.nativeOnly) ..
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
        state.musicPendingWorldEntry = false
        state.musicCurrentAreaKey = context.areaKey
        state.musicCurrentRegionKey = context.regionKey
        state.musicLastContextSignature = contextSignature
        state.musicIntroPending = false
        return
    end

    if state.musicPendingWorldEntry then
        state.musicPendingWorldEntry = false
        state.musicSkipIntroOnWorldEntry = true
        ArmWorldEntryMusicSettle(reason or "world entry")
        LogMusic("Promoted pending world-entry arrival into an active settle window inside supported music scope.")
        RecordMusicTrace("Promoted pending world-entry arrival reason=" .. tostring(reason or "world entry"))
    end

    local enteringSupportedZone = (state.musicLastContextSignature ~= nil and state.musicCurrentAreaKey == nil)
        or (not state.musicCurrentAreaKey)
    local areaChanged = state.musicCurrentAreaKey ~= context.areaKey
    local regionChanged = state.musicCurrentRegionKey ~= context.regionKey
    local playbackAreaChanged = state.musicPlaybackAreaKey ~= nil and state.musicPlaybackAreaKey ~= context.areaKey
    local playbackRegionChanged = state.musicPlaybackRegionKey ~= nil and state.musicPlaybackRegionKey ~= context.regionKey
    -- Fallback-only rotation:
    -- If a track has a known duration, let it finish naturally.
    -- The old fixed timer caused long songs (especially intros) to be
    -- cut off abruptly before their natural end.
    local timeToRotate = state.musicLastTrackStartedAt > 0 and
        state.musicExpectedEndTime <= 0 and
        ((GetTime() - state.musicLastTrackStartedAt) >= MUSIC_TRACK_ROTATE_SECONDS)

    local shouldForceNativeGuard = forceTrackRefresh or
        globalMusicToggleChanged or
        enteringSupportedZone or
        areaChanged or
        regionChanged or
        playbackAreaChanged or
        playbackRegionChanged or
        locationChanged

    if (playbackAreaChanged or playbackRegionChanged) and (BElfVRDB and BElfVRDB.musicVerbose) then
        LogMusic("Current injected track no longer matches active music context; forcing an immediate region swap.")
        RecordMusicTrace("Playback/context mismatch forcing swap from=" ..
            tostring(state.musicPlaybackRegionKey or "<none>") ..
            " to=" .. tostring(context.regionKey or "<none>"))
    end

    if shouldForceNativeGuard then
        EnforceNativeMusicSuppression(reason or "update", true)
    elseif not MUSIC_SUPPRESS_NATIVE_WITH_VOLUME then
        EnforceNativeMusicSuppression(reason or "periodic", false)
    end

    -- Intro should only be a true "fresh entry" cue.
    -- Region boundary swaps inside supported territory must not
    -- keep re-queuing intro tracks.
    if enteringSupportedZone then
        if state.musicSkipIntroOnWorldEntry then
            state.musicIntroPending = false
            state.musicSkipIntroOnWorldEntry = false
            LogMusic("Skipping addon intro on world entry because the client arrived through a loading screen.")
            RecordMusicTrace("Skipped addon intro on world-entry supported arrival.")
        else
            state.musicIntroPending = ShouldQueueMusicIntro(context.regionKey)
        end
    end

    if (state.musicWorldEntrySuppressUntil or 0) > GetTime() then
        state.musicIntroPending = false
        state.musicSkipIntroOnWorldEntry = false
        EnforceNativeMusicSuppression((reason or "world entry") .. " settle", true)
        state.musicCurrentAreaKey = context.areaKey
        state.musicCurrentRegionKey = context.regionKey
        state.musicLastContextSignature = contextSignature
        return
    end

    if state.musicManualStop then
        if forceTrackRefresh or globalMusicToggleChanged or areaChanged or playbackAreaChanged or playbackRegionChanged then
            state.musicManualStop = false
        else
            state.musicCurrentAreaKey = context.areaKey
            state.musicCurrentRegionKey = context.regionKey
            state.musicLastContextSignature = contextSignature
            return
        end
    end

    if not (forceTrackRefresh or
        globalMusicToggleChanged or
        areaChanged or
        playbackAreaChanged or
        playbackRegionChanged or
        timeToRotate or
        not state.musicHandle) then
        state.musicLastContextSignature = contextSignature
        return
    end

    local poolName
    local trackPool
    local resolvedRegionKey = context.regionKey
    local nextTrack

    if state.musicIntroPending then
        poolName = "intro"
        trackPool, resolvedRegionKey = GetMusicTrackPool(context.regionKey, "intro")
        nextTrack = ChooseMusicTrack(poolName, trackPool)
        state.musicIntroPending = false

        if not ShouldPlayMusicIntro(context, resolvedRegionKey, poolName, nextTrack) then
            poolName = context.isNight and "night" or "day"
            trackPool, resolvedRegionKey = GetMusicTrackPool(context.regionKey, poolName)
            nextTrack = ChooseMusicTrack(poolName, trackPool)
        end
    else
        poolName = context.isNight and "night" or "day"
        trackPool, resolvedRegionKey = GetMusicTrackPool(context.regionKey, poolName)
        nextTrack = ChooseMusicTrack(poolName, trackPool)
    end

    if nextTrack then
        local resolvedPoolName = poolName
        if resolvedRegionKey and resolvedRegionKey ~= context.regionKey then
            resolvedPoolName = tostring(context.regionKey or "?") .. "->" .. tostring(resolvedRegionKey) .. ":" .. poolName
        elseif resolvedRegionKey then
            resolvedPoolName = tostring(resolvedRegionKey) .. ":" .. poolName
        end
        local refreshReason = reason or ((areaChanged or playbackAreaChanged or playbackRegionChanged) and "area change" or "rotation")
        local didPlay = PlayMusicTrack(nextTrack, resolvedPoolName, refreshReason, context.areaKey, context.regionKey)
        if didPlay and poolName == "intro" then
            RememberMusicIntroPlayback(context, resolvedRegionKey, poolName, nextTrack)
        end
        if not didPlay and context.regionKey == MUSIC_REGION_AMANI then
            local fallbackPoolName = context.isNight and "night" or "day"
            local fallbackPool, fallbackRegionKey = GetMusicTrackPool(MUSIC_REGION_EVERSONG_SOUTH, fallbackPoolName)
            local fallbackTrack = ChooseMusicTrack(fallbackPoolName, fallbackPool)
            if fallbackTrack then
                local fallbackResolvedPoolName = tostring(fallbackRegionKey or MUSIC_REGION_EVERSONG_SOUTH) .. ":" .. fallbackPoolName
                PlayMusicTrack(fallbackTrack, fallbackResolvedPoolName, "amani fallback after failed troll track", context.areaKey, context.regionKey)
            end
        end
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

    if currentVersion < 4 and type(BElfVRDB.musicIntroHistory) ~= "table" then
        BElfVRDB.musicIntroHistory = {}
    end

    BElfVRDB.schemaVersion = DB_SCHEMA_VERSION
end

local function RestoreNativeDialogSetting()
    if not (SetCVar and GetCVar) then
        return
    end

    local restoreValue = state.dialogPrevEnabled or GetPendingCVarRestore("Sound_EnableDialog")
    if restoreValue == nil then
        return
    end

    state.dialogSuppressToken = state.dialogSuppressToken + 1
    state.dialogPrevEnabled = nil

    if GetCVar("Sound_EnableDialog") ~= tostring(restoreValue) then
        SetCVar("Sound_EnableDialog", tostring(restoreValue))
    end

    ClearPendingCVarRestore("Sound_EnableDialog")
end

RestoreInterruptedTemporaryCVars = function(reason)
    RestoreGlobalMusicEnabledSetting(reason)
    RestoreNativeMusicVolume(reason)
    RestoreNativeAmbienceSetting(reason)
    RestoreNativeDialogSetting()
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

local function CanPlayTargetSelectGreeting(unit)
    if not UnitExists(unit) then
        return false
    end

    if IsUnitDeadForVoice(unit) then
        Log("Skipping target-select greet because target is dead.")
        return false
    end

    if UnitCanAttack and UnitCanAttack("player", unit) then
        Log("Skipping target-select greet because target is hostile/attackable.")
        return false
    end

    return true
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
    if state.dialogPrevEnabled == nil then
        state.dialogPrevEnabled = GetCVar("Sound_EnableDialog")
        RememberPendingCVarRestore("Sound_EnableDialog", state.dialogPrevEnabled)
    end

    if GetCVar("Sound_EnableDialog") ~= "0" then
        SetCVar("Sound_EnableDialog", "0")
    end

    C_Timer.After(DIALOG_SUPPRESSION_WINDOW, function()
        if state.dialogSuppressToken ~= suppressToken then
            return
        end

        local restoreValue = state.dialogPrevEnabled or GetPendingCVarRestore("Sound_EnableDialog")
        if restoreValue ~= nil and GetCVar("Sound_EnableDialog") ~= tostring(restoreValue) then
            SetCVar("Sound_EnableDialog", tostring(restoreValue))
        end

        state.dialogPrevEnabled = nil
        ClearPendingCVarRestore("Sound_EnableDialog")
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

local function NameLooksLikeChildNPC(unit)
    local name = string.lower(UnitName(unit) or "")
    if name == "" then
        return false
    end

    for _, token in ipairs(CHILD_NAME_TOKENS) do
        if strfind(name, token, 1, true) ~= nil then
            return true
        end
    end

    return false
end

NameLooksLikeBloodElfHiddenRaceFallback = function(unit)
    local nameKey = NormalizeUserConfigKey(UnitName(unit))
    if nameKey == "" then
        return false
    end

    local profile = GetDefaultNameProfile(unit)
    if profile and not profile.exclude then
        return true
    end

    for _, token in ipairs(BLOOD_ELF_HIDDEN_RACE_NAME_TOKENS) do
        if strfind(nameKey, token, 1, true) ~= nil then
            return true
        end
    end

    return false
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
        Log("Using configured role override for guid=" .. FormatDebugValue(guid, "<protected-guid>") .. ": " .. guidOverride)
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

    for _, token in ipairs(MILITARY_ROLE_NAME_TOKENS) do
        if string.find(name, token, 1, true) then
            return "military"
        end
    end

    for _, token in ipairs(NOBLE_ROLE_NAME_TOKENS) do
        if string.find(name, token, 1, true) then
            return "noble"
        end
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
    RestoreNativeDialogSetting()
    state.lastPlaybackTime = 0
end

-- Returns "male", "female", or nil if the unit is not a Blood Elf NPC
local function GetBloodElfNPCGender(unit, allowHiddenRaceFallbackWithoutGossip)
    if not UnitExists(unit) then return nil end

    -- We only want NPCs, not player characters
    if UnitIsPlayer(unit) then return nil end

    if IsUnitDeadForVoice(unit) then
        Log("Target is dead; keeping native voice: " .. tostring(UnitName(unit)))
        return nil
    end

    local zoneAllowed, scopeSource, zoneName, subZoneName = IsInBloodElfVoiceArea()
    if not zoneAllowed then
        Log("Skipping TBC voice outside supported areas (" .. tostring(scopeSource) .. "): zone=" ..
            tostring(zoneName ~= "" and string.lower(zoneName) or "?") ..
            " subzone=" .. tostring(subZoneName ~= "" and string.lower(subZoneName) or "?"))
        return nil
    end

    if IsExcludedByNameProfile(unit) then
        Log("Target is excluded by built-in name profile: " .. tostring(UnitName(unit)))
        return nil
    end

    local guid = UnitGUID(unit)
    local guidOverride = GetConfiguredGUIDGenderOverride(guid)
    if guidOverride then
        Log("Using configured gender override for guid=" .. FormatDebugValue(guid, "<protected-guid>") .. ": " .. guidOverride)
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

    if NameLooksLikeChildNPC(unit) then
        Log("Target name looks like a child NPC; keeping native voice: " .. tostring(UnitName(unit)))
        return nil
    end

    local tooltipIdentity = GetUnitTooltipIdentity(unit)

    if BElfVRDB and BElfVRDB.verbose then
        Log("Voice scope accepted via " .. tostring(scopeSource))
    end

    if tooltipIdentity.hasChildMarker then
        Log("Target looks like a child NPC; keeping native voice: " .. tostring(UnitName(unit)))
        return nil
    end

    if not tooltipIdentity.hasBloodElfRace then
        if tooltipIdentity.hasExplicitNonBloodElfRace then
            Log("Target explicitly reports non-Blood-Elf race data (" ..
                tostring(tooltipIdentity.explicitRaceToken or "?") .. "); fallback disabled.")
            return nil
        end

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
end

local function RemoveMutes()
    if BElfVR_NewVoiceIDs then
        for _, id in ipairs(BElfVR_NewVoiceIDs) do
            UnmuteSoundFile(id)
        end
        Log("Unmuted all new voice files.")
    end

    SetTrackedMusicMutesActive(false, nil, "remove mutes")
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
        local introHistoryCount = CountKeys(BElfVRDB.musicIntroHistory)

        ui.musicStatusText:SetText(
            "Music mode: " .. (BElfVRDB.musicEnabled and "Enabled" or "Disabled") ..
            "    Mute tracked supported-zone music: " .. musicMuteState ..
            "\nMusic verbose: " .. musicVerboseState ..
            "    Use intro on fresh entry: " .. introState ..
            "\nIntro default cooldown: " .. tostring(GetConfiguredMusicIntroDefaultCooldown()) .. "s" ..
            "    Stored intro cooldown buckets: " .. tostring(introHistoryCount) ..
            "\nMusic trace recorder: " .. traceState ..
            "    Trace lines stored: " .. traceCount ..
            "\nTracked music mute IDs: " .. musicStats.mutedCount ..
            "    Catalog IDs loaded: " .. musicStats.catalogCount ..
            "\nCatalog families loaded: " .. musicStats.catalogFamilyCount ..
            "    Supplemental IDs loaded: " .. musicStats.supplementalCount ..
            "\nTBC music pools: " .. musicStats.introCount .. " intro / " .. musicStats.dayCount .. " day / " .. musicStats.nightCount .. " night" ..
            "\nRegional TBC pool IDs loaded: " .. musicStats.regionalCount ..
            "\nCurrent injected track: " .. currentTrack .. " (" .. currentPool .. ")" ..
            "\nBehavior: replacement music runs only while tracked supported-zone music muting is active."
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
        EvaluateMusicState("music enabled", true)
    else
        SetTrackedMusicMutesActive(false, nil, "music disabled")
        ResetMusicState(true)
    end

    RefreshUI()
end

local function SetMusicMuteEnabled(enabled)
    BElfVRDB.muteNewMusic = enabled and true or false

    if BElfVRDB.enabled and BElfVRDB.musicEnabled and BElfVRDB.muteNewMusic then
        EvaluateMusicState("music mute enabled", true)
    else
        SetTrackedMusicMutesActive(false, nil, "music mute disabled")
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

    if not BElfVRDB.suppressNativeDialog then
        RestoreNativeDialogSetting()
    end

    RefreshUI()
end

local function BeginStartupMusicChannelPurge(reason)
    if state.musicStartupPurgeInProgress then
        return true
    end

    if not (SetCVar and GetCVar and C_Timer and C_Timer.After) then
        return false
    end

    local currentMusicEnabled = tostring(GetCVar("Sound_EnableMusic") or "1")
    if currentMusicEnabled ~= "1" then
        return false
    end

    state.musicStartupPurgeInProgress = true
    state.musicStartupPurgeIgnoreNextCVar = false
    state.musicStartupPurgeReason = tostring(reason or "startup purge")

    RememberPendingCVarRestore("Sound_EnableMusic", currentMusicEnabled)
    LogMusic("Temporarily toggling Sound_EnableMusic to flush lingering pre-reload addon music.")
    RecordMusicTrace("Startup purge begin reason=" .. tostring(reason or "startup purge"))

    SetCVar("Sound_EnableMusic", "0")

    C_Timer.After(MUSIC_STARTUP_PURGE_DELAY_SECONDS, function()
        local restoreValue = GetPendingCVarRestore("Sound_EnableMusic") or currentMusicEnabled
        local resumedReason = state.musicStartupPurgeReason or "startup purge"
        local resumeContext = GetMusicContext()
        local shouldMuteTrackedMusic = resumeContext.supported and IsMusicReplacementActive()

        SetTrackedMusicMutesActive(shouldMuteTrackedMusic, resumeContext.regionKey, resumedReason .. " pre-enable")

        if StopMusic then
            StopMusic()
            state.musicLastNativeStopAt = GetTime()
        end

        if GetCVar("Sound_EnableMusic") ~= tostring(restoreValue) then
            state.musicStartupPurgeIgnoreNextCVar = true
            SetCVar("Sound_EnableMusic", tostring(restoreValue))

            if StopMusic then
                StopMusic()
                state.musicLastNativeStopAt = GetTime()
            end
        end

        ClearPendingCVarRestore("Sound_EnableMusic")
        state.musicStartupPurgeInProgress = false

        state.musicStartupPurgeReason = nil
        if resumeContext.supported and IsMusicReplacementActive() and IsGlobalMusicEnabled() then
            state.musicPendingWorldEntry = false
            state.musicSkipIntroOnWorldEntry = true
            ArmWorldEntryMusicSettle(resumedReason)
        end

        EvaluateMusicState(resumedReason .. " resume", true)
        RefreshUI()
    end)

    return true
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
        print("|cffFFD700[BElfVR]|r guid=" .. FormatDebugValue(guid, "<protected-guid>") .. " forced to |cffFFFFFF" .. value .. "|r voices.")
    else
        BElfVRDB.guidGenderOverrides[guid] = nil
        print("|cffFFD700[BElfVR]|r Cleared gender override for guid=" .. FormatDebugValue(guid, "<protected-guid>") .. ".")
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
        print("|cffFFD700[BElfVR]|r guid=" .. FormatDebugValue(guid, "<protected-guid>") .. " forced to |cffFFFFFF" .. value .. "|r role voices.")
    else
        BElfVRDB.guidRoleOverrides[guid] = nil
        print("|cffFFD700[BElfVR]|r Cleared role override for guid=" .. FormatDebugValue(guid, "<protected-guid>") .. ".")
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
    section:SetPoint("TOPLEFT", parent, "TOPLEFT", SETTINGS_CONTENT_SIDE_MARGIN, -96)
    section:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", SETTINGS_CONTENT_SIDE_MARGIN, 12)
    section:SetWidth(SETTINGS_CONTENT_WIDTH)
    return section
end

local function ApplyCoverTexCoords(texture, frameWidth, frameHeight, sourceAspect)
    if not texture or not frameWidth or not frameHeight or frameWidth <= 0 or frameHeight <= 0 then
        return
    end

    local frameAspect = frameWidth / frameHeight
    local containWidth, containHeight
    local coverWidth, coverHeight

    if frameAspect > sourceAspect then
        containHeight = frameHeight
        containWidth = containHeight * sourceAspect
        coverWidth = frameWidth
        coverHeight = coverWidth / sourceAspect
    else
        containWidth = frameWidth
        containHeight = containWidth / sourceAspect
        coverHeight = frameHeight
        coverWidth = coverHeight * sourceAspect
    end

    local blend = UI_ART_FIT_BLEND
    if blend < 0 then
        blend = 0
    elseif blend > 1 then
        blend = 1
    end

    local targetWidth = containWidth + (coverWidth - containWidth) * blend
    local targetHeight = containHeight + (coverHeight - containHeight) * blend
    local scaleX = tonumber(UI_ART_SCALE_X) or 1
    local scaleY = tonumber(UI_ART_SCALE_Y) or 1
    if scaleX <= 0 then
        scaleX = 1
    end
    if scaleY <= 0 then
        scaleY = 1
    end
    targetWidth = targetWidth * scaleX
    targetHeight = targetHeight * scaleY

    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetSize(targetWidth, targetHeight)
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

    local panel = CreateFrame("Frame", "BElfRestoreUI", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(SETTINGS_UI_WIDTH, SETTINGS_UI_HEIGHT)
    panel:SetPoint("CENTER")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:Hide()
    tinsert(UISpecialFrames, panel:GetName())

    local artHost = CreateFrame("Frame", nil, panel)
    artHost:SetPoint("TOPLEFT", panel, "TOPLEFT", UI_ART_MARGIN_LEFT, -UI_ART_MARGIN_TOP)
    artHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -UI_ART_MARGIN_RIGHT, UI_ART_MARGIN_BOTTOM)
    if artHost.SetClipsChildren then
        artHost:SetClipsChildren(true)
    end

    local artLayer = artHost:CreateTexture(nil, "BORDER", nil, -8)
    artLayer:SetPoint("CENTER", artHost, "CENTER")
    artLayer:SetAlpha(UI_ART_ALPHA)
    artLayer:SetHorizTile(false)
    artLayer:SetVertTile(false)
    artLayer:SetTexture(UI_ART_PATH)
    if not artLayer:GetTexture() then
        artLayer:SetTexture(UI_ART_PATH_WITH_EXT)
    end
    if not artLayer:GetTexture() then
        artLayer:SetColorTexture(0, 0, 0, 0)
    end
    panel:SetScript("OnSizeChanged", function(self, width, height)
        local contentWidth = artHost:GetWidth()
        local contentHeight = artHost:GetHeight()
        if contentWidth <= 1 or contentHeight <= 1 then
            contentWidth = math.max(1, width - (UI_ART_MARGIN_LEFT + UI_ART_MARGIN_RIGHT))
            contentHeight = math.max(1, height - (UI_ART_MARGIN_TOP + UI_ART_MARGIN_BOTTOM))
        end
        ApplyCoverTexCoords(artLayer, contentWidth, contentHeight, UI_ART_ASPECT_RATIO)
    end)
    ApplyCoverTexCoords(
        artLayer,
        panel:GetWidth() - (UI_ART_MARGIN_LEFT + UI_ART_MARGIN_RIGHT),
        panel:GetHeight() - (UI_ART_MARGIN_TOP + UI_ART_MARGIN_BOTTOM),
        UI_ART_ASPECT_RATIO
    )

    panel.TitleText:SetText("Blood Elf Restore")
    -- Keep both globals so legacy macros/scripts keep working after the UI frame rename.
    _G.BElfRestoreUI = panel
    _G.BElfVoiceRestoreUI = panel

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", SETTINGS_CONTENT_SIDE_MARGIN + 4, -34)
    subtitle:SetWidth(SETTINGS_CONTENT_WIDTH - 16)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Controls for restoring TBC Blood Elf voices and Midnight Quel'Thalas music replacement.")

    ui.voiceTabButton = CreateActionButton(panel, SETTINGS_TAB_BUTTON_WIDTH, SETTINGS_TAB_BUTTON_HEIGHT, "Voice", SETTINGS_TAB_START_X, -60, function()
        SetSettingsTab("voice")
    end)
    ui.musicTabButton = CreateActionButton(panel, SETTINGS_TAB_BUTTON_WIDTH, SETTINGS_TAB_BUTTON_HEIGHT, "Music", SETTINGS_TAB_START_X + SETTINGS_TAB_BUTTON_WIDTH + SETTINGS_TAB_BUTTON_GAP, -60, function()
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
    ui.statusText:SetWidth(SETTINGS_CONTENT_WIDTH - 16)
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

    ui.musicMuteCheckbox = CreateCheckbox(musicSection, 2, -60, "Mute tracked supported-zone music files",
        "Silences the tracked Midnight and Blizzard zone-music IDs used in supported Midnight Quel'Thalas areas so the addon's TBC music can replace them cleanly.",
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
    ui.musicStatusText:SetWidth(SETTINGS_CONTENT_WIDTH - 16)
    ui.musicStatusText:SetJustifyH("LEFT")
    ui.musicStatusText:SetJustifyV("TOP")

    local musicTestIntroButton = CreateActionButton(musicSection, 140, 24, "Test Intro", 6, -300, function()
        local introPool = GetMusicTrackPool(MUSIC_REGION_SILVERMOON, "intro")
        local trackID = introPool and introPool[1]
        if trackID then
            PlayMusicTrack(trackID, "intro", "manual test")
            RefreshUI()
        end
    end)
    local musicTestDayButton = CreateActionButton(musicSection, 140, 24, "Test Day", 152, -300, function()
        local pool = GetMusicTrackPool(MUSIC_REGION_SILVERMOON, "day")
        local trackID = ChooseMusicTrack("day", pool)
        if trackID then
            PlayMusicTrack(trackID, "day", "manual test")
            RefreshUI()
        end
    end)
    local musicTestNightButton = CreateActionButton(musicSection, 140, 24, "Test Night", 298, -300, function()
        local pool = GetMusicTrackPool(MUSIC_REGION_SILVERMOON, "night")
        local trackID = ChooseMusicTrack("night", pool)
        if trackID then
            PlayMusicTrack(trackID, "night", "manual test")
            RefreshUI()
        end
    end)
    local musicReapplyButton = CreateActionButton(musicSection, 212, 24, "Re-apply Music Mutes", 6, -332, function()
        SetMusicMuteEnabled(true)
        if BElfVRDB.enabled and BElfVRDB.musicEnabled then
            print("|cff7FD4FF[BElfVR Music]|r Music mutes enabled and reapplied.")
        else
            print("|cff7FD4FF[BElfVR Music]|r Music mute option enabled. Mutes will apply when music logic is active.")
        end
    end)
    local musicClearTraceButton = CreateActionButton(musicSection, 212, 24, "Clear Music Trace", 224, -332, function()
        BElfVRDB.musicTraceLog = {}
        if BElfVRDB.musicTraceEnabled then
            RecordMusicTrace("Trace log cleared.")
        end
        RefreshUI()
        print("|cff7FD4FF[BElfVR Music]|r Cleared the recorded music trace buffer.")
    end)
    local musicRestoreButton = CreateActionButton(musicSection, 212, 24, "Restore Midnight Music", 6, -364, function()
        SetMusicMuteEnabled(false)
        print("|cff7FD4FF[BElfVR Music]|r Unmuted all tracked supported-zone music IDs.")
    end)
    local musicRefreshButton = CreateActionButton(musicSection, 212, 24, "Force Music Refresh", 224, -364, function()
        EvaluateMusicState("manual ui refresh", true)
        RefreshUI()
        print("|cff7FD4FF[BElfVR Music]|r Forced a music re-evaluation.")
    end)

    -- Anchor music actions under the live status block so added status
    -- lines do not overlap the buttons on future refactors.
    musicTestIntroButton:ClearAllPoints()
    musicTestIntroButton:SetPoint("TOPLEFT", ui.musicStatusText, "BOTTOMLEFT", 0, -16)
    musicTestDayButton:ClearAllPoints()
    musicTestDayButton:SetPoint("TOPLEFT", musicTestIntroButton, "TOPRIGHT", 6, 0)
    musicTestNightButton:ClearAllPoints()
    musicTestNightButton:SetPoint("TOPLEFT", musicTestDayButton, "TOPRIGHT", 6, 0)

    musicReapplyButton:ClearAllPoints()
    musicReapplyButton:SetPoint("TOPLEFT", musicTestIntroButton, "BOTTOMLEFT", 0, -8)
    musicClearTraceButton:ClearAllPoints()
    musicClearTraceButton:SetPoint("TOPLEFT", musicReapplyButton, "TOPRIGHT", 6, 0)

    musicRestoreButton:ClearAllPoints()
    musicRestoreButton:SetPoint("TOPLEFT", musicReapplyButton, "BOTTOMLEFT", 0, -8)
    musicRefreshButton:ClearAllPoints()
    musicRefreshButton:SetPoint("TOPLEFT", musicRestoreButton, "TOPRIGHT", 6, 0)

    ui.panel = panel
    SetSettingsTab("voice")
    RefreshUI()

    return panel
end

local function ShowSettingsUI()
    local panel = CreateSettingsUI()
    if not panel then
        return
    end
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
        " guid=" .. FormatDebugValue(guid, "<protected-guid>"))

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
        if elapsed <= BYE_GRACE_PERIOD and elapsed >= TARGET_LOSS_BYE_DELAY and elapsed <= TARGET_LOSS_BYE_MAX_AGE then
            Log("Triggering target-loss bye for target=" .. tostring(state.lastTargetName or "<unknown>") ..
                " npc=" .. tostring(GetNPCIDFromGUID(state.lastTargetGUID) or "?"))
            PlayRandomTBC(state.lastNPCGender, "bye", state.lastNPCRole, true)
        elseif elapsed < TARGET_LOSS_BYE_DELAY then
            Log("Skipping target-loss bye for target=" .. tostring(state.lastTargetName or "<unknown>") ..
                " because target was not held long enough.")
        elseif elapsed > TARGET_LOSS_BYE_MAX_AGE then
            Log("Skipping target-loss bye for target=" .. tostring(state.lastTargetName or "<unknown>") ..
                " because the target was lost too late to sound believable.")
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

    if not CanPlayTargetSelectGreeting("target") then
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
    if guid == state.lastTargetChangeGUID and (now - state.lastTargetChangeTime) < TARGET_SELECT_DEDUPE_WINDOW then
        return
    end

    -- Hidden-race fallback on target-select is restricted to positive
    -- Blood Elf name/profile hints, not generic humanoids.
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
frame:RegisterEvent("CVAR_UPDATE")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end

        BElfVRDB = BElfVRDB or {}
        for key, value in pairs(DB_DEFAULTS) do
            if BElfVRDB[key] == nil then
                BElfVRDB[key] = value
            end
        end
        MigrateSavedVariables()
        RestoreInterruptedTemporaryCVars("addon loaded")

    elseif event == "PLAYER_LOGIN" then
        CreateSettingsUI()
        ApplyMutes()
        RefreshUI()
        print("|cffFFD700[BElfRestore]|r Loaded. Type |cffFFFFFF/belr|r to open the UI (legacy |cffFFFFFF/belvr|r also works).")

    elseif event == "PLAYER_ENTERING_WORLD" then
        local startupMusicContext = GetMusicContext()
        local shouldHandleWorldEntryMusic = IsMusicReplacementActive()
            and IsGlobalMusicEnabled()
        state.musicPendingWorldEntry = shouldHandleWorldEntryMusic and true or false
        state.musicSkipIntroOnWorldEntry = false
        state.musicWorldEntrySuppressUntil = 0
        local shouldPurgeStartupMusic = shouldHandleWorldEntryMusic
            and startupMusicContext.supported
            and IsMusicReplacementActive()
            and IsGlobalMusicEnabled()

        if not shouldPurgeStartupMusic or not BeginStartupMusicChannelPurge("entering world") then
            EvaluateMusicState("entering world", true)
        end
        RefreshUI()

    elseif event == "PLAYER_TARGET_CHANGED" then
        OnTargetChanged()

    elseif event == "GOSSIP_SHOW" then
        OnGossipShow()

    elseif event == "GOSSIP_CLOSED" then
        OnGossipClosed()

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        local areaMusicContext = GetMusicContext()
        if areaMusicContext.supported and IsMusicReplacementActive() and IsGlobalMusicEnabled() then
            state.musicPendingWorldEntry = false
            state.musicSkipIntroOnWorldEntry = true
            if (state.musicWorldEntrySuppressUntil or 0) <= GetTime() then
                ArmWorldEntryMusicSettle(event)
            end
        end

        EvaluateMusicState(event, false)
        RefreshUI()

    elseif event == "ZONE_CHANGED" or
           event == "ZONE_CHANGED_INDOORS" or
           event == "PLAYER_UPDATE_RESTING" then
        -- Let the music logic decide whether a real playback refresh
        -- is warranted. These events still update trace logs, but we
        -- should not hard-refresh the track on every tiny subzone or
        -- resting flag flip.
        EvaluateMusicState(event, false)
        RefreshUI()

    elseif event == "CVAR_UPDATE" then
        local cvarName = tostring(arg1 or "")
        if cvarName == "Sound_EnableMusic" then
            if state.musicStartupPurgeInProgress then
                RefreshUI()
                return
            end

            if state.musicStartupPurgeIgnoreNextCVar then
                state.musicStartupPurgeIgnoreNextCVar = false
                RefreshUI()
                return
            end
        end

        if cvarName == "Sound_EnableMusic" or cvarName == "Sound_EnableAllSound" then
            EvaluateMusicState(event .. ":" .. cvarName, true)
            RefreshUI()
        end
    elseif event == "PLAYER_LOGOUT" then
        ShutdownMusicState("player logout")
    end
end)

frame:SetScript("OnUpdate", function(self, elapsed)
    if not BElfVRDB then
        return
    end
    if not IsMusicReplacementActive() then
        return
    end

    local worldEntrySettleActive = (state.musicWorldEntrySuppressUntil or 0) > GetTime()
    if state.musicWasInSupportedZone and IsGlobalMusicEnabled() and
        ((state.musicHandle or state.musicCurrentTrackID) or worldEntrySettleActive) then
        EnforceNativeMusicSuppression("heartbeat", false)
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

local function HandleSlashCommand(input)
    local rawInput = input or ""
    local cmd = strtrim(rawInput:lower())

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
        print("|cff7FD4FF[BElfVR Music]|r Tracked supported-zone music muting: |cff00FF00ON|r")

    elseif cmd == "music mute off" then
        SetMusicMuteEnabled(false)
        print("|cff7FD4FF[BElfVR Music]|r Tracked supported-zone music muting: |cffFF4444OFF|r")

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

    elseif cmd == "music note" or strsub(cmd, 1, 11) == "music note " then
        local noteText = rawInput:match("^%s*[Mm][Uu][Ss][Ii][Cc]%s+[Nn][Oo][Tt][Ee]%s*(.*)$")
        noteText = strtrim(tostring(noteText or ""))
        if noteText == "" then
            noteText = "<none>"
        end
        noteText = noteText:gsub("[%c]+", " "):gsub("\"", "'")

        local context = GetMusicContext()
        local zoneName = context.zoneName ~= "" and context.zoneName or "<none>"
        local subZoneName = context.subZoneName ~= "" and context.subZoneName or "<none>"
        local regionName = context.regionKey or "<none>"

        local wrote = AppendMusicTraceLine(
            "NOTE text=\"" .. noteText ..
            "\" zone=" .. zoneName ..
            " subzone=" .. subZoneName ..
            " region=" .. tostring(regionName)
        )

        if wrote then
            if BElfVRDB.musicTraceEnabled then
                print("|cff7FD4FF[BElfVR Music]|r Added note to music trace.")
            else
                print("|cff7FD4FF[BElfVR Music]|r Added note to SavedVariables trace buffer (trace toggle is currently OFF).")
            end
        end
        RefreshUI()

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
        local context = GetMusicContext()
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
        print("  Intro default CD : " .. tostring(GetConfiguredMusicIntroDefaultCooldown()) .. "s")
        print("  Intro history    : " .. tostring(CountKeys(BElfVRDB.musicIntroHistory)) .. " bucket(s)")
        print("  Music muted IDs  : " .. musicStats.mutedCount)
        print("  Catalog music IDs: " .. musicStats.catalogCount .. " across " .. musicStats.catalogFamilyCount .. " families")
        print("  Supplemental IDs : " .. musicStats.supplementalCount)
        print("  TBC music  : " .. musicStats.introCount .. " intro / " .. musicStats.dayCount .. " day / " .. musicStats.nightCount .. " night")
        print("  Current music    : " .. tostring(state.musicCurrentTrackID or "none") .. " (" .. tostring(state.musicCurrentPool or "none") .. ")")
        print("  Music zone       : " .. tostring(context.zoneName ~= "" and context.zoneName or "<none>"))
        print("  Music subzone    : " .. tostring(context.subZoneName ~= "" and context.subZoneName or "<none>"))
        print("  Music region     : " .. tostring(context.regionKey or "<none>") ..
            " scope=" .. tostring(context.inMusicScope) ..
            " scopeSource=" .. tostring(context.musicScopeSource or "none") ..
            " overrideSource=" .. tostring(context.overrideMatchSource or "none"))
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
        print("  |cffFFFFFF/belr|r                                  open the UI")
        print("  |cffFFFFFF/belr on|r / |cffFFFFFF/belr off|r      enable or disable the addon")
        print("  |cffFFFFFF/belr mute on|r / |cffFFFFFF/belr mute off|r")
        print("                                              toggle muting of new voices")
        print("  |cffFFFFFF/belr verbose|r / |cffFFFFFF/belr verbose on|r / |cffFFFFFF/belr verbose off|r")
        print("                                              toggle or set debug output in chat")
        print("  |cffFFFFFF/belr music on|r / |cffFFFFFF/belr music off|r")
        print("                                              enable or disable the music replacement system")
        print("  |cffFFFFFF/belr music mute on|r / |cffFFFFFF/belr music mute off|r")
        print("                                              toggle muting of tracked supported-zone music IDs")
        print("  |cffFFFFFF/belr music verbose|r / |cffFFFFFF/belr music verbose on|r / |cffFFFFFF/belr music verbose off|r")
        print("                                              toggle or set music routing debug output in chat")
        print("  |cffFFFFFF/belr music trace on|r / |cffFFFFFF/belr music trace off|r / |cffFFFFFF/belr music trace clear|r")
        print("                                              record music routing lines into SavedVariables for later review")
        print("  |cffFFFFFF/belr music note <text>|r")
        print("                                              add a manual marker line to the music trace buffer")
        print("  |cffFFFFFF/belr music intro on|r / |cffFFFFFF/belr music intro off|r")
        print("                                              toggle the intro cue when entering the supported region")
        print("  |cffFFFFFF/belr music now|r / |cffFFFFFF/belr music stop|r")
        print("                                              force a music re-check or stop injected music")
        print("  |cffFFFFFF/belr fallback on|r / |cffFFFFFF/belr fallback off|r")
        print("                                              allow humanoid NPC fallback when race is hidden")
        print("  |cffFFFFFF/belr target on|r / |cffFFFFFF/belr target off|r")
        print("                                              toggle greet playback on left-click target")
        print("  |cffFFFFFF/belr invert|r / |cffFFFFFF/belr invert on|r / |cffFFFFFF/belr invert off|r")
        print("                                              toggle or set the reversed NPC sex mapping")
        print("  |cffFFFFFF/belr suppress|r / |cffFFFFFF/belr suppress on|r / |cffFFFFFF/belr suppress off|r")
        print("                                              toggle or set native dialog suppression during injected playback")
        print("  |cffFFFFFF/belr force male|r / |cffFFFFFF/belr force female|r / |cffFFFFFF/belr force clear|r")
        print("                                              override only the current target's exact NPC GUID")
        print("  |cffFFFFFF/belr force-name male|r / |cffFFFFFF/belr force-name female|r / |cffFFFFFF/belr force-name clear|r")
        print("                                              override all matching NPCs by the current target's name")
        print("  |cffFFFFFF/belr role military|r / |cffFFFFFF/belr role noble|r / |cffFFFFFF/belr role standard|r / |cffFFFFFF/belr role clear|r")
        print("                                              override only the current target's exact NPC GUID")
        print("  |cffFFFFFF/belr role-name military|r / |cffFFFFFF/belr role-name noble|r / |cffFFFFFF/belr role-name standard|r / |cffFFFFFF/belr role-name clear|r")
        print("                                              override all matching NPCs by the current target's name")
        print("  |cffFFFFFF/belr status|r                           show current state and loaded sound counts")
        print("  |cffFFFFFF/belr test male greet|r / |cffFFFFFF/belr test male bye|r / |cffFFFFFF/belr test male pissed|r")
        print("  |cffFFFFFF/belr test female greet|r / |cffFFFFFF/belr test female bye|r / |cffFFFFFF/belr test female pissed|r")
        print("  |cffFFFFFF/belr test music intro|r / |cffFFFFFF/belr test music day|r / |cffFFFFFF/belr test music night|r")
        print("  |cffFFFFFF/belvr ...|r                             legacy alias (same command set)")
    end
end

SLASH_BELR1 = "/belr"
SLASH_BELVR1 = "/belvr"
SlashCmdList["BELR"] = HandleSlashCommand
SlashCmdList["BELVR"] = HandleSlashCommand
