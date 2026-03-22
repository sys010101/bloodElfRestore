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
	
	-- WoW API - missing string helper
    "strsub",

    -- Internal addon config helpers (defined as globals in BElfRestore.lua)
    "GetUserConfigRoot", "GetConfigValue", "GetConfigBoolean",
    "GetConfigNumber", "GetConfigInteger", "GetConfigString",
    "NormalizeUserConfigKey",
    "BuildNormalizedStringSet", "BuildNormalizedStringList",
    "BuildNormalizedStringMap", "BuildNormalizedNPCOverrideMap",
    "BuildNormalizedNameProfileMap",

    -- Internal addon constants - voice behavior
    "PISSED_CLICK_THRESHOLD", "PISSED_CLICK_WINDOW",
    "BYE_GRACE_PERIOD", "TARGET_LOSS_BYE_DELAY", "TARGET_LOSS_BYE_MAX_AGE",
    "MIN_PLAYBACK_GAP", "DIALOG_SUPPRESSION_WINDOW",
    "RANGE_TIER_NEAR_CHANCE", "RANGE_TIER_FAR_CHANCE",
    "TARGET_SELECT_DEDUPE_WINDOW",

    -- Internal addon constants - voice scope and classification
    "BLOOD_ELF_FALLBACK_ZONES", "BLOOD_ELF_VOICE_SCOPE_TOKENS",
    "BLOOD_ELF_VOICE_NATIVE_ONLY_TOKENS",
    "BLOOD_ELF_TOOLTIP_RACE_TOKENS", "BLOOD_ELF_TOOLTIP_CHILD_TOKENS",
    "CHILD_NAME_TOKENS", "BLOOD_ELF_HIDDEN_RACE_NAME_TOKENS",
    "KNOWN_NON_BLOOD_ELF_RACE_TOKENS",
    "MILITARY_ROLE_NAME_TOKENS", "NOBLE_ROLE_NAME_TOKENS",
    "DEFAULT_GENDER_OVERRIDES", "DEFAULT_ROLE_OVERRIDES", "DEFAULT_NAME_PROFILES",

    -- Internal addon constants - music scope
    "BLOOD_ELF_MUSIC_ZONES", "BLOOD_ELF_MUSIC_SUBZONES",
    "BLOOD_ELF_MUSIC_SCOPE_TOKENS", "BLOOD_ELF_MUSIC_NATIVE_ONLY_TOKENS",

    -- Internal addon constants - music regions
    "MUSIC_REGION_SILVERMOON", "MUSIC_REGION_SILVERMOON_INTERIOR",
    "MUSIC_REGION_EVERSONG", "MUSIC_REGION_SUNSTRIDER",
    "MUSIC_REGION_EVERSONG_SOUTH", "MUSIC_REGION_DEATHOLME",
    "MUSIC_REGION_AMANI", "MUSIC_REGION_LEGACY_GHOSTLANDS",

    -- Internal addon constants - music routing
    "MUSIC_ZONE_REGION_OVERRIDES", "MUSIC_SUBZONE_REGION_OVERRIDES",
    "MUSIC_SUBZONE_REGION_TOKEN_OVERRIDES",
    "MUSIC_NORMALIZED_SUBZONE_PATTERN_REGION_OVERRIDES",
    "DEFAULT_SUPPORTED_SUBZONE_REGION", "RAW_DEFAULT_SUPPORTED_SUBZONE_REGION",
    "MUSIC_NATIVE_AMBIENCE_SUPPRESS_REGIONS",

    -- Internal addon constants - music timing and playback
    "MUSIC_UPDATE_INTERVAL", "MUSIC_TRACK_ROTATE_SECONDS",
    "MUSIC_REPEAT_COOLDOWN", "MUSIC_INTRO_REPEAT_COOLDOWN",
    "MUSIC_TRANSITION_FADE_MS", "MUSIC_END_GRACE_SECONDS",
    "MUSIC_FORCE_STOP_NATIVE_BEFORE_REPLACEMENT", "MUSIC_NATIVE_GUARD_INTERVAL",
    "MUSIC_PLAYBACK_CHANNEL", "MUSIC_SUPPRESS_NATIVE_WITH_VOLUME",
    "MUSIC_NATIVE_SUPPRESS_VOLUME", "MUSIC_DAY_START_HOUR", "MUSIC_NIGHT_START_HOUR",
    "MUSIC_STARTUP_PURGE_DELAY_SECONDS", "MUSIC_WORLD_ENTRY_SETTLE_SECONDS",
    "MUSIC_TRACE_MAX_ENTRIES",

    -- Internal addon constants - UI
    "UI_ART_PATH", "UI_ART_PATH_WITH_EXT", "UI_ART_ASPECT_RATIO",
    "UI_ART_ALPHA", "UI_ART_FIT_BLEND", "UI_ART_SCALE_X", "UI_ART_SCALE_Y",
    "UI_ART_MARGIN_LEFT", "UI_ART_MARGIN_RIGHT",
    "UI_ART_MARGIN_TOP", "UI_ART_MARGIN_BOTTOM",
    "SETTINGS_UI_WIDTH", "SETTINGS_UI_HEIGHT", "SETTINGS_CONTENT_WIDTH",
    "SETTINGS_CONTENT_SIDE_MARGIN", "SETTINGS_TAB_BUTTON_WIDTH",
    "SETTINGS_TAB_BUTTON_HEIGHT", "SETTINGS_TAB_BUTTON_GAP",
    "SETTINGS_TAB_GROUP_WIDTH", "SETTINGS_TAB_START_X",

    -- Internal addon helper functions
    "NormalizeMusicRegionKey", "NormalizeAreaMatchToken",
    "AreaHasVoiceNativeOnly", "AreaHasNativeOnlyMusic",
    "GetCurrentMapLineageTokens", "ResolveBloodElfMusicScope",
    "ResolveMusicSubZoneRegionOverride",

    -- Internal addon music intro functions
    "GetUserMusicIntroCooldownConfig", "NormalizeConfiguredCooldownSeconds",
    "GetStableTimestampSeconds", "BuildMusicLocationRuleKey",
    "BuildMusicPoolRuleKey", "GetMusicIntroHistoryStore",
    "AddMusicIntroCooldownBucket", "BuildMusicIntroCooldownBuckets",
    "ShouldPlayMusicIntro", "RememberMusicIntroPlayback",
    "GetConfiguredMusicIntroDefaultCooldown",
}