-- HelloLink (spike): does text written by a program outside the game reach the running
-- game without /reload?
--
-- The way in: the client reads a load-on-demand addon's file from disk at the moment the
-- addon is loaded. `tools/hellolink.py install` creates slot addons HelloLink_S001.. before
-- the client starts; `tools/hellolink.py write` puts the same text into every slot; each
-- /hlink loads the next unused slot and shows what it holds. A slot loads once per UI
-- session, so a session has as many polls as there are slots; /reload gives them back.
-- Mechanism described by chelinho139/wow-ai (MIT); nothing here is copied from it.
-- UNVERIFIED in the game: see plan/05-assistant-link.md.
local function say(msg)
    print("|cff66ccffHelloLink|r: " .. msg)
end

local slot, lastSeq = 0, 0

local function loadSlot(name)
    local fn = (_G.C_AddOns and _G.C_AddOns.LoadAddOn) or _G.LoadAddOn
    if type(fn) ~= "function" then return false, "no LoadAddOn on this client" end
    local ok, loaded, why = pcall(fn, name)
    if not ok then return false, loaded end
    return loaded, why
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

-- Is ReloadUI allowed without a key press? If it is, the UI reloads and the last line never
-- shows. (HelloForever's /hello afkreload depends on the answer.)
local function reloadTest()
    say("calling ReloadUI from a timer in 3 s. Do not press anything.")
    _G.C_Timer.After(3, function()
        local ok, err = pcall(_G.ReloadUI)
        say(("still here, so the reload was refused (%s). ReloadUI needs a key press on this client.")
            :format(ok and "no error" or tostring(err)))
    end)
end

-- The way out: /hlink send <text> draws the text as coloured squares near the top-left corner of
-- the game, and tools/hellolink_strip.py reads them from a screenshot. No reload, no file.
-- A square is one of 8 colours (each channel on or off): digit = 4*red + 2*green + blue. The
-- strip is the finder (4 2 1 7 0 6 3 5), then the frame, three bits a square: length (2 bytes),
-- sequence (1 byte), the text, Fletcher-16 (2 bytes). Same numbers as in the tool.
local CELL, PER_ROW, MAX_TEXT, SHOW_SEC = 6, 100, 1400, 30
local TOP_GAP = 24 -- UI units left free at the top: another addon may draw its own row there (one on this Mac does)
local FINDER = { 4, 2, 1, 7, 0, 6, 3, 5 }
local stripFrame, cells, seq, shown = nil, {}, 0, 0
local probeFrame -- the probe rows (further down) share the corner: a text takes it over
local floor = math.floor

local function encode(text)
    seq = seq % 255 + 1
    local bytes = { floor(#text / 256), #text % 256, seq }
    for i = 1, #text do bytes[#bytes + 1] = text:byte(i) end
    local s1, s2 = 0, 0
    for i = 1, #bytes do
        s1 = (s1 + bytes[i]) % 255
        s2 = (s2 + s1) % 255
    end
    bytes[#bytes + 1], bytes[#bytes + 2] = s1, s2
    local digits = {}
    for i = 1, #FINDER do digits[i] = FINDER[i] end
    local acc, nbits = 0, 0
    for i = 1, #bytes do
        acc, nbits = acc * 256 + bytes[i], nbits + 8
        while nbits >= 3 do
            local unit = 2 ^ (nbits - 3)
            local d = floor(acc / unit)
            digits[#digits + 1] = d
            acc, nbits = acc - d * unit, nbits - 3
        end
    end
    if nbits > 0 then digits[#digits + 1] = acc * 2 ^ (3 - nbits) end
    return digits
end

local function hideStrip()
    if stripFrame then stripFrame:Hide() end
end

local function send(text)
    if text == "" then return say("use /hlink send <text>") end
    if #text > MAX_TEXT then
        return say(("too long: %d bytes, the strip holds %d."):format(#text, MAX_TEXT))
    end
    local digits = encode(text)
    if probeFrame then probeFrame:Hide() end
    if not stripFrame then
        stripFrame = CreateFrame("Frame", nil, UIParent)
        stripFrame:SetFrameStrata("TOOLTIP")
        stripFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -TOP_GAP)
        stripFrame:SetSize(PER_ROW * CELL, CELL)
    end
    for i = 1, #digits do
        local t = cells[i]
        if not t then
            t = stripFrame:CreateTexture(nil, "OVERLAY")
            t:SetSize(CELL, CELL)
            t:SetPoint("TOPLEFT", stripFrame, "TOPLEFT", (i - 1) % PER_ROW * CELL, -floor((i - 1) / PER_ROW) * CELL)
            cells[i] = t
        end
        local d = digits[i]
        t:SetColorTexture(d >= 4 and 1 or 0, d % 4 >= 2 and 1 or 0, d % 2, 1)
        t:Show()
    end
    for i = #digits + 1, #cells do cells[i]:Hide() end
    stripFrame:Show()
    shown = shown + 1
    local mine = shown
    _G.C_Timer.After(SHOW_SEC, function()
        if shown == mine then hideStrip() end
    end)
    say(("strip up for %d s: %d bytes in %d squares. /hlink hide takes it down."):format(SHOW_SEC, #text, #digits))
end

-- Probes for docs/specs/29.md, section 9: facts about this client that the live-state strip
-- stands on. Each reports; none changes anything.

-- P1: can the client draw exact squares of 8, 4, 3 and 2 physical pixels? One row a size:
-- the finder, then PROBE_N digits of a known pattern (the same generator is in the tool).
local PROBE_SIZES, PROBE_N, PROBE_TOP, PROBE_SEC = { 8, 4, 3, 2 }, 120, 48, 60
local probeCells, probeShown = {}, 0

local function probeDigits(size)
    local out, state = {}, size
    for i = 1, PROBE_N do
        state = (state * 75 + 74) % 65537
        out[i] = state % 8
    end
    return out
end

local function probeSquares()
    local physical = _G.GetPhysicalScreenSize
    if type(physical) ~= "function" then return say("probe squares: no GetPhysicalScreenSize on this client.") end
    local _, height = physical()
    local unit = 768 / height / UIParent:GetEffectiveScale() -- UI units in one physical pixel
    if not probeFrame then
        probeFrame = CreateFrame("Frame", nil, UIParent)
        probeFrame:SetFrameStrata("TOOLTIP")
        probeFrame:SetSize(1, 1)
    end
    probeFrame:ClearAllPoints()
    probeFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -PROBE_TOP * unit)
    local k, y = 0, 0
    for _, size in ipairs(PROBE_SIZES) do
        local digits = probeDigits(size)
        for i = 1, #FINDER + PROBE_N do
            k = k + 1
            local t = probeCells[k]
            if not t then
                t = probeFrame:CreateTexture(nil, "OVERLAY")
                probeCells[k] = t
            end
            local d = FINDER[i] or digits[i - #FINDER]
            t:SetColorTexture(d >= 4 and 1 or 0, d % 4 >= 2 and 1 or 0, d % 2, 1)
            t:SetSize(size * unit, size * unit)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", probeFrame, "TOPLEFT", (i - 1) * size * unit, -y * unit)
            t:Show()
        end
        y = y + size + 6
    end
    probeFrame:Show()
    probeShown = probeShown + 1
    local mine = probeShown
    _G.C_Timer.After(PROBE_SEC, function()
        if probeShown == mine then probeFrame:Hide() end
    end)
    say(("probe squares: rows of 8, 4, 3 and 2 pixels a square are up for %d s (screen height %d, UI scale %.3f)."):format(
        PROBE_SEC, height, UIParent:GetEffectiveScale()))
end

-- P5: can a bar show a secret value so that a reader can measure it? The client lets an addon
-- hand a secret value to a status bar (its own unit frames do). One row at the very top-left,
-- 3 pixels high: the finder reversed (so no reader takes it for a text or a probe row), then
-- four bars of BAR_PX pixels, white on black: health, power, target health, pet health. The
-- values go from the API straight into the bar: they are never tested, compared or computed on.
local BAR_PX, BAR_GAP, BAR_SQUARE, BAR_SEC = 100, 4, 3, 120
local BAR_UNITS = { { "UnitHealth", "UnitHealthMax", "player" }, { "UnitPower", "UnitPowerMax", "player" },
    { "UnitHealth", "UnitHealthMax", "target" }, { "UnitHealth", "UnitHealthMax", "pet" } }
local barFrame, bars, barShown = nil, {}, 0

local function probeBars()
    local physical = _G.GetPhysicalScreenSize
    if type(physical) ~= "function" then return say("probe bars: no GetPhysicalScreenSize on this client.") end
    local _, height = physical()
    local unit = 768 / height / UIParent:GetEffectiveScale()
    if not barFrame then
        barFrame = CreateFrame("Frame", nil, UIParent)
        barFrame:SetFrameStrata("TOOLTIP")
        barFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
        barFrame:SetSize(1, 1)
        for i = 1, #FINDER do
            local d = FINDER[#FINDER + 1 - i]
            local t = barFrame:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(d >= 4 and 1 or 0, d % 4 >= 2 and 1 or 0, d % 2, 1)
            t:SetSize(BAR_SQUARE * unit, BAR_SQUARE * unit)
            t:SetPoint("TOPLEFT", barFrame, "TOPLEFT", (i - 1) * BAR_SQUARE * unit, 0)
        end
        for k = 1, #BAR_UNITS do
            local x = (#FINDER * BAR_SQUARE + BAR_GAP + (k - 1) * (BAR_PX + BAR_GAP)) * unit
            local back = barFrame:CreateTexture(nil, "BACKGROUND")
            back:SetColorTexture(0, 0, 0, 1)
            back:SetSize((BAR_PX + BAR_GAP) * unit, BAR_SQUARE * unit)
            back:SetPoint("TOPLEFT", barFrame, "TOPLEFT", x - BAR_GAP * unit, 0)
            local bar = CreateFrame("StatusBar", nil, barFrame)
            bar:SetSize(BAR_PX * unit, BAR_SQUARE * unit)
            bar:SetPoint("TOPLEFT", barFrame, "TOPLEFT", x, 0)
            local fill = bar:CreateTexture(nil, "ARTWORK")
            fill:SetColorTexture(1, 1, 1, 1)
            bar:SetStatusBarTexture(fill)
            bars[k] = bar
        end
        barFrame:SetScript("OnUpdate", function()
            for k = 1, #BAR_UNITS do
                local value, max, who = _G[BAR_UNITS[k][1]], _G[BAR_UNITS[k][2]], BAR_UNITS[k][3]
                if _G.UnitExists(who) then
                    bars[k]:SetMinMaxValues(0, max(who))
                    bars[k]:SetValue(value(who))
                    bars[k]:Show()
                else
                    bars[k]:Hide()
                end
            end
        end)
    end
    barFrame:Show()
    barShown = barShown + 1
    local mine = barShown
    _G.C_Timer.After(BAR_SEC, function()
        if barShown == mine then barFrame:Hide() end
    end)
    say(("probe bars: health, power, target health and pet health as bars at the top-left for %d s."):format(BAR_SEC))
end

-- P2: which values the fast block needs are secret (unreadable) now? Sampled at once, and
-- again 2 s into the next fight; both samples then go out through the strip.
local function g(path)
    local v = _G
    for part in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then return nil end
        v = v[part]
    end
    return v
end

local PROBE_VALUES = {
    { "health", "UnitHealth", "player" }, { "healthMax", "UnitHealthMax", "player" },
    { "power", "UnitPower", "player" }, { "powerMax", "UnitPowerMax", "player" },
    { "powerType", "UnitPowerType", "player" }, { "level", "UnitLevel", "player" },
    { "xp", "UnitXP", "player" }, { "xpMax", "UnitXPMax", "player" },
    { "dead", "UnitIsDeadOrGhost", "player" }, { "mounted", "IsMounted" }, { "resting", "IsResting" },
    { "afk", "UnitIsAFK", "player" }, { "cast", "UnitCastingInfo", "player" }, { "channel", "UnitChannelInfo", "player" },
    { "targetExists", "UnitExists", "target" }, { "targetLevel", "UnitLevel", "target" },
    { "targetHealth", "UnitHealth", "target" }, { "targetHealthMax", "UnitHealthMax", "target" },
    { "targetHostile", "UnitCanAttack", "player", "target" }, { "targetClass", "UnitClassification", "target" },
    { "targetName", "UnitName", "target" }, { "targetTapped", "UnitIsTapDenied", "target" },
    { "petHealth", "UnitHealth", "pet" }, { "petHealthMax", "UnitHealthMax", "pet" }, { "petHappiness", "GetPetHappiness" },
    { "map", "C_Map.GetBestMapForUnit", "player" }, { "facing", "GetPlayerFacing" },
    { "money", "GetMoney" }, { "bagFree", "C_Container.GetContainerNumFreeSlots", 0 },
}

-- True when any of the values is secret. The values are only passed on and handed to
-- issecretvalue: a secret value must never be tested, compared or used in arithmetic.
local function anySecret(isSecret, ...)
    for i = 1, select("#", ...) do
        if isSecret((select(i, ...))) then return true end
    end
    return false
end

-- Calls fn and files `name` under secret / none / missing / error, or counts it as readable.
-- Every value fn returns is checked, not only the first (a cast's times and spell id count).
local function classify(by, name, fn, ...)
    if type(fn) ~= "function" then
        by.missing[#by.missing + 1] = name
        return
    end
    local isSecret = _G.issecretvalue
    local function sort(good, ...)
        if not good then
            by.error[#by.error + 1] = name
        elseif type(isSecret) == "function" and anySecret(isSecret, ...) then
            by.secret[#by.secret + 1] = name
        elseif select("#", ...) == 0 or (...) == nil then
            by.none[#by.none + 1] = name
        else
            by.ok = by.ok + 1
        end
    end
    sort(pcall(fn, ...))
end

local function sampleSecrets()
    local by = { secret = {}, missing = {}, error = {}, none = {}, ok = 0 }
    for _, p in ipairs(PROBE_VALUES) do classify(by, p[1], g(p[2]), p[3], p[4]) end
    -- The position is a table with a method: what counts is whether the coordinates are
    -- readable. Each step runs inside classify's pcall and is checked before it is used.
    classify(by, "position", function()
        local map = g("C_Map.GetBestMapForUnit")("player")
        if _G.issecretvalue and _G.issecretvalue(map) then return map end
        if map == nil then return nil end
        local pos = g("C_Map.GetPlayerMapPosition")(map, "player")
        if _G.issecretvalue and _G.issecretvalue(pos) then return pos end
        if pos == nil then return nil end
        return pos:GetXY()
    end)
    local combat = type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown()
    local parts = { "combat=" .. (combat and "yes" or "no"), "readable=" .. by.ok }
    for _, kind in ipairs({ "secret", "none", "missing", "error" }) do
        if #by[kind] > 0 then parts[#parts + 1] = kind .. ": " .. table.concat(by[kind], ", ") end
    end
    return table.concat(parts, "; ")
end

local probeEvents

local function probeSecrets()
    local now = sampleSecrets()
    say("probe secrets, now: " .. now)
    say("pull a mob, and cast something with a cast time: each is sampled once and shown through the strip.")
    send("now: " .. now)
    if not probeEvents then probeEvents = CreateFrame("Frame") end
    probeEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
    probeEvents:RegisterEvent("UNIT_SPELLCAST_START")
    probeEvents:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_SPELLCAST_START" then
            if unit ~= "player" then return end
            probeEvents:UnregisterEvent(event)
            local casting = sampleSecrets()
            say("probe secrets, casting: " .. casting)
            send("casting: " .. casting)
            return
        end
        probeEvents:UnregisterEvent(event)
        _G.C_Timer.After(2, function()
            local fight = sampleSecrets()
            say("probe secrets, in the fight: " .. fight)
            send("fight: " .. fight)
        end)
    end)
end

SLASH_HELLOLINK1 = "/hlink"
SlashCmdList["HELLOLINK"] = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "reloadtest" then return reloadTest() end
    if cmd == "send" then return send(rest) end
    if cmd == "hide" then
        if probeFrame then probeFrame:Hide() end
        if barFrame then barFrame:Hide() end
        return hideStrip()
    end
    if cmd == "probe" and rest:lower() == "squares" then return probeSquares() end
    if cmd == "probe" and rest:lower() == "secrets" then return probeSecrets() end
    if cmd == "probe" and rest:lower() == "bars" then return probeBars() end
    if cmd == "probe" then return say("use /hlink probe squares, /hlink probe secrets or /hlink probe bars") end
    poll()
end
