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

-- How many slots this UI session has used (/hlink and the looks): Assist.lua counts the rest.
function ns.SlotsUsed() return slot end

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

-- P6: how many colours can a square carry? /hlink probe depth <levels> [pixels] [lines] [floor] draws, 80
-- pixels from the top: a finder (the usual digits turned by one place), two digits that give
-- the levels a channel (and the lines: the first digit is floor(levels / 8) + 2 * (lines - 1)), a
-- palette of every colour in order (levels cubed), then DEPTH_N colours of a known pattern, or
-- `lines` whole lines of it, from a line of its own; 256 squares a line. /hlink probe lanes is depth 4 at 1 pixel on 4
-- lines: rows of 1-pixel squares one under the other, as format 3's lanes would be (#232, part C). A reader learns each colour from the
-- palette as this screen shows it, then names every pattern square by its nearest colour.
local DEPTH_FINDER = { 2, 1, 7, 0, 6, 3, 5, 4 }
local DEPTH_LINE, DEPTH_N, DEPTH_TOP, DEPTH_SEC = 256, 240, 80, 120
local depthFrame, depthCells, depthShown = nil, {}, 0

local function probeDepth(arg)
    local levels, px, lines, pct = arg:match("^(%d+)%s*(%d*)%s*(%d*)%s*(%d*)$")
    levels, px, lines, pct = tonumber(levels), tonumber(px) or 2, tonumber(lines) or 1, tonumber(pct) or 0
    local physical = _G.GetPhysicalScreenSize
    if not levels or levels < 2 or levels > 8 or px < 1 or px > 8 or lines < 1 or lines > 4 or pct > 90 or type(physical) ~= "function" then
        return say("use /hlink probe depth <2 to 8 levels a channel> [1 to 8 pixels a square] [1 to 4 lines] [0 to 90 floor per cent]")
    end
    local _, height = physical()
    local unit = 768 / height / UIParent:GetEffectiveScale()
    local symbols = levels ^ 3
    local lo = pct / 100
    -- level k at lo + k * (1 - lo) / (L - 1) of full (#232, part C): with no floor, k / (L - 1) as before
    local function level(k) return lo + k * (1 - lo) / (levels - 1) end
    local colours = {}
    local function digit(d) colours[#colours + 1] = { d >= 4 and 1 or 0, d % 4 >= 2 and 1 or 0, d % 2 } end
    local function symbol(i)
        colours[#colours + 1] = { level(floor(i / (levels * levels))), level(floor(i / levels) % levels), level(i % levels) }
    end
    for i = 1, #DEPTH_FINDER do digit(DEPTH_FINDER[i]) end
    digit(floor(levels / 8) + 2 * (lines - 1))
    digit(levels % 8)
    for i = 0, symbols - 1 do symbol(i) end
    -- with lines, the pattern starts a line of its own: exactly `lines` screen lines (review of #267)
    if lines > 1 then
        while #colours % DEPTH_LINE ~= 0 do colours[#colours + 1] = false end
    end
    local state = levels
    for _ = 1, lines == 1 and DEPTH_N or lines * DEPTH_LINE do
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
        if colours[i] then
            t:SetColorTexture(colours[i][1], colours[i][2], colours[i][3], 1)
            t:SetSize(px * unit, px * unit)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", depthFrame, "TOPLEFT", (i - 1) % DEPTH_LINE * px * unit, -floor((i - 1) / DEPTH_LINE) * px * unit)
            t:Show()
        else
            t:Hide()   -- the rest of the palette's line, before the pattern's first
        end
    end
    for i = #colours + 1, #depthCells do depthCells[i]:Hide() end
    depthFrame:Show()
    depthShown = depthShown + 1
    local mine = depthShown
    _G.C_Timer.After(DEPTH_SEC, function()
        if depthShown == mine then depthFrame:Hide() end
    end)
    say(("probe depth: %d levels a channel (%d colours, %.1f bits a square) at %d pixels a square, %d %s of pattern, floor %d %%, up for %d s."):format(
        levels, symbols, math.log(symbols) / math.log(2), px, lines == 1 and DEPTH_N or lines, lines == 1 and "squares" or "lines", pct, DEPTH_SEC))
end

local MAX_QUESTION = 1400   -- bytes; the strip refuses an object larger than it can carry

----------------------------------------------------------------------
-- The settings window (roadmap line 14): every /hlink strip setting without typing. It sets
-- them through ns.StripSet, the same checks as the command. English, as the commands are.
----------------------------------------------------------------------
local win
local WIN_W = 300

local function text(parent, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    return fs
end

local function refresh()
    if not win or not win:IsShown() then return end
    local st = ns.StripState and ns.StripState()
    local c = win.controls
    if not st then
        win.state:SetText("The strip is not loaded.")
        return
    end
    local function tick(on) return on and "|cff40ff40[x]|r " or "[  ] " end
    c.on.label:SetText(tick(st.on) .. "The strip on")
    for _, v in ipairs({ "2", "3", "4" }) do c["size " .. v].label:SetText(tick(tostring(st.size) == v) .. v) end
    for _, v in ipairs({ "auto", "2", "4" }) do c["depth " .. v].label:SetText(tick(tostring(st.depth) == v) .. v) end
    win.dwell:SetText(("A chunk stays %.2f s"):format((tonumber(st.dwell) or 10) / 100))
    win.state:SetText(("At (%d, %d), %d pixels a square, depth %s (now %s), ramp %s, top %d bits"):format(tonumber(st.x) or 0, tonumber(st.y) or 0,
        tonumber(st.size) or 2, tostring(st.depth), tostring(st.depthNow), st.ramp and "on" or "off", tonumber(st.bits) or 6))
end

local function buildWindow()
    local f = CreateFrame("Frame", "HelloLinkSettings", UIParent)
    f:SetSize(WIN_W, 230)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.94)
    local title = text(f, "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -12)
    title:SetText("HelloLink  |cff808080the strip|r")
    f.controls = {}
    local y = -38
    local function add(key, w, x, words, label)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(w, 18)
        b:SetPoint("TOPLEFT", x, y)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        b.label = text(b)
        b.label:SetPoint("LEFT", 4, 0)
        if label then b.label:SetText(label) end
        b:SetScript("OnClick", function()
            if ns.StripSet then ns.StripSet(words()) end
            refresh()
        end)
        f.controls[key] = b
        return b
    end
    local function row(label)
        local l = text(f)
        l:SetPoint("TOPLEFT", 16, y - 3)
        l:SetText(label)
        return l
    end
    local function state() return (ns.StripState and ns.StripState()) or {} end
    add("on", WIN_W - 32, 16, function() return state().on and "off" or "on" end)
    y = y - 22
    row("Size")
    for i, v in ipairs({ "2", "3", "4" }) do add("size " .. v, 50, 110 + (i - 1) * 54, function() return "size", v end) end
    y = y - 22
    row("Depth")
    for i, v in ipairs({ "auto", "2", "4" }) do add("depth " .. v, 50, 110 + (i - 1) * 54, function() return "depth", v end) end
    y = y - 22
    f.dwell = row("")
    local function dwell(d)
        local v = math.max(5, math.min(100, (tonumber(state().dwell) or 10) + d))
        return "dwell", tostring(v)
    end
    add("dwell-", 24, 200, function() return dwell(-5) end, " -")
    add("dwell+", 24, 228, function() return dwell(5) end, " +")
    y = y - 26
    row("From the left")
    local function at(dx, dy)
        local st = state()
        return "at", tostring(math.max(0, (tonumber(st.x) or 0) + dx)), tostring(math.max(0, (tonumber(st.y) or 0) + dy))
    end
    add("x-10", 34, 110, function() return at(-10, 0) end, "-10")
    add("x-1", 26, 146, function() return at(-1, 0) end, "-1")
    add("x+1", 26, 174, function() return at(1, 0) end, "+1")
    add("x+10", 34, 202, function() return at(10, 0) end, "+10")
    y = y - 22
    row("From the top")
    add("y-10", 34, 110, function() return at(0, -10) end, "-10")
    add("y-1", 26, 146, function() return at(0, -1) end, "-1")
    add("y+1", 26, 174, function() return at(0, 1) end, "+1")
    add("y+10", 34, 202, function() return at(0, 10) end, "+10")
    y = y - 22
    add("at 0 0", 120, 16, function() return "at", "0", "0" end, "Back to (0, 0)")
    f.state = text(f, "GameFontDisableSmall")
    f.state:SetPoint("BOTTOMLEFT", 12, 12)
    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -6, -7)
    close.label = text(close, "GameFontNormal")
    close.label:SetPoint("CENTER", 0, 0)
    close.label:SetText("x")
    close:SetScript("OnClick", function() f:Hide() end)
    f.close = close
    f:SetScript("OnShow", refresh)
    -- Twice a second while open: a change by /hlink strip, or the depth the strip settles on by
    -- itself, shows in the window.
    f.since = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        self.since = self.since + (tonumber(elapsed) or 0)
        if self.since >= 0.5 then
            self.since = 0
            refresh()
        end
    end)
    if type(_G.UISpecialFrames) == "table" then _G.UISpecialFrames[#_G.UISpecialFrames + 1] = "HelloLinkSettings" end
    f:Hide()
    win = f
end

local function openWindow()
    if not win then buildWindow() end
    if win:IsShown() then win:Hide() else win:Show() end
end
ns.OpenSettings = openWindow

-- The game's AddOns options get a HelloLink page with a button that opens the window.
do
    local S = _G.Settings
    if type(S) == "table" and type(S.RegisterCanvasLayoutCategory) == "function" and type(S.RegisterAddOnCategory) == "function" then
        pcall(function()
            local page = CreateFrame("Frame")
            local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
            b:SetSize(180, 22)
            b:SetPoint("TOPLEFT", 16, -16)
            b:SetText("The strip's settings")
            b:SetScript("OnClick", openWindow)
            S.RegisterAddOnCategory(S.RegisterCanvasLayoutCategory(page, "HelloLink"))
        end)
    end
end

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
    if cmd == "settings" then return openWindow() end
    if cmd == "hide" then
        if depthFrame then depthFrame:Hide() end
        return
    end
    if cmd == "probe" and rest:lower():match("^depth") then return probeDepth(rest:lower():gsub("^depth%s*", "")) end
    if cmd == "probe" and rest:lower() == "lanes" then return probeDepth("4 1 4") end
    if cmd == "probe" and rest:lower() == "api" and ns.ProbeApi then
        return say(("probe api: %d answers kept in HelloLinkDB.probe; /reload writes them to disk."):format(ns.ProbeApi("command")))
    end
    if cmd == "probe" then return say("use /hlink probe depth <levels> [pixels] [lines] [floor], /hlink probe lanes, or /hlink probe api") end
    say("use /hlink send <text>, /hlink strip ..., /hlink settings, /hlink probe depth <levels> [pixels], or /hlink alone for the next slot")
end
