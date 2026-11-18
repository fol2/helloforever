-- /hlink probe api (HelloLink/Probe.lua): every probe answers, an error stays in its own
-- line, a secret value is named and never read, and only the last 8 runs are kept.
--   lua5.1 tests/hellolink_probe_test.lua
local fails, checks = 0, 0
local function check(ok, what)
    checks = checks + 1
    if not ok then fails = fails + 1; print("FAIL " .. what) end
end

local SECRET = setmetatable({}, { __tostring = function() error("a secret value was read") end,
    __index = function() error("a secret value was read") end })
local handlers = {}
_G.issecretvalue = function(v) return v == SECRET end
_G.time = function() return 1794516378 end
_G.debugprofilestop = os.clock
_G.C_Timer = { After = function(_, fn) fn() end }
_G.WorldFrame = {}
_G.CreateFrame = function()
    return { RegisterEvent = function() end, SetScript = function(_, _, fn) handlers.event = fn end,
        SetOwner = function() end, SetInventoryItem = function() return true, false, 1234 end }
end
_G.C_Map = { GetBestMapForUnit = function() return 1429 end, GetPlayerMapPosition = function()
    return { GetXY = function() return 0.4, 0.6 end } end }
_G.C_Container = { GetContainerNumFreeSlots = function(bag) return 4, bag == 4 and 1 or 0 end,
    GetItemCooldown = function() return 0, 0, 1 end }
_G.C_Item = { GetItemCount = function() return 1 end }
_G.GetBindLocation = function() return SECRET end
_G.GetQuestsCompleted = function() return { [783] = true, [5] = true } end
_G.GetNumFactions = function() error("no reputation here") end
_G.UnitLevel = function() return 1 end

local ns = {}
assert(loadfile("HelloLink/Probe.lua"))("HelloLink", ns)
check(type(ns.ProbeApi) == "function", "the probe is exported")
handlers.event(nil, "PLAYER_ENTERING_WORLD")
local db = _G.HelloLinkDB
check(type(db) == "table" and #db.probe == 1 and db.probe[1].why == "login", "a login run is kept")
local r = db.probe[1].results
check(#r == 20, "twenty probes answer, got " .. #r)
local function line(name)
    for _, l in ipairs(r) do if l:sub(1, #name) == name then return l end end
    return ""
end
check(line("bag family 0-5"):find('4={1=4, 2=1}', 1, true) ~= nil, "bag 4's family is read: " .. line("bag family"))
check(line("repair tooltip"):find("1234", 1, true) ~= nil, "the tooltip's repair cost is read")
check(line("hearth"):find("<secret>", 1, true) ~= nil, "a secret bind is named, not read: " .. line("hearth"))
check(line("reputation"):find("ERROR", 1, true) ~= nil, "an error stays in its own line")
check(line("talents"):find("ERROR", 1, true) == nil, "the next probe still runs")
check(line("completed quests"):find("GetQuestsCompleted n=2", 1, true) ~= nil, "completed quests are counted")
check(line("RXP step now"):find("no guide", 1, true) ~= nil, "no RXP is said")
handlers.event(nil, "PLAYER_ENTERING_WORLD")
check(#db.probe == 1, "one login run a session")
for _ = 1, 10 do ns.ProbeApi("command") end
check(#db.probe == 8 and db.probe[1].why == "command", "the last 8 runs are kept")
print(("== %d checks, %d failed"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
