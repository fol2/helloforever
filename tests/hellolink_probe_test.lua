-- /hlink probe api (HelloLink/Probe.lua): every probe answers, an error stays in its own
-- line, a secret value is named and never indexed, no other addon's writing function is
-- called, the window events run only their own probes, and only the last 8 runs are kept.
-- The format-2 probes (#213): each value of a unit, aura, cooldown or action as it comes back,
-- and their runs at the first target, in the first fight and in the first raid.
--   lua5.1 tests/hellolink_probe_test.lua
local fails, checks = 0, 0
local function check(ok, what)
    checks = checks + 1
    if not ok then fails = fails + 1; print("FAIL " .. what) end
end

local function boom() error("a secret value was used") end
local SECRET = setmetatable({}, { __tostring = boom, __index = boom, __eq = boom, __lt = boom, __le = boom,
    __concat = boom, __len = boom, __call = boom })
local calls, events, handler = {}, {}, nil
local function count(name) return function(...) calls[name] = (calls[name] or 0) + 1; return ... end end
_G.issecretvalue = function(v) return rawequal(v, SECRET) end
_G.time = function() return 1794516378 end
_G.debugprofilestop = os.clock
_G.C_Timer = { After = function(_, fn) fn() end }
_G.CreateFrame = function()
    return { RegisterEvent = function(_, e) events[e] = true end, SetScript = function(_, _, fn) handler = fn end }
end
_G.C_Map = { GetBestMapForUnit = function() return 1429 end, GetPlayerMapPosition = function() return SECRET end }
_G.C_Container = { GetContainerNumFreeSlots = function(bag) return 4, bag == 4 and 1 or 0 end,
    GetItemCooldown = function() return 0, 0, 1 end }
_G.C_TooltipInfo = { GetInventoryItem = function(_, slot)
    if slot == 16 then return SECRET end
    return { repairCost = slot == 5 and 1234 or 0, lines = {} }
end }
_G.C_TaxiMap = { GetTaxiNodesForMap = function() return SECRET end }
_G.C_Item = { GetItemCount = function() return 1 end }
_G.GetBindLocation = function() return SECRET end
_G.GetQuestsCompleted = function() return { [783] = true, [5] = true } end
_G.GetNumFactions = function() error(setmetatable({}, { __tostring = function() error("no text") end })) end
_G.GetNumTalentTabs = function() return 3 end
_G.UnitLevel = function() return 1 end
_G.GetRealmID = function() return 93 end
_G.GetRealmName = function() error("no name") end
_G.GetNormalizedRealmName = function() return "LivingFlame" end
_G.RXP = {
    orphanedList = { 290 },
    GetOrphanedQuests = count("GetOrphanedQuests"),
    targeting = { GetCurrentTargets = function() return { "Defias Thug" }, {}, {}, { "Mother Fang" } end },
    arrowFrame = { element = { step = { index = 2 } } },
    currentGuide = { steps = { {}, { elements = { { tag = "accept", questId = 290 }, { tag = "goto" } } }, {} } },
}
_G.Auctionator = { API = { v1 = { RegisterForDBUpdate = count("RegisterForDBUpdate"),
    GetAuctionPriceByItemID = function() return 77 end, GetAuctionAgeByItemID = function() return 2 end } } }
-- the full name (0.8.1): each getter alone; a secret GUID is never passed on
local guidSecret, passed = false, {}
_G.UnitGUID = function() return guidSecret and SECRET or "Player-1-0000ABCD" end
_G.UnitFullName = function() return "Fake", "LivingFlame" end
_G.GetUnitName = function(_, withRealm) if withRealm == true then error("no name") end return "Fake" end
_G.GetPlayerInfoByGUID = function(g)
    passed[#passed + 1] = g
    return "Hunter", "HUNTER", "Night Elf", "NightElf", 3, "Fake Family", ""
end
_G.PlayerLocation = { CreateFromGUID = function(_, g) passed[#passed + 1] = g; return { guid = g } end }
_G.C_PlayerInfo = { GetName = function() return SECRET end }
-- format 2 (0.8.2)
local targetOn, raid = true, false
_G.UnitExists = function(u)
    return u == "player" or (u == "target" and targetOn) or u == "nameplate3"
end
_G.UnitName = function() return "Fake" end
_G.UnitHealth = function() return SECRET end
_G.UnitHealthMax = function() return 100 end
_G.UnitPosition = function() error("no position") end
_G.IsInRaid = function() return raid end
_G.C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter)
    if unit == "player" and filter == "HELPFUL" and i == 1 then
        return { spellId = 13165, name = "Aspect of the Hawk", applications = 0, expirationTime = SECRET }
    end
    if unit == "target" and filter == "HARMFUL" and i == 1 then return SECRET end
end }
_G.HasAction = function(slot) return slot == 2 or slot == 5 end
_G.GetActionInfo = function(slot) return "spell", 75, "spell" end
_G.GetActionCooldown = function() return SECRET end
_G.SkillUpForever = { API = { minor = 6, Professions = count("Professions"), Subscribe = count("Subscribe") } }

local ns = {}
assert(loadfile("HelloLink/Probe.lua"))("HelloLink", ns)
check(type(ns.ProbeApi) == "function", "the probe is exported")
check(events.PLAYER_ENTERING_WORLD and events.TAXIMAP_OPENED and events.MERCHANT_SHOW and events.PLAYER_TARGET_CHANGED
    and events.PLAYER_REGEN_DISABLED and events.GROUP_ROSTER_UPDATE, "the six events are registered")
handler(nil, "PLAYER_ENTERING_WORLD")
local db = _G.HelloLinkDB
check(type(db) == "table" and #db.probe == 1 and db.probe[1].why == "login" and db.probe[1].at == 1794516378,
    "a login run is kept, with its time")
local r = db.probe[1].results
check(#r == 43, "forty-three probes answer, got " .. #r)
local function line(name, rs)
    for _, l in ipairs(rs or r) do if l:sub(1, #name) == name then return l end end
    return ""
end
check(line("bag family 0-5"):find("4={1=4, 2=1}", 1, true) ~= nil, "bag 4's family is read: " .. line("bag family"))
local repair = line("repair C_TooltipInfo")
check(repair:find("5=repairCost 1234", 1, true) and repair:find("16=<secret>", 1, true) and not repair:find("ERROR"),
    "the repair cost is read, a secret tooltip named: " .. repair)
check(line("hearth"):find("<secret>", 1, true) ~= nil, "a secret bind is named, not read: " .. line("hearth"))
check(line("taxi"):find("first <secret>", 1, true) and not line("taxi"):find("ERROR"), "a secret taxi list is not indexed: " .. line("taxi"))
check(line("SPF Estimate"):find("position <secret>", 1, true) ~= nil, "a secret position is named, not used: " .. line("SPF"))
check(line("reputation"):find("ERROR", 1, true) ~= nil, "an error whose text fails stays in its own line: " .. line("reputation"))
check(line("talents"):find("tabs=3", 1, true) ~= nil, "the next probe still answers: " .. line("talents"))
check(line("completed quests"):find("GetQuestsCompleted n=2", 1, true) ~= nil, "completed quests are counted")
check(line("RXP step now"):find('"accept":290', 1, true) ~= nil, "the step's tags are read: " .. line("RXP step now"))
check(line("RXP orphans"):find("orphanedList {1=290}", 1, true) ~= nil, "the orphans are read as they are: " .. line("RXP orphans"))
check(line("RXP targets"):find("Mother Fang", 1, true) ~= nil, "RXP's targets are read")
check(line("Auctionator"):find("price(2589)=77", 1, true) ~= nil, "an auction price is read")
check(line("realm"):find('GetRealmID=93 | GetRealmName=ERROR | GetNormalizedRealmName="LivingFlame"', 1, true) ~= nil,
    "the realm id and names are read, each alone: " .. line("realm"))
check(line("SkillUp"):find("minor=6", 1, true) ~= nil, "SkillUp's API is looked at")
check(line("fullName"):find('UnitFullName=("Fake", "LivingFlame") | GetUnitName=ERROR | UnitNameUnmodified=("absent") | '
    .. 'GetPlayerInfoByGUID=("Hunter", "HUNTER", "Night Elf", "NightElf", 3, "Fake Family", "") | C_PlayerInfo.GetName=(<secret>)',
    1, true) ~= nil, "the full-name getters answer, each alone, a secret named: " .. line("fullName"))
check(#passed == 2 and passed[1] == "Player-1-0000ABCD" and passed[2] == "Player-1-0000ABCD", "the GUID is passed to the two that take it")
-- format 2: each value alone, a secret named, an error in its own place
local tl = line("unit target")
check(tl:find('UnitExists=(true) UnitGUID=("Player-1-0000ABCD") UnitName=("Fake") UnitLevel=(1)', 1, true)
    and tl:find("UnitHealth=(<secret>) UnitHealthMax=(100)", 1, true) and tl:find("UnitPosition=ERROR UnitThreatSituation=", 1, true)
    and tl:find("UnitInRange=(\"absent\")", 1, true), "a unit's values each answer alone, a secret named, an error kept in its place: " .. tl)
check(line("unit focus"):find("UnitExists=(false)", 1, true) ~= nil, "a unit that is not there says so: " .. line("unit focus"))
check(line("unit player"):find('UnitGUID=("Player-1-0000ABCD")', 1, true) ~= nil, "the unit's target is asked: " .. line("unit player"))
local ah = line("auras player HELPFUL")
check(ah:find("C_UnitAuras n=1 first {spellId=13165, name=\"Aspect of the Hawk\", applications=0, duration=nil, expirationTime=<secret>", 1, true) ~= nil,
    "an aura's fields are read, a secret one named: " .. ah)
local th = line("auras target HARMFUL")
check(th:find("C_UnitAuras n=0 aura 1 <secret> first {}", 1, true) and not th:find("ERROR", 1, true),
    "a secret aura is named and never indexed: " .. th)
local ab = line("action bar")
check(ab:find("used 2 | 2: GetActionInfo=(\"spell\", 75, \"spell\") GetActionCooldown=(<secret>)", 1, true)
    and ab:find("| 5: GetActionInfo", 1, true), "the used action slots are read, a secret cooldown named: " .. ab)
check(line("nameplates"):find("units n=1 | nameplate3 UnitExists=(true)", 1, true) ~= nil, "the first nameplate is read as a unit: " .. line("nameplates"))
check(line("cooldowns"):find('GetSpellCooldown=("absent")', 1, true) ~= nil and line("hunter") ~= "" and line("addon cost") ~= "",
    "the cooldown, hunter and cost lines answer")
guidSecret, passed = true, {}
ns.ProbeApi("command")
check(#passed == 0 and line("fullName", db.probe[1].results):find("GetPlayerInfoByGUID=(\"<secret guid>\")", 1, true) ~= nil,
    "a secret GUID is named and never passed on: " .. line("fullName", db.probe[1].results))
guidSecret = false
table.remove(db.probe, 1)
-- review round 1: a UnitGUID that is missing or fails skips the two calls that need it, and the
-- three unit-based answers stay
local realGuid = _G.UnitGUID
local UNIT_THREE = 'UnitFullName=("Fake", "LivingFlame") | GetUnitName=ERROR | UnitNameUnmodified=("absent") | '
for _, case in ipairs({ { "missing", nil, "absent" }, { "failing", function() error("no guid") end, "ERROR" } }) do
    _G.UnitGUID, passed = case[2], {}
    ns.ProbeApi("command")
    local l = line("fullName", db.probe[1].results)
    check(#passed == 0 and l:find(UNIT_THREE .. 'GetPlayerInfoByGUID=("' .. case[3] .. '") | C_PlayerInfo.GetName=("' .. case[3] .. '")', 1, true) ~= nil,
        "a " .. case[1] .. " UnitGUID skips the GUID calls and keeps the other three: " .. l)
    table.remove(db.probe, 1)
end
_G.UnitGUID = realGuid
check(next(calls) == nil, "no writing or building function of another addon is called")
handler(nil, "PLAYER_ENTERING_WORLD")
check(#db.probe == 1, "one login run a session")
handler(nil, "TAXIMAP_OPENED")
check(#db.probe[1].results == 1 and line("taxi", db.probe[1].results) ~= "", "a flight master runs the taxi probe only")
handler(nil, "MERCHANT_SHOW")
check(#db.probe[1].results == 2 and line("GetRepairAllCost", db.probe[1].results) ~= "", "a merchant runs the repair probes only")
-- the format-2 runs: once at the first target, a second into the first fight, in the first raid
local function f2run(why) return db.probe[1].why == why and #db.probe[1].results == 22 and line("unit target", db.probe[1].results) ~= ""
    and line("taxi", db.probe[1].results) == "" end
local runs = #db.probe
targetOn = false
handler(nil, "PLAYER_TARGET_CHANGED")
check(#db.probe == runs, "a target change with no target runs nothing")
targetOn = true
handler(nil, "PLAYER_TARGET_CHANGED")
check(f2run("target"), "the first target runs the format-2 probes only")
handler(nil, "PLAYER_TARGET_CHANGED")
check(#db.probe == runs + 1, "once a session")
handler(nil, "PLAYER_REGEN_DISABLED")
check(f2run("combat"), "the first fight runs the format-2 probes only")
handler(nil, "GROUP_ROSTER_UPDATE")
check(db.probe[1].why == "combat", "a group change out of a raid runs nothing")
raid = true
handler(nil, "GROUP_ROSTER_UPDATE")
check(f2run("raid"), "the first raid runs the format-2 probes only")
_G.UnitLevel = function() return setmetatable({}, { __pairs = boom, __index = boom }) end
local realPairs = pairs
pairs = function(t) if getmetatable(t) and getmetatable(t).__pairs then error("cannot format") end return realPairs(t) end
ns.ProbeApi("command")
pairs = realPairs
check(db.probe[1].why == "command" and db.probe[1].level == "ERROR" and #db.probe[1].results == 43,
    "a metadata value that cannot be formatted is ERROR, and the run is kept")
for _ = 1, 10 do ns.ProbeApi("command") end
check(#db.probe == 8 and db.probe[1].why == "command" and #db.probe[1].results == 43, "the last 8 runs are kept, newest first")
print(("== %d checks, %d failed"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
