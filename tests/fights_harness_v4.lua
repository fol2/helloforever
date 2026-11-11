-- Mock harness for HelloForever (Lua 5.1, no WoW client): loads the files listed in the
-- TOC against a fake client and drives events. Covers the lossless fight log, the
-- snapshot / timeline paths and a smoke test of the UI with strict widget mocks.
package.path = "./tests/?.lua;" .. package.path
local ML = require("mocklib")
local ADDON_DIR = arg[1] or "./HelloForever"
local SVOUT = arg[2] or "./tests/HelloForever_v4_SV.lua"
local TRUTH = arg[3] or "./tests/v4_truth.json"

-- The TOC is the module loader: read the version and the file list from it.
local TOC_VERSION, TOC_FILES, TOC_FIELDS = nil, {}, {}
for line in io.lines(ADDON_DIR .. "/HelloForever.toc") do
  line = line:gsub("\r", "")
  local k, v = line:match("^##%s*([%w%-]+):%s*(.-)%s*$")
  if k then TOC_FIELDS[k] = v
  elseif line:match("%S") and not line:match("^#") then TOC_FILES[#TOC_FILES+1] = line:match("^%s*(.-)%s*$") end
end
TOC_VERSION = assert(TOC_FIELDS.Version, "TOC has no Version")

local clock = 1794211200.0 -- 2026-11-09 06:00 UTC
local FRAME = 0.05
local printed = {}
local realprint = print
function print(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring(select(i, ...)) end printed[#printed+1] = table.concat(t, " ") realprint("    | " .. printed[#printed]) end
time = function() return math.floor(clock) end
local osdate = os.date
local dateFails = 0
date = function(fmt, t) if dateFails > 0 then dateFails = dateFails - 1 error("mock date failure") end return osdate("!" .. fmt, t or time()) end
GetTime = function() return clock end
local profMs = 0
debugprofilestop = function() profMs = profMs + 0.01 return profMs end

local SECRET_MT = { __secret = true, __tostring = function() return "<secret>" end }
local function S() return setmetatable({}, SECRET_MT) end
function issecretvalue(v) return type(v) == "table" and getmetatable(v) == SECRET_MT end
function issecrettable(t) return false end

-- timers on a frame clock
local timers = {}
C_Timer = {
  After = function(sec, fn) timers[#timers+1] = { at = clock + math.max(sec, FRAME * 0.5), fn = fn, once = true } end,
  NewTicker = function(sec, fn, iters)
    local tk = { at = clock + sec, every = sec, fn = fn, left = iters or math.huge, poll = (sec < 1) }
    function tk:Cancel() self.cancelled = true end
    timers[#timers+1] = tk
    return tk
  end,
}
local frameCalls, maxFrameCalls = 0, 0
local function frame1()
  clock = clock + FRAME
  frameCalls = 0
  local snap = {}
  for i, t in ipairs(timers) do snap[i] = t end
  for _, t in ipairs(snap) do
    if not t.cancelled and not t.done and t.at <= clock + 1e-9 then
      if t.once then t.done = true; t.fn()
      else t.left = t.left - 1; t.at = t.at + t.every; t.fn(t); if t.left <= 0 then t.done = true end end
    end
  end
  if frameCalls > maxFrameCalls then maxFrameCalls = frameCalls end
end
local function advance(sec) for _ = 1, math.floor(sec / FRAME + 0.5) do frame1() end end
local function activePolls() local n = 0 for _, t in ipairs(timers) do if t.poll and not t.cancelled and not t.done then n = n + 1 end end return n end

-- ---------------- strict widget mocks ----------------
-- Only methods that exist on the real widget type are accepted; anything else throws, so
-- a typo or a method used on the wrong widget type fails the run.
local REGION = { "SetSize", "SetWidth", "SetHeight", "GetWidth", "GetHeight", "SetPoint", "ClearAllPoints", "GetPoint",
  "SetAllPoints", "Show", "Hide", "IsShown", "SetShown", "SetAlpha", "SetScale", "GetParent" }
local KIND = {
  Frame = { "SetScript", "GetScript", "RegisterEvent", "UnregisterEvent", "SetMovable", "EnableMouse", "EnableMouseWheel",
    "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "SetUserPlaced", "SetClampedToScreen", "SetFrameStrata", "SetFrameLevel",
    "GetFrameLevel", "CreateTexture", "CreateFontString" },
  Texture = { "SetColorTexture", "SetTexture", "SetVertexColor", "SetTexCoord" },
  FontString = { "SetText", "GetText", "SetTextColor", "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetFontObject" },
}
KIND.Button = { "RegisterForClicks" }
KIND.StatusBar = { "SetStatusBarTexture", "SetStatusBarColor", "SetMinMaxValues", "SetValue", "GetValue" }
for _, k in ipairs({ "Button", "StatusBar" }) do for _, m in ipairs(KIND.Frame) do KIND[k][#KIND[k]+1] = m end end
local KNOWN_EVENTS = {}
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "PLAYER_LEVEL_UP",
  "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "ZONE_CHANGED_NEW_AREA", "TIME_PLAYED_MSG", "PLAYER_MONEY",
  "PLAYER_EQUIPMENT_CHANGED", "BAG_UPDATE", "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "TRAIT_CONFIG_UPDATED",
  "UNIT_PET", "PET_BAR_UPDATE", "UNIT_HAPPINESS",
  "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL", "UNIT_SPELLCAST_SUCCEEDED", "CHAT_MSG_LOOT", "CHAT_MSG_TRADESKILLS",
  "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "DAMAGE_METER_COMBAT_SESSION_UPDATED",
  "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET", "ADDON_RESTRICTION_STATE_CHANGED" }) do KNOWN_EVENTS[e] = true end
local IMPL = {}
function IMPL:SetScript(k, fn) self.scripts[k] = fn end
function IMPL:GetScript(k) return self.scripts[k] end
function IMPL:RegisterEvent(e) if not KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. tostring(e) .. "\"") end self.events[e] = true end
function IMPL:GetPoint() local p = self.points[1] if p then return p[1], p[2], p[3], p[4], p[5] end end
function IMPL:SetPoint(point, a, b, c, d)
  local rel, relPoint, x, y
  if type(a) == "number" then rel, relPoint, x, y = self.parent, point, a, b
  elseif a == nil then rel, relPoint, x, y = self.parent, point, 0, 0
  else rel, relPoint, x, y = a, b or point, c or 0, d or 0 end
  assert(type(point) == "string" and type(x) == "number" and type(y) == "number", "bad SetPoint arguments")
  self.points[#self.points+1] = { point, rel, relPoint, x, y }
end
function IMPL:ClearAllPoints() self.points = {} end
function IMPL:Show() if not self.shown then self.shown = true if self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end end end
function IMPL:Hide() if self.shown then self.shown = false if self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end end end
function IMPL:SetShown(v) if v then self:Show() else self:Hide() end end
function IMPL:IsShown() return self.shown end
function IMPL:SetText(t) assert(t == nil or type(t) == "string" or type(t) == "number", "SetText needs a string") self.text = t and tostring(t) or "" end
function IMPL:GetText() return self.text end
function IMPL:SetHeight(h) assert(type(h) == "number") self.height = h end
function IMPL:GetHeight() return self.height or 0 end
function IMPL:SetWidth(w) assert(type(w) == "number") self.width = w end
function IMPL:GetWidth() return self.width or 0 end
function IMPL:SetSize(w, h) assert(type(w) == "number" and type(h) == "number") self.width, self.height = w, h end
function IMPL:SetScale(v) assert(type(v) == "number" and v > 0) self.scale = v end
function IMPL:GetFrameLevel() return self.m_level or 1 end
function IMPL:SetFrameLevel(l) assert(type(l) == "number") self.m_level = l end
function IMPL:GetParent() return self.parent end
function IMPL:SetMinMaxValues(a, b) assert(type(a) == "number" and type(b) == "number") self.min, self.max = a, b end
function IMPL:SetValue(v) assert(type(v) == "number") self.value = v end
function IMPL:GetValue() return self.value end
local widgetCount = 0
local function newWidget(kind, parent)
  local allowed = {}
  for _, m in ipairs(REGION) do allowed[m] = true end
  for _, m in ipairs(KIND[kind]) do allowed[m] = true end
  local w = { kind = kind, parent = parent, scripts = {}, events = {}, points = {}, shown = true }
  widgetCount = widgetCount + 1
  if KIND[kind] ~= KIND.Texture and KIND[kind] ~= KIND.FontString then
    function w:CreateTexture(_, layer) assert(layer == nil or type(layer) == "string") return newWidget("Texture", self) end
    function w:CreateFontString(_, layer, font) assert(font == nil or type(font) == "string") return newWidget("FontString", self) end
  end
  return setmetatable(w, { __index = function(_, k)
    if type(k) == "string" and k:match("^%u") then
      if not allowed[k] then error("unknown " .. kind .. " method '" .. k .. "'", 2) end
      return IMPL[k] or function() end
    end
  end })
end
local frames = {}
function CreateFrame(kind, name, parent, template)
  assert(KIND[kind] and kind ~= "Texture" and kind ~= "FontString", "CreateFrame: unknown frame type " .. tostring(kind))
  assert(template == nil, "templates are not available in the mock client")
  local f = newWidget(kind, parent)
  f.m_name = name
  if name then _G[name] = f end
  frames[#frames+1] = f
  return f
end
UIParent, SlashCmdList, UISpecialFrames = newWidget("Frame"), {}, {}
RAID_CLASS_COLORS = { HUNTER = { r = 0.67, g = 0.83, b = 0.45 } }
function BreakUpLargeNumbers(n) return tostring(n) end
function SecondsToTime(n) return tostring(n) end
local tipLines = {}
GameTooltip = {
  SetOwner = function(self, owner, anchor) assert(self == GameTooltip and owner and type(anchor) == "string") tipLines = {} end,
  AddLine = function(self, text) assert(self == GameTooltip and type(text) == "string") tipLines[#tipLines+1] = text end,
  AddDoubleLine = function(self, l, r) assert(self == GameTooltip and type(l) == "string" and type(r) == "string") tipLines[#tipLines+1] = l .. "\t" .. r end,
  Show = function() end, Hide = function() end,
}
-- MenuUtil.CreateContextMenu(owner, generator): record what the generator builds.
local menuItems = {}
local function menuNode()
  local node = {}
  function node:CreateTitle(text) assert(type(text) == "string") end
  function node:CreateDivider() end
  function node:CreateButton(text, fn) assert(type(text) == "string") menuItems[#menuItems+1] = { text = text, fn = fn } return menuNode() end
  function node:CreateCheckbox(text, isSel, setSel) assert(type(text) == "string") menuItems[#menuItems+1] = { text = text, isSel = isSel, setSel = setSel } end
  function node:CreateRadio(text, isSel, setSel, data) assert(type(text) == "string") menuItems[#menuItems+1] = { text = text, isSel = isSel, setSel = setSel, data = data } end
  return node
end
MenuUtil = { CreateContextMenu = function(owner, gen) assert(owner) menuItems = {} gen(owner, menuNode()) end }

local inCombat, restrictState = false, 0
function InCombatLockdown() return inCombat end
C_RestrictedActions = { GetAddOnRestrictionState = function(t) assert(t == 0) return restrictState end }
Enum = {
  DamageMeterType = { DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4, Interrupts = 5, Dispels = 6, DamageTaken = 7, AvoidableDamageTaken = 8, Deaths = 9, EnemyDamageTaken = 10 },
  AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
  CompressionMethod = { Deflate = 0, Zlib = 1, Gzip = 2 },
  CompressionLevel = { Default = 0, OptimizeForSpeed = 1, OptimizeForSize = 2 },
  SpellBookSpellBank = { Player = 0, Pet = 1 },
}
local logCalls = {}
function LoggingCombat(on) assert(type(on) == "boolean", "LoggingCombat needs a boolean") logCalls[#logCalls+1] = on end
function IsInInstance() return false, "none" end
local PGUID = "Player-1-0ABCDEF"
function UnitGUID(u) return u == "player" and PGUID or nil end
local petState = {
  out = true, hunter = true, temp = false, name = "Wolf", family = "Wolf", familyId = 1, level = 9,
  happiness = 3, hapPct = 125, loyalty = 1, tpTotal = 20, tpSpent = 8, xp = 100, xpNext = 400,
}
function UnitExists(u) return u == "player" or (u == "pet" and petState.out) end
function UnitName(u)
  if u == "pet" then return petState.name end
  return "FakeHunter"
end
function GetRealmName() return "TestRealm" end
local P = { level = 9, xp = 1200, xpMax = 4500, money = 5321, capped = false }
function UnitLevel(u)
  if u == "pet" then return petState.level end
  return P.level
end
function HasPetUI()
  if not petState.out then return false, false end
  if petState.temp then return false, false end
  return true, petState.hunter
end
function UnitCreatureFamily(u)
  if u ~= "pet" or not petState.out then return end
  return petState.family, petState.familyId
end
function GetPetHappiness()
  if not petState.out or not petState.hunter or petState.temp then return end
  return petState.happiness, petState.hapPct, petState.loyalty
end
function GetPetTrainingPoints()
  if not petState.out or not petState.hunter or petState.temp then return end
  return petState.tpTotal, petState.tpSpent
end
function GetPetExperience()
  if not petState.out then return end
  return petState.xp, petState.xpNext
end
function GetPetIcon() return "Interface\\Icons\\Ability_Hunter_Pet_Wolf" end
function GetPetActionInfo(i)
  if not petState.out then return end
  if i == 4 then return "Growl", "tex", false, false, true, true, 2649 end
  if i == 5 then return "Bite", "tex", false, false, true, false, 17253 end
end
C_SpellBook = {
  HasPetSpells = function()
    if not petState.out or petState.temp then return nil end
    return 2, "PET"
  end,
  GetSpellBookItemName = function(i, bank)
    if bank ~= 1 then return end
    if i == 1 then return "Growl", "Rank 3" end
    if i == 2 then return "Bite", "Rank 2" end
  end,
  GetSpellBookItemType = function(i, bank)
    if bank ~= 1 then return end
    if i == 1 then return "SPELL", 2649 end
    if i == 2 then return "SPELL", 17253 end
  end,
}
function UnitXP() return P.xp end
function UnitXPMax() return P.xpMax end
function GetMoney() return P.money end
function IsPlayerAtEffectiveMaxLevel() return P.capped end
function UnitClass() return "Hunter", "HUNTER" end
function UnitRace() return "Dwarf", "Dwarf" end
function UnitFactionGroup() return "Alliance", "Alliance" end
function GetXPExhaustion() return 0 end
function GetRealZoneText() return "Darkshore" end
function GetZoneText() return "Darkshore" end
function GetSubZoneText() return "Blackwood Den" end
function GetBuildInfo() return "1.60.1", "70862", "Nov 3 2026", 16001 end
function UnitStat() return 10, 10 end
local loadedAddons = { HelloForever = true }
C_AddOns = {
  GetAddOnMetadata = function(name, field)
    if name == "HelloForever" then return TOC_FIELDS[field] end
    if name == "Matty7500Hunter" and field == "Version" then return "test-0" end
  end,
  IsAddOnLoaded = function(name) return loadedAddons[name] == true end,
}
local equipped = { [16] = "|Hitem:2504|h[Worn Shortbow]|h" }
function GetInventoryItemLink(unit, slot) return equipped[slot] end
NUM_BAG_SLOTS = 4
local bagItems = { [0] = { [1] = { id = 159, count = 5, link = "|Hitem:159|h[Refreshing Spring Water]|h" } } }
function GetContainerNumSlots(bag) return bag == 0 and 16 or 0 end
function GetContainerItemLink(bag, slot) local it = bagItems[bag] and bagItems[bag][slot]; return it and it.link end
function GetContainerItemID(bag, slot) local it = bagItems[bag] and bagItems[bag][slot]; return it and it.id end
function GetContainerItemInfo(bag, slot)
  local it = bagItems[bag] and bagItems[bag][slot]
  if not it then return end
  return "tex", it.count, false, 1, false, false, it.link, false, false, it.id
end
C_Container = {
  GetContainerNumSlots = GetContainerNumSlots,
  GetContainerItemLink = GetContainerItemLink,
  GetContainerItemInfo = function(bag, slot)
    local it = bagItems[bag] and bagItems[bag][slot]
    if not it then return nil end
    return { itemID = it.id, stackCount = it.count, hyperlink = it.link }
  end,
}
-- Quest log: C_QuestLog.GetInfo on Forever has NO isComplete (warcraft.wiki.gg).
local questLog = {
  { title = "The People's Militia", level = 12, isHeader = false, questID = 164, isComplete = nil,
    objectives = { { text = "Defias: 3/8", type = "monster", finished = false, numFulfilled = 3, numRequired = 8 } } },
  { title = "Westfall Stew", level = 10, isHeader = false, questID = 22, isComplete = 1,
    objectives = { { text = "Okra: 3/3", type = "item", finished = true, numFulfilled = 3, numRequired = 3 } } },
  { title = "Lost Necklace", level = 10, isHeader = false, questID = 85, isComplete = nil,
    objectives = { { text = "Necklace: 0/1", type = "item", finished = false, numFulfilled = 0, numRequired = 1 } } },
}
local completedQuests = { 6, 9 }
local historyCalls = 0
function GetNumQuestLogEntries() return #questLog, #questLog end
function GetQuestLogTitle(i)
  local q = questLog[i]
  if not q then return end
  return q.title, q.level, 0, q.isHeader, false, q.isComplete, 1, q.questID
end
function GetNumQuestLeaderBoards(i) local q = questLog[i]; return q and q.objectives and #q.objectives or 0 end
function GetQuestLogLeaderBoard(obj, qi)
  local o = questLog[qi] and questLog[qi].objectives and questLog[qi].objectives[obj]
  if not o then return end
  return o.text, o.type, o.finished
end
function IsQuestComplete(id)
  for _, q in ipairs(questLog) do if q.questID == id then return q.isComplete == 1 or q.isComplete == true end end
  return false
end
C_QuestLog = {
  GetNumQuestLogEntries = GetNumQuestLogEntries,
  GetInfo = function(i)
    local q = questLog[i]
    if not q then return end
    return { title = q.title, level = q.level, isHeader = q.isHeader, questID = q.questID }
  end,
  GetQuestObjectives = function(id)
    for _, q in ipairs(questLog) do if q.questID == id then return q.objectives end end
  end,
  IsQuestFlaggedCompleted = function(id)
    for _, x in ipairs(completedQuests) do if x == id then return true end end
    return false
  end,
  GetAllCompletedQuestIDs = function() historyCalls = historyCalls + 1 return completedQuests end,
}
C_Map = { GetBestMapForUnit = function() return 1439 end }
C_Spell = { GetSpellName = function(id) return "Spell" .. id end }

local encCalls = 0
local rejectLevel, levelCalls = false, 0
C_EncodingUtil = {
  SerializeJSON = function(v) encCalls = encCalls + 1 return ML.json(v) end,
  CompressString = function(s, m, level)
    assert(m == 0, "expected Deflate")
    if level ~= nil then
      if rejectLevel then error("mock: compression level not supported") end
      assert(level == 2, "expected OptimizeForSize")
      levelCalls = levelCalls + 1
    end
    return ML.deflateStored(s)
  end,
  DecompressString = function(z, m) assert(m == 0) return ML.inflateStored(z) end,
  EncodeBase64 = function(s) return ML.b64enc(s) end,
  DecodeBase64 = function(s) return ML.b64dec(s) end,
  DeserializeJSON = function(s) return ML.unjson(s) end,
}

-- ---------------- C_DamageMeter mock ----------------
local NEVER_SECRET = { classFilename = true, isLocalPlayer = true, deathRecapID = true, classification = true, unitClassFilename = true }
local secretMode = false
local sessions = {}
local dmCalls = 0
local throwType = nil
local function secretify(v, key)
  if type(v) == "table" then local o = {} for k, x in pairs(v) do o[k] = secretify(x, k) end return o end
  if key == "specIconID" then return S() end
  if secretMode and not NEVER_SECRET[key] and (type(v) == "number" or type(v) == "string") then return S() end
  return v
end
local function src(guid, cid, name, cls, total, dur, isMe, extra)
  local s = { sourceGUID = guid, sourceCreatureID = cid, name = name, classFilename = cls, specIconID = 132222,
    totalAmount = total, amountPerSecond = total / dur, isLocalPlayer = isMe, deathRecapID = 0, deathTimeSeconds = 0,
    classification = isMe and "" or "normal", sourceDisplayType = isMe and 1 or 2, factionGroup = isMe and "Alliance" or nil }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end
local function spell(id, amt, dur, creature, unit, isPet)
  return { spellID = id, totalAmount = amt, amountPerSecond = amt / dur, creatureName = creature or "", overkillAmount = 0,
    isAvoidable = false, isDeadly = false,
    combatSpellDetails = { unitName = unit or "", unitClassFilename = "", classification = "normal", isPet = isPet or false, isMob = true, amount = amt, specIconID = 132222 } }
end
-- Build a full session: every type, every source, every breakdown.
local function makeSession(sid, name, dur, o)
  o = o or {}
  local me = function(total, extra) return src(PGUID, nil, "FakeHunter", "HUNTER", total, dur, true, extra) end
  local mobs = o.mobs or { { "Creature-0-1-" .. sid, 2163, name } }
  local T = {}
  local function put(t, sources, spellsBy) T[t] = { sources = sources, spells = spellsBy or {} } end
  local dmgSpells = { spell(75, 300, dur), spell(3044, 120, dur), spell(17253, 130, dur, "Wolf", nil, true), spell(16827, 50, dur, "Wolf", nil, true) }
  for i = 1, (o.extraSpells or 0) do dmgSpells[#dmgSpells+1] = spell(10000 + i, 5 + i, dur) end
  local dmgTotal = 0 for _, s in ipairs(dmgSpells) do dmgTotal = dmgTotal + s.totalAmount end
  put(0, { me(dmgTotal) }, { dmgSpells })
  put(1, { me(dmgTotal) }, { dmgSpells })
  put(2, o.heal and { me(o.heal) } or {}, o.heal and { { spell(2061, o.heal, dur) } } or {})
  put(3, o.heal and { me(o.heal) } or {}, o.heal and { { spell(2061, o.heal, dur) } } or {})
  put(4, {}, {}); put(5, {}, {}); put(6, {}, {})
  local taken = {}
  for _, m in ipairs(mobs) do taken[#taken+1] = spell(6603, 40, dur, nil, m[3]) end
  put(7, { me(40 * #mobs) }, { taken })
  put(8, {}, {})
  put(9, o.died and { me(1, { deathRecapID = 77 + sid, deathTimeSeconds = dur }) } or {}, o.died and { {} } or {})
  local enemySrc, enemySp = {}, {}
  for _, m in ipairs(mobs) do
    enemySrc[#enemySrc+1] = src(m[1], m[2], m[3], "", math.floor(dmgTotal / #mobs), dur, false)
    enemySp[#enemySp+1] = { spell(75, math.floor(dmgTotal / #mobs), dur, nil, "FakeHunter") }
  end
  put(10, enemySrc, enemySp)
  if o.empty then for t = 0, 10 do put(t, {}, {}) end end
  sessions[sid] = { name = name, dur = dur, T = T, died = o.died }
end
C_DamageMeter = {
  IsDamageMeterAvailable = function() return true, "" end,
  GetAvailableCombatSessions = function()
    dmCalls = dmCalls + 1; frameCalls = frameCalls + 1; if frameCalls > maxFrameCalls then maxFrameCalls = frameCalls end
    local out = {}
    for sid, s in pairs(sessions) do out[#out+1] = { sessionID = sid, name = s.name, durationSeconds = s.dur } end
    table.sort(out, function(a, b) return a.sessionID < b.sessionID end)
    return out
  end,
  GetCombatSessionFromID = function(sid, typ)
    dmCalls = dmCalls + 1; frameCalls = frameCalls + 1; if frameCalls > maxFrameCalls then maxFrameCalls = frameCalls end
    assert(not inCombat, "C_DamageMeter session read in combat!")
    if throwType and typ == throwType then error("mock failure type " .. typ) end
    local s = assert(sessions[sid], "no session")
    local d = s.T[typ]
    local total, maxA = 0, 0
    for _, x in ipairs(d.sources) do total = total + x.totalAmount; if x.totalAmount > maxA then maxA = x.totalAmount end end
    return secretify({ combatSources = d.sources, maxAmount = maxA, totalAmount = total, durationSeconds = s.dur })
  end,
  GetCombatSessionSourceFromID = function(sid, typ, guid, cid)
    dmCalls = dmCalls + 1; frameCalls = frameCalls + 1; if frameCalls > maxFrameCalls then maxFrameCalls = frameCalls end
    assert(not inCombat, "C_DamageMeter source read in combat!")
    local s = sessions[sid]
    local d = s.T[typ]
    for i, x in ipairs(d.sources) do
      if x.sourceGUID == guid and x.sourceCreatureID == cid then
        local sp = d.spells[i] or {}
        local total, maxA = 0, 0
        for _, y in ipairs(sp) do total = total + y.totalAmount; if y.totalAmount > maxA then maxA = y.totalAmount end end
        return secretify({ combatSpells = sp, maxAmount = maxA, totalAmount = total })
      end
    end
    return secretify({ combatSpells = {}, maxAmount = 0, totalAmount = 0 })
  end,
}
local recapSecret = false
C_DeathRecap = {
  HasRecapEvents = function(id) if recapSecret then return S() end return true end,
  GetRecapEvents = function(id) return secretify({ { event = "SWING_DAMAGE", spellId = 88163, amount = 55, timestamp = clock - 1, currentHP = 0, sourceName = "Blackwood Ursa", absorbed = 0, spellSchool = 1, overkill = 12, critical = true, crushing = false } }) end,
  GetRecapMaxHealth = function(id) return secretMode and S() or 180 end,
  GetRecapLink = function(id) return "|Hdeath:" .. id .. "|h[Death]|h" end,
}

-- expected (truth) record content per session, specIconID removed
local function stripIcon(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do if k ~= "specIconID" then o[k] = stripIcon(x) end end
  return o
end
local truth = {}
local function recordTruth(sid, key)
  local s = sessions[sid]
  local saved = secretMode; secretMode = false
  local types = {}
  for name, t in pairs(Enum.DamageMeterType) do
    local sess = C_DamageMeter.GetCombatSessionFromID(sid, t)
    local by = {}
    for i, x in ipairs(sess.combatSources) do by[i] = stripIcon(C_DamageMeter.GetCombatSessionSourceFromID(sid, t, x.sourceGUID, x.sourceCreatureID)) end
    local cs = stripIcon(sess); cs.bySource = by
    types[name] = cs
  end
  secretMode = saved
  truth[key] = { sid = sid, name = s.name, dur = s.dur, types = types }
end

-- ---------------- load addon ----------------
local ns = {}
for _, file in ipairs(TOC_FILES) do
  assert(loadfile(ADDON_DIR .. "/" .. file))("HelloForever", ns)
end
local f = assert(ns.eventFrame, "no event frame")
for _, k in ipairs({ "AddonCompartmentFunc", "AddonCompartmentFuncOnEnter", "AddonCompartmentFuncOnLeave" }) do
  assert(type(_G[TOC_FIELDS[k]]) == "function", "TOC " .. k .. " names a missing global: " .. tostring(TOC_FIELDS[k]))
end
local function fire(ev, ...) f.scripts.OnEvent(f, ev, ...) end
local function slash(m) SlashCmdList["HELLOFOREVER"](m) end
local CK = "FakeHunter-TestRealm"
local function C() return HelloForeverDB.characters[CK] end
local function allKeys()
  local out = {}
  for d, b in pairs(C().fightLog.days) do for _, k in ipairs(b.keys) do out[#out+1] = k end end
  table.sort(out) return out
end
local function count() return #allKeys() end
local function decode(key)
  local fl = C().fightLog
  local b = fl.days[fl.index[key]]
  for i, k in ipairs(b.keys) do if k == key then
    local blob = b.data[i]
    assert(type(blob) == "string" and blob:sub(1, 3) == "d1:", "not deflate blob")
    return ML.inflateStored(ML.b64dec(blob:sub(4)))
  end end
end
local results = {}
local function check(name, cond) results[#results+1] = (cond and "PASS " or "FAIL ") .. name; realprint((cond and "PASS " or "FAIL ") .. name) end
-- simulate a pull: enter combat, meter events, leave combat
local function pull(sid, name, dur, o, opts)
  opts = opts or {}
  inCombat = true; restrictState = 2
  fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 1)
  fire("PLAYER_REGEN_DISABLED")
  if not opts.sameSession then fire("DAMAGE_METER_CURRENT_SESSION_UPDATED") end
  makeSession(sid, name, dur, o)
  fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 0)
  fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, sid)
  advance(opts.combatSec or 1)
  fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, sid)
end
local function leave(secret)
  inCombat = false
  secretMode = secret and true or false
  restrictState = secret and 2 or 0
  fire("PLAYER_REGEN_ENABLED")
end

realprint("== boot")
fire("ADDON_LOADED", "HelloForever"); fire("PLAYER_LOGIN"); fire("PLAYER_ENTERING_WORLD", true, false); advance(4)
check("boot ok, empty log", count() == 0)
check("combat log mode off: logging left alone at login", #logCalls == 0)

realprint("== 1. instant read at PLAYER_REGEN_ENABLED")
local before = dmCalls
pull(1, "Blackwood Ursa", 12, { heal = 35 })
check("no C_DamageMeter calls in combat", dmCalls == before)
local startT = C().fightTrack.sessions[1].start
leave(false)
local sameFrame = count()
advance(0.2)
check("fight 1 stored within 0.2 s of combat end", count() == 1)
realprint("   stored in the same frame as PLAYER_REGEN_ENABLED: " .. tostring(sameFrame == 1))
local k1 = allKeys()[1]
do
  local p = ns.ParseFightKey(k1)
  check("key is hf1 format", p and p.format == "hf1")
  check("key sid/start/seq", p and p.sid == 1 and p.start == startT and p.seq == 1)
  check("key installId matches DB", p and p.installId == HelloForeverDB.installId)
end
do
  local rec = ns.FightsLoad(k1)
  check("fight context hashes from pre-pull snapshot", rec and rec.context and rec.context.gear
    and rec.context.talents and rec.context.pet
    and C().contextBlobs[rec.context.gear] and C().contextBlobs[rec.context.gear].kind == "gear")
  check("MH unavailable when the addon is not loaded", rec and rec.mh and rec.mh.status == "unavailable")
  check("the unavailable MH stamp stays small (it is on every fight)", rec and rec.mh and rec.mh.note == nil and rec.mh.approx == nil)
  check("context stamped at the pull is not approximate", rec and rec.context and rec.context.approx == nil)
end
recordTruth(1, k1)

realprint("== 2. still secret at REGEN_ENABLED -> read on ADDON_RESTRICTION_STATE_CHANGED(Combat,0)")
pull(2, "Blackwood Shaman", 9, { died = true })
leave(true)
advance(0.6)
check("not stored while secret", count() == 1)
secretMode = false; restrictState = 0
fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0)
advance(0.1)
check("stored right after restriction lifts", count() == 2)
recordTruth(2, allKeys()[2])

realprint("== 3. chain pull: next combat starts before the read")
pull(3, "Blackwood Pathfinder", 15, {})
leave(true)          -- secret
advance(0.1)
pull(4, "Blackwood Totemic", 7, { mobs = { { "Creature-0-1-4a", 2170, "Blackwood Totemic" }, { "Creature-0-1-4b", 2171, "Blackwood Warrior" } } })
leave(false)
advance(0.5)
check("both chained fights stored (3 and 4)", count() == 4)
local ks = allKeys()
recordTruth(3, ks[3]); recordTruth(4, ks[4])
check("no poll ticker left running", activePolls() == 0)

realprint("== 4. one session spanning another pull (session grows) -> rev 2, same key")
local keyBefore = ks[4]
pull(4, "Blackwood Totemic", 19, { mobs = { { "Creature-0-1-4a", 2170, "Blackwood Totemic" }, { "Creature-0-1-4b", 2171, "Blackwood Warrior" }, { "Creature-0-1-4c", 2172, "Blackwood Mystic" } }, extraSpells = 2 }, { sameSession = true })
leave(false); advance(0.5)
check("still 4 fights", count() == 4)
local sum = C().fightSummary
check("summary rev2 for grown session", sum[#sum].key == keyBefore and sum[#sum].rev == 2 and sum[#sum].dur == 19)
recordTruth(4, keyBefore)

realprint("== 5. /reload: catch-up does not duplicate")
fire("PLAYER_ENTERING_WORLD", false, true); advance(4)
check("no duplicates after reload catch-up", count() == 4)

realprint("== 6. meter reset before read -> explicit gap record")
pull(5, "Gnarlpine Ambusher", 6, {})
leave(true); advance(0.3)
sessions = {}
fire("DAMAGE_METER_RESET")
check("gap recorded for unread session 5", count() == 5 and C().fightSummary[#C().fightSummary].gap == "reset")

realprint("== 7. ids restart (relog): new sid 1 is a new fight, old fight 1 untouched")
fire("PLAYER_ENTERING_WORLD", true, false); advance(4)
pull(1, "Gnarlpine Mystic", 8, {})
leave(false); advance(0.5)
check("6 entries, old key kept", count() == 6 and C().fightLog.index[k1] ~= nil)
local newest = C().fightSummary[#C().fightSummary]
check("new sid-1 fight has its own key", newest.name == "Gnarlpine Mystic" and newest.key ~= k1)
recordTruth(1, newest.key)

realprint("== 8. API error on one type does not block the queue")
throwType = 5
pull(2, "Moonkin", 10, {})
leave(false); advance(0.5)
throwType = nil
check("stored despite type 5 error", count() == 7)

realprint("== 9. hitch budget")
check("max C_DamageMeter calls in one frame <= 31 (budget 30 + plan)", maxFrameCalls <= 31)
realprint("   max calls/frame = " .. maxFrameCalls)

realprint("== 10. big session (30 mobs, 40 extra spells) spread across frames")
local mobs = {}
for i = 1, 30 do mobs[i] = { "Creature-0-9-" .. i, 3000 + i, "Mob" .. i } end
maxFrameCalls = 0
pull(3, "Big Pull", 60, { mobs = mobs, extraSpells = 40 })
maxFrameCalls = 0; frameCalls = 0
leave(false)
local frames0 = 0
while count() < 8 and frames0 < 100 do frame1(); frames0 = frames0 + 1 end
check("big session stored", count() == 8)
realprint("   frames to finish = " .. frames0 .. ", max calls/frame = " .. maxFrameCalls)
check("big session split: needs extra frame(s), <=31 calls in any frame", frames0 >= 1 and maxFrameCalls <= 31)
recordTruth(3, C().fightSummary[#C().fightSummary].key)

realprint("== 11. commands")
local p0 = #printed
slash("fights")
check("/hello fights prints", #printed - p0 >= 6)
slash("export")
slash("debug")
check("/hello debug fights line", printed[#printed]:find("fights: api=true", 1, true) ~= nil)
realprint("   " .. printed[#printed])
check("addonVersion from TOC (" .. TOC_VERSION .. ")", HelloForeverDB.addonVersion == TOC_VERSION)
check("VERSION_FALLBACK matches TOC", ns.VERSION_FALLBACK == TOC_VERSION)
check("SOURCE_REVISION matches TOC", ns.SOURCE_REVISION == TOC_VERSION)
check("sourceRevision stamped on DB", HelloForeverDB.sourceRevision == ns.SOURCE_REVISION)
check("schemaVersion stamped on DB", HelloForeverDB.schemaVersion == ns.SCHEMA_VERSION)
check("gameBuild from GetBuildInfo", HelloForeverDB.gameBuild == "70862" and HelloForeverDB.client.build == "70862")
check("installId is 8 hex chars", type(HelloForeverDB.installId) == "string" and HelloForeverDB.installId:match("^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$") ~= nil)
do
  local rec = ns.FightsLoad(k1)
  check("fight export has addonVersion", rec and rec.addonVersion == TOC_VERSION)
  check("fight export has sourceRevision", rec and rec.sourceRevision == ns.SOURCE_REVISION)
  check("fight export has schemaVersion", rec and rec.schemaVersion == ns.SCHEMA_VERSION)
  check("fight export has gameBuild", rec and rec.gameBuild == "70862")
  check("fight export has installId", rec and rec.installId == HelloForeverDB.installId)
end
do
  local snap = C().snapshot
  check("snapshot export has envelope", snap and snap.addonVersion == TOC_VERSION
    and snap.sourceRevision == ns.SOURCE_REVISION and snap.schemaVersion == ns.SCHEMA_VERSION
    and snap.gameBuild == "70862" and snap.installId == HelloForeverDB.installId)
end

realprint("== 11b. 0.6.0 state in the exported SavedVariables (the wow-data contract fixture)")
do
  slash("snap")
  local q = C().snapshot.quests
  check("three log quests: in_progress, ready, accepted", #q.log == 3 and q.log[1].state == "in_progress"
    and q.log[2].state == "ready" and q.log[3].state == "accepted")
  check("objective rows carry have / need", q.log[1].objectives[1].have == 3 and q.log[1].objectives[1].need == 8)
  check("completedTotal reported with the history", q.completedTotal == 2 and #q.completed == 2)
  questLog = { questLog[1], questLog[2] } -- the third quest is abandoned
  ns.PatchQuests()
  q = C().snapshot.quests
  check("abandoned quest recorded with id and title", #q.abandoned == 1 and q.abandoned[1].id == 85
    and q.abandoned[1].title == "Lost Necklace" and type(q.abandoned[1].observedAt) == "number")
  fire("CHAT_MSG_SKILL", "Your skill in Fishing has increased to 75.")
  local oldSpellName = C_Spell.GetSpellName
  C_Spell.GetSpellName = function(id) return id == 7620 and "Fishing" or oldSpellName(id) end
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 7620)
  fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:1::::::::1::::|h[FakeFish]|h|r")
  C_Spell.GetSpellName = oldSpellName
  local kinds = {}
  for _, e in ipairs(C().events) do kinds[e.kind] = true end
  check("profession events in the ring", kinds.skill_up and kinds.profession_cast and kinds.profession_loot)
end

-- dump SV + truth before the trim test (trim test uses its own loop)
local function ser(v, ind)
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t ~= "table" then return tostring(v) end
  local out = { "{\n" }
  local n = #v
  for i = 1, n do out[#out+1] = ind .. "\t" .. ser(v[i], ind .. "\t") .. ", -- [" .. i .. "]\n" end
  local keys = {}
  for k in pairs(v) do if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then keys[#keys+1] = k end end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    local ks = type(k) == "string" and string.format("[%q]", k) or ("[" .. tostring(k) .. "]")
    out[#out+1] = ind .. "\t" .. ks .. " = " .. ser(v[k], ind .. "\t") .. ",\n"
  end
  out[#out+1] = ind .. "}"
  return table.concat(out)
end
local fh = assert(io.open(SVOUT, "w")); fh:write("\nHelloForeverDB = " .. ser(HelloForeverDB, "") .. "\n"); fh:close()
fh = assert(io.open(TRUTH, "w")); fh:write(ML.json(truth)); fh:close()

-- ---------------------------------------------------------------------------
-- Checks added with v0.5.0
-- ---------------------------------------------------------------------------
local function deepEq(a, b, path)
  if type(a) ~= type(b) then return false, path .. ": " .. type(a) .. " vs " .. type(b) end
  if type(a) ~= "table" then
    if type(a) == "number" then if math.abs(a - b) > 1e-6 then return false, path .. ": " .. a .. " vs " .. b end return true end
    if a ~= b then return false, path .. ": " .. tostring(a) .. " vs " .. tostring(b) end
    return true
  end
  for k, v in pairs(a) do local ok, why = deepEq(v, b[k], path .. "/" .. tostring(k)) if not ok then return false, why end end
  for k in pairs(b) do if a[k] == nil then return false, path .. "/" .. tostring(k) .. ": extra" end end
  return true
end
local function doneCount() local n = 0 for _ in pairs(C().fightTrack.done) do n = n + 1 end return n end
local function fightOnce(sid, name, dur, o) pull(sid, name, dur, o); leave(false); advance(0.5) end
local function lastSummary() return C().fightSummary[#C().fightSummary] end

realprint("== 13. lossless: every record still in the log decodes to exactly what the API returned")
do
  local checked, bad = 0, nil
  for key, t in pairs(truth) do
    if C().fightLog.index[key] then
      local rec = ns.FightsLoad(key)
      local ok, why = deepEq(ML.unjson(ML.json(t.types)), rec and rec.types, key)
      checked = checked + 1
      if not ok then bad = why end
    end
  end
  realprint("   records compared: " .. checked .. (bad and ("  first difference: " .. bad) or ""))
  check("decoded records equal the truth", checked >= 1 and bad == nil)
end

realprint("== 12. budget trim: 40 days of big fights; only days older than 7 d trimmed")
for d = 1, 40 do
  clock = clock + 86400
  for j = 1, 3 do
    local sid = 100 + d * 10 + j
    pull(sid, "Day" .. d .. "Mob" .. j, 30, { extraSpells = 400 })
    leave(false); advance(0.5)
  end
end
local fl = C().fightLog
local today = date("%Y-%m-%d")
local cutoff = date("%Y-%m-%d", time() - 7 * 86400)
local okRecent, anyTrim, trimmedOld = true, false, true
for d, t in pairs(fl.trimmed) do anyTrim = true; if d >= cutoff then trimmedOld = false end end
check("trim happened", anyTrim)
check("only days older than 7 d trimmed", trimmedOld)
check("today's bucket intact", fl.days[today] ~= nil and #fl.days[today].keys == 3)
local oldLeft = false
for d in pairs(fl.days) do if d < cutoff then oldLeft = true end end
check("over budget: every day older than 7 d trimmed, recent days kept even if over budget", not oldLeft)
local tk = 0 for _, t in pairs(fl.trimmed) do tk = tk + t.n end
realprint(("   kept %d fights in %.0f KB, trimmed %d fights (keys listed for pipeline verification)"):format(count(), (fl.bytes or 0) / 1024, tk))


realprint("== 13b. PLAYER_REGEN_ENABLED while the client still reports combat: retried shortly after")
do
  local n0 = count()
  pull(650, "Lagging Boar", 5, {})
  secretMode = false; restrictState = 0
  fire("PLAYER_REGEN_ENABLED")          -- inCombat still true
  check("nothing read while still locked down", count() == n0)
  inCombat = false
  advance(0.7)
  check("read on the follow-up, without another trigger", count() == n0 + 1)
end

realprint("== 14. read markers of sessions the client dropped are forgotten after an hour")
do
  local before = doneCount()
  local gaps0 = ns.fightStatus.gaps
  for sid in pairs(sessions) do if sid < 500 then sessions[sid] = nil end end
  slash("fights read"); advance(0.2)
  check("markers kept right after the sessions left the list", doneCount() == before)
  clock = clock + 3700
  slash("fights read"); advance(0.2)
  local present = 0 for _ in pairs(sessions) do present = present + 1 end
  realprint("   done markers " .. before .. " -> " .. doneCount() .. " (sessions still listed: " .. present .. ")")
  check("only listed sessions keep a marker", doneCount() == present)
  check("dropping read sessions records no gap", ns.fightStatus.gaps == gaps0)
end

realprint("== 15. id reused by another fight with LOWER totals: own key, old record untouched")
do
  fightOnce(600, "Twin Boar", 20, { extraSpells = 5 })
  local oldKey, n0 = lastSummary().key, count()
  local oldJson = decode(oldKey)
  makeSession(600, "Twin Boar", 30, {})          -- same id and name, longer, but less damage; no events
  slash("fights read"); advance(0.5)
  local s = lastSummary()
  check("stored as a separate fight", count() == n0 + 1 and s.key ~= oldKey and s.rev == 1)
  check("old record byte-identical", decode(oldKey) == oldJson)
  local rec = ns.FightsLoad(s.key)
  check("new record remembers the key it did not overwrite", rec and rec.rekeyOf == oldKey and rec.startApprox == true)
end

realprint("== 16. shorter session on a read id: lower own totals = another fight, same content = a correction")
do
  fightOnce(601, "Short Boar", 20, { extraSpells = 3 })
  local oldKey, n0 = lastSummary().key, count()
  makeSession(601, "Short Boar", 8, {})            -- shorter AND the player's damage went down
  slash("fights read"); advance(0.5)
  check("another fight: both kept", count() == n0 + 1 and lastSummary().key ~= oldKey and C().fightLog.index[oldKey] ~= nil)
  fightOnce(608, "Trimmed Boar", 20, {})
  local key = lastSummary().key
  n0 = count()
  local rekeyed0 = ns.fightStatus.rekeyed
  makeSession(608, "Trimmed Boar", 17, {})          -- same content, the client shortened the length
  slash("fights read"); advance(0.5)
  check("a length correction updates the same record, no duplicate",
    count() == n0 and lastSummary().key == key and lastSummary().rev == 2 and lastSummary().dur == 17 and ns.fightStatus.rekeyed == rekeyed0)
end

realprint("== 16b. one meter type fails during a re-read: the good record is kept and the read retried")
do
  fightOnce(700, "Glitchy Boar", 10, {})
  local key, n0, rekeyed0 = lastSummary().key, count(), ns.fightStatus.rekeyed
  local good = decode(key)
  makeSession(700, "Glitchy Boar", 15, { extraSpells = 2 })
  throwType = 0                                      -- DamageDone throws on this read
  slash("fights read"); advance(0.5)
  check("not filed as a second fight, good record not overwritten",
    count() == n0 and lastSummary().key == key and ns.fightStatus.rekeyed == rekeyed0 and decode(key) == good)
  throwType = nil
  advance(6)                                         -- the retry, no other trigger
  local rec = ns.FightsLoad(key)
  check("the retry stores the clean read under the same key",
    count() == n0 and lastSummary().key == key and lastSummary().rev == 2 and rec.dur == 15 and rec.types.DamageDone.err == nil and rec.types.DamageDone.totalAmount > 600)
  makeSession(700, "Glitchy Boar", 20, { extraSpells = 4 })
  throwType = 0                                      -- now it keeps failing
  slash("fights read"); advance(20)
  throwType = nil
  rec = ns.FightsLoad(key)
  check("a type that keeps failing is stored after 3 tries, so the queue cannot stick",
    count() == n0 and lastSummary().rev == 3 and rec.dur == 20 and rec.types.DamageDone.err ~= nil and rec.types.HealingDone.err == nil)
  makeSession(700, "Glitchy Boar", 24, { extraSpells = 4 })
  slash("fights read"); advance(0.5)
  check("and repaired by the next clean read", lastSummary().rev == 4 and ns.FightsLoad(key).types.DamageDone.err == nil)
end

realprint("== 16c. session list briefly empty: nothing is read twice when it comes back")
do
  local n0, gaps0 = count(), ns.fightStatus.gaps
  local saved = sessions
  sessions = {}
  slash("fights read"); advance(0.3)
  sessions = saved
  slash("fights read"); advance(0.5)
  check("no duplicates and no gaps", count() == n0 and ns.fightStatus.gaps == gaps0)
end

realprint("== 16d. relog with numbering restarted at the same id (previous login ended at id 1)")
do
  local function freshLogin()
    sessions = {}
    fire("DAMAGE_METER_RESET")
    fire("PLAYER_ENTERING_WORLD", true, false); advance(4)
  end
  local function relog()                                -- client forgets its sessions, no reset event
    sessions = {}
    fire("PLAYER_ENTERING_WORLD", true, false); advance(4)
  end
  local saved = sessions
  -- with meter events (the normal case)
  for _, v in ipairs({ { 12, { extraSpells = 3 }, "same length, more damage" }, { 12, {}, "same length, less damage" }, { 30, { extraSpells = 6 }, "longer, more damage" } }) do
    freshLogin()
    fightOnce(1, "Relog Boar", 12, { extraSpells = 1 })
    local oldKey, n0 = lastSummary().key, count()
    local oldJson = decode(oldKey)
    check("previous login ended with maxDone 1", C().fightTrack.maxDone == 1)
    relog()
    fightOnce(1, "Relog Boar", v[1], v[2])
    check("with events, " .. v[3] .. ": new fight stored, old record intact",
      count() == n0 + 1 and lastSummary().key ~= oldKey and lastSummary().rev == 1 and decode(oldKey) == oldJson)
  end
  -- without any meter event for the new fight (the read alone has to tell)
  for _, v in ipairs({ { 12, { extraSpells = 3 }, "same length, more damage" }, { 12, {}, "same length, less damage" }, { 30, { extraSpells = 6 }, "longer, more damage" } }) do
    freshLogin()
    fightOnce(1, "Relog Boar", 12, { extraSpells = 1 })
    local oldKey, n0 = lastSummary().key, count()
    local oldJson = decode(oldKey)
    relog()
    makeSession(1, "Relog Boar", v[1], v[2])
    slash("fights read"); advance(0.5)
    check("silent, " .. v[3] .. ": new fight stored, old record intact",
      count() == n0 + 1 and lastSummary().key ~= oldKey and lastSummary().rev == 1 and decode(oldKey) == oldJson)
  end
  sessions = saved
  fire("DAMAGE_METER_RESET"); slash("fights read"); advance(0.5)
end

realprint("== 17. session updated after it was read: re-read, new revision only if it changed")
do
  fightOnce(602, "Late Boar", 12, {})
  local key, n0 = lastSummary().key, count()
  makeSession(602, "Late Boar", 12, { heal = 77 })   -- same duration, more data
  fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 2, 602)
  advance(1.5)
  check("late data stored as rev 2 under the same key", count() == n0 and lastSummary().key == key and lastSummary().rev == 2 and lastSummary().heal == 77)
  local unchanged0 = ns.fightStatus.unchanged
  fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 2, 602)
  advance(1.5)
  check("identical re-read stores nothing", lastSummary().rev == 2 and ns.fightStatus.unchanged == unchanged0 + 1)
  for _ = 1, 4 do fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 2, 602); advance(1.5) end
  local calls0 = dmCalls
  fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 2, 602); advance(1.5)
  realprint("   C_DamageMeter calls for one more update after 3 empty re-reads: " .. (dmCalls - calls0))
  check("a session that keeps 'updating' without change is left alone", dmCalls - calls0 <= 1 and lastSummary().rev == 2)
end

realprint("== 18. death recap still secret (secret boolean): wait, then store")
do
  local n0 = count()
  recapSecret = true
  pull(603, "Deadly Boar", 9, { died = true }); leave(false); advance(0.6)
  check("not stored while the recap is secret", count() == n0)
  recapSecret = false
  advance(0.5)
  check("stored once readable, with the recap", count() == n0 + 1 and lastSummary().died == true)
  check("no poll ticker left running", activePolls() == 0)
end

realprint("== 19. an unexpected error in a step is retried next frame, not at the next fight")
do
  local n0, err0 = count(), ns.fightStatus.errors
  pull(609, "Empty Boar", 4, { empty = true })       -- no sources at all: nothing skipped
  dateFails = 1
  leave(false); advance(0.3)
  check("a retried record with nothing skipped is stored on the second try", ns.fightStatus.errors == err0 + 1 and count() == n0 + 1)
  n0, err0 = count(), ns.fightStatus.errors
  pull(604, "Flaky Boar", 7, {})
  dateFails = 1
  leave(false); advance(0.3)
  check("error counted and the fight stored anyway", ns.fightStatus.errors == err0 + 1 and count() == n0 + 1)
  dateFails = 0
end

realprint("== 20. bursts of changes: the last one is not dropped (trailing debounce)")
do
  fire("PLAYER_EQUIPMENT_CHANGED", 16); advance(0.1)
  equipped[16] = "|Hitem:2505|h[Hornwood Recurve Bow]|h"
  fire("PLAYER_EQUIPMENT_CHANGED", 16); advance(0.1)
  equipped[17] = "|Hitem:2100|h[Small Shield]|h"
  fire("PLAYER_EQUIPMENT_CHANGED", 17); advance(1)
  local eq = C().snapshot.equipped
  check("inside the window nothing is re-read", eq.offhand == nil)
  advance(10)
  eq = C().snapshot.equipped
  check("after the window the snapshot has both changes", eq.mainhand == equipped[16] and eq.offhand == equipped[17])
  local gearAt = C().snapshot.freshness.gear.observedAt
  local function zoneEvents() local n = 0 for _, e in ipairs(C().events) do if e.kind == "zone" then n = n + 1 end end return n end
  advance(12)
  local z0 = zoneEvents()
  fire("ZONE_CHANGED_NEW_AREA"); advance(0.1); fire("ZONE_CHANGED_NEW_AREA"); advance(12)
  check("two zone events for the same zone log one entry", zoneEvents() == z0 + 1)
  P.money = 6000; fire("PLAYER_MONEY"); advance(0.1)
  P.money = 7000; fire("PLAYER_MONEY"); advance(0.1)
  P.money = 8000; fire("PLAYER_MONEY"); advance(11)
  check("money: last value of the burst lands in the snapshot", C().snapshot.money == 8000)
  check("gold freshness updated; gear observedAt unchanged",
    C().snapshot.freshness.gold.status == "ok" and C().snapshot.freshness.gold.observedAt > gearAt
      and C().snapshot.freshness.gear.observedAt == gearAt)
end

realprint("== 21. snapshot work asked for in combat waits for the fight to end")
do
  inCombat = true
  slash("snap")
  check("no snapshot taken in combat", C().snapshot.reason ~= "slash")
  inCombat = false
  fire("PLAYER_REGEN_ENABLED"); advance(3)
  check("taken after combat", C().snapshot.reason == "slash")
end

realprint("== 22. level-capped character (xp 0 / xpMax 0) still snapshots and ticks")
do
  local saved = { P.xp, P.xpMax, P.level }
  P.xp, P.xpMax, P.level, P.capped = 0, 0, 60, true
  slash("snap")
  check("capped snapshot accepted", C().snapshot.level == 60 and C().snapshot._valid == true)
  local n0 = #C().timeline
  ns.TimelineTick(false)
  check("timeline records the capped state", #C().timeline == n0 + 1)
  P.capped = false; P.money = 0
  check("all-zero read is still treated as the logout wipe", ns.TakeSnapshot("wipe").reason ~= "wipe")
  P.xp, P.xpMax, P.level, P.money = saved[1], saved[2], saved[3], 8000
  slash("snap")
end

realprint("== 23. level log")
do
  fire("TIME_PLAYED_MSG", 36000, 5400)
  advance(60)
  P.level = 10; P.xp = 30
  fire("PLAYER_LEVEL_UP", 10); advance(2)
  local log = C().levels
  local e = log and log[#log]
  check("level-up logged with time played", e and e.level == 10 and e.took >= 5460 and e.took < 5470 and e.played >= 36060)
  check("snapshot time played keeps counting", C().snapshot.timePlayed.total >= 36060)
  local p0 = #printed
  slash("levels")
  check("/hello levels prints the log", #printed - p0 >= 2)
end

realprint("== 24. timeline trim keeps a keyframe first")
do
  local tl = C().timeline
  for i = #tl + 1, 2000 do tl[i] = { t = i, last = i, n = 1, xp = i, k = (i % 12 == 0) or nil } end
  for i = 1, 3 do P.money = P.money + 1; ns.TimelineTick(false) end
  check("capped at 2000 and decodable from the first entry", #tl <= 2000 and tl[1].k == true)
  realprint("   timeline entries after trim: " .. #tl)
end

realprint("== 25. manual purge and budget")
do
  local n0 = count()
  slash("purge 3")
  check("purging inside the 7-day keep window needs 'force'", count() == n0)
  slash("purge 3 force")
  local cutoff3 = date("%Y-%m-%d", time() - 3 * 86400)
  local left = false
  for d in pairs(C().fightLog.days) do if d < cutoff3 then left = true end end
  local purged = false
  for _, t in pairs(C().fightLog.trimmed) do if t.how == "purge" then purged = true end end
  check("days older than 3 days purged, receipts kept", not left and purged and count() < n0)
  local sum = 0
  for _, b in pairs(C().fightLog.days) do sum = sum + b.bytes end
  check("running byte total matches the buckets", C().fightLog.bytes == sum)
  slash("budget 5")
  check("budget setting applied", HelloForeverDB.settings.budgetMB == 5 and ns.FightsBudgetBytes() == 5 * 1024 * 1024)
  slash("budget 3")
end

realprint("== 26. XP panel")
do
  local panel = HelloForeverFrame
  check("panel built and shown", panel ~= nil and panel:IsShown())
  P.xp = 2250; P.xpMax = 4500
  fire("PLAYER_XP_UPDATE"); advance(1.2)
  realprint("   panel: " .. tostring(panel.level.text) .. " | " .. tostring(panel.pct.text) .. " | " .. tostring(panel.bar.value) .. "/" .. tostring(panel.bar.max) .. " | " .. tostring(panel.rate.text) .. " | " .. tostring(panel.eta.text) .. " | " .. tostring(panel.fight.text))
  check("level / percent / bar follow XP", panel.level.text == "Level 10" and panel.pct.text == "50.0%" and panel.bar.value == 2250 and panel.bar.max == 4500)
  check("rate and time-to-level shown", panel.rate.text:find("XP/h", 1, true) ~= nil and panel.eta.text:find("level in", 1, true) ~= nil)
  check("last fight line shown", panel.fight:IsShown() and panel.fight.text:find("Flaky Boar", 1, true) ~= nil)
  panel.scripts.OnEnter(panel)
  check("tooltip lists the session", #tipLines >= 6)
  local function uiTickers() local n = 0 for _, t in ipairs(timers) do if t.every == 1 and not t.cancelled and not t.done then n = n + 1 end end return n end
  local t0 = uiTickers()
  slash("hide")
  check("hidden panel stops its ticker", not panel:IsShown() and uiTickers() == t0 - 1 and HelloForeverDB.settings.shown == false)
  slash("show")
  check("shown again, one ticker", panel:IsShown() and uiTickers() == t0)
  slash("scale 1.25")
  check("scale applied and saved", panel.scale == 1.25 and HelloForeverDB.settings.scale == 1.25)
  slash("lock")
  panel.scripts.OnDragStart(panel)
  check("locked panel does not start a drag", panel.dragged == nil)
  slash("unlock")
  panel.scripts.OnDragStart(panel); panel:ClearAllPoints(); panel:SetPoint("CENTER", UIParent, "CENTER", 40, -30); panel.scripts.OnDragStop(panel)
  local pos = HelloForeverDB.pos
  check("drag saves {point, relPoint, x, y}", pos[1] == "CENTER" and pos[2] == "CENTER" and pos[3] == 40 and pos[4] == -30)
  advance(0.2)
  slash("scale 1")
  P.xp, P.xpMax, P.capped, P.level = 0, 0, true, 60
  fire("PLAYER_XP_UPDATE"); advance(1.2)
  check("capped: max level + gold rate", panel.pct.text == "max level" and panel.rate.text:find("/h", 1, true) ~= nil and panel.eta.text:find("session", 1, true) ~= nil)
  P.xp, P.xpMax, P.capped, P.level = 2250, 4500, false, 10
  fire("PLAYER_XP_UPDATE"); advance(1.2)
end

realprint("== 27. menu, fight window, addon compartment")
do
  local panel = HelloForeverFrame
  panel.scripts.OnMouseUp(panel, "RightButton")
  check("menu built", #menuItems >= 12)
  local ran = 0
  for _, it in ipairs(menuItems) do
    if it.isSel then
      local before = it.isSel(it.data)
      it.setSel(it.data)
      if it.data == nil then it.setSel(it.data) end -- toggle back
      assert(type(before) == "boolean" or before == nil)
      ran = ran + 1
    end
  end
  check("every menu toggle runs", ran >= 8 and HelloForeverDB.settings.combatLog == "auto" and HelloForeverDB.settings.scale == 1.5)
  slash("combatlog off"); slash("scale 1")
  panel.scripts.OnMouseUp(panel, "LeftButton")
  local win = HelloForeverFights
  check("fight window opens with rows", win ~= nil and win:IsShown() and win.rows[1]:IsShown() and win.rows[1].name.text:find("Flaky Boar", 1, true) ~= nil)
  check("newest fight selected with a breakdown", win.detail.text:find("Damage", 1, true) ~= nil and win.detail.text:find("Spell75", 1, true) ~= nil)
  local died
  for i = 1, #win.rows do local r = win.rows[i] if r.summary and r.summary.died then died = r end end
  died.scripts.OnClick(died)
  check("clicking a row shows that fight (death recap included)", win.detail.text:find("Deadly Boar", 1, true) ~= nil and win.detail.text:find("Died in this fight", 1, true) ~= nil and win.detail.text:find("Blackwood Ursa", 1, true) ~= nil)
  win.list.scripts.OnMouseWheel(win.list, -1)
  check("mouse wheel scrolls the list", win.rows[1].summary ~= lastSummary())
  fightOnce(605, "Window Boar", 6, {})
  win.list.scripts.OnMouseWheel(win.list, 5)
  check("a new fight appears while the window is open", win.rows[1].name.text:find("Window Boar", 1, true) ~= nil)
  HelloForever_OnAddonCompartmentClick("HelloForever", "LeftButton")
  check("compartment click toggles the window", not win:IsShown())
  HelloForever_OnAddonCompartmentEnter("HelloForever", panel); HelloForever_OnAddonCompartmentLeave("HelloForever", panel)
  HelloForever_OnAddonCompartmentClick("HelloForever", "RightButton")
  check("compartment right-click toggles the panel", not panel:IsShown())
  HelloForever_OnAddonCompartmentClick("HelloForever", "RightButton")
end

realprint("== 28. commands and announcements")
do
  local p0 = #printed
  slash("")
  check("/hello prints status and the command list", #printed - p0 >= 12 and printed[p0 + 1]:find("level 10, in Darkshore - Blackwood Den", 1, true) ~= nil)
  slash("announce on")
  p0 = #printed
  fightOnce(606, "Loud Boar", 6, {})
  check("announce prints one line per fight", #printed - p0 == 1 and printed[#printed]:find("Loud Boar", 1, true) ~= nil)
  makeSession(606, "Loud Boar", 9, { extraSpells = 1 })
  p0 = #printed
  slash("reset"); p0 = #printed
  fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, 606); advance(1.5)
  check("a later revision is not announced again", lastSummary().rev == 2 and #printed == p0)
  slash("announce off")
  slash("reset")
  p0 = #printed
  fightOnce(607, "Quiet Boar", 6, {})
  check("announce off prints nothing", #printed == p0)
  local dmg1 = lastSummary().dmg
  pull(607, "Quiet Boar", 11, { extraSpells = 3 }, { sameSession = true }); leave(false); advance(0.5)
  check("session totals count a grown fight once", ns.session.fights == 1 and lastSummary().rev == 2 and lastSummary().dmg > dmg1 and ns.session.dmg == lastSummary().dmg)
  check("size-optimised deflate level requested", levelCalls > 0)
  rejectLevel = true
  local n1 = count()
  fightOnce(610, "Plain Boar", 6, {})
  check("client rejects the level: falls back and still stores deflate", count() == n1 + 1 and ns.fightStatus.encode == "deflate")
  rejectLevel = false
  for _, c in ipairs({ "help", "export", "debug", "fights 3", "reset", "resetpos", "toggle", "toggle", "combatlog", "announce", "budget", "scale", "purge", "nonsense" }) do slash(c) end
  check("session counters restart on /hello reset", ns.session.fights == 0 and ns.session.xp == 0)
  local l0 = #logCalls
  slash("combatlog on")
  check("/hello combatlog on starts logging", #logCalls == l0 + 1 and logCalls[#logCalls] == true)
  slash("combatlog off")
  check("/hello combatlog off stops logging", #logCalls == l0 + 2 and logCalls[#logCalls] == false)
end

realprint("== 29. freshness, bags, quest states")
do
  slash("snap")
  local snap = C().snapshot
  local fr = snap.freshness
  check("per-section freshness present", type(fr) == "table" and fr.gold.status == "ok" and fr.gear.status == "ok"
    and fr.quests.status == "ok" and fr.bags.status == "ok" and fr.pet.status == "ok")
  check("bags snapshot occupied slots only", type(snap.bags) == "table" and snap.bags[1] and snap.bags[1].id == 159 and snap.bags[1].count == 5)
  local q = snap.quests
  check("quests is log/history object", type(q) == "table" and type(q.log) == "table" and #q.log == 2)
  check("abandoned entry survives a full snapshot", #q.abandoned == 1 and q.abandoned[1].id == 85)
  check("GetInfo without isComplete: in_progress vs ready", q.log[1].state == "in_progress" and q.log[2].state == "ready")
  check("completed history from GetAllCompletedQuestIDs", type(q.completed) == "table" and q.completed[1] == 6)
  local goldAt, questsAt = fr.gold.observedAt, fr.quests.observedAt
  advance(2)
  P.money = P.money + 50
  ns.PatchMoney()
  check("PatchMoney refreshes gold only", C().snapshot.freshness.gold.observedAt > goldAt
    and C().snapshot.freshness.quests.observedAt == questsAt)
  questLog = { questLog[2] }
  ns.PatchQuests()
  local ab = C().snapshot.quests.abandoned
  check("left the log and not flagged completed => abandoned",
    type(ab) == "table" and #ab >= 1 and ab[#ab].id == 164)
  local pet = snap.pet
  check("hunter pet name/family/level", pet and pet.kind == "hunter" and pet.name == "Wolf" and pet.family == "Wolf" and pet.level == 9)
  check("hunter pet happiness and training points", pet.happiness == 3 and type(pet.training) == "table" and pet.training.spent == 8)
  local growl
  for i = 1, #pet.abilities do if pet.abilities[i].name == "Growl" then growl = pet.abilities[i] end end
  check("Growl rank 3 autocast on", growl and growl.rank == 3 and growl.autocast == true and growl.spellID == 2649)
  petState.temp, petState.hunter = true, false
  ns.PatchPet()
  check("temporary summon is not the hunter pet", C().snapshot.pet.kind == "temporary" and C().snapshot.pet.happiness == "unknown")
  petState.temp, petState.hunter, petState.out = false, true, true
  ns.PatchPet()
  fire("CHAT_MSG_SKILL", "Your skill in Fishing has increased to 76.")
  local ev = C().events
  local skillUp
  for i = #ev, 1, -1 do if ev[i].kind == "skill_up" then skillUp = ev[i] break end end
  check("profession skill-up event", skillUp and skillUp.skill == "Fishing" and skillUp.rank == 76)
  local oldSpellName = C_Spell.GetSpellName
  C_Spell.GetSpellName = function(id)
    if id == 7620 then return "Fishing" end
    return oldSpellName(id)
  end
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 7620)
  local profCast
  for i = #ev, 1, -1 do if ev[i].kind == "profession_cast" then profCast = ev[i] break end end
  check("profession_cast OOC fishing", profCast and profCast.skill == "Fishing" and profCast.spellID == 7620)
  fire("CHAT_MSG_LOOT", "You receive loot: |cffffffff|Hitem:1::::::::1::::|h[FakeFish]|h|r")
  local profLoot
  for i = #ev, 1, -1 do if ev[i].kind == "profession_loot" then profLoot = ev[i] break end end
  check("profession_loot after fishing cast", profLoot and profLoot.skill == "Fishing" and type(profLoot.item) == "string")
  C_Spell.GetSpellName = oldSpellName
  loadedAddons.Matty7500Hunter = true
  _G.Matty7500Hunter = { lastDecision = { key = "STEADY_SHOT", pending = "AUTO" }, lastScores = { dps = 12 } }
  local mh = ns.SampleMH()
  check("MH lastDecision observed read-only", mh.status == "ok" and mh.decision.key == "STEADY_SHOT"
    and mh.scores.dps == 12 and mh.version == "test-0")
  local before = _G.Matty7500Hunter.lastDecision.key
  ns.SampleMH()
  check("MH global not modified", _G.Matty7500Hunter.lastDecision.key == before and _G.Matty7500Hunter.lastDecision.pending == "AUTO")
end

realprint("== 29b. quests: history re-read only when needed, abandoned never guessed")
do
  slash("snap")
  local function quests() return C().snapshot.quests end
  local function abandonedHas(id)
    for _, e in ipairs(quests().abandoned) do if e.id == id then return true end end
    return false
  end
  local function logState(id)
    for _, e in ipairs(quests().log) do if e.id == id then return e.state end end
  end
  check("state before: one quest in the log, 85 and 164 abandoned", #quests().log == 1 and abandonedHas(85) and abandonedHas(164))

  local calls = historyCalls
  questLog[1].objectives[1].text = "Okra: 3/3 (tick)"
  ns.PatchQuests()
  check("an objective tick does not re-read the turned-in history", historyCalls == calls and #quests().completed == 2)

  -- turn-in whose completed flag lags behind the quest leaving the log
  local stew = questLog[1]
  questLog = {}
  ns.PatchQuests()
  check("left the log, client says not completed: abandoned for now", abandonedHas(22) and historyCalls == calls + 1)
  completedQuests[#completedQuests + 1] = 22
  ns.PatchQuests()
  check("flag arrives later: the abandoned entry is dropped", not abandonedHas(22))
  check("...and the history is re-read, so the turn-in is in it", quests().completed[#quests().completed] == 22 and quests().completedTotal == 3)

  -- a quest that comes back was not abandoned for good
  questLog = { { title = "The People's Militia", level = 12, isHeader = false, questID = 164, isComplete = nil,
    objectives = { { text = "Defias: 0/8", type = "monster", finished = false, numFulfilled = 0, numRequired = 8 } } } }
  ns.PatchQuests()
  check("back in the log: no longer listed as abandoned", not abandonedHas(164) and logState(164) == "accepted" and abandonedHas(85))

  -- finished objectives are counted, kill counts are not summed across objectives
  questLog[2] = { title = "Boars and a Word", level = 11, isHeader = false, questID = 300, isComplete = nil,
    objectives = { { text = "Boars: 10/10", type = "monster", finished = true, numFulfilled = 10, numRequired = 10 },
                   { text = "Speak with the Marshal", type = "event", finished = false } } }
  ns.PatchQuests()
  check("10/10 plus an unfinished objective is in_progress, not ready", logState(300) == "in_progress")

  -- no quest id: the client cannot say whether it was turned in, so nothing is recorded
  questLog[3] = { title = "Nameless Errand", level = 5, isHeader = false, questID = nil, isComplete = nil, objectives = {} }
  ns.PatchQuests()
  check("no flag and no objectives: state unknown, not guessed", quests().log[3].state == "unknown")
  local nAb = #quests().abandoned
  questLog[3] = nil
  ns.PatchQuests()
  check("a quest without an id leaving the log is not called abandoned", #quests().abandoned == nAb)

  -- a client with no history API at all
  local flagged, all = C_QuestLog.IsQuestFlaggedCompleted, C_QuestLog.GetAllCompletedQuestIDs
  C_QuestLog.IsQuestFlaggedCompleted, C_QuestLog.GetAllCompletedQuestIDs = nil, nil
  questLog[2] = nil
  ns.PatchQuests()
  check("no history API: completed is nil and the vanished quest is not guessed abandoned",
    quests().completed == nil and not abandonedHas(300))
  C_QuestLog.IsQuestFlaggedCompleted, C_QuestLog.GetAllCompletedQuestIDs = flagged, all
  slash("snap")
  check("history is back after a full snapshot", type(quests().completed) == "table" and quests().completedTotal == 3)
end

realprint("== 29c. freshness honesty, talents patch, bags event")
do
  local snap = C().snapshot
  local zoneAt = snap.freshness.zone.observedAt
  clock = clock + 3 -- no frames in between: the periodic refresh must not run here
  local realZone, zone = GetRealZoneText, GetZoneText
  GetRealZoneText, GetZoneText = function() return nil end, function() return nil end
  ns.LogoutTouch()
  check("logout without a zone answer keeps the zone's observedAt", snap.zone == "Darkshore" and snap.freshness.zone.observedAt == zoneAt)
  GetRealZoneText, GetZoneText = realZone, zone
  ns.TakeSnapshot("manual")
  snap = C().snapshot

  local fresh = {}
  ns.SetFresh(fresh, "pet", "unavailable")
  check("a section never read has no observedAt", fresh.freshness.pet.status == "unavailable" and fresh.freshness.pet.observedAt == nil)

  -- talents: a change between snapshots must reach the fight context
  local rank = 1
  GetNumTalentTabs = function() return 1 end
  GetTalentTabInfo = function() return 1, "Beast Mastery", "", "icon", rank end
  GetNumTalents = function() return 1 end
  GetTalentInfo = function() return "Improved Aspect of the Hawk", "icon", 1, 1, rank, 5 end
  ns.TakeSnapshot("manual")
  snap = C().snapshot
  local ids = C().contextIds
  local t0, g0, talentsAt = ids.talents, ids.gear, snap.freshness.talents.observedAt
  check("talents read through the classic fallback", snap.talents.src == "GetNumTalentTabs" and #snap.talents.nodes == 1)
  advance(6)
  rank = 2
  fire("TRAIT_CONFIG_UPDATED"); advance(0.2)
  check("talent change patches the snapshot and the context hash",
    C().snapshot.talents.nodes[1].r == 2 and C().contextIds.talents ~= t0 and C().contextIds.gear == g0
      and C().snapshot.freshness.talents.observedAt > talentsAt
      and C().contextBlobs[C().contextIds.talents].kind == "talents")
  GetNumTalentTabs, GetTalentTabInfo, GetNumTalents, GetTalentInfo = nil, nil, nil, nil
  ns.PatchTalents()
  check("no talent API answering keeps the last good talents", C().snapshot.talents.src == "GetNumTalentTabs")

  -- bags: the burst event, once
  bagItems[0][2] = { id = 117, count = 3, link = "|Hitem:117|h[Tough Jerky]|h" }
  advance(11)
  fire("BAG_UPDATE_DELAYED"); advance(0.2)
  check("BAG_UPDATE_DELAYED refreshes the bags section", #C().snapshot.bags == 2 and C().snapshot.bags[2].id == 117)
  bagItems[0][2] = nil
end

realprint("== 29d. each fight keeps its own pre-pull context")
do
  slash("snap")
  local gA = C().contextIds.gear
  pull(620, "Ctx Boar A", 5, {})
  leave(true); advance(0.1)                       -- still secret: unread
  equipped[16] = "|Hitem:2506|h[Hornwood Recurve Bow of Testing]|h"
  ns.PatchEquipped()
  local gB = C().contextIds.gear
  check("gear swap changes the gear hash", gA ~= gB)
  pull(621, "Ctx Boar B", 6, {})
  leave(false); advance(0.6)
  local a, b
  for _, row in ipairs(C().fightSummary) do
    if row.name == "Ctx Boar A" then a = ns.FightsLoad(row.key) end
    if row.name == "Ctx Boar B" then b = ns.FightsLoad(row.key) end
  end
  check("fight read late keeps the gear it was pulled with", a and a.context.gear == gA and a.context.approx == nil)
  check("the next pull has the new gear", b and b.context.gear == gB and b.context.approx == nil)
  check("both gear blobs are kept", C().contextBlobs[gA] and C().contextBlobs[gB])
  check("tracked session carries its context across a /reload", C().fightTrack.sessions[621].ctx.gear == gB)

  -- a session this addon never saw start: catch-up read, marked approximate
  makeSession(622, "Ctx Boar C", 4, {})
  fire("PLAYER_ENTERING_WORLD", false, true); advance(4)
  local c
  for _, row in ipairs(C().fightSummary) do if row.name == "Ctx Boar C" then c = ns.FightsLoad(row.key) end end
  check("catch-up read is marked approx", c and c.context.approx == true and c.mh.approx == true)
end

realprint("== 29e. Matty Hunter read is passive and cannot throw")
do
  local touched = 0
  _G.Matty7500Hunter = setmetatable({ scores = { a = 1, bad = 0 / 0, big = math.huge, fn = function() end,
      long = ("x"):rep(500), hidden = S() } },
    { __index = function(_, k) touched = touched + 1 return { key = "FROM_METAMETHOD" } end })
  local mh = ns.SampleMH()
  check("__index of the MH table is never run", touched == 0 and mh.status == "unknown" and mh.decision == nil)
  check("only plain finite values are copied", mh.scores and mh.scores.a == 1 and mh.scores.bad == nil
    and mh.scores.big == nil and mh.scores.fn == nil and mh.scores.hidden == nil and #mh.scores.long == 200)
  _G.Matty7500Hunter = nil
  loadedAddons.Matty7500Hunter = nil
  local old = C_AddOns.IsAddOnLoaded
  C_AddOns.IsAddOnLoaded = function() error("boom") end
  local ok, res = pcall(ns.SampleMH)
  check("a failing addon query degrades, never throws", ok and type(res) == "table" and res.status ~= nil)
  C_AddOns.IsAddOnLoaded = old
end

realprint("== 29f. profession events: exact skill names, no duplicates, localised chat line")
do
  local ev = C().events
  local function countKind(kind) local n = 0 for _, e in ipairs(ev) do if e.kind == kind then n = n + 1 end end return n end
  C_SkillInfo = {
    GetNumSkillLines = function() return 3 end,
    GetSkillLineInfo = function(i)
      return ({ { name = "Arcane", rank = 1, maxRank = 1 }, { name = "Herbalism", rank = 40, maxRank = 75 },
                { name = "Fishing", rank = 76, maxRank = 150 } })[i]
    end,
  }
  slash("snap")
  local names = { [3044] = "Arcane Shot", [2366] = "Herb Gathering" }
  local oldSpellName = C_Spell.GetSpellName
  C_Spell.GetSpellName = function(id) return names[id] or oldSpellName(id) end
  local n0 = countKind("profession_cast")
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 3044)
  check("a class spell is not a profession cast (Arcane Shot vs the Arcane skill line)", countKind("profession_cast") == n0)
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 2366)
  check("Herb Gathering is filed under Herbalism", countKind("profession_cast") == n0 + 1 and ev[#ev].skill == "Herbalism")
  fire("UNIT_SPELLCAST_SUCCEEDED", "party1", nil, 2366)
  check("other units' casts are ignored", countKind("profession_cast") == n0 + 1)
  C_Spell.GetSpellName = oldSpellName

  local u0 = countKind("skill_up")
  C_SkillInfo.GetSkillLineInfo = function(i)
    return ({ { name = "Arcane", rank = 1, maxRank = 1 }, { name = "Herbalism", rank = 41, maxRank = 75 },
              { name = "Fishing", rank = 76, maxRank = 150 } })[i]
  end
  advance(3)
  fire("SKILL_LINES_CHANGED"); advance(0.2)
  check("skill-up from the skill list", countKind("skill_up") == u0 + 1 and ev[#ev].skill == "Herbalism" and ev[#ev].rank == 41 and ev[#ev].from == 40)
  fire("CHAT_MSG_SKILL", "Your skill in Herbalism has increased to 41.")
  check("the chat line for the same rank is not logged twice", countKind("skill_up") == u0 + 1)
  C_SkillInfo = nil
end

do
  -- A fresh copy of the addon core on a German client: the chat line is parsed from SKILL_RANK_UP.
  local ns2 = {}
  local savedDB = HelloForeverDB
  HelloForeverDB = { characters = {} }
  SKILL_RANK_UP = "Eure Fertigkeit '%s' hat sich auf %d erhöht."
  assert(loadfile(ADDON_DIR .. "/Core.lua"))("HelloForever", ns2)
  assert(loadfile(ADDON_DIR .. "/Snapshot.lua"))("HelloForever", ns2)
  ns2.InitDB()
  ns2.eventFrame.scripts.OnEvent(ns2.eventFrame, "CHAT_MSG_SKILL", "Eure Fertigkeit 'Angeln' hat sich auf 77 erhöht.")
  local ev2 = HelloForeverDB.characters[CK].events
  local last = ev2[#ev2]
  check("localised skill-up line parsed through SKILL_RANK_UP", last and last.kind == "skill_up" and last.skill == "Angeln" and last.rank == 77)
  HelloForeverDB = savedDB
  SKILL_RANK_UP = nil
end

realprint("== 30. logout")
do
  local l0 = #logCalls
  fire("PLAYER_LOGOUT")
  check("combat log mode off: logging left alone at logout", #logCalls == l0)
  local snap = C().snapshot
  check("logout keeps the last good snapshot", snap.reason == "logout" and snap.money == P.money and snap.level == 10 and snap.addonVersion == TOC_VERSION)
  local ev = C().events
  check("event log has the logout", ev[#ev].kind == "logout" and #ev <= 500)
end
realprint("   widgets created: " .. widgetCount)

local fails = 0
for _, l in ipairs(results) do if l:sub(1, 4) == "FAIL" then fails = fails + 1 end end
realprint(("== %d checks, %d failed"):format(#results, fails))
os.exit(fails == 0 and 0 or 1)
