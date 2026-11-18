-- /hlink probe api (HelloLink/Probe.lua): every probe answers, an error stays in its own
-- line, a secret value is named and never indexed, no other addon's writing function is
-- called, the window events run only their own probes, and only the last 8 runs are kept.
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
_G.RXP = {
    orphanedList = { 290 },
    GetOrphanedQuests = count("GetOrphanedQuests"),
    targeting = { GetCurrentTargets = function() return { "Defias Thug" }, {}, {}, { "Mother Fang" } end },
    arrowFrame = { element = { step = { index = 2 } } },
    currentGuide = { steps = { {}, { elements = { { tag = "accept", questId = 290 }, { tag = "goto" } } }, {} } },
}
_G.Auctionator = { API = { v1 = { RegisterForDBUpdate = count("RegisterForDBUpdate"),
    GetAuctionPriceByItemID = function() return 77 end, GetAuctionAgeByItemID = function() return 2 end } } }
_G.SkillUpForever = { API = { minor = 6, Professions = count("Professions"), Subscribe = count("Subscribe") } }

local ns = {}
assert(loadfile("HelloLink/Probe.lua"))("HelloLink", ns)
check(type(ns.ProbeApi) == "function", "the probe is exported")
check(events.PLAYER_ENTERING_WORLD and events.TAXIMAP_OPENED and events.MERCHANT_SHOW, "the three events are registered")
handler(nil, "PLAYER_ENTERING_WORLD")
local db = _G.HelloLinkDB
check(type(db) == "table" and #db.probe == 1 and db.probe[1].why == "login" and db.probe[1].at == 1794516378,
    "a login run is kept, with its time")
local r = db.probe[1].results
check(#r == 19, "nineteen probes answer, got " .. #r)
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
check(line("SPF Estimate"):find("no position", 1, true) ~= nil, "a secret position is not used: " .. line("SPF"))
check(line("reputation"):find("ERROR", 1, true) ~= nil, "an error whose text fails stays in its own line: " .. line("reputation"))
check(line("talents"):find("tabs=3", 1, true) ~= nil, "the next probe still answers: " .. line("talents"))
check(line("completed quests"):find("GetQuestsCompleted n=2", 1, true) ~= nil, "completed quests are counted")
check(line("RXP step now"):find('"accept":290', 1, true) ~= nil, "the step's tags are read: " .. line("RXP step now"))
check(line("RXP orphans"):find("orphanedList {1=290}", 1, true) ~= nil, "the orphans are read as they are: " .. line("RXP orphans"))
check(line("RXP targets"):find("Mother Fang", 1, true) ~= nil, "RXP's targets are read")
check(line("Auctionator"):find("price(2589)=77", 1, true) ~= nil, "an auction price is read")
check(line("SkillUp"):find("minor=6", 1, true) ~= nil, "SkillUp's API is looked at")
check(next(calls) == nil, "no writing or building function of another addon is called")
handler(nil, "PLAYER_ENTERING_WORLD")
check(#db.probe == 1, "one login run a session")
handler(nil, "TAXIMAP_OPENED")
check(#db.probe[1].results == 1 and line("taxi", db.probe[1].results) ~= "", "a flight master runs the taxi probe only")
handler(nil, "MERCHANT_SHOW")
check(#db.probe[1].results == 2 and line("GetRepairAllCost", db.probe[1].results) ~= "", "a merchant runs the repair probes only")
for _ = 1, 10 do ns.ProbeApi("command") end
check(#db.probe == 8 and db.probe[1].why == "command" and #db.probe[1].results == 19, "the last 8 runs are kept, newest first")
print(("== %d checks, %d failed"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
