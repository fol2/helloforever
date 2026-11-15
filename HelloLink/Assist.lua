-- HelloLink / Assist.lua
-- The way in for the assistant (docs/specs/115.md, section 6): what HelloLink takes from the
-- slot file's `assist` part at a look, and the plain global it leaves for HelloForever,
-- HelloLinkAssist. HelloForever reads it with rawget; neither addon calls the other's code.
--
-- The whole part is checked once, strictly (LESSONS.md, "A gate that reads a config file
-- validates the whole file once, strictly"). A text from outside is data: every `|` in it is
-- doubled, so no colour, texture or link code is drawn (seen 15 Nov 2026, plan/05 section 9).
local _, ns = ...
ns = ns or {}

local floor, type, pairs = math.floor, type, pairs

local MAX_CARDS, MAX_TEXT, MAX_DETAIL, MAX_LINES = 8, 120, 600, 6
local BEFORE, AFTER = 180, 5 -- seconds: how old, and how far in the future, a set's t may be

local state = { strip = true, cards = {}, taken = 0, refused = 0 }
local total -- the slots there are, learned from the first slot file that says it
_G.HelloLinkAssist = state
ns.AssistState = state -- for Strip.lua: the answer's `re` and the slots left

local function whole(v, low, high)
    return type(v) == "number" and v == v and v >= low and v <= high and v == floor(v)
end

-- True for a string that is UTF-8 (no byte left over, no overlong form, no surrogate).
local function utf8ok(s)
    local i, len = 1, #s
    while i <= len do
        local c = s:byte(i)
        local n = c < 0x80 and 0 or (c >= 0xC2 and c <= 0xDF) and 1 or (c >= 0xE0 and c <= 0xEF) and 2
            or (c >= 0xF0 and c <= 0xF4) and 3 or nil
        if not n then return false end
        for j = 1, n do
            local d = s:byte(i + j)
            if not d or d < 0x80 or d > 0xBF then return false end
        end
        if n == 2 then
            local d = s:byte(i + 1)
            if (c == 0xE0 and d < 0xA0) or (c == 0xED and d > 0x9F) then return false end
        elseif n == 3 then
            local d = s:byte(i + 1)
            if (c == 0xF0 and d < 0x90) or (c == 0xF4 and d > 0x8F) then return false end
        end
        i = i + n + 1
    end
    return true
end

-- A text as section 3 has it: UTF-8, not empty, at most `limit` bytes and `lines` lines.
local function text(v, limit, lines)
    if type(v) ~= "string" or v == "" or #v > limit or not utf8ok(v) then return nil end
    local _, breaks = v:gsub("\n", "")
    if breaks + 1 > lines then return nil end
    return (v:gsub("|", "||"))
end

-- The card as the addon keeps it, or nil when a field is not as section 3 says.
local function card(c, t)
    if type(c) ~= "table" then return nil end
    local id, kind, prio, src, at, ttl = c.id, c.kind, c.prio, c.src, c.at, c.ttl
    if type(id) ~= "string" or #id > 24 or not id:match("^[%w%-]+$") then return nil end
    if kind ~= "state" and kind ~= "event" then return nil end
    if not whole(prio, 1, 3) or (src ~= "companion" and src ~= "ai") then return nil end
    if not whole(at, 0, t) or not whole(ttl, 10, 3600) then return nil end
    local body, basis = text(c.text, MAX_TEXT, 1), text(c.basis, MAX_TEXT, 1)
    if not body or not basis then return nil end
    local detail
    if c.detail ~= nil then
        detail = text(c.detail, MAX_DETAIL, MAX_LINES)
        if not detail then return nil end
    end
    return { id = id, kind = kind, prio = prio, src = src, at = at, ttl = ttl, text = body, basis = basis, detail = detail }
end

-- The list of at most 8 tables, keyed 1 to n and nothing else; nil when it is not one.
local function list(v)
    if type(v) ~= "table" then return nil end
    local n = 0
    for k in pairs(v) do
        if not whole(k, 1, MAX_CARDS) then return nil end
        n = n + 1
    end
    for i = 1, n do
        if v[i] == nil then return nil end
    end
    return v, n
end

local function left()
    local used = ns.SlotsUsed and ns.SlotsUsed()
    if not total or not used then return nil end
    return total - used < 0 and 0 or total - used
end

-- The slots left now (/hlink uses them too), or nil before a slot file said how many there are.
function ns.AssistLeft()
    return left()
end

-- At a look: `inbox` is the slot file's table, `session` this UI session, `now` the client's
-- time(). A set is taken only for this session and when its companion wrote it a moment ago;
-- a set that is not taken removes the cards from outside. Returns HelloLinkAssist.
function ns.AssistTake(inbox, session, now)
    if type(inbox) == "table" and whole(inbox.slots, 1, 999) then total = inbox.slots end
    state.left = left()
    local a = type(inbox) == "table" and inbox.assist or nil
    local cards, n
    if type(a) == "table" then cards, n = list(a.cards) end
    local ok = cards and whole(a.session, 1, 65535) and whole(a.seq, 0, 2 ^ 53) and whole(a.t, 0, 2 ^ 53)
        and (a.re == nil or whole(a.re, 0, 2 ^ 53))
    if not ok or a.session ~= session or not whole(now, 0, 2 ^ 53) or a.t < now - BEFORE or a.t > now + AFTER then
        state.cards, state.taken, state.refused = {}, 0, 0
        return state
    end
    local taken, refused = {}, 0
    for i = 1, n do
        local c = card(cards[i], a.t)
        if c then taken[#taken + 1] = c else refused = refused + 1 end
    end
    state.session, state.seq, state.t, state.re = session, a.seq, a.t, a.re
    state.cards, state.taken, state.refused = taken, #taken, refused
    return state
end

-- The strip on or off: with it off there is no way in, so no card from outside.
function ns.AssistStrip(on)
    state.strip = on and true or false
    if not on then state.cards, state.taken, state.refused = {}, 0, 0 end
end

-- The session's slots are used up.
function ns.AssistNoSlot()
    state.left = 0
end

