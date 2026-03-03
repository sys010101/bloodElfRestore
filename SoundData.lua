-- ============================================================
--  BElfVoiceRestore - SoundData.lua
--  All FileDataIDs are sourced from wow.tools (build 66198)
--
--  HOW TO POPULATE:
--  1. Go to https://www.wowhead.com/sounds/
--  2. Search / Filter: "any combination of bloodelffemale or bloodelfmale for the TBC ones and generic_blood_elf for the new Midnight ones"
--  3. New 12.0 files go into BElfVR_NewVoiceIDs
--  4. Old TBC files go into the correct category below
--
--  COMMUNITY EDIT NOTES:
--  - Keep entries grouped by voice family and keep the existing order inside each table.
--  - The addon splits the TBC greet tables into role pools by position:
--    noble block first, then standard block, then military block.
--  - Inside each role block, vendor lines should stay together and greeting lines should stay together.
--  - If you add/remove/reorder entries in the TBC tables, also update the role layout offsets in BElfVoiceRestore.lua.
--  - To add new Midnight mute IDs, append them to BElfVR_NewVoiceIDs.
--  - To add new TBC sounds, append them to the matching male/female table in the correct subgroup.
-- ============================================================


-- ============================================================
--  NEW VOICES - Midnight 12.0.1 build 66198
--  Muted entirely. Both male and female new lines go here.
-- ============================================================
BElfVR_NewVoiceIDs = {
    -- ============================================================
    -- MALE - new Midnight 12.0 citizen voices to be muted
    -- ============================================================

    -- Source: VO_120_Generic_Blood_Elf_Citizen_A_02_M
    7433708, -- VO_120_Generic_Blood_Elf_Citizen_A_02_M.ogg
    7433710, -- VO_120_Generic_Blood_Elf_Citizen_A_03_M.ogg
    7433712, -- VO_120_Generic_Blood_Elf_Citizen_A_04_M.ogg
    7433714, -- VO_120_Generic_Blood_Elf_Citizen_A_05_M.ogg
    7433716, -- VO_120_Generic_Blood_Elf_Citizen_A_06_M.ogg
    7433718, -- VO_120_Generic_Blood_Elf_Citizen_A_07_M.ogg
    -- Source: VO_120_Generic_Blood_Elf_Citizen_A_08_M
    7433720, -- VO_120_Generic_Blood_Elf_Citizen_A_08_M.ogg
    7433722, -- VO_120_Generic_Blood_Elf_Citizen_A_09_M.ogg
    7433724, -- VO_120_Generic_Blood_Elf_Citizen_A_10_M.ogg
    7433726, -- VO_120_Generic_Blood_Elf_Citizen_A_11_M.ogg
    7433728, -- VO_120_Generic_Blood_Elf_Citizen_A_12_M.ogg
    7433730, -- VO_120_Generic_Blood_Elf_Citizen_A_13_M.ogg
    7433732, -- VO_120_Generic_Blood_Elf_Citizen_A_14_M.ogg
    -- Source: VO_120_Generic_Blood_Elf_Citizen_A_16_M
    7433736, -- VO_120_Generic_Blood_Elf_Citizen_A_16_M.ogg
    7433738, -- VO_120_Generic_Blood_Elf_Citizen_A_17_M.ogg
    7433740, -- VO_120_Generic_Blood_Elf_Citizen_A_18_M.ogg
    -- Source: VO_120_Generic_Blood_Elf_Citizen_A_19_M
    7433742, -- VO_120_Generic_Blood_Elf_Citizen_A_19_M.ogg
    7433744, -- VO_120_Generic_Blood_Elf_Citizen_A_20_M.ogg
    7433746, -- VO_120_Generic_Blood_Elf_Citizen_A_21_M.ogg
    -- Source: VO_120_Generic_Blood_Elf_Citizen_B_01_M
    7387005, -- VO_120_Generic_Blood_Elf_Citizen_B_01_M.ogg
    7387008, -- VO_120_Generic_Blood_Elf_Citizen_B_02_M.ogg
    7387010, -- VO_120_Generic_Blood_Elf_Citizen_B_03_M.ogg
    7387024, -- VO_120_Generic_Blood_Elf_Citizen_B_04_M.ogg
    7387026, -- VO_120_Generic_Blood_Elf_Citizen_B_05_M.ogg
    7387028, -- VO_120_Generic_Blood_Elf_Citizen_B_06_M.ogg
    7387030, -- VO_120_Generic_Blood_Elf_Citizen_B_07_M.ogg
    -- Source: VO_120_Generic_Blood_Elf_Citizen_B_08_M
    7387032, -- VO_120_Generic_Blood_Elf_Citizen_B_08_M.ogg
    7387034, -- VO_120_Generic_Blood_Elf_Citizen_B_09_M.ogg
    7387036, -- VO_120_Generic_Blood_Elf_Citizen_B_10_M.ogg
    7387038, -- VO_120_Generic_Blood_Elf_Citizen_B_11_M.ogg
    7387040, -- VO_120_Generic_Blood_Elf_Citizen_B_12_M.ogg
    7387042, -- VO_120_Generic_Blood_Elf_Citizen_B_13_M.ogg
    7387044, -- VO_120_Generic_Blood_Elf_Citizen_B_14_M.ogg
    -- Source: VO_120_Generic_Blood_Elf_Citizen_B_16_M
    7387048, -- VO_120_Generic_Blood_Elf_Citizen_B_16_M.ogg
    7387050, -- VO_120_Generic_Blood_Elf_Citizen_B_17_M.ogg
    7387052, -- VO_120_Generic_Blood_Elf_Citizen_B_18_M.ogg
    -- Source: VO_120_Generic_Blood_Elf_Citizen_B_19_M
    7387054, -- VO_120_Generic_Blood_Elf_Citizen_B_19_M.ogg
    7387056, -- VO_120_Generic_Blood_Elf_Citizen_B_20_M.ogg
    7387058, -- VO_120_Generic_Blood_Elf_Citizen_B_21_M.ogg

    -- ============================================================
    -- FEMALE - new Midnight 12.0 citizen voices to be muted
    -- ============================================================

    -- Source: VO_120_Generic_Blood_Elf_Citizen_A_02_F
    7433709, -- VO_120_Generic_Blood_Elf_Citizen_A_02_F.ogg
    7433711, -- VO_120_Generic_Blood_Elf_Citizen_A_03_F.ogg
    7433713, -- VO_120_Generic_Blood_Elf_Citizen_A_04_F.ogg
    7433715, -- VO_120_Generic_Blood_Elf_Citizen_A_05_F.ogg
    7433717, -- VO_120_Generic_Blood_Elf_Citizen_A_06_F.ogg
    7433719, -- VO_120_Generic_Blood_Elf_Citizen_A_07_F.ogg
    -- Source: VO_120_Generic_Blood_Elf_Citizen_A_08_F
    7433721, -- VO_120_Generic_Blood_Elf_Citizen_A_08_F.ogg
    7433723, -- VO_120_Generic_Blood_Elf_Citizen_A_09_F.ogg
    7433725, -- VO_120_Generic_Blood_Elf_Citizen_A_10_F.ogg
    7433727, -- VO_120_Generic_Blood_Elf_Citizen_A_11_F.ogg
    7433729, -- VO_120_Generic_Blood_Elf_Citizen_A_12_F.ogg
    7433731, -- VO_120_Generic_Blood_Elf_Citizen_A_13_F.ogg
    7433733, -- VO_120_Generic_Blood_Elf_Citizen_A_14_F.ogg
    -- Source: VO_120_Generic_Blood_Elf_Citizen_A_16_F
    7433737, -- VO_120_Generic_Blood_Elf_Citizen_A_16_F.ogg
    7433739, -- VO_120_Generic_Blood_Elf_Citizen_A_17_F.ogg
    7433741, -- VO_120_Generic_Blood_Elf_Citizen_A_18_F.ogg
    -- Source: VO_120_Generic_Blood_Elf_Citizen_A_19_F
    7433743, -- VO_120_Generic_Blood_Elf_Citizen_A_19_F.ogg
    7433745, -- VO_120_Generic_Blood_Elf_Citizen_A_20_F.ogg
    7433747, -- VO_120_Generic_Blood_Elf_Citizen_A_21_F.ogg
    -- Source: VO_120_Generic_Blood_Elf_Citizen_B_01_F
    7387007, -- VO_120_Generic_Blood_Elf_Citizen_B_01_F.ogg
    7387009, -- VO_120_Generic_Blood_Elf_Citizen_B_02_F.ogg
    7387011, -- VO_120_Generic_Blood_Elf_Citizen_B_03_F.ogg
    7387025, -- VO_120_Generic_Blood_Elf_Citizen_B_04_F.ogg
    7387027, -- VO_120_Generic_Blood_Elf_Citizen_B_05_F.ogg
    7387029, -- VO_120_Generic_Blood_Elf_Citizen_B_06_F.ogg
    7387031, -- VO_120_Generic_Blood_Elf_Citizen_B_07_F.ogg
    -- Source: VO_120_Generic_Blood_Elf_Citizen_B_08_F
    7387033, -- VO_120_Generic_Blood_Elf_Citizen_B_08_F.ogg
    7387035, -- VO_120_Generic_Blood_Elf_Citizen_B_09_F.ogg
    7387037, -- VO_120_Generic_Blood_Elf_Citizen_B_10_F.ogg
    7387039, -- VO_120_Generic_Blood_Elf_Citizen_B_11_F.ogg
    7387041, -- VO_120_Generic_Blood_Elf_Citizen_B_12_F.ogg
    7387043, -- VO_120_Generic_Blood_Elf_Citizen_B_13_F.ogg
    7387045, -- VO_120_Generic_Blood_Elf_Citizen_B_14_F.ogg
    -- Source: VO_120_Generic_Blood_Elf_Citizen_B_16_F
    7387049, -- VO_120_Generic_Blood_Elf_Citizen_B_16_F.ogg
    7387051, -- VO_120_Generic_Blood_Elf_Citizen_B_17_F.ogg
    7387053, -- VO_120_Generic_Blood_Elf_Citizen_B_18_F.ogg
    -- Source: VO_120_Generic_Blood_Elf_Citizen_B_19_F
    7387055, -- VO_120_Generic_Blood_Elf_Citizen_B_19_F.ogg
    7387057, -- VO_120_Generic_Blood_Elf_Citizen_B_20_F.ogg
    7387059, -- VO_120_Generic_Blood_Elf_Citizen_B_21_F.ogg
}


-- ============================================================
--  NEW MUSIC - Midnight 12.0.x Silvermoon / Eversong tracks
--  These are safe to extend.
--  Add only FileDataIDs that you have verified belong to the new
--  Midnight music set you want muted in this region.
--
--  SAFE TO CHANGE:
--  - You may append new numeric IDs at the end of this list.
--  - You may remove IDs that prove unrelated.
--
--  DO NOT REORDER FOR FUN:
--  - Reordering will not crash the addon, but it makes debugging
--  - and comparing verbose logs harder for anyone sharing notes.
-- ============================================================
BElfVR_NewMusicIDs = {
    7713991, -- mus_1200_silent_207_7713991
    7681090, -- mus_1200_murder_row_7681090
    7681092, -- mus_1200_murder_row_7681092
    7681094, -- mus_1200_murder_row_7681094
    7726826, -- mus_1200_silent_317_7726826
    7713989, -- mus_1200_silent_046_7713989
}


-- ============================================================
--  TBC ORIGINAL MUSIC - Silvermoon
--  These are the replacement tracks the addon can inject on the
--  music channel while you are in the supported Blood Elf zones.
--
--  SAFE TO CHANGE:
--  - You may swap these IDs for verified alternatives.
--  - You may add more IDs to the day/night pools.
--
--  CHANGE WITH CARE:
--  - The `intro`, `day`, and `night` categories are used directly
--  - by the code in BElfVoiceRestore.lua.
--  - Renaming these keys will break playback logic.
-- ============================================================
BElfVR_TBCMusic = {
    intro = {
        53473, -- ES_SilvermoonIntro01
    },
    day = {
        53474, -- ES_SilvermoonWalkDay01
        53475, -- ES_SilvermoonWalkDay02
        53476, -- ES_SilvermoonWalkDay03
    },
    night = {
        53477, -- ES_SilvermoonWalKnight01
        53478, -- ES_SilvermoonWalKnight02
        53479, -- ES_SilvermoonWalKnight03
    },
}


-- ============================================================
--  TBC ORIGINAL VOICES - MALE
--  Still present in the 12.0.1 client. Played on interaction.
-- ============================================================
BElfVR_TBCVoices_Male = {

    greet = {
        -- Source: wowhead.com - BloodElfMaleNobleVendor
        556925, -- NPCBloodElfMaleNobleVendor01.ogg
        556917, -- NPCBloodElfMaleNobleVendor02.ogg
        556923, -- NPCBloodElfMaleNobleVendor03.ogg
        556922, -- NPCBloodElfMaleNobleVendor04.ogg
        556918, -- NPCBloodElfMaleNobleVendor05.ogg
        556929, -- NPCBloodElfMaleNobleVendor06.ogg
        -- Source: wowhead.com - BloodElfMaleNobleGreetings
        556939, -- NPCBloodElfMaleNobleGreeting01.ogg
        556937, -- NPCBloodElfMaleNobleGreeting02.ogg
        556927, -- NPCBloodElfMaleNobleGreeting04.ogg
        556930, -- NPCBloodElfMaleNobleGreeting05.ogg
        556919, -- NPCBloodElfMaleNobleGreeting07.ogg
        556935, -- NPCBloodElfMaleNobleGreeting10.ogg
        556924, -- NPCBloodElfMaleNobleGreeting12.ogg
        -- Source: wowhead.com - BloodElfMaleStandardVendor
        556951, -- NPCBloodElfMaleStandardVendor01.ogg
        556959, -- NPCBloodElfMaleStandardVendor02.ogg
        556943, -- NPCBloodElfMaleStandardVendor03.ogg
        556952, -- NPCBloodElfMaleStandardVendor04.ogg
        556950, -- NPCBloodElfMaleStandardVendor05.ogg
        556953, -- NPCBloodElfMaleStandardVendor06.ogg
        -- Source: wowhead.com - BloodElfMaleStandardGreetings
        556955, -- NPCBloodElfMaleStandardGreeting02.ogg
        556963, -- NPCBloodElfMaleStandardGreeting03.ogg
        556949, -- NPCBloodElfMaleStandardGreeting06.ogg
        556960, -- NPCBloodElfMaleStandardGreeting09.ogg
        556947, -- NPCBloodElfMaleStandardGreeting10.ogg
        556946, -- NPCBloodElfMaleStandardGreeting11.ogg
        -- Source: wowhead.com - BloodElfMaleMilitaryVendor
        556904, -- NPCBloodElfMaleMilitaryVendor01.ogg
        556913, -- NPCBloodElfMaleMilitaryVendor02.ogg
        556902, -- NPCBloodElfMaleMilitaryVendor03.ogg
        556906, -- NPCBloodElfMaleMilitaryVendor04.ogg
        556911, -- NPCBloodElfMaleMilitaryVendor05.ogg
        556908, -- NPCBloodElfMaleMilitaryVendor06.ogg
        -- Source: wowhead.com - BloodElfMaleMilitaryGreetings
        556907, -- NPCBloodElfMaleMilitaryGreeting01.ogg
        556898, -- NPCBloodElfMaleMilitaryGreeting03.ogg
        556899, -- NPCBloodElfMaleMilitaryGreeting04.ogg
        556901, -- NPCBloodElfMaleMilitaryGreeting06.ogg
        556894, -- NPCBloodElfMaleMilitaryGreeting08.ogg
        556897, -- NPCBloodElfMaleMilitaryGreeting10.ogg
    },

    bye = {
        -- Source: wowhead.com - BloodElfMaleNobleFarewell
        556940, -- NPCBloodElfMaleNobleFarewell01.ogg
        556921, -- NPCBloodElfMaleNobleFarewell02.ogg
        556932, -- NPCBloodElfMaleNobleFarewell03.ogg
        556936, -- NPCBloodElfMaleNobleFarewell04.ogg
        556933, -- NPCBloodElfMaleNobleFarewell06.ogg
        556926, -- NPCBloodElfMaleNobleFarewell07.ogg
        -- Source: wowhead.com - BloodElfMaleStandardFarewell
        556957, -- NPCBloodElfMaleStandardFarewell02.ogg
        556961, -- NPCBloodElfMaleStandardFarewell03.ogg
        556945, -- NPCBloodElfMaleStandardFarewell07.ogg
        556956, -- NPCBloodElfMaleStandardFarewell08.ogg
        556954, -- NPCBloodElfMaleStandardFarewell10.ogg
        556941, -- NPCBloodElfMaleStandardFarewell12.ogg
        -- Source: wowhead.com - BloodElfMaleMilitaryFarewell
        556909, -- NPCBloodElfMaleMilitaryFarewell01.ogg
        556916, -- NPCBloodElfMaleMilitaryFarewell04.ogg
        556903, -- NPCBloodElfMaleMilitaryFarewell05.ogg
        556912, -- NPCBloodElfMaleMilitaryFarewell06.ogg
        556915, -- NPCBloodElfMaleMilitaryFarewell07.ogg
        556914, -- NPCBloodElfMaleMilitaryFarewell09.ogg
    },

    pissed = {
        -- Source: wowhead.com - BloodElfMaleNoblePissed
        556938, -- NPCBloodElfMaleNoblePissed01.ogg
        556920, -- NPCBloodElfMaleNoblePissed03.ogg
        556934, -- NPCBloodElfMaleNoblePissed06.ogg
        556928, -- NPCBloodElfMaleNoblePissed08.ogg
        556931, -- NPCBloodElfMaleNoblePissed10.ogg
        -- Source: wowhead.com - BloodElfMaleStandardPissed
        556958, -- NPCBloodElfMaleStandardPissed01.ogg
        556944, -- NPCBloodElfMaleStandardPissed02.ogg
        556962, -- NPCBloodElfMaleStandardPissed04.ogg
        556948, -- NPCBloodElfMaleStandardPissed05.ogg
        556942, -- NPCBloodElfMaleStandardPissed10.ogg
        -- Source: wowhead.com - BloodElfMaleMilitaryPissed
        556905, -- NPCBloodElfMaleMilitaryPissed01.ogg
        556895, -- NPCBloodElfMaleMilitaryPissed03.ogg
        556896, -- NPCBloodElfMaleMilitaryPissed06.ogg
        556900, -- NPCBloodElfMaleMilitaryPissed08.ogg
        556910, -- NPCBloodElfMaleMilitaryPissed09.ogg
    },
}


-- ============================================================
--  TBC ORIGINAL VOICES - FEMALE
--  Still present in the 12.0.1 client. Played on interaction.
-- ============================================================
BElfVR_TBCVoices_Female = {

    greet = {
        -- Source: wowhead.com - BloodElfFemaleNobleVendor
        556864, -- NPCBloodElfFemaleNobleVendor01.ogg
        556860, -- NPCBloodElfFemaleNobleVendor02.ogg
        556859, -- NPCBloodElfFemaleNobleVendor03.ogg
        556869, -- NPCBloodElfFemaleNobleVendor04.ogg
        556867, -- NPCBloodElfFemaleNobleVendor05.ogg
        556855, -- NPCBloodElfFemaleNobleVendor06.ogg
        -- Source: wowhead.com - BloodElfFemaleNobleGreetings
        556851, -- NPCBloodElfFemaleNobleGreeting01.ogg
        556858, -- NPCBloodElfFemaleNobleGreeting02.ogg
        556854, -- NPCBloodElfFemaleNobleGreeting05.ogg
        556863, -- NPCBloodElfFemaleNobleGreeting07.ogg
        556853, -- NPCBloodElfFemaleNobleGreeting08.ogg
        556856, -- NPCBloodElfFemaleNobleGreeting11.ogg
        -- Source: wowhead.com - BloodElfFemaleStandardVendor
        556871, -- NPCBloodElfFemaleStandardVendor01.ogg
        556877, -- NPCBloodElfFemaleStandardVendor02.ogg
        556880, -- NPCBloodElfFemaleStandardVendor03.ogg
        556892, -- NPCBloodElfFemaleStandardVendor04.ogg
        556888, -- NPCBloodElfFemaleStandardVendor05.ogg
        556874, -- NPCBloodElfFemaleStandardVendor06.ogg
        -- Source: wowhead.com - BloodElfFemaleStandardGreetings
        556884, -- NPCBloodElfFemaleStandardGreeting03.ogg
        556886, -- NPCBloodElfFemaleStandardGreeting04.ogg
        556872, -- NPCBloodElfFemaleStandardGreeting05.ogg
        556873, -- NPCBloodElfFemaleStandardGreeting07.ogg
        556870, -- NPCBloodElfFemaleStandardGreeting08.ogg
        556875, -- NPCBloodElfFemaleStandardGreeting12.ogg
        -- Source: wowhead.com - BloodElfFemaleMilitaryGreeting
        556826, -- NPCBloodElfFemaleMilitaryGreeting01.ogg
        556839, -- NPCBloodElfFemaleMilitaryGreeting02.ogg
        556846, -- NPCBloodElfFemaleMilitaryGreeting04.ogg
        556842, -- NPCBloodElfFemaleMilitaryGreeting06.ogg
        556828, -- NPCBloodElfFemaleMilitaryGreeting09.ogg
        556845, -- NPCBloodElfFemaleMilitaryGreeting10.ogg
        556841, -- NPCBloodElfFemaleMilitaryGreeting12.ogg
        -- Source: wowhead.com - BloodElfFemaleMilitaryVendor
        556836, -- NPCBloodElfFemaleMilitaryVendor01.ogg
        556843, -- NPCBloodElfFemaleMilitaryVendor02.ogg
        556834, -- NPCBloodElfFemaleMilitaryVendor03.ogg
        556833, -- NPCBloodElfFemaleMilitaryVendor04.ogg
        556832, -- NPCBloodElfFemaleMilitaryVendor05.ogg
        556837, -- NPCBloodElfFemaleMilitaryVendor06.ogg
    },

    bye = {
        -- Source: wowhead.com - BloodElfFemaleNobleFarewell
        556847, -- NPCBloodElfFemaleNobleFarewell01.ogg
        556861, -- NPCBloodElfFemaleNobleFarewell04.ogg
        556849, -- NPCBloodElfFemaleNobleFarewell08.ogg
        556852, -- NPCBloodElfFemaleNobleFarewell09.ogg
        556850, -- NPCBloodElfFemaleNobleFarewell10.ogg
        556866, -- NPCBloodElfFemaleNobleFarewell12.ogg
        -- Source: wowhead.com - BloodElfFemaleStandardFarewell
        556893, -- NPCBloodElfFemaleStandardFarewell03.ogg
        556887, -- NPCBloodElfFemaleStandardFarewell04.ogg
        556883, -- NPCBloodElfFemaleStandardFarewell06.ogg
        556890, -- NPCBloodElfFemaleStandardFarewell07.ogg
        556879, -- NPCBloodElfFemaleStandardFarewell09.ogg
        556882, -- NPCBloodElfFemaleStandardFarewell11.ogg
        -- Source: wowhead.com - BloodElfFemaleMilitaryFarewell
        556827, -- NPCBloodElfFemaleMilitaryFarewell02.ogg
        556825, -- NPCBloodElfFemaleMilitaryFarewell03.ogg
        556830, -- NPCBloodElfFemaleMilitaryFarewell05.ogg
        556835, -- NPCBloodElfFemaleMilitaryFarewell06.ogg
        556840, -- NPCBloodElfFemaleMilitaryFarewell07.ogg
        556831, -- NPCBloodElfFemaleMilitaryFarewell11.ogg
    },

    pissed = {
        -- Source: wowhead.com - BloodElfFemaleNoblePissed
        556868, -- NPCBloodElfFemaleNoblePissed01.ogg
        556865, -- NPCBloodElfFemaleNoblePissed04.ogg
        556857, -- NPCBloodElfFemaleNoblePissed05.ogg
        556862, -- NPCBloodElfFemaleNoblePissed08.ogg
        556848, -- NPCBloodElfFemaleNoblePissed10.ogg
        -- Source: wowhead.com - BloodElfFemaleStandardPissed
        556885, -- NPCBloodElfFemaleStandardPissed01.ogg
        556881, -- NPCBloodElfFemaleStandardPissed02.ogg
        556891, -- NPCBloodElfFemaleStandardPissed04.ogg
        556876, -- NPCBloodElfFemaleStandardPissed06.ogg
        556889, -- NPCBloodElfFemaleStandardPissed07.ogg
        556878, -- NPCBloodElfFemaleStandardPissed09.ogg
        -- Source: wowhead.com - BloodElfFemaleMilitaryPissed
        556824, -- NPCBloodElfFemaleMilitaryPissed03.ogg
        556838, -- NPCBloodElfFemaleMilitaryPissed06.ogg
        556844, -- NPCBloodElfFemaleMilitaryPissed07.ogg
        556829, -- NPCBloodElfFemaleMilitaryPissed09.ogg
    },
}
