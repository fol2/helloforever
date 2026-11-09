-- HelloForever v0.3.0: XP/hour UI + character snapshot / timeline for offline analysis.
-- v0.2.3: stamp addonVersion + client build into DB and every snapshot.
-- v0.3.0: fights module, per-fight numbers from C_DamageMeter read after combat (/hello fights).
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


local ADDON_VERSION_FALLBACK = "0.3.0"

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
-- 3b. Fights (v0.3.0): per-fight numbers from Blizzard's C_DamageMeter
----------------------------------------------------------------------
-- Why: on Forever, Details only skins C_DamageMeter and saves empty segments
-- (Details core/parser_nocleu1.lua:1996-1997 `do return end` in addSegment).
-- Blizzard keeps the numbers in the client only, so we copy them ourselves.
--
-- API (Gethe/wow-ui-source `forever`, Blizzard_APIDocumentationGenerated/):
--   C_DamageMeter.GetAvailableCombatSessions() -> {sessionID, name, durationSeconds?}[]
--   C_DamageMeter.GetCombatSessionFromID(sessionID, type) -> {combatSources[], maxAmount, totalAmount, durationSeconds?}
--   C_DamageMeter.GetCombatSessionSourceFromID(sessionID, type, sourceGUID?, sourceCreatureID?) -> {combatSpells[], maxAmount, totalAmount}
--   (DamageMeterDocumentation.lua:11-75, 160-244; SecretWhenInCombat = true)
--   Enum.DamageMeterType DamageDone 0, HealingDone 2, DamageTaken 7, Deaths 9
--   (DamageMeterConstantsDocumentation.lua:102-111)
--   C_RestrictedActions.GetAddOnRestrictionState(Enum.AddOnRestrictionType.Combat) -> 0 Inactive / 1 Activating / 2 Active
--   (RestrictedActionsDocumentation.lua:29-43, RestrictedActionsConstantsDocumentation.lua:13-26)
--   issecretvalue / issecrettable (FrameScriptDocumentation.lua:270-303)
-- Wait loop mirrors Details' startWaitSecretDropTimer (parser_nocleu1.lua:791-815):
-- 1 s C_Timer ticker, skip while InCombatLockdown() or restriction state > 0,
-- read only once nothing we touch is secret. Nothing runs while in combat:
-- the ticker is cancelled on PLAYER_REGEN_DISABLED and has no OnUpdate fallback.

local FIGHTS_CAP = 200          -- detailed fights kept per character
local FIGHT_SPELLS_CAP = 15     -- spell rows kept per fight (largest first)
local FIGHT_WAIT_TRIES = 15     -- 1 s ticks after combat before giving up
local FIGHT_LOOKBACK = 20       -- recent fights scanned for duplicates

-- Documented enum values, used only if Enum.* is missing at runtime.
local function enumValue(enumName, field, documented)
    local E = _G.Enum
    local t = type(E) == "table" and E[enumName]
    local v = type(t) == "table" and t[field]
    if type(v) == "number" then return v end
    return documented
end

local DMT_DAMAGE = enumValue("DamageMeterType", "DamageDone", 0)
local DMT_HEALING = enumValue("DamageMeterType", "HealingDone", 2)
local DMT_TAKEN = enumValue("DamageMeterType", "DamageTaken", 7)
local DMT_DEATHS = enumValue("DamageMeterType", "Deaths", 9)
local RESTRICT_COMBAT = enumValue("AddOnRestrictionType", "Combat", 0)

-- True if v is a secret value. If the check itself errors, treat as secret.
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

local function round1(x)
    if type(x) ~= "number" then return nil end
    return math.floor(x * 10 + 0.5) / 10
end

local fightStatus = {
    lastResult = "never", lastReason = nil, lastAt = nil,
    tries = 0, added = 0, secretWaits = 0, errors = 0, lastError = nil,
}

local function fightsDB()
    local c = ensureDB()
    c.fights = c.fights or {}
    c.fightDays = c.fightDays or {}
    c.fightState = c.fightState or { lastSid = 0, resets = 0 }
    return c
end

-- Reasons we must not read now (nil = OK to read).
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

-- Read one meter type for a session; return the local player's source.
-- Returns: src (or false if the player has no row), session  | nil, "secret"/"err"/"nosession"
local function readLocalSource(DM, sid, dmType, playerGUID)
    local ok, sess = pcall(DM.GetCombatSessionFromID, sid, dmType)
    if not ok then return nil, "err" end
    if type(sess) ~= "table" then return nil, "nosession" end
    if isSecretTable(sess) then return nil, "secret" end
    local list = sess.combatSources
    if type(list) ~= "table" then return false, sess end
    if isSecretTable(list) then return nil, "secret" end
    for i = 1, #list do
        local s = list[i]
        if type(s) == "table" then
            local mine = (s.isLocalPlayer == true) -- NeverSecret (DamageMeterDocumentation.lua:206)
            if not mine and playerGUID and not isSecret(s.sourceGUID) then
                mine = (s.sourceGUID == playerGUID)
            end
            if mine then
                if isSecret(s.totalAmount) or isSecret(s.name) or isSecret(s.sourceGUID) then
                    return nil, "secret"
                end
                return s, sess
            end
        end
    end
    return false, sess
end

-- Build one fight record from a session. Returns rec | nil, reason
local function readFight(DM, avail, endAt, approx, playerGUID)
    local sid = avail.sessionID
    local dmgSrc, dmgSess = readLocalSource(DM, sid, DMT_DAMAGE, playerGUID)
    if dmgSrc == nil then return nil, dmgSess end
    local healSrc, r2 = readLocalSource(DM, sid, DMT_HEALING, playerGUID)
    if healSrc == nil then return nil, r2 end
    local takenSrc, r3 = readLocalSource(DM, sid, DMT_TAKEN, playerGUID)
    if takenSrc == nil then return nil, r3 end
    local deathSess
    local deathSrc, r4 = readLocalSource(DM, sid, DMT_DEATHS, playerGUID)
    if deathSrc == nil then return nil, r4 end
    deathSess = r4

    local dur = num(avail.durationSeconds) or (type(dmgSess) == "table" and num(dmgSess.durationSeconds)) or 0
    local name = avail.name
    if isSecret(name) or type(name) ~= "string" or name == "" then name = "Combat #" .. tostring(sid) end
    local t = math.floor((endAt or time()) - dur + 0.5)

    local rec = {
        sid = sid,
        t = t,
        dur = round1(dur),
        name = name,
        zone = safeCall(GetRealZoneText) or safeCall(GetZoneText),
        subzone = safeCall(GetSubZoneText),
        lvl = safeCall(UnitLevel, "player"),
        dmg = (dmgSrc and num(dmgSrc.totalAmount)) or 0,
        heal = (healSrc and num(healSrc.totalAmount)) or 0,
        taken = (takenSrc and num(takenSrc.totalAmount)) or 0,
        petDmg = 0,
        spells = {},
    }
    if approx then rec.approx = true end
    local CM = _G.C_Map
    if type(CM) == "table" then rec.mapID = safeCall(CM.GetBestMapForUnit, "player") end
    local aps = dmgSrc and num(dmgSrc.amountPerSecond)
    if aps then
        rec.dps = round1(aps)
    elseif dur > 0 then
        rec.dps = round1(rec.dmg / dur)
    else
        rec.dps = 0
    end

    -- Deaths: entries with a non-zero deathRecapID are deaths (DamageMeterEntry.lua:572-611)
    local deaths = 0
    if type(deathSess) == "table" and type(deathSess.combatSources) == "table" then
        for _, s in ipairs(deathSess.combatSources) do
            if type(s) == "table" and s.isLocalPlayer == true then
                local rid = s.deathRecapID -- NeverSecret
                if type(rid) == "number" and rid ~= 0 then deaths = deaths + 1 end
            end
        end
    end
    rec.died = deaths > 0
    if deaths > 1 then rec.deaths = deaths end

    -- Per-spell breakdown for the player; pet spells carry creatureName
    -- (DamageMeterEntry.lua:721-723 formats them "Spell (PetName)").
    if dmgSrc and type(DM.GetCombatSessionSourceFromID) == "function" then
        local guid = (not isSecret(dmgSrc.sourceGUID) and dmgSrc.sourceGUID) or playerGUID
        local cid = num(dmgSrc.sourceCreatureID)
        local ok, ss = pcall(DM.GetCombatSessionSourceFromID, sid, DMT_DAMAGE, guid, cid)
        if ok and type(ss) == "table" and not isSecretTable(ss) and type(ss.combatSpells) == "table" then
            local rows = {}
            for _, sp in ipairs(ss.combatSpells) do
                if type(sp) == "table" then
                    if isSecret(sp.spellID) or isSecret(sp.totalAmount) or isSecret(sp.creatureName) then
                        return nil, "secret"
                    end
                    local amt = num(sp.totalAmount) or 0
                    local row = { id = sp.spellID, amt = amt }
                    local cn = sp.creatureName
                    if type(cn) == "string" and cn ~= "" then
                        row.pet = cn
                        rec.petDmg = rec.petDmg + amt
                    end
                    rows[#rows + 1] = row
                end
            end
            table.sort(rows, function(a, b) return (a.amt or 0) > (b.amt or 0) end)
            for i = 1, math.min(#rows, FIGHT_SPELLS_CAP) do
                local row = rows[i]
                row.name = spellNameOf(row.id)
                rec.spells[i] = row
            end
            if #rows > FIGHT_SPELLS_CAP then rec.spellsCut = #rows - FIGHT_SPELLS_CAP end
        elseif ok and type(ss) == "table" then
            return nil, "secret"
        elseif not ok then
            rec.spellsErr = true
        end
    end
    return rec
end

local function isDuplicate(fights, rec)
    for i = #fights, math.max(1, #fights - FIGHT_LOOKBACK + 1), -1 do
        local f = fights[i]
        if f and f.name == rec.name and type(f.t) == "number"
            and math.abs(f.t - rec.t) <= 3 and (f.dur or 0) == (rec.dur or 0) then
            return true
        end
    end
    return false
end

local function rollFights(c)
    local f = c.fights
    while #f > FIGHTS_CAP do
        local o = table.remove(f, 1)
        local day = date("%Y-%m-%d", o.t or 0)
        local d = c.fightDays[day]
        if not d then
            d = { n = 0, dmg = 0, time = 0, deaths = 0, heal = 0, taken = 0, petDmg = 0 }
            c.fightDays[day] = d
        end
        d.n = d.n + 1
        d.dmg = d.dmg + (o.dmg or 0)
        d.time = round1(d.time + (o.dur or 0))
        d.deaths = d.deaths + (o.died and (o.deaths or 1) or 0)
        d.heal = d.heal + (o.heal or 0)
        d.taken = d.taken + (o.taken or 0)
        d.petDmg = d.petDmg + (o.petDmg or 0)
    end
end

-- One read attempt. Returns "done" | "wait" | "fail".
function ns.FightsTryRead(endAt, approxAll)
    local DM = _G.C_DamageMeter
    if type(DM) ~= "table" or type(DM.GetAvailableCombatSessions) ~= "function"
        or type(DM.GetCombatSessionFromID) ~= "function" then
        fightStatus.lastResult = "no_api"
        return "fail"
    end
    local why = fightsBlocked()
    if why then
        fightStatus.lastResult = "wait:" .. why
        return "wait"
    end
    local ok, avail = pcall(DM.GetAvailableCombatSessions)
    if not ok or type(avail) ~= "table" then
        fightStatus.errors = fightStatus.errors + 1
        fightStatus.lastError = "GetAvailableCombatSessions"
        fightStatus.lastResult = "fail:sessions"
        return "fail"
    end
    if isSecretTable(avail) then
        fightStatus.lastResult = "wait:secret"
        fightStatus.secretWaits = fightStatus.secretWaits + 1
        return "wait"
    end

    local c = fightsDB()
    local st = c.fightState
    local list, maxId = {}, 0
    for _, a in ipairs(avail) do
        if type(a) == "table" and num(a.sessionID) then
            list[#list + 1] = a
            if a.sessionID > maxId then maxId = a.sessionID end
        end
    end
    fightStatus.sessions = #list
    fightStatus.maxSid = maxId
    -- Session ids went backwards: client reset them (relog / meter reset).
    if maxId < (st.lastSid or 0) then
        st.lastSid = 0
        st.resets = (st.resets or 0) + 1
    end
    table.sort(list, function(a, b) return a.sessionID < b.sessionID end)

    local playerGUID = safeCall(UnitGUID, "player")
    if isSecret(playerGUID) then playerGUID = nil end
    local fights = c.fights
    local last = fights[#fights]
    local added = 0
    for idx, a in ipairs(list) do
        local sid = a.sessionID
        local newest = (idx == #list)
        local approx = approxAll or not newest or endAt == nil
        local replace = false
        if sid == st.lastSid and last and last.sid == sid then
            -- Same session grew after we read it (fights chained): re-read it.
            local d = num(a.durationSeconds)
            if d and round1(d) > (last.dur or 0) + 0.5 then replace = true end
        end
        if sid > (st.lastSid or 0) or replace then
            local okR, rec, reason = pcall(readFight, DM, a, endAt, approx, playerGUID)
            if not okR then
                fightStatus.errors = fightStatus.errors + 1
                fightStatus.lastError = tostring(rec)
                st.lastSid = sid -- skip a session that throws, don't loop on it
            elseif not rec then
                if reason == "secret" then
                    fightStatus.secretWaits = fightStatus.secretWaits + 1
                    fightStatus.lastResult = "wait:secret"
                    return "wait"
                end
                st.lastSid = sid -- nosession/err: nothing to keep
            else
                if replace then
                    rec.t = last.t
                    rec.approx = last.approx
                    fights[#fights] = rec
                elseif not isDuplicate(fights, rec) then
                    fights[#fights + 1] = rec
                    added = added + 1
                end
                st.lastSid = sid
                last = fights[#fights]
            end
        end
    end
    rollFights(c)
    fightStatus.added = fightStatus.added + added
    fightStatus.lastResult = "ok+" .. added
    fightStatus.lastAt = time()
    return "done"
end

local fightTicker
local function stopFightTicker()
    if fightTicker and type(fightTicker.Cancel) == "function" then
        fightTicker:Cancel()
    end
    fightTicker = nil
end
ns.StopFightTicker = stopFightTicker

-- Start the post-combat wait loop. endAt = unix time combat ended (nil = unknown).
function ns.FightsSchedule(reason, endAt)
    stopFightTicker()
    fightStatus.lastReason = reason
    fightStatus.tries = 0
    if type(_G.C_DamageMeter) ~= "table" then
        fightStatus.lastResult = "no_api"
        return
    end
    if not (C_Timer and type(C_Timer.NewTicker) == "function") then
        fightStatus.lastResult = "no_timer" -- by design: no OnUpdate fallback
        return
    end
    local tries = 0
    local ticker
    ticker = C_Timer.NewTicker(1, function()
        tries = tries + 1
        fightStatus.tries = tries
        local res = ns.FightsTryRead(endAt, endAt == nil)
        if res ~= "wait" or tries >= FIGHT_WAIT_TRIES then
            if res == "wait" then fightStatus.lastResult = fightStatus.lastResult .. " (gave up)" end
            if fightTicker == ticker then stopFightTicker() elseif ticker and ticker.Cancel then ticker:Cancel() end
        end
    end, FIGHT_WAIT_TRIES)
    fightTicker = ticker
end

local function fmtNum(n)
    n = tonumber(n) or 0
    if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
    if n >= 10000 then return ("%.1fk"):format(n / 1000) end
    return tostring(math.floor(n + 0.5))
end

function ns.PrintFights(n)
    local c = fightsDB()
    local f = c.fights
    local days = 0
    for _ in pairs(c.fightDays) do days = days + 1 end
    print(("|cff33ff99HelloForever|r fights: %d stored (cap %d), %d rolled-up day(s). Last %d:")
        :format(#f, FIGHTS_CAP, days, math.min(n, #f)))
    if #f == 0 then
        print("  (none yet; numbers are read ~1-15 s after combat ends)")
        return
    end
    for i = #f, math.max(1, #f - n + 1), -1 do
        local r = f[i]
        local top = r.spells and r.spells[1]
        print(("  %s %s %ss dmg %s (%s dps)%s heal %s taken %s%s%s"):format(
            date("%H:%M", r.t or 0), tostring(r.name), tostring(r.dur or 0),
            fmtNum(r.dmg), tostring(r.dps or 0),
            (r.petDmg or 0) > 0 and (" pet " .. fmtNum(r.petDmg)) or "",
            fmtNum(r.heal), fmtNum(r.taken),
            r.died and " |cffff4040DIED|r" or "",
            top and (" top: " .. tostring(top.name or top.id) .. (top.pet and (" (" .. top.pet .. ")") or "")) or ""))
    end
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
    local c = fightsDB()
    return ("  fights: api=%s meterAvailable=%s%s secretFn=%s restrict=%s lastSid=%s resets=%s stored=%d last=%s reason=%s tries=%s waits=%s err=%s%s")
        :format(tostring(api), avail, why,
            tostring(type(_G.issecretvalue) == "function"),
            tostring(fightsBlocked() or "none"),
            tostring(c.fightState.lastSid), tostring(c.fightState.resets or 0),
            #c.fights, tostring(fightStatus.lastResult), tostring(fightStatus.lastReason),
            tostring(fightStatus.tries), tostring(fightStatus.secretWaits),
            tostring(fightStatus.errors),
            fightStatus.lastError and (" lastErr=" .. tostring(fightStatus.lastError)) or "")
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
        ns.PrintFights(5)
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
            -- Fights catch-up (e.g. after /reload); waits itself if in combat.
            ns.FightsSchedule("entering_world", nil)
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
        -- Entering combat: stop any pending fights read; do nothing in combat.
        ns.StopFightTicker()

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat over: read C_DamageMeter once values stop being secret.
        ns.FightsSchedule("regen", time())

    elseif event == "TIME_PLAYED_MSG" then
        pendingPlayed.total = arg1
        pendingPlayed.level = arg2
        local c = ensureDB()
        if c.snapshot then
            c.snapshot.timePlayed = { total = arg1, level = arg2 }
        end
    end
end)
