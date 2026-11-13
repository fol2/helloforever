-- HelloLink / Strip.lua
-- The live-state strip, format 1 (docs/specs/29.md): one row of squares at the top edge of the
-- game that a program outside reads from the screen. Section numbers are those of the spec;
-- tools/strip1.py is the same format in Python and reads what this draws.
--
-- This file only shows what the client lets an addon read or what the client colours itself.
-- It presses no key, casts nothing and moves nothing.
local _, ns = ...

local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max
local char, concat = string.char, table.concat
local unpack = unpack or table.unpack -- luacheck: ignore 143

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

local function lookup(path)
    local v = _G
    for part in path:gmatch("[^%.]+") do
        if type(v) ~= "table" then return nil end
        v = v[part]
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

local function gather(ok, ...)
    if not ok then return false end
    local isSecret = _G.issecretvalue
    local out = { n = select("#", ...) }
    for i = 1, out.n do
        local v = select(i, ...)
        if type(isSecret) == "function" and isSecret(v) then return false end
        out[i] = v
    end
    return true, out
end

-- `ok, values` for everything `path(...)` returns, by position, with `values.n` their count.
-- `ok` is false when the function is missing or failed, or any of the values is secret.
local function readAll(path, ...)
    local fn = lookup(path)
    if type(fn) ~= "function" then return false end
    return gather(pcall(fn, ...))
end

local function num(v)
    return type(v) == "number" and v or nil
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

local function push(bytes, value, size)
    value = floor(max(0, min(value or 0, 256 ^ size - 1)))
    for i = size - 1, 0, -1 do
        bytes[#bytes + 1] = floor(value / 256 ^ i) % 256
    end
end

local function bytesOf(text)
    local out = {}
    for i = 1, #text do out[i] = text:byte(i) end
    return out
end

local function textOf(bytes)
    local parts = {}
    for i = 1, #bytes, 200 do
        parts[#parts + 1] = char(unpack(bytes, i, min(i + 199, #bytes)))
    end
    return concat(parts)
end

-- The fast block for a state: `state[group]` is a table of the group's fields, or nil when
-- the group is unknown.
local function packFast(state)
    local known, body = 0, {}
    for i, group in ipairs(GROUPS) do
        local values = state[group[1]]
        if values then known = known + 2 ^ (16 - i) end
        for f = 2, #group do
            push(body, values and values[group[f][1]] or 0, group[f][2])
        end
    end
    local out = {}
    push(out, known, 2)
    for i = 1, #body do out[#out + 1] = body[i] end
    return out
end

-- Bytes to squares (section 3): `bits` a square, most significant first, the last filled with 0.
local function squaresOf(bytes, bits)
    local out, acc, have = {}, 0, 0
    for i = 1, #bytes do
        acc, have = acc * 256 + bytes[i], have + 8
        while have >= bits do
            local unit = 2 ^ (have - bits)
            local s = floor(acc / unit)
            out[#out + 1] = s
            acc, have = acc - s * unit, have - bits
        end
    end
    if have > 0 then out[#out + 1] = acc * 2 ^ (bits - have) end
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
local function nameHash(name)
    local s1, s2 = check(bytesOf(name))
    return s1 * 256 + s2
end

-- The cast group, and whether the player casts or channels. The second value is nil when
-- the client does not say (then the state group is unknown too).
local function castNow()
    local ok, c = readAll("UnitCastingInfo", "player")
    if not ok then return nil, nil end
    local spell = c[9]
    if c[1] == nil then
        ok, c = readAll("UnitChannelInfo", "player")
        if not ok then return nil, nil end
        if c[1] == nil then return nil, false end
        spell = c[8]
    end
    if not num(spell) or not num(c[5]) then return nil, true end
    local tenths = ceil((c[5] / 1000 - clock()) * 10)
    return { spell = spell, tenths = tenths > 254 and 255 or max(0, tenths) }, true
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

-- A unit's threat on the target as a whole per cent, 0 when the unit is not on the target's
-- list (the client then returns nothing), nil when the client's answer cannot be used.
local function threatOf(who)
    local ok, t = readAll("UnitDetailedThreatSituation", who, "target")
    if not ok then return nil end
    if t.n == 0 or t[3] == nil then return 0 end
    return num(t[3]) and min(100, floor(t[3] + 0.5)) or nil
end

-- A group is in the state only when every one of its fields was read: a missing function, a
-- failed call or a secret value leaves the group unknown, never a zero that looks known.
local function sample()
    local state = {}
    state.clock = { clock = _G.time() % 65536 }
    local healthMax = num(get("UnitHealthMax", "player"))
    state.health = healthMax and { healthMax = healthMax }
    local powerMax, powerType = num(get("UnitPowerMax", "player")), num(get("UnitPowerType", "player"))
    state.power = powerMax and powerType and { powerMax = powerMax, powerType = powerType }
    local level, xp, xpMax = num(get("UnitLevel", "player")), num(get("UnitXP", "player")), num(get("UnitXPMax", "player"))
    state.level = level and xp and xpMax and { level = level, xp = xp, xpMax = xpMax }

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
    state.state = flags and { flags = flags + (casting and 4 or 0) + (hasTarget and 2 or 0) + (hasPet and 1 or 0) + (lootOpen and 256 or 0) }

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
            state.target = { level = tl < 0 and 255 or tl, flags = tf, nameHash = nameHash(name) }
        end
        local mine, pets = threatOf("player"), nil
        if okPet then
            if hasPet then pets = threatOf("pet") else pets = 0 end   -- no pet: 0; a pet whose threat cannot be read: unknown
        end
        state.threat = mine and pets and { player = mine, pet = pets }
    end
    local petMax = okPet and hasPet and num(get("UnitHealthMax", "pet"))
    state.pet = petMax and { healthMax = petMax }

    local map = num(get("C_Map.GetBestMapForUnit", "player"))
    local pos = map and get("C_Map.GetPlayerMapPosition", map, "player")
    local facing = num(get("GetPlayerFacing"))
    if type(pos) == "table" and type(pos.GetXY) == "function" and facing then
        local ok, xy = gather(pcall(pos.GetXY, pos))
        if ok and num(xy[1]) and num(xy[2]) then
            state.position = { map = map, x = floor(xy[1] * 65535 + 0.5), y = floor(xy[2] * 65535 + 0.5),
                facing = floor(facing / (2 * math.pi) * 256 + 0.5) % 256 }
        end
    end

    local money, free = num(get("GetMoney")), 0
    for bag = 0, 4 do
        local slots = num(get("C_Container.GetContainerNumFreeSlots", bag))
        free = free and slots and free + slots
    end
    state.purse = money and free and { money = money, bagFree = free }

    -- the main hand: an empty slot is item 0; no enchant is 0 seconds
    local okItem, item = read("GetInventoryItemID", "player", 16)
    local okEnchant, enchant = readAll("GetWeaponEnchantInfo")
    if okItem and (item == nil or num(item)) and okEnchant and (not enchant[1] or num(enchant[2])) then
        state.hand = { item = item or 0, enchant = enchant[1] and max(1, ceil(enchant[2] / 1000)) or 0 }
    end
    state.loot = loot
    state.uiError = uiError.error and uiError   -- unknown while the last error's number could not be read
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

local function deflate(text)
    local EU = _G.C_EncodingUtil
    if type(EU) ~= "table" or type(EU.CompressString) ~= "function" then return nil end
    local method = lookup("Enum.CompressionMethod.Deflate") or 0
    local ok, z = pcall(EU.CompressString, text, method)
    z = ok and plain(z)
    if type(z) == "string" and #z > 0 and #z < #text then return z end
    return nil
end

-- The object bytes for a text (nil: the addon cannot read the object now).
local function objectBytes(text)
    local bytes
    if text == nil then
        bytes = { 255 }
    else
        local z = deflate(text)
        bytes = bytesOf(z or text)
        table.insert(bytes, 1, z and 1 or 0)
    end
    local s1, s2 = check(bytes)
    bytes[#bytes + 1], bytes[#bytes + 2] = s1, s2
    return bytes
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
    if o.dirty and (not o.changedAt or now - o.changedAt >= o.every) then
        o.dirty = false
        -- `key`, when the text function gives one, is what counts as a change in place of
        -- the bytes: the text without what moves too often to send for (the bags' ammunition).
        local ok, text, key = pcall(o.text, o)
        if not ok then text, key = nil, nil end
        local bytes = objectBytes(text)
        local same
        if key ~= nil then same = key == o.key else same = sameBytes(bytes, o.obj) end
        if not same then
            o.version = ((o.version or math.random(0, 65535)) + 1) % 65536
            o.obj, o.changedAt, o.rounds = bytes, now, o.want
        end
        o.key = key
    end
    return o.obj and o
end

-- The next object in the order of the ids, after `id`; nil when none is current.
local function nextObject(id, now)
    for step = 1, 6 do
        local try = (id + step - 1) % 6 + 1
        local o = refresh(try, now)
        if o then
            local chunks = chunksOf(o.obj)
            if chunks then return { id = try, version = o.version, chunks = chunks, index = 1 } end
        end
    end
    return nil
end

-- Moves the carousel on when the chunk on the row has been up for `dwell`. Returns true when
-- the row must be drawn again. A chunk's time starts when it is drawn (drawFrame sets
-- `till`), so no chunk is passed over before it was on the row.
local function advance(now)
    if sending and (not sending.till or now < sending.till) then return false end
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
    sending = nextObject(sending and sending.id or 6, now)
    return sending ~= nil or was ~= nil
end

local function mark(id)
    if objects[id] then objects[id].dirty = true end
end

-- What each object says (section 6). A function returns the text, or nil when the addon
-- cannot read the object now.
local function targetText()
    local ok, exists = read("UnitExists", "target")
    if not ok then return nil end
    if not exists then return "null" end
    local name, class, level = get("UnitName", "target"), get("UnitClassification", "target"), num(get("UnitLevel", "target"))
    local okKind, kind = read("UnitCreatureType", "target")
    if type(name) ~= "string" or type(class) ~= "string" or not level or not okKind then return nil end
    return ('{"name": %s, "type": %s, "class": %s, "level": %s}'):format(jsonString(name),
        type(kind) == "string" and jsonString(kind) or "null", jsonString(class), jsonNumber(level))
end

local function placeText()
    local map = num(get("C_Map.GetBestMapForUnit", "player"))
    local zone = get("GetRealZoneText")
    local okSub, sub = read("GetSubZoneText")
    if not map or type(zone) ~= "string" or not okSub or (sub ~= nil and type(sub) ~= "string") then return nil end
    return ('{"map": %s, "zone": %s, "sub": %s}'):format(jsonNumber(map), jsonString(zone), jsonString(sub or ""))
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
-- ammunition's count in the object is that of the last other change of the bags.
local function bagsText()
    local count, free = {}, 0
    local ammo = num(get("GetInventoryItemID", "player", 0))   -- slot 0: ammunition; nil with none
    for bag = 0, 4 do
        local okFree, freeHere = read("C_Container.GetContainerNumFreeSlots", bag)
        local okSlots, slots = read("C_Container.GetContainerNumSlots", bag)
        if not okFree or not okSlots or not num(freeHere) or not num(slots) then return nil end
        free = free + freeHere
        for slot = 1, slots do
            local okInfo, info = read("C_Container.GetContainerItemInfo", bag, slot)
            if not okInfo then return nil end
            if info ~= nil then                -- nil is an empty slot
                local okId, id = field(info, "itemID")
                local okStack, stack = field(info, "stackCount")
                if not okId or not okStack or not num(id) or not num(stack) then return nil end
                count[id] = (count[id] or 0) + stack
            end
        end
    end
    local ids = {}
    for id in pairs(count) do ids[#ids + 1] = id end
    table.sort(ids)
    local keys = {}
    for i, id in ipairs(ids) do
        ids[i] = ("[%s, %s]"):format(jsonNumber(id), jsonNumber(count[id]))
        keys[i] = id == ammo and ("[%s]"):format(jsonNumber(id)) or ids[i]
    end
    return ('{"free": %s, "items": [%s]}'):format(jsonNumber(free), concat(ids, ", ")),
        ('{"free": %s, "items": [%s]}'):format(jsonNumber(free), concat(keys, ", "))
end

-- The quest log, read from the client now. The states are those of docs/SCHEMA.md: failed
-- when the client says so; ready when it says complete, or every objective is finished;
-- in_progress when an objective has moved; accepted when none has; unknown when the client
-- gives neither a flag nor objectives. Finished objectives decide, not summed counts.
-- `ok, value` for a yes-or-no the client may not have a function for. A missing function is
-- the client saying nothing (ok, nil); a failed call or a secret answer is not ok.
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

local function cell(i)
    local t = cells[i]
    if not t then
        t = row:CreateTexture(nil, "OVERLAY")
        cells[i] = t
        local side = db.size * unit
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

local function paintLevels()
    for v, source in ipairs(LEVEL_SOURCES) do
        local who, fn, a, b = source[1], _G[source[2]], source[3], source[4]
        local live = curves and type(fn) == "function" and get("UnitExists", who)
        for part = 1, 3 do
            local i = LEVELS_AT + (v - 1) * 3 + part
            local t = cell(i)
            if not (live and pcall(colourFromClient, t, fn, who, a, b, curves[part])) then t:SetColorTexture(0, 0, 0, 1) end
            shownColour[i] = nil
            t:Show()
        end
    end
end

local function frameStart()
    return depth == 4 and PALETTE_AT + 64 or PALETTE_AT
end

-- Sizes in physical pixels (measured exact on 12 Nov 2026), and what fits the game's width.
local function layout()
    local width, height = _G.GetPhysicalScreenSize()
    unit = 768 / height / UIParent:GetEffectiveScale()
    local side = db.size * unit
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", UIParent, "TOPLEFT", db.x * unit, -db.y * unit)
    row:SetSize(1, 1)
    for i, t in pairs(cells) do
        t:SetSize(side, side)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * side, 0)
    end
    capacity = max(0, floor((width - db.x) / db.size) - frameStart())
    local bits = depth == 4 and 6 or 3
    chunkLen = max(0, min(MAX_CHUNK, floor(capacity * bits / 8) - (7 + 58 + 6 + 2)))
    sending = nil
end

-- Everything on the row but the level squares and the frame: finder, depth, session, palette.
local function paintFixed()
    for i = 1, #FINDER do paintDigit(i, FINDER[i]) end
    paintDigit(DEPTH_AT + 1, depth)
    local digits = squaresOf({ 0, floor(session / 256), session % 256 }, 3)
    for k = 1, 6 do paintDigit(SESSION_AT + k, digits[k + 2]) end
    if depth == 4 then
        for i = 0, 63 do paint(PALETTE_AT + 1 + i, "p" .. i, paletteColour(i)) end
    end
end

local lastBody, lastSquares = nil, 0

-- Builds the frame for the state and the chunk now on the row, and recolours what changed.
local function drawFrame(now)
    if sending and not sending.till then sending.till = now + db.dwell / 100 end  -- the chunk is on the row from now
    local fast = packFast(sample())
    local body = { VERSION }
    push(body, session, 2)
    body[#body + 1] = db.dwell
    push(body, 0, 2)                                  -- seq, set below
    body[#body + 1] = #fast
    for i = 1, #fast do body[#body + 1] = fast[i] end
    if sending then
        local part = sending.chunks[sending.index]
        body[#body + 1] = sending.id
        push(body, sending.version, 2)
        body[#body + 1] = sending.index - 1
        body[#body + 1] = #sending.chunks
        body[#body + 1] = #part
        for i = 1, #part do body[#body + 1] = part[i] end
    else
        for _ = 1, 6 do body[#body + 1] = 0 end
    end
    local key = textOf(body)
    if key == lastBody then return end                -- nothing changed: the same seq stays up
    lastBody = key
    seq = (seq + 1) % 65536
    body[5], body[6] = floor(seq / 256), seq % 256
    local s1, s2 = check(body)
    body[#body + 1], body[#body + 2] = s1, s2
    local squares = squaresOf(body, depth == 4 and 6 or 3)
    local first = frameStart()
    if #squares > capacity then return end            -- the game is too narrow for this frame
    for i = 1, #squares do
        if depth == 4 then paint(first + i, "p" .. squares[i], paletteColour(squares[i]))
        else paintDigit(first + i, squares[i]) end
    end
    for i = #squares + 1, lastSquares do paint(first + i, 0, 0, 0, 0) end  -- black after the frame's end
    lastSquares = #squares
end

-- Starts the row afresh: after a change of size, place, depth or UI scale.
local function repaint()
    for _, t in pairs(cells) do t:Hide() end
    shownColour, lastBody, lastSquares = {}, nil, 0
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

local function look()
    if not looking or depth ~= 4 or db.depth ~= "auto" then return end
    local inbox = ns.loadNextSlot and ns.loadNextSlot()
    if inbox == nil then
        looking = false                                -- the session's slots are used up
        return
    end
    local ask = type(inbox) == "table" and inbox.strip
    if type(ask) == "table" and ask.session == session and ask.depth == 2 then
        looking = false
        setDepth(2, "the strip falls back to 3 bits a square for this session: the reader could not read 6.")
    end
end

----------------------------------------------------------------------
-- Running
----------------------------------------------------------------------
local sinceFast, sinceLevels, sinceSlow = 0, 0, 0

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
        for id = 2, 6 do mark(id) end
    end
    if advance(now) or sinceFast >= FAST_EVERY or lastBody == nil then
        sinceFast = 0
        drawFrame(now)
    end
    local due = LOOKS[lookIndex] or (LOOKS[#LOOKS] + 600 * (lookIndex - #LOOKS))
    if now - loadedAt >= due then
        lookIndex = lookIndex + 1
        look()
    end
end

local EVENTS = {
    PLAYER_TARGET_CHANGED = function() mark(2) end,
    ZONE_CHANGED = function() mark(3) end,
    ZONE_CHANGED_NEW_AREA = function() mark(3) end,
    ZONE_CHANGED_INDOORS = function() mark(3) end,
    BAG_UPDATE_DELAYED = function() mark(4) end,
    BAG_UPDATE = function() mark(4) end,
    QUEST_LOG_UPDATE = function() mark(5) end,
    SKILL_LINES_CHANGED = function() mark(6) end,
    CHAT_MSG_SKILL = function() mark(6) end,
    LOOT_OPENED = function() lootOpen = true end,
    LOOT_CLOSED = function() lootOpen = false end,
    UI_SCALE_CHANGED = function() if row then repaint() end end,
    DISPLAY_SIZE_CHANGED = function() if row then repaint() end end,
    UI_ERROR_MESSAGE = function(kind)
        -- the count goes on; a number that cannot be read leaves the group unknown until the next error
        uiError = { error = num(plain(kind)), counter = (uiError.counter + 1) % 256 }
    end,
    CHAT_MSG_LOOT = function(text, ...)
        -- Whose loot: by GUID (argument 12 of the event), never by name. The name in the
        -- message can have a family name that UnitName does not have (seen 13 Nov 2026).
        local who, me = plain((select(11, ...))), get("UnitGUID", "player")
        text = plain(text)
        if type(text) ~= "string" or type(who) ~= "string" or who ~= me then return end
        local item = tonumber(text:match("|Hitem:(%d+)"))
        if not item then return end
        loot = { counter = (loot.counter + 1) % 256, item = item, quantity = tonumber(text:match("|h|rx(%d+)")) or 1 }
        mark(4)
    end,
}

local function start()
    if type(_G.HelloLinkDB) ~= "table" then _G.HelloLinkDB = {} end
    db = _G.HelloLinkDB
    for k, v in pairs({ on = true, x = 0, y = 0, size = 2, depth = "auto", dwell = 10 }) do
        if db[k] == nil then db[k] = v end
    end
    -- the session number: a counter kept across UI loads (section 4)
    db.session = (num(db.session) or math.random(1, 65535)) % 65535 + 1
    session, depth, loadedAt = db.session, db.depth == 2 and 2 or 4, clock()
    looking = db.depth == "auto"
    curves = makeCurves()
    objects = {
        [1] = { text = function(o) return o.value end, every = 1 },   -- the question; nothing until one is typed
        [2] = { text = targetText, every = 1, dirty = true }, [3] = { text = placeText, every = 1, dirty = true },
        [4] = { text = bagsText, every = 1, dirty = true }, [5] = { text = questsText, every = 2, dirty = true },
        [6] = { text = skillsText, every = 1, dirty = true },
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

function ns.StripCommand(rest)
    if not db then return ns.say("the strip is not loaded yet.") end
    local word, a, b = rest:match("^(%S*)%s*(%S*)%s*(%S*)")
    if word == "on" or word == "off" then
        db.on = word == "on"
        if db.on then row:Show(); repaint() else row:Hide() end
    elseif word == "at" and tonumber(a) and tonumber(b) then
        db.x, db.y = max(0, floor(tonumber(a))), max(0, floor(tonumber(b)))
        repaint()
    elseif word == "size" and (a == "2" or a == "3" or a == "4") then
        db.size = tonumber(a)
        repaint()
    elseif word == "depth" and (a == "auto" or a == "2" or a == "4") then
        db.depth = a == "auto" and "auto" or tonumber(a)
        looking = a == "auto"
        setDepth(a == "2" and 2 or 4)
    elseif word == "dwell" and tonumber(a) and tonumber(a) >= 5 and tonumber(a) <= 100 then
        db.dwell = floor(tonumber(a))
    else
        return ns.say("use /hlink strip on | off | at <x> <y> | size <2|3|4> | depth <auto|2|4> | dwell <5-100>")
    end
    ns.say(("strip %s at (%d, %d), %d pixels a square, depth %s (now %d), a chunk stays %.2f s, session %d."):format(
        db.on and "on" or "off", db.x, db.y, db.size, tostring(db.depth), depth, db.dwell / 100, session))
end
