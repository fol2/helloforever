-- /hlink probe api: asks this client, once, each API that HelloLink 0.8.0 would read
-- (the local program's rounds 4 and 5), and keeps what came back in HelloLinkDB.probe for a
-- reader of the saved data (docs/STRIP.md, section 11). Read only: it calls getters, never a
-- setter, a register or an action, and calls no other addon's function that writes or builds
-- (RXP's orphans and SkillUp's plan are only looked at). It runs all probes 10 s after login
-- and on the command; the taxi probes once when a flight master's map opens, the repair probes
-- once when a merchant opens. A secret value is named, never indexed, compared or passed on.
-- The last 8 runs are kept, newest first.
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

-- A table that is no secret, or nil: the only kind that is indexed.
local function plain(t)
    if type(t) ~= "table" or secret(t) then return nil end
    return t
end

local function map()
    local m = call("C_Map.GetBestMapForUnit", "player")
    if secret(m) or type(m) ~= "number" then return nil end
    return m
end

local function rxpStep(offset)
    local rxp = plain(rawget(_G, "RXP"))
    local guide = rxp and plain(rawget(rxp, "currentGuide"))
    local arrow = rxp and plain(rawget(rxp, "arrowFrame"))
    local element = arrow and plain(rawget(arrow, "element"))
    local step = element and plain(rawget(element, "step"))
    local index = step and rawget(step, "index")
    local steps = guide and plain(rawget(guide, "steps"))
    if secret(index) or type(index) ~= "number" or not steps then return "no guide or step" end
    local s = plain(rawget(steps, index + offset))
    if not s then return "no step " .. (index + offset) end
    local tags, first = {}, nil
    local elements = plain(rawget(s, "elements")) or {}
    for i = 1, 40 do
        local e = plain(rawget(elements, i))
        if not e then break end
        first = first or e
        tags[#tags + 1] = describe(rawget(e, "tag")) .. ":" .. describe(rawget(e, "questId"))
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
    { "repair C_TooltipInfo slot 1,5,16", function()
        local out = {}
        for _, s in ipairs({ 1, 5, 16 }) do
            local d = call("C_TooltipInfo.GetInventoryItem", "player", s)
            local t = plain(d)
            out[#out + 1] = s .. "=" .. (t and ("repairCost " .. describe(rawget(t, "repairCost")) .. " keys " .. keys(t)) or describe(d))
        end
        return table.concat(out, " ")
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
            "first " .. (function(t) return plain(t) and describe(rawget(t, 1)) or describe(t) end)(
                call("C_TaxiMap.GetTaxiNodesForMap", map()))
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
        -- GetOrphanedQuests() rewrites RXP.orphanedList: only its presence and the list as it is.
        local rxp = plain(rawget(_G, "RXP"))
        if not rxp then return "absent" end
        return "GetOrphanedQuests " .. type(rawget(rxp, "GetOrphanedQuests")),
            "orphanedList " .. describe(rawget(rxp, "orphanedList"))
    end },
    { "RXP targets", function()
        local rxp = plain(rawget(_G, "RXP"))
        local t = rxp and plain(rawget(rxp, "targeting"))
        local f = t and rawget(t, "GetCurrentTargets")
        if type(f) ~= "function" then return "absent" end
        local a, b, c, d = f()
        return "targets " .. describe(a), "mobs " .. describe(b), "scan " .. describe(c), "rares " .. describe(d)
    end },
    { "SPF Estimate", function()
        local x, y
        local m = map()
        local raw = m and call("C_Map.GetPlayerMapPosition", m, "player")
        if secret(raw) then return "position <secret>" end
        local p = plain(raw)
        if p and type(p.GetXY) == "function" then x, y = p:GetXY() end
        if secret(x) or secret(y) then return "position <secret>" end
        if type(x) ~= "number" or type(y) ~= "number" then return "no position" end
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
    -- The numeric realm folder under WTF/Account/<account>/ (93, 94 seen): which call names it?
    -- The account's own name is not asked: it is private.
    { "realm", function()
        return "GetRealmID=" .. describe(call("GetRealmID")), "GetRealmName=" .. describe(call("GetRealmName")),
            "GetNormalizedRealmName=" .. describe(call("GetNormalizedRealmName"))
    end },
    { "SkillUp", function()
        -- Professions() may build and commit a route plan on a cache miss: only looked at.
        local api = plain(path("SkillUpForever.API"))
        if not api then return "absent" end
        return "minor=" .. describe(rawget(api, "minor")), "Professions " .. type(rawget(api, "Professions")),
            "Subscribe " .. type(rawget(api, "Subscribe"))
    end },
}

-- One probe's line. Its call and the text of what came back run under one pcall; an error
-- whose text cannot be made is still a line.
local function line(p, clock)
    local t0 = clock and clock()
    local ok, text = pcall(function()
        local r = { pcall(p[2]) }
        local parts = {}
        for i = 2, #r do
            local x = r[i]
            parts[#parts + 1] = (type(x) == "string" and not secret(x)) and x or describe(x)
        end
        return (r[1] and "" or "ERROR ") .. table.concat(parts, " | ")
    end)
    local ms = clock and floor((clock() - t0) * 100 + 0.5) / 100
    return ("%s [%s ms] %s"):format(p[1], tostring(ms), ok and text or "ERROR (no text)")
end

local function meta(fn)
    local ok, text = pcall(function() return describe(fn()) end)
    return ok and text or "ERROR"
end

-- `only`: a set of probe names, or nil for all.
local function run(why, only)
    if type(_G.HelloLinkDB) ~= "table" then _G.HelloLinkDB = {} end
    local db = _G.HelloLinkDB
    db.probe = type(db.probe) == "table" and db.probe or {}
    local clock = type(_G.debugprofilestop) == "function" and _G.debugprofilestop or nil
    local results = {}
    for _, p in ipairs(PROBES) do
        if not only or only[p[1]] then results[#results + 1] = line(p, clock) end
    end
    local okAt, at = pcall(_G.time)
    table.insert(db.probe, 1, { at = okAt and not secret(at) and at or nil, why = why, map = meta(map),
        level = meta(function() return call("UnitLevel", "player") end), results = results })
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
    elseif event == "TAXIMAP_OPENED" then
        run(event, { taxi = true })
    else
        run(event, { ["repair C_TooltipInfo slot 1,5,16"] = true, GetRepairAllCost = true })
    end
end)
