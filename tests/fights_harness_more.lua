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
