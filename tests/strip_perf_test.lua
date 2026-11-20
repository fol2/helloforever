-- The live-state strip's cost and its picture, in a stub client (#175).
-- Usage: lua tests/strip_perf_test.lua [print]
--
-- Thirty seconds of play at 60 frames a second: the character walks, the clock runs, the bags
-- change once a second, the target changes every five, and the client's compressor fails for
-- the first eight seconds. Two things are held:
--   1. the picture: a sum over every square's colour after every frame equals the sum the
--      strip gave before it was made cheaper, with what was added since (PICTURE below;
--      `print` shows the sum now);
--   2. the cost: the memory the strip asks for in a second of play stays under BUDGET_KB.
-- The stub is the client as tests/strip1_addon_test.lua has it, cut to what the fast block and
-- the objects read. A time is printed and not held: it depends on the machine.
-- 1130383108 until #180; object 18 (the hearthstone) joined the carousel. With it left out of
-- the carousel (IDS 17) the sum is still 1130383108: only the new object changed the frames.
-- 1608759021 until 0.8.0: objects 19 to 23 joined, and object 15's containers gained "family".
-- With IDS 18 and the family left out of object 15 the sum is still 1608759021.
-- 846925534 until 0.8.1: object 10 gained "fullName" and "fullNameSource", object 11's steps
-- "elements". With those three left out the sum is still 846925534.
local PICTURE = "1415256988"
local BUDGET_KB = 20          -- a second of play; before #175 the strip asked for 133 (LuaJIT, no JIT), 449 (Lua 5.5)
local FPS, SECONDS = 60, 30

if jit then jit.off() end   -- luacheck: ignore 113 (LuaJIT: a compiled trace asks for memory of its own)

local fails, n = 0, 0
local function check(name, cond, detail)
  n = n + 1; if not cond then fails = fails + 1 end
  print((cond and "PASS " or "FAIL ") .. name .. (not cond and detail and ("\n  got: " .. tostring(detail)) or ""))
end

-- ---------------- the stub client ----------------
local now, wall = 1000.0, 1794516378
GetTime = function() return now end
time = function() return wall end
SlashCmdList = {}
C_Timer = { After = function() end }
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
issecretvalue = function(v) return v == SECRET end
GetPhysicalScreenSize = function() return 2560, 1440 end

local textures, frames = {}, {}
local function widget()
  local w = { shown = true, x = 0, y = 0, r = -1, g = -1, b = -1 }
  for _, m in ipairs({ "SetFrameStrata", "SetFrameLevel", "ClearAllPoints", "RegisterEvent", "UnregisterEvent" }) do w[m] = function() end end
  function w:SetScript(kind, fn) self[kind] = fn end
  function w:GetEffectiveScale() return 0.7 end
  function w:SetSize(a, b) self.w, self.h = a, b end
  function w:SetPoint(point, to, toPoint, x, y) self.point, self.to, self.toPoint, self.x, self.y = point, to, toPoint, x or 0, y or 0 end
  function w:SetColorTexture(r, g, b) self.r, self.g, self.b = r, g, b end
  function w:Show() self.shown = true end
  function w:Hide() self.shown = false end
  function w:CreateTexture() local t = widget(); t.parent = self; textures[#textures + 1] = t; return t end
  return w
end
CreateFrame = function() local f = widget(); frames[#frames + 1] = f; return f end
UIParent = widget()

local P = { health = 868, healthMax = 1158, power = 1100, powerMax = 1335, level = 29, xp = 2004, xpMax = 64000,
  money = 7800, x = 0.5, free = 12 }
local T = { name = "Wetlands Crocolisk", level = 23, health = 99, healthMax = 803 }
UnitExists = function(u) return u == "player" or u == "target" or u == "pet" or u == "targettarget" end
UnitHealth = function() return SECRET end
UnitHealthMax = function(u) if u == "target" then return SECRET end return u == "pet" and 1355 or P.healthMax end
UnitPower = function() return SECRET end
UnitPowerMax = function() return P.powerMax end
UnitPowerType = function() return 2 end
UnitLevel = function(u) return u == "target" and T.level or P.level end
UnitXP = function() return P.xp end
UnitXPMax = function() return P.xpMax end
UnitAffectingCombat = function() return true end
UnitIsDeadOrGhost = function() return false end
UnitIsDead = function() return false end
IsMounted = function() return false end
IsResting = function() return false end
IsIndoors = function() return false end
IsSwimming = function() return false end
IsFlying = function() return false end
ChatEdit_GetActiveWindow = function() return nil end
UnitIsAFK = function() return false end
UnitGUID = function(u) if u == "player" then return "Player-1-0000ABCD" end return "Creature-0-1-1-1-1984-0000ABCDEF" end
UnitReaction = function() return 4 end
UnitName = function(u) return u == "target" and T.name or "FakeHunter" end
GetRealmName = function() return "TestRealm" end
UnitCanAttack = function() return true end
UnitClassification = function() return "normal" end
UnitCreatureType = function() return "Beast" end
UnitIsTapDenied = function() return false end
UnitIsPlayer = function() return false end
UnitIsUnit = function(a, b) return a == "targettarget" and b == "pet" end
UnitDetailedThreatSituation = function(u) if u == "player" then return false, 1, 57.6, 60, 1000 end return true, 3, 100, 100, 5000 end
UnitCastingInfo = function() end
UnitChannelInfo = function() end
C_Map = { GetBestMapForUnit = function() return 1437 end,
  GetPlayerMapPosition = function() return { GetXY = function() return P.x, 0.25 end } end }
GetPlayerFacing = function() return math.pi / 2 end
GetMoney = function() return P.money end
local BAG = { { itemID = 2318, stackCount = 14 }, { itemID = 4234, stackCount = 3 } }
C_Container = { GetContainerNumFreeSlots = function(b) return b == 0 and P.free or 0, 0 end,   -- free, the family (0.8.0)
  GetContainerNumSlots = function(b) return b == 0 and 16 or 0 end,
  GetContainerItemInfo = function(b, s) return b == 0 and BAG[s] or nil end }
GetInventoryItemID = function(_, slot) if slot == 0 then return nil end return 2504 end
GetInventoryItemLink = function() return "|cff9d9d9d|Hitem:2504::::::::29:::::|h[x]|h|r" end
GetInventoryItemDurability = function() return 50, 60 end
UnitClass = function() return "Hunter", "HUNTER", 3 end
UnitRace = function() return "Night Elf", "NightElf", 4 end
GetWeaponEnchantInfo = function() return true, 598400, 0, 0 end
GetRealZoneText = function() return "Wetlands" end
GetSubZoneText = function() return "Black Channel Marsh" end
IsInInstance = function() return false, "none" end
GetInstanceInfo = function() return "Eastern Kingdoms", "none", 0, "", 0, 0, false, 0, 0 end
Enum = { LuaCurveType = { Step = 1 }, BankType = { Character = 0, Guild = 1, Account = 2 } }
CreateColor = function(r, g, b, a) return { GetRGBA = function() return r, g, b, a end } end
C_CurveUtil = { CreateColorCurve = function()
  local c = { pts = {} }
  function c:SetType() end
  function c:AddPoint(x, colour) self.pts[#self.pts + 1] = { x, colour } end
  function c:at(v) local best = self.pts[1][2]; for _, p in ipairs(self.pts) do if p[1] <= v then best = p[2] end end return best end
  return c
end }
UnitHealthPercent = function(u, _, curve)
  if u == "target" then return curve:at(T.health / T.healthMax) end
  if u == "pet" then return curve:at(1258 / 1355) end
  return curve:at(P.health / P.healthMax)
end
UnitPowerPercent = function(_, _, _, curve) return curve:at(P.power / P.powerMax) end
local QUESTS = { { isHeader = true, title = "Wetlands" },
  { questID = 471, title = "Apprentice's Duties", objectives = { { text = "Giant Crocolisk Skin: 3/6", finished = false, numFulfilled = 3, numRequired = 6 } } } }
C_QuestLog = { GetNumQuestLogEntries = function() return #QUESTS end, GetInfo = function(i) return QUESTS[i] end,
  GetQuestObjectives = function(id) for _, q in ipairs(QUESTS) do if q.questID == id then return q.objectives end end end,
  IsFailed = function() return false end }
local SKILLS = { { isHeader = true, name = "Professions" }, { name = "Skinning", skillRank = 120, skillMaxRank = 150, skillID = 393 } }
C_SkillInfo = { GetNumSkillLines = function() return #SKILLS end, GetSkillLineInfo = function(i) return SKILLS[i] end }
C_AddOns = { LoadAddOn = function() HelloLink_Inbox = { seq = 0, text = "" }; return true end }
-- A compressor that fails for the first eight seconds and then gives a shorter text (not a
-- real Deflate stream: the strip does not look inside). The objects go as they are at first
-- (format 0), and the same texts go again compressed, as new versions, once it answers.
C_EncodingUtil = { CompressString = function(text)
  if now < 1008 then error("the compressor is busy") end
  return text:sub(2)
end }

-- ---------------- the addon ----------------
-- The session number and the objects' first versions: one sequence in every Lua (math.random
-- gives another in Lua 5.1 than in LuaJIT for the same seed).
local seed = 7
math.random = function(low, high)   -- luacheck: ignore 122
  seed = seed * 16807 % 2147483647
  return low + seed % (high - low + 1)
end
local ns = {}
local first = #frames
assert(loadfile("HelloLink/HelloLink.lua"))("HelloLink", ns)
assert(loadfile("HelloLink/Assist.lua"))("HelloLink", ns)
assert(loadfile("HelloLink/Strip2.lua"))("HelloLink", ns)   -- before Strip.lua, as in the TOC
assert(loadfile("HelloLink/Strip.lua"))("HelloLink", ns)
local events, row
for i = first + 1, #frames do
  if frames[i].OnEvent then events = frames[i] end
end
events.OnEvent(events, "ADDON_LOADED", "HelloLink")
for i = first + 1, #frames do
  if frames[i].OnUpdate then row = frames[i] end
end
assert(row, "the strip's row")

-- A sum over every square as it is on the screen: where it is and how large (in thousandths
-- of a UI unit; a square hangs by its top left corner from the row's), whether it and the row
-- are shown, and its colour in sixths (the palette's
-- thirds and the digits' halves are whole sixths; the client's colours here too).
local function picture(sum)
  sum = (sum * 31 + (row.shown and 1 or 0) + math.floor(row.x * 1000 + 0.5) * 3 + math.floor(-row.y * 1000 + 0.5) * 5
    + ((row.point == "TOPLEFT" and row.toPoint == "TOPLEFT" and row.to == UIParent) and 0 or 104729)) % 2147483647   -- the row hangs by its top left corner from the screen's
  for i = 1, #textures do
    local t = textures[i]
    local v = t.shown and (math.floor(t.r * 6 + 0.5) * 49 + math.floor(t.g * 6 + 0.5) * 7 + math.floor(t.b * 6 + 0.5) + 1) or 0
    local at = math.floor(t.x * 1000 + 0.5) + math.floor(-t.y * 1000 + 0.5) * 7 + math.floor((t.w or 0) * 1000 + 0.5) * 11
      + math.floor((t.h or 0) * 1000 + 0.5) * 13
      + ((t.point == "TOPLEFT" and t.toPoint == "TOPLEFT" and t.to == row) and 0 or 104729)
    sum = (sum * 31 + v * (at % 65521 + 1)) % 2147483647
  end
  return sum
end

local function frame(k)
  now = now + 1 / FPS
  if k % FPS == 0 then
    wall = wall + 1
    P.free = 12 - (k / FPS) % 3
    events.OnEvent(events, "BAG_UPDATE")
    if (k / FPS) % 5 == 0 then
      T.name = (k / FPS) % 10 == 0 and "Wetlands Crocolisk" or "Mottled Raptor"
      events.OnEvent(events, "PLAYER_TARGET_CHANGED")
    end
  end
  if k % (2 * FPS) < FPS then P.x = 0.3 + (k % 997) / 4000 end   -- walks for a second, stands for a second
  row.OnUpdate(row, 1 / FPS)
end

local sum = 0
for k = 1, 5 * FPS do frame(k) sum = picture(sum) end        -- the first seconds: every object is built
collectgarbage("collect")
collectgarbage("stop")
local kb = collectgarbage("count")
local spent = 0
for k = 5 * FPS + 1, (5 + SECONDS) * FPS do
  local c = os.clock()
  frame(k)
  spent = spent + os.clock() - c
  sum = picture(sum)
end
local asked = (collectgarbage("count") - kb) / SECONDS
collectgarbage("restart")

print(("the strip: %.1f KB asked for in a second of play, %.2f ms of work in a second of play"):format(asked, spent / SECONDS * 1000))

-- ---------------- the same play with the 0.8.0 sources full (review of #192) ----------------
-- A guide of 30 steps (RXP and its saved progress, orphans, targets), 60 reputations, 480
-- completed quests, Auctionator with a price for each item, sixteen items in the bags, a pet.
-- The memory a second and the slowest frame are printed; the memory is held to FULL_KB.
local FULL_KB = 30
do
  local reads = { rep = 0, done = 0, ah = 0, targets = 0 }
  local steps = {}
  for i = 1, 30 do
    local elements = {}
    for e = 1, 8 do elements[e] = { tag = e % 2 == 0 and "accept" or "goto", questId = 1000 + i * 10 + e, zone = 1437, x = 40, y = 50 } end
    elements[9] = { tag = "isQuestTurnedIn", questIds = { 2000 + i, 2001 + i } }
    steps[i] = { index = i, text = ("Kill |cFFFF5722Young Tigers|r and go north %d "):format(i):rep(5), elements = elements, completed = i < 5 }
  end
  RXP = { currentGuide = { name = "29-32 Duskwood", key = "RXP|Duskwood", steps = steps },
    arrowFrame = { element = { zone = 1437, x = 40, y = 50, step = steps[5] } },
    orphanedList = { [783] = { questID = 783 }, [33] = { questID = 33 }, [7] = { questID = 7 } },
    targeting = { GetCurrentTargets = function() reads.targets = reads.targets + 1 return { "Defias Thug" }, { "Murloc", "Raptor" }, {}, {} end } }
  RXPCData = { guideProgress = { ["RXP|Duskwood"] = { step = 5 } } }
  local reps = {}
  for i = 1, 60 do reps[i] = { factionID = i, name = "Faction " .. i, reaction = 4 + i % 4, currentStanding = i * 100,
    currentReactionThreshold = 0, nextReactionThreshold = 9000, isWatched = i == 3, isHeader = i % 10 == 1 } end
  C_Reputation = { GetNumFactions = function() reads.rep = reads.rep + 1 return #reps end, GetFactionDataByIndex = function(i) return reps[i] end }
  local done = {}
  for i = 1, 480 do done[i] = 480 * 3 - i * 3 end
  C_QuestLog.GetAllCompletedQuestIDs = function() reads.done = reads.done + 1 return done end
  local onScan
  Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, id) return id * 7 end,
    GetAuctionAgeByItemID = function(_, id) if id == 3003 then reads.ah = reads.ah + 1 end return 1 end, RegisterForDBUpdate = function(_, fn) onScan = fn end } } }
  for i = 3, 16 do BAG[i] = { itemID = 3000 + i, stackCount = i } end
  HasPetUI = function() return true, true end
  GetPetExperience = function() return 1200, 5600 end
  C_DeathInfo = { GetCorpseMapPosition = function() return nil end }
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", true, false)
  local base = 35 * FPS
  local function fullFrame(k)
    if k % (3 * FPS) == 0 then events.OnEvent(events, "UPDATE_FACTION") end
    if k % (5 * FPS) == 0 and onScan then onScan() end
    frame(k)
  end
  for k = base + 1, base + 5 * FPS do fullFrame(k) end
  collectgarbage("collect")
  collectgarbage("stop")
  local fullKb, slowest, fullSpent = collectgarbage("count"), 0, 0
  for k = base + 5 * FPS + 1, base + (5 + SECONDS) * FPS do
    local c = os.clock()
    fullFrame(k)
    local d = os.clock() - c
    fullSpent, slowest = fullSpent + d, math.max(slowest, d)
  end
  local fullAsked = (collectgarbage("count") - fullKb) / SECONDS
  collectgarbage("restart")
  print(("full sources: %.1f KB asked for in a second of play, %.2f ms of work in a second, the slowest frame %.2f ms")
    :format(fullAsked, fullSpent / SECONDS * 1000, slowest * 1000))
  check(("each full source was read (reputations %d, completed quests %d, Auctionator %d, targets %d)"):format(reads.rep, reads.done, reads.ah, reads.targets),
    reads.rep > 1 and reads.done == 1 and reads.ah > 1 and reads.targets > 1)
  check(("with the 0.8.0 sources full a second of play asks for under %d KB"):format(FULL_KB), fullAsked < FULL_KB, ("%.1f KB"):format(fullAsked))
end
-- ---------------- format 2 against format 1 (docs/specs/213.md, section 12) ----------------
-- The same play, 30 s in each format, one after the other: format 2 asks for no more memory a
-- second than format 1. The picture
-- above is held with format 1 only.
do
  local function measure(base)
    for k = base + 1, base + 5 * FPS do frame(k) end
    collectgarbage("collect")
    collectgarbage("stop")
    local before, work = collectgarbage("count"), 0
    for k = base + 5 * FPS + 1, base + (5 + SECONDS) * FPS do
      local c = os.clock()
      frame(k)
      work = work + os.clock() - c
    end
    local kb = (collectgarbage("count") - before) / SECONDS
    collectgarbage("restart")
    return kb, work / SECONDS * 1000
  end
  local one, oneMs = measure(80 * FPS)
  ns.StripSet("format", "2")
  local two, twoMs = measure(120 * FPS)
  ns.StripSet("format", "1")
  print(("format 1: %.1f KB, %.2f ms a second; format 2: %.1f KB, %.2f ms a second"):format(one, oneMs, two, twoMs))
  check("format 2 asks for no more memory a second than format 1", two <= one, ("%.1f KB against %.1f KB"):format(two, one))
end
if arg[1] == "print" then print("PICTURE = " .. sum) end
check("the picture is PICTURE: the strip of before #175, with object 18 since #180 and objects 19 to 23 since 0.8.0, the 0.8.1 fields", tostring(sum) == PICTURE, sum)
check(("a second of play asks for under %d KB"):format(BUDGET_KB), asked < BUDGET_KB, ("%.1f KB"):format(asked))
print(("== %d checks, %d failed"):format(n, fails))
os.exit(fails == 0 and 0 or 1)
