-- HelloForever / Fights.lua
-- Lossless per-session fight capture from Blizzard's C_DamageMeter (fight log v4).
--
-- Source: Gethe/wow-ui-source `forever`, Blizzard_APIDocumentationGenerated/.
-- * Every meter type (Enum.DamageMeterType 0..10), every source of every type
--   (GetCombatSessionFromID) and every source's spell breakdown incl. per-target details
--   (GetCombatSessionSourceFromID) are copied field by field.
-- * Death recaps via C_DeathRecap, checked for secrets like Details' GetRecapInfoSafe.
-- * Reads start the moment combat ends: PLAYER_REGEN_ENABLED, and
--   ADDON_RESTRICTION_STATE_CHANGED(Combat -> Inactive). The session getters are documented
--   SecretWhenInCombat; if values are still secret a 0.25 s poll retries for 10 s. Unread
--   sessions stay queued and are retried on every later trigger, never dropped.
-- * Session start/end are stamped from DAMAGE_METER_COMBAT_SESSION_UPDATED as Details does.
--   The in-combat handler only writes into a table; no API calls in combat.
-- * A session that vanishes unread (meter reset, relog, list truncation) is logged as a gap
--   record so nothing disappears silently.
-- * A session that is updated after it was read is read again; it is stored as a new
--   revision only if its content actually changed. A re-read in which the player's own
--   cumulative totals went DOWN is a different fight on a recycled id and gets its own key
--   instead of overwriting. A shorter duration alone is not: that is a correction.
-- * Each record is SerializeJSON -> CompressString(Deflate) -> EncodeBase64, verified by a
--   decode round trip, else stored as JSON text / a plain table. The pipeline exports one
--   file per fight; the in-game log is only trimmed past a size budget, oldest days first,
--   never days newer than FL_KEEP_DAYS.
local addonName, ns = ...

local type, pairs, ipairs, tostring, tonumber, pcall, next = type, pairs, ipairs, tostring, tonumber, pcall, next
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local sort, concat = table.sort, table.concat
local time = time
local call, isSecret, plain = ns.Call, ns.IsSecret, ns.Plain

local FL_VERSION = 4
local FL_KEEP_DAYS = 7         -- never trim a day newer than this (pipeline runs daily)
local FL_POLL_SEC = 0.25
local FL_POLL_MAX = 40         -- 10 s of fallback polling while values are secret
local FL_CALLS_PER_STEP = 30   -- C_DamageMeter calls per frame step (hitch budget)
local FL_STEP_MS = 6           -- ...and a time budget for the same step
local FL_SUMMARY_KEEP = 50
local FL_TRIMMED_KEEP = 120    -- trimmed-day receipts kept for the pipeline
local FL_DONE_GONE_SEC = 3600  -- forget a read session this long after it left the list
local FL_STALE_MAX = 3         -- re-reads of an "updated" session that found nothing new
-- Fields documented as SecretValue = true (always secret).
local ALWAYS_SECRET = { specIconID = true }

local function enumValue(enumName, field, documented)
    local E = _G.Enum
    local t = type(E) == "table" and E[enumName]
    local v = type(t) == "table" and t[field]
    if type(v) == "number" then return v end
    return documented
end

local DOC_DM_TYPES = {
    { 0, "DamageDone" }, { 1, "Dps" }, { 2, "HealingDone" }, { 3, "Hps" }, { 4, "Absorbs" },
    { 5, "Interrupts" }, { 6, "Dispels" }, { 7, "DamageTaken" }, { 8, "AvoidableDamageTaken" },
    { 9, "Deaths" }, { 10, "EnemyDamageTaken" },
}

-- All meter types: from Enum at runtime (so new types are picked up), else the documented
-- list. Built once; the enum cannot change during a session.
local typeList
local function meterTypes()
    if typeList then return typeList end
    local E = _G.Enum
    local t = type(E) == "table" and E.DamageMeterType
    local out = {}
    if type(t) == "table" then
        for name, v in pairs(t) do
            if type(name) == "string" and type(v) == "number" then out[#out + 1] = { v, name } end
        end
    end
    if #out == 0 then
        for i, p in ipairs(DOC_DM_TYPES) do out[i] = { p[1], p[2] } end
    end
    sort(out, function(a, b) return a[1] < b[1] end)
    typeList = out
    return out
end

local RESTRICT_COMBAT = enumValue("AddOnRestrictionType", "Combat", 0)

local issecrettable = _G.issecrettable
local isSecretTable = type(issecrettable) == "function" and issecrettable or function() return false end

local function num(v)
    if type(v) == "number" and not isSecret(v) then return v end
    return nil
end

local SECRET = {} -- sentinel: "a value we need is still secret"

-- Deep copy of an API result. Returns SECRET if anything except an ALWAYS_SECRET field is secret.
local function clean(v, depth, skipped, key)
    if isSecret(v) then
        if key and ALWAYS_SECRET[key] then
            skipped[key] = (skipped[key] or 0) + 1
            return nil
        end
        return SECRET
    end
    local tv = type(v)
    if tv == "table" then
        if isSecretTable(v) then return SECRET end
        if depth > 10 then return nil end
        local out = {}
        for k, x in pairs(v) do
            if isSecret(k) then return SECRET end
            local tk = type(k)
            if tk == "string" or tk == "number" then
                local cv = clean(x, depth + 1, skipped, tk == "string" and k or nil)
                if cv == SECRET then return SECRET end
                if cv ~= nil then out[k] = cv end
            end
        end
        return out
    elseif tv == "number" or tv == "string" or tv == "boolean" then
        return v
    end
    return nil
end

local flStatus = {
    state = "idle", lastReason = nil, lastAt = nil, steps = 0, waits = 0, polls = 0,
    stored = 0, gaps = 0, errors = 0, lastError = nil, encode = nil, lastMs = nil, maxMs = 0,
    pending = 0, unchanged = 0, rekeyed = 0,
}
ns.fightStatus = flStatus

local flChar

local function flDB()
    local c = ns.Char()
    if c == flChar then return c end
    local f = c.fightLog
    if type(f) ~= "table" then
        f = { v = FL_VERSION }
        c.fightLog = f
    end
    f.days = f.days or {}
    f.index = f.index or {}
    f.trimmed = f.trimmed or {}
    local tr = c.fightTrack
    if type(tr) ~= "table" then
        tr = {}
        c.fightTrack = tr
    end
    tr.sessions = tr.sessions or {}
    tr.done = tr.done or {}
    tr.maxDone = tr.maxDone or 0
    tr.resets = tr.resets or 0
    c.fightSummary = c.fightSummary or {}
    flChar = c
    return c
end

local function track()
    return flDB().fightTrack
end

-- Last session id handled while in combat. The meter event repeats for the same id all
-- fight long; once it has been noted, the repeats return at once.
local hotSid

-- DAMAGE_METER_CURRENT_SESSION_UPDATED (Details treats it as "new session").
function ns.FightsNewCurrent()
    hotSid = nil
    track().newPending = time()
end

-- Called from DAMAGE_METER_COMBAT_SESSION_UPDATED (also in combat): O(1), no API calls.
-- Returns true when a session that was already read has changed since.
function ns.FightsSeen(sid)
    local tr = track()
    local s = tr.sessions[sid]
    local d = tr.done[sid]
    -- Known id: same session still updating, unless a new session was announced and this id
    -- was already read (ids restarted, e.g. after a meter reset): then it's a new fight.
    if s and not (tr.newPending and d) then
        if d then
            s.dirty = true
            return true
        end
        return false
    end
    local now = time()
    if s then tr.done[sid] = nil end
    tr.newPending = nil
    -- the previous open session ended when this one started
    for osid, os in pairs(tr.sessions) do
        if osid < sid and not os.stop then os.stop = now end
    end
    tr.sessions[sid] = { start = now }
    return false
end

local function stampStop(now)
    for _, s in pairs(track().sessions) do
        if not s.stop then s.stop = now end
    end
end

local function fightsBlocked()
    if ns.InCombat() then return "combat" end
    local RA = _G.C_RestrictedActions
    if type(RA) == "table" and type(RA.GetAddOnRestrictionState) == "function" then
        local ok, state = pcall(RA.GetAddOnRestrictionState, RESTRICT_COMBAT)
        if not ok then return "restriction_err" end
        if isSecret(state) then return "restriction_secret" end
        if type(state) == "number" and state > 0 then return "restricted" end
    end
    return nil
end

----------------------------------------------------------------------
-- Encoding: JSON -> Deflate -> Base64, verified by decoding again.
----------------------------------------------------------------------
local DEFLATE = enumValue("CompressionMethod", "Deflate", 0)
-- Records are written once and kept for days: spend the extra encode time on size.
local LEVEL_SIZE = enumValue("CompressionLevel", "OptimizeForSize", 2)
local levelOK = true

-- Returns blob, bytes, how.
local function encodeRecord(rec)
    local EU = _G.C_EncodingUtil
    if type(EU) == "table" and type(EU.SerializeJSON) == "function"
        and type(EU.CompressString) == "function" and type(EU.EncodeBase64) == "function" then
        local ok, json = pcall(EU.SerializeJSON, rec)
        if ok and type(json) == "string" and json ~= "" then
            local ok2, z
            if levelOK then
                ok2, z = pcall(EU.CompressString, json, DEFLATE, LEVEL_SIZE)
                if not ok2 or type(z) ~= "string" then levelOK = false end
            end
            if not levelOK then ok2, z = pcall(EU.CompressString, json, DEFLATE) end
            local ok3, b64 = false, nil
            if ok2 and type(z) == "string" then ok3, b64 = pcall(EU.EncodeBase64, z) end
            if ok3 and type(b64) == "string" and b64 ~= "" then
                local verified = false
                if type(EU.DecodeBase64) == "function" and type(EU.DecompressString) == "function" then
                    local okd, raw = pcall(EU.DecodeBase64, b64)
                    local oku, back = false, nil
                    if okd and type(raw) == "string" then oku, back = pcall(EU.DecompressString, raw, DEFLATE) end
                    verified = oku and back == json
                end
                if verified then
                    local blob = "d1:" .. b64
                    return blob, #blob, "deflate"
                end
            end
            -- compression unavailable or round trip failed: keep the JSON text itself
            local blob = "j1:" .. json
            return blob, #blob, "json"
        end
    end
    -- last resort: the plain Lua table (always lossless, just bigger)
    return rec, 4000, "table"
end

-- Decode a stored blob back into a record table (used by the fight window, on demand).
local function decodeBlob(blob)
    if type(blob) == "table" then return blob end
    if type(blob) ~= "string" then return nil, "no data" end
    local EU = _G.C_EncodingUtil
    if type(EU) ~= "table" or type(EU.DeserializeJSON) ~= "function" then return nil, "no decoder" end
    local tag = blob:sub(1, 3)
    local json
    if tag == "d1:" then
        local okd, raw = pcall(EU.DecodeBase64, blob:sub(4))
        if not okd or type(raw) ~= "string" then return nil, "base64" end
        local oku, back = pcall(EU.DecompressString, raw, DEFLATE)
        if not oku or type(back) ~= "string" then return nil, "inflate" end
        json = back
    elseif tag == "j1:" then
        json = blob:sub(4)
    else
        return nil, "unknown format"
    end
    local ok, rec = pcall(EU.DeserializeJSON, json)
    if not ok or type(rec) ~= "table" then return nil, "json" end
    return rec
end

local function dayOf(t) return date("%Y-%m-%d", t or time()) end

----------------------------------------------------------------------
-- Storage: per-day buckets, a running byte total, budget trim
----------------------------------------------------------------------
local function budgetBytes()
    local mb = tonumber(ns.settings and ns.settings.budgetMB) or ns.DEFAULTS.budgetMB
    if mb < 1 then mb = 1 elseif mb > 20 then mb = 20 end
    return mb * 1024 * 1024
end
ns.FightsBudgetBytes = budgetBytes

-- The byte total is recounted once per session (older saves may not carry it) and kept
-- up to date by deltas afterwards, instead of walking every day on each store.
local syncedLog

local function syncBytes(f)
    if syncedLog == f and type(f.bytes) == "number" then return end
    local total = 0
    for _, b in pairs(f.days) do total = total + (b.bytes or 0) end
    f.bytes = total
    syncedLog = f
end

local function dropDay(f, d, how)
    local b = f.days[d]
    if not b then return 0 end
    local keys = b.keys or {}
    f.trimmed[d] = { n = #keys, bytes = b.bytes, at = time(), keys = concat(keys, ","), how = how }
    for i = 1, #keys do f.index[keys[i]] = nil end
    f.days[d] = nil
    f.bytes = (f.bytes or 0) - (b.bytes or 0)
    return #keys
end

-- Receipts of trimmed days are for the pipeline's own bookkeeping; keep the newest ones.
local function capTrimmed(f)
    local days = {}
    for d in pairs(f.trimmed) do days[#days + 1] = d end
    if #days <= FL_TRIMMED_KEEP then return end
    sort(days)
    for i = 1, #days - FL_TRIMMED_KEEP do
        f.trimmed[days[i]] = nil
        f.trimmedDropped = (f.trimmedDropped or 0) + 1
    end
end

local function trimFightLog(c)
    local f = c.fightLog
    syncBytes(f)
    local budget = budgetBytes()
    if f.bytes <= budget then return end
    local days = {}
    for d in pairs(f.days) do days[#days + 1] = d end
    sort(days)
    local cutoff = dayOf(time() - FL_KEEP_DAYS * 86400)
    local dropped = false
    for i = 1, #days do
        local d = days[i]
        if f.bytes <= budget or d >= cutoff then break end
        dropDay(f, d)
        dropped = true
    end
    if dropped then capTrimmed(f) end
end

-- Manual purge: drop every day older than `days` days, whatever the budget says.
-- Returns fights dropped, day buckets dropped.
function ns.FightsPurge(days)
    local c = flDB()
    local f = c.fightLog
    syncBytes(f)
    local cutoff = dayOf(time() - days * 86400)
    local old = {}
    for d in pairs(f.days) do
        if d < cutoff then old[#old + 1] = d end
    end
    local fights = 0
    for i = 1, #old do fights = fights + dropDay(f, old[i], "purge") end
    if #old > 0 then capTrimmed(f) end
    return fights, #old
end

-- Put a record into its day bucket; replaces in place if the key already exists (newer rev).
local function storeRecord(c, rec)
    local f = c.fightLog
    syncBytes(f)
    local blob, size, how = encodeRecord(rec)
    flStatus.encode = how
    local day = f.index[rec.key]
    local b, idx
    if day and f.days[day] then
        b = f.days[day]
        local keys = b.keys
        for i = #keys, 1, -1 do
            if keys[i] == rec.key then idx = i break end
        end
    end
    if not idx then
        day = dayOf(rec.start)
        b = f.days[day]
        if not b then
            b = { keys = {}, data = {}, sizes = {}, bytes = 0 }
            f.days[day] = b
        end
        idx = #b.keys + 1
        b.keys[idx] = rec.key
    end
    local delta = size - (b.sizes[idx] or 0)
    b.bytes = (b.bytes or 0) + delta
    b.data[idx] = blob
    b.sizes[idx] = size
    f.index[rec.key] = day
    f.bytes = f.bytes + delta
    trimFightLog(c)
end

function ns.FightLine(r)
    if r.gap then
        return ("%s |cffff8800GAP|r session %s (%s)"):format(date("%H:%M", r.t or 0), tostring(r.key), tostring(r.gap))
    end
    return ("%s %s %ss dmg %s (%s dps)%s heal %s taken %s%s%s"):format(
        date("%H:%M", r.t or 0), tostring(r.name), tostring(r.dur or 0),
        ns.FmtNum(r.dmg), tostring(floor((r.dps or 0) * 10 + 0.5) / 10),
        (r.pet or 0) > 0 and (" pet " .. ns.FmtNum(r.pet)) or "",
        ns.FmtNum(r.heal), ns.FmtNum(r.taken),
        r.died and " |cffff4040DIED|r" or "",
        (r.rev or 1) > 1 and (" rev" .. r.rev) or "")
end

local function mine(rec, typeName)
    local ty = rec.types and rec.types[typeName]
    if type(ty) ~= "table" or type(ty.combatSources) ~= "table" then return nil, nil end
    for i, src in ipairs(ty.combatSources) do
        if src.isLocalPlayer then return src, ty.bySource and ty.bySource[i] end
    end
    return nil, nil
end

-- Compact row for /hello fights and the fight window (no decoding needed to list fights).
local function summarize(c, rec)
    local s = { key = rec.key, t = rec.start, dur = rec.dur, name = rec.name, rev = rec.rev, gap = rec.gap }
    local d, dsp = mine(rec, "DamageDone")
    s.dmg = d and d.totalAmount or 0
    s.dps = d and d.amountPerSecond or 0
    local pet = 0
    if type(dsp) == "table" and type(dsp.combatSpells) == "table" then
        for _, sp in ipairs(dsp.combatSpells) do
            if type(sp.creatureName) == "string" and sp.creatureName ~= "" then pet = pet + (sp.totalAmount or 0) end
        end
    end
    s.pet = pet
    local h = mine(rec, "HealingDone")
    s.heal = h and h.totalAmount or 0
    local tk = mine(rec, "DamageTaken")
    s.taken = tk and tk.totalAmount or 0
    local dd = mine(rec, "Deaths")
    s.died = (dd and type(dd.deathRecapID) == "number" and dd.deathRecapID ~= 0) or false

    local sum = c.fightSummary
    local inRing, prev = false, nil
    for i = #sum, 1, -1 do
        if sum[i].key == s.key then
            prev, sum[i], inRing = sum[i], s, true
            break
        end
    end
    if not inRing then
        sum[#sum + 1] = s
        ns.TrimHead(sum, FL_SUMMARY_KEEP, 0)
    end
    -- A later revision of a fight is not a new fight, even if its row left the ring.
    local isNew = not inRing and (rec.rev or 1) == 1
    if isNew and ns.settings and ns.settings.announce and not s.gap then
        pcall(print, ns.PREFIX .. " " .. ns.FightLine(s))
    end
    ns.Notify("FIGHT", s, isNew, prev)
    return s
end

local function uniqueKey(c, start, sid)
    local base = tostring(start) .. "-" .. tostring(sid)
    local idx = c.fightLog.index
    local key, n = base, 1
    while idx[key] do -- never overwrite a different fight that happens to share the key
        n = n + 1
        key = base .. "-" .. n
    end
    return key
end

local function storeGap(c, sid, s, why)
    local key = tostring(s.start or time()) .. "-" .. tostring(sid)
    if c.fightLog.index[key] then return end
    local rec = { v = FL_VERSION, key = key, sid = sid, start = s.start, stop = s.stop, gap = why,
        char = ns.CharKey(), noted = time() }
    storeRecord(c, rec)
    summarize(c, rec)
    flStatus.gaps = flStatus.gaps + 1
end

----------------------------------------------------------------------
-- Reader: a job spread over frames
----------------------------------------------------------------------
-- In-memory job state (a /reload mid-job just restarts the session read).
local job = nil        -- { todo = {avail...}, rec = staging, ti = next type index, types = list }
local stepScheduled = false
local pollTicker = nil
local pollCount = 0
local needRead = false
local dirtyKick = false

local function stopPoll()
    if pollTicker and type(pollTicker.Cancel) == "function" then pollTicker:Cancel() end
    pollTicker = nil
end

local runStep -- forward

local function nextFrameStep()
    stepScheduled = false
    runStep("next_frame")
end

local function scheduleStep()
    if stepScheduled then return end
    stepScheduled = true
    ns.After(0, nextFrameStep)
end

local function pollTick()
    pollCount = pollCount + 1
    flStatus.polls = flStatus.polls + 1
    if pollCount >= FL_POLL_MAX then stopPoll() end
    runStep("poll")
end

local function startPoll()
    if pollTicker then return end
    pollCount = 0
    pollTicker = ns.Ticker(FL_POLL_SEC, pollTick, FL_POLL_MAX)
end

-- Build the work list. Returns todo list or nil, reason.
local function plan(c, DM)
    local ok, avail = pcall(DM.GetAvailableCombatSessions)
    if not ok or type(avail) ~= "table" then return nil, "sessions_err" end
    if isSecretTable(avail) then return nil, "secret" end
    local tr = c.fightTrack
    local list, present, maxId = {}, {}, 0
    for _, a in ipairs(avail) do
        if type(a) == "table" and num(a.sessionID) then
            if isSecret(a.name) or isSecret(a.durationSeconds) then return nil, "secret" end
            list[#list + 1] = a
            present[a.sessionID] = true
            if a.sessionID > maxId then maxId = a.sessionID end
        end
    end
    flStatus.sessions, flStatus.maxSid = #list, maxId
    -- Ids went backwards: the client restarted numbering (relog / reset). Forget "done".
    -- An empty list proves nothing (it can be empty for a moment across a loading screen);
    -- if numbering really restarted, the first new session shows it.
    if #list > 0 and maxId < tr.maxDone then
        for sid in pairs(tr.done) do tr.sessions[sid] = nil end
        tr.done = {}
        tr.maxDone = 0
        tr.resets = tr.resets + 1
    end
    -- Tracked sessions that vanished before we read them: record a gap, then forget them.
    for sid, s in pairs(tr.sessions) do
        if not present[sid] then
            if not tr.done[sid] then storeGap(c, sid, s, "vanished") end
            tr.sessions[sid] = nil
        end
    end
    -- "Read" markers of sessions the client has dropped from its list are kept for a
    -- while (so a list that is briefly empty does not make every fight look new when it
    -- comes back) and then forgotten, so the table does not grow for ever in SavedVariables.
    local now = time()
    for sid, d in pairs(tr.done) do
        if present[sid] then
            d.gone = nil
        elseif not d.gone then
            d.gone = now
        elseif now - d.gone > FL_DONE_GONE_SEC then
            tr.done[sid] = nil
        end
    end
    sort(list, function(a, b) return a.sessionID < b.sessionID end)
    local todo = {}
    for _, a in ipairs(list) do
        local sid = a.sessionID
        local d = tr.done[sid]
        local dur = num(a.durationSeconds) or 0
        if d and a.name ~= d.name then
            -- same id, different fight: ids restarted without a reset we saw. Read as new.
            tr.done[sid] = nil
            tr.sessions[sid] = nil
            d = nil
        end
        if not d then
            todo[#todo + 1] = a
        else
            local s = tr.sessions[sid]
            -- Longer: a chained pull merged into it. Shorter: the client corrected the
            -- length, or another fight took the id; the re-read tells which (finishRecord).
            local resized = abs(dur - (d.dur or 0)) > 0.5
            local dirty = s and s.dirty and (d.stale or 0) < FL_STALE_MAX
            if resized or dirty then
                a._rev = (d.rev or 1) + 1
                a._key = d.key
                a._prev = d
                todo[#todo + 1] = a
            end
        end
    end
    return todo
end

local function newRecord(c, a)
    local tr = c.fightTrack
    local sid = a.sessionID
    local s = tr.sessions[sid]
    local dur = num(a.durationSeconds)
    local now = time()
    local start, approx = s and s.start, nil
    if not start then
        start = floor(now - (dur or 0) + 0.5)
        approx = true
        s = { start = start, stop = now, approx = true }
        tr.sessions[sid] = s
    end
    local CM = _G.C_Map
    return {
        v = FL_VERSION,
        key = a._key or uniqueKey(c, start, sid),
        rev = a._rev or 1,
        sid = sid,
        name = a.name,
        start = start,
        startApprox = approx,
        stop = s.stop,
        dur = dur,
        char = ns.CharKey(),
        lvl = call(UnitLevel, "player"),
        zone = call(GetRealZoneText) or call(GetZoneText),
        subzone = call(GetSubZoneText),
        mapID = type(CM) == "table" and call(CM.GetBestMapForUnit, "player") or nil,
        addonVersion = ns.version,
        types = {},
        recaps = {},
        skipped = {},
        read = { at = now, reason = flStatus.lastReason },
    }
end

-- Read one meter type's session table (1 call). Returns cleaned table, raw sources | SECRET
local function readTypeSession(DM, sid, typeValue, skipped)
    local ok, sess = pcall(DM.GetCombatSessionFromID, sid, typeValue)
    if not ok then return { err = tostring(sess) }, nil end
    local cs = clean(sess, 0, skipped)
    if cs == SECRET then return SECRET end
    if type(cs) ~= "table" then return { none = true }, nil end
    cs.bySource = {}
    local raw = type(sess) == "table" and sess.combatSources or nil
    if type(raw) ~= "table" or type(DM.GetCombatSessionSourceFromID) ~= "function" then raw = nil end
    return cs, raw
end

-- One source's spell breakdown (1 call). Returns cleaned table | SECRET
local function readTypeSource(DM, sid, typeValue, src, skipped)
    local ok, ss = pcall(DM.GetCombatSessionSourceFromID, sid, typeValue, src.sourceGUID, src.sourceCreatureID)
    if not ok then return { err = tostring(ss) } end
    local c2 = clean(ss, 0, skipped)
    if c2 == SECRET then return SECRET end
    return c2 or false
end

-- Death recaps for every source with a non-zero deathRecapID. Returns false while secret.
local function readRecaps(rec)
    local DR = _G.C_DeathRecap
    if type(DR) ~= "table" or type(DR.GetRecapEvents) ~= "function" then return true end
    if not rec.skipped then rec.skipped = {} end
    for _, ty in pairs(rec.types) do
        if type(ty) == "table" and type(ty.combatSources) == "table" then
            for _, src in ipairs(ty.combatSources) do
                local rid = src.deathRecapID
                if type(rid) == "number" and rid ~= 0 and rec.recaps[tostring(rid)] == nil then
                    local r = { who = src.name, guid = src.sourceGUID }
                    local okh, has = pcall(DR.HasRecapEvents, rid)
                    -- a secret boolean cannot even be tested: wait for it instead
                    if okh and isSecret(has) then return false end
                    r.has = (okh and has) and true or false
                    if r.has then
                        local oke, ev = pcall(DR.GetRecapEvents, rid)
                        local ce = oke and clean(ev, 0, rec.skipped) or nil
                        if ce == SECRET then return false end
                        r.events = ce
                        local okm, mh = pcall(DR.GetRecapMaxHealth, rid)
                        if okm then
                            if isSecret(mh) then return false end
                            r.maxHealth = mh
                        end
                        local okl, link = pcall(DR.GetRecapLink, rid)
                        if okl and not isSecret(link) then r.link = link end
                    end
                    rec.recaps[tostring(rid)] = r
                end
            end
        end
    end
    return true
end

-- A cheap fingerprint of a record's content: per type "total:sources:spells".
local function signature(rec)
    local types = meterTypes()
    local parts = {}
    for i = 1, #types do
        local ty = rec.types[types[i][2]]
        local total, nsrc, nsp = 0, 0, 0
        if type(ty) == "table" then
            total = tonumber(ty.totalAmount) or 0
            local by = ty.bySource
            nsrc = type(ty.combatSources) == "table" and #ty.combatSources or 0
            if type(by) == "table" then
                for j = 1, nsrc do
                    local b = by[j]
                    if type(b) == "table" and type(b.combatSpells) == "table" then nsp = nsp + #b.combatSpells end
                end
            end
        end
        parts[i] = ("%.0f:%d:%d"):format(total, nsrc, nsp)
    end
    return concat(parts, "|")
end

-- The player's own total for one meter type, or nil when this read cannot say (the type
-- failed, or the player has no row in it).
local function ownTotal(rec, typeName)
    local ty = rec.types[typeName]
    if type(ty) ~= "table" or ty.err or ty.none then return nil end
    local sources = ty.combatSources
    if type(sources) ~= "table" then return nil end
    for i = 1, #sources do
        local src = sources[i]
        if src.isLocalPlayer then return tonumber(src.totalAmount) end
    end
    return nil
end

-- Totals that can only grow while one session continues: the player's own damage done,
-- healing done and damage taken. (Session-wide totals are not used: they can fall when
-- another source's row goes away.)
local function ownTotals(rec)
    return { d = ownTotal(rec, "DamageDone"), h = ownTotal(rec, "HealingDone"), t = ownTotal(rec, "DamageTaken") }
end

-- True when a total that both reads know went down.
local function wentDown(now, before)
    if type(before) ~= "table" then return false end
    for k, v in pairs(now) do
        local old = before[k]
        if type(old) == "number" and v < old - 0.5 then return true end
    end
    return false
end

-- Store a finished record. `prev` is the "done" marker of the earlier read when this is a
-- re-read. Returns false when the re-read found nothing new (nothing stored).
local function finishRecord(c, rec, prev)
    local tr = c.fightTrack
    local sid = rec.sid
    local s = tr.sessions[sid]
    if rec.skipped and next(rec.skipped) == nil then rec.skipped = nil end
    local sig, mono = signature(rec), ownTotals(rec)
    if prev and not rec.error then
        if wentDown(mono, prev.mono) then
            -- The player's own totals went down, so this is not the fight we read before:
            -- another fight is using the id. Keep the old record and file this one under
            -- its own key. (Guarded so a retried finish does not re-key twice.)
            if not rec.rekeyOf then
                local now = time()
                rec.rekeyOf = rec.key
                rec.rev = 1
                rec.start = floor(now - (rec.dur or 0) + 0.5)
                rec.startApprox = true
                rec.key = uniqueKey(c, rec.start, sid)
                s = { start = rec.start, stop = now, approx = true }
                tr.sessions[sid] = s
                flStatus.rekeyed = flStatus.rekeyed + 1
            end
        elseif sig == prev.sig and abs((rec.dur or 0) - (prev.dur or 0)) <= 0.5 then
            prev.stale = (prev.stale or 0) + 1
            if s then s.dirty = nil end
            flStatus.unchanged = flStatus.unchanged + 1
            return false
        end
    end
    storeRecord(c, rec)
    summarize(c, rec)
    tr.done[sid] = { key = rec.key, dur = rec.dur or 0, name = rec.name, rev = rec.rev, sig = sig, mono = mono }
    if s then s.dirty = nil end
    if sid > tr.maxDone then tr.maxDone = sid end
    flStatus.stored = flStatus.stored + 1
    return true
end

local profile = _G.debugprofilestop
if type(profile) ~= "function" then profile = nil end

local function advanceJob()
    job.todo.i = (job.todo.i or 1) + 1
    job.rec, job.errs = nil, 0
    job.cur, job.raw, job.si = nil, nil, nil
    if job.todo.i > #job.todo then job = nil end
end

local function rawStep(reason)
    local DM = _G.C_DamageMeter
    if type(DM) ~= "table" or type(DM.GetAvailableCombatSessions) ~= "function"
        or type(DM.GetCombatSessionFromID) ~= "function" then
        flStatus.state = "no_api"
        stopPoll()
        return
    end
    flStatus.lastReason = reason or flStatus.lastReason
    local why = fightsBlocked()
    if why == "combat" then
        flStatus.state = "wait:combat" -- nothing at all in combat; REGEN_ENABLED re-kicks
        stopPoll()
        return
    elseif why then
        flStatus.state = "wait:" .. why
        flStatus.waits = flStatus.waits + 1
        startPoll()
        return
    end
    local t0 = profile and profile() or nil
    local c = flDB()
    if not job then
        local todo, r = plan(c, DM)
        if not todo then
            flStatus.state = "wait:" .. tostring(r)
            flStatus.waits = flStatus.waits + 1
            if r == "secret" then startPoll() end
            return
        end
        if #todo == 0 then
            flStatus.state = "idle"
            flStatus.pending = 0
            needRead = false
            stopPoll()
            return
        end
        todo.i = 1
        job = { todo = todo, types = meterTypes() }
    end
    flStatus.pending = #job.todo - job.todo.i + 1
    flStatus.steps = flStatus.steps + 1
    local calls = 0
    while job and calls < FL_CALLS_PER_STEP do
        local a = job.todo[job.todo.i]
        if not job.rec then
            job.rec = newRecord(c, a)
            job.ti = 1
        end
        local rec = job.rec
        if job.ti <= #job.types then
            -- Cursor: one session call per type, then one call per source; a big pull is
            -- spread over several frames at FL_CALLS_PER_STEP calls each.
            local tv = job.types[job.ti]
            local data
            if not job.cur then
                calls = calls + 1
                local raw
                data, raw = readTypeSession(DM, a.sessionID, tv[1], rec.skipped)
                if data ~= SECRET then job.cur, job.raw, job.si = data, raw, 1 end
            elseif job.raw and job.si <= #job.raw then
                calls = calls + 1
                data = readTypeSource(DM, a.sessionID, tv[1], job.raw[job.si], rec.skipped)
                if data ~= SECRET then
                    job.cur.bySource[job.si] = data
                    job.si = job.si + 1
                end
            else
                rec.types[tv[2]] = job.cur
                job.cur, job.raw, job.si = nil, nil, nil
                job.ti = job.ti + 1
            end
            if data == SECRET then
                -- restart this type from its session call next time (values may have changed)
                job.cur, job.raw, job.si = nil, nil, nil
                flStatus.state = "wait:secret"
                flStatus.waits = flStatus.waits + 1
                startPoll()
                return
            end
            if t0 and profile() - t0 > FL_STEP_MS then break end
        else
            if not readRecaps(rec) then
                flStatus.state = "wait:secret_recap"
                flStatus.waits = flStatus.waits + 1
                startPoll()
                return
            end
            rec.read.steps = flStatus.steps
            finishRecord(c, rec, a._prev)
            advanceJob()
        end
    end
    if t0 then
        local ms = profile() - t0
        flStatus.lastMs = floor(ms * 100 + 0.5) / 100
        if ms > flStatus.maxMs then flStatus.maxMs = flStatus.lastMs end
    end
    flStatus.lastAt = time()
    if job then
        flStatus.state = "reading"
    else
        -- re-plan once more: a new session may have appeared meanwhile
        flStatus.state = "idle"
        flStatus.pending = 0
    end
    scheduleStep()
end

-- All steps run under pcall. A session that keeps throwing is stored with its error after
-- 3 tries (with whatever was read), so one bad session can't block the queue.
runStep = function(reason)
    local ok, err = pcall(rawStep, reason)
    if ok then return end
    flStatus.errors = flStatus.errors + 1
    flStatus.lastError = tostring(err)
    flStatus.state = "error"
    if job and job.rec then
        job.errs = (job.errs or 0) + 1
        if job.errs >= 3 then
            local rec = job.rec
            rec.error = tostring(err)
            pcall(finishRecord, flDB(), rec, nil)
            advanceJob()
        end
        -- try again next frame instead of waiting for the next fight to re-kick the queue
        if not ns.InCombat() then scheduleStep() end
    else
        job = nil
    end
end

-- Entry point for all triggers. Runs the first step immediately (same frame).
function ns.FightsKick(reason)
    needRead = true
    runStep(reason)
end

function ns.FightsCombatStart()
    hotSid = nil
    stopPoll()
    -- A half-read session may keep changing during this fight: drop the staging copy and
    -- plan again afterwards (sessions persist in the client list).
    job = nil
end

local function lateRegen()
    if flStatus.state == "wait:combat" and not ns.InCombat() then ns.FightsKick("regen_late") end
end

function ns.FightsCombatEnd()
    hotSid = nil
    stampStop(time())
    ns.FightsKick("regen")
    -- Lockdown normally ends before this event; if the client still reported combat, look
    -- again shortly instead of waiting for the next trigger.
    if flStatus.state == "wait:combat" then ns.After(0.5, lateRegen) end
end

function ns.FightsRestriction(rtype, state)
    if plain(rtype) ~= RESTRICT_COMBAT then return end
    state = plain(state)
    if type(state) == "number" and state == 0 then
        ns.FightsKick("restriction_off")
    else
        stopPoll()
    end
end

local function dirtyRead()
    dirtyKick = false
    if not ns.InCombat() then ns.FightsKick("meter_update") end
end

function ns.FightsMeterUpdated(_, sid)
    sid = plain(sid)
    if sid ~= nil and sid == hotSid then return end
    local dirty = false
    if type(sid) == "number" and sid > 0 then dirty = ns.FightsSeen(sid) end
    if ns.InCombat() then
        hotSid = sid
        return
    end
    hotSid = nil
    if needRead then
        scheduleStep()
    elseif dirty and not dirtyKick then
        -- a session we already stored was updated: look again once the burst settles
        dirtyKick = true
        ns.After(1, dirtyRead)
    end
end

function ns.FightsMeterReset()
    -- Blizzard (or Details) wiped the sessions.
    local c = flDB()
    local tr = c.fightTrack
    for sid, s in pairs(tr.sessions) do
        if not tr.done[sid] then storeGap(c, sid, s, "reset") end
    end
    tr.sessions = {}
    tr.done = {}
    tr.maxDone = 0
    tr.resets = tr.resets + 1
    job = nil
    hotSid = nil
end

----------------------------------------------------------------------
-- Queries and reports
----------------------------------------------------------------------
local function fightLogStats(c)
    local f = c.fightLog
    syncBytes(f)
    local n, days, oldest = 0, 0, nil
    for d, b in pairs(f.days) do
        days = days + 1
        n = n + #b.keys
        if not oldest or d < oldest then oldest = d end
    end
    local trimmedDays = 0
    for _ in pairs(f.trimmed) do trimmedDays = trimmedDays + 1 end
    return n, days, oldest, f.bytes, trimmedDays
end

-- fights, days, oldest day, bytes, trimmed days, budget bytes
function ns.FightsStats()
    local n, days, oldest, bytes, trimmedDays = fightLogStats(flDB())
    return n, days, oldest, bytes, trimmedDays, budgetBytes()
end

-- The summary ring (newest last). Read-only for callers.
function ns.FightsSummary()
    return flDB().fightSummary
end

-- Decode one stored record by key. Returns record | nil, reason.
function ns.FightsLoad(key)
    local f = flDB().fightLog
    local day = f.index[key]
    local b = day and f.days[day]
    if not b then return nil, "not in the log (trimmed or exported)" end
    for i = #b.keys, 1, -1 do
        if b.keys[i] == key then return decodeBlob(b.data[i]) end
    end
    return nil, "not in the log"
end

function ns.PrintFights(n)
    local c = flDB()
    local s = c.fightSummary
    local total, days = fightLogStats(c)
    print(("%s fights: %d stored in %d day(s); %s. Last %d:")
        :format(ns.PREFIX, total, days, flStatus.state, min(n, #s)))
    if #s == 0 then
        print("  (none yet; read starts the moment combat ends)")
        return
    end
    for i = #s, max(1, #s - n + 1), -1 do
        print("  " .. ns.FightLine(s[i]))
    end
end

function ns.PrintExport()
    local c = flDB()
    local n, days, oldest, bytes, trimmedDays = fightLogStats(c)
    local budget = budgetBytes()
    print(("%s fight log: %d fights, %d day(s) since %s, %.0f KB of %.0f KB budget, %d day(s) trimmed.")
        :format(ns.PREFIX, n, days, tostring(oldest or "-"), bytes / 1024, budget / 1024, trimmedDays))
    print("  Saved to disk only on /reload or logout. Export with /hello export after combat,")
    print("  or let an external offline pipeline pull SavedVariables. Only days older than "
        .. FL_KEEP_DAYS .. " days are ever trimmed, and only past the budget.")
end

function ns.FightsDebugLine()
    local DM = _G.C_DamageMeter
    local api = type(DM) == "table" and type(DM.GetAvailableCombatSessions) == "function"
        and type(DM.GetCombatSessionFromID) == "function"
        and type(DM.GetCombatSessionSourceFromID) == "function"
    local avail, why = "?", ""
    if type(DM) == "table" and type(DM.IsDamageMeterAvailable) == "function" then
        local a, reason = call(DM.IsDamageMeterAvailable)
        if a ~= nil then
            avail = tostring(a)
            why = (reason and reason ~= "") and (" (" .. tostring(reason) .. ")") or ""
        end
    end
    local c = flDB()
    local tr = c.fightTrack
    local n, days, _, bytes = fightLogStats(c)
    local nt, nd = 0, 0
    for _ in pairs(tr.sessions) do nt = nt + 1 end
    for _ in pairs(tr.done) do nd = nd + 1 end
    return ("  fights: api=%s meter=%s%s enc=%s deathRecap=%s state=%s reason=%s pending=%s sessions=%s maxSid=%s tracked=%d done=%d maxDone=%s resets=%s stored=%d/%dd %.0fKB gaps=%d unchanged=%d rekeyed=%d waits=%d polls=%d steps=%d ms=%s/%s err=%d%s")
        :format(tostring(api), avail, why, tostring(flStatus.encode or (type(_G.C_EncodingUtil) == "table" and "ready" or "none")),
            tostring(type(_G.C_DeathRecap) == "table"),
            flStatus.state, tostring(flStatus.lastReason), tostring(flStatus.pending),
            tostring(flStatus.sessions), tostring(flStatus.maxSid), nt, nd, tostring(tr.maxDone), tostring(tr.resets),
            n, days, bytes / 1024, flStatus.gaps, flStatus.unchanged, flStatus.rekeyed,
            flStatus.waits, flStatus.polls, flStatus.steps,
            tostring(flStatus.lastMs), tostring(flStatus.maxMs), flStatus.errors,
            flStatus.lastError and (" lastErr=" .. tostring(flStatus.lastError)) or "")
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
-- Entering combat: stop polling; do nothing in combat.
ns.On("PLAYER_REGEN_DISABLED", ns.FightsCombatStart)
-- Combat over: read now (same frame) if readable, else wait for the restriction to lift.
ns.On("PLAYER_REGEN_ENABLED", ns.FightsCombatEnd)
-- Documented on forever; ns.On returns false (and nothing breaks) on a client without them.
ns.On("ADDON_RESTRICTION_STATE_CHANGED", ns.FightsRestriction)
-- (type, sessionID); fires in combat too: only a table write then.
ns.On("DAMAGE_METER_COMBAT_SESSION_UPDATED", ns.FightsMeterUpdated)
ns.On("DAMAGE_METER_CURRENT_SESSION_UPDATED", ns.FightsNewCurrent)
ns.On("DAMAGE_METER_RESET", ns.FightsMeterReset)

local worldPending = false

ns.On("PLAYER_ENTERING_WORLD", function()
    if worldPending then return end
    worldPending = true
    -- Catch-up (e.g. after /reload); does nothing if in combat.
    ns.After(3, function()
        worldPending = false
        ns.FightsKick("entering_world")
    end)
end)
