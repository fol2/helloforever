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
GetXPExhaustion = function() return P.rested end
UnitAffectingCombat = function() return P.combat end
UnitIsDeadOrGhost = function() return false end
UnitIsDead = function() return false end
IsMounted = function() return false end
IsResting = function() return false end
UnitIsAFK = function() return false end
UnitGUID = function(u) return u == "player" and "Player-6841-01186C4A" or nil end
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
C_Container = { GetContainerNumFreeSlots = function(b) return b == 0 and (P.free or 12) or b == 5 and BAGS[5] and 6 or 0 end,
  GetContainerNumSlots = function(b) return b == 0 and 48 or b == 5 and BAGS[5] and 8 or 0 end,
  GetContainerItemInfo = function(b, s) return BAGS[b] and BAGS[b][s] end }
GetInventoryItemID = function(_, slot) if slot == 0 then return P.ammo end return 2504 end   -- slot 0: ammunition
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
-- have ("Eugen Folx" against "Eugen"), there is no realm, and argument 12 is the player's GUID.
events.OnEvent(events, "CHAT_MSG_LOOT", "You receive loot: |cnIQ1:|Hitem:2318::::::::30:1485:::::::::|h[Light Leather]|h|rx2.",
  "Eugen Folx", "", "", "Eugen Folx", "", 0, 0, "", 0, 1, "Player-6841-01186C4A")
events.OnEvent(events, "CHAT_MSG_LOOT", "Bob Other receives loot: |Hitem:999:|h[Thing]|h|r.",
  "Bob Other", "", "", "Bob Other", "", 0, 0, "", 0, 2, "Player-6841-0BBBBBBB")
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
  if ids[i] ~= ids[i - 1] + 1 and not (ids[i - 1] == 8 and ids[i] == 2) then inOrder = false end
end
check("the objects take turns in the order of their ids, 2 to 8, and then again from the start", inOrder and #ids >= 8)
-- Objects 7 and 8 (#62): where a guide addon's arrow points, and the rested XP.
check("with no guide addon the waypoint object says null", has(round, '[7, 0, "null"]'))
check("the rest object: 0 when the client gives nothing", has(round, '[8, 0, "{\\"rested\\": 0}"]'))
RXP = { arrowFrame = { element = { zone = 1434, x = 40.635038182542, y = 3.5139672370787, step = { title = "Step 12" } } } }
local way = watch(30)
check("the waypoint: the map, and x and y as the position has them (per cent of the map to 0..65535); the step's title",
  has(way, '[7, 0, "{\\"source\\": \\"RXPGuides\\", \\"map\\": 1434, \\"x\\": 26630, \\"y\\": 2303, \\"title\\": \\"Step 12\\", \\"step\\": null, \\"text\\": null}"]'))
RXP.arrowFrame.element = { zone = 1437, x = 10, y = 60.5, title = 'Kill "Crocs"', step = { arrowtext = "not this" } }
check("another place within about a second, with no client event; the element's own title first, a quote escaped",
  has(watch(25), '\\"map\\": 1437, \\"x\\": 6554, \\"y\\": 39649, \\"title\\": \\"Kill \\\\\\"Crocs\\\\\\"\\", '))
RXP.arrowFrame.element = { zone = 1437, x = 10, y = 60.5, title = "", step = { arrowtext = "Go north" } }
check("an empty title: the step's arrow text", has(watch(25), '\\"title\\": \\"Go north\\", '))
RXP.arrowFrame.element = { zone = 1437, x = 10, y = 60.5 }
check("no title anywhere: null", has(watch(25), '\\"y\\": 39649, \\"title\\": null, '))
-- The step's number and text (seen 14 Nov 2026: step.index 109, step.text with colour and
-- texture codes and a line break; the place itself had no text).
RXP.arrowFrame.element = { zone = 1434, x = 33.3, y = 11.9,
  step = { index = 109, text = "   Kill |cFFFF5722Young Stranglethorn Tigers|r\n|TInterface/GossipFrame/BattleMasterGossipIcon:0|t6/10 Young Stranglethorn Tiger slain" } }
check("the step's number and its text as the addon holds it, the line break escaped",
  has(watch(25), '\\"title\\": null, \\"step\\": 109, \\"text\\": \\"   Kill |cFFFF5722Young Stranglethorn Tigers|r\\\\n|TInterface/GossipFrame/BattleMasterGossipIcon:0|t6/10 Young Stranglethorn Tiger slain\\"}'))
RXP.arrowFrame.element.step.text = RXP.arrowFrame.element.step.text:gsub("6/10", "7/10")
check("the text follows the count in it", has(watch(25), "|t7/10 Young Stranglethorn Tiger slain"))
RXP.arrowFrame.element.step = { index = 109.5, text = "half" }
check("a step number that is not whole is left out", has(watch(25), '\\"step\\": null, \\"text\\": \\"half\\"}'))
RXP.arrowFrame.element.step = { index = "x", text = ("y"):rep(601) }
check("a step number that is no number, and a text of more than 600 bytes, are left out", has(watch(25), '\\"step\\": null, \\"text\\": null}'))
RXP.arrowFrame.element = { zone = 1437, x = 10, y = 60.5, title = ("x"):rep(201) }
check("a title of more than 200 bytes is left out", has(watch(25), '\\"y\\": 39649, \\"title\\": null, '))
for _, bad in ipairs({ { zone = "Wetlands", x = 10, y = 60 }, { zone = 1437, x = 140, y = 60 }, { zone = 1437, x = 10 } }) do
  RXP.arrowFrame.element = { zone = 1437, x = 1, y = 1 }; watch(25)
  RXP.arrowFrame.element = bad
  local got = watch(25)
  check("a place that is not a map number and two per cents is no waypoint: null", has(got, '[7, 0, "null"]'))
end
-- Review of #62: values that are no place, a text a reader would refuse, and no code of the
-- other addon run.
for _, bad in ipairs({ { zone = 0 / 0, x = 10, y = 60 }, { zone = 1437, x = 0 / 0, y = 60 }, { zone = 1437, x = 10, y = 0 / 0 },
                       { zone = 1437, x = 10, y = math.huge }, { zone = math.huge, x = 10, y = 60 } }) do
  RXP.arrowFrame.element = { zone = 1437, x = 1, y = 1 }; watch(25)
  RXP.arrowFrame.element = bad
  check("a map or a coordinate that is NaN or infinite is no waypoint: null", has(watch(25), '[7, 0, "null"]'))
end
RXP.arrowFrame.element = { zone = 1437, x = 20, y = 30, title = "bad \255 byte", step = { index = 0 / 0, text = "\237\160\128 surrogate" } }
check("a title and a text that are not UTF-8 are left out; the place stays, and a NaN step number is left out",
  has(watch(25), '\\"map\\": 1437, \\"x\\": 13107, \\"y\\": 19661, \\"title\\": null, \\"step\\": null, \\"text\\": null}'))
RXP.arrowFrame.element = { zone = 1437, x = 20, y = 30, title = "Zürich 北 ✓" }
check("a title in well-formed UTF-8 goes through", has(watch(25), "Zürich 北 ✓"))
local called = 0
local meta = { __index = function() called = called + 1 return 5 end }
RXP.arrowFrame.element = setmetatable({ zone = 1437, x = 21, y = 31 }, meta)
setmetatable(RXP, meta); setmetatable(RXP.arrowFrame, meta)
check("the other addon's tables are read with no __index called: the place, and nothing made up from the metatable",
  has(watch(25), '\\"x\\": 13762, \\"y\\": 20316, \\"title\\": null, \\"step\\": null, \\"text\\": null}') and called == 0)
setmetatable(RXP, nil); setmetatable(RXP.arrowFrame, nil)
RXP.arrowFrame.element = { zone = 1437, x = 1, y = 1 }; watch(25)
RXP.arrowFrame.element = { zone = 1437, x = SECRET, y = 60 }
check("a secret value in the arrow is not used: null", has(watch(25), '[7, 0, "null"]'))
RXP.arrowFrame.element = { zone = 1437, x = 1, y = 1 }; watch(25)
RXP.arrowFrame.element = nil
check("the arrow holds nothing: null", has(watch(25), '[7, 0, "null"]'))
RXP = nil
P.rested = 12345.6
events.OnEvent(events, "UPDATE_EXHAUSTION")
check("rested XP after the client's event, as a whole number", has(watch(25), '[8, 0, "{\\"rested\\": 12345}"]'))
for _, bad in ipairs({ -1, 0 / 0, math.huge, "many" }) do
  P.rested = 7; events.OnEvent(events, "UPDATE_EXHAUSTION"); watch(25)
  P.rested = bad; events.OnEvent(events, "UPDATE_EXHAUSTION")
  check("a rested XP that is no amount is 'cannot be read' (format 255), not a number", has(watch(25), "[8, 255, null]"))
end
P.rested = nil
events.OnEvent(events, "PLAYER_XP_UPDATE"); watch(25)

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
local early = watch(12)
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
for _ = 1, 60 do tick(0.01); paths[#paths + 1] = dump() end
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
check("a wrong command lists the commands", has(slash("strip depth 9"), "use /hlink strip"))
slash("strip off"); tick(0.1)
check("/hlink strip off: nothing is on the row", has(read({ dump() }), '"row": false'))
slash("strip on"); tick(0.1)
check("/hlink strip on brings it back", has(read({ dump() }), '"row": true'))

-- ---------------- a new UI session ----------------
local _, events2, row2 = load()
row, events = row2, events2
tick(0.1)
check("the next UI load has the next session number, and starts at depth 4 again",
  HelloLinkDB.session == session + 1 and has(read({ dump() }), ('"session": %d'):format(session + 1)))

print_real(("== %d checks, %d failed"):format(n, fails))
os.exit(fails == 0 and 0 or 1)
