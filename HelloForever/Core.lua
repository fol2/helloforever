-- HelloForever / Core.lua
-- Shared plumbing for every other file: guarded API calls, secret-value handling, timers,
-- the SavedVariables root, one event frame with a handler table, debounce and
-- "after combat" queues.
--
-- Client: WoW Forever (game type "camelot", TOC 16001). It runs the modern (12.x) UI
-- architecture: no combat log for addons, and many values are *secret* while a
-- restriction is active. Tainted code may store and pass a secret, but arithmetic,
-- comparison, indexing, using it as a table key, or testing a secret boolean throws.
-- Everything read from the client therefore goes through ns.Call / ns.Plain first.
local addonName, ns = ...

local type, pcall, select, pairs, tostring = type, pcall, select, pairs, tostring
local floor = math.floor
local GetTime, time = GetTime, time

ns.name = addonName
ns.PREFIX = "|cff33ff99HelloForever|r"

----------------------------------------------------------------------
-- Secret values
----------------------------------------------------------------------
local issecretvalue = _G.issecretvalue
local HAS_SECRETS = type(issecretvalue) == "function"

-- issecretvalue is a plain C predicate that accepts any value, so it is called directly
-- (no pcall): the fight reader runs it once per copied value.
local isSecret = HAS_SECRETS and issecretvalue or function() return false end
ns.IsSecret = isSecret

-- The value itself when it is safe to use, else nil.
local function plain(v)
    if isSecret(v) then return nil end
    return v
end
ns.Plain = plain

local function scrub(ok, a, b, c, d, e, f, g, h)
    if not ok then return nil end
    if HAS_SECRETS then
        if isSecret(a) then a = nil end
        if isSecret(b) then b = nil end
        if isSecret(c) then c = nil end
        if isSecret(d) then d = nil end
        if isSecret(e) then e = nil end
        if isSecret(f) then f = nil end
        if isSecret(g) then g = nil end
        if isSecret(h) then h = nil end
    end
    return a, b, c, d, e, f, g, h
end

-- pcall an API that may be absent on this client. Errors and secret returns become nil,
-- so callers can do arithmetic / comparisons on whatever comes back.
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    return scrub(pcall(fn, ...))
end
ns.Call = call

local function packAll(ok, ...)
    if not ok then return nil end
    local n = select("#", ...)
    local out = { n = n, ... }
    if HAS_SECRETS then
        for i = 1, n do
            if isSecret(out[i]) then out[i] = nil end
        end
    end
    return out
end

-- Like ns.Call but returns every result as a list with .n (nil holes preserved).
function ns.CallAll(fn, ...)
    if type(fn) ~= "function" then return nil end
    return packAll(pcall(fn, ...))
end

----------------------------------------------------------------------
-- Timers
----------------------------------------------------------------------
local CT = _G.C_Timer
local hasAfter = type(CT) == "table" and type(CT.After) == "function"
local hasTicker = type(CT) == "table" and type(CT.NewTicker) == "function"

function ns.After(sec, fn)
    if hasAfter then
        CT.After(sec, fn)
        return
    end
    local f = CreateFrame("Frame")
    local t0 = GetTime()
    f:SetScript("OnUpdate", function(self)
        if GetTime() - t0 >= sec then
            self:SetScript("OnUpdate", nil)
            fn()
        end
    end)
end

-- Returns an object with :Cancel().
function ns.Ticker(sec, fn, iterations)
    if hasTicker then return CT.NewTicker(sec, fn, iterations) end
    local f = CreateFrame("Frame")
    local acc, left = 0, iterations
    f:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        if acc >= sec then
            acc = acc - sec
            if left then
                left = left - 1
                if left <= 0 then self:SetScript("OnUpdate", nil) end
            end
            fn()
        end
    end)
    function f:Cancel() self:SetScript("OnUpdate", nil) end
    return f
end

----------------------------------------------------------------------
-- Version stamps (computed once; neither changes during a session)
-- VERSION_FALLBACK MUST equal ## Version in HelloForever.toc. The TOC is
-- the source of truth at runtime (GetAddOnMetadata); the fallback is only
-- used if metadata is missing (e.g. a truncated load).
----------------------------------------------------------------------
ns.VERSION_FALLBACK = "0.8.1"
ns.SOURCE_REVISION = "0.8.1" -- bump at each release; a constant is enough
ns.SCHEMA_VERSION = 6        -- SavedVariables / export envelope (see docs/SCHEMA.md)

local VERSION_FALLBACK = ns.VERSION_FALLBACK

local function readVersion()
    local v
    local CA = _G.C_AddOns
    if type(CA) == "table" then v = call(CA.GetAddOnMetadata, addonName, "Version") end
    if type(v) ~= "string" or v == "" then v = call(_G.GetAddOnMetadata, addonName, "Version") end
    if type(v) == "string" and v ~= "" then return v end
    return VERSION_FALLBACK
end
ns.version = readVersion()

local clientInfo
-- GetBuildInfo returns version, build, date, tocversion.
function ns.ClientInfo()
    if not clientInfo then
        local r = ns.CallAll(_G.GetBuildInfo) or {}
        clientInfo = { version = r[1], build = r[2], date = r[3], toc = r[4] }
    end
    return clientInfo
end

local INSTALL_ID_PAT = "^[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$"

-- Per-SavedVariables install id: unique across two machines (two Macs, two
-- WTF folders) without using account/character names. Lua 5.1 has no CSPRNG, so
-- several weak sources are mixed through ns.Hash: wall clock, uptime, the
-- high-resolution profiler clock, the client's RNG and the address of a fresh
-- table (differs per process). The shared RNG is never reseeded: other addons
-- use it, and math.randomseed is not guaranteed to exist in the client.
function ns.NewInstallId()
    local prof = _G.debugprofilestop
    local rnd = math.random
    local parts = {
        tostring(time()), tostring(GetTime()),
        tostring(type(prof) == "function" and call(prof) or 0),
        tostring(type(rnd) == "function" and call(rnd, 1, 2147483646) or 0),
        tostring(type(rnd) == "function" and call(rnd, 1, 2147483646) or 0),
        tostring({}),
    }
    return ns.Hash(table.concat(parts, "|"))
end

function ns.InstallId()
    local d = ns.db
    if not d then d = ns.InitDB() end
    return d.installId
end

-- Envelope on every snapshot, fight record and the SV root. Pipeline keys:
-- addonVersion, sourceRevision, schemaVersion, gameBuild (GetBuildInfo build), installId.
-- The SV root and snapshots also carry `client` (version, build, date, toc); a fight
-- record is stored hundreds of times, so with `slim` it keeps gameBuild and leaves the
-- rest of the client table to the root.
function ns.ExportMeta(dest, slim)
    if type(dest) ~= "table" then dest = {} end
    dest.addonVersion = ns.version
    dest.sourceRevision = ns.SOURCE_REVISION
    dest.schemaVersion = ns.SCHEMA_VERSION
    local cl = ns.ClientInfo()
    if not slim then dest.client = cl end
    dest.gameBuild = cl.build
    dest.installId = ns.InstallId()
    return dest
end

function ns.Stamp(snap)
    if type(snap) ~= "table" then return snap end
    return ns.ExportMeta(snap)
end

----------------------------------------------------------------------
-- Fight IDs
-- New (schemaVersion >= 6):  hf1-<installId>-<unixStart>-<sessionId>-<seq>
--   PCRE: ^hf1-[0-9a-f]{8}-\d+-\d+-\d+$
-- Legacy (kept forever; never rewritten):
--   ^\d+-\d+$            unixStart-sessionId
--   ^\d+-\d+-\d+$        unixStart-sessionId-n   (old collision suffix)
-- Combined importer: ^(?:hf1-[0-9a-f]{8}-\d+-\d+-\d+|\d+-\d+(?:-\d+)?)$
-- seq is always present on hf1 keys so uniqueness does not look like an
-- optional suffix on a two-part id (the form wow-data previously rejected).
----------------------------------------------------------------------
ns.FIGHT_KEY_FORMAT = "hf1"
ns.FIGHT_KEY_PCRE = "^(?:hf1-[0-9a-f]{8}-\\d+-\\d+-\\d+|\\d+-\\d+(?:-\\d+)?)$"

function ns.MakeFightKey(installId, start, sid, seq)
    seq = tonumber(seq) or 1
    if seq < 1 then seq = 1 end
    return ("hf1-%s-%s-%s-%s"):format(
        tostring(installId or ns.InstallId()),
        tostring(floor(tonumber(start) or 0)),
        tostring(floor(tonumber(sid) or 0)),
        tostring(floor(seq))
    )
end

-- 32-bit djb2; used for gear/talent/pet context ids (not crypto).
function ns.Hash(s)
    s = tostring(s or "")
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 4294967296
    end
    return ("%08x"):format(h)
end

local function sortedJoin(t, prefix)
    if type(t) ~= "table" then return prefix .. ns.Hash("") end
    local keys = {}
    for k in pairs(t) do
        local tk = type(k)
        if tk == "string" or tk == "number" then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for i = 1, #keys do
        local k = keys[i]
        parts[i] = tostring(k) .. "=" .. tostring(t[k])
    end
    return prefix .. ns.Hash(table.concat(parts, "|"))
end

function ns.HashGear(eq)
    return sortedJoin(eq, "g-")
end

function ns.HashTalents(tal)
    if type(tal) ~= "table" then return "t-" .. ns.Hash("") end
    local parts = { tostring(tal.spent), tostring(tal.unspent) }
    local nodes = tal.nodes
    if type(nodes) == "table" then
        for i = 1, #nodes do
            local n = nodes[i]
            if type(n) == "table" then
                parts[#parts + 1] = tostring(n.n) .. ":" .. tostring(n.r) .. ":" .. tostring(n.s)
            end
        end
    end
    return "t-" .. ns.Hash(table.concat(parts, "|"))
end

function ns.HashPet(pet)
    if type(pet) ~= "table" then return "p-" .. ns.Hash("") end
    local parts = { tostring(pet.kind), tostring(pet.name), tostring(pet.family), tostring(pet.level) }
    local ab = pet.abilities
    if type(ab) == "table" then
        for i = 1, #ab do
            local a = ab[i]
            if type(a) == "table" then
                parts[#parts + 1] = tostring(a.spellID) .. ":" .. tostring(a.rank) .. ":" .. tostring(a.autocast)
            end
        end
    end
    return "p-" .. ns.Hash(table.concat(parts, "|"))
end

ns.FRESH_OK, ns.FRESH_UNAVAIL, ns.FRESH_STALE = "ok", "unavailable", "stale"

-- observedAt is the last SUCCESSFUL read of a section. "stale" / "unavailable" keep
-- the time already recorded (or `at`); a section that was never read has no observedAt.
function ns.SetFresh(snap, name, status, at)
    if type(snap) ~= "table" or type(name) ~= "string" then return end
    status = status or "ok"
    local fr = snap.freshness
    if type(fr) ~= "table" then
        fr = {}
        snap.freshness = fr
    end
    local row = fr[name]
    if type(row) ~= "table" then
        row = {}
        fr[name] = row
    end
    if status == "ok" then
        row.observedAt = at or time()
    elseif at then
        row.observedAt = at
    end
    row.status = status
end

-- Quest log / history state. Unknown is returned when the client cannot tell
-- accepted apart from ready (no complete flag, no objectives) — never guessed.
--   accepted | in_progress | ready | failed | completed | abandoned | unknown
function ns.ClassifyQuest(q)
    if type(q) ~= "table" then return "unknown" end
    if not q.inLog then
        if q.flaggedCompleted then return "completed" end
        if q.wasInLog then return "abandoned" end
        return "unknown"
    end
    if q.failed or q.isComplete == -1 then return "failed" end
    if q.isComplete == 1 or q.isComplete == true then return "ready" end
    -- objectivesDone / objectivesTotal count finished objectives; `progress` is true when
    -- any objective has moved at all (3/8 kills is progress with nothing finished yet).
    local tot = tonumber(q.objectivesTotal) or 0
    local done = tonumber(q.objectivesDone) or 0
    if tot > 0 and done >= tot then return "ready" end
    if tot > 0 and (done > 0 or q.progress) then return "in_progress" end
    if tot > 0 then return "accepted" end
    if q.isComplete == false then return "accepted" end
    return "unknown"
end

function ns.ParseFightKey(key)
    if type(key) ~= "string" then return nil end
    local inst, start, sid, seq = key:match(
        "^hf1%-([0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])%-([0-9]+)%-([0-9]+)%-([0-9]+)$")
    if inst then
        return { format = "hf1", installId = inst, start = tonumber(start), sid = tonumber(sid), seq = tonumber(seq) }
    end
    local a, b, c = key:match("^([0-9]+)%-([0-9]+)%-([0-9]+)$")
    if a then
        return { format = "legacy_suffix", start = tonumber(a), sid = tonumber(b), seq = tonumber(c) }
    end
    a, b = key:match("^([0-9]+)%-([0-9]+)$")
    if a then
        return { format = "legacy", start = tonumber(a), sid = tonumber(b), seq = 1 }
    end
    return nil
end

----------------------------------------------------------------------
-- SavedVariables root + per-character table
----------------------------------------------------------------------
local DEFAULTS = {
    combatLog = "off", -- "off" | "on" | "auto"
    shown = true,      -- XP panel visible
    locked = false,    -- XP panel cannot be dragged
    scale = 1,         -- XP panel scale
    announce = false,  -- one chat line per captured fight
    budgetMB = 3,      -- fight-log size budget per character
}
ns.DEFAULTS = DEFAULTS

local db, char, charKey

function ns.InitDB()
    local d = _G.HelloForeverDB
    if type(d) ~= "table" then
        d = {}
        _G.HelloForeverDB = d
    end
    if d ~= db then char, charKey = nil, nil end
    db = d
    d.addonVersion = ns.version
    d.sourceRevision = ns.SOURCE_REVISION
    d.schemaVersion = ns.SCHEMA_VERSION
    if type(d.installId) ~= "string" or not d.installId:match(INSTALL_ID_PAT) then
        d.installId = ns.NewInstallId()
    end
    local cl = ns.ClientInfo()
    d.gameBuild = cl.build
    d.client = cl
    if type(d.settings) ~= "table" then d.settings = {} end
    local s = d.settings
    for k, v in pairs(DEFAULTS) do
        if s[k] == nil then s[k] = v end
    end
    if type(d.characters) ~= "table" then d.characters = {} end
    ns.db, ns.settings = d, s
    return d
end

-- The current character's table and its "Name-Realm" key. Cached once the name is known,
-- so hot paths do not rebuild the key (two API calls and a string) on every use.
function ns.Char()
    if char and _G.HelloForeverDB == db then return char, charKey end
    local d = ns.InitDB()
    local name, realm = call(UnitName, "player"), call(GetRealmName)
    local known = type(name) == "string" and name ~= "" and name ~= _G.UNKNOWNOBJECT
        and type(realm) == "string" and realm ~= ""
    local key = tostring(name or "Unknown") .. "-" .. tostring(realm or "Unknown")
    local c = d.characters[key]
    if type(c) ~= "table" then
        c = { timeline = {}, events = {}, _tlCount = 0 }
        d.characters[key] = c
    end
    if type(c.timeline) ~= "table" then c.timeline = {} end
    if type(c.events) ~= "table" then c.events = {} end
    c._tlCount = c._tlCount or 0
    if known then char, charKey = c, key end
    return c, key
end

function ns.CharKey()
    local _, key = ns.Char()
    return key
end

-- Keep an append-only list at or below `cap`: once it grows past the cap, drop the oldest
-- entries in one pass (`slack` at a time) instead of shifting the whole list per insert.
local function trimHead(list, cap, slack)
    local n = #list
    if n <= cap then return 0 end
    local drop = n - cap + (slack or 0)
    if drop > n then drop = n end
    for i = 1, n - drop do list[i] = list[i + drop] end
    for i = n - drop + 1, n do list[i] = nil end
    return drop
end
ns.TrimHead = trimHead

local EVENTS_CAP = 500

function ns.PushEvent(kind, extra)
    local c = ns.Char()
    local e = { t = time(), kind = kind }
    if type(extra) == "table" then
        for k, v in pairs(extra) do e[k] = v end
    end
    local ev = c.events
    ev[#ev + 1] = e
    trimHead(ev, EVENTS_CAP, 25)
end

----------------------------------------------------------------------
-- Events: one frame, one OnEvent, a handler table keyed by event name
----------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}
ns.eventFrame = eventFrame

-- What this client did with each event the addon asked for: false = it does not know the
-- event, a number = how many times it has fired this session. Read by /hello selftest.
local eventLog = {}
ns.eventLog = eventLog

-- Register `fn(...)` for an event. Returns false when this client does not know the event
-- (RegisterEvent throws for unknown names), so optional events degrade quietly.
function ns.On(event, fn)
    local h = handlers[event]
    if not h then
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
            eventLog[event] = false
            return false
        end
        eventLog[event] = 0
        handlers[event] = fn
    elseif type(h) == "function" then
        handlers[event] = { h, fn }
    else
        h[#h + 1] = fn
    end
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local h = handlers[event]
    if not h then return end
    eventLog[event] = (eventLog[event] or 0) + 1
    if type(h) == "function" then
        h(...)
    else
        for i = 1, #h do h[i](...) end
    end
end)

-- Internal notifications between files (e.g. "a fight was stored" -> refresh the UI).
-- Listener errors are contained so the UI can never break data capture.
local listeners = {}

function ns.Listen(what, fn)
    local l = listeners[what]
    if not l then
        l = {}
        listeners[what] = l
    end
    l[#l + 1] = fn
end

function ns.Notify(what, ...)
    local l = listeners[what]
    if not l then return end
    for i = 1, #l do pcall(l[i], ...) end
end

----------------------------------------------------------------------
-- Debounce: run now, then coalesce everything inside the window into ONE trailing call.
-- (A plain throttle drops the last change of a burst: swapping two items within the
-- window used to leave the second one out of the snapshot until the next relog.)
----------------------------------------------------------------------
local debounce = {}

function ns.Debounce(key, sec, fn)
    local p = debounce[key]
    if not p then
        p = { last = -1e9 }
        debounce[key] = p
    end
    if p.queued then return end
    local now = GetTime()
    local wait = sec - (now - p.last)
    if wait <= 0 then
        p.last = now
        fn()
        return
    end
    p.queued = true
    ns.After(wait, function()
        p.queued = nil
        p.last = GetTime()
        fn()
    end)
end

----------------------------------------------------------------------
-- Combat: stats and talents can be secret (or simply noisy) mid-fight, and nothing
-- here is urgent, so snapshot work asked for in combat runs shortly after it ends.
----------------------------------------------------------------------
local ICL = _G.InCombatLockdown

function ns.InCombat()
    return type(ICL) == "function" and ICL() and true or false
end

local queue, queued = {}, 0

-- Runs fn now when out of combat (returns true); otherwise keeps the latest fn per key
-- and runs it ~2 s after combat ends (returns false).
function ns.AfterCombat(key, fn)
    if not ns.InCombat() then
        fn()
        return true
    end
    if not queue[key] then queued = queued + 1 end
    queue[key] = fn
    return false
end

local flushPending = false

local function flush()
    flushPending = false
    if queued == 0 or ns.InCombat() then return end
    local q = queue
    queue, queued = {}, 0
    for _, fn in pairs(q) do pcall(fn) end
end

ns.On("PLAYER_REGEN_ENABLED", function()
    if queued > 0 and not flushPending then
        flushPending = true
        ns.After(2, flush)
    end
end)

----------------------------------------------------------------------
-- Formatting
----------------------------------------------------------------------
function ns.FmtNum(n)
    n = tonumber(n) or 0
    if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
    if n >= 10000 then return ("%.1fk"):format(n / 1000) end
    return tostring(floor(n + 0.5))
end

-- 3725 -> "1h 02m", 125 -> "2m 05s", 42 -> "42s"
function ns.FmtDur(sec)
    sec = floor((tonumber(sec) or 0) + 0.5)
    if sec < 0 then sec = 0 end
    if sec >= 3600 then return ("%dh %02dm"):format(floor(sec / 3600), floor(sec % 3600 / 60)) end
    if sec >= 60 then return ("%dm %02ds"):format(floor(sec / 60), sec % 60) end
    return sec .. "s"
end

-- Copper -> "12g 34s 56c" with coin colours.
function ns.FmtMoney(copper)
    copper = floor((tonumber(copper) or 0) + 0.5)
    local neg = copper < 0
    if neg then copper = -copper end
    local g, s, c = floor(copper / 10000), floor(copper % 10000 / 100), copper % 100
    local out
    if g > 0 then
        out = ("|cffffd700%dg|r |cffc7c7cf%ds|r"):format(g, s)
    elseif s > 0 then
        out = ("|cffc7c7cf%ds|r |cffeda55f%dc|r"):format(s, c)
    else
        out = ("|cffeda55f%dc|r"):format(c)
    end
    return neg and ("-" .. out) or out
end

function ns.Print(msg)
    print(ns.PREFIX .. ": " .. tostring(msg))
end

ns.On("ADDON_LOADED", function(name)
    if name == addonName then ns.InitDB() end
end)
