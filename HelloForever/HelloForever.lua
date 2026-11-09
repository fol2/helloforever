-- HelloForever v0.4.0: XP/hour UI + character snapshot / timeline for offline analysis.
-- v0.2.3: stamp addonVersion + client build into DB and every snapshot.
-- v0.3.0: fights module, per-fight numbers from C_DamageMeter read after combat (/hello fights).
-- v0.4.0: lossless fight log (all meter types, all sources, all spells, death recaps), read the
--         moment combat ends, chain-pull safe, compressed per-day buckets for pipeline export.
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


local ADDON_VERSION_FALLBACK = "0.4.0"

local function getAddonVersion()
    local v
    if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
        v = safeCall(C_AddOns.GetAddOnMetadata, addonName, "Version")
    end
    if (not v or v == "") and type(GetAddOnMetadata) == "function" then
        v = safeCall(GetAddOnMetadata, addonName, "Version")
    end
    if type(v) == "string" and v ~= "" then
        return v
    end
    return ADDON_VERSION_FALLBACK
end

-- GetBuildInfo returns version, build, date, tocversion (names vary by client).
local function getClientInfo()
    local r = safeCallAll(GetBuildInfo)
    if not r or (r.n or 0) == 0 then
        return { version = nil, build = nil, date = nil, toc = nil }
    end
    return {
        version = r[1],
        build = r[2],
        date = r[3],
        toc = r[4],
    }
end

local function stampVersions(snap)
    if type(snap) ~= "table" then return snap end
    snap.addonVersion = getAddonVersion()
    snap.client = getClientInfo()
    return snap
end

local function ensureDB()
    HelloForeverDB = HelloForeverDB or {}
    HelloForeverDB.addonVersion = getAddonVersion()
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

-- Talents (v0.2.2).
-- WoW Forever (TOC 16001, build 1.60.1) has NO classic GetTalentInfo/GetNumTalentTabs.
-- Talents are a C_Traits tree in a config of type Enum.TraitConfigType.CamelotCombat (4),
-- one tree per class; the three classic "tabs" are trait GROUPS of that tree.
-- Blizzard's own Camelot talent frame (wow-ui-source `forever` branch,
-- Blizzard_PlayerSpells/Camelot/ClassTalents/Blizzard_ClassTalentsFrame.lua) gets the config via
-- C_SpecializationInfo.GetCombatConfigIDForSpecGroup(GetActiveSpecGroup()), tabs via
-- C_Traits.GetGroupDisplayInfoByTreeID(treeID), points per tab via C_Traits.GetGroupCurrencyInfo.
-- Snapshot-only (never on the tick). Returns a compact table:
--   { src, configID, configType, configName, treeID, spent, unspent,
--     spec = {index,id,name,role},
--     tabs = { {g=groupID, name, points, order} },
--     nodes = { {n=nodeID, r=rank, m=maxRanks, s=spellID, name, g=tabGroupID} } }  -- purchased only
local function spellNameOf(spellID)
    if not spellID then return nil end
    local CS = _G.C_Spell
    if type(CS) == "table" then
        local n = safeCall(CS.GetSpellName, spellID)
        if n then return n end
        local info = safeCall(CS.GetSpellInfo, spellID)
        if type(info) == "table" and info.name then return info.name end
    end
    return (safeCall(_G.GetSpellInfo, spellID)) -- legacy global, absent on Forever
end

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
    local specIndex = safeCall(getSpec)
    if type(specIndex) == "number" and specIndex > 0 then
        local id, name, _, _, role = safeCall(getSpecInfo, specIndex)
        out.spec = { index = specIndex, id = id, name = name, role = role }
    end

    -- Branch A: Forever / retail trait tree
    local TR = _G.C_Traits
    if type(TR) == "table" and type(TR.GetConfigInfo) == "function" then
        local configID, src
        if type(SI) == "table" and SI.GetCombatConfigIDForSpecGroup then
            local grp = safeCall(SI.GetActiveSpecGroup) or 1
            configID = safeCall(SI.GetCombatConfigIDForSpecGroup, grp)
            src = "SpecInfo.GetCombatConfigIDForSpecGroup"
        end
        if not configID and type(_G.C_ClassTalents) == "table" then
            configID = safeCall(_G.C_ClassTalents.GetActiveConfigID)
            src = "C_ClassTalents.GetActiveConfigID"
        end
        local cfg = configID and safeCall(TR.GetConfigInfo, configID)
        if type(cfg) == "table" and type(cfg.treeIDs) == "table" and cfg.treeIDs[1] then
            local treeID = cfg.treeIDs[1]
            out.src = src .. "+C_Traits"
            out.configID, out.configType, out.configName, out.treeID = configID, cfg.type, cfg.name, treeID
            lastApiUsed.talents = out.src
            lastApiUsed.talentConfigType = cfg.type

            -- Tabs = trait groups of the tree
            local groupSet, groupIDs = {}, {}
            local disp = safeCall(TR.GetGroupDisplayInfoByTreeID, treeID)
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
                local gc = safeCall(TR.GetGroupCurrencyInfo, configID, groupIDs)
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
            local tc = safeCall(TR.GetTreeCurrencyInfo, configID, treeID, false)
            if type(tc) == "table" and type(tc[1]) == "table" then
                out.spent = tc[1].spent
                out.unspent = tc[1].quantity
            end

            -- Purchased nodes
            local nodeIDs = safeCall(TR.GetTreeNodes, treeID)
            if type(nodeIDs) == "table" then
                lastApiUsed.talentNodesScanned = #nodeIDs
                for _, nodeID in ipairs(nodeIDs) do
                    local ni = safeCall(TR.GetNodeInfo, configID, nodeID)
                    local rank = ni and (ni.activeRank or ni.ranksPurchased or 0) or 0
                    if rank > 0 then
                        local entryID = (ni.activeEntry and ni.activeEntry.entryID)
                            or (type(ni.entryIDs) == "table" and ni.entryIDs[1])
                        local spellID, name
                        local ei = entryID and safeCall(TR.GetEntryInfo, configID, entryID)
                        local def = ei and ei.definitionID and safeCall(TR.GetDefinitionInfo, ei.definitionID)
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
        local nTabs = safeCall(_G.GetNumTalentTabs)
        if type(nTabs) == "number" and nTabs > 0 then
            out.src = "GetNumTalentTabs"
            lastApiUsed.talents = out.src
            lastApiUsed.talentTabs = nTabs
            for t = 1, nTabs do
                local _, tabName, _, _, pts = safeCall(_G.GetTalentTabInfo, t) -- 1.13+: id,name,desc,icon,points
                if type(tabName) ~= "string" then tabName, pts = nil, nil end
                local tabPoints = pts or 0
                out.tabs[t] = { g = t, name = tabName, points = tabPoints }
                for i = 1, (safeCall(_G.GetNumTalents, t) or 0) do
                    local tName, _, _, _, rank, maxRank = safeCall(_G.GetTalentInfo, t, i)
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
        local u = safeCall(_G.UnitCharacterPoints, "player")
        if type(u) ~= "number" then u = safeCall(_G.GetUnspentTalentPoints) end
        if type(u) == "number" then out.unspent = u end
    end
    lastApiUsed.talentUnspent = out.unspent

    local first = {}
    for i = 1, math.min(3, #out.nodes) do
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
    return stampVersions(snap)
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
        c.snapshot = stampVersions({
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
        })
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
    stampVersions(prev)
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
-- 3b. Fights v2 (v0.4.0): lossless per-session capture from C_DamageMeter
----------------------------------------------------------------------
-- Source: Gethe/wow-ui-source `forever`, Blizzard_APIDocumentationGenerated/.
-- * Every meter type (Enum.DamageMeterType 0..10, DamageMeterConstantsDocumentation.lua:95-113),
--   every source of every type (GetCombatSessionFromID, DamageMeterDocumentation.lua:21-37),
--   and every source's spell breakdown incl. per-target details
--   (GetCombatSessionSourceFromID :57-75, structs :171-244) are copied field by field.
-- * Death recaps via C_DeathRecap (DeathRecapDocumentation.lua:10-70), checked for secrets
--   like Details' GetRecapInfoSafe (classes/class_utility.lua:3788-3801).
-- * Reads start the moment combat ends: PLAYER_REGEN_ENABLED, and
--   ADDON_RESTRICTION_STATE_CHANGED(Combat -> Inactive), which Blizzard documents as fired
--   "after it is deactivated" (RestrictedActionsDocumentation.lua:96-107). If values are still
--   secret, a 0.25 s poll (Details uses 0.3 s: core/parser_nocleu1.lua:514-527) retries for 10 s;
--   unread sessions stay queued and are retried on every later trigger, never dropped.
-- * Session start/end are stamped from DAMAGE_METER_COMBAT_SESSION_UPDATED as Details does
--   (parser_nocleu1.lua:3266-3291, 274-286). The in-combat handler only writes a timestamp
--   into a table; no API calls in combat.
-- * A session that vanishes unread (meter reset, relog, list truncation) is logged as a gap
--   record so nothing disappears silently.
-- * Each record is SerializeJSON -> CompressString(Deflate) -> EncodeBase64
--   (EncodingUtilDocumentation.lua:11-27, 109-125, 158-172; same calls as Details
--   Libs/PlayerInfo/PlayerInfo.lua:615-622), verified by a decode round trip, else stored as
--   a plain table. The pipeline exports one file per fight; the in-game log is only trimmed
--   past a size budget, oldest days first, never days newer than FL_KEEP_DAYS.

local FL_VERSION = 4
local FL_BUDGET_BYTES = 3 * 1024 * 1024 -- per character, encoded bytes of the fight log
local FL_KEEP_DAYS = 7                   -- never trim a day newer than this (pipeline runs daily)
local FL_POLL_SEC = 0.25
local FL_POLL_MAX = 40                   -- 10 s of fallback polling while values are secret
local FL_CALLS_PER_STEP = 30             -- C_DamageMeter calls per frame step (hitch budget)
local FL_SUMMARY_KEEP = 50
-- Fields documented as SecretValue = true (always secret, DamageMeterDocumentation.lua:203, 242).
local ALWAYS_SECRET = { specIconID = true }

local function enumValue(enumName, field, documented)
    local E = _G.Enum
    local t = type(E) == "table" and E[enumName]
    local v = type(t) == "table" and t[field]
    if type(v) == "number" then return v end
    return documented
end

local DOC_DM_TYPES = {
    { 0, "DamageDone" }, { 1, "Dps" }, { 2, "HealingDone" }, { 3, "Hps" }, { 4, "Absorbs" },
    { 5, "Interrupts" }, { 6, "Dispels" }, { 7, "DamageTaken" }, { 8, "AvoidableDamageTaken" },
    { 9, "Deaths" }, { 10, "EnemyDamageTaken" },
}
-- All meter types: from Enum at runtime (so new types are picked up), else the documented list.
local function meterTypes()
    local E = _G.Enum
    local t = type(E) == "table" and E.DamageMeterType
    local out = {}
    if type(t) == "table" then
        for name, v in pairs(t) do
            if type(name) == "string" and type(v) == "number" then out[#out + 1] = { v, name } end
        end
    end
    if #out == 0 then
        for i, p in ipairs(DOC_DM_TYPES) do out[i] = { p[1], p[2] } end
    end
    table.sort(out, function(a, b) return a[1] < b[1] end)
    return out
end

local RESTRICT_COMBAT = enumValue("AddOnRestrictionType", "Combat", 0)

local function isSecret(v)
    local f = _G.issecretvalue
    if type(f) ~= "function" then return false end
    local ok, r = pcall(f, v)
    if not ok then return true end
    return r and true or false
end

local function isSecretTable(t)
    local f = _G.issecrettable
    if type(f) ~= "function" then return false end
    local ok, r = pcall(f, t)
    if not ok then return true end
    return r and true or false
end

local function num(v)
    if type(v) == "number" and not isSecret(v) then return v end
    return nil
end

local SECRET = {} -- sentinel: "a value we need is still secret"

-- Deep copy of an API result. Returns SECRET if anything except an ALWAYS_SECRET field is secret.
local function clean(v, depth, skipped, key)
    if isSecret(v) then
        if key and ALWAYS_SECRET[key] then
            skipped[key] = (skipped[key] or 0) + 1
            return nil
        end
        return SECRET
    end
    local tv = type(v)
    if tv == "table" then
        if isSecretTable(v) then return SECRET end
        if depth > 10 then return nil end
        local out = {}
        for k, x in pairs(v) do
            if isSecret(k) then return SECRET end
            local tk = type(k)
            if tk == "string" or tk == "number" then
                local cv = clean(x, depth + 1, skipped, tk == "string" and k or nil)
                if cv == SECRET then return SECRET end
                if cv ~= nil then out[k] = cv end
            end
        end
        return out
    elseif tv == "number" or tv == "string" or tv == "boolean" then
        return v
    end
    return nil
end

local flStatus = {
    state = "idle", lastReason = nil, lastAt = nil, steps = 0, waits = 0, polls = 0,
    stored = 0, gaps = 0, errors = 0, lastError = nil, encode = nil, lastMs = nil, maxMs = 0,
    pending = 0,
}

local function flDB()
    local c = ensureDB()
    local f = c.fightLog
    if type(f) ~= "table" then
        f = { v = FL_VERSION }
        c.fightLog = f
    end
    f.days = f.days or {}
    f.index = f.index or {}
    f.trimmed = f.trimmed or {}
    local tr = c.fightTrack
    if type(tr) ~= "table" then
        tr = {}
        c.fightTrack = tr
    end
    tr.sessions = tr.sessions or {}
    tr.done = tr.done or {}
    tr.maxDone = tr.maxDone or 0
    tr.resets = tr.resets or 0
    c.fightSummary = c.fightSummary or {}
    return c
end

-- Cached tracking table so the in-combat event handler doesn't rebuild charKey each event.
local trackRef

local function track()
    if not trackRef then trackRef = flDB().fightTrack end
    return trackRef
end

-- DAMAGE_METER_CURRENT_SESSION_UPDATED (Details treats it as "new session", parser_nocleu1.lua:3337-3369).
function ns.FightsNewCurrent()
    track().newPending = time()
end

-- Called from DAMAGE_METER_COMBAT_SESSION_UPDATED (also in combat): O(1), no API calls.
function ns.FightsSeen(sid)
    local tr = track()
    local s = tr.sessions[sid]
    -- Known id: same session still updating, unless a new session was announced and this id
    -- was already read (ids restarted, e.g. after a meter reset): then it's a new fight.
    if s and not (tr.newPending and tr.done[sid]) then return end
    local now = time()
    if s then tr.done[sid] = nil end
    tr.newPending = nil
    -- the previous open session ended when this one started (Details parser_nocleu1.lua:3281-3288)
    for osid, s in pairs(tr.sessions) do
        if osid < sid and not s.stop then s.stop = now end
    end
    tr.sessions[sid] = { start = now }
end

local function stampStop(now)
    for _, s in pairs(track().sessions) do
        if not s.stop then s.stop = now end
    end
end

local function fightsBlocked()
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return "combat"
    end
    local RA = _G.C_RestrictedActions
    if type(RA) == "table" and type(RA.GetAddOnRestrictionState) == "function" then
        local ok, state = pcall(RA.GetAddOnRestrictionState, RESTRICT_COMBAT)
        if not ok then return "restriction_err" end
        if isSecret(state) then return "restriction_secret" end
        if type(state) == "number" and state > 0 then return "restricted" end
    end
    return nil
end

-- Encoding: JSON -> Deflate -> Base64, verified by decoding again. Returns blob, bytes, how.
local function encodeRecord(rec)
    local EU = _G.C_EncodingUtil
    if type(EU) == "table" and type(EU.SerializeJSON) == "function"
        and type(EU.CompressString) == "function" and type(EU.EncodeBase64) == "function" then
        local ok, json = pcall(EU.SerializeJSON, rec)
        if ok and type(json) == "string" and json ~= "" then
            local method = enumValue("CompressionMethod", "Deflate", 0)
            local ok2, z = pcall(EU.CompressString, json, method)
            local ok3, b64 = false, nil
            if ok2 and type(z) == "string" then ok3, b64 = pcall(EU.EncodeBase64, z) end
            if ok3 and type(b64) == "string" and b64 ~= "" then
                local verified = false
                if type(EU.DecodeBase64) == "function" and type(EU.DecompressString) == "function" then
                    local okd, raw = pcall(EU.DecodeBase64, b64)
                    local oku, back = false, nil
                    if okd and type(raw) == "string" then oku, back = pcall(EU.DecompressString, raw, method) end
                    verified = oku and back == json
                end
                if verified then
                    local blob = "d1:" .. b64
                    return blob, #blob, "deflate"
                end
            end
            -- compression unavailable or round trip failed: keep the JSON text itself
            local blob = "j1:" .. json
            return blob, #blob, "json"
        end
    end
    -- last resort: the plain Lua table (always lossless, just bigger)
    return rec, 4000, "table"
end

local function dayOf(t) return date("%Y-%m-%d", t or time()) end

local function trimFightLog(c)
    local f = c.fightLog
    local total, days = 0, {}
    for d, b in pairs(f.days) do
        total = total + (b.bytes or 0)
        days[#days + 1] = d
    end
    if total > FL_BUDGET_BYTES then
        table.sort(days)
        local cutoff = dayOf(time() - FL_KEEP_DAYS * 86400)
        for _, d in ipairs(days) do
            if total <= FL_BUDGET_BYTES or d >= cutoff then break end
            local b = f.days[d]
            f.trimmed[d] = { n = #b.keys, bytes = b.bytes, at = time(), keys = table.concat(b.keys, ",") }
            for _, k in ipairs(b.keys) do f.index[k] = nil end
            f.days[d] = nil
            total = total - (b.bytes or 0)
        end
    end
    f.bytes = total
end

-- Put a record into its day bucket; replaces in place if the key already exists (newer rev).
local function storeRecord(c, rec)
    local f = c.fightLog
    local blob, size, how = encodeRecord(rec)
    flStatus.encode = how
    local day = f.index[rec.key]
    local b, idx
    if day and f.days[day] then
        b = f.days[day]
        for i, k in ipairs(b.keys) do if k == rec.key then idx = i break end end
    end
    if not idx then
        day = dayOf(rec.start)
        b = f.days[day]
        if not b then
            b = { keys = {}, data = {}, sizes = {}, bytes = 0 }
            f.days[day] = b
        end
        idx = #b.keys + 1
        b.keys[idx] = rec.key
    end
    b.bytes = (b.bytes or 0) - (b.sizes[idx] or 0) + size
    b.data[idx] = blob
    b.sizes[idx] = size
    f.index[rec.key] = day
    trimFightLog(c)
end

local function summarize(c, rec)
    local s = { key = rec.key, t = rec.start, dur = rec.dur, name = rec.name, rev = rec.rev, gap = rec.gap }
    local function mine(typeName)
        local ty = rec.types and rec.types[typeName]
        if type(ty) ~= "table" or type(ty.combatSources) ~= "table" then return nil, nil end
        for i, src in ipairs(ty.combatSources) do
            if src.isLocalPlayer then return src, ty.bySource and ty.bySource[i] end
        end
        return nil, nil
    end
    local d, dsp = mine("DamageDone")
    s.dmg = d and d.totalAmount or 0
    s.dps = d and d.amountPerSecond or 0
    local pet = 0
    if type(dsp) == "table" and type(dsp.combatSpells) == "table" then
        for _, sp in ipairs(dsp.combatSpells) do
            if type(sp.creatureName) == "string" and sp.creatureName ~= "" then pet = pet + (sp.totalAmount or 0) end
        end
    end
    s.pet = pet
    local h = mine("HealingDone")
    s.heal = h and h.totalAmount or 0
    local tk = mine("DamageTaken")
    s.taken = tk and tk.totalAmount or 0
    local dd = mine("Deaths")
    s.died = (dd and type(dd.deathRecapID) == "number" and dd.deathRecapID ~= 0) or false
    local sum = c.fightSummary
    for i = #sum, math.max(1, #sum - 10), -1 do
        if sum[i].key == s.key then sum[i] = s return end
    end
    sum[#sum + 1] = s
    while #sum > FL_SUMMARY_KEEP do table.remove(sum, 1) end
end

local function storeGap(c, sid, s, why)
    local key = tostring(s.start or time()) .. "-" .. tostring(sid)
    if c.fightLog.index[key] then return end
    local rec = { v = FL_VERSION, key = key, sid = sid, start = s.start, stop = s.stop, gap = why,
        char = charKey(), noted = time() }
    storeRecord(c, rec)
    summarize(c, rec)
    flStatus.gaps = flStatus.gaps + 1
end

-- In-memory job state (a /reload mid-job just restarts the session read).
local job = nil        -- { todo = {avail...}, rec = staging, ti = next type index, types = list }
local stepScheduled = false
local pollTicker = nil
local pollCount = 0
local needRead = false

local function stopPoll()
    if pollTicker and type(pollTicker.Cancel) == "function" then pollTicker:Cancel() end
    pollTicker = nil
end

local runStep -- forward

local function scheduleStep()
    if stepScheduled then return end
    if not (C_Timer and type(C_Timer.After) == "function") then return end
    stepScheduled = true
    C_Timer.After(0, function()
        stepScheduled = false
        runStep("next_frame")
    end)
end

local function startPoll()
    if pollTicker then return end
    if not (C_Timer and type(C_Timer.NewTicker) == "function") then return end -- no OnUpdate fallback
    pollCount = 0
    pollTicker = C_Timer.NewTicker(FL_POLL_SEC, function()
        pollCount = pollCount + 1
        flStatus.polls = flStatus.polls + 1
        if pollCount >= FL_POLL_MAX then stopPoll() end
        runStep("poll")
    end, FL_POLL_MAX)
end

-- Build the work list. Returns todo list or nil, reason.
local function plan(c, DM)
    local ok, avail = pcall(DM.GetAvailableCombatSessions)
    if not ok or type(avail) ~= "table" then return nil, "sessions_err" end
    if isSecretTable(avail) then return nil, "secret" end
    local tr = c.fightTrack
    local list, present, maxId = {}, {}, 0
    for _, a in ipairs(avail) do
        if type(a) == "table" and num(a.sessionID) then
            if isSecret(a.name) or isSecret(a.durationSeconds) then return nil, "secret" end
            list[#list + 1] = a
            present[a.sessionID] = true
            if a.sessionID > maxId then maxId = a.sessionID end
        end
    end
    flStatus.sessions, flStatus.maxSid = #list, maxId
    -- Ids went backwards: the client restarted numbering (relog / reset). Forget "done".
    if maxId < tr.maxDone then
        for sid in pairs(tr.done) do tr.sessions[sid] = nil end
        tr.done = {}
        tr.maxDone = 0
        tr.resets = tr.resets + 1
    end
    -- Tracked sessions that vanished before we read them: record a gap, then forget them.
    for sid, s in pairs(tr.sessions) do
        if not present[sid] then
            if not tr.done[sid] then storeGap(c, sid, s, "vanished") end
            tr.sessions[sid] = nil
        end
    end
    table.sort(list, function(a, b) return a.sessionID < b.sessionID end)
    local todo = {}
    for _, a in ipairs(list) do
        local d = tr.done[a.sessionID]
        local dur = num(a.durationSeconds) or 0
        if d and a.name ~= d.name then
            -- same id, different fight: ids restarted without a reset we saw. Read as new.
            tr.done[a.sessionID] = nil
            tr.sessions[a.sessionID] = nil
            d = nil
        end
        if not d then
            todo[#todo + 1] = a
        elseif dur > (d.dur or 0) + 0.5 then
            a._rev = (d.rev or 1) + 1 -- session grew (chained pull merged into it): re-read
            a._key = d.key
            todo[#todo + 1] = a
        end
    end
    return todo
end

local function newRecord(a)
    local tr = track()
    local sid = a.sessionID
    local s = tr.sessions[sid]
    local dur = num(a.durationSeconds)
    local now = time()
    local start, approx = s and s.start, nil
    if not start then
        start = math.floor(now - (dur or 0) + 0.5)
        approx = true
        tr.sessions[sid] = { start = start, stop = now, approx = true }
        s = tr.sessions[sid]
    end
    local CM = _G.C_Map
    local key = a._key
    if not key then
        key = tostring(start) .. "-" .. tostring(sid)
        local idx = flDB().fightLog.index
        local n = 1
        while idx[key] do -- never overwrite a different fight that happens to share the key
            n = n + 1
            key = tostring(start) .. "-" .. tostring(sid) .. "-" .. n
        end
    end
    return {
        v = FL_VERSION,
        key = key,
        rev = a._rev or 1,
        sid = sid,
        name = a.name,
        start = start,
        startApprox = approx,
        stop = s.stop,
        dur = dur,
        char = charKey(),
        lvl = safeCall(UnitLevel, "player"),
        zone = safeCall(GetRealZoneText) or safeCall(GetZoneText),
        subzone = safeCall(GetSubZoneText),
        mapID = type(CM) == "table" and safeCall(CM.GetBestMapForUnit, "player") or nil,
        addonVersion = getAddonVersion(),
        types = {},
        recaps = {},
        skipped = {},
        read = { at = now, reason = flStatus.lastReason },
    }
end

-- Read one meter type's session table (1 call). Returns cleaned table, raw sources | SECRET
local function readTypeSession(DM, sid, typeValue, skipped)
    local ok, sess = pcall(DM.GetCombatSessionFromID, sid, typeValue)
    if not ok then return { err = tostring(sess) }, nil end
    local cs = clean(sess, 0, skipped)
    if cs == SECRET then return SECRET end
    if type(cs) ~= "table" then return { none = true }, nil end
    cs.bySource = {}
    local raw = type(sess) == "table" and sess.combatSources or nil
    if type(raw) ~= "table" or type(DM.GetCombatSessionSourceFromID) ~= "function" then raw = nil end
    return cs, raw
end

-- One source's spell breakdown (1 call). Returns cleaned table | SECRET
local function readTypeSource(DM, sid, typeValue, src, skipped)
    local ok, ss = pcall(DM.GetCombatSessionSourceFromID, sid, typeValue, src.sourceGUID, src.sourceCreatureID)
    if not ok then return { err = tostring(ss) } end
    local c2 = clean(ss, 0, skipped)
    if c2 == SECRET then return SECRET end
    return c2 or false
end

-- Death recaps for every source with a non-zero deathRecapID (DamageMeterEntry.lua:572-611).
local function readRecaps(rec)
    local DR = _G.C_DeathRecap
    if type(DR) ~= "table" or type(DR.GetRecapEvents) ~= "function" then return true end
    for _, ty in pairs(rec.types) do
        if type(ty) == "table" and type(ty.combatSources) == "table" then
            for _, src in ipairs(ty.combatSources) do
                local rid = src.deathRecapID
                if type(rid) == "number" and rid ~= 0 and rec.recaps[tostring(rid)] == nil then
                    local r = { who = src.name, guid = src.sourceGUID }
                    local okh, has = pcall(DR.HasRecapEvents, rid)
                    r.has = okh and has or false
                    if r.has then
                        local oke, ev = pcall(DR.GetRecapEvents, rid)
                        local ce = oke and clean(ev, 0, rec.skipped) or nil
                        if ce == SECRET then return false end
                        r.events = ce
                        local okm, mh = pcall(DR.GetRecapMaxHealth, rid)
                        if okm then
                            if isSecret(mh) then return false end
                            r.maxHealth = mh
                        end
                        local okl, link = pcall(DR.GetRecapLink, rid)
                        if okl and not isSecret(link) then r.link = link end
                    end
                    rec.recaps[tostring(rid)] = r
                end
            end
        end
    end
    return true
end

local function finishRecord(c, rec)
    local tr = c.fightTrack
    if next(rec.skipped) == nil then rec.skipped = nil end
    storeRecord(c, rec)
    summarize(c, rec)
    tr.done[rec.sid] = { key = rec.key, dur = rec.dur or 0, name = rec.name, rev = rec.rev }
    if rec.sid > tr.maxDone then tr.maxDone = rec.sid end
    flStatus.stored = flStatus.stored + 1
end

runStep = function(reason)
    local DM = _G.C_DamageMeter
    if type(DM) ~= "table" or type(DM.GetAvailableCombatSessions) ~= "function"
        or type(DM.GetCombatSessionFromID) ~= "function" then
        flStatus.state = "no_api"
        stopPoll()
        return
    end
    flStatus.lastReason = reason or flStatus.lastReason
    local why = fightsBlocked()
    if why == "combat" then
        flStatus.state = "wait:combat" -- nothing at all in combat; REGEN_ENABLED re-kicks
        stopPoll()
        return
    elseif why then
        flStatus.state = "wait:" .. why
        flStatus.waits = flStatus.waits + 1
        startPoll()
        return
    end
    local t0 = type(debugprofilestop) == "function" and debugprofilestop() or nil
    local c = flDB()
    if not job then
        local todo, r = plan(c, DM)
        if not todo then
            flStatus.state = "wait:" .. tostring(r)
            flStatus.waits = flStatus.waits + 1
            if r == "secret" then startPoll() end
            return
        end
        if #todo == 0 then
            flStatus.state = "idle"
            flStatus.pending = 0
            needRead = false
            stopPoll()
            return
        end
        job = { todo = todo, types = meterTypes() }
    end
    flStatus.pending = #job.todo
    flStatus.steps = flStatus.steps + 1
    local calls = 0
    while job and calls < FL_CALLS_PER_STEP do
        local a = job.todo[1]
        if not job.rec then
            job.rec = newRecord(a)
            job.ti = 1
        end
        local rec = job.rec
        if job.ti <= #job.types then
            -- Cursor: one session call per type, then one call per source; a big pull is
            -- spread over several frames at FL_CALLS_PER_STEP calls each.
            local tv = job.types[job.ti]
            local data
            if not job.cur then
                calls = calls + 1
                local raw
                data, raw = readTypeSession(DM, a.sessionID, tv[1], rec.skipped)
                if data ~= SECRET then job.cur, job.raw, job.si = data, raw, 1 end
            elseif job.raw and job.si <= #job.raw then
                calls = calls + 1
                data = readTypeSource(DM, a.sessionID, tv[1], job.raw[job.si], rec.skipped)
                if data ~= SECRET then
                    job.cur.bySource[job.si] = data
                    job.si = job.si + 1
                end
            else
                rec.types[tv[2]] = job.cur
                job.cur, job.raw, job.si = nil, nil, nil
                job.ti = job.ti + 1
            end
            if data == SECRET then
                -- restart this type from its session call next time (values may have changed)
                job.cur, job.raw, job.si = nil, nil, nil
                flStatus.state = "wait:secret"
                flStatus.waits = flStatus.waits + 1
                startPoll()
                return
            end
        else
            if not readRecaps(rec) then
                flStatus.state = "wait:secret_recap"
                flStatus.waits = flStatus.waits + 1
                startPoll()
                return
            end
            rec.read.steps = flStatus.steps
            finishRecord(c, rec)
            table.remove(job.todo, 1)
            job.rec = nil
            if #job.todo == 0 then job = nil end
        end
    end
    if t0 then
        local ms = debugprofilestop() - t0
        flStatus.lastMs = math.floor(ms * 100 + 0.5) / 100
        if ms > flStatus.maxMs then flStatus.maxMs = flStatus.lastMs end
    end
    flStatus.lastAt = time()
    if job then
        flStatus.state = "reading"
        scheduleStep()
    else
        -- re-plan once more: a new session may have appeared meanwhile
        flStatus.state = "idle"
        flStatus.pending = 0
        scheduleStep()
    end
end

-- All steps run under pcall. A session that keeps throwing is stored with its error after
-- 3 tries (with whatever was read), so one bad session can't block the queue.
local rawStep = runStep
runStep = function(reason)
    local ok, err = pcall(rawStep, reason)
    if ok then return end
    flStatus.errors = flStatus.errors + 1
    flStatus.lastError = tostring(err)
    flStatus.state = "error"
    if job and job.rec then
        job.errs = (job.errs or 0) + 1
        if job.errs >= 3 then
            local rec = job.rec
            rec.error = tostring(err)
            pcall(finishRecord, flDB(), rec)
            table.remove(job.todo, 1)
            job.rec, job.errs = nil, 0
            if #job.todo == 0 then job = nil end
        end
    else
        job = nil
    end
end

-- Entry point for all triggers. Runs the first step immediately (same frame).
function ns.FightsKick(reason)
    needRead = true
    runStep(reason)
end

function ns.FightsCombatStart()
    stopPoll()
    -- job/staging kept in memory; resumes after combat (sessions persist in the client list)
end

function ns.FightsCombatEnd()
    stampStop(time())
    ns.FightsKick("regen")
end

function ns.FightsRestriction(rtype, state)
    if rtype ~= RESTRICT_COMBAT then return end
    if type(state) == "number" and state == 0 then
        ns.FightsKick("restriction_off")
    else
        stopPoll()
    end
end

function ns.FightsMeterUpdated(rtype, sid)
    if type(sid) == "number" and sid > 0 then ns.FightsSeen(sid) end
    if needRead and not stepScheduled and not (type(InCombatLockdown) == "function" and InCombatLockdown()) then
        scheduleStep()
    end
end

function ns.FightsMeterReset()
    -- Blizzard (or Details, core/parser_nocleu1.lua:2422, 2668) wiped the sessions.
    local c = flDB()
    local tr = c.fightTrack
    for sid, s in pairs(tr.sessions) do
        if not tr.done[sid] then storeGap(c, sid, s, "reset") end
    end
    tr.sessions = {}
    tr.done = {}
    tr.maxDone = 0
    tr.resets = tr.resets + 1
    job = nil
end

local function fmtNum(n)
    n = tonumber(n) or 0
    if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
    if n >= 10000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n + 0.5))
end

local function fightLogStats(c)
    local f = c.fightLog
    local n, days, oldest = 0, 0, nil
    for d, b in pairs(f.days) do
        days = days + 1
        n = n + #b.keys
        if not oldest or d < oldest then oldest = d end
    end
    local trimmedDays = 0
    for _ in pairs(f.trimmed) do trimmedDays = trimmedDays + 1 end
    return n, days, oldest, f.bytes or 0, trimmedDays
end

function ns.PrintFights(n)
    local c = flDB()
    local s = c.fightSummary
    local total, days = fightLogStats(c)
    print(("|cff33ff99HelloForever|r fights: %d stored in %d day(s); %s. Last %d:")
        :format(total, days, flStatus.state, math.min(n, #s)))
    if #s == 0 then
        print("  (none yet; read starts the moment combat ends)")
        return
    end
    for i = #s, math.max(1, #s - n + 1), -1 do
        local r = s[i]
        if r.gap then
            print(("  %s |cffff8800GAP|r session %s (%s)"):format(date("%H:%M", r.t or 0), tostring(r.key), tostring(r.gap)))
        else
            print(("  %s %s %ss dmg %s (%s dps)%s heal %s taken %s%s%s"):format(
                date("%H:%M", r.t or 0), tostring(r.name), tostring(r.dur or 0),
                fmtNum(r.dmg), tostring(math.floor((r.dps or 0) * 10 + 0.5) / 10),
                (r.pet or 0) > 0 and (" pet " .. fmtNum(r.pet)) or "",
                fmtNum(r.heal), fmtNum(r.taken),
                r.died and " |cffff4040DIED|r" or "",
                (r.rev or 1) > 1 and (" rev" .. r.rev) or ""))
        end
    end
end

function ns.PrintExport()
    local c = flDB()
    local n, days, oldest, bytes, trimmedDays = fightLogStats(c)
    print(("|cff33ff99HelloForever|r fight log: %d fights, %d day(s) since %s, %.0f KB of %.0f KB budget, %d day(s) trimmed.")
        :format(n, days, tostring(oldest or "-"), bytes / 1024, FL_BUDGET_BYTES / 1024, trimmedDays))
    print("  Saved to disk only on /reload or logout. Export with /hello export after combat,")
    print("  or let an external offline pipeline pull SavedVariables. Only days older than "
        .. FL_KEEP_DAYS .. " days are ever trimmed, and only past the budget.")
end

function ns.FightsDebugLine()
    local DM = _G.C_DamageMeter
    local api = type(DM) == "table" and type(DM.GetAvailableCombatSessions) == "function"
        and type(DM.GetCombatSessionFromID) == "function"
        and type(DM.GetCombatSessionSourceFromID) == "function"
    local avail, why = "?", ""
    if type(DM) == "table" and type(DM.IsDamageMeterAvailable) == "function" then
        local ok, a, reason = pcall(DM.IsDamageMeterAvailable)
        if ok then avail = tostring(a); why = (reason and reason ~= "") and (" (" .. tostring(reason) .. ")") or "" end
    end
    local c = flDB()
    local tr = c.fightTrack
    local n, days, _, bytes = fightLogStats(c)
    local nt = 0
    for _ in pairs(tr.sessions) do nt = nt + 1 end
    return ("  fights: api=%s meter=%s%s enc=%s deathRecap=%s state=%s reason=%s pending=%s sessions=%s maxSid=%s tracked=%d maxDone=%s resets=%s stored=%d/%dd %.0fKB gaps=%d waits=%d polls=%d steps=%d ms=%s/%s err=%d%s")
        :format(tostring(api), avail, why, tostring(flStatus.encode or (type(_G.C_EncodingUtil) == "table" and "ready" or "none")),
            tostring(type(_G.C_DeathRecap) == "table"),
            flStatus.state, tostring(flStatus.lastReason), tostring(flStatus.pending),
            tostring(flStatus.sessions), tostring(flStatus.maxSid), nt, tostring(tr.maxDone), tostring(tr.resets),
            n, days, bytes / 1024, flStatus.gaps, flStatus.waits, flStatus.polls, flStatus.steps,
            tostring(flStatus.lastMs), tostring(flStatus.maxMs), flStatus.errors,
            flStatus.lastError and (" lastErr=" .. tostring(flStatus.lastError)) or "")
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
        .. " cfgType=" .. tostring(a.talentConfigType)
        .. " tabs=" .. tostring(a.talentTabs)
        .. " scanned=" .. tostring(a.talentNodesScanned)
        .. " learned=" .. tostring(a.talentLeaves)
        .. " unspent=" .. tostring(a.talentUnspent))
    print("  talentFirst3=" .. tostring(a.talentFirst))
    local st = ensureDB().snapshot
    local tt = st and st.talents
    if type(tt) == "table" and type(tt.tabs) == "table" then
        local parts = {}
        for _, tb in ipairs(tt.tabs) do parts[#parts + 1] = tostring(tb.name) .. "=" .. tostring(tb.points) end
        print("  talentTabs: " .. table.concat(parts, "  ")
            .. (tt.spec and ("  spec=" .. tostring(tt.spec.name) .. "#" .. tostring(tt.spec.id)) or ""))
    end
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
                type(s.talents) == "table" and type(s.talents.nodes) == "table" and #s.talents.nodes or 0,
                type(s.skills) == "table" and #s.skills or 0,
                type(s.quests) == "table" and #s.quests or 0
            ))
    else
        print("  (no snapshot yet)")
    end
    print(ns.FightsDebugLine())
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
    if cmd == "fights" then
        if (rest or ""):lower() == "read" then
            ns.FightsKick("slash")
        end
        ns.PrintFights(5)
        return
    end
    if cmd == "export" then
        ns.PrintExport()
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
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
-- Documented on forever (DamageMeterDocumentation.lua:130-155, RestrictedActionsDocumentation.lua:96-107);
-- pcall so a client without them still loads.
for _, ev in ipairs({ "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED",
    "DAMAGE_METER_RESET", "ADDON_RESTRICTION_STATE_CHANGED" }) do
    pcall(frame.RegisterEvent, frame, ev)
end

frame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == addonName then
        HelloForeverDB = HelloForeverDB or {}
        HelloForeverDB.addonVersion = getAddonVersion()
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
            -- Fights catch-up (e.g. after /reload); does nothing if in combat.
            ns.FightsKick("entering_world")
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

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entering combat: stop polling; do nothing in combat.
        ns.FightsCombatStart()

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat over: read now (same frame) if readable, else wait for the restriction to lift.
        ns.FightsCombatEnd()

    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        ns.FightsRestriction(arg1, arg2)

    elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
        -- (type, sessionID); fires in combat too: only a timestamp is written then.
        ns.FightsMeterUpdated(arg1, arg2)

    elseif event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
        ns.FightsNewCurrent()

    elseif event == "DAMAGE_METER_RESET" then
        ns.FightsMeterReset()

    elseif event == "TIME_PLAYED_MSG" then
        pendingPlayed.total = arg1
        pendingPlayed.level = arg2
        local c = ensureDB()
        if c.snapshot then
            c.snapshot.timePlayed = { total = arg1, level = arg2 }
        end
    end
end)
