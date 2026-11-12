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

]==]

local chunk = assert(loadstring(src:sub(1, at - 1) .. more .. src:sub(at), "=fights_harness_v4+more"))
chunk(...)
