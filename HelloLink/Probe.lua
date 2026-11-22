-- /hlink probe api: asks this client, once, each API that HelloLink 0.8.0 would read
-- (the local program's rounds 4 and 5) and that strip format 2 would read (#213), and keeps what came back in HelloLinkDB.probe for a
-- reader of the saved data (docs/STRIP.md, section 11). Read only: it calls getters, never a
-- setter, a register or an action, and calls no other addon's function that writes or builds
-- (RXP's orphans and SkillUp's plan are only looked at). It runs all probes 10 s after login
-- and on the command; the taxi probes once when a flight master's map opens, the repair probes
-- once when a merchant opens, each window's probe once a session when it opens (merchant, loot,
-- quest, trade skill: #232, part D; into HelloLinkDB.probeWindows, not `probe`); the format-2 probes once at the first target, once a second
-- into the first fight, and once in the first raid of each UI session. A secret value is named, never indexed, compared or passed on.
-- It also counts some events (`COUNTED`, "events seen"), only counted. The last 8 runs are kept, newest first.
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

-- An error's text: a string that is no secret, cut to 120 bytes; otherwise only its kind.
local function errtext(e)
    if secret(e) then return "<secret>" end
    if type(e) ~= "string" then return type(e) end
    return #e > 120 and e:sub(1, 120) .. "…" or e
end

-- Every value a call returned, in order.
local function all(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = describe((select(i, ...))) end
    return "(" .. table.concat(parts, ", ") .. ")"
end

-- "name=(values)" for each ask { path, args... }, each call alone under its own pcall, so one
-- that fails keeps the others.
local function each(asks)
    local out = {}
    for _, a in ipairs(asks) do
        local ok, text = pcall(function() return all(call(unpack(a))) end)
        out[#out + 1] = a[1] .. "=" .. (ok and text or ("ERROR " .. errtext(text)))
    end
    return table.concat(out, " ")
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
    -- part D items 4 and 5 (#232): the windows and the character, so format 3 knows what this client gives
    { "window merchant", function()
        return each({ { "GetMerchantNumItems" }, { "GetMerchantItemInfo", 1 }, { "C_MerchantFrame.GetItemInfo", 1 },
            { "GetMerchantItemLink", 1 }, { "C_MerchantFrame.GetNumJunkItems" } })
    end },
    { "window loot", function()
        return each({ { "GetNumLootItems" }, { "GetLootSlotInfo", 1 }, { "GetLootSlotLink", 1 }, { "GetLootSlotType", 1 } })
    end },
    { "window quest", function()
        return each({ { "GetQuestID" }, { "GetTitleText" }, { "GetObjectiveText" }, { "GetNumQuestRewards" },
            { "GetNumQuestChoices" }, { "GetNumQuestItems" }, { "GetRewardMoney" }, { "GetRewardXP" },
            { "GetNumAvailableQuests" }, { "GetNumActiveQuests" }, { "C_GossipInfo.GetAvailableQuests" },
            { "C_GossipInfo.GetActiveQuests" } })
    end },
    { "window trade skill", function()
        -- one recipe's details too: the first id of the list (this client's own window lists them with
        -- GetFilteredRecipeIDs), asked whether it is secret before it is passed on; under its own pcall,
        -- so a failure keeps the other answers (review of #268)
        local okR, recipes = pcall(function()
            local listed, filtered = call("C_TradeSkillUI.GetAllRecipeIDs"), call("C_TradeSkillUI.GetFilteredRecipeIDs")
            local ids = plain(filtered) or plain(listed)
            local first = ids and rawget(ids, 1)
            local recipe = secret(first) and "<secret>" or type(first) ~= "number" and "none"
                or describe(call("C_TradeSkillUI.GetRecipeInfo", first))
            return ("GetAllRecipeIDs n=%s GetFilteredRecipeIDs n=%s GetRecipeInfo(first)=%s"):format(
                tostring(count(listed)), tostring(count(filtered)), recipe)
        end)
        return each({ { "GetNumTradeSkills" }, { "GetTradeSkillLine" }, { "GetTradeSkillInfo", 1 },
            { "C_TradeSkillUI.GetTradeSkillLine" }, { "C_TradeSkillUI.GetBaseProfessionInfo" } }),
            okR and recipes or ("recipes ERROR " .. errtext(recipes))
    end },
    { "spellbook", function()
        return each({ { "GetNumSpellTabs" }, { "GetSpellTabInfo", 1 }, { "GetSpellBookItemName", 1, "spell" },
            { "C_SpellBook.GetNumSpellBookSkillLines" }, { "C_SpellBook.GetSpellBookItemName", 1, 0 } })
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
        local out = {}
        for _, name in ipairs({ "GetRealmID", "GetRealmName", "GetNormalizedRealmName" }) do
            local ok, v = pcall(call, name)        -- each alone: one that fails keeps the others
            out[#out + 1] = name .. "=" .. (ok and describe(v) or "ERROR")
        end
        return table.concat(out, " | ")
    end },
    -- Which getter gives the name with the family name ("Name Surname", as CHAT_MSG_LOOT and
    -- the WTF folders have it)? Each alone, every value it returns. A secret GUID is not passed on.
    { "fullName", function()
        -- The GUID is read under its own pcall: when it is missing, fails, is secret or no text,
        -- the two calls that need it are skipped and say why; the other three still answer.
        local guid, why
        if type(path("UnitGUID")) ~= "function" then
            why = "absent"
        else
            local ok, g = pcall(call, "UnitGUID", "player")
            if not ok then why = "ERROR"
            elseif secret(g) then why = "<secret guid>"
            elseif type(g) ~= "string" then why = "no guid"
            else guid = g end
        end
        local function from(guidFn)
            if not guid then return why end
            return guidFn()
        end
        local asks = {
            { "UnitFullName", function() return call("UnitFullName", "player") end },
            { "GetUnitName", function() return call("GetUnitName", "player", true) end },
            { "UnitNameUnmodified", function() return call("UnitNameUnmodified", "player") end },
            { "GetPlayerInfoByGUID", function() return from(function() return call("GetPlayerInfoByGUID", guid) end) end },
            { "C_PlayerInfo.GetName", function()
                return from(function()
                    local pl = plain(rawget(_G, "PlayerLocation"))
                    local make = pl and rawget(pl, "CreateFromGUID")
                    if type(make) ~= "function" or type(path("C_PlayerInfo.GetName")) ~= "function" then return "absent" end
                    return call("C_PlayerInfo.GetName", make(pl, guid))
                end)
            end },
        }
        local out = {}
        for _, a in ipairs(asks) do
            local ok, text = pcall(function() return all(a[2]()) end)
            out[#out + 1] = a[1] .. "=" .. (ok and text or "ERROR")
        end
        return table.concat(out, " | ")
    end },
    -- The Battle.net account, to tell accounts apart (owner, 22 Nov 2026), and the realm that the
    -- game account gives (GetRealmName gives "" since 20 Nov). A BattleTag is private: only its
    -- shape is given, never its text, and no table is described whole. Each call alone.
    { "account", function()
        local function tag(v)
            if secret(v) then return "<secret>" end
            if type(v) ~= "string" then return describe(v) end
            local at = v:find("#", 1, true)
            return ("<%d bytes, %s>"):format(#v, at and ("# then " .. (#v - at) .. " characters") or "no #")
        end
        local function info(t)
            if secret(t) then return "<secret>" end
            if type(t) ~= "table" then return describe(t) end
            local g = rawget(t, "gameAccountInfo")
            if type(g) ~= "table" or secret(g) then g = t end
            return ("tag %s, realmName %s, realmID %s, realmDisplayName %s"):format(tag(rawget(t, "battleTag")),
                describe(rawget(g, "realmName")), describe(rawget(g, "realmID")), describe(rawget(g, "realmDisplayName")))
        end
        local out = {}
        local ok, presence, bt = pcall(call, "BNGetInfo")
        out[1] = "BNGetInfo=" .. (not ok and "ERROR" or presence == "absent" and "absent"
            or ("presence " .. describe(presence) .. ", tag " .. tag(bt)))
        local okc, conn = pcall(call, "BNConnected")
        out[2] = "BNConnected=" .. (okc and describe(conn) or "ERROR")
        local okg, guid = pcall(call, "UnitGUID", "player")
        if not okg or secret(guid) or type(guid) ~= "string" or guid == "absent" then
            out[3] = "guid=" .. (okg and describe(guid) or "ERROR")
            return table.concat(out, " | ")
        end
        out[3] = "guid=" .. (guid:match("^Player%-%d+%-%x+$") and (guid:gsub("%x+$", "<hex>")) or "<another form>")
        for _, fn in ipairs({ "C_BattleNet.GetAccountInfoByGUID", "C_BattleNet.GetGameAccountInfoByGUID" }) do
            local okf, t = pcall(call, fn, guid)
            out[#out + 1] = fn:sub(13) .. "=" .. (okf and info(t) or "ERROR")
        end
        return table.concat(out, " | ")
    end },
    { "SkillUp", function()
        -- Professions() may build and commit a route plan on a cache miss: only looked at.
        local api = plain(path("SkillUpForever.API"))
        if not api then return "absent" end
        return "minor=" .. describe(rawget(api, "minor")), "Professions " .. type(rawget(api, "Professions")),
            "Subscribe " .. type(rawget(api, "Subscribe"))
    end },
}

-- Format 2 (#213): what a unit table, auras, cooldowns, the action bar, nameplates, the group
-- and the hunter's fields would read, each value as it comes back. Run out of combat (login,
-- the command, the first target) and once in combat, where a client may keep more secret.
local UNITS = { "player", "pet", "target", "targettarget", "pettarget", "mouseover", "focus",
    "party1", "partypet1", "raid1", "boss1" }

local function unitAsks(u)
    return each({
        { "UnitExists", u }, { "UnitGUID", u }, { "UnitName", u }, { "UnitLevel", u }, { "UnitClass", u },
        { "UnitClassification", u }, { "UnitIsDead", u }, { "UnitAffectingCombat", u },
        { "UnitCanAttack", "player", u }, { "UnitIsConnected", u }, { "UnitInRange", u },
        { "GetRaidTargetIndex", u }, { "UnitHealth", u }, { "UnitHealthMax", u }, { "UnitPower", u },
        { "UnitCastingInfo", u }, { "UnitChannelInfo", u }, { "UnitPosition", u },
        { "UnitThreatSituation", "player", u }, { "UnitGUID", u .. "target" },
    })
end

-- The native call first, then the global, each under its own pcall: a call that fails or is
-- refused keeps the other's answer.
local function aura(unit, filter)
    local ok, native = pcall(function()
        local api = path("C_UnitAuras.GetAuraDataByIndex")
        if type(api) ~= "function" then return "C_UnitAuras absent" end
        local n, first, why = 0, nil, ""
        for i = 1, 40 do
            local d = api(unit, i, filter)
            if secret(d) then why = " aura " .. i .. " <secret>"; break end -- before any compare
            if d == nil then break end
            n, first = n + 1, first or d
        end
        local t, fields = plain(first), {}
        for _, k in ipairs({ "spellId", "name", "applications", "duration", "expirationTime", "sourceUnit",
            "isFromPlayerOrPlayerPet" }) do
            if t then fields[#fields + 1] = k .. "=" .. describe(rawget(t, k)) end
        end
        return "C_UnitAuras n=" .. n .. why .. " first {" .. table.concat(fields, ", ") .. "}"
    end)
    return ok and native or ("C_UnitAuras ERROR " .. errtext(native)), each({ { "UnitAura", unit, 1, filter } })
end

local F2 = {}
-- Events that format 3 could take in place of reading on every frame (#232, part D: the action
-- bar's usable and in-range bits, another unit's cast): how often each came since the UI loaded,
-- the units of the spell-cast events, and the last arguments; "refused" when this client has no
-- such event (its RegisterEvent raises or answers false). They are only counted, on the probe's own frame (registered below).
local COUNTED = { "ACTIONBAR_UPDATE_USABLE", "ACTION_USABLE_CHANGED", "ACTION_RANGE_CHECK_UPDATE", "ACTIONBAR_UPDATE_STATE",
    "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_SLOT_CHANGED", "SPELL_UPDATE_USABLE", "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_CHANNEL_START" }
local seen = {}
local function eventsSeen()
    local out = {}
    for _, name in ipairs(COUNTED) do
        local s = seen[name]
        if type(s) ~= "table" then
            out[#out + 1] = name .. "=" .. tostring(s or "not registered")
        else
            local units = {}
            for u, n in pairs(s.units) do units[#units + 1] = u .. ":" .. n end
            table.sort(units)
            local args = {}   -- each argument described on its own: a batch of changes keeps its fields
            for i = 1, s.lastN or 0 do args[i] = describe(s.last[i]) end
            out[#out + 1] = ("%s=%d%s last %s"):format(name, s.n, #units > 0 and (" units " .. table.concat(units, ",")) or "",
                s.last and ("(" .. table.concat(args, ", ") .. ")") or "none")
        end
    end
    return table.concat(out, " | ")
end

local F2_PROBES = {}
for _, u in ipairs(UNITS) do F2_PROBES[#F2_PROBES + 1] = { "unit " .. u, function() return unitAsks(u) end } end
for _, p in ipairs({
    { "nameplates", function()
        local found, n = nil, 0
        for i = 1, 40 do
            local e = call("UnitExists", "nameplate" .. i)
            if secret(e) then return "UnitExists(nameplate" .. i .. ") <secret>" end
            if e == true or e == 1 then n = n + 1; found = found or ("nameplate" .. i) end
        end
        return "GetNamePlates n=" .. tostring(count((call("C_NamePlate.GetNamePlates")))), "units n=" .. n,
            found and (found .. " " .. unitAsks(found)) or "none"
    end },
    { "events seen", eventsSeen },
    { "auras player HELPFUL", function() return aura("player", "HELPFUL") end },
    { "auras player HARMFUL", function() return aura("player", "HARMFUL") end },
    { "auras target HELPFUL", function() return aura("target", "HELPFUL") end },
    { "auras target HARMFUL", function() return aura("target", "HARMFUL") end },
    { "cooldowns", function()
        -- the global cooldown, Auto Shot, Hunter's Mark: the native getter and the global, for each
        local out = {}
        for _, id in ipairs({ 61304, 75, 1130 }) do
            out[#out + 1] = id .. ": " .. each({ { "C_Spell.GetSpellCooldown", id }, { "GetSpellCooldown", id } })
        end
        out[#out + 1] = each({ { "C_Spell.IsAutoRepeatSpell", 75 }, { "IsAutoRepeatSpell", "Auto Shot" } })
        return table.concat(out, " | ")
    end },
    { "action bar", function()
        -- C_ActionBar's getters, and the globals the client may keep behind its fall-back setting
        local has = type(path("C_ActionBar.HasAction")) == "function" and "C_ActionBar.HasAction" or "HasAction"
        local used, out = 0, {}
        for slot = 1, 120 do
            local h = call(has, slot)
            if h == "absent" or secret(h) then return has .. " " .. describe(h) end
            if h then
                used = used + 1
                if used <= 3 then
                    local asks = {}
                    for _, name in ipairs({ "GetActionInfo", "GetActionCooldown", "IsUsableAction", "IsActionInRange",
                        "GetActionCount", "IsAutoRepeatAction", "IsCurrentAction" }) do
                        asks[#asks + 1] = { "C_ActionBar." .. name, slot }
                        asks[#asks + 1] = { name, slot }
                    end
                    asks[#asks + 1] = { "C_ActionBar.GetActionUseCount", slot } -- the native name of GetActionCount
                    out[#out + 1] = slot .. ": " .. each(asks)
                end
            end
        end
        return has .. " used in slots 1-120: " .. used, table.concat(out, " | ")
    end },
    { "group", function()
        return each({ { "IsInGroup" }, { "IsInRaid" }, { "GetNumGroupMembers" }, { "GetNumSubgroupMembers" },
            { "GetRaidRosterInfo", 1 } })
    end },
    { "hunter", function()
        local pet = {}
        for i = 1, 10 do pet[#pet + 1] = all(call("GetPetActionInfo", i)) end
        return each({ { "UnitIsFeignDeath", "player" }, { "GetShapeshiftForm" }, { "GetNumShapeshiftForms" },
            { "GetUnitSpeed", "player" }, { "PetHasActionBar" } }), "pet actions " .. table.concat(pet, " ")
    end },
    { "timers", function()
        return each({ { "GetMirrorTimerInfo", 1 }, { "GetMirrorTimerInfo", 2 }, { "GetMirrorTimerInfo", 3 },
            { "GetCorpseRecoveryDelay" } })
    end },
    { "addon cost", function()
        pcall(call, "UpdateAddOnMemoryUsage")
        return each({ { "GetAddOnMemoryUsage", "HelloLink" }, { "GetCVar", "scriptProfile" },
            { "GetAddOnCPUUsage", "HelloLink" }, { "GetFramerate" }, { "GetNetStats" } })
    end },
}) do F2_PROBES[#F2_PROBES + 1] = p end
for _, p in ipairs(F2_PROBES) do PROBES[#PROBES + 1] = p; F2[p[1]] = true end
-- UpdateAddOnMemoryUsage walks every addon: 55 to 78 ms in the game (20 Nov 2026), a stall in a
-- fight. Only the login and the command run it.
F2["addon cost"] = nil

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
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
-- each window's probe once a session when the window opens (#232, part D): once a window, not once an
-- event (a quest list opens by any of five events), into HelloLinkDB.probeWindows by its name, so a
-- window never pushes a run out of `probe` (review of #268)
local WINDOWS = { MERCHANT_SHOW = "window merchant", LOOT_OPENED = "window loot", QUEST_DETAIL = "window quest",
    QUEST_PROGRESS = "window quest", QUEST_COMPLETE = "window quest", QUEST_GREETING = "window quest",
    GOSSIP_SHOW = "window quest", TRADE_SKILL_SHOW = "window trade skill" }
for name in pairs(WINDOWS) do pcall(f.RegisterEvent, f, name) end
local windowDone = {}
local function runWindow(why, name)
    if type(_G.HelloLinkDB) ~= "table" then _G.HelloLinkDB = {} end
    local db = _G.HelloLinkDB
    db.probeWindows = type(db.probeWindows) == "table" and db.probeWindows or {}
    local clock = type(_G.debugprofilestop) == "function" and _G.debugprofilestop or nil
    for _, p in ipairs(PROBES) do
        if p[1] == name then
            local okAt, at = pcall(_G.time)
            db.probeWindows[name] = { at = okAt and not secret(at) and at or nil, why = why, map = meta(map), result = line(p, clock) }
        end
    end
end
for _, name in ipairs(COUNTED) do
    local ok, registered = pcall(f.RegisterEvent, f, name)   -- the client says false for one it lacks
    seen[name] = ok and registered ~= false and { n = 0, units = {} } or "refused"
end
-- Whether an event's run is due now: the target and the raid runs wait for a target and a raid.
local function due(event)
    if event == "PLAYER_TARGET_CHANGED" then return call("UnitExists", "target") == true end
    if event == "GROUP_ROSTER_UPDATE" then return call("IsInRaid") == true end
    return true
end
f:SetScript("OnEvent", function(_, event, ...)
    local s = seen[event]
    if type(s) == "table" then   -- only counted: the unit of a spell-cast event, and the last arguments
        s.n, s.last, s.lastN = s.n + 1, { ... }, select("#", ...)
        local u = ...
        if event:find("^UNIT_SPELLCAST") and type(u) == "string" and not secret(u) then
            u = u:match("^(%a+)") or u   -- "nameplate7" counts as "nameplate"
            s.units[u] = (s.units[u] or 0) + 1
        end
        return
    end
    local w = WINDOWS[event]
    if w then
        -- a gossip or a greeting can come with no quest: each samples once, and a quest window after
        -- it still does (the newest answer is kept; review of #268)
        local gossip = event == "GOSSIP_SHOW" or event == "QUEST_GREETING"
        local key = gossip and event or w
        -- and once a quest window sampled, a gossip after it keeps that sample (check review of #268)
        if not windowDone[key] and not (gossip and windowDone[w]) then
            windowDone[key] = true
            pcall(runWindow, event, w)
        end
        if event ~= "MERCHANT_SHOW" then return end   -- the merchant's repair run below too
    end
    if once[event] then return end
    local ok, now = pcall(due, event)
    if not ok or not now then return end
    once[event] = true
    if event == "PLAYER_REGEN_DISABLED" then
        -- a second into the fight, so a cast and the auras of the pull are there; a fight over by
        -- then is no sample, and the next fight tries again
        _G.C_Timer.After(1, function()
            local okC, fighting = pcall(call, "UnitAffectingCombat", "player")
            if okC and fighting == true then run("combat", F2) else once[event] = nil end
        end)
    elseif event == "PLAYER_TARGET_CHANGED" then
        run("target", F2)
    elseif event == "GROUP_ROSTER_UPDATE" then
        run("raid", F2)
    elseif event == "PLAYER_ENTERING_WORLD" then
        _G.C_Timer.After(10, function() run("login") end)
    elseif event == "TAXIMAP_OPENED" then
        run(event, { taxi = true })
    else
        run(event, { ["repair C_TooltipInfo slot 1,5,16"] = true, GetRepairAllCost = true })
    end
end)
