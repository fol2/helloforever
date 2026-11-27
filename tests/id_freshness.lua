-- Minimal unit tests for fight IDs (and, later, freshness / quest classify).
-- Stubs only the globals Core.lua needs at load; no C_DamageMeter.
package.path = "./tests/?.lua;" .. package.path

local results = {}
local function check(name, cond)
  results[#results + 1] = (cond and "PASS " or "FAIL ") .. name
  print((cond and "PASS " or "FAIL ") .. name)
end

time = function() return 1794211200 end
GetTime = function() return 100.0 end
function GetBuildInfo() return "1.60.1", "70862", "Nov 3 2026", 16001 end
C_AddOns = { GetAddOnMetadata = function(_, field) return field == "Version" and "0.19.0" or nil end }
CreateFrame = function()
  local f = { scripts = {} }
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:RegisterEvent() end
  return f
end
C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = function() end } end }
InCombatLockdown = function() return false end
function UnitName() return "FakeHunter" end
function GetRealmName() return "TestRealm" end
HelloForeverDB = nil
_G.issecretvalue = nil
-- The client is not guaranteed to expose math.randomseed, and other addons share the RNG:
-- the install id must neither need it nor call it.
local reseeded = false
math.randomseed = function() reseeded = true end

local ns = {}
assert(loadfile("./HelloForever/Core.lua"))("HelloForever", ns)
ns.InitDB()

check("version 0.19.0", ns.version == "0.19.0" and ns.VERSION_FALLBACK == "0.19.0")
check("schemaVersion 6", ns.SCHEMA_VERSION == 6)
check("installId 8 hex", ns.InstallId():match("^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$") ~= nil)
check("install id does not reseed the shared RNG", reseeded == false)
do
  local seen, clash = {}, false
  for _ = 1, 200 do
    local v = ns.NewInstallId()
    if seen[v] or not v:match("^%x%x%x%x%x%x%x%x$") then clash = true end
    seen[v] = true
  end
  check("200 install ids in the same second are all different", not clash)
  math.randomseed = nil
  check("install id works on a client without math.randomseed", ns.NewInstallId():match("^%x%x%x%x%x%x%x%x$") ~= nil)
end
do
  -- the TOC is the release source of truth; the fallback and the revision must follow it
  local tocVersion
  for line in io.lines("./HelloForever/HelloForever.toc") do
    tocVersion = tocVersion or line:match("^##%s*Version:%s*(%S+)")
  end
  check("VERSION_FALLBACK and SOURCE_REVISION equal the TOC version (" .. tostring(tocVersion) .. ")",
    tocVersion ~= nil and ns.VERSION_FALLBACK == tocVersion and ns.SOURCE_REVISION == tocVersion)
end

local id = ns.InstallId()
local k = ns.MakeFightKey(id, 1794211200, 1, 1)
check("MakeFightKey shape", k == ("hf1-%s-1794211200-1-1"):format(id))
local p = ns.ParseFightKey(k)
check("ParseFightKey hf1", p and p.format == "hf1" and p.installId == id and p.start == 1794211200 and p.sid == 1 and p.seq == 1)

local k2 = ns.MakeFightKey(id, 1794211200, 1, 2)
check("seq 2 is a new key, not a dash suffix on unix-sid", k2 == ("hf1-%s-1794211200-1-2"):format(id) and k2 ~= k)
check("two Macs: different installId => different key",
  ns.MakeFightKey("aaaaaaaa", 1794211200, 1, 1) ~= ns.MakeFightKey("bbbbbbbb", 1794211200, 1, 1))

check("legacy two-part", ns.ParseFightKey("1794211200-1").format == "legacy"
  and ns.ParseFightKey("1794211200-1").sid == 1)
check("legacy suffix (previously rejected by wow-data)", ns.ParseFightKey("1794211200-1-2").format == "legacy_suffix"
  and ns.ParseFightKey("1794211200-1-2").seq == 2)
check("garbage is nil", ns.ParseFightKey("nope") == nil and ns.ParseFightKey("hf1-zzzzzzzz-1-1-1") == nil)

local combined = ns.FIGHT_KEY_PCRE
check("combined PCRE documented", type(combined) == "string" and combined:find("hf1", 1, true) ~= nil)

local env = ns.ExportMeta({})
check("envelope fields", env.addonVersion == "0.19.0" and env.sourceRevision == "0.19.0"
  and env.schemaVersion == 6 and env.gameBuild == "70862" and env.installId == id)

check("ClassifyQuest ready from isComplete", ns.ClassifyQuest({ inLog = true, isComplete = 1 }) == "ready")
check("ClassifyQuest in_progress", ns.ClassifyQuest({ inLog = true, isComplete = nil, objectivesDone = 3, objectivesTotal = 8 }) == "in_progress")
check("ClassifyQuest accepted", ns.ClassifyQuest({ inLog = true, isComplete = false, objectivesDone = 0, objectivesTotal = 3 }) == "accepted")
check("ClassifyQuest failed", ns.ClassifyQuest({ inLog = true, isComplete = -1 }) == "failed")
check("ClassifyQuest completed history", ns.ClassifyQuest({ inLog = false, flaggedCompleted = true }) == "completed")
check("ClassifyQuest abandoned", ns.ClassifyQuest({ inLog = false, flaggedCompleted = false, wasInLog = true }) == "abandoned")
check("ClassifyQuest unknown not guessed", ns.ClassifyQuest({ inLog = true, isComplete = nil, objectivesTotal = 0 }) == "unknown")
check("ClassifyQuest progress without a finished objective",
  ns.ClassifyQuest({ inLog = true, objectivesDone = 0, objectivesTotal = 2, progress = true }) == "in_progress")
check("ClassifyQuest all objectives finished is ready",
  ns.ClassifyQuest({ inLog = true, objectivesDone = 2, objectivesTotal = 2, progress = true }) == "ready")
check("ClassifyQuest left the log, completion unknown: unknown",
  ns.ClassifyQuest({ inLog = false }) == "unknown")

do
  local snap = {}
  ns.SetFresh(snap, "gold", "ok", 100)
  ns.SetFresh(snap, "gear", "ok", 100)
  ns.SetFresh(snap, "gold", "ok", 200)
  ns.SetFresh(snap, "gear", "stale")
  check("HashGear stable", ns.HashGear({ mainhand = "item:1" }) == ns.HashGear({ mainhand = "item:1" })
  and ns.HashGear({ mainhand = "item:1" }) ~= ns.HashGear({ mainhand = "item:2" }))

check("SetFresh gold moved, gear kept observedAt", snap.freshness.gold.observedAt == 200
    and snap.freshness.gear.observedAt == 100 and snap.freshness.gear.status == "stale")
  ns.SetFresh(snap, "pet", "unavailable")
  check("SetFresh: a section never read has no observedAt", snap.freshness.pet.status == "unavailable"
    and snap.freshness.pet.observedAt == nil)
  ns.SetFresh(snap, "pet")
  check("SetFresh: status defaults to ok and stamps now", snap.freshness.pet.status == "ok"
    and snap.freshness.pet.observedAt == 1794211200)
end

-- Since 20 Nov 2026 this client gives "" for the realm. The character keeps the key of the one
-- realm it was saved under before; with none, or more than one, the key is "Name-".
do
  local keptRealm = GetRealmName
  GetRealmName = function() return "" end
  UnitGUID = function(u) return u == "player" and "Player-1-0000AAAA" or nil end -- the client always has it
  local function keyWith(chars)
    HelloForeverDB = { characters = chars }
    local c, key = ns.Char()
    return key, c
  end
  local old = { timeline = {}, events = {}, _tlCount = 7 }
  local key, c = keyWith({ ["FakeHunter-TestRealm"] = old })
  check("realm \"\": the one saved realm keeps the key", key == "FakeHunter-TestRealm" and c == old)
  local split = { timeline = {}, events = {}, _tlCount = 2 }
  key, c = keyWith({ ["FakeHunter-TestRealm"] = old, ["FakeHunter-"] = split })
  check("realm \"\": the saved realm wins over a Name- record, which stays", key == "FakeHunter-TestRealm"
    and c == old and HelloForeverDB.characters["FakeHunter-"] == split)
  local track = { done = { [5] = { key = "k5" } }, sessions = {} }
  local oldTrack = { done = {}, sessions = {} }
  local kept, moved = { fightTrack = oldTrack }, { fightTrack = track }
  keyWith({ ["FakeHunter-TestRealm"] = kept, ["FakeHunter-"] = moved })
  check("realm \"\": the Name- record's fight read state moves to the kept record", kept.fightTrack == track
    and moved.fightTrack == nil)
  keyWith({ ["FakeHunter-TestRealm"] = kept, ["FakeHunter-"] = moved })
  check("...once: a later load leaves it", kept.fightTrack == track and moved.fightTrack == nil)
  _G.HelloLinkDB = { fullNames = { ["Player-1-0000BBBB"] = { fullName = "FakeHunter Other" } } }
  local other, mine = { fightTrack = { done = {} } }, { fightTrack = { done = {} } }
  local otherTrack = other.fightTrack
  keyWith({ ["FakeHunter-TestRealm"] = other, ["FakeHunter-"] = mine })
  check("realm \"\": with another GUID seen with the name, no read state moves (review of #280)",
    other.fightTrack == otherTrack and mine.fightTrack ~= nil)
  _G.HelloLinkDB = nil
  key = keyWith({ ["FakeHunter-TestRealm"] = old, ["FakeHunter-Unknown"] = {} })
  check("realm \"\": Name-Unknown is no saved realm", key == "FakeHunter-TestRealm")
  UNKNOWNOBJECT = "Unknown"
  UnitName = function() return "Unknown" end
  key = keyWith({ ["Unknown-TestRealm"] = {} })
  check("realm \"\": the client's placeholder name takes no saved realm", key == "Unknown-")
  UnitName = function() return "FakeHunter" end
  UNKNOWNOBJECT = nil
  key = keyWith({})
  check("realm \"\": no saved realm gives Name-", key == "FakeHunter-")
  key = keyWith({ ["FakeHunter-TestRealm"] = {}, ["FakeHunter-OtherRealm"] = {} })
  check("realm \"\": two saved realms give Name-", key == "FakeHunter-")
  key = keyWith({ ["FakeHunterTwo-TestRealm"] = {} })
  check("realm \"\": another character's realm is not taken", key == "FakeHunter-")
  UnitGUID = nil
  GetRealmName = keptRealm
  key = keyWith({ ["FakeHunter-OtherRealm"] = {} })
  check("a realm the client gives is used as it is", key == "FakeHunter-TestRealm")
end

-- spec 276, step 2 (0.19.0): each record holds the character's GUID; a record is found by it first
do
  local G1, G2 = "Player-1-0000AAAA", "Player-1-0000BBBB"
  local guid = G1
  UnitGUID = function(u) return u == "player" and guid or nil end
  local function keyWith(chars, extra)
    HelloForeverDB = { characters = chars }
    for k, v in pairs(extra or {}) do HelloForeverDB[k] = v end
    local c, key = ns.Char()
    return key, c
  end
  local old = { timeline = {}, events = {}, _tlCount = 3 }
  local key, c = keyWith({ ["FakeHunter-TestRealm"] = old })
  check("guid: an old record with no guid is claimed by name", key == "FakeHunter-TestRealm" and c == old
    and old.guid == G1 and old.guidBy == "name" and HelloForeverDB.guids.FakeHunter[G1] == true)
  local seen = HelloForeverDB.guids
  guid = G2
  key, c = keyWith({ ["FakeHunter-TestRealm"] = old }, { guids = seen })
  check("guid: another character with the name gets its own record, under its GUID", key == G2
    and c ~= old and c.guid == G2 and c.guidBy == "new" and old.guid == G1)
  guid = G1
  local moved = { timeline = {}, events = {}, _tlCount = 0, guid = G1, guidBy = "name" }
  key, c = keyWith({ ["FakeHunter-TestRealm"] = {}, ["Elsewhere"] = moved })
  check("guid: a record is found by its guid first", key == "Elsewhere" and c == moved)
  key, c = keyWith({})
  check("guid: a new character keeps the free name key", key == "FakeHunter-TestRealm"
    and c.guid == G1 and c.guidBy == "new")
  key = keyWith({ ["FakeHunter-TestRealm"] = { guid = G2 } })
  check("guid: a record that holds another guid is never taken", key == G1)
  _G.HelloLinkDB = { fullNames = { [G2] = { fullName = "FakeHunter Other" } } }
  local unclaimed = {}
  key = keyWith({ ["FakeHunter-TestRealm"] = unclaimed })
  check("guid: a name that HelloLink saw with another GUID claims nothing", key == G1 and unclaimed.guid == nil)
  _G.HelloLinkDB = nil
  local unclaimed2 = {}
  key = keyWith({ ["FakeHunter-TestRealm"] = unclaimed2 }, { guids = { FakeHunter = { [G2] = true } } })
  check("guid: a name that HelloForever saw with another GUID claims nothing", key == G1 and unclaimed2.guid == nil)
  key = keyWith({ ["FakeHunter-"] = { guid = G1, guidBy = "split", split = true } })
  check("guid: a split record alone is not found by its guid", key == "FakeHunter-TestRealm")
  _G.HelloLinkDB = nil
  GetRealmName = function() return "" end
  local kept = { timeline = {}, events = {}, _tlCount = 1 }
  local split = { timeline = {}, events = {}, _tlCount = 1, fightTrack = { done = {} } }
  local chars = { ["FakeHunter-TestRealm"] = kept, ["FakeHunter-"] = split }
  key = keyWith(chars)
  check("guid: the Name- record split from a claimed record is marked split", key == "FakeHunter-TestRealm"
    and kept.guid == G1 and split.guid == G1 and split.guidBy == "split" and split.split == true)
  key = keyWith(chars)
  check("guid: a split record is never the write record", key == "FakeHunter-TestRealm")
  GetRealmName = function() return "TestRealm" end
  guid = nil
  local before = { timeline = {}, events = {}, _tlCount = 0 }
  key = keyWith({ ["FakeHunter-TestRealm"] = before })
  check("guid: with no GUID yet, the name key as before, and nothing claimed", key == "FakeHunter-TestRealm"
    and before.guid == nil)
  guid = G1
  c, key = ns.Char()
  check("...and the next call, with the GUID, claims it (no key was kept without it)", c == before and before.guid == G1)
  UnitGUID = nil
end

do
  -- #354: the client's combat log is on by default; a stored "off" or "auto" from before is
  -- switched to "on" once (earlier versions wrote the old default, so it shows no choice)
  HelloForeverDB = nil
  ns.InitDB()
  check("combat log: a new install is on", HelloForeverDB.settings.combatLog == "on")
  for _, old in ipairs({ "off", "auto" }) do
    HelloForeverDB = { settings = { combatLog = old } }
    ns.InitDB()
    check("combat log: a stored " .. old .. " from before is switched to on, once", HelloForeverDB.settings.combatLog == "on")
  end
  HelloForeverDB.settings.combatLog = "off"
  ns.InitDB()
  check("combat log: off chosen after the switch stays off", HelloForeverDB.settings.combatLog == "off")
  HelloForeverDB = nil
end

local fails = 0
for _, l in ipairs(results) do if l:sub(1, 4) == "FAIL" then fails = fails + 1 end end
print(("== %d checks, %d failed"):format(#results, fails))
os.exit(fails == 0 and 0 or 1)
