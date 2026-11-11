-- HelloForever / Snapshot.lua
-- Character snapshot + delta timeline for offline analysis, the play-session counters
-- behind the XP panel, the level log and the optional combat-log helper.
local addonName, ns = ...

local type, ipairs, pairs, tostring, tonumber, pcall, next = type, ipairs, pairs, tostring, tonumber, pcall, next
local rawget = rawget
local floor, min, huge = math.floor, math.min, math.huge
local GetTime, time = GetTime, time
local call, callAll, isSecret = ns.Call, ns.CallAll, ns.IsSecret
local sort = table.sort

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

-- Quest complete flag. Forever's C_QuestLog.GetInfo (1.60.1) has NO isComplete
-- field — treating missing as false marked every log quest incomplete. Prefer
-- APIs documented to mean "in the log and ready to turn in":
--   IsQuestComplete / C_QuestLog.IsComplete (log, ready)
--   GetQuestLogTitle return 6 on Classic 1.13 / 6.0+: 1 ready, -1 failed, nil else
--   C_QuestLog.IsQuestFlaggedCompleted / GetAllCompletedQuestIDs (turned-in history)
--   GetQuestLogLeaderBoard / C_QuestLog.GetQuestObjectives (progress)
-- "Defias Trapper slain: 3/8" -> 3, 8 (the counts are digits in every locale).
local function countsFromText(text)
    if type(text) ~= "string" then return nil, nil end
    local have, need = text:match("(%d+)%s*/%s*(%d+)")
    return tonumber(have), tonumber(need)
end

-- Returns the objective rows, how many are finished, how many there are, and whether
-- any of them has moved at all. Finished objectives are counted, never summed kill
-- counts: "10/10 boars, 0/1 talk to X" is one of two, not ten of eleven.
local function questObjectives(logIndex, questID)
    local out, done, progress = {}, 0, false
    local function add(text, typ, finished, have, need)
        if type(have) ~= "number" or type(need) ~= "number" then
            local h, n = countsFromText(text)
            if type(have) ~= "number" then have = h end
            if type(need) ~= "number" then need = n end
        end
        finished = finished and true or false
        out[#out + 1] = { text = text, type = typ, finished = finished, have = have, need = need }
        if finished then done = done + 1 end
        if finished or (type(have) == "number" and have > 0) then progress = true end
    end
    local QL = _G.C_QuestLog
    if questID and type(QL) == "table" and type(QL.GetQuestObjectives) == "function" then
        local objs = call(QL.GetQuestObjectives, questID)
        if type(objs) == "table" then
            for i = 1, #objs do
                local o = objs[i]
                if type(o) == "table" then add(o.text, o.type, o.finished, o.numFulfilled, o.numRequired) end
            end
            return out, done, #out, progress
        end
    end
    local n = call(_G.GetNumQuestLeaderBoards, logIndex)
    if type(n) ~= "number" then n = 0 end
    for i = 1, n do
        local text, typ, finished = call(_G.GetQuestLogLeaderBoard, i, logIndex)
        add(text, typ, finished)
    end
    return out, done, #out, progress
end

local function questReadyFlag(questID, logIndex, info)
    -- Only trust GetInfo.isComplete when the field is actually present.
    if type(info) == "table" and info.isComplete ~= nil then return info.isComplete end
    local QL = _G.C_QuestLog
    if questID and type(QL) == "table" and type(QL.IsComplete) == "function" then
        local v = call(QL.IsComplete, questID)
        if v ~= nil then return v end
    end
    if questID then
        local v = call(_G.IsQuestComplete, questID)
        if v ~= nil then return v end
    end
    if type(_G.GetQuestLogTitle) ~= "function" then return nil end
    local raw = callAll(_G.GetQuestLogTitle, logIndex) or {}
    -- Classic 1.13 / 6.0+: title, level, suggestedGroup, isHeader, isCollapsed, isComplete
    -- Pre-6.0 1.12: title, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete
    if type(raw[4]) == "boolean" then return raw[6] end
    if type(raw[7]) == "number" or raw[7] == nil and type(raw[5]) == "boolean" then return raw[7] end
    return raw[6]
end

local function questFlaggedCompleted(questID)
    if not questID then return nil end
    local QL = _G.C_QuestLog
    if type(QL) == "table" and type(QL.IsQuestFlaggedCompleted) == "function" then
        local v = call(QL.IsQuestFlaggedCompleted, questID)
        if v ~= nil then return v and true or false end
    end
    local v = call(_G.IsQuestFlaggedCompleted, questID)
    if v ~= nil then return v and true or false end
    return nil
end

-- Turned-in history. Returns the id list (ascending, at most COMPLETED_CAP ids) and how
-- many ids the client reported, or nil when this client has no history API.
local COMPLETED_CAP = 4000

local function allCompletedIDs()
    local QL = _G.C_QuestLog
    if type(QL) == "table" and type(QL.GetAllCompletedQuestIDs) == "function" then
        local ids = call(QL.GetAllCompletedQuestIDs)
        if type(ids) == "table" then
            lastApiUsed.questHistory = "C_QuestLog.GetAllCompletedQuestIDs"
            local out, total = {}, #ids
            for i = 1, min(total, COMPLETED_CAP) do out[i] = ids[i] end
            return out, total
        end
    end
    local t = call(_G.GetQuestsCompleted)
    if type(t) == "table" then
        lastApiUsed.questHistory = "GetQuestsCompleted"
        local out = {}
        for id, yes in pairs(t) do
            if yes and type(id) == "number" then out[#out + 1] = id end
        end
        sort(out)
        local total = #out
        for i = total, COMPLETED_CAP + 1, -1 do out[i] = nil end
        return out, total
    end
    lastApiUsed.questHistory = "none"
    return nil, nil
end

-- Was this quest turned in? true / false, or nil when the client cannot say (no id, or
-- no history API). `set` is the turned-in list as a lookup; `whole` is true when that
-- list is not truncated, so an id missing from it really is not completed.
local function turnedIn(id, set, whole)
    if type(id) ~= "number" then return nil end
    if set and set[id] then return true end
    local v = questFlaggedCompleted(id)
    if v ~= nil then return v end
    if set and whole then return false end
    return nil
end

local function questWatchKey(id, title)
    if type(id) == "number" and id > 0 then return "q" .. id end
    return "t" .. tostring(title or "?")
end

local ABANDONED_CAP = 40

-- `full` is true for a whole-character snapshot; the quest-log event path passes false
-- and re-reads the turned-in history only when a quest left the log.
local function collectQuests(prevQ, full)
    local log, seen = {}, {}
    lastApiUsed.quests = "none"
    lastApiUsed.questCount = 0
    local QL = _G.C_QuestLog

    local function addLog(logIndex, title, level, questID, info)
        if not title then return end
        local objs, done, tot, progress = questObjectives(logIndex, questID)
        local ready = questReadyFlag(questID, logIndex, info)
        local state = ns.ClassifyQuest({
            inLog = true,
            isComplete = ready,
            objectivesDone = done,
            objectivesTotal = tot,
            progress = progress,
        })
        log[#log + 1] = {
            id = questID, title = title, level = level or 0,
            state = state, objectives = objs,
        }
        seen[questWatchKey(questID, title)] = { id = questID, title = title, state = state }
    end

    if type(QL) == "table" and type(QL.GetNumQuestLogEntries) == "function" then
        local n = call(QL.GetNumQuestLogEntries) or 0
        for i = 1, n do
            local info = call(QL.GetInfo, i)
            if type(info) == "table" and info.title and not info.isHeader then
                local level = info.level
                if (not level or level == 0) and type(_G.GetQuestLogTitle) == "function" then
                    local raw = callAll(_G.GetQuestLogTitle, i) or {}
                    if type(raw[2]) == "number" and raw[2] > 0 then level = raw[2] end
                end
                addLog(i, info.title, level, info.questID, info)
            end
        end
        if #log > 0 then lastApiUsed.quests = "C_QuestLog.GetInfo" end
    end

    if #log == 0 then
        local n = call(_G.GetNumQuestLogEntries) or 0
        lastApiUsed.quests = "GetQuestLogTitle"
        for i = 1, n do
            local raw = callAll(_G.GetQuestLogTitle, i) or {}
            local title = type(raw[1]) == "string" and raw[1] or nil
            local level = type(raw[2]) == "number" and raw[2] or 0
            local isHeader = raw[4]
            -- 1.13/6.0: isHeader at 4 (boolean). 1.12: suggestedGroup at 4, isHeader at 5.
            if type(raw[4]) ~= "boolean" and type(raw[5]) == "boolean" then isHeader = raw[5] end
            -- Classic 1.13: isHeader at 4. 1.12: isHeader at 5. questID at 8 (3.3+/Classic).
            local questID = type(raw[8]) == "number" and raw[8] or nil
            if title and not isHeader then addLog(i, title, level, questID, nil) end
        end
    end
    lastApiUsed.questCount = #log

    local c = ns.Char()
    local watch = c.questWatch
    if type(watch) ~= "table" then watch = {} end
    local left -- quests that were in the log at the last read and are not now
    for k, prev in pairs(watch) do
        if not seen[k] then
            left = left or {}
            left[#left + 1] = prev
        end
    end

    -- Turned-in history is thousands of ids on a levelled character, and QUEST_LOG_UPDATE
    -- fires on every objective tick: copy it again only when it can have changed.
    local prevIsV6 = type(prevQ) == "table" and (prevQ.log ~= nil or prevQ.abandoned ~= nil)
    local completed, completedTotal
    if full or left or not prevIsV6 or type(prevQ.completed) ~= "table" then
        completed, completedTotal = allCompletedIDs()
    else
        completed, completedTotal = prevQ.completed, prevQ.completedTotal
    end
    local completedSet
    local function isTurnedIn(id)
        if not completedSet and type(completed) == "table" then
            completedSet = {}
            for i = 1, #completed do completedSet[completed[i]] = true end
        end
        return turnedIn(id, completedSet, type(completed) == "table" and (completedTotal or 0) <= #completed)
    end

    -- Abandoned = left the log and the client says it was NOT turned in. A quest the
    -- client cannot vouch for either way is not recorded (never guessed). An entry is
    -- dropped again once the quest is back in the log or shows up as turned in: the
    -- completed flag can lag a turn-in, and a log that had not loaded yet looks empty.
    local abandoned = {}
    local prevAb = prevIsV6 and prevQ.abandoned
    if type(prevAb) == "table" then
        local lateTurnIn = false
        for i = 1, #prevAb do
            local e = prevAb[i]
            if type(e) == "table" and not seen[questWatchKey(e.id, e.title)] then
                if isTurnedIn(e.id) == true then
                    lateTurnIn = true
                else
                    abandoned[#abandoned + 1] = e
                end
            end
        end
        -- the flag arrived after the quest left the log: a reused history list lacks it
        if lateTurnIn and completed == prevQ.completed then
            completed, completedTotal = allCompletedIDs()
            completedSet = nil
        end
    end
    if left then
        local now = time()
        for i = 1, #left do
            local prev = left[i]
            if isTurnedIn(prev.id) == false then
                abandoned[#abandoned + 1] = { id = prev.id, title = prev.title, observedAt = now }
            end
        end
    end
    ns.TrimHead(abandoned, ABANDONED_CAP, 0)
    c.questWatch = seen

    return {
        log = log,
        completed = completed,           -- nil = this client has no history API
        completedTotal = completedTotal, -- > #completed when the list was capped
        abandoned = abandoned,
    }
end

local function collectQuestsFull(prevQ)
    return collectQuests(prevQ, true)
end

local function collectBags()
    lastApiUsed.bags = "none"
    lastApiUsed.bagCount = 0
    local CC = _G.C_Container
    local getSlots, getLink, getInfo
    if type(CC) == "table" and type(CC.GetContainerNumSlots) == "function" then
        lastApiUsed.bags = "C_Container"
        getSlots = function(b) return call(CC.GetContainerNumSlots, b) end
        getLink = type(CC.GetContainerItemLink) == "function"
            and function(b, s) return call(CC.GetContainerItemLink, b, s) end
        getInfo = type(CC.GetContainerItemInfo) == "function"
            and function(b, s) return call(CC.GetContainerItemInfo, b, s) end
    elseif type(_G.GetContainerNumSlots) == "function" then
        lastApiUsed.bags = "GetContainerNumSlots"
        getSlots = function(b) return call(_G.GetContainerNumSlots, b) end
        getLink = function(b, s) return call(_G.GetContainerItemLink, b, s) end
    else
        return nil
    end
    local nBags = 4
    if type(_G.NUM_BAG_SLOTS) == "number" then nBags = _G.NUM_BAG_SLOTS end
    local CI = _G.Constants and _G.Constants.InventoryConstants
    if type(CI) == "table" and type(CI.NumBagSlots) == "number" then nBags = CI.NumBagSlots end
    local items = {}
    for bag = 0, nBags do
        local slots = getSlots(bag) or 0
        for slot = 1, slots do
            local id, count, link
            if getInfo then
                local info = getInfo(bag, slot)
                if type(info) == "table" then
                    id, count, link = info.itemID, info.stackCount, info.hyperlink
                end
            end
            if not link and getLink then link = getLink(bag, slot) end
            if not id then id = call(_G.GetContainerItemID, bag, slot) end
            if not count and type(_G.GetContainerItemInfo) == "function" then
                local raw = callAll(_G.GetContainerItemInfo, bag, slot)
                count = raw and raw[2]
            end
            if link or id then
                items[#items + 1] = { bag = bag, slot = slot, id = id, count = count or 1, link = link }
            end
        end
    end
    lastApiUsed.bagCount = #items
    return items
end

-- Hunter pet. Classic-era APIs only (plus Forever replacements of those
-- APIs: C_SpellBook.HasPetSpells for HasPetSpells). C_StableInfo /
-- C_PetJournal are not Classic-era and are not used. Anything the client
-- does not return is stored as "unknown", never guessed.
-- Permanent hunter pet (HasPetUI isHunterPet) is kept separate from a
-- temporary summon (UnitExists("pet") without isHunterPet), e.g. Summon Hawk.
local PET_ACTION_SLOTS = 10

local function petRank(name, sub, spellID)
    local s = sub
    if (not s or s == "") and spellID then
        local CS = _G.C_Spell
        if type(CS) == "table" and type(CS.GetSpellSubtext) == "function" then
            s = call(CS.GetSpellSubtext, spellID)
        end
        if not s or s == "" then s = call(_G.GetSpellSubtext, spellID) end
    end
    if type(s) == "string" then
        local n = s:match("(%d+)")
        if n then return tonumber(n) end
    end
    if type(name) == "string" then
        local n = name:match("[Rr]ank%s*(%d+)")
        if n then return tonumber(n) end
    end
    return "unknown"
end

local function petAutocastByName()
    local map = {}
    for i = 1, PET_ACTION_SLOTS do
        local raw = callAll(_G.GetPetActionInfo, i)
        if type(raw) == "table" and type(raw[1]) == "string" then
            map[raw[1]] = {
                slot = i,
                autocastAllowed = raw[5] and true or false,
                autocast = raw[6] and true or false,
                spellID = raw[7],
                isToken = raw[3] and true or false,
            }
        end
    end
    return map
end

local function collectPetAbilities()
    local abilities, src = {}, "none"
    local n, token
    local SB = _G.C_SpellBook
    local petBank = 1
    local E = _G.Enum
    if type(E) == "table" and type(E.SpellBookSpellBank) == "table" and type(E.SpellBookSpellBank.Pet) == "number" then
        petBank = E.SpellBookSpellBank.Pet
    end
    if type(SB) == "table" and type(SB.HasPetSpells) == "function" then
        n, token = call(SB.HasPetSpells)
        src = "C_SpellBook.HasPetSpells"
    elseif type(_G.HasPetSpells) == "function" then
        n, token = call(_G.HasPetSpells)
        src = "HasPetSpells"
    end
    local autocast = petAutocastByName()
    if type(n) == "number" and n > 0 then
        for i = 1, n do
            local name, sub, spellID
            if src:find("C_SpellBook", 1, true) and type(SB.GetSpellBookItemName) == "function" then
                name, sub = call(SB.GetSpellBookItemName, i, petBank)
                if type(SB.GetSpellBookItemType) == "function" then
                    local _, sid = call(SB.GetSpellBookItemType, i, petBank)
                    if type(sid) == "number" then spellID = sid end
                end
            else
                name, sub, spellID = call(_G.GetSpellBookItemName, i, "pet")
                if not name then name, sub, spellID = call(_G.GetSpellName, i, "pet") end
            end
            if type(name) == "string" and name ~= "" then
                local ac = autocast[name]
                abilities[#abilities + 1] = {
                    name = name,
                    rank = petRank(name, sub, spellID or (ac and ac.spellID)),
                    spellID = spellID or (ac and ac.spellID) or "unknown",
                    autocast = ac and ac.autocast or (ac == nil and "unknown" or false),
                    slot = ac and ac.slot or nil,
                    sub = (type(sub) == "string" and sub ~= "") and sub or nil,
                }
            end
        end
    elseif next(autocast) then
        src = src == "none" and "GetPetActionInfo" or src
        for name, ac in pairs(autocast) do
            if not ac.isToken then
                abilities[#abilities + 1] = {
                    name = name,
                    rank = petRank(name, nil, ac.spellID),
                    spellID = ac.spellID or "unknown",
                    autocast = ac.autocast,
                    slot = ac.slot,
                }
            end
        end
    end
    lastApiUsed.petAbilities = src
    lastApiUsed.petAbilityCount = #abilities
    lastApiUsed.petToken = token
    return abilities
end

local function collectPet()
    lastApiUsed.pet = "none"
    local exists = call(_G.UnitExists, "pet")
    local hasUI, isHunter = call(_G.HasPetUI)
    local kind
    if isHunter == true then
        kind = "hunter"
    elseif hasUI == true then
        kind = "minion"
    elseif exists == true then
        kind = "temporary"
    elseif exists == false or hasUI == false then
        kind = "none"
    else
        -- HasPetUI / UnitExists missing: do not guess a hunter pet
        lastApiUsed.pet = "unavailable"
        return nil
    end
    lastApiUsed.pet = "HasPetUI+UnitExists"
    if kind == "none" then
        return { kind = "none" }
    end
    local family, familyId = call(_G.UnitCreatureFamily, "pet")
    local hap, hapPct, loyalty = call(_G.GetPetHappiness)
    local tpTotal, tpSpent = call(_G.GetPetTrainingPoints)
    local xp, xpNext = call(_G.GetPetExperience)
    local function unk(v)
        if v == nil then return "unknown" end
        return v
    end
    local training = "unknown"
    if type(tpTotal) == "number" then
        training = { total = tpTotal, spent = tpSpent }
    end
    local xpT = "unknown"
    if type(xp) == "number" then
        xpT = { curr = xp, next = xpNext }
    end
    return {
        kind = kind,
        name = unk(call(UnitName, "pet")),
        family = unk(family),
        familyId = familyId,
        level = unk(call(UnitLevel, "pet")),
        happiness = unk(hap),
        happinessDamagePct = unk(hapPct),
        loyaltyRate = unk(loyalty),
        training = training,
        xp = xpT,
        hasUI = hasUI == true,
        isHunterPet = (isHunter == nil) and "unknown" or (isHunter and true or false),
        abilities = collectPetAbilities(),
        icon = unk(call(_G.GetPetIcon)),
    }
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

-- Writes snap.timePlayed. Fresh only when the client's own counter is known this
-- session; values carried over from the previous snapshot are stale, not "ok".
local function stampPlayed(snap, prev)
    local live = playedNow()
    local tp = timePlayedTable(prev and prev.timePlayed)
    snap.timePlayed = tp
    if live then
        ns.SetFresh(snap, "timePlayed", "ok")
    else
        local pf = prev and prev.freshness and prev.freshness.timePlayed
        ns.SetFresh(snap, "timePlayed", tp.total and "stale" or "unavailable", pf and pf.observedAt)
    end
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
-- nil with no error means the API is missing (unavailable), not an empty result.
local function collectField(prev, field, fn)
    local ok, a = pcall(fn, prev and prev[field])
    if not ok then
        lastApiUsed[field .. "Err"] = tostring(a)
        if prev and prev[field] ~= nil then return prev[field], "stale" end
        return nil, "unavailable"
    end
    if a == nil then
        if prev and prev[field] ~= nil then return prev[field], "stale" end
        return nil, "unavailable"
    end
    return a, "ok"
end

local function putSection(snap, prev, name, field, value, status)
    if status == "ok" then
        snap[field] = value
        ns.SetFresh(snap, name, "ok")
    elseif prev and prev[field] ~= nil then
        snap[field] = prev[field]
        -- a snapshot written before 0.6.0 has no per-section times: its own time is the best known
        local at = prev.freshness and prev.freshness[name] and prev.freshness[name].observedAt
        ns.SetFresh(snap, name, "stale", at or prev.t)
    else
        snap[field] = value
        ns.SetFresh(snap, name, status or "unavailable")
    end
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
        subzone = call(GetSubZoneText),
        _apiUsed = lastApiUsed,
        _valid = isValidXPMoney(xp, xpMax, money),
    }
    local liveOK = snap._valid
    snap.level = call(UnitLevel, "player")
    snap.xp, snap.xpMax, snap.rested = xp, xpMax, call(GetXPExhaustion)
    snap.money = money
    snap.zone = zoneText()
    if liveOK then
        ns.SetFresh(snap, "level", "ok")
        ns.SetFresh(snap, "gold", "ok")
        ns.SetFresh(snap, "zone", "ok")
    else
        if prev then
            snap.level, snap.xp, snap.xpMax, snap.rested = prev.level, prev.xp, prev.xpMax, prev.rested
            snap.money = prev.money
            snap.zone, snap.subzone = prev.zone, prev.subzone
        end
        local pf = prev and prev.freshness
        local pt = prev and prev.t
        ns.SetFresh(snap, "level", prev and "stale" or "unavailable", pf and pf.level and pf.level.observedAt or pt)
        ns.SetFresh(snap, "gold", prev and "stale" or "unavailable", pf and pf.gold and pf.gold.observedAt or pt)
        ns.SetFresh(snap, "zone", prev and "stale" or "unavailable", pf and pf.zone and pf.zone.observedAt or pt)
    end
    local stats, st = collectField(prev, "stats", collectStats)
    putSection(snap, prev, "stats", "stats", stats, st)
    local eq, est = collectField(prev, "equipped", collectEquipped)
    putSection(snap, prev, "gear", "equipped", eq, est)
    local bags, bst = collectField(prev, "bags", collectBags)
    putSection(snap, prev, "bags", "bags", bags, bst)
    local tal, tst = collectField(prev, "talents", collectTalents)
    putSection(snap, prev, "talents", "talents", tal, tst)
    local sk, sst = collectField(prev, "skills", collectSkills)
    putSection(snap, prev, "professions", "skills", sk, sst)
    local rep, rst = collectField(prev, "reputations", collectReputations)
    putSection(snap, prev, "reputation", "reputations", rep, rst)
    local q, qst = collectField(prev, "quests", collectQuestsFull)
    putSection(snap, prev, "quests", "quests", q, qst)
    stampPlayed(snap, prev)
    local pet, pst = collectField(prev, "pet", collectPet)
    putSection(snap, prev, "pet", "pet", pet, pst)
    return ns.Stamp(snap)
end

----------------------------------------------------------------------
-- Context blobs: cheap fight → gear/talents/pet links (hashes, not copies
-- per fight). Cap keeps SavedVariables slim.
----------------------------------------------------------------------
local CONTEXT_CAP = 40

local function compactTalents(tal)
    if type(tal) ~= "table" then return nil end
    return { spent = tal.spent, unspent = tal.unspent, spec = tal.spec, nodes = tal.nodes }
end

local function compactPet(pet)
    if type(pet) ~= "table" then return nil end
    return {
        kind = pet.kind, name = pet.name, family = pet.family, level = pet.level,
        happiness = pet.happiness, abilities = pet.abilities,
    }
end

-- Store the blob for `id` (or just touch it when it is already there) and evict the
-- least recently used blobs past the cap, never the ones currently in use.
local function putBlob(c, kind, id, data)
    local blobs = c.contextBlobs
    local b = blobs[id]
    if b then
        b.t = time()
        return id
    end
    blobs[id] = { kind = kind, t = time(), data = data }
    local n = 0
    for _ in pairs(blobs) do n = n + 1 end
    local keep = c.contextIds
    while n > CONTEXT_CAP do
        local oldest, oldT
        for k, v in pairs(blobs) do
            if k ~= id and not (keep and (k == keep.gear or k == keep.talents or k == keep.pet)) then
                if not oldT or (v.t or 0) < oldT then oldest, oldT = k, v.t or 0 end
            end
        end
        if not oldest then break end
        blobs[oldest] = nil
        n = n - 1
    end
    return id
end

-- Refresh the gear / talents / pet hashes of the current snapshot. `only` names the one
-- part that changed (a patch); without it all three are hashed (a full snapshot).
function ns.RememberContext(only)
    local c = ns.Char()
    local snap = c.snapshot
    if not snap then return nil end
    if type(c.contextBlobs) ~= "table" then c.contextBlobs = {} end
    local ids = c.contextIds
    if type(ids) ~= "table" then
        ids, only = {}, nil
        c.contextIds = ids
    end
    if not only or only == "gear" then
        ids.gear = putBlob(c, "gear", ns.HashGear(snap.equipped), snap.equipped)
    end
    if not only or only == "talents" then
        ids.talents = putBlob(c, "talents", ns.HashTalents(snap.talents), compactTalents(snap.talents))
    end
    if not only or only == "pet" then
        ids.pet = putBlob(c, "pet", ns.HashPet(snap.pet), compactPet(snap.pet))
    end
    return ids
end

----------------------------------------------------------------------
-- Matty7500Hunter / MHP-Hunter-Helper: read-only observe. Never write.
----------------------------------------------------------------------
local MH_ADDONS = { "Matty7500Hunter", "MHP-Hunter-Helper", "Matty7500HunterClassic", "Matty7500HunterForever" }
local MH_GLOBALS = { "Matty7500Hunter", "MHPHunterHelper", "MHP_Hunter_Helper" }
local MH_SV = { "Matty7500HunterDB", "MHPHunterHelperDB", "Matty7500Hunter_lastDecision" }

local function mhAddonLoaded(name)
    local CA = _G.C_AddOns
    if type(CA) == "table" and type(CA.IsAddOnLoaded) == "function" then
        local v = call(CA.IsAddOnLoaded, name)
        if v ~= nil then return v and true or false end
    end
    return call(_G.IsAddOnLoaded, name) == true
end

local function mhAddonVersion(name)
    local CA = _G.C_AddOns
    if type(CA) == "table" then
        local v = call(CA.GetAddOnMetadata, name, "Version")
        if type(v) == "string" and v ~= "" then return v end
    end
    return call(_G.GetAddOnMetadata, name, "Version")
end

local MH_STRING_MAX = 200

-- Copy of the plain values in someone else's table: strings (clipped), finite numbers
-- and booleans, two levels deep. Secret values and anything else are left out, so the
-- copy can always be serialised.
local function mhPlainCopy(t, depth, cap)
    if type(t) ~= "table" or depth > 2 then return nil end
    local out, n = {}, 0
    for k, v in pairs(t) do
        if n >= cap then break end
        if not isSecret(k) and not isSecret(v) then
            local tk, tv = type(k), type(v)
            if tk == "string" or tk == "number" then
                if tv == "string" then
                    out[k] = #v > MH_STRING_MAX and v:sub(1, MH_STRING_MAX) or v
                    n = n + 1
                elseif tv == "boolean" or (tv == "number" and v == v and v ~= huge and v ~= -huge) then
                    out[k] = v
                    n = n + 1
                elseif tv == "table" and depth < 2 and tk == "string" then
                    local sub = mhPlainCopy(v, depth + 1, 10)
                    if sub then
                        out[k] = sub
                        n = n + 1
                    end
                end
            end
        end
    end
    return n > 0 and out or nil
end

-- Field of another addon's table without running its metamethods (reading through
-- __index would be calling its code).
local function mhField(t, k)
    local v = rawget(t, k)
    if isSecret(v) then return nil end
    return v
end

-- Passive: globals + other addons' SV tables only. Never call MH methods,
-- never write, never register callbacks (that would mutate MH).
local function sampleMH()
    local loadedName
    for i = 1, #MH_ADDONS do
        if mhAddonLoaded(MH_ADDONS[i]) then
            loadedName = MH_ADDONS[i]
            break
        end
    end
    local glob, globName
    for i = 1, #MH_GLOBALS do
        local g = _G[MH_GLOBALS[i]]
        if type(g) == "table" then
            glob, globName = g, MH_GLOBALS[i]
            break
        end
    end
    local svName
    for i = 1, #MH_SV do
        if type(_G[MH_SV[i]]) == "table" then
            svName = MH_SV[i]
            break
        end
    end
    if not loadedName and not glob and not svName then
        -- Stored on every fight, so it stays small: MH is not loaded and left no readable
        -- global or SavedVariables table (docs/SCHEMA.md has the long version).
        return { status = "unavailable", observedAt = time() }
    end
    local decision, scores
    if glob then
        local last = mhField(glob, "lastDecision")
        if type(last) == "table" then
            decision = mhPlainCopy(last, 0, 20)
        elseif type(last) == "string" or type(last) == "number" then
            decision = mhPlainCopy({ value = last }, 0, 1)
        end
        scores = mhPlainCopy(mhField(glob, "lastScores"), 0, 15) or mhPlainCopy(mhField(glob, "scores"), 0, 15)
    end
    if not decision and svName then
        local sv = _G[svName]
        if type(sv) == "table" then decision = mhPlainCopy(mhField(sv, "lastDecision"), 0, 20) end
    end
    return {
        status = decision and "ok" or "unknown",
        observedAt = time(),
        addon = loadedName or globName,
        version = loadedName and mhAddonVersion(loadedName) or nil,
        global = globName,
        decision = decision,
        scores = scores,
        sv = svName,
        note = (not decision)
            and "MH present but lastDecision was not readable plain data; methods were not called"
            or nil,
    }
end

-- Runs at combat start, so a surprise in another addon's tables must never throw here.
function ns.SampleMH()
    local ok, r = pcall(sampleMH)
    if ok and type(r) == "table" then return r end
    return { status = "unknown", observedAt = time(), note = "MH read failed; nothing was called or written" }
end

local lastSkillRank = {}

local function skillRankMap(skills)
    local m = {}
    if type(skills) ~= "table" then return m end
    for i = 1, #skills do
        local s = skills[i]
        if type(s) == "table" and s.name then m[s.name] = s.rank end
    end
    return m
end

local function noteSkillRanks(skills)
    lastSkillRank = skillRankMap(skills)
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
    ns.RememberContext()
    noteSkillRanks(snap.skills)
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
        ns.SetFresh(c.snapshot, "zone", c.snapshot.zone and "ok" or "unavailable")
        ns.SetFresh(c.snapshot, "timePlayed", c.snapshot.timePlayed.total and "ok" or "unavailable")
        return c.snapshot
    end
    prev.t = time()
    prev.reason = "logout"
    -- Only what the client still answers at logout counts as observed now.
    local zone = zoneText()
    if zone then
        prev.zone = zone
        prev.subzone = call(GetSubZoneText) or prev.subzone
        ns.SetFresh(prev, "zone", "ok")
    end
    stampPlayed(prev, prev)
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
    ns.SetFresh(snap, "gold", "ok")
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
    ns.SetFresh(snap, "gear", "ok")
    ns.RememberContext("gear")
end

function ns.PatchBags()
    local c = ns.Char()
    local snap = c.snapshot
    if not snap then return end
    local bags = collectBags()
    if bags == nil then return end
    if #bags == 0 and type(snap.bags) == "table" and #snap.bags > 0 then return end
    snap.bags = bags
    snap.t = time()
    ns.SetFresh(snap, "bags", "ok")
end

function ns.PatchPet()
    local c = ns.Char()
    local snap = c.snapshot
    if not snap then return end
    local pet = collectPet()
    if pet == nil then return end
    snap.pet = pet
    snap.t = time()
    ns.SetFresh(snap, "pet", "ok")
    ns.RememberContext("pet")
end

-- Talents-only patch, so a fight's context.talents is the build it was fought with and
-- not the one from the last login.
function ns.PatchTalents()
    local c = ns.Char()
    local snap = c.snapshot
    if not snap then return end
    local ok, tal = pcall(collectTalents)
    if not ok or type(tal) ~= "table" then return end
    -- no API answered: keep what we have (a real respec still answers, with no nodes)
    if not tal.src and type(snap.talents) == "table" and snap.talents.src then return end
    snap.talents = tal
    snap.t = time()
    ns.SetFresh(snap, "talents", "ok")
    ns.RememberContext("talents")
end

function ns.PatchQuests()
    local c = ns.Char()
    local snap = c.snapshot
    if not snap then return end
    local ok, q = pcall(collectQuests, snap.quests, false)
    if not ok or type(q) ~= "table" then return end
    snap.quests = q
    snap.t = time()
    ns.SetFresh(snap, "quests", "ok")
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
        stampPlayed(snap, snap)
        snap.t = time()
        snap._valid = true
        ns.SetFresh(snap, "level", "ok")
        ns.SetFresh(snap, "gold", "ok")
        ns.SetFresh(snap, "stats", "ok")
        ns.SetFresh(snap, "zone", "ok")
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
    else
        -- a later revision whose earlier row is gone: already counted, size of the change unknown
        dmg, dur = 0, 0
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

local zonePushed, zonePushedAt

local function zoneChanged()
    local zone, now = zoneText(), GetTime()
    -- The trailing call of a burst re-reads the zone; log it only if it is a different one.
    if zone ~= zonePushed or not zonePushedAt or now - zonePushedAt > 15 then
        ns.PushEvent("zone", { zone = zone })
        zonePushed, zonePushedAt = zone, now
    end
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

-- These events arrive in bursts (one BAG_UPDATE per bag, a quest-log update per kill),
-- so the handlers are plain shared functions: no closure is built per event.
local function patchBagsSoon() ns.AfterCombat("bags", ns.PatchBags) end
local function bagsChanged() ns.Debounce("bags", 10, patchBagsSoon) end

-- BAG_UPDATE_DELAYED fires once after a burst of BAG_UPDATEs; older clients only have
-- the per-bag event.
if not ns.On("BAG_UPDATE_DELAYED", bagsChanged) then ns.On("BAG_UPDATE", bagsChanged) end

local function patchQuestsSoon() ns.AfterCombat("quests", ns.PatchQuests) end

ns.On("QUEST_LOG_UPDATE", function()
    ns.Debounce("quests", 5, patchQuestsSoon)
end)

local function patchTalentsSoon() ns.AfterCombat("talents", ns.PatchTalents) end
local function talentsChanged() ns.Debounce("talents", 5, patchTalentsSoon) end

-- Forever's trait tree, then the Classic-era talent events; unknown names are skipped.
ns.On("TRAIT_CONFIG_UPDATED", talentsChanged)
ns.On("PLAYER_TALENT_UPDATE", talentsChanged)
ns.On("CHARACTER_POINTS_CHANGED", talentsChanged)

local function patchPetSoon() ns.AfterCombat("pet", ns.PatchPet) end
local function petChanged() ns.Debounce("pet", 2, patchPetSoon) end

ns.On("UNIT_PET", function(unit)
    unit = ns.Plain(unit)
    if unit == "pet" or unit == "player" or unit == nil then petChanged() end
end)
ns.On("PET_BAR_UPDATE", petChanged)
ns.On("UNIT_HAPPINESS", petChanged)

----------------------------------------------------------------------
-- Profession events: skill-ups, gathering/fishing/craft. Combat-safe:
-- UNIT_SPELLCAST_SUCCEEDED and CHAT_MSG_LOOT return at once while in combat.
----------------------------------------------------------------------
local pendingProf

local function diffSkills()
    local skills = collectSkills()
    local now = skillRankMap(skills)
    for name, rank in pairs(now) do
        local prev = lastSkillRank[name]
        if type(prev) == "number" and type(rank) == "number" and rank > prev then
            ns.PushEvent("skill_up", { skill = name, rank = rank, from = prev })
        end
    end
    lastSkillRank = now
    local c = ns.Char()
    if c.snapshot then
        c.snapshot.skills = skills
        c.snapshot.t = time()
        ns.SetFresh(c.snapshot, "professions", "ok")
    end
end

local function diffSkillsSoon() ns.AfterCombat("skills", diffSkills) end

ns.On("SKILL_LINES_CHANGED", function()
    ns.Debounce("skills", 2, diffSkillsSoon)
end)

-- The client's own format string ("Your skill in %s has increased to %d.") turned into
-- a pattern, so the line parses in every locale that keeps that argument order.
local skillUpPattern
local function skillUpMatch(msg)
    if skillUpPattern == nil then
        skillUpPattern = false
        local fmt = _G.SKILL_RANK_UP
        if type(fmt) == "string" then
            local s, d = fmt:find("%s", 1, true), fmt:find("%d", 1, true)
            if s and d and s < d then
                local pat = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
                pat = pat:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
                skillUpPattern = "^" .. pat
            end
        end
    end
    if skillUpPattern then
        local skill, rank = msg:match(skillUpPattern)
        if skill then return skill, rank end
    end
    return msg:match("Your skill in (.+) has increased to (%d+)")
end

ns.On("CHAT_MSG_SKILL", function(msg)
    msg = ns.Plain(msg)
    if type(msg) ~= "string" then return end
    local skill, rank = skillUpMatch(msg)
    if skill then
        rank = tonumber(rank)
        -- SKILL_LINES_CHANGED may already have logged this rank
        if lastSkillRank[skill] == rank then return end
        local from = lastSkillRank[skill]
        ns.PushEvent("skill_up", { skill = skill, rank = rank, from = type(from) == "number" and from or nil })
        lastSkillRank[skill] = rank
    else
        ns.PushEvent("skill_up", { raw = msg:sub(1, 80) })
    end
end)

-- Gathering spells whose name is not the skill line's name (English client).
local PROF_SPELL_SKILL = {
    ["Herb Gathering"] = "Herbalism",
    ["Smelting"] = "Mining",
    ["Disenchant"] = "Enchanting",
    ["Pick Lock"] = "Lockpicking",
}

-- The skill line a spell belongs to, by exact name only. A substring match would file
-- "Arcane Shot" under the "Arcane" class skill line and flood the event log.
local function professionOf(spellName)
    if lastSkillRank[spellName] ~= nil then return spellName end
    local skill = PROF_SPELL_SKILL[spellName]
    if skill and lastSkillRank[skill] ~= nil then return skill end
    return nil
end

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if ns.Plain(unit) ~= "player" or ns.InCombat() then return end
    spellID = ns.Plain(spellID)
    local name = ns.SpellName(spellID)
    if type(name) ~= "string" then return end
    local skill = professionOf(name)
    if not skill then return end
    pendingProf = { skill = skill, spellID = spellID, name = name, at = GetTime() }
    ns.PushEvent("profession_cast", { skill = skill, spellID = spellID, spell = name })
end)

local function lootFromProfession(msg)
    if ns.InCombat() then return end
    if not pendingProf or (GetTime() - pendingProf.at) > 3 then
        pendingProf = nil
        return
    end
    msg = ns.Plain(msg)
    if type(msg) ~= "string" then return end
    local link = msg:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)")
    ns.PushEvent("profession_loot", {
        skill = pendingProf.skill, item = link or msg:sub(1, 80),
        spellID = pendingProf.spellID,
    })
    pendingProf = nil
end

ns.On("CHAT_MSG_LOOT", lootFromProfession)
ns.On("CHAT_MSG_TRADESKILLS", lootFromProfession)

ns.On("TIME_PLAYED_MSG", function(total, level)
    total, level = ns.Plain(total), ns.Plain(level)
    if type(total) ~= "number" then return end
    local now = GetTime()
    played.total, played.at = total, now
    played.level, played.levelAt = type(level) == "number" and level or nil, now
    local c = ns.Char()
    if c.snapshot then
        c.snapshot.timePlayed = { total = total, level = played.level }
        ns.SetFresh(c.snapshot, "timePlayed", "ok")
    end
end)
