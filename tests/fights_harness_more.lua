-- More harness sections for the reset / read-marker fix (0.7.1).
--
--   luajit tests/fights_harness_more.lua ./HelloForever <out_SV.lua> <out_truth.json>
--
-- The sections below need the mock client of fights_harness_v4.lua. That file holds the failing
-- test of a fix and stays as it was committed, so these sections live here and are spliced into
-- its source (before its last section) when this file runs. It runs the whole harness plus
-- these sections, and exits non-zero on any failure.
local path = (arg[0] or "tests/fights_harness_more.lua"):gsub("fights_harness_more%.lua$", "fights_harness_v4.lua")
local f = assert(io.open(path, "r"))
local src = f:read("*a")
f:close()
local marker = 'realprint("== 30. logout")'
local at = assert(src:find(marker, 1, true), "the harness has no logout section to splice before")

local more = [==[
-- After a reset every listed session is read again, over several frames: wait for the reader.
local function settle()
  for _ = 1, 60 do
    advance(0.5)
    if ns.fightStatus.state == "idle" then return end
  end
end

realprint("== 16f. after a reset, only a proven identical session is 'nothing new'")
do
  fightOnce(730, "Coll Boar", 12, {})
  local key, n0 = lastSummary().key, count()
  fire("DAMAGE_METER_RESET")
  slash("fights read"); settle()
  check("the same session, listed after a reset, is not filed again", count() == n0)
  -- another fight on the id: same name, length, totals and row counts; other enemy, other spell
  fire("DAMAGE_METER_RESET")
  makeSession(730, "Coll Boar", 12, {})
  sessions[730].T[10].sources[1].sourceGUID = "Creature-0-9-OTHER"
  sessions[730].T[0].spells[1][1].spellID = 76
  slash("fights read"); settle()
  local s = lastSummary()
  check("another fight with the same totals on a kept id is stored, not dropped", count() == n0 + 1 and s.key ~= key)
  local rec = ns.FightsLoad(s.key)
  check("...under its own key, the earlier record intact", rec and rec.rekeyOf == key and ns.FightsLoad(key) ~= nil)
  -- a marker written before 0.7.1 has no fingerprint: the record is stored rather than dropped
  fightOnce(733, "Old Marker Boar", 12, {})
  local n1 = count()
  C().fightTrack.done[733].fp = nil
  fire("DAMAGE_METER_RESET")
  slash("fights read"); settle()
  check("a marker without a fingerprint proves nothing: the session is stored again", count() == n1 + 1)
  slash("fights read"); settle()
  fire("DAMAGE_METER_RESET"); slash("fights read"); settle()
  check("...once: the new marker has a fingerprint", count() == n1 + 1)
  sessions[730], sessions[733] = nil, nil
end

realprint("== 16f2. the comparison is the whole meter content, in any row order")
do
  -- One fight, a reset, then the same session again with `mutate` applied. `prep` shapes both
  -- reads. Returns how many fights the second read added.
  local function kept(sid, name, mutate, o, prep)
    pull(sid, name, 12, o or {})
    if prep then prep(sessions[sid].T) end
    leave(false); advance(0.5); settle()
    local n0 = count()
    fire("DAMAGE_METER_RESET")
    makeSession(sid, name, 12, o or {})
    if prep then prep(sessions[sid].T) end
    mutate(sessions[sid].T)
    slash("fights read"); settle()
    sessions[sid] = nil
    return count() - n0
  end
  local function noGuid(T) T[10].sources[1].sourceGUID = nil end
  check("a session without a source GUID, unchanged, is the same fight", kept(739, "Fp NoGuid", function() end, nil, noGuid) == 0)
  check("another creature id on a source without a GUID is another fight", kept(740, "Fp Creature", function(T)
    T[10].sources[1].sourceCreatureID = 9999                 -- 2163 before; nothing else changes
  end, nil, noGuid) == 1)
  check("another overkill on a spell row is another fight", kept(741, "Fp Overkill", function(T)
    T[0].spells[1][1].overkillAmount = 77
  end) == 1)
  check("another target in a spell's details is another fight", kept(742, "Fp Target", function(T)
    T[7].spells[1][1].combatSpellDetails.unitName = "Someone Else"
  end) == 1)
  check("the same rows in another order are the same fight", kept(743, "Fp Order", function(T)
    local rows = T[0].spells[1]
    rows[1], rows[#rows] = rows[#rows], rows[1]
  end, { extraSpells = 3 }) == 0)
  local twoMobs = { mobs = { { "Creature-0-1-A", 2163, "Fp Sources" }, { "Creature-0-1-B", 2164, "Fp Other" } } }
  -- two sources with different breakdowns of the same total: only the pairing tells them apart
  local function distinct(T) T[10].spells[2][1].spellID = 76 end
  check("the same sources in another order (with their breakdowns) are the same fight", kept(744, "Fp Sources", function(T)
    local s, b = T[10].sources, T[10].spells
    s[1], s[2] = s[2], s[1]
    b[1], b[2] = b[2], b[1]
  end, twoMobs, distinct) == 0)
  check("a breakdown that moved to the other source is another fight", kept(745, "Fp Sources", function(T)
    local b = T[10].spells
    b[1], b[2] = b[2], b[1]                                   -- the sources stay; nothing else changes
  end, twoMobs, distinct) == 1)
end

realprint("== 16g. a reset makes a session that had stopped changing readable again")
do
  fightOnce(731, "Stale Boar", 12, {})
  local key = lastSummary().key
  for _ = 1, 4 do fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 2, 731); advance(1.5) end
  check("the session is left alone after three empty re-reads", (C().fightTrack.done[731].stale or 0) >= 3)
  fire("DAMAGE_METER_RESET")
  slash("fights read"); settle()
  makeSession(731, "Stale Boar", 12, { heal = 77 })      -- same length, more data
  fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 2, 731); advance(1.5); settle()
  check("a change after the reset is captured as a new revision", lastSummary().key == key and lastSummary().rev == 2 and lastSummary().heal == 77)
  sessions[731] = nil
end

realprint("== 16h. a marker whose session is gone expires after the hour without any read")
do
  fightOnce(732, "Gone Boar", 12, {})
  sessions[732] = nil
  fire("DAMAGE_METER_RESET")
  check("the marker is kept at first", C().fightTrack.done[732] ~= nil)
  advance(3700)                                          -- no read, no meter event
  check("...and gone after an hour", C().fightTrack.done[732] == nil)
end


realprint("== 16i. fight baseline: the record (docs/specs/93.md, step 1)")
do
  -- Missing before the build: then every check below fails (each one needs a stored fight).
  local BL = ns.FightsBaseline or function() end
  local LV = P.level
  local function fightKeys(c, bkey)
    local e = c.baseline and c.baseline[bkey]
    if type(e) ~= "table" or type(e.fights) ~= "table" then return "none" end
    local out = {}
    for i, fx in ipairs(e.fights) do out[i] = fx.key end
    return table.concat(out, ",")
  end
  local function where(c, key) -- the baseline keys that hold the fight `key`
    local out = {}
    for bk, e in pairs(c.baseline or {}) do
      for _, fx in ipairs(e.fights) do if fx.key == key then out[#out + 1] = bk end end
    end
    table.sort(out)
    return table.concat(out, ",")
  end
  local function fightOf(c, key)
    for _, e in pairs(c.baseline or {}) do
      for _, fx in ipairs(e.fights) do if fx.key == key then return fx end end
    end
  end
  local function nkeys(c) local n = 0 for _ in pairs(c.baseline or {}) do n = n + 1 end return n end

  -- Through the reader: real fights of the mock client.
  C().baseline = nil
  local boar = { { "Creature-0-1-900", 4001, "Base Boar" } }
  local B1 = "4001:" .. LV
  fightOnce(900, "Base Boar", 12, { mobs = boar })
  local k1 = lastSummary().key
  local f1 = fightOf(C(), k1)
  check("baseline: a fight with one enemy is stored under <creature id>:<start level>, with its key",
    fightKeys(C(), B1) == k1 and C().baseline[B1].name == "Base Boar")
  check("baseline: ...with dur, dps, taken and died from the record",
    f1 and f1.dur == 12 and f1.dps == 50 and f1.taken == 40 and f1.died == false)
  fightOnce(901, "Base Pair", 12, { mobs = { { "Creature-0-1-901a", 4001, "Base Boar" }, { "Creature-0-1-901b", 4002, "Base Wolf" } } })
  local k2 = lastSummary().key
  check("baseline: a fight with two enemies is not stored; the one-enemy fight stays",
    fightKeys(C(), B1) == k1 and where(C(), k2) == "" and C().baseline["4002:" .. LV] == nil)
  makeSession(900, "Base Boar", 15, { mobs = boar })
  fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 2, 900); advance(1.5)
  check("baseline: a revision that changes dur replaces the stored fight",
    ns.FightsLoad(k1).rev == 2 and fightKeys(C(), B1) == k1 and (fightOf(C(), k1) or {}).dur == 15)
  makeSession(900, "Base Boar", 15, { mobs = boar, died = true })
  fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 2, 900); advance(1.5)
  check("baseline: a revision that adds a death replaces the stored fight",
    ns.FightsLoad(k1).rev == 3 and fightKeys(C(), B1) == k1 and (fightOf(C(), k1) or {}).died == true)
  advance(2)
  fightOnce(902, "Base Boar", 12, { mobs = { { "Creature-0-1-902", 4001, "Base Boar" } } })
  local k3 = lastSummary().key
  makeSession(900, "Base Boar", 15, { mobs = { boar[1], { "Creature-0-1-900b", 4002, "Base Wolf" } }, died = true })
  fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 2, 900); advance(1.5)
  check("baseline: a revision that adds a second enemy removes the stored fight",
    ns.FightsLoad(k1).rev == 4 and fightKeys(C(), B1) == k3 and where(C(), k1) == "")
  -- a level up after the fight, before its read: the key keeps the start level
  advance(2)
  pull(903, "Late Boar", 12, { mobs = { { "Creature-0-1-903", 4003, "Late Boar" } } })
  leave(true); advance(0.6)
  P.level = LV + 1
  secretMode = false; restrictState = 0
  fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0); advance(0.5)
  local late = lastSummary().key
  P.level = LV
  check("baseline: a level up between the fight and its read keeps the start level",
    ns.FightsLoad(late).lvl == LV + 1 and fightKeys(C(), "4003:" .. LV) == late)
  -- the game check, here: five fights with one kind of enemy
  C().baseline = nil
  local five = {}
  for i = 1, 5 do
    advance(2)
    fightOnce(910 + i, "Five Boar", 10 + i, { mobs = { { "Creature-0-1-91" .. i, 4005, "Five Boar" } } })
    five[i] = lastSummary().key
  end
  check("baseline: five fights with one kind of enemy give that key with five fights, in start order",
    fightKeys(C(), "4005:" .. LV) == table.concat(five, ","))
  for sid = 900, 915 do sessions[sid] = nil end

  -- Hand-made records, written from the spec (section 1, decisions 2, 3 and 5).
  local INST = ns.InstallId()
  local function hand(start, o)
    o = o or {}
    local enemies = {}
    for _, cid in ipairs(o.cids or { 5001 }) do
      enemies[#enemies + 1] = { sourceCreatureID = cid ~= 0 and cid or nil, name = "Hand Boar" }
    end
    local rec = {
      key = ns.MakeFightKey(INST, start, o.sid or 1, 1), start = start, rev = o.rev or 1, dur = 12, lvl = 14,
      name = "Hand Boar", pull = { start = { level = 14 }, stop = { level = 14 } },
      types = {
        DamageDone = { combatSources = { { isLocalPlayer = true, totalAmount = 600, amountPerSecond = 999 } } },
        DamageTaken = { combatSources = { { isLocalPlayer = true, totalAmount = 210 } } },
        Deaths = { combatSources = {} },
        EnemyDamageTaken = { combatSources = enemies },
      },
    }
    if o.mut then o.mut(rec) end
    return rec
  end
  local H = "5001:14"
  -- Where `rec` is stored, next to a counted control fight; nil when the control is not stored.
  local function stored(rec)
    local c = {}
    local ctl = hand(500, { sid = 99 })
    BL(c, ctl)
    BL(c, rec)
    if where(c, ctl.key) ~= H then return nil end
    return where(c, rec.key)
  end
  do
    local c, a = {}, hand(1000)
    BL(c, a)
    local fa = fightOf(c, a.key)
    check("baseline (hand-made): dps is the DamageDone total divided by dur, not amountPerSecond",
      fightKeys(c, H) == a.key and fa.dps == 50 and fa.dur == 12 and fa.taken == 210 and fa.died == false)
  end
  check("baseline: two enemies, not counted", stored(hand(1000, { cids = { 5001, 5002 } })) == "")
  check("baseline: one enemy without a creature id, not counted", stored(hand(1000, { cids = { 0 } })) == "")
  check("baseline: a failed or missing EnemyDamageTaken, not counted",
    stored(hand(1000, { mut = function(r) r.types.EnemyDamageTaken = { err = "x" } end })) == ""
    and stored(hand(1000, { mut = function(r) r.types.EnemyDamageTaken = nil end })) == "")
  check("baseline: a level up between the fight and its read keeps the start level",
    stored(hand(1000, { mut = function(r) r.lvl = 15 end })) == H)
  check("baseline: a level up inside the pull block, not counted",
    stored(hand(1000, { mut = function(r) r.pull.stop.level = 15 end })) == "")
  check("baseline: no stop level and another read level (a level up), not counted",
    stored(hand(1000, { mut = function(r) r.pull.stop = nil; r.lvl = 15 end })) == ""
    and stored(hand(1000, { mut = function(r) r.pull.stop = {}; r.lvl = 15 end })) == "")
  check("baseline: no stop level and an equal read level, counted",
    stored(hand(1000, { mut = function(r) r.pull.stop = nil end })) == H
    and stored(hand(1000, { mut = function(r) r.pull.stop = {} end })) == H)
  check("baseline: no stop level and no read level, not counted",
    stored(hand(1000, { mut = function(r) r.pull.stop = nil; r.lvl = nil end })) == "")
  check("baseline: no reliable start level (approx, no level, no pull block), not counted",
    stored(hand(1000, { mut = function(r) r.pull.approx = true end })) == ""
    and stored(hand(1000, { mut = function(r) r.pull.start.level = nil end })) == ""
    and stored(hand(1000, { mut = function(r) r.pull = nil end })) == "")
  do
    local c, died = {}, {}
    local deaths = {
      { combatSources = {} },                                                   -- lived: no row
      { combatSources = { { isLocalPlayer = true, deathRecapID = 0 } } },       -- lived: recap 0
      { combatSources = { { isLocalPlayer = true, deathRecapID = 88 } } },      -- died
      false,                                                                    -- no Deaths type
      { err = "mock failure" },                                                 -- a failed read
      { none = true },                                                          -- no data
    }
    for i, d in ipairs(deaths) do
      BL(c, hand(1000 + i, { sid = i, mut = function(r) r.types.Deaths = d or nil end }))
    end
    local e = c.baseline and c.baseline[H]
    for i, fx in ipairs(e and e.fights or {}) do died[i] = tostring(fx.died) end
    check("baseline: deaths known (lived, died) and unknown (no type, err, none), mixed in one key",
      table.concat(died, ",") == "false,false,true,nil,nil,nil")
  end
  do
    local recs = {
      hand(1001, { sid = 1, mut = function(r) r.types.DamageDone = { err = "x" }; r.types.DamageTaken = nil end }),
      hand(1002, { sid = 2, mut = function(r) r.dur = nil end }),
      hand(1003, { sid = 3, mut = function(r) r.dur = 0 end }),
      hand(1004, { sid = 4, mut = function(r)
        r.types.DamageDone.combatSources[1].totalAmount = nil
        r.types.DamageTaken.combatSources[1].totalAmount = -1
      end }),
    }
    local c = {}
    for _, r in ipairs(recs) do BL(c, r) end
    local g = {}
    for i, r in ipairs(recs) do g[i] = fightOf(c, r.key) or {} end
    check("baseline: missing and failed numbers are stored as missing, never as 0",
      fightKeys(c, H) == recs[1].key .. "," .. recs[2].key .. "," .. recs[3].key .. "," .. recs[4].key
      and g[1].dps == nil and g[1].taken == nil and g[1].dur == 12
      and g[2].dur == nil and g[2].dps == nil and g[2].taken == 210
      and g[3].dur == nil and g[3].dps == nil
      and g[4].dps == nil and g[4].taken == nil and g[4].dur == 12)
  end
  do
    local c, a, b = {}, hand(1000), hand(2000, { sid = 2 })
    BL(c, a); BL(c, b)
    BL(c, hand(1000, { rev = 2, mut = function(r) r.pull.approx = true end }))
    check("baseline: a revision whose start level is no longer reliable removes the stored fight", fightKeys(c, H) == b.key)
  end
  do
    local failed = function(r) r.types.EnemyDamageTaken = { err = "x" } end
    local c, a, b = {}, hand(1000), hand(2000, { sid = 2 })
    BL(c, hand(1000, { mut = failed })); BL(c, b); BL(c, hand(1000, { rev = 2 }))
    check("baseline: a revision after a failed read goes into a key with one later fight, before it",
      fightKeys(c, H) == a.key .. "," .. b.key)
    c = {}
    BL(c, hand(1000, { mut = failed })); BL(c, hand(1000, { rev = 2 }))
    check("baseline: ...and into an empty key", fightKeys(c, H) == a.key)
    c = { baselineResetAt = 1500 }
    local d = hand(1600, { sid = 3 })
    BL(c, hand(1000, { rev = 2 })); BL(c, d)
    check("baseline: after a reset, a revision of a fight started before it is left out", fightKeys(c, H) == d.key)
    c = {}
    local ten = {}
    for i = 1, 10 do local r = hand(2000 + i, { sid = i }); BL(c, r); ten[i] = r.key end
    BL(c, hand(1000, { sid = 50, rev = 2 }))
    check("baseline: a revision older than the ten kept falls out", fightKeys(c, H) == table.concat(ten, ","))
  end
  do
    local c, x, y, z = {}, hand(3000, { sid = 3 }), hand(1000, { sid = 1 }), hand(2000, { sid = 2 })
    BL(c, x); BL(c, y); BL(c, z)
    BL(c, hand(2000, { sid = 2, rev = 2, mut = function(r) r.dur = 20 end }))
    check("baseline: the fights stay in start order, also after a revision",
      fightKeys(c, H) == y.key .. "," .. z.key .. "," .. x.key and fightOf(c, z.key).dur == 20)
  end
  do
    local c, keys = {}, {}
    for i = 1, 11 do local r = hand(1000 + i, { sid = i }); BL(c, r); keys[i] = r.key end
    check("baseline: the ring keeps 10; the eleventh fight pushes out the oldest",
      fightKeys(c, H) == table.concat(keys, ",", 2, 11))
  end
  do
    local c = {}
    for i = 1, 200 do BL(c, hand(10000 + i, { sid = i, cids = { 6000 + i } })) end
    local full = nkeys(c)
    BL(c, hand(30000, { sid = 300, cids = { 6001 } }))   -- 6001 fought again: now 6002 is the oldest
    BL(c, hand(30001, { sid = 301, cids = { 7000 } }))
    check("baseline: at most 200 keys; a new key pushes out the key with the oldest t",
      full == 200 and nkeys(c) == 200 and c.baseline["7000:14"] ~= nil and c.baseline["6002:14"] == nil
      and fightKeys(c, "6001:14") ~= "none" and c.baseline["6003:14"] ~= nil)
  end
  do
    local c = {}
    BL(c, hand(1000, { cids = { 5001, 5002 } }))
    local afterNot = c.baseline and next(c.baseline) == nil
    BL(c, hand(2000, { sid = 2 }))
    BL(c, hand(2000, { sid = 2, rev = 2, cids = { 5001, 5002 } }))
    check("baseline: an empty table stays empty; removing the last fight of a key leaves no empty key",
      afterNot == true and type(c.baseline) == "table" and next(c.baseline) == nil)
  end
  do
    -- the size of a full table: 200 keys of 10 fights, every number known
    collectgarbage("collect")
    local m0 = collectgarbage("count")
    local c = {}
    for k = 1, 200 do
      for i = 1, 10 do
        BL(c, hand(100000 + k * 100 + i, { sid = k * 100 + i, cids = { 8000 + k },
          mut = function(r) r.dur = 12.345; r.types.DamageTaken.combatSources[1].totalAmount = 1234 end }))
      end
    end
    collectgarbage("collect")
    local kb = (collectgarbage("count") - m0)
    local bytes = #ser(c.baseline, "")
    realprint(("    baseline, 200 keys x 10 fights: %.0f KB on disk (as the client writes it), %.0f KB in Lua memory"):format(bytes / 1024, kb))
    check("baseline: a full table (200 keys x 10 fights) is kept, and stays under 1 MB on disk",
      nkeys(c) == 200 and fightKeys(c, "8001:14") ~= "none" and #c.baseline["8001:14"].fights == 10 and bytes < 1024 * 1024)
  end
end
]==]

local chunk = assert(loadstring(src:sub(1, at - 1) .. more .. src:sub(at), "=fights_harness_v4+more"))
chunk(...)
