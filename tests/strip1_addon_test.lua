-- The live-state strip, format 3: the addon draws a row in a stub client, and the Rust
-- reader (`hellolink render-rows`) reads it back.
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
UnitOnTaxi = function(u) return u == "player" and P.taxi or false end
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
local slotFile = { seq = 0, text = "" }   -- a slot as `hellolink install` leaves it
C_AddOns = { LoadAddOn = function() if not slotFile then return false, "MISSING" end HelloLink_Inbox = slotFile; return true end }

-- ---------------- the addon ----------------
local chunked = false   -- whether the last frame built carries a chunk (`watch` reads only those)
local function load()
  local ns = {}
  local first = #frames
  assert(loadfile("HelloLink/HelloLink.lua"))("HelloLink", ns)
  local assist = loadfile("HelloLink/Assist.lua")   -- 0.2.0 (#127); the looks' checks below need it
  if assist then assist("HelloLink", ns) end
  assert(loadfile("HelloLink/Strip.lua"))("HelloLink", ns)
  local real3 = ns.Strip2.frame3
  ns.Strip2.frame3 = function(b, session, dwell, seq, state, sending, ...)
    chunked = sending ~= nil
    return real3(b, session, dwell, seq, state, sending, ...)
  end
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
-- it prints the lines the Python tool printed, byte for byte (#195), about 40 times faster
-- (#193). `sh tests/run_all.sh` builds it first.
local function read(paths, step)
  return sh(("reader/target/release/hellolink render-rows --scale %.12f --step %g %s"):format(1 / unit, step or 0.1,
    table.concat(paths, " ")))
end
local function has(text, piece) return text:find(piece, 1, true) ~= nil end
-- `render-rows` joins only the objects sent as JSON (object formats 0 and 1); format 3's binary
-- objects (object format 2, docs/specs/232.md, part E) are read by `hellolink replay` from a
-- record of the frames. The lines of `rows` as a record, and replay's events; then the lines
-- that went into the record (the frame at replay's time t is the (10 t)th).
local records = 0
local function replay(rows)
  local record, framed = { '{"record": 1, "started": 1}' }, {}
  for line in rows:gmatch("[^\n]+") do
    local hex = line:match('"frame": "(%x+)"')
    if hex and line:find('"why": null', 1, true) then
      framed[#framed + 1] = line
      record[#record + 1] = ('{"t": %.1f, "frame": "%s", "depth": %s, "levels": %s, "more": %s}'):format(
        #framed * 0.1, hex, line:match('"depth": (%d+)'), line:match('"levels": (%b[])'), line:match('"more": (%b[])'))
    end
  end
  records = records + 1
  local path = ("%s/record_%03d.jsonl"):format(DIR, records)
  local f = assert(io.open(path, "w"))
  f:write(table.concat(record, "\n"), "\n")
  f:close()
  return sh("reader/target/release/hellolink replay " .. path), framed
end
-- The directory of a format 3 frame in hex (docs/specs/232.md, section 6): object id -> version.
-- The sections start at byte 9 (after version, session, dwell, seq and fixedLen); the directory
-- is section 2, three bytes an object.
local function directory(hex)
  local function byte(i) return tonumber(hex:sub(2 * i - 1, 2 * i), 16) end
  local dir, at, stop = {}, 9, 8 + byte(7) * 256 + byte(8)
  while at < stop do
    local id, len = byte(at), byte(at + 1)
    if id == 2 then
      for k = at + 2, at + len, 3 do dir[byte(k)] = byte(k + 1) * 256 + byte(k + 2) end
    end
    at = at + 2 + len
  end
  return dir
end
-- The version of object `id` that the directory of the last frame in `rows` names.
local function versionIn(rows, id)
  local last
  for hex in rows:gmatch('"frame": "(%x+)"') do last = hex end
  return last and directory(last)[id]
end

-- ---------------- one frame ----------------
tick(0.1)
local one = read({ dump() })
local session = HelloLinkDB.session
check("a first load draws format 3", has(one, '"format": 3'), one:sub(1, 300))
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
  -- on a flight path 4096 (HelloLink 2.1.0), read in the same frames as flying, so that the run's
  -- timing does not move (IsFlying is false on a real flight path: seen 15 Nov 2026)
  P.swimming, P.flying, P.taxi = false, true, true
  check("flying is 2048, on a flight path 4096 (2.1.0)", flags() == 128 + 2 + 1 + 2048 + 4096)
  P.flying = false
  -- a missing IsFlying counts as false, and 4096 stands on its own, as on a real flight path where
  -- IsFlying is false (review of #318)
  local realFly = IsFlying
  IsFlying = nil
  local f, unknown = flags()
  check("a missing function counts as false: the group stays readable; on a flight path without flying, 4096 alone",
    f == 128 + 2 + 1 + 4096 and not unknown)
  P.taxi = false
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
-- one clock (docs/specs/232.md, section 4 B): with a dwell of 1 s a frame is built once in the
-- second; the updates between build nothing and read no fast state, and the frame stays up
local reads = 0
local realMoney = GetMoney
GetMoney = function() reads = reads + 1; return realMoney() end
slash("strip dwell 100")
tick(1.0); tick(0.1)                              -- a frame has just gone up; it stays for a second
local first = read({ dump() })
local readsBefore = reads
tick(0.1); tick(0.1); tick(0.1)
local same = read({ dump() })
check(("one clock: inside a dwell of 1 s no frame is built, the fast state is not read again (%d, %d), the same seq stays up")
  :format(readsBefore, reads), reads >= 1 and reads == readsBefore and first:match('"seq": (%d+)') ~= nil and same:match('"seq": (%d+)') == first:match('"seq": (%d+)')
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
tick(1.0)                                         -- the dwell of 1 s is over: the next frame
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
-- The carousel of format 3 (docs/specs/213.md, section 7; docs/specs/232.md, section 6) builds a
-- marked object at its turn of the scan, one id every second decision: the 27 ids in 5.4 s. So a
-- change goes whole within about 6 s; `watch(steps)` watches 4 s more than the steps it names
-- (written for format 1's carousel, whose round was 3.2 s). Of those frames it reads the ones that
-- carry a chunk, and the last: a frame without a chunk holds only the fast state, the ring and the
-- directory, which every frame holds (and the test's time is in reading frames).
-- The rows of those frames, then each object replay gives whole as `[id, format, text]`, the
-- shape render-rows gives an object in: the binary objects (object format 2) read as their JSON.
-- Format 3 sends an object whose bytes did not change again only in its refresh round (a minute
-- or so), and the directory of every frame tells a reader that its copy is still the newest
-- (docs/specs/232.md, section 4 A). So, as a reader would, `watch` also gives the copy seen whole
-- in an earlier watch when the last frame's directory still names its version.
local held = {}   -- object id -> { version, line }, of this session
local function watch(steps)
  local paths = {}
  for k = 1, steps + 40 do
    chunked = false
    tick(0.1)
    if chunked or k == steps + 40 then paths[#paths + 1] = dump() end
  end
  local rows = read(paths)
  local got, fresh = { rows }, {}
  local told, framed = replay(rows)
  local session = framed[1] and framed[1]:match('"session": (%d+)')
  if held.session ~= session then held = { session = session } end
  for line in told:gmatch("[^\n]+") do
    if line:find('"kind": "object"', 1, true) then
      local id = tonumber(line:match('"id": (%d+)'))
      got[#got + 1] = ("[%d, %s, %s]"):format(id, line:match('"format": (%d+)'), line:match('"text": (.*)}$'))
      local at = framed[math.floor(tonumber(line:match('"t": ([%d.]+)')) * 10 + 0.5)]
      local version = at and tonumber(at:match(('"chunk": %%[%d, (%%d+),'):format(id)))
      held[id], fresh[id] = { version, got[#got] }, true
    end
  end
  local last = framed[#framed]
  for id, version in pairs(last and directory(last:match('"frame": "(%x+)"')) or {}) do
    if not fresh[id] and held[id] and held[id][1] == version then got[#got + 1] = held[id][2] end
  end
  return table.concat(got, "\n")
end
-- A binary object as `watch` gives it: object format 2, and the JSON the reader gives for it,
-- compact, its keys sorted (docs/specs/232.md, part E; docs/STRIP.md, section 3).
local function bin(id, json) return ('[%d, 2, "%s"]'):format(id, (json:gsub('[\\"]', '\\%0'))) end
events.OnEvent(events, "PLAYER_ENTERING_WORLD", true, false)   -- the login, as the client sends it after the UI loads: object 19 is read then
local round = watch(50)   -- a round of the twenty-two objects 2 to 23, and some of the next
check("the target object, with the creature's id and its reaction to the player (#82)",
  has(round, bin(2, '{"class":"normal","id":1984,"level":23,"name":"Wetlands Crocolisk","reaction":4,"type":"Beast"}')))
do
  -- The id is the sixth part of a creature's or a vehicle's GUID; the reaction a whole number 1 to 8.
  local guid, reaction = T.guid, T.reaction
  local function target(g, r)
    T.guid, T.reaction = g, r
    events.OnEvent(events, "PLAYER_TARGET_CHANGED")
    local last
    for id, re in watch(32):gmatch('\\"id\\":([%w]+),\\"level\\":23,\\"name\\":\\"Wetlands Crocolisk\\",\\"reaction\\":([%w]+),') do
      last = id .. " " .. re
    end
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
  has(round, bin(3, '{"instance":false,"instanceMap":0,"instanceName":"Eastern Kingdoms","instanceType":"none","map":1437,'
    .. '"sub":"Black Channel Marsh","zone":"Wetlands"}')))
do
  -- the instance's four keys of the last place object, as `'instance':true,'instanceMap':36,...`
  local function place()
    events.OnEvent(events, "PLAYER_ENTERING_WORLD")
    local last
    for found in watch(40):gmatch('{(\\"instance\\":.-),\\"map\\":1437,\\"sub\\":\\"Black Channel Marsh\\"') do last = found end
    return last and last:gsub('\\"', "'")
  end
  INSTANCE = { inside = true, kind = "party", name = "The Deadmines", map = 36 }
  check("in a dungeon: true, party, its map id and its name",
    place() == "'instance':true,'instanceMap':36,'instanceName':'The Deadmines','instanceType':'party'")
  INSTANCE = { inside = true, kind = "raid two", name = "bad \255", map = 70000 }
  check("a type that is not a word, a name that is not UTF-8 and a map id out of range are null",
    place() == "'instance':true,'instanceMap':null,'instanceName':null,'instanceType':null")
  INSTANCE = { inside = true, kind = "party", name = "The Deadmines", map = 36.5 }
  check("a map id that is no whole number is null", place():find("'instanceMap':null", 1, true) ~= nil)
  local realIn, realInfo = IsInInstance, GetInstanceInfo
  IsInInstance, GetInstanceInfo = nil, nil
  check("with no such functions the four keys are null, and the place object stays",
    place() == "'instance':null,'instanceMap':null,'instanceName':null,'instanceType':null")
  IsInInstance = function() return SECRET, "party" end
  GetInstanceInfo = function() return "The Deadmines", SECRET, 0, "", 0, 0, false, 36, 0 end
  check("a secret value makes that function's keys null, not the place object",
    place() == "'instance':null,'instanceMap':null,'instanceName':null,'instanceType':null")
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
    place() == "'instance':null,'instanceMap':36,'instanceName':'The Deadmines','instanceType':'party'")
  IsInInstance, GetInstanceInfo = realIn, function() error("no") end
  check("a GetInstanceInfo that fails leaves its three keys null, and `instance`",
    place() == "'instance':true,'instanceMap':null,'instanceName':null,'instanceType':null")
  IsInInstance, GetInstanceInfo = function() return "yes", "party" end, realInfo
  check("an IsInInstance that gives no boolean is null",
    place() == "'instance':null,'instanceMap':36,'instanceName':'The Deadmines','instanceType':'party'")
  IsInInstance, GetInstanceInfo = realIn, realInfo
  INSTANCE = { inside = false, kind = "none", name = "Eastern Kingdoms", map = 0 }
  check("... and back to none outside", place() == "'instance':false,'instanceMap':0,'instanceName':'Eastern Kingdoms','instanceType':'none'")
end
check("the bags object: stacks of one item summed, ordered by id", has(round, bin(4, '{"free":12,"items":[[2318,16],[4234,3]]}')))
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
-- format 3's carousel (docs/specs/213.md, section 7): each new version goes up, the one that waits
-- longest first, and goes once again 1 s later; every object 2 to 23 has its chunks in the round
local ids, upIds, all = {}, {}, true
for id in round:gmatch('"chunk": %[(%d+),') do
  if ids[#ids] ~= tonumber(id) then ids[#ids + 1] = tonumber(id) end
  upIds[tonumber(id)] = true
end
for id = 2, 23 do all = all and upIds[id] == true end
check("every object 2 to 23 goes up in the first round (" .. table.concat(ids, " ") .. ")", all)
check("with no route addon the route object says null (#64)", has(round, bin(9, 'null')))
-- Object 10 (#68): which character is in the game.
check("the who object: the character's name and realm, its class and race (#138), the full name from the loot above (0.8.1)",
  has(round, '[10, 0, "{\\"name\\": \\"FakeHunter\\", \\"realm\\": \\"TestRealm\\", \\"class\\": \\"HUNTER\\", \\"race\\": \\"NightElf\\", '
    .. '\\"fullName\\": \\"FakeHunter Family\\", \\"fullNameSource\\": \\"loot\\", \\"guid\\": \\"Player-1-0000ABCD\\", \\"realmSaved\\": null, \\"talents\\": null}"]'))
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
  -- since 20 Nov 2026 this client gives "" for the realm: that is its answer, not a failed read, so the
  -- realm stays "" in object 10; the character is seen under its GUID (1.18.0, spec 276)
  local keptRealm = GetRealmName
  GetRealmName = function() return "" end
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", true, false)
  check("an empty realm is the realm \"\", not \x27cannot be read\x27",
    has(watch(30), '[10, 0, "{\\"name\\": \\"FakeHunter\\", \\"realm\\": \\"\\", \\"class\\": \\"HUNTER\\"'))
  check("...and the character is seen under its GUID, with the realm \"\"", type(HelloLinkDB.seen) == "table"
    and type(HelloLinkDB.seen["Player-1-0000ABCD"]) == "table" and HelloLinkDB.seen["Player-1-0000ABCD"].realm == ""
    and HelloLinkDB.seen["Player-1-0000ABCD"].guid == "Player-1-0000ABCD")
  GetRealmName = keptRealm
  events.OnEvent(events, "PLAYER_ENTERING_WORLD")
  watch(30)
end
-- Objects 7 and 8 (#62): where a guide addon's arrow points, and the rested XP.
check("with no guide addon the waypoint object says null", has(round, '[7, 0, "null"]'))
check("the rest object: 0 when the client gives nothing", has(round, bin(8, '{"rested":0}')))
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
    .. '{\\"step\\": 1, \\"text\\": \\"one\\", \\"map\\": null, \\"x\\": null, \\"y\\": null, \\"tags\\": [], \\"quests\\": [], \\"done\\": false, \\"elements\\": [], \\"lines\\": []}, '
    .. '{\\"step\\": 2, \\"text\\": \\"two\\", \\"map\\": 1429, \\"x\\": 32768, \\"y\\": 16384, \\"tags\\": [], \\"quests\\": [], \\"done\\": false, \\"elements\\": [[null, null], [null, null], [null, null]]}, '
    .. '{\\"step\\": 3, \\"text\\": null, \\"map\\": null, \\"x\\": null, \\"y\\": null, \\"tags\\": [], \\"quests\\": [], \\"done\\": false, \\"elements\\": [[null, null]]}, '
    .. '{\\"step\\": 4, \\"text\\": \\"four\\", \\"map\\": null, \\"x\\": null, \\"y\\": null, \\"tags\\": [], \\"quests\\": [], \\"done\\": false, \\"elements\\": []}, '
    .. '{\\"step\\": 5, \\"text\\": \\"five\\", \\"map\\": null, \\"x\\": null, \\"y\\": null, \\"tags\\": [], \\"quests\\": [], \\"done\\": false, \\"elements\\": []}], '
    .. '\\"orphans\\": [], \\"targets\\": null}"]'))
RXP.arrowFrame.element.step = { index = 5 }
check("at the guide's end there are fewer steps; a text over 400 bytes is cut to 397 and an ellipsis (#78)",
  has(watch(40), '\\"guide\\": \\"G\\", \\"steps\\": [{\\"step\\": 5, \\"text\\": \\"five\\", \\"map\\": null, \\"x\\": null, \\"y\\": null, \\"tags\\": [], \\"quests\\": [], \\"done\\": false, \\"elements\\": [], \\"lines\\": []}, '
    .. '{\\"step\\": 6, \\"text\\": \\"' .. ("y"):rep(397) .. '…\\", \\"map\\": null, \\"x\\": null, \\"y\\": null, \\"tags\\": [], \\"quests\\": [], \\"done\\": false, \\"elements\\": []}]'))
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
    has(watch(40), '{\\"step\\": 2, \\"text\\": \\"a\\", \\"map\\": 1429, \\"x\\": 32768, \\"y\\": 16384, \\"tags\\": [], \\"quests\\": [], \\"done\\": false, \\"elements\\": [' .. ("[null, null], "):rep(19) .. '[null, null]]}, '
      .. '{\\"step\\": 3, \\"text\\": \\"b\\", \\"map\\": null, \\"x\\": null, \\"y\\": null, \\"tags\\": [], \\"quests\\": [], \\"done\\": false, \\"elements\\": [' .. ("[null, null], "):rep(19) .. '[null, null]]}]'))
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
  local WANT = bin(12, '{"counted":true,"died":[false,0,8],"dps":[38,31,8],"dur":[12,15,8],"fight":"' .. KEY
    .. '","id":1984,"level":14,"name":"Defias Thug","rev":1,"taken":[210,340,8]}')
  -- The versions of object 12 in the order they came, and the text of each.
  local function seen(text)
    local out, last = {}, nil
    for v in text:gmatch('"chunk": %[12, (%d+),') do if v ~= last then out[#out + 1] = tonumber(v); last = v end end
    local texts = {}
    for t in text:gmatch('%[12, 2, "(.-)"%]') do if texts[#texts] ~= t then texts[#texts + 1] = t end end
    return out, texts
  end
  HelloForeverBaseline = nil
  check("with no HelloForever (or before the first counted fight) the baseline object says null", has(watch(30), bin(12, 'null')))
  HelloForeverBaseline = good()
  check("the baseline object: the fight's key and rev, the enemy, the level and the triples, numbers rounded",
    has(watch(30), WANT))
  HelloForeverBaseline = good({ dur = { nil, nil, 2 }, dps = { 38, 31, 2 }, taken = { 210, 340, 3 }, died = { true, 1, 2 } })
  local unknown = watch(30)
  check("a value this fight does not know is null; usual and the death count are null under 3 earlier fights",
    has(unknown, '\\"died\\":[true,null,2],\\"dps\\":[38,null,2],\\"dur\\":[null,null,2],') and has(unknown, '\\"taken\\":[210,340,3]}"]'))
  HelloForeverBaseline = good({ name = "bad \255" })
  check("a name that is not UTF-8 is null; the object stays",
    has(watch(30), '\\"dur\\":[12,15,8],\\"fight\\":\\"' .. KEY .. '\\",\\"id\\":1984,\\"level\\":14,\\"name\\":null,\\"rev\\":1,'))
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
  -- The counted-false revision: only the fight, the revision and `counted`.
  HelloForeverBaseline = { fight = KEY, rev = 2, counted = false }
  all = all .. watch(32)
  HelloForeverBaseline = good({ rev = 3, dur = { 13, 15, 8 } })
  all = all .. watch(32)
  v, texts = seen(all)
  check("revisions 1 counted, 2 not, 3 counted are three versions, the last with the numbers (" .. table.concat(v, " ") .. ")",
    #v >= 3 and v[#v] ~= v[#v - 1] and v[#v - 1] ~= v[#v - 2] and #texts >= 3
    and texts[#texts - 1] == '{\\"counted\\":false,\\"fight\\":\\"' .. KEY .. '\\",\\"rev\\":2}'
    and texts[#texts]:find('{\\"counted\\":true,', 1, true) ~= nil and texts[#texts]:find('\\"rev\\":3,', 1, true) ~= nil
    and texts[#texts]:find('\\"dur\\":[13,15,8]', 1, true) ~= nil)
  HelloForeverBaseline = nil
  check("after /hello baseline reset (HelloForever clears the table) the object says null", has(watch(30), bin(12, 'null')))
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
    if not has(watch(32), bin(12, 'null')) then wrong[#wrong + 1] = i end
  end
  check("a baseline table with a value of the wrong kind or out of range is null (wrong: " .. table.concat(wrong, " ") .. ")", #wrong == 0)
  HelloForeverBaseline = good(); watch(32)
  HelloForeverBaseline = "not a table"
  check("a global that is no table is null", has(watch(32), bin(12, 'null')))
  HelloForeverBaseline = good(); watch(32)
  HelloForeverBaseline = good({ dur = { SECRET, 15, 8 } })
  check("a secret value in a triple is not used: it is null", has(watch(32), '\\"dur\\":[null,15,8],'))
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
      fine and has(got, bin(12, 'null')))
  end
  local called = 0
  HelloForeverBaseline = setmetatable({ fight = KEY, rev = 1, counted = true }, { __index = function() called = called + 1 return 5 end })
  check("HelloForever's table is read with no __index called: without its numbers it is null",
    has(watch(32), bin(12, 'null')) and called == 0)
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
  has(firstRoute, bin(9, '{"goal":{"map":1415,"title":"RestedXP","x":31934,"y":34315},"guided":true,"index":1,"legCount":1,'
    .. '"legs":[{"mode":"walk","seconds":40,"text":"Walk to RestedXP"}],"owner":"RestedXP","seconds":40,"source":"ShortestPathForever"}')))
J = { secondsLeft = 191.4, goal = { map = 1431, x = 0.5, y = 0.25 }, guided = false, index = 2,
  legs = { { mode = "walk", seconds = 30, text = "Walk to Sentinel Hill" }, { mode = "flight", seconds = 121, text = "Fly to Darkshire" },
           { mode = "walk", seconds = 40.2, text = "Walk 200 yards" } } }
local route = watch(40)
check("several legs in their order; no owner and no title are null; the seconds are whole",
  has(route, '{\\"goal\\":{\\"map\\":1431,\\"title\\":null,\\"x\\":32768,\\"y\\":16384},\\"guided\\":false,\\"index\\":2,\\"legCount\\":3,')
  and has(route, '\\"owner\\":null,\\"seconds\\":191,')
  and has(route, '[{\\"mode\\":\\"walk\\",\\"seconds\\":30,\\"text\\":\\"Walk to Sentinel Hill\\"},{\\"mode\\":\\"flight\\",\\"seconds\\":121,\\"text\\":\\"Fly to Darkshire\\"},{\\"mode\\":\\"walk\\",\\"seconds\\":40,'))
J.legs = {}
for i = 1, 25 do J.legs[i] = { mode = "walk", seconds = i, text = "Leg " .. i } end
route = watch(40)
check("more than 20 legs: the first 20, and legCount says how many there are",
  has(route, '\\"legCount\\":25,') and has(route, '\\"text\\":\\"Leg 20\\"}],') and not has(route, "Leg 21"))
J.legs = { { mode = 7, seconds = 0 / 0, text = "bad \255" }, { mode = "boat", seconds = -5, text = ("z"):rep(121) }, "not a leg" }
check("in a leg, a mode that is no word, seconds that are no amount and a text that is not UTF-8 or too long are null; what is no leg is left out",
  has(watch(40), '\\"legCount\\":3,\\"legs\\":[{\\"mode\\":null,\\"seconds\\":null,\\"text\\":null},{\\"mode\\":\\"boat\\",\\"seconds\\":null,\\"text\\":null}],'))
J.legs = { SECRET, { mode = "walk", seconds = 9, text = "After a secret" } }
check("a leg that is a secret value is counted and left out, and the next leg is read",
  has(watch(40), '\\"legCount\\":2,\\"legs\\":[{\\"mode\\":\\"walk\\",\\"seconds\\":9,\\"text\\":\\"After a secret\\"}],'))
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
check("200 legs are counted", has(watch(40), '\\"legCount\\":200,'))
J.legs[201] = { mode = "walk", seconds = 1, text = "L" }
check("with more than 200 legs how many there are is not known: null", has(watch(40), '\\"legCount\\":null,'))
for _, bad in ipairs({ { map = 0 / 0, x = 0.5, y = 0.5 }, { map = 1431, x = 1.5, y = 0.5 }, { map = 1431, x = 0.5, y = math.huge }, { map = 1431, x = SECRET, y = 0.5 }, "nowhere" }) do
  J = { secondsLeft = 5, goal = { map = 1431, x = 0.1, y = 0.1 }, legs = {}, index = 1 }; watch(40)
  J = { secondsLeft = 5, goal = bad, legs = {}, index = 1 }
  check("a goal that is no map and two fractions is no route: null", has(watch(40), bin(9, 'null')))
end
J = { secondsLeft = 0 / 0, goal = { map = 1431, x = 0.1, y = 0.1 }, legs = "none", index = 1.5, guided = "yes" }
check("a time left and an index that are no amount are null; legs that are no list are none; guided is true only for true",
  has(watch(40), '\\"guided\\":false,\\"index\\":null,\\"legCount\\":0,\\"legs\\":[],\\"owner\\":null,\\"seconds\\":null,'))
J = nil
check("no journey: null", has(watch(40), bin(9, 'null')))
ShortestPathForever.API.Journey = function() error("the route addon failed") end
J = { secondsLeft = 5, goal = { map = 1431, x = 0.1, y = 0.1 }, legs = {}, index = 1 }
check("a Journey that fails is null, and the row goes on", has(watch(40), bin(9, 'null')) and has(watch(5), '"row": true'))
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
check("rested XP after the client's event, as a whole number", has(watch(32), bin(8, '{"rested":12345}')))
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
check("no target: the object says null, a new version", has(gone, bin(2, 'null')))
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
-- The first is five chunks (600 letters and the format byte and check, 603 bytes, at 128 bytes a
-- chunk: docs/specs/232.md, section 6); the second is typed while it is on the row. Rounds are
-- counted by version: a round is the chunks 0 to count - 1 in order.
slash("send " .. ("first question "):rep(40))
-- the second is typed as soon as the first one's chunk 0 is on the row: its chunks 1 to 4 are
-- still to go (review of #309: a longer wait let the first be sent whole twice before it)
local early, v1 = "", nil
for _ = 1, 60 do
  tick(0.1)
  local seen = read({ dump() })
  early = early .. seen
  v1 = tonumber(seen:match('"chunk": %[1, (%d+), 0, 5'))
  if v1 then break end
end
check("the first question is five chunks", v1 ~= nil)
check("the second question is typed while the first one's first round has chunks to go",
  v1 ~= nil and not early:find('"chunk": %[1, %d+, [1-4], 5'))
slash("send second question")
local both = early .. watch(70)
-- A round of the question is the chunks 0 to count - 1 of object 1 in one version, seen in order.
-- Format 3 builds one frame a dwell, and `watch` captures one a dwell: each capture of a chunk is
-- one sending of it, and the second round can follow the first at once.
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
      if visit.nextIndex == count then visit.whole = true; close() end
    end
  end
end
close()
local v2
for v in pairs(rounds) do if v ~= v1 then v2 = v end end
check("the second question is read", has(both, '[1, 0, "second question"]'))
check("its version is the first one's plus one", v2 == (v1 + 1) % 65536)
check("and it is sent in two whole rounds of its own, whatever the first had left", rounds[v2] == 2, rounds[v2])

-- ---------------- a chunk stays for dwell, however fast the game runs ----------------
slash("strip dwell 5")
events.OnEvent(events, "PLAYER_TARGET_CHANGED")
local paths, order = {}, {}
for _ = 1, 200 do tick(0.01); paths[#paths + 1] = dump() end   -- 40 decisions: the refresh round's chunks go up
local fastrun = read(paths, 0.01)
local run, last = 0, nil
local shortest = 99
for id, index in fastrun:gmatch('"chunk": %[(%d+), %d+, (%d+)') do
  local key = id .. ":" .. index
  if key == last then run = run + 1 else if last then shortest = math.min(shortest, run) end run, last = 1, key end
end
check("at a dwell of 0.05 s and a frame every 0.01 s, every chunk is on the row for at least 4 captures", shortest >= 4)
-- every object whose last chunk went up comes whole, but for a version whose send began before
-- the run (its first chunk seen is not chunk 0: it cannot come whole here)
local fastObjects, ended, seen, before, whole = replay(fastrun), {}, {}, {}, true
for id, version, index, count in fastrun:gmatch('"chunk": %[(%d+), (%d+), (%d+), (%d+)') do
  local v = id .. ":" .. version
  if not seen[v] then seen[v], before[v] = true, index + 0 > 0 end
  if index + 1 == count + 0 and not before[v] then ended[id] = true end
end
local endedIds = {}
for id in pairs(ended) do
  endedIds[#endedIds + 1] = id
  whole = whole and has(fastObjects, ('"id": %s, "kind": "object"'):format(id))
end
table.sort(endedIds)
check("and the objects still complete (" .. table.concat(endedIds, " ") .. ")", #endedIds >= 3 and whole)
slash("strip dwell 10")

-- ---------------- ammunition is not a change of the bags (#44) ----------------
-- Seen in the game on 13 Nov 2026: each shot takes one from item 3030, and the bags object was
-- sent again about every two seconds of a fight.
local function bagsVersion(text) return versionIn(text, 4) end
P.ammo = 3030
BAGS[0][4] = { itemID = 3030, stackCount = 200 }
events.OnEvent(events, "BAG_UPDATE_DELAYED")
local quiver = watch(30)
check("ammunition is in the bags object with its count", has(quiver, "[3030,200]"))
BAGS[0][4].stackCount = 199
events.OnEvent(events, "BAG_UPDATE"); events.OnEvent(events, "BAG_UPDATE_DELAYED")
local shot = watch(30)
check("a shot (only the ammunition's count changed) makes no new bags object",
  bagsVersion(quiver) ~= nil and bagsVersion(shot) == bagsVersion(quiver) and not has(shot, "[3030,199]"))
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
  bagsVersion(split) ~= stacks and has(split, '\\"free\\":12,\\"items\\":[[2318,16],[3030,199],[4234,3]]'))
BAGS[0][6], P.free = nil, nil
BAGS[0][2].stackCount = 4
events.OnEvent(events, "BAG_UPDATE_DELAYED")
local other = watch(30)
check("another item changes: a new bags object, with the ammunition's count of now",
  bagsVersion(other) ~= bagsVersion(quiver) and has(other, "[3030,199]") and has(other, "[4234,4]"))
-- The sixth bag (#50): this client has a bag 5 (8 slots, seen 13 Nov 2026). Herbs and cloth
-- the owner received were not in the object, which read bags 0 to 4.
BAGS[5] = { { itemID = 2453, stackCount = 2 } }
events.OnEvent(events, "BAG_UPDATE_DELAYED")
local sixth = watch(30)
check("an item in bag 5 is in the bags object; free does not count bag 5",
  bagsVersion(sixth) ~= bagsVersion(other) and has(sixth, '\\"free\\":12,') and has(sixth, "[2453,2]"))
BAGS[5][1].stackCount = 4
events.OnEvent(events, "BAG_UPDATE_DELAYED")
local sixthMore = watch(30)
check("a change in bag 5 is a new bags object", bagsVersion(sixthMore) ~= bagsVersion(sixth) and has(sixthMore, "[2453,4]"))
BAGS[5] = nil
events.OnEvent(events, "BAG_UPDATE_DELAYED")
check("without a bag 5 the object is as before", not has(watch(30), "2453"))
P.ammo = nil
BAGS[0][4].stackCount = 198
events.OnEvent(events, "BAG_UPDATE_DELAYED")
local plain = watch(30)
check("with nothing in the ammunition slot, that item's count is a change like any other",
  bagsVersion(plain) ~= bagsVersion(other) and has(plain, "[3030,198]"))
BAGS[0][4], BAGS[0][2].stackCount = nil, 3
events.OnEvent(events, "BAG_UPDATE_DELAYED"); watch(20)

-- ---------------- a narrow game: small chunks, and an object too large for 12 of them ----------------
-- 420 pixels: 311 squares of 6 bits after the row's head (109 squares; docs/specs/232.md, section 6),
-- 233 bytes; less the 213 the addon keeps for the frame without a chunk (HEAD3, section 11): 20
GetPhysicalScreenSize = function() return 420, 1440 end
events.OnEvent(events, "DISPLAY_SIZE_CHANGED")
for i = 1, 40 do BAGS[0][3 + i] = { itemID = 50000 + i * 37, stackCount = i } end
events.OnEvent(events, "BAG_UPDATE_DELAYED")
local narrow = watch(60)
local size = 0
for len in narrow:gmatch('"chunk": %[%d+, %d+, %d+, %d+, (%d+)%]') do size = math.max(size, tonumber(len)) end
check("the chunk is as long as the row has room for (233 - 213 = 20 bytes)", size == 20, size)
check("the bags object, now several chunks, is joined", has(narrow, '[50037,1]') and has(narrow, '[51480,40]'))
GetPhysicalScreenSize = function() return 400, 1440 end   -- 291 squares: 218 bytes, chunks of 5
events.OnEvent(events, "DISPLAY_SIZE_CHANGED")
events.OnEvent(events, "BAG_UPDATE_DELAYED")
check("an object of more than 12 chunks is sent as format 254 in one chunk", has(watch(60), '[4, 254, null]'))
GetPhysicalScreenSize = function() return 2560, 1440 end
for i = 1, 40 do BAGS[0][3 + i] = nil end
events.OnEvent(events, "DISPLAY_SIZE_CHANGED"); events.OnEvent(events, "BAG_UPDATE_DELAYED"); watch(20)

-- ---------------- compression by the client ----------------
local function rawDeflate(text)
  local f = assert(io.open(DIR .. "/raw.txt", "wb")); f:write(text); f:close()
  -- raw deflate: gzip's output without its 10-byte header (no name, -n) and 8-byte trailer
  sh(("gzip -9 -n -c '%s/raw.txt' > '%s/raw.gz'"):format(DIR, DIR))
  local z = assert(io.open(DIR .. "/raw.gz", "rb")); local data = z:read("*a"); z:close()
  return data:sub(11, -9)
end
C_EncodingUtil = { CompressString = rawDeflate }
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
-- a request by bits (docs/specs/232.md, part C): only fewer bits than the strip has now
slotFile = { seq = 3, text = "", strip = { session = session, bits = 6 } }
out = {}
tick(600); tick(0.1)
check("a request for as many bits as the strip has (6) does nothing",
  has(read({ dump() }), '"depth": 4') and not has(table.concat(out, "\n"), "falls back"))
slotFile = { seq = 4, text = "", strip = { session = session, bits = 9 } }
tick(600); tick(0.1)
check("a request for more bits (9) does nothing: a request never steps up", has(read({ dump() }), '"depth": 4'))
slotFile = { seq = 5, text = "", strip = { session = session, bits = 3 } }
tick(600); tick(0.1)
check("a request for 3 bits makes the row depth 2, and chat says so",
  has(read({ dump() }), '"depth": 2') and has(table.concat(out, "\n"), "falls back to 3 bits"))
slash("strip depth auto"); tick(0.1)

-- ---------------- size, place, off ----------------
slash("strip size 3"); slash("strip at 40 6"); tick(0.1)
local moved = read({ dump() })
check("3 pixels a square at (40, 6): still read", has(moved, '"row": true') and has(moved, '"why": null')
  and math.abs(tonumber(moved:match('"square": ([%d.]+)')) - 3) < 0.01)
slash("strip size 1"); slash("strip at 0 0")      -- format 3's default: 1 pixel a square
check("StripSet: a setting it does not have is refused, and the state is as it was", ns.StripSet("size", "9") == false and ns.StripState().size == 1 and ns.StripState().x == 0)
check("a wrong command lists the commands", has(slash("strip depth 9"), "use /hlink strip"))
-- the client reads "|" and the next letter as an escape (seen 23 Nov 2026: the usage line cut after
-- "size <1"), so a line says every "|" of its text as "||"; only the name's colour is an escape
do
  local said = slash("strip depth 9"):match("|r: (.*)$") or ""
  check("2.0.2: the usage line's \"|\" go to the chat as \"||\"", said:find("<1||2||3||4>", 1, true) ~= nil
    and not said:gsub("||", ""):find("|", 1, true), said)
end
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
  for _ = 1, 20 do tick(1) end   -- its looks at 8 and 20 s go by before the watches of object 13 below
  slash("strip on"); slash("strip depth auto"); tick(0.1)
  -- object 13: the acknowledgement (docs/specs/115.md, section 6)
  HelloForeverAssist = nil
  check("object 13 says null without HelloForever", has(watch(35), bin(13, 'null')))
  HelloForeverAssist = { on = false, lang = "en" }
  check("...and with its assistant off", has(watch(35), bin(13, 'null')))
  HelloLinkAssist.seq, HelloLinkAssist.re, HelloLinkAssist.taken, HelloLinkAssist.refused = 12, 3, 1, 0
  local function on(o)
    local t = { on = true, lang = "en", ask = { n = 4, topic = "session", t = 1794516375 }, shown = "bags" }
    for k, v in pairs(o or {}) do t[k] = v end
    return t
  end
  HelloForeverAssist = on()
  check("object 13: the set the game took, the last question, the slots left and the card shown",
    has(watch(35), bin(13, '{"ask":{"n":4,"t":1794516375,"topic":"session"},"lang":"en","left":' .. tostring(HelloLinkAssist.left)
      .. ',"on":true,"re":3,"refused":0,"seq":12,"shown":"bags","taken":1}')))
  HelloForeverAssist = on({ ask = false, shown = false })
  HelloForeverAssist.ask, HelloForeverAssist.shown = nil, nil
  local none = watch(35)
  check("object 13: no question and no card are null", has(none, '{\\"ask\\":null,\\"lang\\":') and has(none, '\\"shown\\":null,\\"taken\\":1}"]'))
  for _, bad in ipairs({ { lang = "x y" }, { lang = 7 }, { shown = "a b" }, { ask = { n = 0, topic = "session", t = 1 } },
      { ask = { n = 1, topic = "a b", t = 1 } }, { ask = "session" } }) do
    HelloForeverAssist = on(bad)
    local k, v = next(bad)
    check("object 13 is null when HelloForever's table is not as the spec has it (" .. k .. " = " .. tostring(type(v) == "table" and "table" or v) .. ")",
      has(watch(35), bin(13, 'null')))
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
    has(g, '\\"16\\":{\\"dur\\":[50,60],\\"enchant\\":1887,\\"item\\":2504,\\"suffix\\":-9}'))
  check("...a slot without enchant or suffix has them null; an item without durability has dur null",
    has(g, '\\"1\\":{\\"dur\\":null,\\"enchant\\":null,\\"item\\":2504,\\"suffix\\":null}'))
  check("...an empty slot is left out", not has(g, '\\"2\\":{') and has(g, '\\"3\\":{'))
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
  local function version15(text) return versionIn(text, 15) end
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
    has(watch(40), '\\"16\\":{\\"dur\\":[50,60],\\"enchant\\":1887,\\"item\\":2504,\\"suffix\\":-9}'))
  LINKS[16] = "|cff1eff00|Hitem:16866:abc:::::-9:|h[Ranger Bow]|h|r"
  events.OnEvent(events, "PLAYER_EQUIPMENT_CHANGED")
  check("an enchant field that is no number makes the gear unreadable, not an item without enchant", has(watch(40), '[14, 255, null]'))
  LINKS[16] = "|cff1eff00|Hitem:16866:2564::::::|h[Ranger Bow]|h|r"
  events.OnEvent(events, "UNIT_INVENTORY_CHANGED", "player")
  check("an enchant put on worn gear (UNIT_INVENTORY_CHANGED alone) is sent", has(watch(40), '\\"16\\":{\\"dur\\":[50,60],\\"enchant\\":2564,\\"item\\":2504,\\"suffix\\":null}'))
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
  check("a race the client says nothing about is null", has(watch(40), '\\"race\\": null, \\"fullName\\": '))
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
  local KEY = "Player-1-0000ABCD" -- the GUID (1.18.0, spec 276)
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
  -- while the client gives no GUID, the record goes under "Name-Realm"; with the empty realm of this
  -- client (since 20 Nov 2026), "FakeHunter-" (review of #273)
  do
    local keptRealm, keptGuid = GetRealmName, UnitGUID
    GetRealmName = function() return "" end
    UnitGUID = function(u) if u == "player" then return nil end return keptGuid(u) end
    events.OnEvent(events, "BARBER_SHOP_OPEN")
    GetRealmName, UnitGUID = keptRealm, keptGuid
    local empty = HelloLinkDB.looks["FakeHunter-"]
    check("looks: with no GUID and an empty realm the record goes under FakeHunter-", type(empty) == "table" and empty.choices[501] == 7002, empty)
    HelloLinkDB.looks["FakeHunter-"] = nil
  end

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
  local function versions(text)   -- the versions of object 18 that the frames' directories name
    local seen = {}
    for hex in text:gmatch('"frame": "(%x+)"') do
      local v = directory(hex)[18]
      if v then seen[tostring(v)] = true end
    end
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
  -- the first watch began before the use: the version it ends on, against every version of the next
  local v1, v2 = { tostring(versionIn(first, 18)) }, versions(later)
  check("...and it does not change while the cooldown runs: one version over the next eight seconds",
    #v2 == 1 and v1[1] == v2[1] and not later:find('readyAt\\": 0}', 1, true),
    table.concat(v1, ",") .. " / " .. table.concat(v2, ","))
  local READY = hearth('{\\"bind\\": \\"Gadgetzan\\", \\"item\\": 6948, \\"readyAt\\": 0}')
  local before = v2                    -- the cooldown above, still running
  P.hcd = { P.hcd[1], 3595, 1 }
  local told = watch(40)
  check("a duration told otherwise for the same cooldown start changes nothing: the same version",
    #before == 1 and table.concat(versions(told), ",") == before[1], table.concat(before, ",") .. " / " .. table.concat(versions(told), ","))
  P.hcd = "gcd"
  check("the global cooldown (1.5 s, still running) is not the hearthstone's: ready while it runs", has(watch(40), READY))
  P.hcd = { now, 45, 1 }               -- 45 s: the four watches below take 29 s (each 4 s more in format 3)
  watch(30)                            -- the last version of the global cooldown goes by
  local running = watch(20)
  check("a cooldown of 45 s: not ready while it runs", not has(running, READY) and running:find('readyAt\\": [1-9]') ~= nil)
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
  local function version(id, text) return versionIn(text, id) end
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
    has(g1, q('{"slots":{"0":{"count":2783,"item":3030},"1":{"dur":')), g1:match('\n%[14, .-%]"?\n'))
  P.ammoCount = 2782
  events.OnEvent(events, "UNIT_INVENTORY_CHANGED", "player")
  local g2 = watch(40)
  check("a shot (the ammunition's count alone) makes no new version of object 14",
    version(14, g1) ~= nil and version(14, g2) == version(14, g1) and not has(g2, '2782'), tostring(version(14, g1)) .. " " .. tostring(version(14, g2)))
  DUR[3] = { 40, 60 }
  events.OnEvent(events, "UPDATE_INVENTORY_DURABILITY")
  local g3 = watch(40)
  check("...another change of the gear sends the count of now", version(14, g3) ~= version(14, g2)
    and has(g3, q('"0":{"count":2782,"item":3030}')) and has(g3, q('"3":{"dur":[40,60],"enchant":null,"item":2504,"suffix":null}')))
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
  check("no ammunition: slot 0 is left out", has(g4, q('{"slots":{"1":{"dur":')) and not has(g4, q('"0":{')))
  -- this client gives 0 for an empty ammunition slot (seen 22 Nov 2026): left out too, not item 0
  P.ammo = 0
  events.OnEvent(events, "PLAYER_EQUIPMENT_CHANGED")
  local g5 = watch(40)
  check("an ammunition slot the client gives as 0 is left out", has(g5, q('{"slots":{"1":{"dur":')) and not has(g5, q('"0":{')))
  P.ammo = nil

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
    has(steps, q('{"step": 1, "text": "one", "map": 1429, "x": 32768, "y": 16384, "tags": ["accept", "goto", "turnin", "isQuestTurnedIn"], "quests": [33, 34, 36], "done": true, '
      .. '"elements": [["accept", 33], ["goto", null], ["accept", 34], ["turnin", 33], [null, null], [null, null], ["isQuestTurnedIn", 34], ["isQuestTurnedIn", 36]], "lines": []}, '
      .. '{"step": 2, "text": "two", "map": null, "x": null, "y": null, "tags": [], "quests": [], "done": false, "elements": []}], "orphans": [], "targets": null}')),
    steps:match('"object": %[11, .-%]"?%]'))
  do   -- an isOnQuest element may name many quests: all of them, not the first 20 (#192, review round 2)
    local many, want = {}, {}
    for k = 1, 30 do many[k] = 1000 + k; want[k] = tostring(1000 + k) end
    RXP.currentGuide.steps[2].elements = { { tag = "isOnQuest", questIds = many } }
    check("object 11: a step whose element names 30 quests sends all 30",
      has(watch(40), q('"tags": ["isOnQuest"], "quests": [' .. table.concat(want, ", ") .. '], "done": false, ')))
    -- 190 ids, 10 repeats, then a new one: the 200 are counted after the repeats (review round 3)
    local repeats, wantR = {}, {}
    for k = 1, 190 do repeats[k] = 2000 + k; wantR[k] = tostring(2000 + k) end
    for k = 191, 200 do repeats[k] = 2001 end
    repeats[201] = 3191; wantR[191] = "3191"
    RXP.currentGuide.steps[2].elements = { { tag = "isOnQuest", questIds = { unpack(repeats, 1, 100) } },
      { tag = "isOnQuest", questIds = { unpack(repeats, 101, 201) } } }
    -- as plain JSON these pass what one version may send in format 3 (12 chunks of at most 128
    -- bytes, docs/specs/232.md, section 6): the client's deflate sends them (object format 1)
    C_EncodingUtil = { CompressString = rawDeflate }
    check("object 11: the 200 quest ids are counted after the repeats are left out",
      has(watch(40), q('"quests": [' .. table.concat(wantR, ", ") .. '], "done": false, ')))
    -- 0.8.1: the elements keep the repeats, one pair an id, at most 40 in all (200 pairs over five
    -- steps could make the object too large); the quests above still go to 200
    local pairsR = {}
    for k = 1, 40 do pairsR[k] = '["isOnQuest", ' .. repeats[k] .. ']' end
    check("0.8.1: object 11's elements: one pair for each id of a questIds list, in order, at most 40",
      has(watch(40), q('"done": false, "elements": [' .. table.concat(pairsR, ", ") .. ']}]')))
    C_EncodingUtil = nil
    -- 0.8.1: a secret tag or id is null in its pair; a tag that is no plain word is null
    RXP.currentGuide.steps[2].elements = { { tag = "accept", questId = 77 }, { tag = "goto x" }, { tag = "turnin", questId = 78 },
      { tag = "isOnQuest", questIds = {} } }
    check("0.8.1: object 11's elements: a secret id is null, a tag that is no word is null, an empty questIds list is one pair",
      secretly(77, function() return has(watch(40), q('"elements": [["accept", null], [null, null], ["turnin", 78], ["isOnQuest", null]]}]')) end))
    check("0.8.1: object 11's elements: a secret tag is null",
      secretly("turnin", function() return has(watch(40), q('"elements": [["accept", 77], [null, null], [null, 78], ["isOnQuest", null]]}]')) end))
    RXP.currentGuide.steps[2].elements = { { tag = "isOnQuest", questIds = { 101, 102, 103 } } }
    check("0.8.1: a secret id in a questIds list is a pair with null, and the list goes on (review round 1)",
      secretly(102, function() return has(watch(40), q('"quests": [101, 103], "done": false, "elements": [["isOnQuest", 101], ["isOnQuest", null], ["isOnQuest", 103]]}]')) end))
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
  local seen = HelloLinkDB.seen and HelloLinkDB.seen["Player-1-0000ABCD"]
  check("the saved data says which character was in the game, under its GUID, with the time",
    type(seen) == "table" and seen.name == "FakeHunter" and seen.realm == "TestRealm" and seen.guid == "Player-1-0000ABCD"
    and seen.at == 1794516378)
  local realName = UnitName
  UnitName = function(u) if u == "player" then return SECRET end return realName(u) end
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", true, false)
  UnitName = realName
  local n = 0
  for _ in pairs(HelloLinkDB.seen) do n = n + 1 end
  check("...a name that cannot be read writes nothing", n == 1 and HelloLinkDB.seen["Player-1-0000ABCD"] == seen)
  local realTime = time
  time = function() return 1794519999 end
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", false, false)   -- into an instance
  local after = HelloLinkDB.seen["Player-1-0000ABCD"]
  check("...entering an instance does not write the login's time again", after == seen and after.at == 1794516378)
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", false, true)
  check("...a reload does", HelloLinkDB.seen["Player-1-0000ABCD"].at == 1794519999)
  time = realTime
  events.OnEvent(events, "PLAYER_ENTERING_WORLD"); watch(40)

  -- ---------------- HelloLink 0.8.1: the full name, from the player's own loot ----------------
  -- CHAT_MSG_LOOT as the client gave it on 13 Nov 2026: argument 2 is the name with the family
  -- name, argument 12 the GUID. `who` is object 10's text now. The cache is keyed by the GUID:
  -- two characters can share a first name and a realm (review round 1).
  local ME, OTHER, ME2 = "Player-1-0000ABCD", "Player-1-0BBBBBBB", "Player-1-0000EEEE"
  local function lootBy(name, guid, fifth)
    events.OnEvent(events, "CHAT_MSG_LOOT", "You receive loot: |Hitem:2589:|h[Linen Cloth]|h|r.",
      name, "", "", fifth or name, "", 0, 0, "", 0, 3, guid)
  end
  local function who()   -- the newest object 10 of the watch
    local last = ""
    for found in watch(40):gmatch('%[10, %d+, [n"][^%]]*%]') do last = found end
    return last
  end
  local function entry(guid) return HelloLinkDB.fullNames and HelloLinkDB.fullNames[guid or ME] end
  local realName, realGuid, realTime = UnitName, UnitGUID, time
  local function as(name, guid)   -- another character logs in
    UnitName = function(u) if u == "player" then return name end return realName(u) end
    UnitGUID = function(u) if u == "player" then return guid end return realGuid(u) end
    events.OnEvent(events, "PLAYER_ENTERING_WORLD", true, false)
  end
  -- object 10 never asks a getter for the name yet: the probe decides in 0.8.2
  local asked = 0
  UnitFullName = function() asked = asked + 1 return "FakeHunter Getter", "TestRealm" end
  HelloLinkDB.fullNames = nil
  events.OnEvent(events, "PLAYER_ENTERING_WORLD")
  check("0.8.1: object 10 has fullName null before any loot of the player, and asks no getter",
    has(who(), q(', "race": "NightElf", "fullName": null, "fullNameSource": null, "guid": "Player-1-0000ABCD", "realmSaved": null, "talents": null}')) and asked == 0, who())
  lootBy("FakeHunter Other", OTHER)
  check("0.8.1: another player's loot never sets the name, even with the same first word", entry() == nil and entry(OTHER) == nil)
  lootBy("Bob Family", ME)
  lootBy("Fakehunter Family", ME)
  check("0.8.1: a name whose first word is not UnitName's is refused", entry() == nil)
  lootBy("FakeHunter " .. ("x"):rep(50), ME)   -- 61 bytes
  check("0.8.1: a name over 60 bytes is refused", entry() == nil)
  lootBy("FakeHunter \255", ME)
  check("0.8.1: a name that is not UTF-8 is refused", entry() == nil)
  secretly("FakeHunter Secret", function() lootBy("FakeHunter Secret", ME) end)
  check("0.8.1: a secret name is never taken", entry() == nil)
  lootBy("FakeHunter", ME); lootBy("FakeHunter  ", ME)
  check("0.8.1: the first name alone, with or without spaces, is no full name", entry() == nil)
  lootBy("FakeHunter Bad", ME, "FakeHunter Fifth")
  check("0.8.1: the name is argument 2, not argument 5", (entry() or {}).fullName == "FakeHunter Bad")
  lootBy("FakeHunter " .. ("x"):rep(49), ME)   -- 60 bytes
  check("0.8.1: a name of 60 bytes is taken", entry() and entry().fullName == "FakeHunter " .. ("x"):rep(49))
  HelloLinkDB.seen = nil
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", false, true)
  time = function() return 1794517000 end
  lootBy("FakeHunter Family", ME)
  local e = entry()
  check("0.8.1: the player's own loot gives the full name, kept under the GUID with its source and time",
    type(e) == "table" and e.fullName == "FakeHunter Family" and e.source == "loot" and e.at == 1794517000)
  check("0.8.1: ...and HelloLinkDB.seen has it at once, before the next login",
    (HelloLinkDB.seen["Player-1-0000ABCD"] or {}).fullName == "FakeHunter Family")
  time = function() return 1794518000 end
  lootBy("FakeHunter Family", ME)
  check("0.8.1: the same name again does not write the entry again", e ~= nil and entry() == e and e.at == 1794517000)
  time = realTime
  check("0.8.1: object 10 sends it, and still asks no getter",
    has(who(), q(', "race": "NightElf", "fullName": "FakeHunter Family", "fullNameSource": "loot", "guid": "Player-1-0000ABCD", "realmSaved": null, "talents": null}')) and asked == 0, who())
  do
    local keptGuid = UnitGUID
    UnitGUID = function(u) if u == "player" then return SECRET end return keptGuid(u) end
    events.OnEvent(events, "PLAYER_ENTERING_WORLD", false, true)
    check("1.18.0: a GUID the client keeps secret is null in object 10", has(who(), q('"guid": null, "realmSaved": null, "talents": null}')), who())
    UnitGUID = function(u) if u == "player" then return "Creature-0-1-2-3-299-0000" end return keptGuid(u) end
    events.OnEvent(events, "PLAYER_ENTERING_WORLD", false, true)
    check("1.18.0: a GUID that is no player's is null too", has(who(), q('"guid": null, "realmSaved": null, "talents": null}')), who())
    UnitGUID = keptGuid
  end
  do
    -- 1.19.0: realmSaved, the realm of the HelloForever record that holds this GUID (spec 276)
    local function again() events.OnEvent(events, "PLAYER_ENTERING_WORLD", false, true) end
    HelloForeverDB = { characters = {
      ["FakeHunter-TestRealm"] = { guid = ME, guidBy = "name" },
      ["FakeHunter-"] = { guid = ME, guidBy = "split", split = true },
      ["FakeHunter-OtherRealm"] = { guid = OTHER },
    } }
    again()
    check("1.19.0: realmSaved is the realm of HelloForever's record that holds this GUID",
      has(who(), q('"guid": "Player-1-0000ABCD", "realmSaved": "TestRealm", "talents": null}')), who())
    HelloForeverDB.characters["FakeHunter-TestRealm"] = nil
    HelloForeverDB.characters["OldName-Azjol-Nerub"] = { guid = ME, guidBy = "name" }
    again()
    check("1.19.0: a renamed character's old record gives its realm, hyphen and all (review of #285)",
      has(who(), q('"realmSaved": "Azjol-Nerub", "talents": null}')), who())
    HelloForeverDB.characters["OldName-Azjol-Nerub"] = nil
    again()
    check("1.19.0: a split record, or another GUID's, gives no realmSaved", has(who(), q('"realmSaved": null, "talents": null}')), who())
    HelloForeverDB.characters = { [ME] = { guid = ME, guidBy = "new" } }
    again()
    check("1.19.0: a record keyed by its GUID gives no realmSaved", has(who(), q('"realmSaved": null, "talents": null}')), who())
    HelloForeverDB = nil
    again()
  end
  HelloLinkDB.seen = nil
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", false, true)
  local s1 = HelloLinkDB.seen and HelloLinkDB.seen["Player-1-0000ABCD"]
  check("0.8.1: HelloLinkDB.seen keeps its key and gains the full name at a reload",
    type(s1) == "table" and s1.name == "FakeHunter" and s1.fullName == "FakeHunter Family")
  -- a second character with the same first name and realm, and its own GUID
  as("FakeHunter", ME2)
  check("0.8.1: a character with the same first name and realm does not get the other's full name",
    has(who(), q('"name": "FakeHunter", ')) and has(who(), q('"fullName": null'))
    and HelloLinkDB.seen[ME].fullName == "FakeHunter Family"   -- 1.18.0: the first one's entry is its own
    and (HelloLinkDB.seen[ME2] == nil or HelloLinkDB.seen[ME2].fullName == nil), who())
  lootBy("FakeHunter Smith", ME2)
  check("0.8.1: ...it keeps its own, under its GUID", (entry(ME2) or {}).fullName == "FakeHunter Smith"
    and has(who(), q('"fullName": "FakeHunter Smith"')), who())
  as("FakeHunter", ME)
  check("0.8.1: ...and the first one has its own back", (entry() or {}).fullName == "FakeHunter Family"
    and has(who(), q('"fullName": "FakeHunter Family"')) and HelloLinkDB.seen["Player-1-0000ABCD"].fullName == "FakeHunter Family", who())
  as("Zed", ME2)
  check("0.8.1: a name that does not start the cached full name is not sent", has(who(), q('"name": "Zed", ')) and has(who(), q('"fullName": null')), who())
  -- #201: a GUID of "" is no GUID: no full name is kept under "", and none is sent
  as("FakeHunter", "")
  lootBy("FakeHunter Empty", "")
  check("#201: an empty GUID keys no full name", entry("") == nil)
  HelloLinkDB.fullNames[""] = { fullName = "FakeHunter Empty", source = "loot" }   -- as HelloLink 1.22.0 could write it
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", false, true)
  check("#201: ...and an entry under \"\" is never sent", has(who(), q('"fullName": null')), who())
  HelloLinkDB.fullNames[""] = nil
  -- #201: a reload with no GUID writes seen under "<name>-<realm>"; when the GUID comes back, loot
  -- with the cached name fills seen's entry under the GUID, though the cache does not change
  HelloLinkDB.seen = nil
  UnitGUID = function(u) if u == "player" then return nil end return realGuid(u) end
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", false, true)
  UnitGUID = function(u) if u == "player" then return ME end return realGuid(u) end
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", false, false) -- the next loading screen, no loot (review of #298)
  check("#201: ...the GUID back, the next loading screen fills seen's entry from the cache, with no loot",
    (HelloLinkDB.seen[ME] or {}).fullName == "FakeHunter Family")
  HelloLinkDB.seen[ME] = nil
  lootBy("FakeHunter Family", ME)
  check("#201: ...the GUID back, loot with the cached name fills seen's entry under it",
    (HelloLinkDB.seen[ME] or {}).fullName == "FakeHunter Family" and (entry() or {}).fullName == "FakeHunter Family")
  HelloLinkDB.seen[ME] = { name = "FakeHunter", realm = "TestRealm", guid = ME }
  lootBy("FakeHunter Family", ME)
  check("#201: ...and fills an entry under the GUID that lacks it", HelloLinkDB.seen[ME].fullName == "FakeHunter Family")
  UnitName, UnitGUID = realName, realGuid
  HelloLinkDB.fullNames[ME] = { fullName = 7, source = "loot" }
  events.OnEvent(events, "PLAYER_ENTERING_WORLD")
  check("0.8.1: a saved entry that is no name is null", has(who(), q('"fullName": null, "fullNameSource": null, "guid": "Player-1-0000ABCD", "realmSaved": null, "talents": null}')), who())
  lootBy("FakeHunter Family", ME)
  UnitFullName = nil
  events.OnEvent(events, "PLAYER_ENTERING_WORLD"); watch(40)
end

-- ---------------- the party, the frame ring, the carousel's order (docs/specs/213.md) ----------------
do
  local S2 = ns.Strip2
  -- The addon's row read back, and `replay` gives its states.
  -- a party of four and a target of target, each with its own health (review of #227)
  local realExists, realPercent = UnitExists, UnitHealthPercent
  local HP = { targettarget = 0.30, party1 = 0.10, party2 = 0.50, party3 = 0.70, party4 = 0.95 }
  UnitExists = function(u) return HP[u] ~= nil or realExists(u) end
  UnitHealthPercent = function(u, a, curve) if HP[u] then return curve:at(HP[u]) end return realPercent(u, a, curve) end
  local px = 0.5
  local realMap = C_Map.GetPlayerMapPosition
  C_Map.GetPlayerMapPosition = function() return { GetXY = function() return px, 0.25 end } end
  tick(0.1)
  check("the frame has its level squares", has(read({ dump() }), '"levels": [75, 83, 12, 93]'), read({ dump() }):sub(1, 300))
  local paths = {}
  for i = 1, 30 do
    if i % 3 == 0 then px = px + 0.0001 end   -- a walk: a few map units each 0.3 s
    tick(0.1)
    paths[#paths + 1] = dump()
  end
  local rows = read(paths, 0.1)
  local events3, framed = replay(rows)
  check("the reader reads every frame of the row (" .. #framed .. " of 30)", #framed == 30, rows:sub(1, 400))
  local states, objects = 0, 0
  for line in events3:gmatch("[^\n]+") do
    if line:find('"kind": "state"', 1, true) then states = states + 1 end
    if line:find('"kind": "object"', 1, true) then objects = objects + 1 end
  end
  check("replay gives a state for each new frame (" .. states .. " states)", states >= 10, events3:sub(1, 600))
  local last
  for line in events3:gmatch("[^\n]+") do if line:find('"kind": "state"', 1, true) then last = line end end
  check("the last state has the walked position, the target of target and the further levels",
    last and has(last, ('"x": %d'):format(math.floor(px * 65535 + 0.5))) and has(last, '"targettarget": {"flags": 128, "level": 29')
      and has(last, '"format": 3') and has(last, '"more": [30, 9, 50, 70, 95]'), last)
  UnitExists, UnitHealthPercent = realExists, realPercent
  -- the ring by itself: 600 frames fill its 512 slots and go round; a new session starts it afresh
  local db = {}
  for s = 1, 600 do ns.Strip2.noteFrame(db, s, 7) end
  check("1.0.0: the frame ring keeps the last 512 frames in place, the newest in slot `at`",
    db.frames.at == 600 - 512 and db.frames.seq[db.frames.at] == 600 and db.frames.seq[db.frames.at + 1] == 89
      and #db.frames.seq == 512 and db.frames.session == 7)
  ns.Strip2.noteFrame(db, 1, 8)
  check("1.0.0: a new UI session starts the ring afresh", db.frames.at == 1 and #db.frames.seq == 1 and db.frames.session == 8)
  local ring = HelloLinkDB.frames
  check("1.0.0: the saved data keeps when each frame went up, with its seq (a ring of 512)",
    type(ring) == "table" and ring.at >= 1 and #ring.t <= 512 and #ring.t == #ring.seq and ring.t[ring.at] == now)
  check("objects come whole in the 3 s (" .. objects .. ")", objects >= 3, events3:sub(1, 600))
  local longest = 0
  for line in rows:gmatch("[^\n]+") do
    local size = line:match('"chunk": %[%d+, %d+, %d+, %d+, (%d+)%]')
    if size then longest = math.max(longest, tonumber(size)) end
  end
  check("no chunk is longer than 128 bytes (the longest " .. longest .. ")", longest > 0 and longest <= 128)

  -- The order of chunks (section 7), with objects of the test's own.
  local objs = { [1] = { obj = { 1 }, version = 1, sent = 1 }, [2] = { obj = { 2 }, version = 5, sent = 5 } }
  local lists = { [1] = { { 1, 1 }, { 1, 2 } }, [2] = { { 2, 1 } } }
  local function chunks(o) for id, x in pairs(objs) do if x == o then return lists[id] end end end
  S2.resetSending()
  local sent, t, nextSend = {}, 0, S2.nextSend
  local sending
  for _ = 1, 80 do
    t = t + 0.1
    -- object 2 changes at every decision: a new version waits all the time
    objs[2].version = objs[2].version + 1
    sending = nextSend(sending, 2, objs, function() end, chunks, t, 0.1)
    if sending then
      sent[#sent + 1] = sending.id .. (sending.new and "n" or "r") .. sending.index
      sending.till = t
    end
  end
  local refreshed = table.concat(sent, " "):find("1r2", 1, true) ~= nil
  check("changes that never stop do not starve the refresh: object 1 is refreshed whole", refreshed, table.concat(sent, " "):sub(1, 200))
  local before = objs[1].version
  S2.rechunked(objs, 77)
  S2.rechunked(objs, 77)
  check("a new chunk length gives every object a new version, once", objs[1].version == before + 1 and objs[1].sent == nil)
  C_Map.GetPlayerMapPosition = realMap
  tick(0.1)
end


-- ---------------- format 3 (docs/specs/232.md, section 6) ----------------
do
  local S2 = ns.Strip2
  -- The hand-written vectors (tests/vectors/strip3.json), made byte for byte from a state.
  local hexes = {}
  for hex in io.open("tests/vectors/strip3.json"):read("*a"):gmatch('"hex": "(%x+)"') do hexes[#hexes + 1] = hex:lower() end
  local function frameHex(seq, state, objs, sending, ring, fit)
    local b = {}
    local n = S2.frame3(b, 4711, 10, seq, state, sending, objs, S2.IDS, ring, fit)
    local s1, s2 = 0, 0
    for i = 1, S2.fx do s1 = (s1 + b[i]) % 255; s2 = (s2 + s1) % 255 end
    b[S2.fx + 1], b[S2.fx + 2] = s1, s2
    local t = {}
    for i = 1, n do t[i] = ("%02x"):format(b[i]) end
    return table.concat(t)
  end
  local key = { clock = { clock = 54321 }, target = { level = 35, flags = 129, nameHash = 10475 },
    position = { map = 1435, x = 30000, y = 40000, facing = 64 } }
  local objs = { [9] = { obj = "a", version = 258 }, [24] = { obj = "b", version = 48879 } }
  check("format 3: the vector of the fixed part only, byte for byte", frameHex(0x1234, key, objs) == hexes[1],
    frameHex(0x1234, key, objs))
  -- the event ring (section 6, section 3): the vector's three events, the counter at 42
  do
    local count = S2.ringCount
    S2.ringCount = 42
    local ring = { { now, 1, 2589, 3 }, { now, 4, 1234 }, { now, 7 } }
    check("format 3: the vector with an event ring, byte for byte", frameHex(0x1234, key, objs, nil, ring) == hexes[#hexes],
      frameHex(0x1234, key, objs, nil, ring))
    -- an empty ring still says its counter: a reader knows how many came while it was away
    check("format 3: an empty ring is its counter alone", frameHex(0x1234, key, objs, nil, {}):find("18beef03012a", 1, true) ~= nil)
    -- a row too short for the whole ring: the newest events that fit, the counter whole (review of #255)
    local whole = #hexes[#hexes] / 2
    local short = frameHex(0x1234, key, objs, nil, ring, whole - 1)
    check("format 3: a ring too long for the row keeps its newest events and its counter",
      #short / 2 <= whole - 1 and short:find("18beef03072a04000004d207", 1, true) ~= nil, short)
    -- a row too short for even the counter: no ring, the rest of the frame still goes
    check("format 3: a row too short for the counter leaves the ring out",
      frameHex(0x1234, key, objs, nil, ring, #hexes[1] / 2) == hexes[1])
    S2.ringCount = count
  end

  -- What the ring takes from the state read anyway: XP, a level with the XP across it, money
  -- each way, a death; a group unknown for a while says only its change; at most 8, for 10 s
  do
    local ring, count, was = S2.ring, S2.ringCount, S2.ringWas
    S2.ring, S2.ringCount, S2.ringWas = {}, 0, {}
    local function st(level, xp, xpMax, money, flags)
      return { level = level and { level = level, xp = xp, xpMax = xpMax },
        purse = money and { money = money, bagFree = 1 }, state = flags and { flags = flags } }
    end
    local function said()
      local t = {}
      for i, e in ipairs(S2.ring) do t[i] = table.concat({ e[2], e[3], e[4] }, ":") end
      return table.concat(t, " ")
    end
    S2.noteRing(st(5, 100, 400, 1000, 0), 0)            -- the first state only sets what was
    S2.noteRing(st(5, 150, 400, 1000, 0), 0.1)          -- 50 XP
    S2.noteRing(st(6, 30, 500, 1200, 0), 0.2)           -- one level up: 250 to its end and 30 more; 200 copper
    S2.noteRing(st(nil, nil, nil, nil, nil), 0.3)       -- all unknown: nothing
    S2.noteRing(st(6, 30, 500, 900, 64), 0.4)           -- back: 300 copper lost
    S2.noteRing(st(8, 10, 900, 900, 0), 0.5)            -- two levels up: XP not known, nothing
    S2.noteRing(st(8, 20, 900, 900, 0), 0.6)            -- 10 XP from there
    check("format 3: the ring takes XP and money from the state", said() == "5:50 5:280 3:200 4:300 5:10", said())
    check("format 3: the ring counts every event", S2.ringCount == 5, S2.ringCount)
    for k = 1, 5 do S2.happen(1, 2, k) end
    check("format 3: the ring keeps the last 8", #S2.ring == 8 and S2.ring[1][3] == 200 and S2.ringCount == 10, said())
    S2.happen(9, 2, 99)
    local kept = S2.ringNow(11.5)
    check("format 3: the ring keeps 10 s of events", #kept == 1 and kept[1][3] == 99, said())
    -- the loot and UI error events of the client go in
    S2.ring = {}
    events.OnEvent(events, "CHAT_MSG_LOOT", "You receive loot: |Hitem:2589:|h[Linen Cloth]|h|rx3.",
      "FakeHunter Family", "", "", "FakeHunter Family", "", 0, 0, "", 0, 1, "Player-1-0000ABCD")
    events.OnEvent(events, "UI_ERROR_MESSAGE", 51, "x")
    events.OnEvent(events, "PLAYER_LEVEL_UP", 7)
    events.OnEvent(events, "PLAYER_DEAD")
    S2.noteRing({}, now)                                -- the level goes in at the next frame
    check("format 3: a loot, a UI error, a level and a death go in the ring", said() == "1:2589:3 2:51 7 6:7", said())
    -- the client's events cost no GetTime (rule 4): they take the time of the next frame
    local times, realTime = 0, GetTime
    GetTime = function() times = times + 1 return realTime() end
    events.OnEvent(events, "CHAT_MSG_LOOT", "You receive loot: |Hitem:2589:|h[Linen Cloth]|h|r.",
      "FakeHunter Family", "", "", "FakeHunter Family", "", 0, 0, "", 0, 1, "Player-1-0000ABCD")
    events.OnEvent(events, "UI_ERROR_MESSAGE", 52, "x")
    GetTime = realTime
    check("format 3: a loot and a UI error ask no GetTime (" .. times .. ")", times == 0)
    local stamped = true
    for _, e in ipairs(S2.ringNow(now)) do stamped = stamped and e[1] == now end
    check("format 3: the next frame stamps them", stamped and #S2.ring == 6)
    -- a level goes after the XP that made it (review of #255)
    S2.ring, S2.ringWas = {}, {}
    S2.noteRing(st(5, 350, 400, 1000, 0), 0)
    S2.levelUp = 6
    S2.noteRing(st(6, 0, 500, 1000, 0), 0.1)
    check("format 3: a level goes after the XP that made it", said() == "5:50 6:6", said())
    -- two levels before a frame: both go in, in order (check review of #255)
    S2.ring = {}
    events.OnEvent(events, "PLAYER_LEVEL_UP", 7)
    events.OnEvent(events, "PLAYER_LEVEL_UP", 8)
    S2.noteRing({}, 0.2)
    check("format 3: two levels before a frame both go in", said() == "6:7 6:8", said())
    S2.ring, S2.ringCount, S2.ringWas = ring, count, was
  end

  objs[26] = { obj = "c", version = 1 }
  local secret = { id = 26, version = 1, chunks = { { 0xFD, 0xFD, 0xFD } }, index = 1 }
  check("format 3: the vector with a chunk of format 253, byte for byte", frameHex(0x1235, key, objs, secret) == hexes[2],
    frameHex(0x1235, key, objs, secret))
  objs[24].obj = nil
  check("format 3: an object with nothing to send is not in the directory",
    not frameHex(0x1234, key, objs):find("18beef", 1, true))

  -- a stop during a send once again asks for one more: the send that began before it does not end
  -- the request (review of #242)
  do
    local objs = { [5] = { obj = "x", version = 7, sent = 7, againAt = 0, againVer = 7, againSince = 0 } }
    local function chunksOf() return { { 1 }, { 2 } } end
    local function refresh() end
    S2.three = true
    S2.resetSending()
    local sending = S2.nextSend(nil, 27, objs, refresh, chunksOf, 10, 0.1)
    local first = sending and sending.again and sending.index == 1
    objs[5].upAt = 10
    S2.stall(objs, 27, 10.05, 0.5)                   -- the game stops while chunk 1 is up
    sending = S2.nextSend(sending, 27, objs, refresh, chunksOf, 10.1, 0.1)   -- chunk 2
    local again
    for k = 1, 10 do                                 -- the send ends; the request still waits
      sending = S2.nextSend(sending, 27, objs, refresh, chunksOf, 10.1 + k * 0.1, 0.1)
      if sending and sending.again and sending.index == 1 then again = k break end
    end
    check("format 3: a stop during a send once again is sent once more (" .. tostring(again) .. ")", first and again ~= nil)
    S2.resetSending()
  end

  -- Whether tests/vectors/objects3.json's `k`th object reads as `json`, compared as values (jq's
  -- ==): its `json`, what the reader reads its payload as (reader/hellolink-format/tests/strip3.rs).
  -- With the bytes the addon wrote equal to that payload, the values the addon sent are these.
  local function readsAs(k, json)
    return sh(("jq -e --argjson want '%s' '.objects[%d] | has(\"json\") and .json == $want' tests/vectors/objects3.json"):format(json, k - 1)) == "true\n"
  end

  -- Object 26 in binary (object format 2): the bytes of tests/vectors/objects3.json, written by
  -- the addon from the same aura (docs/specs/232.md, part E)
  do
    local payloads = {}
    for hex in io.open("tests/vectors/objects3.json"):read("*a"):gmatch('"payload": "(%x+)"') do payloads[#payloads + 1] = hex:lower() end
    local realAuras = C_UnitAuras
    C_UnitAuras = { GetAuraDataByIndex = function(u, i, filter)
      if u == "player" and i == 1 and filter == "HELPFUL" then
        return { spellId = 14320, name = "Aspect of the Hawk", applications = 2, duration = 1800,
          expirationTime = 174300.53, sourceUnit = "player" }
      end
    end }
    local b = {}
    local len = S2.aurasBin(b)
    local t = {}
    for i = 1, len do t[i] = ("%02x"):format(b[i]) end
    check("format 3: object 26 in binary, byte for byte as written by hand", table.concat(t) == payloads[1], table.concat(t))
    -- a tie of the second decimal goes as `%.1f` rounds it, as format 2's JSON said it (review of #248)
    C_UnitAuras = { GetAuraDataByIndex = function(u, i, filter)
      if u == "player" and i == 1 and filter == "HELPFUL" then
        return { spellId = 14320, name = "Aspect of the Hawk", applications = 0, duration = 10.25, expirationTime = 174300.25 }
      end
    end }
    len = S2.aurasBin(b)
    t = {}
    for i = 1, len do t[i] = ("%02x"):format(b[i]) end
    check("format 3: object 26 rounds a tie as `%.1f` does (10.25 to 10.2)", table.concat(t) == payloads[2], table.concat(t))
    check("format 3: object 26's bytes read as the same times",
      readsAs(2, '{"player": [["S:14320:26398", 0, 10.2, 174300.2, null]], "target": []}'))
    -- a value the client gives as infinity or NaN cannot hold the build in its loop (review of #248)
    C_UnitAuras = { GetAuraDataByIndex = function(u, i, filter)
      if u == "player" and i == 1 and filter == "HELPFUL" then
        return { spellId = 14320, name = "Aspect of the Hawk", applications = math.huge, duration = 0 / 0, expirationTime = -math.huge }
      end
    end }
    check("format 3: object 26 ends its build with values that are not finite", type(S2.aurasBin(b)) == "number")
    C_UnitAuras = realAuras
  end

  -- Object 24 in binary: the bytes of tests/vectors/objects3.json's third object, written by the
  -- addon from the same units; the values they read as are those of the reads
  do
    local payloads = {}
    for hex in io.open("tests/vectors/objects3.json"):read("*a"):gmatch('"payload": "(%x+)"') do payloads[#payloads + 1] = hex:lower() end
    local names = { "UnitExists", "UnitGUID", "UnitName", "UnitLevel", "UnitClass", "UnitClassification", "UnitIsDead",
      "UnitAffectingCombat", "UnitCanAttack", "UnitIsConnected", "UnitThreatSituation", "GetRaidTargetIndex",
      "UnitCastingInfo", "UnitChannelInfo" }
    local kept = {}
    for _, k in ipairs(names) do kept[k] = _G[k] end
    local GUID = { player = "Player-1-0000AAAA", pet = "Pet-0-1-2-3-111-00000001", party1 = "Player-1-0000ABCD",
      party1target = "Creature-0-1-2-3-740-00000000AB", nameplate1 = "Creature-0-1-2-3-740-00000000CD" }
    GUID.nameplate1target = GUID.pet
    UnitExists = function(u) return u == "party1" or u == "nameplate1" end
    UnitGUID = function(u) return GUID[u] end
    UnitName = function(u) if u == "party1target" or u == "nameplate1" then return "Adolescent Whelp" end end
    UnitLevel = function(u) return u == "party1" and 38 or 35 end
    UnitClass = function(u) if u == "party1" then return "Priest", "PRIEST" end return "Mage", "MAGE" end
    UnitClassification = function() return "normal" end
    UnitIsDead = function() return false end
    UnitAffectingCombat = function() return true end
    UnitCanAttack = function(_, u) return u == "nameplate1" end
    UnitIsConnected = function(u) return u == "party1" end
    UnitThreatSituation = function(_, u) return u == "party1" and 0 or 3 end
    GetRaidTargetIndex = function() return nil end
    UnitCastingInfo = function() return nil end
    UnitChannelInfo = function() return nil end
    local b = {}
    local len = S2.unitsBin(b)
    local t = {}
    for i = 1, len do t[i] = ("%02x"):format(b[i]) end
    check("format 3: object 24 in binary, byte for byte as written by hand", table.concat(t) == payloads[3], table.concat(t))
    check("format 3: object 24's bytes from the same reads say the same units",
      readsAs(3, '{"party1": ["P:50919:0", 38, "PRIEST", "normal", 10, "C:740:10475", 0, null, null], '
        .. '"nameplates": [["C:740:10475", 35, "MAGE", "normal", 6, "pet", 3, null, null]]}'))
    for _, k in ipairs(names) do _G[k] = kept[k] end
  end

  -- Object 27 in binary: the bytes of tests/vectors/objects3.json's fourth object, written by the
  -- addon; the values they read as are those of the reads
  do
    local payloads = {}
    for hex in io.open("tests/vectors/objects3.json"):read("*a"):gmatch('"payload": "(%x+)"') do payloads[#payloads + 1] = hex:lower() end
    local function hexOf(b, len)
      local t = {}
      for i = 1, len do t[i] = ("%02x"):format(b[i]) end
      return table.concat(t)
    end
    local names = { "GetActionInfo", "C_Spell", "C_Item", "C_ActionBar" }
    local kept = {}
    for _, k in ipairs(names) do kept[k] = _G[k] end
    GetActionInfo = function(slot)
      if slot == 1 then return "spell", 14320, "spell" end
      if slot == 2 then return "item", 6948 end
      if slot == 3 then return "companion", 7 end
    end
    C_Spell = { GetSpellName = function(id) return id == 14320 and "Aspect of the Hawk" or nil end }
    C_Item = { GetItemNameByID = function(id) return id == 6948 and "Hearthstone" or nil end }
    C_ActionBar = { GetActionCooldown = function(slot)
      if slot == 1 then return { startTime = 0, duration = 0, isActive = false, isOnGCD = false } end
      if slot == 2 then return { startTime = 1234.5, duration = 1.5, isActive = true, isOnGCD = true } end
    end }
    local b = {}
    local len = S2.cooldownsBin(b)
    check("format 3: object 27 in binary, byte for byte as written by hand", hexOf(b, len) == payloads[4], hexOf(b, len))
    check("format 3: object 27's bytes from the same reads say the same slots",
      readsAs(4, '{"slots": [[1, "S:14320:26398", false, false, 0.0, 0.0], [2, "I:6948:35158", true, true, 1234.5, 1.5], '
        .. '[3, null, false, false, null, null]]}'))
    for _, k in ipairs(names) do _G[k] = kept[k] end
  end

  -- Object 9 in binary: tests/vectors/objects3.json's fifth to seventh objects, written by the
  -- addon from the same journeys; the values they read as are those of the reads
  do
    local payloads = {}
    for hex in io.open("tests/vectors/objects3.json"):read("*a"):gmatch('"payload": "(%x+)"') do payloads[#payloads + 1] = hex:lower() end
    local kept, J = ShortestPathForever, nil
    ShortestPathForever = { API = { Journey = function() return J end } }
    local function bin()
      local b = {}
      local len = S2.routeBin(b)
      local t = {}
      for i = 1, len do t[i] = ("%02x"):format(b[i]) end
      return table.concat(t)
    end
    J = { secondsLeft = 40, goal = { map = 1415, x = 0.48728519678116, y = 0.52361696958542, title = "RestedXP" },
      legs = { { mode = "walk", seconds = 40, text = "Walk to RestedXP" } }, owner = "RestedXP", guided = true, index = 1 }
    check("format 3: object 9 in binary, byte for byte as written by hand", bin() == payloads[5], bin())
    check("format 3: object 9's bytes from the same reads say the same route", readsAs(5,
      '{"source": "ShortestPathForever", "owner": "RestedXP", "goal": {"map": 1415, "x": 31934, "y": 34315, "title": "RestedXP"}, '
      .. '"seconds": 40, "index": 1, "guided": true, "legCount": 1, "legs": [{"mode": "walk", "seconds": 40, "text": "Walk to RestedXP"}]}'))
    J = { secondsLeft = 0 / 0, goal = { map = 1431, x = 0.1, y = 0.1 }, legs = { { mode = 7, seconds = 0 / 0, text = "bad \255" } },
      index = 1.5, guided = "yes" }
    check("format 3: object 9 with every null, byte for byte", bin() == payloads[6], bin())
    J = { secondsLeft = 5, goal = { map = 1431, x = 0.1, y = 0.1 }, legs = {}, index = 1 }
    for i = 1, 201 do J.legs[i] = {} end
    check("format 3: object 9 with more than 200 legs: legCount null, 20 legs, byte for byte", bin() == payloads[8], bin())
    J = nil
    check("format 3: no journey is object 9's null, one byte", bin() == payloads[7] and readsAs(7, "null"), bin())
    ShortestPathForever = kept
  end

  -- Object 2 in binary: tests/vectors/objects3.json's ninth to eleventh objects, written by the
  -- addon from the same target; the values they read as are those of the reads
  do
    local payloads = {}
    for hex in io.open("tests/vectors/objects3.json"):read("*a"):gmatch('"payload": "(%x+)"') do payloads[#payloads + 1] = hex:lower() end
    local names = { "UnitExists", "UnitName", "UnitClassification", "UnitLevel", "UnitCreatureType", "UnitGUID", "UnitReaction" }
    local kept = {}
    for _, k in ipairs(names) do kept[k] = _G[k] end
    local tg
    UnitExists = function(u) if u == "target" then return tg ~= nil end return kept.UnitExists(u) end
    UnitName = function(u) if u == "target" then return tg.name end return kept.UnitName(u) end
    UnitClassification = function(u) if u == "target" then return tg.class end return kept.UnitClassification(u) end
    UnitLevel = function(u) if u == "target" then return tg.level end return kept.UnitLevel(u) end
    UnitCreatureType = function(u) if u == "target" then return tg.kind end return kept.UnitCreatureType(u) end
    UnitGUID = function(u) if u == "target" then return tg.guid end return kept.UnitGUID(u) end
    UnitReaction = function(u) if u == "target" then return tg.reaction end return kept.UnitReaction(u) end
    local function bin()
      local b = {}
      local len = S2.targetBin(b)
      if type(len) ~= "number" then return tostring(len) end
      local t = {}
      for i = 1, len do t[i] = ("%02x"):format(b[i]) end
      return table.concat(t)
    end
    tg = { name = "Wetlands Crocolisk", class = "normal", level = 23, kind = "Beast",
      guid = "Creature-0-1-2-3-1984-0000ABCDEF", reaction = 4 }
    check("format 3: object 2 in binary, byte for byte as written by hand", bin() == payloads[9], bin())
    check("format 3: object 2's bytes from the same reads say the same target", readsAs(9,
      '{"name": "Wetlands Crocolisk", "type": "Beast", "class": "normal", "level": 23, "id": 1984, "reaction": 4}'))
    tg = { name = "Bob", class = "normal", level = -1, guid = "Player-1-0000ABCD", reaction = 9 }
    check("format 3: object 2 with no type, a hidden level, no id and no reaction, byte for byte", bin() == payloads[10], bin())
    tg = nil
    check("format 3: no target is object 2's null, one byte", bin() == payloads[11] and readsAs(11, "null"), bin())
    tg = { name = SECRET, class = "normal", level = 1, guid = "x" }
    check("format 3: a target that cannot be read is no binary (format 255)", bin() == "nil", bin())
    -- the refresh path writes the bytes of format 255 for it, FF 00 00 (review of #261): not 253
    local o = { bin = S2.targetBin }
    local function sums(t) local s1, s2 = 0, 0 for i = 1, #t do s1 = (s1 + t[i]) % 255 s2 = (s2 + s1) % 255 end return s1, s2 end
    S2.refreshBin(o, now, sums, 1000, nil)
    check("format 3: a target that cannot be read goes as FF 00 00", o.obj and #o.obj == 3 and o.obj[1] == 255
      and o.obj[2] == 0 and o.obj[3] == 0, o.obj and table.concat(o.obj, " "))
    for _, k in ipairs(names) do _G[k] = kept[k] end
  end

  -- Object 13 in binary: tests/vectors/objects3.json's twelfth to fourteenth objects, written by
  -- the addon from the same acknowledgement; the values they read as are those of the reads
  do
    local payloads = {}
    for hex in io.open("tests/vectors/objects3.json"):read("*a"):gmatch('"payload": "(%x+)"') do payloads[#payloads + 1] = hex:lower() end
    local keptHf, keptState = HelloForeverAssist, ns.AssistState
    local function bin()
      local b = {}
      local len = S2.assistBin(b)
      local t = {}
      for i = 1, len do t[i] = ("%02x"):format(b[i]) end
      return table.concat(t)
    end
    HelloForeverAssist = { on = true, lang = "en", shown = "bags", ask = { n = 4, topic = "session", t = 1794516375 } }
    ns.AssistState = { seq = 12, re = 3, left = 163, taken = 1, refused = 0 }
    check("format 3: object 13 in binary, byte for byte as written by hand", bin() == payloads[12], bin())
    check("format 3: object 13's bytes from the same reads say the same", readsAs(12,
      '{"on": true, "lang": "en", "seq": 12, "re": 3, "ask": {"n": 4, "topic": "session", "t": 1794516375}, '
      .. '"left": 163, "taken": 1, "refused": 0, "shown": "bags"}'))
    HelloForeverAssist = { on = true, lang = "en" }
    ns.AssistState = {}
    check("format 3: object 13 before the first cards and look, byte for byte", bin() == payloads[13], bin())
    HelloForeverAssist = { on = false, lang = "en" }
    check("format 3: the assistant off is object 13's null, one byte", bin() == payloads[14] and readsAs(14, "null"), bin())
    -- seq and re up to 2^53 (what the assistant takes): the zigzag is twice that, not 0 (review of #262)
    local function hex(n) local b = {} local len = S2.bin.svar(b, 0, n) local t = {} for i = 1, len do t[i] = ("%02x"):format(b[i]) end return table.concat(t) end
    check("format 3: a whole number of 2^53 goes as the zigzag 2^54, eight bytes", hex(2 ^ 53) == "8080808080808020", hex(2 ^ 53))
    check("format 3: 2^52 as the zigzag 2^53", hex(2 ^ 52) == "8080808080808010", hex(2 ^ 52))
    HelloForeverAssist, ns.AssistState = keptHf, keptState
  end

  -- Objects 3 and 8 in binary: tests/vectors/objects3.json's 15th to 18th objects, written by the
  -- addon from the same reads; the values they read as are those of the reads
  do
    local payloads = {}
    for hex in io.open("tests/vectors/objects3.json"):read("*a"):gmatch('"payload": "(%x+)"') do payloads[#payloads + 1] = hex:lower() end
    local kept = { best = C_Map.GetBestMapForUnit, zone = GetRealZoneText, sub = GetSubZoneText, inside = IsInInstance,
      info = GetInstanceInfo, rested = GetXPExhaustion }
    local function hexOf(f)
      local b = {}
      local len = f(b)
      if type(len) ~= "number" then return tostring(len) end
      local t = {}
      for i = 1, len do t[i] = ("%02x"):format(b[i]) end
      return table.concat(t)
    end
    C_Map.GetBestMapForUnit = function() return 1437 end
    GetRealZoneText = function() return "Wetlands" end
    GetSubZoneText = function() return "Black Channel Marsh" end
    IsInInstance = function() return false, "none" end
    GetInstanceInfo = function() return "Eastern Kingdoms", "none", 0, "", 5, 0, false, 0 end
    check("format 3: object 3 in binary, byte for byte as written by hand", hexOf(S2.placeBin) == payloads[15], hexOf(S2.placeBin))
    check("format 3: object 3's bytes from the same reads say the same place", readsAs(15,
      '{"map": 1437, "zone": "Wetlands", "sub": "Black Channel Marsh", "instance": false, "instanceType": "none", '
      .. '"instanceMap": 0, "instanceName": "Eastern Kingdoms"}'))
    C_Map.GetBestMapForUnit = function() return 1429 end
    GetRealZoneText = function() return "Elwynn Forest" end
    GetSubZoneText = function() return nil end
    IsInInstance, GetInstanceInfo = nil, nil
    check("format 3: object 3 with no subzone and no instance facts, byte for byte", hexOf(S2.placeBin) == payloads[16], hexOf(S2.placeBin))
    C_Map.GetBestMapForUnit = function() return 2 ^ 31 end      -- no map under 2^31 (review of #264)
    check("format 3: a map that is no whole number under 2^31 is no place (format 255)",
      hexOf(S2.placeBin) == "nil", hexOf(S2.placeBin))
    C_Map.GetBestMapForUnit = function() return 1429 end
    GetRealZoneText = function() return SECRET end
    check("format 3: a place that cannot be read is no binary (format 255)",
      hexOf(S2.placeBin) == "nil", hexOf(S2.placeBin))
    GetXPExhaustion = function() return 12345.6 end
    check("format 3: object 8 in binary, byte for byte as written by hand", hexOf(S2.restBin) == payloads[17]
      and readsAs(17, '{"rested": 12345}'), hexOf(S2.restBin))
    GetXPExhaustion = function() return nil end
    check("format 3: object 8 with none rested, byte for byte", hexOf(S2.restBin) == payloads[18], hexOf(S2.restBin))
    GetXPExhaustion = function() return -1 end
    check("format 3: a rested XP that is no amount is no binary (format 255)", hexOf(S2.restBin) == "nil")
    C_Map.GetBestMapForUnit, GetRealZoneText, GetSubZoneText = kept.best, kept.zone, kept.sub
    IsInInstance, GetInstanceInfo, GetXPExhaustion = kept.inside, kept.info, kept.rested
  end

  -- Object 12 in binary: tests/vectors/objects3.json's 19th to 22nd objects, written by the addon
  -- from the same HelloForever table; the values they read as are those of the reads
  do
    local payloads = {}
    for hex in io.open("tests/vectors/objects3.json"):read("*a"):gmatch('"payload": "(%x+)"') do payloads[#payloads + 1] = hex:lower() end
    local kept = HelloForeverBaseline
    local function bin()
      local b = {}
      local len = S2.baselineBin(b)
      local t = {}
      for i = 1, len do t[i] = ("%02x"):format(b[i]) end
      return table.concat(t)
    end
    HelloForeverBaseline = { fight = "hf1-0000abcd-1794516378-12-1", rev = 1, counted = true, id = 1984, level = 14,
      name = "Defias Thug", dur = { 12.4, 15, 8 }, dps = { 37.6, 31, 8 }, taken = { 210, 340, 8 }, died = { false, 0, 8 } }
    check("format 3: object 12 in binary, byte for byte as written by hand", bin() == payloads[19], bin())
    check("format 3: object 12's bytes from the same reads say the same fight", readsAs(19,
      '{"fight": "hf1-0000abcd-1794516378-12-1", "rev": 1, "counted": true, "id": 1984, "level": 14, "name": "Defias Thug", '
      .. '"dur": [12, 15, 8], "dps": [38, 31, 8], "taken": [210, 340, 8], "died": [false, 0, 8]}'))
    HelloForeverBaseline = { fight = "f-1", rev = 1, counted = true, id = 299, level = 5, name = "bad \255",
      dur = { 10, 12, 2 }, dps = { 5, 4, 2 }, taken = { 0, 1, 2 }, died = { true, nil, 2 } }
    check("format 3: object 12 with no name, no usual values and a death, byte for byte", bin() == payloads[20], bin())
    HelloForeverBaseline = { fight = "hf1-0000abcd-1794516378-12-1", rev = 2, counted = false }
    check("format 3: object 12 of a fight not counted, byte for byte", bin() == payloads[21], bin())
    HelloForeverBaseline = nil
    check("format 3: no baseline is object 12's null, one byte", bin() == payloads[22] and readsAs(22, "null"), bin())
    HelloForeverBaseline = kept
  end

  -- Objects 4 and 14 in binary: tests/vectors/objects3.json's 23rd to 27th objects, written by the
  -- addon; the values they read as are those of the reads; a shot (the ammunition's count alone) makes
  -- no new version, any other change does (the key, #44)
  do
    local payloads = {}
    for hex in io.open("tests/vectors/objects3.json"):read("*a"):gmatch('"payload": "(%x+)"') do payloads[#payloads + 1] = hex:lower() end
    local names = { "GetInventoryItemID", "GetInventoryItemLink", "GetInventoryItemDurability", "GetInventoryItemCount" }
    local kept, keptC = {}, C_Container
    for _, k in ipairs(names) do kept[k] = _G[k] end
    local worn, ammo, ammoCount, bags = {}, nil, 0, {}
    GetInventoryItemID = function(_, slot) if slot == 0 then return ammo end return worn[slot] and worn[slot].id end
    GetInventoryItemLink = function(_, slot) return worn[slot] and worn[slot].link end
    GetInventoryItemDurability = function(slot) if worn[slot] and worn[slot].dur then return worn[slot].dur[1], worn[slot].dur[2] end end
    GetInventoryItemCount = function(_, slot) if slot == 0 then return ammoCount end end
    C_Container = { GetContainerNumFreeSlots = function(bag) return bags[bag] and bags[bag].free or 0, 0 end,
      GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
      GetContainerItemInfo = function(bag, slot) local s = bags[bag] and bags[bag][slot] return s and { itemID = s[1], stackCount = s[2] } or nil end }
    local function hexOf(f)
      local b, k = {}, {}
      local len = f(b, k)
      if type(len) ~= "number" then return tostring(len) end
      local t = {}
      for i = 1, len do t[i] = ("%02x"):format(b[i]) end
      return table.concat(t)
    end
    bags = { [0] = { { 2318, 10 }, { 2318, 6 }, { 4234, 3 }, free = 12 } }
    check("format 3: object 4 in binary, byte for byte as written by hand", hexOf(S2.bagsBin) == payloads[23], hexOf(S2.bagsBin))
    check("format 3: object 4's bytes from the same reads say the same", readsAs(23, '{"free": 12, "items": [[2318, 16], [4234, 3]]}'))
    bags = {}
    check("format 3: object 4 of empty bags, byte for byte", hexOf(S2.bagsBin) == payloads[24], hexOf(S2.bagsBin))
    ammo, ammoCount = 3030, 2783
    worn = { [16] = { id = 2504, link = "|cff1eff00|Hitem:2504:1887:::::-9:0:60:::::::|h[Thing]|h|r", dur = { 50, 60 } } }
    check("format 3: object 14 in binary, byte for byte as written by hand", hexOf(S2.gearBin) == payloads[25], hexOf(S2.gearBin))
    check("format 3: object 14's bytes from the same reads say the same", readsAs(25,
      '{"slots": {"0": {"item": 3030, "count": 2783}, "16": {"item": 2504, "enchant": 1887, "suffix": -9, "dur": [50, 60]}}}'))
    -- the key: a shot makes no new version; a change of durability does
    local function sums(t) local s1, s2 = 0, 0 for i = 1, #t do s1 = (s1 + t[i]) % 255 s2 = (s2 + s1) % 255 end return s1, s2 end
    local o = { bin = S2.gearBin }
    S2.refreshBin(o, now, sums, 1000, nil)
    local v = o.version
    ammoCount = 2782
    S2.refreshBin(o, now, sums, 1000, nil)
    local afterShot = o.version
    worn[16].dur = { 49, 60 }
    S2.refreshBin(o, now, sums, 1000, nil)
    check(("format 3: a shot makes no new version of object 14 (%s, %s), a worn item's durability does (%s)"):format(v, afterShot, o.version),
      v ~= nil and afterShot == v and o.version ~= v)
    bags = { [0] = { { 3030, 200 }, { 3030, 1 }, { 4234, 3 }, free = 4 } }
    local ob = { bin = S2.bagsBin }
    S2.refreshBin(ob, now, sums, 1000, nil)
    v = ob.version
    bags = { [0] = { { 3030, 200 }, { 3030, 1 }, { 4234, 3 }, free = 4 } }
    bags[0][1][2] = 199
    S2.refreshBin(ob, now, sums, 1000, nil)
    afterShot = ob.version
    bags = { [0] = { { 3030, 199 }, { 4234, 3 }, free = 5 } }   -- a stack shot empty: a slot freed, no new version
    S2.refreshBin(ob, now, sums, 1000, nil)
    local afterEmpty = ob.version
    bags = { [0] = { { 3030, 199 }, { 4234, 4 }, free = 5 } }
    S2.refreshBin(ob, now, sums, 1000, nil)
    check(("format 3: shots and a stack shot empty make no new version of object 4 (%s, %s, %s), another item does (%s)"):format(
      v, afterShot, afterEmpty, ob.version), v ~= nil and afterShot == v and afterEmpty == v and ob.version ~= v)
    -- the same key on a narrower strip: the version is made again in the encoding that suits it; another
    -- ammunition with the same bytes is a new version, as the text's key says (review of #266)
    local function squeeze(s) return s:sub(1, 4) end
    S2.refreshBin(ob, now, sums, 1000, squeeze)
    local wide = ob.version
    S2.refreshBin(ob, now, sums, 5, squeeze)
    check(("format 3: the same key on a strip too narrow for it goes deflated, a new version (%s, %s, format %s)"):format(
      wide, ob.version, ob.obj and ob.obj[1]), ob.version ~= wide and ob.obj and ob.obj[1] == 3)
    bags = { [0] = { { 3030, 200 }, { 3031, 200 }, { 4234, 3 }, free = 4 } }
    S2.refreshBin(ob, now, sums, 1000, squeeze)
    local before = ob.version
    ammo = 3031
    S2.refreshBin(ob, now, sums, 1000, squeeze)
    check(("format 3: another ammunition in use, the same bags, is a new version of object 4 (%s, %s)"):format(before, ob.version),
      ob.version ~= before)
    ammo = 3030
    ammo, worn = nil, { [1] = { id = 7, link = "|Hitem:7::::::::1:::::::|h[x]|h|r" } }
    check("format 3: object 14 with no enchant, suffix or durability, byte for byte", hexOf(S2.gearBin) == payloads[26], hexOf(S2.gearBin))
    worn = {}
    check("format 3: object 14 with nothing worn, byte for byte", hexOf(S2.gearBin) == payloads[27], hexOf(S2.gearBin))
    for _, k in ipairs(names) do _G[k] = kept[k] end
    C_Container = keptC
  end

  -- The same payload, a smaller limit (a narrower strip): the newest version is not kept as it is
  -- but goes deflated; a deflate that failed is tried again (review of #253)
  do
    local function sums(bytes) local s1, s2 = 0, 0 for i = 1, #bytes do s1 = (s1 + bytes[i]) % 255; s2 = (s2 + s1) % 255 end return s1, s2 end
    local o = { bin = function(b) for i = 1, 400 do b[i] = i % 7 end return 400 end }
    local works = true
    local function squeeze(s) return works and s:sub(1, 20) or nil end   -- a stand-in for the client's deflate
    S2.refreshBin(o, 1, sums, 1536, squeeze)
    local plain = o.obj[1]
    S2.refreshBin(o, 2, sums, 300, squeeze)
    local smaller = o.obj[1]
    o.obj = nil; o.raw = nil
    works = false
    S2.refreshBin(o, 3, sums, 300, squeeze)
    local failed = o.obj[1]
    works = true
    S2.refreshBin(o, 4, sums, 300, squeeze)
    check(("format 3: a payload that no longer fits goes deflated (%s, %s), a failed deflate is tried again (%s, %s)")
      :format(plain, smaller, failed, o.obj[1]), plain == 2 and smaller == 3 and failed == 2 and o.obj[1] == 3)
  end

  -- The addon in format 3: the row's head, one clock, a new version twice, again after a stall.
  -- A new chunk length gives every object a new version (S2.rechunked): a narrow game for a
  -- moment, then the full width again, so that the objects below go up as new versions.
  GetPhysicalScreenSize = function() return 500, 1440 end
  events.OnEvent(events, "DISPLAY_SIZE_CHANGED"); tick(0.1)
  GetPhysicalScreenSize = function() return 2560, 1440 end
  events.OnEvent(events, "DISPLAY_SIZE_CHANGED"); tick(0.1)
  local from = now          -- the ring also holds the frames before this section: only those after this
  local drawn, real3, seen = {}, S2.frame3, nil
  S2.frame3 = function(b, session, dwell, seq, state, sending, objects, ids)
    seen = objects
    drawn[#drawn + 1] = { t = now, id = sending and sending.id, version = sending and sending.version,
      stay = sending and sending.till and sending.till - now,
      need = sending and sending.need,
      index = sending and sending.index, count = sending and #sending.chunks, again = sending and sending.again,
      new = sending and sending.new }
    return real3(b, session, dwell, seq, state, sending, objects, ids)
  end
  local px = 0.5
  local realMap = C_Map.GetPlayerMapPosition
  C_Map.GetPlayerMapPosition = function() return { GetXY = function() return px, 0.25 end } end
  for i = 1, 600 do          -- 10 s at 60 updates a second, walking
    if i % 10 == 0 then px = px + 0.0001 end
    tick(1 / 60)
  end
  local ring, short, gaps = HelloLinkDB.frames, 0, 0
  local times = {}
  for k = 1, #ring.t do if ring.t[k] > from then times[#times + 1] = ring.t[k] end end
  table.sort(times)
  for k = 2, #times do
    gaps = gaps + 1
    if times[k] - times[k - 1] < 0.1 - 1e-9 then short = short + 1 end
  end
  check(("format 3: one clock: no frame went up sooner than a dwell after the one before (%d gaps, %d short)"):format(gaps, short),
    gaps >= 50 and short == 0)
  local built = 0
  for k = 2, #drawn do
    if drawn[k].t - drawn[k - 1].t < 0.1 - 1e-9 then built = built + 1 end
  end
  check(("format 3: a frame is built at most once a dwell (%d builds, %d too soon)"):format(#drawn, built), #drawn >= 50 and built == 0)
  -- a new version goes twice: all its chunks, then all of them again, marked, the second sending
  -- starting 1 s or more after the first one's last chunk went up
  local function whole(from, id, version, again)   -- the time the version's chunks went up whole from `from`, or nil
    local got, count, startAt, endAt = {}, nil, nil, nil
    for k = from, #drawn do
      local e = drawn[k]
      if e.id == id and e.version == version and (e.again and true or false) == again then
        got[e.index], count = true, e.count
        startAt = startAt or e.t
        local all = true
        for i = 1, count do all = all and got[i] end
        if all then return startAt, e.t, k end
      end
    end
  end
  local pairs2, early = 0, 0                 -- every version sent twice: none again sooner than 1 s
  for a = 1, #drawn do
    local d = drawn[a]
    if d.id and d.index == 1 and d.new and not d.again then   -- a first sending, not a refresh
      local _, firstEnd, k = whole(a, d.id, d.version, false)
      local againStart, againEnd
      if firstEnd then againStart, againEnd = whole(k + 1, d.id, d.version, true) end
      if againStart and againEnd then
        pairs2 = pairs2 + 1
        if againStart - firstEnd < 1 - 1e-9 then early = early + 1 end
      end
    end
  end
  check(("format 3: a new version goes whole once again, each starting 1 s or more after it went up whole (%d versions, %d sooner)")
    :format(pairs2, early), pairs2 >= 3 and early == 0)
  -- a stop of 0.5 s: what was up in the second before goes once again
  -- (no version waits to go again by the rule above, so only the stop can send one again)
  for _, o in pairs(seen) do o.againAt = nil end
  local before = #drawn
  local upBefore = {}
  for k = before, 1, -1 do
    if now - drawn[k].t > 1 then break end
    if drawn[k].id then upBefore[drawn[k].id] = true end
  end
  tick(0.5)
  local stopped = now
  for _ = 1, 120 do tick(1 / 60) end
  local resent
  for k = before + 1, #drawn do
    local d = drawn[k]
    -- in the 0.9 s after the stop: the rule above sends again only 1 s after a version went whole
    if d.t <= stopped + 0.9 and d.again and d.index == 1 and upBefore[d.id] then
      local _, endAt = whole(k, d.id, d.version, true)
      if endAt then resent = d.id .. "/" .. d.version break end
    end
  end
  check("format 3: after a stop of the game, a version that was up before it goes once again (" .. tostring(resent) .. ")",
    next(upBefore) ~= nil and resent ~= nil)
  -- The painted row read back by the Rust reader (section 6), at 6 bits and at 3 bits: every
  -- frame read as format 3, and `replay` gives its states and objects (review of #242).
  local wasDepth = HelloLinkDB.depth
  local realAuras = C_UnitAuras      -- an aura, so that object 26 goes in binary (object format 2)
  local stacks = 2                   -- one more at each depth: a new version, sent at once, not by the refresh round
  C_UnitAuras = { GetAuraDataByIndex = function(u, i, filter)
    if u == "player" and i == 1 and filter == "HELPFUL" then
      return { spellId = 14320, name = "Aspect of the Hawk", applications = stacks, duration = 1800,
        expirationTime = 174300.53, sourceUnit = "player" }
    end
  end }
  for _, depth in ipairs({ "4", "2" }) do
    slash("strip depth " .. depth)
    stacks = stacks + 1
    tick(0.1)
    local paths = {}
    for _ = 1, 60 do   -- 6 s: the scan builds each id about every 5.4 s, so the new version is in it
      px = px + 0.0001
      tick(0.1)
      paths[#paths + 1] = dump()
    end
    local rows = read(paths, 0.1)
    local framed, record = 0, { '{"record": 1, "started": 1}' }
    for line in rows:gmatch("[^\n]+") do
      local i, hex = line:match('"i": (%d+)'), line:match('"frame": "(%x+)"')
      if hex and line:find('"format": 3', 1, true) and line:find('"why": null', 1, true) then
        framed = framed + 1
        record[#record + 1] = ('{"t": %.1f, "frame": "%s", "depth": %s, "levels": %s, "more": %s}'):format(
          tonumber(i) * 0.1, hex, depth, line:match('"levels": (%b[])'), line:match('"more": (%b[])'))
      end
    end
    check(("format 3 at depth %s: the reader reads every frame of the row (%d of 60)"):format(depth, framed), framed == 60,
      rows:sub(1, 400))
    local f = assert(io.open(DIR .. "/format3_" .. depth .. ".jsonl", "w"))
    f:write(table.concat(record, "\n"), "\n")
    f:close()
    local events = sh("reader/target/release/hellolink replay " .. DIR .. "/format3_" .. depth .. ".jsonl")
    local states, objects, last, binary = 0, 0, nil, nil
    for line in events:gmatch("[^\n]+") do
      if line:find('"kind": "state"', 1, true) then states, last = states + 1, line end
      if line:find('"kind": "object"', 1, true) then objects = objects + 1 end
      if line:find('"format": 2, "id": 26', 1, true) or (line:find('"id": 26', 1, true) and line:find('"format": 2', 1, true)) then binary = line end
    end
    check(("format 3 at depth %s: object 26 comes in binary (object format 2) and reads as its JSON"):format(depth),
      binary and has(binary, "S:14320:26398") and has(binary, '"kind": "object"'), (binary or events):sub(1, 400))
    check(("format 3 at depth %s: replay gives format 3 states with the walked position (%d states), and objects (%d)")
      :format(depth, states, objects),
      states >= 20 and objects >= 1 and last and has(last, '"format": 3')
        and has(last, ('"x": %d'):format(math.floor(px * 65535 + 0.5))), (last or events):sub(1, 600))
  end
  -- the back-off (section 4 B): while the game draws under 20 frames a second, the chunk moves on
  -- every second frame, also when the updates come late; the fixed part still goes every frame
  -- (here the walk changes it every dwell); GetFramerate is read once a second (review of #257)
  do
    local function run(fps, step, seconds)
      local calls = 0
      GetFramerate = function() calls = calls + 1 return type(fps) == "function" and fps() or fps end
      S2.rateAt = 0                                  -- read at the next update
      tick(step)
      local first, frames, realNote = #drawn + 1, 0, S2.noteFrame
      S2.noteFrame = function(...) frames = frames + 1 return realNote(...) end
      calls = 0
      local moved = now
      for _ = 1, math.floor(seconds / step + 0.5) do
        if now - moved >= 0.1 - 1e-9 then px, moved = px + 0.0001, now end
        tick(step)
      end
      S2.noteFrame = realNote
      -- runs: how many frames in a row each chunk was on; the first and last runs left out
      local runs, needs, last, n, need = {}, {}, nil, 0, nil
      for k = first, #drawn do
        local d = drawn[k]
        local key = d.id and (d.id .. ":" .. d.version .. ":" .. d.index .. ":" .. tostring(d.again)) or "none"
        if key == last then n = n + 1 else
          if last then runs[#runs + 1], needs[#runs + 1] = n, need end
          last, n, need = key, 1, d.need
        end
      end
      table.remove(runs, 1)
      table.remove(needs, 1)
      local shortest, shortestSlow = math.huge, math.huge
      for i, r in ipairs(runs) do
        shortest = math.min(shortest, r)
        if needs[i] == 2 then shortestSlow = math.min(shortestSlow, r) end
      end
      return shortest, frames, calls, nil, shortestSlow
    end
    local fastShort, fastFrames, _, fastGap = run(60, 1 / 60, 3)
    local slowShort, slowFrames, slowCalls = run(15, 1 / 60, 3)
    slash("strip dwell 5")                         -- the shortest dwell, 0.05 s, and updates 0.125 s apart
    local lateShort = run(8, 0.125, 3)               -- (8 frames a second): past two dwells, under a stall
    slash("strip dwell 10")
    local againShort = run(25, 1 / 60, 3)
    -- the rate going up and down each second: a chunk begun slow still stays its two frames
    local _, _, _, _, flipShort = run(function() return math.floor(now) % 2 == 0 and 15 or 25 end, 1 / 60, 6)
    GetFramerate = nil
    S2.rateAt = 0
    print(("   back-off: shortest run fast %s slow %s late %s again %s; frames %d, %d; calls %d"):format(
      fastShort, slowShort, lateShort, againShort, fastFrames, slowFrames, slowCalls))
    check(("format 3: under 20 frames a second each chunk is on two frames or more (shortest %s; %s at 60)"):format(slowShort, fastShort),
      slowShort >= 2 and fastShort == 1)
    check(("format 3: also when the updates come late, past a dwell (shortest %s)"):format(lateShort), lateShort >= 2)
    check(("format 3: the fixed part still goes every dwell when the game is slow (%d frames against %d)"):format(slowFrames, fastFrames),
      slowFrames >= fastFrames - 2 and slowFrames >= 25)
    check(("format 3: at 20 frames a second or more, a chunk a frame again (shortest %s)"):format(againShort), againShort == 1)
    check(("format 3: a chunk begun while slow stays two frames when the rate goes up (shortest %s)"):format(flipShort),
      flipShort ~= math.huge and flipShort >= 2)
    check(("format 3: GetFramerate is read once a second (%d in 3 s)"):format(slowCalls), slowCalls >= 2 and slowCalls <= 4)
  end
  -- a raid of 40 and 12 nameplates: object 24's binary passes what one version may send (12 chunks
  -- of 128), so it goes deflated by the client, still binary (object format 3), not as format 254
  -- (review of #251). The client's deflate is gzip's raw stream here, as above.
  do
    local names = { "UnitExists", "UnitGUID", "UnitName", "UnitLevel", "UnitClass", "UnitClassification", "C_EncodingUtil" }
    local kept = {}
    for _, k in ipairs(names) do kept[k] = _G[k] end
    C_EncodingUtil = { CompressString = rawDeflate }
    UnitExists = function(u) return u:match("^raid%d+$") ~= nil or (u:match("^nameplate(%d+)$") and tonumber(u:match("%d+")) <= 12) or false end
    UnitGUID = function(u)
      if u:match("^raid%d+target$") then return "Creature-0-1-2-3-9999-0000000001" end   -- every one on one boss
      local r = u:match("^raid(%d+)$")
      if r then return ("Player-1-%08X"):format(tonumber(r)) end
      local p = u:match("^nameplate(%d+)$")
      if p then return ("Creature-0-1-2-3-%d-%010X"):format(1000 + tonumber(p), tonumber(p)) end
    end
    UnitName = function(u)
      if u:match("^raid%d+target$") then return "The Boss" end
      local p = u:match("^nameplate(%d+)$")
      return p and ("Raid Target Dummy " .. p) or nil
    end
    UnitLevel = function() return 60 end
    UnitClass = function() return "Warrior", "WARRIOR" end
    UnitClassification = function() return "elite" end
    for _ = 1, 420 do tick(1 / 60) end   -- 7 s: object 24 is built every 0.5 s
    local o = seen[24]
    check(("format 3: a raid's units go as deflated binary when their binary is too large (format %s, %d bytes)")
      :format(tostring(o and o.obj and o.obj[1]), o and o.obj and #o.obj or 0),
      o and o.obj and o.obj[1] == 3 and #o.obj <= 12 * 128)
    for _, k in ipairs(names) do _G[k] = kept[k] end
    for _ = 1, 420 do tick(1 / 60) end   -- the raid gone: binary again
    check("format 3: with the raid gone, object 24 goes in binary again", seen[24].obj and seen[24].obj[1] == 2)
  end
  slash("strip depth " .. tostring(wasDepth))
  C_UnitAuras = realAuras
  S2.frame3 = real3
  C_Map.GetPlayerMapPosition = realMap
  tick(0.1)
end

-- ---------------- the computed palette: ramp rows and 9 bits (docs/specs/232.md, part C) ----------------
-- The ramp's levels: level k at lo + k (1 - lo) / (L - 1) of full, lo = 0.29 (the floor
-- screenshots of 22 Nov 2026). The fractions below are written out by hand from that formula.
do
  local keptSlot = slotFile
  -- the looks here serve the strip only: the slots the assistant keeps for questions are not counted
  local realLeft = ns.AssistLeft
  ns.AssistLeft = function() return nil end
  local S2 = ns.Strip2
  local FOUR = { 87 / 300, 158 / 300, 229 / 300, 1 }   -- 0.29, 0.526667, 0.763333, 1: the bytes 74, 134, 195, 255
  local EIGHT = { 203 / 700, 274 / 700, 345 / 700, 416 / 700, 487 / 700, 558 / 700, 629 / 700, 1 }   -- 74, 100, 126, 152, 177, 203, 229, 255
  -- the ramp's codes at 4 levels as level triples (from 1): 0; red rising; green rising; blue rising
  local RAMP4 = { { 1, 1, 1 }, { 2, 1, 1 }, { 3, 1, 1 }, { 4, 1, 1 }, { 1, 2, 1 }, { 1, 3, 1 }, { 1, 4, 1 },
    { 1, 1, 2 }, { 1, 1, 3 }, { 1, 1, 4 } }
  local px = 0.4
  local realMap = C_Map.GetPlayerMapPosition
  C_Map.GetPlayerMapPosition = function() return { GetXY = function() return px, 0.25 end } end
  -- the bytes of the last frame the addon built (the table it builds in is the one it then shows)
  local built, real3 = nil, S2.frame3
  S2.frame3 = function(b, ...)
    local n = real3(b, ...)
    built = { b = b, n = n }
    return n
  end
  local function builtHex()
    local t = {}
    for i = 1, built.n do t[i] = ("%02x"):format(built.b[i]) end
    return table.concat(t)
  end
  -- a frame that differs from the one before (the walk moves), drawn and read
  local function frameNow()
    px = px + 0.0001
    tick(0.1)
    return read({ dump() })
  end
  local function colourAt(sq)   -- the colour of square `sq` (from 0) on the row
    local side = S2.side(HelloLinkDB) * unit
    for _, t in ipairs(textures) do
      if t.parent == row and t.shown and math.abs(t.x - sq * side) < 1e-6 then return { t.r, t.g, t.b } end
    end
  end
  local function near(c, want)
    return c ~= nil and math.abs(c[1] - want[1]) < 1e-9 and math.abs(c[2] - want[2]) < 1e-9 and math.abs(c[3] - want[3]) < 1e-9
  end
  local function onLevels(sq, count, levels)   -- every channel of the squares sq to sq + count - 1 is one of the levels
    for i = sq, sq + count - 1 do
      local c = colourAt(i)
      for k = 1, 3 do
        local ok = false
        for _, v in ipairs(levels) do ok = ok or (c ~= nil and math.abs(c[k] - v) < 1e-9) end
        if not ok then return false, i end
      end
    end
    return true
  end
  local function frameLen(line) return #(line:match('"frame": "(%x+)"') or "") / 2 end
  slash("strip depth auto")
  local drawn = frameNow()
  check("ramp: off by default; the row is the drawn palette (digit 5, apart, no gap), its bytes the addon's",
    ns.StripState().ramp == false and HelloLinkDB.ramp == false and has(slash("strip depth auto"), "ramp off")
      and has(drawn, '"depth": 4') and has(drawn, '"why": null') and not has(drawn, '"gap"') and not has(drawn, '"apart": null')
      and drawn:match('"frame": "(%x+)"') == builtHex() and near(colourAt(20), { 1, 0, 1 }), drawn:sub(1, 300))
  check("/hlink strip ramp on is taken, saved and said", has(slash("strip ramp on"), "ramp on") and HelloLinkDB.ramp == true
    and ns.StripState().ramp == true)
  local ramp = frameNow()
  check("ramp on at 6 bits: the reader reads a ramp row (depth 4, gap 60 of the bytes 74, 134, 195, 255, leak 0, no apart)",
    has(ramp, '"format": 3') and has(ramp, '"depth": 4') and has(ramp, '"gap": 60') and has(ramp, '"leak": 0')
      and has(ramp, '"apart": null') and has(ramp, '"why": null') and has(ramp, ('"session": %d'):format(HelloLinkDB.session)),
    ramp:sub(1, 400))
  check("ramp on: the frame's bytes as read are the bytes the addon built, as with the drawn palette",
    ramp:match('"frame": "(%x+)"') == builtHex() and frameLen(ramp) > 80, ramp:sub(1, 200))
  check("ramp on: the depth square is the digit 1, square 28 the levels square (the digit 3)",
    near(colourAt(20), { 0, 0, 1 }) and near(colourAt(21), { 0, 0, 0 }) and near(colourAt(28), { 0, 1, 1 }))
  local rampOk = true
  for i, l in ipairs(RAMP4) do
    if not near(colourAt(28 + i), { FOUR[l[1]], FOUR[l[2]], FOUR[l[3]] }) then rampOk = false end
  end
  check("ramp on: the 10 ramp squares are the codes 0, 16, 32, 48, 4, 8, 12, 1, 2, 3 at 0.29, 0.526667, 0.763333, 1; `more` at 39",
    rampOk and near(colourAt(39), { 0, 0, 0 }) and near(colourAt(40), { 1, 0, 1 }))   -- `more`: 5, the digits 0 and 5
  local onRamp, bad = onLevels(39 + 17, math.floor(frameLen(ramp) * 8 / 6), FOUR)
  check("ramp on: every frame square is drawn at the ramp's levels, not the drawn palette's", onRamp, bad)
  -- the fall-back from a ramp row at 6 bits: 3 bits, as before
  slotFile = { seq = 21, text = "", strip = { session = HelloLinkDB.session, bits = 3 } }
  out = {}
  tick(600)
  local three = frameNow()
  check("a request for 3 bits from a ramp row at 6 bits makes the row depth 2 (digit 7, no ramp), and chat says so",
    has(three, '"depth": 2') and not has(three, '"gap"') and has(three, '"why": null') and near(colourAt(20), { 1, 1, 1 })
      and has(table.concat(out, "\n"), "falls back to 3 bits"), three:sub(1, 300))
  slash("strip depth auto")
  -- 9 bits: they need the ramp
  slash("strip ramp off")
  check("/hlink strip bits 9 with the ramp off is refused in chat, and the bits stay 6",
    has(slash("strip bits 9"), "needs the ramp") and HelloLinkDB.bits == 6 and ns.StripState().depthNow == 4)
  slash("strip ramp on")
  check("/hlink strip bits 9 is taken and saved", has(slash("strip bits 9"), "9 bits") and HelloLinkDB.bits == 9
    and ns.StripState().depthNow == 8)
  local nine = frameNow()
  local s0 = HelloLinkDB.session
  check("9 bits: the reader reads a ramp row of 8 levels (depth 8, gap 25, leak 0) and the bytes the addon built",
    has(nine, '"depth": 8') and has(nine, '"gap": 25') and has(nine, '"leak": 0') and has(nine, '"why": null')
      and nine:match('"frame": "(%x+)"') == builtHex(), nine:sub(1, 300))
  local ok9 = near(colourAt(28), { 1, 1, 1 })   -- the levels square: the digit 7
  local codes = { { 0, 0, 0 } }
  for k = 1, 7 do codes[#codes + 1] = { k, 0, 0 } end
  for k = 1, 7 do codes[#codes + 1] = { 0, k, 0 } end
  for k = 1, 7 do codes[#codes + 1] = { 0, 0, k } end
  for i, l in ipairs(codes) do
    if not near(colourAt(28 + i), { EIGHT[l[1] + 1], EIGHT[l[2] + 1], EIGHT[l[3] + 1] }) then ok9 = false end
  end
  local onNine, bad9 = onLevels(51 + 17, math.floor(frameLen(nine) * 8 / 9), EIGHT)
  check("9 bits: the levels square, the 22 ramp squares, `more` at 51, every frame square at the 8 levels",
    ok9 and near(colourAt(51), { 0, 0, 0 }) and near(colourAt(52), { 1, 0, 1 }) and onNine, bad9)
  -- 9 to 6 to 3 in one session, by two requests
  slotFile = { seq = 22, text = "", strip = { session = s0, bits = 6 } }
  out = {}
  tick(600)
  local six = frameNow()
  check("a request for 6 bits from a 9-bit row makes it the 6-bit ramp row, in the same session, and chat says so",
    has(six, '"depth": 4') and has(six, '"gap": 60') and HelloLinkDB.session == s0 and has(six, ('"session": %d'):format(s0))
      and has(table.concat(out, "\n"), "falls back to 6 bits"), six:sub(1, 300))
  slotFile = { seq = 23, text = "", strip = { session = s0, depth = 2 } }
  out = {}
  tick(600)
  local last = frameNow()
  check("... and then `depth = 2` makes it 3 bits, still in the same session",
    has(last, '"depth": 2') and has(last, ('"session": %d'):format(s0)) and has(table.concat(out, "\n"), "falls back to 3 bits"),
    last:sub(1, 300))
  slash("strip depth auto")
  check("/hlink strip depth auto goes back to 9 bits", ns.StripState().depthNow == 8)
  check("/hlink strip ramp off makes the bits 6 again, and the row the drawn palette",
    has(slash("strip ramp off"), "ramp off") and HelloLinkDB.bits == 6 and ns.StripState().depthNow == 4
      and not has(frameNow(), '"gap"'))
  check("/hlink strip bits 6 is taken; a wrong value is refused", ns.StripSet("bits", "6") and not ns.StripSet("bits", "8")
    and not ns.StripSet("ramp", "maybe"))
  slotFile, ns.AssistLeft = keptSlot, realLeft
  S2.frame3, C_Map.GetPlayerMapPosition = real3, realMap
  tick(0.1)
end

-- ---------------- lanes (docs/specs/232.md, part C, "Lanes"; section 6, the layout square) ----------------
-- A lane is the next screen line under the row, from under the frame's first square, 1 pixel a
-- square. The frame's squares run along lane 1 to the game's right edge, then along lane 2.
do
  local S2 = ns.Strip2
  local px = 0.4
  local realMap = C_Map.GetPlayerMapPosition
  C_Map.GetPlayerMapPosition = function() return { GetXY = function() return px, 0.25 end } end
  local built, real3 = nil, S2.frame3
  S2.frame3 = function(b, ...)
    local n = real3(b, ...)
    built = { b = b, n = n }
    return n
  end
  local function builtHex()
    local t = {}
    for i = 1, built.n do t[i] = ("%02x"):format(built.b[i]) end
    return table.concat(t)
  end
  local function frameNow()
    px = px + 0.0001
    tick(0.1)
    return read({ dump() })
  end
  -- the shown squares of lane `k` (from 1), and the colour of its square `sq` (from 0, from the row's left edge)
  local function lane(k)
    local side, got = S2.side(HelloLinkDB) * unit, {}
    for _, t in ipairs(textures) do
      if t.parent == row and t.shown and math.abs(t.y + (k - 1) * side) < 1e-6 then got[#got + 1] = t end
    end
    return got
  end
  local function colourAt(sq, k)
    local side = S2.side(HelloLinkDB) * unit
    for _, t in ipairs(lane(k or 1)) do
      if math.abs(t.x - sq * side) < 1e-6 then return { t.r, t.g, t.b } end
    end
  end
  local function same(c, want) return c ~= nil and c[1] == want[1] and c[2] == want[2] and c[3] == want[3] end
  local function readsBuilt(line) return has(line, '"why": null') and line:match('"frame": "(%x+)"') == builtHex() end
  -- the objects that came whole over `steps` frames: id -> text
  local function objectsOver(steps)
    local paths = {}
    for _ = 1, steps do tick(0.1); paths[#paths + 1] = dump() end
    local got, count = {}, 0
    for id, text in read(paths):gmatch('"object": %[(%d+), %d+, ("[^\n]-")%]') do
      got[tonumber(id)], count = text, count + 1
    end
    return got, count
  end
  slash("strip size 1"); slash("strip depth auto"); slash("strip at 0 0")
  local one = frameNow()
  check("lanes: 1 by default and saved; said with the other settings; the layout square is 0 and the row reads",
    HelloLinkDB.lanes == 1 and ns.StripState().lanes == 1 and has(slash("strip depth auto"), "lanes 1")
      and same(colourAt(21), { 0, 0, 0 }) and readsBuilt(one) and not has(one, '"lanes"'), one:sub(1, 300))
  -- refusals: more than one lane needs squares of 1 pixel
  slash("strip size 2")
  local refused = slash("strip lanes 4")
  check("/hlink strip lanes 4 at 2 pixels a square is refused in chat, and the lanes stay 1",
    has(refused, "squares of 1 pixel") and not has(refused, "use /hlink strip")
      and not ns.StripSet("lanes", "4")
      and HelloLinkDB.lanes == 1, refused)
  slash("strip size 1")
  check("/hlink strip lanes 0 and 5 are not settings", not ns.StripSet("lanes", "0") and not ns.StripSet("lanes", "5")
    and has(slash("strip lanes 5"), "lanes <1-4>") and HelloLinkDB.lanes == 1)
  check("/hlink strip lanes 4 at 1 pixel is taken, saved and said",
    has(slash("strip lanes 4"), "lanes 4") and HelloLinkDB.lanes == 4 and ns.StripState().lanes == 4)
  -- the full width: the frame fits lane 1, and the lanes under it stay empty (rule 4: room, not squares)
  local wide = frameNow()
  check("4 lanes at the full width: the layout square is the digit 3, the reader reads the frame the addon built, lane 2 is empty",
    same(colourAt(21), { 0, 1, 1 }) and readsBuilt(wide) and has(wide, '"lanes": 4') and #lane(2) == 0, wide:sub(1, 300))
  -- a narrow row (2560 - 2350 pixels; review of the rebase: the frame must not fit lane 1): the frame runs on into lane 2
  slash("strip at 2350 0")
  local narrow = frameNow()
  local per = 2560 - 2350 - (27 + 1 + 64 + 2 + 3 * #S2.MORE)   -- the squares of lane 1 after the row's head
  check(("4 lanes, a narrow row: the frame (%d squares) runs over lane 1 (%d) into lane 2, and the reader joins it")
    :format(math.ceil(built.n * 8 / 6), per),
    math.ceil(built.n * 8 / 6) > per and #lane(2) > 0 and readsBuilt(narrow) and has(narrow, '"lanes": 4'), narrow:sub(1, 300))
  -- Each run below starts at a new chunk length, so every object gets a new version and is sent
  -- whole (review of #227): 0 bytes with 1 lane on the narrow row, 128 with 4 lanes there, 128 at
  -- the full width.
  local oneLane = slash("strip lanes 1")
  local _, none = objectsOver(60)
  check("1 lane, the same narrow row: no room for a chunk, so no object comes", none == 0, none)
  -- a row with no room for a chunk says so: in chat and in StripState for the window (22 Nov 2026:
  -- in the game a row at x = 2400 failed every frame and said nothing)
  check("1 lane, the same narrow row: the reply says there is no room for a chunk, and StripState's room is 0",
    has(oneLane, "no room for a chunk here") and ns.StripState().room == 0, oneLane)
  local offReply = slash("strip off")
  check("...but not while the strip is off", not has(offReply, "no room for a chunk"), offReply)
  slash("strip on")
  local fourLanes = slash("strip lanes 4")
  check("4 lanes on the narrow row: room for a chunk, and the reply says nothing of it",
    not has(fourLanes, "no room for a chunk") and ns.StripState().room > 0, fourLanes)
  local far = objectsOver(60)
  slash("strip lanes 1"); slash("strip at 0 0")
  local near = objectsOver(60)
  local sameObjects, ids, differ = next(far) ~= nil, {}, {}
  for id, text in pairs(near) do
    ids[#ids + 1] = id
    if far[id] ~= text then sameObjects, differ[#differ + 1] = false, id .. ": " .. tostring(far[id]) .. " against " .. text end
  end
  for id in pairs(far) do if near[id] == nil then sameObjects, differ[#differ + 1] = false, id .. " only with 4 lanes" end end
  table.sort(ids)
  check("4 lanes on the narrow row give the same objects as 1 lane at the full width (" .. table.concat(ids, " ") .. ")", sameObjects,
    table.concat(differ, "\n"))
  -- the ramp, 9 bits and 3 bits, each with 4 lanes on a row narrower still (2560 - 2392 pixels):
  -- lane 1 holds 112, 100 and 123 frame squares, fewer than the frame without a chunk
  slash("strip lanes 4"); slash("strip at 2392 0")
  slash("strip ramp on")
  local ramp = frameNow()
  check("4 lanes with the ramp (6 bits): the frame runs into lane 2 and the reader reads it",
    #lane(2) > 0 and readsBuilt(ramp) and has(ramp, '"gap": 60') and has(ramp, '"lanes": 4'), ramp:sub(1, 300))
  slash("strip bits 9")
  local nine = frameNow()
  check("4 lanes at 9 bits: the frame runs into lane 2 and the reader reads it",
    #lane(2) > 0 and readsBuilt(nine) and has(nine, '"depth": 8') and has(nine, '"lanes": 4'), nine:sub(1, 300))
  slash("strip ramp off"); slash("strip depth 2")
  local three = frameNow()
  check("4 lanes at 3 bits: the frame runs into lane 2 and the reader reads it",
    #lane(2) > 0 and readsBuilt(three) and has(three, '"depth": 2') and has(three, '"lanes": 4'), three:sub(1, 300))
  slash("strip depth auto")
  -- 2 pixels a square: one lane, the setting kept
  slash("strip size 2")
  local big = frameNow()
  check("at 2 pixels a square the row has one lane (layout 0), the setting stays 4",
    HelloLinkDB.lanes == 4 and same(colourAt(21), { 0, 0, 0 }) and #lane(2) == 0 and not has(big, '"lanes"'), big:sub(1, 300))
  slash("strip size 1")
  check("back at 1 pixel: 4 lanes again", same(colourAt(21), { 0, 1, 1 }))
  slash("strip lanes 1"); slash("strip at 0 0")
  check("/hlink strip lanes 1: the layout square 0, lane 2 empty", same(colourAt(21), { 0, 0, 0 }) and #lane(2) == 0
    and HelloLinkDB.lanes == 1)
  S2.frame3, C_Map.GetPlayerMapPosition = real3, realMap
  tick(0.1)
end

-- ---------------- objects 24 to 27 (docs/specs/213.md, section 7; binary in format 3) ----------------
do
  local realGuid, realExists, realName, realLevel, realClass = UnitGUID, UnitExists, UnitName, UnitLevel, UnitClass
  local realClassif, realConnected = UnitClassification, UnitIsConnected
  local U = { party1 = { guid = "Player-1-0000BEEF", name = "Friend", level = 28, class = "PRIEST" },
    party2 = { guid = "Player-1-0000CAFE", name = "Other", level = 30, class = "MAGE" },
    partypet1 = { guid = "Pet-0-1-1-1-165189-00000000AA", name = "Fluffy", level = 27, class = "WARRIOR" },
    nameplate1 = { guid = T.guid, name = T.name, level = T.level, class = "WARRIOR" } }
  UnitGUID = function(u)
    if U[u] then return U[u].guid end
    if u == "party1target" then return U.party2.guid end   -- a later unit of the table
    if u == "party2target" or u == "nameplate1target" then return T.guid end
    return realGuid(u)
  end
  -- the hash of a GUID, by the check of docs/STRIP.md section 3, written here
  local function hashOf(s)
    local s1, s2 = 0, 0
    for i = 1, #s do s1 = (s1 + s:byte(i)) % 255; s2 = (s2 + s1) % 255 end
    return s1 * 256 + s2
  end
  UnitExists = function(u) return U[u] ~= nil or realExists(u) end
  UnitName = function(u) if U[u] then return U[u].name end return realName(u) end
  UnitLevel = function(u) if U[u] then return U[u].level end return realLevel(u) end
  UnitClass = function(u) if U[u] then return U[u].class, U[u].class, 1 end return realClass and realClass(u) end
  UnitIsConnected = function() return true end
  UnitThreatSituation = function() return 2 end
  GetRaidTargetIndex = function(u) if u == "nameplate1" then return 8 end end
  local aurasSecret = false
  C_UnitAuras = { GetAuraDataByIndex = function(u, i, filter)
    if aurasSecret == "field" and u == "player" and i == 1 and filter == "HELPFUL" then
      return { spellId = SECRET, name = SECRET, applications = 0, duration = 0, expirationTime = 0, sourceUnit = "player" }
    end
    if aurasSecret then error("Auras cannot be accessed when secret while tainted by 'HelloLink'") end
    if u == "player" and i == 1 and filter == "HELPFUL" then
      return { spellId = 14320, name = "Aspect of the Hawk", applications = 0, duration = 0, expirationTime = 0, sourceUnit = "player" }
    end
  end }
  -- slot 1 a spell, slot 2 an item, slot 3 a macro of a spell
  GetActionInfo = function(slot)
    if slot == 1 then return "spell", 75, "spell" end
    if slot == 2 then return "item", 6948 end
    if slot == 3 then return "macro", 4 end
    if slot == 4 then return "macro", 19434, "spell" end   -- Forever's form: the spell's id
    if slot == 145 then return "spell", 75, "spell" end    -- the extra bar
  end
  GetMacroSpell = function(m) if m == 4 then return 1130 end end
  C_Item = { GetItemNameByID = function(id) if id == 6948 then return "Hearthstone" end end }
  C_Spell = C_Spell or {}
  C_Spell.GetSpellName = function(id)
    if id == 75 then return "Auto Shot" end
    if id == 1130 then return "Hunter's Mark" end
    if id == 19434 then return "Aimed Shot" end
  end
  C_ActionBar = C_ActionBar or {}
  local secretTimes = false
  C_ActionBar.GetActionCooldown = function()
    if secretTimes == "start" then return { startTime = SECRET, duration = 5, isActive = true, isOnGCD = false, isEnabled = true } end
    if secretTimes == "duration" then return { startTime = 5, duration = SECRET, isActive = true, isOnGCD = false, isEnabled = true } end
    return { startTime = 0, duration = 0, isActive = false, isOnGCD = false, isEnabled = true }
  end
  -- replay's events of `frames` frames; objects 24, 26 and 27 come in binary (object format 2)
  -- and read as their JSON, compact (docs/specs/232.md, part E)
  local function play(frames)
    local paths = {}
    for _ = 1, frames do tick(0.1); paths[#paths + 1] = dump() end
    return (replay(read(paths, 0.1)))
  end
  local function object(events, id)
    local last
    for line in events:gmatch("[^\n]+") do
      if line:find('"kind": "object"', 1, true) and line:find(('"id": %d,'):format(id), 1, true) then last = line end
    end
    return last
  end
  local ev = play(120)
  local units, namesObj, auras, cds = object(ev, 24), object(ev, 25), object(ev, 26), object(ev, 27)
  -- object 25 goes by the refresh only (a round is about a minute): its text, as built now
  namesObj = ns.Strip2.namesText():gsub('"', '\\"')
  check("objects 24-27: the unit table has the party member by its GUID's hash, its target the later member by token, and the nameplate",
    units and has(units, ('\\"party1\\":[\\"P:%d:0\\",28,\\"PRIEST\\"'):format(hashOf(U.party1.guid)))
      and has(units, '\\"party2\\",2,null,null]') and has(units, '\\"nameplates\\":[[\\"C:1984:')
      and has(units, '\\"target\\",2,8,null]'), units)
  check("objects 24-27: a party member's pet is there by its GUID's hash; no name and no GUID of another player is sent",
    units and has(units, ('\\"partypet1\\":[\\"P:%d:0\\"'):format(hashOf(U.partypet1.guid)))
      and not has(units, "Friend") and not has(units, "Fluffy") and not has(units, "0000BEEF"), units)
  check("objects 24-27: the names hold the creature and the spells, with their hashes",
    namesObj and has(namesObj, '\\"C:1984\\": [\\"Wetlands Crocolisk\\", ') and has(namesObj, '\\"S:75\\": [\\"Auto Shot\\", '), namesObj)
  check("objects 24-27: the player's aura out of combat", auras and has(auras, '\\"player\\":[[\\"S:14320:')
    and has(auras, '0,0.0,0.0,\\"player\\"]]'), auras)
  check("objects 24-27: every used slot: the spell, the item, the macro's spell", cds and has(cds, '[[1,\\"S:75:')
    and has(cds, '[2,\\"I:6948:') and has(cds, '[3,\\"S:1130:') and has(cds, '[4,\\"S:19434:') and has(cds, '[145,\\"S:75:')
    and has(cds, 'false,false,0.0,0.0]'), cds)
  check("objects 24-27: the names hold the item and the target from the fast data", namesObj and has(namesObj, '\\"I:6948\\": [\\"Hearthstone\\", ')
    and has(namesObj, '\\"C:1984\\"'), namesObj)
  local realSecret = issecretvalue
  for _, which in ipairs({ "start", "duration" }) do
    secretTimes = which
    local asked = 0
    issecretvalue = function(v) if v == SECRET then asked = asked + 1 end return realSecret(v) end
    local secretCds = object(play(80), 27)
    issecretvalue = realSecret
    local want = which == "start" and 'true,false,null,5.0]' or 'true,false,5.0,null]'
    check("objects 24-27: a secret cooldown " .. which .. " is null, asked about first (" .. asked .. ")",
      secretCds and has(secretCds, '[1,\\"S:75:') and has(secretCds, want) and asked > 0, secretCds)
  end
  secretTimes = false
  -- names only the fast data names: a channelled spell and a target seen once
  UnitChannelInfo = function(u) if u == "player" then return "Rapid Fire", nil, nil, 0, 1000, false, nil, 3045 end end
  ns.Strip2.noteFast(now)
  UnitChannelInfo = function() end
  check("objects 24-27: the names hold a channelled spell that only the fast data named",
    has(ns.Strip2.namesText(), '"S:3045": ["Rapid Fire", '), ns.Strip2.namesText())
  -- the refresh sends a version whole although the names change at every build
  local S2 = ns.Strip2
  S2.resetSending()
  local objs = { [25] = { obj = { 1 }, version = 1, sent = 1 } }
  local lists = {}
  local function chunks(o) lists[o.version] = lists[o.version] or { { 1 }, { 2 }, { 3 } } return lists[o.version] end
  local seen, sending, tt = {}, nil, 0
  for _ = 1, 400 do
    tt = tt + 0.1
    objs[25].version = objs[25].version + 1          -- a new version at every decision
    sending = S2.nextSend(sending, 25, objs, function() end, chunks, tt, 0.1)
    if sending and not sending.new then seen[sending.version] = (seen[sending.version] or 0) + 1 end
    if sending then sending.till = tt end
  end
  local whole = false
  for _, count in pairs(seen) do if count >= 3 then whole = true end end
  check("objects 24-27: the refresh sends a version of names whole, though a newer comes each time", whole)
  -- the refresh round of format 3: 25 objects of 3 chunks (75, as the owner's play of 22 Nov 2026
  -- held) go round on one decision in 6 (S2.REFRESH_EVERY3, spec 232, section 4 A), not in 8
  do
    S2.three = true
    S2.resetSending()
    local held = {}
    for id = 1, 25 do held[id] = { obj = { 1 }, version = 1, sent = 1 } end
    local list = { { 1 }, { 2 }, { 3 } }
    local firstAt, backAt, s, d = nil, nil, nil, 0
    while not backAt and d < 1000 do
      d = d + 1
      s = S2.nextSend(s, 25, held, function() end, function() return list end, d * 0.125, 0.125)
      if s and not s.new and s.id == 1 and s.index == 1 then
        if firstAt then backAt = d else firstAt = d end
      end
      if s then s.till = d * 0.125 end   -- exact in binary: no decision skipped by rounding
    end
    local round = backAt and firstAt and backAt - firstAt
    check(("objects 24-27: format 3's refresh goes round 75 chunks in 450 decisions (%s)"):format(tostring(round)),
      round == 450)
    S2.resetSending()
  end
  -- the names (25) go by the refresh only, and their text changes at each build in play: a build
  -- during the round's send of them made the directory name a newer version, so the reader dropped
  -- the rest of the send and waited a round more (up to 184 s in the owner's hour of 22 Nov 2026,
  -- spec 232, section 11). Each of their chunks goes with the version the directory names.
  do
    S2.resetSending()
    -- the 27 objects of play, one chunk each, but the names with 10 (60 decisions a send: longer
    -- than the scan's 54, so a scan turn comes in each send)
    local names, one, ten = {}, { { 1 } }, {}
    for id = 1, 27 do names[id] = { obj = { 1 }, version = 1, sent = 1 } end
    for k = 1, 10 do ten[k] = { k } end
    local builds = 0
    local function build(id) if id == 25 then names[25].version, builds = names[25].version + 1, builds + 1 end end
    local function chunks(o) return o == names[25] and ten or one end
    local s, sent, behind = nil, 0, 0
    for d = 1, 1800 do
      s = S2.nextSend(s, 27, names, build, chunks, d * 0.125, 0.125)
      if s and not s.new and s.id == 25 then
        sent = sent + 1
        if s.version ~= names[25].version then behind = behind + 1 end
      end
      if s then s.till = d * 0.125 end
    end
    check(("objects 24-27: no names chunk goes behind the version the directory names (%d of %d), and the names "
      .. "are still built between sends (%d builds)"):format(behind, sent, builds),
      sent >= 50 and behind == 0 and builds >= 5)
    S2.resetSending()
  end
  -- the guide's waypoint (7) is asked for at the 2nd, 7th, 12th and 17th of 20 decisions besides its
  -- turn in the scan (the 14th); the quests (5) on their turn only (the 10th): the local program saw
  -- object 7 a step behind object 11 (23 Nov 2026)
  do
    S2.resetSending()
    local at = { [5] = {}, [7] = {} }
    local d = 0
    local function spy(id) if at[id] then at[id][#at[id] + 1] = d end end
    local s
    for k = 1, 20 do
      d = k
      s = S2.nextSend(s, 27, {}, spy, function() return nil end, k * 0.125, 0.125)
    end
    local five, seven = table.concat(at[5], " "), table.concat(at[7], " ")
    check(("guide objects: 7 is asked for at decisions 2 7 12 17 and on its turn, 5 on its turn only (5: %s; 7: %s)"):format(five, seven),
      five == "10" and seven == "2 7 12 14 17")
    S2.resetSending()
  end
  aurasSecret = true
  local secret = object(play(80), 26)
  check("objects 24-27: auras the client refuses are format 253, and the reader says secret",
    secret and has(secret, '"format": 253') and has(secret, '"secret": true'), secret)
  aurasSecret = false
  object(play(40), 26)   -- readable again: a version that is not 253
  aurasSecret = "field"
  local fieldSecret = object(play(80), 26)
  check("objects 24-27: an aura with a secret field is format 253 too, not an empty list",
    fieldSecret and has(fieldSecret, '"format": 253'), fieldSecret)
  aurasSecret = false
  UnitGUID, UnitExists, UnitName, UnitLevel, UnitClass = realGuid, realExists, realName, realLevel, realClass
  UnitClassification, UnitIsConnected = realClassif, realConnected
  C_UnitAuras, GetActionInfo, UnitThreatSituation, GetRaidTargetIndex, GetMacroSpell, C_Item = nil, nil, nil, nil, nil, nil
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
  has(watch(30), bin(12, 'null')) and HelloLinkDB.baseline == nil)
check("0.8.1: the full name survives the reload in the saved table",
  has(watch(30), '\\"fullName\\": \\"FakeHunter Family\\", \\"fullNameSource\\": \\"loot\\", \\"guid\\": \\"Player-1-0000ABCD\\", \\"realmSaved\\": null, \\"talents\\": null}"]'))

-- A saved data of an earlier HelloLink (1.0.0 released format 2, and format 1 was before it) loads
-- as format 3, the only format (the owner, 22 Nov 2026: formats 1 and 2 are legacy): the row it
-- draws is read as format 3.
do
  local kept, keptRow, keptEvents = HelloLinkDB, row, events
  local function drawn(saved)
    HelloLinkDB = saved
    local _, loadedEvents, loadedRow = load()
    row, events = loadedRow, loadedEvents
    tick(0.1)
    return read({ dump() })
  end
  local two, one = drawn({ format = 2, formatRelease = 2 }), drawn({ format = 1 })
  check("a saved format 2 of 1.0.0 loads as format 3", has(two, '"format": 3') and has(two, '"why": null'), two:sub(1, 300))
  check("a saved format 1 loads as format 3", has(one, '"format": 3') and has(one, '"why": null'), one:sub(1, 300))
  -- formats 1 and 2 are legacy since HelloLink 2.0.0: a format chosen after 1.1.0 loads as format 3 too
  local chose2, chose1 = drawn({ format = 2, formatRelease = 3 }), drawn({ format = 1, formatRelease = 3 })
  check("2.0.0: a format 2 chosen after 1.1.0 loads as format 3", has(chose2, '"format": 3') and has(chose2, '"why": null'), chose2:sub(1, 300))
  check("2.0.0: a format 1 chosen after 1.1.0 loads as format 3", has(chose1, '"format": 3') and has(chose1, '"why": null'), chose1:sub(1, 300))
  local reply = slash("strip format 2")
  check("2.0.0: /hlink strip format 2 gives the usage line and changes nothing",
    has(reply, "use /hlink strip") and not has(reply, "format <") and HelloLinkDB.format == 3, reply)
  HelloLinkDB, row, events = kept, keptRow, keptEvents
end

-- The ramp and the bits: off by default, saved across a load; a 9-bit frame's squares against
-- bytes written by hand (docs/STRIP.md, section 2, "Bytes from squares"; docs/specs/232.md, part C).
do
  local kept, keptRow, keptEvents = HelloLinkDB, row, events
  HelloLinkDB = {}
  local fresh = load()
  local st = fresh.StripState()
  check("a first load: the ramp off, 6 bits, depth 4", st.ramp == false and st.bits == 6 and st.depthNow == 4
    and HelloLinkDB.ramp == false and HelloLinkDB.bits == 6)
  fresh.StripSet("ramp", "on")
  fresh.StripSet("bits", "9")
  HelloLinkDB.session = 23099   -- the next load's session is 23100, 5A 3C
  local ns9, events9, row9 = load()
  row, events = row9, events9
  st = ns9.StripState()
  check("the ramp and 9 bits are saved: the next load starts at 9 bits with the ramp", st.ramp == true and st.bits == 9
    and st.depthNow == 8 and HelloLinkDB.session == 23100)
  tick(0.1)
  -- The frame starts 03 5A 3C 0A (version, session, dwell): the bits 000000110 101101000 111100000
  -- are the codes 6, 360 and 480, the levels (0, 0, 6), (5, 5, 0) and (7, 4, 0). Level k is drawn
  -- at (203 + 71 k) / 700 of full (lo 0.29). The frame starts at square 51 + 2 + 3 × 5 = 68.
  local side = ns9.Strip2.side(HelloLinkDB) * unit
  local function at(sq)
    for _, t in ipairs(textures) do
      if t.parent == row and t.shown and math.abs(t.x - sq * side) < 1e-6 then return t end
    end
  end
  local want = { { 203 / 700, 203 / 700, 629 / 700 }, { 558 / 700, 558 / 700, 203 / 700 }, { 1, 487 / 700, 203 / 700 } }
  local ok, got = true, {}
  for i, w in ipairs(want) do
    local t = at(67 + i)
    got[#got + 1] = t and ("%.6f %.6f %.6f"):format(t.r, t.g, t.b) or "none"
    if not (t and math.abs(t.r - w[1]) < 1e-9 and math.abs(t.g - w[2]) < 1e-9 and math.abs(t.b - w[3]) < 1e-9) then ok = false end
  end
  check("9 bits: the frame's first squares are the codes 6, 360, 480 of the bytes 03 5A 3C 0A, written by hand", ok,
    table.concat(got, " / "))
  local line = read({ dump() })
  check("9 bits: the reader reads that frame (session 23100, depth 8)", has(line, '"session": 23100') and has(line, '"depth": 8')
    and has(line, '"why": null') and (line:match('"frame": "(%x+)"') or ""):sub(1, 8) == "035a3c0a", line:sub(1, 300))
  HelloLinkDB, row, events = kept, keptRow, keptEvents
end

-- The lanes: 1 on a first load, saved across a load (docs/specs/232.md, part C, "Lanes").
do
  local kept, keptRow, keptEvents = HelloLinkDB, row, events
  HelloLinkDB = {}
  local fresh = load()
  check("a first load: 1 lane", fresh.StripState().lanes == 1 and HelloLinkDB.lanes == 1)
  fresh.StripSet("lanes", "3")
  local again, eventsAgain, rowAgain = load()
  row, events = rowAgain, eventsAgain
  tick(0.1)
  local layout
  for _, t in ipairs(textures) do
    if t.parent == row and t.shown and math.abs(t.x - 21 * unit) < 1e-6 and t.y == 0 then layout = { t.r, t.g, t.b } end
  end
  check("3 lanes are saved: the next load draws the layout square 2 (green)", again.StripState().lanes == 3
    and layout ~= nil and layout[1] == 0 and layout[2] == 1 and layout[3] == 0)
  HelloLinkDB, row, events = kept, keptRow, keptEvents
end

-- ---------------- the talents in object 10 (2.2.0) ----------------
-- At the end of the run: their reads take watches that would move the timing of the checks above.
do
  local function q(json) return (json:gsub('"', '\\"')) end   -- as the reader prints an object's text
  -- 2.2.0: the talents, read as HelloForever reads them on this client (C_SpecializationInfo's
  -- combat config, C_Traits' groups); a tab with nothing spent is left out by the client
  C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end,
    GetCombatConfigIDForSpecGroup = function(g) return g == 1 and 77 or nil end }
  C_Traits = {
    GetConfigInfo = function(c) return c == 77 and { treeIDs = { 9 } } or nil end,
    GetGroupDisplayInfoByTreeID = function(t)
      return t == 9 and { { groupID = 11372, displayName = "Beast Mastery" }, { groupID = 11373, displayName = "Marksmanship" },
        { groupID = 11374, displayName = "Survival" } } or nil
    end,
    GetGroupCurrencyInfo = function(c, ids)
      return c == 77 and #ids == 3 and { { traitNodeGroupID = 11372, currencyInfos = { { spent = 21 } } },
        { traitNodeGroupID = 11374, currencyInfos = { { spent = 9 } } } } or nil
    end,
    GetTreeCurrencyInfo = function(c, t) return c == 77 and t == 9 and { { spent = 30, quantity = 1 } } or nil end,
  }
  -- 2.4.0: the bought nodes, as HelloForever's snapshot reads them (C_Traits' tree nodes, an
  -- entry's definition for the spell); ranks that add up to the points spent (seen in its saved data)
  local NODES = {   -- node id: rank (active, or bought only), most, entry (active, or the first), spell, override
    [101] = { active = 5, most = 5, entry = 1001, spell = 19552 }, [102] = { active = 5, most = 5, entry = 1002, spell = 19621 },
    [103] = { active = 0, most = 5, entry = 1003, spell = 19555 },   -- not bought
    [104] = { bought = 2, most = 2, first = 1004, spell = 19590 }, [105] = { active = 5, most = 5, entry = 1005, spell = 19598 },
    [106] = { active = 4, most = 5, entry = 1006, spell = 19616 },
    [107] = { active = 5, most = 5, entry = 1007, spell = 19283, override = 19300 },
    [108] = { active = 3, most = 3, entry = 1008, spell = 19184 }, [109] = { active = 1, most = 1, entry = 1009, spell = 1293241 } }
  local nodeReads = 0
  C_Traits.GetTreeNodes = function(t) return t == 9 and { 101, 102, 103, 104, 105, 106, 107, 108, 109 } or nil end
  C_Traits.GetNodeInfo = function(c, id)
    nodeReads = nodeReads + 1
    local n = c == 77 and NODES[id]
    if not n then return nil end
    return { ID = id, activeRank = n.active, ranksPurchased = n.bought or n.active, maxRanks = n.most,
      activeEntry = n.entry and { entryID = n.entry } or nil, entryIDs = { n.first or n.entry } }
  end
  C_Traits.GetEntryInfo = function(c, e) return c == 77 and { definitionID = e + 4000 } or nil end
  C_Traits.GetDefinitionInfo = function(d)
    for _, n in pairs(NODES) do
      if (n.entry or n.first) + 4000 == d then return { spellID = n.spell, overriddenSpellID = n.override } end
    end
  end
  local NODES_JSON = '"nodes": [[19184, 3, 3], [19300, 5, 5], [19552, 5, 5], [19590, 2, 2], [19598, 5, 5], [19616, 4, 5], '
    .. '[19621, 5, 5], [1293241, 1, 1]]'
  events.OnEvent(events, "TRAIT_CONFIG_UPDATED")
  local seen = watch(40)   -- the whole watch: object 10 holds a list, with its "]"
  check("2.2.0: object 10 holds the talents: spent, unspent, each tab's points (0 for one the client leaves out); "
    .. "2.4.0: the bought nodes as [spell, rank, most], by spell (an override's spell; a rank bought but not active)",
    has(seen, q('"talents": {"spent": 30, "unspent": 1, "tabs": [{"name": "Beast Mastery", "points": 21}, '
      .. '{"name": "Marksmanship", "points": 0}, {"name": "Survival", "points": 9}], ' .. NODES_JSON .. '}}')), seen:sub(-700))
  -- the safety net builds object 10 every 30 s: the nodes are read again only after a talent event
  -- or a change of the tabs' points
  local realTotal, treeReads = C_Traits.GetTreeCurrencyInfo, 0
  C_Traits.GetTreeCurrencyInfo = function(...) treeReads = treeReads + 1 return realTotal(...) end
  nodeReads = 0
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", false, false)   -- marks object 10, as the safety net does each 30 s
  local quiet = watch(40)
  check(("2.4.0: the nodes are not read again with no talent event and the same points (object 10 built %d times, "
    .. "%d node reads)"):format(treeReads, nodeReads), treeReads >= 1 and nodeReads == 0 and has(quiet, q(NODES_JSON)))
  local realGroups = C_Traits.GetGroupCurrencyInfo
  C_Traits.GetGroupCurrencyInfo = function() return { { traitNodeGroupID = 11372, currencyInfos = { { spent = 20 } } },
    { traitNodeGroupID = 11373, currencyInfos = { { spent = 1 } } }, { traitNodeGroupID = 11374, currencyInfos = { { spent = 9 } } } } end
  treeReads, nodeReads = 0, 0
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", false, false)   -- a build, as the safety net's (review of 2.4.0)
  watch(40)
  check(("2.4.0: a change of the tabs' points reads the nodes again, once (object 10 built %d times, %d node reads)")
    :format(treeReads, nodeReads), treeReads >= 1 and nodeReads == 9)
  -- a dual-spec switch reads them again too (ACTIVE_TALENT_GROUP_CHANGED; review of 2.4.0)
  treeReads, nodeReads = 0, 0
  events.OnEvent(events, "ACTIVE_TALENT_GROUP_CHANGED")
  watch(40)
  check(("2.4.0: a spec switch reads the nodes again (%d node reads)"):format(nodeReads), treeReads >= 1 and nodeReads == 9)
  C_Traits.GetGroupCurrencyInfo, C_Traits.GetTreeCurrencyInfo = realGroups, realTotal
  -- ranks that do not add up to the points spent: the nodes null, the tabs kept
  NODES[106].active = 3
  events.OnEvent(events, "TRAIT_CONFIG_UPDATED")
  check("2.4.0: nodes whose ranks do not add up to the points spent are null; the tabs stay",
    has(watch(40), q('{"name": "Survival", "points": 9}], "nodes": null}')), "rank sum")
  NODES[106].active = 4
  -- a secret answer for a node: the nodes null, and the guard is asked (rule 7)
  local realNode, askedNode = C_Traits.GetNodeInfo, 0
  local realSecretNode = issecretvalue
  issecretvalue = function(v) if v == SECRET then askedNode = askedNode + 1 end return realSecretNode(v) end
  C_Traits.GetNodeInfo = function(c, id) if id == 105 then return SECRET end return realNode(c, id) end
  events.OnEvent(events, "PLAYER_TALENT_UPDATE")
  check("2.4.0: a secret node gives nodes null, and the secret was asked about",
    has(watch(40), q('"points": 9}], "nodes": null}')) and askedNode >= 1, "asked " .. askedNode)
  issecretvalue, C_Traits.GetNodeInfo = realSecretNode, realNode
  -- a failed read is not kept: the next build, with no talent event, reads them again (review of 2.4.0)
  events.OnEvent(events, "PLAYER_ENTERING_WORLD", false, false)
  check("2.4.0: after a failed read the nodes come back at the next build, with no talent event", has(watch(40), q(NODES_JSON)))
  -- a secret active entry, or a secret override, fails the nodes: no fall-back to another spell (review of 2.4.0)
  askedNode = 0
  issecretvalue = function(v) if v == SECRET then askedNode = askedNode + 1 end return realSecretNode(v) end
  C_Traits.GetNodeInfo = function(c, id)
    local info = realNode(c, id)
    if id == 105 then info.activeEntry = { entryID = SECRET } end
    return info
  end
  events.OnEvent(events, "PLAYER_TALENT_UPDATE")
  check("2.4.0: a secret active entry gives nodes null, not the first entry's spell",
    has(watch(40), q('"points": 9}], "nodes": null}')) and askedNode >= 1, "asked " .. askedNode)
  C_Traits.GetNodeInfo = realNode
  local realDef = C_Traits.GetDefinitionInfo
  C_Traits.GetDefinitionInfo = function(d)
    if d == 1005 + 4000 then return { spellID = 19598, overriddenSpellID = SECRET } end
    return realDef(d)
  end
  events.OnEvent(events, "PLAYER_TALENT_UPDATE")
  check("2.4.0: a secret override gives nodes null, not the spell under it",
    has(watch(40), q('"points": 9}], "nodes": null}')), "override")
  issecretvalue, C_Traits.GetDefinitionInfo = realSecretNode, realDef
  -- a secret answer goes to issecretvalue and nowhere else (rule 7: the guard is asked)
  local realTree, asked = C_Traits.GetTreeCurrencyInfo, 0
  local realSecret = issecretvalue
  issecretvalue = function(v) if v == SECRET then asked = asked + 1 end return realSecret(v) end
  C_Traits.GetTreeCurrencyInfo = function() return SECRET end
  events.OnEvent(events, "CHARACTER_POINTS_CHANGED")
  check("2.2.0: a secret talent read gives talents null, and the secret was asked about",
    has(watch(40), q('"talents": null}')) and asked >= 1, "asked " .. asked)
  issecretvalue, C_Traits.GetTreeCurrencyInfo = realSecret, realTree
  -- points in a group the tabs do not show: the tabs would not add up (review of #323)
  local realSpent = C_Traits.GetGroupCurrencyInfo
  C_Traits.GetGroupCurrencyInfo = function() return { { traitNodeGroupID = 11372, currencyInfos = { { spent = 21 } } },
    { traitNodeGroupID = 99999, currencyInfos = { { spent = 9 } } } } end
  events.OnEvent(events, "CHARACTER_POINTS_CHANGED")
  check("2.2.0: points in a group no tab shows give talents null", has(watch(40), q('"talents": null}')), "unknown group")
  -- the client gives the visible tabs only and they do not add up to the points spent (round 2)
  C_Traits.GetGroupCurrencyInfo = function() return { { traitNodeGroupID = 11372, currencyInfos = { { spent = 21 } } } } end
  events.OnEvent(events, "CHARACTER_POINTS_CHANGED")
  check("2.2.1: tabs that do not add up to the points spent give talents null", has(watch(40), q('"talents": null}')), "sum")
  C_Traits.GetGroupCurrencyInfo = realSpent
  -- no active spec group: the active config, not group 1 (review of #323)
  C_SpecializationInfo.GetActiveSpecGroup = function() return SECRET end
  C_ClassTalents = { GetActiveConfigID = function() return 77 end }
  events.OnEvent(events, "CHARACTER_POINTS_CHANGED")
  check("2.2.0: with no spec group the active config is read", has(watch(40), q('"talents": {"spent": 30')), "active config")
  C_ClassTalents = nil
  events.OnEvent(events, "CHARACTER_POINTS_CHANGED")
  check("2.2.0: with no spec group and no active config, talents null (not group 1)", has(watch(40), q('"talents": null}')), "group 1")
  C_SpecializationInfo, C_Traits = nil, nil
end

-- ---------------- the current step's lines in object 11 (2.3.0) ----------------
-- RestedXP's `.line` and `.loop` elements (functions.lua: `segments`, x and y pairs in per cent of
-- `zone`; map.lua: a negative point starts a dashed part, `connectPoints` closes the path), at the
-- end of the run as the talents' checks
do
  local loop = {}
  for i = 1, 60 do loop[#loop + 1] = i; loop[#loop + 1] = 50 end
  RXP = RXP or {}   -- an earlier check took the guide addon away
  RXP.currentGuide = { name = "L", key = "L", steps = {
    { index = 1, text = "patrol", elements = {
      { tag = "loop", zone = 1417, segments = { 10, 20, -30, -40, 50, 60 } },   -- not closed; a dashed part
      { tag = "loop", zone = 1417, segments = loop, connectPoints = true },
      { tag = "line", zone = 1417, segments = { 1, 1, 2, 2 } } } },   -- a third: past STEP_LINES
    { index = 2, text = "after", elements = { { tag = "line", zone = 1417, segments = { 5, 5, 6, 6 } } } } } }
  RXPCData = { guideProgress = { L = { step = 1 } } }
  C_EncodingUtil = { CompressString = rawDeflate }   -- the game has one: a version is then made once from its text
  local seen = watch(40)
  local want = '"lines": [{"map": 1417, "loop": false, "pts": [6554, 13107, 19661, 26214, 32768, 39321]}, '
    .. '{"map": 1417, "loop": true, "pts": [655, 32768, '
  local at = seen:find(want:gsub('"', '\\"'), 1, true)
  local loopPts = at and seen:sub(at):match('\\"loop\\": true, \\"pts\\": %[([%d, ]+)%]') or ""
  local xs, rising = {}, true
  for x in loopPts:gmatch("(%d+), %d+") do xs[#xs + 1] = tonumber(x) end
  for i = 2, #xs do rising = rising and xs[i] > xs[i - 1] end
  check("2.3.0: the current step's lines in units of 65535 (a dashed point as its absolute value; closed only with "
    .. "connectPoints); a loop of 60 points is 24, rising, its first and last kept; at most 2 lines",
    at ~= nil and #xs == 24 and rising and loopPts:match("39321, 32768$") ~= nil
      and not seen:find('\\"pts\\": [655, 655', 1, true), loopPts ~= "" and loopPts or seen:sub(-400))
  check("2.3.0: the object reads, and a step after the current one has no lines",
    seen:find('\\"text\\": \\"after\\"', 1, true) ~= nil and not seen:find('\\"text\\": \\"after\\"[^}]*\\"lines\\"'), seen:sub(-300))
  -- the game's window made narrower: the steps choose again against the new room, with no guide
  -- event (chunks of 20 bytes, 240 for 12: the full steps deflate to 325 bytes and do not fit, the
  -- lighter ones to 177 and do; review of #325, round 2), and take their lines again when the room comes back
  GetPhysicalScreenSize = function() return 420, 1440 end
  events.OnEvent(events, "DISPLAY_SIZE_CHANGED")
  local slim = watch(60)
  local lastL = slim:match('.*(\\"guide\\": \\"L\\".*)') or ""   -- the newest version read
  check("2.3.0: after the window narrows, the steps go without their lines, not as format 254",
    not has(slim, '[11, 254, null]') and has(lastL, '\\"lines\\": []') and not has(lastL, '\\"pts\\"')
      and has(lastL, '\\"text\\": \\"after\\"'), slim:sub(-400))
  GetPhysicalScreenSize = function() return 2560, 1440 end
  events.OnEvent(events, "DISPLAY_SIZE_CHANGED")
  check("2.3.0: with the room back, the current step's lines come back", has(watch(40), (want:gsub('"', '\\"'))))
  -- 401 points: 24 are kept, the 400th the last (RestedXP's loops stop at 400; review of #325, round 2)
  local long = {}
  for i = 1, 401 do long[#long + 1] = i % 100; long[#long + 1] = i == 400 and 77 or 50 end
  RXP.currentGuide.steps[1].elements = { { tag = "line", zone = 1417, segments = long } }
  local far = watch(40)
  local farPts = far:match('.*\\"pts\\": %[([%d, ]+)%]') or ""
  local count = select(2, farPts:gsub("%d+", ""))
  check("2.3.0: a line of 401 points is 24, its last the 400th", count == 48 and farPts:match("%d+, 50462$") ~= nil, farPts)
  C_EncodingUtil = nil
  -- too large with its lines: the steps go without them, not as format 254 (review of #325)
  local seed, function_text = 7, nil
  function_text = function(n)
    local out = {}
    for i = 1, n do seed = (seed * 1103515245 + 12345) % 2147483648; out[i] = string.char(97 + seed % 26) end
    return table.concat(out)
  end
  local wide = {}
  for i = 1, 48 do wide[#wide + 1] = (i * 37) % 100; wide[#wide + 1] = (i * 53) % 100 end
  RXP.currentGuide = { name = "W", key = "W", steps = {
    { index = 1, text = function_text(390), elements = {
      { tag = "line", zone = 1417, segments = wide }, { tag = "line", zone = 1418, segments = wide } } },
    { index = 2, text = function_text(390) }, { index = 3, text = "last" } } }
  RXPCData = { guideProgress = { W = { step = 1 } } }
  local big = watch(40)
  check("2.3.0: a steps object too large with its lines goes without them, not as format 254",
    big:find('\\"text\\": \\"last\\"', 1, true) ~= nil and big:find('\\"lines\\": []', 1, true) ~= nil
      and not big:find('\\"guide\\": \\"W\\"[^%]]*\\"pts\\"'), big:sub(-500))
end

print_real(("== %d checks, %d failed"):format(n, fails))
os.exit(fails == 0 and 0 or 1)
