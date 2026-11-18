-- /hlink probe api: asks this client, once, each API that HelloLink 0.8.0 would read
-- (the local program's rounds 4 and 5), and keeps what came back in HelloLinkDB.probe for a
-- reader of the saved data. Read only: it calls getters, never a setter, a register or an
-- action. It also runs by itself 10 s after login and once when a flight master's map or a
-- merchant opens (taxi and repair answers can differ there). The last 8 runs are kept.
local _, ns = ...
ns = ns or {}

local KEEP, floor = 8, math.floor

local function secret(v)
    local f = _G.issecretvalue
    return type(f) == "function" and f(v) == true
end

-- A short text of any value: a secret one is never looked at, only named.
local function describe(v, depth)
    if secret(v) then return "<secret>" end
    local t = type(v)
    if t == "string" then return ("%q"):format(#v > 80 and v:sub(1, 80) .. "…" or v) end
    if t ~= "table" then return tostring(v) end
    if (depth or 0) >= 2 then return "{…}" end
    local out, n = {}, 0
    for k, x in pairs(v) do
        n = n + 1
        if n > 10 then out[#out + 1] = "…"; break end
        out[#out + 1] = describe(k, 2) .. "=" .. describe(x, (depth or 0) + 1)
    end
    return "{" .. table.concat(out, ", ") .. "}"
end

local function path(p)
    local v = _G
    for part in p:gmatch("[^.]+") do
        if type(v) ~= "table" then return nil end
        v = rawget(v, part)
    end
    return v
end

local function call(p, ...)
    local f = path(p)
    if type(f) ~= "function" then return "absent" end
    return f(...)
end

local function keys(t)
    if type(t) ~= "table" or secret(t) then return describe(t) end
    local out = {}
    for k in pairs(t) do if type(k) == "string" then out[#out + 1] = k end end
    table.sort(out)
    return table.concat(out, ",")
end

local function count(t)
    if type(t) ~= "table" or secret(t) then return describe(t) end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local tip
local function tooltip()
    tip = tip or CreateFrame("GameTooltip", "HelloLinkProbeTip", nil, "GameTooltipTemplate")
    tip:SetOwner(_G.WorldFrame, "ANCHOR_NONE")
    return tip
end

local function map() return call("C_Map.GetBestMapForUnit", "player") end

local function rxpStep(offset)
    local rxp = rawget(_G, "RXP")
    local guide = type(rxp) == "table" and rawget(rxp, "currentGuide")
    local arrow = type(rxp) == "table" and rawget(rxp, "arrowFrame")
    local element = type(arrow) == "table" and rawget(arrow, "element")
    local step = type(element) == "table" and rawget(element, "step")
    local index = type(step) == "table" and rawget(step, "index")
    local steps = type(guide) == "table" and rawget(guide, "steps")
    if type(index) ~= "number" or type(steps) ~= "table" then return "no guide or step" end
    local s = steps[index + offset]
    if type(s) ~= "table" then return "no step " .. (index + offset) end
    local tags, first = {}, nil
    for _, e in ipairs(type(s.elements) == "table" and s.elements or {}) do
        first = first or e
        if type(e) == "table" then tags[#tags + 1] = tostring(e.tag) .. ":" .. tostring(e.questId) end
    end
    return index + offset, "step keys " .. keys(s), "element keys " .. keys(first), "tags " .. table.concat(tags, " ")
end

-- name, function: each runs alone, under pcall, timed.
local PROBES = {
    -- round 4
    { "bag family 0-5", function()
        local out = {}
        for bag = 0, 5 do out[#out + 1] = bag .. "=" .. describe({ call("C_Container.GetContainerNumFreeSlots", bag) }) end
        return table.concat(out, " ")
    end },
    { "repair tooltip slot 1,5,16", function()
        local out = {}
        for _, s in ipairs({ 1, 5, 16 }) do out[#out + 1] = s .. "=" .. describe({ tooltip():SetInventoryItem("player", s) }) end
        return table.concat(out, " ")
    end },
    { "repair C_TooltipInfo slot 5", function()
        local d = call("C_TooltipInfo.GetInventoryItem", "player", 5)
        return keys(d), type(d) == "table" and describe(d.repairCost) or "-"
    end },
    { "GetRepairAllCost", function() return call("GetRepairAllCost") end },
    { "completed quests", function()
        return "C_QuestLog.GetAllCompletedQuestIDs n=" .. tostring(count((call("C_QuestLog.GetAllCompletedQuestIDs")))),
            "GetQuestsCompleted n=" .. tostring(count((call("GetQuestsCompleted")))),
            "IsQuestFlaggedCompleted(783)=" .. describe(call("C_QuestLog.IsQuestFlaggedCompleted", 783))
    end },
    { "corpse", function()
        return describe({ call("C_DeathInfo.GetCorpseMapPosition", map()) }), "UnitIsGhost=" .. describe(call("UnitIsGhost", "player"))
    end },
    { "taxi", function()
        return "NumTaxiNodes=" .. describe(call("NumTaxiNodes")),
            "GetTaxiNodesForMap n=" .. tostring(count((call("C_TaxiMap.GetTaxiNodesForMap", map())))),
            "GetAllTaxiNodes n=" .. tostring(count((call("C_TaxiMap.GetAllTaxiNodes", map())))),
            "first " .. describe((call("C_TaxiMap.GetTaxiNodesForMap", map()) or {})[1])
    end },
    { "reputation", function()
        return "GetNumFactions=" .. describe(call("GetNumFactions")),
            "GetFactionInfo(1)=" .. describe({ call("GetFactionInfo", 1) }),
            "C_Reputation.GetNumFactions=" .. describe(call("C_Reputation.GetNumFactions")),
            "C_Reputation.GetFactionDataByIndex(1)=" .. describe(call("C_Reputation.GetFactionDataByIndex", 1)),
            "watched=" .. describe({ call("GetWatchedFactionInfo") })
    end },
    { "hearth", function()
        return describe({ call("C_Item.GetItemCount", 6948) }), describe({ call("C_Container.GetItemCooldown", 6948) }),
            describe(call("GetBindLocation"))
    end },
    { "rested", function() return describe(call("GetXPExhaustion")), describe(call("IsResting")) end },
    -- round 5
    { "RXP step now", function() return rxpStep(0) end },
    { "RXP step +1", function() return rxpStep(1) end },
    { "RXP orphans", function()
        local rxp = rawget(_G, "RXP")
        local f = type(rxp) == "table" and rawget(rxp, "GetOrphanedQuests")
        if type(f) ~= "function" then return "absent" end
        return describe(f())
    end },
    { "RXP targets", function()
        local rxp = rawget(_G, "RXP")
        local t = type(rxp) == "table" and rawget(rxp, "targeting")
        local f = type(t) == "table" and rawget(t, "GetCurrentTargets")
        if type(f) ~= "function" then return "absent" end
        local a, b, c, d = f()
        return "targets " .. describe(a), "mobs " .. describe(b), "scan " .. describe(c), "rares " .. describe(d)
    end },
    { "SPF Estimate", function()
        local x, y
        local p = call("C_Map.GetPlayerMapPosition", map(), "player")
        if type(p) == "table" and p.GetXY then x, y = p:GetXY() end
        if not x then return "no position" end
        return describe({ call("ShortestPathForever.API.Estimate", map(), x, y, map(), 0.5, 0.5) })
    end },
    { "Auctionator", function()
        return "RegisterForDBUpdate " .. type(path("Auctionator.API.v1.RegisterForDBUpdate")),
            "price(2589)=" .. describe(call("Auctionator.API.v1.GetAuctionPriceByItemID", "HelloLink", 2589)),
            "age(2589)=" .. describe(call("Auctionator.API.v1.GetAuctionAgeByItemID", "HelloLink", 2589))
    end },
    { "talents", function()
        local out = { "tabs=" .. describe(call("GetNumTalentTabs")) }
        for i = 1, 3 do out[#out + 1] = i .. "=" .. describe({ call("GetTalentTabInfo", i) }) end
        return table.concat(out, " ")
    end },
    { "pet", function()
        return "happiness " .. describe({ call("GetPetHappiness") }), "xp " .. describe({ call("GetPetExperience") }),
            "HasPetUI " .. describe({ call("HasPetUI") })
    end },
    { "ammo slot 0", function()
        return describe(call("GetInventoryItemID", "player", 0)), describe(call("GetInventoryItemCount", "player", 0)),
            "AmmoSlot " .. describe({ call("GetInventorySlotInfo", "AmmoSlot") })
    end },
    { "SkillUp", function()
        local api = path("SkillUpForever.API")
        if type(api) ~= "table" then return "absent" end
        local list, why = api.Professions({ steps = 3 })
        return "minor=" .. describe(api.minor), "why=" .. describe(why), "n=" .. tostring(count(list)),
            "first " .. describe(type(list) == "table" and list[1])
    end },
}

local function run(why)
    if type(_G.HelloLinkDB) ~= "table" then _G.HelloLinkDB = {} end
    local db = _G.HelloLinkDB
    db.probe = type(db.probe) == "table" and db.probe or {}
    local clock = _G.debugprofilestop
    local results = {}
    for _, p in ipairs(PROBES) do
        local t0 = clock and clock()
        local r = { pcall(p[2]) }
        local ms = clock and floor((clock() - t0) * 100 + 0.5) / 100
        local parts = {}
        for i = 2, #r do parts[#parts + 1] = type(r[i]) == "string" and r[i] or describe(r[i]) end
        results[#results + 1] = ("%s [%s ms] %s%s"):format(p[1], tostring(ms), r[1] and "" or "ERROR ",
            table.concat(parts, " | "))
    end
    table.insert(db.probe, 1, { at = _G.time(), why = why, map = describe(map()),
        level = describe(call("UnitLevel", "player")), results = results })
    while #db.probe > KEEP do table.remove(db.probe) end
    return #results
end
ns.ProbeApi = run

local once = {}
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("TAXIMAP_OPENED")
f:RegisterEvent("MERCHANT_SHOW")
f:SetScript("OnEvent", function(_, event)
    if once[event] then return end
    once[event] = true
    if event == "PLAYER_ENTERING_WORLD" then
        _G.C_Timer.After(10, function() run("login") end)
    else
        run(event)
    end
end)
