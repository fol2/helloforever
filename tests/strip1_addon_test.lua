-- The live-state strip, format 1: the addon draws a row in a stub client, and the Python
-- reader (tools/strip1.py, through `hellolink_strip.py rows`) reads it back.
-- Usage: lua tests/strip1_addon_test.lua <scratch dir>
--
-- The stub is the client as plan/05 recorded it on 12 Nov 2026 where that is known: health
-- and power are secret, their maxima are not; squares asked for in physical pixels are
-- exact; the client colours a square from a step colour curve at a per cent of 0 to 1.
-- ASSUMED, not seen in the game: the event names, the fields of C_Container, C_QuestLog and
-- C_SkillInfo, the shapes of UnitCastingInfo and GetWeaponEnchantInfo, what CompressString
-- returns (here a raw Deflate stream made by Python), and everything about timing.
local DIR = assert(arg[1], "usage: strip1_addon_test.lua <scratch dir>")
local out = {}
print_real = print
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end out[#out + 1] = table.concat(t, " ") end
local fails, n = 0, 0
local function check(name, cond, detail)
  n = n + 1; if not cond then fails = fails + 1 end
  print_real((cond and "PASS " or "FAIL ") .. name .. (not cond and detail and ("\n  got: " .. tostring(detail)) or ""))
end
local function sh(cmd) local p = assert(io.popen(cmd .. " 2>&1")); local s = p:read("*a"); p:close(); return s end

-- ---------------- the stub client ----------------
local now = 1000.0
GetTime = function() return now end
time = function() return 1794516378 end
SlashCmdList = {}
C_Timer = { After = function() end }
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
issecretvalue = function(v) return v == SECRET end
GetPhysicalScreenSize = function() return 2560, 1440 end

local textures, frames = {}, {}
local function widget()
  local w = { shown = true, x = 0, y = 0 }
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

-- the character
local P = { health = 868, healthMax = 1158, power = 1100, powerMax = 1335, level = 29, xp = 2004, xpMax = 64000,
  money = 7800, casting = nil, target = true, pet = true, combat = true }
INSTANCE = { inside = false, kind = "none", name = "Eastern Kingdoms", map = 0 }
local T = { name = "Wetlands Crocolisk", level = 23, health = 99, healthMax = 803, class = "normal", kind = "Beast",
  guid = "Creature-0-1-1-1-1984-0000ABCDEF", reaction = 4 }
local secretMax = false
UnitExists = function(u) return u == "player" or (u == "target" and P.target) or (u == "pet" and P.pet) or (u == "targettarget" and P.target) end
UnitHealth = function(u) return SECRET end
UnitHealthMax = function(u) if u == "target" or secretMax then return SECRET end return u == "pet" and 1355 or P.healthMax end
UnitPower = function() return SECRET end
UnitPowerMax = function() return P.powerMax end
UnitPowerType = function() return 2 end
UnitLevel = function(u) return u == "target" and T.level or P.level end
UnitXP = function() return P.xp end
UnitXPMax = function() return P.xpMax end
GetXPExhaustion = function() return P.rested end
-- the hearthstone (object 18, #180): one in the bags, bound in Gadgetzan, ready
P.hearths, P.bind = 1, "Gadgetzan"
GetBindLocation = function() return P.bind end
GetItemCount = function(id) if id == 6948 then return P.hearths end return 0 end
UnitAffectingCombat = function() return P.combat end
UnitIsDeadOrGhost = function() return false end
UnitIsDead = function() return false end
IsMounted = function() return false end
IsResting = function() return false end
IsIndoors = function() return P.indoors end
IsSwimming = function() return P.swimming end
IsFlying = function() return P.flying end
ChatEdit_GetActiveWindow = function() return P.chat end
UnitIsAFK = function() return false end
UnitGUID = function(u) if u == "player" then return "Player-1-0000ABCD" end if u == "target" then return T.guid end end
UnitReaction = function(u, other) if u == "target" and other == "player" then return T.reaction end end
UnitName = function(u) return u == "target" and T.name or "FakeHunter" end
GetRealmName = function() return "TestRealm" end
UnitCanAttack = function() return true end
UnitClassification = function() return T.class end
UnitCreatureType = function() return T.kind end
UnitIsTapDenied = function() return false end
UnitIsPlayer = function() return false end
UnitIsUnit = function(a, b) return a == "targettarget" and b == "pet" end
UnitDetailedThreatSituation = function(u) if u == "player" then return false, 1, 57.6, 60, 1000 end return true, 3, 100, 100, 5000 end
UnitCastingInfo = function() if P.casting then return "Aimed Shot", nil, nil, now * 1000 - 500, now * 1000 + 1650, false, nil, false, 19434 end end
UnitChannelInfo = function() end
C_Map = { GetBestMapForUnit = function() return 1437 end,
  GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.25 end } end }
GetPlayerFacing = function() return math.pi / 2 end
GetMoney = function() return P.money end
local BAGS = { [0] = { { itemID = 2318, stackCount = 14 }, { itemID = 4234, stackCount = 3 }, { itemID = 2318, stackCount = 2 } } }
GEAR, LINKS, DUR = {}, {}, {}   -- the gear of object 14: by slot, an item id (false: empty), a link, durability (false: none)
-- the second value is the bag's family (0.8.0): 0 any item; FAMILY[bag] = 1 a quiver, "none" no second value
FAMILY = {}
C_Container = { GetContainerNumFreeSlots = function(b)
    local free = b == 0 and (P.free or 12) or b == 5 and BAGS[5] and 6 or 0
    if FAMILY[b] == "none" then return free end
    return free, FAMILY[b] or 0
  end,
  GetContainerNumSlots = function(b) return b == 0 and 48 or b == 5 and BAGS[5] and 8 or b == 6 and BAGS[6] and 98 or 0 end,
  GetContainerItemInfo = function(b, s) return BAGS[b] and BAGS[b][s] end }
C_Container.GetItemCooldown = function(id)
  local c = P.hcd or { 0, 0, 1 }
  if c == "gcd" then return now, 1.5, 1 end   -- a global cooldown that goes on: a spell cast again and again
  if c == "fails" then error("not now") end
  return c[1], c[2], c[3]
end
GetInventoryItemCount = function(_, slot) if slot == 0 then return P.ammoCount or 200 end return 1 end   -- 0.8.0: the ammunition's count
GetInventoryItemID = function(_, slot) if slot == 0 then return P.ammo end if GEAR[slot] == nil then return 2504 end return GEAR[slot] or nil end   -- slot 0: ammunition
GetInventoryItemLink = function(_, slot) return LINKS[slot] or ("|cff9d9d9d|Hitem:%d::::::::29:::::|h[x]|h|r"):format(2504) end
GetInventoryItemDurability = function(slot) local d = DUR[slot] if d == false then return nil, nil end return (d or { 50, 60 })[1], (d or { 50, 60 })[2] end
UnitClass = function() return "Hunter", "HUNTER", 3 end
UnitRace = function() return "Night Elf", "NightElf", 4 end
C_Bank = { FetchPurchasedBankTabIDs = function(kind) return kind == 0 and { 6 } or {} end }
GetWeaponEnchantInfo = function() return true, 598400, 0, 0 end
GetRealZoneText = function() return "Wetlands" end
GetSubZoneText = function() return "Black Channel Marsh" end
IsInInstance = function() return INSTANCE.inside, INSTANCE.kind end
GetInstanceInfo = function() return INSTANCE.name, INSTANCE.kind, 0, "", 0, 0, false, INSTANCE.map, 0 end
-- the client colours a square from a step curve at the unit's per cent (0 to 1)
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
-- the quest log and the skill lines, as the client's own functions give them
local QUESTS = {
  { isHeader = true, title = "Wetlands" },
  { questID = 471, title = "Apprentice's Duties", objectives = { { text = "Giant Crocolisk Skin: 3/6", finished = false, numFulfilled = 3, numRequired = 6 } } },
  { questID = 290, title = "Lifting the Curse", objectives = { { text = "Speak with \"Glorin\"", finished = false, numFulfilled = 0, numRequired = 0 } } },
  { questID = 305, title = "In Search of The Excavation Team", objectives = { { text = "Find the team", finished = true, numFulfilled = 1, numRequired = 1 } } },
  { questID = 999, title = "No Objectives", objectives = {} },
}
C_QuestLog = { GetNumQuestLogEntries = function() return #QUESTS end, GetInfo = function(i) return QUESTS[i] end,
  GetQuestObjectives = function(id) for _, q in ipairs(QUESTS) do if q.questID == id then return q.objectives end end end,
  IsFailed = function() return false end }
-- 0.8.0: the completed quests (object 19), the corpse (20), the reputations (21), the pet (23)
DONE, DONE_CALLS = { 783, 7, 33 }, 0
C_QuestLog.GetAllCompletedQuestIDs = function() DONE_CALLS = DONE_CALLS + 1 return DONE end
C_DeathInfo = { GetCorpseMapPosition = function() return P.corpse end }
REPS = { { factionID = 72, name = "Stormwind", reaction = 6, currentStanding = 3200, currentReactionThreshold = 3000,
  nextReactionThreshold = 9000, isWatched = true, isHeader = false }, { name = "Alliance", isHeader = true, isWatched = false } }
C_Reputation = { GetNumFactions = function() return #REPS end, GetFactionDataByIndex = function(i) return REPS[i] end }
P.petUI, P.petXp = true, { 1200, 5600 }
HasPetUI = function() return P.petUI, true end
GetPetExperience = function() return P.petXp[1], P.petXp[2] end
local SKILLS = { { isHeader = true, name = "Professions" }, { name = "Skinning", skillRank = 120, skillMaxRank = 150, skillID = 393 },
  { name = "Leatherworking", skillRank = 75, skillMaxRank = 150, skillID = 165 } }
C_SkillInfo = { GetNumSkillLines = function() return #SKILLS end, GetSkillLineInfo = function(i) return SKILLS[i] end }
-- the slots that carry text into the game
local slotFile = { seq = 0, text = "" }   -- a slot as `tools/hellolink.py install` leaves it
C_AddOns = { LoadAddOn = function() if not slotFile then return false, "MISSING" end HelloLink_Inbox = slotFile; return true end }

-- ---------------- the addon ----------------
local function load()
  local ns = {}
  local first = #frames
  assert(loadfile("HelloLink/HelloLink.lua"))("HelloLink", ns)
  local assist = loadfile("HelloLink/Assist.lua")   -- 0.2.0 (#127); the looks' checks below need it
  if assist then assist("HelloLink", ns) end
  assert(loadfile("HelloLink/Strip.lua"))("HelloLink", ns)
  local events
  for i = first + 1, #frames do if frames[i].OnEvent then events = frames[i] end end
  events.OnEvent(events, "ADDON_LOADED", "HelloLink")
  local row
  for i = first + 1, #frames do if frames[i].OnUpdate then row = frames[i] end end
  return ns, events, row
end
local ns, events, row = load()
local function slash(m) out = {}; SlashCmdList["HELLOLINK"](m) return table.concat(out, "\n") end
local function tick(dt) now = now + dt; row.OnUpdate(row, dt) end
local unit = 768 / 1440 / 0.7

local shots = 0
local function dump()
  local path = ("%s/row_%03d"):format(DIR, shots)
  shots = shots + 1
  local f = assert(io.open(path .. ".txt", "w"))
  for _, t in ipairs(textures) do
    if t.shown and t.parent.shown and t.parent == row and t.r then
      f:write(("%.9g %.9g %.9g %.9g %.6f %.6f %.6f\n"):format(t.parent.x + t.x, -(t.parent.y + t.y), t.w, t.h, t.r, t.g, t.b))
    end
  end
  f:close()
  return path .. ".txt"
end
-- The frames are drawn and read by the Rust reader, one process a call, not one a frame (#95):
-- it prints the lines tests/render_rows.py prints, byte for byte (#195), about 40 times faster
-- (#193). `sh tests/run_all.sh` builds it first.
local function read(paths, step)
  return sh(("reader/target/release/hellolink render-rows --scale %.12f --step %g %s"):format(1 / unit, step or 0.1,
    table.concat(paths, " ")))
end
local function has(text, piece) return text:find(piece, 1, true) ~= nil end

-- ---------------- one frame ----------------
tick(0.1)
local one = read({ dump() })
local session = HelloLinkDB.session
check("the row is read: session, depth 4, a frame that passes its check", has(one, '"row": true') and has(one, ('"session": %d'):format(session))
  and has(one, '"depth": 4') and has(one, '"why": null') and has(one, '"dwell": 10'))
check("the level squares: health 868/1158, power 1100/1335, target 99/803, pet 1258/1355 read 75, 83, 12, 93", has(one, '"levels": [75, 83, 12, 93]'))
check("the maxima that are not secret are numbers; the target's are not in the frame at all",
  has(one, '"health": {"healthMax": 1158}') and has(one, '"power": {"powerMax": 1335, "powerType": 2}') and has(one, '"pet": {"healthMax": 1355}'))
check("level, XP, money, free slots", has(one, '"level": {"level": 29, "xp": 2004, "xpMax": 64000}') and has(one, '"purse": {"bagFree": 12, "money": 7800}'))
check("state flags: in combat, has target, has pet", has(one, ('"state": {"flags": %d}'):format(128 + 2 + 1)))
do
  -- Indoors 512, swimming 1024, flying 2048 (#101).
  local function flags()
    tick(0.1)
    local f = read({ dump() }):match('"state": {"flags": (%d+)}')
    return f and tonumber(f), read({ dump() }):find('"state": null', 1, true) ~= nil
  end
  P.indoors = true
  check("indoors is 512", flags() == 128 + 2 + 1 + 512)
  P.indoors, P.swimming = false, true
  check("swimming is 1024", flags() == 128 + 2 + 1 + 1024)
  P.swimming, P.flying = false, true
  check("flying is 2048", flags() == 128 + 2 + 1 + 2048)
  P.flying = false
  local realFly = IsFlying
  IsFlying = nil
  local f, unknown = flags()
  check("a missing function counts as false: the group stays readable", f == 128 + 2 + 1 and not unknown)
  IsFlying = function() return SECRET end
  -- A comparison with nil or a `not` before the ask cannot be observed: Lua runs no metamethod
  -- for them. The flag goes through `read`, which asks first, as every other flag does.
  local log, realSecret, realType = {}, issecretvalue, type
  issecretvalue = function(v) if v == SECRET then log[#log + 1] = "asked" end return realSecret(v) end
  type = function(v) if v == SECRET then log[#log + 1] = "typed" end return realType(v) end
  local _, gone = flags()
  issecretvalue, type = realSecret, realType
  check("a secret flag makes the state group unknown, asked about and never typed (" .. table.concat(log, " "):sub(1, 30) .. ")",
    gone and #log >= 1 and not table.concat(log, " "):find("typed", 1, true))
  IsFlying = function() error("no") end
  local _, failed = flags()
  check("a failing flag makes the state group unknown", failed)
  IsFlying = realFly
  check("... and readable again", flags() == 128 + 2 + 1)
  -- A chat input open, 8192 (#131): the active edit box, or nil. Missing or failing: unknown.
  P.chat = { name = "ChatFrame1EditBox" }
  check("a chat input open is 8192", flags() == 128 + 2 + 1 + 8192)
  P.chat = nil
  check("...and closed it is not", flags() == 128 + 2 + 1)
  local realChat = ChatEdit_GetActiveWindow
  ChatEdit_GetActiveWindow = nil
  local _, noChat = flags()
  check("without the client's function the state group is unknown, not 'closed'", noChat)
  ChatEdit_GetActiveWindow = function() error("no") end
  local _, badChat = flags()
  check("a failing call makes it unknown too", badChat)
  ChatEdit_GetActiveWindow = function() return SECRET end
  local _, secretChat = flags()
  check("a secret answer makes it unknown", secretChat)
  ChatEdit_GetActiveWindow = realChat
  check("... and readable again", flags() == 128 + 2 + 1)
end
local s1, s2 = 0, 0
for c in ("Wetlands Crocolisk"):gmatch(".") do s1 = (s1 + c:byte()) % 255; s2 = (s2 + s1) % 255 end
check("the target: level, hostile and attacking the pet, the hash of its name (the check of section 7 over the name)",
  has(one, ('"target": {"flags": 129, "level": 23, "nameHash": %d}'):format(s1 * 256 + s2)))
check("threat: 57.6 is 58, the pet's 100", has(one, '"threat": {"pet": 100, "player": 58}'))
check("position: map, the middle and a quarter, facing a quarter turn", has(one, '"position": {"facing": 64, "map": 1437, "x": 32768, "y": 16384}'))
check("the main hand and its enchant's seconds, rounded up", has(one, '"hand": {"enchant": 599, "item": 2504}'))
check("no cast: the cast group is unknown", has(one, '"cast": null'))

-- ---------------- the fast state changes ----------------
local before = tonumber(one:match('"seq": (%d+)'))
-- nothing changes while one chunk stays on the row: a dwell of 1 s, and three reads of the fast state
local reads = 0
local realMoney = GetMoney
GetMoney = function() reads = reads + 1; return realMoney() end
slash("strip dwell 100")
tick(1.0); tick(0.1)                              -- a chunk has just gone up; it stays for a second
local first = read({ dump() })
local readsBefore = reads
tick(0.1); tick(0.1); tick(0.1)
local same = read({ dump() })
check("the fast state was read again three times, nothing had changed, and the same seq stays up",
  reads >= readsBefore + 3 and first:match('"seq": (%d+)') ~= nil and same:match('"seq": (%d+)') == first:match('"seq": (%d+)')
  and same:match('"chunk": (%b[])') == first:match('"chunk": (%b[])'))
before = tonumber(same:match('"seq": (%d+)'))
GetMoney = realMoney
slash("strip dwell 10")
P.casting, P.money = true, 7900
events.OnEvent(events, "LOOT_OPENED")
-- As the client gave it on 13 Nov 2026: the name has a family name that UnitName does not
-- have ("FakeHunter Family" against "FakeHunter"), there is no realm, and argument 12 is the player's GUID.
events.OnEvent(events, "CHAT_MSG_LOOT", "You receive loot: |cnIQ1:|Hitem:2318::::::::30:1485:::::::::|h[Light Leather]|h|rx2.",
  "FakeHunter Family", "", "", "FakeHunter Family", "", 0, 0, "", 0, 1, "Player-1-0000ABCD")
events.OnEvent(events, "CHAT_MSG_LOOT", "Bob Other receives loot: |Hitem:999:|h[Thing]|h|r.",
  "Bob Other", "", "", "Bob Other", "", 0, 0, "", 0, 2, "Player-1-0BBBBBBB")
events.OnEvent(events, "UI_ERROR_MESSAGE", 50, "Out of range.")
tick(0.1)
local changed = read({ dump() })
check("a cast: the spell and tenths left (1.65 s is 17, rounded up), and the casting flag",
  has(changed, '"cast": {"spell": 19434, "tenths": 17}') and has(changed, ('"state": {"flags": %d}'):format(128 + 4 + 2 + 1 + 256)))
check("loot: one item received (another player's is not counted), its id and quantity; the loot window flag",
  has(changed, '"loot": {"counter": 1, "item": 2318, "quantity": 2}'))
check("a UI error: its number and a count", has(changed, '"uiError": {"counter": 1, "error": 50}'))
check("the seq went up", tonumber(changed:match('"seq": (%d+)')) > before)
P.casting = nil
events.OnEvent(events, "LOOT_CLOSED")

-- ---------------- a secret value is unknown, never a number ----------------
secretMax = true
tick(0.1)
local hidden = read({ dump() })
check("a maximum the client keeps secret makes its group unknown", has(hidden, '"health": null') and has(hidden, '"pet": null'))
secretMax = false

-- ---------------- the carousel ----------------
-- 3.2 s (32 steps) is a round of the objects 2 to 23 and a little more (2.5 s before 0.8.0).
local function watch(steps)
  local paths = {}
  for _ = 1, steps do tick(0.1); paths[#paths + 1] = dump() end
  return read(paths)
end
events.OnEvent(events, "PLAYER_ENTERING_WORLD", true, false)   -- the login, as the client sends it after the UI loads: object 19 is read then
local round = watch(50)   -- a round of the twenty-two objects 2 to 23, and some of the next
check("the target object, with the creature's id and its reaction to the player (#82)",
  has(round, '[2, 0, "{\\"name\\": \\"Wetlands Crocolisk\\", \\"type\\": \\"Beast\\", \\"class\\": \\"normal\\", \\"level\\": 23, \\"id\\": 1984, \\"reaction\\": 4}"]'))
do
  -- The id is the sixth part of a creature's or a vehicle's GUID; the reaction a whole number 1 to 8.
  local guid, reaction = T.guid, T.reaction
  local function target(g, r)
    T.guid, T.reaction = g, r
    events.OnEvent(events, "PLAYER_TARGET_CHANGED")
    local last
    for id, re in watch(32):gmatch('\\"level\\": 23, \\"id\\": ([%w]+), \\"reaction\\": ([%w]+)}') do last = id .. " " .. re end
    return last
  end
  check("a vehicle has an id too; a hostile reaction", target("Vehicle-0-1-1-1-777-0000ABCDEF", 2) == "777 2")
  check("a player, a pet and a GUID of another shape have no id",
    target("Player-1-0000ABCD", 5) == "null 5" and target("Pet-0-1-1-1-5678-0000ABCDEF", 5) == "null 5"
    and target("Creature-0-1-1-1-x-0000ABCDEF", 5) == "null 5" and target("Creature-1984", 5) == "null 5" and target(1984, 5) == "null 5")
  check("an id of 9 digits is given; one of 10 digits, one with a leading zero, and a GUID cut short or too long are null",
    target("Creature-0-1-1-1-123456789-0000ABCDEF", 5) == "123456789 5" and target("Creature-0-1-1-1-1234567890-0000ABCDEF", 5) == "null 5"
    and target("Creature-0-1-1-1-01984-0000ABCDEF", 5) == "null 5" and target("Creature-0-1-1-1-1984-", 5) == "null 5"
    and target("Creature-0-1-1-1-1984-0000ABCDEF-extra", 5) == "null 5")
  check("reactions 1 and 8, the ends of the range, are given", target(guid, 1) == "1984 1" and target(guid, 8) == "1984 8")
  check("a reaction that is no whole number from 1 to 8 is null",
    target(guid, 0) == "1984 null" and target(guid, 9) == "1984 null" and target(guid, 2.5) == "1984 null" and target(guid, "4") == "1984 null" and target(guid, nil) == "1984 null")
  -- The order of the calls: the GUID and the reaction are asked about straight after they are
  -- read, and a `type` of them before that is seen. A comparison with nil or a `not` before the
  -- ask is not seen: Lua runs no metamethod for them, so no test can observe one. Both values
  -- go through `get`, which asks first.
  local log, realSecret, realType, realGuid, realReaction = {}, issecretvalue, type, UnitGUID, UnitReaction
  UnitGUID = function(u) if u == "target" then log[#log + 1] = "read" return SECRET end return realGuid(u) end
  UnitReaction = function() log[#log + 1] = "read" return SECRET end
  issecretvalue = function(v) if log[#log] == "read" and v == SECRET then log[#log + 1] = "asked" end return realSecret(v) end
  type = function(v) if v == SECRET then log[#log + 1] = "typed" end return realType(v) end
  local secret = target(guid, reaction)
  UnitGUID, UnitReaction, issecretvalue, type = realGuid, realReaction, realSecret, realType
  local good = #log >= 4
  for i = 1, #log, 2 do if log[i] ~= "read" or log[i + 1] ~= "asked" then good = false end end
  check("a secret GUID and a secret reaction are null, each asked about straight after it is read (" .. table.concat(log, " "):sub(1, 40) .. ")",
    good and secret == "null null")
  check("... and they are back when the client gives them again", target(guid, reaction) == "1984 4")
end
check("the place object, with the instance's facts: none here (#91)",
  has(round, '[3, 0, "{\\"map\\": 1437, \\"zone\\": \\"Wetlands\\", \\"sub\\": \\"Black Channel Marsh\\", \\"instance\\": false, \\"instanceType\\": \\"none\\", \\"instanceMap\\": 0, \\"instanceName\\": \\"Eastern Kingdoms\\"}"]'))
do
  local function place()
    events.OnEvent(events, "PLAYER_ENTERING_WORLD")
    local last
    for found in watch(40):gmatch('\\"sub\\": \\"Black Channel Marsh\\", (\\"instance\\": .-)}"]') do last = found end
    return last and last:gsub('\\"', "'")
  end
  INSTANCE = { inside = true, kind = "party", name = "The Deadmines", map = 36 }
  check("in a dungeon: true, party, its map id and its name",
    place() == "'instance': true, 'instanceType': 'party', 'instanceMap': 36, 'instanceName': 'The Deadmines'")
  INSTANCE = { inside = true, kind = "raid two", name = "bad \255", map = 70000 }
  check("a type that is not a word, a name that is not UTF-8 and a map id out of range are null",
    place() == "'instance': true, 'instanceType': null, 'instanceMap': null, 'instanceName': null")
  INSTANCE = { inside = true, kind = "party", name = "The Deadmines", map = 36.5 }
  check("a map id that is no whole number is null", place():find("'instanceMap': null", 1, true) ~= nil)
  local realIn, realInfo = IsInInstance, GetInstanceInfo
  IsInInstance, GetInstanceInfo = nil, nil
  check("with no such functions the four keys are null, and the place object stays",
    place() == "'instance': null, 'instanceType': null, 'instanceMap': null, 'instanceName': null")
  IsInInstance = function() return SECRET, "party" end
  GetInstanceInfo = function() return "The Deadmines", SECRET, 0, "", 0, 0, false, 36, 0 end
  check("a secret value makes that function's keys null, not the place object",
    place() == "'instance': null, 'instanceType': null, 'instanceMap': null, 'instanceName': null")
  -- The order of the calls: a secret value is asked about before a `type` of it. (A
  -- comparison with nil cannot be observed in Lua.)
  local log, realSecret, realType = {}, issecretvalue, type
  issecretvalue = function(v) if v == SECRET then log[#log + 1] = "asked" end return realSecret(v) end
  type = function(v) if v == SECRET then log[#log + 1] = "typed" end return realType(v) end
  place()
  issecretvalue, type = realSecret, realType
  check("a secret instance value is asked about and never typed (" .. table.concat(log, " "):sub(1, 40) .. ")",
    #log >= 2 and not table.concat(log, " "):find("typed", 1, true))
  -- Each function on its own: one that fails, or gives a value of the wrong type.
  IsInInstance = function() error("no") end
  GetInstanceInfo = realInfo
  INSTANCE = { inside = true, kind = "party", name = "The Deadmines", map = 36 }
  check("an IsInInstance that fails leaves `instance` null, and the others",
    place() == "'instance': null, 'instanceType': 'party', 'instanceMap': 36, 'instanceName': 'The Deadmines'")
  IsInInstance, GetInstanceInfo = realIn, function() error("no") end
  check("a GetInstanceInfo that fails leaves its three keys null, and `instance`",
    place() == "'instance': true, 'instanceType': null, 'instanceMap': null, 'instanceName': null")
  IsInInstance, GetInstanceInfo = function() return "yes", "party" end, realInfo
  check("an IsInInstance that gives no boolean is null", place():find("'instance': null, 'instanceType': 'party'", 1, true) ~= nil)
  IsInInstance, GetInstanceInfo = realIn, realInfo
  INSTANCE = { inside = false, kind = "none", name = "Eastern Kingdoms", map = 0 }
  check("... and back to none outside", place() == "'instance': false, 'instanceType': 'none', 'instanceMap': 0, 'instanceName': 'Eastern Kingdoms'")
end
check("the bags object: stacks of one item summed, ordered by id", has(round, '[4, 0, "{\\"free\\": 12, \\"items\\": [[2318, 16], [4234, 3]]}"]'))
check("the quests object, read from the client, ordered by id, a quote in a text escaped, a header left out",
  has(round, '\\"id\\": 290, \\"title\\": \\"Lifting the Curse\\", \\"state\\": \\"accepted\\"')
  and has(round, 'Speak with \\\\\\"Glorin\\\\\\"') and has(round, '\\"have\\": null, \\"need\\": null, \\"done\\": false')
  and round:find('"id\\": 290', 1, true) < round:find('"id\\": 471', 1, true) and not has(round, 'Wetlands\\", \\"state'))
check("the quest states of docs/SCHEMA.md: in_progress, ready by its objectives, unknown without any",
  has(round, '\\"id\\": 471, \\"title\\": \\"Apprentice\'s Duties\\", \\"state\\": \\"in_progress\\", \\"objectives\\": [{\\"text\\": \\"Giant Crocolisk Skin: 3/6\\", \\"have\\": 3, \\"need\\": 6, \\"done\\": false}]')
  and has(round, '\\"id\\": 305, \\"title\\": \\"In Search of The Excavation Team\\", \\"state\\": \\"ready\\"')
  and has(round, '\\"id\\": 999, \\"title\\": \\"No Objectives\\", \\"state\\": \\"unknown\\", \\"objectives\\": []'))
check("the skills object, read from the client, ordered by id",
  has(round, '[6, 0, "[{\\"id\\": 165, \\"name\\": \\"Leatherworking\\", \\"rank\\": 75, \\"max\\": 150}, {\\"id\\": 393, \\"name\\": \\"Skinning\\", \\"rank\\": 120, \\"max\\": 150}]"]'))
local ids, inOrder = {}, true
for id in round:gmatch('"chunk": %[(%d+),') do
  if ids[#ids] ~= tonumber(id) then ids[#ids + 1] = tonumber(id) end
end
for i = 2, #ids do
  if ids[i] ~= ids[i - 1] + 1 and not (ids[i - 1] == 23 and ids[i] == 2) then inOrder = false end
end
check("the objects take turns in the order of their ids, 2 to 23, and then again from the start (" .. table.concat(ids, " ") .. ")", inOrder and #ids >= 22)
check("with no route addon the route object says null (#64)", has(round, '[9, 0, "null"]'))
-- Object 10 (#68): which character is in the game.
check("the who object: the character's name and realm, its class and race (#138)",
  has(round, '[10, 0, "{\\"name\\": \\"FakeHunter\\", \\"realm\\": \\"TestRealm\\", \\"class\\": \\"HUNTER\\", \\"race\\": \\"NightElf\\"}"]'))
do
  local name = UnitName
  UnitName = function(u) if u == "player" then return SECRET end return name(u) end
  events.OnEvent(events, "PLAYER_ENTERING_WORLD")
  check("a name that cannot be read is 'cannot be read' (format 255), and nothing is done with it", has(watch(30), "[10, 255, null]"))
  -- The order of the calls: the client is asked whether each value is secret straight after it
  -- is read. A test of the format alone would pass on code that never asks.
  local log, realm, realSecret = {}, GetRealmName, issecretvalue
  UnitName = function(u) if u == "player" then log[#log + 1] = "read" return SECRET end return name(u) end
  GetRealmName = function() log[#log + 1] = "read" return SECRET end
  issecretvalue = function(v) if log[#log] == "read" and v == SECRET then log[#log + 1] = "asked" end return realSecret(v) end
  events.OnEvent(events, "PLAYER_ENTERING_WORLD")
  watch(30)
  GetRealmName, issecretvalue = realm, realSecret
  local good = #log >= 4
  for i = 1, #log, 2 do if log[i] ~= "read" or log[i + 1] ~= "asked" then good = false end end
  check("the name and the realm are each asked about straight after they are read (" .. table.concat(log, " "):sub(1, 40) .. ")", good)
  UnitName = name
  events.OnEvent(events, "PLAYER_ENTERING_WORLD")
  check("... and the name is back when the client gives it again", has(watch(30), '[10, 0, "{\\"name\\": \\"FakeHunter\\"'))
end
-- Objects 7 and 8 (#62): where a guide addon's arrow points, and the rested XP.
check("with no guide addon the waypoint object says null", has(round, '[7, 0, "null"]'))
check("the rest object: 0 when the client gives nothing", has(round, '[8, 0, "{\\"rested\\": 0}"]'))
RXP = { arrowFrame = { element = { zone = 1434, x = 40.635038182542, y = 3.5139672370787, step = { title = "Step 12" } } } }
local way = watch(30)
check("the waypoint: the map, and x and y as the position has them (per cent of the map to 0..65535); the step's title",
  has(way, '[7, 0, "{\\"source\\": \\"RXPGuides\\", \\"guide\\": null, \\"map\\": 1434, \\"x\\": 26630, \\"y\\": 2303, \\"title\\": \\"Step 12\\", \\"step\\": null, \\"text\\": null}"]'))
RXP.arrowFrame.element = { zone = 1437, x = 10, y = 60.5, title = 'Kill "Crocs"', step = { arrowtext = "not this" } }
check("another place within about a second, with no client event; the element's own title first, a quote escaped",
  has(watch(32), '\\"map\\": 1437, \\"x\\": 6554, \\"y\\": 39649, \\"title\\": \\"Kill \\\\\\"Crocs\\\\\\"\\", '))
RXP.arrowFrame.element = { zone = 1437, x = 10, y = 60.5, title = "", step = { arrowtext = "Go north" } }
check("an empty title: the step's arrow text", has(watch(32), '\\"title\\": \\"Go north\\", '))
RXP.arrowFrame.element = { zone = 1437, x = 10, y = 60.5 }
check("no title anywhere: null", has(watch(32), '\\"y\\": 39649, \\"title\\": null, '))
-- The step's number and text (seen 14 Nov 2026: step.index 109, step.text with colour and
-- texture codes and a line break; the place itself had no text).
RXP.arrowFrame.element = { zone = 1434, x = 33.3, y = 11.9,
  step = { index = 109, text = "   Kill |cFFFF5722Young Stranglethorn Tigers|r\n|TInterface/GossipFrame/BattleMasterGossipIcon:0|t6/10 Young Stranglethorn Tiger slain" } }
check("the step's number and its text as the addon holds it, the line break escaped",
  has(watch(32), '\\"title\\": null, \\"step\\": 109, \\"text\\": \\"   Kill |cFFFF5722Young Stranglethorn Tigers|r\\\\n|TInterface/GossipFrame/BattleMasterGossipIcon:0|t6/10 Young Stranglethorn Tiger slain\\"}'))
RXP.arrowFrame.element.step.text = RXP.arrowFrame.element.step.text:gsub("6/10", "7/10")
check("the text follows the count in it", has(watch(32), "|t7/10 Young Stranglethorn Tiger slain"))
RXP.arrowFrame.element.step = { index = 109.5, text = "half" }
check("a step number that is not whole is left out", has(watch(32), '\\"step\\": null, \\"text\\": \\"half\\"}'))
RXP.arrowFrame.element.step = { index = "x", text = ("y"):rep(601) }
check("a step number that is no number is left out; a text of more than 600 bytes is cut to 597 and an ellipsis (#78)",
  has(watch(32), '\\"step\\": null, \\"text\\": \\"' .. ("y"):rep(597) .. '…\\"}'))
RXP.arrowFrame.element = { zone = 1437, x = 10, y = 60.5, title = ("x"):rep(201) }
check("a title of more than 200 bytes is left out", has(watch(32), '\\"y\\": 39649, \\"title\\": null, '))
for _, bad in ipairs({ { zone = "Wetlands", x = 10, y = 60 }, { zone = 1437, x = 140, y = 60 }, { zone = 1437, x = 10 } }) do
  RXP.arrowFrame.element = { zone = 1437, x = 1, y = 1 }; watch(32)
  RXP.arrowFrame.element = bad
  local got = watch(32)
  check("a place that is not a map number and two per cents is no waypoint: null", has(got, '[7, 0, "null"]'))
end
-- The guide's name (#64; seen 14 Nov 2026: currentGuide.name "29-32 Duskwood").
RXP.currentGuide = { name = "29-32 Duskwood", key = "RestedXP Forever Guide (A)|Speedrun Guide 30-40|29-32 Duskwood" }
RXP.arrowFrame.element = { zone = 1431, x = 50, y = 50 }
check("the waypoint names the guide", has(watch(32), '{\\"source\\": \\"RXPGuides\\", \\"guide\\": \\"29-32 Duskwood\\", \\"map\\": 1431, '))
RXP.currentGuide = { name = "bad \255" }
check("a guide name that is not UTF-8 is left out", has(watch(32), '{\\"source\\": \\"RXPGuides\\", \\"guide\\": null, \\"map\\": 1431, '))
-- Object 11 (#74): the guide's next steps.
check("with no current step the steps object says null", has(watch(30), '[11, 0, "null"]'))
RXP.currentGuide = { name = "G", steps = {
  { index = 1, text = "one" },
  { index = 2, text = "two", elements = { { text = "no place" }, { zone = 1429, x = 50, y = 25 }, { zone = 1, x = 1, y = 1 } } },
  { index = 3, text = "bad \255", elements = { { zone = 70000, x = 1, y = 1 } } },
  { index = 4, text = "four" },
  { index = 5, text = "five" },
  { index = 6, text = ("y"):rep(401) },
} }
RXP.arrowFrame.element = { zone = 1431, x = 50, y = 50, step = { index = 1 } }
check("the steps object: the current step and the four after it, each with its number, text and first place (0.8.0)",
  has(watch(40), '[11, 0, "{\\"source\\": \\"RXPGuides\\", \\"guide\\": \\"G\\", \\"steps\\": ['
    .. '{\\"step\\": 1, \\"text\\": \\"one\\", \\"map\\": null, \\"x\\": null, \\"y\\": null, \\"tags\\": [], \\"quests\\": [], \\"done\\": false}, '
    .. '{\\"step\\": 2, \\"text\\": \\"two\\", \\"map\\": 1429, \\"x\\": 32768, \\"y\\": 16384, \\"tags\\": [], \\"quests\\": [], \\"done\\": false}, '
    .. '{\\"step\\": 3, \\"text\\": null, \\"map\\": null, \\"x\\": null, \\"y\\": null, \\"tags\\": [], \\"quests\\": [], \\"done\\": false}, '
    .. '{\\"step\\": 4, \\"text\\": \\"four\\", \\"map\\": null, \\"x\\": null, \\"y\\": null, \\"tags\\": [], \\"quests\\": [], \\"done\\": false}, '
    .. '{\\"step\\": 5, \\"text\\": \\"five\\", \\"map\\": null, \\"x\\": null, \\"y\\": null, \\"tags\\": [], \\"quests\\": [], \\"done\\": false}], '
    .. '\\"orphans\\": [], \\"targets\\": null}"]'))
RXP.arrowFrame.element.step = { index = 5 }
check("at the guide's end there are fewer steps; a text over 400 bytes is cut to 397 and an ellipsis (#78)",
  has(watch(40), '\\"guide\\": \\"G\\", \\"steps\\": [{\\"step\\": 5, \\"text\\": \\"five\\", \\"map\\": null, \\"x\\": null, \\"y\\": null, \\"tags\\": [], \\"quests\\": [], \\"done\\": false}, '
    .. '{\\"step\\": 6, \\"text\\": \\"' .. ("y"):rep(397) .. '…\\", \\"map\\": null, \\"x\\": null, \\"y\\": null, \\"tags\\": [], \\"quests\\": [], \\"done\\": false}]'))
do
  -- Where the cut may not fall (#78): inside a character, a texture code or a colour code.
  local function cut(text)
    RXP.currentGuide.steps[6].text = text
    local last
    for found in watch(40):gmatch('\\"step\\": 6, \\"text\\": \\"(.-)…\\", \\"map\\"') do last = found end
    return last                                      -- the newest: the row still shows the old text at first
  end
  check("a cut that would split a character of three bytes moves back to before it", cut(("y"):rep(396) .. "北北") == ("y"):rep(396))
  check("a cut that would fall in a texture code moves back to before the code",
    cut(("y"):rep(390) .. "|TInterface/Icons/INV_Misc_QuestionMark:0|t and more") == ("y"):rep(390))
  check("a cut that would fall in the ten characters of a colour code moves back to before the code",
    cut(("y"):rep(392) .. "|cFF00FF25Marshal McBride|r") == ("y"):rep(392))
  check("a cut after a whole colour code stays: the text may lack its closing code",
    cut(("y"):rep(380) .. "|cFF00FF25" .. ("z"):rep(30)) == ("y"):rep(380) .. "|cFF00FF25" .. ("z"):rep(7))
  -- Every place where the cut can fall in a character of 2, 3 and 4 bytes: with k of its bytes
  -- before the cut the whole character goes; with all of them before it, it stays.
  for _, c in ipairs({ "\195\169", "\229\140\151", "\240\157\132\158" }) do
    local good = true
    for k = 1, #c do
      local got = cut(("y"):rep(397 - k) .. c .. ("y"):rep(10))
      if got ~= ("y"):rep(397 - k) .. (k == #c and c or "") then good = false end
    end
    check("a character of " .. #c .. " bytes is never split by the cut, wherever the cut falls in it", good)
  end
  check("an escaped bar is text: ||T is no texture code and ||c no colour code",
    cut("||T" .. ("y"):rep(400)) == "||T" .. ("y"):rep(394) and cut(("y"):rep(390) .. "||c" .. ("y"):rep(20)) == ("y"):rep(390) .. "||c" .. ("y"):rep(4))
  check("an escaped bar is not split: a cut between its two bars moves back to before it", cut(("y"):rep(396) .. "||" .. ("y"):rep(10)) == ("y"):rep(396))
  check("a text that is all one texture code leaves the ellipsis alone", cut("|TInterface/" .. ("x"):rep(500) .. "|t") == "")
  check("an escaped bar inside a texture code does not end the code: ||t is no |t",
    cut("|Tfoo||t" .. ("x"):rep(500) .. "|t") == "" and cut("|Tfoo||t|t" .. ("y"):rep(500)) == "|Tfoo||t|t" .. ("y"):rep(387))
  check("a text of exactly 400 bytes is not cut", (function()
    RXP.currentGuide.steps[6].text = ("y"):rep(400)
    return has(watch(40), '\\"step\\": 6, \\"text\\": \\"' .. ("y"):rep(400) .. '\\", \\"map\\"') end)())
  RXP.currentGuide.steps[6].text = ("y"):rep(401)
end
RXP.arrowFrame.element.step = { index = 7 }
check("after the last step the list is empty", has(watch(40), '\\"guide\\": \\"G\\", \\"steps\\": [], '))
do
  -- The order of the calls: each entry of the guide's list is asked about straight after it is
  -- read. A `type` of the entry before that is seen too. A comparison with nil is not: Lua
  -- gives a test no way to see one.
  local log, realGet, realSecret, realType = {}, rawget, issecretvalue, type
  RXP.currentGuide.steps[2] = SECRET
  RXP.arrowFrame.element.step = { index = 2 }
  rawget = function(t, k) local v = realGet(t, k) if v == SECRET then log[#log + 1] = "read" end return v end
  issecretvalue = function(v) if realGet(log, #log) == "read" and v == SECRET then log[#log + 1] = "asked" end return realSecret(v) end
  type = function(v) if v == SECRET then log[#log + 1] = "typed" end return realType(v) end
  local seen = watch(40)
  rawget, issecretvalue, type = realGet, realSecret, realType
  local good = #log >= 2
  for i = 1, #log, 2 do if log[i] ~= "read" or log[i + 1] ~= "asked" then good = false end end
  check("a secret step is asked about straight after it is read, and ends the list (" .. table.concat(log, " "):sub(1, 40) .. ")",
    good and has(seen, '\\"guide\\": \\"G\\", \\"steps\\": [], '))
end
RXP.arrowFrame.element.step = { index = 2.5 }
check("a current step that is no whole number: null", has(watch(40), '[11, 0, "null"]'))
do
  -- A step's place is looked for in its first 20 elements only.
  local at20, at21 = {}, {}
  for i = 1, 19 do at20[i], at21[i] = {}, {} end
  at20[20] = { zone = 1429, x = 50, y = 25 }
  at21[20], at21[21] = {}, { zone = 1429, x = 50, y = 25 }
  RXP.currentGuide.steps = { { index = 1 }, { index = 2, text = "a", elements = at20 }, { index = 3, text = "b", elements = at21 } }
  RXP.arrowFrame.element.step = { index = 1 }
  check("a place in a step's 20th element is found; one in the 21st is not",
    has(watch(40), '{\\"step\\": 2, \\"text\\": \\"a\\", \\"map\\": 1429, \\"x\\": 32768, \\"y\\": 16384, \\"tags\\": [], \\"quests\\": [], \\"done\\": false}, '
      .. '{\\"step\\": 3, \\"text\\": \\"b\\", \\"map\\": null, \\"x\\": null, \\"y\\": null, \\"tags\\": [], \\"quests\\": [], \\"done\\": false}]'))
end
RXP.arrowFrame.element = { zone = 1431, x = 50, y = 50 }
RXP.currentGuide = nil

-- Object 12 (#109): the fight baseline (docs/specs/93.md, section 4). HelloForever leaves the
-- last counted fight in the plain global HelloForeverBaseline; HelloLink reads it with rawget.
do
  local KEY = "hf1-0000abcd-1794516378-12-1"
  local function good(o)
    local b = { fight = KEY, rev = 1, counted = true, id = 1984, level = 14, name = "Defias Thug",
      dur = { 12, 15, 8 }, dps = { 37.6, 30.5, 8 }, taken = { 210, 340, 8 }, died = { false, 0, 8 } }
    for k, v in pairs(o or {}) do b[k] = v end
    return b
  end
  local WANT = '[12, 0, "{\\"fight\\": \\"' .. KEY .. '\\", \\"rev\\": 1, \\"counted\\": true, \\"id\\": 1984, \\"level\\": 14, '
    .. '\\"name\\": \\"Defias Thug\\", \\"dur\\": [12, 15, 8], \\"dps\\": [38, 31, 8], \\"taken\\": [210, 340, 8], \\"died\\": [false, 0, 8]}"]'
  -- The versions of object 12 in the order they came, and the text of each.
  local function seen(text)
    local out, last = {}, nil
    for v in text:gmatch('"chunk": %[12, (%d+),') do if v ~= last then out[#out + 1] = tonumber(v); last = v end end
    local texts = {}
    for t in text:gmatch('"object": %[12, 0, "(.-)"%]') do if texts[#texts] ~= t then texts[#texts + 1] = t end end
    return out, texts
  end
  HelloForeverBaseline = nil
  check("with no HelloForever (or before the first counted fight) the baseline object says null", has(watch(30), '[12, 0, "null"]'))
  HelloForeverBaseline = good()
  check("the baseline object: the fight's key and rev, the enemy, the level and the triples, numbers rounded",
    has(watch(30), WANT))
  HelloForeverBaseline = good({ dur = { nil, nil, 2 }, dps = { 38, 31, 2 }, taken = { 210, 340, 3 }, died = { true, 1, 2 } })
  check("a value this fight does not know is null; usual and the death count are null under 3 earlier fights",
    has(watch(30), '\\"dur\\": [null, null, 2], \\"dps\\": [38, null, 2], \\"taken\\": [210, 340, 3], \\"died\\": [true, null, 2]}"]'))
  HelloForeverBaseline = good({ name = "bad \255" })
  check("a name that is not UTF-8 is null; the object stays", has(watch(30), '\\"level\\": 14, \\"name\\": null, \\"dur\\": [12, 15, 8]'))
  -- Two fights with the same numbers are two versions: the key tells them apart.
  HelloForeverBaseline = good()
  local both = watch(32)
  local other = "hf1-0000abcd-1794516400-13-1"
  HelloForeverBaseline = good({ fight = other })
  both = both .. watch(32)
  local v, texts = seen(both)
  check("two fights with the same numbers are two versions of the object (" .. table.concat(v, " ") .. ")",
    #v >= 2 and v[#v] ~= v[#v - 1] and #texts >= 2 and texts[#texts]:find(other, 1, true) ~= nil
    and texts[#texts - 1]:find(KEY, 1, true) ~= nil)
  -- Revisions 1 counted, 2 not, 3 counted: three versions, the last with the numbers.
  local all = ""
  HelloForeverBaseline = good()
  all = all .. watch(32)
  -- The text of the counted-false object is that of tests/strip1_test.py, whose bytes are written out by hand there.
  HelloForeverBaseline = { fight = KEY, rev = 2, counted = false }
  all = all .. watch(32)
  HelloForeverBaseline = good({ rev = 3, dur = { 13, 15, 8 } })
  all = all .. watch(32)
  v, texts = seen(all)
  check("revisions 1 counted, 2 not, 3 counted are three versions, the last with the numbers (" .. table.concat(v, " ") .. ")",
    #v >= 3 and v[#v] ~= v[#v - 1] and v[#v - 1] ~= v[#v - 2] and #texts >= 3
    and texts[#texts - 1] == '{\\"fight\\": \\"' .. KEY .. '\\", \\"rev\\": 2, \\"counted\\": false}'
    and texts[#texts]:find('\\"rev\\": 3, \\"counted\\": true, ', 1, true) ~= nil and texts[#texts]:find('\\"dur\\": [13, 15, 8]', 1, true) ~= nil)
  HelloForeverBaseline = nil
  check("after /hello baseline reset (HelloForever clears the table) the object says null", has(watch(30), '[12, 0, "null"]'))
  -- Anything not as the spec has it is null, never an error and never a made-up value.
  local bads = {
    { fight = 7 }, { fight = 'a"b' }, { fight = ("x"):rep(65) }, { rev = 0 }, { rev = 1.5 }, { rev = 0 / 0 }, { counted = "yes" },
    { id = 0 }, { id = 2.5 }, { level = 0 }, { level = 256 }, { dur = "12" }, { dur = { -1, 15, 8 } }, { dps = { 0 / 0, 15, 8 } },
    { taken = { 210, math.huge, 8 } }, { dur = { 12, 15, 2.5 } }, { dur = { 12, 15 } }, { died = { "no", 0, 8 } }, { died = { false, 9, 8 } },
    { died = { false, 0.5, 8 } }, { taken = { 1e12, 340, 8 } },
    -- review of #110: a wrong middle value is wrong under 3 earlier fights too
    { dur = { 12, -1, 2 } }, { died = { false, -1, 2 } }, { dps = { 38, 0 / 0, 0 } }, { died = { false, 3, 2 } },
  }
  local wrong = {}
  for i, bad in ipairs(bads) do
    HelloForeverBaseline = good(); watch(32)
    HelloForeverBaseline = good(bad)
    if not has(watch(32), '[12, 0, "null"]') then wrong[#wrong + 1] = i end
  end
  check("a baseline table with a value of the wrong kind or out of range is null (wrong: " .. table.concat(wrong, " ") .. ")", #wrong == 0)
  HelloForeverBaseline = good(); watch(32)
  HelloForeverBaseline = "not a table"
  check("a global that is no table is null", has(watch(32), '[12, 0, "null"]'))
  HelloForeverBaseline = good(); watch(32)
  HelloForeverBaseline = good({ dur = { SECRET, 15, 8 } })
  check("a secret value in a triple is not used: it is null", has(watch(32), '\\"dur\\": [null, 15, 8], '))
  do
    -- The order of the calls: the global is asked about straight after it is read.
    local log, realGet, realSecret, realType = {}, rawget, issecretvalue, type
    HelloForeverBaseline = SECRET
    rawget = function(t, k) local v = realGet(t, k) if v == SECRET then log[#log + 1] = "read" end return v end
    issecretvalue = function(x) if realGet(log, #log) == "read" and x == SECRET then log[#log + 1] = "asked" end return realSecret(x) end
    type = function(x) if x == SECRET then log[#log + 1] = "typed" end return realType(x) end
    local got = watch(32)
    rawget, issecretvalue, type = realGet, realSecret, realType
    local fine = #log >= 2
    for i = 1, #log, 2 do if log[i] ~= "read" or log[i + 1] ~= "asked" then fine = false end end
    check("a secret global is asked about straight after it is read, and is null (" .. table.concat(log, " "):sub(1, 40) .. ")",
      fine and has(got, '[12, 0, "null"]'))
  end
  local called = 0
  HelloForeverBaseline = setmetatable({ fight = KEY, rev = 1, counted = true }, { __index = function() called = called + 1 return 5 end })
  check("HelloForever's table is read with no __index called: without its numbers it is null",
    has(watch(32), '[12, 0, "null"]') and called == 0)
  HelloForeverBaseline = nil; watch(32)
end

-- The route (object 9, #64): what the route addon's public interface gives, as seen in the
-- game on 14 Nov 2026. Only Journey is called; a function that steers must never be.
local J, steered = nil, 0
local function steer() steered = steered + 1 end
ShortestPathForever = { API = { Journey = function() return J end, Navigate = steer, NavigateRoute = steer, Cancel = steer,
  Pause = steer, Resume = steer, SkipLeg = steer, RenameStop = steer } }
J = { secondsLeft = 40, goal = { map = 1415, x = 0.48728519678116, y = 0.52361696958542, title = "RestedXP" },
  legs = { { mode = "walk", seconds = 40, text = "Walk to RestedXP" } }, owner = "RestedXP", guided = true, index = 1 }
local firstRoute = watch(40)
check("the route: the goal as the position has it (a fraction of the map to 0..65535), the time left, the legs",
  has(firstRoute, '{\\"source\\": \\"ShortestPathForever\\", \\"owner\\": \\"RestedXP\\", \\"goal\\": {\\"map\\": 1415, \\"x\\": 31934, \\"y\\": 34315, \\"title\\": \\"RestedXP\\"}, \\"seconds\\": 40, \\"index\\": 1, \\"guided\\": true, \\"legCount\\": 1, \\"legs\\": [{\\"mode\\": \\"walk\\", \\"seconds\\": 40, \\"text\\": \\"Walk to RestedXP\\"}]}"]'))
J = { secondsLeft = 191.4, goal = { map = 1431, x = 0.5, y = 0.25 }, guided = false, index = 2,
  legs = { { mode = "walk", seconds = 30, text = "Walk to Sentinel Hill" }, { mode = "flight", seconds = 121, text = "Fly to Darkshire" },
           { mode = "walk", seconds = 40.2, text = "Walk 200 yards" } } }
local route = watch(40)
check("several legs in their order; no owner and no title are null; the seconds are whole",
  has(route, '\\"owner\\": null, \\"goal\\": {\\"map\\": 1431, \\"x\\": 32768, \\"y\\": 16384, \\"title\\": null}, \\"seconds\\": 191, \\"index\\": 2, \\"guided\\": false, \\"legCount\\": 3, ')
  and has(route, '{\\"mode\\": \\"walk\\", \\"seconds\\": 30, \\"text\\": \\"Walk to Sentinel Hill\\"}, {\\"mode\\": \\"flight\\", \\"seconds\\": 121, \\"text\\": \\"Fly to Darkshire\\"}, {\\"mode\\": \\"walk\\", \\"seconds\\": 40, '))
J.legs = {}
for i = 1, 25 do J.legs[i] = { mode = "walk", seconds = i, text = "Leg " .. i } end
route = watch(40)
check("more than 20 legs: the first 20, and legCount says how many there are",
  has(route, '\\"legCount\\": 25, ') and has(route, '\\"text\\": \\"Leg 20\\"}]}') and not has(route, "Leg 21"))
J.legs = { { mode = 7, seconds = 0 / 0, text = "bad \255" }, { mode = "boat", seconds = -5, text = ("z"):rep(121) }, "not a leg" }
check("in a leg, a mode that is no word, seconds that are no amount and a text that is not UTF-8 or too long are null; what is no leg is left out",
  has(watch(40), '\\"legCount\\": 3, \\"legs\\": [{\\"mode\\": null, \\"seconds\\": null, \\"text\\": null}, {\\"mode\\": \\"boat\\", \\"seconds\\": null, \\"text\\": null}]}'))
J.legs = { SECRET, { mode = "walk", seconds = 9, text = "After a secret" } }
check("a leg that is a secret value is counted and left out, and the next leg is read",
  has(watch(40), '\\"legCount\\": 2, \\"legs\\": [{\\"mode\\": \\"walk\\", \\"seconds\\": 9, \\"text\\": \\"After a secret\\"}]}'))
-- The order (a review finding): a leg is read once, and the next thing done with it is the
-- question whether it is secret. The code before read it, compared it with nil, and read it again.
do
  local log, realGet, realSecret = {}, rawget, issecretvalue
  J.legs = { SECRET, { mode = "walk", seconds = 9, text = "Order" } }
  local legs = J.legs
  rawget = function(t, k) if t == legs and k == 1 then log[#log + 1] = "read" end return realGet(t, k) end
  issecretvalue = function(v) if realGet(log, #log) == "read" and v == SECRET then log[#log + 1] = "asked" end return realSecret(v) end
  watch(40)
  rawget, issecretvalue = realGet, realSecret
  local good = #log >= 2
  for i = 1, #log, 2 do if log[i] ~= "read" or log[i + 1] ~= "asked" then good = false end end
  check("a leg is read once, and asked whether it is secret before anything else is done with it (" .. table.concat(log, " "):sub(1, 40) .. ")", good)
end
J.legs = {}
for i = 1, 200 do J.legs[i] = { mode = "walk", seconds = 1, text = "L" } end
check("200 legs are counted", has(watch(40), '\\"legCount\\": 200, '))
J.legs[201] = { mode = "walk", seconds = 1, text = "L" }
check("with more than 200 legs how many there are is not known: null", has(watch(40), '\\"legCount\\": null, '))
for _, bad in ipairs({ { map = 0 / 0, x = 0.5, y = 0.5 }, { map = 1431, x = 1.5, y = 0.5 }, { map = 1431, x = 0.5, y = math.huge }, { map = 1431, x = SECRET, y = 0.5 }, "nowhere" }) do
  J = { secondsLeft = 5, goal = { map = 1431, x = 0.1, y = 0.1 }, legs = {}, index = 1 }; watch(40)
  J = { secondsLeft = 5, goal = bad, legs = {}, index = 1 }
  check("a goal that is no map and two fractions is no route: null", has(watch(40), '[9, 0, "null"]'))
end
J = { secondsLeft = 0 / 0, goal = { map = 1431, x = 0.1, y = 0.1 }, legs = "none", index = 1.5, guided = "yes" }
check("a time left and an index that are no amount are null; legs that are no list are none; guided is true only for true",
  has(watch(40), '\\"seconds\\": null, \\"index\\": null, \\"guided\\": false, \\"legCount\\": 0, \\"legs\\": []}'))
J = nil
check("no journey: null", has(watch(40), '[9, 0, "null"]'))
ShortestPathForever.API.Journey = function() error("the route addon failed") end
J = { secondsLeft = 5, goal = { map = 1431, x = 0.1, y = 0.1 }, legs = {}, index = 1 }
check("a Journey that fails is null, and the row goes on", has(watch(40), '[9, 0, "null"]') and has(watch(5), '"row": true'))
check("no function that plans, steers or cancels a journey was called", steered == 0)
ShortestPathForever = nil

-- Review of #62: values that are no place, a text a reader would refuse, and no code of the
-- other addon run.
for _, bad in ipairs({ { zone = 0 / 0, x = 10, y = 60 }, { zone = 1437, x = 0 / 0, y = 60 }, { zone = 1437, x = 10, y = 0 / 0 },
                       { zone = 1437, x = 10, y = math.huge }, { zone = math.huge, x = 10, y = 60 } }) do
  RXP.arrowFrame.element = { zone = 1437, x = 1, y = 1 }; watch(32)
  RXP.arrowFrame.element = bad
  check("a map or a coordinate that is NaN or infinite is no waypoint: null", has(watch(32), '[7, 0, "null"]'))
end
RXP.arrowFrame.element = { zone = 1437, x = 20, y = 30, title = "bad \255 byte", step = { index = 0 / 0, text = "\237\160\128 surrogate" } }
check("a title and a text that are not UTF-8 are left out; the place stays, and a NaN step number is left out",
  has(watch(32), '\\"map\\": 1437, \\"x\\": 13107, \\"y\\": 19661, \\"title\\": null, \\"step\\": null, \\"text\\": null}'))
RXP.arrowFrame.element = { zone = 1437, x = 20, y = 30, title = "Zürich 北 ✓" }
check("a title in well-formed UTF-8 goes through", has(watch(32), "Zürich 北 ✓"))
local called = 0
local meta = { __index = function() called = called + 1 return 5 end }
RXP.arrowFrame.element = setmetatable({ zone = 1437, x = 21, y = 31 }, meta)
setmetatable(RXP, meta); setmetatable(RXP.arrowFrame, meta)
check("the other addon's tables are read with no __index called: the place, and nothing made up from the metatable",
  has(watch(32), '\\"x\\": 13762, \\"y\\": 20316, \\"title\\": null, \\"step\\": null, \\"text\\": null}') and called == 0)
setmetatable(RXP, nil); setmetatable(RXP.arrowFrame, nil)
RXP.arrowFrame.element = { zone = 1437, x = 1, y = 1 }; watch(32)
RXP.arrowFrame.element = { zone = 1437, x = SECRET, y = 60 }
check("a secret value in the arrow is not used: null", has(watch(32), '[7, 0, "null"]'))
RXP.arrowFrame.element = { zone = 1437, x = 1, y = 1 }; watch(32)
RXP.arrowFrame.element = nil
check("the arrow holds nothing: null", has(watch(32), '[7, 0, "null"]'))
RXP = nil
P.rested = 12345.6
events.OnEvent(events, "UPDATE_EXHAUSTION")
check("rested XP after the client's event, as a whole number", has(watch(32), '[8, 0, "{\\"rested\\": 12345}"]'))
for _, bad in ipairs({ -1, 0 / 0, math.huge, "many" }) do
  P.rested = 7; events.OnEvent(events, "UPDATE_EXHAUSTION"); watch(32)
  P.rested = bad; events.OnEvent(events, "UPDATE_EXHAUSTION")
  check("a rested XP that is no amount is 'cannot be read' (format 255), not a number", has(watch(32), "[8, 255, null]"))
end
P.rested = nil
events.OnEvent(events, "PLAYER_XP_UPDATE"); watch(32)

P.target = false
events.OnEvent(events, "PLAYER_TARGET_CHANGED")
local gone = watch(35)   -- a round of twenty-two objects (0.8.0)
check("no target: the object says null, a new version", has(gone, '[2, 0, "null"]'))
check("and the target and threat groups are unknown, the target's level squares black", has(gone, '"target": null') and has(gone, '"threat": null')
  and has(gone, '"levels": [75, 83, null, 93]'))
P.target = true
events.OnEvent(events, "PLAYER_TARGET_CHANGED")

slash("send 點解我呢區升得咁慢？")
local asked = watch(55)   -- its turn (at most a round), then a round of the others, then its turn again
check("a question is object 1, and comes before the others at its turn", has(asked, '[1, 0, "點解我呢區升得咁慢？"]'))
local later = watch(30)
check("after two rounds the question has left the queue", not has(later, '"chunk": [1,'))

local realInfo = C_QuestLog.GetInfo
C_QuestLog.GetInfo = nil
events.OnEvent(events, "QUEST_LOG_UPDATE")
local unread = watch(30)
check("an object the addon cannot read is format 255, and a reader drops its copy", has(unread, '[5, 255, null]'))
C_QuestLog.GetInfo = realInfo
BAGS[0][2] = { itemID = 4234, stackCount = SECRET }
events.OnEvent(events, "BAG_UPDATE_DELAYED")
check("a secret count in a bag makes the bags object unreadable, not a count of 1", has(watch(30), '[4, 255, null]'))
BAGS[0][2] = { itemID = 4234, stackCount = 3 }
events.OnEvent(events, "BAG_UPDATE_DELAYED"); events.OnEvent(events, "QUEST_LOG_UPDATE"); watch(30)
local realObjectives = C_QuestLog.GetQuestObjectives
C_QuestLog.GetQuestObjectives = function() error("not now") end
events.OnEvent(events, "QUEST_LOG_UPDATE")
check("objectives that cannot be read make the quests object unreadable, not quests without objectives", has(watch(40), '[5, 255, null]'))
C_QuestLog.GetQuestObjectives = realObjectives
events.OnEvent(events, "QUEST_LOG_UPDATE")
check("readable again, the quests come back", has(watch(40), '[5, 0, "[{'))
C_QuestLog.GetQuestObjectives = function(id) if id == 471 then return SECRET end return realObjectives(id) end
events.OnEvent(events, "QUEST_LOG_UPDATE")
check("one quest's objectives secret: the object is unreadable, not that quest with no objectives", has(watch(40), '[5, 255, null]'))
C_QuestLog.GetQuestObjectives = realObjectives
events.OnEvent(events, "QUEST_LOG_UPDATE")
check("and readable again after that", has(watch(40), '[5, 0, "[{'))
C_QuestLog.IsFailed = function() return SECRET end
events.OnEvent(events, "QUEST_LOG_UPDATE")
check("a secret 'failed' flag is not a 'no': the object is unreadable", has(watch(40), '[5, 255, null]'))
C_QuestLog.IsFailed = function() return false end
SKILLS[2].skillMaxRank = nil
events.OnEvent(events, "SKILL_LINES_CHANGED")
check("a skill line without a maximum is not a maximum of 0: the object is unreadable", has(watch(40), '[6, 255, null]'))
SKILLS[2].skillMaxRank = 150
local realSub = GetSubZoneText
GetSubZoneText = function() return SECRET end
events.OnEvent(events, "ZONE_CHANGED")
check("a secret subzone is not an empty one: the place object is unreadable", has(watch(40), '[3, 255, null]'))
GetSubZoneText = realSub
events.OnEvent(events, "ZONE_CHANGED"); events.OnEvent(events, "QUEST_LOG_UPDATE"); events.OnEvent(events, "SKILL_LINES_CHANGED"); watch(40)

-- ---------------- unknown is not zero ----------------
local realEnchant, realAfk, realCast = GetWeaponEnchantInfo, UnitIsAFK, UnitCastingInfo
GetWeaponEnchantInfo = nil
UnitIsAFK = function() return SECRET end
tick(0.1)
local partial = read({ dump() })
check("a missing function leaves its group unknown: the main hand is not 'empty, no enchant'", has(partial, '"hand": null'))
check("one secret flag makes the state group unknown, not a set of zeros", has(partial, '"state": null'))
check("the groups that could be read are still there", has(partial, '"health": {"healthMax": 1158}') and has(partial, '"threat": {"pet": 100, "player": 58}'))
GetWeaponEnchantInfo, UnitIsAFK = realEnchant, realAfk
UnitDetailedThreatSituation = function(u) if u == "pet" then return true, 3, 100, 100, 5000 end end
tick(0.1)
check("a unit that is not on the target's threat list has 0", has(read({ dump() }), '"threat": {"pet": 100, "player": 0}'))
UnitDetailedThreatSituation = nil
tick(0.1)
check("without the threat function the group is unknown", has(read({ dump() }), '"threat": null'))
UnitDetailedThreatSituation = function(u) if u == "player" then return false, 1, 57.6, 60, 1000 end return true, 3, 100, 100, 5000 end
UnitDetailedThreatSituation = function(u) if u == "pet" then return true, 3, SECRET, 100, 5000 end return false, 1, 57.6, 60, 1000 end
tick(0.1)
check("a pet whose threat is secret makes the threat group unknown, not a pet at 0", has(read({ dump() }), '"threat": null'))
UnitDetailedThreatSituation = function(u) if u == "player" then return false, 1, 57.6, 60, 1000 end return true, 3, 100, 100, 5000 end
events.OnEvent(events, "UI_ERROR_MESSAGE", SECRET, "x")
tick(0.1)
check("a UI error whose number is secret leaves that group unknown", has(read({ dump() }), '"uiError": null'))
events.OnEvent(events, "UI_ERROR_MESSAGE", 51, "x")
tick(0.1)
check("and the next readable one is known again, the count having gone on", has(read({ dump() }), '"uiError": {"counter": 3, "error": 51}'))
UnitCastingInfo = function() return SECRET end
tick(0.1)
local nocast = read({ dump() })
check("a cast the client keeps secret: no cast group, and the state group unknown with it", has(nocast, '"cast": null') and has(nocast, '"state": null'))
UnitCastingInfo = realCast

-- ---------------- a question typed while another is on its way ----------------
-- The first is three chunks (600 letters at 255 bytes a chunk); the second is typed while it
-- is on the row. Rounds are counted by version: a round is the chunks 0 to count - 1 in order.
slash("send " .. ("first question "):rep(40))
local early = watch(30)   -- its turn comes after object 16: at most a round
local v1 = tonumber(early:match('"chunk": %[1, (%d+), 0, 3'))
check("the first question is three chunks", v1 ~= nil)
slash("send second question")
local both = early .. watch(70)
-- A round of the question is one visit of the carousel to object 1: a stretch of captures
-- whose chunk is object 1 in one version, between captures of other objects. It counts when
-- the chunks 0 to count - 1 were seen in order in that stretch. The same chunk captured
-- several times is one chunk; two captures of a one-chunk question are still one round.
local rounds = {}
local visit                                  -- { version, count, nextIndex, whole }
local function close()
  if visit and visit.whole then rounds[visit.version] = (rounds[visit.version] or 0) + 1 end
  visit = nil
end
for id, v, index, count in both:gmatch('"chunk": %[(%d+), (%d+), (%d+), (%d+)') do
  id, v, index, count = tonumber(id), tonumber(v), tonumber(index), tonumber(count)
  if id ~= 1 then
    close()
  else
    if visit and visit.version ~= v then close() end
    visit = visit or { version = v, count = count, nextIndex = 0, whole = false }
    if index == visit.nextIndex then
      visit.nextIndex = index + 1
      if visit.nextIndex == count then visit.whole = true end
    end
  end
end
close()
local v2
for v in pairs(rounds) do if v ~= v1 then v2 = v end end
check("the second question is read", has(both, '[1, 0, "second question"]'))
check("its version is the first one's plus one", v2 == (v1 + 1) % 65536)
check("and it is sent in two whole rounds of its own, whatever the first had left", rounds[v2] == 2)

-- ---------------- a chunk stays for dwell, however fast the game runs ----------------
slash("strip dwell 5")
events.OnEvent(events, "PLAYER_TARGET_CHANGED")
local paths, order = {}, {}
for _ = 1, 200 do tick(0.01); paths[#paths + 1] = dump() end   -- 40 chunks: objects 2 and 3 come round
local fastrun = read(paths, 0.01)
local run, last = 0, nil
local shortest = 99
for id, index in fastrun:gmatch('"chunk": %[(%d+), %d+, (%d+)') do
  local key = id .. ":" .. index
  if key == last then run = run + 1 else if last then shortest = math.min(shortest, run) end run, last = 1, key end
end
check("at a dwell of 0.05 s and a frame every 0.01 s, every chunk is on the row for at least 4 captures", shortest >= 4)
check("and the objects still complete", has(fastrun, '"object": [2,') and has(fastrun, '"object": [3,'))
slash("strip dwell 10")

-- ---------------- ammunition is not a change of the bags (#44) ----------------
-- Seen in the game on 13 Nov 2026: each shot takes one from item 3030, and the bags object was
-- sent again about every two seconds of a fight.
local function bagsVersion(text)
  local last
  for found in text:gmatch('"chunk": %[4, (%d+),') do last = found end
  return last
end
P.ammo = 3030
BAGS[0][4] = { itemID = 3030, stackCount = 200 }
events.OnEvent(events, "BAG_UPDATE_DELAYED")
local quiver = watch(30)
check("ammunition is in the bags object with its count", has(quiver, "[3030, 200]"))
BAGS[0][4].stackCount = 199
events.OnEvent(events, "BAG_UPDATE"); events.OnEvent(events, "BAG_UPDATE_DELAYED")
local shot = watch(30)
check("a shot (only the ammunition's count changed) makes no new bags object",
  bagsVersion(quiver) ~= nil and bagsVersion(shot) == bagsVersion(quiver) and not has(shot, "[3030, 199]"))
BAGS[0][5] = { itemID = 3030, stackCount = 1 }
events.OnEvent(events, "BAG_UPDATE_DELAYED")      -- a second stack: 200 in all
local stacks = bagsVersion(watch(30))
BAGS[0][5], BAGS[0][4].stackCount, P.free = nil, 199, 13
events.OnEvent(events, "BAG_UPDATE_DELAYED")
check("a stack of ammunition shot empty frees a slot: still no new bags object", bagsVersion(watch(30)) == stacks)
BAGS[0][6], BAGS[0][2].stackCount, P.free = { itemID = 4234, stackCount = 1 }, 2, 12
events.OnEvent(events, "BAG_UPDATE_DELAYED")
local split = watch(30)
check("with ammunition in the bags, another item's stack split in two (only the free slots change) is a new bags object",
  bagsVersion(split) ~= stacks and has(split, '\\"free\\": 12, \\"items\\": [[2318, 16], [3030, 199], [4234, 3]]'))
BAGS[0][6], P.free = nil, nil
BAGS[0][2].stackCount = 4
events.OnEvent(events, "BAG_UPDATE_DELAYED")
local other = watch(30)
check("another item changes: a new bags object, with the ammunition's count of now",
  bagsVersion(other) ~= bagsVersion(quiver) and has(other, "[3030, 199]") and has(other, "[4234, 4]"))
-- The sixth bag (#50): this client has a bag 5 (8 slots, seen 13 Nov 2026). Herbs and cloth
-- the owner received were not in the object, which read bags 0 to 4.
BAGS[5] = { { itemID = 2453, stackCount = 2 } }
events.OnEvent(events, "BAG_UPDATE_DELAYED")
local sixth = watch(30)
check("an item in bag 5 is in the bags object; free does not count bag 5",
  bagsVersion(sixth) ~= bagsVersion(other) and has(sixth, '\\"free\\": 12, ') and has(sixth, "[2453, 2]"))
BAGS[5][1].stackCount = 4
events.OnEvent(events, "BAG_UPDATE_DELAYED")
local sixthMore = watch(30)
check("a change in bag 5 is a new bags object", bagsVersion(sixthMore) ~= bagsVersion(sixth) and has(sixthMore, "[2453, 4]"))
BAGS[5] = nil
events.OnEvent(events, "BAG_UPDATE_DELAYED")
check("without a bag 5 the object is as before", not has(watch(30), "2453"))
P.ammo = nil
BAGS[0][4].stackCount = 198
events.OnEvent(events, "BAG_UPDATE_DELAYED")
local plain = watch(30)
check("with nothing in the ammunition slot, that item's count is a change like any other",
  bagsVersion(plain) ~= bagsVersion(other) and has(plain, "[3030, 198]"))
BAGS[0][4], BAGS[0][2].stackCount = nil, 3
events.OnEvent(events, "BAG_UPDATE_DELAYED"); watch(20)

-- ---------------- a narrow game: small chunks, and an object too large for 12 of them ----------------
GetPhysicalScreenSize = function() return 600, 1440 end   -- 600 pixels: 209 squares of 6 bits after the palette, 156 bytes
events.OnEvent(events, "DISPLAY_SIZE_CHANGED")
for i = 1, 40 do BAGS[0][3 + i] = { itemID = 50000 + i * 37, stackCount = i } end
events.OnEvent(events, "BAG_UPDATE_DELAYED")
local narrow = watch(60)
local size = tonumber(narrow:match('"chunk": %[%d+, %d+, %d+, %d+, (%d+)%]'))
check("the chunk is as long as the row has room for (156 - 73 = 83 bytes)", size ~= nil and size <= 83)
check("the bags object, now several chunks, is joined", has(narrow, '[50037, 1]') and has(narrow, '[51480, 40]'))
GetPhysicalScreenSize = function() return 480, 1440 end   -- 149 squares: 111 bytes, chunks of 38
events.OnEvent(events, "DISPLAY_SIZE_CHANGED")
events.OnEvent(events, "BAG_UPDATE_DELAYED")
check("an object of more than 12 chunks is sent as format 254 in one chunk", has(watch(60), '[4, 254, null]'))
GetPhysicalScreenSize = function() return 2560, 1440 end
for i = 1, 40 do BAGS[0][3 + i] = nil end
events.OnEvent(events, "DISPLAY_SIZE_CHANGED"); events.OnEvent(events, "BAG_UPDATE_DELAYED"); watch(20)

-- ---------------- compression by the client ----------------
C_EncodingUtil = { CompressString = function(text)
  local f = assert(io.open(DIR .. "/raw.txt", "wb")); f:write(text); f:close()
  sh(("python3 -c \"import zlib,sys;d=open(sys.argv[1],'rb').read();c=zlib.compressobj(9,zlib.DEFLATED,-15);open(sys.argv[2],'wb').write(c.compress(d)+c.flush())\" '%s/raw.txt' '%s/raw.z'"):format(DIR, DIR))
  local z = assert(io.open(DIR .. "/raw.z", "rb")); local data = z:read("*a"); z:close()
  return data
end }
QUESTS[#QUESTS + 1] = { questID = 1000, title = "One More", objectives = {} }
events.OnEvent(events, "QUEST_LOG_UPDATE")
local squeezed = watch(40)
check("with a compressor the quests object goes out as format 1 and reads the same", has(squeezed, '[5, 1, "[{')
  and has(squeezed, '\\"id\\": 1000, \\"title\\": \\"One More\\"'))
C_EncodingUtil = nil

-- ---------------- what a rebuild costs ----------------
local t0, runs = os.clock(), 300
for _ = 1, runs do P.money = P.money + 1; tick(0.1) end
local each = (os.clock() - t0) / runs * 1000
print_real(("   a frame with a changed fast block: %.3f ms in this stub"):format(each))
check("a rebuild is cheap in the stub (under 3 ms; the game's own cost is measured there)", each < 3)

-- ---------------- depth 2, by hand ----------------
check("/hlink strip depth 2 says what the strip is now", has(slash("strip depth 2"), "depth 2 (now 2)"))
tick(0.1)
local two = read({ dump() })
check("depth 2: the row is read with no palette", has(two, '"depth": 2') and has(two, '"apart": null') and has(two, '"why": null')
  and has(two, '"levels": [75, 83, 12, 93]') and has(two, '"health": {"healthMax": 1158}'))
slash("strip depth auto")
tick(0.1)
check("/hlink strip depth auto goes back to depth 4", has(read({ dump() }), '"depth": 4'))

-- ---------------- the fall-back a reader asks for ----------------
slotFile = { seq = 1, text = "", strip = { session = session + 7, depth = 2 } }
tick(600); tick(0.1)                              -- past the next time the addon looks at a slot
check("a request that names another session does nothing", has(read({ dump() }), '"depth": 4'))
slotFile = { seq = 2, text = "", strip = { session = session, depth = 2 } }
out = {}
tick(600); tick(0.1)
check("a request that names this session makes the row depth 2, and chat says so",
  has(read({ dump() }), '"depth": 2') and has(table.concat(out, "\n"), "falls back to 3 bits"))
slash("strip depth auto"); tick(0.1)

-- ---------------- size, place, off ----------------
slash("strip size 3"); slash("strip at 40 6"); tick(0.1)
local moved = read({ dump() })
check("3 pixels a square at (40, 6): still read", has(moved, '"row": true') and has(moved, '"why": null')
  and math.abs(tonumber(moved:match('"square": ([%d.]+)')) - 3) < 0.01)
slash("strip size 2"); slash("strip at 0 0")
check("StripSet: a setting it does not have is refused, and the state is as it was", ns.StripSet("size", "9") == false and ns.StripState().size == 2 and ns.StripState().x == 0)
check("a wrong command lists the commands", has(slash("strip depth 9"), "use /hlink strip"))
slash("strip off"); tick(0.1)
check("/hlink strip off: nothing is on the row", has(read({ dump() }), '"row": false'))
slash("strip on"); tick(0.1)
check("/hlink strip on brings it back", has(read({ dump() }), '"row": true'))

-- ---------------- the looks serve the assistant (docs/specs/115.md, section 6; #127) ----------------
do
  local looks, times = 0, {}
  local realLoad = C_AddOns.LoadAddOn
  C_AddOns.LoadAddOn = function(...) looks = looks + 1; times[#times + 1] = now return realLoad(...) end
  local function looked(f) local l0 = looks; f(); return looks - l0 end
  slotFile = { seq = 3, text = "", slots = 200 }
  slash("strip depth 2"); tick(0.1)                -- the strip's own looks stop at depth 2
  check("at depth 2 with the assistant off the fixed times make no look", looked(function() tick(600); tick(0.1) end) == 0)
  slash("strip depth auto"); tick(0.1)
  check("with the assistant off a level up or a rest makes no look, also at depth auto",
    looked(function() events.OnEvent(events, "PLAYER_LEVEL_UP") end) == 0)
  slash("strip depth 2"); tick(0.1)
  HelloForeverAssist = { on = true }
  check("with HelloForever's assistant on they go on at any depth", looked(function() tick(600); tick(0.1) end) == 1)
  local card = { id = "session", kind = "event", prio = 3, src = "companion", at = 1794516370, ttl = 600, text = "a card", basis = "test" }
  slotFile = { seq = 3, text = "", slots = 200, assist = { session = session, seq = 1, t = 1794516378, cards = { card } } }
  tick(600); tick(0.1)
  check("a look takes the set into HelloLinkAssist", type(HelloLinkAssist) == "table" and HelloLinkAssist.cards[1]
    and HelloLinkAssist.cards[1].text == "a card" and HelloLinkAssist.left == 200 - ns.SlotsUsed())
  -- never in a fight: made after it
  InCombatLockdown = function() return true end
  check("a look that falls due in a fight is not made in it", looked(function() tick(600); tick(0.1) end) == 0)
  InCombatLockdown = function() return false end
  check("...but after it", looked(function() tick(1) end) == 1)
  -- a question: looks 3, 8 and 20 s after it, until its answer
  HelloForeverAssist = { on = true, ask = { n = 1, topic = "session", t = 1794516378 } }
  tick(1)                                         -- the second's read sees the question
  local asked, from = now, #times + 1
  local q = looked(function() for _ = 1, 25 do tick(1) end end)
  local at = {}
  for i = from, #times do at[#at + 1] = math.floor(times[i] - asked + 0.5) end
  check("a question without an answer gives three looks, at 3, 8 and 20 s", q == 3 and table.concat(at, ",") == "3,8,20", table.concat(at, ","))
  HelloForeverAssist.ask = { n = 2, topic = "session", t = 1794516378 }
  slotFile.assist = { session = session, seq = 2, t = 1794516378, re = 2, cards = {} }
  tick(1)
  q = looked(function() for _ = 1, 25 do tick(1) end end)
  check("an answer (a set whose re is the question's number) stops the looks", q == 1 and HelloLinkAssist.re == 2, q)
  -- a question in a fight: its look after the fight
  HelloForeverAssist.ask = { n = 3, topic = "session", t = 1794516378 }
  InCombatLockdown = function() return true end
  tick(1)
  check("a question's look that falls in a fight is not made in it", looked(function() for _ = 1, 5 do tick(1) end end) == 0)
  InCombatLockdown = function() return false end
  check("...but after it", looked(function() tick(1) end) == 1)
  slotFile.assist.re = 3; for _ = 1, 25 do tick(1) end
  -- moments
  IsResting = function() return true end
  check("a look when the character starts resting", looked(function() events.OnEvent(events, "PLAYER_UPDATE_RESTING") end) == 1)
  IsResting = function() return false end
  check("no look when the rest ends", looked(function() events.OnEvent(events, "PLAYER_UPDATE_RESTING") end) == 0)
  check("a look at a level up", looked(function() events.OnEvent(events, "PLAYER_LEVEL_UP") end) == 1)
  -- the strip off: no way in
  slash("strip off")
  check("with the strip off the table says so and holds no card", HelloLinkAssist.strip == false and #HelloLinkAssist.cards == 0)
  check("...and no look is made", looked(function() tick(600); tick(0.1) end) == 0)
  check("...not even at a moment", looked(function() events.OnEvent(events, "PLAYER_LEVEL_UP") end) == 0)
  slash("strip on"); tick(0.1)
  -- the last 20 slots are for questions, counted now: /hlink uses slots too
  slotFile.slots = ns.SlotsUsed() + 23
  tick(600); tick(0.1)                            -- a look: 22 are left
  slash(""); slash("")                            -- two by hand: 20 are left
  check("with 20 slots left the fixed times make no look", ns.AssistLeft() == 20 and looked(function() tick(600); tick(0.1) end) == 0)
  check("...nor a moment", looked(function() events.OnEvent(events, "PLAYER_LEVEL_UP") end) == 0)
  HelloForeverAssist.ask = { n = 4, topic = "session", t = 1794516378 }
  tick(1)
  check("...but a question does", looked(function() tick(3) end) == 1)
  slash("strip on"); slash("strip depth auto"); tick(0.1)
  -- object 13: the acknowledgement (docs/specs/115.md, section 6)
  HelloForeverAssist = nil
  check("object 13 says null without HelloForever", has(watch(35), '[13, 0, "null"]'))
  HelloForeverAssist = { on = false, lang = "en" }
  check("...and with its assistant off", has(watch(35), '[13, 0, "null"]'))
  HelloLinkAssist.seq, HelloLinkAssist.re, HelloLinkAssist.taken, HelloLinkAssist.refused = 12, 3, 1, 0
  local function on(o)
    local t = { on = true, lang = "en", ask = { n = 4, topic = "session", t = 1794516375 }, shown = "bags" }
    for k, v in pairs(o or {}) do t[k] = v end
    return t
  end
  HelloForeverAssist = on()
  check("object 13: the set the game took, the last question, the slots left and the card shown",
    has(watch(35), '[13, 0, "{\\"on\\": true, \\"lang\\": \\"en\\", \\"seq\\": 12, \\"re\\": 3, \\"ask\\": {\\"n\\": 4, \\"topic\\": \\"session\\", \\"t\\": 1794516375}, \\"left\\": '
      .. tostring(HelloLinkAssist.left) .. ', \\"taken\\": 1, \\"refused\\": 0, \\"shown\\": \\"bags\\"}"]'))
  HelloForeverAssist = on({ ask = false, shown = false })
  HelloForeverAssist.ask, HelloForeverAssist.shown = nil, nil
  local none = watch(35)
  check("object 13: no question and no card are null", has(none, '\\"ask\\": null, \\"left\\": ') and has(none, '\\"shown\\": null}"]'))
  for _, bad in ipairs({ { lang = "x y" }, { lang = 7 }, { shown = "a b" }, { ask = { n = 0, topic = "session", t = 1 } },
      { ask = { n = 1, topic = "a b", t = 1 } }, { ask = "session" } }) do
    HelloForeverAssist = on(bad)
    local k, v = next(bad)
    check("object 13 is null when HelloForever's table is not as the spec has it (" .. k .. " = " .. tostring(type(v) == "table" and "table" or v) .. ")",
      has(watch(35), '[13, 0, "null"]'))
  end
  HelloForeverAssist = nil
  C_AddOns.LoadAddOn = realLoad
  slotFile = { seq = 0, text = "" }
end

-- ---------------- the gear, the bags slot by slot, the bank (objects 14, 15, 16; #138) ----------------
do
  LINKS[16] = "|cff1eff00|Hitem:16866:1887:::::-9:123:34::::|h[Ranger Bow]|h|r"
  DUR[1], GEAR[2] = false, false            -- slot 1 without durability, slot 2 empty
  events.OnEvent(events, "PLAYER_EQUIPMENT_CHANGED")
  local g = watch(40)
  check("object 14: an equipped slot with its item, the enchant and the random suffix from its link, its durability",
    has(g, '\\"16\\": {\\"item\\": 2504, \\"enchant\\": 1887, \\"suffix\\": -9, \\"dur\\": [50, 60]}'))
  check("...a slot without enchant or suffix has them null; an item without durability has dur null",
    has(g, '\\"1\\": {\\"item\\": 2504, \\"enchant\\": null, \\"suffix\\": null, \\"dur\\": null}'))
  check("...an empty slot is left out", not has(g, '\\"2\\": {') and has(g, '\\"3\\": {'))
  LINKS[5] = SECRET
  events.OnEvent(events, "PLAYER_EQUIPMENT_CHANGED")
  check("a secret link makes the gear unreadable, not a slot without enchant", has(watch(40), '[14, 255, null]'))
  LINKS[5] = nil; LINKS[16] = nil; DUR[1], GEAR[2] = nil, nil
  events.OnEvent(events, "PLAYER_EQUIPMENT_CHANGED")
  local b = watch(40)
  check("object 15: each bag slot by slot, empty slots left out, a bag of no slots left out",
    -- format 0 (plain) or 1 (Deflate, when that is shorter): the reader gives the same text
    has(b, '"{\\"bags\\": [{\\"bag\\": 0, \\"size\\": 48, \\"family\\": 0, \\"slots\\": [[1, 2318, 14], [2, 4234, 3], [3, 2318, 2]]}]}"]')
    and (has(b, '"object": [15, 0, "{') or has(b, '"object": [15, 1, "{')), b:match('"object": %[15, .-%]"?%]') or "no object 15")
  -- the ammunition's count alone is no new version (a shot takes one, #44)
  P.ammo = 2512
  BAGS[0][4] = { itemID = 2512, stackCount = 200 }
  events.OnEvent(events, "BAG_UPDATE")
  watch(40)
  local function version15(text) local v for x in text:gmatch('"chunk": %[15, (%d+),') do v = x end return v end
  local v1 = version15(watch(40))
  BAGS[0][4].stackCount = 199
  events.OnEvent(events, "BAG_UPDATE")
  local v2 = version15(watch(40))
  check("a shot (the ammunition's count alone) makes no new version of object 15", v1 ~= nil and v1 == v2, tostring(v1) .. " " .. tostring(v2))
  BAGS[0][4], P.ammo = nil, nil
  events.OnEvent(events, "BAG_UPDATE")
  -- the bank
  check("object 16 is null while the bank is closed", has(watch(40), '[16, 0, "null"]'))
  BAGS[6] = { { itemID = 9999, stackCount = 5 } }
  events.OnEvent(events, "BANKFRAME_OPENED")
  check("open, it has the purchased tabs slot by slot", has(watch(40), '[16, 0, "{\\"tabs\\": [{\\"bag\\": 6, \\"size\\": 98, \\"slots\\": [[1, 9999, 5]]}]}"]'))
  events.OnEvent(events, "BANKFRAME_CLOSED")
  check("...and null again when it closes (the last bank seen is not kept)", has(watch(40), '[16, 0, "null"]'))
  -- review of #139: a read that fails is never a smaller bank, a gear slot without enchant,
  -- a character without class, or bags in which a shot looks like a change
  local realFetch = C_Bank.FetchPurchasedBankTabIDs
  events.OnEvent(events, "BANKFRAME_OPENED")
  C_Bank.FetchPurchasedBankTabIDs = function(kind) if kind == 2 then error("not now") end return realFetch(kind) end
  events.OnEvent(events, "PLAYERBANKSLOTS_CHANGED")
  check("the account's tabs cannot be read: the bank is unreadable, not the character's tabs alone", has(watch(40), '[16, 255, null]'))
  C_Bank.FetchPurchasedBankTabIDs = function() return SECRET end
  events.OnEvent(events, "PLAYERBANKSLOTS_CHANGED")
  local secretBank = watch(40)
  check("secret tab lists: the bank is unreadable, not a bank of no tabs", has(secretBank, '[16, 255, null]') and not has(secretBank, '\\"tabs\\": []'))
  C_Bank.FetchPurchasedBankTabIDs = realFetch
  events.OnEvent(events, "BANKFRAME_CLOSED"); watch(40)
  BAGS[6] = nil
  LINKS[16] = "|cffa335ee|Hitem:16866:1887:::::-9:123:34::::Player-1234-0ABCDEF0:|h[Ranger Bow]|h|r"
  events.OnEvent(events, "PLAYER_EQUIPMENT_CHANGED")
  check("a crafted item's link (a crafter's GUID after the fields) keeps its enchant and suffix",
    has(watch(40), '\\"16\\": {\\"item\\": 2504, \\"enchant\\": 1887, \\"suffix\\": -9'))
  LINKS[16] = "|cff1eff00|Hitem:16866:abc:::::-9:|h[Ranger Bow]|h|r"
  events.OnEvent(events, "PLAYER_EQUIPMENT_CHANGED")
  check("an enchant field that is no number makes the gear unreadable, not an item without enchant", has(watch(40), '[14, 255, null]'))
  LINKS[16] = "|cff1eff00|Hitem:16866:2564::::::|h[Ranger Bow]|h|r"
  events.OnEvent(events, "UNIT_INVENTORY_CHANGED", "player")
  check("an enchant put on worn gear (UNIT_INVENTORY_CHANGED alone) is sent", has(watch(40), '\\"16\\": {\\"item\\": 2504, \\"enchant\\": 2564, \\"suffix\\": null'))
  LINKS[16] = nil
  events.OnEvent(events, "PLAYER_EQUIPMENT_CHANGED"); watch(40)
  P.ammo = SECRET
  events.OnEvent(events, "BAG_UPDATE")
  local noAmmo = watch(40)
  check("the ammunition cannot be read: bags and bag slots are unreadable, a shot not being known from a change",
    has(noAmmo, '[4, 255, null]') and has(noAmmo, '[15, 255, null]'))
  P.ammo = nil
  events.OnEvent(events, "BAG_UPDATE"); watch(40)
  local realClass, realRace = UnitClass, UnitRace
  UnitClass = function() return "Hunter", SECRET, 3 end
  events.OnEvent(events, "PLAYER_ENTERING_WORLD")
  check("a secret class makes the who object unreadable, not a character of class null", has(watch(40), '[10, 255, null]'))
  UnitClass, UnitRace = realClass, function() error("not now") end
  events.OnEvent(events, "PLAYER_ENTERING_WORLD")
  check("a race the client fails to give makes the who object unreadable", has(watch(40), '[10, 255, null]'))
  UnitRace = function() return nil end
  events.OnEvent(events, "PLAYER_ENTERING_WORLD")
  check("a race the client says nothing about is null", has(watch(40), '\\"race\\": null}"]'))
  UnitRace = realRace
  events.OnEvent(events, "PLAYER_ENTERING_WORLD"); watch(40)
end

-- ---------------- the trainer window (object 17, #141) ----------------
-- The calls as this client's own trainer UI makes them (Blizzard_TrainerUI, forever branch).
do
  local TR = { guid = "Creature-0-6848-0-12-1700-0000ABCDEF", trade = true, step = 3, kind = 2,
    filter = { available = true, unavailable = true, used = true },
    services = {
      { "Skinning", "used", 1, "Apprentice", nil, 10 },
      { "Skinning", "available", 10, "Journeyman", { "Skinning", 50 }, 500 },
      { "Skinning", "unavailable", 35, "Artisan", { "Skinning", 200 }, 50000 },
    } }
  local realGuid = UnitGUID
  UnitGUID = function(u) if u == "npc" then return TR.guid end return realGuid(u) end
  Enum.TrainerType = { General = 0, TalentsObsolete = 1, Tradeskills = 2, Pet = 3 }
  C_Trainer = { GetTrainerType = function() return TR.kind end }
  GetNumTrainerServices = function() return #TR.services end
  GetTrainerServiceStepIndex = function() return TR.step end
  IsTradeskillTrainer = function() return TR.trade end
  GetTrainerServiceSkillLine = function(i) return TR.services[i] and "Skinning" end
  GetTrainerServiceTypeFilter = function(f) return TR.filter[f] end
  GetTrainerServiceInfo = function(i) local s = TR.services[i] return s[1], s[2], 136247, s[3], s[4], "" end
  GetTrainerServiceSkillReq = function(i) local r = TR.services[i][5] if r then return r[1], r[2], true end end
  GetTrainerServiceCost = function(i) return TR.services[i][6], TR.trade end
  local function trainer(text) return '\\"services\\": ' .. text end

  check("object 17 is null while no trainer window is open", has(watch(40), '[17, 0, "null"]'))
  events.OnEvent(events, "TRAINER_SHOW")
  local shown = watch(40)
  check("a profession trainer: its creature id, its profession, the stage it teaches (the step), the filter",
    has(shown, '"{\\"npc\\": 1700, \\"pet\\": false, \\"skill\\": \\"Skinning\\", \\"step\\": 3, \\"filter\\": {\\"available\\": true, \\"unavailable\\": true, \\"used\\": true}, '),
    shown:match('"object": %[17, .-%]"?%]') or "no object 17")
  check("...and each service: name, rank, state, required level, required skill [name, rank], cost",
    has(shown, trainer('[[\\"Skinning\\", \\"Apprentice\\", \\"used\\", 1, null, 10], [\\"Skinning\\", \\"Journeyman\\", \\"available\\", 10, [\\"Skinning\\", 50], 500], [\\"Skinning\\", \\"Artisan\\", \\"unavailable\\", 35, [\\"Skinning\\", 200], 50000]]}"]')))
  TR.filter.used = false
  table.remove(TR.services, 1); TR.step = 2
  events.OnEvent(events, "TRAINER_UPDATE")
  check("the window's filter is carried: a list with a filter off is partial", has(watch(40), '\\"filter\\": {\\"available\\": true, \\"unavailable\\": true, \\"used\\": false}'))
  TR.services[1][6] = SECRET
  events.OnEvent(events, "TRAINER_UPDATE")
  check("a secret cost makes the object unreadable, not a service without cost", has(watch(40), '[17, 255, null]'))
  TR.services[1][6] = 500
  local realInfo = GetTrainerServiceInfo
  GetTrainerServiceInfo = function(i) if i == 2 then error("not now") end return realInfo(i) end
  events.OnEvent(events, "TRAINER_UPDATE")
  check("a service the client fails to give makes the object unreadable, not a shorter list", has(watch(40), '[17, 255, null]'))
  GetTrainerServiceInfo = function(i) if i == 2 then return nil, "available", 1, 1, "" end return realInfo(i) end
  events.OnEvent(events, "TRAINER_UPDATE")
  check("a name the client does not have yet: unreadable until it comes", has(watch(40), '[17, 255, null]'))
  GetTrainerServiceInfo = realInfo
  events.OnEvent(events, "TRAINER_SERVICE_INFO_NAME_UPDATE")
  check("...and read when the client says the name came (TRAINER_SERVICE_INFO_NAME_UPDATE)",
    has(watch(40), trainer('[[\\"Skinning\\", \\"Journeyman\\", \\"available\\", 10, [\\"Skinning\\", 50], 500], ')))
  TR.trade, TR.step, TR.guid = false, nil, "Player-1-0000BEEF"
  TR.filter.used = true
  TR.services = { { "Battle Shout", "available", 1, "", nil, 10 } }
  events.OnEvent(events, "TRAINER_UPDATE")
  check("a class trainer that is no creature: npc, skill and step null, an empty rank null",
    has(watch(40), '"{\\"npc\\": null, \\"pet\\": false, \\"skill\\": null, \\"step\\": null, \\"filter\\": {\\"available\\": true, \\"unavailable\\": true, \\"used\\": true}, \\"services\\": [[\\"Battle Shout\\", null, \\"available\\", 1, null, 10]]}"]'))
  TR.kind = 3
  TR.services = { { "Growl", "available", 10, "Rank 2", nil, 10 } }
  events.OnEvent(events, "TRAINER_UPDATE")
  check("a pet trainer says so: its costs are pet training points, not copper",
    has(watch(40), '\\"pet\\": true, \\"skill\\": null, \\"step\\": null, \\"filter\\": {\\"available\\": true, \\"unavailable\\": true, \\"used\\": true}, \\"services\\": [[\\"Growl\\", \\"Rank 2\\", \\"available\\", 10, null, 10]]}"]'))
  TR.kind = SECRET
  events.OnEvent(events, "TRAINER_UPDATE")
  check("a secret trainer type makes the object unreadable, not costs in copper", has(watch(40), '[17, 255, null]'))
  TR.kind, TR.trade, TR.services = 2, true, {}
  events.OnEvent(events, "TRAINER_UPDATE")
  check("a profession trainer whose filter hides every service: skill not known (null), no services",
    has(watch(40), '\\"pet\\": false, \\"skill\\": null, \\"step\\": null, \\"filter\\": {\\"available\\": true, \\"unavailable\\": true, \\"used\\": true}, \\"services\\": []}"]'))
  -- a step past the end of the services (seen in the game on 16 Nov 2026, #160): not an index
  TR.step = 2
  events.OnEvent(events, "TRAINER_UPDATE")
  check("a step with no services is not given: step null (#160)", has(watch(40), '\\"step\\": null, \\"filter\\"') and not has(watch(1), '\\"step\\": 2'))
  TR.services = { { "Skinning", "available", 0, "Artisan", { "Skinning", 200 }, 45000 } }
  events.OnEvent(events, "TRAINER_UPDATE")
  check("a step past the end of the services is not given, and the profession is read from the list",
    has(watch(40), '\\"skill\\": \\"Skinning\\", \\"step\\": null, '))
  TR.step = 0
  events.OnEvent(events, "TRAINER_UPDATE")
  check("a step of 0 is not given", has(watch(40), '\\"skill\\": \\"Skinning\\", \\"step\\": null, '))
  TR.step = 1
  events.OnEvent(events, "TRAINER_UPDATE")
  check("a step in the list is kept", has(watch(40), '\\"skill\\": \\"Skinning\\", \\"step\\": 1, '))
  TR.step, TR.services = nil, {}
  local realTrade = IsTradeskillTrainer
  IsTradeskillTrainer = function() return SECRET end
  events.OnEvent(events, "TRAINER_UPDATE")
  check("a secret answer to 'a profession trainer?' makes the object unreadable", has(watch(40), '[17, 255, null]'))
  IsTradeskillTrainer = realTrade
  events.OnEvent(events, "TRAINER_CLOSED")
  check("null again when the window closes (the last trainer seen is not kept)", has(watch(40), '[17, 0, "null"]'))
  UnitGUID = realGuid
end

-- ---------------- the character's looks, taken at a barber (#168) ----------------
-- Saved data only: HelloLinkDB.looks, nothing on the strip. ASSUMED, not seen in the game: the
-- two event names, and the answer's fields, which are written here by hand from the client's
-- own documentation (BarberShopDocumentation.lua, CharacterCustomizationSharedDocumentation.lua).
do
  local from = ns.LooksFrom or function() return "no ns.LooksFrom" end
  local function count(t) local k = 0 for _ in pairs(t) do k = k + 1 end return k end
  local function option(id, at, ...)
    local o = { id = id, name = "an option", orderIndex = 1, optionType = 0, currentChoiceIndex = at, choices = {} }
    for i, choice in ipairs({ ... }) do o.choices[i] = { id = choice, name = "a choice" } end
    return o
  end
  local one = { { id = 3, name = "Body", chrModelID = 124, options = { option(501, 2, 7001, 7002, 7003), option(502, 1, 7100) } } }
  local models, choices = from(one)
  check("looks: each option's current choice, by the ids, as numbers",
    type(choices) == "table" and choices[501] == 7002 and choices[502] == 7100 and count(choices) == 2)
  check("looks: the category's model", type(models) == "table" and models[3] == 124 and count(models) == 1)

  models, choices = from({ { id = 3, options = { option(501, nil, 7001, 7002), option(502, 1, 7100) } } })
  check("looks: an option with no current choice is left out", type(choices) == "table" and choices[501] == nil
    and choices[502] == 7100 and count(choices) == 1)
  check("looks: a category with no model says false", type(models) == "table" and models[3] == false)

  models, choices = from({ one[1], { id = 9, name = "Other form", chrModelID = 125, options = { option(601, 3, 1, 2, 8003) } } })
  check("looks: two categories give the options of both, and a model each",
    type(choices) == "table" and choices[501] == 7002 and choices[502] == 7100 and choices[601] == 8003 and count(choices) == 3
    and models[3] == 124 and models[9] == 125 and count(models) == 2)

  check("looks: nothing, an empty answer, and an answer with no current choice give no record",
    from(nil) == nil and from({}) == nil and from("categories") == nil
    and from({ { id = 3, options = {} } }) == nil and from({ { id = 3, options = { option(501, nil, 7001) } } }) == nil)

  models, choices = from({ "no table", { name = "no id", options = { option(700, 1, 1) } }, { id = 4, options = "no table" },
    { id = 3, chrModelID = "124", options = { "no table", option("501", 1, 7001), option(503, 4, 7001), option(504, 1.5, 7001),
      { id = 505, currentChoiceIndex = 1 }, { id = 506, currentChoiceIndex = 1, choices = { { id = "7001" } } },
      { id = 507, currentChoiceIndex = 1, choices = { { id = SECRET } } }, option(502, 1, 7100) } } })
  check("looks: a field that is missing, secret or of another type leaves out that option only",
    type(choices) == "table" and choices[502] == 7100 and count(choices) == 1 and models[3] == false and models[4] == false and count(models) == 2)

  -- A secret in any one place is handed to issecretvalue first, and none of it reaches the
  -- result. The stub's SECRET is a table, so a type check alone would refuse it at the scalar
  -- places and take it at the table places: only the log shows that the guard was asked.
  local function clean(v, seen)
    if rawequal(v, SECRET) then return false end
    if type(v) ~= "table" then return true end
    seen = seen or {}
    if seen[v] then return true end
    seen[v] = true
    for k, x in pairs(v) do if not clean(k, seen) or not clean(x, seen) then return false end end
    return true
  end
  local function withSecret(at)   -- one category, one option, one choice; SECRET stands at `at`
    local function s(place, v) if place == at then return SECRET end return v end
    return s("answer", { s("category", { id = s("category id", 3), chrModelID = s("model", 124),
      options = s("option list", { s("option", { id = s("option id", 501), currentChoiceIndex = s("index", 1),
        choices = s("choice list", { s("choice", { id = s("choice id", 7001) }) }) }) }) }) })
  end
  for _, at in ipairs({ "category id", "model", "option id", "index", "choice id",
                        "answer", "category", "option list", "option", "choice list", "choice" }) do
    local log, realSecret = {}, issecretvalue
    issecretvalue = function(v) if rawequal(v, SECRET) then log[#log + 1] = "asked" end return realSecret(v) end
    local ok, m, c = pcall(from, withSecret(at))
    issecretvalue = realSecret
    check("looks: a secret " .. at .. " is handed to issecretvalue, and none of it is kept",
      ok and #log > 0 and clean(m) and clean(c), ("ok %s, asked %d"):format(tostring(ok), #log))
  end

  -- the events
  local KEY = "FakeHunter-TestRealm"
  UnitSex = function() return 3 end
  local answer = one
  C_BarberShop = { GetAvailableCustomizations = function() return answer end }
  HelloLinkDB.looks = nil
  events.OnEvent(events, "BARBER_SHOP_OPEN")
  local rec = type(HelloLinkDB.looks) == "table" and HelloLinkDB.looks[KEY]
  check("looks: sitting in the chair writes the record under the character's name and realm",
    type(rec) == "table" and rec.choices[501] == 7002 and rec.choices[502] == 7100 and rec.models[3] == 124, rec)
  check("...with the client's time, the race's file name and the sex", rec and rec.at == 1794516378 and rec.race == "NightElf" and rec.sex == 3
    and count(rec) == 5)

  answer = nil
  events.OnEvent(events, "BARBER_SHOP_OPEN")
  check("looks: an answer of nothing keeps the older record", rec and HelloLinkDB.looks[KEY] == rec)
  C_BarberShop.GetAvailableCustomizations = function() error("not now") end
  events.OnEvent(events, "BARBER_SHOP_APPEARANCE_APPLIED")
  C_BarberShop = nil
  events.OnEvent(events, "BARBER_SHOP_APPEARANCE_APPLIED")
  check("...and so does a call that fails, and a client without the barber's functions", rec and HelloLinkDB.looks[KEY] == rec)

  answer = { { id = 3, chrModelID = 124, options = { option(501, 3, 7001, 7002, 7003) } } }
  C_BarberShop = { GetAvailableCustomizations = function() return answer end }
  events.OnEvent(events, "BARBER_SHOP_APPEARANCE_APPLIED")
  local rec2 = HelloLinkDB.looks[KEY]
  check("looks: a new appearance applied replaces the record whole", rec2 ~= rec and type(rec2) == "table"
    and rec2.choices[501] == 7003 and rec2.choices[502] == nil)

  local name, sex, race = UnitName, UnitSex, UnitRace
  UnitName = function(u) if u == "player" then return SECRET end return name(u) end
  answer = one
  events.OnEvent(events, "BARBER_SHOP_OPEN")
  check("looks: no record when the character's name cannot be read", HelloLinkDB.looks[KEY] == rec2 and count(HelloLinkDB.looks) == 1)
  UnitName = name
  UnitSex, UnitRace = function() return SECRET end, function() error("not now") end
  events.OnEvent(events, "BARBER_SHOP_OPEN")
  local rec3 = HelloLinkDB.looks[KEY]
  check("looks: a race or a sex that cannot be read is left out; the choices are still written",
    rec3 ~= rec2 and type(rec3) == "table" and rec3.choices[501] == 7002 and rec3.race == nil and rec3.sex == nil)
  UnitSex, UnitRace = sex, race
  HelloLinkDB.looks, C_BarberShop = nil, nil
end

-- ---------------- the hearthstone (object 18, #180) ----------------
do
  local realTime = time
  local t0 = 1794516378
  time = function() return t0 + math.floor(now - 1000) end   -- the client's clock goes on, in whole seconds
  local function hearth(text) return '[18, 0, "' .. text .. '"]' end
  local function versions(text)
    local seen = {}
    for v in text:gmatch('"chunk": %[18, (%d+),') do seen[v] = true end
    local list = {}
    for v in pairs(seen) do list[#list + 1] = v end
    return list
  end
  local ready = watch(40)
  check("object 18: where the hearthstone is bound, its item id, and 0: ready now",
    has(ready, hearth('{\\"bind\\": \\"Gadgetzan\\", \\"item\\": 6948, \\"readyAt\\": 0}')),
    ready:match('"object": %[18, .-%]') or "no object 18")
  local usedAt = time()
  P.hcd = { now, 3600, 1 }
  local first = watch(40)
  local at = tonumber(first:match('readyAt\\": (%d+)}"%]'))
  check("after a use, readyAt is the Unix second the cooldown ends (within a second of use + 3600)",
    at ~= nil and math.abs(at - (usedAt + 3600)) <= 1, tostring(at))
  local later = watch(40)
  local v1, v2 = versions(first), versions(later)
  check("...and it does not change while the cooldown runs: one version over eight seconds",
    #v1 == 1 and #v2 == 1 and v1[1] == v2[1] and not later:find('readyAt\\": 0}', 1, true),
    table.concat(v1, ",") .. " / " .. table.concat(v2, ","))
  local READY = hearth('{\\"bind\\": \\"Gadgetzan\\", \\"item\\": 6948, \\"readyAt\\": 0}')
  local before = v2                    -- the cooldown above, still running
  P.hcd = { P.hcd[1], 3595, 1 }
  local told = watch(40)
  check("a duration told otherwise for the same cooldown start changes nothing: the same version",
    #before == 1 and table.concat(versions(told), ",") == before[1], table.concat(before, ",") .. " / " .. table.concat(versions(told), ","))
  P.hcd = "gcd"
  check("the global cooldown (1.5 s, still running) is not the hearthstone's: ready while it runs", has(watch(40), READY))
  P.hcd = { now, 20, 1 }
  watch(30)                            -- the last version of the global cooldown goes by
  local running = watch(20)
  check("a cooldown of 20 s: not ready while it runs", not has(running, READY) and running:find('readyAt\\": [1-9]') ~= nil)
  P.hcd = { P.hcd[1], 5, 1 }             -- 5 s into it, a shorter duration is told for the same start
  local shorter = watch(40)
  check("...a shorter duration told for the same start does not end it early",
    not has(shorter, READY) and shorter:find('readyAt\\": [1-9]') ~= nil)
  P.hcd = { P.hcd[1], 1.5, 1 }           -- even a duration as short as the global cooldown
  local gcdShort = watch(40)
  check("...nor does a duration of 1.5 s told for the same start",
    not has(gcdShort, READY) and gcdShort:find('readyAt\\": [1-9]') ~= nil)
  check("...and ready (0) once its end, as taken at the start, has passed", has(watch(200), READY))
  P.hcd = { P.hcd[1], 1.5, 1 }           -- after the end: 1.5 s, then a longer duration, for the same start
  watch(20)
  P.hcd = { P.hcd[1], 60, 1 }
  local longer = watch(40)
  check("...an ended cooldown does not come back when a longer duration is told for its start",
    has(longer, READY) and longer:find('readyAt\\": [1-9]') == nil)
  P.hcd = nil
  local realSecretBind = issecretvalue
  issecretvalue = function(v) return v == "Booty Bay" or realSecretBind(v) end   -- a good name, but secret
  P.bind = "Booty Bay"
  check("a secret bind is null, though it is a good name; the rest is still sent", has(watch(40), hearth('{\\"bind\\": null, \\"item\\": 6948, \\"readyAt\\": 0}')))
  issecretvalue = realSecretBind
  P.bind = "Gadgetzan"
  -- A secret value here is a number, so only the secret check can refuse it (a table would be
  -- refused by the type check as well).
  local realSecret = issecretvalue
  issecretvalue = function(v) return v == 77 or realSecret(v) end
  P.hcd = { 77, 3600, 1 }
  check("a secret cooldown start makes the object unreadable, never a time", has(watch(40), '[18, 255, null]'))
  P.hcd = { now, 77, 1 }
  check("a secret cooldown duration makes the object unreadable", has(watch(40), '[18, 255, null]'))
  P.hcd = nil
  P.hearths = 77
  check("a secret count makes the object unreadable, never a hearthstone", has(watch(40), '[18, 255, null]'))
  issecretvalue = realSecret
  P.hearths = nil
  check("a count the client does not give makes the object unreadable, not 'no hearthstone'", has(watch(40), '[18, 255, null]'))
  local realCount = GetItemCount
  GetItemCount = function() error("not now") end
  check("a count call that fails makes the object unreadable", has(watch(40), '[18, 255, null]'))
  GetItemCount = realCount
  P.hearths = 1
  P.hcd = "fails"
  check("a cooldown call that fails makes the object unreadable", has(watch(40), '[18, 255, null]'))
  P.hcd = nil
  check("...and the object is readable again when the calls answer", has(watch(40), READY))
  P.hearths = 0
  check("no hearthstone in the bags: null", has(watch(40), hearth('null')))
  P.hearths = 1
  time = realTime
end

-- ---------------- HelloLink 0.8.0: what the probe of 18 Nov 2026 saw answer ----------------
do
  local function q(json) return (json:gsub('"', '\\"')) end          -- as the reader prints an object's text
  local function obj(id, json) return ('[%d, 0, "%s"]'):format(id, q(json)) end
  local function unread(id) return ('[%d, 255, null]'):format(id) end
  local function version(id, text) local v for x in text:gmatch('"chunk": %[' .. id .. ', (%d+),') do v = x end return v end
  -- A secret here is a number, so only the secret check can refuse it (a table would be refused
  -- by a type check as well).
  local realSecret = issecretvalue
  local function secretly(v, f)
    issecretvalue = function(x) return x == v or realSecret(x) end
    local ok, got = pcall(f)
    issecretvalue = realSecret
    assert(ok, got)
    return got
  end

  -- object 15: each container's family
  FAMILY[0] = 1
  events.OnEvent(events, "BAG_UPDATE")
  check("object 15: a container says its family, the second value of GetContainerNumFreeSlots (a quiver: 1)",
    has(watch(40), q('{"bag": 0, "size": 48, "family": 1, "slots": [')))
  FAMILY[0] = 77
  events.OnEvent(events, "BAG_UPDATE")
  check("a secret family makes object 15 unreadable", secretly(77, function() return has(watch(40), unread(15)) end))
  FAMILY[0] = "none"
  events.OnEvent(events, "BAG_UPDATE")
  check("a family the client does not give makes object 15 unreadable, not 'any item'", has(watch(40), unread(15)))
  FAMILY[0] = nil
  events.OnEvent(events, "BAG_UPDATE")
  check("...and readable again", has(watch(40), q('{"bag": 0, "size": 48, "family": 0, "slots": [')))

  -- object 14: the ammunition, slot 0
  P.ammo, P.ammoCount = 3030, 2783
  events.OnEvent(events, "PLAYER_EQUIPMENT_CHANGED")
  local g1 = watch(40)
  check("object 14: slot 0 is the ammunition, its item and count, before slot 1",
    has(g1, q('{"slots": {"0": {"item": 3030, "count": 2783}, "1": {"item": 2504, ')), g1:match('"object": %[14, .-%]"?%]'))
  P.ammoCount = 2782
  events.OnEvent(events, "UNIT_INVENTORY_CHANGED", "player")
  local g2 = watch(40)
  check("a shot (the ammunition's count alone) makes no new version of object 14",
    version(14, g1) ~= nil and version(14, g2) == version(14, g1) and not has(g2, '2782'), tostring(version(14, g1)) .. " " .. tostring(version(14, g2)))
  DUR[3] = { 40, 60 }
  events.OnEvent(events, "UPDATE_INVENTORY_DURABILITY")
  local g3 = watch(40)
  check("...another change of the gear sends the count of now", version(14, g3) ~= version(14, g2)
    and has(g3, q('"0": {"item": 3030, "count": 2782}')) and has(g3, q('"3": {"item": 2504, "enchant": null, "suffix": null, "dur": [40, 60]}')))
  P.ammoCount = 77
  events.OnEvent(events, "PLAYER_EQUIPMENT_CHANGED")
  check("a secret ammunition count makes object 14 unreadable", secretly(77, function() return has(watch(40), unread(14)) end))
  local realCount = GetInventoryItemCount
  GetInventoryItemCount = nil
  events.OnEvent(events, "PLAYER_EQUIPMENT_CHANGED")
  check("without GetInventoryItemCount, ammunition makes object 14 unreadable, not a count", has(watch(40), unread(14)))
  GetInventoryItemCount = realCount
  P.ammo, P.ammoCount, DUR[3] = nil, nil, nil
  events.OnEvent(events, "PLAYER_EQUIPMENT_CHANGED")
  local g4 = watch(40)
  check("no ammunition: slot 0 is left out", has(g4, q('{"slots": {"1": {"item": 2504, ')) and not has(g4, q('"0": {')))

  -- object 19: the completed quests, never on a timer
  check("object 19: the completed quests by id, read at login", has(round, obj(19, '{"ids": [7, 33, 783]}')))
  local calls = DONE_CALLS
  for _ = 1, 400 do tick(0.1) end                 -- 40 s: past the 30 s safety net and every timer
  check("object 19 is not read again on a timer (" .. (DONE_CALLS - calls) .. " reads in 40 s)", DONE_CALLS == calls)
  DONE[#DONE + 1] = 900
  events.OnEvent(events, "QUEST_TURNED_IN", 900)
  check("...it is read again when a quest is turned in", has(watch(40), obj(19, '{"ids": [7, 33, 783, 900]}')))
  DONE[#DONE] = 77
  events.OnEvent(events, "QUEST_TURNED_IN", 77)
  check("a secret id makes object 19 unreadable", secretly(77, function() return has(watch(40), unread(19)) end))
  DONE[#DONE] = 900.5
  events.OnEvent(events, "QUEST_TURNED_IN")
  check("an id that is no whole number makes object 19 unreadable", has(watch(40), unread(19)))
  DONE[#DONE] = nil
  local realDone = C_QuestLog.GetAllCompletedQuestIDs
  C_QuestLog.GetAllCompletedQuestIDs = nil
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", true, false)
  check("without the client's function object 19 is unreadable (format 255)", has(watch(40), unread(19)))
  C_QuestLog.GetAllCompletedQuestIDs = realDone
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", false, true)
  check("...and read again at the next reload", has(watch(40), obj(19, '{"ids": [7, 33, 783]}')))
  calls = DONE_CALLS
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", false, false)   -- a loading screen into an instance
  watch(40)
  check("entering an instance (PLAYER_ENTERING_WORLD false, false) does not read object 19 (" .. (DONE_CALLS - calls) .. " reads)",
    DONE_CALLS == calls)

  -- object 20: the corpse
  check("object 20: alive, no corpse: null", has(watch(40), obj(20, 'null')))
  local cx, cy = 0.5, 0.25
  P.corpse = { GetXY = function() return cx, cy end }
  events.OnEvent(events, "PLAYER_DEAD")
  check("dead: the corpse's map and x, y as the fast block's position has them", has(watch(40), obj(20, '{"map": 1437, "x": 32768, "y": 16384}')))
  cx = 0.77
  events.OnEvent(events, "PLAYER_UNGHOST")
  check("a secret coordinate makes object 20 unreadable", secretly(0.77, function() return has(watch(40), unread(20)) end))
  cx = 1.5
  events.OnEvent(events, "ZONE_CHANGED_NEW_AREA")
  check("a coordinate out of the map makes object 20 unreadable", has(watch(40), unread(20)))
  P.corpse = nil
  events.OnEvent(events, "PLAYER_ALIVE")
  check("alive again: null", has(watch(40), obj(20, 'null')))
  local realDeath = C_DeathInfo
  C_DeathInfo = nil
  events.OnEvent(events, "PLAYER_DEAD")
  check("without C_DeathInfo object 20 is unreadable, not 'alive'", has(watch(40), unread(20)))
  C_DeathInfo = realDeath
  events.OnEvent(events, "PLAYER_ALIVE"); watch(40)

  -- object 21: the reputations
  local REP = obj(21, '[{"id": 72, "name": "Stormwind", "standing": 6, "value": 3200, "min": 3000, "max": 9000, "watched": true, "header": false}, '
    .. '{"id": null, "name": "Alliance", "standing": null, "value": null, "min": null, "max": null, "watched": false, "header": true}]')
  check("object 21: each faction in the client's order; a field the client does not give is null", has(watch(40), REP))
  REPS[1].currentStanding = 3300
  events.OnEvent(events, "UPDATE_FACTION")
  check("...read again on UPDATE_FACTION", has(watch(40), q('"value": 3300, ')))
  REPS[1].currentStanding = 77
  events.OnEvent(events, "UPDATE_FACTION")
  check("a secret field makes object 21 unreadable", secretly(77, function() return has(watch(40), unread(21)) end))
  REPS[1].currentStanding = 3200
  local realRep = C_Reputation
  C_Reputation = nil
  events.OnEvent(events, "UPDATE_FACTION")
  check("without C_Reputation object 21 is unreadable", has(watch(40), unread(21)))
  C_Reputation = realRep
  events.OnEvent(events, "UPDATE_FACTION")
  check("...and back", has(watch(40), REP))
  -- At most one read in 2 s, also when the reads change nothing; at a dwell of 0.05 s the carousel
  -- comes round faster than that. `least` is the shortest time between two reads.
  local function least(times)
    local l = 99
    for i = 2, #times do l = math.min(l, times[i] - times[i - 1]) end
    return #times >= 2 and l or nil
  end
  local function marked(event, wrap)
    local times = {}
    wrap(function() times[#times + 1] = now end)
    slash("strip dwell 5")
    for _ = 1, 160 do events.OnEvent(events, event); tick(0.05) end   -- 8 s, marked every frame
    slash("strip dwell 10")
    wrap(nil)
    return least(times)
  end
  local realNum = C_Reputation.GetNumFactions
  local gap = marked("UPDATE_FACTION", function(f)
    C_Reputation.GetNumFactions = f and function() f() return realNum() end or realNum
  end)
  check("object 21 is read at most once in 2 s, also when nothing changed (" .. tostring(gap) .. " s)", gap and gap >= 1.999)

  -- object 22: Auctionator's prices
  check("object 22: null without Auctionator", has(watch(40), obj(22, 'null')))
  local PRICES, AGES, registered, onUpdate = { [2318] = 95, [2504] = 1234, [9999] = 77 }, { [2318] = 2, [2504] = 0 }, 0, nil
  Auctionator = { API = { v1 = {
    GetAuctionPriceByItemID = function(caller, id) assert(caller == "HelloLink") if id == 4234 then error("no data") end return PRICES[id] end,
    GetAuctionAgeByItemID = function(_, id) return AGES[id] end,
    RegisterForDBUpdate = function(caller, fn) assert(caller == "HelloLink") registered, onUpdate = registered + 1, fn end } } }
  events.OnEvent(events, "BAG_UPDATE")
  check("object 22: each distinct item of the bags and the gear, by id: [id, copper, age in days]; no data and a failed call are null",
    has(watch(40), obj(22, '{"source": "Auctionator", "prices": [[2318, 95, 2], [2504, 1234, 0], [4234, null, null]]}')))
  PRICES[2318] = 120
  if onUpdate then onUpdate() end
  check("Auctionator's own update marks object 22", has(watch(40), q('[[2318, 120, 2], ')))
  BAGS[6] = { { itemID = 9999, stackCount = 5 } }
  events.OnEvent(events, "BANKFRAME_OPENED")
  AGES[2504] = 77
  check("with the bank open its items are there too; a secret price and a secret age are null",
    secretly(77, function() local w = watch(40) return has(w, q('[4234, null, null], [9999, null, null]]}')) and has(w, q('[2504, 1234, null]')) end))
  AGES[2504] = 0
  BAGS[6] = { { itemID = 9998, stackCount = 1 } }
  events.OnEvent(events, "PLAYERBANKSLOTS_CHANGED")
  check("a change of the bank's slots marks object 22", has(watch(40), q('[9998, null, null]]}')))
  BAGS[6] = { { itemID = 9997, stackCount = 1 } }
  events.OnEvent(events, "BANK_TABS_CHANGED")
  check("...and so does a change of its tabs", has(watch(40), q('[9997, null, null]]}')))
  events.OnEvent(events, "BANKFRAME_CLOSED")
  BAGS[6] = nil
  for _ = 1, 3 do events.OnEvent(events, "BAG_UPDATE"); watch(32) end
  check("Auctionator is asked once to tell of its updates (" .. registered .. ")", registered == 1)
  local realAge = Auctionator.API.v1.GetAuctionAgeByItemID
  local ahGap = marked("BAG_UPDATE", function(f)
    Auctionator.API.v1.GetAuctionAgeByItemID = f and function(c, id) if id == 2318 then f() end return realAge(c, id) end or realAge
  end)
  check("object 22 is read at most once in 2 s, also when nothing changed (" .. tostring(ahGap) .. " s)", ahGap and ahGap >= 1.999)
  BAGS[0][2].itemID = 77
  events.OnEvent(events, "BAG_UPDATE")
  check("a secret item id in the bags makes object 22 unreadable", secretly(77, function() return has(watch(40), unread(22)) end))
  BAGS[0][2].itemID = 4234
  -- With rawget no __index is called: neither _G's for the global, nor one on Auctionator's tables.
  local index, api = 0, Auctionator.API
  Auctionator = nil
  setmetatable(_G, { __index = function(_, k) if k == "Auctionator" then index = index + 1 return { API = api } end end })
  events.OnEvent(events, "BAG_UPDATE")
  local viaG = watch(40)
  setmetatable(_G, nil)
  Auctionator = setmetatable({}, { __index = function() index = index + 1 return api end })
  events.OnEvent(events, "BAG_UPDATE")
  local viaTable = watch(40)
  check("Auctionator is read with rawget: no __index is called, of _G or of its tables (" .. index .. ")",
    has(viaG, obj(22, 'null')) and has(viaTable, obj(22, 'null')) and index == 0)
  Auctionator = nil
  events.OnEvent(events, "BAG_UPDATE"); watch(40)

  -- object 23: the pet
  check("object 23: the pet's experience [current, needed]", has(watch(40), obj(23, '{"xp": [1200, 5600]}')))
  P.petUI = false
  events.OnEvent(events, "UNIT_PET", "player")
  check("no pet (HasPetUI false): null", has(watch(40), obj(23, 'null')))
  P.petUI, P.petXp = true, { 77, 5600 }
  events.OnEvent(events, "UNIT_PET_EXPERIENCE", "pet")
  check("a secret experience makes object 23 unreadable", secretly(77, function() return has(watch(40), unread(23)) end))
  local realUI = HasPetUI
  HasPetUI = nil
  events.OnEvent(events, "PET_UI_UPDATE")
  check("without HasPetUI object 23 is unreadable, not 'no pet'", has(watch(40), unread(23)))
  HasPetUI, P.petXp = realUI, { 1200, 5600 }
  events.OnEvent(events, "PET_UI_UPDATE"); watch(40)

  -- object 11: tags, quests, done; RXP's orphans and targets
  local orphaned = 0
  -- The shapes are RXPGuides' own (its installed source, read 19 Nov 2026): QuestLog.lua keeps
  -- orphanedList[questID] = { ... }; functions.lua gives isOnQuest and isQuestTurnedIn elements
  -- a list questIds; RXPGuides.lua keeps the step in RXPCData.guideProgress[guide.key].step.
  RXP = { GetOrphanedQuests = function() orphaned = orphaned + 1 error("GetOrphanedQuests must not be called") end,
    arrowFrame = { element = { zone = 1431, x = 50, y = 50, step = { index = 1 } } },
    currentGuide = { name = "G", steps = {
      { index = 1, text = "one", completed = true, elements = { { tag = "accept", questId = 33 }, { tag = "goto", zone = 1429, x = 50, y = 25 },
        { tag = "accept", questId = 34 }, { tag = "turnin", questId = 33 }, { tag = "bad tag", questId = 2.5 }, { tag = 7, questId = "35" },
        { tag = "isQuestTurnedIn", questIds = { 34, 36 } } } },
      { index = 2, text = "two", completed = false } } } }
  local steps = watch(40)
  check("object 11: a step's tags and quests, each once, in order, and whether it is done",
    has(steps, q('{"step": 1, "text": "one", "map": 1429, "x": 32768, "y": 16384, "tags": ["accept", "goto", "turnin", "isQuestTurnedIn"], "quests": [33, 34, 36], "done": true}, '
      .. '{"step": 2, "text": "two", "map": null, "x": null, "y": null, "tags": [], "quests": [], "done": false}], "orphans": [], "targets": null}')),
    steps:match('"object": %[11, .-%]"?%]'))
  do   -- an isOnQuest element may name many quests: all of them, not the first 20 (#192, review round 2)
    local many, want = {}, {}
    for k = 1, 30 do many[k] = 1000 + k; want[k] = tostring(1000 + k) end
    RXP.currentGuide.steps[2].elements = { { tag = "isOnQuest", questIds = many } }
    check("object 11: a step whose element names 30 quests sends all 30",
      has(watch(40), q('"tags": ["isOnQuest"], "quests": [' .. table.concat(want, ", ") .. '], "done": false}]')))
    -- 190 ids, 10 repeats, then a new one: the 200 are counted after the repeats (review round 3)
    local repeats, wantR = {}, {}
    for k = 1, 190 do repeats[k] = 2000 + k; wantR[k] = tostring(2000 + k) end
    for k = 191, 200 do repeats[k] = 2001 end
    repeats[201] = 3191; wantR[191] = "3191"
    RXP.currentGuide.steps[2].elements = { { tag = "isOnQuest", questIds = { unpack(repeats, 1, 100) } },
      { tag = "isOnQuest", questIds = { unpack(repeats, 101, 201) } } }
    check("object 11: the 200 quest ids are counted after the repeats are left out",
      has(watch(40), q('"quests": [' .. table.concat(wantR, ", ") .. '], "done": false}]')))
    RXP.currentGuide.steps[2].elements = nil
  end
  RXP.orphanedList = { [102] = { questID = 102, questLogIndex = 3 }, [77] = { questID = 77 }, [101] = { questID = 101 } }
  RXP.targeting = { GetCurrentTargets = function() return { "Defias Thug", "Defias Thug", 7 }, { "Murloc" }, {}, nil end }
  local more = secretly(77, function() return watch(40) end)
  check("RXP's orphaned quests as it keeps them (a secret id left out), and its four lists of names",
    has(more, q('"orphans": [101, 102], "targets": {"target": ["Defias Thug"], "mobs": ["Murloc"], "scan": [], "rares": []}}')), more:match('"object": %[11, .-%]"?%]'))
  check("RXP.GetOrphanedQuests is never called (it writes the list anew)", orphaned == 0)
  RXP.targeting.GetCurrentTargets = function() return 77 end
  check("a secret answer of the targeting is null", secretly(77, function() return has(watch(40), q('"targets": null}')) end))
  RXP.targeting.GetCurrentTargets = function() error("not now") end
  check("a targeting that fails is null; the orphans are sorted by id", has(watch(40), q('"orphans": [77, 101, 102], "targets": null}')))
  -- The arrow can point at the corpse: a waypoint with no step. The step is RXP's own record.
  RXP.currentGuide.key = "RestedXP|G"
  RXP.arrowFrame.element = { zone = 1431, x = 50, y = 50 }
  check("with the arrow at a corpse and no record of the step, the object is null", has(watch(40), obj(11, 'null')))
  RXPCData = { guideProgress = { ["RestedXP|G"] = { step = 2, stepId = 2 } } }
  check("...with RXP's record of the guide's step, the steps from that step", has(watch(40), q('"steps": [{"step": 2, "text": "two", ')))
  RXP.arrowFrame.element.step = { index = 1 }
  check("...and the record comes before the arrow's step", has(watch(40), q('"steps": [{"step": 2, "text": "two", ')))
  RXP, RXPCData = nil, nil

  -- HelloLinkDB.seen: which character is in the game, for a program that reads the saved file
  HelloLinkDB.seen = nil
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", true, false)
  local seen = HelloLinkDB.seen and HelloLinkDB.seen["FakeHunter-TestRealm"]
  check("the saved data says which character was in the game, under the key of object 10, with the time",
    type(seen) == "table" and seen.name == "FakeHunter" and seen.realm == "TestRealm" and seen.at == 1794516378)
  local realName = UnitName
  UnitName = function(u) if u == "player" then return SECRET end return realName(u) end
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", true, false)
  UnitName = realName
  local n = 0
  for _ in pairs(HelloLinkDB.seen) do n = n + 1 end
  check("...a name that cannot be read writes nothing", n == 1 and HelloLinkDB.seen["FakeHunter-TestRealm"] == seen)
  local realTime = time
  time = function() return 1794519999 end
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", false, false)   -- into an instance
  local after = HelloLinkDB.seen["FakeHunter-TestRealm"]
  check("...entering an instance does not write the login's time again", after == seen and after.at == 1794516378)
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", false, true)
  check("...a reload does", HelloLinkDB.seen["FakeHunter-TestRealm"].at == 1794519999)
  time = realTime
  events.OnEvent(events, "PLAYER_ENTERING_WORLD"); watch(40)
end

-- ---------------- a new UI session ----------------
local _, events2, row2 = load()
row, events = row2, events2
tick(0.1)
check("the next UI load has the next session number, and starts at depth 4 again",
  HelloLinkDB.session == session + 1 and has(read({ dump() }), ('"session": %d'):format(session + 1)))
-- A reload empties every global: HelloForever's table is gone until its next counted fight (#109).
HelloForeverBaseline = nil
check("after a reload the baseline object says null, and HelloLink keeps nothing of it",
  has(watch(30), '[12, 0, "null"]') and HelloLinkDB.baseline == nil)

print_real(("== %d checks, %d failed"):format(n, fails))
os.exit(fails == 0 and 0 or 1)
