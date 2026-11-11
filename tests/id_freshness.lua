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
C_AddOns = { GetAddOnMetadata = function(_, field) return field == "Version" and "0.6.0" or nil end }
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

check("version 0.6.0", ns.version == "0.6.0" and ns.VERSION_FALLBACK == "0.6.0")
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
check("envelope fields", env.addonVersion == "0.6.0" and env.sourceRevision == "0.6.0"
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

local fails = 0
for _, l in ipairs(results) do if l:sub(1, 4) == "FAIL" then fails = fails + 1 end end
print(("== %d checks, %d failed"):format(#results, fails))
os.exit(fails == 0 and 0 or 1)
