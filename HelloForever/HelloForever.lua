-- HelloForever v0.2.0: XP/hour UI + character snapshot / timeline for offline analysis.
-- Every .toc file receives: addon name, private shared table.
local addonName, ns = ...

----------------------------------------------------------------------
-- Helpers (pcall / existence guards for this custom classic-era client)
----------------------------------------------------------------------
local function safeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e, f, g, h
end

local function after(sec, fn)
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(sec, fn)
    else
        -- Fallback: one-shot OnUpdate throttle
        local f = CreateFrame("Frame")
        local t0 = GetTime()
        f:SetScript("OnUpdate", function(self)
            if GetTime() - t0 >= sec then
                self:SetScript("OnUpdate", nil)
                fn()
            end
        end)
    end
end

local function newTicker(sec, fn)
    if C_Timer and type(C_Timer.NewTicker) == "function" then
        return C_Timer.NewTicker(sec, fn)
    end
    local f = CreateFrame("Frame")
    local acc = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= sec then
            acc = acc - sec
            fn()
        end
    end)
    return f
end

local function charKey()
    local name = safeCall(UnitName, "player") or "Unknown"
    local realm = safeCall(GetRealmName) or "Unknown"
    return name .. "-" .. realm
end

local function ensureDB()
    HelloForeverDB = HelloForeverDB or {}
    HelloForeverDB.settings = HelloForeverDB.settings or { combatLog = "off" }
    if HelloForeverDB.settings.combatLog == nil then
        HelloForeverDB.settings.combatLog = "off"
    end
    HelloForeverDB.characters = HelloForeverDB.characters or {}
    local key = charKey()
    local c = HelloForeverDB.characters[key]
    if not c then
        c = { snapshot = nil, timeline = {}, events = {}, _tlCount = 0 }
        HelloForeverDB.characters[key] = c
    end
    c.timeline = c.timeline or {}
    c.events = c.events or {}
    c._tlCount = c._tlCount or 0
    return c, key
end

local function pushEvent(kind, extra)
    local c = ensureDB()
    local e = { t = time(), kind = kind }
    if type(extra) == "table" then
        for k, v in pairs(extra) do e[k] = v end
    end
    local ev = c.events
    ev[#ev + 1] = e
    -- Cap events at 500 (lightweight)
    while #ev > 500 do table.remove(ev, 1) end
end

----------------------------------------------------------------------
-- 1. Snapshot
----------------------------------------------------------------------
local INVENTORY_SLOTS = {
    {1, "head"}, {2, "neck"}, {3, "shoulder"}, {4, "shirt"}, {5, "chest"},
    {6, "waist"}, {7, "legs"}, {8, "feet"}, {9, "wrist"}, {10, "hands"},
    {11, "finger1"}, {12, "finger2"}, {13, "trinket1"}, {14, "trinket2"},
    {15, "back"}, {16, "mainhand"}, {17, "offhand"}, {18, "ranged"}, {19, "tabard"},
}

local function collectStats()
    local s = {}
    -- UnitStat returns current, effective, posBuff, negBuff; take effective (2nd) if present
    local function oneStat(i)
        local a, b = safeCall(UnitStat, "player", i)
        return b or a
    end
    s.str = oneStat(1)
    s.agi = oneStat(2)
    s.sta = oneStat(3)
    s.int = oneStat(4)
    s.spi = oneStat(5)
    local apBase, apPos, apNeg = safeCall(UnitAttackPower, "player")
    if apBase then s.ap = (apBase or 0) + (apPos or 0) + (apNeg or 0) end
    local rapBase, rapPos, rapNeg = safeCall(UnitRangedAttackPower, "player")
    if rapBase then s.rangedAP = (rapBase or 0) + (rapPos or 0) + (rapNeg or 0) end
    s.crit = safeCall(GetCritChance)
    s.rangedCrit = safeCall(GetRangedCritChance)
    s.hit = safeCall(GetHitModifier)
    s.spellHit = safeCall(GetSpellHitModifier)
    s.dodge = safeCall(GetDodgeChance)
    s.parry = safeCall(GetParryChance)
    s.block = safeCall(GetBlockChance)
    s.armor = safeCall(UnitArmor, "player")
    return s
end

local function collectEquipped()
    local eq = {}
    for _, pair in ipairs(INVENTORY_SLOTS) do
        local slot, name = pair[1], pair[2]
        local link = safeCall(GetInventoryItemLink, "player", slot)
        if link then eq[name] = link end
    end
    return eq
end

local function collectTalents()
    local tabs = {}
    -- Classic: GetNumTalentTabs / GetTalentTabInfo / GetNumTalents / GetTalentInfo
    local nTabs = safeCall(GetNumTalentTabs) or 0
    for t = 1, nTabs do
        local name, _, pointsSpent, background, previewPointsSpent =
            safeCall(GetTalentTabInfo, t)
        local tab = {
            name = name,
            points = pointsSpent or previewPointsSpent or 0,
            background = background,
            talents = {},
        }
        local nTal = safeCall(GetNumTalents, t) or 0
        for i = 1, nTal do
            local tName, _, tier, column, rank, maxRank =
                safeCall(GetTalentInfo, t, i)
            if tName then
                tab.talents[#tab.talents + 1] = {
                    name = tName, tier = tier, column = column,
                    rank = rank or 0, maxRank = maxRank or 0,
                }
            end
        end
        tabs[#tabs + 1] = tab
    end
    return tabs
end

local function collectSkills()
    local skills = {}
    local n
    if C_SkillInfo and type(C_SkillInfo.GetNumSkillLines) == "function" then
        n = safeCall(C_SkillInfo.GetNumSkillLines)
    else
        n = safeCall(GetNumSkillLines)
    end
    n = n or 0
    for i = 1, n do
        local name, isHeader, _, rank, _, _, maxRank
        if type(GetSkillLineInfo) == "function" then
            name, isHeader, _, rank, _, _, maxRank = safeCall(GetSkillLineInfo, i)
        end
        if name and not isHeader and rank then
            skills[#skills + 1] = { name = name, rank = rank, max = maxRank or 0 }
        end
    end
    return skills
end

local function collectReputations()
    local reps = {}
    -- Prefer modern C_Reputation if present (VocXP uses it on this client)
    local R = _G.C_Reputation
    if type(R) == "table" and type(R.GetNumFactions) == "function"
        and type(R.GetFactionDataByIndex) == "function" then
        local n = safeCall(R.GetNumFactions) or 0
        for i = 1, n do
            local fd = safeCall(R.GetFactionDataByIndex, i)
            if type(fd) == "table" and fd.name and not fd.isHeader then
                reps[#reps + 1] = {
                    name = fd.name,
                    standing = fd.reaction or fd.standingID,
                    value = fd.currentStanding or fd.barValue,
                    min = fd.currentReactionThreshold or fd.barMin,
                    max = fd.nextReactionThreshold or fd.barMax,
                }
            end
        end
        return reps
    end
    -- Classic fallback
    local n = safeCall(GetNumFactions) or 0
    for i = 1, n do
        local name, _, standingID, barMin, barMax, barValue, _, _,
            isHeader, _, _, _, _ = safeCall(GetFactionInfo, i)
        if name and not isHeader then
            reps[#reps + 1] = {
                name = name, standing = standingID,
                value = barValue, min = barMin, max = barMax,
            }
        end
    end
    return reps
end

local function collectQuests()
    local quests = {}
    local QL = _G.C_QuestLog
    if type(QL) == "table" and type(QL.GetNumQuestLogEntries) == "function" then
        local n = safeCall(QL.GetNumQuestLogEntries) or 0
        for i = 1, n do
            local info
            if type(QL.GetInfo) == "function" then
                info = safeCall(QL.GetInfo, i)
            elseif type(QL.GetQuestLogTitle) == "function" then
                -- unlikely; fall through
            end
            if type(info) == "table" and info.title and not info.isHeader then
                quests[#quests + 1] = {
                    title = info.title,
                    level = info.level,
                    complete = info.isComplete and true or false,
                }
            end
        end
        if #quests > 0 then return quests end
    end
    local n = safeCall(GetNumQuestLogEntries) or 0
    for i = 1, n do
        local title, level, _, isHeader, _, isComplete =
            safeCall(GetQuestLogTitle, i)
        if title and not isHeader then
            quests[#quests + 1] = {
                title = title, level = level,
                complete = (isComplete == 1) or (isComplete == true) or false,
            }
        end
    end
    return quests
end

-- timePlayed filled asynchronously via TIME_PLAYED_MSG
local pendingPlayed = { total = nil, level = nil }

local function collectSnapshot(reason)
    local className, classFile = safeCall(UnitClass, "player")
    local raceName, raceFile = safeCall(UnitRace, "player")
    local factionEn, factionLoc = safeCall(UnitFactionGroup, "player")
    local snap = {
        t = time(),
        reason = reason or "manual",
        name = safeCall(UnitName, "player"),
        realm = safeCall(GetRealmName),
        class = classFile or className,
        className = className,
        race = raceFile or raceName,
        raceName = raceName,
        faction = factionEn or factionLoc,
        level = safeCall(UnitLevel, "player"),
        xp = safeCall(UnitXP, "player"),
        xpMax = safeCall(UnitXPMax, "player"),
        rested = safeCall(GetXPExhaustion),
        money = safeCall(GetMoney),
        zone = safeCall(GetRealZoneText) or safeCall(GetZoneText),
        subzone = safeCall(GetSubZoneText),
        stats = collectStats(),
        equipped = collectEquipped(),
        talents = collectTalents(),
        skills = collectSkills(),
        reputations = collectReputations(),
        quests = collectQuests(),
        timePlayed = {
            total = pendingPlayed.total,
            level = pendingPlayed.level,
        },
    }
    return snap
end

function ns.TakeSnapshot(reason)
    local c = ensureDB()
    c.snapshot = collectSnapshot(reason)
    return c.snapshot
end

----------------------------------------------------------------------
-- 2. Timeline: idle dedupe + delta encoding + periodic keyframes
----------------------------------------------------------------------
-- Entry shapes:
--   keyframe: {t, last, n, k=true, zone, subzone, level, xp, money}
--   delta:    {t, last, n, <only changed fields among zone/subzone/level/xp/money>}
-- Idle (identical state): bump last + n on the previous entry; do not append.
-- Keyframe every 12th APPEND, and on login.
local TL_FIELDS = { "zone", "subzone", "level", "xp", "money" }
local TL_CAP = 2000
local TL_KEYFRAME_EVERY = 12
local lastState = nil  -- in-memory reconstructed full state

local function currentTLState()
    return {
        zone = safeCall(GetRealZoneText) or safeCall(GetZoneText) or "",
        subzone = safeCall(GetSubZoneText) or "",
        level = safeCall(UnitLevel, "player") or 0,
        xp = safeCall(UnitXP, "player") or 0,
        money = safeCall(GetMoney) or 0,
    }
end

local function statesEqual(a, b)
    if not a or not b then return false end
    for _, f in ipairs(TL_FIELDS) do
        if a[f] ~= b[f] then return false end
    end
    return true
end

local function trimTimeline(tl)
    while #tl > TL_CAP do table.remove(tl, 1) end
end

-- forceKeyframe: true on login / explicit
function ns.TimelineTick(forceKeyframe)
    local c = ensureDB()
    local tl = c.timeline
    local now = time()
    local state = currentTLState()

    if lastState and statesEqual(state, lastState) and not forceKeyframe then
        local last = tl[#tl]
        if last then
            last.last = now
            last.n = (last.n or 1) + 1
        end
        return
    end

    -- Decide keyframe vs delta
    local needKF = forceKeyframe
        or (lastState == nil)
        or ((c._tlCount % TL_KEYFRAME_EVERY) == 0)

    local entry = { t = now, last = now, n = 1 }
    if needKF then
        entry.k = true
        for _, f in ipairs(TL_FIELDS) do entry[f] = state[f] end
    else
        for _, f in ipairs(TL_FIELDS) do
            if state[f] ~= lastState[f] then
                entry[f] = state[f]
            end
        end
    end

    tl[#tl + 1] = entry
    c._tlCount = c._tlCount + 1
    lastState = state
    trimTimeline(tl)
end

----------------------------------------------------------------------
-- 3. Optional combat-log helper (default OFF)
----------------------------------------------------------------------
local function applyCombatLogMode(mode)
    local settings = HelloForeverDB and HelloForeverDB.settings
    if not settings then return end
    settings.combatLog = mode
    if mode == "on" then
        if type(LoggingCombat) == "function" then LoggingCombat(true) end
    elseif mode == "off" then
        if type(LoggingCombat) == "function" then LoggingCombat(false) end
    elseif mode == "auto" then
        -- evaluated on zone/instance changes
        local inInst, instType = false, nil
        if type(IsInInstance) == "function" then
            inInst, instType = IsInInstance()
        end
        local want = inInst and (instType == "party" or instType == "raid")
        if type(LoggingCombat) == "function" then LoggingCombat(want and true or false) end
    end
end

local function refreshAutoCombatLog()
    local settings = HelloForeverDB and HelloForeverDB.settings
    if not settings or settings.combatLog ~= "auto" then return end
    applyCombatLogMode("auto")
end

----------------------------------------------------------------------
-- 4. Slash command: /hello
----------------------------------------------------------------------
SLASH_HELLOFOREVER1 = "/hello"
SlashCmdList["HELLOFOREVER"] = function(msg)
    msg = (msg or ""):match("^%s*(.-)%s*$") or ""
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""

    if cmd == "reset" then
        ns.ResetSession()
        print("|cff33ff99HelloForever|r: XP counter reset.")
        return
    end
    if cmd == "snap" then
        local snap = ns.TakeSnapshot("slash")
        print(("|cff33ff99HelloForever|r: snapshot saved (level %s, %s).")
            :format(tostring(snap.level), tostring(snap.zone)))
        return
    end
    if cmd == "combatlog" then
        local mode = (rest or ""):lower()
        if mode ~= "on" and mode ~= "off" and mode ~= "auto" then
            local cur = (HelloForeverDB and HelloForeverDB.settings
                and HelloForeverDB.settings.combatLog) or "off"
            print("|cff33ff99HelloForever|r: combatlog = " .. tostring(cur)
                .. " (use /hello combatlog on|off|auto)")
            return
        end
        ensureDB()
        applyCombatLogMode(mode)
        print("|cff33ff99HelloForever|r: combatlog set to " .. mode)
        return
    end

    -- default: keep original /hello behaviour
    local level = UnitLevel("player")
    local zone = GetZoneText()
    local sub = GetSubZoneText()
    if sub ~= "" then zone = zone .. " - " .. sub end
    print(("|cff33ff99HelloForever|r: level %d, in %s."):format(level, zone))
end

----------------------------------------------------------------------
-- 5. XP-per-hour tracking (unchanged behaviour)
----------------------------------------------------------------------
local sessionStart, xpGained, lastXP, lastMax

function ns.ResetSession()
    sessionStart = GetTime()
    xpGained = 0
    lastXP, lastMax = UnitXP("player"), UnitXPMax("player")
end

local function OnXPUpdate()
    local cur, max = UnitXP("player"), UnitXPMax("player")
    local delta = cur - lastXP
    if delta < 0 then
        delta = (lastMax - lastXP) + cur
    end
    xpGained = xpGained + delta
    lastXP, lastMax = cur, max
end

----------------------------------------------------------------------
-- 6. Movable XP/hour frame (unchanged)
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
    HelloForeverDB = HelloForeverDB or {}
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
    local eta = "--"
    if perHour > 0 then
        local needed = UnitXPMax("player") - UnitXP("player")
        eta = SecondsToTime(needed / perHour * 3600)
    end
    text:SetText(("XP/hour: %s\nLevel in: %s"):format(
        BreakUpLargeNumbers(math.floor(perHour)), eta))
end

----------------------------------------------------------------------
-- 7. Events
----------------------------------------------------------------------
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("PLAYER_XP_UPDATE")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("TIME_PLAYED_MSG")

frame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == addonName then
        HelloForeverDB = HelloForeverDB or {}
        HelloForeverDB.settings = HelloForeverDB.settings or { combatLog = "off" }
        HelloForeverDB.characters = HelloForeverDB.characters or {}
        local pos = HelloForeverDB.pos
        self:ClearAllPoints()
        if pos then
            self:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
        else
            self:SetPoint("TOP", UIParent, "TOP", 0, -120)
        end

    elseif event == "PLAYER_LOGIN" then
        ns.ResetSession()
        Refresh()
        newTicker(1, Refresh)
        -- Request time played (answer arrives as TIME_PLAYED_MSG)
        if type(RequestTimePlayed) == "function" then
            safeCall(RequestTimePlayed)
        end
        pushEvent("login")
        -- Login keyframe
        lastState = nil
        ns.TimelineTick(true)
        applyCombatLogMode(HelloForeverDB.settings.combatLog or "off")
        -- 5-minute timeline ticker
        newTicker(300, function() ns.TimelineTick(false) end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Delay so unit/zone APIs settle
        after(3, function()
            ns.TakeSnapshot("entering_world")
            refreshAutoCombatLog()
        end)

    elseif event == "PLAYER_LOGOUT" then
        pushEvent("logout")
        ns.TimelineTick(false)
        ns.TakeSnapshot("logout")
        -- Ensure combat log off on logout to avoid huge files overnight
        if type(LoggingCombat) == "function" then
            local mode = HelloForeverDB.settings and HelloForeverDB.settings.combatLog
            if mode ~= "on" then LoggingCombat(false) end
        end

    elseif event == "PLAYER_LEVEL_UP" then
        pushEvent("level_up", { level = arg1 })
        after(1, function()
            ns.TakeSnapshot("level_up")
            ns.TimelineTick(false)
        end)

    elseif event == "PLAYER_XP_UPDATE" then
        OnXPUpdate()
        Refresh()

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        local z = safeCall(GetRealZoneText) or safeCall(GetZoneText)
        pushEvent("zone", { zone = z })
        ns.TimelineTick(false)
        refreshAutoCombatLog()

    elseif event == "TIME_PLAYED_MSG" then
        pendingPlayed.total = arg1
        pendingPlayed.level = arg2
        -- Patch latest snapshot if present
        local c = ensureDB()
        if c.snapshot then
            c.snapshot.timePlayed = { total = arg1, level = arg2 }
        end
    end
end)
