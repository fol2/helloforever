-- HelloForever / Snapshot.lua
-- Character snapshot + delta timeline for offline analysis, the play-session counters
-- behind the XP panel, the level log and the optional combat-log helper.
local addonName, ns = ...

local type, ipairs, tostring, pcall, next = type, ipairs, tostring, pcall, next
local floor, min = math.floor, math.min
local GetTime, time = GetTime, time
local call, callAll = ns.Call, ns.CallAll

----------------------------------------------------------------------
-- 1. Snapshot collectors
----------------------------------------------------------------------
local INVENTORY_SLOTS = {
    {1, "head"}, {2, "neck"}, {3, "shoulder"}, {4, "shirt"}, {5, "chest"},
    {6, "waist"}, {7, "legs"}, {8, "feet"}, {9, "wrist"}, {10, "hands"},
    {11, "finger1"}, {12, "finger2"}, {13, "trinket1"}, {14, "trinket2"},
    {15, "back"}, {16, "mainhand"}, {17, "offhand"}, {18, "ranged"}, {19, "tabard"},
}

-- Which API branch each collector used (filled during collect*, shown by /hello debug)
local lastApiUsed = {}

local function oneStat(i)
    local a, b = call(UnitStat, "player", i)
    return b or a
end

local function collectStats()
    local s = {}
    s.str = oneStat(1)
    s.agi = oneStat(2)
    s.sta = oneStat(3)
    s.int = oneStat(4)
    s.spi = oneStat(5)
    local apBase, apPos, apNeg = call(UnitAttackPower, "player")
    if apBase then s.ap = apBase + (apPos or 0) + (apNeg or 0) end
    local rapBase, rapPos, rapNeg = call(UnitRangedAttackPower, "player")
    if rapBase then s.rangedAP = rapBase + (rapPos or 0) + (rapNeg or 0) end
    s.crit = call(GetCritChance)
    s.rangedCrit = call(GetRangedCritChance)
    s.hit = call(GetHitModifier)
    s.spellHit = call(GetSpellHitModifier)
    s.dodge = call(GetDodgeChance)
    s.parry = call(GetParryChance)
    s.block = call(GetBlockChance)
    s.armor = call(UnitArmor, "player")
    return s
end

-- Returns the equipped table and how many slots were filled.
local function collectEquipped()
    local eq = {}
    local count = 0
    for i = 1, #INVENTORY_SLOTS do
        local slot, name = INVENTORY_SLOTS[i][1], INVENTORY_SLOTS[i][2]
        local link = call(GetInventoryItemLink, "player", slot)
        if link then
            eq[name] = link
            count = count + 1
        else
            local id = call(GetInventoryItemID, "player", slot)
            if id then
                eq[name] = "item:" .. tostring(id)
                count = count + 1
            end
        end
    end
    lastApiUsed.equipped = "GetInventoryItemLink+ID"
    lastApiUsed.equippedCount = count
    return eq, count
end

-- Talents.
-- WoW Forever (TOC 16001) has NO classic GetTalentInfo/GetNumTalentTabs. Talents are a
-- C_Traits tree in a config of type Enum.TraitConfigType.CamelotCombat (4), one tree per
-- class; the three classic "tabs" are trait GROUPS of that tree. Blizzard's own Camelot
-- talent frame (wow-ui-source `forever` branch,
-- Blizzard_PlayerSpells/Camelot/ClassTalents/Blizzard_ClassTalentsFrame.lua) gets the
-- config via C_SpecializationInfo.GetCombatConfigIDForSpecGroup(GetActiveSpecGroup()),
-- tabs via C_Traits.GetGroupDisplayInfoByTreeID(treeID), points per tab via
-- C_Traits.GetGroupCurrencyInfo. Snapshot-only (never on the tick). Returns:
--   { src, configID, configType, configName, treeID, spent, unspent,
--     spec = {index,id,name,role},
--     tabs = { {g=groupID, name, points, order} },
--     nodes = { {n=nodeID, r=rank, m=maxRanks, s=spellID, name, g=tabGroupID} } }  -- purchased only
local function spellNameOf(spellID)
    if not spellID then return nil end
    local CS = _G.C_Spell
    if type(CS) == "table" then
        local n = call(CS.GetSpellName, spellID)
        if n then return n end
        local info = call(CS.GetSpellInfo, spellID)
        if type(info) == "table" and info.name then return info.name end
    end
    return (call(_G.GetSpellInfo, spellID)) -- legacy global, absent on Forever
end
ns.SpellName = spellNameOf

local function collectTalents()
    local out = { nodes = {}, tabs = {} }
    lastApiUsed.talents = "none"
    lastApiUsed.talentTabs = 0
    lastApiUsed.talentLeaves = 0
    lastApiUsed.talentNodesScanned = 0
    lastApiUsed.talentFirst = nil

    -- Spec (on Forever the "spec" is class-level, e.g. Warrior specID 1491, pointsSpent 0)
    local SI = _G.C_SpecializationInfo
    local getSpec = (type(SI) == "table" and SI.GetSpecialization) or _G.GetSpecialization
    local getSpecInfo = (type(SI) == "table" and SI.GetSpecializationInfo) or _G.GetSpecializationInfo
    local specIndex = call(getSpec)
    if type(specIndex) == "number" and specIndex > 0 then
        local id, name, _, _, role = call(getSpecInfo, specIndex)
        out.spec = { index = specIndex, id = id, name = name, role = role }
    end

    -- Branch A: Forever / retail trait tree
    local TR = _G.C_Traits
    if type(TR) == "table" and type(TR.GetConfigInfo) == "function" then
        local configID, src
        if type(SI) == "table" and SI.GetCombatConfigIDForSpecGroup then
            local grp = call(SI.GetActiveSpecGroup) or 1
            configID = call(SI.GetCombatConfigIDForSpecGroup, grp)
            src = "SpecInfo.GetCombatConfigIDForSpecGroup"
        end
        if not configID and type(_G.C_ClassTalents) == "table" then
            configID = call(_G.C_ClassTalents.GetActiveConfigID)
            src = "C_ClassTalents.GetActiveConfigID"
        end
        local cfg = configID and call(TR.GetConfigInfo, configID)
        if type(cfg) == "table" and type(cfg.treeIDs) == "table" and cfg.treeIDs[1] then
            local treeID = cfg.treeIDs[1]
            out.src = src .. "+C_Traits"
            out.configID, out.configType, out.configName, out.treeID = configID, cfg.type, cfg.name, treeID
            lastApiUsed.talents = out.src
            lastApiUsed.talentConfigType = cfg.type

            -- Tabs = trait groups of the tree
            local groupSet, groupIDs = {}, {}
            local disp = call(TR.GetGroupDisplayInfoByTreeID, treeID)
            if type(disp) == "table" then
                for _, d in ipairs(disp) do
                    if d.groupID then
                        groupSet[d.groupID] = #out.tabs + 1
                        groupIDs[#groupIDs + 1] = d.groupID
                        out.tabs[#out.tabs + 1] = { g = d.groupID, name = d.displayName, order = d.orderIndex, points = 0 }
                    end
                end
            end
            if #groupIDs > 0 then
                local gc = call(TR.GetGroupCurrencyInfo, configID, groupIDs)
                if type(gc) == "table" then
                    for _, gi in ipairs(gc) do -- groups with 0 spent are omitted
                        local idx = groupSet[gi.traitNodeGroupID]
                        local ci = type(gi.currencyInfos) == "table" and gi.currencyInfos[1]
                        if idx and ci then out.tabs[idx].points = ci.spent or 0 end
                    end
                end
            end
            lastApiUsed.talentTabs = #out.tabs

            -- Spent / unspent across the whole tree
            local tc = call(TR.GetTreeCurrencyInfo, configID, treeID, false)
            if type(tc) == "table" and type(tc[1]) == "table" then
                out.spent = tc[1].spent
                out.unspent = tc[1].quantity
            end

            -- Purchased nodes
            local nodeIDs = call(TR.GetTreeNodes, treeID)
            if type(nodeIDs) == "table" then
                lastApiUsed.talentNodesScanned = #nodeIDs
                for _, nodeID in ipairs(nodeIDs) do
                    local ni = call(TR.GetNodeInfo, configID, nodeID)
                    local rank = ni and (ni.activeRank or ni.ranksPurchased or 0) or 0
                    if rank > 0 then
                        local entryID = (ni.activeEntry and ni.activeEntry.entryID)
                            or (type(ni.entryIDs) == "table" and ni.entryIDs[1])
                        local spellID, name
                        local ei = entryID and call(TR.GetEntryInfo, configID, entryID)
                        local def = ei and ei.definitionID and call(TR.GetDefinitionInfo, ei.definitionID)
                        if type(def) == "table" then
                            spellID = def.overriddenSpellID or def.spellID
                            name = def.overrideName or spellNameOf(spellID)
                        end
                        local g
                        if type(ni.groupIDs) == "table" then -- tab group is not always first
                            for _, gid in ipairs(ni.groupIDs) do
                                if groupSet[gid] then g = gid break end
                            end
                        end
                        out.nodes[#out.nodes + 1] = {
                            n = nodeID, r = rank, m = ni.maxRanks, s = spellID, name = name, g = g,
                        }
                    end
                end
            end
            lastApiUsed.talentLeaves = #out.nodes
        end
    end

    -- Branch B: classic API fallback (absent on Forever; kept for other flavours)
    if #out.nodes == 0 and not out.configID then
        local nTabs = call(_G.GetNumTalentTabs)
        if type(nTabs) == "number" and nTabs > 0 then
            out.src = "GetNumTalentTabs"
            lastApiUsed.talents = out.src
            lastApiUsed.talentTabs = nTabs
            for t = 1, nTabs do
                local _, tabName, _, _, pts = call(_G.GetTalentTabInfo, t) -- 1.13+: id,name,desc,icon,points
                if type(tabName) ~= "string" then tabName, pts = nil, nil end
                out.tabs[t] = { g = t, name = tabName, points = pts or 0 }
                for i = 1, (call(_G.GetNumTalents, t) or 0) do
                    local tName, _, _, _, rank, maxRank = call(_G.GetTalentInfo, t, i)
                    if tName and type(rank) == "number" and rank > 0 then
                        out.nodes[#out.nodes + 1] = { n = t * 100 + i, r = rank, m = maxRank, name = tName, g = t }
                    end
                end
            end
            lastApiUsed.talentLeaves = #out.nodes
        end
    end

    -- Unspent fallback
    if out.unspent == nil then
        local u = call(_G.UnitCharacterPoints, "player")
        if type(u) ~= "number" then u = call(_G.GetUnspentTalentPoints) end
        if type(u) == "number" then out.unspent = u end
    end
    lastApiUsed.talentUnspent = out.unspent

    local first = {}
    for i = 1, min(3, #out.nodes) do
        local nd = out.nodes[i]
        first[i] = tostring(nd.name or nd.s or nd.n) .. " " .. tostring(nd.r) .. "/" .. tostring(nd.m)
    end
    lastApiUsed.talentFirst = table.concat(first, ", ")
    return out
end

local function collectSkills()
    local skills = {}
    lastApiUsed.skills = "none"
    lastApiUsed.skillCount = 0

    -- Branch A: classic GetNumSkillLines / GetSkillLineInfo (capture all returns)
    local n = call(_G.GetNumSkillLines)
    if type(n) == "number" and n > 0 and type(_G.GetSkillLineInfo) == "function" then
        lastApiUsed.skills = "GetSkillLineInfo"
        for i = 1, n do
            local raw = callAll(_G.GetSkillLineInfo, i) or {}
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
        n = call(SI.GetNumSkillLines) or 0
        for i = 1, n do
            local info = call(SI.GetSkillLineInfo, i)
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
    if type(_G.GetProfessions) == "function" and type(_G.GetProfessionInfo) == "function" then
        lastApiUsed.skills = "GetProfessions"
        -- GetProfessions returns up to 5 indices (prof1, prof2, archaeology, fishing, cooking)
        local idxs = callAll(_G.GetProfessions) or {}
        for i = 1, (idxs.n or 0) do
            local idx = idxs[i]
            if type(idx) == "number" then
                local raw = callAll(_G.GetProfessionInfo, idx) or {}
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
        local n = call(R.GetNumFactions) or 0
        for i = 1, n do
            local fd = call(R.GetFactionDataByIndex, i)
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
    local n = call(_G.GetNumFactions) or 0
    for i = 1, n do
        local raw = callAll(_G.GetFactionInfo, i) or {}
        local name = type(raw[1]) == "string" and raw[1] or nil
        local isHeader = raw[9]
        if name and not isHeader then
            reps[#reps + 1] = {
                name = name, standing = raw[3],
                value = raw[6], min = raw[4], max = raw[5],
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
        local n = call(QL.GetNumQuestLogEntries) or 0
        for i = 1, n do
            local info = call(QL.GetInfo, i)
            if type(info) == "table" and info.title and not info.isHeader then
                local level = info.level
                -- If modern level missing/0, try classic GetQuestLogTitle for level
                if (not level or level == 0) and type(_G.GetQuestLogTitle) == "function" then
                    local raw = callAll(_G.GetQuestLogTitle, i) or {}
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
        if #quests > 0 then
            lastApiUsed.quests = "C_QuestLog.GetInfo"
            lastApiUsed.questCount = #quests
            return quests
        end
    end

    -- Classic GetQuestLogTitle: (title, level, questTag, suggestedGroup, isHeader, ...)
    local n = call(_G.GetNumQuestLogEntries) or 0
    lastApiUsed.quests = "GetQuestLogTitle"
    for i = 1, n do
        local raw = callAll(_G.GetQuestLogTitle, i) or {}
        local title = type(raw[1]) == "string" and raw[1] or nil
        local level = type(raw[2]) == "number" and raw[2] or 0
        local isHeader = raw[5]
        -- Some clients put isHeader at index 4; treat a boolean there as the header flag
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

----------------------------------------------------------------------
-- Time played: TIME_PLAYED_MSG arrives once after login; later reads add the time
-- elapsed since, so snapshots and the level log carry current values.
----------------------------------------------------------------------
local played = { total = nil, level = nil, at = nil, levelAt = nil }

-- Returns total seconds played, seconds played this level (either may be nil).
local function playedNow()
    local now = GetTime()
    local total = played.total and (played.total + (now - (played.at or now)))
    local level = played.level and (played.level + (now - (played.levelAt or now)))
    return total and floor(total + 0.5), level and floor(level + 0.5)
end
ns.PlayedNow = playedNow

local function timePlayedTable(prev)
    local total, level = playedNow()
    return {
        total = total or (prev and prev.total),
        level = level or (prev and prev.level),
    }
end

local function zoneText()
    return call(GetRealZoneText) or call(GetZoneText)
end

local function atLevelCap()
    local lvl = call(UnitLevel, "player")
    if type(lvl) ~= "number" or lvl <= 0 then return false end
    if call(_G.IsPlayerAtEffectiveMaxLevel) == true then return true end
    local cap = call(_G.GetMaxLevelForPlayerExpansion) or call(_G.GetMaxPlayerLevel)
    return type(cap) == "number" and cap > 0 and lvl >= cap
end
ns.AtLevelCap = atLevelCap

-- A read of money==0 AND xp==0 AND xpMax==0 is the logout wipe, not real data. A
-- level-capped character legitimately reads xp==0 / xpMax==0, so that pair only counts
-- as real when the client still reports a capped level and some money.
local function isValidXPMoney(xp, xpMax, money)
    if xp == nil and xpMax == nil and money == nil then return false end
    local x = xp or 0
    local xm = xpMax or 0
    local m = money or 0
    if x == 0 and xm == 0 then
        if m == 0 then return false end
        return atLevelCap()
    end
    return true
end

-- A collector that throws keeps the previous snapshot's value instead of losing it.
local function collectField(prev, field, fn)
    local ok, a = pcall(fn)
    if ok then return a end
    lastApiUsed[field .. "Err"] = tostring(a)
    return prev and prev[field] or nil
end

local function collectSnapshot(reason, prev)
    lastApiUsed = {}
    local className, classFile = call(UnitClass, "player")
    local raceName, raceFile = call(UnitRace, "player")
    local factionEn, factionLoc = call(UnitFactionGroup, "player")
    local xp = call(UnitXP, "player")
    local xpMax = call(UnitXPMax, "player")
    local money = call(GetMoney)
    local snap = {
        t = time(),
        reason = reason or "manual",
        name = call(UnitName, "player"),
        realm = call(GetRealmName),
        class = classFile or className,
        className = className,
        race = raceFile or raceName,
        raceName = raceName,
        faction = factionEn or factionLoc,
        level = call(UnitLevel, "player"),
        xp = xp,
        xpMax = xpMax,
        rested = call(GetXPExhaustion),
        money = money,
        zone = zoneText(),
        subzone = call(GetSubZoneText),
        stats = collectField(prev, "stats", collectStats),
        equipped = collectField(prev, "equipped", collectEquipped),
        talents = collectField(prev, "talents", collectTalents),
        skills = collectField(prev, "skills", collectSkills),
        reputations = collectField(prev, "reputations", collectReputations),
        quests = collectField(prev, "quests", collectQuests),
        timePlayed = timePlayedTable(prev and prev.timePlayed),
        _apiUsed = lastApiUsed,
        _valid = isValidXPMoney(xp, xpMax, money),
    }
    return ns.Stamp(snap)
end

-- Full snapshot (entering world, slash, level-up). Skips the overwrite if the new read
-- looks wiped (all zeros) and we already have a good one.
function ns.TakeSnapshot(reason)
    local c = ns.Char()
    local snap = collectSnapshot(reason, c.snapshot)
    if not snap._valid and c.snapshot and c.snapshot._valid ~= false then
        return c.snapshot
    end
    c.snapshot = snap
    return snap
end

-- Lightweight logout: do NOT re-read stats/money/xp/equipment (the APIs return 0 by
-- then). Keep the last good snapshot and only update timePlayed / zone / reason / t.
function ns.LogoutTouch()
    local c = ns.Char()
    local prev = c.snapshot
    if not prev then
        c.snapshot = ns.Stamp({
            t = time(),
            reason = "logout",
            name = call(UnitName, "player"),
            realm = call(GetRealmName),
            zone = zoneText(),
            subzone = call(GetSubZoneText),
            timePlayed = timePlayedTable(),
            _valid = false,
            _logoutStub = true,
        })
        return c.snapshot
    end
    prev.t = time()
    prev.reason = "logout"
    prev.zone = zoneText() or prev.zone
    prev.subzone = call(GetSubZoneText) or prev.subzone
    prev.timePlayed = timePlayedTable(prev.timePlayed)
    ns.Stamp(prev)
    return prev
end

-- Money-only patch of the current snapshot.
function ns.PatchMoney()
    local c = ns.Char()
    local snap = c.snapshot
    if not snap then return end
    local money = call(GetMoney)
    if money == nil then return end
    -- Reject a zero-wipe if we previously had non-zero money
    if money == 0 and type(snap.money) == "number" and snap.money > 0 then return end
    snap.money = money
    snap.t = time()
end

-- Equipment-only patch.
function ns.PatchEquipped()
    local c = ns.Char()
    local snap = c.snapshot
    if not snap then return end
    local eq, n = collectEquipped()
    -- Don't wipe a populated equipped table with an empty one
    if n == 0 and type(snap.equipped) == "table" and next(snap.equipped) ~= nil then return end
    snap.equipped = eq
    snap.t = time()
end

-- Refresh stats (+ xp/money/zone) on the existing snapshot without rebuilding talents etc.
function ns.RefreshLiveFields()
    local c = ns.Char()
    local snap = c.snapshot
    if not snap then return ns.TakeSnapshot("periodic") end
    local xp = call(UnitXP, "player")
    local xpMax = call(UnitXPMax, "player")
    local money = call(GetMoney)
    if isValidXPMoney(xp, xpMax, money) then
        snap.xp = xp
        snap.xpMax = xpMax
        snap.money = money
        snap.level = call(UnitLevel, "player") or snap.level
        snap.rested = call(GetXPExhaustion)
        snap.stats = collectStats()
        snap.zone = zoneText() or snap.zone
        snap.subzone = call(GetSubZoneText) or snap.subzone
        snap.timePlayed = timePlayedTable(snap.timePlayed)
        snap.t = time()
        snap._valid = true
    end
    return snap
end

function ns.ApiUsed()
    return lastApiUsed
end

----------------------------------------------------------------------
-- 2. Timeline: idle dedupe + delta encoding + periodic keyframes
----------------------------------------------------------------------
local TL_FIELDS = { "zone", "subzone", "level", "xp", "money" }
local TL_N = #TL_FIELDS
local TL_CAP = 2000
local TL_KEYFRAME_EVERY = 12
local lastState = nil

local function currentTLState()
    local xp = call(UnitXP, "player")
    local xpMax = call(UnitXPMax, "player")
    local money = call(GetMoney)
    -- Invalid wipe read: nil so TimelineTick skips it
    if not isValidXPMoney(xp, xpMax, money) then return nil end
    return {
        zone = zoneText() or "",
        subzone = call(GetSubZoneText) or "",
        level = call(UnitLevel, "player") or 0,
        xp = xp or 0,
        money = money or 0,
    }
end

-- Deltas can only be decoded from a keyframe, so after dropping the oldest entries the
-- list is cut forward to the next keyframe.
local function trimTimeline(tl)
    if ns.TrimHead(tl, TL_CAP, 24) == 0 then return end
    local first = 1
    while tl[first] and not tl[first].k do first = first + 1 end
    if first > 1 and tl[first] then
        local n = #tl
        local drop = first - 1
        for i = 1, n - drop do tl[i] = tl[i + drop] end
        for i = n - drop + 1, n do tl[i] = nil end
    end
end

function ns.TimelineTick(forceKeyframe)
    local c = ns.Char()
    local tl = c.timeline
    local state = currentTLState()
    if not state then return end
    local now = time()

    if lastState and not forceKeyframe then
        local same = true
        for i = 1, TL_N do
            local f = TL_FIELDS[i]
            if state[f] ~= lastState[f] then same = false break end
        end
        if same then
            local last = tl[#tl]
            if last then
                last.last = now
                last.n = (last.n or 1) + 1
            end
            return
        end
    end

    local entry = { t = now, last = now, n = 1 }
    if forceKeyframe or lastState == nil or (c._tlCount % TL_KEYFRAME_EVERY) == 0 then
        entry.k = true
        for i = 1, TL_N do
            local f = TL_FIELDS[i]
            entry[f] = state[f]
        end
    else
        for i = 1, TL_N do
            local f = TL_FIELDS[i]
            if state[f] ~= lastState[f] then entry[f] = state[f] end
        end
    end

    tl[#tl + 1] = entry
    c._tlCount = c._tlCount + 1
    lastState = state
    trimTimeline(tl)
end

----------------------------------------------------------------------
-- 3. Combat-log helper. "off" (the default) means hands off: HelloForever only stops
--    logging when asked to with /hello combatlog off, never on its own at login, so it
--    does not fight a logger the player started some other way.
----------------------------------------------------------------------
local function setLogging(on)
    if type(_G.LoggingCombat) == "function" then pcall(_G.LoggingCombat, on and true or false) end
end

local function wantAutoLogging()
    if type(_G.IsInInstance) ~= "function" then return false end
    local ok, inInst, instType = pcall(_G.IsInInstance)
    return ok and inInst and (instType == "party" or instType == "raid") or false
end

function ns.SetCombatLogMode(mode)
    local settings = ns.settings or ns.InitDB().settings
    settings.combatLog = mode
    if mode == "on" then
        setLogging(true)
    elseif mode == "off" then
        setLogging(false)
    elseif mode == "auto" then
        setLogging(wantAutoLogging())
    end
end

local function refreshAutoCombatLog()
    if ns.settings and ns.settings.combatLog == "auto" then setLogging(wantAutoLogging()) end
end

----------------------------------------------------------------------
-- 4. Play session (in memory): XP rate, gold, fight totals for the panel
----------------------------------------------------------------------
local session = {}
ns.session = session

function ns.ResetSession()
    session.start = GetTime()
    session.xp = 0
    session.lastXP, session.lastMax = call(UnitXP, "player"), call(UnitXPMax, "player")
    session.money0 = call(GetMoney)
    session.fights, session.dmg, session.fightSec, session.deaths = 0, 0, 0, 0
    session.bestDps, session.bestName = 0, nil
    session.last = nil
    ns.Notify("SESSION")
end

local function onXPUpdate()
    local cur, max = call(UnitXP, "player"), call(UnitXPMax, "player")
    if not cur or not max then return end
    local lastXP = session.lastXP
    if lastXP then
        local delta = cur - lastXP
        -- XP went down: we levelled, so add what was left of the old level
        if delta < 0 then delta = ((session.lastMax or lastXP) - lastXP) + cur end
        if delta > 0 then session.xp = (session.xp or 0) + delta end
    end
    session.lastXP, session.lastMax = cur, max
end

-- XP per hour this session, seconds until the next level at that rate (nil if unknown).
function ns.XPRate()
    local start = session.start
    if not start then return 0, nil end
    local hours = (GetTime() - start) / 3600
    local perHour = hours > 0 and (session.xp or 0) / hours or 0
    if perHour <= 0 then return 0, nil end
    local cur, max = call(UnitXP, "player"), call(UnitXPMax, "player")
    if not cur or not max or max <= 0 then return perHour, nil end
    return perHour, (max - cur) / perHour * 3600
end

-- Copper gained (or lost) this session and the hourly rate.
function ns.MoneyRate()
    local now = call(GetMoney)
    if not now or not session.money0 or not session.start then return 0, 0 end
    local delta = now - session.money0
    local hours = (GetTime() - session.start) / 3600
    return delta, hours > 0 and delta / hours or 0
end

-- Fight totals for the session; fed by Fights.lua each time a fight is stored.
ns.Listen("FIGHT", function(s, isNew, prev)
    if type(s) ~= "table" or s.gap then return end
    local dmg, dur = s.dmg or 0, s.dur or 0
    if isNew then
        session.fights = (session.fights or 0) + 1
        if s.died then session.deaths = (session.deaths or 0) + 1 end
    elseif type(prev) == "table" then
        -- a re-read of a grown session: count only what was added
        dmg, dur = dmg - (prev.dmg or 0), dur - (prev.dur or 0)
        if s.died and not prev.died then session.deaths = (session.deaths or 0) + 1 end
    end
    session.dmg = (session.dmg or 0) + dmg
    session.fightSec = (session.fightSec or 0) + dur
    if (s.dps or 0) > (session.bestDps or 0) and (s.dur or 0) >= 5 then
        session.bestDps, session.bestName = s.dps, s.name
    end
    session.last = s
end)

----------------------------------------------------------------------
-- 5. Level log: when each level was reached and how long the previous one took
----------------------------------------------------------------------
local LEVELS_CAP = 100

local function logLevel(level)
    if type(level) ~= "number" then return end
    local c = ns.Char()
    if type(c.levels) ~= "table" then c.levels = {} end
    local total, inLevel = playedNow()
    local log = c.levels
    log[#log + 1] = { level = level, t = time(), played = total, took = inLevel }
    ns.TrimHead(log, LEVELS_CAP, 0)
    -- the per-level clock restarts at the ding
    if played.level then played.level, played.levelAt = 0, GetTime() end
end

function ns.PrintLevels(n)
    local log = ns.Char().levels
    if type(log) ~= "table" or #log == 0 then
        ns.Print("no level-ups recorded yet (each ding is logged from now on).")
        return
    end
    n = n or 10
    print(("%s levels: last %d of %d"):format(ns.PREFIX, min(n, #log), #log))
    for i = #log, math.max(1, #log - n + 1), -1 do
        local e = log[i]
        print(("  %s  level %s%s%s"):format(
            date("%Y-%m-%d %H:%M", e.t or 0), tostring(e.level),
            e.took and ("  took " .. ns.FmtDur(e.took)) or "",
            e.played and ("  (played " .. ns.FmtDur(e.played) .. ")") or ""))
    end
end

----------------------------------------------------------------------
-- 6. Events
----------------------------------------------------------------------
local PERIODIC_SEC = 300

ns.On("PLAYER_LOGIN", function()
    ns.ResetSession()
    call(_G.RequestTimePlayed)
    ns.PushEvent("login")
    lastState = nil
    ns.TimelineTick(true)
    local mode = ns.settings.combatLog
    if mode == "on" or mode == "auto" then ns.SetCombatLogMode(mode) end
    -- 5-minute timeline tick + live field refresh (stats/xp/money/zone)
    ns.Ticker(PERIODIC_SEC, function()
        ns.TimelineTick(false)
        ns.AfterCombat("live", ns.RefreshLiveFields)
    end)
end)

local worldPending = false

ns.On("PLAYER_ENTERING_WORLD", function()
    if worldPending then return end
    worldPending = true
    -- Delay so unit/zone/equipment APIs settle; this is the primary full snapshot
    ns.After(3, function()
        worldPending = false
        ns.AfterCombat("snap", function() ns.TakeSnapshot("entering_world") end)
        if not lastState then ns.TimelineTick(true) end
        refreshAutoCombatLog()
    end)
end)

ns.On("PLAYER_LOGOUT", function()
    ns.PushEvent("logout")
    -- TimelineTick no-ops if the logout wipe is detected.
    ns.TimelineTick(false)
    ns.LogoutTouch()
    if ns.settings.combatLog == "auto" then setLogging(false) end
end)

ns.On("PLAYER_LEVEL_UP", function(level)
    level = ns.Plain(level)
    ns.PushEvent("level_up", { level = level })
    logLevel(level)
    ns.After(1, function()
        ns.AfterCombat("snap", function() ns.TakeSnapshot("level_up") end)
        ns.TimelineTick(false)
        ns.Notify("XP")
    end)
end)

ns.On("PLAYER_XP_UPDATE", function()
    onXPUpdate()
    ns.Notify("XP")
end)

ns.On("UPDATE_EXHAUSTION", function()
    ns.Notify("XP")
end)

local function zoneChanged()
    ns.PushEvent("zone", { zone = zoneText() })
    ns.TimelineTick(false)
    refreshAutoCombatLog()
end

ns.On("ZONE_CHANGED_NEW_AREA", function()
    ns.Debounce("zone", 10, zoneChanged)
end)

local function moneyChanged()
    ns.PatchMoney()
    ns.TimelineTick(false)
end

ns.On("PLAYER_MONEY", function()
    ns.Debounce("money", 10, moneyChanged)
end)

ns.On("PLAYER_EQUIPMENT_CHANGED", function()
    ns.Debounce("equip", 10, ns.PatchEquipped)
end)

ns.On("TIME_PLAYED_MSG", function(total, level)
    total, level = ns.Plain(total), ns.Plain(level)
    if type(total) ~= "number" then return end
    local now = GetTime()
    played.total, played.at = total, now
    played.level, played.levelAt = type(level) == "number" and level or nil, now
    local c = ns.Char()
    if c.snapshot then
        c.snapshot.timePlayed = { total = total, level = played.level }
    end
end)
