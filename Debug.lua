-- ============================================================
--  BElfRestore - Debug.lua
--  DebugChatFrame integration + global c() / cp() shortcuts
--  Ring-buffer log capture + copyable dump frame
--
--  REQUIRES: DebugChatFrame addon (optional - falls back to print)
--  SETUP:    Add to .toc BEFORE BElfRestore.lua:
--              ## OptionalDeps: DebugChatFrame
--              Debug.lua
-- ============================================================

local ADDON_NAME = "bloodElfRestore"
local MODULE     = "BElfVR"
local DEBUG_LOG_MAX = 2000

-- holds the DebugChatFrame instance once initialized
BElfVR_DebugFrame = nil

-- ============================================================
--  Ring-buffer capture
--  Stores every c()/cp() call into BElfVRDB.debugLog so it
--  survives /reload and can be dumped to a copyable frame.
--
--  Lines logged before ADDON_LOADED (before BElfVRDB exists)
--  are held in a temporary pre-init buffer and flushed once
--  BElfVR_InitDebug() runs.
-- ============================================================
local preInitBuffer = {}
local preInitFlushed = false

local function TrimLog(log)
    local overflow = #log - DEBUG_LOG_MAX
    if overflow > 0 then
        for _ = 1, overflow do
            tremove(log, 1)
        end
    end
end

local function CaptureToLog(line)
    local timestamp = date("%H:%M:%S")
    local entry = "[" .. timestamp .. "] " .. line

    if not BElfVRDB then
        -- DB not ready yet — stash until InitDebug flushes
        preInitBuffer[#preInitBuffer + 1] = entry
        return
    end

    BElfVRDB.debugLog = BElfVRDB.debugLog or {}
    local log = BElfVRDB.debugLog
    log[#log + 1] = entry
    TrimLog(log)
end

local function FlushPreInitBuffer()
    if preInitFlushed or not BElfVRDB then return end
    preInitFlushed = true

    BElfVRDB.debugLog = BElfVRDB.debugLog or {}
    local log = BElfVRDB.debugLog
    for _, entry in ipairs(preInitBuffer) do
        log[#log + 1] = entry
    end
    TrimLog(log)
    preInitBuffer = {}
end

local function ArgsToString(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "table" then
            -- shallow table dump for debug visibility
            local items = {}
            for k, val in pairs(v) do
                items[#items + 1] = tostring(k) .. "=" .. tostring(val)
            end
            parts[#parts + 1] = "{" .. table.concat(items, ", ") .. "}"
        else
            parts[#parts + 1] = tostring(v)
        end
    end
    return table.concat(parts, " ")
end

-- ============================================================
--  InitDebug
--  Call this from your ADDON_LOADED block in BElfRestore.lua
-- ============================================================
function BElfVR_InitDebug()
    -- Flush any lines captured before BElfVRDB was ready
    FlushPreInitBuffer()

    -- Attempt programmatic load if OptionalDeps didn't trigger it
    if not DebugChatFrame then
        if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("DebugChatFrame") then
            if C_AddOns.EnableAddOn then
                C_AddOns.EnableAddOn("DebugChatFrame", UnitName("player"))
            end
            if C_AddOns.LoadAddOn then
                C_AddOns.LoadAddOn("DebugChatFrame")
            end
        elseif IsAddOnLoaded and not IsAddOnLoaded("DebugChatFrame") then
            pcall(EnableAddOn, "DebugChatFrame", UnitName("player"))
            pcall(LoadAddOn, "DebugChatFrame")
        end
    end

    if not DebugChatFrame then
        -- DebugChatFrame not installed, c()/cp() will fallback to print
        return
    end

    local opt = {
        addon         = ADDON_NAME,
        chatFrameName = "BElfVR",
        font          = DCF_ConsoleMonoCondensedSemiBold,
        size          = 13,
        windowAlpha   = 0.9,
        maxLines      = 2000,
    }

    BElfVR_DebugFrame = DebugChatFrame:New(opt, function(chatFrame)
        chatFrame:log(MODULE, "DebugChatFrame ready! Addon:", ADDON_NAME)
        chatFrame:log(MODULE, "chatFrame:", chatFrame:GetName())
        chatFrame:log(MODULE, "tab-name:", chatFrame:GetTabName())
    end)
end

-- ============================================================
--  c(...)  - global debug shortcut (standard logging)
--
--  Usage:
--    c("MyModule", "some message")
--    c("MyModule", "value is:", someVariable)
--    c("MyModule", "table:", {1, 2, 3})
--
--  If DebugChatFrame is installed  -> logs to the BElfVR tab
--  If DebugChatFrame is NOT installed -> falls back to print()
--  Always captures to BElfVRDB.debugLog ring buffer.
-- ============================================================
function c(...)
    CaptureToLog(ArgsToString(...))
    if BElfVR_DebugFrame then
        return BElfVR_DebugFrame:log(...)
    end
    print(...)
end

-- ============================================================
--  cp(moduleName, ...)  - module-prefixed debug shortcut
--
--  Usage:
--    cp("Voice", "Loading...")
--      -> Output: {{ bloodElfRestore::Voice }}: Loading...
--
--  Uses logp() for structured module-prefixed output.
--  Falls back to a formatted print() if DebugChatFrame is absent.
--  Always captures to BElfVRDB.debugLog ring buffer.
-- ============================================================
function cp(moduleName, ...)
    CaptureToLog("{{ " .. tostring(moduleName) .. " }} " .. ArgsToString(...))
    if BElfVR_DebugFrame then
        return BElfVR_DebugFrame:logp(moduleName, ...)
    end
    print("{{ " .. ADDON_NAME .. "::" .. tostring(moduleName) .. " }}:", ...)
end

-- ============================================================
--  Copyable dump frame
--  /belr dumplog opens a scrollable EditBox with the full
--  ring-buffer contents. Select all (Ctrl+A) and copy (Ctrl+C).
-- ============================================================
local dumpFrame

function BElfVR_ShowLogDump()
    if not BElfVRDB or not BElfVRDB.debugLog or #BElfVRDB.debugLog == 0 then
        print("|cffFFD700[BElfVR]|r Debug log is empty.")
        return
    end

    if not dumpFrame then
        dumpFrame = CreateFrame("Frame", "BElfVR_LogDumpFrame", UIParent, "BasicFrameTemplateWithInset")
        dumpFrame:SetSize(720, 480)
        dumpFrame:SetPoint("CENTER")
        dumpFrame:SetMovable(true)
        dumpFrame:EnableMouse(true)
        dumpFrame:RegisterForDrag("LeftButton")
        dumpFrame:SetScript("OnDragStart", dumpFrame.StartMoving)
        dumpFrame:SetScript("OnDragStop", dumpFrame.StopMovingOrSizing)
        dumpFrame:SetFrameStrata("DIALOG")

        dumpFrame.title = dumpFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        dumpFrame.title:SetPoint("TOP", 0, -6)
        dumpFrame.title:SetText("BElfVR Debug Log  (Ctrl+A, Ctrl+C to copy)")

        local scrollFrame = CreateFrame("ScrollFrame", nil, dumpFrame, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 12, -32)
        scrollFrame:SetPoint("BOTTOMRIGHT", -30, 12)

        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject("ChatFontNormal")
        editBox:SetWidth(scrollFrame:GetWidth() or 660)
        editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scrollFrame:SetScrollChild(editBox)

        dumpFrame.editBox = editBox
        dumpFrame.scrollFrame = scrollFrame
    end

    local text = table.concat(BElfVRDB.debugLog, "\n")
    dumpFrame.editBox:SetText(text)
    dumpFrame.editBox:SetCursorPosition(0)
    dumpFrame:Show()
    print("|cffFFD700[BElfVR]|r Showing " .. #BElfVRDB.debugLog .. " log line(s). Use Ctrl+A then Ctrl+C to copy.")
end

function BElfVR_ClearLog()
    if BElfVRDB then
        BElfVRDB.debugLog = {}
    end
    print("|cffFFD700[BElfVR]|r Debug log cleared.")
end
