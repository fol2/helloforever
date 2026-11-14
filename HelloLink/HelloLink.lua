-- HelloLink: the live-state strip (Strip.lua) and the commands around it.
--
-- /hlink send <text> gives the strip a question (object 1). /hlink strip ... controls the strip.
-- /hlink probe depth draws rows that show how many colours a square can carry on a display
-- (docs/specs/29.md, section 9; kept for the checks of #60). /hlink with nothing loads the
-- next slot addon and shows what it holds: the way in, which the strip also uses to hear a
-- reader's request (tools/hellolink.py). Format 0 (the text strip of /hlink send) and the other
-- probes of the spike were removed (#45).
-- The slot mechanism was described by chelinho139/wow-ai (MIT); nothing here is copied from it.
local _, ns = ...
ns = ns or {} -- a test may load this file alone

local function say(msg)
    print("|cff66ccffHelloLink|r: " .. msg)
end
ns.say = say

local slot, lastSeq = 0, 0

local function loadSlot(name)
    local fn = (_G.C_AddOns and _G.C_AddOns.LoadAddOn) or _G.LoadAddOn
    if type(fn) ~= "function" then return false, "no LoadAddOn on this client" end
    local ok, loaded, why = pcall(fn, name)
    if not ok then return false, loaded end
    return loaded, why
end

-- For Strip.lua: loads the next unused slot and returns what it holds, or nil when the
-- session's slots are used up. It shares the slots with /hlink.
function ns.loadNextSlot()
    slot = slot + 1
    _G.HelloLink_Inbox = nil
    local ok = loadSlot(("HelloLink_S%03d"):format(slot))
    local d = _G.HelloLink_Inbox
    if not ok or type(d) ~= "table" then return nil end
    return d
end

local function poll()
    slot = slot + 1
    local name = ("HelloLink_S%03d"):format(slot)
    _G.HelloLink_Inbox = nil
    local ok, why = loadSlot(name)
    local d = _G.HelloLink_Inbox
    if not ok or type(d) ~= "table" then
        say(("no slot left (%s: %s). /reload gives the slots back."):format(name, tostring(why)))
        return
    end
    if d.seq == lastSeq then
        say(("nothing new (slot %d)."):format(slot))
        return
    end
    lastSeq = d.seq
    say(("slot %d, message %s:"):format(slot, tostring(d.seq)))
    for line in tostring(d.text):gmatch("[^\n]+") do print("  " .. line) end
end

local floor = math.floor

-- P6: how many colours can a square carry? /hlink probe depth <levels> [pixels] draws, 80
-- pixels from the top: a finder (the usual digits turned by one place), two digits that give
-- the levels a channel, a palette of every colour in order (levels cubed), then DEPTH_N
-- colours of a known pattern; 256 squares a line. A reader learns each colour from the
-- palette as this screen shows it, then names every pattern square by its nearest colour.
local DEPTH_FINDER = { 2, 1, 7, 0, 6, 3, 5, 4 }
local DEPTH_LINE, DEPTH_N, DEPTH_TOP, DEPTH_SEC = 256, 240, 80, 120
local depthFrame, depthCells, depthShown = nil, {}, 0

local function probeDepth(arg)
    local levels, px = arg:match("^(%d+)%s*(%d*)$")
    levels, px = tonumber(levels), tonumber(px) or 2
    local physical = _G.GetPhysicalScreenSize
    if not levels or levels < 2 or levels > 8 or px < 1 or px > 8 or type(physical) ~= "function" then
        return say("use /hlink probe depth <2 to 8 levels a channel> [1 to 8 pixels a square]")
    end
    local _, height = physical()
    local unit = 768 / height / UIParent:GetEffectiveScale()
    local symbols = levels ^ 3
    local colours = {}
    local function digit(d) colours[#colours + 1] = { d >= 4 and 1 or 0, d % 4 >= 2 and 1 or 0, d % 2 } end
    local function symbol(i)
        colours[#colours + 1] = { floor(i / (levels * levels)) / (levels - 1), floor(i / levels) % levels / (levels - 1), i % levels / (levels - 1) }
    end
    for i = 1, #DEPTH_FINDER do digit(DEPTH_FINDER[i]) end
    digit(floor(levels / 8))
    digit(levels % 8)
    for i = 0, symbols - 1 do symbol(i) end
    local state = levels
    for _ = 1, DEPTH_N do
        state = (state * 75 + 74) % 65537
        symbol(state % symbols)
    end
    if not depthFrame then
        depthFrame = CreateFrame("Frame", nil, UIParent)
        depthFrame:SetFrameStrata("TOOLTIP")
        depthFrame:SetSize(1, 1)
    end
    depthFrame:ClearAllPoints()
    depthFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -DEPTH_TOP * unit)
    for i = 1, #colours do
        local t = depthCells[i]
        if not t then
            t = depthFrame:CreateTexture(nil, "OVERLAY")
            depthCells[i] = t
        end
        t:SetColorTexture(colours[i][1], colours[i][2], colours[i][3], 1)
        t:SetSize(px * unit, px * unit)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", depthFrame, "TOPLEFT", (i - 1) % DEPTH_LINE * px * unit, -floor((i - 1) / DEPTH_LINE) * px * unit)
        t:Show()
    end
    for i = #colours + 1, #depthCells do depthCells[i]:Hide() end
    depthFrame:Show()
    depthShown = depthShown + 1
    local mine = depthShown
    _G.C_Timer.After(DEPTH_SEC, function()
        if depthShown == mine then depthFrame:Hide() end
    end)
    say(("probe depth: %d levels a channel (%d colours, %.1f bits a square) at %d pixels a square, up for %d s."):format(
        levels, symbols, math.log(symbols) / math.log(2), px, DEPTH_SEC))
end

local MAX_QUESTION = 1400   -- bytes; the strip refuses an object larger than it can carry

SLASH_HELLOLINK1 = "/hlink"
SlashCmdList["HELLOLINK"] = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" then return poll() end
    if cmd == "send" then
        if rest == "" then return say("use /hlink send <text>") end
        if #rest > MAX_QUESTION then
            return say(("too long: %d bytes, a question holds %d."):format(#rest, MAX_QUESTION))
        end
        if not ns.StripQuestion then return say("the strip is not loaded yet.") end
        if not ns.StripQuestion(rest) then return say("the strip is off: /hlink strip on, then send again.") end
        return say("sent to the strip as the question.")
    end
    if cmd == "strip" and ns.StripCommand then return ns.StripCommand(rest:lower()) end
    if cmd == "hide" then
        if depthFrame then depthFrame:Hide() end
        return
    end
    if cmd == "probe" and rest:lower():match("^depth") then return probeDepth(rest:lower():gsub("^depth%s*", "")) end
    if cmd == "probe" then return say("use /hlink probe depth <levels> [pixels]") end
    say("use /hlink send <text>, /hlink strip ..., /hlink probe depth <levels> [pixels], or /hlink alone for the next slot")
end
