-- luacheck configuration for bloodElfRestore
-- https://luacheck.readthedocs.io/en/stable/

std = "lua51"
max_line_length = false
unused_args = false

-- W111 / W112: global writes and modifications are suppressed intentionally.
-- Reason: SavedVariables, cross-file data tables, and slash command registration
-- all require writing to globals by WoW addon design. These are not bugs.
-- W113 (undefined global read) remains ACTIVE to catch typos like MutSoundFile.
ignore = {"111", "112"}

globals = {
    -- WoW API - Frame / UI
    "CreateFrame", "UIParent", "WorldFrame",
    "GameTooltip", "UISpecialFrames",
    "GossipFrame", "MerchantFrame",

    -- WoW API - Unit queries
    "UnitExists", "UnitIsPlayer", "UnitSex", "UnitRace",
    "UnitName", "UnitGUID", "UnitCreatureType",
    "UnitCanAttack", "UnitIsDeadOrGhost",

    -- WoW API - Zone / Map
    "GetRealZoneText", "GetZoneText", "GetSubZoneText", "C_Map",

    -- WoW API - CVars
    "GetCVar", "SetCVar",

    -- WoW API - Sound
    "MuteSoundFile", "UnmuteSoundFile",
    "PlaySoundFile", "StopSound", "StopMusic",

    -- WoW API - Time / State
    "GetTime", "GetServerTime", "GetGameTime",
    "IsResting", "IsIndoors",
    "CheckInteractDistance",
    "date", "time",

    -- WoW API - Timer / AddOn
    "C_Timer",
    "C_AddOns", "IsAddOnLoaded", "EnableAddOn", "LoadAddOn",

    -- WoW API - Non-standard string and table helpers
    "tinsert", "tremove", "wipe",
    "strsplit", "strfind", "strtrim",

    -- WoW API - Slash commands
    "SlashCmdList",

    -- Optional dependency: DebugChatFrame addon
    "DebugChatFrame", "DCF_ConsoleMonoCondensedSemiBold",

    -- SavedVariables
    "BElfVRDB",

    -- Cross-file addon data (defined in SoundData.lua, Midnight_ID_catalog.lua, etc.)
    "BElfVR_Config",
    "BElfVR_NewVoiceIDs",
    "BElfVR_NewMusicIDs",
    "BElfVR_SupplementalMusicMuteIDs",
    "BElfVR_RegionalMusicMuteIDs",
    "BElfVR_TBCVoices_Male",
    "BElfVR_TBCVoices_Female",
    "BElfVR_TBCMusic",
    "BElfVR_TBCMusicRegions",
    "BElfVR_TBCMusicDurations",
    "BElfVR_MidnightMusicCatalog",
    "BElfVR_MidnightMusicFamilyIDs",
    "BElfVR_MidnightAllMusicIDs",
    "BElfVR_MidnightIDCatalogMeta",
    "BElfVR_TBCIDCatalogMeta",
    "BElfVR_TBCZoneMusicCatalog",

    -- Cross-file addon functions (defined in Debug.lua, used in BElfRestore.lua)
    "BElfVR_InitDebug",
    "BElfVR_ShowLogDump",
    "BElfVR_ClearLog",
    "BElfVR_DebugFrame",
    "c",
    "cp",
}