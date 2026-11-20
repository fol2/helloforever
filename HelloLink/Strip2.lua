-- HelloLink / Strip2.lua
-- The live-state strip, format 2 (docs/specs/213.md): the frame, keyframes and deltas of the
-- fast part, the further level triples, and the order in which objects are sent. Strip.lua
-- draws the row and calls these when its format setting is 2. Section numbers are the spec's.
--
-- Nothing here reads the client but `unitGroups`, through the reads Strip.lua hands it.
local _, ns = ...

local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local S2 = {}
ns.Strip2 = S2

S2.VERSION, S2.KEYFRAME = 2, 128
S2.CHUNK = 128          -- the most bytes of chunk a frame (decision 7)
S2.REFRESH_EVERY = 8    -- with no new version waiting, a refresh chunk on every 8th frame
-- The further level triples (section 8): always five, black for a unit that is not there, so
-- the row's layout does not move when a party forms.
S2.MORE = { "targettarget", "party1", "party2", "party3", "party4" }

-- Section 6: the groups of format 1, then targettarget and pettarget.
local GROUPS = {
    { "clock", { "clock", 2 } },
    { "health", { "healthMax", 3 } },
    { "power", { "powerMax", 3 }, { "powerType", 1 } },
    { "level", { "level", 1 }, { "xp", 3 }, { "xpMax", 3 } },
    { "state", { "flags", 2 } },
    { "cast", { "spell", 3 }, { "tenths", 1 } },
    { "target", { "level", 1 }, { "flags", 1 }, { "nameHash", 2 } },
    { "pet", { "healthMax", 3 } },
    { "position", { "map", 2 }, { "x", 2 }, { "y", 2 }, { "facing", 1 } },
    { "purse", { "money", 4 }, { "bagFree", 1 } },
    { "hand", { "item", 3 }, { "enchant", 2 } },
    { "loot", { "counter", 1 }, { "item", 3 }, { "quantity", 1 } },
    { "uiError", { "error", 2 }, { "counter", 1 } },
    { "threat", { "player", 1 }, { "pet", 1 } },
    { "targettarget", { "level", 1 }, { "flags", 1 }, { "nameHash", 2 } },
    { "pettarget", { "level", 1 }, { "flags", 1 }, { "nameHash", 2 } },
}
S2.GROUPS = GROUPS
local POSITION = 9
local BIT = {}
for i = 1, 24 do BIT[i] = 2 ^ (24 - i) end

-- As Strip.lua's `put`: a whole number of `size` bytes, most significant first, at bytes[at + 1].
local TOP = { 255, 65535, 16777215, 4294967295 }
local function put(bytes, at, value, size)
    value = floor(max(0, min(value or 0, TOP[size])))
    for k = size, 1, -1 do
        bytes[at + k] = value % 256
        value = floor(value / 256)
    end
    return at + size
end
S2.put = put

-- A zigzag varint of the whole number `d` (section 6) at bytes[at + 1]; the place after it.
local function varint(bytes, at, d)
    local z = d >= 0 and 2 * d or -2 * d - 1
    repeat
        local low = z % 128
        z = floor(z / 128)
        at = at + 1
        bytes[at] = z > 0 and low + 128 or low
    until z == 0
    return at
end

-- The kept keyframe: the fields of each group as sent, and whether the group was known.
local key, keyHas = {}, {}
for i = 1, #GROUPS do key[i] = {} end
local keyLow, keyClock, keyMap   -- nil: no keyframe sent yet
local changed = {}               -- the changed groups of the delta being built (kept, #175)

-- Forgets the keyframe: the row starts afresh (a load, a change of format, depth or size).
function S2.reset()
    keyLow, keyClock, keyMap = nil, nil, nil
end

-- Whether this frame must be a keyframe (section 6, "The addon's rules").
function S2.keyDue(state)
    if keyLow == nil then return true end
    local c = state.clock
    if (c and c.clock) ~= keyClock then return true end
    local p = state.position
    if p and (not keyHas[POSITION] or p.map ~= keyMap) then return true end
    return false
end

local function differs(i, values)
    local g, k = GROUPS[i], key[i]
    for f = 2, #g do
        if values[g[f][1]] ~= k[g[f][1]] then return true end
    end
    return false
end

-- Takes the frame just drawn as the keyframe: its state and the low byte of its seq.
function S2.commit(state, low)
    for i = 1, #GROUPS do
        local g, values = GROUPS[i], state[GROUPS[i][1]]
        keyHas[i] = values and true or false
        if values then
            local k = key[i]
            for f = 2, #g do k[g[f][1]] = values[g[f][1]] end
        end
    end
    keyLow = low
    keyClock = state.clock and state.clock.clock
    keyMap = state.position and state.position.map
end

-- The fast part (section 6) at bytes[at + 1]; the place after it.
function S2.packFast(bytes, at, state, isKey)
    local mask, to = 0, at + 3
    if isKey then
        for i = 1, #GROUPS do
            local g = GROUPS[i]
            local values = state[g[1]]
            if values then
                mask = mask + BIT[i]
                for f = 2, #g do to = put(bytes, to, values[g[f][1]], g[f][2]) end
            end
        end
        put(bytes, at, mask, 3)
        return to
    end
    local n = 0
    for i = 1, #GROUPS do
        local values = state[GROUPS[i][1]]
        if (values and (not keyHas[i] or differs(i, values))) or (not values and keyHas[i]) then
            mask = mask + BIT[i]
            n = n + 1
            changed[n] = i
        end
    end
    put(bytes, at, mask, 3)
    -- `gone`: a bit a changed group, 1 for one unknown now, the first bit the most significant
    for b = 1, ceil(n / 8) do
        local byte = 0
        for k = 1, 8 do
            local c = changed[(b - 1) * 8 + k]
            if c and (b - 1) * 8 + k <= n and not state[GROUPS[c][1]] then byte = byte + 2 ^ (8 - k) end
        end
        to = to + 1
        bytes[to] = byte
    end
    for k = 1, n do
        local i = changed[k]
        local g = GROUPS[i]
        local values = state[g[1]]
        if values then
            if i == POSITION then
                local kp = key[POSITION]
                to = varint(bytes, to, values.x - kp.x)
                to = varint(bytes, to, values.y - kp.y)
                to = to + 1
                bytes[to] = values.facing
            else
                for f = 2, #g do to = put(bytes, to, values[g[f][1]], g[f][2]) end
            end
        end
    end
    return to
end

-- The frame (section 5) at bytes[1] on, without its check: the number of bytes. `seq` is the
-- seq this frame will have. `sending` is the chunk on the row, or nil.
function S2.frame(bytes, session, dwell, seq, isKey, state, sending)
    bytes[1] = S2.VERSION
    local n = put(bytes, 1, session, 2)
    bytes[n + 1] = dwell
    n = put(bytes, n + 1, seq, 2)
    bytes[n + 1] = isKey and S2.KEYFRAME or 0
    bytes[n + 2] = isKey and seq % 256 or keyLow
    local fastAt = n + 3                 -- bytes[fastAt] is fastLen
    local fastEnd = S2.packFast(bytes, fastAt, state, isKey)
    bytes[fastAt] = fastEnd - fastAt
    n = fastEnd
    if sending then
        local part = sending.chunks[sending.index]
        bytes[n + 1] = sending.id
        n = put(bytes, n + 1, sending.version, 2)
        bytes[n + 1], bytes[n + 2], bytes[n + 3] = sending.index - 1, #sending.chunks, #part
        n = n + 3
        for i = 1, #part do bytes[n + i] = part[i] end
        n = n + #part
    else
        n = n + 1
        bytes[n] = 0
    end
    return n
end

-- The longest head before a chunk: the frame head, a keyframe of every group, the object head.
S2.HEAD = 9 + 3 + 64 + 6 + 2

----------------------------------------------------------------------
-- Groups 15 and 16: a unit's level, flags and name hash, as group 7 for the target.
----------------------------------------------------------------------
local unitValues = { targettarget = {}, pettarget = {} }

-- `r` holds Strip.lua's reads: read, get, num, flag, nameHash, CLASSIFICATION.
function S2.unitGroups(state, r)
    for unit, g in pairs(unitValues) do
        state[unit] = nil
        local ok, exists = r.read("UnitExists", unit)
        if ok and exists then
            local level, name, class = r.num(r.get("UnitLevel", unit)), r.get("UnitName", unit), r.get("UnitClassification", unit)
            local f = type(class) == "string" and r.CLASSIFICATION[class] or nil
            f = r.flag(f, 128, "UnitCanAttack", "player", unit)
            f = r.flag(f, 64, "UnitIsDead", unit)
            f = r.flag(f, 8, "UnitIsTapDenied", unit)
            f = r.flag(f, 4, "UnitIsPlayer", unit)
            f = r.flag(f, 2, "UnitIsUnit", unit .. "target", "player")
            f = r.flag(f, 1, "UnitIsUnit", unit .. "target", "pet")
            if level and f and type(name) == "string" then
                g.level, g.flags, g.nameHash = level < 0 and 255 or level, f, r.nameHash(name)
                state[unit] = g
            end
        end
    end
end

----------------------------------------------------------------------
-- Which chunk goes next (section 7)
----------------------------------------------------------------------
local S = { idle = 0, nextAt = 0, rid = 0, rk = 0, rver = nil }
local current = {}   -- the table handed back for a chunk; Strip.lua keeps it as `sending`

function S2.resetSending()
    S.idle, S.nextAt, S.rid, S.rk, S.rver = 0, 0, 0, 0, nil
end

local function hand(id, o, chunks, index, new)
    current = { id = id, version = o.version, chunks = chunks, index = index, new = new }
    return current
end

-- The chunk to draw next, or nil for none. `sending` is the chunk whose time is up, or nil.
-- `refresh(id)` gives the object's newest version (Strip.lua's `refresh`), `chunks(o)` its
-- chunks. Decided once a dwell (`now`, `dwell` seconds).
function S2.nextSend(sending, ids, objects, refresh, chunks, now, dwell)
    if sending and sending.new then
        if sending.index < #sending.chunks then
            sending.index, sending.till = sending.index + 1, nil
            return sending
        end
        -- a version sent whole; the question (object 1) goes twice, then leaves
        local o = objects[sending.id]
        if o and o.version == sending.version then
            if o.rounds then
                o.rounds = o.rounds - 1
                if o.rounds <= 0 then o.obj, o.rounds = nil, nil end
            else
                o.sent = o.version
            end
        end
    end
    if not sending and now < S.nextAt then return nil end
    S.nextAt = now + dwell
    -- a version not yet sent whole: object 24 first, then the one that waits longest
    local best, bestAt
    for id = 1, ids do
        local o = refresh(id, now)
        if o and o.sent ~= o.version and chunks(o) then
            if id == 24 then best = id break end
            if not best or (o.changedAt or 0) < bestAt then best, bestAt = id, o.changedAt or 0 end
        end
    end
    if best then
        S.idle = 0
        local o = objects[best]
        return hand(best, o, chunks(o), 1, true)
    end
    S.idle = S.idle + 1
    if S.idle % S2.REFRESH_EVERY ~= 0 then return nil end
    -- the refresh: the next chunk of the round, the held objects in id order
    for step = 0, ids do
        local id = step == 0 and S.rid or (S.rid + step - 1) % ids + 1
        local o = id >= 1 and objects[id]
        local list = o and o.obj and chunks(o)
        if list then
            if step > 0 or S.rver ~= o.version then S.rk = 0 end
            if S.rk < #list then
                S.rid, S.rk, S.rver = id, S.rk + 1, o.version
                return hand(id, o, list, S.rk, false)
            end
        end
    end
    return nil
end
