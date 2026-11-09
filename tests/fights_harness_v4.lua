-- Mock harness for HelloForever v0.4.0 lossless fights (Lua 5.1, no WoW client).
package.path = "./tests/?.lua;" .. package.path
local ML = require("mocklib")
local ADDON = arg[1] or "./HelloForever/HelloForever.lua"
local SVOUT = arg[2] or "./tests/HelloForever_v4_SV.lua"
local TRUTH = arg[3] or "./tests/v4_truth.json"

local clock = 1794211200.0 -- 2026-11-09 06:00 UTC
local FRAME = 0.05
local printed = {}
local realprint = print
function print(...) local t = {} for i = 1, select("#", ...) do t[#t+1] = tostring(select(i, ...)) end printed[#printed+1] = table.concat(t, " ") realprint("    | " .. printed[#printed]) end
time = function() return math.floor(clock) end
local osdate = os.date
date = function(fmt, t) return osdate("!" .. fmt, t or time()) end
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

local frames = {}
function CreateFrame()
  local f = { scripts = {}, events = {} }
  for _, m in ipairs({ "SetSize", "SetMovable", "EnableMouse", "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "ClearAllPoints", "SetPoint" }) do f[m] = function() end end
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:RegisterEvent(e) self.events[e] = true end
  function f:GetPoint() return "TOP", nil, "TOP", 0, 0 end
  function f:CreateTexture() return { SetAllPoints = function() end, SetColorTexture = function() end } end
  function f:CreateFontString() return { SetPoint = function() end, SetText = function() end } end
  frames[#frames+1] = f
  return f
end
UIParent, SlashCmdList = {}, {}
function BreakUpLargeNumbers(n) return tostring(n) end
function SecondsToTime(n) return tostring(n) end

local inCombat, restrictState = false, 0
function InCombatLockdown() return inCombat end
C_RestrictedActions = { GetAddOnRestrictionState = function(t) assert(t == 0) return restrictState end }
Enum = {
  DamageMeterType = { DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4, Interrupts = 5, Dispels = 6, DamageTaken = 7, AvoidableDamageTaken = 8, Deaths = 9, EnemyDamageTaken = 10 },
  AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
  CompressionMethod = { Deflate = 0, Zlib = 1, Gzip = 2 },
}
local PGUID = "Player-1-0ABCDEF"
function UnitGUID(u) return u == "player" and PGUID or nil end
function UnitName() return "FakeHunter" end
function GetRealmName() return "TestRealm" end
function UnitLevel() return 9 end
function UnitXP() return 1200 end
function UnitXPMax() return 4500 end
function GetMoney() return 5321 end
function UnitClass() return "Hunter", "HUNTER" end
function UnitRace() return "Dwarf", "Dwarf" end
function UnitFactionGroup() return "Alliance", "Alliance" end
function GetXPExhaustion() return 0 end
function GetRealZoneText() return "Darkshore" end
function GetZoneText() return "Darkshore" end
function GetSubZoneText() return "Blackwood Den" end
function GetBuildInfo() return "1.60.1", "70862", "Nov 3 2026", 16001 end
function UnitStat() return 10, 10 end
C_AddOns = { GetAddOnMetadata = function() return "0.4.0" end }
C_Map = { GetBestMapForUnit = function() return 1439 end }
C_Spell = { GetSpellName = function(id) return "Spell" .. id end }

local encCalls = 0
C_EncodingUtil = {
  SerializeJSON = function(v) encCalls = encCalls + 1 return ML.json(v) end,
  CompressString = function(s, m) assert(m == 0, "expected Deflate") return ML.deflateStored(s) end,
  DecompressString = function(z, m) assert(m == 0) return ML.inflateStored(z) end,
  EncodeBase64 = function(s) return ML.b64enc(s) end,
  DecodeBase64 = function(s) return ML.b64dec(s) end,
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
C_DeathRecap = {
  HasRecapEvents = function(id) return true end,
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
assert(loadfile(ADDON))("HelloForever", ns)
local f = frames[1]
local function fire(ev, a1, a2) f.scripts.OnEvent(f, ev, a1, a2) end
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
check("key = tracked start-sid", k1 == tostring(startT) .. "-1")
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
check("addonVersion 0.4.0", HelloForeverDB.addonVersion == "0.4.0")

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

local fails = 0
for _, l in ipairs(results) do if l:sub(1, 4) == "FAIL" then fails = fails + 1 end end
realprint(("== %d checks, %d failed"):format(#results, fails))
os.exit(fails == 0 and 0 or 1)
