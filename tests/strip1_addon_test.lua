-- The live-state strip, format 1: the addon draws a row in a stub client, and the Python
-- reader (tools/strip1.py, through `hellolink_strip.py rows`) reads it back.
-- Usage: lua tests/strip1_addon_test.lua <scratch dir>
--
-- The stub is the client as plan/05 recorded it on 12 Nov 2026 where that is known: health
-- and power are secret, their maxima are not; squares asked for in physical pixels are
-- exact; the client colours a square from a step colour curve at a per cent of 0 to 1.
-- ASSUMED, not seen in the game: the event names, C_Container's item fields, the shapes of
-- UnitCastingInfo and GetWeaponEnchantInfo, and everything the test says about timing.
local DIR = assert(arg[1], "usage: strip1_addon_test.lua <scratch dir>")
local TOOL = "python3 tools/hellolink_strip.py"
local out = {}
print_real = print
print = function(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end out[#out + 1] = table.concat(t, " ") end
local fails, n = 0, 0
local function check(name, cond) n = n + 1; if not cond then fails = fails + 1 end print_real((cond and "PASS " or "FAIL ") .. name) end
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
local T = { name = "Wetlands Crocolisk", level = 23, health = 99, healthMax = 803, class = "normal", kind = "Beast" }
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
UnitAffectingCombat = function() return P.combat end
UnitIsDeadOrGhost = function() return false end
UnitIsDead = function() return false end
IsMounted = function() return false end
IsResting = function() return false end
UnitIsAFK = function() return false end
UnitName = function(u) return u == "target" and T.name or "Eugen" end
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
C_Container = { GetContainerNumFreeSlots = function(b) return b == 0 and 12 or 0 end,
  GetContainerNumSlots = function(b) return b == 0 and 16 or 0 end,
  GetContainerItemInfo = function(b, s) return BAGS[b] and BAGS[b][s] end }
GetInventoryItemID = function() return 2504 end
GetWeaponEnchantInfo = function() return true, 598400, 0, 0 end
GetRealZoneText = function() return "Wetlands" end
GetSubZoneText = function() return "Black Channel Marsh" end
-- the client colours a square from a step curve at the unit's per cent (0 to 1)
Enum = { LuaCurveType = { Step = 1 } }
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
-- HelloForever's snapshot, read for quests and skills
HelloForeverDB = { characters = { ["Eugen-TestRealm"] = { snapshot = {
  quests = { log = {
    { id = 471, title = "Apprentice's Duties", state = "in_progress", objectives = { { text = "Giant Crocolisk Skin", have = 3, need = 6, finished = false } } },
    { id = 290, title = "Lifting the Curse", state = "accepted", objectives = { { text = "Speak with \"Glorin\"", finished = false } } } } },
  skills = { { name = "Leatherworking", rank = 75, max = 150, id = 165 }, { name = "Skinning", rank = 120, max = 150, id = 393 } } } } } }
-- the slots that carry text into the game
local slotFile
C_AddOns = { LoadAddOn = function() if not slotFile then return false, "MISSING" end HelloLink_Inbox = slotFile; return true end }

-- ---------------- the addon ----------------
local function load()
  local ns = {}
  local first = #frames
  assert(loadfile("HelloLink/HelloLink.lua"))("HelloLink", ns)
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
  sh(("%s render '%s.txt' '%s.bmp' --scale %.12f --dx 0 --dy 0 --width 2560 --height 12"):format(TOOL, path, path, 1 / unit))
  return path .. ".bmp"
end
local function read(paths, step) return sh(("%s rows --step %g %s"):format(TOOL, step or 0.1, table.concat(paths, " "))) end
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
check("the target: level, hostile and attacking the pet, the hash of its name", has(one, '"flags": 129, "level": 23'))
check("threat: 57.6 is 58, the pet's 100", has(one, '"threat": {"pet": 100, "player": 58}'))
check("position: map, the middle and a quarter, facing a quarter turn", has(one, '"position": {"facing": 64, "map": 1437, "x": 32768, "y": 16384}'))
check("the main hand and its enchant's seconds, rounded up", has(one, '"hand": {"enchant": 599, "item": 2504}'))
check("no cast: the cast group is unknown", has(one, '"cast": null'))

-- ---------------- the fast state changes ----------------
local before = tonumber(one:match('"seq": (%d+)'))
tick(0.02)
local same = read({ dump() })
check("nothing changed: the same seq stays up", tonumber(same:match('"seq": (%d+)')) == before or has(same, '"chunk": ['))
P.casting, P.money = true, 7900
events.OnEvent(events, "LOOT_OPENED")
events.OnEvent(events, "CHAT_MSG_LOOT", "You receive loot: |cff9d9d9d|Hitem:2318::::::::29:::::|h[Light Leather]|h|rx2.", "Eugen-TestRealm")
events.OnEvent(events, "CHAT_MSG_LOOT", "Bob receives loot: |Hitem:999:|h[Thing]|h|r.", "Bob-TestRealm")
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
local function watch(steps)
  local paths = {}
  for _ = 1, steps do tick(0.1); paths[#paths + 1] = dump() end
  return read(paths)
end
local round = watch(14)
check("the target object", has(round, '[2, 0, "{\\"name\\": \\"Wetlands Crocolisk\\", \\"type\\": \\"Beast\\", \\"class\\": \\"normal\\", \\"level\\": 23}"]'))
check("the place object", has(round, '[3, 0, "{\\"map\\": 1437, \\"zone\\": \\"Wetlands\\", \\"sub\\": \\"Black Channel Marsh\\"}"]'))
check("the bags object: stacks of one item summed, ordered by id", has(round, '[4, 0, "{\\"free\\": 12, \\"items\\": [[2318, 16], [4234, 3]]}"]'))
check("the quests object, from HelloForever's snapshot, ordered by id, a quote in a text escaped",
  has(round, '\\"id\\": 290, \\"title\\": \\"Lifting the Curse\\", \\"state\\": \\"accepted\\"')
  and has(round, 'Speak with \\\\\\"Glorin\\\\\\"') and has(round, '\\"have\\": null, \\"need\\": null, \\"done\\": false')
  and round:find('"id\\": 290', 1, true) < round:find('"id\\": 471', 1, true))
check("the skills object", has(round, '[6, 0, "[{\\"id\\": 165, \\"name\\": \\"Leatherworking\\", \\"rank\\": 75, \\"max\\": 150}, {\\"id\\": 393'))
check("the objects come in the order of their ids", round:find('"object": [2,', 1, true) < round:find('"object": [3,', 1, true)
  and round:find('"object": [3,', 1, true) < round:find('"object": [4,', 1, true))

P.target = false
events.OnEvent(events, "PLAYER_TARGET_CHANGED")
local gone = watch(16)
check("no target: the object says null, a new version", has(gone, '[2, 0, "null"]'))
check("and the target and threat groups are unknown, the target's level squares black", has(gone, '"target": null') and has(gone, '"threat": null')
  and has(gone, '"levels": [75, 83, null, 93]'))
P.target = true
events.OnEvent(events, "PLAYER_TARGET_CHANGED")

slash("send 點解我呢區升得咁慢？")
local asked = watch(30)
check("a question is object 1, and comes before the others at its turn", has(asked, '[1, 0, "點解我呢區升得咁慢？"]'))
local later = watch(30)
check("after two rounds the question has left the queue", not has(later, '"chunk": [1,'))

HelloForeverDB.characters["Eugen-TestRealm"].snapshot.quests = nil
events.OnEvent(events, "QUEST_LOG_UPDATE")
local unread = watch(20)
check("an object the addon cannot read is format 255, and a reader drops its copy", has(unread, '[5, 255, null]'))

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
tick(31)
check("a request that names another session does nothing", has(read({ dump() }), '"depth": 4'))
slotFile = { seq = 2, text = "", strip = { session = session, depth = 2 } }
out = {}
tick(30)
check("a request that names this session makes the row depth 2, and chat says so",
  has(read({ dump() }), '"depth": 2') and has(table.concat(out, "\n"), "falls back to 3 bits"))
slash("strip depth auto"); tick(0.1)

-- ---------------- size, place, off ----------------
slash("strip size 3"); slash("strip at 40 6"); tick(0.1)
local moved = read({ dump() })
check("3 pixels a square at (40, 6): still read", has(moved, '"row": true') and has(moved, '"why": null')
  and math.abs(tonumber(moved:match('"square": ([%d.]+)')) - 3) < 0.01)
slash("strip size 2"); slash("strip at 0 0")
check("a wrong command lists the commands", has(slash("strip depth 9"), "use /hlink strip"))
slash("strip off"); tick(0.1)
check("/hlink strip off: nothing is on the row", has(read({ dump() }), '"row": false'))
slash("strip on"); tick(0.1)
check("/hlink strip on brings it back", has(read({ dump() }), '"row": true'))

-- ---------------- a new UI session ----------------
local _, _, row2 = load()
row = row2
tick(0.1)
check("the next UI load has the next session number, and starts at depth 4 again",
  HelloLinkDB.session == session + 1 and has(read({ dump() }), ('"session": %d'):format(session + 1)))

print_real(("== %d checks, %d failed"):format(n, fails))
os.exit(fails == 0 and 0 or 1)
