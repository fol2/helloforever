-- The live-state strip's cost and its picture, in a stub client (#175).
-- Usage: lua tests/strip_perf_test.lua [print]
--
-- Thirty seconds of play at 60 frames a second: the character walks, the clock runs, the bags
-- change once a second, the target changes every five. Two things are held:
--   1. the picture: a sum over every square's colour after every frame equals the sum the
--      strip gave before it was made cheaper (PICTURE below; `print` shows the sum now);
--   2. the cost: the memory the strip asks for in a second of play stays under BUDGET_KB.
-- The stub is the client as tests/strip1_addon_test.lua has it, cut to what the fast block and
-- the objects read. A time is printed and not held: it depends on the machine.
local PICTURE = "968695481"
local BUDGET_KB = 20          -- a second of play; before #175 the strip asked for 133 (LuaJIT, no JIT)
local FPS, SECONDS = 60, 30

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
  function w:SetPoint(_, _, _, x, y) self.x, self.y = x or 0, y or 0 end
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
C_Container = { GetContainerNumFreeSlots = function(b) return b == 0 and P.free or 0 end,
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
-- a compressor that never makes the text shorter: the object goes as it is (format 0)
C_EncodingUtil = { CompressString = function(text) return text end }

-- ---------------- the addon ----------------
math.randomseed(7)   -- the session number and the objects' first versions
local ns = {}
local first = #frames
assert(loadfile("HelloLink/HelloLink.lua"))("HelloLink", ns)
assert(loadfile("HelloLink/Assist.lua"))("HelloLink", ns)
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

-- A sum over every square: its place in the list and its colour in sixths (the palette's
-- thirds and the digits' halves are whole sixths; the client's colours here too).
local function picture(sum)
  for i = 1, #textures do
    local t = textures[i]
    local v = t.shown and (math.floor(t.r * 6 + 0.5) * 49 + math.floor(t.g * 6 + 0.5) * 7 + math.floor(t.b * 6 + 0.5) + 1) or 0
    sum = (sum * 31 + v * (i % 251 + 1)) % 2147483647
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
if arg[1] == "print" then print("PICTURE = " .. sum) end
check("the picture is the one the strip gave before #175", tostring(sum) == PICTURE, sum)
check(("a second of play asks for under %d KB"):format(BUDGET_KB), asked < BUDGET_KB, ("%.1f KB"):format(asked))
print(("== %d checks, %d failed"):format(n, fails))
os.exit(fails == 0 and 0 or 1)
