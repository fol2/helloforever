-- HelloForever: a first addon for WoW: Forever.
-- Every file listed in the .toc receives two values: the addon name and a
-- private table shared by all files of this addon.
local addonName, ns = ...

----------------------------------------------------------------------
-- 1. Slash command: /hello
----------------------------------------------------------------------
-- WoW finds slash commands by name: SLASH_<KEY>1, SLASH_<KEY>2 ... plus
-- SlashCmdList["<KEY>"].
SLASH_HELLOFOREVER1 = "/hello"
SlashCmdList["HELLOFOREVER"] = function(msg)
    if msg == "reset" then
        ns.ResetSession()
        print("|cff33ff99HelloForever|r: XP counter reset.")
        return
    end
    local level = UnitLevel("player")
    local zone = GetZoneText()
    local sub = GetSubZoneText()
    if sub ~= "" then zone = zone .. " - " .. sub end
    print(("|cff33ff99HelloForever|r: level %d, in %s."):format(level, zone))
end

----------------------------------------------------------------------
-- 2. XP-per-hour tracking
----------------------------------------------------------------------
local sessionStart, xpGained, lastXP, lastMax

function ns.ResetSession()
    sessionStart = GetTime()   -- seconds, high resolution
    xpGained = 0
    lastXP, lastMax = UnitXP("player"), UnitXPMax("player")
end

local function OnXPUpdate()
    local cur, max = UnitXP("player"), UnitXPMax("player")
    local delta = cur - lastXP
    if delta < 0 then
        -- Level up: XP resets to 0, so add what was left of the old bar.
        delta = (lastMax - lastXP) + cur
    end
    xpGained = xpGained + delta
    lastXP, lastMax = cur, max
end

----------------------------------------------------------------------
-- 3. A small movable frame
----------------------------------------------------------------------
local frame = CreateFrame("Frame", "HelloForeverFrame", UIParent)
frame:SetSize(160, 36)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    HelloForeverDB.pos = { point, relPoint, x, y }
end)

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.5)

local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
text:SetPoint("CENTER")

local function Refresh()
    local hours = (GetTime() - sessionStart) / 3600
    local perHour = hours > 0 and xpGained / hours or 0
    -- Time to level = XP still needed / XP per second.
    local eta = "--"
    if perHour > 0 then
        local needed = UnitXPMax("player") - UnitXP("player")
        eta = SecondsToTime(needed / perHour * 3600)   -- e.g. "1 Hr 12 Min"
    end
    text:SetText(("XP/hour: %s\nLevel in: %s"):format(
        BreakUpLargeNumbers(math.floor(perHour)), eta))
end

----------------------------------------------------------------------
-- 4. Events
----------------------------------------------------------------------
-- An addon does nothing until the game tells it something happened.
-- Register for events, then handle them in one OnEvent script.
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_XP_UPDATE")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        -- SavedVariables are ready only from this point.
        HelloForeverDB = HelloForeverDB or {}
        local pos = HelloForeverDB.pos
        self:ClearAllPoints()
        if pos then
            self:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        else
            self:SetPoint("TOP", UIParent, "TOP", 0, -120)
        end
    elseif event == "PLAYER_LOGIN" then
        -- Unit data (level, XP) is reliable from here.
        ns.ResetSession()
        Refresh()
        C_Timer.NewTicker(1, Refresh)   -- redraw once a second
    elseif event == "PLAYER_XP_UPDATE" then
        OnXPUpdate()
        Refresh()
    end
end)
