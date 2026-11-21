-- HelloLink / Strip.lua
-- The live-state strip, format 1 (docs/specs/29.md): one row of squares at the top edge of the
-- game that a program outside reads from the screen. Section numbers are those of the spec;
-- tools/strip1.py is the same format in Python and reads what this draws.
--
-- This file only shows what the client lets an addon read or what the client colours itself.
-- It presses no key, casts nothing and moves nothing.
local _, ns = ...

-- Format 2 (docs/specs/213.md): the frame, keyframes and deltas of the fast part, groups 15 and
-- 16, and the order in which objects are sent, as `ns.Strip2`. In a block of its own at the head
-- of this file: its locals end with the block, so they do not count against the main chunk's
-- 200 (it has no room for another), and no file is added to the TOC, which the client reads
-- only at its start (a /reload loads this file anew, but not a file new to the TOC).
do
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
    local keyAt                      -- when it was drawn, by the addon's own clock (GetTime)
    local changed = {}               -- the changed groups of the delta being built (kept, #175)

    -- Forgets the keyframe: the row starts afresh (a load, a change of format, depth or size).
    function S2.reset()
        keyLow, keyClock, keyMap, keyAt = nil, nil, nil, nil
    end

    -- Whether this frame must be a keyframe (section 6, "The addon's rules"). `now` is the addon's
    -- own clock: a keyframe at least once a second also when the client's clock stands still.
    function S2.keyDue(state, now)
        if keyLow == nil then return true end
        if now and keyAt and now - keyAt >= 1 then return true end
        local c = state.clock
        if (c and c.clock) ~= keyClock then return true end
        local p = state.position
        if p and (not keyHas[POSITION] or p.map ~= keyMap) then return true end   -- known now, none in the keyframe
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
    function S2.commit(state, low, now)
        keyAt = now
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
    local S = { idle = 0, nextAt = 0, rid = 0, rk = 0, rver = nil, scan = 0, tick = 0 }
    local current = {}   -- the table handed back for a chunk; Strip.lua keeps it as `sending`

    function S2.resetSending()
        S.idle, S.nextAt, S.rid, S.rk, S.rver, S.scan, S.tick = 0, 0, 0, 0, nil, 0, 0
    end

    local function hand(id, o, chunks, index, new)
        -- one table, refilled (#175): Strip.lua keeps it as `sending` and sets its `till`
        current.id, current.version, current.chunks, current.index, current.new, current.till = id, o.version, chunks, index, new, nil
        current.again = nil
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
                    -- format 3: a new version goes whole once again 1 s later (docs/specs/232.md)
                    -- (a send once again that began before a later request leaves that request
                    -- waiting: a stall during it asks for one more; an earlier due time stays)
                    if S2.three and sending.again then
                        if (o.againSince or 0) <= (sending.startedAt or 0) then o.againAt = nil end
                    elseif S2.three and not (o.againAt and o.againVer == o.version and o.againAt <= now + 1) then
                        o.againAt, o.againVer, o.againSince = now + 1, o.version, now
                    end
                end
            end
        end
        if not sending and now < S.nextAt then return nil end
        S.nextAt = now + dwell
        -- One id every second decision is built afresh, in turn (Strip.lua's refresh: only when it was
        -- marked changed). Each id comes round in about 4.6 s, as format 1's carousel reads them: no
        -- more memory or work than format 1 (tests/strip_perf_test.lua).
        S.tick = S.tick + 1
        -- the unit table (24) is built every 5th decision, besides its turn: party and raid units
        -- are asked for every 0.2 to 0.5 s (#213)
        if ids >= 24 and S.tick % 5 == 0 then refresh(24, now) end
        if S.tick % 2 == 0 then
            S.scan = S.scan % ids + 1
            refresh(S.scan, now)
        end
        -- every 8th decision is the refresh's, so that changes that never stop cannot starve it
        S.idle = S.idle + 1
        if S.idle % S2.REFRESH_EVERY == 0 then
            -- the version the round began is sent to its end, also when a newer one came
            -- meanwhile (a large object that changes often would never be sent whole)
            if S.rlist and S.rk < #S.rlist then
                S.rk = S.rk + 1
                local o = objects[S.rid]
                if o then
                    current.id, current.version, current.chunks, current.index, current.new, current.till =
                        S.rid, S.rver, S.rlist, S.rk, false, nil
                    current.again = nil
                    return current
                end
            end
            for step = 0, ids do
                local id = step == 0 and S.rid or (S.rid + step - 1) % ids + 1
                local o = id >= 1 and objects[id]
                local list = o and o.obj and chunks(o)
                if list and step == 0 then list = nil end   -- the object the round was on: done
                if list then
                    S.rid, S.rk, S.rver, S.rlist = id, 1, o.version, list
                    return hand(id, o, list, 1, false)
                end
            end
        end
        -- a version not yet sent whole: object 24 first, then the one that waits longest
        local best, bestAt
        for id = 1, ids do
            local o = objects[id]
            if o and not o.obj then o = nil end
            -- object 25 (names) goes by the refresh only (section 7)
            if o and id ~= 25 and o.sent ~= o.version and chunks(o) then
                if id == 24 then best = id break end
                if not best or (o.changedAt or 0) < bestAt then best, bestAt = id, o.changedAt or 0 end
            end
        end
        if best then
            local o = objects[best]
            return hand(best, o, chunks(o), 1, true)
        end
        -- format 3: a version due to go once again, after every new one (the refresh keeps its
        -- 8th decisions above)
        for id = 1, S2.three and ids or 0 do
            local o = objects[id]
            if o and o.againAt and o.againVer ~= o.version then o.againAt = nil end
            if o and o.obj and o.againAt and now >= o.againAt and chunks(o) then
                local c = hand(id, o, chunks(o), 1, true)
                c.again, c.startedAt = true, now
                return c
            end
        end
        return nil
    end

    ----------------------------------------------------------------------
    -- Objects 24 to 27 (section 7): units, names, auras, cooldowns. Format 2 only. Every value
    -- from the client goes through `r.plain` (a secret one is nil) before anything else: before
    -- `type`, a comparison or a sum.
    ----------------------------------------------------------------------
    -- A JSON string; most here (references, tokens, class names) need no escape, and so ask
    -- for no memory (Strip.lua's jsonString makes a function each call).
    local function q(r, s)
        if s:find("[%c\"\\]") then return r.jsonString(s) end
        return "\"" .. s .. "\""
    end
    -- A number the client gave, or nil when it is secret or no number.
    local function n(r, v)
        return r.num(r.plain(v))
    end
    S2.SECRET = {}   -- a text function's answer for format 253: the client keeps it secret now
    S2.IDS = 27      -- format 2's object ids, 1 to this
    local names, nameCount = {}, 0   -- "C:740" -> { name, hash, seen }: what object 25 sends
    local NAME_LIFE, NAMES_MAX = 300, 200

    -- A reference "<kind>:<id>:<hash>" for a creature, a spell or an item with a name; the name is
    -- kept for object 25 while there is room (a full list never costs a reference). nil when the
    -- id or the name cannot be read.
    -- A reference's id and hash, its name kept for object 25; nil for a thing with no id or name.
    -- Format 3's binary objects write the two numbers (`refB`); JSON writes `ref`'s text.
    function S2.refParts(r, kind, id, name, now)
        id, name = r.plain(id), r.plain(name)
        if type(id) == "string" then id = tonumber(id) end   -- a creature's id comes from its GUID as text
        id = r.num(id)
        if not id or id < 1 or type(name) ~= "string" or name == "" then return nil end
        id = floor(id)
        local nameKey = kind .. ":" .. id
        local hash = r.nameHash(name)
        local kept = names[nameKey]
        if not kept and nameCount < NAMES_MAX then
            kept = {}
            names[nameKey], nameCount = kept, nameCount + 1
        end
        if kept then kept.name, kept.hash, kept.seen = name, hash, now end
        return id, hash, nameKey
    end
    local function ref(r, kind, id, name, now)
        local whole, hash, nameKey = S2.refParts(r, kind, id, name, now)
        if not whole then return nil end
        return nameKey .. ":" .. hash
    end

    -- A unit's reference: a creature by its npc id; a player, or a player's pet, by a hash of its
    -- GUID with no name (decision 13).
    -- Gives the reference's text, then its kind, id and hash (format 3's binary objects).
    local function who(r, unit, now)
        local guid = r.plain(r.get("UnitGUID", unit))
        if type(guid) ~= "string" then return nil end
        if guid:match("^Player%-") or guid:match("^Pet%-") then
            local h = r.nameHash(guid)
            return ("P:%d:0"):format(h), "P", h, 0
        end
        local cid = r.creatureId(guid)
        local id, hash, nameKey = S2.refParts(r, "C", cid, r.get("UnitName", unit), now)
        if not id then return nil end
        return nameKey .. ":" .. hash, "C", id, hash
    end

    local UNITS = { "focus", "mouseover" }
    for i = 1, 4 do UNITS[#UNITS + 1] = "party" .. i end
    for i = 1, 4 do UNITS[#UNITS + 1] = "partypet" .. i end
    for i = 1, 40 do UNITS[#UNITS + 1] = "raid" .. i end
    for i = 1, 5 do UNITS[#UNITS + 1] = "boss" .. i end
    local FAST_UNITS = { "player", "pet", "target" }   -- a target that is one of these is named so
    local PLATES = {}
    for i = 1, 40 do PLATES[i] = "nameplate" .. i end

    -- tables kept for the reads of every unit (#175): no new table a unit
    local classValues, castValues, channelValues = {}, {}, {}
    -- One unit's values, read into the kept table U (#175): the JSON and the binary writers both
    -- take them from here, so that the two formats say the same. Nil when the unit has no reference.
    local U = {}
    local function unitRead(r, unit, now, byGuid)
        local id, kind, wid, whash = who(r, unit, now)
        if not id then return nil end
        U.id, U.kind, U.wid, U.whash = id, kind, wid, whash
        local level = n(r, r.get("UnitLevel", unit))
        U.level = level and (level < 0 and -1 or floor(level)) or -1
        local okClass, classes = r.readInto(classValues, "UnitClass", unit)
        local file = okClass and r.plain(classes[2]) or nil
        U.file = type(file) == "string" and file or nil
        local classification = r.plain(r.get("UnitClassification", unit))
        U.class = type(classification) == "string" and classification or nil
        local f = 0
        f = r.flag(f, 1, "UnitIsDead", unit)
        f = r.flag(f, 2, "UnitAffectingCombat", unit)
        f = r.flag(f, 4, "UnitCanAttack", "player", unit)
        f = r.flag(f, 8, "UnitIsConnected", unit)
        U.flags = f and floor(f) or nil
        local tguid = r.plain(r.get("UnitGUID", unit .. "target"))
        U.target = nil
        if type(tguid) == "string" then
            U.target = byGuid[tguid] or who(r, unit .. "target", now)
        end
        local threat = n(r, r.get("UnitThreatSituation", "player", unit))
        U.threat = threat and floor(threat) or nil
        local mark = n(r, r.get("GetRaidTargetIndex", unit))
        U.mark = mark and floor(mark) or nil
        local okCast, cast = r.readInto(castValues, "UnitCastingInfo", unit)
        local sid, shash, skey
        if okCast then sid, shash, skey = S2.refParts(r, "S", cast[9], cast[1], now) end
        if not sid then
            local okChannel, channel = r.readInto(channelValues, "UnitChannelInfo", unit)
            if okChannel then sid, shash, skey = S2.refParts(r, "S", channel[8], channel[1], now) end
        end
        U.sid, U.shash, U.spell = sid, shash, sid and (skey .. ":" .. shash) or nil
        return U
    end
    local function unitJson(r, unit, now, byGuid)
        if not unitRead(r, unit, now, byGuid) then return nil end
        return ('[%s, %d, %s, %s, %s, %s, %s, %s, %s]'):format(q(r, U.id), U.level,
            U.file and q(r, U.file) or "null", U.class and q(r, U.class) or "null",
            U.flags or "null", U.target and q(r, U.target) or "null", U.threat or "null", U.mark or "null",
            U.spell and q(r, U.spell) or "null")
    end

    -- The units that exist, all of them first, so that a unit's target names any of them by its
    -- token (a party member that targets a later one).
    local parts, byGuid, present, presentCount, plates = {}, {}, {}, 0, {}
    local function unitsPresent(r)
        for k in pairs(byGuid) do byGuid[k] = nil end
        for _, unit in ipairs(FAST_UNITS) do
            local g = r.plain(r.get("UnitGUID", unit))
            if type(g) == "string" then byGuid[g] = unit end
        end
        presentCount = 0
        for _, unit in ipairs(UNITS) do
            local ok, exists = r.read("UnitExists", unit)
            if ok and exists then
                presentCount = presentCount + 1
                present[presentCount] = unit
                local g = r.plain(r.get("UnitGUID", unit))
                if type(g) == "string" and not byGuid[g] then byGuid[g] = unit end
            end
        end
    end
    function S2.unitsText()
        local r, now = S2.reads, _G.GetTime and _G.GetTime() or 0
        unitsPresent(r)
        local count = 0
        for i = 1, presentCount do
            local unit = present[i]
            local j = unitJson(r, unit, now, byGuid)
            if j then count = count + 1; parts[count] = q(r, unit) .. ": " .. j end
        end
        for i = #plates, 1, -1 do plates[i] = nil end
        for i = 1, 40 do
            local unit = PLATES[i]
            local ok, exists = r.read("UnitExists", unit)
            if ok and exists then
                local j = unitJson(r, unit, now, byGuid)
                if j then plates[#plates + 1] = j end
            end
        end
        count = count + 1
        parts[count] = '"nameplates": [' .. table.concat(plates, ", ") .. "]"
        return "{" .. table.concat(parts, ", ", 1, count) .. "}"
    end

    -- The names the fast data names (section 7): the target's, the target of target's, the pet's
    -- target, the cast, the main hand and the last loot. Noted once a second.
    local fastCast = {}
    function S2.noteFast(now)
        local r = S2.reads
        for _, unit in ipairs({ "target", "targettarget", "pettarget" }) do
            local guid = r.plain(r.get("UnitGUID", unit))
            local id = type(guid) == "string" and r.creatureId(guid)
            if id then ref(r, "C", id, r.get("UnitName", unit), now) end
        end
        local okCast, cast = r.readInto(fastCast, "UnitCastingInfo", "player")
        if okCast then ref(r, "S", cast[9], cast[1], now) end
        local okChannel, channel = r.readInto(fastCast, "UnitChannelInfo", "player")
        if okChannel then ref(r, "S", channel[8], channel[1], now) end
        local mainHand = r.get("GetInventoryItemID", "player", 16)
        if mainHand then ref(r, "I", mainHand, r.get("C_Item.GetItemNameByID", mainHand), now) end
        local looted = S2.lootItem and S2.lootItem()
        if looted then ref(r, "I", looted, r.get("C_Item.GetItemNameByID", looted), now) end
    end

    -- Object 25: the names named in the last 5 minutes. Sent by the refresh only (section 7).
    -- The names still alive, their keys in order; the old ones forgotten.
    local function namesList()
        local now, list = _G.GetTime and _G.GetTime() or 0, {}
        for nameKey, kept in pairs(names) do
            if now - kept.seen > NAME_LIFE then
                names[nameKey], nameCount = nil, nameCount - 1
            else
                list[#list + 1] = nameKey
            end
        end
        table.sort(list)
        return list
    end
    function S2.namesText()
        local list = namesList()
        local r = S2.reads
        for i, nameKey in ipairs(list) do
            list[i] = ("%s: [%s, %d]"):format(q(r, nameKey), q(r, names[nameKey].name), names[nameKey].hash)
        end
        return "{" .. table.concat(list, ", ") .. "}"
    end

    -- Object 26: the player's and the target's auras, helpful first. The client refuses the read
    -- in combat (an error, seen 20 Nov 2026), and a secret aura is refused too: format 253.
    local AURA_UNITS, AURA_FILTERS = { "player", "target" }, { "HELPFUL", "HARMFUL" }
    function S2.aurasText()
        local r, now = S2.reads, _G.GetTime and _G.GetTime() or 0
        local get = r.lookup("C_UnitAuras.GetAuraDataByIndex")
        if type(get) ~= "function" then return nil end
        local out = {}
        for _, unit in ipairs(AURA_UNITS) do
            local list = {}
            for _, filter in ipairs(AURA_FILTERS) do
                for i = 1, 40 do
                    local ok, a = pcall(get, unit, i, filter)
                    if not ok then return S2.SECRET end
                    if r.secret(a) then return S2.SECRET end
                    if type(a) ~= "table" then break end
                    if r.secret(a.spellId) or r.secret(a.name) or r.secret(a.expirationTime) then return S2.SECRET end
                    local spell = ref(r, "S", a.spellId, a.name, now)
                    if spell then
                        local stacks, duration, expires = n(r, a.applications), n(r, a.duration), n(r, a.expirationTime)
                        local source = r.plain(a.sourceUnit)
                        list[#list + 1] = ("[%s, %d, %.1f, %.1f, %s]"):format(q(r, spell), stacks and floor(stacks) or 0,
                            duration or 0, expires or 0, type(source) == "string" and q(r, source) or "null")
                    end
                end
            end
            out[#out + 1] = ("%s: [%s]"):format(q(r, unit), table.concat(list, ", "))
        end
        return "{" .. table.concat(out, ", ") .. "}"
    end

    ----------------------------------------------------------------------
    -- Format 3's objects in binary (object format 2; docs/specs/232.md, part E). The shapes are
    -- reader/hellolink-format/src/objects.rs; tests/vectors/objects3.json holds both sides to the
    -- same bytes. Each writer puts its value at b[n + 1] on and gives the place after it.
    ----------------------------------------------------------------------
    local function uvar(b, at, v)   -- LEB128 of a whole number of 0 or more
        -- not a finite number of 0 or more (NaN, infinity): 0, so that the loop always ends. Up to 2^54:
        -- the zigzag of a whole number up to 2^53 (twice it, exact in a double; review of #262)
        if v ~= v or v < 0 or v > 2 ^ 54 then v = 0 end
        v = floor(v)
        repeat
            local low = v % 128
            v = floor(v / 128)
            at = at + 1
            b[at] = v > 0 and low + 128 or low
        until v == 0
        return at
    end
    local function svar(b, at, v) return uvar(b, at, v >= 0 and 2 * v or -2 * v - 1) end   -- zigzag
    -- ten times a number with one decimal, rounded as `%.1f` rounds it (the JSON of format 2 says
    -- the same value); a number that is not finite as 0 (it would never end the LEB128 loop)
    local function tenthsOf(v)
        if v ~= v or v >= 2 ^ 49 or v <= -2 ^ 49 then v = 0 end   -- not finite, or too large: 0
        return floor(tonumber(("%.1f"):format(v)) * 10 + 0.5)
    end
    local function tenths(b, at, v) return svar(b, at, tenthsOf(v)) end
    local function text(b, at, s)
        at = uvar(b, at, #s)
        for i = 1, #s do b[at + i] = s:byte(i) end
        return at + #s
    end
    -- a reference's id and hash: the id (LEB128), then the hash, 16 bits little-endian
    local function refB(b, at, id, hash)
        at = uvar(b, at, id)
        b[at + 1], b[at + 2] = hash % 256, floor(hash / 256)
        return at + 2
    end
    S2.bin = { uvar = uvar, svar = svar, tenths = tenths, tenthsOf = tenthsOf, text = text, ref = refB }

    -- Object 26 in binary: the same reads as `aurasText`, kept in place a build (#175).
    local A = { id = {}, hash = {}, stacks = {}, dur = {}, exp = {}, src = {} }
    function S2.aurasBin(b)
        local r, now = S2.reads, _G.GetTime and _G.GetTime() or 0
        local get = r.lookup("C_UnitAuras.GetAuraDataByIndex")
        if type(get) ~= "function" then return nil end
        b[1] = 3                                     -- presence: player and target
        local at = 1
        for _, unit in ipairs(AURA_UNITS) do
            local count = 0
            for _, filter in ipairs(AURA_FILTERS) do
                for i = 1, 40 do
                    local ok, a = pcall(get, unit, i, filter)
                    if not ok then return S2.SECRET end
                    if r.secret(a) then return S2.SECRET end
                    if type(a) ~= "table" then break end
                    if r.secret(a.spellId) or r.secret(a.name) or r.secret(a.expirationTime) then return S2.SECRET end
                    local id, hash = S2.refParts(r, "S", a.spellId, a.name, now)
                    if id then
                        count = count + 1
                        local stacks, duration, expires = n(r, a.applications), n(r, a.duration), n(r, a.expirationTime)
                        local source = r.plain(a.sourceUnit)
                        A.id[count], A.hash[count] = id, hash
                        A.stacks[count] = stacks and floor(stacks) or 0
                        A.dur[count], A.exp[count] = duration or 0, expires or 0
                        A.src[count] = type(source) == "string" and source or false
                    end
                end
            end
            at = uvar(b, at, count)
            for k = 1, count do
                at = refB(b, at, A.id[k], A.hash[k])
                at = svar(b, at, A.stacks[k])
                at = tenths(b, at, A.dur[k])
                at = tenths(b, at, A.exp[k])
                if A.src[k] then
                    b[at + 1] = 1
                    at = text(b, at + 1, A.src[k])
                else
                    at = at + 1
                    b[at] = 0
                end
            end
        end
        return at
    end

    -- Object 24 in binary: a record of the 55 unit tokens and "nameplates" (56 presence bits in
    -- 7 bytes), each unit as `unitRead` read it.
    local UNIT_AT = {}
    for i, unit in ipairs(UNITS) do UNIT_AT[unit] = i - 1 end   -- a token's field, from 0
    local function whoB(b, at, kind, id, hash)
        b[at + 1] = kind:byte()
        return refB(b, at + 1, id, hash)
    end
    S2.bin.who = whoB
    local function optText(b, at, s)
        if not s then b[at + 1] = 0 return at + 1 end
        b[at + 1] = 1
        return text(b, at + 1, s)
    end
    local function optInt(b, at, v)
        if not v then b[at + 1] = 0 return at + 1 end
        b[at + 1] = 1
        return svar(b, at + 1, v)
    end
    S2.bin.optText, S2.bin.optInt = optText, optInt
    local function unitBin(b, at)
        at = whoB(b, at, U.kind, U.wid, U.whash)
        at = svar(b, at, U.level)
        at = optText(b, at, U.file)
        at = optText(b, at, U.class)
        at = optInt(b, at, U.flags)
        at = optText(b, at, U.target)
        at = optInt(b, at, U.threat)
        at = optInt(b, at, U.mark)
        if not U.sid then b[at + 1] = 0 return at + 1 end
        b[at + 1] = 1
        return whoB(b, at + 1, "S", U.sid, U.shash)
    end
    local plateBuf = {}
    function S2.unitsBin(b)
        local r, now = S2.reads, _G.GetTime and _G.GetTime() or 0
        unitsPresent(r)
        for i = 1, 7 do b[i] = 0 end
        local at = 7
        for i = 1, presentCount do
            local unit = present[i]
            if unitRead(r, unit, now, byGuid) then
                local field = UNIT_AT[unit]
                local k = 1 + floor(field / 8)
                b[k] = b[k] + 2 ^ (field % 8)
                at = unitBin(b, at)
            end
        end
        b[7] = b[7] + 2 ^ (#UNITS % 8)                 -- "nameplates": always there
        local count, len = 0, 0
        for i = 1, 40 do
            local unit = PLATES[i]
            local ok, exists = r.read("UnitExists", unit)
            if ok and exists and unitRead(r, unit, now, byGuid) then
                count = count + 1
                len = unitBin(plateBuf, len)
            end
        end
        at = uvar(b, at, count)
        for i = 1, len do b[at + i] = plateBuf[i] end
        return at + len
    end

    -- Object 27: the first 48 used action slots, `[slot, what, active, onGCD, start, duration]`.
    -- `what` is the spell (a macro's spell), or the item; null for anything else. The times are
    -- null while the client keeps them secret (in combat).
    local infoValues, nameValues, cdValues, macroValues = {}, {}, {}, {}   -- kept for 120 slots a build (#175)
    -- The used slots' values, read into kept tables (#175): the JSON and the binary writers both
    -- take them from here, so that the two formats say the same. The number of slots read.
    local C = { slot = {}, what = {}, kind = {}, id = {}, hash = {}, active = {}, gcd = {}, start = {}, dur = {} }
    local function cooldownsRead(r, now)
        local count = 0
        for slot = 1, 180 do
            local okInfo, info = r.readInto(infoValues, "GetActionInfo", slot)
            local kind = okInfo and r.plain(info[1])
            if type(kind) == "string" then
                local id = n(r, info[2])
                if kind == "macro" and id then
                    -- Forever gives a macro's spell as ("macro", spellId, "spell"); else the id is
                    -- the macro's, and GetMacroSpell gives its spell
                    if r.plain(info[3]) ~= "spell" then
                        local okMacro, macro = r.readInto(macroValues, "GetMacroSpell", id)
                        id = okMacro and n(r, macro[1])
                    end
                    kind = "spell"
                end
                local wid, whash, wkey, wkind
                if kind == "spell" and id then
                    local okName, spellName = r.readInto(nameValues, "C_Spell.GetSpellName", id)
                    wid, whash, wkey = S2.refParts(r, "S", id, okName and spellName[1], now)
                    wkind = "S"
                elseif kind == "item" and id then
                    wid, whash, wkey = S2.refParts(r, "I", id, r.get("C_Item.GetItemNameByID", id), now)
                    wkind = "I"
                end
                local okCd, cd = r.readInto(cdValues, "C_ActionBar.GetActionCooldown", slot)
                local c = okCd and r.plain(cd[1])
                c = type(c) == "table" and c or nil
                local active, gcd = c and r.plain(c.isActive), c and r.plain(c.isOnGCD)
                count = count + 1
                C.slot[count] = slot
                C.what[count] = wid and (wkey .. ":" .. whash) or false
                C.kind[count], C.id[count], C.hash[count] = wkind, wid, whash
                C.active[count], C.gcd[count] = active == true, gcd == true
                C.start[count] = c and n(r, c.startTime) or false
                C.dur[count] = c and n(r, c.duration) or false
                if count >= 48 then break end
            end
        end
        return count
    end
    -- Object 27 in binary: a record of "slots", each slot packed: one byte of bits, then its values
    -- (objects.rs, `Packed`). Bits from 0: slot is zero, what is there, active, onGCD, start is
    -- there, start is zero, duration is there, duration is zero.
    function S2.cooldownsBin(b)
        local r, now = S2.reads, _G.GetTime and _G.GetTime() or 0
        local count = cooldownsRead(r, now)
        b[1] = 1                                     -- presence: "slots"
        local at = S2.bin.uvar(b, 1, count)
        for k = 1, count do
            local st = C.start[k] and S2.bin.tenthsOf(C.start[k])
            local du = C.dur[k] and S2.bin.tenthsOf(C.dur[k])
            local bits = (C.slot[k] == 0 and 1 or 0) + (C.what[k] and 2 or 0) + (C.active[k] and 4 or 0)
                + (C.gcd[k] and 8 or 0) + (st and 16 or 0) + (st == 0 and 32 or 0) + (du and 64 or 0) + (du == 0 and 128 or 0)
            at = at + 1
            b[at] = bits
            if C.slot[k] ~= 0 then at = S2.bin.svar(b, at, C.slot[k]) end
            if C.what[k] then at = S2.bin.who(b, at, C.kind[k], C.id[k], C.hash[k]) end
            if st and st ~= 0 then at = S2.bin.svar(b, at, st) end
            if du and du ~= 0 then at = S2.bin.svar(b, at, du) end
        end
        return at
    end
    function S2.cooldownsText()
        local r, now = S2.reads, _G.GetTime and _G.GetTime() or 0
        local count = cooldownsRead(r, now)
        local list = {}
        for k = 1, count do
            list[k] = ("[%d, %s, %s, %s, %s, %s]"):format(C.slot[k], C.what[k] and q(r, C.what[k]) or "null",
                C.active[k] and "true" or "false", C.gcd[k] and "true" or "false",
                C.start[k] and ("%.1f"):format(C.start[k]) or "null", C.dur[k] and ("%.1f"):format(C.dur[k]) or "null")
        end
        return '{"slots": [' .. table.concat(list, ", ") .. "]}"
    end

    -- When objects 24 to 27 are marked changed: units twice a second, auras and cooldowns once,
    -- names every 5 s; the fast data's names once a second.
    local since = { units = 0, each = 0, names = 0 }
    function S2.marks(elapsed, mark)
        since.units, since.each, since.names = since.units + elapsed, since.each + elapsed, since.names + elapsed
        if since.units >= 0.5 then since.units = 0; mark(24) end
        if since.each >= 1 then
            since.each = 0
            mark(26); mark(27)
            S2.noteFast(_G.GetTime and _G.GetTime() or 0)
        end
        if since.names >= 5 then since.names = 0; mark(25) end
    end

    -- When each of the last 512 frames went up, by the addon's clock, with its seq: kept in the
    -- saved data (`HelloLinkDB.frames`), to set against the reader's record (#213: frames that
    -- no capture saw). One ring of numbers, filled in place: no memory a frame.
    local RING = 512
    function S2.noteFrame(db, seq, session)
        local ring = db.frames
        -- one session's frames only: a new UI session (a /reload) starts the ring afresh
        if type(ring) ~= "table" or type(ring.at) ~= "number" or ring.session ~= session then
            ring = { at = 0, t = {}, seq = {}, session = session }
            db.frames = ring
        end
        ring.at = ring.at % RING + 1
        ring.t[ring.at] = _G.GetTime and _G.GetTime() or 0
        ring.seq[ring.at] = seq
    end

    -- Format 2 keeps its own square size (`size2`, 1 to 4): format 1 never has fewer than 2, and
    -- an older HelloLink reads only `size`.
    function S2.side(db)
        return db.format >= 2 and (db.size2 or 1) or db.size
    end

    -- The chunks' length changed (size, place, depth): every object gets a new version, so that a
    -- reader that holds a version cut the old way takes the new chunks (review of #227).
    local lastChunkLen
    function S2.rechunked(objects, chunkLen)
        if chunkLen == lastChunkLen then return end
        lastChunkLen = chunkLen
        for _, o in pairs(objects or {}) do
            if o.obj then o.version, o.sent = ((o.version or 0) + 1) % 65536, nil end
        end
    end

    -- How often the level triples are coloured in format 2: the four of format 1 and the target of
    -- target on every second call (10 a second, the frames' rate), the party's on every fourth.
    -- Format 1 colours its four on every call (20 a second): format 2 asks the client no more.
    local levelCalls = 0
    -- After the row starts afresh, the next call colours every triple (review of #227).
    function S2.resetLevels()
        levelCalls = -1
    end
    function S2.levelTurn()
        levelCalls = levelCalls + 1
        return levelCalls % 2 == 0, levelCalls % 4 == 0
    end

    ----------------------------------------------------------------------
    -- Format 3 (docs/specs/232.md, section 6): every frame whole. The carousel above is shared;
    -- `S2.three` turns on its two rules of format 3 (a new version twice, again after a stall).
    ----------------------------------------------------------------------
    S2.VERSION3 = 3
    -- Format 3 has a layout square after the depth square: the session, the palette and what
    -- follows them are one square further on.
    function S2.shift(db) return db.format == 3 and 1 or 0 end
    S2.nextFrame = 0      -- the one clock: the next frame is built at or after this time
    -- The back-off (section 4 B): while the game draws fewer than SLOW_FPS frames a second (`slow`, read
    -- once a second at `rateAt`), a chunk begun then stays two frames (`need`, counted in frames, not time); the fixed part
    -- still goes every frame.
    S2.SLOW_FPS, S2.slow, S2.rateAt = 20, false, 0
    -- The head before a chunk at most: the frame head, the fast section, a directory of 27
    -- objects, the event ring at its longest, the fixed check, the chunk's head and its check.
    S2.HEAD3 = 8 + 2 + 67 + 2 + 3 * 27 + 3 + 8 * 5 + 2 + 6 + 2

    -- The fast section's 67 bytes at bytes[at + 1]: the mask, then every group at full size, an
    -- unknown one as 0, so that every group is always at the same place. The place after it.
    function S2.packFast3(bytes, at, state)
        local mask, to = 0, at + 3
        for i = 1, #GROUPS do
            local g = GROUPS[i]
            local values = state[g[1]]
            if values then mask = mask + BIT[i] end
            for f = 2, #g do to = put(bytes, to, values and values[g[f][1]], g[f][2]) end
        end
        put(bytes, at, mask, 3)
        return to
    end

    local function sums(bytes, first, last)
        local s1, s2 = 0, 0
        for i = first, last do
            s1 = (s1 + bytes[i]) % 255
            s2 = (s2 + s1) % 255
        end
        return s1, s2
    end

    -- The frame at bytes[1] on: the number of bytes. The fixed check's two bytes are left 0 at
    -- `S2.fx + 1` and `S2.fx + 2` (Strip.lua's `show` writes them once the seq is set); the
    -- chunk's own check is written here. `ids` objects go in the directory. `ring` (S2.ringNow)
    -- gives the event ring, after the directory, less its first `skip` events; without it the
    -- frame has none.
    local function build3(bytes, session, dwell, seq, state, sending, objects, ids, ring, skip)
        bytes[1] = S2.VERSION3
        local to = put(bytes, 1, session, 2)
        bytes[to + 1] = dwell
        to = put(bytes, to + 1, seq, 2) + 2          -- fixedLen at bytes 7 and 8, set below
        bytes[to + 1], bytes[to + 2] = 1, 67
        to = S2.packFast3(bytes, to + 2, state)
        local dir = to + 2
        local m = dir
        for id = 1, ids do
            local o = objects[id]
            if o and o.obj and o.version then
                bytes[m + 1] = id
                m = put(bytes, m + 1, o.version, 2)
            end
        end
        bytes[to + 1], bytes[to + 2] = 2, m - dir
        if ring then
            local at = m
            bytes[m + 1], bytes[m + 3] = 3, S2.ringCount
            m = m + 3
            for i = skip + 1, #ring do
                local e = ring[i]
                local sizes = S2.KINDS[e[2]]
                bytes[m + 1] = e[2]
                m = m + 1
                for k = 1, #sizes do m = put(bytes, m, e[k + 2], sizes[k]) end
            end
            bytes[at + 2] = m - at - 2
        end
        put(bytes, 6, m - 8, 2)
        S2.fx = m
        bytes[m + 1], bytes[m + 2] = 0, 0
        to = m + 2
        if not sending then
            bytes[to + 1] = 0
            return to + 1
        end
        local at, part = to, sending.chunks[sending.index]
        bytes[to + 1] = sending.id
        to = put(bytes, to + 1, sending.version, 2)
        bytes[to + 1], bytes[to + 2], bytes[to + 3] = sending.index - 1, #sending.chunks, #part
        to = to + 3
        for i = 1, #part do bytes[to + i] = part[i] end
        to = to + #part
        bytes[to + 1], bytes[to + 2] = sums(bytes, at + 1, to)
        return to + 2
    end
    -- The frame (build3). With `fit`, the bytes the row has room for, a ring too long for it keeps its
    -- newest events and its counter: the reader says the rest lost, and the fast state still goes.
    -- When even the counter alone does not fit (a full directory on a short row), the frame has no
    -- ring; the next frame that has one says what came in between.
    function S2.frame3(bytes, session, dwell, seq, state, sending, objects, ids, ring, fit)
        local skip = 0
        local len = build3(bytes, session, dwell, seq, state, sending, objects, ids, ring, skip)
        while fit and len > fit and ring do
            if skip < #ring then skip = skip + 1 else ring = nil end
            len = build3(bytes, session, dwell, seq, state, sending, objects, ids, ring, skip)
        end
        return len
    end

    -- Builds an object of format 3 in binary (object format 2): its payload into a kept table,
    -- a new version only when the bytes changed, and a new table only then (#175). The client
    -- keeps it secret: format 253; it cannot be read: 255. `check` is Strip.lua's sums. When the
    -- bytes pass `limit`, what one version may send (a raid with its nameplates), they go
    -- deflated by the client (`deflate`, Strip.lua's): object format 3, still binary (#251).
    local binBuf, piece = {}, {}
    local function deflated(len, deflate)
        local strings = {}
        for i = 1, len, 4000 do   -- `unpack` takes a few thousand values at most
            for k = i, math.min(i + 3999, len) do piece[k - i + 1] = binBuf[k] end
            strings[#strings + 1] = string.char(unpack(piece, 1, math.min(4000, len - i + 1)))
        end
        return deflate(table.concat(strings))
    end
    local keyBuf = {}
    function S2.refreshBin(o, now, check, limit, deflate)
        local ok, len, keyLen = pcall(o.bin, binBuf, keyBuf)
        local old, bytes = o.obj
        if ok and type(len) == "number" then
            -- a writer that gives a key (the bags' and the gear's: the bytes without the ammunition's
            -- count, as their text's key, #44): no new version while the key is the newest version's
            if type(keyLen) == "number" then
                local k = o.keyRaw
                if old and (old[1] == 2 or old[1] == 3) and k and o.keyLen == keyLen then
                    local same = true
                    for i = 1, keyLen do
                        if k[i] ~= keyBuf[i] then same = false break end
                    end
                    if same then return end
                end
                k = k or {}
                for i = 1, keyLen do k[i] = keyBuf[i] end
                o.keyRaw, o.keyLen = k, keyLen
            end
            -- the payload of the newest version again, in the encoding that still suits the limit
            -- (plain while it fits, deflated while it does not): nothing to build, no table
            local raw = o.raw
            local fits = len + 3 <= limit
            if old and (old[1] == 2 and fits or old[1] == 3 and not fits) and raw and o.rawLen == len then
                local same = true
                for i = 1, len do
                    if raw[i] ~= binBuf[i] then same = false break end
                end
                if same then return end
            end
            raw = raw or {}
            for i = 1, len do raw[i] = binBuf[i] end
            o.raw, o.rawLen = raw, len
            -- deflated when it is too large for one version
            local z = len + 3 > limit and deflated(len, deflate)
            if z then
                bytes = { 3 }
                for i = 1, #z do bytes[i + 1] = z:byte(i) end
            else
                bytes = { 2 }
                for i = 1, len do bytes[i + 1] = binBuf[i] end
            end
        else
            local kind = (ok and len == S2.SECRET) and 253 or 255
            if old and #old == 3 and old[1] == kind then return end
            bytes = { kind }
        end
        local s1, s2 = check(bytes)
        bytes[#bytes + 1], bytes[#bytes + 2] = s1, s2
        o.version = ((o.version or math.random(0, 65535)) + 1) % 65536
        o.obj, o.changedAt, o.rounds = bytes, now, o.want
        o.from, o.packer, o.method, o.chunks, o.key = false, nil, nil, nil, nil
    end

    -- The game stopped for `gap` seconds: every version that had a chunk up in the second before
    -- the stop is sent whole once again (section 6).
    function S2.stall(objects, ids, now, gap)
        for id = 1, ids do
            local o = objects[id]
            if o and o.upAt and o.upAt >= now - gap - 1 then o.againAt, o.againVer, o.againSince = now, o.version, now end
        end
    end

    -- The event ring (section 6, section 3): the last 8 events of the last 10 s, and a counter
    -- of every event. Kinds and the bytes after the kind byte: 1 loot (item 3, quantity 1),
    -- 2 UI error (number 2), 3 money gained (copper 4), 4 money lost (copper 4), 5 XP gained (3),
    -- 6 a new level (1), 7 death (none). Taken from the client's events and from what the addon
    -- reads anyway: no client call. An event of the client is stamped with the time of the next
    -- frame (S2.ringNow), so that it costs no GetTime (rule 4).
    S2.KINDS = { { 3, 1 }, { 2 }, { 4 }, { 4 }, { 3 }, { 1 }, {} }
    S2.RING_KEEP, S2.RING_MAX = 10, 8
    S2.ring, S2.ringCount, S2.ringWas = {}, 0, {}
    function S2.happen(now, kind, a, b)
        local r = S2.ring
        S2.ringCount = (S2.ringCount + 1) % 256
        if #r == S2.RING_MAX then table.remove(r, 1) end
        r[#r + 1] = { now, kind, a, b }
    end
    -- What changed since the state before: XP and money. A group that is unknown now keeps the
    -- value before it, so a group that comes back says only the change. A level and a death come
    -- from the client's events (PLAYER_LEVEL_UP, PLAYER_DEAD), not from the state.
    function S2.noteRing(state, now)
        local w, l, p = S2.ringWas, state.level, state.purse
        if l and l.level and l.xp then
            if w.level and l.level == w.level and l.xp > w.xp then
                S2.happen(now, 5, l.xp - w.xp)
            elseif w.level and l.level == w.level + 1 and w.xpMax and w.xpMax > w.xp then
                S2.happen(now, 5, w.xpMax - w.xp + l.xp)   -- one level up: the rest of the old and the new
            end
            w.level, w.xp, w.xpMax = l.level, l.xp, l.xpMax
        end
        if p and p.money then
            if w.money and p.money ~= w.money then
                S2.happen(now, p.money > w.money and 3 or 4, math.abs(p.money - w.money))
            end
            w.money = p.money
        end
        -- a level of the client's PLAYER_LEVEL_UP goes after the XP that made it
        if S2.levelUp then
            S2.happen(now, 6, S2.levelUp)
            S2.levelUp = nil
        end
    end
    -- The ring's entries still kept at `now`, oldest first; an event not yet stamped takes `now`.
    function S2.ringNow(now)
        local r = S2.ring
        for i = 1, #r do r[i][1] = r[i][1] or now end
        while r[1] and r[1][1] < now - S2.RING_KEEP do table.remove(r, 1) end
        return r
    end
end

local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local concat = table.concat

local VERSION = 1
local FINDER = { 4, 2, 1, 7, 0, 6, 3, 5 }
local LEVELS_AT, DEPTH_AT, SESSION_AT, PALETTE_AT = 8, 20, 21, 27 -- squares from the row's start
local MAX_CHUNKS, MAX_CHUNK = 12, 255
local FAST_EVERY = 0.1                                             -- seconds between reads of the fast state
local LOOKS = { 30, 60, 120, 300 }                                 -- seconds after the UI loaded; then every 600

-- Section 5: the groups of the fast block in order, each a list of { field, bytes }.
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
}

----------------------------------------------------------------------
-- Values from the client. A secret value is never tested, compared or computed on: `plain`
-- hands it to issecretvalue and to nothing else, and gives nil in its place.
----------------------------------------------------------------------
local function plain(v)
    local isSecret = _G.issecretvalue
    if type(isSecret) == "function" and isSecret(v) then return nil end
    return v
end

-- A path is split once and its parts kept (#175): the fast block asks for some forty values
-- ten times a second. The value itself is looked up afresh every time: another addon may
-- have replaced the function since.
local PARTS = {}
local function lookup(path)
    local parts = PARTS[path]
    if parts == nil then
        parts = false
        if path:find(".", 1, true) then
            parts = {}
            for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
        end
        PARTS[path] = parts
    end
    if not parts then return _G[path] end
    local v = _G
    for i = 1, #parts do
        if type(v) ~= "table" then return nil end
        v = v[parts[i]]
    end
    return v
end

-- `ok, value` for the first value `path(...)` returns. `ok` is false when the value cannot be
-- used: the function is missing, it failed, or the value is secret. A value of nil with `ok`
-- true is the client saying "nothing" (no target, no cast).
local function read(path, ...)
    local fn = lookup(path)
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, ...)
    if not ok then return false end
    local isSecret = _G.issecretvalue
    if type(isSecret) == "function" and isSecret(v) then return false end
    return true, v
end

-- The first value, or nil when it cannot be used or is nothing.
local function get(path, ...)
    local ok, v = read(path, ...)
    if ok then return v end
    return nil
end

-- Fills `out` with the values, `out.n` their count; what it held before is gone. Nothing is
-- written when a value is secret.
local function fill(out, ok, ...)
    if not ok then return false end
    local isSecret = _G.issecretvalue
    local n = select("#", ...)
    if type(isSecret) == "function" then
        for i = 1, n do
            if isSecret((select(i, ...))) then return false end
        end
    end
    for i = 1, n do out[i] = (select(i, ...)) end
    for i = n + 1, out.n or 0 do out[i] = nil end
    out.n = n
    return true, out
end

local function gather(ok, ...)
    return fill({}, ok, ...)
end

-- `ok, values` for everything `path(...)` returns, by position, with `values.n` their count.
-- `ok` is false when the function is missing or failed, or any of the values is secret.
local function readAll(path, ...)
    local fn = lookup(path)
    if type(fn) ~= "function" then return false end
    return gather(pcall(fn, ...))
end

-- The same into a table the caller keeps, for what is read ten times a second (#175). The
-- values are good until the caller's next read into that table.
local function readInto(out, path, ...)
    local fn = lookup(path)
    if type(fn) ~= "function" then return false end
    return fill(out, pcall(fn, ...))
end

local function num(v)
    return type(v) == "number" and v or nil
end

-- A whole number of a size JSON and the reader can take: not NaN, not infinite.
local function finite(v)
    return type(v) == "number" and v == v and v > -2147483648 and v < 2147483648
end

----------------------------------------------------------------------
-- Bytes (sections 4, 5 and 7)
----------------------------------------------------------------------
local function check(bytes, first, last)
    local s1, s2 = 0, 0
    for i = first or 1, last or #bytes do
        s1 = (s1 + bytes[i]) % 255
        s2 = (s2 + s1) % 255
    end
    return s1, s2
end

-- A whole number of `size` bytes, most significant first, into a table the caller keeps (#175):
-- it goes to `bytes[at + 1]` onwards, and the place after it is returned. The frame is built ten
-- times a second; it asks for no memory.
local TOP = { 255, 65535, 16777215, 4294967295 }
local function put(bytes, at, value, size)
    value = floor(max(0, min(value or 0, TOP[size])))
    if size == 1 then
        bytes[at + 1] = value
    elseif size == 2 then
        bytes[at + 1], bytes[at + 2] = floor(value / 256), value % 256
    elseif size == 3 then
        bytes[at + 1], bytes[at + 2], bytes[at + 3] = floor(value / 65536), floor(value / 256) % 256, value % 256
    else
        bytes[at + 1], bytes[at + 2] = floor(value / 16777216), floor(value / 65536) % 256
        bytes[at + 3], bytes[at + 4] = floor(value / 256) % 256, value % 256
    end
    return at + size
end

-- The fast block for a state, written to `bytes[at + 1]` onwards: `state[group]` is a table of
-- the group's fields, or nil or false when the group is unknown. Returns the place after it.
local GROUP_BIT = {}
for i = 1, #GROUPS do GROUP_BIT[i] = 2 ^ (16 - i) end
local function packFast(bytes, at, state)
    local known, to = 0, at + 2
    for i = 1, #GROUPS do
        local group = GROUPS[i]
        local values = state[group[1]]
        if values then known = known + GROUP_BIT[i] end
        for f = 2, #group do
            to = put(bytes, to, values and values[group[f][1]] or 0, group[f][2])
        end
    end
    put(bytes, at, known, 2)
    return to
end

-- Bytes to squares (section 3): `bits` a square, most significant first, the last filled with 0.
-- The first `n` bytes go into `out`, a table the caller keeps; the count of squares is returned.
local function squaresInto(out, bytes, n, bits)
    local count, acc, have = 0, 0, 0
    local whole = 0
    if bits == 6 then
        -- three bytes are four squares of 6 bits: the same squares as the loop below gives,
        -- without its powers (#175). What is left over, one or two bytes, goes through the loop.
        whole = n - n % 3
        for i = 1, whole, 3 do
            local a, b, c = bytes[i], bytes[i + 1], bytes[i + 2]
            local bLow, cLow = b % 16, c % 64
            out[count + 1] = (a - a % 4) / 4
            out[count + 2] = a % 4 * 16 + (b - bLow) / 16
            out[count + 3] = bLow * 4 + (c - cLow) / 64
            out[count + 4] = cLow
            count = count + 4
        end
    end
    for i = whole + 1, n do
        acc, have = acc * 256 + bytes[i], have + 8
        while have >= bits do
            local unit = 2 ^ (have - bits)
            local s = floor(acc / unit)
            count = count + 1
            out[count] = s
            acc, have = acc - s * unit, have - bits
        end
    end
    if have > 0 then
        count = count + 1
        out[count] = acc * 2 ^ (bits - have)
    end
    return count
end

local function squaresOf(bytes, bits)
    local out = {}
    squaresInto(out, bytes, #bytes, bits)
    return out
end

----------------------------------------------------------------------
-- JSON for the objects (section 6): the keys in the order given, nothing else.
----------------------------------------------------------------------
local function jsonString(s)
    s = tostring(s):gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' end
        if c == "\\" then return "\\\\" end
        if c == "\n" then return "\\n" end
        return ("\\u%04x"):format(c:byte())
    end)
    return '"' .. s .. '"'
end

local function jsonNumber(n)
    return ("%d"):format(floor(n))
end

----------------------------------------------------------------------
-- State kept between frames
----------------------------------------------------------------------
local db                                  -- HelloLinkDB
local session, seq, depth = 0, 0, 4
local loadedAt, lookIndex, looking = nil, 1, true
local lootOpen = false
local loot = { counter = 0, item = 0, quantity = 0 }
local uiError = { error = 0, counter = 0 }

local function clock()
    return _G.GetTime()
end

----------------------------------------------------------------------
-- The fast state (section 5)
----------------------------------------------------------------------
local hashedName, hashOfName   -- the last name and its hash: a target keeps its name (#175)
local function nameHash(name)
    if name ~= hashedName then
        local s1, s2 = 0, 0
        for i = 1, #name do
            s1 = (s1 + name:byte(i)) % 255
            s2 = (s2 + s1) % 255
        end
        hashedName, hashOfName = name, s1 * 256 + s2
    end
    return hashOfName
end

-- The cast group, and whether the player casts or channels. The second value is nil when
-- the client does not say (then the state group is unknown too).
local castValues, castGroup = {}, {}   -- kept between reads (#175)
local function castNow()
    local ok, c = readInto(castValues, "UnitCastingInfo", "player")
    if not ok then return nil, nil end
    local spell = c[9]
    if c[1] == nil then
        ok, c = readInto(castValues, "UnitChannelInfo", "player")
        if not ok then return nil, nil end
        if c[1] == nil then return nil, false end
        spell = c[8]
    end
    if not num(spell) or not num(c[5]) then return nil, true end
    local tenths = ceil((c[5] / 1000 - clock()) * 10)
    castGroup.spell, castGroup.tenths = spell, tenths > 254 and 255 or max(0, tenths)
    return castGroup, true
end

local CLASSIFICATION = { normal = 0, trivial = 0, minus = 0, elite = 32, rareelite = 48, worldboss = 32, rare = 16 }

-- Adds `bit` to the sum when `path(...)` is true. Returns the sum, or nil when the client's
-- answer cannot be used: one unreadable flag makes the whole group unknown.
local function flag(sum, bit, path, ...)
    if sum == nil then return nil end
    local ok, v = read(path, ...)
    if not ok then return nil end
    return sum + (v and bit or 0)
end

-- A flag whose function a client may not have: a missing function counts as false (#101).
local function flagIfAny(sum, bit, path)
    if type(lookup(path)) ~= "function" then return sum end
    return flag(sum, bit, path)
end

-- A unit's threat on the target as a whole per cent, 0 when the unit is not on the target's
-- list (the client then returns nothing), nil when the client's answer cannot be used.
local threatValues = {}
local function threatOf(who)
    local ok, t = readInto(threatValues, "UnitDetailedThreatSituation", who, "target")
    if not ok then return nil end
    if t.n == 0 or t[3] == nil then return 0 end
    return num(t[3]) and min(100, floor(t[3] + 0.5)) or nil
end

-- A group is in the state only when every one of its fields was read: a missing function, a
-- failed call or a secret value leaves the group unknown, never a zero that looks known.
-- The state and its groups are kept between reads and written afresh by each (#175): the frame
-- is packed from them at once, and nothing else holds them.
local fastState = {}
local G = { clock = {}, health = {}, power = {}, level = {}, state = {}, target = {}, threat = {}, pet = {},
    position = {}, purse = {}, hand = {} }
local xyValues, enchantValues = {}, {}
local function sample()
    local state = fastState
    local g = G.clock
    g.clock = _G.time() % 65536
    state.clock = g
    local healthMax = num(get("UnitHealthMax", "player"))
    g = G.health
    g.healthMax = healthMax
    state.health = healthMax and g
    local powerMax, powerType = num(get("UnitPowerMax", "player")), num(get("UnitPowerType", "player"))
    g = G.power
    g.powerMax, g.powerType = powerMax, powerType
    state.power = powerMax and powerType and g
    local level, xp, xpMax = num(get("UnitLevel", "player")), num(get("UnitXP", "player")), num(get("UnitXPMax", "player"))
    g = G.level
    g.level, g.xp, g.xpMax = level, xp, xpMax
    state.level = level and xp and xpMax and g
    state.target, state.threat, state.position, state.hand = nil, nil, nil, nil

    local okTarget, hasTarget = read("UnitExists", "target")
    local okPet, hasPet = read("UnitExists", "pet")
    local cast, casting = castNow()
    state.cast = cast
    local flags = okTarget and okPet and casting ~= nil and 0 or nil
    flags = flag(flags, 128, "UnitAffectingCombat", "player")
    flags = flag(flags, 64, "UnitIsDeadOrGhost", "player")
    flags = flag(flags, 32, "IsMounted")
    flags = flag(flags, 16, "IsResting")
    flags = flag(flags, 8, "UnitIsAFK", "player")
    -- Seen 15 Nov 2026: all three false outdoors on the ground, indoors true in a building, flying
    -- false on a flight path; none secret. The client gives no height (UnitPosition's z was 0):
    -- these are hints about where the player is, not a level.
    flags = flagIfAny(flags, 512, "IsIndoors")
    flags = flagIfAny(flags, 1024, "IsSwimming")
    flags = flagIfAny(flags, 2048, "IsFlying")
    -- A chat input is open (8192): the client's active chat edit box, or nil. Seen 15 Nov 2026:
    -- the box's IsShown and IsVisible stay true when it is closed; only the active window tells.
    -- Missing or failing, the whole group is unknown, not false: a program that types into the
    -- game refuses on an unknown (agreed with the local program, 15 Nov 2026).
    local okChat, chatBox = read("ChatEdit_GetActiveWindow")
    if not okChat then flags = nil end
    g = G.state
    g.flags = flags and flags + (casting and 4 or 0) + (hasTarget and 2 or 0) + (hasPet and 1 or 0)
        + (lootOpen and 256 or 0) + (chatBox ~= nil and 8192 or 0)
    state.state = flags and g

    if okTarget and hasTarget then
        local tl, name, class = num(get("UnitLevel", "target")), get("UnitName", "target"), get("UnitClassification", "target")
        local tf = type(class) == "string" and CLASSIFICATION[class] or nil
        tf = flag(tf, 128, "UnitCanAttack", "player", "target")
        tf = flag(tf, 64, "UnitIsDead", "target")
        tf = flag(tf, 8, "UnitIsTapDenied", "target")
        tf = flag(tf, 4, "UnitIsPlayer", "target")
        tf = flag(tf, 2, "UnitIsUnit", "targettarget", "player")
        if okPet and hasPet then tf = flag(tf, 1, "UnitIsUnit", "targettarget", "pet") elseif not okPet then tf = nil end
        if tl and tf and type(name) == "string" then
            g = G.target
            g.level, g.flags, g.nameHash = tl < 0 and 255 or tl, tf, nameHash(name)
            state.target = g
        end
        local mine, pets = threatOf("player"), nil
        if okPet then
            if hasPet then pets = threatOf("pet") else pets = 0 end   -- no pet: 0; a pet whose threat cannot be read: unknown
        end
        g = G.threat
        g.player, g.pet = mine, pets
        state.threat = mine and pets and g
    end
    local petMax = okPet and hasPet and num(get("UnitHealthMax", "pet"))
    g = G.pet
    g.healthMax = petMax
    state.pet = petMax and g

    local map = num(get("C_Map.GetBestMapForUnit", "player"))
    local pos = map and get("C_Map.GetPlayerMapPosition", map, "player")
    local facing = num(get("GetPlayerFacing"))
    if type(pos) == "table" and type(pos.GetXY) == "function" and facing then
        local ok, xy = fill(xyValues, pcall(pos.GetXY, pos))
        if ok and num(xy[1]) and num(xy[2]) then
            g = G.position
            g.map, g.x, g.y = map, floor(xy[1] * 65535 + 0.5), floor(xy[2] * 65535 + 0.5)
            g.facing = floor(facing / (2 * math.pi) * 256 + 0.5) % 256
            state.position = g
        end
    end

    local money, free = num(get("GetMoney")), 0
    for bag = 0, 4 do
        local slots = num(get("C_Container.GetContainerNumFreeSlots", bag))
        free = free and slots and free + slots
    end
    g = G.purse
    g.money, g.bagFree = money, free
    state.purse = money and free and g

    -- the main hand: an empty slot is item 0; no enchant is 0 seconds
    local okItem, item = read("GetInventoryItemID", "player", 16)
    local okEnchant, enchant = readInto(enchantValues, "GetWeaponEnchantInfo")
    if okItem and (item == nil or num(item)) and okEnchant and (not enchant[1] or num(enchant[2])) then
        g = G.hand
        g.item, g.enchant = item or 0, enchant[1] and max(1, ceil(enchant[2] / 1000)) or 0
        state.hand = g
    end
    state.loot = loot
    state.uiError = uiError.error and uiError   -- unknown while the last error's number could not be read
    if db.format >= 2 then ns.Strip2.unitGroups(state, ns.Strip2.reads) end   -- groups 15 and 16
    return state
end

----------------------------------------------------------------------
-- Objects and the carousel (section 6)
----------------------------------------------------------------------
-- id -> { text = fn, every = seconds between versions, dirty, obj = the newest version's bytes,
--         version, changedAt }; the question (1) also has value, want and rounds
local objects = {}
local sending        -- { id, version, chunks, index, till = when the chunk may change } or nil
local chunkLen = 0

-- The client's compressor and its method now, or nil when the client has none.
local function compressor()
    local EU = _G.C_EncodingUtil
    if type(EU) ~= "table" or type(EU.CompressString) ~= "function" then return nil end
    return EU.CompressString, lookup("Enum.CompressionMethod.Deflate") or 0
end

-- The compressed text with the compressor and the method that made it, or nil when it is not
-- shorter or could not be made (the call failed; the answer was secret, no string, or empty).
-- After a nil the same text is tried again at the next refresh, as before #175: only a
-- compressed text that was used counts as this compressor's answer for the text.
local function deflate(text)
    local fn, method = compressor()
    if not fn then return nil end
    local ok, z = pcall(fn, text, method)
    z = ok and plain(z)
    if type(z) == "string" and #z > 0 and #z < #text then return z, fn, method end
    return nil
end

-- The object bytes for a text (nil: the addon cannot read the object now).
local function objectBytes(text)
    local bytes, fn, method
    if text == nil then
        bytes = { 255 }
    elseif text == ns.Strip2.SECRET then
        bytes = { 253 }   -- format 2: secret now, keep the last copy (docs/specs/213.md, section 7)
    else
        local z
        z, fn, method = deflate(text)
        local from = z or text
        bytes = { z and 1 or 0 }
        for i = 1, #from do bytes[i + 1] = from:byte(i) end
    end
    local s1, s2 = check(bytes)
    bytes[#bytes + 1], bytes[#bytes + 2] = s1, s2
    return bytes, fn, method
end

-- Whether the object's newest version was made from this text in a way that gives the same
-- bytes again (#175): no text at all, or a text that went compressed by the compressor that is
-- there now. A text that went as it is (the compressor failed, or gave nothing shorter) is
-- tried again, as before.
local function madeFrom(o, text)
    if not o.obj or o.from ~= (text or false) then return false end
    if text == nil then return true end
    local fn, method = compressor()
    return fn ~= nil and o.packer == fn and o.method == method
end

local function chunksOf(bytes)
    if chunkLen < 3 then return nil end -- not even the three bytes of format 254 fit one chunk
    if #bytes > MAX_CHUNKS * chunkLen then
        local s1, s2 = check({ 254 })
        bytes = { 254, s1, s2 }
    end
    local out = {}
    for i = 1, #bytes, chunkLen do
        local part = {}
        for j = i, min(i + chunkLen - 1, #bytes) do part[#part + 1] = bytes[j] end
        out[#out + 1] = part
    end
    return out
end

local function sameBytes(a, b)
    if not a or not b or #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

-- Builds the object's newest version when it is marked changed, at most once every
-- `o.every` seconds (a version number then cannot come round while a reader holds a piece).
local function refresh(id, now)
    local o = objects[id]
    if not o then return nil end
    -- `gap`, when an object has one, is the least time between two reads, whether or not the
    -- read changed anything (objects 21 and 22: their reads are not cheap).
    if o.dirty and (not o.changedAt or now - o.changedAt >= o.every) and (not o.gap or not o.readAt or now - o.readAt >= o.gap) then
        o.dirty, o.readAt = false, now
        -- format 3: an object with a binary form is built in it (object format 2, #232); when its
        -- bytes pass what one version may send, they go deflated (object format 3, #251)
        if ns.Strip2.three and o.bin then
            ns.Strip2.refreshBin(o, now, check, MAX_CHUNKS * chunkLen, deflate)
            return o.obj and o
        end
        -- `key`, when the text function gives one, is what counts as a change in place of
        -- the bytes: the text without what moves too often to send for (the bags' ammunition).
        local ok, text, key = pcall(o.text, o)
        if not ok then text, key = nil, nil end
        -- The bytes are made only when they can be needed (#175): not when the key says
        -- nothing changed, and not when the newest version was made from this very text
        -- (`madeFrom`). `from` is that text, false for no text; `packer` and `method` the
        -- compressor that answered for it.
        local same, bytes, fn, method
        if key ~= nil then
            same = key == o.key
        elseif madeFrom(o, text) then
            same = true
        end
        if not same then
            bytes, fn, method = objectBytes(text)
            if key == nil then same = sameBytes(bytes, o.obj) end
            if same then o.from, o.packer, o.method = text or false, fn, method end   -- the same bytes: now known to come from this text
        end
        if not same then
            o.version = ((o.version or math.random(0, 65535)) + 1) % 65536
            o.obj, o.changedAt, o.rounds = bytes, now, o.want
            o.from, o.packer, o.method, o.chunks = text or false, fn, method, nil
        end
        o.key = key
    end
    return o.obj and o
end

local IDS = 23      -- the object ids, 1 to this

-- The next object in the order of the ids, after `id`; nil when none is current.
local function nextObject(id, now)
    for step = 1, IDS do
        local try = (id + step - 1) % IDS + 1
        local o = refresh(try, now)
        if o then
            -- an object's chunks are kept until its bytes or the chunk's length change (#175):
            -- the carousel sends every object again and again
            if o.chunks == nil or o.chunksOf ~= o.obj or o.chunksAt ~= chunkLen then
                o.chunks, o.chunksOf, o.chunksAt = chunksOf(o.obj) or false, o.obj, chunkLen
            end
            if o.chunks then return { id = try, version = o.version, chunks = o.chunks, index = 1 } end
        end
    end
    return nil
end

-- Moves the carousel on when the chunk on the row has been up for `dwell`. Returns true when
-- the row must be drawn again. A chunk's time starts when it is drawn (drawFrame sets
-- `till`), so no chunk is passed over before it was on the row.
local function advance(now)
    if sending and (not sending.till or now < sending.till) then return false end
    -- format 3's back-off: a chunk begun while the game was slow stays its two frames (section 4 B)
    if sending and (sending.frames or 1) < (sending.need or 1) then return false end
    if db.format >= 2 then
        local was = sending
        sending = ns.Strip2.nextSend(sending, ns.Strip2.IDS, objects, refresh, ns.Strip2.chunksOf, now, db.dwell / 100)
        return sending ~= nil or was ~= nil
    end
    if sending and sending.index < #sending.chunks then
        sending.index, sending.till = sending.index + 1, nil
        return true
    end
    if sending then
        local o = objects[sending.id]
        -- a question is sent in two rounds, then leaves the queue; only the version that was
        -- just sent counts, not one typed meanwhile
        if o and o.rounds and o.version == sending.version then
            o.rounds = o.rounds - 1
            if o.rounds <= 0 then o.obj, o.rounds = nil, nil end
        end
    end
    local was = sending
    sending = nextObject(sending and sending.id or IDS, now)
    return sending ~= nil or was ~= nil
end

local function mark(id)
    if objects[id] then objects[id].dirty = true end
end

-- What each object says (section 6). A function returns the text, or nil when the addon
-- cannot read the object now.
-- The creature's id is the sixth part of its GUID (seen 14 Nov 2026 on a creature out of
-- combat: "Creature-0-<server>-<instance>-<zone>-1984-<spawn>", not secret), as a string of at
-- most 9 digits; nil for a player, a pet and other things.
local function creatureId(guid)
    local kindOf, id
    if type(guid) == "string" then kindOf, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-([1-9]%d*)%-%x+$") end
    if kindOf ~= "Creature" and kindOf ~= "Vehicle" or (id and #id > 9) then return nil end
    return id
end

local targetText
do
-- The target as read, kept in place a build (#175). `targetRead` gives true, false for no target
-- (the object is null), or nil when it cannot be read (a failed or secret read: format 255).
local T = {}
local function targetRead()
    local ok, exists = read("UnitExists", "target")
    if not ok then return nil end
    if not exists then return false end
    local name, class, level = get("UnitName", "target"), get("UnitClassification", "target"), num(get("UnitLevel", "target"))
    local okKind, kind = read("UnitCreatureType", "target")
    if type(name) ~= "string" or type(class) ~= "string" or not level or not okKind then return nil end
    -- The reaction to the player is 1 to 8 (seen: 4). `get` gives nil for a value that is
    -- secret or cannot be read.
    local guid, reaction = get("UnitGUID", "target"), get("UnitReaction", "target", "player")
    local id = creatureId(guid)
    if type(reaction) ~= "number" or reaction < 1 or reaction > 8 or reaction ~= floor(reaction) then reaction = nil end
    T.name, T.kind, T.class, T.level = name, type(kind) == "string" and kind or nil, class, floor(level)
    T.id, T.reaction = id and tonumber(id) or nil, reaction
    return true
end

function targetText()
    local r = targetRead()
    if r == nil then return nil end
    if not r then return "null" end
    return ('{"name": %s, "type": %s, "class": %s, "level": %s, "id": %s, "reaction": %s}'):format(jsonString(T.name),
        T.kind and jsonString(T.kind) or "null", jsonString(T.class), jsonNumber(T.level),
        T.id and jsonNumber(T.id) or "null", T.reaction and jsonNumber(T.reaction) or "null")
end

-- Object 2 in binary (docs/specs/232.md, part E; the shape is reader/hellolink-format/src/objects.rs):
-- no target as one byte 0; else 1, then the record of its six fields, all present, a null as an Opt.
ns.Strip2.targetBin = function(b)
    local B = ns.Strip2.bin
    local r = targetRead()
    if r == nil then return nil end
    if not r then b[1] = 0 return 1 end
    b[1], b[2] = 1, 63
    local at = B.text(b, 2, T.name)
    at = B.optText(b, at, T.kind)
    at = B.text(b, at, T.class)
    at = B.svar(b, at, T.level)
    at = B.optInt(b, at, T.id)
    return B.optInt(b, at, T.reaction)
end
ns.Strip2.targetText = targetText   -- for the tests
end

-- True when `s` is well-formed UTF-8: a reader refuses an object whose text is not.
local function utf8ok(s)
    local i, n = 1, #s
    while i <= n do
        local c = s:byte(i)
        local more = c < 0x80 and 0 or (c >= 0xC2 and c <= 0xDF) and 1 or (c >= 0xE0 and c <= 0xEF) and 2
            or (c >= 0xF0 and c <= 0xF4) and 3
        if not more then return false end
        for k = 1, more do
            local b = s:byte(i + k)
            if not b or b < 0x80 or b > 0xBF then return false end
        end
        local second = s:byte(i + 1)
        if (c == 0xE0 and second < 0xA0) or (c == 0xED and second > 0x9F) or (c == 0xF0 and second < 0x90)
            or (c == 0xF4 and second > 0x8F) then return false end
        i = i + more + 1
    end
    return true
end

-- The instance's facts beside the place (#91). Seen 14 Nov 2026 in a city: IsInInstance gave
-- false and "none"; GetInstanceInfo gave the continent's name, "none" and, eighth, 0, none of
-- them secret. Not seen inside an instance. A function that is missing, fails or gives a secret
-- value leaves its keys null; the place itself stays.
local placeText
do
-- The place as read, kept in place a build (#175); `placeRead` says false when it cannot be read.
local P = {}
local function placeRead()
    local map = num(get("C_Map.GetBestMapForUnit", "player"))
    local zone = get("GetRealZoneText")
    local okSub, sub = read("GetSubZoneText")
    -- a map that is no whole number under 2^31 (`finite`) cannot be read, in both formats (review of #264)
    if not map or not finite(map) or type(zone) ~= "string" or not okSub
        or (sub ~= nil and type(sub) ~= "string") then return false end
    local okIn, inside = readAll("IsInInstance")
    local okInfo, info = readAll("GetInstanceInfo")
    local inIt                              -- not `okIn and inside[1]`: a failed read is no `false`
    if okIn then inIt = inside[1] end
    local kind = okInfo and info[2]
    local imap = okInfo and info[8]
    local name = okInfo and info[1]
    if type(inIt) ~= "boolean" then inIt = nil end
    if type(kind) ~= "string" or #kind > 16 or not kind:match("^%a+$") then kind = nil end
    if type(imap) ~= "number" or imap < 0 or imap > 65535 or imap ~= floor(imap) then imap = nil end
    if type(name) ~= "string" or #name > 200 or not utf8ok(name) then name = nil end
    P.map, P.zone, P.sub, P.inside, P.kind, P.imap, P.name = floor(map), zone, sub or "", inIt, kind, imap, name
    return true
end

function placeText()
    if not placeRead() then return nil end
    return ('{"map": %s, "zone": %s, "sub": %s, "instance": %s, "instanceType": %s, "instanceMap": %s, "instanceName": %s}'):format(
        jsonNumber(P.map), jsonString(P.zone), jsonString(P.sub), P.inside == nil and "null" or tostring(P.inside),
        P.kind and jsonString(P.kind) or "null", P.imap and jsonNumber(P.imap) or "null", P.name and jsonString(P.name) or "null")
end

-- Object 3 in binary (docs/specs/232.md, part E; the shape is reader/hellolink-format/src/objects.rs):
-- the record of its seven fields, all present; the instance's four as Opts.
ns.Strip2.placeBin = function(b)
    local B = ns.Strip2.bin
    if not placeRead() then return nil end
    b[1] = 127
    local at = B.svar(b, 1, P.map)
    at = B.text(b, at, P.zone)
    at = B.text(b, at, P.sub)
    if P.inside == nil then b[at + 1] = 0 at = at + 1 else b[at + 1], b[at + 2] = 1, P.inside and 1 or 0 at = at + 2 end
    at = B.optText(b, at, P.kind)
    at = B.optInt(b, at, P.imap)
    return B.optText(b, at, P.name)
end
ns.Strip2.placeText = placeText   -- for the tests
end

-- True when `t` is a table an addon may index: not secret, and readable where the client has
-- a say in that (canaccesstable). Nothing is done with `t` before the client was asked.
local function usable(t)
    local isSecret = _G.issecretvalue
    if type(isSecret) == "function" and isSecret(t) then return false end
    if type(t) ~= "table" then return false end
    local can = _G.canaccesstable
    if type(can) == "function" then
        local ok, yes = pcall(can, t)
        if not ok or not yes then return false end
    end
    return true
end

-- A field of a table the client returned: `ok, value`. `ok` is false when the table may not
-- be indexed or the value is secret.
local function field(t, key)
    if not usable(t) then return false end
    local v = t[key]
    local isSecret = _G.issecretvalue
    if type(isSecret) == "function" and isSecret(v) then return false end
    return true, v
end

-- Returns the text and the key that decides a change (see refresh): the text with the
-- ammunition's count left out. Each shot takes one from that count; without the key the object
-- was sent again about every two seconds of a fight (seen 13 Nov 2026, #44). So the
-- ammunition's count in the object, and the slot a stack of it freed, are those of the last
-- other change of the bags.
-- `ok, id` of the ammunition (inventory slot 0): id nil with none. `ok` false when the client
-- cannot say: then a shot cannot be told from another change, and the object is not read (#138).
local function ammoId()
    local ok, id = read("GetInventoryItemID", "player", 0)
    if not ok or (id ~= nil and not num(id)) then return false end
    return true, id
end

local bagsText
do
-- The bags as read, kept in place a build (#175): each item's count, the ids in order, the free
-- slots of bags 0 to 4, the slots that hold ammunition, and the ammunition's id. False: cannot be read.
local BG = { count = {}, ids = {} }
local function bagsRead()
    local count, ids = BG.count, BG.ids
    for id in pairs(count) do count[id] = nil end
    for i = #ids, 1, -1 do ids[i] = nil end
    local free, ammoSlots = 0, 0
    local okAmmo, ammo = ammoId()
    if not okAmmo then return false end
    -- Bag 5 is this client's sixth bag (8 slots, seen 13 Nov 2026): herbs and cloth go there.
    -- Its items count; `free` stays that of bags 0 to 4, the fast block's bagFree, because
    -- what bag 5 may hold is not known. A client without it answers 0 slots.
    for bag = 0, 5 do
        local okFree, freeHere = read("C_Container.GetContainerNumFreeSlots", bag)
        local okSlots, slots = read("C_Container.GetContainerNumSlots", bag)
        if not okFree or not okSlots or not num(freeHere) or not num(slots) then return false end
        if bag <= 4 then free = free + freeHere end
        for slot = 1, slots do
            local okInfo, info = read("C_Container.GetContainerItemInfo", bag, slot)
            if not okInfo then return false end
            if info ~= nil then                -- nil is an empty slot
                local okId, id = field(info, "itemID")
                local okStack, stack = field(info, "stackCount")
                if not okId or not okStack or not num(id) or not num(stack) then return false end
                count[id] = (count[id] or 0) + stack
                if id == ammo then ammoSlots = ammoSlots + 1 end
            end
        end
    end
    for id in pairs(count) do ids[#ids + 1] = id end
    table.sort(ids)
    BG.free, BG.ammoSlots, BG.ammo = free, ammoSlots, ammo
    return true
end

function bagsText()
    if not bagsRead() then return nil end
    local items, keys = {}, {}
    for i, id in ipairs(BG.ids) do
        items[i] = ("[%s, %s]"):format(jsonNumber(id), jsonNumber(BG.count[id]))
        keys[i] = id == BG.ammo and ("[%s]"):format(jsonNumber(id)) or items[i]
    end
    -- A stack of ammunition shot empty frees a slot, so the key counts the slots that hold
    -- ammunition as free: any other change of the free slots still shows.
    return ('{"free": %s, "items": [%s]}'):format(jsonNumber(BG.free), concat(items, ", ")),
        ('{"free": %s, "items": [%s]}'):format(jsonNumber(BG.free + BG.ammoSlots), concat(keys, ", "))
end

-- Object 4 in binary (docs/specs/232.md, part E): the record of free and items, each item a
-- tuple of id and count. Into `k` the key, as the text's: the ammunition's count as 0, and the
-- slots that hold it counted as free.
local function bagsWrite(b, forKey)
    local B = ns.Strip2.bin
    b[1] = 3
    local at = B.svar(b, 1, floor(BG.free + (forKey and BG.ammoSlots or 0)))
    at = B.uvar(b, at, #BG.ids)
    for _, id in ipairs(BG.ids) do
        at = B.svar(b, at, floor(id))
        at = B.svar(b, at, (forKey and id == BG.ammo) and 0 or floor(BG.count[id]))
    end
    return at
end
ns.Strip2.bagsBin = function(b, k)
    if not bagsRead() then return nil end
    return bagsWrite(b, false), k and bagsWrite(k, true) or nil
end
ns.Strip2.bagsText = bagsText   -- for the tests
end

-- An item string's fields after "item:" (warcraft.wiki.gg, ItemLink): 1 the item id, 2 the
-- permanent enchant, 7 the random suffix (negative: ItemRandomSuffix; positive: the older
-- ItemRandomProperties). An empty field is none.
-- `ok, enchant, suffix`: `ok` false when the link is not an item link or a field is not a
-- number. Later fields (a crafter's GUID, for one) are not read.
local function linkFields(link)
    local body = type(link) == "string" and link:match("|Hitem:(.-)|h")
    if not body then return false end
    local fields, i = {}, 0
    for part in (body .. ":"):gmatch("([^:]*):") do
        i = i + 1
        if i == 2 or i == 7 then
            if part ~= "" and not tonumber(part) then return false end
            fields[i] = tonumber(part)
        end
        if i == 7 then break end
    end
    return true, fields[2], fields[7]
end

-- Object 14: the equipped gear, slots 1 to 19 (#138). Each: the item, its permanent enchant and
-- random suffix from its link, and its durability [current, max] (null for an item without).
-- Slot 0 is the ammunition, `{"item": id, "count": n}` (seen 18 Nov 2026: 3030 and 2783), left
-- out when empty. A shot takes one from its count, so the key leaves the count out (as objects 4
-- and 15 do, #44): the count sent is that of the last other change of the gear.
-- nil (cannot read) when a call fails or answers a secret.
local gearText
do
-- The gear as read, kept in place a build (#175): by slot 1 to 19, the item (false: empty), its
-- enchant and suffix (false: none) and durability (false: none); the ammunition and its count.
local GR = { id = {}, enchant = {}, suffix = {}, cur = {}, full = {} }
local function gearRead()
    local okAmmo, ammo = ammoId()
    if not okAmmo then return false end
    GR.ammo = ammo and num(ammo)
    if ammo then
        local okCount, count = read("GetInventoryItemCount", "player", 0)
        if not okCount or not finite(count) or count < 0 then return false end
        GR.ammoCount = count
    end
    for slot = 1, 19 do
        local okId, id = read("GetInventoryItemID", "player", slot)
        if not okId or (id ~= nil and not num(id)) then return false end
        GR.id[slot] = id ~= nil and num(id) or false
        if id then
            local okLink, link = read("GetInventoryItemLink", "player", slot)
            if not okLink then return false end
            local okFields, enchant, suffix = linkFields(link)
            if not okFields then return false end
            local okDur, dur = readAll("GetInventoryItemDurability", slot)
            if not okDur then return false end
            local cur, full = num(dur[1]), num(dur[2])
            GR.enchant[slot], GR.suffix[slot] = enchant or false, suffix or false
            GR.cur[slot], GR.full[slot] = (cur and full) and cur or false, (cur and full) and full or false
        end
    end
    return true
end

-- Returns the text and the key that decides a change (see refresh): the text with the
-- ammunition's count left out (#44).
function gearText()
    if not gearRead() then return nil end
    local parts, key = {}, nil
    if GR.ammo then
        parts[1] = ('"0": {"item": %s, "count": %s}'):format(jsonNumber(GR.ammo), jsonNumber(GR.ammoCount))
        key = ('"0": {"item": %s}'):format(jsonNumber(GR.ammo))
    end
    for slot = 1, 19 do
        local id = GR.id[slot]
        if id then
            local cur, full = GR.cur[slot], GR.full[slot]
            parts[#parts + 1] = ('"%d": {"item": %s, "enchant": %s, "suffix": %s, "dur": %s}'):format(slot, jsonNumber(id),
                GR.enchant[slot] and jsonNumber(GR.enchant[slot]) or "null", GR.suffix[slot] and jsonNumber(GR.suffix[slot]) or "null",
                cur and ("[%s, %s]"):format(jsonNumber(cur), jsonNumber(full)) or "null")
        end
    end
    local text = ('{"slots": {%s}}'):format(concat(parts, ", "))
    if not GR.ammo then return text end
    parts[1] = key
    return text, ('{"slots": {%s}}'):format(concat(parts, ", "))
end

-- Object 14 in binary (docs/specs/232.md, part E): the record "slots" of the fields "0" to "19"
-- (three presence bytes), "0" the ammunition {item, count}, each other a worn item {item,
-- enchant, suffix, dur}. Into `k` the key, as the text's: the ammunition's count as 0.
local function gearWrite(b, forKey)
    local B = ns.Strip2.bin
    local bits = GR.ammo and 1 or 0
    for slot = 1, 19 do
        if GR.id[slot] then bits = bits + 2 ^ slot end
    end
    b[1], b[2], b[3], b[4] = 1, bits % 256, floor(bits / 256) % 256, floor(bits / 65536)
    local at = 4
    if GR.ammo then
        b[at + 1] = 3
        at = B.svar(b, at + 1, floor(GR.ammo))
        at = B.svar(b, at, forKey and 0 or floor(GR.ammoCount))
    end
    for slot = 1, 19 do
        local id = GR.id[slot]
        if id then
            b[at + 1] = 15
            at = B.svar(b, at + 1, floor(id))
            at = B.optInt(b, at, GR.enchant[slot] and floor(GR.enchant[slot]) or nil)
            at = B.optInt(b, at, GR.suffix[slot] and floor(GR.suffix[slot]) or nil)
            if GR.cur[slot] then
                b[at + 1] = 1
                at = B.svar(b, at + 1, floor(GR.cur[slot]))
                at = B.svar(b, at, floor(GR.full[slot]))
            else
                at = at + 1
                b[at] = 0
            end
        end
    end
    return at
end
ns.Strip2.gearBin = function(b, k)
    if not gearRead() then return nil end
    return gearWrite(b, false), k and gearWrite(k, true) or nil
end
ns.Strip2.gearText = gearText   -- for the tests
end

-- One container as `{"bag": n, "size": n, "slots": [[slot, item, count], ...]}`, empty slots
-- left out, and the same with the ammunition's counts left out (the key of a change: a shot
-- takes one from its count, #44). nil when it cannot be read. With `withFamily` the container
-- also says what it may hold: `"family"`, the second value of GetContainerNumFreeSlots (0 any
-- item; seen 18 Nov 2026: 0 for bags, 1 for a quiver). A family that cannot be read is nil.
local function containerJson(bag, ammo, withFamily)
    local okSlots, size = read("C_Container.GetContainerNumSlots", bag)
    if not okSlots or not num(size) then return nil end
    local family = ""
    if withFamily and size > 0 then
        local okFree, free = readAll("C_Container.GetContainerNumFreeSlots", bag)
        if not okFree or not finite(free[2]) then return nil end
        family = (', "family": %s'):format(jsonNumber(free[2]))
    end
    local slots, keys = {}, {}
    for slot = 1, size do
        local okInfo, info = read("C_Container.GetContainerItemInfo", bag, slot)
        if not okInfo then return nil end
        if info ~= nil then
            local okId, id = field(info, "itemID")
            local okStack, stack = field(info, "stackCount")
            if not okId or not okStack or not num(id) or not num(stack) then return nil end
            slots[#slots + 1] = ("[%d, %s, %s]"):format(slot, jsonNumber(id), jsonNumber(stack))
            keys[#keys + 1] = id == ammo and ("[%d, %s]"):format(slot, jsonNumber(id)) or slots[#slots]
        end
    end
    local head = ('{"bag": %d, "size": %s%s, "slots": ['):format(bag, jsonNumber(size), family)
    return head .. concat(slots, ", ") .. "]}", head .. concat(keys, ", ") .. "]}", size
end

-- Object 15: the bags, slot by slot (#138): the keyring (-1) when the client has one, the
-- backpack (0), bags 1 to 4 and the reagent bag (5) (this client's indices: its UI source,
-- BagIndexConstants, 1.60.1). A container of no slots is left out.
local function bagSlotsText()
    local okAmmo, ammo = ammoId()
    if not okAmmo then return nil end
    local texts, keys = {}, {}
    for bag = -1, 5 do
        local text, key, size = containerJson(bag, ammo, true)
        if not text then return nil end
        if size > 0 then texts[#texts + 1], keys[#keys + 1] = text, key end
    end
    return ('{"bags": [%s]}'):format(concat(texts, ", ")), ('{"bags": [%s]}'):format(concat(keys, ", "))
end

-- Object 16: the bank's purchased tabs while the bank is open (#138): the character's, then the
-- account's (C_Bank.FetchPurchasedBankTabIDs), each as a container of object 15. "null" while
-- it is closed: the last bank seen is not kept. A bank too large for one object is sent as
-- too large (section 6), and object 15 still goes.
local bankOpen = false

-- The bank's purchased tabs as container ids, the character's then the account's; nil when a
-- list cannot be read. Every read must succeed: a bank with one type missing is not the whole bank.
local function bankBags()
    local bags = {}
    for _, kind in ipairs({ "Character", "Account" }) do
        local bankType = lookup("Enum.BankType." .. kind)
        if bankType == nil then return nil end
        local okIds, ids = read("C_Bank.FetchPurchasedBankTabIDs", bankType)
        if not okIds or not usable(ids) then return nil end
        for i = 1, #ids do
            local okBag, bag = field(ids, i)
            if not okBag or not num(bag) then return nil end
            bags[#bags + 1] = bag
        end
    end
    return bags
end

local function bankText()
    if not bankOpen then return "null" end
    local bags = bankBags()
    if not bags then return nil end
    local tabs = {}
    for i, bag in ipairs(bags) do
        tabs[i] = containerJson(bag, nil)
        if not tabs[i] then return nil end
    end
    return ('{"tabs": [%s]}'):format(concat(tabs, ", "))
end

-- The quest log, read from the client now. The states are those of docs/SCHEMA.md: failed
-- when the client says so; ready when it says complete, or every objective is finished;
-- in_progress when an objective has moved; accepted when none has; unknown when the client
-- gives neither a flag nor objectives. Finished objectives decide, not summed counts.
-- `ok, value` for a yes-or-no the client may not have a function for. A missing function is
-- the client saying nothing (ok, nil); a failed call or a secret answer is not ok.


-- A field of another addon's table, read without running any code of that addon: rawget, so
-- no `__index` is called. nil when the table may not be indexed or the value is secret.
local function rawField(t, key)
    if not usable(t) then return nil end
    return plain(rawget(t, key))
end

-- A text of another addon for the JSON: a string that is not empty, at most `limit` bytes
-- and well-formed UTF-8; else nil.
local function guideText(v, limit)
    if type(v) == "string" and v ~= "" and #v <= limit and utf8ok(v) then return v end
    return nil
end

-- Object 17: the trainer window while it is open (#141), read as this client's own trainer UI
-- reads it (Blizzard_TrainerUI, forever branch). GetTrainerServiceInfo gives the name, the state
-- ("available", "unavailable", "used"), an icon, the required level and the rank text; the step
-- service (GetTrainerServiceStepIndex) is the stage a profession trainer teaches. The window's
-- filter decides which services the client lists; the addon does not change it, so the object
-- carries it. A pet trainer's costs are pet training points, not copper (the client's UI shows
-- them so for Enum.TrainerType.Pet): `pet` says which. "null" while no trainer window is open. A
-- failed or secret read: nil.
local trainerOpen = false
local TRAINER_FILTERS = { "available", "unavailable", "used" }
local function trainerText()
    if not trainerOpen then return "null" end
    local okGuid, guid = read("UnitGUID", "npc")
    local okN, n = read("GetNumTrainerServices")
    local okStep, step = read("GetTrainerServiceStepIndex")
    local okTrade, trade = read("IsTradeskillTrainer")
    local okType, kind = read("C_Trainer.GetTrainerType")
    local petType = lookup("Enum.TrainerType.Pet")
    if not okType or not num(kind) or not num(petType) then return nil end
    if not okGuid or not okN or not num(n) or not okStep or (step ~= nil and not num(step)) or not okTrade then return nil end
    -- `step` is an index in the services, or none: the client once gave a step past its list,
    -- most likely after a service was bought (seen 16 Nov 2026, #160); a reader would take it as an index.
    if step ~= nil and (step < 1 or step > n or step ~= floor(step)) then step = nil end
    local skill
    if trade and n > 0 then
        local okSkill, line = read("GetTrainerServiceSkillLine", step or 1)
        if not okSkill or (line ~= nil and not guideText(line, 60)) then return nil end
        skill = line
    end
    local filter = {}
    for _, f in ipairs(TRAINER_FILTERS) do
        local ok, on = read("GetTrainerServiceTypeFilter", f)
        if not ok then return nil end
        filter[#filter + 1] = ('"%s": %s'):format(f, on and "true" or "false")
    end
    local services = {}
    for i = 1, n do
        local ok, info = readAll("GetTrainerServiceInfo", i)
        if not ok then return nil end
        local name, state, reqLevel, rank = info[1], info[2], info[4], info[5]
        if not guideText(name, 80) or (state ~= "available" and state ~= "unavailable" and state ~= "used") then return nil end
        if (reqLevel ~= nil and not num(reqLevel)) or (rank ~= nil and rank ~= "" and not guideText(rank, 60)) then return nil end
        local okReq, req = readAll("GetTrainerServiceSkillReq", i)
        if not okReq then return nil end
        local reqText = "null"
        if req[1] ~= nil then
            if not guideText(req[1], 60) or not num(req[2]) then return nil end
            reqText = ("[%s, %s]"):format(jsonString(req[1]), jsonNumber(req[2]))
        end
        local okCost, cost = read("GetTrainerServiceCost", i)
        if not okCost or (cost ~= nil and not num(cost)) then return nil end
        services[i] = ("[%s, %s, %s, %s, %s, %s]"):format(jsonString(name), (rank and rank ~= "") and jsonString(rank) or "null",
            jsonString(state), reqLevel and jsonNumber(reqLevel) or "null", reqText, cost and jsonNumber(cost) or "null")
    end
    return ('{"npc": %s, "pet": %s, "skill": %s, "step": %s, "filter": {%s}, "services": [%s]}'):format(creatureId(guid) or "null",
        kind == petType and "true" or "false", skill and jsonString(skill) or "null", step and jsonNumber(step) or "null", concat(filter, ", "), concat(services, ", "))
end

-- A long text of a guide for the JSON: as guideText, but a text over `limit` bytes is cut and
-- ends with an ellipsis, the whole within `limit`. The cut is at a character's border, and
-- not inside a texture code (|T...|t) or the ten characters of a colour code (|cAARRGGBB).
-- An escaped bar (||) is text. It may be inside coloured text: the cut text can lack its closing |r.
local ELLIPSIS = "\226\128\166"

local function cutText(v, limit)
    if type(v) ~= "string" or v == "" or not utf8ok(v) then return nil end
    if #v <= limit then return v end
    local n = limit - #ELLIPSIS
    while n > 0 do                                   -- not between the bytes of one character
        local b = v:byte(n + 1)
        if b < 0x80 or b > 0xBF then break end
        n = n - 1
    end
    -- Walk the codes from the start, so that an escaped bar (||) is never taken for one. Stop
    -- before a code that the cut leaves unfinished: a texture without its |t, a colour code of
    -- fewer than ten characters, a bar with nothing after it.
    local s, i = v:sub(1, n), 1
    while true do
        i = s:find("|", i, true)
        if not i then break end
        local kind = s:sub(i + 1, i + 1)
        if kind == "|" then
            i = i + 2
        elseif kind == "T" then
            local close, j = nil, i + 2              -- the code's |t: an escaped bar in it is text too
            while true do
                j = s:find("|", j, true)
                if not j then break end
                local after = s:sub(j + 1, j + 1)
                if after == "t" then close = j + 1 break end
                j = j + (after == "|" and 2 or 1)
            end
            if not close then s = s:sub(1, i - 1) break end
            i = close + 1
        elseif kind == "c" then
            if i + 9 > #s then s = s:sub(1, i - 1) break end
            i = i + 10
        elseif kind == "" then
            s = s:sub(1, i - 1)
            break
        else
            i = i + 2
        end
    end
    return s .. ELLIPSIS
end

-- Object 7: where a guide addon's arrow points. One addon is read, RestedXP Guides: its
-- table `RXP` holds the arrow, the arrow the element it points at, the element its step
-- (seen 13 and 14 Nov 2026: zone 1434, x 40.6, y 3.5, per cent of the map, no title;
-- step.index 109, step.text with colour and texture codes). Only values are read, with
-- rawget; no code of that addon is called. "null": the addon is not there, or the arrow
-- holds no place.
-- ponytail: whether the arrow is shown is not looked at. Add it when a hidden arrow is seen
-- to keep a place.
local function waypointText()
    local element = rawField(rawField(rawget(_G, "RXP"), "arrowFrame"), "element")
    if not usable(element) then return "null" end
    local map, x, y = rawField(element, "zone"), rawField(element, "x"), rawField(element, "y")
    if not finite(map) or not finite(x) or not finite(y) or map < 0 or map > 65535 or x < 0 or x > 100 or y < 0 or y > 100 then
        return "null"
    end
    local step = rawField(element, "step")
    local title = guideText(rawField(element, "title"), 200) or guideText(rawField(step, "arrowtext"), 200)
        or guideText(rawField(step, "title"), 200)
    local index, text = rawField(step, "index"), cutText(rawField(step, "text"), 600)
    if not finite(index) or index < 0 or index ~= floor(index) then index = nil end
    -- the guide's name (seen 14 Nov 2026: currentGuide.name "29-32 Duskwood")
    local guide = guideText(rawField(rawField(rawget(_G, "RXP"), "currentGuide"), "name"), 200)
    return ('{"source": "RXPGuides", "guide": %s, "map": %s, "x": %s, "y": %s, "title": %s, "step": %s, "text": %s}'):format(
        guide and jsonString(guide) or "null", jsonNumber(map), jsonNumber(x / 100 * 65535 + 0.5), jsonNumber(y / 100 * 65535 + 0.5),
        title and jsonString(title) or "null", index and jsonNumber(index) or "null", text and jsonString(text) or "null")
end

-- Object 11: the guide's steps: the step that the arrow's element belongs to and the four after
-- it. The guide's list is read with rawget, as object 7 reads the arrow (seen 14 Nov 2026:
-- currentGuide.steps is a list, steps[n].index is n, steps[n].text a text of several lines,
-- steps[n].elements a list whose entries may hold zone, x and y as the arrow's element does;
-- seen 18 Nov 2026: a step has active and completed, an element tag and questId). A step's
-- place is that of its first element that has one, among the first 20 (seen: 12 in one step);
-- its tags and quests are those of the same 20. "null": no guide addon, no list, or no current
-- step. The object also carries RXP's orphaned quests as RXP keeps them, and the names its
-- targeting looks for.
-- At most 200 quest ids and 40 element pairs a step (written as numbers below: this chunk is at
-- Lua's limit of 200 locals). 200 pairs over five steps could make the object too large (254).
local NEXT_STEPS, STEP_TEXT, STEP_ELEMENTS = 4, 400, 20
local NAMES = 20    -- names in each list of targets

-- The values of a list of another addon, read with rawget, in order and each once: those that
-- `keep(v)` turns into JSON. A secret value is left out, and the list goes on. At most `limit`
-- are kept, counted after the repeats are left out; at most `scan` (default `limit`) looked at.
local function listJson(list, limit, keep, scan)
    local out, seen, isSecret = {}, {}, _G.issecretvalue
    if not usable(list) then return "[]" end
    for i = 1, scan or limit do
        if #out >= limit then break end
        local v = rawget(list, i)
        -- asked whether it is secret before anything else is done with it, a comparison included
        local secret = type(isSecret) == "function" and isSecret(v)
        if not secret then
            if v == nil then break end
            local j = keep(v)
            if j and not seen[j] then seen[j], out[#out + 1] = true, j end
        end
    end
    return "[" .. concat(out, ", ") .. "]"
end

local function questJson(v)
    return finite(v) and v > 0 and v == floor(v) and jsonNumber(v) or nil
end

local function nameJson(v)
    v = cutText(v, 60)
    return v and jsonString(v)
end

-- RXP's targeting asks the names of what to look for (seen 18 Nov 2026: four lists, in the
-- order target, mobs, scan, rares). "null" when it cannot be asked.
local function targetsJson(rxp)
    local fn = rawField(rawField(rxp, "targeting"), "GetCurrentTargets")
    if type(fn) ~= "function" then return "null" end
    local ok, lists = gather(pcall(fn))
    if not ok then return "null" end
    local parts = {}
    for i, key in ipairs({ "target", "mobs", "scan", "rares" }) do
        parts[i] = ('"%s": %s'):format(key, listJson(lists[i], NAMES, nameJson))
    end
    return "{" .. concat(parts, ", ") .. "}"
end

-- RXP's orphaned quests: its table keyed by quest id (QuestLog.lua, GetOrphanedQuests:
-- orphanedList[questID] = { ... }), read raw, the keys sorted. At most 200.
local function orphansJson(list)
    if not usable(list) then return "[]" end
    local ids, isSecret = {}, _G.issecretvalue
    local k = next(list)
    while k ~= nil and #ids < 200 do
        if not (type(isSecret) == "function" and isSecret(k)) and questJson(k) then ids[#ids + 1] = k end
        k = next(list, k)
    end
    table.sort(ids)
    for i, id in ipairs(ids) do ids[i] = jsonNumber(id) end
    return "[" .. concat(ids, ", ") .. "]"
end

local function tagJson(v)
    return type(v) == "string" and #v <= 40 and v:match("^[%w_]+$") and jsonString(v) or nil
end

local function stepsText()
    local rxp = rawget(_G, "RXP")
    local guide = rawField(rxp, "currentGuide")
    local steps = rawField(guide, "steps")
    -- The current step as RXP keeps it for this guide (RXPGuides.lua, SaveGuideProgress:
    -- RXPCData.guideProgress[guide.key].step). The arrow's step is the fall-back only: the arrow
    -- can point at the corpse, a waypoint with no step (map.lua).
    local index = rawField(rawField(rawField(rawget(_G, "RXPCData"), "guideProgress"), rawField(guide, "key")), "step")
    if not finite(index) then
        index = rawField(rawField(rawField(rawField(rxp, "arrowFrame"), "element"), "step"), "index")
    end
    if not usable(steps) or not finite(index) or index < 0 or index ~= floor(index) then return "null" end
    local out = {}
    for n = index, index + NEXT_STEPS do
        local step = rawField(steps, n)
        if not usable(step) then break end
        local text, elements = cutText(rawField(step, "text"), STEP_TEXT), rawField(step, "elements")
        local map, x, y
        local tags, quests, pairList = {}, {}, {}
        for e = 1, STEP_ELEMENTS do
            local element = rawField(elements, e)
            if not usable(element) then break end
            local m, ex, ey = rawField(element, "zone"), rawField(element, "x"), rawField(element, "y")
            if not map and finite(m) and finite(ex) and finite(ey) and m >= 0 and m <= 65535 and ex >= 0 and ex <= 100
                and ey >= 0 and ey <= 100 then
                map, x, y = m, ex, ey
            end
            local tag, quest = rawField(element, "tag"), rawField(element, "questId")
            if tag ~= nil then tags[#tags + 1] = tag end
            if quest ~= nil then quests[#quests + 1] = quest end
            -- 0.8.1: the element as [tag, quest id], in order; one pair for each id of a list
            local tagText, listed = tagJson(tag) or "null", false
            -- isOnQuest and isQuestTurnedIn keep a list of ids instead (functions.lua: element.questIds)
            local list = rawField(element, "questIds")
            if usable(list) then
                local isSecret = _G.issecretvalue
                for k = 1, 200 do
                    -- a secret id is a pair with null, not the end of the list (0.8.1)
                    local raw = rawget(list, k)
                    local secret = type(isSecret) == "function" and isSecret(raw)
                    if not secret and raw == nil then break end
                    local id = not secret and raw or nil
                    if id ~= nil then quests[#quests + 1] = id end
                    listed = true
                    if #pairList < 40 then pairList[#pairList + 1] = "[" .. tagText .. ", " .. (questJson(id) or "null") .. "]" end
                end
            end
            if not listed and #pairList < 40 then
                pairList[#pairList + 1] = "[" .. tagText .. ", " .. (questJson(quest) or "null") .. "]"
            end
        end
        out[#out + 1] = ('{"step": %s, "text": %s, "map": %s, "x": %s, "y": %s, "tags": %s, "quests": %s, "done": %s, "elements": [%s]}'):format(
            jsonNumber(n), text and jsonString(text) or "null", map and jsonNumber(map) or "null",
            map and jsonNumber(x / 100 * 65535 + 0.5) or "null", map and jsonNumber(y / 100 * 65535 + 0.5) or "null",
            listJson(tags, STEP_ELEMENTS, tagJson), listJson(quests, 200, questJson, 20 * 201),
            rawField(step, "completed") == true and "true" or "false", concat(pairList, ", "))
    end
    local name = guideText(rawField(guide, "name"), 200)
    -- Only the list as RXP keeps it: RXP.GetOrphanedQuests would write it anew, and is never called.
    return ('{"source": "RXPGuides", "guide": %s, "steps": [%s], "orphans": %s, "targets": %s}'):format(
        name and jsonString(name) or "null", concat(out, ", "), orphansJson(rawField(rxp, "orphanedList")),
        targetsJson(rxp))
end

-- A whole amount that is not negative, or `null`, for the JSON.
local function jsonAmount(v, whole)
    if not finite(v) or v < 0 or (whole and v ~= floor(v)) then return "null" end
    return jsonNumber(v)
end

-- Object 9: the journey the route addon has planned. It is asked through that addon's public
-- interface, ShortestPathForever.API.Journey, which only reads and gives new tables (seen
-- 14 Nov 2026: a goal of map 1415 with x and y as fractions of the map, one leg "walk" of
-- 40 s, owner "RestedXP"). No other function of that addon is called: none that plans, steers
-- or cancels a journey. "null": no such addon, no journey, a plan not ready, or a failure.
-- The interface gives no place for a leg, and none is taken from the addon's inner tables.
local LEGS = 20     -- the legs sent; `legCount` says how many there are
local SCAN = 200    -- the legs counted
local routeText
do
-- An amount: a whole number of 0 or more (the floor of it), nil when it is no amount (as jsonAmount).
local function amount(v, whole)
    if not finite(v) or v < 0 or (whole and v ~= floor(v)) then return nil end
    return floor(v)
end
-- The journey as read, kept in place a build (#175); `routeRead` fills it and says false for "null".
local R = { mode = {}, seconds = {}, text = {} }
local function routeRead()
    local journey = rawField(rawField(rawget(_G, "ShortestPathForever"), "API"), "Journey")
    if type(journey) ~= "function" then return false end
    local ok, j = pcall(journey)
    j = ok and plain(j)
    local goal = rawField(j, "goal")
    local map, x, y = rawField(goal, "map"), rawField(goal, "x"), rawField(goal, "y")
    if not finite(map) or not finite(x) or not finite(y) or map < 0 or map > 65535 or x < 0 or x > 1 or y < 0 or y > 1 then
        return false
    end
    -- The legs are counted up to SCAN; with more, how many there are is not known (nil).
    local legs, n, count, isSecret = rawField(j, "legs"), 0, 0, _G.issecretvalue
    while usable(legs) and count <= SCAN do
        local leg = rawget(legs, count + 1)
        -- asked whether it is secret before anything else is done with it, a comparison included
        local secret = type(isSecret) == "function" and isSecret(leg)
        if not secret and leg == nil then break end
        count = count + 1
        if not secret and usable(leg) and count <= LEGS then
            local mode = rawField(leg, "mode")
            if type(mode) ~= "string" or #mode > 24 or not mode:match("^%a+$") then mode = nil end
            n = n + 1
            R.mode[n], R.seconds[n], R.text[n] = mode or false, amount(rawField(leg, "seconds")) or false,
                guideText(rawField(leg, "text"), 120) or false
        end
    end
    R.n, R.owner, R.map, R.x, R.y = n, guideText(rawField(j, "owner"), 60), floor(map), floor(x * 65535 + 0.5), floor(y * 65535 + 0.5)
    R.title, R.left, R.index = guideText(rawField(goal, "title"), 200), amount(rawField(j, "secondsLeft")), amount(rawField(j, "index"), true)
    R.guided, R.legCount = rawField(j, "guided") == true, count <= SCAN and count or nil
    return true
end

local function jsonOr(v, f) if v then return f(v) end return "null" end
function routeText()
    if not routeRead() then return "null" end
    local out = {}
    for i = 1, R.n do
        out[i] = ('{"mode": %s, "seconds": %s, "text": %s}'):format(jsonOr(R.mode[i], jsonString),
            jsonOr(R.seconds[i], jsonNumber), jsonOr(R.text[i], jsonString))
    end
    return ('{"source": "ShortestPathForever", "owner": %s, "goal": {"map": %s, "x": %s, "y": %s, "title": %s}, '
        .. '"seconds": %s, "index": %s, "guided": %s, "legCount": %s, "legs": [%s]}'):format(
        jsonOr(R.owner, jsonString), jsonNumber(R.map), jsonNumber(R.x), jsonNumber(R.y), jsonOr(R.title, jsonString),
        jsonOr(R.left, jsonNumber), jsonOr(R.index, jsonNumber), R.guided and "true" or "false",
        jsonOr(R.legCount, jsonNumber), table.concat(out, ", "))
end

-- Object 9 in binary (docs/specs/232.md, part E; the shape is reader/hellolink-format/src/objects.rs):
-- null as one byte 0; else 1, then the record of its eight fields, all present, a null as an Opt.
local function routeBin(b)
    local B = ns.Strip2.bin
    if not routeRead() then b[1] = 0 return 1 end
    b[1], b[2] = 1, 255
    local at = B.text(b, 2, "ShortestPathForever")
    at = B.optText(b, at, R.owner)
    b[at + 1] = 15                                    -- the goal: map, x, y, title
    at = B.svar(b, at + 1, R.map)
    at = B.svar(b, at, R.x)
    at = B.svar(b, at, R.y)
    at = B.optText(b, at, R.title)
    at = B.optInt(b, at, R.left)
    at = B.optInt(b, at, R.index)
    b[at + 1] = R.guided and 1 or 0
    at = B.optInt(b, at + 1, R.legCount)
    at = B.uvar(b, at, R.n)
    for i = 1, R.n do
        b[at + 1] = 7                                 -- a leg: mode, seconds, text
        at = B.optText(b, at + 1, R.mode[i] or nil)
        at = B.optInt(b, at, R.seconds[i] or nil)
        at = B.optText(b, at, R.text[i] or nil)
    end
    return at
end
ns.Strip2.routeText, ns.Strip2.routeBin = routeText, routeBin   -- routeBin is format 3's; both for the tests
end

-- Object 12: the fight baseline (docs/specs/93.md, section 4). HelloForever leaves the last
-- counted fight in the plain global HelloForeverBaseline, which is not saved, so a reload
-- empties it. It is read with rawget; no code of that addon is called. "null": no such table
-- (no HelloForever, no counted fight yet this session, or after /hello baseline reset), or a
-- table that is not as the spec has it.
local BASELINE_MIN, BASELINE_KEEP = 3, 10   -- earlier fights before a usual value; at most kept

local function whole(v, low, high)
    return finite(v) and v >= low and v <= high and v == floor(v)
end

local baselineText
do
-- A rounded amount: the whole number nearest it; false for nil (null); nil when it is no amount
-- (`finite` holds it under 2^31, so both formats say the same).
local function rounded(v)
    if v == nil then return false end
    if not finite(v) or v < 0 then return nil end
    return floor(v + 0.5)
end

-- `[this fight, usual, how many earlier fights know it]` (for `died`: a yes-or-no, then how
-- many died) into `t3` (has1, v1, has2, v2, n), or nil when the triple is not as the spec has it.
-- The middle is null under 3.
local function tripleRead(t, died, t3)
    if not usable(t) then return nil end
    local this, usual, n = rawField(t, 1), rawField(t, 2), rawField(t, 3)
    if not whole(n, 0, BASELINE_KEEP) then return nil end
    -- Every value is checked first; only then is the middle left out under 3 (review of #110).
    if died then
        if this ~= nil and type(this) ~= "boolean" then return nil end
        if usual ~= nil and not whole(usual, 0, n) then return nil end
        t3.has1, t3.v1, t3.has2, t3.v2 = this ~= nil, this, usual ~= nil, usual
    else
        local a, b = rounded(this), rounded(usual)
        if a == nil or b == nil then return nil end
        t3.has1, t3.v1, t3.has2, t3.v2 = a ~= false, a, b ~= false, b
    end
    if n < BASELINE_MIN then t3.has2 = false end
    t3.n = n
    return true
end

-- The baseline as read, kept in place a build (#175); `baselineRead` says false for "null".
local K = { "dur", "dps", "taken", "died" }
local Bt = { triples = { {}, {}, {}, {} } }
local function baselineRead()
    local b = rawget(_G, "HelloForeverBaseline")
    if not usable(b) then return false end
    local fight, rev, counted = rawField(b, "fight"), rawField(b, "rev"), rawField(b, "counted")
    if type(fight) ~= "string" or #fight > 64 or not fight:match("^[%w%-]+$") or not whole(rev, 1, 2147483647) then
        return false
    end
    Bt.fight, Bt.rev, Bt.counted = fight, rev, false
    if counted == false then return true end
    local id, level = rawField(b, "id"), rawField(b, "level")
    if counted ~= true or not whole(id, 1, 999999999) or not whole(level, 1, 255) then return false end
    for i, k in ipairs(K) do
        if not tripleRead(rawField(b, k), k == "died", Bt.triples[i]) then return false end
    end
    Bt.counted, Bt.id, Bt.level, Bt.name = true, id, level, guideText(rawField(b, "name"), 200)
    return true
end

function baselineText()
    if not baselineRead() then return "null" end
    local head = ('{"fight": %s, "rev": %s, "counted": '):format(jsonString(Bt.fight), jsonNumber(Bt.rev))
    if not Bt.counted then return head .. "false}" end
    local parts = {}
    for i, k in ipairs(K) do
        local t = Bt.triples[i]
        parts[i] = ('"%s": [%s, %s, %s]'):format(k, t.has1 and (i == 4 and tostring(t.v1) or jsonNumber(t.v1)) or "null",
            t.has2 and jsonNumber(t.v2) or "null", jsonNumber(t.n))
    end
    return head .. ('true, "id": %s, "level": %s, "name": %s, %s}'):format(jsonNumber(Bt.id), jsonNumber(Bt.level),
        Bt.name and jsonString(Bt.name) or "null", concat(parts, ", "))
end

-- Object 12 in binary (docs/specs/232.md, part E; the shape is reader/hellolink-format/src/objects.rs):
-- null as one byte 0; else 1, then the record: an uncounted fight has its first three fields only,
-- a counted one all ten (two presence bytes); each triple a tuple of Opt, Opt and the count.
ns.Strip2.baselineBin = function(b)
    local B = ns.Strip2.bin
    if not baselineRead() then b[1] = 0 return 1 end
    b[1], b[2], b[3] = 1, Bt.counted and 255 or 7, Bt.counted and 3 or 0
    local at = B.text(b, 3, Bt.fight)
    at = B.svar(b, at, Bt.rev)
    b[at + 1] = Bt.counted and 1 or 0
    at = at + 1
    if not Bt.counted then return at end
    at = B.svar(b, at, Bt.id)
    at = B.svar(b, at, Bt.level)
    at = B.optText(b, at, Bt.name)
    for i = 1, 4 do
        local t = Bt.triples[i]
        if not t.has1 then
            b[at + 1] = 0
            at = at + 1
        elseif i == 4 then                            -- died: a yes-or-no
            b[at + 1], b[at + 2] = 1, t.v1 and 1 or 0
            at = at + 2
        else
            b[at + 1] = 1
            at = B.svar(b, at + 1, t.v1)
        end
        at = B.optInt(b, at, t.has2 and t.v2 or nil)
        at = B.svar(b, at, t.n)
    end
    return at
end
ns.Strip2.baselineText = baselineText   -- for the tests
end

-- Object 13: the acknowledgement of the assistant's way in (docs/specs/115.md, section 6): what
-- the game took from the companion, and its last question. From HelloForever's plain table
-- (read with rawget; no code of it is called) and HelloLinkAssist (Assist.lua). "null" when
-- HelloForever's table is absent or not as the spec has it, or its assistant is off.
local assistText
do
-- The acknowledgement as read, kept in place a build (#175); `assistRead` says false for "null".
local A = {}
local function assistRead()
    local hf = rawget(_G, "HelloForeverAssist")
    if not usable(hf) or rawField(hf, "on") ~= true then return false end
    local lang, shown, ask = rawField(hf, "lang"), rawField(hf, "shown"), rawField(hf, "ask")
    if type(lang) ~= "string" or not lang:match("^[%a%-]+$") or #lang > 8 then return false end
    if shown ~= nil and (type(shown) ~= "string" or #shown > 28 or not shown:match("^[%w%-:]+$")) then return false end
    A.askN = nil
    if ask ~= nil then
        if not usable(ask) then return false end
        local n, topic, t = rawField(ask, "n"), rawField(ask, "topic"), rawField(ask, "t")
        if not whole(n, 1, 65535) or type(topic) ~= "string" or #topic > 24 or not topic:match("^[%a%-]+$")
            or not whole(t, 0, 2 ^ 53) then return false end
        A.askN, A.topic, A.t = n, topic, t
    end
    local st = ns.AssistState or {}
    A.lang, A.shown, A.seq, A.re, A.left = lang, shown, st.seq, st.re, st.left
    A.taken, A.refused = st.taken or 0, st.refused or 0
    return true
end
local function numOrNull(v) return v == nil and "null" or jsonNumber(v) end
function assistText()
    if not assistRead() then return "null" end
    local askJson = A.askN and ('{"n": %s, "topic": %s, "t": %s}'):format(jsonNumber(A.askN), jsonString(A.topic), jsonNumber(A.t))
    return ('{"on": true, "lang": %s, "seq": %s, "re": %s, "ask": %s, "left": %s, "taken": %s, "refused": %s, "shown": %s}'):format(
        jsonString(A.lang), numOrNull(A.seq), numOrNull(A.re), askJson or "null", numOrNull(A.left), numOrNull(A.taken),
        numOrNull(A.refused), A.shown == nil and "null" or jsonString(A.shown))
end

-- Object 13 in binary (docs/specs/232.md, part E; the shape is reader/hellolink-format/src/objects.rs):
-- null as one byte 0; else 1, then the record of its nine fields (two presence bytes), all present.
local function whole0(v) return v and floor(v) end
ns.Strip2.assistBin = function(b)
    local B = ns.Strip2.bin
    if not assistRead() then b[1] = 0 return 1 end
    b[1], b[2], b[3], b[4] = 1, 255, 1, 1             -- present; fields 1 to 8, field 9; on: true
    local at = B.text(b, 4, A.lang)
    at = B.optInt(b, at, whole0(A.seq))
    at = B.optInt(b, at, whole0(A.re))
    if A.askN then
        b[at + 1], b[at + 2] = 1, 7                   -- ask there: n, topic, t
        at = B.svar(b, at + 2, floor(A.askN))
        at = B.text(b, at, A.topic)
        at = B.svar(b, at, floor(A.t))
    else
        at = at + 1
        b[at] = 0
    end
    at = B.optInt(b, at, whole0(A.left))
    at = B.svar(b, at, floor(A.taken))
    at = B.svar(b, at, floor(A.refused))
    return B.optText(b, at, A.shown)
end
ns.Strip2.assistText = assistText   -- for the tests
end

-- Object 8: the rested XP. The client gives nothing when there is none (seen 13 Nov 2026).
-- A value that is no amount (negative, NaN, infinite) is "cannot be read", not 0.
local restText
do
-- The rested XP as a whole number, or nil when it cannot be read.
local function restRead()
    local ok, rested = read("GetXPExhaustion")
    if not ok or (rested ~= nil and (not finite(rested) or rested < 0)) then return nil end
    return floor(rested or 0)
end
function restText()
    local rested = restRead()
    return rested and ('{"rested": %s}'):format(jsonNumber(rested)) or nil
end
-- Object 8 in binary: the record of its one field (docs/specs/232.md, part E)
ns.Strip2.restBin = function(b)
    local rested = restRead()
    if not rested then return nil end
    b[1] = 1
    return ns.Strip2.bin.svar(b, 1, rested)
end
ns.Strip2.restText = restText   -- for the tests
end

-- Object 18: the hearthstone (#180): where it is bound and when it is ready. `readyAt` is the
-- end of its cooldown in the client's time() (the fast block's clock), worked out once for each
-- cooldown start: a countdown would be a new version every second, a fixed end is not. A
-- cooldown of 1.5 s or less is the global cooldown, not the hearthstone's. Not seen in the
-- game (18 Nov 2026): whether this client answers these calls, or keeps them secret. A failed,
-- empty or secret count or cooldown: nil; a bind that cannot be read is null.
local HEARTH = 6948
local hearthAt = { start = nil, endsAt = nil, readyAt = 0 }
local function either(a, b)
    if type(lookup(a)) == "function" then return a end
    return b
end
local function hearthText()
    local okCount, count = read(either("C_Item.GetItemCount", "GetItemCount"), HEARTH)
    count = okCount and num(count)       -- no answer is not "none in the bags"
    if not count or not finite(count) then return nil end
    if count < 1 then return "null" end
    local okCd, cd = readAll(either("C_Container.GetItemCooldown", "GetItemCooldown"), HEARTH)
    local start, duration = okCd and num(cd[1]), okCd and num(cd[2])
    if not start or not duration or not finite(start) or not finite(duration) then return nil end
    -- The same start is the same cooldown: its end is the one taken at its start, whatever
    -- duration is told since, even 1.5 s. Only another start is looked at again.
    if start <= 0 or start ~= hearthAt.start then
        if duration <= 1.5 or start <= 0 then   -- no cooldown, or the global one
            hearthAt.start, hearthAt.endsAt, hearthAt.readyAt = nil, nil, 0
        else                                -- a new cooldown: its end is taken once, as told now
            local nowTime = num(get("time"))
            if not nowTime then return nil end
            hearthAt.start, hearthAt.endsAt = start, start + duration
            hearthAt.readyAt = floor(nowTime + (start + duration - clock()) + 0.5)
        end
    end
    if hearthAt.endsAt and hearthAt.endsAt <= clock() then hearthAt.readyAt = 0 end
    local bind = guideText(get("GetBindLocation"), 200)
    return ('{"bind": %s, "item": %d, "readyAt": %s}'):format(bind and jsonString(bind) or "null", HEARTH,
        jsonNumber(hearthAt.readyAt))
end

-- Object 10: which character is in the game: the first name and the realm's display name,
-- which make the key of HelloForever's saved data (seen 14 Nov 2026; the client's own folders
-- of saved files have other names).
-- The name and the realm as object 10 sends them; nil when either cannot be read.
local function whoNames()
    local name, realm = guideText(get("UnitName", "player"), 60), guideText(get("GetRealmName"), 60)
    if not name or not realm then return nil end
    return name, realm
end

-- The full name the player's own loot gave (0.8.1), or nil. Kept under the player's GUID: two
-- characters can share a first name and a realm. Only while its first word is still `name`.
function ns.SavedFullName(name)
    local me = get("UnitGUID", "player")
    local saved = type(me) == "string" and type(db.fullNames) == "table" and db.fullNames[me]
    local full = type(saved) == "table" and saved.source == "loot" and guideText(saved.fullName, 60)
    if full and full:match("^(%S+)%s+%S") == name then return full end
    return nil
end

local function whoText()
    local name, realm = whoNames()
    if not name then return nil end
    -- The class and the race as the client's file names ("HUNTER", "NightElf"): the second value
    -- of UnitClass and of UnitRace (#138). null when the client gives none; a failed or secret
    -- read, or a value that is no name, makes the object unreadable.
    local okClass, class = readAll("UnitClass", "player")
    local okRace, race = readAll("UnitRace", "player")
    if not okClass or not okRace then return nil end
    class, race = class[2], race[2]
    if class ~= nil and not guideText(class, 40) or race ~= nil and not guideText(race, 40) then return nil end
    -- The name with the family name, as the player's own loot gave it (0.8.1; kept in the saved data).
    local full = ns.SavedFullName(name)
    return ('{"name": %s, "realm": %s, "class": %s, "race": %s, "fullName": %s, "fullNameSource": %s}'):format(
        jsonString(name), jsonString(realm), class and jsonString(class) or "null", race and jsonString(race) or "null",
        full and jsonString(full) or "null", full and '"loot"' or "null")
end

-- Object 19: the quests this character has completed (seen 18 Nov 2026: 480 ids in 21 ms), by
-- id. Read only when marked: at login and when a quest is turned in, never on a timer. A failed
-- or secret read, or an id that is no whole number: nil.
local function doneText()
    local ok, ids = read("C_QuestLog.GetAllCompletedQuestIDs")
    if not ok or not usable(ids) then return nil end
    local out = {}
    for i = 1, #ids do
        local okId, id = field(ids, i)
        if not okId or not finite(id) or id < 1 or id ~= floor(id) then return nil end
        out[i] = id
    end
    table.sort(out)
    for i, id in ipairs(out) do out[i] = jsonNumber(id) end
    return ('{"ids": [%s]}'):format(concat(out, ", "))
end

-- Object 20: where the corpse lies, on the player's map, x and y as the fast block's position.
-- "null" when the client gives no place (the player is alive). Not seen while dead (18 Nov 2026).
local function corpseText()
    local okMap, map = read("C_Map.GetBestMapForUnit", "player")
    if not okMap or not finite(map) then return nil end
    local ok, pos = read("C_DeathInfo.GetCorpseMapPosition", map)
    if not ok then return nil end
    if pos == nil then return "null" end
    local okFn, getXY = field(pos, "GetXY")
    if not okFn or type(getXY) ~= "function" then return nil end
    local okXY, xy = gather(pcall(getXY, pos))
    local x, y = okXY and xy[1], okXY and xy[2]
    if not finite(x) or not finite(y) or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
    return ('{"map": %s, "x": %s, "y": %s}'):format(jsonNumber(map), jsonNumber(x * 65535 + 0.5), jsonNumber(y * 65535 + 0.5))
end

-- Object 21: the reputations, in the client's order, headers included (seen 18 Nov 2026:
-- C_Reputation.GetFactionDataByIndex gives factionID, name, reaction, currentStanding,
-- currentReactionThreshold, nextReactionThreshold, isWatched, isHeader). A field the client
-- does not give is null; a failed or secret read makes the object unreadable.
local REP_FIELDS = { { "id", "factionID" }, { "name", "name" }, { "standing", "reaction" }, { "value", "currentStanding" },
    { "min", "currentReactionThreshold" }, { "max", "nextReactionThreshold" }, { "watched", "isWatched" }, { "header", "isHeader" } }
local function repText()
    local okN, n = read("C_Reputation.GetNumFactions")
    if not okN or not finite(n) then return nil end
    local rows = {}
    for i = 1, n do
        local ok, info = read("C_Reputation.GetFactionDataByIndex", i)
        if not ok or not usable(info) then return nil end
        local parts = {}
        for k, f in ipairs(REP_FIELDS) do
            local okField, v = field(info, f[2])
            if not okField then return nil end
            local j
            if f[1] == "name" then
                j = guideText(v, 100) and jsonString(v)
            elseif type(v) == "boolean" then
                j = tostring(v)
            elseif finite(v) then
                j = jsonNumber(v)
            end
            parts[k] = ('"%s": %s'):format(f[1], j or "null")
        end
        rows[#rows + 1] = "{" .. concat(parts, ", ") .. "}"
    end
    return "[" .. concat(rows, ", ") .. "]"
end

-- Object 22: what Auctionator last saw the player's items sell for (the owner approved this
-- feed, 18 Nov 2026). The items are those of the bags (0 to 5), of the bank while it is open, and
-- of the worn gear (slots 0 to 19), each once, by id. Auctionator is asked through its public
-- interface (Auctionator.API.v1) and told once to say when its prices change. "null" without
-- Auctionator; a failed or secret read of the items: nil.
local ahRegistered = false

-- Adds the item ids of a container to `ids`; false when it cannot be read.
local function itemsOf(bag, ids)
    local okSlots, size = read("C_Container.GetContainerNumSlots", bag)
    if not okSlots or not num(size) then return false end
    for slot = 1, size do
        local okInfo, info = read("C_Container.GetContainerItemInfo", bag, slot)
        if not okInfo then return false end
        if info ~= nil then
            local okId, id = field(info, "itemID")
            if not okId or not num(id) then return false end
            ids[id] = true
        end
    end
    return true
end

local function ahText()
    local api = rawField(rawField(rawget(_G, "Auctionator"), "API"), "v1")
    local price, age = rawField(api, "GetAuctionPriceByItemID"), rawField(api, "GetAuctionAgeByItemID")
    if type(price) ~= "function" or type(age) ~= "function" then return "null" end
    if not ahRegistered then
        ahRegistered = true
        local register = rawField(api, "RegisterForDBUpdate")
        if type(register) == "function" then pcall(register, "HelloLink", function() mark(22) end) end
    end
    local ids = {}
    for bag = 0, 5 do
        if not itemsOf(bag, ids) then return nil end
    end
    if bankOpen then
        local bags = bankBags()
        if not bags then return nil end
        for _, bag in ipairs(bags) do
            if not itemsOf(bag, ids) then return nil end
        end
    end
    for slot = 0, 19 do
        local ok, id = read("GetInventoryItemID", "player", slot)
        if not ok or (id ~= nil and not num(id)) then return nil end
        if id then ids[id] = true end
    end
    local list = {}
    for id in pairs(ids) do list[#list + 1] = id end
    table.sort(list)
    for i, id in ipairs(list) do
        local okP, p = pcall(price, "HelloLink", id)
        local okA, a = pcall(age, "HelloLink", id)
        p, a = okP and plain(p), okA and plain(a)
        list[i] = ("[%s, %s, %s]"):format(jsonNumber(id), jsonAmount(p, true), jsonAmount(a, true))
    end
    return ('{"source": "Auctionator", "prices": [%s]}'):format(concat(list, ", "))
end

-- Object 23: the pet's experience, [current, needed], or "null" without a pet (HasPetUI). The
-- pet's happiness is not sent: this client has no GetPetHappiness (seen 18 Nov 2026).
local function petText()
    local okUI, ui = read("HasPetUI")
    if not okUI then return nil end
    if not ui then return "null" end
    local ok, xp = readAll("GetPetExperience")
    if not ok or not finite(xp[1]) or not finite(xp[2]) or xp[1] < 0 or xp[2] < 0 then return nil end
    return ('{"xp": [%s, %s]}'):format(jsonNumber(xp[1]), jsonNumber(xp[2]))
end

-- Saved, not on the strip (docs/STRIP.md, section 11): which characters were in the game, so a
-- program knows which account folder holds the live character. One entry for each character.
local function recordSeen()
    local name, realm = whoNames()
    if not name then return end
    if type(db.seen) ~= "table" then db.seen = {} end
    db.seen[name .. "-" .. realm] = { name = name, realm = realm, at = num(get("time")), fullName = ns.SavedFullName(name) }
end

local function yesNo(path, ...)
    if type(lookup(path)) ~= "function" then return true, nil end
    return read(path, ...)
end

local function questsText()
    local okCount, count = read("C_QuestLog.GetNumQuestLogEntries")
    if not okCount or not num(count) or type(lookup("C_QuestLog.GetInfo")) ~= "function" then return nil end
    local rows = {}
    for i = 1, count do
        local okInfo, info = read("C_QuestLog.GetInfo", i)
        if not okInfo then return nil end
        if info ~= nil then
            local okId, id = field(info, "questID")
            local okTitle, title = field(info, "title")
            local okHead, header = field(info, "isHeader")
            if not okId or not okTitle or not okHead then return nil end
            if not header and num(id) and type(title) == "string" then
                -- the objectives must be read: a quest whose objectives cannot be read is not
                -- a quest without objectives
                local okObjs, objs = read("C_QuestLog.GetQuestObjectives", id)
                if not okObjs or (objs ~= nil and not usable(objs)) then return nil end
                local parts, done, moved = {}, 0, false
                for n = 1, objs and #objs or 0 do
                    local o = objs[n]
                    local okText, text = field(o, "text")
                    local okFin, finished = field(o, "finished")
                    local okHave, have = field(o, "numFulfilled")
                    local okNeed, need = field(o, "numRequired")
                    if not (okText and okFin and okHave and okNeed) or (text ~= nil and type(text) ~= "string") then return nil end
                    if not (num(have) and num(need) and need > 0) then have, need = nil, nil end
                    if finished then done = done + 1 end
                    if finished or (have and have > 0) then moved = true end
                    parts[#parts + 1] = ('{"text": %s, "have": %s, "need": %s, "done": %s}'):format(
                        jsonString(text or ""), have and jsonNumber(have) or "null",
                        need and jsonNumber(need) or "null", finished and "true" or "false")
                end
                local okFailed, failed = yesNo("C_QuestLog.IsFailed", id)
                local okComplete, complete = yesNo("C_QuestLog.IsComplete", id)
                if not okFailed or not okComplete then return nil end   -- a secret flag is not "no"
                local state = failed and "failed" or (complete or (#parts > 0 and done == #parts)) and "ready"
                    or #parts == 0 and "unknown" or moved and "in_progress" or "accepted"
                rows[#rows + 1] = { id, ('{"id": %s, "title": %s, "state": "%s", "objectives": [%s]}'):format(
                    jsonNumber(id), jsonString(title), state, concat(parts, ", ")) }
            end
        end
    end
    table.sort(rows, function(a, b) return a[1] < b[1] end)
    for i, r in ipairs(rows) do rows[i] = r[2] end
    return "[" .. concat(rows, ", ") .. "]"
end

-- The skill lines, read from the client now.
local function skillsText()
    local okCount, count = read("C_SkillInfo.GetNumSkillLines")
    if not okCount or not num(count) then return nil end
    local rows = {}
    for i = 1, count do
        local okInfo, info = read("C_SkillInfo.GetSkillLineInfo", i)
        if not okInfo then return nil end
        if info ~= nil then
            local okName, name = field(info, "name")
            local okHead, header = field(info, "isHeader")
            local okRank, rank = field(info, "rank")
            if okRank and rank == nil then okRank, rank = field(info, "skillRank") end
            local okMax, top = field(info, "maxRank")
            if okMax and top == nil then okMax, top = field(info, "skillMaxRank") end
            local okId, id = field(info, "skillID")
            if not (okName and okHead and okRank and okMax and okId) then return nil end
            if not header then
                -- a line needs all four: a missing rank, maximum or id is not a zero
                if type(name) ~= "string" or not num(rank) or not num(top) or not num(id) then return nil end
                rows[#rows + 1] = { id, name, ('{"id": %s, "name": %s, "rank": %s, "max": %s}'):format(
                    jsonNumber(id), jsonString(name), jsonNumber(rank), jsonNumber(top)) }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        return a[2] < b[2]
    end)
    for i, r in ipairs(rows) do rows[i] = r[3] end
    return "[" .. concat(rows, ", ") .. "]"
end

----------------------------------------------------------------------
-- The row on screen (section 3)
----------------------------------------------------------------------
local row, cells, shownColour = nil, {}, {}
local unit, capacity = 1, 0   -- UI units in a physical pixel; frame squares that fit
local curves                  -- three step colour curves for a level square triple
local LEVEL_SOURCES = { { "player", "UnitHealthPercent", true }, { "player", "UnitPowerPercent", nil, false },
    { "target", "UnitHealthPercent", true }, { "pet", "UnitHealthPercent", true } }

local function digitColour(d)
    return d >= 4 and 1 or 0, d % 4 >= 2 and 1 or 0, d % 2
end

local function paletteColour(i)
    return floor(i / 16) / 3, floor(i / 4) % 4 / 3, i % 4 / 3
end

-- The palette's 64 colours and the names `paint` knows them by, made once (#175).
local PALETTE_KEY, PALETTE_R, PALETTE_G, PALETTE_B = {}, {}, {}, {}
for i = 0, 63 do
    PALETTE_KEY[i] = "p" .. i
    PALETTE_R[i], PALETTE_G[i], PALETTE_B[i] = paletteColour(i)
end

local function cell(i)
    local t = cells[i]
    if not t then
        t = row:CreateTexture(nil, "OVERLAY")
        cells[i] = t
        local side = ns.Strip2.side(db) * unit
        t:SetSize(side, side)
        t:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * side, 0)
    end
    return t
end

-- Colours square `i` (from 1) unless it already has that colour.
local function paint(i, key, r, g, b)
    if shownColour[i] == key then return end
    shownColour[i] = key
    local t = cell(i)
    t:SetColorTexture(r, g, b, 1)
    t:Show()
end

local function paintDigit(i, d)
    paint(i, d, digitColour(d))
end

local function makeCurves()
    if type(lookup("C_CurveUtil.CreateColorCurve")) ~= "function" or type(_G.CreateColor) ~= "function"
        or lookup("Enum.LuaCurveType.Step") == nil or type(_G.UnitHealthPercent) ~= "function" then
        return nil
    end
    local set = {}
    for part = 1, 3 do
        local curve = _G.C_CurveUtil.CreateColorCurve()
        curve:SetType(_G.Enum.LuaCurveType.Step)
        local last
        for level = 0, 127 do
            local d = part == 1 and floor(level / 16) or part == 2 and floor(level / 2) % 8 or (level % 2 == 1 and 6 or 2)
            if d ~= last then
                curve:AddPoint(level / 128, _G.CreateColor(d >= 4 and 1 or 0, d % 4 >= 2 and 1 or 0, d % 2, 1))
                last = d
            end
        end
        set[part] = curve
    end
    return set
end

-- The level squares (section 5): the client colours them. The colour goes from the client's
-- function straight to the texture; nothing here looks at it.
local function colourFromClient(t, fn, who, a, b, curve)
    if b == nil then t:SetColorTexture(fn(who, a, curve):GetRGBA())
    else t:SetColorTexture(fn(who, a, b, curve):GetRGBA()) end
end

local levelUp = {}   -- the level squares that are shown: a shown square is not shown again (#175)
local function paintLevels()
    local mainTurn, partyTurn = true, false
    if db.format >= 2 then
        mainTurn, partyTurn = ns.Strip2.levelTurn()
        if not mainTurn and not partyTurn then return end
    end
    for v = 1, mainTurn and #LEVEL_SOURCES or 0 do
        local source = LEVEL_SOURCES[v]
        local who, fn, a, b = source[1], _G[source[2]], source[3], source[4]
        local live = curves and type(fn) == "function" and get("UnitExists", who)
        for part = 1, 3 do
            local i = LEVELS_AT + (v - 1) * 3 + part
            local t = cell(i)
            if not (live and pcall(colourFromClient, t, fn, who, a, b, curves[part])) then t:SetColorTexture(0, 0, 0, 1) end
            shownColour[i] = nil
            if not levelUp[i] then
                levelUp[i] = true
                t:Show()
            end
        end
    end
    if db.format < 2 then return end
    local base, fn = (depth == 4 and PALETTE_AT + 64 or PALETTE_AT) + ns.Strip2.shift(db) + 2, _G.UnitHealthPercent
    for v = 1, #ns.Strip2.MORE do
        local who = ns.Strip2.MORE[v]
        if v == 1 and not mainTurn or v > 1 and not partyTurn then who = nil end
        local live = who and curves and type(fn) == "function" and get("UnitExists", who)
        for part = 1, who and 3 or 0 do
            local i = base + (v - 1) * 3 + part
            local t = cell(i)
            if not (live and pcall(colourFromClient, t, fn, who, true, nil, curves[part])) then t:SetColorTexture(0, 0, 0, 1) end
            shownColour[i] = nil
            if not levelUp[i] then
                levelUp[i] = true
                t:Show()
            end
        end
    end
end

local function frameStart()
    local base = (depth == 4 and PALETTE_AT + 64 or PALETTE_AT) + ns.Strip2.shift(db)
    if db.format >= 2 then return base + 2 + 3 * #ns.Strip2.MORE end   -- `more` and its triples
    return base
end

-- Sizes in physical pixels (measured exact on 12 Nov 2026), and what fits the game's width.
local function layout()
    local width, height = _G.GetPhysicalScreenSize()
    unit = 768 / height / UIParent:GetEffectiveScale()
    local side = ns.Strip2.side(db) * unit
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", UIParent, "TOPLEFT", db.x * unit, -db.y * unit)
    row:SetSize(1, 1)
    for i, t in pairs(cells) do
        t:SetSize(side, side)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * side, 0)
    end
    capacity = max(0, floor((width - db.x) / ns.Strip2.side(db)) - frameStart())
    local bits = depth == 4 and 6 or 3
    if db.format >= 2 then
        chunkLen = max(0, min(ns.Strip2.CHUNK, floor(capacity * bits / 8) - (db.format == 3 and ns.Strip2.HEAD3 or ns.Strip2.HEAD)))
        ns.Strip2.rechunked(objects, chunkLen)
    else
        chunkLen = max(0, min(MAX_CHUNK, floor(capacity * bits / 8) - (7 + 58 + 6 + 2)))
    end
    sending = nil
end

-- Everything on the row but the level squares and the frame: finder, depth, session, palette.
local function paintFixed()
    for i = 1, #FINDER do paintDigit(i, FINDER[i]) end
    -- format 2 has the digits 6 and 3 in the depth square, format 3 the digits 5 and 7 and then
    -- the layout square (one lane: 0); both have `more` after the palette
    local shift = ns.Strip2.shift(db)
    paintDigit(DEPTH_AT + 1, db.format == 3 and (depth == 4 and 5 or 7) or db.format == 2 and (depth == 4 and 6 or 3) or depth)
    if shift == 1 then paintDigit(DEPTH_AT + 2, 0) end
    if db.format >= 2 then
        local base, more = (depth == 4 and PALETTE_AT + 64 or PALETTE_AT) + shift, #ns.Strip2.MORE
        paintDigit(base + 1, floor(more / 8))
        paintDigit(base + 2, more % 8)
    end
    local digits = squaresOf({ 0, floor(session / 256), session % 256 }, 3)
    for k = 1, 6 do paintDigit(SESSION_AT + shift + k, digits[k + 2]) end
    if depth == 4 then
        for i = 0, 63 do paint(PALETTE_AT + shift + 1 + i, PALETTE_KEY[i], PALETTE_R[i], PALETTE_G[i], PALETTE_B[i]) end
    end
end

-- `lastBody` is true while a frame has been built since the row was started afresh. The frame
-- is built in `body`, a table kept between frames (#175); `shown` and `shownLen` are the frame
-- on the row, with its seq and its check sum, to tell whether anything changed.
local lastBody, lastSquares = nil, 0
local body, shown, shownLen, squares = {}, {}, 0, {}

-- Whether `body`'s first `n` bytes are the frame on the row, but for the seq (bytes 5 and 6) and,
-- in format 3, the fixed check (written by `show` once the seq is set).
local function unchanged(n)
    if not lastBody or n ~= shownLen then return false end
    local fx = db.format == 3 and ns.Strip2.fx or -9
    for i = 1, n do
        if body[i] ~= shown[i] and i ~= 5 and i ~= 6 and i ~= fx + 1 and i ~= fx + 2 then return false end
    end
    return true
end

-- Builds the frame for the state and the chunk now on the row, and recolours what changed.
local function drawFrame(now)
    if sending and not sending.till then   -- the chunk is on the row from now
        sending.till, sending.frames = now + db.dwell / 100, 0
        sending.need = db.format == 3 and ns.Strip2.slow and 2 or 1   -- frames it stays (the back-off)
    end
    if sending then sending.frames = (sending.frames or 0) + 1 end
    if db.format == 3 then
        local S2 = ns.Strip2
        if sending and objects[sending.id] then objects[sending.id].upAt = now end   -- for a stall
        local state = sample()
        S2.noteRing(state, now)
        local n = S2.frame3(body, session, db.dwell, (seq + 1) % 65536, state, sending, objects, S2.IDS,
            S2.ringNow(now), floor(capacity * (depth == 4 and 6 or 3) / 8))
        if unchanged(n) then return end
        seq = (seq + 1) % 65536
        return S2.show(n)
    end
    if db.format == 2 then
        local S2, state = ns.Strip2, sample()
        local isKey = S2.keyDue(state, now)
        local n = S2.frame(body, session, db.dwell, (seq + 1) % 65536, isKey, state, sending)
        if unchanged(n) then return end
        seq = (seq + 1) % 65536
        if isKey then S2.commit(state, seq % 256, now) end
        return ns.Strip2.show(n)
    end
    body[1] = VERSION
    local n = put(body, 1, session, 2)
    body[n + 1] = db.dwell
    n = put(body, n + 1, 0, 2)                        -- seq, set below
    local fastEnd = packFast(body, n + 1, sample())
    body[n + 1] = fastEnd - (n + 1)
    n = fastEnd
    if sending then
        local part = sending.chunks[sending.index]
        body[n + 1] = sending.id
        n = put(body, n + 1, sending.version, 2)
        body[n + 1], body[n + 2], body[n + 3] = sending.index - 1, #sending.chunks, #part
        n = n + 3
        for i = 1, #part do body[n + i] = part[i] end
        n = n + #part
    else
        for i = 1, 6 do body[n + i] = 0 end
        n = n + 6
    end
    if unchanged(n) then return end                   -- nothing changed: the same seq stays up
    seq = (seq + 1) % 65536
    return ns.Strip2.show(n)
end

-- Puts the frame built in `body` (n bytes, its seq set here) on the row: the check, the squares,
-- the colours that changed. Both formats end here. A field of ns: Strip.lua's main chunk has no
-- room for another local.
ns.Strip2.show = function(n)
    body[5], body[6] = floor(seq / 256), seq % 256
    local last = n + 2
    if db.format == 3 then                            -- format 3: the fixed check, inside the frame
        local fx = ns.Strip2.fx
        body[fx + 1], body[fx + 2] = check(body, 1, fx)
        last = n
        -- At 6 bits, three bytes are four squares. A frame of the same length is drawn three bytes
        -- at a time, only where they changed: most of format 3's frame stays (docs/specs/232.md,
        -- section 4 B), and the rest of the row is not looked at.
        local count, first = ceil(n * 4 / 3), frameStart()
        if depth == 4 and lastBody and ns.Strip2.drawn and count <= capacity then
            local old, up, on = shown, shownColour, shownLen
            for i = 1, n, 3 do
                local a, b, c = body[i], i + 1 <= n and body[i + 1] or 0, i + 2 <= n and body[i + 2] or 0
                if i + 2 > on or a ~= old[i] or b ~= old[i + 1] or c ~= old[i + 2] then
                    local bLow, cLow = b % 16, c % 64
                    local s = (i - 1) / 3 * 4
                    for k = 1, min(4, count - s) do
                        local v = k == 1 and (a - a % 4) / 4 or k == 2 and a % 4 * 16 + (b - bLow) / 16
                            or k == 3 and bLow * 4 + (c - cLow) / 64 or cLow
                        local key = PALETTE_KEY[v]
                        if up[first + s + k] ~= key then paint(first + s + k, key, PALETTE_R[v], PALETTE_G[v], PALETTE_B[v]) end
                    end
                end
            end
            for i = count + 1, lastSquares do paint(first + i, 0, 0, 0, 0) end  -- black after the frame's end
            body, shown, shownLen, lastBody, lastSquares = shown, body, n, true, count
            return ns.Strip2.noteFrame(db, seq, session)
        end
    else
        body[n + 1], body[n + 2] = check(body, 1, n)
    end
    body, shown, shownLen, lastBody = shown, body, n, true   -- the other table is the next frame's
    local count = squaresInto(squares, shown, last, depth == 4 and 6 or 3)
    local first = frameStart()
    -- the game is too narrow for this frame: it is not drawn, so the row still shows an older one
    -- (format 3 draws the next frame whole, not by what changed from this one)
    ns.Strip2.drawn = count <= capacity
    if count > capacity then return end
    if depth == 4 then
        local up = shownColour
        for i = 1, count do
            local s = squares[i]
            local key = PALETTE_KEY[s]
            if up[first + i] ~= key then paint(first + i, key, PALETTE_R[s], PALETTE_G[s], PALETTE_B[s]) end
        end
    else
        for i = 1, count do paintDigit(first + i, squares[i]) end
    end
    for i = count + 1, lastSquares do paint(first + i, 0, 0, 0, 0) end  -- black after the frame's end
    lastSquares = count
    if db.format >= 2 then ns.Strip2.noteFrame(db, seq, session) end   -- only a frame that went up
end

-- Starts the row afresh: after a change of size, place, depth or UI scale.
local function repaint()
    for _, t in pairs(cells) do t:Hide() end
    shownColour, levelUp, lastBody, lastSquares = {}, {}, nil, 0
    ns.Strip2.reset()
    ns.Strip2.resetSending()
    ns.Strip2.resetLevels()
    layout()
    paintFixed()
end

----------------------------------------------------------------------
-- The fall-back (section 3)
----------------------------------------------------------------------
local function setDepth(to, why)
    if depth == to then return end
    depth = to
    repaint()
    if why then ns.say(why) end
end

-- HelloForever's assistant is on: its plain table, read with rawget (docs/specs/115.md, section 6).
local function assistOn()
    local a = rawget(_G, "HelloForeverAssist")
    return type(a) == "table" and rawget(a, "on") == true
end

local function inCombat()
    local f = _G.InCombatLockdown
    return type(f) == "function" and f() and true or false
end

local owed       -- a look that fell due in a fight: false, or true for a question's look
local lastLookAt -- the clock of the last look: one look a moment at most

-- A look loads the next slot. It serves the strip's fall-back and the assistant at once
-- (docs/specs/115.md, section 6, "When HelloLink looks"). `question`: a look after a question,
-- the only kind made when 20 slots or fewer are left. `moment`: a rest or a level up, which
-- looks only for the assistant. Never in a fight: it is made after it.
local function look(question, moment)
    if not db.on then return end -- the strip off: no look for either
    local forStrip = not moment and looking and depth == 4 and db.depth == "auto"
    local forAssist = assistOn()
    if not forStrip and not forAssist then return end
    if inCombat() then
        owed = owed == true or question == true -- one look after the fight; a question's if any was
        return
    end
    local left = ns.AssistLeft and ns.AssistLeft()
    if not question and left and left <= 20 then return end
    lastLookAt = clock()
    local inbox = ns.loadNextSlot and ns.loadNextSlot()
    if inbox == nil then
        looking = false                                -- the session's slots are used up
        if ns.AssistNoSlot then ns.AssistNoSlot() end
        return
    end
    local ask = type(inbox) == "table" and inbox.strip
    if forStrip and type(ask) == "table" and ask.session == session and ask.depth == 2 then
        looking = false
        setDepth(2, "the strip falls back to 3 bits a square for this session: the reader could not read 6.")
    end
    if db.on and ns.AssistTake then ns.AssistTake(inbox, session, _G.time()) end
end

-- A question of HelloForever's (its table's `ask.n`): looks 3, 8 and 20 s after it, until a
-- set of this session answers it (`re`).
local QUESTION_LOOKS = { 3, 8, 20 }
local lastAsk, askAt, askLooks
local function followQuestion(now)
    local a = rawget(_G, "HelloForeverAssist")
    local ask = type(a) == "table" and rawget(a, "ask")
    local n = type(ask) == "table" and rawget(ask, "n")
    if type(n) == "number" and n ~= lastAsk then
        lastAsk, askAt, askLooks = n, now, 1
    end
    if not askLooks then return end
    local st = ns.AssistState
    if st and st.re == lastAsk then askLooks = nil return end
    if lastLookAt == now then return end -- a look was made this moment: the next one waits
    local due = QUESTION_LOOKS[askLooks]
    if not due then askLooks = nil return end
    if now - askAt >= due then
        askLooks = askLooks + 1
        look(true)
    end
end

----------------------------------------------------------------------
-- Running
----------------------------------------------------------------------
local sinceFast, sinceLevels, sinceSlow = 0, 0, 0

local sinceGuide, sinceRoute = 0, 0
local function onUpdate(_, elapsed)
    if not db or not db.on then return end
    local now = clock()
    elapsed = elapsed or 0
    sinceFast, sinceLevels, sinceSlow = sinceFast + elapsed, sinceLevels + elapsed, sinceSlow + elapsed
    if sinceLevels >= 0.05 or lastBody == nil then
        sinceLevels = 0
        paintLevels()
    end
    if sinceSlow >= 30 then  -- a safety net for an event this client does not send
        sinceSlow = 0
        for id = 2, IDS do
            if id ~= 19 then mark(id) end   -- the completed quests: only at login and a turn-in
        end
    end
    sinceGuide = sinceGuide + elapsed
    if db.format >= 2 then ns.Strip2.marks(elapsed, mark) end   -- objects 24 to 27
    if sinceGuide >= 1 then  -- the guide addon's arrow is in its memory: no client event tells of it
        sinceGuide = 0
        mark(7)
        mark(12)                 -- and HelloForever's baseline table: no client event tells of it either
        mark(13)                 -- and the assistant's two tables
        mark(18)                 -- and the hearthstone: no event of this client is known for a bind
    end
    if owed ~= nil and not inCombat() then -- before the question's own times: one look, not two
        local q = owed
        owed = nil
        look(q)
    end
    if sinceGuide == 0 then followQuestion(now) end -- once a second, with the reads above
    sinceRoute = sinceRoute + elapsed
    if sinceRoute >= 2 then  -- the route is asked of the route addon: no client event tells of it
        sinceRoute = 0
        mark(9)
        mark(11)                 -- and the guide's list is in the guide addon's memory
    end
    local S2 = ns.Strip2
    S2.three = db.format == 3
    if S2.three then
        -- format 3: one clock (docs/specs/232.md, section 6); a stop of the game sends again
        if elapsed > 0.25 then S2.stall(objects, S2.IDS, now, elapsed) end
        -- the back-off (section 4 B): the game's frame rate, read once a second
        if now >= S2.rateAt then
            S2.rateAt = now + 1
            local fps = num(get("GetFramerate"))
            S2.slow = fps ~= nil and fps < S2.SLOW_FPS
        end
        if now >= S2.nextFrame or lastBody == nil then
            S2.nextFrame = now + db.dwell / 100
            advance(now)
            drawFrame(now)
        end
    elseif advance(now) or sinceFast >= FAST_EVERY or lastBody == nil then
        sinceFast = 0
        drawFrame(now)
    end
    local due = LOOKS[lookIndex] or (LOOKS[#LOOKS] + 600 * (lookIndex - #LOOKS))
    if now - loadedAt >= due then
        lookIndex = lookIndex + 1
        look()
    end
end

----------------------------------------------------------------------
-- Saved, not on the strip: the character's own appearance choices (#168; docs/STRIP.md,
-- section 11). The client gives them only at a barber, so they are taken when the barber's
-- window opens and when a new appearance is applied, and kept in HelloLinkDB.looks for a
-- program that reads the saved file. Every field is checked: an API can differ on this client.
----------------------------------------------------------------------
local function id(v)
    return num(plain(v))
end

local function tableOf(v)
    v = plain(v)
    return type(v) == "table" and v or nil
end

-- The client's answer (a list of categories) as `models, choices`: models[category id] is the
-- category's model id or false, choices[option id] the id of the option's current choice. An
-- option with no current choice is left out. nil when the answer holds no choice at all.
function ns.LooksFrom(categories)
    local models, choices, any = {}, {}, false
    for _, category in pairs(tableOf(categories) or {}) do
        category = tableOf(category)
        local categoryID = category and id(category.id)
        if categoryID then
            models[categoryID] = id(category.chrModelID) or false
            for _, option in pairs(tableOf(category.options) or {}) do
                option = tableOf(option)
                local optionID, at = option and id(option.id), option and id(option.currentChoiceIndex)
                local list = optionID and at and tableOf(option.choices)
                local choice = list and tableOf(list[at])
                local choiceID = choice and id(choice.id)
                if choiceID then choices[optionID], any = choiceID, true end
            end
        end
    end
    if not any then return nil end
    return models, choices
end

-- Nothing from the client (away from a barber, or no character set up) keeps the older record.
local function recordLooks()
    local models, choices = ns.LooksFrom(get("C_BarberShop.GetAvailableCustomizations"))
    -- the key of HelloForever's saved data, and the name and realm of object 10
    local name, realm = get("UnitName", "player"), get("GetRealmName")
    if not models or type(name) ~= "string" or name == "" or type(realm) ~= "string" or realm == "" then return end
    local okRace, race = readAll("UnitRace", "player")
    race = okRace and race[2]
    if type(db.looks) ~= "table" then db.looks = {} end
    db.looks[name .. "-" .. realm] = {
        at = num(get("time")), race = type(race) == "string" and race or nil, sex = num(get("UnitSex", "player")),
        models = models, choices = choices,
    }
end

local EVENTS = {
    PLAYER_TARGET_CHANGED = function() mark(2) end,
    ZONE_CHANGED = function() mark(3) end,
    ZONE_CHANGED_NEW_AREA = function() mark(3) mark(20) end,
    ZONE_CHANGED_INDOORS = function() mark(3) end,
    BAG_UPDATE_DELAYED = function() mark(4) mark(15) mark(16) mark(22) end,
    BAG_UPDATE = function() mark(4) mark(15) mark(16) mark(22) end,
    PLAYER_EQUIPMENT_CHANGED = function() mark(14) mark(22) end,
    UPDATE_INVENTORY_DURABILITY = function() mark(14) end,
    UNIT_INVENTORY_CHANGED = function() mark(14) end,   -- an enchant put on worn gear; any unit: a cheap read
    BANKFRAME_OPENED = function() bankOpen = true mark(16) mark(22) end,
    BANKFRAME_CLOSED = function() bankOpen = false mark(16) mark(22) end,
    TRAINER_SHOW = function() trainerOpen = true mark(17) end,
    TRAINER_UPDATE = function() mark(17) end,
    TRAINER_SERVICE_INFO_NAME_UPDATE = function() mark(17) end,   -- a name the client had not yet
    TRAINER_CLOSED = function() trainerOpen = false mark(17) end,
    PLAYERBANKSLOTS_CHANGED = function() mark(16) mark(22) end,
    BANK_TABS_CHANGED = function() mark(16) mark(22) end,
    QUEST_LOG_UPDATE = function() mark(5) end,
    QUEST_TURNED_IN = function() mark(19) end,
    PLAYER_DEAD = function() mark(20) ns.Strip2.happen(nil, 7) end,
    PLAYER_ALIVE = function() mark(20) end,
    PLAYER_UNGHOST = function() mark(20) end,
    UPDATE_FACTION = function() mark(21) end,
    UNIT_PET = function() mark(23) end,
    UNIT_PET_EXPERIENCE = function() mark(23) end,
    PET_UI_UPDATE = function() mark(23) end,
    SKILL_LINES_CHANGED = function() mark(6) end,
    CHAT_MSG_SKILL = function() mark(6) end,
    UPDATE_EXHAUSTION = function() mark(8) end,
    PLAYER_XP_UPDATE = function() mark(8) end,
    PLAYER_UPDATE_RESTING = function()
        mark(8)
        if get("IsResting") == true then look(false, true) end   -- a moment: the character starts resting
    end,
    PLAYER_LEVEL_UP = function(level)
        level = num(plain(level))
        if level then   -- into the ring at the next frame, after its XP; one still waiting goes in first
            if ns.Strip2.levelUp then ns.Strip2.happen(nil, 6, ns.Strip2.levelUp) end
            ns.Strip2.levelUp = level
        end
        look(false, true)
    end,
    PLAYER_ENTERING_WORLD = function(isLogin, isReload)   -- after every loading screen: an instance too
        mark(3) mark(10) mark(20) mark(21)
        -- the completed quests and the login's record only at a login or a reload, not at each instance
        if plain(isLogin) == true or plain(isReload) == true then
            mark(19)
            recordSeen()
        end
    end,
    BARBER_SHOP_OPEN = function() recordLooks() end,
    BARBER_SHOP_APPEARANCE_APPLIED = function() recordLooks() end,
    LOOT_OPENED = function() lootOpen = true end,
    LOOT_CLOSED = function() lootOpen = false end,
    UI_SCALE_CHANGED = function() if row then repaint() end end,
    DISPLAY_SIZE_CHANGED = function() if row then repaint() end end,
    UI_ERROR_MESSAGE = function(kind)
        -- the count goes on; a number that cannot be read leaves the group unknown until the next error
        uiError = { error = num(plain(kind)), counter = (uiError.counter + 1) % 256 }
        if uiError.error then ns.Strip2.happen(nil, 2, uiError.error) end
    end,
    CHAT_MSG_LOOT = function(text, ...)
        -- Whose loot: by GUID (argument 12 of the event), never by name. The name in the
        -- message can have a family name that UnitName does not have (seen 13 Nov 2026).
        local who, me = plain((select(11, ...))), get("UnitGUID", "player")
        text = plain(text)
        if type(text) ~= "string" or type(who) ~= "string" or who ~= me then return end
        -- The full name (0.8.1): argument 2, when it is the first name, a space and a family name,
        -- at most 60 bytes. Kept under the GUID (argument 12, the player's: checked above).
        local full, name, realm = guideText(plain((...)), 60), whoNames()
        if full and name and full:match("^(%S+)%s+%S") == name then
            if type(db.fullNames) ~= "table" then db.fullNames = {} end
            local saved, key = db.fullNames[who], name .. "-" .. realm
            if type(saved) ~= "table" or saved.fullName ~= full then
                db.fullNames[who] = { fullName = full, source = "loot", at = num(get("time")) }
                if type(db.seen) == "table" and type(db.seen[key]) == "table" then db.seen[key].fullName = full end
                mark(10)
            end
        end
        local item = tonumber(text:match("|Hitem:(%d+)"))
        if not item then return end
        loot = { counter = (loot.counter + 1) % 256, item = item, quantity = tonumber(text:match("|h|rx(%d+)")) or 1 }
        ns.Strip2.happen(nil, 1, item, loot.quantity)
        mark(4)
    end,
}

local function start()
    if type(_G.HelloLinkDB) ~= "table" then _G.HelloLinkDB = {} end
    db = _G.HelloLinkDB
    for k, v in pairs({ on = true, x = 0, y = 0, size = 2, depth = "auto", dwell = 10, format = 3 }) do
        if db[k] == nil then db[k] = v end
    end
    -- HelloLink 1.1.0 releases format 3 (the owner, 21 Nov 2026; 1.0.0 released format 2): a
    -- saved data of an earlier version is moved to it once; after that `/hlink strip format 2`
    -- or `1` is the player's choice.
    if db.formatRelease ~= 3 then db.format, db.formatRelease = 3, 3 end
    if db.format ~= 2 and db.format ~= 3 then db.format = 1 end
    if db.size2 == nil then db.size2 = 1 end
    -- what Strip2.lua needs of this file (docs/specs/213.md)
    ns.Strip2.reads = { read = read, get = get, num = num, flag = flag, nameHash = nameHash, CLASSIFICATION = CLASSIFICATION,
        plain = plain, readAll = readAll, readInto = readInto, lookup = lookup, jsonString = jsonString, creatureId = creatureId }
    ns.Strip2.lootItem = function() return loot.item ~= 0 and loot.item or nil end
    ns.Strip2.reads.secret = function(v)
        local f = _G.issecretvalue
        return type(f) == "function" and f(v) and true or false
    end
    ns.Strip2.chunksOf = function(o)
        if o.chunks == nil or o.chunksOf ~= o.obj or o.chunksAt ~= chunkLen then
            o.chunks, o.chunksOf, o.chunksAt = chunksOf(o.obj) or false, o.obj, chunkLen
        end
        return o.chunks or nil
    end
    -- the session number: a counter kept across UI loads (section 4)
    db.session = (num(db.session) or math.random(1, 65535)) % 65535 + 1
    session, depth, loadedAt = db.session, db.depth == 2 and 2 or 4, clock()
    looking = db.depth == "auto"
    if ns.AssistStrip then ns.AssistStrip(db.on) end
    curves = makeCurves()
    objects = {
        [1] = { text = function(o) return o.value end, every = 1 },   -- the question; nothing until one is typed
        [2] = { text = targetText, bin = function(b) return ns.Strip2.targetBin(b) end, every = 1, dirty = true }, [3] = { text = placeText, bin = function(b) return ns.Strip2.placeBin(b) end, every = 1, dirty = true },
        [4] = { text = bagsText, bin = function(b, k) return ns.Strip2.bagsBin(b, k) end, every = 1, dirty = true }, [5] = { text = questsText, every = 2, dirty = true },
        [6] = { text = skillsText, every = 1, dirty = true },
        [7] = { text = waypointText, every = 1, dirty = true }, [8] = { text = restText, bin = function(b) return ns.Strip2.restBin(b) end, every = 1, dirty = true },
        [9] = { text = routeText, bin = function(b) return ns.Strip2.routeBin(b) end, every = 2, dirty = true },   -- binary in format 3 (#232)
        [10] = { text = whoText, every = 1, dirty = true },
        [11] = { text = stepsText, every = 2, dirty = true },
        [12] = { text = baselineText, bin = function(b) return ns.Strip2.baselineBin(b) end, every = 1, dirty = true },
        [13] = { text = assistText, bin = function(b) return ns.Strip2.assistBin(b) end, every = 1, dirty = true },
        [14] = { text = gearText, bin = function(b, k) return ns.Strip2.gearBin(b, k) end, every = 2, dirty = true },
        [15] = { text = bagSlotsText, every = 2, dirty = true },
        [16] = { text = bankText, every = 2, dirty = true },
        [17] = { text = trainerText, every = 2, dirty = true },
        [18] = { text = hearthText, every = 1, dirty = true },
        [19] = { text = doneText, every = 2 },   -- not read until PLAYER_ENTERING_WORLD marks it
        [20] = { text = corpseText, every = 1, dirty = true },
        [21] = { text = repText, every = 2, gap = 2, dirty = true },
        [22] = { text = ahText, every = 2, gap = 2, dirty = true },
        [23] = { text = petText, every = 1, dirty = true },
        -- format 2 only (docs/specs/213.md, section 7): format 1's carousel stops at 23
        [24] = { text = function() return ns.Strip2.unitsText() end, bin = function(b) return ns.Strip2.unitsBin(b) end,
            every = 0.5, dirty = true },
        [25] = { text = function() return ns.Strip2.namesText() end, every = 5, dirty = true },
        [26] = { text = function() return ns.Strip2.aurasText() end, bin = function(b) return ns.Strip2.aurasBin(b) end,
            every = 1, dirty = true },
        [27] = { text = function() return ns.Strip2.cooldownsText() end, bin = function(b) return ns.Strip2.cooldownsBin(b) end,
            every = 1, dirty = true },
    }
    row = CreateFrame("Frame", nil, UIParent)
    row:SetFrameStrata("TOOLTIP")
    row:SetFrameLevel(9000)
    repaint()
    row:SetScript("OnUpdate", onUpdate)
    if not db.on then row:Hide() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= "HelloLink" or db then return end
        start()
        for name in pairs(EVENTS) do pcall(events.RegisterEvent, events, name) end
        return
    end
    local handler = EVENTS[event]
    if handler and db then handler(...) end
end)

----------------------------------------------------------------------
-- What HelloLink.lua calls
----------------------------------------------------------------------
-- /hlink send <text>: the question, object 1, sent in two rounds.
function ns.StripQuestion(text)
    if not db or not db.on then return false end
    local o = objects[1]        -- kept for the whole session: its version only ever counts up
    o.value, o.want, o.dirty = text, 2, true
    o.obj = nil                 -- the same text typed again is a new question
    return true
end

-- Sets one of the strip's settings as /hlink strip does, without a word in chat; false when the
-- words are none of its settings (the settings window calls it too).
function ns.StripSet(word, a, b)
    if not db then return false end
    if word == "on" or word == "off" then
        db.on = word == "on"
        if db.on then row:Show(); repaint() else row:Hide() end
        if ns.AssistStrip then ns.AssistStrip(db.on) end
    elseif word == "at" and tonumber(a) and tonumber(b) then
        db.x, db.y = max(0, floor(tonumber(a))), max(0, floor(tonumber(b)))
        repaint()
    elseif word == "size" and (a == "2" or a == "3" or a == "4" or (a == "1" and db.format >= 2)) then
        -- each format keeps its own size: format 2 from 1 pixel, format 1 from 2
        if db.format >= 2 then db.size2 = tonumber(a) else db.size = tonumber(a) end
        repaint()
    elseif word == "format" and (a == "1" or a == "2" or a == "3") then
        db.format = tonumber(a)
        -- an object with a binary form is built anew in the other format's encoding (#248)
        for _, o in pairs(objects) do
            if o.bin then o.obj, o.chunks, o.from, o.key, o.dirty = nil, nil, nil, nil, true end
        end
        repaint()
    elseif word == "depth" and (a == "auto" or a == "2" or a == "4") then
        db.depth = a == "auto" and "auto" or tonumber(a)
        looking = a == "auto"
        setDepth(a == "2" and 2 or 4)
    elseif word == "dwell" and tonumber(a) and tonumber(a) >= 5 and tonumber(a) <= 100 then
        db.dwell = floor(tonumber(a))
    else
        return false
    end
    return true
end

-- The strip's settings now, for the settings window; nil before the strip is loaded.
function ns.StripState()
    if not db then return nil end
    return { on = db.on, x = db.x, y = db.y, size = ns.Strip2.side(db), depth = db.depth, dwell = db.dwell, depthNow = depth, format = db.format }
end

function ns.StripCommand(rest)
    if not db then return ns.say("the strip is not loaded yet.") end
    local word, a, b = rest:match("^(%S*)%s*(%S*)%s*(%S*)")
    if not ns.StripSet(word, a, b) then
        return ns.say("use /hlink strip on | off | at <x> <y> | size <1|2|3|4> | depth <auto|2|4> | dwell <5-100> | format <1|2|3> (size 1 needs format 2 or 3)")
    end
    ns.say(("strip %s at (%d, %d), format %d, %d pixels a square, depth %s (now %d), a chunk stays %.2f s, session %d."):format(
        db.on and "on" or "off", db.x, db.y, db.format, ns.Strip2.side(db), tostring(db.depth), depth, db.dwell / 100, session))
end
