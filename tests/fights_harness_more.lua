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
  local fightOnceRaw = fightOnce
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

  -- Through the reader: real fights of the mock client. Read what earlier sections left first.
  slash("fights read"); settle()
  C().baseline = nil
  local function fightOnce(...) fightOnceRaw(...); settle() end
  local boar = { { "Creature-0-1-960", 4001, "Base Boar" } }
  local B1 = "4001:" .. LV
  fightOnce(960, "Base Boar", 12, { mobs = boar })
  local k1 = lastSummary().key
  local f1 = fightOf(C(), k1)
  check("baseline: a fight with one enemy is stored under <creature id>:<start level>, with its key",
    fightKeys(C(), B1) == k1 and C().baseline[B1].name == "Base Boar")
  check("baseline: ...with dur, dps, taken and died from the record",
    f1 and f1.dur == 12 and f1.dps == 50 and f1.taken == 40 and f1.died == false)
  fightOnce(961, "Base Pair", 12, { mobs = { { "Creature-0-1-961a", 4001, "Base Boar" }, { "Creature-0-1-961b", 4002, "Base Wolf" } } })
  local k2 = lastSummary().key
  check("baseline: a fight with two enemies is not stored; the one-enemy fight stays",
    fightKeys(C(), B1) == k1 and where(C(), k2) == "" and C().baseline["4002:" .. LV] == nil)
  makeSession(960, "Base Boar", 15, { mobs = boar })
  fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 2, 960); advance(1.5); settle()
  check("baseline: a revision that changes dur replaces the stored fight",
    ns.FightsLoad(k1).rev == 2 and fightKeys(C(), B1) == k1 and (fightOf(C(), k1) or {}).dur == 15)
  makeSession(960, "Base Boar", 15, { mobs = boar, died = true })
  fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 2, 960); advance(1.5); settle()
  check("baseline: a revision that adds a death replaces the stored fight",
    ns.FightsLoad(k1).rev == 3 and fightKeys(C(), B1) == k1 and (fightOf(C(), k1) or {}).died == true)
  advance(2)
  fightOnce(962, "Base Boar", 12, { mobs = { { "Creature-0-1-962", 4001, "Base Boar" } } })
  local k3 = lastSummary().key
  makeSession(960, "Base Boar", 15, { mobs = { boar[1], { "Creature-0-1-960b", 4002, "Base Wolf" } }, died = true })
  fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 2, 960); advance(1.5); settle()
  check("baseline: a revision that adds a second enemy removes the stored fight",
    ns.FightsLoad(k1).rev == 4 and fightKeys(C(), B1) == k3 and where(C(), k1) == "")
  -- a level up after the fight, before its read: the key keeps the start level
  advance(2)
  pull(963, "Late Boar", 12, { mobs = { { "Creature-0-1-963", 4003, "Late Boar" } } })
  leave(true); advance(0.6)
  P.level = LV + 1
  secretMode = false; restrictState = 0
  fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0); advance(0.5); settle()
  local late = lastSummary().key
  P.level = LV
  check("baseline: a level up between the fight and its read keeps the start level",
    ns.FightsLoad(late).lvl == LV + 1 and fightKeys(C(), "4003:" .. LV) == late)
  -- the game check, here: five fights with one kind of enemy
  C().baseline = nil
  local five = {}
  for i = 1, 5 do
    advance(2)
    fightOnce(970 + i, "Five Boar", 10 + i, { mobs = { { "Creature-0-1-97" .. i, 4005, "Five Boar" } } })
    five[i] = lastSummary().key
  end
  check("baseline: five fights with one kind of enemy give that key with five fights, in start order",
    fightKeys(C(), "4005:" .. LV) == table.concat(five, ","))
  for sid = 960, 975 do sessions[sid] = nil end

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
    -- t follows a removal: the key's latest fight leaves, so its t goes back to the one before
    local c = {}
    BL(c, hand(100, { sid = 1, cids = { 6001 } })); BL(c, hand(300, { sid = 3, cids = { 6001 } }))
    BL(c, hand(200, { sid = 2, cids = { 6002 } }))
    for i = 3, 200 do BL(c, hand(1000 + i, { sid = 10 + i, cids = { 6000 + i } })) end
    BL(c, hand(300, { sid = 3, rev = 2, cids = { 6001, 9999 } }))   -- fight 300 no longer counts
    BL(c, hand(5000, { sid = 500, cids = { 7000 } }))
    check("baseline: after its latest fight is removed, a key's t is its new latest start (the cap removes it first)",
      nkeys(c) == 200 and c.baseline["6001:14"] == nil and fightKeys(c, "6002:14") ~= "none" and c.baseline["7000:14"] ~= nil)
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

realprint("== 16j. fight baseline: the line after a fight (docs/specs/93.md, step 2)")
do
  -- Missing before the build: BL returns nothing and there is no line, so every check fails.
  local BL = ns.FightsBaseline or function() end
  local LINE = ns.BaselineLine or function() return "" end
  local DOT = " \194\183 "   -- " · " (U+00B7) between the parts of the line
  local INST = ns.InstallId()
  -- A hand-made record from the spec (section 1, decision 5): one enemy, level 14.
  -- o.dur, o.dmg (DamageDone total), o.taken: false leaves the number out; o.died: true, false or nil (unknown).
  local function rec(start, o)
    o = o or {}
    local function pick(v, default) if v == nil then return default end return v or nil end
    local r = {
      key = ns.MakeFightKey(INST, start, o.sid or start, 1), start = start, rev = 1, dur = pick(o.dur, 12), lvl = 14,
      name = "Hand Boar", pull = { start = { level = 14 }, stop = { level = 14 } },
      types = {
        DamageDone = { combatSources = { { isLocalPlayer = true, totalAmount = pick(o.dmg, 600) } } },
        DamageTaken = { combatSources = { { isLocalPlayer = true, totalAmount = pick(o.taken, 210) } } },
        EnemyDamageTaken = { combatSources = { { sourceCreatureID = 5001, name = "Hand Boar" } } },
      },
    }
    if o.died == true then
      r.types.Deaths = { combatSources = { { isLocalPlayer = true, deathRecapID = 88 } } }
    elseif o.died == false then
      r.types.Deaths = { combatSources = {} }
    end
    return r
  end
  -- Store `earlier` (a list of option tables) in a new character table, then return the line for `last`.
  local function lineAfter(earlier, last)
    local c = {}
    for i, o in ipairs(earlier) do BL(c, rec(1000 + i, o)) end
    local bk, name, fight, prev = BL(c, rec(5000, last))
    if not bk then return nil end
    return LINE(bk, name, fight, prev)
  end
  local function durs(list, extra)
    local out = {}
    for i, d in ipairs(list) do
      local o = { dur = d }
      for k, v in pairs(extra and extra[i] or {}) do o[k] = v end
      out[i] = o
    end
    return out
  end
  local H = "Hand Boar (lvl 14): "

  local got = lineAfter(durs({ 10, 20, 30 }, { { taken = 100 }, { taken = 300 }, { taken = 200 } }), {})
  check("baseline line: the usual values are the medians of the earlier fights (odd count)",
    got == H .. "12 s, usual 20 s" .. DOT .. "50 dps, usual 30" .. DOT .. "taken 210, usual 200 (3 fights)")
  got = lineAfter(durs({ 10, 20, 30, 40 }, { { taken = 100 }, { taken = 200 }, { taken = 300 }, { taken = 400 } }), {})
  check("baseline line: an even count gives the mean of the two middle values",
    got == H .. "12 s, usual 25 s" .. DOT .. "50 dps, usual 25" .. DOT .. "taken 210, usual 250 (4 fights)")
  check("baseline line: fewer than 3 earlier fights: first fights, N so far (N counts this fight)",
    lineAfter(durs({ 10, 20 }), {}) == H .. "first fights, 3 so far"
    and lineAfter({}, {}) == H .. "first fights, 1 so far")
  got = lineAfter(durs({ 10, 20, 30, 40, 50 }, { { taken = 100 }, { taken = false }, { taken = 500 }, { taken = false }, { taken = 300 } }), {})
  check("baseline line: a number known in only some earlier fights has the median of those (3 of 5)",
    got == H .. "12 s, usual 30 s" .. DOT .. "50 dps, usual 20" .. DOT .. "taken 210, usual 300 (5 fights)")
  got = lineAfter(durs({ 10, 20, 30, 40 }, { { taken = 100 }, { taken = false }, { taken = false }, { taken = 400 } }), {})
  check("baseline line: a number that fewer than 3 earlier fights know is shown without its usual value",
    got == H .. "12 s, usual 25 s" .. DOT .. "50 dps, usual 25" .. DOT .. "taken 210 (4 fights)")
  got = lineAfter(durs({ 10, 20, 30 }, { { dmg = false }, { dmg = false }, {} }), { taken = false })
  check("baseline line: only dps is not comparable, and this fight's unknown number is left out",
    got == H .. "12 s, usual 20 s" .. DOT .. "50 dps (3 fights)")
  check("baseline line: no number this fight knows can be compared: first fights",
    lineAfter(durs({ 10, 20, 30 }), { dur = false, dmg = false, taken = false }) == H .. "first fights, 4 so far")
  got = lineAfter(durs({ 10, 20, 30 }, { { died = false }, { died = false }, { died = false } }), { died = true })
  check("baseline line: a death, with how many earlier fights died",
    got == H .. "12 s, usual 20 s" .. DOT .. "50 dps, usual 30" .. DOT .. "taken 210, usual 210 (3 fights)" .. DOT .. "DIED (usual: 0 of 3 died)")
  got = lineAfter(durs({ 10, 20, 30, 40 }, { { died = false }, { died = true }, { died = nil }, { died = false } }), { died = true })
  check("baseline line: ...counted over the earlier fights that know it (1 of 3; one unknown)",
    got ~= nil and got:sub(-#("DIED (usual: 1 of 3 died)")) == "DIED (usual: 1 of 3 died)" and got:find("(4 fights)", 1, true) ~= nil)
  check("baseline line: a death with fewer than 3 earlier fights that know it: DIED alone",
    lineAfter(durs({ 10, 20 }, { { died = false }, { died = false } }), { died = true }) == H .. "first fights, 3 so far" .. DOT .. "DIED"
    and lineAfter(durs({ 10, 20, 30 }, { { died = false } }), { died = true }) ==
      H .. "12 s, usual 20 s" .. DOT .. "50 dps, usual 30" .. DOT .. "taken 210, usual 210 (3 fights)" .. DOT .. "DIED")
  got = lineAfter(durs({ 10, 20, 30 }, { { died = true }, { died = true }, { died = true } }), { died = false })
  check("baseline line: a fight that lived says nothing of deaths",
    got ~= nil and got ~= "" and got:find("DIED", 1, true) == nil)
  -- The eleventh fight: the ten before it are compared, then the oldest leaves.
  -- With the oldest (2 s) the median of ten is (40 + 50) / 2 = 45; without it, nine give 50.
  got = lineAfter(durs({ 2, 10, 20, 30, 40, 50, 60, 70, 80, 90 }), {})
  check("baseline line: the eleventh fight is compared with the ten before it",
    got == H .. "12 s, usual 45 s" .. DOT .. "50 dps, usual 14" .. DOT .. "taken 210, usual 210 (10 fights)")
  do
    local c = {}
    for i = 1, 3 do BL(c, rec(1000 + i)) end
    local two = rec(5000)
    two.types.EnemyDamageTaken.combatSources[2] = { sourceCreatureID = 5002, name = "Hand Wolf" }
    check("baseline line: a fight that does not count gives no line", BL(c, two) == nil and BL(c, rec(5001)) ~= nil)
  end

  -- Through the reader and the slash command (the mock client: 600 damage, 40 taken an enemy).
  local LV = tostring(P.level)
  local function lines(p0)
    local out = {}
    for i = p0 + 1, #printed do if printed[i]:find("(lvl ", 1, true) then out[#out + 1] = printed[i] end end
    return out
  end
  local function boar(sid) return { mobs = { { "Creature-0-1-" .. sid, 4101, "Line Boar" } } } end
  slash("fights read"); settle()
  check("/hello baseline is off by default", ns.settings.baseline == false and ns.DEFAULTS.baseline == false)
  local p0 = #printed
  for i, d in ipairs({ 10, 20, 30, 40 }) do advance(2); fightOnce(980 + i, "Line Boar", d, boar(980 + i)); settle() end
  local e = C().baseline and C().baseline["4101:" .. LV]
  check("baseline off: no line after a counted fight", ns.settings.baseline == false and #lines(p0) == 0 and e ~= nil and #e.fights == 4)
  slash("baseline on")
  check("/hello baseline on turns the setting on", ns.settings.baseline == true and HelloForeverDB.settings.baseline == true)
  p0 = #printed
  advance(2); fightOnce(985, "Line Boar", 12, boar(985)); settle()
  local L = lines(p0)
  check("baseline on: one line after a counted new fight, against the four before it",
    #L == 1 and L[1]:find("Line Boar (lvl " .. LV .. "): 12 s, usual 25 s" .. DOT .. "50 dps, usual 25" .. DOT
      .. "taken 40, usual 40 (4 fights)", 1, true) ~= nil)
  p0 = #printed
  makeSession(985, "Line Boar", 15, boar(985))
  fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 2, 985); advance(1.5); settle()
  check("baseline on: a revision of the fight gives no line", ns.settings.baseline == true and lastSummary().rev == 2 and #lines(p0) == 0)
  p0 = #printed
  advance(2); fightOnce(986, "Line Pair", 12, { mobs = { { "Creature-0-1-986a", 4101, "Line Boar" }, { "Creature-0-1-986b", 4102, "Line Wolf" } } }); settle()
  check("baseline on: a fight with two enemies gives no line", ns.settings.baseline == true and lastSummary().name == "Line Pair" and #lines(p0) == 0)
  slash("baseline off")
  p0 = #printed
  advance(2); fightOnce(987, "Line Boar", 12, boar(987)); settle()
  check("/hello baseline off: no line again", ns.settings.baseline == false and lastSummary().rev == 1 and #lines(p0) == 0)
  slash("baseline on")
  local before = lastSummary().key
  slash("baseline reset")
  check("/hello baseline reset empties the table and sets baselineResetAt to the time",
    type(C().baseline) == "table" and next(C().baseline) == nil and C().baselineResetAt == time())
  makeSession(987, "Line Boar", 14, boar(987))
  fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 2, 987); advance(1.5); settle()
  check("...a revision of a fight from before the reset is not put back",
    lastSummary().key == before and lastSummary().rev == 2 and next(C().baseline) == nil)
  p0 = #printed
  advance(2); fightOnce(988, "Line Boar", 12, boar(988)); settle()
  L = lines(p0)
  check("...and the next fight is a first fight", #L == 1 and L[1]:find("Line Boar (lvl " .. LV .. "): first fights, 1 so far", 1, true) ~= nil)
  -- A fight that started before a reset and is read after it is left out: no line (review, #106).
  check("baseline line: a fight that started before baselineResetAt gives no line (hand-made)",
    (function()
      local c = { baselineResetAt = 4000 }
      for i = 1, 3 do BL(c, rec(4000 + i)) end
      return BL(c, rec(3999)) == nil and BL(c, rec(4100)) ~= nil
    end)())
  advance(2)
  local n989 = count()
  pull(989, "Line Boar", 12, boar(989))
  leave(true); advance(0.6)                       -- the read waits: the values are secret
  slash("baseline reset")
  p0 = #printed
  secretMode = false; restrictState = 0
  fire("ADDON_RESTRICTION_STATE_CHANGED", 0, 0); advance(0.5); settle()
  check("baseline on: a fight started before the reset and read after it gives no line",
    ns.settings.baseline == true and count() == n989 + 1 and lastSummary().name == "Line Boar" and lastSummary().rev == 1
    and #lines(p0) == 0 and next(C().baseline) == nil)
  slash("baseline off")
  for sid = 980, 990 do sessions[sid] = nil end
end

realprint("== 16k. fight baseline: the hand-over to the strip's object 12 (docs/specs/93.md, step 3)")
do
  -- HelloForever leaves the last counted fight in the plain global HelloForeverBaseline; HelloLink
  -- reads it with rawget. Missing before the build: the global is never set, so these checks fail.
  local LV = P.level
  local function G() return rawget(_G, "HelloForeverBaseline") end
  local function tri(t) return type(t) == "table" and (tostring(t[1]) .. "," .. tostring(t[2]) .. "," .. tostring(t[3])) or "none" end
  local function boar(sid) return { mobs = { { "Creature-0-1-" .. sid, 4201, "Strip Boar" } } } end
  local function pair(sid) return { mobs = { { "Creature-0-1-" .. sid .. "a", 4201, "Strip Boar" }, { "Creature-0-1-" .. sid .. "b", 4202, "Strip Wolf" } } } end
  local function revise(sid, dur, o)
    makeSession(sid, "Strip Boar", dur, o)
    fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 2, sid); advance(1.5); settle()
  end
  local function revOf(key) for _, s in ipairs(C().fightSummary) do if s.key == key then return s.rev end end end
  slash("fights read"); settle()
  advance(2); fightOnce(1100, "Strip Boar", 9, boar(1100)); settle()
  local pre = G()
  slash("baseline reset")
  check("strip: a counted fight sets the table; a reset takes it away", type(pre) == "table" and pre.counted == true and G() == nil)
  local keys = {}
  for i, d in ipairs({ 10, 20, 30 }) do advance(2); fightOnce(1100 + i, "Strip Boar", d, boar(1100 + i)); settle(); keys[i] = lastSummary().key end
  local g = G()
  check("strip: after a counted new fight, its key, rev, enemy, level and triples; usual is nil under 3 earlier fights",
    type(g) == "table" and g.fight == keys[3] and g.rev == 1 and g.counted == true and g.id == 4201 and g.level == LV
    and g.name == "Strip Boar" and tri(g.dur) == "30,nil,2" and tri(g.dps) == "20,nil,2" and tri(g.taken) == "40,nil,2"
    and tri(g.died) == "false,nil,2")
  advance(2); fightOnce(1104, "Strip Boar", 12, boar(1104)); settle()
  local k4 = lastSummary().key
  g = G()
  check("strip: the fourth fight against the medians of the three before it; died counts the deaths",
    type(g) == "table" and g.fight == k4 and g.rev == 1 and g.counted == true
    and tri(g.dur) == "12,20,3" and tri(g.dps) == "50,30,3" and tri(g.taken) == "40,40,3" and tri(g.died) == "false,0,3")
  local sent = G()
  advance(2); fightOnce(1105, "Strip Pair", 12, pair(1105)); settle()
  check("strip: a new fight that does not count leaves the object as it was", sent ~= nil and G() == sent)
  revise(1103, 33, boar(1103))
  check("strip: a revision of another fight than the one last sent leaves the object as it was", revOf(keys[3]) == 2 and sent ~= nil and G() == sent)
  revise(1104, 15, boar(1104))
  g = G()
  check("strip: a counted revision of the fight last sent: sent again with its rev and numbers",
    revOf(k4) == 2 and type(g) == "table" and g.fight == k4 and g.rev == 2 and g.counted == true and tri(g.dur) == "15,20,3"
    and tri(g.dps) == "40,30,3")
  -- The read of EnemyDamageTaken keeps failing: after 3 tries the record is stored with that
  -- type failed (section 16b), and the fight does not count.
  throwType = 10
  makeSession(1104, "Strip Boar", 16, boar(1104))
  fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 2, 1104); advance(20); settle()
  throwType = nil
  g = G()
  check("strip: a revision that no longer counts (a failed enemy read): fight, rev and counted false, nothing else",
    revOf(k4) == 3 and type(g) == "table" and g.fight == k4 and g.rev == 3 and g.counted == false
    and g.id == nil and g.dur == nil and g.died == nil)
  revise(1104, 17, boar(1104))
  g = G()
  check("strip: after counted false, a revision that counts again is sent with its numbers",
    revOf(k4) == 4 and type(g) == "table" and g.fight == k4 and g.rev == 4 and g.counted == true and tri(g.dur) == "17,20,3")
  revise(1104, 17, pair(1104))
  g = G()
  check("strip: a revision with a second enemy: counted false again",
    revOf(k4) == 5 and type(g) == "table" and g.fight == k4 and g.rev == 5 and g.counted == false and g.dur == nil)
  advance(2); fightOnce(1106, "Strip Boar", 12, boar(1106)); settle()
  local k6 = lastSummary().key
  advance(2); fightOnce(1107, "Strip Boar", 12, boar(1107)); settle()
  local k7 = lastSummary().key
  check("strip: two fights with the same numbers are two objects: the fight's key tells them apart",
    k6 ~= k7 and (G() or {}).fight == k7 and (G() or {}).counted == true)
  pre = G()
  slash("baseline reset")
  check("strip: /hello baseline reset clears the object", type(pre) == "table" and pre.fight == k7 and G() == nil)
  revise(1107, 14, boar(1107))
  check("strip: ...and a revision of the fight sent before the reset does not bring it back",
    type(pre) == "table" and pre.fight == k7 and revOf(k7) == 2 and G() == nil)
  for sid = 1100, 1107 do sessions[sid] = nil end
end

realprint("== 16l. saved data: a value the client cannot give is not written as a number")
do
  local function bagsNow() fire("BAG_UPDATE_DELAYED"); advance(11) end
  local function first() local b = C().snapshot.bags return b and b[1] end
  local saved = bagItems[0][1]
  bagItems[0][1] = { id = 159, count = 5, link = "|Hitem:159|h[Refreshing Spring Water]|h" }
  bagsNow()
  local at = C().snapshot.freshness.bags.observedAt
  check("a read bag: the item and its count, fresh", first() and first().count == 5 and C().snapshot.freshness.bags.status == "ok")
  advance(2)
  -- A real secret is a number, which a type check lets through: the check is that the guard
  -- was asked about the count, and that nothing was written.
  local realIsSecret, asked = ns.IsSecret, 0
  ns.IsSecret = function(v) if getmetatable(v) == SECRET_MT then asked = asked + 1 end return realIsSecret(v) end
  bagItems[0][1].count = S()
  bagsNow()
  ns.IsSecret = realIsSecret
  check("a count the client keeps secret: not written as 1; the last read stays, stale, with its time",
    first() and first().count == 5 and C().snapshot.freshness.bags.status == "stale" and C().snapshot.freshness.bags.observedAt == at,
    first() and (tostring(first().count) .. " " .. C().snapshot.freshness.bags.status))
  check("...and the guard was asked about it", asked >= 1, asked)
  bagItems[0][1].count = 7
  local realSlots = C_Container.GetContainerNumSlots
  C_Container.GetContainerNumSlots = function(b) if b == 1 then error("not now") end return realSlots(b) end
  bagsNow()
  check("a bag whose size cannot be read: not a bag of no slots; the last read stays, stale",
    first() and first().count == 5 and C().snapshot.freshness.bags.status == "stale")
  C_Container.GetContainerNumSlots = realSlots
  bagsNow()
  check("readable again: the new count, fresh", first() and first().count == 7 and C().snapshot.freshness.bags.status == "ok")
  bagItems[0][1] = saved
  bagsNow()
  -- the timeline
  local tl = C().timeline
  local function noZeroAfter(n0)
    for i = n0 + 1, #tl do if tl[i].xp == 0 or tl[i].level == 0 or tl[i].money == 0 then return false end end
    return true
  end
  local n0, xp = #tl, P.xp
  P.xp = S()
  ns.TimelineTick(true)
  check("XP the client keeps secret: the timeline tick is skipped, not written as 0", #tl == n0 and noZeroAfter(n0), #tl - n0)
  P.xp = nil
  ns.TimelineTick(true)
  check("...and XP it does not give", #tl == n0, #tl - n0)
  P.xp = xp
  local realLevel = UnitLevel
  UnitLevel = function(u) if u == "player" then return S() end return realLevel(u) end
  ns.TimelineTick(true)
  check("a level the client keeps secret: the tick is skipped, not written as level 0", #tl == n0 and noZeroAfter(n0), #tl - n0)
  UnitLevel = realLevel
  ns.TimelineTick(true)
  check("all readable: the tick is written", #tl == n0 + 1 and tl[#tl].xp == P.xp and tl[#tl].level ~= 0, #tl - n0)
end
]==]

local chunk = assert(loadstring(src:sub(1, at - 1) .. more .. src:sub(at), "=fights_harness_v4+more"))
chunk(...)
