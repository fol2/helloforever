-- HelloForever v0.2.1: XP/hour UI + character snapshot / timeline for offline analysis.
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

-- Capture ALL return values from a pcall'd function into a list (1..n).
-- Used so we can inspect what this client actually returns for talent/skill APIs.
local function safeCallAll(fn, ...)
    if type(fn) ~= "function" then return nil end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil end
    -- drop the ok flag; return packed table of returns
    local out = {}
    for i = 2, #results do
        out[i - 1] = results[i]
    end
    out.n = #results - 1
    return out
end

local function after(sec, fn)
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(sec, fn)
    else
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
    while #ev > 500 do table.remove(ev, 1) end
end

-- Throttle helper: returns true if enough time has passed since last fire.
local throttleAt = {}
local function throttled(key, minSec)
    local now = GetTime()
    local last = throttleAt[key] or 0
    if now - last < minSec then return false end
    throttleAt[key] = now
    return true
end

----------------------------------------------------------------------
-- 1. Snapshot collectors
----------------------------------------------------------------------
local INVENTORY_SLOTS = {
    {1, "head"}, {2, "neck"}, {3, "shoulder"}, {4, "shirt"}, {5, "chest"},
    {6, "waist"}, {7, "legs"}, {8, "feet"}, {9, "wrist"}, {10, "hands"},
    {11, "finger1"}, {12, "finger2"}, {13, "trinket1"}, {14, "trinket2"},
    {15, "back"}, {16, "mainhand"}, {17, "offhand"}, {18, "ranged"}, {19, "tabard"},
}

-- Which API branch each collector used (filled during collect*, exposed via /hello debug)
local lastApiUsed = {}

local function collectStats()
    local s = {}
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
    local count = 0
    for _, pair in ipairs(INVENTORY_SLOTS) do
        local slot, name = pair[1], pair[2]
        local link = safeCall(GetInventoryItemLink, "player", slot)
        if link then
            eq[name] = link
            count = count + 1
        else
            local id = safeCall(GetInventoryItemID, "player", slot)
            if id then
                eq[name] = "item:" .. tostring(id)
                count = count + 1
            end
        end
    end
    lastApiUsed.equipped = "GetInventoryItemLink+ID"
    lastApiUsed.equippedCount = count
    return eq
end

local function collectTalents()
    local tabs = {}
    lastApiUsed.talents = "none"
    lastApiUsed.talentTabs = 0
    lastApiUsed.talentLeaves = 0

    -- Branch A: classic GetNumTalentTabs / GetTalentTabInfo / GetTalentInfo
    -- Capture ALL returns — classic/forever return positions vary.
    local nTabs = safeCall(GetNumTalentTabs)
    if type(nTabs) == "number" and nTabs > 0 then
        lastApiUsed.talents = "GetNumTalentTabs"
        lastApiUsed.talentTabs = nTabs
        for t = 1, nTabs do
            local raw = safeCallAll(GetTalentTabInfo, t) or {}
            -- Heuristic: first string is name; first number that looks like points
            -- is pointsSpent. Also keep raw for offline inspection.
            local name, pointsSpent, background
            for i = 1, (raw.n or 0) do
                local v = raw[i]
                if type(v) == "string" and not name then
                    name = v
                elseif type(v) == "number" and not pointsSpent and i > 1 then
                    -- skip iconTexture (often a number/string); prefer small ints as points
                    if v >= 0 and v <= 100 and type(raw[i - 1]) ~= "nil" then
                        -- common layouts:
                        -- (name, icon, pointsSpent, background, ...)
                        -- (name, iconTexture, pointsSpent, background, previewPointsSpent, ...)
                        if type(raw[2]) == "string" or type(raw[2]) == "number" then
                            if i == 3 then pointsSpent = v end
                        end
                    end
                end
            end
            -- Prefer explicit index 3 if present and numeric (classic)
            if type(raw[3]) == "number" then pointsSpent = raw[3] end
            if type(raw[1]) == "string" then name = raw[1] end
            if type(raw[4]) == "string" then background = raw[4]
            elseif type(raw[4]) == "number" and type(raw[5]) == "string" then background = raw[5]
            end

            local tab = {
                name = name,
                points = pointsSpent or 0,
                background = background,
                talents = {},
                _rawTab = raw, -- keep packed returns for offline analysis
            }
            local nTal = safeCall(GetNumTalents, t) or 0
            for i = 1, nTal do
                local tr = safeCallAll(GetTalentInfo, t, i) or {}
                local tName, tier, column, rank, maxRank
                if type(tr[1]) == "string" then tName = tr[1] end
                -- classic: name, iconTexture, tier, column, rank, maxRank, ...
                if type(tr[3]) == "number" then tier = tr[3] end
                if type(tr[4]) == "number" then column = tr[4] end
                if type(tr[5]) == "number" then rank = tr[5] end
                if type(tr[6]) == "number" then maxRank = tr[6] end
                if tName then
                    tab.talents[#tab.talents + 1] = {
                        name = tName, tier = tier, column = column,
                        rank = rank or 0, maxRank = maxRank or 0,
                        _raw = tr,
                    }
                    lastApiUsed.talentLeaves = lastApiUsed.talentLeaves + 1
                end
            end
            tabs[#tabs + 1] = tab
        end
        if #tabs > 0 then return tabs end
    end

    -- Branch B: C_ClassTalents / C_Traits (retail-ish; may exist on hybrid clients)
    local CT = _G.C_ClassTalents
    local TR = _G.C_Traits
    if type(CT) == "table" and type(TR) == "table" then
        lastApiUsed.talents = "C_ClassTalents+C_Traits"
        local configID = safeCall(CT.GetActiveConfigID)
        if configID and type(TR.GetConfigInfo) == "function" then
            local cfg = safeCall(TR.GetConfigInfo, configID)
            tabs[#tabs + 1] = {
                name = "activeConfig",
                configID = configID,
                _config = cfg,
                talents = {},
            }
            return tabs
        end
    end

    return tabs
end

local function collectSkills()
    local skills = {}
    lastApiUsed.skills = "none"
    lastApiUsed.skillCount = 0

    -- Branch A: classic GetNumSkillLines / GetSkillLineInfo (capture all returns)
    local n = safeCall(GetNumSkillLines)
    if type(n) == "number" and n > 0 and type(GetSkillLineInfo) == "function" then
        lastApiUsed.skills = "GetSkillLineInfo"
        for i = 1, n do
            local raw = safeCallAll(GetSkillLineInfo, i) or {}
            -- classic: name, header, isExpanded, skillRank, numTempPoints, skillModifier, skillMaxRank, ...
            local name = type(raw[1]) == "string" and raw[1] or nil
            local isHeader = raw[2]
            local rank = type(raw[4]) == "number" and raw[4] or nil
            local maxRank = type(raw[7]) == "number" and raw[7] or nil
            if name and not isHeader and rank then
                skills[#skills + 1] = {
                    name = name, rank = rank, max = maxRank or 0, _raw = raw,
                }
            end
        end
        lastApiUsed.skillCount = #skills
        if #skills > 0 then return skills end
    end

    -- Branch B: C_SkillInfo
    local SI = _G.C_SkillInfo
    if type(SI) == "table" and type(SI.GetNumSkillLines) == "function" then
        lastApiUsed.skills = "C_SkillInfo"
        n = safeCall(SI.GetNumSkillLines) or 0
        for i = 1, n do
            local info
            if type(SI.GetSkillLineInfo) == "function" then
                info = safeCall(SI.GetSkillLineInfo, i)
            end
            if type(info) == "table" and info.name and not info.isHeader then
                skills[#skills + 1] = {
                    name = info.name,
                    rank = info.rank or info.skillRank,
                    max = info.maxRank or info.skillMaxRank or 0,
                    _raw = info,
                }
            end
        end
        lastApiUsed.skillCount = #skills
        if #skills > 0 then return skills end
    end

    -- Branch C: GetProfessions / GetProfessionInfo (Cataclysm+)
    if type(GetProfessions) == "function" and type(GetProfessionInfo) == "function" then
        lastApiUsed.skills = "GetProfessions"
        -- GetProfessions returns up to 5 indices (prof1, prof2, archaeology, fishing, cooking)
        local idxs = safeCallAll(GetProfessions) or {}
        for i = 1, (idxs.n or 0) do
            local idx = idxs[i]
            if type(idx) == "number" then
                local raw = safeCallAll(GetProfessionInfo, idx) or {}
                -- name, icon, skillLevel, maxSkillLevel, numAbilities, spelloffset, skillLine, ...
                if type(raw[1]) == "string" then
                    skills[#skills + 1] = {
                        name = raw[1],
                        rank = type(raw[3]) == "number" and raw[3] or 0,
                        max = type(raw[4]) == "number" and raw[4] or 0,
                        _raw = raw,
                    }
                end
            end
        end
        lastApiUsed.skillCount = #skills
    end

    return skills
end

local function collectReputations()
    local reps = {}
    lastApiUsed.reputations = "none"
    local R = _G.C_Reputation
    if type(R) == "table" and type(R.GetNumFactions) == "function"
        and type(R.GetFactionDataByIndex) == "function" then
        lastApiUsed.reputations = "C_Reputation"
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
        lastApiUsed.repCount = #reps
        return reps
    end
    lastApiUsed.reputations = "GetFactionInfo"
    local n = safeCall(GetNumFactions) or 0
    for i = 1, n do
        local raw = safeCallAll(GetFactionInfo, i) or {}
        local name = type(raw[1]) == "string" and raw[1] or nil
        local standingID = raw[3]
        local barMin, barMax, barValue = raw[4], raw[5], raw[6]
        local isHeader = raw[9]
        if name and not isHeader then
            reps[#reps + 1] = {
                name = name, standing = standingID,
                value = barValue, min = barMin, max = barMax,
            }
        end
    end
    lastApiUsed.repCount = #reps
    return reps
end

local function collectQuests()
    local quests = {}
    lastApiUsed.quests = "none"
    lastApiUsed.questCount = 0
    local QL = _G.C_QuestLog

    -- Prefer C_QuestLog.GetInfo if it yields titles; still try classic for level.
    if type(QL) == "table" and type(QL.GetNumQuestLogEntries) == "function" then
        local n = safeCall(QL.GetNumQuestLogEntries) or 0
        local usedModern = false
        for i = 1, n do
            local info
            if type(QL.GetInfo) == "function" then
                info = safeCall(QL.GetInfo, i)
            end
            if type(info) == "table" and info.title and not info.isHeader then
                usedModern = true
                local level = info.level
                -- If modern level missing/0, try classic GetQuestLogTitle for level
                if (not level or level == 0) and type(GetQuestLogTitle) == "function" then
                    local raw = safeCallAll(GetQuestLogTitle, i) or {}
                    if type(raw[2]) == "number" and raw[2] > 0 then
                        level = raw[2]
                    end
                end
                quests[#quests + 1] = {
                    title = info.title,
                    level = level or 0,
                    complete = info.isComplete and true or false,
                    questID = info.questID,
                }
            end
        end
        if usedModern and #quests > 0 then
            lastApiUsed.quests = "C_QuestLog.GetInfo"
            lastApiUsed.questCount = #quests
            return quests
        end
    end

    -- Classic GetQuestLogTitle: (title, level, questTag, suggestedGroup, isHeader, ...)
    local n = safeCall(GetNumQuestLogEntries) or 0
    lastApiUsed.quests = "GetQuestLogTitle"
    for i = 1, n do
        local raw = safeCallAll(GetQuestLogTitle, i) or {}
        local title = type(raw[1]) == "string" and raw[1] or nil
        local level = type(raw[2]) == "number" and raw[2] or 0
        local isHeader = raw[5]
        -- Some clients put isHeader at index 4; treat truthy non-number as header flag
        if type(raw[4]) == "boolean" then isHeader = raw[4] end
        if type(raw[5]) == "boolean" then isHeader = raw[5] end
        local isComplete = raw[6]
        if title and not isHeader then
            quests[#quests + 1] = {
                title = title,
                level = level,
                complete = (isComplete == 1) or (isComplete == true) or false,
                _raw = raw,
            }
        end
    end
    lastApiUsed.questCount = #quests
    return quests
end

-- timePlayed filled asynchronously via TIME_PLAYED_MSG
local pendingPlayed = { total = nil, level = nil }

-- A read of money==0 AND xp==0 AND xpMax==0 is treated as invalid (logout wipe).
local function isValidXPMoney(xp, xpMax, money)
    if xp == nil and xpMax == nil and money == nil then return false end
    local x = xp or 0
    local xm = xpMax or 0
    local m = money or 0
    if x == 0 and xm == 0 and m == 0 then
        return false
    end
    -- xpMax==0 with any xp is also nonsense mid-game
    if xm == 0 and x == 0 then
        return false
    end
    return true
end

local function collectSnapshot(reason)
    lastApiUsed = {}
    local className, classFile = safeCall(UnitClass, "player")
    local raceName, raceFile = safeCall(UnitRace, "player")
    local factionEn, factionLoc = safeCall(UnitFactionGroup, "player")
    local xp = safeCall(UnitXP, "player")
    local xpMax = safeCall(UnitXPMax, "player")
    local money = safeCall(GetMoney)
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
        xp = xp,
        xpMax = xpMax,
        rested = safeCall(GetXPExhaustion),
        money = money,
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
        _apiUsed = lastApiUsed,
        _valid = isValidXPMoney(xp, xpMax, money),
    }
    return snap
end

-- Full snapshot (entering world, slash, level-up, periodic). Skips overwrite
-- if the new read looks wiped (all zeros) and we already have a good one.
function ns.TakeSnapshot(reason)
    local c = ensureDB()
    local snap = collectSnapshot(reason)
    if not snap._valid and c.snapshot and c.snapshot._valid ~= false then
        -- Keep previous good snapshot; only refresh metadata if caller insists
        -- via lightweight logout path. For full takes, refuse the wipe.
        return c.snapshot
    end
    c.snapshot = snap
    return c.snapshot
end

-- Lightweight logout: do NOT re-read stats/money/xp/equipment. Keep last good
-- snapshot and only update timePlayed / zone / reason / t.
function ns.LogoutTouch()
    local c = ensureDB()
    local prev = c.snapshot
    if not prev then
        -- Nothing to keep; still avoid a wiped full collect — store a stub.
        c.snapshot = {
            t = time(),
            reason = "logout",
            name = safeCall(UnitName, "player"),
            realm = safeCall(GetRealmName),
            zone = safeCall(GetRealZoneText) or safeCall(GetZoneText),
            subzone = safeCall(GetSubZoneText),
            timePlayed = {
                total = pendingPlayed.total,
                level = pendingPlayed.level,
            },
            _valid = false,
            _logoutStub = true,
        }
        return c.snapshot
    end
    prev.t = time()
    prev.reason = "logout"
    prev.zone = safeCall(GetRealZoneText) or safeCall(GetZoneText) or prev.zone
    prev.subzone = safeCall(GetSubZoneText) or prev.subzone
    prev.timePlayed = {
        total = pendingPlayed.total or (prev.timePlayed and prev.timePlayed.total),
        level = pendingPlayed.level or (prev.timePlayed and prev.timePlayed.level),
    }
    return prev
end

-- Money-only patch of the current snapshot (throttled caller).
function ns.PatchMoney()
    local c = ensureDB()
    local money = safeCall(GetMoney)
    if money == nil then return end
    -- Reject zero-wipe if we previously had non-zero money
    if money == 0 and c.snapshot and type(c.snapshot.money) == "number" and c.snapshot.money > 0 then
        return
    end
    if c.snapshot then
        c.snapshot.money = money
        c.snapshot.t = time()
    end
end

-- Equipment-only patch (throttled caller).
function ns.PatchEquipped()
    local c = ensureDB()
    if not c.snapshot then return end
    local eq = collectEquipped()
    -- Don't wipe a populated equipped table with an empty one
    local n = 0
    for _ in pairs(eq) do n = n + 1 end
    if n == 0 then
        local prev = 0
        if type(c.snapshot.equipped) == "table" then
            for _ in pairs(c.snapshot.equipped) do prev = prev + 1 end
        end
        if prev > 0 then return end
    end
    c.snapshot.equipped = eq
    c.snapshot.t = time()
end

-- Refresh stats (+ xp/money/zone) on the existing snapshot without rebuilding talents etc.
function ns.RefreshLiveFields()
    local c = ensureDB()
    if not c.snapshot then
        ns.TakeSnapshot("periodic")
        return c.snapshot
    end
    local xp = safeCall(UnitXP, "player")
    local xpMax = safeCall(UnitXPMax, "player")
    local money = safeCall(GetMoney)
    if isValidXPMoney(xp, xpMax, money) then
        c.snapshot.xp = xp
        c.snapshot.xpMax = xpMax
        c.snapshot.money = money
        c.snapshot.level = safeCall(UnitLevel, "player") or c.snapshot.level
        c.snapshot.rested = safeCall(GetXPExhaustion)
        c.snapshot.stats = collectStats()
        c.snapshot.zone = safeCall(GetRealZoneText) or safeCall(GetZoneText) or c.snapshot.zone
        c.snapshot.subzone = safeCall(GetSubZoneText) or c.snapshot.subzone
        c.snapshot.t = time()
        c.snapshot._valid = true
    end
    return c.snapshot
end

----------------------------------------------------------------------
-- 2. Timeline: idle dedupe + delta encoding + periodic keyframes
----------------------------------------------------------------------
local TL_FIELDS = { "zone", "subzone", "level", "xp", "money" }
local TL_CAP = 2000
local TL_KEYFRAME_EVERY = 12
local lastState = nil

local function currentTLState()
    local xp = safeCall(UnitXP, "player")
    local xpMax = safeCall(UnitXPMax, "player")
    local money = safeCall(GetMoney)
    -- Invalid wipe read → return nil so TimelineTick can skip
    if not isValidXPMoney(xp, xpMax, money) then
        return nil
    end
    return {
        zone = safeCall(GetRealZoneText) or safeCall(GetZoneText) or "",
        subzone = safeCall(GetSubZoneText) or "",
        level = safeCall(UnitLevel, "player") or 0,
        xp = xp or 0,
        money = money or 0,
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

function ns.TimelineTick(forceKeyframe)
    local c = ensureDB()
    local tl = c.timeline
    local now = time()
    local state = currentTLState()

    -- Skip invalid reads (logout wipe of xp/money/xpMax)
    if not state then
        return
    end

    if lastState and statesEqual(state, lastState) and not forceKeyframe then
        local last = tl[#tl]
        if last then
            last.last = now
            last.n = (last.n or 1) + 1
        end
        return
    end

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
local function printApiUsed()
    local a = lastApiUsed
    if type(a) ~= "table" then
        local c = ensureDB()
        a = (c.snapshot and c.snapshot._apiUsed) or {}
    end
    print("|cff33ff99HelloForever|r debug _apiUsed:")
    print("  talents=" .. tostring(a.talents)
        .. " tabs=" .. tostring(a.talentTabs)
        .. " leaves=" .. tostring(a.talentLeaves))
    print("  skills=" .. tostring(a.skills)
        .. " count=" .. tostring(a.skillCount))
    print("  reputations=" .. tostring(a.reputations)
        .. " count=" .. tostring(a.repCount))
    print("  quests=" .. tostring(a.quests)
        .. " count=" .. tostring(a.questCount))
    print("  equipped=" .. tostring(a.equipped)
        .. " count=" .. tostring(a.equippedCount))
    local c = ensureDB()
    local s = c.snapshot
    if s then
        local eqN = 0
        if type(s.equipped) == "table" then for _ in pairs(s.equipped) do eqN = eqN + 1 end end
        print(("  snapshot reason=%s valid=%s level=%s xp=%s/%s money=%s eq=%d tal=%d sk=%d q=%d")
            :format(
                tostring(s.reason), tostring(s._valid),
                tostring(s.level), tostring(s.xp), tostring(s.xpMax),
                tostring(s.money), eqN,
                type(s.talents) == "table" and #s.talents or 0,
                type(s.skills) == "table" and #s.skills or 0,
                type(s.quests) == "table" and #s.quests or 0
            ))
    else
        print("  (no snapshot yet)")
    end
end

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
        print(("|cff33ff99HelloForever|r: snapshot saved (level %s, %s, valid=%s).")
            :format(tostring(snap.level), tostring(snap.zone), tostring(snap._valid)))
        return
    end
    if cmd == "debug" then
        -- Force a live collect so lastApiUsed is fresh, without overwriting a
        -- good snapshot with a wipe (TakeSnapshot already guards).
        ns.TakeSnapshot("debug")
        printApiUsed()
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
frame:RegisterEvent("PLAYER_MONEY")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

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
        if type(RequestTimePlayed) == "function" then
            safeCall(RequestTimePlayed)
        end
        pushEvent("login")
        lastState = nil
        ns.TimelineTick(true)
        applyCombatLogMode(HelloForeverDB.settings.combatLog or "off")
        -- 5-minute timeline tick + live field refresh (stats/xp/money/zone)
        newTicker(300, function()
            ns.TimelineTick(false)
            ns.RefreshLiveFields()
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Delay so unit/zone/equipment APIs settle; this is the primary full snap
        after(3, function()
            ns.TakeSnapshot("entering_world")
            -- Also force a keyframe once data is valid
            if not lastState then
                ns.TimelineTick(true)
            end
            refreshAutoCombatLog()
        end)

    elseif event == "PLAYER_LOGOUT" then
        pushEvent("logout")
        -- Lightweight: do NOT re-read stats/money/xp/equipment (APIs return 0).
        -- TimelineTick will no-op if the wipe-read is detected.
        ns.TimelineTick(false)
        ns.LogoutTouch()
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
        if not throttled("zone", 10) then return end
        local z = safeCall(GetRealZoneText) or safeCall(GetZoneText)
        pushEvent("zone", { zone = z })
        ns.TimelineTick(false)
        refreshAutoCombatLog()

    elseif event == "PLAYER_MONEY" then
        -- money-only patch, throttled >=10s
        if not throttled("money", 10) then return end
        ns.PatchMoney()
        ns.TimelineTick(false)

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        if not throttled("equip", 10) then return end
        ns.PatchEquipped()

    elseif event == "TIME_PLAYED_MSG" then
        pendingPlayed.total = arg1
        pendingPlayed.level = arg2
        local c = ensureDB()
        if c.snapshot then
            c.snapshot.timePlayed = { total = arg1, level = arg2 }
        end
    end
end)
